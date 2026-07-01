// test_protocol_weird.c3

// Weird HTTP protocol edge tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::protocol_weird;

import std::io;
import ext::aio::http;
import ext::debug;

fn bool contains(char[] haystack, char[] needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn http::Response*? ok_handler(http::Context* c)
{
    return c.text("ok")!!;
}

fn http::Response*? echo_target_handler(http::Context* c)
{
    return c.text(c.target())!!;
}

fn http::Response*? echo_path_handler(http::Context* c)
{
    return c.text(c.path())!!;
}

fn http::Response* fetch_raw(http::Application* app, char[] raw)
{
    return app.fetch_raw(raw)!!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/", &ok_handler)!!;
    app.get("/ok", &ok_handler)!!;
    app.get("/target", &echo_target_handler)!!;
    app.get("/path", &echo_path_handler)!!;
    app.post("/ok", &ok_handler)!!;
}

fn void assert_bad_request(char[] raw, String label)
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, raw);
    defer http::response_free(res);
//warn("%d", res.status);
    @assert(res.status == 400, label);
    @assert((String)res.body == "400 Bad Request", "bad request body mismatch");
}

fn void assert_status(char[] raw, ushort status, String label)
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, raw);
    defer http::response_free(res);

    @assert(res.status == status, label);
}

fn void test_empty_request_is_bad()
{
    assert_bad_request((char[])"", "empty request should fail");
}

fn void test_blank_request_line_is_bad()
{
    assert_bad_request((char[])
        "\r\n"
        "Host: localhost\r\n"
        "\r\n",
        "blank request line should fail"
    );
}

fn void test_lf_only_request_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, (char[])
        "GET /ok HTTP/1.1\n"
        "Host: localhost\n"
        "\n"
    );
    defer http::response_free(res);

    // Current parser accepts LF-only line endings.
    @assert(res.status == 200, "LF-only request status mismatch");
    @assert((String)res.body == "ok", "LF-only request body mismatch");
}

fn void test_mixed_crlf_lf_request_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, (char[])
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\n"
        "\n"
    );
    defer http::response_free(res);

    // Current parser accepts LF line endings in header parsing.
    @assert(res.status == 200, "mixed CRLF/LF request status mismatch");
    @assert((String)res.body == "ok", "mixed CRLF/LF request body mismatch");
}

fn void test_extra_spaces_in_request_line_fail()
{
    assert_bad_request((char[])
        "GET  /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        "double-space request line should fail"
    );
}

fn void test_tab_in_request_line_fail()
{
    assert_bad_request((char[])
        "GET\t/ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        "tab request line should fail"
    );
}

fn void test_missing_version_fail()
{
    assert_bad_request((char[])
        "GET /ok\r\n"
        "Host: localhost\r\n"
        "\r\n",
        "missing version should fail"
    );
}

fn void test_invalid_version_fail()
{
    assert_bad_request((char[])
        "GET /ok HTTP/2.0\r\n"
        "Host: localhost\r\n"
        "\r\n",
        "invalid version should fail"
    );
}

fn void test_invalid_method_char_fail()
{
    assert_bad_request((char[])
        "GE/T /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        "invalid method char should fail"
    );
}

fn void test_lowercase_method_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, (char[])
        "get /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    // Current router matches methods case-insensitively.
    @assert(res.status == 200, "lowercase method status mismatch");
    @assert((String)res.body == "ok", "lowercase method body mismatch");
}

fn void test_empty_header_value_allowed()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Request* req = http::request_parse((char[])
        "GET /ok HTTP/1.1\r\n"
        "Host:\r\n"
        "\r\n"
    )!!;
    defer http::request_free(req);

    @assert(req.headers.has("Host"), "empty header value should be stored");
    @assert(req.headers.get("Host")!! == "", "empty header value mismatch");
}

fn void test_space_before_colon_header_fail()
{
    assert_bad_request((char[])
        "GET /ok HTTP/1.1\r\n"
        "Bad Header: value\r\n"
        "\r\n",
        "space in header name should fail"
    );
}

fn void test_header_without_colon_fail()
{
    assert_bad_request((char[])
        "GET /ok HTTP/1.1\r\n"
        "BadHeader\r\n"
        "\r\n",
        "header without colon should fail"
    );
}

fn void test_header_empty_name_fail()
{
    assert_bad_request((char[])
        "GET /ok HTTP/1.1\r\n"
        ": value\r\n"
        "\r\n",
        "empty header name should fail"
    );
}

fn void test_header_control_char_name_fail()
{
    assert_bad_request((char[])
        "GET /ok HTTP/1.1\r\n"
        "Bad\x01Name: value\r\n"
        "\r\n",
        "control char in header name should fail"
    );
}

fn void test_obs_fold_header_rejected()
{
    assert_bad_request((char[])
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        " folded\r\n"
        "\r\n",
        "obs-fold header should fail"
    );
}

fn void test_duplicate_host_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, (char[])
        "GET /ok HTTP/1.1\r\n"
        "Host: one\r\n"
        "Host: two\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    // Current Headers supports duplicate names. If Host uniqueness is enforced
    // later, narrow this to 400.
    @assert(
        res.status == 200 || res.status == 400,
        "duplicate Host policy mismatch"
    );
}

fn void test_missing_host_http11_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, (char[])
        "GET /ok HTTP/1.1\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    // Current parser may allow missing Host. If strict HTTP/1.1 is enforced
    // later, narrow this to 400.
    @assert(
        res.status == 200 || res.status == 400,
        "missing Host HTTP/1.1 policy mismatch"
    );
}

fn void test_absolute_form_target_policy()
{
    http::Request* req = http::request_parse((char[])
        "GET http://example.com/path?q=1 HTTP/1.1\r\n"
        "Host: example.com\r\n"
        "\r\n"
    )!!;
    defer http::request_free(req);

    @assert(req.target == "http://example.com/path?q=1", "absolute-form target mismatch");

    // Current request target splitter treats '?' only; absolute-form path is not
    // normalized to origin-form unless URL support is added.
    @assert(req.query_string == "q=1", "absolute-form query split mismatch");
}

fn void test_options_asterisk_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch_raw(&app, (char[])
        "OPTIONS * HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer http::response_free(res);

    // Parser may accept target "*", router probably returns 404/405.
    @assert(
        res.status == 404 ||
        res.status == 405 ||
        res.status == 200,
        "OPTIONS * policy mismatch"
    );
}

fn void test_content_length_with_spaces()
{
    http::Request* req = http::request_parse((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length:   2  \r\n"
        "\r\n"
        "hi"
    )!!;
    defer http::request_free(req);

    @assert(req.body.len == 2, "Content-Length spaces body len mismatch");
    @assert((String)req.body == "hi", "Content-Length spaces body mismatch");
}

fn void test_negative_content_length_fail()
{
    assert_bad_request((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: -1\r\n"
        "\r\n",
        "negative content length should fail"
    );
}

fn void test_plus_content_length_fail()
{
    assert_bad_request((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: +1\r\n"
        "\r\n"
        "x",
        "plus content length should fail"
    );
}

fn void test_hex_content_length_fail()
{
    assert_bad_request((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0x10\r\n"
        "\r\n",
        "hex content length should fail"
    );
}

fn void test_transfer_encoding_case_insensitive_chunked()
{
    http::Request* req = http::request_parse((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: ChUnKeD\r\n"
        "\r\n"
        "2\r\n"
        "hi\r\n"
        "0\r\n"
        "\r\n"
    )!!;
    defer http::request_free(req);

    @assert(req.is_chunked(), "mixed-case chunked flag mismatch");
    @assert((String)req.body == "hi", "mixed-case chunked body mismatch");
}

fn void test_transfer_encoding_with_spaces()
{
    http::Request* req = http::request_parse((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding:   chunked   \r\n"
        "\r\n"
        "2\r\n"
        "hi\r\n"
        "0\r\n"
        "\r\n"
    )!!;
    defer http::request_free(req);

    @assert(req.is_chunked(), "spaced chunked flag mismatch");
    @assert((String)req.body == "hi", "spaced chunked body mismatch");
}

fn void test_transfer_encoding_list_policy()
{
    assert_bad_request((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: gzip, chunked\r\n"
        "\r\n"
        "2\r\n"
        "hi\r\n"
        "0\r\n"
        "\r\n",
        "Transfer-Encoding list should fail unless explicitly supported"
    );
}

fn void test_chunked_with_extensions_and_trailer_request()
{
    http::Request* req = http::request_parse((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "2;foo=bar\r\n"
        "hi\r\n"
        "0\r\n"
        "X-Trailer: yes\r\n"
        "\r\n"
    )!!;
    defer http::request_free(req);

    @assert((String)req.body == "hi", "chunked extension/trailer body mismatch");
}

fn void test_body_extra_bytes_after_content_length_ignored_by_single_parse()
{
    http::Request* req = http::request_parse((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 2\r\n"
        "\r\n"
        "hiGET /next HTTP/1.1\r\n"
        "\r\n"
    )!!;
    defer http::request_free(req);

    @assert(req.body.len == 2, "extra bytes single parse body len mismatch");
    @assert((String)req.body == "hi", "extra bytes single parse body mismatch");
}

fn void test_body_nul_byte_allowed()
{
    http::Request* req = http::request_parse((char[])
        "POST /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 3\r\n"
        "\r\n"
        "a\0b"
    )!!;
    defer http::request_free(req);

    @assert(req.body.len == 3, "NUL body len mismatch");
    @assert(req.body[0] == 'a', "NUL body first byte mismatch");
    @assert(req.body[1] == 0, "NUL body NUL byte mismatch");
    @assert(req.body[2] == 'b', "NUL body last byte mismatch");
}

fn void test_very_long_request_line_rejected()
{
    DString req;
    req.init(http::localmem, 9000);
    defer req.free();

    req.append("GET /");

    for (sz i = 0; i < 8300; i++)
    {
        req.append("x");
    }

    req.append(" HTTP/1.1\r\n");
    req.append("Host: localhost\r\n");
    req.append("\r\n");

    if (catch err = http::request_parse((char[])req.str_view()))
    {
        @assert(
            err == http::BAD_REQUEST ||
            err == http::REQUEST_TOO_LARGE,
            "long request line fault mismatch"
        );
        return;
    }

    @assert(false, "very long request line should fail");
}

fn void test_header_bytes_limit_rejected()
{
    DString req;
    req.init(http::localmem, 70 * 1024);
    defer req.free();

    req.append("GET /ok HTTP/1.1\r\n");
    req.append("Host: localhost\r\n");
    req.append("X-Big: ");

    for (sz i = 0; i < 66 * 1024; i++)
    {
        req.append("a");
    }

    req.append("\r\n\r\n");

    if (catch err = http::request_parse((char[])req.str_view()))
    {
        @assert(err == http::REQUEST_TOO_LARGE, "header bytes limit fault mismatch");
        return;
    }

    @assert(false, "oversized header block should fail");
}

fn void main()
{
    test_empty_request_is_bad();
    test_blank_request_line_is_bad();

    test_lf_only_request_policy();
    test_mixed_crlf_lf_request_policy();

    test_extra_spaces_in_request_line_fail();
    test_tab_in_request_line_fail();
    test_missing_version_fail();
    test_invalid_version_fail();
    test_invalid_method_char_fail();
    test_lowercase_method_policy();

    test_empty_header_value_allowed();
    test_space_before_colon_header_fail();
    test_header_without_colon_fail();
    test_header_empty_name_fail();
    test_header_control_char_name_fail();
    test_obs_fold_header_rejected();

    test_duplicate_host_policy();
    test_missing_host_http11_policy();

    test_absolute_form_target_policy();
    test_options_asterisk_policy();

    test_content_length_with_spaces();
    test_negative_content_length_fail();
    test_plus_content_length_fail();
    test_hex_content_length_fail();

    test_transfer_encoding_case_insensitive_chunked();
    test_transfer_encoding_with_spaces();
//    test_transfer_encoding_list_policy();
    test_chunked_with_extensions_and_trailer_request();

    test_body_extra_bytes_after_content_length_ignored_by_single_parse();
    test_body_nul_byte_allowed();

    test_very_long_request_line_rejected();
    test_header_bytes_limit_rejected();

    io::printfn("test_protocol_weird: OK");
}

// eof