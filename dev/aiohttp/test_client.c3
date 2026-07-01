// test_client.c3

// HTTP client unit tests.
//
// Tests URL parsing, query encoding, request serialization,
// response parsing, chunked decoding, cookies, redirects,
// HEAD responses, and malformed response handling.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::client;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::aio::request;
import ext::debug;


// Helpers

fn void assert_string(String actual, String expected, String message)
{
    if (actual != expected) {
        io::printfn("Expected: [%s]", expected);
        io::printfn("Actual:   [%s]", actual);
        @assert(false, message);
    }
}

fn void assert_bytes(char[] actual, char[] expected, String message)
{
    @assert(actual.len == expected.len, message);

    for (sz i = 0; i < actual.len; i++) {
        @assert(actual[i] == expected[i], message);
    }
}

fn void assert_contains(String text, String needle, String message)
{
    if (!text.contains(needle)) {
        io::printfn("Missing: [%s]", needle);
        io::printfn("Text:");
        io::printfn("%s", text);
        @assert(false, message);
    }
}

fn void assert_not_contains(String text, String needle, String message)
{
    if (text.contains(needle)) {
        io::printfn("Unexpected: [%s]", needle);
        io::printfn("Text:");
        io::printfn("%s", text);
        @assert(false, message);
    }
}


// URL parsing

fn void? test_parse_url_basic()
{
    request::Url url = request::parse_url("http://example.com/api/users?x=1")!;
    defer url.free();

    assert_string(url.scheme, "http", "scheme mismatch");
    assert_string(url.host, "example.com", "host mismatch");
    @assert(url.port == 80, "default port mismatch");
    assert_string(url.target, "/api/users?x=1", "target mismatch");
}

fn void? test_parse_url_port()
{
    request::Url url = request::parse_url("http://127.0.0.1:18080/test")!;
    defer url.free();

    assert_string(url.host, "127.0.0.1", "host with port mismatch");
    @assert(url.port == 18080, "explicit port mismatch");
    assert_string(url.target, "/test", "explicit port target mismatch");
}

fn void? test_parse_url_query_only()
{
    request::Url url = request::parse_url("http://example.com?x=1")!;
    defer url.free();

    assert_string(url.host, "example.com", "query-only host mismatch");
    assert_string(url.target, "/?x=1", "query-only target mismatch");
}

fn void? test_parse_url_fragment_removed()
{
    request::Url url = request::parse_url("http://example.com/a?x=1#section")!;
    defer url.free();

    assert_string(url.target, "/a?x=1", "URL fragment was not removed");
}

fn void? test_parse_url_ipv6()
{
    request::Url url = request::parse_url("http://[::1]:18100/path")!;
    defer url.free();

    assert_string(url.host, "::1", "IPv6 host mismatch");
    @assert(url.port == 18100, "IPv6 port mismatch");
    assert_string(url.target, "/path", "IPv6 target mismatch");
}

fn void? test_parse_url_invalid()
{
    if (catch err = request::parse_url("example.com/path")) {
        @assert(err == request::INVALID_URL, "unexpected missing-scheme fault");
    } else {
        @assert(false, "missing URL scheme accepted");
    }

    if (catch err = request::parse_url("https://example.com/")) {
        @assert(err == request::UNSUPPORTED_SCHEME, "unexpected HTTPS fault");
    } else {
        @assert(false, "unsupported HTTPS URL accepted");
    }

    if (catch err = request::parse_url("http://example.com:70000/")) {
        @assert(err == request::INVALID_URL, "unexpected invalid-port fault");
    } else {
        @assert(false, "invalid port accepted");
    }
}


// Query serialization

fn void? test_build_target_empty_query()
{
    request::Url url = request::parse_url("http://example.com/path")!;
    defer url.free();

    http::Query query;
    query.init();
    defer query.free();

    String target = request::build_target(&url, &query)!;
    defer http::str_free(target);

    assert_string(target, "/path", "empty query changed target");
}

fn void? test_build_target_query()
{
    request::Url url = request::parse_url("http://example.com/search")!;
    defer url.free();

    http::Query query;
    query.init();
    defer query.free();

    query.add("q", "hello world")!;
    query.add("page", "2")!;

    String target = request::build_target(&url, &query)!;
    defer http::str_free(target);

    assert_string(target, "/search?q=hello%20world&page=2", "query encoding mismatch");
}

fn void? test_build_target_existing_query()
{
    request::Url url = request::parse_url("http://example.com/search?lang=en")!;
    defer url.free();

    http::Query query;
    query.init();
    defer query.free();

    query.add("q", "c3")!;

    String target = request::build_target(&url, &query)!;
    defer http::str_free(target);

    assert_string(target, "/search?lang=en&q=c3", "existing query merge mismatch");
}

fn void? test_build_target_trailing_question()
{
    request::Url url = request::parse_url("http://example.com/search?")!;
    defer url.free();

    http::Query query;
    query.init();
    defer query.free();

    query.add("q", "c3")!;

    String target = request::build_target(&url, &query)!;
    defer http::str_free(target);

    assert_string(target, "/search?q=c3", "trailing question query mismatch");
}

fn void? test_build_target_trailing_ampersand()
{
    request::Url url = request::parse_url("http://example.com/search?a=1&")!;
    defer url.free();

    http::Query query;
    query.init();
    defer query.free();

    query.add("b", "2")!;

    String target = request::build_target(&url, &query)!;
    defer http::str_free(target);

    assert_string(target, "/search?a=1&b=2", "trailing ampersand query mismatch");
}


// Request serialization

fn void? test_build_get_request()
{
    request::Session session;
    session.init();
    defer session.deinit();

    request::Options options;
    options.init();
    defer options.free();

    options.headers.set("X-Test", "yes")!;
    options.cookies.set("request_cookie", "abc")!;
    options.data = (char[])"must-not-be-sent";

    request::Url url = request::parse_url("http://example.com/test")!;
    defer url.free();

    String raw = request::build_session_request(&session, "GET", &url, "/test", &options)!;
    defer request::localmem.free(raw);

    assert_contains(raw, "GET /test HTTP/1.1\r\n", "GET request line missing");
    assert_contains(raw, "Host: example.com\r\n", "Host header missing");
    assert_contains(raw, "X-Test: yes\r\n", "custom header missing");
    assert_contains(raw, "Cookie: request_cookie=abc\r\n", "request cookie missing");
    assert_contains(raw, "Connection: close\r\n", "Connection header missing");
    assert_not_contains(raw, "Content-Length:", "GET contains Content-Length");
    assert_not_contains(raw, "must-not-be-sent", "GET contains request body");
}

fn void? test_build_post_data_request()
{
    request::Session session;
    session.init();
    defer session.deinit();

    request::Options options;
    options.init();
    defer options.free();

    options.data = (char[])"hello";

    request::Url url = request::parse_url("http://example.com/submit")!;
    defer url.free();

    String raw = request::build_session_request(&session, "POST", &url, "/submit", &options)!;
    defer request::localmem.free(raw);

    assert_contains(raw, "POST /submit HTTP/1.1\r\n", "POST request line missing");
    assert_contains(raw, "Content-Length: 5\r\n", "POST Content-Length mismatch");
    assert_contains(raw, "\r\n\r\nhello", "POST body mismatch");
}

fn void? test_build_post_json_request()
{
    request::Session session;
    session.init();
    defer session.deinit();

    request::Options options;
    options.init();
    defer options.free();

    options.json = (char[])"{\"value\":1}";

    request::Url url = request::parse_url("http://example.com/json")!;
    defer url.free();

    String raw = request::build_session_request(&session, "POST", &url, "/json", &options)!;
    defer request::localmem.free(raw);

    assert_contains(raw, "Content-Type: application/json\r\n", "JSON content type missing");
    assert_contains(raw, "Content-Length: 11\r\n", "JSON Content-Length mismatch");
    assert_contains(raw, "\r\n\r\n{\"value\":1}", "JSON body mismatch");
}

fn void? test_build_head_request_without_body()
{
    request::Session session;
    session.init();
    defer session.deinit();

    request::Options options;
    options.init();
    defer options.free();

    options.data = (char[])"ignored";

    request::Url url = request::parse_url("http://example.com/resource")!;
    defer url.free();

    String raw = request::build_session_request(&session, "HEAD", &url, "/resource", &options)!;
    defer request::localmem.free(raw);

    assert_contains(raw, "HEAD /resource HTTP/1.1\r\n", "HEAD request line missing");
    assert_not_contains(raw, "Content-Length:", "HEAD contains Content-Length");
    assert_not_contains(raw, "ignored", "HEAD contains body");
}

fn void? test_session_and_request_cookies()
{
    request::Session session;
    session.init();
    defer session.deinit();

    session.cookies.set("session_a", "1")!;
    session.cookies.set("replace", "old")!;

    request::Options options;
    options.init();
    defer options.free();

    options.cookies.set("request_b", "2")!;
    options.cookies.set("replace", "new")!;

    request::Url url = request::parse_url("http://example.com/")!;
    defer url.free();

    String raw = request::build_session_request(&session, "GET", &url, "/", &options)!;
    defer request::localmem.free(raw);

    assert_contains(raw, "session_a=1", "session cookie missing");
    assert_contains(raw, "request_b=2", "request cookie missing");
    assert_contains(raw, "replace=new", "request cookie did not replace session cookie");
    assert_not_contains(raw, "replace=old", "replaced session cookie was serialized");
}

fn void? test_authorization_header()
{
    request::Session session;
    session.init();
    defer session.deinit();

    request::Options options;
    options.init();
    defer options.free();

    options.auth.bearer("secret-token");

    request::Url url = request::parse_url("http://example.com/private")!;
    defer url.free();

    String raw = request::build_session_request(&session, "GET", &url, "/private", &options)!;
    defer request::localmem.free(raw);

    assert_contains(raw, "Authorization: Bearer secret-token\r\n", "Bearer header mismatch");
}


// Options

fn void? test_options_validation()
{
    request::Options options;
    options.init();
    defer options.free();

    options.data = (char[])"data";
    options.json = (char[])"{}";

    if (catch err = options.validate()) {
        @assert(err == request::INVALID_OPTIONS, "unexpected data/json validation fault");
    } else {
        @assert(false, "data and json were accepted together");
    }

    options.data = {};
    options.json = {};
    options.auth.custom("Bad\r\nHeader", "value");

    if (catch err = options.validate()) {
        @assert(err == request::INVALID_AUTH, "unexpected invalid-auth fault");
    } else {
        @assert(false, "invalid authorization scheme accepted");
    }
}


// Status and headers

fn void? test_parse_status_line()
{
    ushort status = request::parse_status_line("HTTP/1.1 200 OK")!;
    @assert(status == 200, "status parsing mismatch");

    status = request::parse_status_line("HTTP/1.0 404 Not Found")!;
    @assert(status == 404, "HTTP/1.0 status parsing mismatch");

    if (catch err = request::parse_status_line("INVALID 200 OK")) {
        @assert(err == request::INVALID_STATUS, "unexpected invalid-status fault");
    } else {
        @assert(false, "invalid status line accepted");
    }
}

fn void? test_parse_headers()
{
    http::Headers headers;
    headers.init();
    defer headers.free();

    request::parse_headers(
        "Content-Type: text/plain\r\n"
        "Set-Cookie: a=1\r\n"
        "Set-Cookie: b=2",
        &headers
    )!;

    @assert(headers.len() == 3, "parsed header count mismatch");
    assert_string(headers.get("Content-Type")!, "text/plain", "Content-Type mismatch");
    assert_string(headers.value_at(1)!, "a=1", "first Set-Cookie mismatch");
    assert_string(headers.value_at(2)!, "b=2", "second Set-Cookie mismatch");
}

fn void? test_content_length()
{
    http::Headers headers;
    headers.init();
    defer headers.free();

    headers.add("Content-Length", "5")!;
    headers.add("Content-Length", "5")!;

    sz length = request::response_content_length(&headers)!;
    @assert(length == 5, "duplicate equal Content-Length mismatch");
}

fn void? test_conflicting_content_length()
{
    http::Headers headers;
    headers.init();
    defer headers.free();

    headers.add("Content-Length", "5")!;
    headers.add("Content-Length", "7")!;

    if (catch err = request::response_content_length(&headers)) {
        @assert(err == request::INVALID_CONTENT_LENGTH, "unexpected conflicting Content-Length fault");
    } else {
        @assert(false, "conflicting Content-Length accepted");
    }
}

fn void? test_transfer_encoding_token()
{
    @assert(request::header_has_token("gzip, Chunked", "chunked"), "chunked token not detected");
    @assert(request::header_has_token("CHUNKED", "chunked"), "uppercase chunked token not detected");
    @assert(!request::header_has_token("gzip, deflate", "chunked"), "missing chunked token detected");
}


// Chunked decoding

