// test_memory_ownership.c3

// Response/context ownership tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::memory_ownership;

import std::io;
import ext::aio::http;
import ext::debug;

const sz LOOP_COUNT = 1000;

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

fn aio::http::Response*? normal_handler(aio::http::Context* c)
{
    return c.text("normal")!!;
}

fn aio::http::Response*? external_handler(aio::http::Context* c)
{
    aio::http::Response* res = aio::http::response_text("external")!!;
    res.header("X-External", "yes")!!;

    return res;
}

fn aio::http::Response*? replace_handler(aio::http::Context* c)
{
    c.text("old")!!;

    aio::http::Response* res = aio::http::response_text("new")!!;
    res.header("X-New", "yes")!!;

    return res;
}

fn aio::http::Response*? null_handler(aio::http::Context* c)
{
    c.text("context response")!!;

    return null;
}

fn aio::http::Response*? body_copy_handler(aio::http::Context* c)
{
    char* p = aio::http::localmem.malloc(16)!!;
    char[] buf = p[0:16];

    buf[0:4] = "copy"[0:4];

    aio::http::Response* res = c.body_response(buf[0:4])!!;

    aio::http::localmem.free(buf);

    return res;
}

fn aio::http::Response*? middleware_replace(aio::http::Context* c, aio::http::Next next)
{
    aio::http::Response* old = next(c)!!;
    @assert(old != null, "middleware old response missing");

    aio::http::Response* res = aio::http::response_text("middleware replaced")!!;
    res.header("X-Middleware-Replaced", "yes")!!;

    return res;
}

fn aio::http::Response*? middleware_after(aio::http::Context* c, aio::http::Next next)
{
    aio::http::Response* res = next(c)!!;

    c.header("X-After", "yes")!!;

    return res;
}

fn aio::http::Response*? middleware_body_after(aio::http::Context* c, aio::http::Next next)
{
    aio::http::Response* res = next(c)!!;

    c.text("after body")!!;

    return res;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.get("/normal", &normal_handler)!!;
    app.get("/external", &external_handler)!!;
    app.get("/replace", &replace_handler)!!;
    app.get("/null", &null_handler)!!;
    app.get("/copy", &body_copy_handler)!!;
}

fn aio::http::Response* fetch(aio::http::Application* app, String path)
{
    char[256] raw;
    String req = string::bformat(raw[..],
        "GET %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        path
    );

    return app.fetch_raw((char[])req)!!;
}

fn void test_context_owned_response()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = fetch(&app, "/normal");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "context owned response status mismatch");
    @assert((String)res.body == "normal", "context owned response body mismatch");
}

fn void test_external_response()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = fetch(&app, "/external");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "external response status mismatch");
    @assert((String)res.body == "external", "external response body mismatch");
    @assert(res.headers.get("X-External")!! == "yes", "external response header mismatch");
}

fn void test_handler_replaces_context_response()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = fetch(&app, "/replace");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "replace response status mismatch");
    @assert((String)res.body == "new", "replace response body mismatch");
    @assert(res.headers.get("X-New")!! == "yes", "replace response header mismatch");
}

fn void test_null_handler_returns_context_response()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = fetch(&app, "/null");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "null handler status mismatch");
    @assert((String)res.body == "context response", "null handler body mismatch");
}

fn void test_body_response_copies_input()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = fetch(&app, "/copy");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "body copy status mismatch");
    @assert((String)res.body == "copy", "body copy mismatch");
}

fn void test_middleware_replaces_response_ownership()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_replace);
    app.get("/normal", &normal_handler)!!;

    aio::http::Response* res = fetch(&app, "/normal");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "middleware replace status mismatch");
    @assert((String)res.body == "middleware replaced", "middleware replace body mismatch");
    @assert(res.headers.get("X-Middleware-Replaced")!! == "yes", "middleware replace header mismatch");
}

fn void test_middleware_after_external_response()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_after);
    app.get("/external", &external_handler)!!;

    aio::http::Response* res = fetch(&app, "/external");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "middleware after external status mismatch");
    @assert((String)res.body == "external", "middleware after external body mismatch");
    @assert(res.headers.get("X-External")!! == "yes", "middleware after external original header mismatch");
    @assert(res.headers.get("X-After")!! == "yes", "middleware after external after header mismatch");
}

fn void test_middleware_body_after()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_body_after);
    app.get("/normal", &normal_handler)!!;

    aio::http::Response* res = fetch(&app, "/normal");
    defer aio::http::response_free(res);

    @assert(res.status == 200, "middleware body after status mismatch");
    @assert((String)res.body == "after body", "middleware body after mismatch");
}

fn void test_fallback_404_ownership()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = fetch(&app, "/missing");
    defer aio::http::response_free(res);

    @assert(res.status == 404, "404 ownership status mismatch");
    @assert(contains(res.body, "404 Not Found"), "404 ownership body mismatch");
}

fn void test_fallback_405_ownership()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::Response* res = app.fetch_raw((char[])
        "POST /normal HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 405, "405 ownership status mismatch");
    @assert((String)res.body == "405 Method Not Allowed", "405 ownership body mismatch");
}

fn void test_repeated_fetch_raw()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        aio::http::Response* res = fetch(&app, "/normal");
        defer aio::http::response_free(res);

        @assert(res.status == 200, "repeated fetch status mismatch");
        @assert((String)res.body == "normal", "repeated fetch body mismatch");
    }
}

fn void test_repeated_external_response()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        aio::http::Response* res = fetch(&app, "/external");
        defer aio::http::response_free(res);

        @assert(res.status == 200, "repeated external status mismatch");
        @assert((String)res.body == "external", "repeated external body mismatch");
    }
}

fn void test_repeated_middleware_replace()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_replace);
    app.get("/normal", &normal_handler)!!;

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        aio::http::Response* res = fetch(&app, "/normal");
        defer aio::http::response_free(res);

        @assert(res.status == 200, "repeated middleware replace status mismatch");
        @assert((String)res.body == "middleware replaced", "repeated middleware replace body mismatch");
    }
}

fn void main()
{
    test_context_owned_response();
    test_external_response();
    test_handler_replaces_context_response();
    test_null_handler_returns_context_response();
    test_body_response_copies_input();

    test_middleware_replaces_response_ownership();
    test_middleware_after_external_response();
    test_middleware_body_after();

    test_fallback_404_ownership();
    test_fallback_405_ownership();

    test_repeated_fetch_raw();
    test_repeated_external_response();
    test_repeated_middleware_replace();

    io::printfn("test_memory_ownership: OK");
}

// eof