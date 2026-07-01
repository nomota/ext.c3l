// test_stream_all.c3

// Integration tests for static streaming, HEAD stream/file,
// no-body stream/file, header validation, and static security.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::stream_all;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;
import ext::aio::path;
import c::stdlib;

const String HOST = "127.0.0.1";
const ushort PORT = 18096;

const String ROOT = "zz_root";
const String LARGE_FILE = "zz_root/large.txt";
const String SMALL_FILE = "zz_root/small.txt";
const String SECRET_FILE = "zz_root/secret.txt";
const String SUBDIR = "zz_root/subdir";
const String LINK_FILE = "zz_root/link.txt";

const sz LARGE_SIZE = 96 * 1024;
const sz MAX_RESPONSE_BYTES = 1024 * 1024;
const usz RESPONSE_TIMEOUT_US = 2_000_000;

int g_stream_writer_called = 0;
int g_no_body_stream_writer_called = 0;

// Response helpers

fn String body_part(String raw)
{
    sz idx = raw.index_of("\r\n\r\n") ?? -1;
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool has_header(String raw, String header)
{
    return raw.contains(header);
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

// File helpers

fn void? write_all_file(String file_path, char[] data)
{
    aio::File* file = aio::file_open(file_path, "w")!;
    defer file.close();

    sz total = 0;

    while (total < data.len)
    {
        sz n = file.write(
            data[total:data.len - total]
        )!;

        if (n <= 0)
        {
            return http::STATIC_READ_ERROR~;
        }

        total += n;
    }
}

fn char[]? make_large_data()
{
    char* p = http::localmem.malloc(LARGE_SIZE)!;
    char[] data = p[0:LARGE_SIZE];

    for (sz i = 0; i < data.len; i++)
    {
        data[i] = 'A' + (char)(i % 26);
    }

    String marker = "STATIC_STREAM_MARKER_0123456789";

    data[4096:marker.len] =
        marker[0:marker.len];

    return data;
}

fn void cleanup_files()
{
    if (catch path::remove(LINK_FILE)) {}
    if (catch path::remove(LARGE_FILE)) {}
    if (catch path::remove(SMALL_FILE)) {}
    if (catch path::remove(SECRET_FILE)) {}

    char[256] cmd;

    string::bformat(
        cmd[..],
        "rm -rf %s",
        ROOT
    );

    stdlib::system(&cmd[0]);
}

fn void? setup_files()
{
    cleanup_files();

    path::makedirs(ROOT, 0o777, true)!;
    path::makedirs(SUBDIR, 0o777, true)!;

    write_all_file(
        SMALL_FILE,
        (char[])"small static file"
    )!;

    write_all_file(
        SECRET_FILE,
        (char[])"secret"
    )!;

    char[] large = make_large_data()!;
    defer http::localmem.free(large);

    write_all_file(LARGE_FILE, large)!;
}

// HTTP client helpers

fn String? fetch_raw(String request)
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
                RESPONSE_TIMEOUT_US
            );

        if (catch err = read_result)
        {
            if (err == aio::CLOSED)
            {
                break;
            }

            if (err == aio::TIMEOUT)
            {
                return aio::TIMEOUT~;
            }

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

// Handlers

fn void? test_stream_writer(aio::Stream* stream, void* arg)
{
    g_stream_writer_called++;

    http::write_chunk(stream, "hello")!;

    http::write_chunk(stream, " stream")!;
}

fn void? no_body_stream_writer(aio::Stream* stream, void* arg)
{
    g_no_body_stream_writer_called++;

    http::write_chunk(stream, "must-not-run")!;
}

fn Response*? stream_handler(Ctx* c)
{
    return c.stream(&test_stream_writer, null)!;
}

fn Response*? head_stream_handler(Ctx* c)
{
    return c.stream(&test_stream_writer, null)!;
}

fn Response*? head_file_handler(Ctx* c)
{
    return c.file(LARGE_FILE, LARGE_SIZE)!;
}

fn Response*? no_body_stream_handler(Ctx* c)
{
    Response* res = c.stream(&no_body_stream_writer, null)!;

    res.set_status(204)!;

    return res;
}

fn Response*? no_body_file_handler(Ctx* c)
{
    Response* res = c.file(LARGE_FILE, LARGE_SIZE)!;

    res.set_status(204)!;

    return res;
}

// Server task

fn void? server_task(void* arg)
{
    ApplicationServer* server =
        (ApplicationServer*)arg;

    server.serve()!;
}

// Tests

fn void test_header_validation()
{
    Response* res = http::response_new()!!;
    defer http::response_free(res);

    if (catch err = res.header("Bad Header", "ok"))
    {
        @assert(err == http::INVALID_HEADER_NAME,
            "space in header name should be rejected"
        );
    }
    else
    {
        @assert(false,
            "invalid header name was accepted"
        );
    }

    if (catch err = res.header("Bad:Header", "ok"))
    {
        @assert(err == http::INVALID_HEADER_NAME,
            "colon in header name should be rejected"
        );
    }
    else
    {
        @assert(false,
            "header name containing colon was accepted"
        );
    }

    if (catch err = res.header("X-Test", "bad\rvalue"))
    {
        @assert(err == http::INVALID_HEADER_VALUE,
            "CR in header value should be rejected"
        );
    }
    else
    {
        @assert(false,
            "header value containing CR was accepted"
        );
    }

    if (catch err = res.header("X-Test", "bad\nvalue"))
    {
        @assert(err == http::INVALID_HEADER_VALUE,
            "LF in header value should be rejected"
        );
    }
    else
    {
        @assert(false,
            "header value containing LF was accepted"
        );
    }

    res.header("X-Test", "good value")!!;

    String value = res.headers.get("X-Test")!!;

    @assert(value == "good value",
        "valid header value mismatch"
    );
}

fn void? test_static_streaming()
{
    String raw = fetch_raw(
        "GET /static/large.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200),
        "static streaming status mismatch"
    );

    @assert(has_header(raw, "Transfer-Encoding: chunked\r\n"),
        "static streaming transfer encoding missing"
    );

    @assert(!has_header(raw, "Content-Length:"),
        "static streaming response has content length"
    );

    @assert(raw.contains("STATIC_STREAM_MARKER_0123456789"),
        "static streaming marker missing"
    );

    @assert(raw.contains("\r\n0\r\n\r\n"),
        "static streaming last chunk missing"
    );
}

fn void? test_head_stream_file()
{
    g_stream_writer_called = 0;

    String raw_stream = fetch_raw(
        "HEAD /head-stream HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw_stream);

    @assert(status_is(raw_stream, 200),
        "HEAD stream status mismatch"
    );

    @assert(has_header(raw_stream, "Content-Length: 0\r\n"),
        "HEAD stream content length mismatch"
    );

    @assert(!has_header(raw_stream, "Transfer-Encoding: chunked\r\n"),
        "HEAD stream should not be chunked"
    );

    @assert(body_part(raw_stream).len == 0,
        "HEAD stream contains a response body"
    );

    @assert(
        g_stream_writer_called == 0,
        "HEAD stream writer was called"
    );

    char[64] len_buf;

    String expected_length = string::bformat(
        len_buf[..],
        "Content-Length: %d\r\n",
        LARGE_SIZE
    );

    String raw_file = fetch_raw(
        "HEAD /head-file HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw_file);

    @assert(status_is(raw_file, 200),
        "HEAD file status mismatch");

    @assert(has_header(raw_file, expected_length),
        "HEAD file content length mismatch");

    @assert(!has_header(raw_file, "Transfer-Encoding: chunked\r\n"),
        "HEAD file should not be chunked"
    );

    @assert(
        body_part(raw_file).len == 0,
        "HEAD file contains a response body"
    );
}

fn void? test_no_body_stream_file()
{
    g_no_body_stream_writer_called = 0;

    String raw_stream = fetch_raw(
        "GET /no-body-stream HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw_stream);

    @assert(
        status_is(raw_stream, 204),
        "no-body stream status mismatch"
    );

    @assert(
        has_header(
            raw_stream,
            "Content-Length: 0\r\n"
        ),
        "no-body stream content length mismatch"
    );

    @assert(
        !has_header(
            raw_stream,
            "Transfer-Encoding: chunked\r\n"
        ),
        "no-body stream should not be chunked"
    );

    @assert(
        body_part(raw_stream).len == 0,
        "no-body stream contains a response body"
    );

    @assert(
        g_no_body_stream_writer_called == 0,
        "no-body stream writer was called"
    );

    String raw_file = fetch_raw(
        "GET /no-body-file HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw_file);

    @assert(
        status_is(raw_file, 204),
        "no-body file status mismatch"
    );

    @assert(
        has_header(
            raw_file,
            "Content-Length: 0\r\n"
        ),
        "no-body file content length mismatch"
    );

    @assert(
        !has_header(
            raw_file,
            "Transfer-Encoding: chunked\r\n"
        ),
        "no-body file should not be chunked"
    );

    @assert(
        body_part(raw_file).len == 0,
        "no-body file contains a response body"
    );

    @assert(
        !raw_file.contains(
            "STATIC_STREAM_MARKER_0123456789"
        ),
        "no-body file contains file data"
    );
}

fn void? test_static_security()
{
    String traversal = fetch_raw(
        "GET /static/../secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(traversal);

    @assert(
        status_is(traversal, 403),
        "path traversal should be forbidden"
    );

    String backslash = fetch_raw(
        "GET /static/foo\\bar HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(backslash);

    @assert(
        status_is(backslash, 403) ||
        status_is(backslash, 400),
        "backslash path should be rejected"
    );

    String directory = fetch_raw(
        "GET /static/subdir HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(directory);

    @assert(
        status_is(directory, 404),
        "static directory should not be served"
    );

    if (catch path::symlink("small.txt", LINK_FILE))
    {
        return;
    }

    String link = fetch_raw(
        "GET /static/link.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(link);

    @assert(
        status_is(link, 403),
        "static symbolic link should be forbidden"
    );
}

fn void? test_main(void* arg)
{
    setup_files()!;
    defer cleanup_files();

    Application app;
    app.init();
    defer app.deinit();

    app.get(
        "/stream",
        &stream_handler
    )!;

    app.get(
        "/head-stream",
        &head_stream_handler
    )!;

    app.head(
        "/head-stream",
        &head_stream_handler
    )!;

    app.get(
        "/head-file",
        &head_file_handler
    )!;

    app.head(
        "/head-file",
        &head_file_handler
    )!;

    app.get(
        "/no-body-stream",
        &no_body_stream_handler
    )!;

    app.get(
        "/no-body-file",
        &no_body_file_handler
    )!;

    app.static_files("/static", ROOT)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_header_validation();
    test_static_streaming()!;
    test_head_stream_file()!;
    test_no_body_stream_file()!;
    test_static_security()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    io::printfn("test_stream_all: OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof