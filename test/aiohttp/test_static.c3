// test_static.c3

// Static file helper, cache validator, and range request tests.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::staticx;

import std::io;
import ext::aio::http;
import ext::aio;
import ext::debug;

const String TEST_ROOT = "zz_static_test";

const String INDEX_BODY = "<h1>index</h1>";
const String HELLO_BODY = "hello static";
const String CSS_BODY = "body { margin: 0; }";
const String JS_BODY = "console.log('ok');";
const String JSON_BODY = "{\"ok\":true}";
const String SVG_BODY = "<svg></svg>";
const String PDF_BODY = "%PDF-test";


// General helpers

fn bool contains(String haystack, String needle)
{
    return haystack.contains(needle);
}

fn void? write_file(String file_path, String data) @maydiscard
{
    aio::File* file = aio::file_open(file_path, "w")!;
    defer file.free();

    file.write_all((char[])data)!;
    file.flush()!;
}

fn void remove_file_if_exists(String file_path)
{
    if (aio::path::exists(file_path)) {
        aio::path::remove(file_path);
    }
}

fn void remove_dir_if_exists(String dir_path)
{
    if (aio::path::exists(dir_path)) {
        aio::path::removedirs(dir_path);
    }
}

fn void? setup_static_root() @maydiscard
{
    aio::path::makedirs(TEST_ROOT, 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/css", 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/js", 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/img", 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/docs", 0o777, true)!;

    write_file(TEST_ROOT +++ "/index.html", INDEX_BODY)!;
    write_file(TEST_ROOT +++ "/hello.txt", HELLO_BODY)!;
    write_file(TEST_ROOT +++ "/css/app.css", CSS_BODY)!;
    write_file(TEST_ROOT +++ "/js/app.js", JS_BODY)!;
    write_file(TEST_ROOT +++ "/data.json", JSON_BODY)!;
    write_file(TEST_ROOT +++ "/img/logo.svg", SVG_BODY)!;
    write_file(TEST_ROOT +++ "/docs/file.pdf", PDF_BODY)!;
    write_file(TEST_ROOT +++ "/empty.txt", "")!;
}

fn void cleanup_static_root()
{
    http::clear_root();

    remove_file_if_exists(TEST_ROOT +++ "/css/app.css");
    remove_file_if_exists(TEST_ROOT +++ "/js/app.js");
    remove_file_if_exists(TEST_ROOT +++ "/img/logo.svg");
    remove_file_if_exists(TEST_ROOT +++ "/docs/file.pdf");

    remove_file_if_exists(TEST_ROOT +++ "/index.html");
    remove_file_if_exists(TEST_ROOT +++ "/hello.txt");
    remove_file_if_exists(TEST_ROOT +++ "/data.json");
    remove_file_if_exists(TEST_ROOT +++ "/empty.txt");

    remove_dir_if_exists(TEST_ROOT +++ "/css");
    remove_dir_if_exists(TEST_ROOT +++ "/js");
    remove_dir_if_exists(TEST_ROOT +++ "/img");
    remove_dir_if_exists(TEST_ROOT +++ "/docs");
    remove_dir_if_exists(TEST_ROOT);
}


// Request and context helpers

fn http::Request* make_request_method(String method, String request_path, String headers = "")
{
    String raw = string::tformat(
        "%s %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "%s"
        "\r\n",
        method,
        request_path,
        headers
    );

    return http::request_parse((char[])raw)!!;
}

fn http::Request* make_request(String request_path)
{
    return make_request_method("GET", request_path);
}

fn http::Request* make_request_with_headers(String request_path, String headers)
{
    return make_request_method("GET", request_path, headers);
}

fn http::Context* make_context_from_request(http::Request* req, String request_path)
{
    http::Params params;
    params.init();

    String rel;

    if (request_path == "/static" || request_path == "/static/") {
        rel = "";
    } else if (request_path.starts_with("/static/")) {
        rel = request_path["/static/".len:request_path.len - "/static/".len];
    } else if (request_path.starts_with("/")) {
        rel = request_path[1..];
    } else {
        rel = request_path;
    }

    params.set_splat(rel)!!;

    http::Context* c = http::context_new_with_params(req, &params)!!;

    params.free();

    return c;
}

fn http::Context* make_context_method(String method, String request_path, String headers = "")
{
    http::Request* req = make_request_method(method, request_path, headers);
    return make_context_from_request(req, request_path);
}

fn http::Context* make_context(String request_path)
{
    return make_context_method("GET", request_path);
}

fn http::Context* make_context_with_headers(String request_path, String headers)
{
    return make_context_method("GET", request_path, headers);
}

fn void free_context_and_request(http::Context* c)
{
    if (c == null) return;

    http::Request* req = c.req;

    http::context_free(c);

    if (req != null) {
        http::request_free(req);
    }
}

fn void free_owned_string(String value)
{
    if (value.len > 0) {
        http::localmem.free(value);
    }
}


// Content type tests

fn void test_content_type_from_path()
{
    @assert(
        http::content_type_from_path("index.html") == "text/html; charset=utf-8",
        "html content type mismatch"
    );

    @assert(
        http::content_type_from_path("index.htm") == "text/html; charset=utf-8",
        "htm content type mismatch"
    );

    @assert(
        http::content_type_from_path("app.css") == "text/css; charset=utf-8",
        "css content type mismatch"
    );

    @assert(
        http::content_type_from_path("app.js") == "application/javascript; charset=utf-8",
        "js content type mismatch"
    );

    @assert(
        http::content_type_from_path("app.mjs") == "application/javascript; charset=utf-8",
        "mjs content type mismatch"
    );

    @assert(
        http::content_type_from_path("data.json") == "application/json; charset=utf-8",
        "json content type mismatch"
    );

    @assert(
        http::content_type_from_path("readme.txt") == "text/plain; charset=utf-8",
        "txt content type mismatch"
    );

    @assert(
        http::content_type_from_path("data.xml") == "application/xml; charset=utf-8",
        "xml content type mismatch"
    );

    @assert(
        http::content_type_from_path("data.csv") == "text/csv; charset=utf-8",
        "csv content type mismatch"
    );

    @assert(
        http::content_type_from_path("logo.svg") == "image/svg+xml",
        "svg content type mismatch"
    );

    @assert(
        http::content_type_from_path("image.png") == "image/png",
        "png content type mismatch"
    );

    @assert(
        http::content_type_from_path("image.jpg") == "image/jpeg",
        "jpg content type mismatch"
    );

    @assert(
        http::content_type_from_path("image.jpeg") == "image/jpeg",
        "jpeg content type mismatch"
    );

    @assert(
        http::content_type_from_path("image.gif") == "image/gif",
        "gif content type mismatch"
    );

    @assert(
        http::content_type_from_path("image.webp") == "image/webp",
        "webp content type mismatch"
    );

    @assert(
        http::content_type_from_path("favicon.ico") == "image/x-icon",
        "ico content type mismatch"
    );

    @assert(
        http::content_type_from_path("module.wasm") == "application/wasm",
        "wasm content type mismatch"
    );

    @assert(
        http::content_type_from_path("file.pdf") == "application/pdf",
        "pdf content type mismatch"
    );

    @assert(
        http::content_type_from_path("file.zip") == "application/zip",
        "zip content type mismatch"
    );

    @assert(
        http::content_type_from_path("file.gz") == "application/gzip",
        "gzip content type mismatch"
    );

    @assert(
        http::content_type_from_path("movie.mp4") == "video/mp4",
        "mp4 content type mismatch"
    );

    @assert(
        http::content_type_from_path("movie.webm") == "video/webm",
        "webm content type mismatch"
    );

    @assert(
        http::content_type_from_path("audio.mp3") == "audio/mpeg",
        "mp3 content type mismatch"
    );

    @assert(
        http::content_type_from_path("audio.wav") == "audio/wav",
        "wav content type mismatch"
    );

    @assert(
        http::content_type_from_path("file.bin") == "application/octet-stream",
        "fallback content type mismatch"
    );
}


// Path helper tests

fn void test_percent_decode()
{
    String decoded1 = http::percent_decode("hello.txt")!!;
    defer http::localmem.free(decoded1);

    String decoded2 = http::percent_decode("css%2Fapp.css")!!;
    defer http::localmem.free(decoded2);

    String decoded3 = http::percent_decode("%68%65%6c%6c%6f.txt")!!;
    defer http::localmem.free(decoded3);

    @assert(decoded1 == "hello.txt", "plain percent decode mismatch");
    @assert(decoded2 == "css/app.css", "slash percent decode mismatch");
    @assert(decoded3 == "hello.txt", "encoded text decode mismatch");
}

fn void test_percent_decode_invalid()
{
    if (try http::percent_decode("%")) {
        @assert(false, "short percent encoding should fail");
    }

    if (try http::percent_decode("%2")) {
        @assert(false, "incomplete percent encoding should fail");
    }

    if (try http::percent_decode("%GG")) {
        @assert(false, "invalid percent encoding should fail");
    }

    if (try http::percent_decode("%00")) {
        @assert(false, "NUL percent encoding should fail");
    }
}

fn void test_normalize_path()
{
    String p1 = http::normalize_path("css/./app.css")!!;
    defer free_owned_string(p1);

    String p2 = http::normalize_path("css/a/../app.css")!!;
    defer free_owned_string(p2);

    String p3 = http::normalize_path("css//app.css")!!;
    defer free_owned_string(p3);

    String p4 = http::normalize_path("//css///app.css//")!!;
    defer free_owned_string(p4);

    String p5 = http::normalize_path("a/b/../../hello.txt")!!;
    defer free_owned_string(p5);

    String p6 = http::normalize_path(".")!!;
    defer free_owned_string(p6);

    String p7 = http::normalize_path("a/..")!!;
    defer free_owned_string(p7);

    String p8 = http::normalize_path("..hidden/file.txt")!!;
    defer free_owned_string(p8);

    @assert(p1 == "css/app.css", "normalize dot segment mismatch");
    @assert(p2 == "css/app.css", "normalize parent segment mismatch");
    @assert(p3 == "css/app.css", "normalize duplicate slash mismatch");
    @assert(p4 == "/css/app.css", "normalize absolute path mismatch");
    @assert(p5 == "hello.txt", "normalize nested parent mismatch");
    @assert(p6.len == 0, "normalize current directory mismatch");
    @assert(p7.len == 0, "normalize removed path mismatch");
    @assert(p8 == "..hidden/file.txt", "normal filename beginning with dots mismatch");
}

fn void test_normalize_path_forbidden()
{
    if (catch err = http::normalize_path("../secret.txt")) {
        @assert(err == http::STATIC_FORBIDDEN, "relative parent escape fault mismatch");
    } else {
        @assert(false, "relative parent escape should fail");
    }

    if (catch err = http::normalize_path("/../secret.txt")) {
        @assert(err == http::STATIC_FORBIDDEN, "absolute parent escape fault mismatch");
    } else {
        @assert(false, "absolute parent escape should fail");
    }

    if (catch err = http::normalize_path("/a/../../b")) {
        @assert(err == http::STATIC_FORBIDDEN, "normalized root escape fault mismatch");
    } else {
        @assert(false, "normalized root escape should fail");
    }

    if (catch err = http::normalize_path("css\\app.css")) {
        @assert(err == http::STATIC_FORBIDDEN, "backslash fault mismatch");
    } else {
        @assert(false, "backslash path should fail");
    }
}

fn void test_normalize_rel()
{
    @assert(http::normalize_rel("") == "index.html", "empty relative path mismatch");
    @assert(http::normalize_rel("/") == "index.html", "root relative path mismatch");
    @assert(http::normalize_rel("///") == "index.html", "multiple root slash mismatch");
    @assert(http::normalize_rel("/hello.txt") == "hello.txt", "leading slash removal mismatch");
    @assert(http::normalize_rel("css/app.css") == "css/app.css", "normal relative path mismatch");
}

fn void test_is_safe_rel()
{
    @assert(http::is_safe_rel("css/app.css"), "normal relative path should be safe");
    @assert(http::is_safe_rel("..hidden/file.txt"), "normal dotted filename should be safe");
    @assert(!http::is_safe_rel("../secret.txt"), "leading parent segment should be unsafe");
    @assert(!http::is_safe_rel("a/../secret.txt"), "middle parent segment should be unsafe");
    @assert(!http::is_safe_rel("css\\app.css"), "backslash path should be unsafe");
}

fn void test_join_path()
{
    String p1 = http::join_path(TEST_ROOT, "index.html")!!;
    defer http::localmem.free(p1);

    String p2 = http::join_path(TEST_ROOT +++ "/", "index.html")!!;
    defer http::localmem.free(p2);

    String p3 = http::join_path(TEST_ROOT, "/index.html")!!;
    defer http::localmem.free(p3);

    String p4 = http::join_path(TEST_ROOT +++ "/", "/index.html")!!;
    defer http::localmem.free(p4);

    String expected = TEST_ROOT +++ "/index.html";

    @assert(p1 == expected, "join path p1 mismatch");
    @assert(p2 == expected, "join path p2 mismatch");
    @assert(p3 == expected, "join path p3 mismatch");
    @assert(p4 == expected, "join path p4 mismatch");

    if (catch err = http::join_path("", "index.html")) {
        @assert(err == http::STATIC_NOT_CONFIGURED, "empty root fault mismatch");
    } else {
        @assert(false, "empty root should fail");
    }
}


// File I/O tests

fn void test_read_file_text()
{
    char[] data = aio::file_load(TEST_ROOT +++ "/hello.txt")!!;
    defer http::localmem.free(data);

    @assert((String)data == HELLO_BODY, "static read text mismatch");
}

fn void test_read_file_empty()
{
    char[] data = aio::file_load(TEST_ROOT +++ "/empty.txt")!!;
    @assert(data.len == 0, "empty file length mismatch");
}

fn void test_read_file_not_found()
{
    if (catch err = aio::file_load(TEST_ROOT +++ "/missing.txt")) {
        return;
    }

    @assert(false, "missing static file should fail");
}

fn void test_read_file_directory()
{
    if (catch err = aio::file_load(TEST_ROOT +++ "/css")) {
        return;
    }

    @assert(false, "directory static read should fail");
}


// Basic static handler tests

fn void test_static_handler_not_configured()
{
    http::clear_root();

    http::Context* c = make_context("/static/hello.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 500, "static not configured status mismatch");
    @assert((String)res.body == "static root not configured", "static not configured body mismatch");
}

fn void test_static_handler_text_file()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/hello.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "static text status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "static text body kind mismatch");
    @assert(res.file_offset == 0, "static text file offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "static text file size mismatch");

    @assert(
        res.headers.get("Content-Type")!! == "text/plain; charset=utf-8",
        "static text content type mismatch"
    );

    @assert(
        res.headers.get("Content-Length")!! == "12",
        "static text Content-Length mismatch"
    );

    @assert(
        res.headers.get("Accept-Ranges")!! == "bytes",
        "static Accept-Ranges header mismatch"
    );

    @assert(
        res.headers.get("ETag")!!.len > 0,
        "static ETag header missing"
    );

    @assert(
        res.headers.get("Last-Modified")!!.len > 0,
        "static Last-Modified header missing"
    );
}

fn void test_static_handler_index_fallback()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "static index status mismatch");
    @assert(res.file_offset == 0, "static index offset mismatch");
    @assert(res.file_size == INDEX_BODY.len, "static index size mismatch");

    @assert(
        res.headers.get("Content-Type")!! == "text/html; charset=utf-8",
        "static index content type mismatch"
    );
}

fn void test_static_handler_css_file()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/css/app.css");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "static css status mismatch");
    @assert(res.file_size == CSS_BODY.len, "static css size mismatch");

    @assert(
        res.headers.get("Content-Type")!! == "text/css; charset=utf-8",
        "static css content type mismatch"
    );
}

fn void test_static_handler_json_file()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/data.json");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "static json status mismatch");
    @assert(res.file_size == JSON_BODY.len, "static json size mismatch");

    @assert(
        res.headers.get("Content-Type")!! == "application/json; charset=utf-8",
        "static json content type mismatch"
    );
}

fn void test_static_handler_empty_file()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/empty.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "empty static file status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "empty static file body kind mismatch");
    @assert(res.file_offset == 0, "empty static file offset mismatch");
    @assert(res.file_size == 0, "empty static file size mismatch");

    @assert(
        res.headers.get("Content-Type")!! == "text/plain; charset=utf-8",
        "empty static file content type mismatch"
    );

    @assert(
        res.headers.get("Content-Length")!! == "0",
        "empty static file Content-Length mismatch"
    );
}

fn void test_static_handler_normalized_path()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/css/../hello.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "normalized static path status mismatch");
    @assert(res.file_size == HELLO_BODY.len, "normalized static path size mismatch");
}

fn void test_static_handler_duplicate_slashes()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/css//app.css");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "duplicate slash static path status mismatch");
    @assert(res.file_size == CSS_BODY.len, "duplicate slash static path size mismatch");
}

fn void test_static_handler_percent_encoded_path()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/css%2Fapp.css");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "percent encoded static path status mismatch");
    @assert(res.file_size == CSS_BODY.len, "percent encoded static path size mismatch");
}

fn void test_static_handler_not_found()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/missing.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 404, "static missing status mismatch");
    @assert((String)res.body == "static file not found", "static missing body mismatch");
}

fn void test_static_handler_forbidden_dotdot()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/../secret.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 403, "static dotdot status mismatch");
    @assert((String)res.body == "forbidden", "static dotdot body mismatch");
}

fn void test_static_handler_forbidden_normalized_escape()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/a/../../secret.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 403, "normalized static escape status mismatch");
    @assert((String)res.body == "forbidden", "normalized static escape body mismatch");
}

fn void test_static_handler_forbidden_encoded_dotdot()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/%2e%2e/secret.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 403, "encoded static dotdot status mismatch");
    @assert((String)res.body == "forbidden", "encoded static dotdot body mismatch");
}

fn void test_static_handler_forbidden_backslash()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/css\\app.css");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 403, "static backslash status mismatch");
    @assert((String)res.body == "forbidden", "static backslash body mismatch");
}

fn void test_static_handler_forbidden_nul()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context("/static/hello.txt%00.html");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 403, "static NUL path status mismatch");
    @assert((String)res.body == "forbidden", "static NUL path body mismatch");
}


// Conditional GET tests

fn void test_static_handler_not_modified_etag()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String etag = first_res.headers.get("ETag")!!;

    String headers = string::tformat("If-None-Match: %s\r\n", etag);

    http::Context* second = make_context_with_headers("/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* second_res = http::static_handler(second)!!;

    @assert(second_res.status == 304, "If-None-Match status mismatch");
    @assert(second_res.body_kind == http::BodyKind.BODY_EMPTY, "304 body kind mismatch");
    @assert(second_res.body.len == 0, "304 response body should be empty");
    @assert(second_res.headers.get("ETag")!! == etag, "304 ETag mismatch");
    @assert(second_res.headers.get("Accept-Ranges")!! == "bytes", "304 Accept-Ranges mismatch");
    @assert(second_res.headers.get("Content-Length")!! == "0", "304 Content-Length mismatch");
}

fn void test_static_handler_not_modified_etag_wildcard()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "If-None-Match: *\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 304, "If-None-Match wildcard status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_EMPTY, "If-None-Match wildcard body kind mismatch");
    @assert(res.headers.get("Content-Length")!! == "0", "If-None-Match wildcard length mismatch");
}

fn void test_static_handler_not_modified_since()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String modified = first_res.headers.get("Last-Modified")!!;

    String headers = string::tformat("If-Modified-Since: %s\r\n", modified);

    http::Context* second = make_context_with_headers("/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* second_res = http::static_handler(second)!!;

    @assert(second_res.status == 304, "If-Modified-Since status mismatch");
    @assert(second_res.body_kind == http::BodyKind.BODY_EMPTY, "If-Modified-Since body kind mismatch");
    @assert(second_res.body.len == 0, "If-Modified-Since response body should be empty");
}

fn void test_static_handler_if_none_match_precedence()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String modified = first_res.headers.get("Last-Modified")!!;

    String headers = string::tformat(
        "If-None-Match: \"wrong-etag\"\r\n"
        "If-Modified-Since: %s\r\n",
        modified
    );

    http::Context* second = make_context_with_headers("/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* second_res = http::static_handler(second)!!;

    @assert(second_res.status == 200, "If-None-Match precedence status mismatch");
    @assert(second_res.body_kind == http::BodyKind.BODY_FILE, "If-None-Match precedence body kind mismatch");
    @assert(second_res.file_size == HELLO_BODY.len, "If-None-Match precedence file size mismatch");
}


// Range request tests

fn void test_static_handler_range_start_end()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=0-4\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "fixed range status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "fixed range body kind mismatch");
    @assert(res.file_offset == 0, "fixed range offset mismatch");
    @assert(res.file_size == 5, "fixed range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 0-4/12", "fixed range Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "5", "fixed range Content-Length mismatch");
    @assert(res.headers.get("Accept-Ranges")!! == "bytes", "fixed range Accept-Ranges mismatch");
}

fn void test_static_handler_range_middle()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=6-11\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "middle range status mismatch");
    @assert(res.file_offset == 6, "middle range offset mismatch");
    @assert(res.file_size == 6, "middle range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 6-11/12", "middle range Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "6", "middle range Content-Length mismatch");
}

fn void test_static_handler_range_open_ended()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=6-\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "open-ended range status mismatch");
    @assert(res.file_offset == 6, "open-ended range offset mismatch");
    @assert(res.file_size == 6, "open-ended range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 6-11/12", "open-ended Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "6", "open-ended Content-Length mismatch");
}

fn void test_static_handler_range_suffix()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=-6\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "suffix range status mismatch");
    @assert(res.file_offset == 6, "suffix range offset mismatch");
    @assert(res.file_size == 6, "suffix range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 6-11/12", "suffix range Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "6", "suffix range Content-Length mismatch");
}

fn void test_static_handler_range_end_clamped()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=6-999\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "clamped range status mismatch");
    @assert(res.file_offset == 6, "clamped range offset mismatch");
    @assert(res.file_size == 6, "clamped range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 6-11/12", "clamped range Content-Range mismatch");
}

fn void test_static_handler_range_suffix_larger_than_file()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=-100\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "large suffix range status mismatch");
    @assert(res.file_offset == 0, "large suffix range offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "large suffix range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 0-11/12", "large suffix range Content-Range mismatch");
}

fn void test_static_handler_range_not_satisfiable()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=100-200\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 416, "unsatisfied range status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_EMPTY, "unsatisfied range body kind mismatch");
    @assert(res.body.len == 0, "unsatisfied range body mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes */12", "unsatisfied Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "0", "unsatisfied Content-Length mismatch");
    @assert(res.headers.get("Accept-Ranges")!! == "bytes", "unsatisfied Accept-Ranges mismatch");
}

fn void test_static_handler_range_reverse()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=8-3\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 416, "reverse range status mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes */12", "reverse range Content-Range mismatch");
}

fn void test_static_handler_multiple_ranges()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=0-1,4-5\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 416, "multiple range status mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes */12", "multiple range Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "0", "multiple range Content-Length mismatch");
}

fn void test_static_handler_empty_file_range()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/empty.txt",
        "Range: bytes=0-0\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 416, "empty file range status mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes */0", "empty file Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "0", "empty file range length mismatch");
}


// If-Range tests

fn void test_static_handler_if_range_etag_match()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String etag = first_res.headers.get("ETag")!!;

    String headers = string::tformat(
        "Range: bytes=0-4\r\n"
        "If-Range: %s\r\n",
        etag
    );

    http::Context* second = make_context_with_headers("/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* res = http::static_handler(second)!!;

    @assert(res.status == 206, "matching If-Range ETag status mismatch");
    @assert(res.file_offset == 0, "matching If-Range ETag offset mismatch");
    @assert(res.file_size == 5, "matching If-Range ETag size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 0-4/12", "matching If-Range Content-Range mismatch");
}

fn void test_static_handler_if_range_etag_mismatch()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=0-4\r\n"
        "If-Range: \"wrong-etag\"\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "mismatching If-Range ETag status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "mismatching If-Range body kind mismatch");
    @assert(res.file_offset == 0, "mismatching If-Range offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "mismatching If-Range size mismatch");
    @assert(!res.headers.has("Content-Range"), "mismatching If-Range must not include Content-Range");
    @assert(res.headers.get("Content-Length")!! == "12", "mismatching If-Range length mismatch");
}

fn void test_static_handler_if_range_weak_etag()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String etag = first_res.headers.get("ETag")!!;

    String headers = string::tformat(
        "Range: bytes=0-4\r\n"
        "If-Range: W/%s\r\n",
        etag
    );

    http::Context* second = make_context_with_headers("/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* res = http::static_handler(second)!!;

    @assert(res.status == 200, "weak If-Range ETag must produce full response");
    @assert(res.file_offset == 0, "weak If-Range response offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "weak If-Range response size mismatch");
    @assert(!res.headers.has("Content-Range"), "weak If-Range response must not include Content-Range");
}

fn void test_static_handler_if_range_date_match()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String modified = first_res.headers.get("Last-Modified")!!;

    String headers = string::tformat(
        "Range: bytes=6-\r\n"
        "If-Range: %s\r\n",
        modified
    );

    http::Context* second = make_context_with_headers("/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* res = http::static_handler(second)!!;

    @assert(res.status == 206, "matching If-Range date status mismatch");
    @assert(res.file_offset == 6, "matching If-Range date offset mismatch");
    @assert(res.file_size == 6, "matching If-Range date size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 6-11/12", "matching If-Range date Content-Range mismatch");
}

fn void test_static_handler_if_range_date_mismatch()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_with_headers(
        "/static/hello.txt",
        "Range: bytes=0-4\r\n"
        "If-Range: Thu, 01 Jan 1970 00:00:00 GMT\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "mismatching If-Range date status mismatch");
    @assert(res.file_offset == 0, "mismatching If-Range date offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "mismatching If-Range date size mismatch");
    @assert(!res.headers.has("Content-Range"), "mismatching If-Range date must not include Content-Range");
}


// HEAD tests

fn void test_static_handler_head_file()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_method("HEAD", "/static/hello.txt");
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 200, "HEAD static status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "HEAD static body kind mismatch");
    @assert(res.file_offset == 0, "HEAD static offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "HEAD static size mismatch");
    @assert(res.headers.get("Content-Length")!! == "12", "HEAD static Content-Length mismatch");
}

fn void test_static_handler_head_range()
{
    http::set_root(TEST_ROOT);

    http::Context* c = make_context_method(
        "HEAD",
        "/static/hello.txt",
        "Range: bytes=0-4\r\n"
    );
    defer free_context_and_request(c);

    http::Response* res = http::static_handler(c)!!;

    @assert(res.status == 206, "HEAD range status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "HEAD range body kind mismatch");
    @assert(res.file_offset == 0, "HEAD range offset mismatch");
    @assert(res.file_size == 5, "HEAD range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 0-4/12", "HEAD range Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "5", "HEAD range Content-Length mismatch");
}

fn void test_static_handler_head_not_modified()
{
    http::set_root(TEST_ROOT);

    http::Context* first = make_context("/static/hello.txt");
    defer free_context_and_request(first);

    http::Response* first_res = http::static_handler(first)!!;
    String etag = first_res.headers.get("ETag")!!;

    String headers = string::tformat("If-None-Match: %s\r\n", etag);

    http::Context* second = make_context_method("HEAD", "/static/hello.txt", headers);
    defer free_context_and_request(second);

    http::Response* res = http::static_handler(second)!!;

    @assert(res.status == 304, "HEAD conditional status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_EMPTY, "HEAD conditional body kind mismatch");
    @assert(res.headers.get("Content-Length")!! == "0", "HEAD conditional Content-Length mismatch");
}


// Application tests

fn void test_application_static_files()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "Application.static_files status mismatch");
    @assert(res.body_kind == http::BodyKind.BODY_FILE, "Application.static_files body kind mismatch");
    @assert(res.file_offset == 0, "Application.static_files offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "Application.static_files size mismatch");

    @assert(
        res.headers.get("Content-Type")!! == "text/plain; charset=utf-8",
        "Application.static_files content type mismatch"
    );
}

fn void test_application_static_files_range()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=6-11\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 206, "Application.static_files range status mismatch");
    @assert(res.file_offset == 6, "Application.static_files range offset mismatch");
    @assert(res.file_size == 6, "Application.static_files range size mismatch");
    @assert(res.headers.get("Content-Range")!! == "bytes 6-11/12", "Application range Content-Range mismatch");
    @assert(res.headers.get("Content-Length")!! == "6", "Application range Content-Length mismatch");
}

fn void test_application_static_files_root_prefix()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/", TEST_ROOT)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET /hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(res.status == 200, "root static status mismatch");
    @assert(res.file_offset == 0, "root static offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "root static size mismatch");
}

fn void test_static_serialized_response()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "static serialized status missing");

    @assert(
        contains(wire, "Content-Type: text/plain; charset=utf-8\r\n"),
        "static serialized content type missing"
    );

    @assert(
        contains(wire, "Content-Length: 12\r\n"),
        "static serialized length missing"
    );

    @assert(
        contains(wire, "Accept-Ranges: bytes\r\n"),
        "static serialized Accept-Ranges missing"
    );

    @assert(contains(wire, "ETag: "), "static serialized ETag missing");
    @assert(contains(wire, "Last-Modified: "), "static serialized Last-Modified missing");

    @assert(
        !contains(wire, "Transfer-Encoding: chunked\r\n"),
        "file response must not use chunked encoding"
    );

    @assert(
        wire.ends_with("\r\n\r\n"),
        "serialized file response should contain headers only"
    );

    @assert(
        res.body_kind == http::BodyKind.BODY_FILE,
        "static response body kind mismatch"
    );

    @assert(res.file_offset == 0, "static serialized file offset mismatch");
    @assert(res.file_size == HELLO_BODY.len, "static serialized file size mismatch");
}

fn void test_static_serialized_range_response()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=0-4\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 206 Partial Content\r\n"), "serialized range status missing");
    @assert(contains(wire, "Content-Range: bytes 0-4/12\r\n"), "serialized Content-Range missing");
    @assert(contains(wire, "Content-Length: 5\r\n"), "serialized range length missing");
    @assert(contains(wire, "Accept-Ranges: bytes\r\n"), "serialized range Accept-Ranges missing");
    @assert(wire.ends_with("\r\n\r\n"), "serialized range response should contain headers only");

    @assert(res.file_offset == 0, "serialized range offset mismatch");
    @assert(res.file_size == 5, "serialized range size mismatch");
}


// Main

fn void? main_task(void* arg)
{
    cleanup_static_root();
    setup_static_root()!;

    defer cleanup_static_root();

    test_content_type_from_path();

    test_percent_decode();
    test_percent_decode_invalid();

    test_normalize_path();
    test_normalize_path_forbidden();
    test_normalize_rel();
    test_is_safe_rel();
    test_join_path();

    test_read_file_text();
    test_read_file_empty();
    test_read_file_not_found();
    test_read_file_directory();

    test_static_handler_not_configured();
    test_static_handler_text_file();
    test_static_handler_index_fallback();
    test_static_handler_css_file();
    test_static_handler_json_file();
    test_static_handler_empty_file();
    test_static_handler_normalized_path();
    test_static_handler_duplicate_slashes();
    test_static_handler_percent_encoded_path();
    test_static_handler_not_found();
    test_static_handler_forbidden_dotdot();
    test_static_handler_forbidden_normalized_escape();
    test_static_handler_forbidden_encoded_dotdot();
    test_static_handler_forbidden_backslash();
    test_static_handler_forbidden_nul();

    test_static_handler_not_modified_etag();
    test_static_handler_not_modified_etag_wildcard();
    test_static_handler_not_modified_since();
    test_static_handler_if_none_match_precedence();

    test_static_handler_range_start_end();
    test_static_handler_range_middle();
    test_static_handler_range_open_ended();
    test_static_handler_range_suffix();
    test_static_handler_range_end_clamped();
    test_static_handler_range_suffix_larger_than_file();
    test_static_handler_range_not_satisfiable();
    test_static_handler_range_reverse();
    test_static_handler_multiple_ranges();
    test_static_handler_empty_file_range();

    test_static_handler_if_range_etag_match();
    test_static_handler_if_range_etag_mismatch();
    test_static_handler_if_range_weak_etag();
    test_static_handler_if_range_date_match();
    test_static_handler_if_range_date_mismatch();

    test_static_handler_head_file();
    test_static_handler_head_range();
    test_static_handler_head_not_modified();

    test_application_static_files();
    test_application_static_files_range();
    test_application_static_files_root_prefix();

    test_static_serialized_response();
    test_static_serialized_range_response();

    http::clear_root();

    io::printfn("test_static: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof