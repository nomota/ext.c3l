// test_server.c3

// Server-side helper tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::server;

import std::io;
import ext::aio::http;
import ext::debug;

fn bool contains(char[] haystack, char[] needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn http::Request* parse_request(char[] raw)
{
    http::Request* req = http::request_parse(raw)!!;
    return req;
}

fn void test_request_buffer_init_append()
{
    DString buf;
    buf.init(http::localmem, 8);
    defer buf.free();

    buf.append((char[])"GET ");
    buf.append((char[])"/ HTTP/1.1");

    @assert(buf.len() == "GET / HTTP/1.1".len, "buffer len mismatch");
    @assert(buf.str_view() == "GET / HTTP/1.1", "buffer content mismatch");
}

fn void test_request_buffer_grows()
{
    DString buf;
    buf.init(http::localmem, 4);
    defer buf.free();

    buf.append((char[])"1234");
    buf.append((char[])"567890");

    @assert(buf.len() == 10, "grown buffer len mismatch");
    @assert(buf.str_view() == "1234567890", "grown buffer content mismatch");
}

fn void test_request_buffer_empty_views()
{
    DString buf;
    buf.init(http::localmem, 8);
    defer buf.free();

    @assert(buf.len() == 0, "empty buffer len mismatch");
    @assert(buf.str_view().len == 0, "empty buffer string mismatch");
}


fn void test_request_wants_close_http10_default()
{
    char[] raw =
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(http::request_wants_close(req), "HTTP/1.0 should close by default");
}

fn void test_request_wants_close_http10_keep_alive()
{
    char[] raw =
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(!http::request_wants_close(req), "HTTP/1.0 keep-alive should not close");
}

fn void test_request_wants_close_http11_default()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(!http::request_wants_close(req), "HTTP/1.1 should keep alive by default");
}

fn void test_request_wants_close_http11_close()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(http::request_wants_close(req), "HTTP/1.1 Connection: close mismatch");
}

fn void test_response_apply_connection_http11()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Response* res = http::response_text("ok")!!;
    defer http::response_free(res);

    http::response_apply_connection(res, req);

    String conn = res.headers.get("Connection")!!;
    @assert(conn == "keep-alive", "HTTP/1.1 response connection mismatch");
}

fn void test_response_apply_connection_http11_close()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Response* res = http::response_text("ok")!!;
    defer http::response_free(res);

    http::response_apply_connection(res, req);

    String conn = res.headers.get("Connection")!!;
    @assert(conn == "close", "HTTP/1.1 close response connection mismatch");
}

fn void test_response_apply_connection_http10_keep_alive()
{
    char[] raw =
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Response* res = http::response_text("ok")!!;
    defer http::response_free(res);

    http::response_apply_connection(res, req);

    String conn = res.headers.get("Connection")!!;
    @assert(conn == "close", "HTTP/1.0 response connection mismatch");
}

fn void test_application_server_lifecycle()
{
    http::Application app;
    app.init();
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, "127.0.0.1", 18080);
    defer server.free();

    @assert(server.app == &app, "server app mismatch");
    @assert(server.host == "127.0.0.1", "server host mismatch");
    @assert(server.port == 18080, "server port mismatch");
    @assert(!server.owns_app, "server owns_app mismatch");
    @assert(!server.closed, "server closed mismatch");
}

fn void test_app_server_new_free()
{
    http::Application app;
    app.init();
    defer app.deinit();

    http::ApplicationServer* server = http::app_server_new(&app, "127.0.0.1", 18081)!!;
    defer http::app_server_free(server);

    @assert(server.app == &app, "app_server_new app mismatch");
    @assert(server.host == "127.0.0.1", "app_server_new host mismatch");
    @assert(server.port == 18081, "app_server_new port mismatch");
    @assert(!server.closed, "app_server_new closed mismatch");
}

fn http::Response*? home_handler(http::Context* c)
{
    return c.text("home")!!;
}

fn void test_fetch_then_connection_policy()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home_handler)!!;

    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Response* res = app.fetch(req)!!;
    defer http::response_free(res);

    http::response_apply_connection(res, req);

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "fetch status missing");
    @assert(contains(wire, "Connection: keep-alive\r\n"), "connection keep-alive missing");
    @assert(contains(wire, "\r\n\r\nhome"), "fetch body missing");
}

fn void test_fetch_close_request()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home_handler)!!;

    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Response* res = app.fetch(req)!!;
    defer http::response_free(res);

    http::response_apply_connection(res, req);

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "Connection: close\r\n"), "connection close missing");
    @assert(contains(wire, "\r\n\r\nhome"), "close request body missing");
}

fn void test_application_server_close_idempotent()
{
    http::Application app;
    app.init();
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, "127.0.0.1", 18090);
    defer server.free();

    server.close();

    @assert(server.closed, "server close idempotent closed mismatch");
}

fn void test_application_server_wait_closed_idempotent()
{
    http::Application app;
    app.init();
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, "127.0.0.1", 18091);
    defer server.free();

    server.wait_closed();

    @assert(server.waited, "server wait_closed idempotent mismatch");
}

fn void main()
{
    test_request_buffer_init_append();
    test_request_buffer_grows();
    test_request_buffer_empty_views();

    test_request_wants_close_http10_default();
    test_request_wants_close_http10_keep_alive();
    test_request_wants_close_http11_default();
    test_request_wants_close_http11_close();

    test_response_apply_connection_http11();
    test_response_apply_connection_http11_close();
    test_response_apply_connection_http10_keep_alive();

    test_application_server_lifecycle();
    test_app_server_new_free();

    test_fetch_then_connection_policy();
    test_fetch_close_request();

    test_application_server_close_idempotent();
    io::printfn("test_server: OK");
}

// eof