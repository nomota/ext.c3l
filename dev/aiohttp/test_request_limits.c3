// test_request_limits.c3

// Request size/limit tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::request_limits;

import std::io;
import ext::aiohttp;
import ext::debug;

fn void test_request_line_too_large()
{
    DString raw;
    raw.init(aiohttp::localmem, aiohttp::MAX_REQUEST_LINE_LEN + 128);
    defer raw.free();

    raw.append((char[])"GET /");

    for (sz i = 0; i < aiohttp::MAX_REQUEST_LINE_LEN; i++)
    {
        raw.append((char[])"a");
    }

    raw.append((char[])" HTTP/1.1\r\n");
    raw.append((char[])"Host: localhost\r\n");
    raw.append((char[])"\r\n");

    if (catch err = aiohttp::request_parse(raw.str_view()))
    {
        @assert(err == aiohttp::BAD_REQUEST, "too large request line fault mismatch");
        return;
    }

    @assert(false, "too large request line should fail");
}

fn void test_header_bytes_too_large()
{
    DString raw;
    raw.init(aiohttp::localmem, aiohttp::MAX_HEADER_BYTES + 1024);
    defer raw.free();

    raw.append((char[])"GET / HTTP/1.1\r\n");
    raw.append((char[])"Host: localhost\r\n");
    raw.append((char[])"X-Big: ");

    for (sz i = 0; i < aiohttp::MAX_HEADER_BYTES; i++)
    {
        raw.append((char[])"a");
    }

    raw.append((char[])"\r\n");
    raw.append((char[])"\r\n");

    if (catch err = aiohttp::request_parse(raw.str_view()))
    {
        @assert(err == aiohttp::REQUEST_TOO_LARGE, "too large headers fault mismatch");
        return;
    }

    @assert(false, "too large headers should fail");
}

fn void test_body_bytes_too_large_by_content_length()
{
    DString raw;
    raw.init(aiohttp::localmem, 256);
    defer raw.free();

    raw.append((char[])"POST / HTTP/1.1\r\n");
    raw.append((char[])"Host: localhost\r\n");
    raw.append((char[])"Content-Length: ");

    String len = string::tformat("%d", aiohttp::MAX_BODY_BYTES + 1);
    raw.append((char[])len);

    raw.append((char[])"\r\n");
    raw.append((char[])"\r\n");

    if (catch err = aiohttp::request_parse(raw.str_view()))
    {
        @assert(err == aiohttp::REQUEST_TOO_LARGE, "too large body content length fault mismatch");
        return;
    }

    @assert(false, "too large body content length should fail");
}

fn void test_content_length_overflow()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 99999999999999999999999999999999999999999999999999999999\r\n"
        "\r\n";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::REQUEST_TOO_LARGE, "content length overflow fault mismatch");
        return;
    }

    @assert(false, "content length overflow should fail");
}

fn void test_content_length_not_number()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: abc\r\n"
        "\r\n";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::BAD_REQUEST, "non-numeric content length fault mismatch");
        return;
    }

    @assert(false, "non-numeric content length should fail");
}

fn void test_content_length_with_spaces()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length:   5  \r\n"
        "\r\n"
        "hello";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.content_length()!! == 5, "spaced content length mismatch");
    @assert(req.body.len == 5, "spaced content length body len mismatch");
    @assert((String)req.body == "hello", "spaced content length body mismatch");
}

fn void test_body_shorter_than_content_length()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 10\r\n"
        "\r\n"
        "hello";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::BODY_INCOMPLETE, "short body fault mismatch");
        return;
    }

    @assert(false, "short body should fail");
}

fn void test_body_longer_than_content_length_allowed()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello trailing";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.body.len == 5, "body should be clipped to Content-Length");
    @assert((String)req.body == "hello", "body clipped value mismatch");
}

fn void test_missing_header_end()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::BAD_REQUEST, "missing header end fault mismatch");
        return;
    }

    @assert(false, "missing header end should fail");
}

fn void test_headers_complete_false_without_end()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n";

    @assert(!aiohttp::request_headers_complete(raw), "headers should not be complete");
}

fn void test_headers_complete_crlf()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    @assert(aiohttp::request_headers_complete(raw), "CRLF headers should be complete");
}

fn void test_headers_complete_lf()
{
    char[] raw =
        "GET / HTTP/1.1\n"
        "Host: localhost\n"
        "\n";

    @assert(aiohttp::request_headers_complete(raw), "LF headers should be complete");
}

fn void test_expected_total_len_without_header_end()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Content-Length: 5\r\n";

    if (catch err = aiohttp::request_expected_total_len(raw))
    {
        @assert(err == aiohttp::BODY_INCOMPLETE, "expected_total_len missing header end fault mismatch");
        return;
    }

    @assert(false, "expected_total_len without header end should fail");
}

fn void test_expected_total_len_get_no_body()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    sz n = aiohttp::request_expected_total_len(raw)!!;

    @assert(n == raw.len, "GET expected total length mismatch");
}

fn void test_expected_total_len_post_body()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello trailing";

    sz header_len =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "\r\n".len;

    sz n = aiohttp::request_expected_total_len(raw)!!;

    @assert(n == header_len + 5, "POST expected total length mismatch");
}

fn void test_message_complete_get()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    @assert(aiohttp::request_message_complete(raw), "GET message should be complete");
}

fn void test_message_complete_post()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    @assert(aiohttp::request_message_complete(raw), "POST message should be complete");
}

fn void test_message_incomplete_post()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "he";

    @assert(!aiohttp::request_message_complete(raw), "POST message should be incomplete");
}

fn void test_header_boundary_exact_small()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.method == "GET", "small header method mismatch");
    @assert(req.path == "/", "small header path mismatch");
}

fn void test_empty_content_length_zero()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.body.len == 0, "zero content length body mismatch");
    @assert(!req.has_body(), "zero content length should not have body");
}

fn void test_negative_content_length_rejected()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: -1\r\n"
        "\r\n";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::BAD_REQUEST, "negative content length fault mismatch");
        return;
    }

    @assert(false, "negative content length should fail");
}

fn void test_multiple_content_length_first_used()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "Content-Length: 10\r\n"
        "\r\n"
        "hello trailing";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.content_length()!! == 5, "first Content-Length should be used");
    @assert(req.body.len == 5, "multiple content length body len mismatch");
    @assert((String)req.body == "hello", "multiple content length body mismatch");
}

fn void main()
{
    test_request_line_too_large();
    test_header_bytes_too_large();

    test_body_bytes_too_large_by_content_length();
    test_content_length_overflow();
    test_content_length_not_number();
    test_content_length_with_spaces();
    test_negative_content_length_rejected();

    test_body_shorter_than_content_length();
    test_body_longer_than_content_length_allowed();

    test_missing_header_end();
    test_headers_complete_false_without_end();
    test_headers_complete_crlf();
    test_headers_complete_lf();

    test_expected_total_len_without_header_end();
    test_expected_total_len_get_no_body();
    test_expected_total_len_post_body();

    test_message_complete_get();
    test_message_complete_post();
    test_message_incomplete_post();

    test_header_boundary_exact_small();
    test_empty_content_length_zero();
    test_multiple_content_length_first_used();

    io::printfn("test_request_limits: OK");
}

// eof