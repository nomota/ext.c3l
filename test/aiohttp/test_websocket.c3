// test_websocket.c3

// WebSocket frame, handshake, close, and UTF-8 tests.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::websocket;

import std::io;
import ext::aio::http;
import ext::mem;
import ext::debug;

// Test helpers

fn void assert_bytes(char[] actual, char[] expected, String message)
{
    @assert(actual.len == expected.len, message);

    for (sz i = 0; i < actual.len; i++) {
        @assert(actual[i] == expected[i], message);
    }
}

fn void assert_string(String actual, String expected, String message)
{
    @assert(actual == expected, message);
}

fn Request* parse_request(String raw)
{
    return http::request_parse((char[])raw)!!;
}


// Accept key

fn void test_accept_key()
{
    String accept = http::ws_accept_key("dGhlIHNhbXBsZSBub25jZQ==")!!;
    defer http::localmem.free(accept);

    assert_string(
        accept,
        "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
        "RFC 6455 accept key mismatch"
    );
}


// Handshake request

fn void test_handshake_request()
{
    String raw =
        "GET /chat HTTP/1.1\r\n"
        "Host: server.example.com\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Origin: http://example.com\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_websocket_upgrade(), "valid WebSocket upgrade not detected");

    String key = req.websocket_key()!!;

    assert_string(
        key,
        "dGhlIHNhbXBsZSBub25jZQ==",
        "WebSocket key mismatch"
    );
}

fn void test_handshake_connection_tokens()
{
    String raw =
        "GET /ws HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: WebSocket\r\n"
        "Connection: keep-alive, Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_websocket_upgrade(), "Connection token list not accepted");
    req.validate_websocket_upgrade()!!;
}

fn void test_handshake_invalid_method()
{
    String raw =
        "POST /ws HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(!req.is_websocket_upgrade(), "POST accepted as WebSocket upgrade");

    if (catch err = req.validate_websocket_upgrade()) {
        @assert(err == http::WS_BAD_HANDSHAKE, "wrong invalid-method fault");
        return;
    }

    @assert(false, "invalid WebSocket method accepted");
}

fn void test_handshake_invalid_version()
{
    String raw =
        "GET /ws HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 12\r\n"
        "\r\n";

    Request* req = parse_request(raw);
    defer http::request_free(req);

    if (catch err = req.validate_websocket_upgrade()) {
        @assert(err == http::WS_UNSUPPORTED_VERSION, "wrong version fault");
        return;
    }

    @assert(false, "unsupported WebSocket version accepted");
}

fn void test_handshake_invalid_key()
{
    String raw =
        "GET /ws HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: invalid\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    Request* req = parse_request(raw);
    defer http::request_free(req);

    if (catch err = req.validate_websocket_upgrade()) {
        @assert(err == http::WS_INVALID_KEY, "wrong invalid-key fault");
        return;
    }

    @assert(false, "invalid WebSocket key accepted");
}


// Handshake response

fn void test_handshake_response()
{
    String raw =
        "GET /chat HTTP/1.1\r\n"
        "Host: server.example.com\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    Request* req = parse_request(raw);
    defer http::request_free(req);

    Response* res = http::websocket_handshake_response(req)!!;
    defer http::response_free(res);

    @assert(res.status == 101, "handshake status is not 101");

    String upgrade = res.headers.get("Upgrade") ?? "";
    String connection = res.headers.get("Connection") ?? "";
    String accept = res.headers.get("Sec-WebSocket-Accept") ?? "";

    @assert(http::str_iequals(upgrade, "websocket"), "Upgrade response header mismatch");
    @assert(http::str_iequals(connection, "Upgrade"), "Connection response header mismatch");

    assert_string(
        accept,
        "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
        "Sec-WebSocket-Accept mismatch"
    );

    String wire = res.serialize_headers_only(true)!!;
    defer http::localmem.free(wire);

    @assert(wire.contains("HTTP/1.1 101 Switching Protocols\r\n"), "missing 101 status line");
    @assert(wire.contains("Upgrade: websocket\r\n"), "missing Upgrade header");
    @assert(wire.contains("Connection: Upgrade\r\n"), "missing Connection header");
    @assert(wire.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"), "missing accept header");
    @assert(!wire.contains("Content-Length:"), "101 response contains Content-Length");
    @assert(!wire.contains("Transfer-Encoding:"), "101 response contains Transfer-Encoding");
}

fn void test_version_response()
{
    Response* res = http::websocket_version_response()!!;
    defer http::response_free(res);

    @assert(res.status == 426, "version response status mismatch");

    String version = res.headers.get("Sec-WebSocket-Version") ?? "";
    assert_string(version, "13", "version response header mismatch");
}


// Short unmasked frame

fn void test_short_server_frame()
{
    WebSocketFrame* frame = http::ws_text_frame("Hello")!!;
    defer http::ws_frame_free(frame);

    char[] encoded = http::ws_frame_encode(frame)!!;
    defer  http::localmem.free(encoded);

    @assert(encoded.len == 7, "short frame encoded length mismatch");
    @assert(encoded[0] == (http::WS_FIN | (char)http::WS_TEXT), "short frame first byte mismatch");
    @assert(encoded[1] == 5, "short frame payload length mismatch");

    assert_bytes(encoded[2:5], (char[])"Hello", "short frame payload mismatch");

    sz expected = http::ws_frame_expected_len(encoded)!!;
    @assert(expected == encoded.len, "short frame expected length mismatch");

    bool complete = http::ws_frame_complete(encoded)!!;
    @assert(complete, "complete short frame reported incomplete");

    sz consumed = 0;
    WebSocketFrame* decoded = http::ws_frame_decode_server(encoded, &consumed)!!;
    defer http::ws_frame_free(decoded);

    @assert(consumed == encoded.len, "short frame consumed length mismatch");
    @assert(decoded.fin, "short frame FIN missing");
    @assert(decoded.opcode == http::WS_TEXT, "short frame opcode mismatch");
    @assert(!decoded.masked, "server frame unexpectedly masked");

    assert_bytes(decoded.payload, (char[])"Hello", "decoded short payload mismatch");
}


// Masked client frame

fn void test_masked_client_frame()
{
    WebSocketFrame* frame = http::ws_text_frame("Hello")!!;
    defer http::ws_frame_free(frame);

    char[4] mask = { 0x37, 0xFA, 0x21, 0x3D };

    char[] encoded = http::ws_frame_encode_masked(frame, mask)!!;
    defer  http::localmem.free(encoded);

    @assert(encoded.len == 11, "masked frame encoded length mismatch");
    @assert(encoded[0] == 0x81, "masked frame first byte mismatch");
    @assert(encoded[1] == 0x85, "masked frame second byte mismatch");

    @assert(encoded[2] == 0x37, "mask byte 0 mismatch");
    @assert(encoded[3] == 0xFA, "mask byte 1 mismatch");
    @assert(encoded[4] == 0x21, "mask byte 2 mismatch");
    @assert(encoded[5] == 0x3D, "mask byte 3 mismatch");

    char[5] expected_masked = {
        0x7F,
        0x9F,
        0x4D,
        0x51,
        0x58,
    };

    assert_bytes(encoded[6:5], expected_masked[..], "RFC masked payload mismatch");

    sz consumed = 0;
    WebSocketFrame* decoded = http::ws_frame_decode_client(encoded, &consumed)!!;
    defer http::ws_frame_free(decoded);

    @assert(consumed == encoded.len, "masked frame consumed length mismatch");
    @assert(decoded.masked, "client frame mask flag missing");
    @assert(decoded.opcode == http::WS_TEXT, "masked frame opcode mismatch");

    assert_bytes(decoded.payload, (char[])"Hello", "masked frame decode mismatch");
}


// Direction validation

fn void test_server_frame_rejects_mask()
{
    WebSocketFrame* frame = http::ws_text_frame("masked")!!;
    defer http::ws_frame_free(frame);

    char[4] mask = { 1, 2, 3, 4 };

    char[] encoded = http::ws_frame_encode_masked(frame, mask)!!;
    defer  http::localmem.free(encoded);

    sz consumed = 0;
    WebSocketFrame*? decoded = http::ws_frame_decode_server(encoded, &consumed);

    if (catch err = decoded) {
        @assert(err == http::WS_FRAME_UNEXPECTED_MASK, "wrong masked-server-frame fault");
        return;
    }

    http::ws_frame_free(decoded);
    @assert(false, "masked server frame accepted");
}

fn void test_client_frame_requires_mask()
{
    WebSocketFrame* frame = http::ws_text_frame("plain")!!;
    defer http::ws_frame_free(frame);

    char[] encoded = http::ws_frame_encode(frame)!!;
    defer  http::localmem.free(encoded);

    sz consumed = 0;
    WebSocketFrame*? decoded = http::ws_frame_decode_client(encoded, &consumed);

    if (catch err = decoded) {
        @assert(err == http::WS_FRAME_NOT_MASKED, "wrong unmasked-client-frame fault");
        return;
    }

    http::ws_frame_free(decoded);
    @assert(false, "unmasked client frame accepted");
}


// Extended payload lengths

fn void test_payload_126()
{
    char[126] payload;

    for (sz i = 0; i < payload.len; i++) {
        payload[i] = (char)(i & 0xFF);
    }

    WebSocketFrame* frame = http::ws_binary_frame(payload[..])!!;
    defer http::ws_frame_free(frame);

    char[] encoded = http::ws_frame_encode(frame)!!;
    defer  http::localmem.free(encoded);

    @assert(encoded.len == 130, "126-byte frame length mismatch");
    @assert(encoded[1] == http::WS_PAYLOAD_16, "126-byte frame marker mismatch");
    @assert(encoded[2] == 0, "126-byte high length mismatch");
    @assert(encoded[3] == 126, "126-byte low length mismatch");

    sz consumed = 0;
    WebSocketFrame* decoded = http::ws_frame_decode_server(encoded, &consumed)!!;
    defer http::ws_frame_free(decoded);

    @assert(consumed == encoded.len, "126-byte consumed length mismatch");
    @assert(decoded.payload.len == payload.len, "126-byte payload length mismatch");

    assert_bytes(decoded.payload, payload[..], "126-byte payload mismatch");
}

fn void test_payload_65536()
{
    const sz SIZE = 65536;

    char[] payload = http::localmem.alloc_array(char, SIZE)!!;
    defer  http::localmem.free(payload);

    for (sz i = 0; i < payload.len; i++) {
        payload[i] = (char)(i & 0xFF);
    }

    WebSocketFrame* frame = http::ws_binary_frame(payload)!!;
    defer http::ws_frame_free(frame);

    char[] encoded = http::ws_frame_encode(frame)!!;
    defer  http::localmem.free(encoded);

    @assert(encoded.len == SIZE + 10, "64-bit frame encoded length mismatch");
    @assert(encoded[1] == http::WS_PAYLOAD_64, "64-bit frame marker mismatch");

    @assert(encoded[2] == 0, "64-bit length byte 0 mismatch");
    @assert(encoded[3] == 0, "64-bit length byte 1 mismatch");
    @assert(encoded[4] == 0, "64-bit length byte 2 mismatch");
    @assert(encoded[5] == 0, "64-bit length byte 3 mismatch");
    @assert(encoded[6] == 0, "64-bit length byte 4 mismatch");
    @assert(encoded[7] == 1, "64-bit length byte 5 mismatch");
    @assert(encoded[8] == 0, "64-bit length byte 6 mismatch");
    @assert(encoded[9] == 0, "64-bit length byte 7 mismatch");

    sz consumed = 0;
    WebSocketFrame* decoded = http::ws_frame_decode_server(encoded, &consumed)!!;
    defer http::ws_frame_free(decoded);

    @assert(consumed == encoded.len, "64-bit frame consumed length mismatch");
    @assert(decoded.payload.len == SIZE, "64-bit payload length mismatch");

    assert_bytes(decoded.payload, payload, "64-bit payload mismatch");
}


// Fragmentation

fn void test_fragment_frames()
{
    WebSocketFrame* first = http::ws_frame_create(http::WS_TEXT, (char[])"Hel", false)!!;
    defer http::ws_frame_free(first);

    WebSocketFrame* second = http::ws_continuation_frame((char[])"lo", true)!!;
    defer http::ws_frame_free(second);

    @assert(!first.fin, "first fragment unexpectedly final");
    @assert(first.opcode == http::WS_TEXT, "first fragment opcode mismatch");

    @assert(second.fin, "last fragment FIN missing");
    @assert(second.opcode == http::WS_CONTINUATION, "continuation opcode mismatch");

    char[] first_encoded = http::ws_frame_encode(first)!!;
    defer  http::localmem.free(first_encoded);

    char[] second_encoded = http::ws_frame_encode(second)!!;
    defer  http::localmem.free(second_encoded);

    WebSocketFrame* first_decoded = http::ws_frame_decode_server(first_encoded, null)!!;
    defer http::ws_frame_free(first_decoded);

    WebSocketFrame* second_decoded = http::ws_frame_decode_server(second_encoded, null)!!;
    defer http::ws_frame_free(second_decoded);

    assert_bytes(first_decoded.payload, (char[])"Hel", "first fragment payload mismatch");
    assert_bytes(second_decoded.payload, (char[])"lo", "last fragment payload mismatch");
}


// Control frames

fn void test_ping_frame()
{
    WebSocketFrame* ping = http::ws_ping_frame((char[])"ping")!!;
    defer http::ws_frame_free(ping);

    @assert(ping.fin, "ping frame not final");
    @assert(ping.is_control(), "ping frame not control");
    @assert(ping.opcode == http::WS_PING, "ping opcode mismatch");

    char[] encoded = http::ws_frame_encode(ping)!!;
    defer  http::localmem.free(encoded);

    WebSocketFrame* decoded = http::ws_frame_decode_server(encoded, null)!!;
    defer http::ws_frame_free(decoded);

    assert_bytes(decoded.payload, (char[])"ping", "ping payload mismatch");
}

fn void test_control_frame_too_large()
{
    char[126] payload;

    WebSocketFrame*? frame = http::ws_ping_frame(payload[..]);

    if (catch err = frame) {
        @assert(err == http::WS_FRAME_INVALID_CONTROL, "wrong oversized-control fault");
        return;
    }

    http::ws_frame_free(frame);
    @assert(false, "oversized control frame accepted");
}

fn void test_fragmented_control_frame()
{
    WebSocketFrame*? frame = http::ws_frame_create(http::WS_PING, (char[])"x", false);

    if (catch err = frame) {
        @assert(err == http::WS_FRAME_INVALID_CONTROL, "wrong fragmented-control fault");
        return;
    }

    http::ws_frame_free(frame);
    @assert(false, "fragmented control frame accepted");
}


// Close payload

fn void test_close_frame()
{
    char[5] payload;

    payload[0] = (char)(http::WS_CLOSE_NORMAL >> 8);
    payload[1] = (char)http::WS_CLOSE_NORMAL;
    payload[2] = 'b';
    payload[3] = 'y';
    payload[4] = 'e';

    http::ws_validate_close_payload(payload[..])!!;

    @assert(http::ws_close_code(payload[..]) == http::WS_CLOSE_NORMAL, "close code mismatch");

    WebSocketFrame* close_frame = http::ws_close_frame(payload[..])!!;
    defer http::ws_frame_free(close_frame);

    char[] encoded = http::ws_frame_encode(close_frame)!!;
    defer  http::localmem.free(encoded);

    WebSocketFrame* decoded = http::ws_frame_decode_server(encoded, null)!!;
    defer http::ws_frame_free(decoded);

    @assert(decoded.opcode == http::WS_CLOSE, "close opcode mismatch");
    assert_bytes(decoded.payload, payload[..], "close payload mismatch");
}

fn void test_close_payload_one_byte()
{
    char[1] payload = { 0x03 };

    if (catch err = http::ws_validate_close_payload(payload[..])) {
        @assert(err == http::WS_CLOSE_INVALID, "wrong one-byte close fault");
        return;
    }

    @assert(false, "one-byte close payload accepted");
}

fn void test_invalid_close_code()
{
    char[2] payload;

    payload[0] = (char)(1005 >> 8);
    payload[1] = (char)1005;

    if (catch err = http::ws_validate_close_payload(payload[..])) {
        @assert(err == http::WS_CLOSE_INVALID, "wrong invalid-close-code fault");
        return;
    }

    @assert(false, "reserved close code accepted");
}


// UTF-8

fn void test_valid_utf8()
{
    @assert(http::ws_utf8_valid((char[])"hello"), "ASCII rejected as UTF-8");
    @assert(http::ws_utf8_valid((char[])"안녕하세요"), "Korean UTF-8 rejected");
    @assert(http::ws_utf8_valid((char[])"😀"), "four-byte UTF-8 rejected");
}

fn void test_invalid_utf8()
{
    char[2] truncated = { 0xC2, 0x00 };
    char[3] surrogate = { 0xED, 0xA0, 0x80 };
    char[4] too_large = { 0xF4, 0x90, 0x80, 0x80 };
    char[2] overlong = { 0xC0, 0xAF };

    @assert(!http::ws_utf8_valid(truncated[..]), "invalid continuation accepted");
    @assert(!http::ws_utf8_valid(surrogate[..]), "UTF-8 surrogate accepted");
    @assert(!http::ws_utf8_valid(too_large[..]), "out-of-range UTF-8 accepted");
    @assert(!http::ws_utf8_valid(overlong[..]), "overlong UTF-8 accepted");
}

fn void test_close_invalid_utf8()
{
    char[4] payload;

    payload[0] = (char)(http::WS_CLOSE_NORMAL >> 8);
    payload[1] = (char)http::WS_CLOSE_NORMAL;
    payload[2] = 0xC0;
    payload[3] = 0xAF;

    if (catch err = http::ws_validate_close_payload(payload[..])) {
        @assert(err == http::WS_INVALID_UTF8, "wrong close UTF-8 fault");
        return;
    }

    @assert(false, "invalid close reason UTF-8 accepted");
}


// Incomplete and invalid frames

fn void test_incomplete_frame()
{
    char[1] data = { 0x81 };

    if (catch err = http::ws_frame_expected_len(data[..])) {
        @assert(err == http::WS_FRAME_INCOMPLETE, "wrong incomplete frame fault");
        return;
    }

    @assert(false, "incomplete frame accepted");
}

fn void test_noncanonical_16_bit_length()
{
    char[4] data = {
        0x82,
        http::WS_PAYLOAD_16,
        0x00,
        0x7D,
    };

    if (catch err = http::ws_frame_expected_len(data[..])) {
        @assert(err == http::WS_FRAME_INVALID, "wrong noncanonical-length fault");
        return;
    }

    @assert(false, "noncanonical 16-bit length accepted");
}

fn void test_invalid_opcode()
{
    char[2] data = {
        0x83,
        0x00,
    };

    WebSocketFrame*? frame = http::ws_frame_decode_server(data[..], null);

    if (catch err = frame) {
        @assert(err == http::WS_FRAME_INVALID_OPCODE, "wrong invalid-opcode fault");
        return;
    }

    http::ws_frame_free(frame);
    @assert(false, "reserved opcode accepted");
}

fn void test_rsv_rejected()
{
    char[2] data = {
        http::WS_FIN | http::WS_RSV1 | (char)http::WS_TEXT,
        0x00,
    };

    WebSocketFrame*? frame = http::ws_frame_decode_server(data[..], null);
 
    if (catch err = frame) {
        @assert(err == http::WS_FRAME_INVALID, "wrong RSV fault");
        return;
    }

    http::ws_frame_free(frame);
    @assert(false, "RSV frame accepted without extension");
}


// Message

fn void test_websocket_message()
{
    WebSocketMessage message;
    message.init();

    message.opcode = http::WS_TEXT;
    message.data = http::bytes_clone((char[])"hello")!!;
    message.owns_data = true;

    @assert(message.is_text(), "text message not recognized");
    @assert(!message.is_binary(), "text message recognized as binary");
    assert_string(message.text(), "hello", "message text mismatch");

    message.free();

    @assert(message.data.len == 0, "message data not cleared");
    @assert(!message.owns_data, "message ownership not cleared");
}


// Main

fn void? task_main(void* arg)
{
    test_accept_key();

    test_handshake_request();
    test_handshake_connection_tokens();
    test_handshake_invalid_method();
    test_handshake_invalid_version();
    test_handshake_invalid_key();
    test_handshake_response();
    test_version_response();

    test_short_server_frame();
    test_masked_client_frame();
    test_server_frame_rejects_mask();
    test_client_frame_requires_mask();

    test_payload_126();
    test_payload_65536();

    test_fragment_frames();

    test_ping_frame();
    test_control_frame_too_large();
    test_fragmented_control_frame();

    test_close_frame();
    test_close_payload_one_byte();
    test_invalid_close_code();

    test_valid_utf8();
    test_invalid_utf8();
    test_close_invalid_utf8();

    test_incomplete_frame();
    test_noncanonical_16_bit_length();
    test_invalid_opcode();
    test_rsv_rejected();

    test_websocket_message();

    warn("OK");
}

fn void main()
{
    aio::run(&task_main)!!;
}

// eof