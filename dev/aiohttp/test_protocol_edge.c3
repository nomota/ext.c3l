// test_protocol_edge.c3

// Protocol edge tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::protocol_edge;

import std::io;
import ext::aio::http;
import ext::debug;

fn aio::http::Response*? echo_handler(aio::http::Context* c)
{
    return c.text(c.req_text())!!;
}

fn aio::http::Response*? home_handler(aio::http::Context* c)
{
    return c.text("home")!!;
}

fn void test_duplicate_same_content_length_allowed()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.body.len == 5, "duplicate same content-length body len mismatch");
    @assert((String)req.body == "hello", "duplicate same content-length body mismatch");
}

fn void test_conflicting_content_length_rejected()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "Content-Length: 6\r\n"
        "\r\n"
        "hello!";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::BAD_REQUEST || err == aio::http::INVALID_HEADER, "conflicting content-length fault mismatch");
        return;
    }

    @assert(false, "conflicting content-length should fail");
}

fn void test_content_length_and_chunked_rejected()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 4\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::BAD_REQUEST || err == aio::http::INVALID_HEADER, "content-length plus chunked fault mismatch");
        return;
    }

    @assert(false, "content-length plus chunked should fail");
}

fn void test_unsupported_transfer_encoding_rejected()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: gzip\r\n"
        "\r\n"
        "hello";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::BAD_REQUEST || err == aio::http::INVALID_HEADER, "unsupported transfer-encoding fault mismatch");
        return;
    }

    @assert(false, "unsupported transfer-encoding should fail");
}

fn void test_transfer_encoding_chunked_with_spaces()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding:   chunked   \r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.is_chunked(), "chunked with spaces flag mismatch");
    @assert((String)req.body == "Wiki", "chunked with spaces body mismatch");
}

fn void test_transfer_encoding_mixed_case()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: ChUnKeD\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.is_chunked(), "mixed case chunked flag mismatch");
    @assert((String)req.body == "Wiki", "mixed case chunked body mismatch");
}

fn void test_invalid_http_version_rejected()
{
    char[] raw =
        "GET / HTTP/2.0\r\n"
        "Host: localhost\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::INVALID_VERSION, "invalid HTTP version fault mismatch");
        return;
    }

    @assert(false, "invalid HTTP version should fail");
}

fn void test_empty_request_target_rejected()
{
    char[] raw =
        "GET  HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    if (catch err = aio::http::request_parse(raw))
    {
        @assert(err == aio::http::BAD_REQUEST, "empty request target fault mismatch");
        return;
    }

    @assert(false, "empty request target should fail");
}

fn void test_absolute_uri_target()
{
    char[] raw =
        "GET http://example.com/path?q=1 HTTP/1.1\r\n"
        "Host: example.com\r\n"
        "\r\n";

    aio::http::Request* req = aio::http::request_parse(raw)!!;
    defer aio::http::request_free(req);

    @assert(req.target == "http://example.com/path?q=1", "absolute URI target mismatch");
}

fn void test_header_too_large_rejected()
{
    DString raw;
    raw.init(aio::http::localmem, aio::http::MAX_HEADER_BYTES + 1024);
    defer raw.free();

    raw.append((char[])"GET / HTTP/1.1\r\n");
    raw.append((char[])"Host: localhost\r\n");
    raw.append((char[])"X-Large: ");

    for (sz i = 0; i < aio::http::MAX_HEADER_BYTES + 32; i++)
    {
        raw.append((char[])"x");
    }

    raw.append((char[])"\r\n\r\n");

    if (catch err = aio::http::request_parse((char[])raw.str_view()))
    {
        @assert(err == aio::http::REQUEST_TOO_LARGE, "large header fault mismatch");
        return;
    }

    @assert(false, "large header should fail");
}

fn void test_request_line_too_large_rejected()
{
    DString raw;
    raw.init(aio::http::localmem, aio::http::MAX_REQUEST_LINE_LEN + 1024);
    defer raw.free();

    raw.append((char[])"GET /");

    for (sz i = 0; i < aio::http::MAX_REQUEST_LINE_LEN + 16; i++)
    {
        raw.append((char[])"x");
    }

    raw.append((char[])" HTTP/1.1\r\n");
    raw.append((char[])"Host: localhost\r\n");
    raw.append((char[])"\r\n");

    if (catch err = aio::http::request_parse((char[])raw.str_view()))
    {
        @assert(err == aio::http::BAD_REQUEST || err == aio::http::REQUEST_TOO_LARGE, "large request line fault mismatch");
        return;
    }

    @assert(false, "large request line should fail");
}

fn void test_body_too_large_rejected()
{
    DString raw;
    raw.init(aio::http::localmem, 256);
    defer raw.free();

    raw.appendf(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: %d\r\n"
        "\r\n",
        aio::http::MAX_BODY_BYTES + 1
    )!!;

    if (catch err = aio::http::request_parse((char[])raw.str_view()))
    {
        @assert(err == aio::http::REQUEST_TOO_LARGE, "body too large fault mismatch");
        return;
    }

    @assert(false, "body too large should fail");
}

fn void test_application_bad_request_for_protocol_error()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.post("/echo", &echo_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: abc\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 400, "protocol bad request app status mismatch");
    @assert((String)res.body == "400 Bad Request", "protocol bad request app body mismatch");
}

fn void test_application_ok_after_edge_setup()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &home_handler)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "app ok status mismatch");
    @assert((String)res.body == "home", "app ok body mismatch");
}

fn void main()
{
    test_duplicate_same_content_length_allowed();
    test_conflicting_content_length_rejected();
    test_content_length_and_chunked_rejected();

    test_unsupported_transfer_encoding_rejected();
    test_transfer_encoding_chunked_with_spaces();
    test_transfer_encoding_mixed_case();

    test_invalid_http_version_rejected();
    test_empty_request_target_rejected();
    test_absolute_uri_target();

    test_header_too_large_rejected();
    test_request_line_too_large_rejected();
    test_body_too_large_rejected();

    test_application_bad_request_for_protocol_error();
    test_application_ok_after_edge_setup();

    io::printfn("test_protocol_edge: OK");
}

// eof
