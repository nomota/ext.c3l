// test_static.c3

// Static file helper tests for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module test::staticx;

import std::io;
import ext::aio::http;
import ext::aio;
import ext::debug;

const String TEST_ROOT = "/tmp/aio::http_static_test";

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

fn void? setup_static_root() @maydiscard
{
    aio::path::makedirs(TEST_ROOT, 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/css", 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/js", 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/img", 0o777, true)!;
    aio::path::makedirs(TEST_ROOT +++ "/docs", 0o777, true)!;

    write_file(TEST_ROOT +++ "/index.html", "<h1>index</h1>")!;
    write_file(TEST_ROOT +++ "/hello.txt", "hello static")!;
    write_file(TEST_ROOT +++ "/css/app.css", "body { margin: 0; }")!;
    write_file(TEST_ROOT +++ "/js/app.js", "console.log('ok');")!;
    write_file(TEST_ROOT +++ "/data.json", "{\"ok\":true}")!;
    write_file(TEST_ROOT +++ "/img/logo.svg", "<svg></svg>")!;
    write_file(TEST_ROOT +++ "/docs/file.pdf", "%PDF-test")!;
    write_file(TEST_ROOT +++ "/empty.txt", "")!;
}

fn void cleanup_static_root()
{
    aio::http::clear_root();

    if (aio::path::exists(TEST_ROOT +++ "/css/app.css"))
    {
        aio::path::remove(TEST_ROOT +++ "/css/app.css");
    }

    if (aio::path::exists(TEST_ROOT +++ "/js/app.js"))
    {
        aio::path::remove(TEST_ROOT +++ "/js/app.js");
    }

    if (aio::path::exists(TEST_ROOT +++ "/img/logo.svg"))
    {
        aio::path::remove(TEST_ROOT +++ "/img/logo.svg");
    }

    if (aio::path::exists(TEST_ROOT +++ "/docs/file.pdf"))
    {
        aio::path::remove(TEST_ROOT +++ "/docs/file.pdf");
    }

    if (aio::path::exists(TEST_ROOT +++ "/index.html"))
    {
        aio::path::remove(TEST_ROOT +++ "/index.html");
    }

    if (aio::path::exists(TEST_ROOT +++ "/hello.txt"))
    {
        aio::path::remove(TEST_ROOT +++ "/hello.txt");
    }

    if (aio::path::exists(TEST_ROOT +++ "/data.json"))
    {
        aio::path::remove(TEST_ROOT +++ "/data.json");
    }

    if (aio::path::exists(TEST_ROOT +++ "/empty.txt"))
    {
        aio::path::remove(TEST_ROOT +++ "/empty.txt");
    }

    if (aio::path::exists(TEST_ROOT +++ "/css"))
    {
        aio::path::removedirs(TEST_ROOT +++ "/css");
    }

    if (aio::path::exists(TEST_ROOT +++ "/js"))
    {
        aio::path::removedirs(TEST_ROOT +++ "/js");
    }

    if (aio::path::exists(TEST_ROOT +++ "/img"))
    {
        aio::path::removedirs(TEST_ROOT +++ "/img");
    }

    if (aio::path::exists(TEST_ROOT +++ "/docs"))
    {
        aio::path::removedirs(TEST_ROOT +++ "/docs");
    }

    if (aio::path::exists(TEST_ROOT))
    {
        aio::path::removedirs(TEST_ROOT);
    }
}

fn aio::http::Request* make_request(String request_path)
{
    String raw = string::tformat(
        "GET %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        request_path
    );

    return aio::http::request_parse((char[])raw)!!;
}

fn aio::http::Request* make_request_with_headers(String request_path, String headers)
{
    String raw = string::tformat(
        "GET %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "%s"
        "\r\n",
        request_path,
        headers
    );

    return aio::http::request_parse((char[])raw)!!;
}

fn aio::http::Context* make_context_from_request(
    aio::http::Request* req,
    String request_path)
{
    aio::http::Params params;
    params.init();

    String rel;

    if (request_path == "/static" || request_path == "/static/")
    {
        rel = "";
    }
    else if (request_path.starts_with("/static/"))
    {
        rel = request_path[
            "/static/".len:
            request_path.len - "/static/".len
        ];
    }
    else if (request_path.starts_with("/"))
    {
        rel = request_path[1..];
    }
    else
    {
        rel = request_path;
    }

    params.set_splat(rel)!!;

    aio::http::Context* c =
        aio::http::context_new_with_params(req, &params)!!;

    params.free();

    return c;
}

fn aio::http::Context* make_context(String request_path)
{
    aio::http::Request* req = make_request(request_path);

    return make_context_from_request(req, request_path);
}

fn aio::http::Context* make_context_with_headers(
    String request_path,
    String headers)
{
    aio::http::Request* req =
        make_request_with_headers(request_path, headers);

    return make_context_from_request(req, request_path);
}

fn void free_context_and_request(aio::http::Context* c)
{
    if (c == null) return;

    aio::http::Request* req = c.req;

    aio::http::context_free(c);

    if (req != null)
    {
        aio::http::request_free(req);
    }
}

fn void free_owned_string(String value)
{
    if (value.len > 0)
    {
        aio::http::localmem.free(value);
    }
}

fn void test_content_type_from_path()
{
    @assert(
        aio::http::content_type_from_path("index.html") ==
            "text/html; charset=utf-8",
        "html content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("index.htm") ==
            "text/html; charset=utf-8",
        "htm content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("app.css") ==
            "text/css; charset=utf-8",
        "css content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("app.js") ==
            "application/javascript; charset=utf-8",
        "js content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("app.mjs") ==
            "application/javascript; charset=utf-8",
        "mjs content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("data.json") ==
            "application/json; charset=utf-8",
        "json content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("readme.txt") ==
            "text/plain; charset=utf-8",
        "txt content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("data.xml") ==
            "application/xml; charset=utf-8",
        "xml content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("data.csv") ==
            "text/csv; charset=utf-8",
        "csv content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("logo.svg") ==
            "image/svg+xml",
        "svg content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("image.png") ==
            "image/png",
        "png content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("image.jpg") ==
            "image/jpeg",
        "jpg content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("image.jpeg") ==
            "image/jpeg",
        "jpeg content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("image.gif") ==
            "image/gif",
        "gif content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("image.webp") ==
            "image/webp",
        "webp content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("favicon.ico") ==
            "image/x-icon",
        "ico content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("module.wasm") ==
            "application/wasm",
        "wasm content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("file.pdf") ==
            "application/pdf",
        "pdf content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("file.zip") ==
            "application/zip",
        "zip content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("file.gz") ==
            "application/gzip",
        "gzip content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("movie.mp4") ==
            "video/mp4",
        "mp4 content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("movie.webm") ==
            "video/webm",
        "webm content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("audio.mp3") ==
            "audio/mpeg",
        "mp3 content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("audio.wav") ==
            "audio/wav",
        "wav content type mismatch"
    );

    @assert(
        aio::http::content_type_from_path("file.bin") ==
            "application/octet-stream",
        "fallback content type mismatch"
    );
}

fn void test_percent_decode()
{
    String decoded1 = aio::http::percent_decode("hello.txt")!!;
    defer aio::http::localmem.free(decoded1);

    String decoded2 = aio::http::percent_decode("css%2Fapp.css")!!;
    defer aio::http::localmem.free(decoded2);

    String decoded3 = aio::http::percent_decode("%68%65%6c%6c%6f.txt")!!;
    defer aio::http::localmem.free(decoded3);

    @assert(decoded1 == "hello.txt", "plain percent decode mismatch");
    @assert(decoded2 == "css/app.css", "slash percent decode mismatch");
    @assert(decoded3 == "hello.txt", "encoded text decode mismatch");
}

fn void test_percent_decode_invalid()
{
    if (catch err = aio::http::percent_decode("%"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "short percent encoding fault mismatch"
        );
    }
    else
    {
        @assert(false, "short percent encoding should fail");
    }

    if (catch err = aio::http::percent_decode("%2"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "incomplete percent encoding fault mismatch"
        );
    }
    else
    {
        @assert(false, "incomplete percent encoding should fail");
    }

    if (catch err = aio::http::percent_decode("%GG"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "invalid percent encoding fault mismatch"
        );
    }
    else
    {
        @assert(false, "invalid percent encoding should fail");
    }

    if (catch err = aio::http::percent_decode("%00"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "NUL percent encoding fault mismatch"
        );
    }
    else
    {
        @assert(false, "NUL percent encoding should fail");
    }
}

fn void test_normalize_path()
{
    String p1 = aio::http::normalize_path("css/./app.css")!!;
    defer free_owned_string(p1);

    String p2 = aio::http::normalize_path("css/a/../app.css")!!;
    defer free_owned_string(p2);

    String p3 = aio::http::normalize_path("css//app.css")!!;
    defer free_owned_string(p3);

    String p4 = aio::http::normalize_path("//css///app.css//")!!;
    defer free_owned_string(p4);

    String p5 = aio::http::normalize_path("a/b/../../hello.txt")!!;
    defer free_owned_string(p5);

    String p6 = aio::http::normalize_path(".")!!;
    defer free_owned_string(p6);

    String p7 = aio::http::normalize_path("a/..")!!;
    defer free_owned_string(p7);

    String p8 = aio::http::normalize_path("..hidden/file.txt")!!;
    defer free_owned_string(p8);

    @assert(p1 == "css/app.css", "normalize dot segment mismatch");
    @assert(p2 == "css/app.css", "normalize parent segment mismatch");
    @assert(p3 == "css/app.css", "normalize duplicate slash mismatch");
    @assert(p4 == "/css/app.css", "normalize absolute path mismatch");
    @assert(p5 == "hello.txt", "normalize nested parent mismatch");
    @assert(p6.len == 0, "normalize current directory mismatch");
    @assert(p7.len == 0, "normalize removed path mismatch");
    @assert(
        p8 == "..hidden/file.txt",
        "normal filename beginning with dots mismatch"
    );
}

fn void test_normalize_path_forbidden()
{
    if (catch err = aio::http::normalize_path("../secret.txt"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "relative parent escape fault mismatch"
        );
    }
    else
    {
        @assert(false, "relative parent escape should fail");
    }

    if (catch err = aio::http::normalize_path("/../secret.txt"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "absolute parent escape fault mismatch"
        );
    }
    else
    {
        @assert(false, "absolute parent escape should fail");
    }

    if (catch err = aio::http::normalize_path("/a/../../b"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "normalized root escape fault mismatch"
        );
    }
    else
    {
        @assert(false, "normalized root escape should fail");
    }

    if (catch err = aio::http::normalize_path("css\\app.css"))
    {
        @assert(
            err == aio::http::STATIC_FORBIDDEN,
            "backslash fault mismatch"
        );
    }
    else
    {
        @assert(false, "backslash path should fail");
    }
}

fn void test_normalize_rel()
{
    @assert(
        aio::http::normalize_rel("") == "index.html",
        "empty relative path mismatch"
    );

    @assert(
        aio::http::normalize_rel("/") == "index.html",
        "root relative path mismatch"
    );

    @assert(
        aio::http::normalize_rel("///") == "index.html",
        "multiple root slash mismatch"
    );

    @assert(
        aio::http::normalize_rel("/hello.txt") == "hello.txt",
        "leading slash removal mismatch"
    );

    @assert(
        aio::http::normalize_rel("css/app.css") == "css/app.css",
        "normal relative path mismatch"
    );
}

fn void test_is_safe_rel()
{
    @assert(
        aio::http::is_safe_rel("css/app.css"),
        "normal relative path should be safe"
    );

    @assert(
        aio::http::is_safe_rel("..hidden/file.txt"),
        "normal dotted filename should be safe"
    );

    @assert(
        !aio::http::is_safe_rel("../secret.txt"),
        "leading parent segment should be unsafe"
    );

    @assert(
        !aio::http::is_safe_rel("a/../secret.txt"),
        "middle parent segment should be unsafe"
    );

    @assert(
        !aio::http::is_safe_rel("css\\app.css"),
        "backslash path should be unsafe"
    );
}

fn void test_join_path()
{
    String p1 = aio::http::join_path("/tmp/root", "index.html")!!;
    defer aio::http::localmem.free(p1);

    String p2 = aio::http::join_path("/tmp/root/", "index.html")!!;
    defer aio::http::localmem.free(p2);

    String p3 = aio::http::join_path("/tmp/root", "/index.html")!!;
    defer aio::http::localmem.free(p3);

    String p4 = aio::http::join_path("/tmp/root/", "/index.html")!!;
    defer aio::http::localmem.free(p4);

    @assert(
        p1 == "/tmp/root/index.html",
        "join path p1 mismatch"
    );

    @assert(
        p2 == "/tmp/root/index.html",
        "join path p2 mismatch"
    );

    @assert(
        p3 == "/tmp/root/index.html",
        "join path p3 mismatch"
    );

    @assert(
        p4 == "/tmp/root/index.html",
        "join path p4 mismatch"
    );

    if (catch err = aio::http::join_path("", "index.html"))
    {
        @assert(
            err == aio::http::STATIC_NOT_CONFIGURED,
            "empty root fault mismatch"
        );
    }
    else
    {
        @assert(false, "empty root should fail");
    }
}

fn void test_read_file_text()
{
    char[] data =
        aio::file_load((char[])(TEST_ROOT +++ "/hello.txt"))!!;
    defer aio::http::localmem.free(data);

    @assert(
        (String)data == "hello static",
        "static read text mismatch"
    );
}

fn void test_read_file_empty()
{
    char[] data =
        aio::file_load((char[])(TEST_ROOT +++ "/empty.txt"))!!;

    @assert(data.len == 0, "empty file length mismatch");
}

fn void test_read_file_not_found()
{
    if (catch err =
        aio::file_load((char[])(TEST_ROOT +++ "/missing.txt")))
    {
        return;
    }

    @assert(false, "missing static file should fail");
}

fn void test_read_file_directory()
{
    if (catch err =
        aio::file_load((char[])(TEST_ROOT +++ "/css")))
    {
        @assert(
            err == aio::http::PATH_IS_NOT_FILE,
            "directory read fault mismatch"
        );

        return;
    }

    @assert(false, "directory static read should fail");
}

fn void test_static_handler_not_configured()
{
    aio::http::clear_root();

    aio::http::Context* c = make_context("/static/hello.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 500,
        "static not configured status mismatch"
    );

    @assert(
        (String)res.body == "static root not configured",
        "static not configured body mismatch"
    );
}

fn void test_static_handler_text_file()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c = make_context("/static/hello.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 200, "static text status mismatch");

    @assert(
        res.headers.get("Content-Type")!! ==
            "text/plain; charset=utf-8",
        "static text content type mismatch"
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
//warn((String)res.body);
    @assert(res.file_size == 12,
        "static text body mismatch"
    );
}

fn void test_static_handler_index_fallback()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c = make_context("/static/");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 200, "static index status mismatch");

    @assert(
        res.headers.get("Content-Type")!! ==
            "text/html; charset=utf-8",
        "static index content type mismatch"
    );

    @assert(
        res.file_size == "<h1>index</h1>".len,
        "static index body mismatch"
    );
}

fn void test_static_handler_css_file()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c = make_context("/static/css/app.css");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 200, "static css status mismatch");

    @assert(
        res.headers.get("Content-Type")!! ==
            "text/css; charset=utf-8",
        "static css content type mismatch"
    );

    @assert(
        res.file_size == "body { margin: 0; }".len,
        "static css body mismatch"
    );
}

fn void test_static_handler_json_file()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c = make_context("/static/data.json");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 200, "static json status mismatch");

    @assert(
        res.headers.get("Content-Type")!! ==
            "application/json; charset=utf-8",
        "static json content type mismatch"
    );

    @assert(
        res.file_size == "{\"ok\":true}".len,
        "static json body mismatch"
    );
}

fn void test_static_handler_empty_file()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c = make_context("/static/empty.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 200, "empty static file status mismatch");

    @assert(
        res.headers.get("Content-Type")!! ==
            "text/plain; charset=utf-8",
        "empty static file content type mismatch"
    );

    @assert(res.body.len == 0, "empty static file body mismatch");
}

fn void test_static_handler_normalized_path()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/css/../hello.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 200,
        "normalized static path status mismatch"
    );

    @assert(
        res.file_size == "hello static".len,
        "normalized static path body mismatch"
    );
}

fn void test_static_handler_duplicate_slashes()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/css//app.css");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 200,
        "duplicate slash static path status mismatch"
    );

    @assert(
        res.file_size == "body { margin: 0; }".len,
        "duplicate slash static path body mismatch"
    );
}

fn void test_static_handler_percent_encoded_path()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/css%2Fapp.css");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 200,
        "percent encoded static path status mismatch"
    );

    @assert(
        res.file_size == "body { margin: 0; }".len,
        "percent encoded static path body mismatch"
    );
}

fn void test_static_handler_not_found()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c = make_context("/static/missing.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 404, "static missing status mismatch");

    @assert(
        (String)res.body == "static file not found",
        "static missing body mismatch"
    );
}

fn void test_static_handler_forbidden_dotdot()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/../secret.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(res.status == 403, "static dotdot status mismatch");

    @assert(
        (String)res.body == "forbidden",
        "static dotdot body mismatch"
    );
}

fn void test_static_handler_forbidden_normalized_escape()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/a/../../secret.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 403,
        "normalized static escape status mismatch"
    );

    @assert(
        (String)res.body == "forbidden",
        "normalized static escape body mismatch"
    );
}

fn void test_static_handler_forbidden_encoded_dotdot()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/%2e%2e/secret.txt");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 403,
        "encoded static dotdot status mismatch"
    );

    @assert(
        (String)res.body == "forbidden",
        "encoded static dotdot body mismatch"
    );
}

fn void test_static_handler_forbidden_backslash()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/css\\app.css");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 403,
        "static backslash status mismatch"
    );

    @assert(
        (String)res.body == "forbidden",
        "static backslash body mismatch"
    );
}

