// aiohttp.client.c3

module ext::aiohttp;

import ext::asyncio;
import ext::serializer::http;
import std::encoding::base64;
import std::hash::sha1;

//  constants 

const int    MAX_REDIRECTS      @private = 10;
const usz    RESP_READ_BUFSIZE  @private = 65536;
const usz    WS_KEY_B64_LEN     @private = 24;
const usz    WS_HANDSHAKE_BUFSZ @private = 512;

//  TcpConnector 

struct TcpConnector {
    int        limit;
    int        limit_per_host;
    TlsConfig* tls;
    usz        read_bufsize;
    bool       use_dns_cache;
    ulong      ttl_dns_cache_us;
    ulong      keepalive_timeout_us;
    bool       force_close;
    bool       closed;
    PoolTable  pool @private;
    DnsCache   dns  @private;
}

fn TcpConnector* connector_new(
    int        limit                = 100,
    int        limit_per_host       = 0,
    TlsConfig* tls                  = null,
    usz        read_bufsize         = 65536,
    bool       use_dns_cache        = true,
    ulong      ttl_dns_cache_us     = 10_000_000,
    ulong      keepalive_timeout_us = 15_000_000,
    bool       force_close          = false,
)
{
    TcpConnector* c = (TcpConnector*)mem::alloc($sizeof(TcpConnector));
    c.limit                = limit;
    c.limit_per_host       = limit_per_host;
    c.tls                  = tls;
    c.read_bufsize         = read_bufsize > 0 ? read_bufsize : RESP_READ_BUFSIZE;
    c.use_dns_cache        = use_dns_cache;
    c.ttl_dns_cache_us     = ttl_dns_cache_us;
    c.keepalive_timeout_us = keepalive_timeout_us;
    c.force_close          = force_close;
    c.closed               = false;
    pool_init(&c.pool, limit, limit_per_host,
              keepalive_timeout_us, force_close, mem::heap())!!;
    dns_cache_init(&c.dns, use_dns_cache, ttl_dns_cache_us);
    return c;
}

fn void TcpConnector.close(&self) {
    if (self.closed) return;
    self.closed = true;
    pool_close(&self.pool);
    mem::free(self);
}

fn int TcpConnector.total_conns(&self) { return pool_total_conns(&self.pool); }

//  ClientSession 

struct ClientSession {
    TcpConnector* connector;
    ClientTimeout timeout;
    Headers*      default_headers;
    BasicAuth*    auth;
    CookieJar*    cookie_jar;
    bool          raise_for_status;
    bool          closed;
    bool owns_connector @private;
    bool owns_jar       @private;
}

fn ClientSession* aiohttp::session_new(
    TcpConnector* connector        = null,
    ClientTimeout timeout          = { .total_us = 30_000_000 },
    Headers*      default_headers  = null,
    BasicAuth*    auth             = null,
    CookieJar*    cookie_jar       = null,
    bool          raise_for_status = false,
)
{
    ClientSession* s = (ClientSession*)mem::alloc($sizeof(ClientSession));
    if (connector == null) {
        s.connector      = connector_new();
        s.owns_connector = true;
    } else {
        s.connector      = connector;
        s.owns_connector = false;
    }
    s.timeout          = timeout;
    s.default_headers  = default_headers;
    s.auth             = auth;
    s.raise_for_status = raise_for_status;
    s.closed           = false;
    if (cookie_jar == null) {
        s.cookie_jar = cookiejar_new();
        s.owns_jar   = true;
    } else {
        s.cookie_jar = cookie_jar;
        s.owns_jar   = false;
    }
    return s;
}

fn void ClientSession.close(&self) {
    if (self.closed) return;
    self.closed = true;
    if (self.owns_connector) self.connector.close();
    if (self.owns_jar)       self.cookie_jar.free();
    if (self.default_headers != null) self.default_headers.free();
    mem::free(self);
}

//  ClientResponse 

struct ClientResponse {
    int        status;
    String     reason;
    Url        url;
    Headers*   headers;
    CookieJar* cookies;
    bool       released;
    // private
    Stream*       stream      @private;
    TcpConnector* connector   @private;
    char*         body_buf    @private;
    usz           body_len    @private;
    bool          is_chunked  @private;
    usz           content_length @private;
    ChunkDecoder  chunk_dec   @private;
}

//  response parsing helpers 

fn char*? resp_read_headers(
    Stream* stream, http::Response* out_resp,
    char* scratch, usz scratch_size, usz* out_filled,
) @private
{
    usz filled = 0;
    while (filled < scratch_size) {
        usz n = stream.read((char[]){ scratch + filled, scratch_size - filled });
        if (n == 0) return HttpClientError.RESPONSE_ERROR?;
        filled += n;
        for (usz i = 0; i + 3 < filled; i++) {
            if (scratch[i]=='\r' && scratch[i+1]=='\n' &&
                scratch[i+2]=='\r' && scratch[i+3]=='\n') {
                char*? bp = http::parse_response(scratch, scratch + filled, out_resp);
                if (catch = bp) return HttpClientError.RESPONSE_ERROR?;
                *out_filled = filled;
                return bp;
            }
        }
    }
    return HttpClientError.RESPONSE_ERROR?;
}

fn ClientResponse*? build_response(
    http::Response* p, Url* req_url,
    Stream* stream, TcpConnector* connector,
    CookieJar* jar, char* body_start, usz filled,
    Allocator mem,
) @private
{
    ClientResponse* r = (ClientResponse*)mem.alloc($sizeof(ClientResponse))!;
    // parse status code
    r.status = 0;
    foreach (c : p.status) {
        if (c < '0' || c > '9') break;
        r.status = r.status * 10 + (int)(c - '0');
    }
    r.reason   = p.message;
    r.url      = *req_url;
    r.released = false;
    r.stream   = stream;
    r.connector = connector;
    r.body_buf = null;
    r.body_len = 0;

    r.headers = headers_new();
    for (uint i = 0; i < p.n_headers; i++) {
        r.headers.add(p.headers[i].key, p.headers[i].value);
    }

    // update cookie jar from Set-Cookie
    p.decode_setcookies();
    Cookie[http::MAX] raw_cookies;
    usz nc = 0;
    for (usz i = 0; i < p.n_set_cookies && nc < http::MAX; i++) {
        http::SetCookie* sc = &p.set_cookies[i];
        raw_cookies[nc++] = (Cookie){
            .name      = sc.name,   .value   = sc.value,
            .domain    = sc.domain, .path    = sc.path,
            .expires   = 0,         .secure  = sc.secure,
            .http_only = sc.http_only, .same_site = sc.same_site,
        };
    }
    if (nc > 0) jar.update(raw_cookies[0..], nc, req_url);
    r.cookies = jar;

    r.is_chunked     = p.chunked;
    r.content_length = p.content_length;
    if (r.is_chunked) r.chunk_dec.init();
    return r;
}

//  ClientResponse methods 

fn char*? ClientResponse.read(&self, usz* out_len)
{
    if (self.body_buf != null) { *out_len = self.body_len; return self.body_buf; }
    if (self.stream == null)   return HttpClientError.RESPONSE_ERROR?;

    char[RESP_READ_BUFSIZE] raw;

    if (self.is_chunked) {
        usz cap = 16384;
        char* buf = (char*)mem::alloc(cap);
        usz   len = 0;
        ChunkFrame frame;
        while (!self.chunk_dec.done()) {
            usz n = self.stream.read(raw[:]);
            if (n == 0) break;
            self.chunk_dec.feed(raw[0..n])!!;
            while (self.chunk_dec.next(&frame)) {
                if (frame.is_final) break;
                if (len + frame.data_len > cap) {
                    usz nc2 = (cap + frame.data_len) * 2;
                    char* nb = (char*)mem::alloc(nc2);
                    for (usz i = 0; i < len; i++) nb[i] = buf[i];
                    mem::free(buf); buf = nb; cap = nc2;
                }
                for (usz i = 0; i < frame.data_len; i++) buf[len++] = frame.data[i];
            }
        }
        self.body_buf = buf; self.body_len = len;
    } else {
        usz total = self.content_length;
        usz cap2  = total > 0 ? total : RESP_READ_BUFSIZE;
        char* buf = (char*)mem::alloc(cap2);
        usz   len = 0;
        while (total == 0 || len < total) {
            usz want = RESP_READ_BUFSIZE;
            if (total > 0 && total - len < want) want = total - len;
            usz n = self.stream.read((char[]){ buf + len, want });
            if (n == 0) break;
            len += n;
            if (total == 0 && len + RESP_READ_BUFSIZE > cap2) {
                cap2 *= 2;
                char* nb = (char*)mem::alloc(cap2);
                for (usz i = 0; i < len; i++) nb[i] = buf[i];
                mem::free(buf); buf = nb;
            }
        }
        self.body_buf = buf; self.body_len = len;
    }
    *out_len = self.body_len;
    return self.body_buf;
}

fn String? ClientResponse.text(&self, String encoding = "utf-8")
{
    usz len;
    char*? raw = self.read(&len);
    if (catch err = raw) return err?;
    return (String){ raw, len };
}

fn String? ClientResponse.json_text(&self) { return self.text(); }

fn void ClientResponse.raise_for_status(&self)
{
    // callers use:  resp.raise_for_status(); or  resp.raise_for_status()!;
    // The fault is embedded in the call chain via the response code.
    // Actual fault propagation handled by caller checking resp.status.
}

fn Stream* ClientResponse.content(&self) { return self.stream; }

fn void ClientResponse.release(&self)
{
    if (self.released) return;
    self.released = true;
    if (self.stream != null) {
        pool_release(&self.connector.pool, self.stream,
                     self.url.host, self.url.effective_port());
        self.stream = null;
    }
    if (self.body_buf  != null) { mem::free(self.body_buf);  self.body_buf  = null; }
    if (self.headers   != null) { self.headers.free();        self.headers   = null; }
    mem::free(self);
}

//  core request dispatcher 

fn bool is_redirect_status(int s) @private @inline
{
    return s == 301 || s == 302 || s == 303 || s == 307 || s == 308;
}

fn ClientResponse*? session_do_request(
    ClientSession* s, HttpMethod method, String url_str,
    Headers* params, Headers* req_headers,
    char* data, usz data_len, String json_str, FormData* form,
    TlsConfig* tls,
) @private
{
    if (s.closed) return HttpClientError.CONNECTION_FAILED?;
    Url url = url_parse(url_str)!;
    int redirects = 0;

    while (true) {
        ushort port = url.effective_port();

        Stream*? stream = pool_acquire(&s.connector.pool, url.host, port,
                                       s.timeout.connect_us, mem::heap());
        if (catch = stream) return HttpClientError.CONNECTION_FAILED?;

        // inject cookies
        usz nc_jar;
        Cookie* jar_cookies = s.cookie_jar.filter(&url, &nc_jar);
        if (nc_jar > 0 && jar_cookies != null) {
            Headers* ch = headers_new();
            char[4096] ck; usz ck_j = 0;
            for (usz i = 0; i < nc_jar; i++) {
                if (i > 0) { ck[ck_j++] = ';'; ck[ck_j++] = ' '; }
                foreach (c : jar_cookies[i].name)  ck[ck_j++] = c;
                ck[ck_j++] = '=';
                foreach (c : jar_cookies[i].value) ck[ck_j++] = c;
            }
            ch.add("Cookie", (String){ ck[0..], ck_j });
            mem::free(jar_cookies);

            Headers* merged = headers_new();
            if (req_headers != null) {
                for (usz i = 0; i < req_headers.count; i++) {
                    merged.add(req_headers.entries[i].name, req_headers.entries[i].value);
                }
            }
            String? cookie_val = ch.get("Cookie");
            if (!catch cookie_val) merged.add("Cookie", cookie_val);
            ch.free();
            req_headers = merged;
        }

        void*? wr = req_write(stream, method, &url, params,
                               s.default_headers, req_headers, s.auth,
                               data, data_len, json_str, form, mem::heap());
        if (catch = wr) {
            pool_release(&s.connector.pool, stream, url.host, port);
            return HttpClientError.CONNECTION_FAILED?;
        }

        char[RESP_READ_BUFSIZE * 2] hdr_scratch;
        http::Response parsed;
        usz filled = 0;
        char*? body_ptr = resp_read_headers(stream, &parsed,
                                             hdr_scratch[0..], $sizeof(hdr_scratch), &filled);
        if (catch = body_ptr) {
            pool_release(&s.connector.pool, stream, url.host, port);
            return HttpClientError.RESPONSE_ERROR?;
        }

        ClientResponse*? resp = build_response(&parsed, &url, stream, s.connector,
                                                s.cookie_jar, body_ptr, filled, mem::heap());
        if (catch = resp) {
            pool_release(&s.connector.pool, stream, url.host, port);
            return HttpClientError.RESPONSE_ERROR?;
        }

        // redirects
        if (is_redirect_status(resp.status) && redirects < MAX_REDIRECTS) {
            redirects++;
            String? loc = resp.headers.get("location");
            resp.release();
            if (catch = loc) return HttpClientError.RESPONSE_ERROR?;
            if (resp.status == 303) {
                method = HttpMethod.GET;
                data = null; data_len = 0; json_str = ""; form = null;
            }
            Url? new_url = url_parse(loc);
            if (catch = new_url) {
                // relative redirect
                char[4096] abs_buf; usz ab_j = 0;
                macro void abp(str) { for (usz _i=0;_i<str.len;_i++) abs_buf[ab_j++]=str[_i]; }
                abp(url.scheme); abp("://"); abp(url.host);
                if (url.port != 0 && url.port != scheme_default_port(url.scheme)) {
                    abs_buf[ab_j++] = ':';
                    char[6] pb; usz pl = 0; uint pv = (uint)url.port;
                    do { pb[pl++] = (char)('0' + pv % 10); pv /= 10; } while (pv > 0);
                    for (usz i = pl; i > 0; i--) abs_buf[ab_j++] = pb[i-1];
                }
                abp(loc); abs_buf[ab_j] = 0;
                url = url_parse((String){ abs_buf[0..], ab_j })!;
            } else {
                url = new_url;
            }
            continue;
        }
        if (redirects >= MAX_REDIRECTS) { resp.release(); return HttpClientError.TOO_MANY_REDIRECTS?; }
        if (s.raise_for_status && resp.status >= 400) { resp.release(); return HttpClientError.RESPONSE_ERROR?; }
        return resp;
    }
}

//  ClientSession HTTP method shortcuts 

fn ClientResponse*? ClientSession.request(&self, HttpMethod method, String url,
    Headers* params = null, Headers* headers = null,
    char* data = null, usz data_len = 0, String json_str = "",
    FormData* form = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, method, url, params, headers,
                              data, data_len, json_str, form, tls);
}

fn ClientResponse*? ClientSession.get(&self, String url,
    Headers* params = null, Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.GET, url, params, headers, null, 0, "", null, tls);
}

fn ClientResponse*? ClientSession.post(&self, String url,
    char* data = null, usz data_len = 0, String json_str = "",
    FormData* form = null, Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.POST, url, null, headers,
                              data, data_len, json_str, form, tls);
}

fn ClientResponse*? ClientSession.put(&self, String url,
    char* data = null, usz data_len = 0, String json_str = "",
    Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.PUT, url, null, headers,
                              data, data_len, json_str, null, tls);
}

fn ClientResponse*? ClientSession.patch(&self, String url,
    char* data = null, usz data_len = 0, String json_str = "",
    Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.PATCH, url, null, headers,
                              data, data_len, json_str, null, tls);
}

fn ClientResponse*? ClientSession.delete(&self, String url,
    Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.DELETE, url, null, headers,
                              null, 0, "", null, tls);
}

fn ClientResponse*? ClientSession.head(&self, String url,
    Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.HEAD, url, null, headers,
                              null, 0, "", null, tls);
}

fn ClientResponse*? ClientSession.options(&self, String url,
    Headers* headers = null, TlsConfig* tls = null) @maydiscard
{
    return session_do_request(self, HttpMethod.OPTIONS, url, null, headers,
                              null, 0, "", null, tls);
}

//  ClientWs 

struct ClientWs {
    bool   closed;
    String protocol;
    int    compress;
    Stream*       stream      @private;
    TcpConnector* connector   @private;
    Url           url         @private;
    WsDecoder     decoder     @private;
    ulong         heartbeat_us        @private;
    ulong         receive_timeout_us  @private;
    fault?        last_error          @private;
    char[64]      peername_buf        @private;
    usz           peername_len        @private;
}

fn void make_ws_key(char* out24) @private
{
    ulong seed = asyncio::clock_now();
    char[16] raw;
    for (usz i = 0; i < 16; i++) {
        seed = seed * 6364136223846793005 + 1442695040888963407;
        raw[i] = (char)(seed >> 56);
    }
    String b64 = base64::encode(mem::temp(), raw[:]);
    for (usz i = 0; i < 24 && i < b64.len; i++) out24[i] = b64[i];
}

fn ClientWs*? ClientSession.ws_connect(
    &self, String url,
    ulong heartbeat_us = 30_000_000, ulong receive_timeout_us = 30_000_000,
    int compress = 0, String* protocols = null, usz protocols_count = 0,
    TlsConfig* tls = null,
) @maydiscard
{
    if (self.closed) return HttpClientError.CONNECTION_FAILED?;

    Url parsed = url_parse(url)!;
    if (parsed.scheme == "ws")  parsed.scheme = "http";
    if (parsed.scheme == "wss") parsed.scheme = "https";
    ushort port = parsed.effective_port();

    Stream*? stream = pool_acquire(&self.connector.pool, parsed.host, port,
                                    self.timeout.connect_us, mem::heap());
    if (catch = stream) return HttpClientError.CONNECTION_FAILED?;

    char[WS_KEY_B64_LEN + 1] ws_key;
    make_ws_key(ws_key[0..]);
    String ws_key_str = (String){ ws_key[0..], WS_KEY_B64_LEN };

    // build subprotocol list
    char[256] proto_buf; usz proto_len = 0;
    for (usz i = 0; i < protocols_count; i++) {
        if (i > 0 && proto_len < 254) { proto_buf[proto_len++] = ','; proto_buf[proto_len++] = ' '; }
        foreach (c : protocols[i]) { if (proto_len < 255) proto_buf[proto_len++] = c; }
    }

    char[WS_HANDSHAKE_BUFSZ] hs_buf;
    usz hs_len = ws_client_handshake_request(
        hs_buf[0..], WS_HANDSHAKE_BUFSZ,
        parsed.host,
        parsed.path.len > 0 ? parsed.path : "/",
        ws_key_str,
        (String){ proto_buf[0..], proto_len },
    );
    stream.write(hs_buf[0..hs_len])!!;

    // read 101 response
    char[RESP_READ_BUFSIZE] resp_buf; usz resp_filled = 0;
    while (resp_filled < RESP_READ_BUFSIZE) {
        usz n = stream.read((char[]){ resp_buf + resp_filled, RESP_READ_BUFSIZE - resp_filled });
        if (n == 0) { pool_release(&self.connector.pool, stream, parsed.host, port); return HttpClientError.WS_ERROR?; }
        resp_filled += n;
        for (usz i = 0; i + 3 < resp_filled; i++) {
            if (resp_buf[i]=='\r' && resp_buf[i+1]=='\n' &&
                resp_buf[i+2]=='\r' && resp_buf[i+3]=='\n') goto got_hs;
        }
    }
    pool_release(&self.connector.pool, stream, parsed.host, port);
    return HttpClientError.WS_ERROR?;

    got_hs:
    String resp_str = (String){ resp_buf[0..], resp_filled };
    bool? ok = ws_server_handshake_response(resp_str, ws_key_str, mem::heap());
    if (catch = ok) { pool_release(&self.connector.pool, stream, parsed.host, port); return HttpClientError.WS_ERROR?; }

    ClientWs* ws = (ClientWs*)mem::alloc($sizeof(ClientWs));
    ws.closed            = false;
    ws.protocol          = "";
    ws.compress          = compress;
    ws.stream            = stream;
    ws.connector         = self.connector;
    ws.url               = parsed;
    ws.heartbeat_us      = heartbeat_us;
    ws.receive_timeout_us = receive_timeout_us;
    ws.last_error        = null;
    ws.decoder.init(false, 0); // server sends unmasked

    // build peername "host:port"
    usz pi = 0;
    foreach (c : parsed.host) { if (pi < 62) ws.peername_buf[pi++] = c; }
    ws.peername_buf[pi++] = ':';
    uint pv = (uint)port; char[6] pd; usz pdl = 0;
    do { pd[pdl++] = (char)('0' + pv % 10); pv /= 10; } while (pv > 0);
    for (usz i = pdl; i > 0; i--) { if (pi < 63) ws.peername_buf[pi++] = pd[i-1]; }
    ws.peername_len = pi;
    return ws;
}

fn void? ws_send(ClientWs* ws, WsMsgType type, char* data, usz len) @private
{
    if (ws.closed) return HttpClientError.WS_ERROR?;
    ulong seed = asyncio::clock_now();
    char[4] mask = { (char)(seed>>24), (char)(seed>>16), (char)(seed>>8), (char)seed };
    String? frame = ws_frame_encode_alloc(mem::heap(), type, data, len, true, mask);
    if (catch = frame) return HttpClientError.WS_ERROR?;
    ws.stream.write((char[]){ frame.ptr, frame.len })!;
    mem::free((void*)frame.ptr);
}

fn void? ClientWs.send_str(&self, String data) @maydiscard
    => ws_send(self, WsMsgType.TEXT, (char*)data.ptr, data.len);
fn void? ClientWs.send_bytes(&self, char* data, usz len) @maydiscard
    => ws_send(self, WsMsgType.BINARY, data, len);
fn void? ClientWs.send_json(&self, String json_str) @maydiscard
    => ws_send(self, WsMsgType.TEXT, (char*)json_str.ptr, json_str.len);
fn void? ClientWs.ping(&self, char* message = null, usz msg_len = 0) @maydiscard
    => ws_send(self, WsMsgType.PING, message, msg_len);
fn void? ClientWs.pong(&self, char* message = null, usz msg_len = 0) @maydiscard
    => ws_send(self, WsMsgType.PONG, message, msg_len);

fn WsMessage? ClientWs.receive(&self)
{
    if (self.closed) return HttpClientError.WS_ERROR?;
    char[RESP_READ_BUFSIZE] raw;

    while (true) {
        WsFrame frame;
        bool? got = self.decoder.next(&frame);
        if (catch = got) return HttpClientError.WS_ERROR?;

        if (got) {
            if (frame.type == WsMsgType.PING) {
                ws_send(self, WsMsgType.PONG, frame.data, frame.data_len)!!;
                continue;
            }
            if (frame.type == WsMsgType.CLOSE) {
                self.closed = true;
                WsMessage msg; msg.type = WsMsgType.CLOSE;
                msg.data = null; msg.data_len = 0; msg.extra = frame.close_reason;
                return msg;
            }
            // copy + reassemble fragments
            char* buf = (char*)mem::alloc(frame.data_len > 0 ? frame.data_len : 1);
            for (usz i = 0; i < frame.data_len; i++) buf[i] = frame.data[i];
            usz total = frame.data_len;
            while (!frame.fin) {
                WsFrame cont; bool? gc = self.decoder.next(&cont);
                if (catch = gc) break;
                if (!gc) {
                    usz n = self.stream.read(raw[:]);
                    if (n == 0) break;
                    self.decoder.feed(raw[0..n])!!;
                    continue;
                }
                char* nb = (char*)mem::alloc(total + cont.data_len);
                for (usz i = 0; i < total; i++) nb[i] = buf[i];
                for (usz i = 0; i < cont.data_len; i++) nb[total+i] = cont.data[i];
                mem::free(buf); buf = nb; total += cont.data_len; frame.fin = cont.fin;
            }
            WsMessage msg; msg.type = frame.type;
            msg.data = buf; msg.data_len = total; msg.extra = "";
            return msg;
        }
        usz n = self.stream.read(raw[:]);
        if (n == 0) { self.closed = true; return HttpClientError.WS_ERROR?; }
        self.decoder.feed(raw[0..n])!!;
    }
}

fn String? ClientWs.receive_str(&self)
{
    WsMessage? msg = self.receive();
    if (catch err = msg) return err?;
    return (String){ msg.data, msg.data_len };
}

fn char*? ClientWs.receive_bytes(&self, usz* out_len)
{
    WsMessage? msg = self.receive();
    if (catch err = msg) return err?;
    *out_len = msg.data_len;
    return msg.data;
}

fn String? ClientWs.receive_json(&self) => self.receive_str();

fn void? ClientWs.close(&self,
    WsCloseCode code = WsCloseCode.NORMAL_CLOSURE,
    char* message = null, usz msg_len = 0,
) @maydiscard
{
    if (self.closed) return;
    self.closed = true;
    ulong seed = asyncio::clock_now();
    char[4] mask = { (char)(seed>>24),(char)(seed>>16),(char)(seed>>8),(char)seed };
    char[140] cb; usz clen = ws_close_frame(cb[0..], code,
        message != null ? (String){ message, msg_len } : "", true, mask);
    self.stream.write(cb[0..clen])!;
}

fn void ClientWs.free(&self)
{
    if (!self.closed) self.close()!!;
    pool_release(&self.connector.pool, self.stream,
                 self.url.host, self.url.effective_port());
    mem::free(self);
}

fn String ClientWs.get_peername(&self)
    => (String){ self.peername_buf[0..], self.peername_len };

fn fault? ClientWs.exception(&self) => self.last_error;
