// test_request.c3

module test::httpserver_request;

import std::io;
import ext::httpserver;
import ext::debug;

fn void test_basic_get()
{
    char[] raw = (char[])"GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    assert(req.method == "GET");
    assert(req.target == "/hello");
    assert(req.path == "/hello");
    assert(req.query_string == "");
    assert(req.version == "HTTP/1.1");

    String host = req.header("Host")!!;
    assert(host == "localhost");
}

fn void test_get_query()
{
    char[] raw = (char[])"GET /search?q=c3&page=1 HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    assert(req.target == "/search?q=c3&page=1");
    assert(req.path == "/search");
    assert(req.query_string == "q=c3&page=1");
}

fn void test_headers()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\nUser-Agent: curl\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    String host = req.header("host")!!;
    String ua = req.header("USER-AGENT")!!;

    assert(host == "localhost");
    assert(ua == "curl");
}

fn void test_post_body()
{
    char[] raw = (char[])"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nhello";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    assert(req.method == "POST");
    assert(req.path == "/echo");
    assert(req.has_body());
    assert(req.body.len == 5);
    assert((String)req.body == "hello");
}

fn void test_lf_only()
{
    char[] raw = (char[])"GET /hello HTTP/1.1\nHost: localhost\n\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    assert(req.method == "GET");
    assert(req.path == "/hello");

    String host = req.header("Host")!!;
    assert(host == "localhost");
}

fn void test_incomplete_body()
{
    char[] raw = (char[])"POST /echo HTTP/1.1\r\nContent-Length: 10\r\n\r\nhello";

    Request*? req = httpserver::request_parse(raw);

    if (catch err = req) {
        assert(err == httpserver::BODY_INCOMPLETE);
        return;
    }

    httpserver::request_free(req);
    @assert(false);
}

fn void test_invalid_method()
{
    char[] raw = (char[])"GE T / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request*? req = httpserver::request_parse(raw);

    if (catch err = req) {
        // warn("%s", err);
        assert(err == httpserver::BAD_REQUEST || err == httpserver::INVALID_METHOD || err == httpserver::INVALID_VERSION);
        return;
    }

    httpserver::request_free(req);
    @assert(false);
}

fn void test_invalid_version()
{
    char[] raw = (char[])"GET / HTTP/2.0\r\nHost: localhost\r\n\r\n";

    Request*? req = httpserver::request_parse(raw);

    if (catch err = req) {
        assert(err == httpserver::INVALID_VERSION);
        return;
    }

    httpserver::request_free(req);
    @assert(false);
}

fn void test_malformed_header()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nBadHeader\r\n\r\n";

    Request*? req = httpserver::request_parse(raw);

    if (catch err = req) {
        assert(err == httpserver::INVALID_HEADER);
        return;
    }

    httpserver::request_free(req);
    @assert(false);
}

fn void test_too_large_body_length()
{
    char[] raw = (char[])"POST / HTTP/1.1\r\nContent-Length: 999999999999999999999999999\r\n\r\n";

    Request*? req = httpserver::request_parse(raw);

    if (catch err = req) {
        assert(err == httpserver::REQUEST_TOO_LARGE);
        return;
    }

    httpserver::request_free(req);
    @assert(false);
}

fn void test_expected_total_len()
{
    char[] raw = (char[])"POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello trailing";

    sz n = httpserver::request_expected_total_len(raw)!!;

    assert(n == "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n".len + 5);
}

fn void test_message_complete()
{
    char[] ok = (char[])"POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello";
    char[] bad = (char[])"POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhe";

    assert(httpserver::request_message_complete(ok));
    assert(!httpserver::request_message_complete(bad));
}

fn void test_missing_header()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    Request* req = httpserver::request_parse(raw)!!;
    defer httpserver::request_free(req);

    String? v = req.header("Missing");

    if (catch err = v) {
        assert(err == httpserver::NOT_FOUND);
        return;
    }

    @assert(false);
}


fn void main()
{
    test_basic_get();
    test_get_query();
    test_headers();
    test_post_body();
    test_lf_only();
    test_incomplete_body();
    test_invalid_method();
    test_invalid_version();
    test_malformed_header();
    test_too_large_body_length();
    test_expected_total_len();
    test_message_complete();
    test_missing_header();
    io::printfn("test_request: ok");
}