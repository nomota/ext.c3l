// test_static.c3

// Static file helper tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::staticx;

import std::io;
import ext::aiohttp;
import ext::aio;
import ext::debug;

const String TEST_ROOT = "/tmp/aiohttp_static_test";

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

fn void? write_file(String path, String data) @maydiscard
{
    aio::File* f = aio::file_open(path, "w")!;
    defer f.free();

    f.write_all((char[])data)!;
    f.flush()!;
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
    aiohttp::static_clear_root();

    if (aio::path::exists(TEST_ROOT +++ "/css/app.css")) aio::path::remove(TEST_ROOT +++ "/css/app.css");
    if (aio::path::exists(TEST_ROOT +++ "/js/app.js")) aio::path::remove(TEST_ROOT +++ "/js/app.js");
    if (aio::path::exists(TEST_ROOT +++ "/img/logo.svg")) aio::path::remove(TEST_ROOT +++ "/img/logo.svg");
    if (aio::path::exists(TEST_ROOT +++ "/docs/file.pdf")) aio::path::remove(TEST_ROOT +++ "/docs/file.pdf");
    if (aio::path::exists(TEST_ROOT +++ "/index.html")) aio::path::remove(TEST_ROOT +++ "/index.html");
    if (aio::path::exists(TEST_ROOT +++ "/hello.txt")) aio::path::remove(TEST_ROOT +++ "/hello.txt");
    if (aio::path::exists(TEST_ROOT +++ "/data.json")) aio::path::remove(TEST_ROOT +++ "/data.json");
    if (aio::path::exists(TEST_ROOT +++ "/empty.txt")) aio::path::remove(TEST_ROOT +++ "/empty.txt");

    if (aio::path::exists(TEST_ROOT +++ "/css")) aio::path::removedirs(TEST_ROOT +++ "/css");
    if (aio::path::exists(TEST_ROOT +++ "/js")) aio::path::removedirs(TEST_ROOT +++ "/js");
    if (aio::path::exists(TEST_ROOT +++ "/img")) aio::path::removedirs(TEST_ROOT +++ "/img");
    if (aio::path::exists(TEST_ROOT +++ "/docs")) aio::path::removedirs(TEST_ROOT +++ "/docs");
    if (aio::path::exists(TEST_ROOT)) aio::path::removedirs(TEST_ROOT);
}

fn aiohttp::Request* make_request(String path)
{
    String raw = string::tformat(
        "GET %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n",
        path
    );

    aiohttp::Request* req = aiohttp::request_parse((char[])raw)!!;
    return req;
}

fn aiohttp::Context* make_context(String path)
{
    aiohttp::Request* req = make_request(path);

    aiohttp::Params params;
    params.init();

    String rel;

    if (path == "/static" || path == "/static/")
    {
        rel = "";
    }
    else
    {
        rel = path["/static/".len:path.len - "/static/".len];
    }

    params.set_splat(rel)!!;

    aiohttp::Context* c = aiohttp::context_new_with_params(req, &params)!!;

    params.free();

    return c;
}

fn void free_context_and_request(aiohttp::Context* c)
{
    if (c == null) return;

    aiohttp::Request* req = c.req;

    aiohttp::context_free(c);

    if (req != null)
    {
        aiohttp::request_free(req);
    }
}

fn void test_static_content_type()
{
    @assert(aiohttp::static_content_type("index.html") == "text/html; charset=utf-8", "html content type mismatch");
    @assert(aiohttp::static_content_type("index.htm") == "text/html; charset=utf-8", "htm content type mismatch");
    @assert(aiohttp::static_content_type("app.css") == "text/css; charset=utf-8", "css content type mismatch");
    @assert(aiohttp::static_content_type("app.js") == "application/javascript; charset=utf-8", "js content type mismatch");
    @assert(aiohttp::static_content_type("app.mjs") == "application/javascript; charset=utf-8", "mjs content type mismatch");
    @assert(aiohttp::static_content_type("data.json") == "application/json; charset=utf-8", "json content type mismatch");
    @assert(aiohttp::static_content_type("readme.txt") == "text/plain; charset=utf-8", "txt content type mismatch");
    @assert(aiohttp::static_content_type("logo.svg") == "image/svg+xml", "svg content type mismatch");
    @assert(aiohttp::static_content_type("image.png") == "image/png", "png content type mismatch");
    @assert(aiohttp::static_content_type("image.jpg") == "image/jpeg", "jpg content type mismatch");
    @assert(aiohttp::static_content_type("image.jpeg") == "image/jpeg", "jpeg content type mismatch");
    @assert(aiohttp::static_content_type("image.gif") == "image/gif", "gif content type mismatch");
    @assert(aiohttp::static_content_type("image.webp") == "image/webp", "webp content type mismatch");
    @assert(aiohttp::static_content_type("favicon.ico") == "image/x-icon", "ico content type mismatch");
    @assert(aiohttp::static_content_type("module.wasm") == "application/wasm", "wasm content type mismatch");
    @assert(aiohttp::static_content_type("file.pdf") == "application/pdf", "pdf content type mismatch");
    @assert(aiohttp::static_content_type("file.bin") == "application/octet-stream", "fallback content type mismatch");
}

fn void test_static_contains_dotdot()
{
    @assert(aiohttp::static_contains_dotdot(".."), "dotdot should be blocked");
    @assert(aiohttp::static_contains_dotdot("../x"), "../x should be blocked");
    @assert(aiohttp::static_contains_dotdot("x/../y"), "x/../y should be blocked");
    @assert(aiohttp::static_contains_dotdot("x/.."), "x/.. should be blocked");
    @assert(aiohttp::static_contains_dotdot("a..b"), "a..b should be blocked by conservative policy");

    @assert(!aiohttp::static_contains_dotdot("css/app.css"), "normal path should not be blocked");
    @assert(!aiohttp::static_contains_dotdot("index.html"), "index should not be blocked");
}

fn void test_static_has_backslash()
{
    @assert(aiohttp::static_has_backslash("a\\b"), "backslash should be blocked");
    @assert(!aiohttp::static_has_backslash("a/b"), "slash should not be blocked");
}

fn void test_static_join_path()
{
    String p1 = aiohttp::static_join_path("/tmp/root", "index.html")!!;
    defer aiohttp::localmem.free(p1);

    String p2 = aiohttp::static_join_path("/tmp/root/", "index.html")!!;
    defer aiohttp::localmem.free(p2);

    String p3 = aiohttp::static_join_path("/tmp/root", "/index.html")!!;
    defer aiohttp::localmem.free(p3);

    String p4 = aiohttp::static_join_path("/tmp/root/", "/index.html")!!;
    defer aiohttp::localmem.free(p4);

    @assert(p1 == "/tmp/root/index.html", "join path p1 mismatch");
    @assert(p2 == "/tmp/root/index.html", "join path p2 mismatch");
    @assert(p3 == "/tmp/root/index.html", "join path p3 mismatch");
    @assert(p4 == "/tmp/root/index.html", "join path p4 mismatch");
}

fn void test_static_read_file_text()
{
    char[] data = aiohttp::static_read_file(TEST_ROOT +++ "/hello.txt")!!;
    defer aiohttp::localmem.free(data);

    @assert((String)data == "hello static", "static read text mismatch");
}

fn void test_static_read_file_not_found()
{
    if (catch err = aiohttp::static_read_file(TEST_ROOT +++ "/missing.txt"))
    {
        @assert(err == aiohttp::STATIC_NOT_FOUND, "missing static file fault mismatch");
        return;
    }

    @assert(false, "missing static file should fail");
}

fn void test_static_read_file_directory()
{
    if (catch err = aiohttp::static_read_file(TEST_ROOT +++ "/css"))
    {
        @assert(err == aiohttp::STATIC_NOT_FOUND, "directory static read fault mismatch");
        return;
    }

    @assert(false, "directory static read should fail");
}

