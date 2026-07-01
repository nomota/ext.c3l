// ws_frame.c3

// WebSocket frame encoding and decoding.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::mem;


// Faults

faultdef WS_FRAME_INCOMPLETE;
faultdef WS_FRAME_TOO_LARGE;
faultdef WS_FRAME_INVALID;
faultdef WS_FRAME_NOT_MASKED;
faultdef WS_FRAME_UNEXPECTED_MASK;
faultdef WS_FRAME_INVALID_OPCODE;
faultdef WS_FRAME_INVALID_CONTROL;


// Constants

const sz WS_MAX_FRAME_PAYLOAD = 16 * 1024 * 1024;

const char WS_FIN = 0x80;
const char WS_RSV1 = 0x40;
const char WS_RSV2 = 0x20;
const char WS_RSV3 = 0x10;
const char WS_MASK = 0x80;

const char WS_PAYLOAD_16 = 126;
const char WS_PAYLOAD_64 = 127;


// Opcodes
alias WebSocketOpcode = char;

const WS_CONTINUATION = 0x0;
const WS_TEXT = 0x1;
const WS_BINARY = 0x2;
const WS_CLOSE = 0x8;
const WS_PING = 0x9;
const WS_PONG = 0xA;


// Frame

struct WebSocketFrame
{
    bool fin;
    bool rsv1;
    bool rsv2;
    bool rsv3;

    WebSocketOpcode opcode;

    bool masked;
    char[4] mask_key;

    char[] payload;
    bool owns_payload;
}


// Lifecycle

fn void WebSocketFrame.init(&self)
{
    self.fin = true;
    self.rsv1 = false;
    self.rsv2 = false;
    self.rsv3 = false;

    self.opcode = WS_CONTINUATION;

    self.masked = false;
    self.mask_key[0] = 0;
    self.mask_key[1] = 0;
    self.mask_key[2] = 0;
    self.mask_key[3] = 0;

    self.payload = {};
    self.owns_payload = false;
}

fn void WebSocketFrame.deinit(&self)
{
    if (self.owns_payload && self.payload.len > 0) {
        localmem.free(self.payload);
    }

    self.init();
}

fn void WebSocketFrame.free(&self)
{
    self.deinit();
}

fn WebSocketFrame*? ws_frame_new()
{
    WebSocketFrame* frame = localmem.alloc(WebSocketFrame)!;
    frame.init();

    return frame;
}

fn void ws_frame_free(WebSocketFrame* frame)
{
    if (frame == null) return;

    frame.deinit();
    localmem.free(frame);
}


// Opcode helpers

fn bool ws_opcode_valid(char value) @local
{
    switch (value) {
        case 0x0:
        case 0x1:
        case 0x2:
        case 0x8:
        case 0x9:
        case 0xA:
            return true;

        default:
            return false;
    }
}

fn bool ws_opcode_is_control(WebSocketOpcode opcode) @inline
{
    return ((char)opcode & 0x08) != 0;
}

fn bool ws_opcode_is_data(WebSocketOpcode opcode) @inline
{
    return opcode == WS_CONTINUATION ||
           opcode == WS_TEXT ||
           opcode == WS_BINARY;
}

fn bool WebSocketFrame.is_control(&self) @inline
{
    return ws_opcode_is_control(self.opcode);
}

fn bool WebSocketFrame.is_data(&self) @inline
{
    return ws_opcode_is_data(self.opcode);
}


// Integer helpers

fn ulong ws_read_u16(char[] data, sz offset) @local
{
    return ((ulong)data[offset] << 8) |
           (ulong)data[offset + 1];
}

fn ulong ws_read_u64(char[] data, sz offset) @local
{
    ulong value = 0;

    for (sz i = 0; i < 8; i++) {
        value = (value << 8) | (ulong)data[offset + i];
    }

    return value;
}

fn void ws_write_u16(char[] data, sz offset, ulong value) @local
{
    data[offset] = (char)(value >> 8);
    data[offset + 1] = (char)value;
}

fn void ws_write_u64(char[] data, sz offset, ulong value) @local
{
    for (sz i = 0; i < 8; i++) {
        sz shift = (7 - i) * 8;
        data[offset + i] = (char)(value >> shift);
    }
}


// Masking

fn void ws_frame_apply_mask(char[] data, char[4] mask_key) @local
{
    for (sz i = 0; i < data.len; i++) {
        data[i] ^= mask_key[i & 3];
    }
}


// Validation

fn void? WebSocketFrame.validate(&self)
{
    if (!ws_opcode_valid((char)self.opcode)) {
        return WS_FRAME_INVALID_OPCODE~;
    }

    if (self.rsv1 || self.rsv2 || self.rsv3) {
        return WS_FRAME_INVALID~;
    }

    if (self.payload.len > WS_MAX_FRAME_PAYLOAD) {
        return WS_FRAME_TOO_LARGE~;
    }

    if (self.is_control()) {
        if (!self.fin) return WS_FRAME_INVALID_CONTROL~;
        if (self.payload.len > 125) return WS_FRAME_INVALID_CONTROL~;
    }
}


// Header size

fn sz? ws_frame_header_len(sz payload_len, bool masked)
{
    if (payload_len < 0) return WS_FRAME_INVALID~;
    if (payload_len > WS_MAX_FRAME_PAYLOAD) return WS_FRAME_TOO_LARGE~;

    sz header_len = 2;

    if (payload_len > 125 && payload_len <= 0xFFFF) {
        header_len += 2;
    } else if (payload_len > 0xFFFF) {
        header_len += 8;
    }

    if (masked) header_len += 4;

    return header_len;
}


// Expected frame size

fn sz? ws_frame_expected_len(char[] data)
{
    if (data.len < 2) return WS_FRAME_INCOMPLETE~;

    bool masked = (data[1] & WS_MASK) != 0;
    ulong payload_len = (ulong)(data[1] & 0x7F);
    sz offset = 2;

    if (payload_len == WS_PAYLOAD_16) {
        if (data.len < offset + 2) return WS_FRAME_INCOMPLETE~;

        payload_len = ws_read_u16(data, offset);
        offset += 2;

        if (payload_len < 126) return WS_FRAME_INVALID~;
    } else if (payload_len == WS_PAYLOAD_64) {
        if (data.len < offset + 8) return WS_FRAME_INCOMPLETE~;

        payload_len = ws_read_u64(data, offset);
        offset += 8;

        if ((payload_len & 0x8000000000000000) != 0) {
            return WS_FRAME_INVALID~;
        }

        if (payload_len <= 0xFFFF) return WS_FRAME_INVALID~;
    }

    if (payload_len > (ulong)WS_MAX_FRAME_PAYLOAD) {
        return WS_FRAME_TOO_LARGE~;
    }

    if (masked) offset += 4;

    ulong total_len = (ulong)offset + payload_len;

    if (total_len > (ulong)sz::max) {
        return WS_FRAME_TOO_LARGE~;
    }

    return (sz)total_len;
}

fn bool? ws_frame_complete(char[] data)
{
    sz expected_len = ws_frame_expected_len(data)!;
    return data.len >= expected_len;
}


// Decoding

fn WebSocketFrame*? ws_frame_decode(char[] data, bool require_masked, sz* consumed)
{
    if (consumed != null) *consumed = 0;
    if (data.len < 2) return WS_FRAME_INCOMPLETE~;

    char first = data[0];
    char second = data[1];

    bool fin = (first & WS_FIN) != 0;
    bool rsv1 = (first & WS_RSV1) != 0;
    bool rsv2 = (first & WS_RSV2) != 0;
    bool rsv3 = (first & WS_RSV3) != 0;

    char opcode_value = first & 0x0F;

    if (!ws_opcode_valid(opcode_value)) {
        return WS_FRAME_INVALID_OPCODE~;
    }

    if (rsv1 || rsv2 || rsv3) {
        return WS_FRAME_INVALID~;
    }

    bool masked = (second & WS_MASK) != 0;

    if (require_masked && !masked) {
        return WS_FRAME_NOT_MASKED~;
    }

    ulong payload_len = (ulong)(second & 0x7F);
    sz offset = 2;

    if (payload_len == WS_PAYLOAD_16) {
        if (data.len < offset + 2) return WS_FRAME_INCOMPLETE~;

        payload_len = ws_read_u16(data, offset);
        offset += 2;

        if (payload_len < 126) return WS_FRAME_INVALID~;
    } else if (payload_len == WS_PAYLOAD_64) {
        if (data.len < offset + 8) return WS_FRAME_INCOMPLETE~;

        payload_len = ws_read_u64(data, offset);
        offset += 8;

        if ((payload_len & 0x8000000000000000) != 0) {
            return WS_FRAME_INVALID~;
        }

        if (payload_len <= 0xFFFF) return WS_FRAME_INVALID~;
    }

    if (payload_len > (ulong)WS_MAX_FRAME_PAYLOAD) {
        return WS_FRAME_TOO_LARGE~;
    }

    char[4] mask_key = { 0, 0, 0, 0 };

    if (masked) {
        if (data.len < offset + 4) return WS_FRAME_INCOMPLETE~;

        mask_key[0] = data[offset];
        mask_key[1] = data[offset + 1];
        mask_key[2] = data[offset + 2];
        mask_key[3] = data[offset + 3];

        offset += 4;
    }

    ulong total_len = (ulong)offset + payload_len;

    if (total_len > (ulong)sz::max) {
        return WS_FRAME_TOO_LARGE~;
    }

    if (total_len > (ulong)data.len) {
        return WS_FRAME_INCOMPLETE~;
    }

    WebSocketOpcode opcode = (WebSocketOpcode)opcode_value;

    if (ws_opcode_is_control(opcode)) {
        if (!fin) return WS_FRAME_INVALID_CONTROL~;
        if (payload_len > 125) return WS_FRAME_INVALID_CONTROL~;
    }

    WebSocketFrame* frame = ws_frame_new()!;
    defer catch ws_frame_free(frame);

    frame.fin = fin;
    frame.rsv1 = rsv1;
    frame.rsv2 = rsv2;
    frame.rsv3 = rsv3;

    frame.opcode = opcode;

    frame.masked = masked;
    frame.mask_key[0] = mask_key[0];
    frame.mask_key[1] = mask_key[1];
    frame.mask_key[2] = mask_key[2];
    frame.mask_key[3] = mask_key[3];

    if (payload_len > 0) {
        frame.payload = localmem.alloc_array(char, (sz)payload_len)!;
        frame.owns_payload = true;

        frame.payload[..] = data[offset:(sz)payload_len];

        if (masked) {
            ws_frame_apply_mask(frame.payload, frame.mask_key);
        }
    }

    if (consumed != null) *consumed = (sz)total_len;

    return frame;
}

fn WebSocketFrame*? ws_frame_decode_client(char[] data, sz* consumed)
{
    return ws_frame_decode(data, true, consumed);
}

fn WebSocketFrame*? ws_frame_decode_server(char[] data, sz* consumed)
{
    WebSocketFrame* frame = ws_frame_decode(data, false, consumed)!;

    if (frame.masked) {
        ws_frame_free(frame);
        return WS_FRAME_UNEXPECTED_MASK~;
    }

    return frame;
}


// Encoding

fn char[]? ws_frame_encode_with_mask(WebSocketFrame* frame, bool masked, char[4] mask_key)
{
    if (frame == null) return WS_FRAME_INVALID~;

    frame.validate()!;

    sz payload_len = frame.payload.len;
    sz header_len = ws_frame_header_len(payload_len, masked)!;
    sz total_len = header_len + payload_len;

    char[] output = localmem.alloc_array(char, total_len)!;
    defer catch localmem.free(output);

    char first = (char)frame.opcode;

    if (frame.fin) first |= WS_FIN;
    if (frame.rsv1) first |= WS_RSV1;
    if (frame.rsv2) first |= WS_RSV2;
    if (frame.rsv3) first |= WS_RSV3;

    output[0] = first;

    sz offset = 2;

    if (payload_len <= 125) {
        output[1] = (char)payload_len;
    } else if (payload_len <= 0xFFFF) {
        output[1] = WS_PAYLOAD_16;
        ws_write_u16(output, offset, (ulong)payload_len);
        offset += 2;
    } else {
        output[1] = WS_PAYLOAD_64;
        ws_write_u64(output, offset, (ulong)payload_len);
        offset += 8;
    }

    if (masked) {
        output[1] |= WS_MASK;

        output[offset] = mask_key[0];
        output[offset + 1] = mask_key[1];
        output[offset + 2] = mask_key[2];
        output[offset + 3] = mask_key[3];

        offset += 4;
    }

    if (payload_len > 0) {
        output[offset:payload_len] = frame.payload[..];

        if (masked) {
            ws_frame_apply_mask(output[offset:payload_len], mask_key);
        }
    }

    return output;
}

fn char[]? ws_frame_encode(WebSocketFrame* frame)
{
    char[4] mask_key = { 0, 0, 0, 0 };
    return ws_frame_encode_with_mask(frame, false, mask_key);
}

fn char[]? ws_frame_encode_masked(WebSocketFrame* frame, char[4] mask_key)
{
    return ws_frame_encode_with_mask(frame, true, mask_key);
}


// Frame construction

fn WebSocketFrame*? ws_frame_create(WebSocketOpcode opcode, char[] payload, bool fin)
{
    if (payload.len > WS_MAX_FRAME_PAYLOAD) {
        return WS_FRAME_TOO_LARGE~;
    }

    WebSocketFrame* frame = ws_frame_new()!;
    defer catch ws_frame_free(frame);

    frame.opcode = opcode;
    frame.fin = fin;

    if (payload.len > 0) {
        frame.payload = bytes_clone(payload)!;
        frame.owns_payload = true;
    }

    frame.validate()!;

    return frame;
}

fn WebSocketFrame*? ws_text_frame(String text)
{
    return ws_frame_create(WS_TEXT, (char[])text, true);
}

fn WebSocketFrame*? ws_binary_frame(char[] payload)
{
    return ws_frame_create(WS_BINARY, payload, true);
}

fn WebSocketFrame*? ws_continuation_frame(char[] payload, bool fin)
{
    return ws_frame_create(WS_CONTINUATION, payload, fin);
}

fn WebSocketFrame*? ws_ping_frame(char[] payload)
{
    return ws_frame_create(WS_PING, payload, true);
}

fn WebSocketFrame*? ws_pong_frame(char[] payload)
{
    return ws_frame_create(WS_PONG, payload, true);
}

fn WebSocketFrame*? ws_close_frame(char[] payload)
{
    return ws_frame_create(WS_CLOSE, payload, true);
}

// eof