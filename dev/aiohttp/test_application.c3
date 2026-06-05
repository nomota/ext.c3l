// test_application.c3

module test::aiohttp_application;

import std::io;
import ext::aiohttp;
import ext::debug;

fn bool contains(String s, String needle)
{
    if (needle.len == 0) return true;
    if (s.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= s.len; i++)
    {
        if (s[i:needle.len] == needle) return true;
    }

    return false;
}

fn aiohttp::Response*? home(aiohttp::Ctx* c)
{
    return c.text("home")!;
}

fn aiohttp::Response*? user(aiohttp::Ctx* c)
{
    String id = c.param("id")!!;
    return c.text(id)!;
}

fn aiohttp::Response*? search(aiohttp::Ctx* c)
{
    String q = c.query("q")!!;
    return c.text(q)!;
}

fn aiohttp::Response*? echo_body(aiohttp::Ctx* c)
{
    return c.text(c.req_text())!;
}

fn aiohttp::Response*? login_form(aiohttp::Ctx* c)
{
    String username = c.form("username")!!;
    return c.text(username)!;
}

fn aiohttp::Response*? cookie_handler(aiohttp::Ctx* c)
{
    String? sid = c.cookie("sid");

    if (catch err = sid)
    {
        c.cookie_set_default("sid", "abc")!!;
        return c.text("new cookie")!;
    }

    return c.text(sid)!;
}

fn aiohttp::Response*? auth_middleware(aiohttp::Ctx* c, aiohttp::Next next)
{
    String? auth = c.req_header("Authorization");

    if (catch err = auth)
    {
        c.status(401)!!;
        return c.text("unauthorized")!;
    }

    return next(c)!;
}

fn aiohttp::Response*? add_header_middleware(aiohttp::Ctx* c, aiohttp::Next next)
{
    aiohttp::Response* res = next(c)!;
    c.header("X-Test", "yes")!;
    return res;
}

fn void test_fetch_home()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "home status mismatch");
    @assert(contains(wire, "\r\n\r\nhome"), "home body mismatch");
}

fn void test_fetch_param()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/users/:id", &user)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET /users/kim%20lee HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "\r\n\r\nkim lee"), "param response mismatch");
}

fn void test_fetch_query()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/search", &search)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET /search?q=hello+world HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "\r\n\r\nhello world"), "query response mismatch");
}

fn void test_fetch_post_body()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/echo", &echo_body)!!;

    aiohttp::Response* res = app.fetch_raw((char[])(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello"
    ))!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "\r\n\r\nhello"), "post body echo mismatch");
}

fn void test_fetch_form()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/login", &login_form)!!;

    aiohttp::Response* res = app.fetch_raw((char[])(
        "POST /login HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 12\r\n"
        "\r\n"
        "username=kim"
    ))!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "\r\n\r\nkim"), "form response mismatch");
}

fn void test_fetch_cookie_set()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &cookie_handler)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "Set-Cookie: sid=abc; Path=/; SameSite=Lax\r\n"), "Set-Cookie header missing");
    @assert(contains(wire, "\r\n\r\nnew cookie"), "new cookie body mismatch");
}

fn void test_fetch_cookie_read()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &cookie_handler)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\nCookie: sid=abc\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "\r\n\r\nabc"), "cookie read body mismatch");
}

fn void test_404()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET /missing HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 404, "expected 404");
}

fn void test_405()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.get("/only-get", &home)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"POST /only-get HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 405, "expected 405");
}

fn void test_middleware_header()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&add_header_middleware);
    app.get("/", &home)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "X-Test: yes\r\n"), "middleware header missing");
}

fn void test_path_middleware_auth_block()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &auth_middleware)!!;
    app.get("/api/data", &home)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET /api/data HTTP/1.1\r\nHost: localhost\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 401, "expected 401");
}

fn void test_path_middleware_auth_pass()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &auth_middleware)!!;
    app.get("/api/data", &home)!!;

    aiohttp::Response* res = app.fetch_raw((char[])"GET /api/data HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer test\r\n\r\n")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(res.status == 200, "expected 200");
    @assert(contains(wire, "\r\n\r\nhome"), "auth pass body mismatch");
}

fn void main()
{
    test_fetch_home();
    test_fetch_param();
    test_fetch_query();
    test_fetch_post_body();
    test_fetch_form();
    test_fetch_cookie_set();
    test_fetch_cookie_read();
    test_404();
    test_405();
    test_middleware_header();
    test_path_middleware_auth_block();
    test_path_middleware_auth_pass();

    io::printfn("test_application: OK");
}

// eof