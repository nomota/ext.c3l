// test_errhandler.c3

// Custom not-found and error handler integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::errhandler;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18105;

faultdef TEST_HANDLER_ERROR;
faultdef TEST_MIDDLEWARE_ERROR;
faultdef TEST_ERROR_HANDLER_ERROR;

fn bool contains(char[] a, char[] b) @inline
{
    return ((String)a).contains((String)b);
}

fn sz find_string(String s, String needle) @inline
{
    return s.index_of(needle) ?? -1;
}

fn sz count_occurrences(String s, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= s.len)
    {
        String rest = s[pos..];

        sz? idx = rest.index_of(needle);

        if (catch err = idx)
        {
            break;
        }

        count++;
        pos += idx + needle.len;
    }

    return count;
}

fn String body_part(String raw)
{
    sz idx = find_string(raw, "\r\n\r\n");
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;
    String prefix = string::bformat(buf[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
}

fn String? fetch_raw(String request, ulong read_timeout_us = 2_000_000)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString out;
    out.init(http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? n = client.read_timeout(buf[..], read_timeout_us);

        if (catch err = n)
        {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            return err~;
        }

        if (n == 0) break;

        out.append(buf[0:n]);
    }

    client.close();

    return out.copy_str(http::localmem);
}


// State

bool custom_not_found_called = false;
bool custom_error_called = false;
bool failing_error_called = false;

fault received_error = aio::NONE;


// Handlers

fn Response*? hello_handler(Ctx* c)
{
    return c.text("hello")!;
}

fn Response*? failing_handler(Ctx* c)
{
    return TEST_HANDLER_ERROR~;
}

fn Response*? custom_not_found_handler(Ctx* c)
{
    custom_not_found_called = true;

    c.status(404)!;
    c.header("X-Custom-Not-Found", "yes")!;

    return c.text("custom-not-found")!;
}

fn Response*? custom_error_handler(Ctx* c, fault err)
{
    custom_error_called = true;
    received_error = err;

    c.status(500)!;
    c.header("X-Custom-Error", "yes")!;

    if (err == TEST_HANDLER_ERROR)
    {
        return c.text("custom-handler-error")!;
    }

    if (err == TEST_MIDDLEWARE_ERROR)
    {
        return c.text("custom-middleware-error")!;
    }

    return c.text("custom-unknown-error")!;
}

fn Response*? failing_error_handler(Ctx* c, fault err)
{
    failing_error_called = true;
    return TEST_ERROR_HANDLER_ERROR~;
}


// Middleware

fn Response*? failing_middleware(Ctx* c, Next next)
{
    if (c.path() == "/middleware-error")
    {
        return TEST_MIDDLEWARE_ERROR~;
    }

    return next(c)!;
}


// Server task

fn void? server_task(void* arg)
{
    ApplicationServer* server = (ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
}

fn void wake_server()
{
    aio::Stream*? s = aio::stream_connect(HOST, PORT);

    if (catch err = s)
    {
        return;
    }

    s.close();
    s.free();
}


// Tests

fn void? test_default_not_found()
{
    Application app;
    app.init();
    defer app.deinit();

    Request* req = http::request_parse((char[])
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::request_free(req);

    Response* res = app.fetch(req)!;
    defer http::response_free(res);

    @assert(res.status == 404);
}

fn void? test_custom_not_found_wire()
{
    custom_not_found_called = false;

    String raw = fetch_raw(
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 404));
    @assert(custom_not_found_called);
    @assert(contains(raw, "X-Custom-Not-Found: yes\r\n"));
    @assert(contains(body_part(raw), "custom-not-found"));
}

fn void? test_custom_handler_error_wire()
{
    custom_error_called = false;
    received_error = aio::NONE;

    String raw = fetch_raw(
        "GET /handler-error HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 500));
    @assert(custom_error_called);
    @assert(received_error == TEST_HANDLER_ERROR);
    @assert(contains(raw, "X-Custom-Error: yes\r\n"));
    @assert(contains(body_part(raw), "custom-handler-error"));
}

fn void? test_custom_middleware_error_wire()
{
    custom_error_called = false;
    received_error = aio::NONE;

    String raw = fetch_raw(
        "GET /middleware-error HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 500));
    @assert(custom_error_called);
    @assert(received_error == TEST_MIDDLEWARE_ERROR);
    @assert(contains(raw, "X-Custom-Error: yes\r\n"));
    @assert(contains(body_part(raw), "custom-middleware-error"));
}

fn void? test_error_handler_failure_fallback()
{
    Application app;
    app.init();
    defer app.deinit();

    app.on_error(&failing_error_handler);
    app.get("/fail", &failing_handler)!;

    failing_error_called = false;

    Request* req = http::request_parse((char[])
        "GET /fail HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::request_free(req);

    Response* res = app.fetch(req)!;
    defer http::response_free(res);

    @assert(failing_error_called);
    @assert(res.status == 500);
}

fn void? test_clear_handlers()
{
    Application app;
    app.init();
    defer app.deinit();

    app.not_found(&custom_not_found_handler);
    app.on_error(&custom_error_handler);

    app.clear_not_found_handler();
    app.clear_error_handler();

    @assert(app.not_found_handler == null);
    @assert(app.error_handler == null);
}

fn void? test_keepalive_after_not_found()
{
    custom_not_found_called = false;

    String raw = fetch_raw(
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 404 ") == 1);
    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1);
    @assert(custom_not_found_called);
    @assert(contains(raw, "custom-not-found"));
    @assert(contains(raw, "hello"));
    @assert(raw.index_of("custom-not-found")! < raw.index_of("hello")!);
}

fn void? test_keepalive_after_error()
{
    custom_error_called = false;
    received_error = aio::NONE;

    String raw = fetch_raw(
        "GET /handler-error HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 500 ") == 1);
    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1);
    @assert(custom_error_called);
    @assert(received_error == TEST_HANDLER_ERROR);
    @assert(contains(raw, "custom-handler-error"));
    @assert(contains(raw, "hello"));
    @assert(raw.index_of("custom-handler-error")! < raw.index_of("hello")!);
}


// Main

fn void? test_main(void* arg)
{
    test_default_not_found()!;
    test_error_handler_failure_fallback()!;
    test_clear_handlers()!;

    Application app;
    app.init();
    defer app.deinit();

    app.not_found(&custom_not_found_handler);
    app.on_error(&custom_error_handler);

    app.use(&failing_middleware);

    app.get("/hello", &hello_handler)!;
    app.get("/handler-error", &failing_handler)!;
    app.get("/middleware-error", &hello_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_custom_not_found_wire()!;
    test_custom_handler_error_wire()!;
    test_custom_middleware_error_wire()!;
    test_keepalive_after_not_found()!;
    test_keepalive_after_error()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    warn("OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof