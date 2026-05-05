// test_form_cookie.c3

module test::httpserver_form_cookie;

import std::io;
import ext::httpserver;
import ext::debug;

fn Response* dummy_handler(Ctx* c)
{
    return c.text("ok");
}


// 
// form-urlencoded
// 

fn void test_request_form_params()
{
    char[] raw = (char[])(
        "POST /login HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 26\r\n"
        "\r\n"
        "username=kim&password=1234"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    assert(req.is_form_urlencoded());

    Query form = req.form_params()!!;
    defer form.free();

    String username = form.get("username")!!;
    String password = form.get("password")!!;

    assert(username == "kim");
    assert(password == "1234");
}

fn void test_request_form_plus_and_percent()
{
    char[] raw = (char[])(
        "POST /login HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded; charset=utf-8\r\n"
        "Content-Length: 38\r\n"
        "\r\n"
        "username=kim+lee&message=hello%20world"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Query form = req.form_params()!!;
    defer form.free();

    String username = form.get("username")!!;
    String message = form.get("message")!!;

    assert(username == "kim lee");
    assert(message == "hello world");
}

fn void test_request_form_unsupported_type()
{
    char[] raw = (char[])(
        "POST /login HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Query? form = req.form_params();

    if (catch err = form) {
        assert(err == httpserver::UNSUPPORTED_FORM_TYPE);
        return;
    }

    form.free();
    @assert(false);
}

fn void test_context_form()
{
    char[] raw = (char[])(
        "POST /login HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 26\r\n"
        "\r\n"
        "username=kim&password=1234"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Ctx c;
    c.init(req);
    defer c.free();

    String username = c.form("username")!!;
    String password = c.form("password")!!;

    assert(username == "kim");
    assert(password == "1234");

    Query* forms = c.forms();
    assert(forms != null);
    assert(forms.len() == 2);
}


// 
// cookies
// 

fn void test_request_cookies()
{
    char[] raw = (char[])(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: session_id=abc123; theme=dark; count=10\r\n"
        "\r\n"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Cookies cookies = req.cookies()!!;
    defer cookies.free();

    String sid = cookies.get("session_id")!!;
    String theme = cookies.get("theme")!!;
    String count = cookies.get("count")!!;

    assert(sid == "abc123");
    assert(theme == "dark");
    assert(count == "10");
}

fn void test_request_cookie_copy()
{
    char[] raw = (char[])(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: session_id=abc123; theme=dark\r\n"
        "\r\n"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    String sid = req.cookie_copy("session_id")!!;
    defer httpserver::localmem.free(sid);

    assert(sid == "abc123");
}

fn void test_context_cookie()
{
    char[] raw = (char[])(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: session_id=abc123; theme=dark\r\n"
        "\r\n"
    );

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Ctx c;
    c.init(req);
    defer c.free();

    String sid = c.cookie("session_id")!!;
    String theme = c.cookie("theme")!!;

    assert(sid == "abc123");
    assert(theme == "dark");

    Cookies* cookies = c.cookies();
    assert(cookies != null);
    assert(cookies.len() == 2);
}

fn void test_cookie_build_default()
{
    CookieOptions opt = httpserver::cookie_options_default();

    String cookie = httpserver::cookie_build("session_id", "abc123", &opt)!!;
    defer httpserver::localmem.free(cookie);

    assert(cookie == "session_id=abc123; Path=/; SameSite=Lax");
}

fn void test_cookie_build_full_options()
{
    CookieOptions opt = httpserver::cookie_options_default();
    opt.domain = "example.com";
    opt.max_age = "3600";
    opt.http_only = true;
    opt.secure = true;
    opt.same_site = "Strict";

    String cookie = httpserver::cookie_build("sid", "abc", &opt)!!;
    defer httpserver::localmem.free(cookie);

    assert(cookie == "sid=abc; Path=/; Domain=example.com; Max-Age=3600; SameSite=Strict; HttpOnly; Secure");
}

fn void test_context_cookie_set_default()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Ctx c;
    c.init(req);
    defer c.free();

    c.cookie_set_default("theme", "dark")!!;

    String wire = c.res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Set-Cookie: theme=dark; Path=/; SameSite=Lax\r\n"));
}

fn void test_context_delete_cookie()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Ctx c;
    c.init(req);
    defer c.free();

    c.delete_cookie("session_id")!!;

    String wire = c.res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Set-Cookie: session_id=; Path=/; Max-Age=0; SameSite=Lax\r\n"));
}


// 
// local contains helper
// 

fn bool contains(String s, String needle)
{
    if (needle.len == 0) return true;
    if (s.len < needle.len) return false;

    for (usz i = 0; i + needle.len <= s.len; i++) {
        if (s[i:needle.len] == needle) return true;
    }

    return false;
}


// 
// main
// 

fn void main()
{
    test_request_form_params();
    test_request_form_plus_and_percent();
    test_request_form_unsupported_type();
    test_context_form();

    test_request_cookies();
    test_request_cookie_copy();
    test_context_cookie();
    test_cookie_build_default();
    test_cookie_build_full_options();
    test_context_cookie_set_default();
    test_context_delete_cookie();

    io::printfn("test_form_cookie: ok");
}