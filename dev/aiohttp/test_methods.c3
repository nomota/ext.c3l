// test_methods.c3

// HTTP method semantics tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::methods;

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

fn aio::http::Response*? get_handler(aio::http::Context* c)
{
    return c.text("hello")!!;
}

fn aio::http::Response*? head_handler(aio::http::Context* c)
{
    return c.text("hello")!!;
}

fn aio::http::Response*? options_handler(aio::http::Context* c)
{
    c.header("Allow", "GET, HEAD, OPTIONS")!!;
    return c.text("options")!!;
}

fn String serialize(aio::http::Response* res)
{
    return res.serialize()!!;
}

fn void test_get_method()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &get_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "GET status mismatch");
    @assert((String)res.body == "hello", "GET body mismatch");
}

fn void test_head_route_dispatch()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.head("/", &head_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "HEAD / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "HEAD status mismatch");
    @assert((String)res.body == "hello", "HEAD dispatch body mismatch");
}

fn void test_options_route_dispatch()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.options("/", &options_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "OPTIONS / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "OPTIONS status mismatch");
    @assert((String)res.body == "options", "OPTIONS body mismatch");
    @assert(res.headers.get("Allow")!! == "GET, HEAD, OPTIONS", "OPTIONS allow header mismatch");
}

fn void test_method_not_allowed()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &get_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 405, "405 status mismatch");
    @assert((String)res.body == "405 Method Not Allowed", "405 body mismatch");
}

fn void test_unknown_method_bad_request()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &get_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "BAD METHOD / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 400, "bad method status mismatch");
    @assert((String)res.body == "400 Bad Request", "bad method body mismatch");
}

fn void main()
{
    test_get_method();
    test_head_route_dispatch();
    test_options_route_dispatch();
    test_method_not_allowed();
    test_unknown_method_bad_request();

    io::printfn("test_methods: OK");
}

// eof