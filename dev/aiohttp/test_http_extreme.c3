// test_http_extreme.c3

// Large I/O, fuzz request, and mount tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::http_extreme;

import std::io;
import ext::aio::http;
import ext::debug;

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

fn aio::http::Response*? home_handler(aio::http::Context* c)
{
    return c.text("home")!!;
}

fn aio::http::Response*? api_users_handler(aio::http::Context* c)
{
    return c.text("api users")!!;
}

fn aio::http::Response*? api_user_handler(aio::http::Context* c)
{
    String id = c.param("id")!!;

    return c.text(id)!!;
}

fn aio::http::Response*? admin_handler(aio::http::Context* c)
{
    return c.text("admin")!!;
}

fn aio::http::Response*? large_response_handler(aio::http::Context* c)
{
    DString body;
    body.init(aio::http::localmem, 128 * 1024);
    defer body.free();

    for (sz i = 0; i < 128 * 1024; i++)
    {
        body.append((char[])"x");
    }

    return c.text(body.str_view())!!;
}

fn aio::http::Response*? large_echo_handler(aio::http::Context* c)
{
    return c.text(c.req_text())!!;
}

fn void test_large_response_serialization()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/large", &large_response_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "large response status mismatch");
    @assert(res.body.len == 128 * 1024, "large response body length mismatch");

    String wire = res.serialize()!!;
    defer aio::http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "large response wire status mismatch");
    @assert(contains(wire, "Content-Length: 131072\r\n"), "large response Content-Length mismatch");
}

fn void test_large_request_body()
{
    DString body;
    body.init(aio::http::localmem, 64 * 1024);
    defer body.free();

    for (sz i = 0; i < 64 * 1024; i++)
    {
        body.append((char[])"a");
    }

    DString raw;
    raw.init(aio::http::localmem, 65 * 1024);
    defer raw.free();

    raw.append((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 65536\r\n"
        "\r\n"
    );
    raw.append((char[])body.str_view());

    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.post("/echo", &large_echo_handler)!!;

    aio::http::Response* res = app.fetch_raw(raw.str_view())!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "large request response status mismatch");
    @assert(res.body.len == 64 * 1024, "large request echo body length mismatch");
    @assert(res.body[0] == 'a', "large request first byte mismatch");
    @assert(res.body[res.body.len - 1] == 'a', "large request last byte mismatch");
}

fn void test_large_header_rejected()
{
    DString raw;
    raw.init(aio::http::localmem, aio::http::MAX_HEADER_BYTES + 4096);
    defer raw.free();

    raw.append((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "X-Large: "
    );

    for (sz i = 0; i < aio::http::MAX_HEADER_BYTES; i++)
    {
        raw.append((char[])"x");
    }

    raw.append((char[])
        "\r\n"
        "\r\n"
    );

    if (catch err = aio::http::request_parse(raw.str_view()))
    {
        @assert(err == aio::http::REQUEST_TOO_LARGE, "large header fault mismatch");
        return;
    }

    @assert(false, "large header should fail");
}

fn void test_fuzz_empty_input()
{
    if (catch err = aio::http::request_parse({}))
    {
        @assert(err == aio::http::BAD_REQUEST, "empty input fault mismatch");
        return;
    }

    @assert(false, "empty input should fail");
}

fn void test_fuzz_random_text()
{
    char[] raw = (char[])"this is not http";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::BAD_REQUEST, "random text fault mismatch");
        return;
    }

    @assert(false, "random text should fail");
}

fn void test_fuzz_bad_request_line_no_version()
{
    char[] raw =
        "GET /\r\n"
        "Host: localhost\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::BAD_REQUEST, "bad request line no version fault mismatch");
        return;
    }

    @assert(false, "bad request line no version should fail");
}

fn void test_fuzz_bad_method_token()
{
    char[] raw =
        "GE<T / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::INVALID_METHOD, "bad method token fault mismatch");
        return;
    }

    @assert(false, "bad method token should fail");
}

fn void test_fuzz_bad_version()
{
    char[] raw =
        "GET / HTTP/2.0\r\n"
        "Host: localhost\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::INVALID_VERSION, "bad version fault mismatch");
        return;
    }

    @assert(false, "bad version should fail");
}

fn void test_fuzz_header_without_colon()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "BadHeader\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::INVALID_HEADER, "header without colon fault mismatch");
        return;
    }

    @assert(false, "header without colon should fail");
}

fn void test_fuzz_bad_header_name()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Bad Header: x\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::INVALID_HEADER, "bad header name fault mismatch");
        return;
    }

    @assert(false, "bad header name should fail");
}

fn void test_fuzz_invalid_url_encoding_in_param()
{
    aio::http::Router router;
    router.init();
    defer router.free();

    router.get("/users/:id", &home_handler)!!;

    if (catch err = router.match("GET", "/users/%ZZ"))
    {
        @assert(err == aio::http::ROUTE_NOT_FOUND, "invalid param encoding route fault mismatch");
        return;
    }

    @assert(false, "invalid param encoding should not match");
}

fn void test_fuzz_invalid_url_encoding_in_query()
{
    char[] raw =
        "GET /search?q=%ZZ HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    if (catch err = req.query_params())
    {
        @assert(err == aio::http::INVALID_URL_ENCODING, "invalid query encoding fault mismatch");
        return;
    }

    @assert(false, "invalid query encoding should fail");
}

fn void test_mount_basic()
{
    aio::http::Application api;
    api.init();
    defer api.deinit();

    api.get("/users", &api_users_handler)!!;
    api.get("/users/:id", &api_user_handler)!!;

    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home_handler)!!;
    app.route("/api", &api)!!;

    aio::http::Response* res1 = app.fetch_raw((char[])
        "GET /api/users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res1);

    aio::http::Response* res2 = app.fetch_raw((char[])
        "GET /api/users/42 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res2);

    @assert(res1.status == 200, "mount users status mismatch");
    @assert((String)res1.body == "api users", "mount users body mismatch");

    @assert(res2.status == 200, "mount user id status mismatch");
    @assert((String)res2.body == "42", "mount user id body mismatch");
}

fn void test_mount_root_child_path()
{
    aio::http::Application child;
    child.init();
    defer child.deinit();

    child.get("/", &admin_handler)!!;

    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.route("/admin", &child)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /admin HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "mount root child status mismatch");
    @assert((String)res.body == "admin", "mount root child body mismatch");
}

fn void test_mount_prefix_root()
{
    aio::http::Application child;
    child.init();
    defer child.deinit();

    child.get("/admin", &admin_handler)!!;

    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.route("/", &child)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /admin HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "mount prefix root status mismatch");
    @assert((String)res.body == "admin", "mount prefix root body mismatch");
}

fn void test_mount_not_found()
{
    aio::http::Application api;
    api.init();
    defer api.deinit();

    api.get("/users", &api_users_handler)!!;

    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.route("/api", &api)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /api/missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 404, "mount missing status mismatch");
}

fn void test_mount_method_not_allowed()
{
    aio::http::Application api;
    api.init();
    defer api.deinit();

    api.get("/users", &api_users_handler)!!;

    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.route("/api", &api)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "POST /api/users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 405, "mount method not allowed status mismatch");
}

fn void main()
{
    test_large_response_serialization();
    test_large_request_body();
    test_large_header_rejected();

    test_fuzz_empty_input();
    test_fuzz_random_text();
    test_fuzz_bad_request_line_no_version();
    test_fuzz_bad_method_token();
    test_fuzz_bad_version();
    test_fuzz_header_without_colon();
    test_fuzz_bad_header_name();
    test_fuzz_invalid_url_encoding_in_param();
    test_fuzz_invalid_url_encoding_in_query();

    test_mount_basic();
    test_mount_root_child_path();
    test_mount_prefix_root();
    test_mount_not_found();
    test_mount_method_not_allowed();

    io::printfn("test_http_extreme: OK");
}

// eof