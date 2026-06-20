// test_chunked_all.c3

// Chunked request and response integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::chunked_all;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::aio::path;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18101;

const String ROOT = "zz_chunked_all";
const String FILE_PATH = "zz_chunked_all/file.txt";
const String FILE_BODY = "file chunk body";
const sz FILE_SIZE = 15;

const sz MAX_RESPONSE_BYTES = 1024 * 1024;
const ulong RESPONSE_TIMEOUT_US = 2_000_000;

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


fn void cleanup_files()
{
    if (catch path::remove(FILE_PATH)) {}

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
            return aio::http::HTTP_WRITE_ERROR~;
        }

        total += n;
    }
}

fn void? setup_files()
{
    cleanup_files();

    path::makedirs(ROOT, 0o777, true)!;

    write_all_file(
        FILE_PATH,
        (char[])FILE_BODY
    )!;
}

fn String? fetch_raw(
    String request,
    ulong read_timeout_us = RESPONSE_TIMEOUT_US
)
{
    aio::Stream* client =
        aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString out;
    out.init(aio::http::localmem, 4096);
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
            return aio::http::REQUEST_TOO_LARGE~;
        }
    }

    client.close();

    return out.copy_str(aio::http::localmem);
}

fn String? fetch_raw_split(
    String[] parts,
    ulong delay_ms = 20,
    ulong read_timeout_us = RESPONSE_TIMEOUT_US
)
{
    aio::Stream* client =
        aio::stream_connect(HOST, PORT)!;
    defer client.free();

    for (sz i = 0; i < parts.len; i++)
    {
        client.write_all((char[])parts[i])!;

        if (delay_ms > 0)
        {
            aio::sleep((uint)delay_ms)!;
        }
    }

    DString out;
    out.init(aio::http::localmem, 4096);
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
            return aio::http::REQUEST_TOO_LARGE~;
        }
    }

    client.close();

    return out.copy_str(aio::http::localmem);
}

// Handlers

fn Response*? hello_handler(Ctx* c)
{
    return c.text("hello")!;
}

fn Response*? chunked_echo_handler(Ctx* c)
{
    char[] body = c.body();

    if ((String)body != "Wikipedia")
    {
        c.status(500)!;
        return c.text("bad chunked body")!;
    }

    return c.text("chunked-ok")!;
}

fn Response*? chunked_upper_handler(Ctx* c)
{
    char[] body = c.body();

    if ((String)body != "0123456789")
    {
        c.status(500)!;
        return c.text("bad uppercase chunked body")!;
    }

    return c.text("chunked-upper-ok")!;
}

fn void? stream_writer(aio::Stream* stream, void* arg)
{
    aio::http::write_chunk(
        stream,
        (char[])"stream-"
    )!;

    aio::http::write_chunk(
        stream,
        (char[])"chunk-"
    )!;

    aio::http::write_chunk(
        stream,
        (char[])"body"
    )!;
}

fn Response*? stream_handler(Ctx* c)
{
    Response* res =
        aio::http::response_stream(
            &stream_writer,
            null
        )!;

    res.content_type(
        "text/plain; charset=utf-8"
    )!;

    return res;
}

fn Response*? file_handler(Ctx* c)
{
    Response* res =
        aio::http::response_file(
            FILE_PATH,
            FILE_SIZE
        )!;

    res.content_type(
        "text/plain; charset=utf-8"
    )!;

    return res;
}

fn Response*? no_content_handler(Ctx* c)
{
    Response* res =
        aio::http::response_text(
            "must-not-appear"
        )!;

    res.set_status(204)!;

    return res;
}

fn Response*? not_modified_handler(Ctx* c)
{
    Response* res =
        aio::http::response_text(
            "must-not-appear"
        )!;

    res.set_status(304)!;

    return res;
}

// Server helpers

