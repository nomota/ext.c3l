// test_cors_all.c3

// CORS middleware integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::cors_all;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18104;

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

fn bool has_header(String raw, String header)
{
    return contains(raw, header);
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

fn Response*? hello_handler(Ctx* c)
{
    return c.text("hello")!;
}

fn Response*? exposed_handler(Ctx* c)
{
    c.header("X-Request-Id", "abc123")!;
    return c.text("exposed")!;
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
    aio::Stream*? s = aio::stream_connect(HOST, PORT);

    if (catch err = s)
    {
        return;
    }

    s.close();
    s.free();
}

// Tests

fn void? test_cors_normal_request_default()
{
    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(has_header(raw, "Access-Control-Allow-Origin: *\r\n"));
    @assert(!contains(raw, "Access-Control-Allow-Credentials: true\r\n"));
    @assert(contains(body_part(raw), "hello"));
}

fn void? test_cors_preflight_default()
{
    String raw = fetch_raw(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: POST\r\n"
        "Access-Control-Request-Headers: X-Test, Content-Type\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 204));
    @assert(has_header(raw, "Access-Control-Allow-Origin: *\r\n"));
    @assert(has_header(raw, "Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS\r\n"));
    @assert(has_header(raw, "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"));
    @assert(has_header(raw, "Access-Control-Max-Age: 86400\r\n"));
    @assert(!contains(body_part(raw), "hello"));
}

fn void? test_cors_no_origin_default_omits_headers()
{
    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!contains(raw, "Access-Control-Allow-Origin: "));
    @assert(contains(body_part(raw), "hello"));
}

fn void? test_cors_always_send()
{
    aio::http::cors_always_send(true);
    defer aio::http::cors_always_send(false);

    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(has_header(raw, "Access-Control-Allow-Origin: *\r\n"));
}

fn void? test_cors_credentials_echo_origin()
{
    aio::http::cors_allow_origin("*");
    aio::http::cors_allow_credentials(true);
    defer aio::http::cors_allow_credentials(false);

    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://cred.example\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(has_header(raw, "Access-Control-Allow-Origin: https://cred.example\r\n"));
    @assert(has_header(raw, "Access-Control-Allow-Credentials: true\r\n"));
    @assert(has_header(raw, "Vary: Origin\r\n"));
}

fn void? test_cors_allow_origin_list_allowed()
{
    aio::http::cors_allow_origin("https://a.example, https://b.example");
    defer aio::http::cors_allow_origin("*");

    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://b.example\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(has_header(raw, "Access-Control-Allow-Origin: https://b.example\r\n"));
    @assert(has_header(raw, "Vary: Origin\r\n"));
}

fn void? test_cors_allow_origin_list_rejected()
{
    aio::http::cors_allow_origin("https://a.example, https://b.example");
    defer aio::http::cors_allow_origin("*");

    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://evil.example\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!contains(raw, "Access-Control-Allow-Origin: "));
    @assert(contains(body_part(raw), "hello"));
}

fn void? test_cors_echo_request_headers()
{
    aio::http::cors_echo_request_headers();
    defer aio::http::cors_allow_headers("Content-Type, Authorization");

    String raw = fetch_raw(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: PATCH\r\n"
        "Access-Control-Request-Headers: X-Token, X-Trace\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 204));
    @assert(has_header(raw, "Access-Control-Allow-Headers: X-Token, X-Trace\r\n"));
}

fn void? test_cors_echo_request_method()
{
    aio::http::cors_echo_request_method();
    defer aio::http::cors_allow_methods("GET, POST, PUT, PATCH, DELETE, OPTIONS");

    String raw = fetch_raw(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: PATCH\r\n"
        "Access-Control-Request-Headers: X-Token\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 204));
    @assert(has_header(raw, "Access-Control-Allow-Methods: PATCH\r\n"));
}

fn void? test_cors_expose_headers()
{
    aio::http::cors_expose_headers("X-Request-Id");
    defer aio::http::cors_expose_headers("");

    String raw = fetch_raw(
        "GET /exposed HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(has_header(raw, "X-Request-Id: abc123\r\n"));
    @assert(has_header(raw, "Access-Control-Expose-Headers: X-Request-Id\r\n"));
}

fn void? test_cors_preflight_status()
{
    aio::http::cors_preflight_status(200);
    defer aio::http::cors_preflight_status(204);

    String raw = fetch_raw(
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: POST\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(has_header(raw, "Access-Control-Allow-Origin: *\r\n"));
}

fn void? test_cors_pipeline()
{
    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "OPTIONS /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Origin: https://example.com\r\n"
        "Access-Control-Request-Method: POST\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 1);
    @assert(count_occurrences(raw, "HTTP/1.1 204 No Content") == 1);
    @assert(count_occurrences(raw, "Access-Control-Allow-Origin: *") == 2);
    @assert(contains(raw, "hello"));
}

fn void? test_main(void* arg)
{
    aio::http::cors_init_default();
    aio::http::cors_allow_origin("*");
    aio::http::cors_allow_methods("GET, POST, PUT, PATCH, DELETE, OPTIONS");
    aio::http::cors_allow_headers("Content-Type, Authorization");
    aio::http::cors_expose_headers("");
    aio::http::cors_max_age("86400");
    aio::http::cors_allow_credentials(false);
    aio::http::cors_always_send(false);
    aio::http::cors_vary(true);
    aio::http::cors_preflight_status(204);

    Application app;
    app.init();
    defer app.deinit();

    app.use(&aio::http::cors);

    app.get("/hello", &hello_handler)!;
    app.post("/hello", &hello_handler)!;
    app.patch("/hello", &hello_handler)!;
    app.get("/exposed", &exposed_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_cors_normal_request_default()!;
    test_cors_preflight_default()!;
    test_cors_no_origin_default_omits_headers()!;
    test_cors_always_send()!;
    test_cors_credentials_echo_origin()!;
    test_cors_allow_origin_list_allowed()!;
    test_cors_allow_origin_list_rejected()!;
    test_cors_echo_request_headers()!;
    test_cors_echo_request_method()!;
    test_cors_expose_headers()!;
    test_cors_preflight_status()!;
    test_cors_pipeline()!;

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