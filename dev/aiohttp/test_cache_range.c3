// test_cache_range.c3

// Static ETag, conditional GET, and byte range integration tests.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::cache_range;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::aio::path;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18108;

const ulong READ_TIMEOUT_US = 2_000_000;
const ulong SERVER_START_DELAY_US = 200;

const String ROOT = "zz_static_cache_range";
const String FILE_PATH = "zz_static_cache_range/sample.txt";
const String FILE_BODY = "0123456789abcdefghijklmnopqrstuvwxyz";
const sz FILE_SIZE = 36;


// String helpers

fn String body_part(String raw)
{
    sz index = raw.index_of("\r\n\r\n") ?? -1;
    if (index < 0) return "";

    return raw[index + 4..];
}

fn bool status_is(String raw, ushort status)
{
    char[64] buffer;
    String prefix = string::bformat(buffer[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
}

fn String header_value(String raw, String name)
{
    char[256] prefix_buffer;
    String prefix = string::bformat(prefix_buffer[..], "%s: ", name);

    sz start = raw.index_of(prefix) ?? -1;
    if (start < 0) return "";

    start += prefix.len;

    sz end = raw[start..].index_of("\r\n") ?? -1;
    if (end < 0) return "";

    return raw[start:end];
}


// File fixture

fn void? write_fixture_file()
{
    path::mkdirs(ROOT)!;

    aio::File* file = aio::file_open(FILE_PATH, "wb")!;
    defer file.free();

    char[] data = (char[])FILE_BODY;
    sz written = 0;

    while (written < data.len) {
        sz n = file.write(data[written..])!;
        if (n <= 0) return aio::IO_ERROR~;

        written += n;
    }
}

fn void cleanup_fixture()
{
    if (path::exists(FILE_PATH)) {
        path::remove(FILE_PATH);
    }

    if (path::exists(ROOT)) {
        path::remove(ROOT);
    }
}


// HTTP client

fn String? fetch_raw(String request, ulong read_timeout_us = READ_TIMEOUT_US)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString output;
    output.init(http::localmem, 4096);
    defer catch output.free();

    char[4096] buffer;

    while (true) {
        sz? n = client.read_timeout(buffer[..], read_timeout_us);

        if (catch err = n) {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            return err~;
        }

        if (n == 0) break;

        output.append(buffer[0:n]);
    }

    client.close();

    return output.copy_str(http::localmem);
}


// Server task

fn void? server_task(void* arg)
{
    ApplicationServer* server = (ApplicationServer*)arg;

    if (catch err = server.serve()) {
        return;
    }
}

fn void wake_server()
{
    aio::Stream*? stream = aio::stream_connect(HOST, PORT);

    if (catch err = stream) {
        return;
    }

    stream.close();
    stream.free();
}


// ETag and conditional GET tests

fn void? test_etag_present()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(header_value(raw, "ETag").len > 0);
    @assert(header_value(raw, "Last-Modified").len > 0);
    @assert(header_value(raw, "Accept-Ranges") == "bytes");
    @assert(header_value(raw, "Content-Length") == "36");
    @assert(body_part(raw) == FILE_BODY);
}

fn void? test_if_none_match()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String etag = header_value(first, "ETag");

    @assert(etag.len > 0);

    String request = string::format(
        http::localmem,
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-None-Match: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        etag
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 304));
    @assert(header_value(raw, "ETag") == etag);
    @assert(header_value(raw, "Content-Length") == "0");
    @assert(!raw.contains("Content-Type:"));
    @assert(body_part(raw).len == 0);
}

fn void? test_if_none_match_wildcard()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-None-Match: *\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 304));
    @assert(body_part(raw).len == 0);
}

fn void? test_if_none_match_mismatch()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-None-Match: \"not-the-current-etag\"\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(body_part(raw) == FILE_BODY);
}

fn void? test_if_modified_since()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String last_modified = header_value(first, "Last-Modified");

    @assert(last_modified.len > 0);

    String request = string::format(
        http::localmem,
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-Modified-Since: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        last_modified
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 304));
    @assert(header_value(raw, "Last-Modified") == last_modified);
    @assert(body_part(raw).len == 0);
}

fn void? test_if_none_match_precedence()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String last_modified = header_value(first, "Last-Modified");

    String request = string::format(
        http::localmem,
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-None-Match: \"wrong-etag\"\r\n"
        "If-Modified-Since: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        last_modified
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(body_part(raw) == FILE_BODY);
}


// Range tests

fn void? test_range_start_end()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=5-9\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 5-9/36");
    @assert(header_value(raw, "Content-Length") == "5");
    @assert(header_value(raw, "Accept-Ranges") == "bytes");
    @assert(body_part(raw) == "56789");
}

fn void? test_range_open_ended()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=30-\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 30-35/36");
    @assert(header_value(raw, "Content-Length") == "6");
    @assert(body_part(raw) == "uvwxyz");
}

fn void? test_range_suffix()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=-4\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 32-35/36");
    @assert(header_value(raw, "Content-Length") == "4");
    @assert(body_part(raw) == "wxyz");
}

fn void? test_range_end_clamped()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=33-999\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 33-35/36");
    @assert(header_value(raw, "Content-Length") == "3");
    @assert(body_part(raw) == "xyz");
}

fn void? test_range_not_satisfiable()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=100-200\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 416));
    @assert(header_value(raw, "Content-Range") == "bytes */36");
    @assert(header_value(raw, "Content-Length") == "0");
    @assert(body_part(raw).len == 0);
}

fn void? test_multiple_ranges_rejected()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=0-1,4-5\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 416));
    @assert(header_value(raw, "Content-Range") == "bytes */36");
    @assert(body_part(raw).len == 0);
}


// If-Range tests

fn void? test_if_range_etag_match()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String etag = header_value(first, "ETag");

    String request = string::format(
        http::localmem,
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=10-14\r\n"
        "If-Range: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        etag
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 10-14/36");
    @assert(body_part(raw) == "abcde");
}

fn void? test_if_range_etag_mismatch()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=10-14\r\n"
        "If-Range: \"wrong-etag\"\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Range:"));
    @assert(header_value(raw, "Content-Length") == "36");
    @assert(body_part(raw) == FILE_BODY);
}

fn void? test_if_range_date_match()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String last_modified = header_value(first, "Last-Modified");

    String request = string::format(
        http::localmem,
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=0-3\r\n"
        "If-Range: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        last_modified
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 0-3/36");
    @assert(body_part(raw) == "0123");
}


// HEAD tests

fn void? test_head_conditional()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String etag = header_value(first, "ETag");

    String request = string::format(
        http::localmem,
        "HEAD /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "If-None-Match: %s\r\n"
        "Connection: close\r\n"
        "\r\n",
        etag
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 304));
    @assert(body_part(raw).len == 0);
}

fn void? test_head_range()
{
    String raw = fetch_raw(
        "HEAD /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=5-9\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 206));
    @assert(header_value(raw, "Content-Range") == "bytes 5-9/36");
    @assert(header_value(raw, "Content-Length") == "5");
    @assert(body_part(raw).len == 0);
}


// Main

fn void? test_main(void* arg)
{
    write_fixture_file()!;
    defer cleanup_fixture();

    Application app;
    app.init();
    defer app.deinit();

    app.static_files("/static", ROOT)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(SERVER_START_DELAY_US)!;

    test_etag_present()!;
    test_if_none_match()!;
    test_if_none_match_wildcard()!;
    test_if_none_match_mismatch()!;
    test_if_modified_since()!;
    test_if_none_match_precedence()!;

    test_range_start_end()!;
    test_range_open_ended()!;
    test_range_suffix()!;
    test_range_end_clamped()!;
    test_range_not_satisfiable()!;
    test_multiple_ranges_rejected()!;

    test_if_range_etag_match()!;
    test_if_range_etag_mismatch()!;
    test_if_range_date_match()!;

    test_head_conditional()!;
    test_head_range()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    warn("OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof