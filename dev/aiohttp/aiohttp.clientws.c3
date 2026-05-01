// aiohttp.clientws.c3

module ext::aiohttp;

import ext::asyncio;
import ext::serializer::http;
import ext::serializer::simdjson;
import std::encoding::base64;
import std::hash::sha1;
import ext::mem;
import ext::debug;
import ext::thread::fiber;
import std::collections::pair;


//  ClientWs 

struct ClientWs {
    bool   closed;
    String protocol;
    int    compress;
    Stream*       stream;
    TcpConnector* connector;
    Url           url;
    WsDecoder     decoder;
    double        heartbeat;
    double       receive_timeout;
    fault        last_error;
    char[64]      peername_buf;
    usz           peername_len;
}

fn void make_ws_key(char* out24) @private
{
    ulong seed = asyncio::clock_now();
    char[16] raw;
    for (usz i = 0; i < 16; i++) {
        seed = seed * 6364136223846793005 + 1442695040888963407;
        raw[i] = (char)(seed >> 56);
    }
    String b64 = base64::encode(localmem, &raw);
    for (usz i = 0; i < 24 && i < b64.len; i++) out24[i] = b64[i];
}

fn ClientWs*? ClientSession.ws_connect(
    &self, String url,
    double heartbeat = 30.0, double receive_timeout = 30.0,
    int compress = 0, String* protocols = null, usz protocols_count = 0,
    TlsConfig* tls = null,
) @maydiscard
{
    if (self.closed) return CONNECTION_FAILED~;

    Url parsed = url_parse(url)!;
    if (parsed.scheme == "ws")  parsed.scheme = "http";
    if (parsed.scheme == "wss") parsed.scheme = "https";
    ushort port = parsed.effective_port();

    Stream*? stream = pool_acquire(&self.connector.pool, parsed.host, port, self.timeout.connect, localmem);
    if (catch err = stream) return CONNECTION_FAILED~;

    char[WS_KEY_B64_LEN + 1] ws_key;
    make_ws_key(&ws_key[0]);
    String ws_key_str = (String) ws_key[0: WS_KEY_B64_LEN];

    // build subprotocol list
    char[256] proto_buf; usz proto_len = 0;
    for (usz i = 0; i < protocols_count; i++) {
        if (i > 0 && proto_len < 254) { proto_buf[proto_len++] = ','; proto_buf[proto_len++] = ' '; }
        foreach (c : protocols[i]) { if (proto_len < 255) proto_buf[proto_len++] = c; }
    }

    char[WS_HANDSHAKE_BUFSZ] hs_buf;
    usz hs_len = ws_client_handshake_request(
        &hs_buf[0], WS_HANDSHAKE_BUFSZ,
        parsed.host,
        parsed.path.len > 0 ? parsed.path : "/",
        ws_key_str,
        (String)proto_buf[0:proto_len],
    );
    stream.write(hs_buf[0:hs_len])!;

    // read 101 response
    char[RESP_READ_BUFSIZE] resp_buf;
    usz resp_filled = 0;
    bool got_hs = false;
    while (!got_hs && resp_filled < RESP_READ_BUFSIZE) {
        usz n = stream.read(resp_buf[resp_filled: RESP_READ_BUFSIZE - resp_filled ])!;
        if (n == 0) { pool_release(&self.connector.pool, stream, parsed.host, port); return WS_ERROR~; }
        resp_filled += n;
        for (usz i = 0; i + 3 < resp_filled; i++) {
            if (resp_buf[i]=='\r' && resp_buf[i+1]=='\n' && resp_buf[i+2]=='\r' && resp_buf[i+3]=='\n') {
                got_hs = true;
                break;
            }
        }
    }
    if (!got_hs) {
        pool_release(&self.connector.pool, stream, parsed.host, port);
        return WS_ERROR~;
    }
    
    String resp_str = (String) resp_buf[0: resp_filled];
    bool? ok = ws_server_handshake_response(resp_str, ws_key_str, localmem);
    if (catch err = ok) { pool_release(&self.connector.pool, stream, parsed.host, port); return WS_ERROR~; }

    ClientWs* ws = localmem.alloc(ClientWs);
    ws.closed = false;
    ws.protocol = "";
    ws.compress = compress;
    ws.stream = stream;
    ws.connector = self.connector;
    ws.url = parsed;
    ws.heartbeat = heartbeat;
    ws.receive_timeout = receive_timeout;
    ws.last_error = NONE;
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
    if (ws.closed) return WS_ERROR~;
    ulong seed = asyncio::clock_now();
    char[4] mask = { (char)(seed>>24), (char)(seed>>16), (char)(seed>>8), (char)seed };
    String? frame = ws_frame_encode_alloc(localmem, type, data, len, true, mask);
    if (catch err = frame) return WS_ERROR~;
    defer frame.free(localmem);

    ws.stream.write(frame[0:frame.len])!;
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
    if (self.closed) return WS_ERROR~;
    char[RESP_READ_BUFSIZE] raw;

    while (true) {
        WsFrame frame;
        bool? got = self.decoder.next(&frame);
        if (catch err = got) return WS_ERROR~;

        if (got) {
            if (frame.type == WsMsgType.PING) {
                ws_send(self, WsMsgType.PONG, frame.data, frame.data_len)!;
                continue;
            }
            if (frame.type == WsMsgType.CLOSE) {
                self.closed = true;
                WsMessage msg; msg.type = WsMsgType.CLOSE;
                msg.data = null; msg.data_len = 0; msg.extra = frame.close_reason;
                return msg;
            }
            // copy + reassemble fragments
            char* buf = localmem.malloc(frame.data_len > 0 ? frame.data_len : 1);
            for (usz i = 0; i < frame.data_len; i++) buf[i] = frame.data[i];
            usz total = frame.data_len;
            while (!frame.fin) {
                WsFrame cont;
                bool? gc = self.decoder.next(&cont);
                if (catch err = gc) break;
                if (!gc) {
                    usz n = self.stream.read(&raw)!;
                    if (n == 0) break;
                    self.decoder.feed(&raw[0], n)!;
                    continue;
                }
                char* nb = localmem.malloc(total + cont.data_len);
                for (usz i = 0; i < total; i++) nb[i] = buf[i];
                for (usz i = 0; i < cont.data_len; i++) nb[total+i] = cont.data[i];
                localmem.free(buf); buf = nb; total += cont.data_len; frame.fin = cont.fin;
            }
            WsMessage msg; msg.type = frame.type;
            msg.data = buf; msg.data_len = total; msg.extra = "";
            return msg;
        }
        usz n = self.stream.read(&raw)!;
        if (n == 0) { self.closed = true; return WS_ERROR~; }
        self.decoder.feed(&raw[0], n)!;
    }
}

fn String? ClientWs.receive_str(&self)
{
    WsMessage? msg = self.receive();
    if (catch err = msg) return err~;
    return (String)msg.data[0: msg.data_len ];
}

fn char*? ClientWs.receive_bytes(&self, usz* out_len)
{
    WsMessage? msg = self.receive();
    if (catch err = msg) return err~;
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
    char[140] cb; usz clen = ws_close_frame(&cb[0], code,
        message != null ? (String)message[0: msg_len] : "", true, mask);
    self.stream.write(cb[0:clen])!;
}

fn void ClientWs.free(&self)
{
    if (!self.closed) (void)self.close();
    pool_release(&self.connector.pool, self.stream, self.url.host, self.url.effective_port());
    localmem.free(self);
}

fn String ClientWs.get_peername(&self)
 => (String) self.peername_buf[0: self.peername_len];

fn fault ClientWs.exception(&self) => self.last_error;
