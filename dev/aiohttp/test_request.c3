// test_request.c3

module test::aio::http_request;

import std::io;
import ext::aio::http;
import ext::debug;

fn void test_basic_get()
{
    char[] raw = (char[])"GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.method == "GET", "method mismatch");
    @assert(req.target == "/hello", "target mismatch");
    @assert(req.path == "/hello", "path mismatch");
    @assert(req.query_string == "", "query_string mismatch");
    @assert(req.version == "HTTP/1.1", "version mismatch");

    String host = req.header("Host")!!;
    @assert(host == "localhost", "host mismatch");
}

fn void test_get_query()
{
    char[] raw = (char[])"GET /search?q=c3&page=1 HTTP/1.1\r\nHost: localhost\r\n\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.target == "/search?q=c3&page=1", "target mismatch");
    @assert(req.path == "/search", "path mismatch");
    @assert(req.query_string == "q=c3&page=1", "query_string mismatch");
}

fn void test_headers()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\nUser-Agent: curl\r\n\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    String host = req.header("host")!!;
    String ua = req.header("USER-AGENT")!!;

    @assert(host == "localhost", "case-insensitive Host lookup failed");
    @assert(ua == "curl", "case-insensitive User-Agent lookup failed");
}

fn void test_post_body()
{
    char[] raw = (char[])"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nhello";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.method == "POST", "method mismatch");
    @assert(req.path == "/echo", "path mismatch");
    @assert(req.has_body(), "body missing");
    @assert(req.body.len == 5, "body length mismatch");
    @assert((String)req.body == "hello", "body text mismatch");
}

fn void test_lf_only()
{
    char[] raw = (char[])"GET /hello HTTP/1.1\nHost: localhost\n\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.method == "GET", "method mismatch");
    @assert(req.path == "/hello", "path mismatch");

    String host = req.header("Host")!!;
    @assert(host == "localhost", "host mismatch");
}

fn void test_incomplete_body()
{
    char[] raw = (char[])"POST /echo HTTP/1.1\r\nContent-Length: 10\r\n\r\nhello";

    aio::http::Request*? req = aio::http::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aio::http::BODY_INCOMPLETE, "expected BODY_INCOMPLETE");
        return;
    }

    aio::http::request_free(req);
    @assert(false, "expected incomplete body error");
}

fn void test_invalid_method()
{
    char[] raw = (char[])"GE T / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    aio::http::Request*? req = aio::http::request_parse(raw);

    if (catch err = req)
    {
        @assert(
            err == aio::http::BAD_REQUEST ||
            err == aio::http::INVALID_METHOD ||
            err == aio::http::INVALID_VERSION,
            "expected invalid method style error"
        );
        return;
    }

    aio::http::request_free(req);
    @assert(false, "expected invalid method error");
}

fn void test_invalid_version()
{
    char[] raw = (char[])"GET / HTTP/2.0\r\nHost: localhost\r\n\r\n";

    aio::http::Request*? req = aio::http::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aio::http::INVALID_VERSION, "expected INVALID_VERSION");
        return;
    }

    aio::http::request_free(req);
    @assert(false, "expected invalid version error");
}

fn void test_malformed_header()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nBadHeader\r\n\r\n";

    aio::http::Request*? req = aio::http::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aio::http::INVALID_HEADER, "expected INVALID_HEADER");
        return;
    }

    aio::http::request_free(req);
    @assert(false, "expected malformed header error");
}

fn void test_too_large_body_length()
{
    char[] raw = (char[])"POST / HTTP/1.1\r\nContent-Length: 999999999999999999999999999\r\n\r\n";

    aio::http::Request*? req = aio::http::request_parse(raw);

    if (catch err = req)
    {
        @assert(err == aio::http::REQUEST_TOO_LARGE, "expected REQUEST_TOO_LARGE");
        return;
    }

    aio::http::request_free(req);
    @assert(false, "expected too large body length error");
}

fn void test_expected_total_len()
{
    char[] raw = (char[])"POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello trailing";

    sz n = aio::http::request_expected_total_len(raw)!!;

    @assert(
        n == "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n".len + 5,
        "expected total length mismatch"
    );
}

fn void test_message_complete()
{
    char[] ok = (char[])"POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello";
    char[] bad = (char[])"POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhe";

    @assert(aio::http::request_message_complete(ok), "complete request not detected");
    @assert(!aio::http::request_message_complete(bad), "incomplete request detected as complete");
}

fn void test_missing_header()
{
    char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    String? v = req.header("Missing");

    if (catch err = v)
    {
        @assert(err == aio::http::NOT_FOUND, "expected NOT_FOUND");
        return;
    }

    @assert(false, "expected missing header error");
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

    io::printfn("test_request: OK");
}

// eof