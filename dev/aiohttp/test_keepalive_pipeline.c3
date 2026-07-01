// test_keepalive_pipeline.c3

// Keep-alive, pipelining, Content-Length body,
// chunked body, and Connection: close tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::keepalive_pipeline;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18100;

fn bool contains(char[] a, char[] b) @inline
{
    return ((String)a).contains((String)b);
}

fn sz find_string(String s, String needle) @inline
{
    return s.index_of(needle) ?? -1;
}

fn sz count_occurrences(String s, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= s.len)
    {
        String rest = s[pos..];

        sz? idx = rest.index_of(needle);

        if (catch err = idx)
        {
            break;
        }

        count++;
        pos += (sz)idx + needle.len;
    }

    return count;
}

fn String body_part(String raw)
{
    sz idx = find_string(raw, "\r\n\r\n");
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;
    String prefix = string::bformat(buf[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
}

fn String? fetch_raw(String request, ulong read_timeout_us = 2_000_000)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString out;
    out.init(http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? n = client.read_timeout(buf[..], read_timeout_us);

        if (catch err = n)
        {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            return err~;
        }

        if (n == 0) break;

        out.append(buf[0:n]);
    }

    client.close();

    return out.copy_str(http::localmem);
}

fn String? fetch_raw_keepalive(String[] writes, ulong delay_ms = 0, ulong read_timeout_us = 2_000_000)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    for (sz i = 0; i < writes.len; i++)
    {
        client.write_all((char[])writes[i])!;

        if (delay_ms > 0)
        {
            aio::sleep((uint)delay_ms)!;
        }
    }

    DString out;
    out.init(http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? n = client.read_timeout(buf[..], read_timeout_us);

        if (catch err = n)
        {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            return err~;
        }

        if (n == 0) break;

        out.append(buf[0:n]);
    }

    client.close();

    return out.copy_str(http::localmem);
}

fn Response*? hello_handler(Ctx* c)
{
    return c.text("hello")!;
}

fn Response*? one_handler(Ctx* c)
{
    return c.text("one")!;
}

fn Response*? two_handler(Ctx* c)
{
    return c.text("two")!;
}

fn Response*? echo_handler(Ctx* c)
{
    return c.text((String)c.body())!;
}

fn Response*? chunked_handler(Ctx* c)
{
    char[] body = c.body();

    if ((String)body != "Wikipedia")
    {
        c.status(500)!;
        return c.text("bad chunked body")!;
    }

    return c.text("chunked-ok")!;
}

fn void? server_task(void* arg)
{
    ApplicationServer* server = (ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
}

fn void wake_server()
{
    aio::Stream*? s = aio::stream_connect(HOST, PORT);

    if (catch err = s)
    {
        return;
    }

    s.close();
    s.free();
}

fn void? test_keepalive_two_sequential_gets()
{
    String[2] writes = {
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n",

        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n",
    };

    String raw = fetch_raw_keepalive(writes[..], 50)!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "one"));
    @assert(contains(raw, "two"));
    @assert(raw.index_of("one")! < raw.index_of("two")!);
}

fn void? test_pipelined_two_gets_one_write()
{
    String raw = fetch_raw(
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "one"));
    @assert(contains(raw, "two"));
    @assert(raw.index_of("one")! < raw.index_of("two")!);
}

fn void? test_content_length_post_then_get_pipeline()
{
    String raw = fetch_raw(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 5\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "abcde"
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "abcde"));
    @assert(contains(raw, "hello"));
    @assert(raw.index_of("abcde")! < raw.index_of("hello")!);
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
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "chunked-ok"));
    @assert(contains(raw, "hello"));
    @assert(raw.index_of("chunked-ok")! < raw.index_of("hello")!);
}

fn void? test_connection_close_prevents_second_response()
{
    String raw = fetch_raw(
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1);
    @assert(contains(raw, "one"));
    @assert(!contains(raw, "two"));
}

fn void? test_malformed_chunked_closes_connection()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "Z\r\n"
        "bad\r\n"
        "0\r\n"
        "\r\n"
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 400));
    @assert(count_occurrences(raw, "HTTP/1.1 ") == 1);
    @assert(!contains(raw, "hello"));
}

fn void? test_http_10_closes_by_default()
{
    String raw = fetch_raw(
        "GET /one HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1);
    @assert(contains(raw, "one"));
    @assert(!contains(raw, "two"));
}

fn void? test_http_10_keepalive()
{
    String raw = fetch_raw(
        "GET /one HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "one"));
    @assert(contains(raw, "two"));
}

fn void? test_main(void* arg)
{
    Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!;
    app.get("/one", &one_handler)!;
    app.get("/two", &two_handler)!;
    app.post("/echo", &echo_handler)!;
    app.post("/chunked", &chunked_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_keepalive_two_sequential_gets()!;
    test_pipelined_two_gets_one_write()!;
    test_content_length_post_then_get_pipeline()!;
    test_chunked_post_then_get_pipeline()!;
    test_connection_close_prevents_second_response()!;
    test_malformed_chunked_closes_connection()!;
    test_http_10_closes_by_default()!;
    test_http_10_keepalive()!;

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