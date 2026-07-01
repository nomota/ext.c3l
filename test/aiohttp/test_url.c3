// test_url.c3

module test::aio::http_url;

import std::io;
import ext::aio::http;
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

fn void test_url_decode_plain()
{
    String s = http::url_decode("hello")!!;
    defer http::localmem.free(s);

    @assert(s == "hello", "plain url decode failed");
}

fn void test_url_decode_percent()
{
    String s = http::url_decode("hello%20c3")!!;
    defer http::localmem.free(s);

    @assert(s == "hello c3", "percent url decode failed");
}

fn void test_url_decode_slash()
{
    String s = http::url_decode("docs%2Ffile.txt")!!;
    defer http::localmem.free(s);

    @assert(s == "docs/file.txt", "slash url decode failed");
}

fn void test_query_decode_plus()
{
    String s = http::query_decode("hello+c3")!!;
    defer http::localmem.free(s);

    @assert(s == "hello c3", "query plus decode failed");
}

fn void test_url_decode_plus_not_space()
{
    String s = http::url_decode("hello+c3")!!;
    defer http::localmem.free(s);

    @assert(s == "hello+c3", "url plus should not become space");
}

fn void test_invalid_percent_short()
{
    String? s = http::url_decode("abc%");

    if (catch err = s)
    {
        @assert(err == http::INVALID_URL_ENCODING, "expected INVALID_URL_ENCODING");
        return;
    }

    http::localmem.free(s);
    @assert(false, "invalid short percent should fail");
}

fn void test_invalid_percent_hex()
{
    String? s = http::url_decode("abc%ZZ");

    if (catch err = s)
    {
        @assert(err == http::INVALID_URL_ENCODING, "expected INVALID_URL_ENCODING");
        return;
    }

    http::localmem.free(s);
    @assert(false, "invalid hex percent should fail");
}

fn void test_query_parse_basic()
{
    http::Query q;
    q.init();
    defer q.free();

    http::query_parse(&q, "a=1&b=2")!!;

    String a = q.get("a")!!;
    String b = q.get("b")!!;

    @assert(a == "1", "query a mismatch");
    @assert(b == "2", "query b mismatch");
}

fn void test_query_parse_flag()
{
    http::Query q;
    q.init();
    defer q.free();

    http::query_parse(&q, "debug&x=1")!!;

    String debug = q.get("debug")!!;
    String x = q.get("x")!!;

    @assert(debug == "", "query flag should have empty value");
    @assert(x == "1", "query x mismatch");
}

fn void test_query_parse_empty_value()
{
    http::Query q;
    q.init();
    defer q.free();

    http::query_parse(&q, "a=&b=2")!!;

    String a = q.get("a")!!;
    String b = q.get("b")!!;

    @assert(a == "", "empty query value mismatch");
    @assert(b == "2", "query b mismatch");
}

fn void test_query_parse_plus_and_percent()
{
    http::Query q;
    q.init();
    defer q.free();

    http::query_parse(&q, "name=kim+lee&file=my%20doc.txt")!!;

    String name = q.get("name")!!;
    String file = q.get("file")!!;

    @assert(name == "kim lee", "query plus value mismatch");
    @assert(file == "my doc.txt", "query percent value mismatch");
}

fn void test_query_parse_repeated()
{
    http::Query q;
    q.init();
    defer q.free();

    http::query_parse(&q, "tag=a&tag=b")!!;

    String first = q.get("tag")!!;

    @assert(first == "a", "repeated query should return first value");
    @assert(q.len() == 2, "repeated query count mismatch");
}

fn void test_request_query_params()
{
    char[] raw = (char[])"GET /search?q=c3&page=1 HTTP/1.1\r\nHost: localhost\r\n\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::Query q = req.query_params()!!;
    defer q.free();

    String qv = q.get("q")!!;
    String page = q.get("page")!!;

    @assert(qv == "c3", "request query q mismatch");
    @assert(page == "1", "request query page mismatch");
}

fn void test_request_query_copy()
{
    char[] raw = (char[])"GET /search?q=hello+world HTTP/1.1\r\nHost: localhost\r\n\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    String q = req.query_copy("q")!!;
    defer http::localmem.free(q);

    @assert(q == "hello world", "request query copy mismatch");
}

fn void main()
{
    test_url_decode_plain();
    test_url_decode_percent();
    test_url_decode_slash();
    test_query_decode_plus();
    test_url_decode_plus_not_space();
    test_invalid_percent_short();
    test_invalid_percent_hex();

    test_query_parse_basic();
    test_query_parse_flag();
    test_query_parse_empty_value();
    test_query_parse_plus_and_percent();
    test_query_parse_repeated();

    test_request_query_params();
    test_request_query_copy();

    io::printfn("test_url: OK");
}

// eof