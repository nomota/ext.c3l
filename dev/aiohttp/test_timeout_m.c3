// test_timeout_m.c3

// Request timeout middleware integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::timeout_m;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18106;

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
        pos += idx + needle.len;
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
    out.init(aio::http::localmem, 4096);
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

    return out.copy_str(aio::http::localmem);
}


// Handlers

fn Response*? fast_handler(Ctx* c)
{
    aio::sleep(20)!;
    return c.text("fast-ok")!;
}

fn Response*? slow_handler(Ctx* c)
{
    aio::sleep(300)!;
    return c.text("slow-finished")!;
}

fn Response*? immediate_handler(Ctx* c)
{
    return c.text("immediate-ok")!;
}

fn Response*? exact_handler(Ctx* c)
{
    aio::sleep(100)!;
    return c.text("exact-ok")!;
}


// Server task

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
    aio::Stream*? stream = aio::stream_connect(HOST, PORT);

    if (catch err = stream)
    {
        return;
    }

    stream.close();
    stream.free();
}


// Tests

fn void? test_timeout_fast_request()
{
    String raw = fetch_raw(
        "GET /fast HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "fast-ok"));
}

fn void? test_timeout_immediate_request()
{
    String raw = fetch_raw(
        "GET /immediate HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "immediate-ok"));
}

fn void? test_timeout_slow_request()
{
    String raw = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);
//warn(raw);
    @assert(status_is(raw, 504));
    @assert(contains(body_part(raw), "504 Gateway Timeout"));
    @assert(!contains(body_part(raw), "slow-finished"));
}

fn void? test_timeout_keepalive_after_fast()
{
    String raw = fetch_raw(
        "GET /fast HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /immediate HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "fast-ok"));
    @assert(contains(raw, "immediate-ok"));
    @assert(raw.index_of("fast-ok")! < raw.index_of("immediate-ok")!);
}

fn void? test_timeout_connection_after_timeout()
{
    String raw = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /immediate HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 504 ") == 1);
    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1);
    @assert(contains(raw, "504 Gateway Timeout"));
    @assert(contains(raw, "immediate-ok"));
}

fn void? test_timeout_setting_api()
{
    aio::http::set_timeout_ms(250);
    @assert(aio::http::get_timeout_ms() == 250);
    @assert(aio::http::get_timeout_us() == 250_000);

    aio::http::set_timeout_us(150_000);
    @assert(aio::http::get_timeout_us() == 150_000);
    @assert(aio::http::get_timeout_ms() == 150);

    aio::http::reset_timeout();
    @assert(aio::http::get_timeout_us() == aio::http::DEFAULT_REQUEST_TIMEOUT_US);
}

fn void? test_timeout_exact_boundary()
{
    aio::http::set_timeout_ms(200);

    String raw = fetch_raw(
        "GET /exact HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "exact-ok"));
}

fn void? test_timeout_restored_after_override()
{
    aio::http::set_timeout_ms(50);

    String slow = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(slow);

    @assert(status_is(slow, 504));

    aio::http::set_timeout_ms(500);

    String fast = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(fast);

    @assert(status_is(fast, 200));
    @assert(contains(body_part(fast), "slow-finished"));
}


// Main

fn void? test_main(void* arg)
{
    test_timeout_setting_api()!;

    aio::http::set_timeout_ms(100);

    Application app;
    app.init();
    defer app.deinit();

    app.use(&aio::http::middleware_timeout);

    app.get("/fast", &fast_handler)!;
    app.get("/slow", &slow_handler)!;
    app.get("/immediate", &immediate_handler)!;
    app.get("/exact", &exact_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_timeout_fast_request()!;
    test_timeout_immediate_request()!;
    test_timeout_slow_request()!;
    test_timeout_keepalive_after_fast()!;
    test_timeout_connection_after_timeout()!;
    test_timeout_exact_boundary()!;
    test_timeout_restored_after_override()!;

    aio::http::reset_timeout();

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