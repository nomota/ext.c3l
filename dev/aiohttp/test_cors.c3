// test_cors.c3

// CORS middleware tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::cors;

import std::io;
import ext::aiohttp;
import ext::debug;

fn aiohttp::Response*? home_handler(aiohttp::Context* c)
{
    return c.text("home")!!;
}

fn bool contains(String haystack, String needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn void cors_reset_default()
{
    aiohttp::CorsOptions opt = aiohttp::cors_options_default();
    aiohttp::cors_set_options(&opt);
}

fn aiohttp::Response* fetch_with_cors(String raw)
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&aiohttp::cors_default);
    app.get("/hello", &home_handler)!!;

    return app.fetch_raw((char[])raw)!!;
}

fn void test_cors_preflight_default()
{
    cors_reset_default();

    aiohttp::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 204, "preflight default status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "*", "preflight allow origin mismatch");
    @assert(res.headers.get("Access-Control-Allow-Methods")!! == "GET, POST, PUT, PATCH, DELETE, OPTIONS", "preflight allow methods mismatch");
    @assert(res.headers.get("Access-Control-Allow-Headers")!! == "Content-Type, Authorization", "preflight allow headers mismatch");
    @assert(res.headers.get("Access-Control-Max-Age")!! == "86400", "preflight max age mismatch");
}

fn void test_cors_normal_request_default()
{
    cors_reset_default();

    aiohttp::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "normal CORS status mismatch");
    @assert((String)res.body == "home", "normal CORS body mismatch");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "*", "normal allow origin mismatch");
}

fn void test_cors_no_origin_still_applies_default()
{
    cors_reset_default();

    aiohttp::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "no-origin status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "*", "no-origin allow origin mismatch");
}

fn void test_cors_credentials_echo_origin()
{
    aiohttp::CorsOptions opt = aiohttp::cors_options_default();
    opt.allow_origin = "*";
    opt.allow_credentials = true;
    aiohttp::cors_set_options(&opt);

    aiohttp::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://client.example\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "credentials status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "https://client.example", "credentials origin echo mismatch");
    @assert(res.headers.get("Access-Control-Allow-Credentials")!! == "true", "credentials header mismatch");
    @assert(res.headers.get("Vary")!! == "Origin", "credentials vary mismatch");
}

fn void test_cors_custom_origin()
{
    aiohttp::CorsOptions opt = aiohttp::cors_options_default();
    opt.allow_origin = "https://allowed.example";
    aiohttp::cors_set_options(&opt);

    aiohttp::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://client.example\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "custom origin status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "https://allowed.example", "custom origin mismatch");
    @assert(res.headers.get("Vary")!! == "Origin", "custom origin vary mismatch");
}

fn void test_cors_expose_headers()
{
    aiohttp::CorsOptions opt = aiohttp::cors_options_default();
    opt.expose_headers = "X-Request-Id, X-Total-Count";
    aiohttp::cors_set_options(&opt);

    aiohttp::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "expose headers status mismatch");
    @assert(res.headers.get("Access-Control-Expose-Headers")!! == "X-Request-Id, X-Total-Count", "expose headers mismatch");
}

fn void test_cors_custom_preflight_values()
{
    aiohttp::CorsOptions opt = aiohttp::cors_options_default();
    opt.allow_methods = "GET, POST";
    opt.allow_headers = "X-Token, Content-Type";
    opt.max_age = "60";
    aiohttp::cors_set_options(&opt);

    aiohttp::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: POST\r\n"
        "Access-Control-Request-Headers: X-Token\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 204, "custom preflight status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Methods")!! == "GET, POST", "custom allow methods mismatch");
    @assert(res.headers.get("Access-Control-Allow-Headers")!! == "X-Token, Content-Type", "custom allow headers mismatch");
    @assert(res.headers.get("Access-Control-Max-Age")!! == "60", "custom max age mismatch");
}

fn void test_cors_preflight_echo_request_headers()
{
    aiohttp::CorsOptions opt = aiohttp::cors_options_default();
    opt.allow_headers = "";
    aiohttp::cors_set_options(&opt);

    aiohttp::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "Access-Control-Request-Headers: X-Custom, X-Trace\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 204, "echo request headers status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Headers")!! == "X-Custom, X-Trace", "echo request headers mismatch");
}

fn void test_cors_preflight_missing_request_method_falls_through()
{
    cors_reset_default();

    aiohttp::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 405, "missing request method should fall through to method-not-allowed");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "*", "fallthrough CORS origin mismatch");
}

fn void test_cors_serialized_headers()
{
    cors_reset_default();

    aiohttp::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 204 No Content\r\n"), "serialized CORS status missing");
    @assert(contains(wire, "Access-Control-Allow-Origin: *\r\n"), "serialized allow origin missing");
    @assert(contains(wire, "Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS\r\n"), "serialized allow methods missing");
    @assert(contains(wire, "Content-Length: 0\r\n"), "serialized content length mismatch");
}

fn void main()
{
    test_cors_preflight_default();
    test_cors_normal_request_default();
    test_cors_no_origin_still_applies_default();

    test_cors_credentials_echo_origin();
    test_cors_custom_origin();
    test_cors_expose_headers();

    test_cors_custom_preflight_values();
    test_cors_preflight_echo_request_headers();
    test_cors_preflight_missing_request_method_falls_through();

    test_cors_serialized_headers();

    cors_reset_default();

    io::printfn("test_cors: OK");
}

// eof