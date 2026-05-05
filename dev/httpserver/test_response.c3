// test_response.c3

module test::httpserver_response;

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

fn void test_text_response()
{
    Response* res = httpserver::response_text("hello");
    defer httpserver::response_free(res);

    assert(res.status == 200);

    String ct = res.headers.get("Content-Type")!!;
    assert(ct == "text/plain; charset=utf-8");

    assert((String)res.body == "hello");

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "HTTP/1.1 200 OK\r\n"));
    assert(contains(wire, "Content-Type: text/plain; charset=utf-8\r\n"));
    assert(contains(wire, "Content-Length: 5\r\n"));
    assert(contains(wire, "\r\n\r\nhello"));
}

fn void test_json_response()
{
    Response* res = httpserver::response_json("{\"ok\":true}");
    defer httpserver::response_free(res);

    String ct = res.headers.get("Content-Type")!!;
    assert(ct == "application/json; charset=utf-8");

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Content-Length: 11\r\n"));
    assert(contains(wire, "\r\n\r\n{\"ok\":true}"));
}

fn void test_html_response()
{
    Response* res = httpserver::response_html("<h1>Hello</h1>");
    defer httpserver::response_free(res);

    String ct = res.headers.get("Content-Type")!!;
    assert(ct == "text/html; charset=utf-8");

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "<h1>Hello</h1>"));
}

fn void test_custom_header()
{
    Response* res = httpserver::response_text("ok");
    defer httpserver::response_free(res);

    res.header("X-Test", "yes");

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "X-Test: yes\r\n"));
}

fn void test_repeated_set_cookie()
{
    Response* res = httpserver::response_text("ok");
    defer httpserver::response_free(res);

    res.set_cookie("a=1; Path=/");
    res.set_cookie("b=2; Path=/");

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Set-Cookie: a=1; Path=/\r\n"));
    assert(contains(wire, "Set-Cookie: b=2; Path=/\r\n"));
}

fn void test_auto_connection()
{
    Response* res = httpserver::response_text("ok");
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Connection: close\r\n"));
}

fn void test_manual_content_length_preserved()
{
    Response* res = httpserver::response_text("hello");
    defer httpserver::response_free(res);

    res.content_length(999);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "Content-Length: 999\r\n"));
}

fn void test_no_body_status_204()
{
    Response* res = httpserver::response_text("hello");
    defer httpserver::response_free(res);

    res.set_status(204);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);

    assert(contains(wire, "HTTP/1.1 204 No Content\r\n"));
    assert(contains(wire, "Content-Length: 0\r\n"));
    assert(!contains(wire, "\r\n\r\nhello"));
}

fn void test_redirect()
{
    Response* res = httpserver::response_redirect("/new-page", 302);
    defer httpserver::response_free(res);

    String wire = res.serialize();
    defer httpserver::localmem.free(wire);
    // warn("%s", wire);
    assert(contains(wire, "HTTP/1.1 302 Moved Temporarily\r\n"));
    assert(contains(wire, "Location: /new-page\r\n"));
}

fn void test_write_to_small_buffer()
{
    Response* res = httpserver::response_text("hello");
    defer httpserver::response_free(res);

    char[4] small;
    usz n = res.write_to(&small);

    assert(n == 0);
}

fn void test_write_to_exact_buffer()
{
    Response* res = httpserver::response_text("hello");
    defer httpserver::response_free(res);

    usz need = res.serialized_len();

    char* p = httpserver::localmem.malloc(need);
    defer httpserver::localmem.free(p);

    char[] out = p[0:need];

    usz n = res.write_to(out);

    assert(n == need);

    String wire = (String)out;
    assert(contains(wire, "HTTP/1.1 200 OK\r\n"));
    assert(contains(wire, "\r\n\r\nhello"));
}

fn void main()
{
    test_text_response();
    test_json_response();
    test_html_response();
    test_custom_header();
    test_repeated_set_cookie();
    test_auto_connection();
    test_manual_content_length_preserved();
    test_no_body_status_204();
    test_redirect();
    test_write_to_small_buffer();
    test_write_to_exact_buffer();

    io::printfn("test_response: ok");
}