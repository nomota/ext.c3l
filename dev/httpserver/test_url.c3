// test_url.c3

module test::httpserver_url;

import std::io;
import ext::httpserver;
import ext::debug;

fn void test_url_decode_plain()
{
    String s = httpserver::url_decode("hello")!!;
    defer httpserver::localmem.free(s);

    assert(s == "hello");
}

fn void test_url_decode_percent()
{
    String s = httpserver::url_decode("hello%20c3")!!;
    defer httpserver::localmem.free(s);

    assert(s == "hello c3");
}

fn void test_url_decode_slash()
{
    String s = httpserver::url_decode("docs%2Ffile.txt")!!;
    defer httpserver::localmem.free(s);

    assert(s == "docs/file.txt");
}

fn void test_query_decode_plus()
{
    String s = httpserver::query_decode("hello+c3")!!;
    defer httpserver::localmem.free(s);

    assert(s == "hello c3");
}

fn void test_url_decode_plus_not_space()
{
    String s = httpserver::url_decode("hello+c3")!!;
    defer httpserver::localmem.free(s);

    assert(s == "hello+c3");
}

fn void test_invalid_percent_short()
{
    String? s = httpserver::url_decode("abc%");

    if (catch err = s) {
        assert(err == httpserver::INVALID_URL_ENCODING);
        return;
    }

    httpserver::localmem.free(s);
    @assert(false);
}

fn void test_invalid_percent_hex()
{
    String? s = httpserver::url_decode("abc%ZZ");

    if (catch err = s) {
        assert(err == httpserver::INVALID_URL_ENCODING);
        return;
    }

    httpserver::localmem.free(s);
    @assert(false);
}

fn void test_query_parse_basic()
{
    Query q;
    q.init();
    defer q.free();

    httpserver::query_parse(&q, "a=1&b=2")!!;

    String a = q.get("a")!!;
    String b = q.get("b")!!;

    assert(a == "1");
    assert(b == "2");
}

fn void test_query_parse_flag()
{
    Query q;
    q.init();
    defer q.free();

    httpserver::query_parse(&q, "debug&x=1")!!;

    String debug = q.get("debug")!!;
    String x = q.get("x")!!;

    assert(debug == "");
    assert(x == "1");
}

fn void test_query_parse_empty_value()
{
    Query q;
    q.init();
    defer q.free();

    httpserver::query_parse(&q, "a=&b=2")!!;

    String a = q.get("a")!!;
    String b = q.get("b")!!;

    assert(a == "");
    assert(b == "2");
}

fn void test_query_parse_plus_and_percent()
{
    Query q;
    q.init();
    defer q.free();

    httpserver::query_parse(&q, "name=kim+lee&file=my%20doc.txt")!!;

    String name = q.get("name")!!;
    String file = q.get("file")!!;

    assert(name == "kim lee");
    assert(file == "my doc.txt");
}

fn void test_query_parse_repeated()
{
    Query q;
    q.init();
    defer q.free();

    httpserver::query_parse(&q, "tag=a&tag=b")!!;

    String first = q.get("tag")!!;

    // KeyVals.get() returns the first matching value.
    assert(first == "a");
    assert(q.len() == 2);
}

fn void test_request_query_params()
{
    char[] raw = (char[])"GET /search?q=c3&page=1 HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    Query q = req.query_params()!!;
    defer q.free();

    String qv = q.get("q")!!;
    String page = q.get("page")!!;

    assert(qv == "c3");
    assert(page == "1");
}

fn void test_request_query_copy()
{
    char[] raw = (char[])"GET /search?q=hello+world HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    String q = req.query_copy("q")!!;
    defer httpserver::localmem.free(q);

    assert(q == "hello world");
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

    io::printfn("test_url: ok");
}