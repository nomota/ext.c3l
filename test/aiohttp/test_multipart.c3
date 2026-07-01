// test_multipart.c3

// multipart/form-data tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::multipart;

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

fn http::Response*? cached_mixed_handler(http::Context* c)
{
    String username = c.multipart_value("username")!!;
    http::MultipartPart* file = c.multipart_file_ref("avatar");

    @assert(username == "nomota", "cached username mismatch");
    @assert(file != null, "cached file missing");
    @assert(file.filename == "avatar.txt", "cached filename mismatch");
    @assert((String)file.body == "hello file", "cached file body mismatch");

    http::MultipartForm* form = c.multiparts();
    @assert(form != null, "cached form missing");
    @assert(form.len() == 2, "cached form len mismatch");

    return c.text("cached ok")!!;
}

fn http::Response*? field_handler(http::Context* c)
{
    String value = c.multipart_value_copy("username")!!;
    defer http::localmem.free(value);

    return c.text(value)!!;
}

fn http::Response*? file_handler(http::Context* c)
{
    http::MultipartPart* file = c.multipart_file("avatar")!!;
    defer http::multipart_part_free(file);

    @assert(file.filename == "avatar.txt", "file filename mismatch");
    @assert(file.content_type == "text/plain", "file content type mismatch");
    @assert((String)file.body == "hello file", "file body mismatch");

    return c.text(file.filename)!!;
}

fn http::Response*? mixed_handler(http::Context* c)
{
    http::MultipartForm form = c.multipart()!!;
    defer form.free();

    String username = form.value("username")!!;
    http::MultipartPart* file = form.file("avatar");

    @assert(username == "nomota", "mixed username mismatch");
    @assert(file != null, "mixed file missing");
    @assert(file.filename == "avatar.txt", "mixed filename mismatch");
    @assert((String)file.body == "hello file", "mixed file body mismatch");

    return c.text("mixed ok")!!;
}

fn void test_context_multipart_cache()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.post("/cached", &cached_mixed_handler)!!;

    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n";

    String raw = string::format(
        http::localmem,
        "POST /cached HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: %d\r\n"
        "\r\n"
        "%s",
        body.len,
        (String)body
    );
    defer http::localmem.free(raw);

    http::Response* res = app.fetch_raw((char[])raw)!!;
    defer http::response_free(res);

    @assert(res.status == 200, "cached multipart status mismatch");
    @assert((String)res.body == "cached ok", "cached multipart body mismatch");
}

fn void test_boundary_from_content_type()
{
    String boundary = http::boundary_from_content_type(
        "multipart/form-data; boundary=----c3test"
    )!!;
    defer http::localmem.free(boundary);

    @assert(boundary == "----c3test", "boundary mismatch");
}

fn void test_boundary_from_content_type_quoted()
{
    String boundary = http::boundary_from_content_type(
        "multipart/form-data; boundary=\"----c3test\""
    )!!;
    defer http::localmem.free(boundary);

    @assert(boundary == "----c3test", "quoted boundary mismatch");
}

fn void test_boundary_missing()
{
    if (catch err = http::boundary_from_content_type("multipart/form-data"))
    {
        @assert(err == http::NOT_FOUND, "missing boundary fault mismatch");
        return;
    }

    @assert(false, "missing boundary should fail");
}

fn void test_boundary_invalid()
{
    if (catch err = http::boundary_from_content_type(
        "multipart/form-data; boundary=\"bad boundary\""
    ))
    {
        @assert(err == http::BOUNDARY_NOT_FOUND, "invalid boundary fault mismatch");
        return;
    }

    @assert(false, "invalid boundary should fail");
}

fn void test_request_is_multipart_true()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 0\r\n"
        "\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    @assert(req.is_multipart(), "request is_multipart true mismatch");
}

fn void test_request_is_multipart_false()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 0\r\n"
        "\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    @assert(!req.is_multipart(), "request is_multipart false mismatch");
}

fn void test_multipart_parse_single_field()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    @assert(form.len() == 1, "single field part count mismatch");

    String username = form.value("username")!!;
    @assert(username == "nomota", "single field value mismatch");

    http::MultipartPart* part = form.get("username");
    @assert(part != null, "single field part missing");
    @assert(!part.is_file(), "single field should not be file");
    @assert(part.text() == "nomota", "single field text mismatch");
}

fn void test_multipart_parse_two_fields()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"lang\"\r\n"
        "\r\n"
        "c3\r\n"
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    @assert(form.len() == 2, "two fields part count mismatch");
    @assert(form.value("username")!! == "nomota", "username field mismatch");
    @assert(form.value("lang")!! == "c3", "lang field mismatch");
}

fn void test_multipart_parse_file()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    @assert(form.len() == 1, "file part count mismatch");

    http::MultipartPart* file = form.file("avatar");
    @assert(file != null, "file part missing");
    @assert(file.is_file(), "file part should be file");
    @assert(file.name == "avatar", "file name mismatch");
    @assert(file.filename == "avatar.txt", "file filename mismatch");
    @assert(file.content_type == "text/plain", "file content type mismatch");
    @assert((String)file.body == "hello file", "file body mismatch");
}

fn void test_multipart_parse_mixed()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    @assert(form.len() == 2, "mixed part count mismatch");
    @assert(form.value("username")!! == "nomota", "mixed username mismatch");

    http::MultipartPart* file = form.file("avatar");
    @assert(file != null, "mixed file missing");
    @assert(file.filename == "avatar.txt", "mixed filename mismatch");
    @assert((String)file.body == "hello file", "mixed file body mismatch");
}

fn void test_multipart_parse_empty_file()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"empty.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "\r\n"
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    http::MultipartPart* file = form.file("avatar");
    @assert(file != null, "empty file missing");
    @assert(file.filename == "empty.txt", "empty filename mismatch");
    @assert(file.body.len == 0, "empty file body len mismatch");
}

fn void test_multipart_parse_repeated_fields()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"tag\"\r\n"
        "\r\n"
        "a\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"tag\"\r\n"
        "\r\n"
        "b\r\n"
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    @assert(form.len() == 2, "repeated fields count mismatch");
    @assert(form.value("tag")!! == "a", "repeated first value mismatch");
}

fn void test_multipart_parse_empty_form()
{
    char[] body =
        "------c3test--\r\n";

    http::MultipartForm form = http::multipart_parse(body, "----c3test")!!;
    defer form.free();

    @assert(form.len() == 0, "empty multipart form count mismatch");
}

fn void test_multipart_parse_missing_boundary()
{
    char[] body =
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n";

    if (catch err = http::multipart_parse(body, "----c3test"))
    {
        @assert(err == http::BOUNDARY_NOT_FOUND, "missing boundary fault mismatch");
        return;
    }

    @assert(false, "missing boundary should fail");
}

fn void test_multipart_parse_incomplete()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota";

    if (catch err = http::multipart_parse(body, "----c3test"))
    {
//warn("%s", err);
        @assert(err == http::MULTIPART_BODY_INCOMPLETE, "incomplete multipart fault mismatch");
        return;
    }

    @assert(false, "incomplete multipart should fail");
}

fn void test_multipart_parse_missing_content_disposition()
{
    char[] body =
        "------c3test\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    if (catch err = http::multipart_parse(body, "----c3test"))
    {
        @assert(err == http::INVALID_MULTIPART_BODY, "missing content disposition fault mismatch");
        return;
    }

    @assert(false, "missing content disposition should fail");
}

fn void test_multipart_parse_missing_name()
{
    char[] body =
        "------c3test\r\n"
        "Content-Disposition: form-data\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    if (catch err = http::multipart_parse(body, "----c3test"))
    {
        @assert(err == http::INVALID_MULTIPART_BODY, "missing name fault mismatch");
        return;
    }

    @assert(false, "missing name should fail");
}

fn void test_request_multipart()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 89\r\n"
        "\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::MultipartForm form = req.multipart()!!;
    defer form.free();

    @assert(form.value("username")!! == "nomota", "request multipart value mismatch");
}

fn void test_request_multipart_value_copy()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 89\r\n"
        "\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    String value = req.multipart_value_copy("username")!!;
    defer http::localmem.free(value);

    @assert(value == "nomota", "request multipart value copy mismatch");
}

fn void test_request_multipart_file_copy()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 140\r\n"
        "\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    http::MultipartPart* file = req.multipart_file("avatar")!!;
    defer http::multipart_part_free(file);

    @assert(file.filename == "avatar.txt", "request file copy filename mismatch");
    @assert(file.content_type == "text/plain", "request file copy content type mismatch");
    @assert((String)file.body == "hello file", "request file copy body mismatch");
}

fn void test_request_multipart_unsupported_type()
{
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 7\r\n"
        "\r\n"
        "a=b&c=d";

    http::Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    if (catch err = req.multipart())
    {
        @assert(err == http::UNSUPPORTED_MULTIPART_TYPE, "unsupported multipart type fault mismatch");
        return;
    }

    @assert(false, "unsupported multipart type should fail");
}

fn void test_context_multipart_value_copy()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.post("/field", &field_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "POST /field HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 89\r\n"
        "\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "context multipart field status mismatch");
    @assert((String)res.body == "nomota", "context multipart field body mismatch");
}

fn void test_context_multipart_file()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.post("/file", &file_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "POST /file HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 140\r\n"
        "\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "context multipart file status mismatch");
    @assert((String)res.body == "avatar.txt", "context multipart file body mismatch");
}

fn void test_context_multipart_mixed()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.post("/mixed", &mixed_handler)!!;

    http::Response* res = app.fetch_raw((char[])
        "POST /mixed HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: 213\r\n"
        "\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "context multipart mixed status mismatch");
    @assert((String)res.body == "mixed ok", "context multipart mixed body mismatch");
}

fn void main()
{
    test_boundary_from_content_type();
    test_boundary_from_content_type_quoted();
    test_boundary_missing();
    test_boundary_invalid();

    test_request_is_multipart_true();
    test_request_is_multipart_false();

    test_multipart_parse_single_field();
    test_multipart_parse_two_fields();
    test_multipart_parse_file();
    test_multipart_parse_mixed();
    test_multipart_parse_empty_file();
    test_multipart_parse_repeated_fields();
    test_multipart_parse_empty_form();

    test_multipart_parse_missing_boundary();
    test_multipart_parse_incomplete();
    test_multipart_parse_missing_content_disposition();
    test_multipart_parse_missing_name();

    test_request_multipart();
    test_request_multipart_value_copy();
    test_request_multipart_file_copy();
    test_request_multipart_unsupported_type();

    test_context_multipart_value_copy();
    test_context_multipart_file();
    test_context_multipart_mixed();

    test_context_multipart_cache();
    
    io::printfn("test_multipart: OK");
}

// eof