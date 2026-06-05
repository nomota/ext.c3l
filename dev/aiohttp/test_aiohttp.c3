// test_aiohttp.c3

// Basic test suite for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::string;
import ext::aiohttp;
import ext::debug;
import ext::aio;

fn aiohttp::Response*? hello_handler(aiohttp::Context* c)
{
    String name = c.query("name")!!;

    @assert(c.method() == "GET", "method mismatch");
    @assert(c.path() == "/hello", "path mismatch");
    @assert(name == "mio", "query mismatch");

    c.header("X-Test", "ok")!!;
    return c.text("hello")!!;
}

fn aiohttp::Response*? user_handler(aiohttp::Context* c)
{
    String id = c.param("id")!!;

    @assert(id == "42", "param mismatch");

    return c.json("{\"id\":42}")!!;
}

fn aiohttp::Response*? splat_handler(aiohttp::Context* c)
{
    String rest = c.splat()!!;

    @assert(rest == "css/app.css", "splat mismatch");

    return c.text(rest)!!;
}

fn aiohttp::Response*? form_handler(aiohttp::Context* c)
{
    @assert(c.is_form_urlencoded(), "form content type mismatch");

    String user = c.form("user")!!;
    String lang = c.form("lang")!!;

    @assert(user == "nomota", "form user mismatch");
    @assert(lang == "c3", "form lang mismatch");

    return c.text("form ok")!!;
}

fn aiohttp::Response*? cookie_handler(aiohttp::Context* c)
{
    String sid = c.cookie("sid")!!;

    @assert(sid == "abc123", "cookie mismatch");

    c.cookie_set_default("theme", "dark")!!;

    return c.text("cookie ok")!!;
}

fn aiohttp::Response*? post_body_handler(aiohttp::Context* c)
{
    @assert(c.req_is_json(), "json content type mismatch");

    String body = c.req_json_text();

    @assert(body == "{\"ok\":true}", "json body mismatch");

    return c.json("{\"received\":true}")!!;
}

fn aiohttp::Response*? custom_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    c.header("X-Middleware-Before", "1")!!;

    aiohttp::Response* res = next(c)!!;

    c.header("X-Middleware-After", "1")!!;

    return res;
}

fn void assert_contains(String haystack, String needle)
{
    if (needle.len == 0) return;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return;
    }

    @assert(false, "expected substring not found");
}

fn void test_headers()
{
    aiohttp::Headers headers;
    headers.init();
    defer headers.free();

    headers.add("Set-Cookie", "a=1")!!;
    headers.add("Set-Cookie", "b=2")!!;
    headers.set("Content-Type", "text/plain")!!;

    @assert(headers.len() == 3, "headers len mismatch");
    @assert(headers.has("content-type"), "case-insensitive has failed");

    String ct = headers.get("CONTENT-TYPE")!!;
    @assert(ct == "text/plain", "case-insensitive get failed");

    String wire = headers.serialize()!!;
    defer aiohttp::localmem.free(wire);

    assert_contains(wire, "Content-Type: text/plain\r\n");
    assert_contains(wire, "Set-Cookie: a=1\r\n");
    assert_contains(wire, "Set-Cookie: b=2\r\n");
}

fn void test_request_parse()
{
    char[] raw =
        "POST /submit?x=1&y=hello+world HTTP/1.1\r\n"
        "Host: example.com\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.method == "POST", "request method mismatch");
    @assert(req.target == "/submit?x=1&y=hello+world", "request target mismatch");
    @assert(req.path == "/submit", "request path mismatch");
    @assert(req.query_string == "x=1&y=hello+world", "query string mismatch");
    @assert(req.version == "HTTP/1.1", "version mismatch");

    sz len = req.content_length()!!;
    @assert(len == 11, "content length mismatch");

    @assert(req.body.len == 11, "body length mismatch");
    @assert((String)req.body == "{\"ok\":true}", "body mismatch");

    aiohttp::Query q = req.query_params()!!;
    defer q.free();

    @assert(q.get("x")!! == "1", "query x mismatch");
    @assert(q.get("y")!! == "hello world", "query y mismatch");
}

fn void test_response_serialize()
{
    aiohttp::Response* res = aiohttp::response_text("hello")!!;
    defer aiohttp::response_free(res);

    res.header("X-Test", "ok")!!;

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    assert_contains(wire, "HTTP/1.1 200 OK\r\n");
    assert_contains(wire, "Content-Type: text/plain; charset=utf-8\r\n");
    assert_contains(wire, "Content-Length: 5\r\n");
    assert_contains(wire, "Connection: close\r\n");
    assert_contains(wire, "X-Test: ok\r\n");
    assert_contains(wire, "\r\nhello");
}

fn void test_router()
{
    aiohttp::Router router;
    router.init();
    defer router.free();

    router.get("/users/:id", &user_handler)!!;
    router.get("/static/*", &splat_handler)!!;

    aiohttp::RouteMatch m = router.match("GET", "/users/42")!!;
    defer m.free();

    @assert(m.params.get("id")!! == "42", "router param mismatch");

    aiohttp::RouteMatch s = router.match("GET", "/static/css/app.css")!!;
    defer s.free();

    @assert(s.params.splat()!! == "css/app.css", "router splat mismatch");
}

fn void test_application_get()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&custom_middleware);
    app.get("/hello", &hello_handler)!!;

    char[] raw =
        "GET /hello?name=mio HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "GET response status mismatch");
    @assert(res.headers.get("X-Test")!! == "ok", "handler header mismatch");
    @assert(res.headers.get("X-Middleware-Before")!! == "1", "middleware before mismatch");
    @assert(res.headers.get("X-Middleware-After")!! == "1", "middleware after mismatch");
    @assert((String)res.body == "hello", "GET response body mismatch");
}

fn void test_application_params()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();
//warn("-");
    app.get("/users/:id", &user_handler)!!;
//warn("-");
    app.get("/static/*", &splat_handler)!!;
//warn("-");
    char[] raw1 =
        "GET /users/42 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Response* res1 = app.fetch_raw(raw1)!!;
    defer aiohttp::response_free(res1);
//warn("-");
    @assert(res1.status == 200, "param route status mismatch");
    @assert((String)res1.body == "{\"id\":42}", "param route body mismatch");

    char[] raw2 =
        "GET /static/css/app.css HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";
//warn("-");
    aiohttp::Response* res2 = app.fetch_raw(raw2)!!;
    defer aiohttp::response_free(res2);
//warn("-");
    @assert(res2.status == 200, "splat route status mismatch");
    @assert((String)res2.body == "css/app.css", "splat route body mismatch");
}

fn void test_application_form()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/form", &form_handler)!!;

    char[] raw =
        "POST /form HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded; charset=utf-8\r\n"
        "Content-Length: 19\r\n"
        "\r\n"
        "user=nomota&lang=c3";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "form response status mismatch");
    @assert((String)res.body == "form ok", "form response body mismatch");
}

fn void test_application_cookie()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/cookie", &cookie_handler)!!;

    char[] raw =
        "GET /cookie HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: sid=abc123; mode=test\r\n"
        "\r\n";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "cookie response status mismatch");
    @assert((String)res.body == "cookie ok", "cookie response body mismatch");

    String set_cookie = res.headers.get("Set-Cookie")!!;
    assert_contains(set_cookie, "theme=dark");
    assert_contains(set_cookie, "Path=/");
    assert_contains(set_cookie, "SameSite=Lax");
}

fn void test_application_json_body()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/json", &post_body_handler)!!;

    char[] raw =
        "POST /json HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "json response status mismatch");
    @assert((String)res.body == "{\"received\":true}", "json response body mismatch");
}

fn void test_not_found()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!!;

    char[] raw =
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 404, "not found status mismatch");
    @assert((String)res.body == "404 Not Found", "not found body mismatch");
}

fn void test_method_not_allowed()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!!;

    char[] raw =
        "POST /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 405, "method not allowed status mismatch");
    @assert((String)res.body == "405 Method Not Allowed", "method not allowed body mismatch");
}

fn void test_bad_request()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    char[] raw =
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 400, "bad request status mismatch");
    @assert((String)res.body == "400 Bad Request", "bad request body mismatch");
}

fn void test_cors_preflight()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&aiohttp::cors_default);
    app.get("/hello", &hello_handler)!!;

    char[] raw =
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: GET\r\n"
        "\r\n";

    aiohttp::Response* res = app.fetch_raw(raw)!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 204, "cors preflight status mismatch");
    @assert(res.headers.get("Access-Control-Allow-Origin")!! == "*", "cors allow origin mismatch");
    @assert(res.headers.has("Access-Control-Allow-Methods"), "cors allow methods missing");
}

fn void? main_task(void* arg)
{
    test_headers();
    test_request_parse();
    test_response_serialize();
    test_router();

    test_application_get();
    test_application_params();
    test_application_form();
    test_application_cookie();
    test_application_json_body();

    test_not_found();
    test_method_not_allowed();
    test_bad_request();
    test_cors_preflight();

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof 