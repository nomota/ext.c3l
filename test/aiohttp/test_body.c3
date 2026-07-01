// test_body.c3

// Request body helper tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::body;

import std::io;
import ext::aio::http;
import ext::debug;

fn http::Request* parse_request(char[] raw)
{
    return http::request_parse(raw)!!;
}

fn http::Context* context_from_raw(char[] raw)
{
    http::Request* req = parse_request(raw);

    http::Context* c = http::context_new(req)!!;

    return c;
}

fn void context_from_raw_free(http::Context* c)
{
    if (c == null) return;

    http::Request* req = c.req;

    http::context_free(c);

    if (req != null)
    {
        http::request_free(req);
    }
}

fn void test_content_type_base_plain()
{
    String base = http::content_type_base("application/json");

    @assert(base == "application/json", "plain content type base mismatch");
}

fn void test_content_type_base_with_charset()
{
    String base = http::content_type_base("application/json; charset=utf-8");

    @assert(base == "application/json", "charset content type base mismatch");
}

fn void test_content_type_base_trims()
{
    String base = http::content_type_base("  text/plain ; charset=utf-8  ");

    @assert(base == "text/plain", "trimmed content type base mismatch");
}

fn void test_request_content_type_is()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.content_type_is("application/json"), "content_type_is json mismatch");
    @assert(!req.content_type_is("text/plain"), "content_type_is false mismatch");
}

fn void test_context_content_type_is()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Context* c = context_from_raw(raw);
    defer context_from_raw_free(c);

    @assert(c.content_type_is("text/plain"), "context content_type_is mismatch");
    @assert(!c.content_type_is("application/json"), "context content_type_is false mismatch");
}

fn void test_request_is_json_application_json()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_json(), "application/json should be json");
}

fn void test_request_is_json_vendor_json()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/problem+json; charset=utf-8\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_json(), "vendor +json should be json");
}

fn void test_request_is_not_json()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(!req.is_json(), "text/plain should not be json");
}

fn void test_request_is_text_plain()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_text(), "text/plain should be text");
}

fn void test_request_is_text_subtype()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/csv; charset=utf-8\r\n"
        "Content-Length: 7\r\n"
        "\r\n"
        "a,b,c\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_text(), "text/csv should be text");
}

fn void test_request_is_html()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/html; charset=utf-8\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "<h1>Hi</h1>";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_html(), "text/html should be html");
}

fn void test_request_is_octet_stream()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/octet-stream\r\n"
        "Content-Length: 4\r\n"
        "\r\n"
        "data";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    @assert(req.is_octet_stream(), "application/octet-stream mismatch");
}

fn void test_context_body_type_checks()
{
    char[] raw =
        "POST /json HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Context* c = context_from_raw(raw);
    defer context_from_raw_free(c);

    @assert(c.req_is_json(), "context req_is_json mismatch");
    @assert(!c.req_is_text(), "context req_is_text false mismatch");
    @assert(!c.req_is_html(), "context req_is_html false mismatch");
    @assert(!c.req_is_octet_stream(), "context req_is_octet_stream false mismatch");
}

fn void test_request_bytes()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    char[] body = req.bytes();

    @assert(body.len == 5, "bytes len mismatch");
    @assert((String)body == "hello", "bytes body mismatch");
}

fn void test_request_text()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    String text = req.text();

    @assert(text == "hello", "request text mismatch");
}

fn void test_request_json_text()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    String json = req.json_text();

    @assert(json == "{\"ok\":true}", "request json_text mismatch");
}

fn void test_request_bytes_copy()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    char[] copied = req.bytes_copy()!!;
    defer http::localmem.free(copied);

    @assert(copied.len == 5, "bytes_copy len mismatch");
    @assert((String)copied == "hello", "bytes_copy value mismatch");
}

fn void test_request_text_copy()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    String copied = req.text_copy()!!;
    defer http::localmem.free(copied);

    @assert(copied == "hello", "text_copy mismatch");
}

fn void test_empty_body_copies()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    http::Request* req = parse_request(raw);
    defer http::request_free(req);

    if (catch err = req.bytes_copy())
    {
        @assert(err == http::EMPTY_BODY, "empty bytes_copy fault mismatch");
    }
    else
    {
        @assert(false, "empty bytes_copy should fail");
    }

    if (catch err = req.text_copy())
    {
        @assert(err == http::EMPTY_BODY, "empty text_copy fault mismatch");
        return;
    }

    @assert(false, "empty text_copy should fail");
}

fn void test_context_body_readers()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Context* c = context_from_raw(raw);
    defer context_from_raw_free(c);

    @assert((String)c.req_bytes() == "{\"ok\":true}", "context req_bytes mismatch");
    @assert(c.req_text() == "{\"ok\":true}", "context req_text mismatch");
    @assert(c.req_json_text() == "{\"ok\":true}", "context req_json_text mismatch");
}

fn void test_context_body_copy_helpers()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    http::Context* c = context_from_raw(raw);
    defer context_from_raw_free(c);

    char[] copied = c.req_bytes_copy()!!;
    defer http::localmem.free(copied);

    String text = c.req_text_copy()!!;
    defer http::localmem.free(text);

    @assert((String)copied == "hello", "context req_bytes_copy mismatch");
    @assert(text == "hello", "context req_text_copy mismatch");
}

fn void test_context_null_request_body_readers()
{
    http::Context c = {};

    @assert(c.req_bytes().len == 0, "null context req_bytes mismatch");
    @assert(c.req_text() == "", "null context req_text mismatch");
    @assert(c.req_json_text() == "", "null context req_json_text mismatch");

    if (catch err = c.req_bytes_copy())
    {
        @assert(err == http::EMPTY_BODY, "null context req_bytes_copy fault mismatch");
    }
    else
    {
        @assert(false, "null context req_bytes_copy should fail");
    }

    if (catch err = c.req_text_copy())
    {
        @assert(err == http::EMPTY_BODY, "null context req_text_copy fault mismatch");
        return;
    }
    else
    {
        @assert(false, "null context req_text_copy should fail");
    }
}

fn void test_require_helpers()
{
    char[] raw =
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"ok\":true}";

    http::Context* c = context_from_raw(raw);
    defer context_from_raw_free(c);

    @assert(c.require_json(), "require_json mismatch");
    @assert(!c.require_text(), "require_text false mismatch");
}

fn void main()
{
    test_content_type_base_plain();
    test_content_type_base_with_charset();
    test_content_type_base_trims();

    test_request_content_type_is();
    test_context_content_type_is();

    test_request_is_json_application_json();
    test_request_is_json_vendor_json();
    test_request_is_not_json();
    test_request_is_text_plain();
    test_request_is_text_subtype();
    test_request_is_html();
    test_request_is_octet_stream();

    test_context_body_type_checks();

    test_request_bytes();
    test_request_text();
    test_request_json_text();
    test_request_bytes_copy();
    test_request_text_copy();
    test_empty_body_copies();

    test_context_body_readers();
    test_context_body_copy_helpers();
    test_context_null_request_body_readers();

    test_require_helpers();

    io::printfn("test_body: OK");
}

// eof