// test_live_edge.c3

// Live server edge tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::live_server_edge;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18082;

fn sz? response_content_length(String header_block)
{
    sz pos = 0;

    while (pos < header_block.len)
    {
        sz rel = header_block[pos..].index_of("\r\n") ?? -1;

        String line;

        if (rel < 0)
        {
            line = header_block[pos:header_block.len - pos];
            pos = header_block.len;
        }
        else
        {
            line = header_block[pos:rel];
            pos += rel + 2;
        }

        if (line.len == 0) continue;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) continue;

        String name = line[0:colon];
        String value = line[colon + 1:line.len - colon - 1].trim();

        if (http::str_iequals(name, "Content-Length"))
        {
            return value.to_long()!;
        }
    }

    return http::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    String header_block = response[0:header_end];

    sz? content_length = response_content_length(header_block);

    if (catch err = content_length)
    {
        return header_end + 4;
    }

    return header_end + 4 + content_length;
}

fn String? read_response(aio::Stream* stream)
{
    if (stream == null) return http::BAD_REQUEST~;

    DString buf;
    buf.init(http::localmem, 4096);
    defer buf.free();

    while (true)
    {
        char[1024] tmp;

        sz n = stream.read(tmp[..])!;

        if (n == 0) break;

        buf.append(tmp[0:n]);

        String text = buf.str_view();

        sz? total = response_expected_total_len(text);

        if (try total)
        {
            if (buf.len() >= total)
            {
                return text[0:total].copy(http::localmem);
            }
        }

        if (buf.len() > 2 * 1024 * 1024)
        {
            return http::REQUEST_TOO_LARGE~;
        }
    }

    return buf.str_view().copy(http::localmem);
}

fn String? request_once(String request)
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    stream.write_all((char[])request)!;

    String response = read_response(stream)!;

    stream.close();

    return response;
}

fn http::Response*? small_handler(http::Context* c)
{
    return c.text("small")!;
}

fn http::Response*? large_handler(http::Context* c)
{
    DString body;
    body.init(http::localmem, 64 * 1024);
    defer body.free();

    for (sz i = 0; i < 64 * 1024; i++)
    {
        body.append((char[])"x");
    }

    return c.text(body.str_view())!;
}

fn http::Response*? empty_handler(http::Context* c)
{
    return c.empty();
}

fn http::Response*? close_header_handler(http::Context* c)
{
    c.header("Connection", "close")!;
    return c.text("close")!;
}

fn http::Response*? status_204_handler(http::Context* c)
{
    c.status(204)!;
    return c.empty();
}

fn http::Response*? echo_handler(http::Context* c)
{
    return c.text(c.req_text())!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/small", &small_handler)!!;
    app.get("/large", &large_handler)!!;
    app.get("/empty", &empty_handler)!!;
    app.get("/close", &close_header_handler)!!;
    app.get("/no-content", &status_204_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    http::Application* app = (http::Application*)arg;

    app.serve(HOST, PORT)!;
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < 200; i++)
    {
        aio::Stream*? maybe_stream =
            aio::stream_connect(HOST, PORT);

        if (catch err = maybe_stream)
        {
            aio::sleep(100_000)!;
            continue;
        }

        aio::Stream* stream = maybe_stream;

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void test_small_response()
{
    String response = request_once(
        "GET /small HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "small response status mismatch"
    );
    @assert(
        response.contains("Content-Length: 5\r\n"),
        "small response content length mismatch"
    );
    @assert(
        response.contains("\r\n\r\nsmall"),
        "small response body mismatch"
    );
}

fn void test_large_response()
{
    String response = request_once(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "large response status mismatch"
    );
    @assert(
        response.contains("Content-Length: 65536\r\n"),
        "large response content length mismatch"
    );

    sz sep = response.index_of("\r\n\r\n") ?? -1;

    @assert(sep >= 0, "large response missing header separator");

    String body = response[sep + 4:response.len - sep - 4];

    @assert(body.len == 65536, "large response body length mismatch");
    @assert(body[0] == 'x', "large response first byte mismatch");
    @assert(body[body.len - 1] == 'x', "large response last byte mismatch");
}

fn void test_empty_response()
{
    String response = request_once(
        "GET /empty HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "empty response status mismatch"
    );
    @assert(
        response.contains("Content-Length: 0\r\n"),
        "empty response content length mismatch"
    );

    sz sep = response.index_of("\r\n\r\n") ?? -1;

    @assert(sep >= 0, "empty response separator missing");

    String body = response[sep + 4:response.len - sep - 4];

    @assert(body.len == 0, "empty response body should be empty");
}

fn void test_no_content_response()
{
    String response = request_once(
        "GET /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 204 No Content\r\n"),
        "204 status mismatch"
    );
    @assert(
        response.contains("Content-Length: 0\r\n"),
        "204 content length mismatch"
    );

    sz sep = response.index_of("\r\n\r\n") ?? -1;

    @assert(sep >= 0, "204 response separator missing");

    String body = response[sep + 4:response.len - sep - 4];

    @assert(body.len == 0, "204 response body should be empty");
}

fn void test_connection_close_response_header()
{
    String response = request_once(
        "GET /close HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "close header status mismatch"
    );
    @assert(
        response.contains("Connection: close\r\n"),
        "close header missing"
    );
    @assert(
        response.contains("\r\n\r\nclose"),
        "close header body mismatch"
    );
}

fn void test_http10_default_close()
{
    String response = request_once(
        "GET /small HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.0 status mismatch"
    );
    @assert(
        response.contains("Connection: close\r\n"),
        "HTTP/1.0 should close by default"
    );
    @assert(
        response.contains("\r\n\r\nsmall"),
        "HTTP/1.0 body mismatch"
    );
}

fn void test_http11_default_keep_alive_header()
{
    String response = request_once(
        "GET /small HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.1 status mismatch"
    );
    @assert(
        response.contains("Connection: keep-alive\r\n"),
        "HTTP/1.1 keep-alive header mismatch"
    );
    @assert(
        response.contains("\r\n\r\nsmall"),
        "HTTP/1.1 body mismatch"
    );
}

fn void test_invalid_content_length_returns_400()
{
    String response = request_once(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: abc\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 400 Bad Request\r\n"),
        "invalid content length status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n400 Bad Request"),
        "invalid content length body mismatch"
    );
}

fn void test_malformed_header_returns_400()
{
    String response = request_once(
        "GET /small HTTP/1.1\r\n"
        "BadHeader\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 400 Bad Request\r\n"),
        "malformed header status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n400 Bad Request"),
        "malformed header body mismatch"
    );
}

fn void test_many_sequential_requests()
{
    for (sz i = 0; i < 20; i++)
    {
        String response = request_once(
            "GET /small HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Connection: close\r\n"
            "\r\n"
        )!!;

        @assert(
            response.contains("HTTP/1.1 200 OK\r\n"),
            "many sequential status mismatch"
        );
        @assert(
            response.contains("\r\n\r\nsmall"),
            "many sequential body mismatch"
        );

        http::localmem.free(response);
    }
}

fn void? main_task(void* arg)
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::spawn(&server_task, &app)!;

    wait_server_ready()!;

    test_small_response();
    test_large_response();
    test_empty_response();
    test_no_content_response();

    test_connection_close_response_header();
    test_http10_default_close();
    test_http11_default_keep_alive_header();

    test_invalid_content_length_returns_400();
    test_malformed_header_returns_400();

    test_many_sequential_requests();

    aio::current_loop().stop()!;

    io::printfn("test_live_edge: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof