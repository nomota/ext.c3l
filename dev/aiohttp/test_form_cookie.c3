// test_form_cookie.c3

module test::aio::http_form_cookie;

import std::io;
import ext::aio::http;
import ext::debug;

fn http::Response*? dummy_handler(http::Ctx* c)
{
    return c.text("ok")!;
}

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

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    @assert(req.is_form_urlencoded(), "request should be form-urlencoded");

    http::Query form = req.form_params()!!;
    defer form.free();

    String username = form.get("username")!!;
    String password = form.get("password")!!;

    @assert(username == "kim", "username mismatch");
    @assert(password == "1234", "password mismatch");
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

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Query form = req.form_params()!!;
    defer form.free();

    String username = form.get("username")!!;
    String message = form.get("message")!!;

    @assert(username == "kim lee", "plus decoding mismatch");
    @assert(message == "hello world", "percent decoding mismatch");
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

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Query? form = req.form_params();

    if (catch err = form)
    {
        @assert(err == http::UNSUPPORTED_FORM_TYPE, "expected UNSUPPORTED_FORM_TYPE");
        return;
    }

    form.free();
    @assert(false, "unsupported form type should fail");
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

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Ctx c;
    c.init(req)!!;
    defer c.free();

    String username = c.form("username")!!;
    String password = c.form("password")!!;

    @assert(username == "kim", "context form username mismatch");
    @assert(password == "1234", "context form password mismatch");

    http::Query* forms = c.forms();
    @assert(forms != null, "forms should not be null");
    @assert(forms.len() == 2, "form count mismatch");
}

fn void test_request_cookies()
{
    char[] raw = (char[])(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: session_id=abc123; theme=dark; count=10\r\n"
        "\r\n"
    );

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Cookies cookies = req.cookies()!!;
    defer cookies.free();

    String sid = cookies.get("session_id")!!;
    String theme = cookies.get("theme")!!;
    String count = cookies.get("count")!!;

    @assert(sid == "abc123", "session_id cookie mismatch");
    @assert(theme == "dark", "theme cookie mismatch");
    @assert(count == "10", "count cookie mismatch");
}

fn void test_request_cookie_copy()
{
    char[] raw = (char[])(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: session_id=abc123; theme=dark\r\n"
        "\r\n"
    );

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    String sid = req.cookie_copy("session_id")!!;
    defer http::localmem.free(sid);

    @assert(sid == "abc123", "cookie copy mismatch");
}

fn void test_context_cookie()
{
    char[] raw = (char[])(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Cookie: session_id=abc123; theme=dark\r\n"
        "\r\n"
    );

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Ctx c;
    c.init(req)!!;
    defer c.free();

    String sid = c.cookie("session_id")!!;
    String theme = c.cookie("theme")!!;

    @assert(sid == "abc123", "context session_id cookie mismatch");
    @assert(theme == "dark", "context theme cookie mismatch");

    http::Cookies* cookies = c.cookies();
    @assert(cookies != null, "context cookies should not be null");
    @assert(cookies.len() == 2, "context cookie count mismatch");
}

fn void test_cookie_build_default()
{
    http::CookieOptions opt = http::cookie_options_default();

    String cookie = http::cookie_build("session_id", "abc123", &opt)!!;
    defer http::localmem.free(cookie);

    @assert(cookie == "session_id=abc123; Path=/; SameSite=Lax", "default cookie build mismatch");
}

fn void test_cookie_build_full_options()
{
    http::CookieOptions opt = http::cookie_options_default();
    opt.domain = "example.com";
    opt.max_age = "3600";
    opt.http_only = true;
    opt.secure = true;
    opt.same_site = "Strict";

    String cookie = http::cookie_build("sid", "abc", &opt)!!;
    defer http::localmem.free(cookie);

    @assert(cookie == "sid=abc; Path=/; Domain=example.com; Max-Age=3600; SameSite=Strict; HttpOnly; Secure", "full cookie build mismatch");
}

fn void test_context_cookie_set_default()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Ctx c;
    c.init(req)!!;
    defer c.free();

    c.cookie_set_default("theme", "dark")!!;

    String wire = c.res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "Set-Cookie: theme=dark; Path=/; SameSite=Lax\r\n"), "Set-Cookie default missing");
}

fn void test_context_delete_cookie()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Ctx c;
    c.init(req)!!;
    defer c.free();

    c.delete_cookie("session_id")!!;

    String wire = c.res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "Set-Cookie: session_id=; Path=/; Max-Age=0; SameSite=Lax\r\n"), "delete cookie header missing");
}

fn void test_cookie_invalid_value()
{
    http::CookieOptions opt = http::cookie_options_default();

    String? cookie = http::cookie_build("sid", "abc;def", &opt);

    if (catch err = cookie)
    {
        @assert(err == http::INVALID_COOKIE_VALUE, "expected INVALID_COOKIE_VALUE");
        return;
    }

    http::localmem.free(cookie);
    @assert(false, "invalid cookie value should fail");
}

fn void test_cookie_invalid_same_site_none_without_secure()
{
    http::CookieOptions opt = http::cookie_options_default();
    opt.same_site = "None";
    opt.secure = false;

    String? cookie = http::cookie_build("sid", "abc", &opt);

    if (catch err = cookie)
    {
        @assert(err == http::INVALID_COOKIE_OPTION, "expected INVALID_COOKIE_OPTION");
        return;
    }

    http::localmem.free(cookie);
    @assert(false, "SameSite=None without Secure should fail");
}

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

    test_cookie_invalid_value();
    test_cookie_invalid_same_site_none_without_secure();

    io::printfn("test_form_cookie: OK");
}

// eof