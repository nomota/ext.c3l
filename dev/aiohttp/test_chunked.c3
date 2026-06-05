// test_chunked.c3

// Chunked transfer decoding tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::chunked;

import std::io;
import ext::aiohttp;
import ext::debug;

fn bool contains(String haystack, String needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn aiohttp::Response*? echo_text_handler(aiohttp::Context* c)
{
    return c.text(c.req_text())!!;
}

fn aiohttp::Response*? echo_len_handler(aiohttp::Context* c)
{
    char[64] buf;
    String s = string::bformat(buf[..], "%d", c.req_bytes().len);

    return c.text(s)!!;
}

fn void test_chunked_decode_basic()
{
    char[] raw =
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "Wikipedia", "chunked basic body mismatch");
    @assert(r.consumed == raw.len, "chunked basic consumed mismatch");
}

fn void test_chunked_decode_empty()
{
    char[] raw =
        "0\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert(r.body.len == 0, "chunked empty body len mismatch");
    @assert(r.consumed == raw.len, "chunked empty consumed mismatch");
}

fn void test_chunked_decode_single_chunk()
{
    char[] raw =
        "b\r\n"
        "hello world\r\n"
        "0\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "hello world", "chunked single body mismatch");
    @assert(r.consumed == raw.len, "chunked single consumed mismatch");
}

fn void test_chunked_decode_uppercase_hex()
{
    char[] raw =
        "A\r\n"
        "0123456789\r\n"
        "0\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "0123456789", "chunked uppercase hex body mismatch");
    @assert(r.consumed == raw.len, "chunked uppercase hex consumed mismatch");
}

fn void test_chunked_decode_chunk_extensions()
{
    char[] raw =
        "4;name=value\r\n"
        "Wiki\r\n"
        "5;foo=bar\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "Wikipedia", "chunked extension body mismatch");
    @assert(r.consumed == raw.len, "chunked extension consumed mismatch");
}

fn void test_chunked_decode_trailers()
{
    char[] raw =
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "X-Trailer: yes\r\n"
        "Another: value\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "Wikipedia", "chunked trailer body mismatch");
    @assert(r.consumed == raw.len, "chunked trailer consumed mismatch");
}

fn void test_chunked_decode_extra_bytes_after_message()
{
    char[] raw =
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "\r\n"
        "GET /next HTTP/1.1\r\n"
        "\r\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "Wiki", "chunked extra body mismatch");
    @assert(r.consumed == "4\r\nWiki\r\n0\r\n\r\n".len, "chunked extra consumed mismatch");
}

fn void test_chunked_decode_lf_only()
{
    char[] raw =
        "4\n"
        "Wiki\n"
        "5\n"
        "pedia\n"
        "0\n"
        "\n";

    aiohttp::ChunkedDecodeResult r = aiohttp::chunked_decode(raw)!!;
    defer aiohttp::localmem.free(r.body);

    @assert((String)r.body == "Wikipedia", "chunked LF-only body mismatch");
    @assert(r.consumed == raw.len, "chunked LF-only consumed mismatch");
}

fn void test_chunked_decode_incomplete_size_line()
{
    char[] raw = "4";

    if (catch err = aiohttp::chunked_decode(raw))
    {
        @assert(err == aiohttp::CHUNKED_BODY_INCOMPLETE, "incomplete size line fault mismatch");
        return;
    }

    @assert(false, "incomplete size line should fail");
}

fn void test_chunked_decode_incomplete_data()
{
    char[] raw =
        "5\r\n"
        "abc";

    if (catch err = aiohttp::chunked_decode(raw))
    {
        @assert(err == aiohttp::CHUNKED_BODY_INCOMPLETE, "incomplete data fault mismatch");
        return;
    }

    @assert(false, "incomplete data should fail");
}

fn void test_chunked_decode_missing_chunk_crlf()
{
    char[] raw =
        "3\r\n"
        "abc"
        "0\r\n"
        "\r\n";

    if (catch err = aiohttp::chunked_decode(raw))
    {
        @assert(err == aiohttp::INVALID_CHUNKED_BODY || err == aiohttp::CHUNKED_BODY_INCOMPLETE, "missing chunk CRLF fault mismatch");
        return;
    }

    @assert(false, "missing chunk CRLF should fail");
}

fn void test_chunked_decode_bad_hex()
{
    char[] raw =
        "Z\r\n"
        "abc\r\n"
        "0\r\n"
        "\r\n";

    if (catch err = aiohttp::chunked_decode(raw))
    {
        @assert(err == aiohttp::INVALID_CHUNKED_BODY, "bad hex fault mismatch");
        return;
    }

    @assert(false, "bad hex should fail");
}

fn void test_chunked_decode_empty_size()
{
    char[] raw =
        "\r\n"
        "abc\r\n"
        "0\r\n"
        "\r\n";

    if (catch err = aiohttp::chunked_decode(raw))
    {
        @assert(err == aiohttp::INVALID_CHUNKED_BODY, "empty size fault mismatch");
        return;
    }

    @assert(false, "empty size should fail");
}

fn void test_chunked_decode_missing_final_blank_line()
{
    char[] raw =
        "4\r\n"
        "Wiki\r\n"
        "0\r\n";

    if (catch err = aiohttp::chunked_decode(raw))
    {
        @assert(err == aiohttp::CHUNKED_BODY_INCOMPLETE, "missing final blank line fault mismatch");
        return;
    }

    @assert(false, "missing final blank line should fail");
}

fn void test_request_is_chunked_true()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "0\r\n"
        "\r\n";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.is_chunked(), "request is_chunked true mismatch");
}

fn void test_request_is_chunked_false()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "\r\n";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(!req.is_chunked(), "request is_chunked false mismatch");
}

fn void test_request_parse_chunked_body()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.is_chunked(), "parsed chunked request flag mismatch");
    @assert(req.body.len == "Wikipedia".len, "parsed chunked body len mismatch");
    @assert((String)req.body == "Wikipedia", "parsed chunked body mismatch");
}

fn void test_request_parse_chunked_with_trailer()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "X-Trailer: yes\r\n"
        "\r\n";

    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    defer aiohttp::request_free(req);

    @assert(req.body.len == "Wikipedia".len, "chunked trailer request body len mismatch");
    @assert((String)req.body == "Wikipedia", "chunked trailer request body mismatch");
}

fn void test_request_parse_chunked_incomplete_body()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "5\r\n"
        "abc";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::CHUNKED_BODY_INCOMPLETE, "chunked incomplete request fault mismatch");
        return;
    }

    @assert(false, "chunked incomplete request should fail");
}

fn void test_request_parse_chunked_bad_body()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "Z\r\n"
        "abc\r\n"
        "0\r\n"
        "\r\n";

    if (catch err = aiohttp::request_parse(raw))
    {
        @assert(err == aiohttp::INVALID_CHUNKED_BODY, "chunked bad request fault mismatch");
        return;
    }

    @assert(false, "chunked bad request should fail");
}

fn void test_application_chunked_echo()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/echo", &echo_text_handler)!!;

    aiohttp::Response* res = app.fetch_raw((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "chunked app echo status mismatch");
    @assert((String)res.body == "Wikipedia", "chunked app echo body mismatch");
}

fn void test_application_chunked_empty()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/echo-len", &echo_len_handler)!!;

    aiohttp::Response* res = app.fetch_raw((char[])
        "POST /echo-len HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "0\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "chunked empty app status mismatch");
    @assert((String)res.body == "0", "chunked empty app body mismatch");
}

fn void test_application_chunked_bad_request()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.post("/echo", &echo_text_handler)!!;

    aiohttp::Response* res = app.fetch_raw((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "Z\r\n"
        "abc\r\n"
        "0\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 400, "chunked bad app status mismatch");
    @assert((String)res.body == "400 Bad Request", "chunked bad app body mismatch");
}

fn void test_request_expected_total_len_chunked()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
        "GET /next HTTP/1.1\r\n"
        "\r\n";

    sz n = aiohttp::request_expected_total_len(raw)!!;

    @assert(n == (
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
    ).len, "chunked expected total len mismatch");
}

fn void test_request_message_complete_chunked_true()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "\r\n";

    @assert(aiohttp::request_message_complete(raw), "complete chunked message mismatch");
}

fn void test_request_message_complete_chunked_false()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wi";

    @assert(!aiohttp::request_message_complete(raw), "incomplete chunked message mismatch");
}

fn void test_request_expected_total_len_chunked_with_trailer()
{
    char[] raw =
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "X-Trailer: yes\r\n"
        "\r\n"
        "GET /next HTTP/1.1\r\n"
        "\r\n";

    sz n = aiohttp::request_expected_total_len(raw)!!;

    @assert(n == (
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "0\r\n"
        "X-Trailer: yes\r\n"
        "\r\n"
    ).len, "chunked trailer expected total len mismatch");
}

fn void main()
{
    test_chunked_decode_basic();
    test_chunked_decode_empty();
    test_chunked_decode_single_chunk();
    test_chunked_decode_uppercase_hex();
    test_chunked_decode_chunk_extensions();
    test_chunked_decode_trailers();
    test_chunked_decode_extra_bytes_after_message();
    test_chunked_decode_lf_only();

    test_chunked_decode_incomplete_size_line();
    test_chunked_decode_incomplete_data();
    test_chunked_decode_missing_chunk_crlf();
    test_chunked_decode_bad_hex();
    test_chunked_decode_empty_size();
    test_chunked_decode_missing_final_blank_line();

    test_request_is_chunked_true();
    test_request_is_chunked_false();
    test_request_parse_chunked_body();
    test_request_parse_chunked_with_trailer();
    test_request_parse_chunked_incomplete_body();
    test_request_parse_chunked_bad_body();

    test_application_chunked_echo();
    test_application_chunked_empty();
    test_application_chunked_bad_request();

    test_request_expected_total_len_chunked();
    test_request_message_complete_chunked_true();
    test_request_message_complete_chunked_false();
    test_request_expected_total_len_chunked_with_trailer();
 
    io::printfn("test_chunked: OK");
}

// eof 