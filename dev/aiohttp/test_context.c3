// test_context.c3

// Context tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::context;

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

fn aiohttp::Request* parse_request(char[] raw)
{
    aiohttp::Request* req = aiohttp::request_parse(raw)!!;
    return req;
}

fn void test_context_basic_request_accessors()
{
    char[] raw =
        "POST /submit?x=1 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "\r\n"
        "hello";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    @assert(c.method() == "POST", "method mismatch");
    @assert(c.path() == "/submit", "path mismatch");
    @assert(c.target() == "/submit?x=1", "target mismatch");
    @assert(c.has_body(), "has_body mismatch");
    @assert((String)c.body() == "hello", "body mismatch");

    String host = c.req_header("Host")!!;
    @assert(host == "localhost", "request header mismatch");
}

fn void test_context_empty_request_accessors()
{
    aiohttp::Context c = {};

    @assert(c.method() == "", "empty method mismatch");
    @assert(c.path() == "", "empty path mismatch");
    @assert(c.target() == "", "empty target mismatch");
    @assert(!c.has_body(), "empty body flag mismatch");
    @assert(c.body().len == 0, "empty body mismatch");

    String? h = c.req_header("Host");
    if (catch err = h)
    {
        @assert(err == aiohttp::CONTEXT_NOT_READY, "empty req_header fault mismatch");
        return;
    }

    @assert(false, "empty context req_header should fail");
}

fn void test_context_params()
{
    char[] raw =
        "GET /users/42 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Params params;
    params.init();
    defer params.free();

    params.put("id", "42")!!;
    params.set_splat("users/42")!!;

    aiohttp::Context c;
    c.init_with_params(req, &params)!!;
    defer c.free();

    String id = c.param("id")!!;
    String splat = c.splat()!!;

    @assert(id == "42", "param mismatch");
    @assert(splat == "users/42", "splat mismatch");
    @assert(c.has_param("id"), "has_param mismatch");
    @assert(!c.has_param("missing"), "missing has_param mismatch");
}

fn void test_context_query_cache()
{
    char[] raw =
        "GET /search?q=hello+world&page=1 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    String q = c.query("q")!!;
    String page = c.query("page")!!;

    @assert(q == "hello world", "query q mismatch");
    @assert(page == "1", "query page mismatch");
    @assert(c.has_query("q"), "has_query q mismatch");
    @assert(!c.has_query("missing"), "has_query missing mismatch");

    aiohttp::Query* queries = c.queries();
    @assert(queries != null, "queries pointer is null");
    @assert(queries.len() == 2, "queries len mismatch");

    String? missing = c.query("missing");
    if (catch err = missing)
    {
        @assert(err == aiohttp::NOT_FOUND, "missing query fault mismatch");
        return;
    }

    @assert(false, "missing query should fail");
}

fn void test_context_response_status_and_headers()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    c.status(201)!!;
    c.header("X-Test", "yes")!!;
    c.add_header("Set-Cookie", "a=1")!!;
    c.add_header("Set-Cookie", "b=2")!!;
    c.content_type("text/plain")!!;

    @assert(c.get_status() == 201, "context status mismatch");
    @assert(c.res.headers.get("X-Test")!! == "yes", "context header mismatch");
    @assert(c.res.headers.get("Content-Type")!! == "text/plain", "context content type mismatch");
    @assert(c.res.headers.len() == 4, "context headers len mismatch");
}

fn void test_context_text_response()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.text("hello")!!;

    @assert(res == c.res, "text response pointer mismatch");
    @assert(res.status == 200, "text response status mismatch");
    @assert((String)res.body == "hello", "text response body mismatch");
    @assert(res.headers.get("Content-Type")!! == "text/plain; charset=utf-8", "text content type mismatch");
}

fn void test_context_html_response()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.html("<h1>Hello</h1>")!!;

    @assert(res == c.res, "html response pointer mismatch");
    @assert((String)res.body == "<h1>Hello</h1>", "html response body mismatch");
    @assert(res.headers.get("Content-Type")!! == "text/html; charset=utf-8", "html content type mismatch");
}

fn void test_context_json_response()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.json("{\"ok\":true}")!!;

    @assert(res == c.res, "json response pointer mismatch");
    @assert((String)res.body == "{\"ok\":true}", "json response body mismatch");
    @assert(res.headers.get("Content-Type")!! == "application/json; charset=utf-8", "json content type mismatch");
}

fn void test_context_body_response()
{
    char[] raw =
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.body_response((char[])"raw-body")!!;

    @assert(res == c.res, "body response pointer mismatch");
    @assert((String)res.body == "raw-body", "body response mismatch");
}

fn void test_context_redirect()
{
    char[] raw =
        "GET /old HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.redirect("/new", 301)!!;

    @assert(res.status == 301, "redirect status mismatch");
    @assert(res.headers.get("Location")!! == "/new", "redirect location mismatch");
}

fn void test_context_not_found()
{
    char[] raw =
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.not_found()!!;

    @assert(res.status == 404, "not_found status mismatch");
    @assert((String)res.body == "404 Not Found", "not_found body mismatch");
}

fn void test_context_internal_error()
{
    char[] raw =
        "GET /error HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = c.internal_error()!!;

    @assert(res.status == 500, "internal_error status mismatch");
    @assert((String)res.body == "500 Internal Server Error", "internal_error body mismatch");
}

fn void test_context_with_response_replaces_response()
{
    char[] raw =
        "GET /replace HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* replacement = aiohttp::response_text("replacement")!!;

    aiohttp::Response* res = c.with_response(replacement);

    @assert(res == replacement, "with_response pointer mismatch");
    @assert(c.res == replacement, "context replacement mismatch");
    @assert((String)c.res.body == "replacement", "replacement body mismatch");
}

fn aiohttp::Response*? call_handler(aiohttp::Context* c)
{
    c.header("X-Handler", "yes")!!;
    return c.text("called")!!;
}

fn void test_context_call()
{
    char[] raw =
        "GET /call HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response* res = aiohttp::context_call(&c, &call_handler)!!;

    @assert(res == c.res, "context_call response mismatch");
    @assert((String)res.body == "called", "context_call body mismatch");
    @assert(res.headers.get("X-Handler")!! == "yes", "context_call header mismatch");
}

fn void test_context_call_null_handler()
{
    char[] raw =
        "GET /call HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    aiohttp::Response*? res = aiohttp::context_call(&c, null);

    if (catch err = res)
    {
        @assert(err == aiohttp::CONTEXT_NOT_READY, "null handler fault mismatch");
        return;
    }

    @assert(false, "null handler should fail");
}

fn void test_context_serialized_response()
{
    char[] raw =
        "GET /serialize HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n";

    aiohttp::Request* req = parse_request(raw);
    defer aiohttp::request_free(req);

    aiohttp::Context c;
    c.init(req)!!;
    defer c.free();

    c.status(202)!!;
    c.header("X-Test", "ok")!!;
    c.text("accepted")!!;

    String wire = c.res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 202 Accepted\r\n"), "serialized status missing");
    @assert(contains(wire, "X-Test: ok\r\n"), "serialized custom header missing");
    @assert(contains(wire, "Content-Length: 8\r\n"), "serialized content-length missing");
    @assert(contains(wire, "\r\n\r\naccepted"), "serialized body missing");
}

fn void main()
{
    test_context_basic_request_accessors();
    test_context_empty_request_accessors();
    test_context_params();
    test_context_query_cache();

    test_context_response_status_and_headers();
    test_context_text_response();
    test_context_html_response();
    test_context_json_response();
    test_context_body_response();
    test_context_redirect();
    test_context_not_found();
    test_context_internal_error();

    test_context_with_response_replaces_response();
    test_context_call();
    test_context_call_null_handler();
    test_context_serialized_response();

    io::printfn("test_context: OK");
}

// eof