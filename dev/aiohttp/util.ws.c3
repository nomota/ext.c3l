// util.ws.c3

module ext::aiohttp;

import std::encoding::base64;
import std::hash::sha1;
import ext::debug; // warn()

// WebSocket frame codec — RFC 6455.
//
// Shared by both ClientWs (client side) and WebSocketResponse (server side).
//
// Handshake:
//   ws_client_handshake_request()   : build the HTTP Upgrade request headers
//   ws_server_handshake_response()  : validate + build the HTTP 101 response
//   ws_accept_key()                 : compute Sec-WebSocket-Accept value
//
// Frame encoding:
//   ws_frame_size()                 : predict encoded frame byte count
//   ws_frame_encode()               : write one frame into a pre-allocated buffer
//   ws_frame_encode_alloc()         : allocator convenience wrapper
//
// Frame decoding:
//   WsDecoder                       : streaming state machine
//   WsDecoder.feed()                : push raw bytes
//   WsDecoder.next()                : pull one decoded WsFrame
//   WsDecoder.done()                : true after CLOSE frame consumed
//
// Masking:
//   Client → Server frames MUST be masked (RFC 6455 §5.3).
//   Server → Client frames MUST NOT be masked.
//   ws_frame_encode() takes a bool masked parameter.
//   The masking key is caller-supplied (use a CSPRNG in production;
//   a simple 32-bit counter is fine for testing).

//  constants 

const String WS_GUID @private = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// WebSocket opcodes (RFC 6455 §5.2)
const char WS_OP_CONT  @private = 0x0;
const char WS_OP_TEXT  @private = 0x1;
const char WS_OP_BIN   @private = 0x2;
const char WS_OP_CLOSE @private = 0x8;
const char WS_OP_PING  @private = 0x9;
const char WS_OP_PONG  @private = 0xA;

// Maximum control frame payload (RFC 6455 §5.5)
const usz WS_MAX_CONTROL_LEN @private = 125;

//  faults 

faultdef
    INVALID_OPCODE,       // unknown or reserved opcode
    FRAGMENTED_CONTROL,   // control frame with FIN=0
    CONTROL_TOO_LONG,     // control frame payload > 125 bytes
    INVALID_MASK,         // server received a masked frame (or vice versa)
    PAYLOAD_TOO_LARGE,    // decoded payload exceeds configured limit
    BAD_HANDSHAKE,        // HTTP Upgrade response is invalid
    BAD_ACCEPT_KEY;       // Sec-WebSocket-Accept mismatch


//  handshake 

// Compute Sec-WebSocket-Accept from a client key.
// Returns a base64 string into mem. Caller must free if mem is a heap allocator.
fn String ws_accept_key(Allocator alloc, String client_key)
{
    localmem = alloc;
    
    // concatenate key + GUID into a stack buffer
    char[128] combined;
    usz klen = client_key.len < 88 ? client_key.len : 88;
    usz glen = WS_GUID.len;
    for (usz i = 0; i < klen; i++) combined[i] = client_key[i];
    for (usz i = 0; i < glen; i++) combined[klen + i] = WS_GUID[i];
    usz total = klen + glen;

    Sha1 sha;
    sha.init();
    sha.update(combined[0:total]);
    char[sha1::HASH_BYTES] digest = sha.final();

    return base64::encode(alloc, &digest);
}

struct OBuf {
    char* out;
    usz size;
    usz cursor;
}

fn void OBuf.put(&self, String str) @inline
{
    if (self.size <= self.cursor+str.len) {
        warn("buf size overflow");
        return;
    }
    
    self.out[self.cursor:str.len] = str[0:str.len];
    self.cursor += str.len;
}

fn void OBuf.putc(&self, char c) @inline
{
    if (self.size <= self.cursor+1) {
        warn("buf size overflow");
        return;
    }
    
    self.out[self.cursor++] = c;
}

fn void OBuf.putn(&self, int n) @inline
{
    char[20] t;
    usz l = 0;
    int v = n;
    if (v == 0) { 
        t[l++] = '0';
    } else {
        while (v > 0) {
            t[l++] = (char)('0' + v % 10);
            v /= 10;
        }
    }
    while (l > 0) {
        self.out[self.cursor++] = t[--l];
    }
}

fn void OBuf.crlf(&self) @inline
{
    self.put("\r\n");
}

fn String OBuf.str(&self) @inline
{
    return (String)self.out[0:self.cursor];
}


// Build the HTTP/1.1 Upgrade request line + headers into out[].
// Returns number of bytes written.
// out must be at least 512 bytes (typical; larger for long URLs/subprotocols).
//
// client_key must be a base64-encoded 16-byte random value (24 chars).
// subprotocols: comma-separated list, "" = omit header.
fn usz ws_client_handshake_request(
    char*  out,
    usz    out_size,
    String host,
    String path,
    String client_key,
    String subprotocols = "",
)
{
    OBuf buf = { out, out_size, 0 };

    buf.put("GET ");
    buf.put(path.len > 0 ? path : "/");
    buf.put(" HTTP/1.1\r\n");
    buf.put("Host: ");
    buf.put(host);
    buf.put("\r\n");
    buf.put("Upgrade: websocket\r\n");
    buf.put("Connection: Upgrade\r\n");
    buf.put("Sec-WebSocket-Version: 13\r\n");
    buf.put("Sec-WebSocket-Key: ");
    buf.put(client_key);
    buf.put("\r\n");

    if (subprotocols.len > 0) {
        buf.put("Sec-WebSocket-Protocol: ");
        buf.put(subprotocols);
        buf.put("\r\n");
    }

    buf.put("\r\n"); // blank line terminates headers
    return buf.cursor;
}

// case-insensitive header name comparison (lowercase or title-case)
fn bool name_eq(String a, String b) @inline
{
    if (a.len != b.len) return false;
    for (usz i = 0; i < a.len; i++) {
        char ca = a[i] | 0x20; // to lower
        char cb = b[i] | 0x20;
        if (ca != cb) return false;
    }
    return true;
}

// Validate the server's HTTP 101 response and check Sec-WebSocket-Accept.
// response_headers must be a null-terminated string of the response header block.
// client_key is the value sent in the request.
// Uses tmem (temp allocator) internally.
fn bool? ws_server_handshake_response(
    String response_headers,
    String client_key,
    Allocator alloc,
)
{
    localmem = alloc;
    
    // must contain "101"
    bool has_101 = false;
    bool has_upgrade = false;
    bool has_connection = false;
    String accept_val;

    // scan line by line
    usz pos = 0;
    while (pos < response_headers.len) {
        usz line_start = pos;
        while (pos < response_headers.len &&
               !(response_headers[pos] == '\r' &&
                 pos + 1 < response_headers.len &&
                 response_headers[pos + 1] == '\n')) {
            pos++;
        }
        String line = (String) response_headers[line_start: pos - line_start];
        pos += 2; // skip CRLF

        if (line.len == 0) break; // end of headers

        // status line check
        if (line.len > 12 && line[9] == '1' && line[10] == '0' && line[11] == '1') {
            has_101 = true;
            continue;
        }

        // find ": " separator
        usz colon = line.len;
        for (usz i = 0; i < line.len; i++) {
            if (line[i] == ':') { colon = i; break; }
        }
        if (colon >= line.len) continue;

        String name = (String) line[0:colon];
        usz val_start = colon + 1;
        while (val_start < line.len && line[val_start] == ' ') val_start++;
        String val  = (String) line[val_start:line.len - val_start];
 
        if (name_eq(name, "upgrade")) has_upgrade = true;
        if (name_eq(name, "connection")) has_connection = true;
        if (name_eq(name, "sec-websocket-accept")) accept_val = val;
    }

    if (!has_101 || !has_upgrade || !has_connection) {
        return BAD_HANDSHAKE~;
    }

    String expected = ws_accept_key(alloc, client_key);
    if (accept_val != expected) return BAD_ACCEPT_KEY~;

    return true;
}

// Build the HTTP 101 Switching Protocols response into out[].
// Returns number of bytes written.
fn usz ws_server_handshake_accept(
    char*  out,
    usz    out_size,
    String client_key,
    String subprotocol,  // "" = omit
    Allocator alloc,
)
{
    localmem = alloc;
    
    String accept = ws_accept_key(alloc, client_key);

    OBuf buf = { out, out_size, 0 };
    
    buf.put("HTTP/1.1 101 Switching Protocols\r\n");
    buf.put("Upgrade: websocket\r\n");
    buf.put("Connection: Upgrade\r\n");
    buf.put("Sec-WebSocket-Accept: ");
    buf.put(accept);
    buf.put("\r\n");

    if (subprotocol.len > 0) {
        buf.put("Sec-WebSocket-Protocol: ");
        buf.put(subprotocol);
        buf.put("\r\n");
    }

    buf.put("\r\n");
    return buf.cursor;;
}

//  frame encoding 

// Map WsMsgType to wire opcode.
fn char ws_opcode(WsMsgType t) @private @inline
{
    switch (t) {
        case WsMsgType.TEXT:   return WS_OP_TEXT;
        case WsMsgType.BINARY: return WS_OP_BIN;
        case WsMsgType.PING:   return WS_OP_PING;
        case WsMsgType.PONG:   return WS_OP_PONG;
        case WsMsgType.CLOSE:  return WS_OP_CLOSE;
        default:               return WS_OP_BIN;
    }
}

// Return the byte count ws_frame_encode() will write.
fn usz ws_frame_size(usz payload_len, bool masked)
{
    usz header = 2; // FIN/opcode byte + payload-len byte
    if (payload_len <= 125) {
        header += 0;
    } else if (payload_len <= 0xFFFF) {
        header += 2;
    } else {
        header += 8;
    }
    if (masked) header += 4; // masking key
    return header + payload_len;
}

// Encode one WebSocket frame into out[].
// out must be at least ws_frame_size(payload_len, masked) bytes.
// mask_key is ignored when masked == false.
// Returns number of bytes written.
fn usz ws_frame_encode(
    char*     out,
    WsMsgType type,
    char*     payload,
    usz       payload_len,
    bool      masked,
    char[4]   mask_key,
    bool      fin = true,
)
{
    usz j = 0;

    // byte 0: FIN + opcode
    out[j++] = (char)(((fin ? 1 : 0) << 7) | ws_opcode(type));

    // byte 1: MASK bit + payload length (7 / 7+16 / 7+64)
    char mask_bit = masked ? (char)0x80 : (char)0x00;
    if (payload_len <= 125) {
        out[j++] = (char)(mask_bit | (char)payload_len);
    } else if (payload_len <= 0xFFFF) {
        out[j++] = (char)(mask_bit | 126);
        out[j++] = (char)((payload_len >> 8) & 0xFF);
        out[j++] = (char)(payload_len        & 0xFF);
    } else {
        out[j++] = (char)(mask_bit | 127);
        // 64-bit big-endian (top 32 bits are zero on 32-bit targets)
        out[j++] = 0; out[j++] = 0; out[j++] = 0; out[j++] = 0;
        out[j++] = (char)((payload_len >> 24) & 0xFF);
        out[j++] = (char)((payload_len >> 16) & 0xFF);
        out[j++] = (char)((payload_len >>  8) & 0xFF);
        out[j++] = (char)(payload_len         & 0xFF);
    }

    // masking key
    if (masked) {
        out[j++] = mask_key[0];
        out[j++] = mask_key[1];
        out[j++] = mask_key[2];
        out[j++] = mask_key[3];
    }

    // payload (masked XOR or plain copy)
    if (masked) {
        for (usz i = 0; i < payload_len; i++) {
            out[j++] = payload[i] ^ mask_key[i & 3];
        }
    } else {
        for (usz i = 0; i < payload_len; i++) {
            out[j++] = payload[i];
        }
    }

    return j;
}

// Allocator convenience wrapper — encodes one frame, returns the buffer.
// Caller must free the returned string.
fn String? ws_frame_encode_alloc(
    Allocator alloc,
    WsMsgType type,
    char*     payload,
    usz       payload_len,
    bool      masked,
    char[4]   mask_key,
    bool      fin = true,
)
{
    localmem = alloc;
    
    usz sz  = ws_frame_size(payload_len, masked);
    char* buf = localmem.malloc(sz);
    usz written = ws_frame_encode(buf, type, payload, payload_len, masked, mask_key, fin);
    return (String) buf[0:written];
}

// Build a CLOSE frame with optional status code and reason.
// close_code == 0 → no body (empty CLOSE frame).
fn usz ws_close_frame(
    char*       out,
    WsCloseCode close_code,
    String      reason,
    bool        masked,
    char[4]     mask_key,
)
{
    if (close_code == (WsCloseCode)0) {
        return ws_frame_encode(out, WsMsgType.CLOSE, null, 0, masked, mask_key);
    }

    // payload: 2-byte big-endian code + reason (≤123 bytes for total ≤125)
    usz reason_len = reason.len < 123 ? reason.len : 123;
    char[125] body;
    ushort code_val = (ushort)close_code;
    body[0] = (char)(code_val >> 8);
    body[1] = (char)(code_val & 0xFF);
    for (usz i = 0; i < reason_len; i++) body[2 + i] = reason[i];

    return ws_frame_encode(out, WsMsgType.CLOSE, body[0..], 2 + reason_len, masked, mask_key);
}

//  frame decoding 

const usz WS_RING_SIZE @private = 131072; // 128 KiB — must be power of two
const usz WS_RING_MASK @private = WS_RING_SIZE - 1;

// Decoded frame — data is a pointer into WsDecoder's ring buffer.
// Copy data before the next feed() call if you need it to persist.
struct WsFrame {
    WsMsgType type;
    char*     data;
    usz       data_len;
    bool      fin;           // true = final fragment
    bool      is_control;    // ping / pong / close
    WsCloseCode close_code;  // valid when type == CLOSE
    String    close_reason;  // slice into data (not null-terminated)
}

enum WsDecoderState : char @private {
    HEADER1,     // waiting for byte 0 (FIN + opcode)
    HEADER2,     // waiting for byte 1 (MASK + length)
    LEN16,       // reading 2-byte extended length
    LEN64,       // reading 8-byte extended length
    MASK_KEY,    // reading 4-byte masking key
    PAYLOAD,     // reading payload bytes
}

struct WsDecoder {
    char[WS_RING_SIZE] ring;
    usz r_head;
    usz r_tail;

    // frame header state
    WsDecoderState state;
    bool   expect_masked; // true on server (client must mask)
    usz    max_payload; // 0 = unlimited

    // current frame fields
    char   frame_opcode;
    bool   frame_fin;
    bool   frame_masked;
    usz    frame_payload_len;
    usz    frame_remaining;
    char[4] frame_mask_key;
    usz    header_bytes_read; // for multi-byte header fields

    // fragmentation reassembly
    WsMsgType frag_type; // type of ongoing fragmented message
    bool   in_fragment;

    bool   closed;
}

fn void WsDecoder.init(&self, bool expect_masked, usz max_payload = 0)
{
    self.r_head        = 0;
    self.r_tail        = 0;
    self.state         = WsDecoderState.HEADER1;
    self.expect_masked = expect_masked;
    self.max_payload   = max_payload;
    self.in_fragment   = false;
    self.closed        = false;
}

fn usz WsDecoder.buffered(&self) @inline { return self.r_tail - self.r_head; }

fn char WsDecoder.ring_at(&self, usz offset) @inline
{
    return self.ring[(self.r_head + offset) & WS_RING_MASK];
}

fn void WsDecoder.consume(&self, usz n) @inline { self.r_head += n; }

// Push raw bytes into the decoder.
fn void? WsDecoder.feed(&self, char* data, usz len)
{
    usz avail = WS_RING_SIZE - self.buffered();
    if (len > avail) return OVERFLOW~;
    for (usz i = 0; i < len; i++) {
        self.ring[self.r_tail & WS_RING_MASK] = data[i];
        self.r_tail++;
    }
}

// Pull the next decoded frame.
// Returns true + fills *out when a complete frame (or payload chunk) is ready.
// Returns false when more data is needed.
// Propagates WsCodecError on protocol violations.
fn bool? WsDecoder.next(&self, WsFrame* out)
{
    if (self.closed) return false;

    while (true) {
        switch (self.state) {

        //  byte 0: FIN + RSV + opcode 
        case WsDecoderState.HEADER1:
            if (self.buffered() < 1) return false;
            char b0 = self.ring_at(0);
            self.consume(1);

            self.frame_fin    = (b0 & 0x80) != 0;
            self.frame_opcode = b0 & 0x0F;

            // validate opcode
            switch (self.frame_opcode) {
                case WS_OP_CONT:
                case WS_OP_TEXT:
                case WS_OP_BIN:
                case WS_OP_CLOSE:
                case WS_OP_PING:
                case WS_OP_PONG:
                    break;
                default:
                    return INVALID_OPCODE~;
            }

            // control frames must not be fragmented
            bool is_ctrl = self.frame_opcode >= 0x8;
            if (is_ctrl && !self.frame_fin) return FRAGMENTED_CONTROL~;

            self.state = WsDecoderState.HEADER2;
            continue;

        //  byte 1: MASK bit + payload length 
        case WsDecoderState.HEADER2:
            if (self.buffered() < 1) return false;
            char b1 = self.ring_at(0);
            self.consume(1);

            self.frame_masked = (b1 & 0x80) != 0;

            if (self.frame_masked != self.expect_masked) {
                return INVALID_MASK~;
            }

            usz len7 = (usz)(b1 & 0x7F);
            self.header_bytes_read = 0;

            if (len7 <= 125) {
                self.frame_payload_len = len7;
                self.state = self.frame_masked
                    ? WsDecoderState.MASK_KEY
                    : WsDecoderState.PAYLOAD;

                // control frame payload limit
                bool is_ctrl = self.frame_opcode >= 0x8;
                if (is_ctrl && self.frame_payload_len > WS_MAX_CONTROL_LEN) {
                    return CONTROL_TOO_LONG~;
                }
            } else if (len7 == 126) {
                self.frame_payload_len = 0;
                self.state = WsDecoderState.LEN16;
            } else {
                self.frame_payload_len = 0;
                self.state = WsDecoderState.LEN64;
            }
            continue;

        //  16-bit extended length 
        case WsDecoderState.LEN16:
            if (self.buffered() < 2) return false;
            self.frame_payload_len = ((usz)self.ring_at(0) << 8) |
                                      (usz)self.ring_at(1);
            self.consume(2);
            self.state = self.frame_masked
                ? WsDecoderState.MASK_KEY
                : WsDecoderState.PAYLOAD;
            continue;

        //  64-bit extended length (top 32 bits must be 0) 
        case WsDecoderState.LEN64:
            if (self.buffered() < 8) return false;
            usz hi = ((usz)self.ring_at(0) << 24) | ((usz)self.ring_at(1) << 16)
                   | ((usz)self.ring_at(2) <<  8) |  (usz)self.ring_at(3);
            usz lo = ((usz)self.ring_at(4) << 24) | ((usz)self.ring_at(5) << 16)
                   | ((usz)self.ring_at(6) <<  8) |  (usz)self.ring_at(7);
            self.consume(8);
            self.frame_payload_len = (hi << 32) | lo;
            self.state = self.frame_masked
                ? WsDecoderState.MASK_KEY
                : WsDecoderState.PAYLOAD;
            continue;

        //  4-byte masking key 
        case WsDecoderState.MASK_KEY:
            if (self.buffered() < 4) return false;
            self.frame_mask_key[0] = self.ring_at(0);
            self.frame_mask_key[1] = self.ring_at(1);
            self.frame_mask_key[2] = self.ring_at(2);
            self.frame_mask_key[3] = self.ring_at(3);
            self.consume(4);
            self.frame_remaining = self.frame_payload_len;
            self.state = WsDecoderState.PAYLOAD;
            continue;

        //  payload bytes (zero-copy into ring, unmask in place) 
        case WsDecoderState.PAYLOAD:
            if (self.frame_remaining == 0) {
                // full frame header + payload consumed — emit frame
                out.fin         = self.frame_fin;
                out.is_control  = self.frame_opcode >= 0x8;
                out.data        = null;
                out.data_len    = 0;

                // resolve opcode (handle continuations)
                switch (self.frame_opcode) {
                    case WS_OP_TEXT:
                        out.type       = WsMsgType.TEXT;
                        self.frag_type = WsMsgType.TEXT;
                        self.in_fragment = !self.frame_fin;
                    case WS_OP_BIN:
                        out.type       = WsMsgType.BINARY;
                        self.frag_type = WsMsgType.BINARY;
                        self.in_fragment = !self.frame_fin;
                    case WS_OP_CONT:
                        out.type = self.frag_type;
                        if (self.frame_fin) self.in_fragment = false;
                    case WS_OP_PING:  out.type = WsMsgType.PING;
                    case WS_OP_PONG:  out.type = WsMsgType.PONG;
                    case WS_OP_CLOSE:
                        out.type  = WsMsgType.CLOSE;
                        self.closed = true;
                    default:
                        out.type = WsMsgType.BINARY;
                }

                out.close_code   = (WsCloseCode)0;
                out.close_reason = "";

                self.state = WsDecoderState.HEADER1;
                return true;
            }

            usz avail = self.buffered();
            if (avail == 0) return false;

            usz take = self.frame_remaining < avail ? self.frame_remaining : avail;

            // expose contiguous slice (bounded by ring wrap)
            usz ring_pos = self.r_head & WS_RING_MASK;
            usz contig   = WS_RING_SIZE - ring_pos;
            if (take > contig) take = contig;

            // check user payload limit
            if (self.max_payload > 0 && self.frame_payload_len > self.max_payload) {
                return PAYLOAD_TOO_LARGE~;
            }

            // unmask in place
            if (self.frame_masked) {
                usz offset = self.frame_payload_len - self.frame_remaining;
                for (usz i = 0; i < take; i++) {
                    usz ring_i = (ring_pos + i) & WS_RING_MASK;
                    self.ring[ring_i] ^= self.frame_mask_key[(offset + i) & 3];
                }
            }

            // fill frame slice
            out.type      = WsMsgType.BINARY; // will be overwritten at end of payload
            out.data      = &self.ring[ring_pos];
            out.data_len  = take;
            out.fin       = self.frame_fin && (take == self.frame_remaining);
            out.is_control = self.frame_opcode >= 0x8;
            out.close_code   = (WsCloseCode)0;
            out.close_reason = "";

            // resolve type for this partial frame
            switch (self.frame_opcode) {
                case WS_OP_TEXT:   out.type = WsMsgType.TEXT;
                case WS_OP_BIN:    out.type = WsMsgType.BINARY;
                case WS_OP_CONT:   out.type = self.frag_type;
                case WS_OP_PING:   out.type = WsMsgType.PING;
                case WS_OP_PONG:   out.type = WsMsgType.PONG;
                case WS_OP_CLOSE:  out.type = WsMsgType.CLOSE;
                default:           out.type = WsMsgType.BINARY;
            }

            self.consume(take);
            self.frame_remaining -= take;
            return true;
        }
    }
}

fn bool WsDecoder.done(&self) @inline { return self.closed; }