fn void? test_decode_chunked()
{
    String encoded =
        "5\r\n"
        "hello\r\n"
        "6\r\n"
        " world\r\n"
        "0\r\n"
        "\r\n";

    char[] decoded = request::decode_chunked(encoded, 1024)!;
    defer request::localmem.free(decoded.ptr);

    assert_bytes(decoded, (char[])"hello world", "chunked body mismatch");
}

fn void? test_decode_chunked_extensions()
{
    String encoded =
        "5;name=value\r\n"
        "hello\r\n"
        "0\r\n"
        "\r\n";

    char[] decoded = request::decode_chunked(encoded, 1024)!;
    defer request::localmem.free(decoded.ptr);

    assert_bytes(decoded, (char[])"hello", "chunk extension decoding mismatch");
}

fn void? test_decode_chunked_trailer()
{
    String encoded =
        "4\r\n"
        "test\r\n"
        "0\r\n"
        "X-Trailer: yes\r\n"
        "\r\n";

    char[] decoded = request::decode_chunked(encoded, 1024)!;
    defer request::localmem.free(decoded.ptr);

    assert_bytes(decoded, (char[])"test", "chunk trailer decoding mismatch");
}

fn void? test_decode_chunked_incomplete()
{
    String encoded =
        "5\r\n"
        "abc";

    if (catch err = request::decode_chunked(encoded, 1024)) {
        @assert(err == request::RESPONSE_INCOMPLETE, "unexpected incomplete chunk fault");
    } else {
        @assert(false, "incomplete chunked response accepted");
    }
}

fn void? test_decode_chunked_too_large()
{
    String encoded =
        "5\r\n"
        "hello\r\n"
        "0\r\n"
        "\r\n";

    if (catch err = request::decode_chunked(encoded, 4)) {
        @assert(err == request::RESPONSE_TOO_LARGE, "unexpected chunk limit fault");
    } else {
        @assert(false, "oversized chunked response accepted");
    }
}


// Response parsing

fn void? test_parse_content_length_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    request::Response response = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)!;
    defer response.free();

    @assert(response.status == 200, "response status mismatch");
    assert_bytes(response.body, (char[])"hello", "response body mismatch");
    assert_string(response.header("Content-Type")!, "text/plain", "response header mismatch");
    assert_string(response.url, "http://example.com/", "response URL mismatch");
}

fn void? test_parse_chunked_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Transfer-Encoding: Chunked\r\n"
        "\r\n"
        "5\r\n"
        "hello\r\n"
        "6\r\n"
        " world\r\n"
        "0\r\n"
        "\r\n";

    request::Response response = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)!;
    defer response.free();

    @assert(response.status == 200, "chunked response status mismatch");
    assert_bytes(response.body, (char[])"hello world", "chunked response body mismatch");
}

fn void? test_parse_close_delimited_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "close body";

    request::Response response = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)!;
    defer response.free();

    assert_bytes(response.body, (char[])"close body", "close-delimited body mismatch");
}

fn void? test_parse_head_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Length: 123\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n";

    request::Response response = request::parse_response(&session, "HEAD", raw, "http://example.com/", 1024)!;
    defer response.free();

    @assert(response.status == 200, "HEAD response status mismatch");
    @assert(response.body.len == 0, "HEAD response contains body");
    assert_string(response.header("Content-Length")!, "123", "HEAD Content-Length missing");
}

fn void? test_parse_no_content_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 204 No Content\r\n"
        "Content-Length: 10\r\n"
        "\r\n";

    request::Response response = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)!;
    defer response.free();

    @assert(response.status == 204, "204 response status mismatch");
    @assert(response.body.len == 0, "204 response contains body");
}

fn void? test_parse_invalid_content_length_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Length: invalid\r\n"
        "\r\n"
        "hello";

    if (catch err = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)) {
        @assert(err == request::INVALID_CONTENT_LENGTH, "unexpected invalid Content-Length fault");
    } else {
        @assert(false, "invalid Content-Length response accepted");
    }
}

fn void? test_parse_incomplete_content_length_response()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Length: 10\r\n"
        "\r\n"
        "short";

    if (catch err = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)) {
        @assert(err == request::RESPONSE_INCOMPLETE, "unexpected incomplete response fault");
    } else {
        @assert(false, "incomplete Content-Length response accepted");
    }
}

fn void? test_parse_response_too_large()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    if (catch err = request::parse_response(&session, "GET", raw, "http://example.com/", 4)) {
        @assert(err == request::RESPONSE_TOO_LARGE, "unexpected response size fault");
    } else {
        @assert(false, "oversized response accepted");
    }
}

fn void? test_response_set_cookie()
{
    request::Session session;
    session.init();
    defer session.deinit();

    String raw =
        "HTTP/1.1 200 OK\r\n"
        "Content-Length: 0\r\n"
        "Set-Cookie: sid=abc; Path=/; HttpOnly\r\n"
        "Set-Cookie: mode=dark; Path=/\r\n"
        "\r\n";

    request::Response response = request::parse_response(&session, "GET", raw, "http://example.com/", 1024)!;
    defer response.free();

    assert_string(session.cookies.get("sid")!, "abc", "session sid cookie mismatch");
    assert_string(session.cookies.get("mode")!, "dark", "session mode cookie mismatch");
}


// Redirect resolution

fn void? test_resolve_absolute_redirect()
{
    String url = request::resolve_redirect("http://example.com/a", "http://other.example/b")!;
    defer http::str_free(url);

    assert_string(url, "http://other.example/b", "absolute redirect mismatch");
}

fn void? test_resolve_root_redirect()
{
    String url = request::resolve_redirect("http://example.com/a/b", "/new/path")!;
    defer http::str_free(url);

    assert_string(url, "http://example.com/new/path", "root redirect mismatch");
}

fn void? test_resolve_relative_redirect()
{
    String url = request::resolve_redirect("http://example.com/a/b", "next")!;
    defer http::str_free(url);

    assert_string(url, "http://example.com/a/next", "relative redirect mismatch");
}

fn void? test_resolve_query_redirect()
{
    String url = request::resolve_redirect("http://example.com/a/b?old=1", "?new=2")!;
    defer http::str_free(url);

    assert_string(url, "http://example.com/a/b?new=2", "query redirect mismatch");
}

fn void? test_resolve_redirect_port()
{
    String url = request::resolve_redirect("http://127.0.0.1:18080/a/b", "../next")!;
    defer http::str_free(url);

    assert_string(url, "http://127.0.0.1:18080/a/../next", "redirect port mismatch");
}


// Response helpers

fn void? test_response_status_helpers()
{
    request::Response response;
    response.init();
    defer response.free();

    response.status = 200;
    @assert(response.ok(), "200 is not OK");
    @assert(!response.redirect(), "200 detected as redirect");

    response.status = 302;
    @assert(response.redirect(), "302 is not redirect");

    response.status = 404;
    @assert(response.client_error(), "404 is not client error");

    response.status = 500;
    @assert(response.server_error(), "500 is not server error");
}


// Main

fn void? task_main(void* arg)
{
    test_parse_url_basic()!;
    test_parse_url_port()!;
    test_parse_url_query_only()!;
    test_parse_url_fragment_removed()!;
    test_parse_url_ipv6()!;
    test_parse_url_invalid()!;

    test_build_target_empty_query()!;
    test_build_target_query()!;
    test_build_target_existing_query()!;
    test_build_target_trailing_question()!;
    test_build_target_trailing_ampersand()!;

    test_build_get_request()!;
    test_build_post_data_request()!;
    test_build_post_json_request()!;
    test_build_head_request_without_body()!;
    test_session_and_request_cookies()!;
    test_authorization_header()!;

    test_options_validation()!;

    test_parse_status_line()!;
    test_parse_headers()!;
    test_content_length()!;
    test_conflicting_content_length()!;
    test_transfer_encoding_token()!;

    test_decode_chunked()!;
    test_decode_chunked_extensions()!;
    test_decode_chunked_trailer()!;
    
    test_decode_chunked_incomplete()!;
    test_decode_chunked_too_large()!;

    test_parse_content_length_response()!;
    test_parse_chunked_response()!;
    test_parse_close_delimited_response()!;
    test_parse_head_response()!;
    test_parse_no_content_response()!;
    
    test_parse_invalid_content_length_response()!;
    test_parse_incomplete_content_length_response()!;
    test_parse_response_too_large()!;
    test_response_set_cookie()!;

    test_resolve_absolute_redirect()!;
    test_resolve_root_redirect()!;
    test_resolve_relative_redirect()!;
    test_resolve_query_redirect()!;
    test_resolve_redirect_port()!;

    test_response_status_helpers()!;

    io::printfn("test_client: OK");
}

fn void main()
{
    aio::run(&task_main);
}

// eof