fn void? server_task(void* arg)
{
    ApplicationServer* server =
        (ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
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

// Request tests

fn void? test_chunked_request_split_reads()
{
    String[4] parts = {
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4\r\n",

        "Wiki\r\n",

        "5\r\npedia\r\n",

        "0\r\n\r\n",
    };

    String raw = fetch_raw_split(parts[..])!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "split chunked request status mismatch"
    );

    @assert(
        body_part(raw).contains("chunked-ok"),
        "split chunked request body mismatch"
    );
}

fn void? test_chunked_request_extension()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4;ext=value\r\n"
        "Wiki\r\n"
        "5;foo=bar\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "chunk extension status mismatch"
    );

    @assert(
        body_part(raw).contains("chunked-ok"),
        "chunk extension body mismatch"
    );
}

fn void? test_chunked_request_uppercase_hex()
{
    String raw = fetch_raw(
        "POST /chunked-upper HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "A\r\n"
        "0123456789\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "uppercase chunk size status mismatch"
    );

    @assert(
        body_part(raw).contains(
            "chunked-upper-ok"
        ),
        "uppercase chunk size body mismatch"
    );
}

fn void? test_chunked_request_trailer()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Trailer: X-Test-Trailer\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "X-Test-Trailer: yes\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "chunk trailer status mismatch"
    );

    @assert(
        body_part(raw).contains("chunked-ok"),
        "chunk trailer body mismatch"
    );
}

fn void? test_chunked_request_malformed_size()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "Z\r\n"
        "bad\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 400),
        "malformed chunk size status mismatch"
    );
}

fn void? test_chunked_request_incomplete_timeout()
{
    ulong old_timeout =
        aio::http::http_get_read_timeout_us();

    aio::http::http_set_read_timeout_us(200_000);

    defer aio::http::http_set_read_timeout_us(
        old_timeout
    );

    aio::Stream* client =
        aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4\r\n"
        "Wi"
    )!;

    DString out;
    out.init(aio::http::localmem, 4096);
    defer out.free();

    while (true)
    {
        char[4096] buf;

        sz? read_result =
            client.read_timeout(
                buf[..],
                1_500_000
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
            return aio::http::REQUEST_TOO_LARGE~;
        }
    }

    String raw = out.str_view();

    @assert(
        status_is(raw, 408),
        "incomplete chunked request timeout status mismatch"
    );

    client.close();
}

fn void? test_chunked_post_then_get_pipeline()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        count_occurrences(
            raw,
            "HTTP/1.1 200 OK"
        ) == 2,
        "chunked pipeline response count mismatch"
    );

    sz chunked_pos =
        raw.index_of("chunked-ok") ?? -1;

    sz hello_pos =
        raw.index_of("hello") ?? -1;

    @assert(
        chunked_pos >= 0,
        "chunked pipeline first body missing"
    );

    @assert(
        hello_pos >= 0,
        "chunked pipeline second body missing"
    );

    @assert(
        chunked_pos < hello_pos,
        "chunked pipeline response order mismatch"
    );
}

// Response tests

fn void? test_chunked_stream_response()
{
    String raw = fetch_raw(
        "GET /stream HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "chunked stream response status mismatch"
    );

    @assert(raw.contains("Transfer-Encoding: chunked\r\n"),
        "chunked stream transfer encoding missing"
    );

    @assert(
        !raw.contains("Content-Length: "),
        "chunked stream contains content length"
    );

    @assert(
        raw.contains("\r\n7\r\nstream-\r\n"),
        "first stream chunk mismatch"
    );

    @assert(
        raw.contains("\r\n6\r\nchunk-\r\n"),
        "second stream chunk mismatch"
    );

    @assert(
        raw.contains("\r\n4\r\nbody\r\n"),
        "third stream chunk mismatch"
    );

    @assert(
        raw.contains("\r\n0\r\n\r\n"),
        "stream final chunk missing"
    );
}

