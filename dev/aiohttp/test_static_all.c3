// test_static_all.c3

// Static file serving integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::static_all;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::aio::path;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18102;

const sz MAX_RESPONSE_BYTES = 1024 * 1024;
const usz RESPONSE_TIMEOUT_US = 2_000_000;

const String ROOT = "zz_static_all";
const String PUBLIC_DIR = "zz_static_all/public";
const String SECRET_PATH = "zz_static_all/secret.txt";
const String INDEX_PATH = "zz_static_all/public/index.html";
const String TXT_PATH = "zz_static_all/public/hello.txt";
const String CSS_PATH = "zz_static_all/public/app.css"; 
const String JS_PATH = "zz_static_all/public/app.js";
const String JSON_PATH = "zz_static_all/public/data.json";
const String DIR_PATH = "zz_static_all/public/dir";
const String LINK_PATH = "zz_static_all/public/link.txt";

// Response helpers

fn sz count_occurrences(String text, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= text.len)
    {
        sz idx = text[pos..].index_of(needle) ?? -1;
        if (idx < 0) break;

        count++;
        pos += idx + needle.len;
    }

    return count;
}

fn String body_part(String raw)
{
    sz idx = raw.index_of("\r\n\r\n") ?? -1;
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;

    String prefix = string::bformat(
        buf[..],
        "HTTP/1.1 %d ",
        status
    );

    return raw.starts_with(prefix);
}

fn bool has_header(String raw, String header)
{
    return raw.contains(header);
}

fn String? header_value(String raw, String name)
{
    sz header_end = raw.index_of("\r\n\r\n") ?? -1;
    if (header_end < 0) return http::NOT_FOUND~;

    String headers = raw[0:header_end];
    sz pos = 0;

    // Skip the status line.
    sz status_end = headers.index_of("\r\n") ?? -1;
    if (status_end < 0) return http::NOT_FOUND~;

    pos = status_end + 2;

    while (pos < headers.len)
    {
        sz line_end =
            headers[pos..].index_of("\r\n") ?? -1;

        String line;

        if (line_end < 0)
        {
            line = headers[pos..];
            pos = headers.len;
        }
        else
        {
            line = headers[pos:line_end];
            pos += line_end + 2;
        }

        if (line.len == 0) continue;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) continue;

        String header_name = line[0:colon];

        if (!http::str_iequals(header_name, name))
        {
            continue;
        }

        return line[colon + 1..].trim();
    }

    return http::NOT_FOUND~;
}

// File helpers

fn void cleanup_files()
{
    if (catch path::remove(LINK_PATH)) {}

    char[256] cmd;

    string::bformat(
        cmd[..],
        "rm -rf %s",
        ROOT
    );

    stdlib::system(&cmd[0]);
}

fn void? write_all_file(String file_path, char[] data)
{
    aio::File* file = aio::file_open(file_path, "wb")!;
    defer file.close();

    sz total = 0;

    while (total < data.len)
    {
        sz n = file.write(
            data[total:data.len - total]
        )!;

        if (n <= 0)
        {
            return http::WRITE_ERROR~;
        }

        total += n;
    }
}

fn void? setup_files()
{
    cleanup_files();

    path::makedirs(PUBLIC_DIR, 0o777, true)!;
    path::makedirs(DIR_PATH, 0o777, true)!;

    write_all_file(
        SECRET_PATH,
        (char[])"secret"
    )!;

    write_all_file(
        INDEX_PATH,
        (char[])"<h1>index</h1>"
    )!;

    write_all_file(
        TXT_PATH,
        (char[])"hello static"
    )!;

    write_all_file(
        CSS_PATH,
        (char[])"body { color: black; }"
    )!;

    write_all_file(
        JS_PATH,
        (char[])"console.log('ok');"
    )!;

    write_all_file(
        JSON_PATH,
        (char[])"{\"ok\":true}"
    )!;

    // Symlink creation may not be supported or permitted.
    if (catch path::symlink("../secret.txt", LINK_PATH))
    {
    }
}

// HTTP client helpers

fn String? fetch_raw(String request, usz read_timeout_us = RESPONSE_TIMEOUT_US)
{
    aio::Stream* client =
        aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString out;
    out.init(http::localmem, 4096);
    defer out.free();

    while (true)
    {
        char[4096] buf;

        sz? read_result =
            client.read_timeout(
                buf[..],
                read_timeout_us
            );

        if (catch err = read_result)
        {
            if (err == aio::CLOSED) break;

            // Every request in this file eventually asks the
            // server to close the connection. A timeout therefore
            // indicates an incomplete or hung response.
            if (err == aio::TIMEOUT) return aio::TIMEOUT~;

            return err~;
        }

        sz n = read_result;
        if (n == 0) break;

        out.append(buf[0:n]);

        if (out.len() > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }
    }

    client.close();

    return out.copy_str(http::localmem);
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < 200; i++)
    {
        aio::Stream*? stream_result =
            aio::stream_connect(HOST, PORT);

        if (catch err = stream_result)
        {
            aio::sleep(10_000)!;
            continue;
        }

        aio::Stream* stream = stream_result;

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void wake_server()
{
    aio::Stream*? stream_result =
        aio::stream_connect(HOST, PORT);

    if (catch err = stream_result)
    {
        return;
    }

    aio::Stream* stream = stream_result;

    stream.close();
    stream.free();
}

// Server task

fn void? server_task(void* arg)
{
    ApplicationServer* server =
        (ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
}

// Tests

fn void? test_static_get_txt()
{
    String raw = fetch_raw(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "static text status mismatch"
    );

    @assert(
        has_header(
            raw,
            "Content-Type: text/plain; charset=utf-8\r\n"
        ),
        "static text content type mismatch"
    );

    @assert(
        body_part(raw).contains("hello static"),
        "static text body mismatch"
    );
}

fn void? test_static_get_index()
{
    String raw = fetch_raw(
        "GET /static/ HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "static index status mismatch"
    );

    @assert(
        has_header(
            raw,
            "Content-Type: text/html; charset=utf-8\r\n"
        ),
        "static index content type mismatch"
    );

    @assert(
        body_part(raw).contains("<h1>index</h1>"),
        "static index body mismatch"
    );
}

fn void? test_static_head_txt()
{
    String raw = fetch_raw(
        "HEAD /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "static HEAD status mismatch"
    );

    @assert(
        has_header(
            raw,
            "Content-Type: text/plain; charset=utf-8\r\n"
        ),
        "static HEAD content type mismatch"
    );

    @assert(
        body_part(raw).len == 0,
        "static HEAD response contains a body"
    );
}

fn void? test_static_not_found()
{
    String raw = fetch_raw(
        "GET /static/missing.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 404),
        "missing static file status mismatch"
    );
}

fn void? test_static_directory_not_found()
{
    String raw = fetch_raw(
        "GET /static/dir HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 404),
        "static directory should not be served"
    );
}

fn void? test_static_path_traversal_forbidden()
{
    String raw = fetch_raw(
        "GET /static/../secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 403),
        "static path traversal should be forbidden"
    );
}

fn void? test_static_nested_path_traversal_forbidden()
{
    String raw = fetch_raw(
        "GET /static/a/../../secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 403),
        "nested static path traversal should be forbidden"
    );
}

fn void? test_static_percent_encoded_traversal_forbidden()
{
    String raw = fetch_raw(
        "GET /static/%2e%2e/secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 403),
        "encoded static path traversal should be forbidden"
    );
}

fn void? test_static_percent_encoded_upper_traversal_forbidden()
{
    String raw = fetch_raw(
        "GET /static/%2E%2E/secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 403),
        "uppercase encoded traversal should be forbidden"
    );
}

fn void? test_static_backslash_forbidden()
{
    String raw = fetch_raw(
        "GET /static/a%5Cb.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 403),
        "encoded backslash path should be forbidden"
    );
}

fn void? test_static_symlink_forbidden_or_not_found()
{
    // Skip when the platform did not create the symlink.
    if (!path::exists(LINK_PATH))
    {
        return;
    }

    String raw = fetch_raw(
        "GET /static/link.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 403) ||
        status_is(raw, 404),
        "static symlink should be forbidden or hidden"
    );
}

fn void? test_static_content_types()
{
    String css = fetch_raw(
        "GET /static/app.css HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(css);

    @assert(
        status_is(css, 200),
        "CSS status mismatch"
    );

    @assert(
        has_header(
            css,
            "Content-Type: text/css; charset=utf-8\r\n"
        ),
        "CSS content type mismatch"
    );

    String js = fetch_raw(
        "GET /static/app.js HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(js);

    @assert(
        status_is(js, 200),
        "JavaScript status mismatch"
    );

    @assert(
        has_header(
            js,
            "Content-Type: application/javascript; "
            "charset=utf-8\r\n"
        ),
        "JavaScript content type mismatch"
    );

    String json = fetch_raw(
        "GET /static/data.json HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(json);

    @assert(
        status_is(json, 200),
        "JSON status mismatch"
    );

    @assert(
        has_header(
            json,
            "Content-Type: application/json; charset=utf-8\r\n"
        ),
        "JSON content type mismatch"
    );
}

fn void? test_static_cache_headers_exist()
{
    String raw = fetch_raw(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "cache header response status mismatch"
    );

    @assert(
        has_header(raw, "Accept-Ranges: bytes\r\n"),
        "Accept-Ranges header missing"
    );

    if (raw.contains("Last-Modified: "))
    {
        @assert(
            raw.contains("ETag: "),
            "ETag missing when Last-Modified exists"
        );
    }
}

fn void? test_static_if_none_match()
{
    String first = fetch_raw(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    @assert(
        status_is(first, 200),
        "initial ETag request status mismatch"
    );

    String? etag_result =
        header_value(first, "ETag");

    if (catch err = etag_result)
    {
        return;
    }

    String etag = etag_result;

    String request = string::format(
        http::localmem,
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-None-Match: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        etag
    );
    defer http::localmem.free(request);

    String second = fetch_raw(request)!;
    defer http::localmem.free(second);

    @assert(
        status_is(second, 304),
        "If-None-Match status mismatch"
    );

    @assert(
        body_part(second).len == 0,
        "304 ETag response contains a body"
    );
}

fn void? test_static_if_modified_since()
{
    String first = fetch_raw(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    @assert(
        status_is(first, 200),
        "initial Last-Modified request status mismatch"
    );

    String? modified_result =
        header_value(first, "Last-Modified");

    if (catch err = modified_result)
    {
        return;
    }

    String last_modified = modified_result;

    String request = string::format(
        http::localmem,
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-Modified-Since: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        last_modified
    );
    defer http::localmem.free(request);

    String second = fetch_raw(request)!;
    defer http::localmem.free(second);

    @assert(
        status_is(second, 304),
        "If-Modified-Since status mismatch"
    );

    @assert(
        body_part(second).len == 0,
        "304 Last-Modified response contains a body"
    );
}

fn void? test_static_keepalive_pipeline()
{
    String raw = fetch_raw(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /static/data.json HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        count_occurrences(
            raw,
            "HTTP/1.1 200 OK"
        ) == 2,
        "pipeline response count mismatch"
    );

    @assert(
        raw.contains("hello static"),
        "first pipeline body missing"
    );

    @assert(
        raw.contains("{\"ok\":true}"),
        "second pipeline body missing"
    );

    sz text_pos =
        raw.index_of("hello static") ?? -1;

    sz json_pos =
        raw.index_of("{\"ok\":true}") ?? -1;

    @assert(
        text_pos >= 0 && json_pos >= 0,
        "pipeline response body position missing"
    );

    @assert(
        text_pos < json_pos,
        "pipeline response order mismatch"
    );
}

fn void? test_main(void* arg)
{
    setup_files()!;
    defer cleanup_files();

    Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", PUBLIC_DIR)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_static_get_txt()!;
    test_static_get_index()!;
    test_static_head_txt()!;
    test_static_not_found()!;
    test_static_directory_not_found()!;
    test_static_path_traversal_forbidden()!;
    test_static_nested_path_traversal_forbidden()!;
    test_static_percent_encoded_traversal_forbidden()!; 
    test_static_percent_encoded_upper_traversal_forbidden()!;
    test_static_backslash_forbidden()!;
    test_static_symlink_forbidden_or_not_found()!;
    test_static_content_types()!;
    test_static_cache_headers_exist()!;
    test_static_if_none_match()!;
    test_static_if_modified_since()!;
    test_static_keepalive_pipeline()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    io::printfn("test_static_all: OK");
}

fn void main()
{
    aio::run(&test_main)!!; 
}

// eof 