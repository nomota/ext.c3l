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
const ulong SERVER_READY_RETRY_DELAY_US = 10_000;
const sz SERVER_READY_RETRY_COUNT = 200;

const String ROOT = "zz_static_cache_range";
const String FILE_PATH = "zz_static_cache_range/sample.txt";
const String FILE_BODY = "0123456789abcdefghijklmnopqrstuvwxyz";
const sz FILE_SIZE = 36;


// Response helpers

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

fn String header_value(String raw, String expected_name)
{
    sz header_end = raw.index_of("\r\n\r\n") ?? -1;
    if (header_end < 0) return "";

    String header_block = raw[0:header_end];
    sz pos = 0;

    while (pos < header_block.len) {
        sz line_len = header_block[pos..].index_of("\r\n") ?? -1;

        String line;

        if (line_len < 0) {
            line = header_block[pos..];
            pos = header_block.len;
        } else {
            line = header_block[pos:line_len];
            pos += line_len + 2;
        }

        if (line.len == 0) continue;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) continue;

        String name = line[0:colon];

        if (!http::str_iequals(name, expected_name)) {
            continue;
        }

        return line[colon + 1..].trim();
    }

    return "";
}

fn bool response_is_chunked(String raw)
{
    String transfer_encoding = header_value(raw, "Transfer-Encoding");

    if (transfer_encoding.len == 0) return false;

    return http::str_iequals(transfer_encoding.trim(), "chunked");
}

fn sz? parse_hex_size(String value)
{
    String text = value.trim();

    sz extension = text.index_of(";") ?? -1;

    if (extension >= 0) {
        text = text[0:extension].trim();
    }

    if (text.len == 0) return http::BAD_REQUEST~;

    sz result = 0;

    for (sz i = 0; i < text.len; i++) {
        char c = text[i];
        char digit;

        if (c >= '0' && c <= '9') {
            digit = c - '0';
        } else if (c >= 'a' && c <= 'f') {
            digit = c - 'a' + 10;
        } else if (c >= 'A' && c <= 'F') {
            digit = c - 'A' + 10;
        } else {
            return http::BAD_REQUEST~;
        }

        result = result * 16 + (sz)digit;
    }

    return result;
}

fn String? response_body_copy(String raw)
{
    String wire_body = body_part(raw);

    if (!response_is_chunked(raw)) {
        return wire_body.copy(http::localmem);
    }

    DString decoded;
    decoded.init(http::localmem, wire_body.len);
    defer catch decoded.free();

    sz pos = 0;

    while (true) {
        if (pos >= wire_body.len) {
            return http::BODY_INCOMPLETE~;
        }

        sz line_len = wire_body[pos..].index_of("\r\n") ?? -1;

        if (line_len < 0) {
            return http::BODY_INCOMPLETE~;
        }

        String size_line = wire_body[pos:line_len];
        sz chunk_size = parse_hex_size(size_line)!;

        pos += line_len + 2;

        if (chunk_size == 0) {
            if (pos + 2 > wire_body.len) {
                return http::BODY_INCOMPLETE~;
            }

            if (wire_body[pos] != '\r' || wire_body[pos + 1] != '\n') {
                return http::BAD_REQUEST~;
            }

            return decoded.copy_str(http::localmem);
        }

        if (chunk_size > wire_body.len - pos) {
            return http::BODY_INCOMPLETE~;
        }

        if (wire_body.len - pos - chunk_size < 2) {
            return http::BODY_INCOMPLETE~;
        }

        decoded.append(wire_body[pos:chunk_size]);
        pos += chunk_size;

        if (wire_body[pos] != '\r' || wire_body[pos + 1] != '\n') {
            return http::BAD_REQUEST~;
        }

        pos += 2;
    }
}

fn void assert_response_length(String raw, sz expected)
{
    if (response_is_chunked(raw)) {
        @assert(
            header_value(raw, "Transfer-Encoding") == "chunked",
            "chunked Transfer-Encoding mismatch"
        );

        @assert(
            header_value(raw, "Content-Length").len == 0,
            "chunked response must not contain Content-Length"
        );

        return;
    }

    char[64] buffer;
    String expected_text = string::bformat(buffer[..], "%d", expected);

    @assert(
        header_value(raw, "Content-Length") == expected_text,
        "response Content-Length mismatch"
    );
}


// File fixture

fn void? write_fixture_file()
{
    if (!path::exists(ROOT)) {
        path::mkdir(ROOT)!;
    }

    aio::File* file = aio::file_open(FILE_PATH, "wb")!;
    defer file.free();

    file.write_all((char[])FILE_BODY)!;
    file.flush()!;
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
        sz? read_size = client.read_timeout(buffer[..], read_timeout_us);

        if (catch err = read_size) {
            if (err == aio::TIMEOUT || err == aio::CLOSED) break;

            return err~;
        }

        if (read_size == 0) break;

        output.append(buffer[0:read_size]);
    }

    client.close();

    return output.copy_str(http::localmem);
}


// Server helpers

fn void? server_task(void* arg)
{
    ApplicationServer* server = (ApplicationServer*)arg;

    if (server == null) return http::SERVER_CLOSED~;

    if (catch err = server.serve()) {
        return;
    }
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < SERVER_READY_RETRY_COUNT; i++) {
        aio::Stream*? stream = aio::stream_connect(HOST, PORT);

        if (catch err = stream) {
            aio::sleep(SERVER_READY_RETRY_DELAY_US)!;
            continue;
        }

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
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

    @assert(status_is(raw, 200), "ETag initial status mismatch");

    @assert(
        header_value(raw, "ETag").len > 0,
        "ETag header missing"
    );

    @assert(
        header_value(raw, "Last-Modified").len > 0,
        "Last-Modified header missing"
    );

    @assert(
        header_value(raw, "Accept-Ranges") == "bytes",
        "Accept-Ranges header mismatch"
    );

    assert_response_length(raw, FILE_SIZE);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(body == FILE_BODY, "ETag initial response body mismatch");
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

    @assert(etag.len > 0, "initial ETag missing");

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

    @assert(status_is(raw, 304), "If-None-Match status mismatch");
    @assert(header_value(raw, "ETag") == etag, "If-None-Match ETag mismatch");
    @assert(!raw.contains("Content-Type:"), "304 must not contain Content-Type");

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(body.len == 0, "If-None-Match response body must be empty");
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

    @assert(
        status_is(raw, 304),
        "If-None-Match wildcard status mismatch"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body.len == 0,
        "If-None-Match wildcard response body must be empty"
    );
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

    @assert(
        status_is(raw, 200),
        "If-None-Match mismatch status mismatch"
    );

    assert_response_length(raw, FILE_SIZE);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == FILE_BODY,
        "If-None-Match mismatch body mismatch"
    );
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

    @assert(last_modified.len > 0, "initial Last-Modified missing");

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

    @assert(
        status_is(raw, 304),
        "If-Modified-Since status mismatch"
    );

    @assert(
        header_value(raw, "Last-Modified") == last_modified,
        "If-Modified-Since Last-Modified mismatch"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body.len == 0,
        "If-Modified-Since response body must be empty"
    );
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

    @assert(last_modified.len > 0, "initial Last-Modified missing");

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

    @assert(
        status_is(raw, 200),
        "If-None-Match precedence status mismatch"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == FILE_BODY,
        "If-None-Match precedence body mismatch"
    );
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

    @assert(status_is(raw, 206), "fixed range status mismatch");

    @assert(
        header_value(raw, "Content-Range") == "bytes 5-9/36",
        "fixed range Content-Range mismatch"
    );

    @assert(
        header_value(raw, "Accept-Ranges") == "bytes",
        "fixed range Accept-Ranges mismatch"
    );

    assert_response_length(raw, 5);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(body == "56789", "fixed range body mismatch");
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

    @assert(status_is(raw, 206), "open-ended range status mismatch");

    @assert(
        header_value(raw, "Content-Range") == "bytes 30-35/36",
        "open-ended range Content-Range mismatch"
    );

    assert_response_length(raw, 6);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(body == "uvwxyz", "open-ended range body mismatch");
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

    @assert(status_is(raw, 206), "suffix range status mismatch");

    @assert(
        header_value(raw, "Content-Range") == "bytes 32-35/36",
        "suffix range Content-Range mismatch"
    );

    assert_response_length(raw, 4);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(body == "wxyz", "suffix range body mismatch");
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

    @assert(status_is(raw, 206), "clamped range status mismatch");

    @assert(
        header_value(raw, "Content-Range") == "bytes 33-35/36",
        "clamped range Content-Range mismatch"
    );

    assert_response_length(raw, 3);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(body == "xyz", "clamped range body mismatch");
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

    @assert(
        status_is(raw, 416),
        "unsatisfied range status mismatch"
    );

    @assert(
        header_value(raw, "Content-Range") == "bytes */36",
        "unsatisfied range Content-Range mismatch"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body.len == 0,
        "unsatisfied range response body must be empty"
    );
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

    @assert(
        status_is(raw, 416),
        "multiple range status mismatch"
    );

    @assert(
        header_value(raw, "Content-Range") == "bytes */36",
        "multiple range Content-Range mismatch"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body.len == 0,
        "multiple range response body must be empty"
    );
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

    @assert(etag.len > 0, "initial If-Range ETag missing");

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

    @assert(
        status_is(raw, 206),
        "matching If-Range ETag status mismatch"
    );

    @assert(
        header_value(raw, "Content-Range") == "bytes 10-14/36",
        "matching If-Range ETag Content-Range mismatch"
    );

    assert_response_length(raw, 5);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == "abcde",
        "matching If-Range ETag body mismatch"
    );
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

    @assert(
        status_is(raw, 200),
        "mismatching If-Range ETag status mismatch"
    );

    @assert(
        header_value(raw, "Content-Range").len == 0,
        "mismatching If-Range ETag must not contain Content-Range"
    );

    assert_response_length(raw, FILE_SIZE);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == FILE_BODY,
        "mismatching If-Range ETag body mismatch"
    );
}

fn void? test_if_range_weak_etag()
{
    String first = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(first);

    String etag = header_value(first, "ETag");

    @assert(etag.len > 0, "initial weak If-Range ETag missing");

    String request = string::format(
        http::localmem,
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=10-14\r\n"
        "If-Range: W/%s\r\n"
        "Connection: close\r\n"
        "\r\n",
        etag
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "weak If-Range ETag must produce full response"
    );

    @assert(
        header_value(raw, "Content-Range").len == 0,
        "weak If-Range ETag must not contain Content-Range"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == FILE_BODY,
        "weak If-Range ETag full body mismatch"
    );
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

    @assert(
        last_modified.len > 0,
        "initial If-Range Last-Modified missing"
    );

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

    @assert(
        status_is(raw, 206),
        "matching If-Range date status mismatch"
    );

    @assert(
        header_value(raw, "Content-Range") == "bytes 0-3/36",
        "matching If-Range date Content-Range mismatch"
    );

    assert_response_length(raw, 4);

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == "0123",
        "matching If-Range date body mismatch"
    );
}

fn void? test_if_range_date_mismatch()
{
    String raw = fetch_raw(
        "GET /static/sample.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Range: bytes=0-3\r\n"
        "If-Range: Thu, 01 Jan 1970 00:00:00 GMT\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "mismatching If-Range date status mismatch"
    );

    @assert(
        header_value(raw, "Content-Range").len == 0,
        "mismatching If-Range date must not contain Content-Range"
    );

    String body = response_body_copy(raw)!;
    defer http::localmem.free(body);

    @assert(
        body == FILE_BODY,
        "mismatching If-Range date body mismatch"
    );
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

    @assert(etag.len > 0, "initial HEAD ETag missing");

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

    @assert(
        status_is(raw, 304),
        "conditional HEAD status mismatch"
    );

    @assert(
        body_part(raw).len == 0,
        "conditional HEAD body must be empty"
    );
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

    @assert(status_is(raw, 206), "HEAD range status mismatch");

    @assert(
        header_value(raw, "Content-Range") == "bytes 5-9/36",
        "HEAD range Content-Range mismatch"
    );

    String content_length = header_value(raw, "Content-Length");
    String transfer_encoding = header_value(raw, "Transfer-Encoding");

    @assert(
        content_length == "5" ||
        http::str_iequals(transfer_encoding, "chunked"),
        "HEAD range length metadata mismatch"
    );

    @assert(
        body_part(raw).len == 0,
        "HEAD range body must be empty"
    );
}


// Main

fn void? test_main(void* arg)
{
    cleanup_fixture();
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

    wait_server_ready()!;

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
    test_if_range_weak_etag()!;
    test_if_range_date_match()!;
    test_if_range_date_mismatch()!;

    test_head_conditional()!;
    test_head_range()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    io::printfn("test_cache_range: OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof 