// aiohttp.webresp.c3

module ext::aiohttp::web;

import ext::aiohttp;
import ext::asyncio;
import ext::serializer::http;
import ext::aiofiles;
import ext::aiofiles::os;
import ext::mem;
import ext::debug;
import ext::thread::fiber;


//  Response 

struct Response {
    int      status;
    String   reason;
    Headers* headers;
    char*    body;
    usz      body_len;
    String   content_type;
    String   charset;
}

fn Response* response_new(
    int    status = 200,
    String text = "",
    char*  body = null,
    usz    body_len = 0,
    String content_type = "text/plain",
    String charset = "utf-8",
)
{
    Response* r = localmem.alloc(Response);
    r.status = status;
    r.reason = aiohttp::http_reason(status);
    
    r.headers = aiohttp::headers_new();
    if (g_server_header != "") {
        r.headers.set("Server", g_server_header);
    }
    
    r.content_type = content_type;
    r.charset = charset;

    if (text.len > 0) {
        r.body = (char*)text.ptr;
        r.body_len = text.len;
    } else {
        r.body = body;
        r.body_len = body_len;
    }
    return r;
}

fn Response* json_response(String json_str, int status = 200)
{
    return response_new(
        status,
        "", // empty text
        (char*)json_str.ptr, // body
        json_str.len, // body len
        "application/json",
        "utf-8",
    );
}

fn void Response.free(&self)
{
    if (self.headers != null) { 
        self.headers.free(); 
        self.headers = null;
    }
    localmem.free(self);
}

fn void Response.set_header(&self, String name, String value)
{
    self.headers.set(name, value);
}

fn void Response.set_cookie(&self,
    String name,
    String value,
    String path = "",
    String domain = "",
    bool secure = true,
    bool httponly = false,
    String samesite = "Lax", // CSRF protection ("Strict", "Lax", "None")
    uint max_age = 3600, // seconds,
    String expires = "",
)
{
    // build "Set-Cookie: name=value; Path=/; ..."
    char[512] buf; 
    OBuf b = { &buf[0], 512, 0 };
    
    b.put(name); b.putc('='); b.put(value);
    if (path.len > 0) { b.put("; Path=");  b.put(path);   }
    if (domain.len > 0) { b.put("; Domain="); b.put(domain); }
    if (secure) b.put("; Secure");
    if (httponly) b.put("; HttpOnly");
    if (samesite.len > 0) { b.put("; SameSite="); b.put(samesite); }
    if (expires.len > 0) { b.put("; Expires="); b.put(expires); }
    if (max_age > 0) {
        b.put("; MaxAge=");
        b.putn(max_age);
    }

warn("Set-Cookie: %s", b.str());
    self.headers.add("Set-Cookie", b.str().copy(localmem));
}

fn void Response.del_cookie(&self, String name)
{
    for (usz i = 0; i < self.headers.len(); i++) {
        KeyVal x = self.headers.entries[i];
        if (x.name != "Set-Cookie") continue;
        if (! x.value.starts_with(name)) continue;
        self.headers.entries.remove_at(i);
        break;
    }
    
    // set cookie with expired date to delete it
    char[256] buf;
    OBuf b = { &buf[0], 256, 0 };
    
    b.put(name); b.put("=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT");

    self.headers.add("Set-Cookie", b.str().copy(localmem));
}

        
//  HTTP error shortcuts 

fn Response* http_bad_request          (String text = "Bad Request") => response_new(400, text);
fn Response* http_unauthorized         (String text = "Unauthorized") => response_new(401, text);
fn Response* http_forbidden            (String text = "Forbidden") => response_new(403, text);
fn Response* http_not_found            (String text = "Not Found") => response_new(404, text);
fn Response* http_method_not_allowed   (String text = "Method Not Allowed") => response_new(405, text);
fn Response* http_internal_server_error(String text = "Internal Server Error") => response_new(500, text);

fn Response* http_redirect(String location, int status = 302)
{
    Response* r = response_new(status);
    r.set_header("Location", location);
    return r;
}

fn Response* http_moved_permanently(String location)
 => http_redirect(location, 301);

//  response serializer 

fn void? write_response(Stream* s, Response* resp) @private
{
    char[RESP_SCRATCH_SZ] buf;
    OBuf b = { &buf[0], RESP_SCRATCH_SZ, 0 };

    b.put("HTTP/1.1 "); b.putn(resp.status); b.putc(' '); b.put(resp.reason); b.crlf();

    // Content-Type
    if (!resp.headers.has("content-type") && resp.content_type.len > 0) {
        b.put("Content-Type: "); 
        b.put(resp.content_type);
        if (resp.charset.len > 0) { b.put("; charset="); b.put(resp.charset); }
        b.crlf();
    }

    // Content-Length
    if (!resp.headers.has("content-length")) {
        b.put("Content-Length: "); b.putn((int)resp.body_len); b.crlf();
    }

    // Connection
    if (!resp.headers.has("connection")) { b.put("Connection: keep-alive"); b.crlf(); }

    // custom headers
    for (usz i = 0; i < resp.headers.len(); i++) {
        b.put(resp.headers.entries[i].name);
        b.put(": ");
        b.put(resp.headers.entries[i].value);
        b.crlf();
    }
    b.crlf();
    s.write(b.str())!;

    if (resp.body_len > 0 && resp.body != null) {
        s.write(resp.body[0:resp.body_len ])!;
    }
}

//  StreamResponse 

/*
struct Response {
    int      status;
    String   reason;
    Headers* headers;
    char*    body;
    usz      body_len;
    String   content_type;
    String   charset;
}
*/

struct StreamResponse {
    inline Response resp;
    // int      status;
    // String   reason;
    // Headers* headers;
    bool     prepared;
    bool     eof_sent;
    Stream*  stream;
}

fn StreamResponse* stream_response_new(int status = 200)
{
    StreamResponse* r = localmem.alloc(StreamResponse);
    *r = {
        .status = status,
        .reason = aiohttp::http_reason(status),
        .headers = aiohttp::headers_new(),
        .prepared = false,
        .eof_sent = false,
        .stream = null,
    };
    
    return r;
}

fn void StreamResponse.set_header(&self, String name, String value)
{
    self.headers.set(name, value);
}


fn void? StreamResponse.prepare(&self, Request* req)
{
    if (self.prepared) return;
    self.stream = req.stream;
    self.prepared = true;

    char[RESP_SCRATCH_SZ] buf;    
    OBuf b = { &buf[0], RESP_SCRATCH_SZ, 0 };
    
    b.put("HTTP/1.1 "); b.putn(self.status); b.putc(' '); b.put(self.reason);
    b.crlf();
    b.put("Transfer-Encoding: chunked\r\n");
    if (!self.headers.has("connection")) b.put("Connection: keep-alive\r\n");
    for (usz i = 0; i < self.headers.len(); i++) {
        b.put(self.headers.entries[i].name);
        b.put(": ");
        b.put(self.headers.entries[i].value);
        b.crlf();
    }
    b.crlf();
    self.stream.write(b.str())!;
}

fn void? StreamResponse.write(&self, char* data, usz len) @maydiscard
{
    if (!self.prepared || self.stream == null) return INTERNAL_SERVER_ERROR~;
    usz frame_sz = aiohttp::chunk_encoded_size(len);
    char* frame = localmem.malloc(frame_sz);
    defer localmem.free(frame);
    usz written = aiohttp::chunk_encode(frame, data, len);
    self.stream.write(frame[0:written])!;
}

fn void? StreamResponse.write_eof(&self) @maydiscard
{
    if (!self.prepared || self.eof_sent || self.stream == null) return;
    self.eof_sent = true;
    char[5] tail;
    usz n = aiohttp::chunk_encode_final(&tail[0]);
    self.stream.write(tail[0:n])!;
}

fn void StreamResponse.free(&self)
{
    if (!self.eof_sent) {
        (void)self.write_eof();
    }
    self.headers.free();
    localmem.free(self);
}

//  FileResponse 

struct FileResponse {
    inline Response resp;
    // int      status;
    // Headers* headers;
    String   filepath;
    // String   content_type;
}

fn FileResponse* file_response_new(
    String filepath,
    int status = 200,
    String content_type = "",
)
{
    FileResponse* r = localmem.alloc(FileResponse);
    *r = {
        .status = status,
        .headers = aiohttp::headers_new(),
        .filepath = filepath,
        .content_type = content_type,
    };
    return r;
}

fn void FileResponse.free(&self)
{
    self.headers.free();
    localmem.free(self);
}

// Send FileResponse to stream — called by the request dispatcher.
fn void? file_response_send(FileResponse* fr, Stream* s) @private
{
    // delegate to static file handler
    StaticConfig cfg = {
        .url_prefix = "",
        .fs_root = "",
        .show_index = false,
        .chunk_size = 65536,
    };
    // open and stream the file directly
    AioFile? afile = aiofiles::open(fr.filepath, "rb");
    if (catch err = afile) {
        // send 404
        Response* err_r = http_not_found();
        (void)write_response(s, err_r);
        err_r.free();
        return;
    }

    usz file_size = 0;
    Stat? st = os::stat(fr.filepath);
    if (try st) {
        file_size = (usz)st.st_size;
    }
    
    // detect MIME if not set
    String mime = fr.content_type.len > 0 ? fr.content_type : static_mime(fr.filepath);

    // write header
    char[RESP_SCRATCH_SZ] buf; 
    OBuf b = { &buf[0], RESP_SCRATCH_SZ, 0 };
    
    b.put("HTTP/1.1 200 OK\r\nContent-Type: "); b.put(mime);
    b.put("\r\nContent-Length: "); b.putn((int)file_size);
    b.put("\r\nConnection: keep-alive\r\n");
    for (usz i = 0; i < fr.headers.len(); i++) {
        b.put(fr.headers.entries[i].name); b.put(": ");
        b.put(fr.headers.entries[i].value); b.crlf();
    }
    b.crlf();
    s.write(b.str())!;

    // stream file body
    char[65536] chunk;
    while (true) {
        usz? n = afile.read_unbuffered(&chunk);
        if (catch err = n) break;
        if (n == 0) break;
        s.write(chunk[0:n])!;
    }
    afile.close();
}

//  WebSocketResponse 

struct WebSocketResponse {
    bool   closed;
    String protocol;
    int    compress;
    Stream*    stream;
    WsDecoder  decoder;
    ulong      heartbeat_us;
}

fn WebSocketResponse* ws_response_new(
    ulong   heartbeat_us = 0,
    int     compress = 0,
    String* protocols = null,
    usz     protocols_count = 0,
)
{
    WebSocketResponse* ws = (WebSocketResponse*)localmem.malloc($sizeof(WebSocketResponse));
    ws.closed = false;
    ws.protocol = "";
    ws.compress = compress;
    ws.stream = null;
    ws.heartbeat_us = heartbeat_us;
    ws.decoder.init(true, 0); // server: expects masked frames from client
    return ws;
}

fn void? WebSocketResponse.prepare(&self, Request* req)
{
    // validate Upgrade headers
    String? upgrade = req.headers.get("upgrade");
    if (catch err = upgrade) return BAD_REQUEST~;

    String? wskey = req.headers.get("sec-websocket-key");
    if (catch err = wskey) return BAD_REQUEST~;

    self.stream = req.stream;

    // build 101 response
    char[512] hs_buf;
    usz hs_len = aiohttp::ws_server_handshake_accept(&hs_buf[0], 512, wskey, self.protocol, localmem);
    self.stream.write(hs_buf[0:hs_len])!;
}

fn void? ws_server_send(WebSocketResponse* ws, WsMsgType type, char* data, usz len) @private
{
    if (ws.closed || ws.stream == null) return INTERNAL_SERVER_ERROR~;
    // server sends UNMASKED frames
    char[4] no_mask = { 0, 0, 0, 0 };
    String? frame = aiohttp::ws_frame_encode_alloc(localmem, type, data, len, false, no_mask);
    if (catch err = frame) return INTERNAL_SERVER_ERROR~;
    defer frame.free(localmem);

    ws.stream.write(frame[0:frame.len])!;
}

fn void? WebSocketResponse.send_str  (&self, String data) @maydiscard => ws_server_send(self, WsMsgType.TEXT,   (char*)data.ptr, data.len);
fn void? WebSocketResponse.send_bytes(&self, char* data, usz len) @maydiscard => ws_server_send(self, WsMsgType.BINARY, data, len);
fn void? WebSocketResponse.send_json (&self, String json_str) @maydiscard => ws_server_send(self, WsMsgType.TEXT,   (char*)json_str.ptr, json_str.len);
fn void? WebSocketResponse.ping(&self, char* msg = null, usz len = 0) @maydiscard => ws_server_send(self, WsMsgType.PING, msg, len);
fn void? WebSocketResponse.pong(&self, char* msg = null, usz len = 0) @maydiscard => ws_server_send(self, WsMsgType.PONG, msg, len);

fn WsMessage? WebSocketResponse.receive(&self)
{
    if (self.closed || self.stream == null) return INTERNAL_SERVER_ERROR~;
    char[REQ_READ_BUFSZ] raw;
    while (true) {
        WsFrame frame;
        bool? got = self.decoder.next(&frame);
        if (catch err = got) return INTERNAL_SERVER_ERROR~;
        if (got) {
            if (frame.type == WsMsgType.PING) {
                ws_server_send(self, WsMsgType.PONG, frame.data, frame.data_len)!;
                continue;
            }
            if (frame.type == WsMsgType.CLOSE) {
                self.closed = true;
                // echo CLOSE back
                char[4] no_mask = { 0,0,0,0 };
                char[4] cb;
                usz clen = aiohttp::ws_close_frame(&cb[0], WsCloseCode.NORMAL_CLOSURE, "", false, no_mask);
                self.stream.write(cb[0:clen])!;
                WsMessage msg;
                msg.type=WsMsgType.CLOSE;
                msg.data=null;
                msg.data_len=0;
                msg.extra=frame.close_reason;
                return msg;
            }
            char* buf = localmem.malloc(frame.data_len > 0 ? frame.data_len : 1);
            for (usz i = 0; i < frame.data_len; i++) buf[i] = frame.data[i];
            usz total = frame.data_len;
            while (!frame.fin) {
                WsFrame cont; bool? gc = self.decoder.next(&cont);
                if (catch err = gc) break;
                if (!gc) {
                    usz n = self.stream.read(&raw)!;
                    if (n==0) break;
                    self.decoder.feed(&raw[0], n)!; continue;
                }
                char* nb = localmem.malloc(total + cont.data_len);
                for (usz i=0;i<total;i++) nb[i]=buf[i];
                for (usz i=0;i<cont.data_len;i++) nb[total+i]=cont.data[i];
                localmem.free(buf); buf=nb; total+=cont.data_len; frame.fin=cont.fin;
            }
            WsMessage msg; msg.type=frame.type; msg.data=buf;
            return msg;
        }
        usz n = self.stream.read(&raw)!; 
        if(n==0){self.closed=true; return INTERNAL_SERVER_ERROR~;}
        self.decoder.feed(&raw[0], n)!;
    }
}

fn bool WebSocketResponse.next(&self, WsMessage* out_msg)
{
    if (self.closed) return false;
    WsMessage? msg = self.receive();
    if (catch err = msg) return false;
    if (msg.type == WsMsgType.CLOSE) return false;
    *out_msg = msg;
    return true;
}

fn void? WebSocketResponse.close(&self, WsCloseCode code = WsCloseCode.NORMAL_CLOSURE) @maydiscard
{
    if (self.closed || self.stream == null) return;
    self.closed = true;
    char[4] no_mask = {0,0,0,0};
    char[140] cb;
    usz clen = aiohttp::ws_close_frame(&cb[0], code, "", false, no_mask);
    self.stream.write(cb[0:clen])!;
}

fn void WebSocketResponse.free(&self)
{
    if (!self.closed) self.close();
    localmem.free(self);
}

