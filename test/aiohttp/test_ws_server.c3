// test_ws_server.c3

// WebSocket live server integration tests.
//
// Tests HTTP upgrade, masked client frames, echo messages,
// fragmentation, ping/pong, close handshake, and pending
// WebSocket data received with the HTTP upgrade request.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::ws_server;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::mem;
import ext::debug;
import c::errno;

const String HOST = "127.0.0.1";
const ushort PORT = 18108;

const ulong READ_TIMEOUT_US = 2_000_000;
const ulong SERVER_START_DELAY_US = 200;


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

fn void? read_exact(aio::Stream* stream, char[] out)
{
    @assert(stream != null, "read_exact stream is null");

    sz offset = 0;

    while (offset < out.len) {
        sz n = stream.read_timeout(out[offset..], READ_TIMEOUT_US)!;

        @assert(n > 0, "connection closed during read_exact");
        offset += n;
    }
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


// Frame helpers

fn ulong read_u64_be(char[8] data)
{
    ulong value = 0;

    for (sz i = 0; i < 8; i++) {
        value = (value << 8) | (ulong)data[i];
    }

    return value;
}

fn void apply_mask(char[] data, char[4] mask)
{
    for (sz i = 0; i < data.len; i++) {
        data[i] ^= mask[i & 3];
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

fn http::WebSocketFrame*? read_server_frame_from_pending(aio::Stream* stream, DString* pending)
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


// WebSocket handler

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

fn Response*? normal_route(Context* c)
{
    return c.text("normal")!;
}


// Server task

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


// Handshake

fn aio::Stream*? open_websocket(DString* pending, bool send_first_frame_with_handshake = false)
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;

    String request =
        "GET /ws HTTP/1.1\r\n"
        "Host: 127.0.0.1:18108\r\n"
        "Upgrade: websocket\r\n"
        "Connection: keep-alive, Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    if (!send_first_frame_with_handshake) {
        stream.write_all((char[])request)!;
    } else {
        http::WebSocketFrame* frame = http::ws_text_frame("pending")!;
        defer http::ws_frame_free(frame);

        char[4] mask = { 0x11, 0x22, 0x33, 0x44 };
        char[] encoded = http::ws_frame_encode_masked(frame, mask)!;
        defer http::localmem.free(encoded);

        char[] wire = http::localmem.alloc_array(char, request.len + encoded.len)!;
        defer http::localmem.free(wire);

        wire[0:request.len] = request[..];
        wire[request.len:encoded.len] = encoded[..];

        stream.write_all(wire)!;
    }

    String headers = read_http_headers(stream, pending)!;
    defer http::localmem.free(headers);

    @assert(headers.contains("HTTP/1.1 101 Switching Protocols\r\n"), "missing 101 response");
    @assert(headers.contains("Upgrade: websocket\r\n"), "missing Upgrade response header");
    @assert(headers.contains("Connection: Upgrade\r\n"), "missing Connection response header");
    @assert(headers.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"), "wrong Sec-WebSocket-Accept");
    @assert(!headers.contains("Content-Length:"), "101 response contains Content-Length");
    @assert(!headers.contains("Transfer-Encoding:"), "101 response contains Transfer-Encoding");

    return stream;
}


// Tests

fn void? test_normal_http_route()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    String request =
        "GET /normal HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n";

    stream.write_all((char[])request)!;

    DString response;
    response.init(http::localmem, 1024);
    defer response.free();

    char[1024] buffer;

    while (true) {
        sz? n = stream.read_timeout(buffer[..], READ_TIMEOUT_US);

        if (catch err = n) {
            @assert(err == aio::CLOSED || err == aio::TIMEOUT, "normal route read failed");
            break;
        }

        if (n <= 0) break;

        response.append(buffer[0:n]);
    }

    String wire = response.str_view();

    @assert(wire.contains("HTTP/1.1 200 OK\r\n"), "normal HTTP status mismatch");
    @assert(wire.contains("\r\n\r\nnormal"), "normal HTTP body mismatch");
}

fn void? test_websocket_handshake()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_CLOSE, {}, true)!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "server did not reply with close frame");

    stream.close();
}

fn void? test_text_echo()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_TEXT, (char[])"hello websocket")!;

    http::WebSocketFrame* frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.fin, "echo text frame is fragmented");
    @assert(frame.opcode == http::WS_TEXT, "echo text opcode mismatch");

    assert_string((String)frame.payload, "hello websocket", "echo text payload mismatch");

    send_client_frame(stream, http::WS_CLOSE, {})!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "text echo close reply missing");

    stream.close();
}

fn void? test_binary_echo()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[8] payload = { 0, 1, 2, 3, 252, 253, 254, 255 };

    send_client_frame(stream, http::WS_BINARY, payload[..])!;

    http::WebSocketFrame* frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_BINARY, "echo binary opcode mismatch");
    assert_bytes(frame.payload, payload[..], "echo binary payload mismatch");

    send_client_frame(stream, http::WS_CLOSE, {})!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "binary echo close reply missing");

    stream.close();
}

fn void? test_fragmented_text_echo()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_TEXT, (char[])"frag", false)!;
    send_client_frame(stream, http::WS_CONTINUATION, (char[])"mented", false)!;
    send_client_frame(stream, http::WS_CONTINUATION, (char[])" text", true)!;

    http::WebSocketFrame* frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_TEXT, "fragmented echo opcode mismatch");
    assert_string((String)frame.payload, "fragmented text", "fragmented echo payload mismatch");

    send_client_frame(stream, http::WS_CLOSE, {})!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "fragmented echo close reply missing");

    stream.close();
}

fn void? test_ping_pong()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    send_client_frame(stream, http::WS_PING, (char[])"alive")!;

    http::WebSocketFrame* frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.fin, "pong frame is fragmented");
    @assert(frame.opcode == http::WS_PONG, "ping did not produce pong");

    assert_string((String)frame.payload, "alive", "pong payload mismatch");

    send_client_frame(stream, http::WS_CLOSE, {})!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "ping/pong close reply missing");

    stream.close();
}

fn void? test_close_handshake()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    char[5] payload;

    payload[0] = (char)(http::WS_CLOSE_NORMAL >> 8);
    payload[1] = (char)http::WS_CLOSE_NORMAL;
    payload[2] = 'b';
    payload[3] = 'y';
    payload[4] = 'e';

    send_client_frame(stream, http::WS_CLOSE, payload[..])!;

    http::WebSocketFrame* frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_CLOSE, "close response opcode mismatch");
    assert_bytes(frame.payload, payload[..], "close response payload mismatch");

    stream.close();
}

fn void? test_pending_frame_after_handshake()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending, true)!;
    defer stream.free();

    http::WebSocketFrame* frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(frame);

    @assert(frame.opcode == http::WS_TEXT, "pending echo opcode mismatch");
    assert_string((String)frame.payload, "pending", "pending frame was lost during upgrade");

    send_client_frame(stream, http::WS_CLOSE, {})!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "pending frame close reply missing");

    stream.close();
}

fn void? test_unmasked_client_frame_rejected()
{
    DString pending;
    pending.init(http::localmem, 256);
    defer pending.free();

    aio::Stream* stream = open_websocket(&pending)!;
    defer stream.free();

    http::WebSocketFrame* frame = http::ws_text_frame("unmasked")!;
    defer http::ws_frame_free(frame);

    char[] encoded = http::ws_frame_encode(frame)!;
    defer http::localmem.free(encoded);

    stream.write_all(encoded)!;

    http::WebSocketFrame* close_frame = read_server_frame_from_pending(stream, &pending)!;
    defer http::ws_frame_free(close_frame);

    @assert(close_frame.opcode == http::WS_CLOSE, "unmasked frame did not close connection");
    @assert(close_frame.payload.len >= 2, "protocol close code missing");

    ushort code = ((ushort)close_frame.payload[0] << 8) | (ushort)close_frame.payload[1];

    @assert(code == http::WS_CLOSE_PROTOCOL_ERROR, "wrong unmasked-frame close code");

    stream.close();
}


// Main

fn void? task_main(void* arg)
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/normal", &normal_route)!;
    app.get("/ws", &websocket_route)!;

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::Task* task = aio::spawn_joinable(&server_task, &server)!;

    wait_server_ready()!;

    test_normal_http_route()!;
    test_websocket_handshake()!;
    test_text_echo()!;
    test_binary_echo()!;
    test_fragmented_text_echo()!;
    test_ping_pong()!;
    test_close_handshake()!;
    test_pending_frame_after_handshake()!;
    test_unmasked_client_frame_rejected()!;

    server.stop()!;
    wake_server();

    if (catch err = task.join()) {
//warn("%s", err);
        @assert(err == http::SERVER_CLOSED || err == aio::CANCELLED || err == aio::ACCEPT_ERROR, "unexpected server task fault");
    }

    warn("OK");
}

fn void main()
{
    aio::run(&task_main)!!;
}

// eof