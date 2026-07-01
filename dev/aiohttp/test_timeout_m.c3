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

const ulong FAST_DELAY_US = 20_000;
const ulong SLOW_DELAY_US = 300_000;
const ulong BOUNDARY_DELAY_US = 100_000;

const ulong RESPONSE_READ_TIMEOUT_US = 2_000_000;
const ulong DEFAULT_TEST_TIMEOUT_US = 100_000;

const ulong SERVER_READY_RETRY_DELAY_US = 10_000;
const sz SERVER_READY_RETRY_COUNT = 200;

// Response helpers

fn bool contains(String text, String value) @inline
{
    return text.contains(value);
}

fn sz count_occurrences(String text, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= text.len) {
        sz index = text[pos..].index_of(needle) ?? -1;
        if (index < 0) break;

        count++;
        pos += index + needle.len;
    }

    return count;
}

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

fn String? fetch_raw(String request, ulong read_timeout_us = RESPONSE_READ_TIMEOUT_US)
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


// Handlers

fn Response*? fast_handler(Ctx* c)
{
    aio::sleep(FAST_DELAY_US)!;
    return c.text("fast-ok")!;
}

fn Response*? slow_handler(Ctx* c)
{
    aio::sleep(SLOW_DELAY_US)!;
    return c.text("slow-finished")!;
}

fn Response*? immediate_handler(Ctx* c)
{
    return c.text("immediate-ok")!;
}

fn Response*? exact_handler(Ctx* c)
{
    aio::sleep(BOUNDARY_DELAY_US)!;
    return c.text("exact-ok")!;
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
            aio::sleep(100_000)!;
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


// Basic timeout tests

fn void? test_timeout_fast_request()
{
    http::set_timeout_us(DEFAULT_TEST_TIMEOUT_US);

    String raw = fetch_raw(
        "GET /fast HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200), "fast request status mismatch");
    @assert(contains(body_part(raw), "fast-ok"), "fast request body mismatch");
}

fn void? test_timeout_immediate_request()
{
    http::set_timeout_us(DEFAULT_TEST_TIMEOUT_US);

    String raw = fetch_raw(
        "GET /immediate HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200), "immediate request status mismatch");
    @assert(contains(body_part(raw), "immediate-ok"), "immediate request body mismatch");
}

fn void? test_timeout_slow_request()
{
    http::set_timeout_us(DEFAULT_TEST_TIMEOUT_US);

    String raw = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 504), "slow request timeout status mismatch");
    @assert(contains(body_part(raw), "504 Gateway Timeout"), "slow request timeout body mismatch");
    @assert(!contains(body_part(raw), "slow-finished"), "timed-out handler body must not be sent");
}


// Keep-alive and pipelining tests

fn void? test_timeout_keepalive_after_fast()
{
    http::set_timeout_us(DEFAULT_TEST_TIMEOUT_US);

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
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2, "fast keep-alive response count mismatch");
    @assert(contains(raw, "fast-ok"), "fast keep-alive first body missing");
    @assert(contains(raw, "immediate-ok"), "fast keep-alive second body missing");

    sz fast_index = raw.index_of("fast-ok") ?? -1;
    sz immediate_index = raw.index_of("immediate-ok") ?? -1;

    @assert(fast_index >= 0, "fast keep-alive first body position missing");
    @assert(immediate_index >= 0, "fast keep-alive second body position missing");
    @assert(fast_index < immediate_index, "fast keep-alive response order mismatch");
}

fn void? test_timeout_connection_after_timeout()
{
    http::set_timeout_us(DEFAULT_TEST_TIMEOUT_US);

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
    defer http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 504 ") == 1, "timeout keep-alive 504 count mismatch");
    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1, "timeout keep-alive 200 count mismatch");
    @assert(contains(raw, "504 Gateway Timeout"), "timeout keep-alive timeout body missing");
    @assert(contains(raw, "immediate-ok"), "timeout keep-alive next response missing");

    sz timeout_index = raw.index_of("504 Gateway Timeout") ?? -1;
    sz immediate_index = raw.index_of("immediate-ok") ?? -1;

    @assert(timeout_index >= 0, "timeout keep-alive timeout position missing");
    @assert(immediate_index >= 0, "timeout keep-alive immediate position missing");
    @assert(timeout_index < immediate_index, "timeout keep-alive response order mismatch");
}


// Configuration tests

fn void? test_timeout_setting_api()
{
    ulong original_timeout_us = http::get_timeout_us();
    defer http::set_timeout_us(original_timeout_us);

    http::set_timeout_ms(250);

    @assert(http::get_timeout_ms() == 250, "set_timeout_ms value mismatch");
    @assert(http::get_timeout_us() == 250_000, "set_timeout_ms microsecond conversion mismatch");

    http::set_timeout_us(150_000);

    @assert(http::get_timeout_us() == 150_000, "set_timeout_us value mismatch");
    @assert(http::get_timeout_ms() == 150, "set_timeout_us millisecond conversion mismatch");

    http::reset_timeout();

    @assert(
        http::get_timeout_us() == http::DEFAULT_REQUEST_TIMEOUT_US,
        "reset_timeout value mismatch"
    );
}

fn void? test_timeout_boundary_margin()
{
    ulong original_timeout_us = http::get_timeout_us();
    defer http::set_timeout_us(original_timeout_us);

    http::set_timeout_ms(200);

    String raw = fetch_raw(
        "GET /exact HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200), "timeout boundary margin status mismatch");
    @assert(contains(body_part(raw), "exact-ok"), "timeout boundary margin body mismatch");
}

fn void? test_timeout_override_and_restore()
{
    ulong original_timeout_us = http::get_timeout_us();
    defer http::set_timeout_us(original_timeout_us);

    http::set_timeout_ms(50);

    String timed_out = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(timed_out);

    @assert(status_is(timed_out, 504), "short timeout override status mismatch");
    @assert(!contains(body_part(timed_out), "slow-finished"), "short timeout override leaked handler result");

    http::set_timeout_ms(500);

    String completed = fetch_raw(
        "GET /slow HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(completed);

    @assert(status_is(completed, 200), "long timeout override status mismatch");
    @assert(contains(body_part(completed), "slow-finished"), "long timeout override body mismatch");
}


// Main

fn void? test_main(void* arg)
{
    test_timeout_setting_api()!;

    ulong original_timeout_us = http::get_timeout_us();
    defer http::set_timeout_us(original_timeout_us);

    http::set_timeout_us(DEFAULT_TEST_TIMEOUT_US);

    Application app;
    app.init();
    defer app.deinit();

    app.use(&http::middleware_timeout);

    app.get("/fast", &fast_handler)!;
    app.get("/slow", &slow_handler)!;
    app.get("/immediate", &immediate_handler)!;
    app.get("/exact", &exact_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_timeout_fast_request()!;
    test_timeout_immediate_request()!;
    test_timeout_slow_request()!;

    test_timeout_keepalive_after_fast()!;
    test_timeout_connection_after_timeout()!;

    test_timeout_boundary_margin()!;
    test_timeout_override_and_restore()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    io::printfn("test_timeout_m: OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof