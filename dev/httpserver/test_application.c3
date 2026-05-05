// test_application.c3

module test::httpserver_application;

import std::io;
import ext::httpserver;
import ext::debug;

fn bool contains(String s, String needle)
{
    if (needle.len == 0) return true;
    if (s.len < needle.len) return false;

    for (usz i = 0; i + needle.len <= s.len; i++) {
        if (s[i:needle.len] == needle) return true;
    }

    return false;
}

fn Response* home(Ctx* c)
{
    return c.text("home");
}

fn Response* user(Ctx* c)
{
    String id = c.param("id")!!;
    return c.text(id);
}

fn Response* search(Ctx* c)
{
    String q = c.query("q")!!;
    return c.text(q);
}

fn Response* echo_body(Ctx* c)
{
    return c.text(c.req_text());
}

fn Response* login_form(Ctx* c)
{
    String username = c.form("username")!!;
    return c.text(username);
}

fn Response* cookie_handler(Ctx* c)
{
    String? sid = c.cookie("sid");

    if (catch err = sid) {
        c.cookie_set_default("sid", "abc")!!;
        return c.text("new cookie");
    }

    return c.text(sid);
}

fn Response* auth_middleware(Ctx* c, Next next)
{
    String? auth = c.req_header("Authorization");

    if (catch err = auth) {
        c.status(401);
        return c.text("unauthorized");
    }

    return next(c);
}

fn Response* add_header_middleware(Ctx* c, Next next)
{
    Response* res = next(c);
    c.header("X-Test", "yes");
    return res;
}

fn void test_fetch_home()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &home)!!;

    Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "HTTP/1.1 200 OK\r\n"));
    assert(contains(wire, "\r\n\r\nhome"));
}

fn void test_fetch_param()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/users/:id", &user)!!;

    Response* res = app.fetch_raw((char[])"GET /users/kim%20lee HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "\r\n\r\nkim lee"));
}

fn void test_fetch_query()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/search", &search)!!;

    Response* res = app.fetch_raw((char[])"GET /search?q=hello+world HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "\r\n\r\nhello world"));
}

fn void test_fetch_post_body()
{
    Application app;
    app.init();
    defer app.free();

    app.post("/echo", &echo_body)!!;

    Response* res = app.fetch_raw((char[])(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello"
    ));
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "\r\n\r\nhello"));
}

fn void test_fetch_form()
{
    Application app;
    app.init();
    defer app.free();

    app.post("/login", &login_form)!!;

    Response* res = app.fetch_raw((char[])(
        "POST /login HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 12\r\n"
        "\r\n"
        "username=kim"
    ));
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "\r\n\r\nkim"));
}

fn void test_fetch_cookie_set()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &cookie_handler)!!;

    Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Set-Cookie: sid=abc; Path=/; SameSite=Lax\r\n"));
    assert(contains(wire, "\r\n\r\nnew cookie"));
}

fn void test_fetch_cookie_read()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &cookie_handler)!!;

    Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\nCookie: sid=abc\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "\r\n\r\nabc"));
}

fn void test_404()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &home)!!;

    Response* res = app.fetch_raw((char[])"GET /missing HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    assert(res.status == 404);
}

fn void test_405()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/only-get", &home)!!;

    Response* res = app.fetch_raw((char[])"POST /only-get HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n");
    defer httpserver::response_free(res);

    assert(res.status == 405);
}

fn void test_middleware_header()
{
    Application app;
    app.init();
    defer app.free();

    app.use(&add_header_middleware);
    app.get("/", &home)!!;

    Response* res = app.fetch_raw((char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "X-Test: yes\r\n"));
}

fn void test_path_middleware_auth_block()
{
    Application app;
    app.init();
    defer app.free();

    app.use_path("/api", &auth_middleware)!!;
    app.get("/api/data", &home)!!;

    Response* res = app.fetch_raw((char[])"GET /api/data HTTP/1.1\r\nHost: localhost\r\n\r\n");
    defer httpserver::response_free(res);

    assert(res.status == 401);
}

fn void test_path_middleware_auth_pass()
{
    Application app;
    app.init();
    defer app.free();

    app.use_path("/api", &auth_middleware)!!;
    app.get("/api/data", &home)!!;

    Response* res = app.fetch_raw((char[])"GET /api/data HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer test\r\n\r\n");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(res.status == 200);
    assert(contains(wire, "\r\n\r\nhome"));
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

    io::printfn("test_application: ok");
}