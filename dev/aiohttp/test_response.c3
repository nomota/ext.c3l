// test_response.c3

module test::aiohttp_response;

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

fn void test_text_response()
{
    aiohttp::Response* res = aiohttp::response_text("hello")!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "status mismatch");

    String ct = res.headers.get("Content-Type")!!;
    @assert(ct == "text/plain; charset=utf-8", "content type mismatch");

    @assert((String)res.body == "hello", "body mismatch");

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "missing status line");
    @assert(contains(wire, "Content-Type: text/plain; charset=utf-8\r\n"), "missing content type");
    @assert(contains(wire, "Content-Length: 5\r\n"), "missing content length");
    @assert(contains(wire, "\r\n\r\nhello"), "missing body");
}

fn void test_json_response()
{
    aiohttp::Response* res = aiohttp::response_json("{\"ok\":true}")!!;
    defer aiohttp::response_free(res);

    String ct = res.headers.get("Content-Type")!!;
    @assert(ct == "application/json; charset=utf-8", "content type mismatch");

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "Content-Length: 11\r\n"), "missing content length");
    @assert(contains(wire, "\r\n\r\n{\"ok\":true}"), "missing json body");
}

fn void test_html_response()
{
    aiohttp::Response* res = aiohttp::response_html("<h1>Hello</h1>")!!;
    defer aiohttp::response_free(res);

    String ct = res.headers.get("Content-Type")!!;
    @assert(ct == "text/html; charset=utf-8", "content type mismatch");

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "<h1>Hello</h1>"), "missing html body");
}

fn void test_custom_header()
{
    aiohttp::Response* res = aiohttp::response_text("ok")!!;
    defer aiohttp::response_free(res);

    res.header("X-Test", "yes")!!;

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "X-Test: yes\r\n"), "missing custom header");
}

fn void test_repeated_set_cookie()
{
    aiohttp::Response* res = aiohttp::response_text("ok")!!;
    defer aiohttp::response_free(res);

    res.set_cookie("a=1; Path=/")!!;
    res.set_cookie("b=2; Path=/")!!;

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "Set-Cookie: a=1; Path=/\r\n"), "missing first Set-Cookie");
    @assert(contains(wire, "Set-Cookie: b=2; Path=/\r\n"), "missing second Set-Cookie");
}

fn void test_auto_connection()
{
    aiohttp::Response* res = aiohttp::response_text("ok")!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "Connection: close\r\n"), "missing default Connection header");
}

fn void test_manual_content_length_preserved()
{
    aiohttp::Response* res = aiohttp::response_text("hello")!!;
    defer aiohttp::response_free(res);

    res.content_length(999)!!;

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "Content-Length: 999\r\n"), "manual Content-Length not preserved");
}

fn void test_no_body_status_204()
{
    aiohttp::Response* res = aiohttp::response_text("hello")!!;
    defer aiohttp::response_free(res);

    res.set_status(204)!!;

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 204 No Content\r\n"), "missing 204 status line");
    @assert(contains(wire, "Content-Length: 0\r\n"), "204 should serialize Content-Length: 0");
    @assert(!contains(wire, "\r\n\r\nhello"), "204 response must not include body");
}

fn void test_redirect()
{
    aiohttp::Response* res = aiohttp::response_redirect("/new-page", 302)!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 302 Moved Temporarily\r\n"), "missing redirect status line");
    @assert(contains(wire, "Location: /new-page\r\n"), "missing Location header");
}

fn void test_write_to_small_buffer()
{
    aiohttp::Response* res = aiohttp::response_text("hello")!!;
    defer aiohttp::response_free(res);

    char[4] small;
    sz n = res.write_to(small[..]);

    @assert(n == 0, "small buffer should fail with 0");
}

fn void test_write_to_exact_buffer()
{
    aiohttp::Response* res = aiohttp::response_text("hello")!!;
    defer aiohttp::response_free(res);

    sz need = res.serialized_len();

    char* p = aiohttp::localmem.malloc(need)!!;
    defer aiohttp::localmem.free(p);

    char[] out = p[0:need];

    sz n = res.write_to(out);

    @assert(n == need, "write_to exact buffer length mismatch");

    String wire = (String)out;
    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "missing status line");
    @assert(contains(wire, "\r\n\r\nhello"), "missing body");
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

    io::printfn("test_response: OK");
}

// eof