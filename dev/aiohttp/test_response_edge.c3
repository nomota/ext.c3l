// test_response_edge.c3

// Response/header/serialization edge tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::response_edge;

import std::io;
import ext::aio::http;
import ext::debug;

const sz LOOP_COUNT = 1000;

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

fn sz find_string(String s, String needle)
{
    if (needle.len == 0) return 0;
    if (s.len < needle.len) return -1;

    for (sz i = 0; i + needle.len <= s.len; i++)
    {
        if (s[i:needle.len] == needle) return i;
    }

    return -1;
}

fn String body_part(String response)
{
    sz sep = find_string(response, "\r\n\r\n");
    if (sep < 0) return "";

    return response[sep + 4:response.len - sep - 4];
}

fn http::Response*? text_handler(http::Context* c)
{
    return c.text("hello")!!;
}

fn http::Response*? mutate_body_handler(http::Context* c)
{
    c.text("short")!!;
    c.text("a longer body")!!;

    return c.res;
}

fn http::Response*? empty_handler(http::Context* c)
{
    http::Response* res = http::response_empty(200)!!;

    return res;
}

fn http::Response*? no_content_handler(http::Context* c)
{
    http::Response* res = http::response_empty(204)!!;
    res.set_text("this body must not be serialized")!!;

    return res;
}

fn http::Response*? not_modified_handler(http::Context* c)
{
    http::Response* res = http::response_empty(304)!!;
    res.set_text("this body must not be serialized")!!;

    return res;
}

fn http::Response*? redirect_handler(http::Context* c)
{
    return c.redirect("/target")!!;
}

fn http::Response*? duplicate_cookie_handler(http::Context* c)
{
    http::Response* res = c.text("cookies")!!;

    res.set_cookie("a=1")!!;
    res.set_cookie("b=2")!!;

    return res;
}

fn http::Response*? overwrite_header_handler(http::Context* c)
{
    http::Response* res = c.text("headers")!!;

    res.header("X-Test", "one")!!;
    res.header("X-Test", "two")!!;

    return res;
}

fn http::Response*? binary_handler(http::Context* c)
{
    char[7] data;

    data[0] = 0;
    data[1] = 1;
    data[2] = 2;
    data[3] = 'A';
    data[4] = 'B';
    data[5] = 0;
    data[6] = 255;

    http::Response* res = http::response_empty(200)!!;
    res.set_body_copy(data[..])!!;
    res.header("Content-Type", "application/octet-stream")!!;

    return res;
}

fn http::Response*? custom_status_handler(http::Context* c)
{
    http::Response* res = http::response_empty(201)!!;
    res.set_text("created")!!;

    return res;
}

fn http::Response*? header_case_handler(http::Context* c)
{
    http::Response* res = c.text("case")!!;

    res.header("X-Mixed-Case", "ok")!!;

    return res;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/text", &text_handler)!!;
    app.get("/mutate-body", &mutate_body_handler)!!;
    app.get("/empty", &empty_handler)!!;
    app.get("/no-content", &no_content_handler)!!;
    app.get("/not-modified", &not_modified_handler)!!;
    app.get("/redirect", &redirect_handler)!!;
    app.get("/cookies", &duplicate_cookie_handler)!!;
    app.get("/headers", &overwrite_header_handler)!!;
    app.get("/binary", &binary_handler)!!;
    app.get("/custom-status", &custom_status_handler)!!;
    app.get("/header-case", &header_case_handler)!!;
}

fn http::Response* fetch(http::Application* app, String method, String path)
{
    char[512] raw;

    String req = string::bformat(raw[..],
        "%s %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        method,
        path
    );

    return app.fetch_raw((char[])req)!!;
}

fn String serialize_response(http::Response* res)
{
    return res.serialize()!!;
}

fn void test_basic_text_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/text");
    defer http::response_free(res);

    @assert(res.status == 200, "basic text status mismatch");
    @assert((String)res.body == "hello", "basic text body mismatch");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "basic text wire status mismatch");
    @assert(contains(wire, "Content-Length: 5\r\n"), "basic text content length mismatch");
    @assert(contains(wire, "\r\n\r\nhello"), "basic text wire body mismatch");
}

fn void test_body_mutation_updates_content_length()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/mutate-body");
    defer http::response_free(res);

    @assert(res.status == 200, "body mutation status mismatch");
    @assert((String)res.body == "a longer body", "body mutation body mismatch");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "Content-Length: 13\r\n"), "body mutation content length mismatch");
    @assert(contains(wire, "\r\n\r\na longer body"), "body mutation wire body mismatch");
}

fn void test_empty_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/empty");
    defer http::response_free(res);

    @assert(res.status == 200, "empty response status mismatch");
    @assert(res.body.len == 0, "empty response body should be empty");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "empty response wire status mismatch");
    @assert(contains(wire, "Content-Length: 0\r\n"), "empty response content length mismatch");
    @assert(body_part(wire).len == 0, "empty response wire body should be empty");
}

fn void test_no_content_has_no_serialized_body()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/no-content");
    defer http::response_free(res);

    @assert(res.status == 204, "204 response status mismatch");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 204 No Content\r\n"), "204 wire status mismatch");
    @assert(!contains(wire, "this body must not be serialized"), "204 body should not be serialized");
    @assert(body_part(wire).len == 0, "204 wire body should be empty");
}

fn void test_not_modified_has_no_serialized_body()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/not-modified");
    defer http::response_free(res);

    @assert(res.status == 304, "304 response status mismatch");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 304 Not Modified\r\n"), "304 wire status mismatch");
    @assert(!contains(wire, "this body must not be serialized"), "304 body should not be serialized");
    @assert(body_part(wire).len == 0, "304 wire body should be empty");
}

fn void test_head_response_status_only()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "HEAD", "/text");
    defer http::response_free(res);

    @assert(res.status == 200, "HEAD status mismatch");
    @assert((String)res.body == "hello", "HEAD fetch_raw body policy mismatch");
}

fn void test_redirect_response()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/redirect");
    defer http::response_free(res);

    @assert(
        res.status == 301 ||
        res.status == 302 ||
        res.status == 303 ||
        res.status == 307 ||
        res.status == 308,
        "redirect status mismatch"
    );

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "Location: /target\r\n"), "redirect location header mismatch");
}

fn void test_duplicate_set_cookie_serialization()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/cookies");
    defer http::response_free(res);

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "Set-Cookie: a=1"), "first Set-Cookie missing");
    @assert(contains(wire, "Set-Cookie: b=2"), "second Set-Cookie missing");
}

fn void test_header_overwrite_policy()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/headers");
    defer http::response_free(res);

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "X-Test: two\r\n"), "header overwrite final value missing");
}

fn void test_binary_response_body()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/binary");
    defer http::response_free(res);

    @assert(res.status == 200, "binary response status mismatch");
    @assert(res.body.len == 7, "binary response body len mismatch");
    @assert(res.body[0] == 0, "binary response byte 0 mismatch");
    @assert(res.body[1] == 1, "binary response byte 1 mismatch");
    @assert(res.body[2] == 2, "binary response byte 2 mismatch");
    @assert(res.body[3] == 'A', "binary response byte 3 mismatch");
    @assert(res.body[4] == 'B', "binary response byte 4 mismatch");
    @assert(res.body[5] == 0, "binary response byte 5 mismatch");
    @assert(res.body[6] == 255, "binary response byte 6 mismatch");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "Content-Length: 7\r\n"), "binary response content length mismatch");

    String body = body_part(wire);

    @assert(body.len == 7, "binary wire body len mismatch");
    @assert(body[0] == 0, "binary wire byte 0 mismatch");
    @assert(body[1] == 1, "binary wire byte 1 mismatch");
    @assert(body[2] == 2, "binary wire byte 2 mismatch");
    @assert(body[3] == 'A', "binary wire byte 3 mismatch");
    @assert(body[4] == 'B', "binary wire byte 4 mismatch");
    @assert(body[5] == 0, "binary wire byte 5 mismatch");
    @assert(body[6] == 255, "binary wire byte 6 mismatch");
}

fn void test_custom_status()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/custom-status");
    defer http::response_free(res);

    @assert(res.status == 201, "custom status mismatch");

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 201 Created\r\n"), "custom status wire mismatch");
    @assert(contains(wire, "\r\n\r\ncreated"), "custom status body mismatch");
}

fn void test_header_case_preserved()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/header-case");
    defer http::response_free(res);

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(contains(wire, "X-Mixed-Case: ok\r\n"), "header case preservation mismatch");
}

fn void test_invalid_response_header_name_policy()
{
    http::Response* res = http::response_text("bad")!!;
    defer http::response_free(res);

    if (catch err = res.header("Bad Header", "x"))
    {
//warn("%s", err);
        @assert(err == http::BAD_REQUEST || err == http::INVALID_HEADER || err == http::INVALID_HEADER_NAME, "invalid response header name fault mismatch");
        return;
    }

    String wire = serialize_response(res);
    defer http::localmem.free(wire);

    @assert(!contains(wire, "Bad Header: x\r\n"), "invalid response header should not serialize");
}

fn void test_repeated_serialize()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = fetch(&app, "GET", "/text");
    defer http::response_free(res);

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        String wire = serialize_response(res);

        @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "repeated serialize status mismatch");
        @assert(contains(wire, "Content-Length: 5\r\n"), "repeated serialize content length mismatch");
        @assert(contains(wire, "\r\n\r\nhello"), "repeated serialize body mismatch");

        http::localmem.free(wire);
    }
}

fn void test_repeated_fetch_and_serialize()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    for (sz i = 0; i < LOOP_COUNT; i++)
    {
        http::Response* res = fetch(&app, "GET", "/text");

        String wire = serialize_response(res);

        @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "repeated fetch serialize status mismatch");
        @assert(contains(wire, "\r\n\r\nhello"), "repeated fetch serialize body mismatch");

        http::localmem.free(wire);
        http::response_free(res);
    }
}

fn void main()
{
    test_basic_text_response();
    test_body_mutation_updates_content_length();
    test_empty_response();

    test_no_content_has_no_serialized_body();
    test_not_modified_has_no_serialized_body();
    test_head_response_status_only();

    test_redirect_response();

    test_duplicate_set_cookie_serialization();
    test_header_overwrite_policy();
    test_header_case_preserved();
    test_invalid_response_header_name_policy();

    test_binary_response_body();
    test_custom_status();

    test_repeated_serialize();
    test_repeated_fetch_and_serialize();

    io::printfn("test_response_edge: OK");
}

// eof