fn void? test_file_response()
{
    String raw = fetch_raw(
        "GET /file HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "file response status mismatch"
    );

    @assert(
        raw.contains("Transfer-Encoding: chunked\r\n"),
        "file response transfer encoding missing"
    );

    @assert(
        !raw.contains("Content-Length: "),
        "chunked file response contains content length"
    );

    @assert(
        raw.contains("\r\nf\r\nfile chunk body\r\n"),
        "file response chunk mismatch"
    );

    @assert(
        raw.contains("\r\n0\r\n\r\n"),
        "file response final chunk missing"
    );
}

fn void? test_head_stream_response_has_no_chunk_body()
{
    String raw = fetch_raw(
        "HEAD /stream HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "HEAD stream response status mismatch"
    );

    @assert(
        raw.contains("Content-Length: 0\r\n"),
        "HEAD stream content length mismatch"
    );

    @assert(
        !raw.contains("Transfer-Encoding: chunked\r\n"),
        "HEAD stream should not be chunked"
    );

    @assert(
        body_part(raw).len == 0,
        "HEAD stream contains a body"
    );

    @assert(
        !raw.contains("\r\n0\r\n\r\n"),
        "HEAD stream contains a final chunk"
    );
}

fn void? test_head_file_response_has_no_body()
{
    String raw = fetch_raw(
        "HEAD /file HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "HEAD file response status mismatch"
    );

    @assert(
        raw.contains("Content-Length: 15\r\n"),
        "HEAD file content length mismatch"
    );

    @assert(
        !raw.contains("Transfer-Encoding: chunked\r\n"),
        "HEAD file should not be chunked"
    );

    @assert(
        body_part(raw).len == 0,
        "HEAD file contains a body"
    );

    @assert(
        !raw.contains("\r\n0\r\n\r\n"),
        "HEAD file contains a final chunk"
    );
}

fn void? test_204_has_no_chunk_body()
{
    String raw = fetch_raw(
        "GET /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 204),
        "204 response status mismatch"
    );

    @assert(
        raw.contains("Content-Length: 0\r\n"),
        "204 content length mismatch"
    );

    @assert(
        !raw.contains(
            "Transfer-Encoding: chunked"
        ),
        "204 response should not be chunked"
    );

    @assert(
        body_part(raw).len == 0,
        "204 response contains a body"
    );

    @assert(
        !raw.contains("\r\n0\r\n\r\n"),
        "204 response contains a final chunk"
    );
}

fn void? test_304_has_no_chunk_body()
{
    String raw = fetch_raw(
        "GET /not-modified HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(
        status_is(raw, 304),
        "304 response status mismatch"
    );

    @assert(
        raw.contains("Content-Length: 0\r\n"),
        "304 content length mismatch"
    );

    @assert(
        !raw.contains(
            "Transfer-Encoding: chunked"
        ),
        "304 response should not be chunked"
    );

    @assert(
        body_part(raw).len == 0,
        "304 response contains a body"
    );

    @assert(
        !raw.contains("\r\n0\r\n\r\n"),
        "304 response contains a final chunk"
    );
}

fn void? test_main(void* arg)
{
    setup_files()!;
    defer cleanup_files();

    Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!;
    app.post("/chunked", &chunked_echo_handler)!;
    app.post(
        "/chunked-upper",
        &chunked_upper_handler
    )!;

    app.get("/stream", &stream_handler)!;
    app.head("/stream", &stream_handler)!;

    app.get("/file", &file_handler)!;
    app.head("/file", &file_handler)!;

    app.get(
        "/no-content",
        &no_content_handler
    )!;

    app.get(
        "/not-modified",
        &not_modified_handler
    )!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_chunked_request_split_reads()!;
    test_chunked_request_extension()!;
    test_chunked_request_uppercase_hex()!;
    test_chunked_request_trailer()!;
    test_chunked_request_malformed_size()!;
    test_chunked_request_incomplete_timeout()!;
    test_chunked_post_then_get_pipeline()!;

    test_chunked_stream_response()!;
    test_file_response()!;
    test_head_stream_response_has_no_chunk_body()!;
    test_head_file_response_has_no_body()!;
    test_204_has_no_chunk_body()!;
    test_304_has_no_chunk_body()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    io::printfn("test_chunked_all: OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof