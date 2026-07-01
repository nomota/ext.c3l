// test_ws_protocol.c3

// WebSocket protocol error and state-machine integration tests.
//
// Tests invalid UTF-8, invalid fragmentation sequences, control frames
// between fragments, invalid close payloads, repeated messages, and
// server recovery after malformed WebSocket connections.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::ws_protocol;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::mem;
import ext::debug;
import c::errno;


const String HOST = "127.0.0.1";
const ushort PORT = 18109;

const ulong READ_TIMEOUT_US = 2_000_000;


// Helpers

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

fn sz find_header_end(String data)
{
    return data.index_of("\r\n\r\n") ?? -1;
}

fn ushort close_code(http::WebSocketFrame* frame)
{
    @assert(frame != null, "close frame is null");
    @assert(frame.opcode == http::WS_CLOSE, "frame is not close");
    @assert(frame.payload.len >= 2, "close frame has no status code");

    return ((ushort)frame.payload[0] << 8) | (ushort)frame.payload[1];
}

fn String? read_http_headers(aio::Stream* stream, DString* pending)
{
    @assert(stream != null, "read_http_headers stream is null");
    @assert(pending != null, "read_http_headers pending is null");

    DString input;
    input.init(http::localmem, 1024);
    defer input.free();

    char[1024] buffer;

    while (true) {
        String view = input.str_view();
        sz header_end = find_header_end(view);

        if (header_end >= 0) {
            sz total = header_end + 4;

            if (view.len > total) {
                pending.append((char[])view[total..]);
            }

            return view[0:total].copy(http::localmem);
        }

        sz n = stream.read_timeout(buffer[..], READ_TIMEOUT_US)!;

        @assert(n > 0, "connection closed before HTTP headers");
        input.append(buffer[0:n]);
    }
}

fn http::WebSocketFrame*? read_server_frame(aio::Stream* stream, DString* pending)
{
    @assert(stream != null, "read_server_frame stream is null");
    @assert(pending != null, "read_server_frame pending is null");

    while (true) {
        String view = pending.str_view();

        if (view.len >= 2) {
            sz? expected = http::ws_frame_expected_len((char[])view);

            if (try expected) {
                if (view.len >= expected) {
                    sz consumed = 0;
                    http::WebSocketFrame* frame = http::ws_frame_decode_server((char[])view, &consumed)!;

                    pending.delete(0, (usz)consumed);
                    return frame;
                }
            } else {
                if (catch err = expected) {
                    if (err != http::WS_FRAME_INCOMPLETE) return err~;
                }
            }
        }

        char[4096] buffer;
        sz n = stream.read_timeout(buffer[..], READ_TIMEOUT_US)!;

        @assert(n > 0, "connection closed before WebSocket frame");
        pending.append(buffer[0:n]);
    }
}

fn void? send_client_frame(aio::Stream* stream, http::WebSocketOpcode opcode, char[] payload, bool fin = true)
{
    @assert(stream != null, "send_client_frame stream is null");

    http::WebSocketFrame* frame = http::ws_frame_create(opcode, payload, fin)!;
    defer http::ws_frame_free(frame);

    char[4] mask = { 0x12, 0x34, 0x56, 0x78 };

    char[] encoded = http::ws_frame_encode_masked(frame, mask)!;
    defer http::localmem.free(encoded);

    stream.write_all(encoded)!;
}

fn void? send_raw_masked_frame(aio::Stream* stream, char first, char[] payload)
{
    @assert(stream != null, "send_raw_masked_frame stream is null");
    @assert(payload.len <= 125, "raw helper only supports short payload");

    char[4] mask = { 0x21, 0x43, 0x65, 0x87 };
    char[] wire = http::localmem.alloc_array(char, 6 + payload.len)!;
    defer http::localmem.free(wire);

    wire[0] = first;
    wire[1] = http::WS_MASK | (char)payload.len;

    wire[2] = mask[0];
    wire[3] = mask[1];
    wire[4] = mask[2];
    wire[5] = mask[3];

    for (sz i = 0; i < payload.len; i++) {
        wire[6 + i] = payload[i] ^ mask[i & 3];
    }

    stream.write_all(wire)!;
}

fn void? send_invalid_close_payload(aio::Stream* stream, char[] payload)
{
    return send_raw_masked_frame(stream, http::WS_FIN | (char)http::WS_CLOSE, payload);
}


// WebSocket route

fn void? echo_handler(http::WebSocketConnection* connection, http::WebSocketMessage* message)
{
    if (connection == null || message == null) return errno::E_INVALID_ARG~;

    if (message.is_text()) {
        connection.send_text(message.text())!;
        return;
    }

    if (message.is_binary()) {
        connection.send_binary(message.data)!;
    }
}

fn Response*? websocket_route(Context* c)
{
    return c.upgrade_websocket(&echo_handler, READ_TIMEOUT_US)!;
}

fn Response*? health_route(Context* c)
{
    return c.text("healthy")!;
}


// Server helpers

fn void? server_task(void* arg)
{
    http::ApplicationServer* server = (http::ApplicationServer*)arg;

    if (server == null) return errno::E_INVALID_ARG~;

    server.serve()!;
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < 100; i++) {
        aio::Stream*? client = aio::stream_connect(HOST, PORT);

        if (try client) {
            client.close();
            client.free();
            return;
        }

        aio::sleep(10_000)!;
    }

    @assert(false, "WebSocket server did not start");
}

fn void wake_server()
{
    aio::Stream*? client = aio::stream_connect(HOST, PORT);

    if (try client) {
        client.close();
        client.free();
    }
}

fn aio::Stream*? open_websocket(DString* pending)
{
    @assert(pending != null, "open_websocket pending is null");

    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;

    String request =
        "GET /ws HTTP/1.1\r\n"
        "Host: 127.0.0.1:18109\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    stream.write_all((char[])request)!;

    String headers = read_http_headers(stream, pending)!;
    defer http::localmem.free(headers);

    @assert(headers.contains("HTTP/1.1 101 Switching Protocols\r\n"), "missing 101 response");
    @assert(headers.contains("Upgrade: websocket\r\n"), "missing Upgrade response header");
    @assert(headers.contains("Connection: Upgrade\r\n"), "missing Connection response header");

    return stream;
}

fn void? close_websocket(aio::Stream* stream, DString* pending)
{
    if (stream == null) return;

    send_client_frame(stream, http::WS_CLOSE, {})!;

    http::WebSocketFrame* frame = read_server_frame(stream, pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "close response missing");

    stream.close();
}


// Tests

fn void? test_control_frame_between_fragments()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_TEXT, (char[])"hel", false)!;
    send_client_frame(stream, http::WS_PING, (char[])"middle", true)!;
    send_client_frame(stream, http::WS_CONTINUATION, (char[])"lo", true)!;

    http::WebSocketFrame* pong = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(pong);

    @assert(pong.opcode == http::WS_PONG, "interleaved ping did not produce pong");
    assert_string((String)pong.payload, "middle", "interleaved pong payload mismatch");

    http::WebSocketFrame* text = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(text);

    @assert(text.opcode == http::WS_TEXT, "fragmented text opcode mismatch");
    assert_string((String)text.payload, "hello", "fragmented text payload mismatch");

    close_websocket(stream, &pending)!;
}

fn void? test_fragmented_binary()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[3] first = { 0, 1, 2 };
    char[4] second = { 3, 252, 253, 255 };
    char[7] expected = { 0, 1, 2, 3, 252, 253, 255 };

    send_client_frame(stream, http::WS_BINARY, first[..], false)!;
    send_client_frame(stream, http::WS_CONTINUATION, second[..], true)!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_BINARY, "fragmented binary opcode mismatch");
    assert_bytes(frame.payload, expected[..], "fragmented binary payload mismatch");

    close_websocket(stream, &pending)!;
}

fn void? test_unexpected_continuation()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_CONTINUATION, (char[])"invalid", true)!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "unexpected continuation did not close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "unexpected continuation close code mismatch");

    stream.close();
}

fn void? test_second_data_frame_during_fragment()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_TEXT, (char[])"first", false)!;
    send_client_frame(stream, http::WS_TEXT, (char[])"second", true)!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "second data frame did not close connection");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "second data frame close code mismatch");

    stream.close();
}

fn void? test_binary_during_text_fragment()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_TEXT, (char[])"text", false)!;
    send_client_frame(stream, http::WS_BINARY, (char[])"binary", true)!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "binary data during text fragment did not close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "mixed fragment close code mismatch");

    stream.close();
}

fn void? test_invalid_text_utf8()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[2] invalid = { 0xC0, 0xAF };

    send_client_frame(stream, http::WS_TEXT, invalid[..], true)!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "invalid UTF-8 text did not close");
    @assert(close_code(frame) == http::WS_CLOSE_INVALID_PAYLOAD, "invalid UTF-8 close code mismatch");

    stream.close();
}

fn void? test_invalid_fragmented_text_utf8()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[1] first = { 0xE2 };
    char[2] second = { 0x28, 0xA1 };

    send_client_frame(stream, http::WS_TEXT, first[..], false)!;
    send_client_frame(stream, http::WS_CONTINUATION, second[..], true)!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "invalid fragmented UTF-8 did not close");
    @assert(close_code(frame) == http::WS_CLOSE_INVALID_PAYLOAD, "invalid fragmented UTF-8 close code mismatch");

    stream.close();
}

fn void? test_close_payload_one_byte()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[1] payload = { 0x03 };

    send_invalid_close_payload(stream, payload[..])!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "one-byte close payload did not produce close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "one-byte close payload code mismatch");

    stream.close();
}

fn void? test_reserved_close_code()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[2] payload;

    payload[0] = (char)(1005 >> 8);
    payload[1] = (char)1005;

    send_invalid_close_payload(stream, payload[..])!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "reserved close code did not produce close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "reserved close code response mismatch");

    stream.close();
}

fn void? test_invalid_close_reason_utf8()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[4] payload;

    payload[0] = (char)(http::WS_CLOSE_NORMAL >> 8);
    payload[1] = (char)http::WS_CLOSE_NORMAL;
    payload[2] = 0xC0;
    payload[3] = 0xAF;

    send_invalid_close_payload(stream, payload[..])!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "invalid close reason did not produce close");
    @assert(close_code(frame) == http::WS_CLOSE_INVALID_PAYLOAD, "invalid close reason response mismatch");

    stream.close();
}

fn void? test_fragmented_control_frame()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_raw_masked_frame(stream, (char)http::WS_PING, (char[])"x")!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "fragmented ping did not close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "fragmented ping close code mismatch");

    stream.close();
}

fn void? test_reserved_opcode()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_raw_masked_frame(stream, http::WS_FIN | 0x03, {})!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "reserved opcode did not close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "reserved opcode close code mismatch");

    stream.close();
}

fn void? test_rsv_bit_rejected()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_raw_masked_frame(stream, http::WS_FIN | http::WS_RSV1 | (char)http::WS_TEXT, (char[])"x")!;

    http::WebSocketFrame* frame = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "RSV frame did not close");
    @assert(close_code(frame) == http::WS_CLOSE_PROTOCOL_ERROR, "RSV frame close code mismatch");

    stream.close();
}

fn void? test_repeated_messages()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_TEXT, (char[])"one")!;
    send_client_frame(stream, http::WS_TEXT, (char[])"two")!;

    char[4] binary = { 0, 1, 254, 255 };
    send_client_frame(stream, http::WS_BINARY, binary[..])!;

    send_client_frame(stream, http::WS_PING, (char[])"alive")!;
    send_client_frame(stream, http::WS_TEXT, (char[])"three")!;

    http::WebSocketFrame* one = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(one);

    http::WebSocketFrame* two = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(two);

    http::WebSocketFrame* binary_echo = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(binary_echo);

    http::WebSocketFrame* pong = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(pong);

    http::WebSocketFrame* three = read_server_frame(stream, &pending)!;
    defer http::ws_frame_free(three);

    @assert(one.opcode == http::WS_TEXT, "first repeated opcode mismatch");
    assert_string((String)one.payload, "one", "first repeated payload mismatch");

    @assert(two.opcode == http::WS_TEXT, "second repeated opcode mismatch");
    assert_string((String)two.payload, "two", "second repeated payload mismatch");

    @assert(binary_echo.opcode == http::WS_BINARY, "repeated binary opcode mismatch");
    assert_bytes(binary_echo.payload, binary[..], "repeated binary payload mismatch");

    @assert(pong.opcode == http::WS_PONG, "repeated ping did not produce pong");
    assert_string((String)pong.payload, "alive", "repeated pong payload mismatch");

    @assert(three.opcode == http::WS_TEXT, "third repeated opcode mismatch");
    assert_string((String)three.payload, "three", "third repeated payload mismatch");

    close_websocket(stream, &pending)!;
}

fn void? test_abrupt_disconnect_recovery()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;

    stream.close();
    stream.free();

    aio::sleep(20_000)!;

    aio::Stream* health = aio::stream_connect(HOST, PORT)!;
    defer health.free();

    String request =
        "GET /health HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n";

    health.write_all((char[])request)!;

    DString response;
    response.init(http::localmem, 1024);
    defer response.free();

    char[1024] buffer;

    while (true) {
        sz? n = health.read_timeout(buffer[..], READ_TIMEOUT_US);

        if (catch err = n) {
            @assert(err == aio::CLOSED || err == aio::TIMEOUT, "health response read failed");
            break;
        }

        if (n <= 0) break;

        response.append(buffer[0:n]);
    }

    String wire = response.str_view();

    @assert(wire.contains("HTTP/1.1 200 OK\r\n"), "server failed after abrupt disconnect");
    @assert(wire.contains("\r\n\r\nhealthy"), "health response body mismatch");
}


// Main

fn void? task_main(void* arg)
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/ws", &websocket_route)!;
    app.get("/health", &health_route)!;

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::Task* task = aio::spawn_joinable(&server_task, &server)!;

    wait_server_ready()!;

    test_control_frame_between_fragments()!;
    test_fragmented_binary()!;

    test_unexpected_continuation()!;
    test_second_data_frame_during_fragment()!;
    test_binary_during_text_fragment()!;

    test_invalid_text_utf8()!;
    test_invalid_fragmented_text_utf8()!;

    test_close_payload_one_byte()!;
    test_reserved_close_code()!;
    test_invalid_close_reason_utf8()!;

    test_fragmented_control_frame()!;
    test_reserved_opcode()!;
    test_rsv_bit_rejected()!;

    test_repeated_messages()!;
    test_abrupt_disconnect_recovery()!;

    server.stop()!;
    wake_server();

    if (catch err = task.join()) {
        @assert(
            err == http::SERVER_CLOSED ||
            err == aio::CANCELLED ||
            err == aio::ACCEPT_ERROR,
            "unexpected server task fault"
        );
    }

    warn("OK");
}

fn void main()
{
    aio::run(&task_main)!!;
}

// eof