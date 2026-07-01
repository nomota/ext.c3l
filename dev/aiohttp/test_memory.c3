// test_memory.c3

// Memory ownership and lifecycle tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::memory;

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

fn http::Response*? home_handler(http::Context* c)
{
    return c.text("home")!!;
}

fn http::Response*? replacement_handler(http::Context* c)
{
    http::Response* res = http::response_text("replacement")!!;
    res.header("X-Replaced", "yes")!!;

    return res;
}

fn http::Response*? borrowed_body_handler(http::Context* c)
{
    static char[] body = "borrowed";

    c.res.set_body_borrowed(body);
    c.res.content_type("text/plain")!!;

    return c.res;
}

fn http::Response*? empty_handler(http::Context* c)
{
    return c.empty();
}

fn http::Request* parse_request(char[] raw)
{
    return http::request_parse(raw)!!;
}

fn void test_headers_clear_reuse()
{
    http::Headers headers;
    headers.init();
    defer headers.free();

    headers.add("Host", "localhost")!!;
    headers.add("Set-Cookie", "a=1")!!;
    headers.add("Set-Cookie", "b=2")!!;

    headers.clear();

    @assert(headers.len() == 0, "headers clear len mismatch");

    headers.set("Content-Type", "text/plain")!!;
    headers.add("X-Test", "ok")!!;

    @assert(headers.len() == 2, "headers reuse len mismatch");
    @assert(headers.get("content-type")!! == "text/plain", "headers reuse content-type mismatch");
    @assert(headers.get("x-test")!! == "ok", "headers reuse X-Test mismatch");
}

fn void test_headers_free_empty()
{
    http::Headers headers;
    headers.init();

    headers.free();
}

fn void test_response_free_text()
{
    http::Response* res = http::response_text("hello")!!;

    @assert(res.status == 200, "response text status mismatch");
    @assert((String)res.body == "hello", "response text body mismatch");

    http::response_free(res);
}

fn void test_response_free_json()
{
    http::Response* res = http::response_json("{\"ok\":true}")!!;

    @assert(res.headers.get("Content-Type")!! == "application/json; charset=utf-8", "json content type mismatch");
    @assert((String)res.body == "{\"ok\":true}", "json body mismatch");

    http::response_free(res);
}

fn void test_response_borrowed_body_free()
{
    static char[] body = "borrowed-body";

    http::Response* res = http::response_empty(200)!!;
    res.set_body_borrowed(body);

    @assert(!res.owns_body, "borrowed response should not own body");
    @assert((String)res.body == "borrowed-body", "borrowed body mismatch");

    http::response_free(res);
}

fn void test_response_copy_then_borrowed()
{
    static char[] borrowed = "borrowed";

    http::Response* res = http::response_text("owned")!!;
    defer http::response_free(res);

    @assert(res.owns_body, "response should own initial text body");

    res.set_body_borrowed(borrowed);

    @assert(!res.owns_body, "response should not own borrowed body");
    @assert((String)res.body == "borrowed", "copy then borrowed body mismatch");
}

fn void test_response_borrowed_then_copy()
{
    static char[] borrowed = "borrowed";

    http::Response* res = http::response_empty(200)!!;
    defer http::response_free(res);

    res.set_body_borrowed(borrowed);
    res.set_body_copy((char[])"copied")!!;

    @assert(res.owns_body, "response should own copied body");
    @assert((String)res.body == "copied", "borrowed then copy body mismatch");
}

fn void test_request_free_get()
{
    char[] raw =
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);

    @assert(req.method == "GET", "request method mismatch");
    @assert(req.path == "/hello", "request path mismatch");

    http::request_free(req);
}

fn void test_request_free_with_body()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);

    @assert(req.owns_body, "parsed request should own body");
    @assert((String)req.body == "hello", "request body mismatch");

    http::request_free(req);
}

fn void test_request_set_body_copy_replaces_old()
{
    http::Request* req = http::request_new()!!;
    defer http::request_free(req);

    req.set_body_copy((char[])"first")!!;
    req.set_body_copy((char[])"second")!!;

    @assert(req.owns_body, "request should own copied body");
    @assert((String)req.body == "second", "request replaced copied body mismatch");
}

fn void test_request_set_body_borrowed_after_copy()
{
    static char[] borrowed = "borrowed";

    http::Request* req = http::request_new()!!;
    defer http::request_free(req);

    req.set_body_copy((char[])"owned")!!;
    req.set_body_borrowed(borrowed)!!;

    @assert(!req.owns_body, "request borrowed body ownership mismatch");
    @assert((String)req.body == "borrowed", "request borrowed body mismatch");
}

fn void test_request_set_body_copy_after_borrowed()
{
    static char[] borrowed = "borrowed";

    http::Request* req = http::request_new()!!;
    defer http::request_free(req);

    req.set_body_borrowed(borrowed)!!;
    req.set_body_copy((char[])"owned")!!;

    @assert(req.owns_body, "request copied body ownership mismatch");
    @assert((String)req.body == "owned", "request copied body mismatch");
}

fn void test_route_match_free()
{
    http::Router router;
    router.init();
    defer router.free();

    router.get("/users/:id", &home_handler)!!;

    http::RouteMatch m = router.match("GET", "/users/42")!!;

    @assert(m.params.get("id")!! == "42", "route match param mismatch");

    m.free();
}

fn void test_router_clear_reuse()
{
    http::Router router;
    router.init();
    defer router.free();

    router.get("/a", &home_handler)!!;
    router.get("/b", &home_handler)!!;

    router.clear();

    @assert(router.routes.len() == 0, "router clear len mismatch");

    router.get("/c", &home_handler)!!;

    http::RouteMatch m = router.match("GET", "/c")!!;
    defer m.free();

    @assert(m.handler != null, "router reuse handler mismatch");
}

fn void test_context_free_basic()
{
    char[] raw =
        "GET /hello?name=kim HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Context* c = http::context_new(req)!!;

    @assert(c.query("name")!! == "kim", "context query mismatch");

    http::context_free(c);
}

fn void test_context_free_with_caches()
{
    char[] raw =
        "POST /submit?x=1 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: sid=abc; mode=test\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "name=nomota";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Context* c = http::context_new(req)!!;

    @assert(c.query("x")!! == "1", "context query cache mismatch");
    @assert(c.cookie("sid")!! == "abc", "context cookie cache mismatch");
    @assert(c.form("name")!! == "nomota", "context form cache mismatch");

    http::context_free(c);
}

fn void test_context_with_response_replaces_owned_response()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Context* c = http::context_new(req)!!;
    defer http::context_free(c);

    http::Response* replacement = http::response_text("replacement")!!;

    http::Response* active = c.with_response(replacement);

    @assert(active == replacement, "with_response return mismatch");
    @assert(c.res == replacement, "with_response context response mismatch");
    @assert((String)c.res.body == "replacement", "with_response body mismatch");
}

fn void test_context_with_response_null_keeps_existing()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Context* c = http::context_new(req)!!;
    defer http::context_free(c);

    http::Response* old = c.res;
    http::Response* active = c.with_response(null);

    @assert(active == old, "with_response null return mismatch");
    @assert(c.res == old, "with_response null should keep existing response");
}

fn void test_application_fetch_detaches_context_response()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "fetch detached response status mismatch");
    @assert((String)res.body == "home", "fetch detached response body mismatch");

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "\r\n\r\nhome"), "detached response serialize mismatch");
}

fn void test_application_fetch_replacement_response()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &replacement_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "replacement response status mismatch");
    @assert((String)res.body == "replacement", "replacement response body mismatch");
    @assert(res.headers.get("X-Replaced")!! == "yes", "replacement response header mismatch");
}

fn void test_application_fetch_borrowed_body_response()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &borrowed_body_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(!res.owns_body, "borrowed fetch response ownership mismatch");
    @assert((String)res.body == "borrowed", "borrowed fetch response body mismatch");
}

fn void test_application_clear_reuse()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/old", &home_handler)!!;
    app.use(&http::middleware_powered_by);

    app.clear();

    app.get("/new", &home_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET /new HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "application reuse status mismatch");
    @assert((String)res.body == "home", "application reuse body mismatch");
}

fn void test_middleware_stack_clear_reuse()
{
    http::MiddlewareStack stack;
    stack.init();
    defer stack.free();

    stack.use(&http::middleware_powered_by);
    stack.use_path("/api", &http::middleware_logger)!!;

    stack.clear();

    @assert(stack.len() == 0, "middleware stack clear len mismatch");

    stack.use(&http::middleware_powered_by);

    @assert(stack.len() == 1, "middleware stack reuse len mismatch");
}

fn void test_cookie_build_free()
{
    http::CookieOptions opt = http::cookie_options_default();

    String cookie = http::cookie_build("sid", "abc", &opt)!!;

    @assert(cookie == "sid=abc; Path=/; SameSite=Lax", "cookie build mismatch");

    http::localmem.free(cookie);
}

fn void test_url_decode_free()
{
    String decoded = http::url_decode("hello%20world")!!;

    @assert(decoded == "hello world", "url decode mismatch");

    http::localmem.free(decoded);
}

fn void test_query_params_free()
{
    char[] raw =
        "GET /search?q=hello+world&page=1 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    http::Query q = req.query_params()!!;

    @assert(q.get("q")!! == "hello world", "query params q mismatch");
    @assert(q.get("page")!! == "1", "query params page mismatch");

    q.free();
}

fn void test_request_cookie_copy_free()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: sid=abc\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    String sid = req.cookie_copy("sid")!!;

    @assert(sid == "abc", "cookie copy mismatch");

    http::localmem.free(sid);
}

fn void test_request_form_copy_free()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 8\r\n"
        "\r\n"
        "name=kim";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    String name = req.form_copy("name")!!;

    @assert(name == "kim", "form copy mismatch");

    http::localmem.free(name);
}

fn void test_request_text_copy_free()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    String text = req.text_copy()!!;

    @assert(text == "hello", "text copy mismatch");

    http::localmem.free(text);
}

fn void test_request_bytes_copy_free()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/octet-stream\r\n"
        "Content-Length: 4\r\n"
        "\r\n"
        "data";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    char[] data = req.bytes_copy()!!;

    @assert(data.len == 4, "bytes copy len mismatch");
    @assert((String)data == "data", "bytes copy mismatch");

    http::localmem.free(data);
}

fn void test_empty_body_copy_faults()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    if (catch err = req.bytes_copy())
    {
        @assert(err == http::EMPTY_BODY, "empty bytes_copy fault mismatch");
    }
    else
    {
        @assert(false, "empty bytes_copy should fail");
    }

    if (catch err = req.text_copy())
    {
        @assert(err == http::EMPTY_BODY, "empty text_copy fault mismatch");
        return;
    }

    @assert(false, "empty text_copy should fail");
}

fn void main()
{
    test_headers_clear_reuse();
    test_headers_free_empty();

    test_response_free_text();
    test_response_free_json();
    test_response_borrowed_body_free();
    test_response_copy_then_borrowed();
    test_response_borrowed_then_copy();

    test_request_free_get();
    test_request_free_with_body();
    test_request_set_body_copy_replaces_old();
    test_request_set_body_borrowed_after_copy();
    test_request_set_body_copy_after_borrowed();

    test_route_match_free();
    test_router_clear_reuse();

    test_context_free_basic();
    test_context_free_with_caches();
    test_context_with_response_replaces_owned_response();
    test_context_with_response_null_keeps_existing();

    test_application_fetch_detaches_context_response();
    test_application_fetch_replacement_response();
    test_application_fetch_borrowed_body_response();
    test_application_clear_reuse();

    test_middleware_stack_clear_reuse();

    test_cookie_build_free();
    test_url_decode_free();
    test_query_params_free();
    test_request_cookie_copy_free();
    test_request_form_copy_free();
    test_request_text_copy_free();
    test_request_bytes_copy_free();
    test_empty_body_copy_faults();

    io::printfn("test_memory: OK");
}

// eof