// test_cors.c3

// CORS middleware tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::cors;

import std::io;
import ext::aio::http;
import ext::debug;

fn http::Response*? home_handler(http::Context* c)
{
    return c.text("home")!!;
}

fn bool contains(String haystack, String needle)
{
    return haystack.contains(needle);
}

fn void cors_reset_default()
{
    http::CorsOptions opt = http::cors_options_default();
    http::cors_set_options(&opt);
}

fn http::Response* fetch_with_cors(String raw)
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&http::cors_default);
    app.get("/hello", &home_handler)!!;

    return app.fetch_raw((char[])raw)!!;
}

fn void test_cors_preflight_default()
{
    cors_reset_default();

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 204, "preflight default status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!! == "*",
        "preflight allow origin mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Methods")!!
            == "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        "preflight allow methods mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Headers")!!
            == "Content-Type, Authorization",
        "preflight allow headers mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Max-Age")!! == "86400",
        "preflight max age mismatch"
    );
    @assert(
        res.headers.get("Vary")!!
            == "Origin, Access-Control-Request-Method, Access-Control-Request-Headers",
        "preflight vary mismatch"
    );
}

fn void test_cors_normal_request_default()
{
    cors_reset_default();

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "normal CORS status mismatch");
    @assert((String)res.body == "home", "normal CORS body mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!! == "*",
        "normal allow origin mismatch"
    );

    String vary = res.headers.get("Vary") ?? "";
    @assert(vary == "", "wildcard origin should not add Vary");
}

fn void test_cors_no_origin_omits_headers_by_default()
{
    cors_reset_default();

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "no-origin status mismatch");
    @assert((String)res.body == "home", "no-origin body mismatch");

    String allow_origin = res.headers.get("Access-Control-Allow-Origin") ?? "";
    @assert(
        allow_origin == "",
        "no-origin request should not get allow-origin header"
    );

    String allow_credentials = res.headers.get("Access-Control-Allow-Credentials") ?? "";
    @assert(
        allow_credentials == "",
        "no-origin request should not get credentials header"
    );

    String expose_headers = res.headers.get("Access-Control-Expose-Headers") ?? "";
    @assert(
        expose_headers == "",
        "no-origin request should not get expose-headers header"
    );

    String vary = res.headers.get("Vary") ?? "";
    @assert(
        vary == "",
        "no-origin request should not get vary header"
    );
}

fn void test_cors_always_send_wildcard()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.always_send = true;
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "always-send status mismatch");
    @assert((String)res.body == "home", "always-send body mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!! == "*",
        "always-send allow origin mismatch"
    );

    String vary = res.headers.get("Vary") ?? "";
    @assert(vary == "",
        "always-send wildcard should not add Vary"
    );
}

fn void test_cors_credentials_echo_origin()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin = "*";
    opt.allow_credentials = true;
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://client.example\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "credentials status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!!
            == "https://client.example",
        "credentials origin echo mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Credentials")!! == "true",
        "credentials header mismatch"
    );
    @assert(
        res.headers.get("Vary")!! == "Origin",
        "credentials vary mismatch"
    );
}

fn void test_cors_custom_origin_allowed()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin = "https://allowed.example";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://allowed.example\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "custom origin status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!!
            == "https://allowed.example",
        "custom origin mismatch"
    );
    @assert(
        res.headers.get("Vary")!! == "Origin",
        "custom origin vary mismatch"
    );
}

fn void test_cors_custom_origin_list_allowed()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin =
        "https://first.example, https://second.example";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://second.example\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "origin-list status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!!
            == "https://second.example",
        "origin-list allow-origin mismatch"
    );
    @assert(
        res.headers.get("Vary")!! == "Origin",
        "origin-list vary mismatch"
    );
}

fn void test_cors_custom_origin_rejected()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin = "https://allowed.example";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://client.example\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "rejected origin status mismatch");
    @assert((String)res.body == "home", "rejected origin body mismatch");

    String allow_origin = res.headers.get("Access-Control-Allow-Origin") ?? "";
    @assert(allow_origin == "",
        "rejected origin should not get allow-origin header"
    );

    String vary = res.headers.get("Vary") ?? "";
    @assert(vary == "",
        "rejected origin should not get vary header"
    );
}

fn void test_cors_expose_headers()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.expose_headers = "X-Request-Id, X-Total-Count";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "expose headers status mismatch");
    @assert(
        res.headers.get("Access-Control-Expose-Headers")!!
            == "X-Request-Id, X-Total-Count",
        "expose headers mismatch"
    );
}

fn void test_cors_custom_preflight_values()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_methods = "GET, POST";
    opt.allow_headers = "X-Token, Content-Type";
    opt.max_age = "60";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: POST\r\n"
        "Access-Control-Request-Headers: X-Token\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 204, "custom preflight status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Methods")!!
            == "GET, POST",
        "custom allow methods mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Headers")!!
            == "X-Token, Content-Type",
        "custom allow headers mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Max-Age")!! == "60",
        "custom max age mismatch"
    );
}

fn void test_cors_custom_preflight_status()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.preflight_status = 200;
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(
        res.status == 200,
        "custom preflight status mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!! == "*",
        "custom preflight allow-origin mismatch"
    );
}

fn void test_cors_preflight_echo_request_headers()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_headers = "";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "Access-Control-Request-Headers: X-Custom, X-Trace\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(
        res.status == 204,
        "echo request headers status mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Headers")!!
            == "X-Custom, X-Trace",
        "echo request headers mismatch"
    );
}

fn void test_cors_preflight_echo_request_method()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_methods = "";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: PATCH\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(
        res.status == 204,
        "echo request method status mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Methods")!! == "PATCH",
        "echo request method mismatch"
    );
}

fn void test_cors_preflight_credentials()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin = "*";
    opt.allow_credentials = true;
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://client.example\r\n"
        "Access-Control-Request-Method: POST\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 204, "preflight credentials status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!!
            == "https://client.example",
        "preflight credentials origin mismatch"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Credentials")!! == "true",
        "preflight credentials header mismatch"
    );
}

fn void test_cors_preflight_rejected_origin()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin = "https://allowed.example";
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://rejected.example\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(
        res.status == 204,
        "rejected preflight status mismatch"
    );

    String allow_origin = res.headers.get("Access-Control-Allow-Origin") ?? "";
    @assert(allow_origin == "",
        "rejected preflight should not get allow-origin header"
    );

    String allow_methods = res.headers.get("Access-Control-Allow-Methods") ?? "";
    @assert(allow_methods == "",
        "rejected preflight should not get allow-methods header"
    );

    String vary = res.headers.get("Vary") ?? "";
    @assert(vary == "",
        "rejected preflight should not get vary header"
    );
}

fn void test_cors_preflight_missing_request_method_falls_through()
{
    cors_reset_default();

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(
        res.status == 405,
        "missing request method should fall through"
    );
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!! == "*",
        "fallthrough CORS origin mismatch"
    );
}

fn void test_cors_vary_disabled()
{
    http::CorsOptions opt = http::cors_options_default();
    opt.allow_origin = "https://allowed.example";
    opt.vary = false;
    http::cors_set_options(&opt);

    http::Response* res = fetch_with_cors(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://allowed.example\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    @assert(res.status == 200, "vary-disabled status mismatch");
    @assert(
        res.headers.get("Access-Control-Allow-Origin")!!
            == "https://allowed.example",
        "vary-disabled allow-origin mismatch"
    );

    String vary = res.headers.get("Vary") ?? "";
    @assert(vary == "",
        "vary-disabled response should not get Vary"
    );
}

fn void test_cors_serialized_headers()
{
    cors_reset_default();

    http::Response* res = fetch_with_cors(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(
        contains(wire, "HTTP/1.1 204 No Content\r\n"),
        "serialized CORS status missing"
    );
    @assert(
        contains(wire, "Access-Control-Allow-Origin: *\r\n"),
        "serialized allow origin missing"
    );
    @assert(
        contains(
            wire,
            "Access-Control-Allow-Methods: "
            "GET, POST, PUT, PATCH, DELETE, OPTIONS\r\n"
        ),
        "serialized allow methods missing"
    );
    @assert(
        contains(
            wire,
            "Access-Control-Allow-Headers: "
            "Content-Type, Authorization\r\n"
        ),
        "serialized allow headers missing"
    );
    @assert(
        contains(wire, "Access-Control-Max-Age: 86400\r\n"),
        "serialized max age missing"
    );
    @assert(
        contains(wire, "Content-Length: 0\r\n"),
        "serialized content length mismatch"
    );
}

fn void main()
{
    test_cors_preflight_default();
    test_cors_normal_request_default();
    test_cors_no_origin_omits_headers_by_default();
    test_cors_always_send_wildcard();

    test_cors_credentials_echo_origin();
    test_cors_custom_origin_allowed();
    test_cors_custom_origin_list_allowed();
    test_cors_custom_origin_rejected();
    test_cors_expose_headers();

    test_cors_custom_preflight_values();
    test_cors_custom_preflight_status();
    test_cors_preflight_echo_request_headers();
    test_cors_preflight_echo_request_method();
    test_cors_preflight_credentials();
    test_cors_preflight_rejected_origin();
    test_cors_preflight_missing_request_method_falls_through();

    test_cors_vary_disabled();
    test_cors_serialized_headers();

    cors_reset_default();

    io::printfn("test_cors: OK");
}

// eof