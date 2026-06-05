// test_error_cases.c3

// Error-path tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::error_cases;

import std::io;
import ext::aiohttp;
import ext::debug;

fn aiohttp::Response*? dummy_handler(aiohttp::Context* c)
{
    return c.text("ok")!!;
}

fn void test_invalid_header_name_add()
{
    aiohttp::Headers headers;
    headers.init();
    defer headers.free();

    if (catch err = headers.add("Bad Header", "x"))
    {
        @assert(err == aiohttp::INVALID_HEADER_NAME, "invalid header name fault mismatch");
        return;
    }

    @assert(false, "invalid header name should fail");
}

fn void test_invalid_header_name_set()
{
    aiohttp::Headers headers;
    headers.init();
    defer headers.free();

    if (catch err = headers.set("Bad:Header", "x"))
    {
        @assert(err == aiohttp::INVALID_HEADER_NAME, "invalid header set fault mismatch");
        return;
    }

    @assert(false, "invalid header set should fail");
}

fn void test_invalid_request_header_line()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "BadHeader\r\n"
        "\r\n";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::INVALID_HEADER, "invalid header fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "malformed header should fail");
}

fn void test_invalid_request_method()
{
    char[] raw =
        "GE<T / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::INVALID_METHOD, "invalid method fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "invalid method should fail");
}

fn void test_invalid_request_version()
{
    char[] raw =
        "GET / HTTP/2.0\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::INVALID_VERSION, "invalid version fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "invalid version should fail");
}

fn void test_bad_request_line()
{
    char[] raw =
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::BAD_REQUEST, "bad request line fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "bad request line should fail");
}

fn void test_body_incomplete()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 10\r\n"
        "\r\n"
        "hello";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::BODY_INCOMPLETE, "incomplete body fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "incomplete body should fail");
}

fn void test_content_length_invalid()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: abc\r\n"
        "\r\n";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::BAD_REQUEST, "invalid content length fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "invalid content length should fail");
}

fn void test_content_length_too_large_number()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 999999999999999999999999999999999999999\r\n"
        "\r\n";

    aiohttp::Request*? req = aiohttp::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aiohttp::REQUEST_TOO_LARGE, "too large content length fault mismatch");
        return;
    }

    aiohttp::request_free(req);
    @assert(false, "too large content length should fail");
}

fn void test_invalid_url_decode_short_percent()
{
    String? s = aiohttp::url_decode("abc%");

    if (catch err = s)
    {
        @assert(err == aiohttp::INVALID_URL_ENCODING, "short percent fault mismatch");
        return;
    }

    aiohttp::localmem.free(s);
    @assert(false, "short percent should fail");
}

fn void test_invalid_url_decode_bad_hex()
{
    String? s = aiohttp::url_decode("abc%ZZ");

    if (catch err = s)
    {
        @assert(err == aiohttp::INVALID_URL_ENCODING, "bad hex fault mismatch");
        return;
    }

    aiohttp::localmem.free(s);
    @assert(false, "bad hex should fail");
}

fn void test_query_parse_invalid_encoding()
{
    aiohttp::Query q;
    q.init();
    defer q.free();

    if (catch err = aiohttp::query_parse(&q, "name=abc%ZZ"))
    {
        @assert(err == aiohttp::INVALID_URL_ENCODING, "query invalid encoding fault mismatch");
        return;
    }

    @assert(false, "query invalid encoding should fail");
}

fn void test_invalid_param_name()
{
    aiohttp::Params params;
    params.init();
    defer params.free();

    if (catch err = params.put("1id", "42"))
    {
        @assert(err == aiohttp::INVALID_PARAM_NAME, "invalid param name fault mismatch");
        return;
    }

    @assert(false, "invalid param name should fail");
}

fn void test_invalid_route_empty_path()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    if (catch err = r.get("", &dummy_handler))
    {
        @assert(err == aiohttp::INVALID_ROUTE_PATH, "empty route path fault mismatch");
        return;
    }

    @assert(false, "empty route path should fail");
}

fn void test_invalid_route_no_leading_slash()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    if (catch err = r.get("users", &dummy_handler))
    {
        @assert(err == aiohttp::INVALID_ROUTE_PATH, "route without slash fault mismatch");
        return;
    }

    @assert(false, "route without slash should fail");
}

fn void test_invalid_route_trailing_slash()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    if (catch err = r.get("/users/", &dummy_handler))
    {
        @assert(err == aiohttp::INVALID_ROUTE_PATH, "trailing slash route fault mismatch");
        return;
    }

    @assert(false, "trailing slash route should fail");
}

fn void test_invalid_route_param_name()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    if (catch err = r.get("/users/:1id", &dummy_handler))
    {
        @assert(err == aiohttp::INVALID_ROUTE_PATH, "invalid route param fault mismatch");
        return;
    }

    @assert(false, "invalid route param should fail");
}

fn void test_invalid_route_splat_not_last()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    if (catch err = r.get("/files/*/edit", &dummy_handler))
    {
        @assert(err == aiohttp::INVALID_ROUTE_PATH, "invalid splat route fault mismatch");
        return;
    }

    @assert(false, "splat not last should fail");
}

fn void test_route_not_found()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    aiohttp::RouteMatch? m = r.match("GET", "/missing");

    if (catch err = m)
    {
        @assert(err == aiohttp::ROUTE_NOT_FOUND, "route not found fault mismatch");
        return;
    }

    m.free();
    @assert(false, "missing route should fail");
}

fn void test_method_not_allowed()
{
    aiohttp::Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    aiohttp::RouteMatch? m = r.match("POST", "/hello");

    if (catch err = m)
    {
        @assert(err == aiohttp::METHOD_NOT_ALLOWED, "method not allowed fault mismatch");
        return;
    }

    m.free();
    @assert(false, "method not allowed should fail");
}

fn void test_response_invalid_status()
{
    aiohttp::Response* res = aiohttp::response_new()!!;
    defer aiohttp::response_free(res);

    if (catch err = res.set_status(99))
    {
        @assert(err == aiohttp::INVALID_STATUS, "invalid status fault mismatch");
        return;
    }

    @assert(false, "invalid status should fail");
}

fn void test_cookie_build_invalid_name()
{
    String? cookie = aiohttp::cookie_build("bad name", "abc");

    if (catch err = cookie)
    {
        @assert(err == aiohttp::INVALID_COOKIE_NAME, "invalid cookie name fault mismatch");
        return;
    }

    aiohttp::localmem.free(cookie);
    @assert(false, "invalid cookie name should fail");
}

fn void test_cookie_build_invalid_value_semicolon()
{
    String? cookie = aiohttp::cookie_build("sid", "abc;def");

    if (catch err = cookie)
    {
        @assert(err == aiohttp::INVALID_COOKIE_VALUE, "invalid cookie value fault mismatch");
        return;
    }

    aiohttp::localmem.free(cookie);
    @assert(false, "invalid cookie value should fail");
}

fn void test_cookie_build_invalid_value_newline()
{
    String? cookie = aiohttp::cookie_build("sid", "abc\n");

    if (catch err = cookie)
    {
        @assert(err == aiohttp::INVALID_COOKIE_VALUE, "invalid cookie newline fault mismatch");
        return;
    }

    aiohttp::localmem.free(cookie);
    @assert(false, "invalid cookie newline should fail");
}

fn void test_cookie_same_site_none_without_secure()
{
    aiohttp::CookieOptions opt = aiohttp::cookie_options_default();
    opt.same_site = "None";
    opt.secure = false;

    String? cookie = aiohttp::cookie_build("sid", "abc", &opt);

    if (catch err = cookie)
    {
        @assert(err == aiohttp::INVALID_COOKIE_OPTION, "SameSite=None without Secure fault mismatch");
        return;
    }

    aiohttp::localmem.free(cookie);
    @assert(false, "SameSite=None without Secure should fail");
}

fn void test_cookie_same_site_none_with_secure()
{
    aiohttp::CookieOptions opt = aiohttp::cookie_options_default();
    opt.same_site = "None";
    opt.secure = true;

    String cookie = aiohttp::cookie_build("sid", "abc", &opt)!!;
    defer aiohttp::localmem.free(cookie);

    @assert(cookie == "sid=abc; Path=/; SameSite=None; Secure", "SameSite=None Secure cookie mismatch");
}

fn void test_cookie_invalid_max_age()
{
    aiohttp::CookieOptions opt = aiohttp::cookie_options_default();
    opt.max_age = "abc";

    String? cookie = aiohttp::cookie_build("sid", "abc", &opt);

    if (catch err = cookie)
    {
        @assert(err == aiohttp::INVALID_COOKIE_OPTION, "invalid max age fault mismatch");
        return;
    }

    aiohttp::localmem.free(cookie);
    @assert(false, "invalid max age should fail");
}

fn void test_form_unsupported_type()
{
    char[] raw =
        "POST /form HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    aiohttp::Query? form = req.form_params();

    if (catch err = form)
    {
        @assert(err == aiohttp::UNSUPPORTED_FORM_TYPE, "unsupported form type fault mismatch");
        return;
    }

    form.free();
    @assert(false, "unsupported form type should fail");
}

fn void test_application_bad_request_response()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    aiohttp::Response* res = app.fetch_raw((char[])
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 400, "application bad request status mismatch");
    @assert((String)res.body == "400 Bad Request", "application bad request body mismatch");
}

fn void test_application_payload_too_large_response()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    aiohttp::Response* res = app.fetch_raw((char[])
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 999999999999999999999999999999999999999\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 413, "application payload too large status mismatch");
    @assert((String)res.body == "413 Payload Too Large", "application payload too large body mismatch");
}

fn void main()
{
    test_invalid_header_name_add();
    test_invalid_header_name_set();
    test_invalid_request_header_line();
    test_invalid_request_method();
    test_invalid_request_version();
    test_bad_request_line();
    test_body_incomplete();
    test_content_length_invalid();
    test_content_length_too_large_number();

    test_invalid_url_decode_short_percent();
    test_invalid_url_decode_bad_hex();
    test_query_parse_invalid_encoding();

    test_invalid_param_name();
    test_invalid_route_empty_path();
    test_invalid_route_no_leading_slash();
    test_invalid_route_trailing_slash();
    test_invalid_route_param_name();
    test_invalid_route_splat_not_last();
    test_route_not_found();
    test_method_not_allowed();

    test_response_invalid_status();

    test_cookie_build_invalid_name();
    test_cookie_build_invalid_value_semicolon();
    test_cookie_build_invalid_value_newline();
    test_cookie_same_site_none_without_secure();
    test_cookie_same_site_none_with_secure();
    test_cookie_invalid_max_age();

    test_form_unsupported_type();

    test_application_bad_request_response();
    test_application_payload_too_large_response();

    io::printfn("test_error_cases: OK");
}

// eof