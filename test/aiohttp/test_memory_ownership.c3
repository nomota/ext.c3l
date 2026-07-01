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

fn http::Response*? normal_handler(http::Context* c)
{
    return c.text("normal")!!;
}

fn http::Response*? external_handler(http::Context* c)
{
    http::Response* res = http::response_text("external")!!;
    res.header("X-External", "yes")!!;

    return res;
}

fn http::Response*? replace_handler(http::Context* c)
{
    c.text("old")!!;

    http::Response* res = http::response_text("new")!!;
    res.header("X-New", "yes")!!;

    return res;
}

fn http::Response*? null_handler(http::Context* c)
{
    c.text("context response")!!;

    return null;
}

fn http::Response*? body_copy_handler(http::Context* c)
{
    char* p = http::localmem.malloc(16)!!;
    char[] buf = p[0:16];

    buf[0:4] = "copy"[0:4];

    http::Response* res = c.body_response(buf[0:4])!!;

    http::localmem.free(buf);

    return res;
}

fn http::Response*? middleware_replace(http::Context* c, http::Next next)
{
    http::Response* old = next(c)!!;
    @assert(old != null, "middleware old response missing");

    http::Response* res = http::response_text("middleware replaced")!!;
    res.header("X-Middleware-Replaced", "yes")!!;

    return res;
}

fn http::Response*? middleware_after(http::Context* c, http::Next next)
{
    http::Response* res = next(c)!!;

    c.header("X-After", "yes")!!;

    return res;
}

fn http::Response*? middleware_body_after(http::Context* c, http::Next next)
{
    http::Response* res = next(c)!!;

    c.text("after body")!!;

    return res;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/normal", &normal_handler)!!;
    app.get("/external", &external_handler)!!;
    app.get("/replace", &replace_handler)!!;
    app.get("/null", &null_handler)!!;
    app.get("/copy", &body_copy_handler)!!;
}

fn http::Response* fetch(http::Application* app, String path)
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
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "/normal");
    defer http::response_free(res);

    @assert(res.status == 200, "context owned response status mismatch");
    @assert((String)res.body == "normal", "context owned response body mismatch");
}

fn void test_external_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "/external");
    defer http::response_free(res);

    @assert(res.status == 200, "external response status mismatch");
    @assert((String)res.body == "external", "external response body mismatch");
    @assert(res.headers.get("X-External")!! == "yes", "external response header mismatch");
}

fn void test_handler_replaces_context_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "/replace");
    defer http::response_free(res);

    @assert(res.status == 200, "replace response status mismatch");
    @assert((String)res.body == "new", "replace response body mismatch");
    @assert(res.headers.get("X-New")!! == "yes", "replace response header mismatch");
}

fn void test_null_handler_returns_context_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "/null");
    defer http::response_free(res);

    @assert(res.status == 200, "null handler status mismatch");
    @assert((String)res.body == "context response", "null handler body mismatch");
}

fn void test_body_response_copies_input()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "/copy");
    defer http::response_free(res);

    @assert(res.status == 200, "body copy status mismatch");
    @assert((String)res.body == "copy", "body copy mismatch");
}

fn void test_middleware_replaces_response_ownership()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_replace);
    app.get("/normal", &normal_handler)!!;

    http::Response* res = fetch(&app, "/normal");
    defer http::response_free(res);

    @assert(res.status == 200, "middleware replace status mismatch");
    @assert((String)res.body == "middleware replaced", "middleware replace body mismatch");
    @assert(res.headers.get("X-Middleware-Replaced")!! == "yes", "middleware replace header mismatch");
}

fn void test_middleware_after_external_response()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_after);
    app.get("/external", &external_handler)!!;

    http::Response* res = fetch(&app, "/external");
    defer http::response_free(res);

    @assert(res.status == 200, "middleware after external status mismatch");
    @assert((String)res.body == "external", "middleware after external body mismatch");
    @assert(res.headers.get("X-External")!! == "yes", "middleware after external original header mismatch");
    @assert(res.headers.get("X-After")!! == "yes", "middleware after external after header mismatch");
}

fn void test_middleware_body_after()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_body_after);
    app.get("/normal", &normal_handler)!!;

    http::Response* res = fetch(&app, "/normal");
    defer http::response_free(res);

    @assert(res.status == 200, "middleware body after status mismatch");
    @assert((String)res.body == "after body", "middleware body after mismatch");
}

fn void test_fallback_404_ownership()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "/missing");
    defer http::response_free(res);

    @assert(res.status == 404, "404 ownership status mismatch");
    @assert(contains(res.body, "404 Not Found"), "404 ownership body mismatch");
}

fn void test_fallback_405_ownership()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = app.fetch_raw((char[])
        "POST /normal HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 405, "405 ownership status mismatch");
    @assert((String)res.body == "405 Method Not Allowed", "405 ownership body mismatch");
}

fn void test_repeated_fetch_raw()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        http::Response* res = fetch(&app, "/normal");
        defer http::response_free(res);

        @assert(res.status == 200, "repeated fetch status mismatch");
        @assert((String)res.body == "normal", "repeated fetch body mismatch");
    }
}

fn void test_repeated_external_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        http::Response* res = fetch(&app, "/external");
        defer http::response_free(res);

        @assert(res.status == 200, "repeated external status mismatch");
        @assert((String)res.body == "external", "repeated external body mismatch");
    }
}

fn void test_repeated_middleware_replace()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_replace);
    app.get("/normal", &normal_handler)!!;

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        http::Response* res = fetch(&app, "/normal");
        defer http::response_free(res);

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