fn void test_static_handler_forbidden_nul()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* c =
        make_context("/static/hello.txt%00.html");
    defer free_context_and_request(c);

    aio::http::Response* res = aio::http::static_handler(c)!!;

    @assert(
        res.status == 403,
        "static NUL path status mismatch"
    );

    @assert(
        (String)res.body == "forbidden",
        "static NUL path body mismatch"
    );
}

fn void test_static_handler_not_modified_etag()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* first =
        make_context("/static/hello.txt");
    defer free_context_and_request(first);

    aio::http::Response* first_res =
        aio::http::static_handler(first)!!;

    String etag = first_res.headers.get("ETag")!!;

    String headers = string::tformat(
        "If-None-Match: %s\r\n",
        etag
    );

    aio::http::Context* second =
        make_context_with_headers(
            "/static/hello.txt",
            headers
        );
    defer free_context_and_request(second);

    aio::http::Response* second_res =
        aio::http::static_handler(second)!!;

    @assert(
        second_res.status == 304,
        "If-None-Match status mismatch"
    );

    @assert(
        second_res.body.len == 0,
        "304 response body should be empty"
    );

    @assert(
        second_res.headers.get("ETag")!! == etag,
        "304 ETag mismatch"
    );

    @assert(
        second_res.headers.get("Accept-Ranges")!! == "bytes",
        "304 Accept-Ranges mismatch"
    );
}

fn void test_static_handler_not_modified_since()
{
    aio::http::set_root(TEST_ROOT);

    aio::http::Context* first =
        make_context("/static/hello.txt");
    defer free_context_and_request(first);

    aio::http::Response* first_res =
        aio::http::static_handler(first)!!;

    String modified =
        first_res.headers.get("Last-Modified")!!;

    String headers = string::tformat(
        "If-Modified-Since: %s\r\n",
        modified
    );

    aio::http::Context* second =
        make_context_with_headers(
            "/static/hello.txt",
            headers
        );
    defer free_context_and_request(second);

    aio::http::Response* second_res =
        aio::http::static_handler(second)!!;

    @assert(
        second_res.status == 304,
        "If-Modified-Since status mismatch"
    );

    @assert(
        second_res.body.len == 0,
        "If-Modified-Since response body should be empty"
    );
}

fn void test_application_static_files()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(
        res.status == 200,
        "Application.static_files status mismatch"
    );

    @assert(
        res.headers.get("Content-Type")!! ==
            "text/plain; charset=utf-8",
        "Application.static_files content type mismatch"
    );

    @assert(
        res.file_size == "hello static".len,
        "Application.static_files body mismatch"
    );
}

fn void test_application_static_files_root_prefix()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/", TEST_ROOT)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "root static status mismatch");

    @assert(res.file_size == "hello static".len,
        "root static body mismatch"
    );
}

fn void test_static_serialized_response()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    aio::http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::response_free(res);

    String wire = res.serialize()!!;
    defer aio::http::localmem.free(wire);

    @assert(
        contains(wire, "HTTP/1.1 200 OK\r\n"),
        "static serialized status missing"
    );

    @assert(
        contains(
            wire,
            "Content-Type: text/plain; charset=utf-8\r\n"
        ),
        "static serialized content type missing"
    );
//warn(wire);
    @assert(
        contains(wire, "Content-Length: 12\r\n"),
        "static serialized length missing"
    );

    @assert(
        contains(wire, "Accept-Ranges: bytes\r\n"),
        "static serialized Accept-Ranges missing"
    );

    @assert(
        contains(wire, "ETag: "),
        "static serialized ETag missing"
    );

    @assert(
        contains(wire, "Last-Modified: "),
        "static serialized Last-Modified missing"
    );

    @assert(
        !contains(wire, "Transfer-Encoding: chunked\r\n"),
        "file response must not use chunked encoding"
    );
    
    @assert(
        wire.ends_with("\r\n\r\n"),
        "serialized file response should contain headers only"
    );
    
    @assert(
        res.body_kind == aio::http::BodyKind.BODY_FILE,
        "static response body kind mismatch"
    );
    
    @assert(
        res.file_size == "hello static".len,
        "static serialized file size mismatch"
    );
}

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
    test_static_handler_not_modified_since();

    test_application_static_files();
    test_application_static_files_root_prefix();
    test_static_serialized_response();

    aio::http::clear_root();

    io::printfn("test_static: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof