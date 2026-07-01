// ws_connection.c3

// WebSocket stream connection and message handling.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::aio;
import ext::mem;
import c::errno;

// Faults

faultdef WS_CONNECTION_CLOSED;
faultdef WS_CONNECTION_READ_ERROR;
faultdef WS_CONNECTION_WRITE_ERROR;
faultdef WS_CONNECTION_TRUNCATED;
faultdef WS_MESSAGE_TOO_LARGE;
faultdef WS_INVALID_UTF8;
faultdef WS_CLOSE_INVALID;
faultdef WS_CLOSE_REASON_TOO_LARGE;


// Constants

const sz WS_MAX_MESSAGE_PAYLOAD = 16 * 1024 * 1024;
const ulong WS_DEFAULT_READ_TIMEOUT_US = 0;

const ushort WS_CLOSE_NORMAL = 1000;
const ushort WS_CLOSE_GOING_AWAY = 1001;
const ushort WS_CLOSE_PROTOCOL_ERROR = 1002;
const ushort WS_CLOSE_UNSUPPORTED_DATA = 1003;
const ushort WS_CLOSE_INVALID_PAYLOAD = 1007;
const ushort WS_CLOSE_POLICY_VIOLATION = 1008;
const ushort WS_CLOSE_MESSAGE_TOO_BIG = 1009;
const ushort WS_CLOSE_INTERNAL_ERROR = 1011;


// Message

struct WebSocketMessage
{
    WebSocketOpcode opcode;
    char[] data;
    bool owns_data;
}

fn void WebSocketMessage.init(&self)
{
    self.opcode = WS_CONTINUATION;
    self.data = {};
    self.owns_data = false;
}

fn void WebSocketMessage.deinit(&self)
{
    if (self.owns_data && self.data.len > 0) {
        localmem.free(self.data);
    }

    self.init();
}

fn void WebSocketMessage.free(&self)
{
    self.deinit();
}

fn bool WebSocketMessage.is_text(&self) @inline
{
    return self.opcode == WS_TEXT;
}

fn bool WebSocketMessage.is_binary(&self) @inline
{
    return self.opcode == WS_BINARY;
}

fn String WebSocketMessage.text(&self) @inline
{
    return (String)self.data;
}


// Connection

struct WebSocketConnection
{
    aio::Stream* stream;

    char[] prebuffer;
    sz prebuffer_pos;
    bool owns_prebuffer;

    bool server_side;
    bool close_sent;
    bool close_received;
    bool closed;

    ushort close_code;

    ulong read_timeout_us;
    sz max_message_payload;

    WebSocketOpcode fragmented_opcode;
    DString fragmented;
    bool fragmented_active;
}

// Lifecycle

fn void WebSocketConnection.init(&self, aio::Stream* stream, bool server_side, char[] prebuffer = {}, bool owns_prebuffer = false)
{
    self.stream = stream;

    self.prebuffer = prebuffer;
    self.prebuffer_pos = 0;
    self.owns_prebuffer = owns_prebuffer;

    self.server_side = server_side;
    self.close_sent = false;
    self.close_received = false;
    self.closed = stream == null;

    self.close_code = 0;

    self.read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US;
    self.max_message_payload = WS_MAX_MESSAGE_PAYLOAD;

    self.fragmented_opcode = WS_CONTINUATION;
    self.fragmented.init(localmem);
    self.fragmented_active = false;
}

fn void WebSocketConnection.deinit(&self)
{
    self.fragmented.free();

    if (self.owns_prebuffer && self.prebuffer.len > 0) {
        localmem.free(self.prebuffer);
    }

    self.stream = null;

    self.prebuffer = {};
    self.prebuffer_pos = 0;
    self.owns_prebuffer = false;

    self.server_side = false;
    self.close_sent = false;
    self.close_received = false;
    self.closed = true;

    self.close_code = 0;

    self.read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US;
    self.max_message_payload = WS_MAX_MESSAGE_PAYLOAD;

    self.fragmented_opcode = WS_CONTINUATION;
    self.fragmented_active = false;
}

fn WebSocketConnection*? ws_connection_new(aio::Stream* stream, bool server_side)
{
    if (stream == null) return errno::E_INVALID_ARG~;

    WebSocketConnection* connection = localmem.alloc(WebSocketConnection)!;
    connection.init(stream, server_side);

    return connection;
}

fn void ws_connection_free(WebSocketConnection* connection)
{
    if (connection == null) return;

    connection.deinit();
    localmem.free(connection);
}

fn bool WebSocketConnection.is_open(&self) @inline
{
    return !self.closed && self.stream != null;
}

fn bool WebSocketConnection.is_closing(&self) @inline
{
    return self.close_sent || self.close_received;
}

fn bool WebSocketConnection.is_closed(&self) @inline
{
    return self.closed || self.stream == null;
}

fn void WebSocketConnection.set_read_timeout_us(&self, ulong timeout_us)
{
    self.read_timeout_us = timeout_us;
}

fn ulong WebSocketConnection.get_read_timeout_us(&self) @inline
{
    return self.read_timeout_us;
}

fn void WebSocketConnection.set_max_message_payload(&self, sz max_payload)
{
    if (max_payload <= 0 || max_payload > WS_MAX_MESSAGE_PAYLOAD) {
        self.max_message_payload = WS_MAX_MESSAGE_PAYLOAD;
        return;
    }

    self.max_message_payload = max_payload;
}

fn sz WebSocketConnection.get_max_message_payload(&self) @inline
{
    return self.max_message_payload;
}


// Low-level stream I/O

fn sz? WebSocketConnection.read_some(&self, char[] buffer)
{
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;
    if (buffer.len == 0) return 0;

    if (self.prebuffer_pos < self.prebuffer.len) {
        sz available = self.prebuffer.len - self.prebuffer_pos;
        sz count = available < buffer.len ? available : buffer.len;

        buffer[0:count] = self.prebuffer[self.prebuffer_pos:count];
        self.prebuffer_pos += count;

        return count;
    }

    sz? result;

    if (self.read_timeout_us > 0) {
        result = self.stream.read_timeout(buffer, self.read_timeout_us)!;
    } else {
        result = self.stream.read(buffer)!;
    }

    if (catch err = result) {
        if (err == aio::CLOSED) {
            self.closed = true;
            return WS_CONNECTION_TRUNCATED~;
        }

        return WS_CONNECTION_READ_ERROR~;
    }

    sz n = result;

    if (n <= 0) {
        self.closed = true;
        return WS_CONNECTION_TRUNCATED~;
    }

    return n;
}

fn void? WebSocketConnection.read_exact(&self, char[] buffer)
{
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;

    sz offset = 0;

    while (offset < buffer.len) {
        sz n = self.read_some(buffer[offset..])!;

        if (n <= 0) {
            self.closed = true;
            return WS_CONNECTION_TRUNCATED~;
        }

        offset += n;
    }
}

fn void? WebSocketConnection.write_bytes(&self, char[] data)
{
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;
    if (data.len == 0) return;

    if (catch err = self.stream.write_all(data)) {
        self.closed = true;
        return WS_CONNECTION_WRITE_ERROR~;
    }
}


// Mask generation

fn uint ws_random_mask() @local
{
    ulong value = aio::time_us();

    value ^= value << 13;
    value ^= value >> 7;
    value ^= value << 17;

    return (uint)(value ^ (value >> 32));
}

fn void ws_make_mask(char[4]* mask) @local
{
    uint value = ws_random_mask();

    (*mask)[0] = (char)(value >> 24);
    (*mask)[1] = (char)(value >> 16);
    (*mask)[2] = (char)(value >> 8);
    (*mask)[3] = (char)value;
}


// Frame writing

fn void? WebSocketConnection.write_frame(&self, WebSocketOpcode opcode, char[] payload, bool fin)
{
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;

    WebSocketFrame* frame = ws_frame_create(opcode, payload, fin)!;
    defer ws_frame_free(frame);

    char[] encoded;

    if (self.server_side) {
        encoded = ws_frame_encode(frame)!;
    } else {
        char[4] mask;
        ws_make_mask(&mask);

        encoded = ws_frame_encode_masked(frame, mask)!;
    }

    defer localmem.free(encoded);

    self.write_bytes(encoded)!;
}


// Frame reading helpers

fn ulong ws_connection_read_u64_be(char[8] data) @local
{
    ulong value = 0;

    for (sz i = 0; i < 8; i++) {
        value = (value << 8) | (ulong)data[i];
    }

    return value;
}

fn void ws_connection_apply_mask(char[] data, char[4] mask) @local
{
    for (sz i = 0; i < data.len; i++) {
        data[i] ^= mask[i & 3];
    }
}


// Frame reading

fn WebSocketFrame? WebSocketConnection.read_frame(&self)
{
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;

    char[2] base;
    self.read_exact(base[..])!;

    char first = base[0];
    char second = base[1];

    bool fin = (first & WS_FIN) != 0;
    bool rsv1 = (first & WS_RSV1) != 0;
    bool rsv2 = (first & WS_RSV2) != 0;
    bool rsv3 = (first & WS_RSV3) != 0;

    char opcode_value = first & 0x0F;

    switch (opcode_value) {
        case 0x0:
        case 0x1:
        case 0x2:
        case 0x8:
        case 0x9:
        case 0xA:
            break;

        default:
            return WS_FRAME_INVALID_OPCODE~;
    }

    if (rsv1 || rsv2 || rsv3) return WS_FRAME_INVALID~;

    WebSocketOpcode opcode = (WebSocketOpcode)opcode_value;
    bool masked = (second & WS_MASK) != 0;
    ulong payload_len = (ulong)(second & 0x7F);

    bool control = opcode == WS_CLOSE || opcode == WS_PING || opcode == WS_PONG;

    if (control && !fin) return WS_FRAME_INVALID_CONTROL~;

    if (payload_len == WS_PAYLOAD_16) {
        char[2] extended;
        self.read_exact(extended[..])!;

        payload_len = ((ulong)extended[0] << 8) | (ulong)extended[1];

        if (payload_len < 126) return WS_FRAME_INVALID~;
    } else if (payload_len == WS_PAYLOAD_64) {
        char[8] extended;
        self.read_exact(extended[..])!;

        if ((extended[0] & 0x80) != 0) return WS_FRAME_INVALID~;

        payload_len = ws_connection_read_u64_be(extended);

        if (payload_len <= 0xFFFF) return WS_FRAME_INVALID~;
    }

    if (control && payload_len > 125) return WS_FRAME_INVALID_CONTROL~;
    if (payload_len > (ulong)WS_MAX_FRAME_PAYLOAD) return WS_FRAME_TOO_LARGE~;

    if (self.server_side && !masked) return WS_FRAME_NOT_MASKED~;
    if (!self.server_side && masked) return WS_FRAME_UNEXPECTED_MASK~;

    char[4] mask = { 0, 0, 0, 0 };

    if (masked) {
        self.read_exact(mask[..])!;
    }

    WebSocketFrame frame;
    frame.init();

    frame.fin = fin;
    frame.rsv1 = rsv1;
    frame.rsv2 = rsv2;
    frame.rsv3 = rsv3;

    frame.opcode = opcode;

    frame.masked = masked;
    frame.mask_key[0] = mask[0];
    frame.mask_key[1] = mask[1];
    frame.mask_key[2] = mask[2];
    frame.mask_key[3] = mask[3];

    if (payload_len == 0) return frame;

    frame.payload = localmem.alloc_array(char, (sz)payload_len)!;
    frame.owns_payload = true;

    if (catch err = self.read_exact(frame.payload)) {
        frame.free();
        return err~;
    }

    if (masked) {
        ws_connection_apply_mask(frame.payload, mask);
    }

    return frame;
}


// UTF-8 validation

fn bool ws_is_continuation(char value) @inline
{
    return (value & 0xC0) == 0x80;
}

fn bool ws_utf8_valid(char[] data)
{
    sz i = 0;

    while (i < data.len) {
        char c = data[i];

        if (c <= 0x7F) {
            i++;
            continue;
        }

        if (c >= 0xC2 && c <= 0xDF) {
            if (i + 1 >= data.len) return false;
            if (!ws_is_continuation(data[i + 1])) return false;

            i += 2;
            continue;
        }

        if (c == 0xE0) {
            if (i + 2 >= data.len) return false;
            if (data[i + 1] < 0xA0 || data[i + 1] > 0xBF) return false;
            if (!ws_is_continuation(data[i + 2])) return false;

            i += 3;
            continue;
        }

        if (c >= 0xE1 && c <= 0xEC) {
            if (i + 2 >= data.len) return false;
            if (!ws_is_continuation(data[i + 1])) return false;
            if (!ws_is_continuation(data[i + 2])) return false;

            i += 3;
            continue;
        }

        if (c == 0xED) {
            if (i + 2 >= data.len) return false;
            if (data[i + 1] < 0x80 || data[i + 1] > 0x9F) return false;
            if (!ws_is_continuation(data[i + 2])) return false;

            i += 3;
            continue;
        }

        if (c >= 0xEE && c <= 0xEF) {
            if (i + 2 >= data.len) return false;
            if (!ws_is_continuation(data[i + 1])) return false;
            if (!ws_is_continuation(data[i + 2])) return false;

            i += 3;
            continue;
        }

        if (c == 0xF0) {
            if (i + 3 >= data.len) return false;
            if (data[i + 1] < 0x90 || data[i + 1] > 0xBF) return false;
            if (!ws_is_continuation(data[i + 2])) return false;
            if (!ws_is_continuation(data[i + 3])) return false;

            i += 4;
            continue;
        }

        if (c >= 0xF1 && c <= 0xF3) {
            if (i + 3 >= data.len) return false;
            if (!ws_is_continuation(data[i + 1])) return false;
            if (!ws_is_continuation(data[i + 2])) return false;
            if (!ws_is_continuation(data[i + 3])) return false;

            i += 4;
            continue;
        }

        if (c == 0xF4) {
            if (i + 3 >= data.len) return false;
            if (data[i + 1] < 0x80 || data[i + 1] > 0x8F) return false;
            if (!ws_is_continuation(data[i + 2])) return false;
            if (!ws_is_continuation(data[i + 3])) return false;

            i += 4;
            continue;
        }

        return false;
    }

    return true;
}


// Close payload

fn bool ws_close_code_valid(ushort code)
{
    if (code < 1000 || code >= 5000) return false;

    if (code >= 1000 && code <= 1015) {
        return code != 1004 &&
               code != 1005 &&
               code != 1006 &&
               code != 1015;
    }

    return code >= 3000;
}

fn ushort ws_close_code(char[] payload)
{
    if (payload.len < 2) return 0;

    return ((ushort)payload[0] << 8) |
           (ushort)payload[1];
}

fn void? ws_validate_close_payload(char[] payload)
{
    if (payload.len == 0) return;
    if (payload.len == 1) return WS_CLOSE_INVALID~;

    ushort code = ws_close_code(payload);

    if (!ws_close_code_valid(code)) {
        return WS_CLOSE_INVALID~;
    }

    if (payload.len > 2 && !ws_utf8_valid(payload[2..])) {
        return WS_INVALID_UTF8~;
    }
}


// Sending

fn void? WebSocketConnection.send_text(&self, String text)
{
    if (!ws_utf8_valid((char[])text)) return WS_INVALID_UTF8~;

    self.write_frame(WS_TEXT, (char[])text, true)!;
}

fn void? WebSocketConnection.send_binary(&self, char[] data)
{
    self.write_frame(WS_BINARY, data, true)!;
}

fn void? WebSocketConnection.send_ping(&self, char[] data = {})
{
    if (data.len > 125) return WS_FRAME_INVALID_CONTROL~;

    self.write_frame(WS_PING, data, true)!;
}

fn void? WebSocketConnection.send_pong(&self, char[] data = {})
{
    if (data.len > 125) return WS_FRAME_INVALID_CONTROL~;

    self.write_frame(WS_PONG, data, true)!;
}

fn void? WebSocketConnection.send_close(&self, ushort code = WS_CLOSE_NORMAL, String reason = "")
{
    if (self.close_sent) return;
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;

    if (code == 0) {
        if (reason.len > 0) return WS_CLOSE_INVALID~;

        self.write_frame(WS_CLOSE, {}, true)!;
        self.close_sent = true;
        self.close_code = 0;

        return;
    }

    if (!ws_close_code_valid(code)) return WS_CLOSE_INVALID~;
    if (!ws_utf8_valid((char[])reason)) return WS_INVALID_UTF8~;
    if (reason.len > 123) return WS_CLOSE_REASON_TOO_LARGE~;

    char[125] payload;

    payload[0] = (char)(code >> 8);
    payload[1] = (char)code;

    if (reason.len > 0) {
        payload[2:reason.len] = reason[..];
    }

    self.write_frame(WS_CLOSE, payload[0:reason.len + 2], true)!;

    self.close_sent = true;
    self.close_code = code;
}


// Fragmented message helpers

fn void WebSocketConnection.reset_fragmented(&self)
{
    self.fragmented.clear();
    self.fragmented_opcode = WS_CONTINUATION;
    self.fragmented_active = false;
}

fn void? WebSocketConnection.append_fragment(&self, char[] payload)
{
    if (payload.len > self.max_message_payload - self.fragmented.len()) {
        return WS_MESSAGE_TOO_LARGE~;
    }

    self.fragmented.append(payload);
}

fn WebSocketMessage? WebSocketConnection.finish_fragmented(&self)
{
    WebSocketOpcode opcode = self.fragmented_opcode;
    char[] data = self.fragmented.str_view();

    if (opcode == WS_TEXT && !ws_utf8_valid(data)) {
        self.reset_fragmented();
        return WS_INVALID_UTF8~;
    }

    WebSocketMessage message;
    message.init();

    message.opcode = opcode;

    if (data.len > 0) {
        message.data = bytes_clone(data)!;
        message.owns_data = true;
    }

    self.reset_fragmented();

    return message;
}


// Receiving

fn WebSocketMessage? WebSocketConnection.receive(&self)
{
    if (!self.is_open()) return WS_CONNECTION_CLOSED~;

    while (self.is_open()) {
        WebSocketFrame frame = self.read_frame()!;
        defer frame.free();

        switch (frame.opcode) {
            case WS_PING:
                self.send_pong(frame.payload)!;
                continue;

            case WS_PONG:
                continue;

            case WS_CLOSE:
                if (frame.payload.len == 1) {
                    if (!self.close_sent) {
                        self.send_close(WS_CLOSE_PROTOCOL_ERROR, "Invalid close frame")!!;
                    }

                    self.close_received = true;
                    self.closed = true;

                    return WS_CLOSE_INVALID~;
                }

                if (frame.payload.len >= 2) {
                    ushort code = ws_close_code(frame.payload);

                    if (!ws_close_code_valid(code)) {
                        if (!self.close_sent) {
                            self.send_close(WS_CLOSE_PROTOCOL_ERROR, "Invalid close code")!!;
                        }

                        self.close_received = true;
                        self.closed = true;

                        return WS_CLOSE_INVALID~;
                    }

                    if (frame.payload.len > 2 && !ws_utf8_valid(frame.payload[2..])) {
                        if (!self.close_sent) {
                            self.send_close(WS_CLOSE_INVALID_PAYLOAD, "Invalid UTF-8")!!;
                        }

                        self.close_received = true;
                        self.closed = true;

                        return WS_INVALID_UTF8~;
                    }

                    self.close_code = code;
                } else {
                    self.close_code = 0;
                }

                self.close_received = true;

                if (!self.close_sent) {
                    if (frame.payload.len >= 2) {
                        ushort code = ws_close_code(frame.payload);
                        String reason = frame.payload.len > 2 ? (String)frame.payload[2..] : "";

                        self.send_close(code, reason)!;
                    } else {
                        self.send_close(0, "")!;
                    }
                }

                self.closed = true;
                return WS_CONNECTION_CLOSED~;

            case WS_TEXT:
            case WS_BINARY:
                if (self.fragmented_active) {
                    if (!self.close_sent) {
                        self.send_close(WS_CLOSE_PROTOCOL_ERROR, "Unexpected data frame")!!;
                    }

                    self.closed = true;
                    return WS_FRAME_INVALID~;
                }

                if (frame.fin) {
                    if (frame.payload.len > self.max_message_payload) {
                        if (!self.close_sent) {
                            self.send_close(WS_CLOSE_MESSAGE_TOO_BIG, "Message too large")!!;
                        }

                        return WS_MESSAGE_TOO_LARGE~;
                    }

                    if (frame.opcode == WS_TEXT && !ws_utf8_valid(frame.payload)) {
                        if (!self.close_sent) {
                            self.send_close(WS_CLOSE_INVALID_PAYLOAD, "Invalid UTF-8")!!;
                        }

                        return WS_INVALID_UTF8~;
                    }

                    WebSocketMessage message;
                    message.init();

                    message.opcode = frame.opcode;

                    if (frame.payload.len > 0) {
                        message.data = bytes_clone(frame.payload)!;
                        message.owns_data = true;
                    }

                    return message;
                }

                self.fragmented_opcode = frame.opcode;
                self.fragmented_active = true;
                self.fragmented.clear();

                if (catch err = self.append_fragment(frame.payload)) {
                    self.reset_fragmented();

                    if (!self.close_sent) {
                        self.send_close(WS_CLOSE_MESSAGE_TOO_BIG, "Message too large")!!;
                    }

                    return err~;
                }

                continue;

            case WS_CONTINUATION:
                if (!self.fragmented_active) {
                    if (!self.close_sent) {
                        self.send_close(WS_CLOSE_PROTOCOL_ERROR, "Unexpected continuation")!!;
                    }

                    self.closed = true;
                    return WS_FRAME_INVALID~;
                }

                if (catch err = self.append_fragment(frame.payload)) {
                    self.reset_fragmented();

                    if (!self.close_sent) {
                        self.send_close(WS_CLOSE_MESSAGE_TOO_BIG, "Message too large")!!;
                    }

                    return err~;
                }

                if (frame.fin) {
                    return self.finish_fragmented();
                }

                continue;

            default:
                if (!self.close_sent) {
                    self.send_close(WS_CLOSE_PROTOCOL_ERROR, "Invalid opcode")!!;
                }

                self.closed = true;
                return WS_FRAME_INVALID_OPCODE~;
        }
    }

    return WS_CONNECTION_CLOSED~;
}


// Shutdown

fn void? WebSocketConnection.close(&self, ushort code = WS_CLOSE_NORMAL, String reason = "")
{
    if (self.closed) return;

    if (!self.close_sent) {
        self.send_close(code, reason)!;
    }

    if (self.stream != null) {
        self.stream.close();
    }

    self.closed = true;
}

fn void WebSocketConnection.abort(&self)
{
    if (self.stream != null) {
        self.stream.close();
    }

    self.closed = true;
}

// eof