fn void test_static_handler_not_configured()
{
    aiohttp::static_clear_root();

    aiohttp::Context* c = make_context("/static/hello.txt");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 500, "static not configured status mismatch");
    @assert((String)res.body == "static root not configured", "static not configured body mismatch");
}

fn void test_static_handler_text_file()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/hello.txt");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 200, "static text status mismatch");
    @assert(res.headers.get("Content-Type")!! == "text/plain; charset=utf-8", "static text content type mismatch");
    @assert((String)res.body == "hello static", "static text body mismatch");
}

fn void test_static_handler_index_fallback()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 200, "static index status mismatch");
    @assert(res.headers.get("Content-Type")!! == "text/html; charset=utf-8", "static index content type mismatch");
    @assert((String)res.body == "<h1>index</h1>", "static index body mismatch");
}

fn void test_static_handler_css_file()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/css/app.css");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 200, "static css status mismatch");
    @assert(res.headers.get("Content-Type")!! == "text/css; charset=utf-8", "static css content type mismatch");
    @assert((String)res.body == "body { margin: 0; }", "static css body mismatch");
}

fn void test_static_handler_json_file()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/data.json");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 200, "static json status mismatch");
    @assert(res.headers.get("Content-Type")!! == "application/json; charset=utf-8", "static json content type mismatch");
    @assert((String)res.body == "{\"ok\":true}", "static json body mismatch");
}

fn void test_static_handler_not_found()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/missing.txt");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 404, "static missing status mismatch");
    @assert((String)res.body == "static file not found", "static missing body mismatch");
}

fn void test_static_handler_forbidden_dotdot()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/../secret.txt");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 403, "static dotdot status mismatch");
    @assert((String)res.body == "forbidden", "static dotdot body mismatch");
}

fn void test_static_handler_forbidden_backslash()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Context* c = make_context("/static/css\\app.css");
    defer free_context_and_request(c);

    aiohttp::Response* res = aiohttp::static_handler(c)!!;

    @assert(res.status == 403, "static backslash status mismatch");
    @assert((String)res.body == "forbidden", "static backslash body mismatch");
}

fn void test_application_static_files()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    aiohttp::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "Application.static_files status mismatch");
    @assert(res.headers.get("Content-Type")!! == "text/plain; charset=utf-8", "Application.static_files content type mismatch");
    @assert((String)res.body == "hello static", "Application.static_files body mismatch");
}

fn void test_application_static_files_root_prefix()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/", TEST_ROOT)!!;

    aiohttp::Response* res = app.fetch_raw((char[])
        "GET /hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "root static status mismatch");
    @assert((String)res.body == "hello static", "root static body mismatch");
}

fn void test_static_serialized_response()
{
    aiohttp::static_set_root(TEST_ROOT);

    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", TEST_ROOT)!!;

    aiohttp::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::response_free(res);

    String wire = res.serialize()!!;
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "HTTP/1.1 200 OK\r\n"), "static serialized status missing");
    @assert(contains(wire, "Content-Type: text/plain; charset=utf-8\r\n"), "static serialized content type missing");
    @assert(contains(wire, "Content-Length: 12\r\n"), "static serialized length missing");
    @assert(contains(wire, "\r\n\r\nhello static"), "static serialized body missing");
}

fn void? main_task(void* arg)
{
    cleanup_static_root();
    setup_static_root()!;

    defer cleanup_static_root();

    test_static_content_type();
    test_static_contains_dotdot();
    test_static_has_backslash();
    test_static_join_path();

    test_static_read_file_text();
    test_static_read_file_not_found();
    test_static_read_file_directory();

    test_static_handler_not_configured();
    test_static_handler_text_file();
    test_static_handler_index_fallback();
    test_static_handler_css_file();
    test_static_handler_json_file();
    test_static_handler_not_found();
    test_static_handler_forbidden_dotdot();
    test_static_handler_forbidden_backslash();

    test_application_static_files();
    test_application_static_files_root_prefix();
    test_static_serialized_response();

    aiohttp::static_clear_root();

    io::printfn("test_static: OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof