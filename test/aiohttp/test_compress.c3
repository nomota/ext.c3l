// test_compress.c3

// Response compression middleware integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::compress;

import std::io;
import std::compression::gzip;
import std::compression::deflate;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18107;

const ulong READ_TIMEOUT_US = 2_000_000;
const ulong SERVER_START_DELAY_US = 200;
const sz DEFAULT_MIN_SIZE = 64;

const String LARGE_TEXT =
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789";

const String JSON_TEXT =
    "{\"message\":\"abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789\"}";

const String BINARY_TEXT =
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789"
    "abcdefghijklmnopqrstuvwxyz0123456789";

const String INCOMPRESSIBLE_TEXT =
    "7fA2kP9xQ4mL8vN1cR6tY3wB5uD0sH";


fn bool contains(char[] text, char[] needle) @inline
{
    return ((String)text).contains((String)needle);
}

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
    String prefix = string::bformat(buf[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
}

fn String? fetch_raw(
    String request,
    ulong read_timeout_us = READ_TIMEOUT_US
)
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


// Handlers

fn Response*? large_text_handler(Ctx* c)
{
    return c.text(LARGE_TEXT)!;
}

fn Response*? small_text_handler(Ctx* c)
{
    return c.text("small")!;
}

fn Response*? json_handler(Ctx* c)
{
    return c.json(JSON_TEXT)!;
}

fn Response*? binary_handler(Ctx* c)
{
    c.content_type("application/octet-stream")!;

    return c.body_response((char[])BINARY_TEXT)!;
}

fn Response*? encoded_handler(Ctx* c)
{
    Response* response = c.text(LARGE_TEXT)!;
    response.header("Content-Encoding", "br")!;

    return response;
}

fn Response*? no_content_handler(Ctx* c)
{
    Response* response = c.text(LARGE_TEXT)!;
    response.set_status(204)!;

    return response;
}

fn Response*? vary_handler(Ctx* c)
{
    Response* response = c.text(LARGE_TEXT)!;
    response.header("Vary", "Origin")!;

    return response;
}

fn Response*? vary_existing_handler(Ctx* c)
{
    Response* response = c.text(LARGE_TEXT)!;
    response.header(
        "Vary",
        "Origin, Accept-Encoding"
    )!;

    return response;
}

fn Response*? incompressible_handler(Ctx* c)
{
    return c.text(INCOMPRESSIBLE_TEXT)!;
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

fn void? test_compress_gzip()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(raw.contains("Content-Encoding: gzip\r\n"));
    @assert(raw.contains("Vary: Accept-Encoding"));

    String compressed = body_part(raw);

    char[] decoded = gzip::uncompress_bytes(
        http::localmem,
        (char[])compressed
    )!;
    defer http::localmem.free(decoded);

    @assert((String)decoded == LARGE_TEXT);
}

fn void? test_compress_deflate()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: deflate\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(raw.contains("Content-Encoding: deflate\r\n"));
    @assert(raw.contains("Vary: Accept-Encoding"));

    String compressed = body_part(raw);

    char[] decoded = deflate::decompress(
        http::localmem,
        (char[])compressed
    )!;
    defer http::localmem.free(decoded);

    @assert((String)decoded == LARGE_TEXT);
}

fn void? test_compress_prefers_gzip()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: deflate;q=0.5, gzip;q=1.0\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
}

fn void? test_compress_prefers_deflate()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip;q=0.3, deflate;q=0.9\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(raw.contains("Content-Encoding: deflate\r\n"));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
}

fn void? test_compress_identity()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: identity\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw) == LARGE_TEXT);
}

fn void? test_compress_no_accept_encoding()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw) == LARGE_TEXT);
}

fn void? test_compress_small_body()
{
    String raw = fetch_raw(
        "GET /small HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw) == "small");
}

fn void? test_compress_json()
{
    String raw = fetch_raw(
        "GET /json HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(raw.contains("Content-Encoding: gzip\r\n"));
    @assert(
        raw.contains(
            "Content-Type: application/json; charset=utf-8\r\n"
        )
    );

    String compressed = body_part(raw);

    char[] decoded = gzip::uncompress_bytes(
        http::localmem,
        (char[])compressed
    )!;
    defer http::localmem.free(decoded);

    @assert((String)decoded == JSON_TEXT);
}

fn void? test_compress_binary_skipped()
{
    String raw = fetch_raw(
        "GET /binary HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(
        raw.contains(
            "Content-Type: application/octet-stream\r\n"
        )
    );
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw) == BINARY_TEXT);
}

fn void? test_compress_existing_encoding_skipped()
{
    String raw = fetch_raw(
        "GET /encoded HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(raw.contains("Content-Encoding: br\r\n"));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw) == LARGE_TEXT);
}

fn void? test_compress_204_skipped()
{
    String raw = fetch_raw(
        "GET /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip, deflate\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 204));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw).len == 0);
}

fn void? test_compress_head_skipped()
{
    String raw = fetch_raw(
        "HEAD /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip, deflate\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw).len == 0);
}

fn void? test_compress_disabled_gzip()
{
    http::enable_gzip(false);
    defer http::enable_gzip(true);

    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip, deflate\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(raw.contains("Content-Encoding: deflate\r\n"));

    String compressed = body_part(raw);

    char[] decoded = deflate::decompress(
        http::localmem,
        (char[])compressed
    )!;
    defer http::localmem.free(decoded);

    @assert((String)decoded == LARGE_TEXT);
}

fn void? test_compress_min_size()
{
    http::compress_set_min_size(LARGE_TEXT.len + 1);
    defer http::compress_set_min_size(DEFAULT_MIN_SIZE);

    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(!raw.contains("Content-Encoding: gzip\r\n"));
    @assert(!raw.contains("Content-Encoding: deflate\r\n"));
    @assert(body_part(raw) == LARGE_TEXT);
}

fn void? test_compress_keepalive_pipeline()
{
    String raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
        "GET /small HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: identity\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        count_occurrences(raw, "HTTP/1.1 200 OK") == 2
    );
    @assert(
        count_occurrences(raw, "Content-Encoding: gzip\r\n") == 1
    );
    @assert(
        count_occurrences(raw, "Content-Encoding: deflate\r\n") == 0
    );
    @assert(raw.contains("small"));
}

fn void? test_compress_negotiation_edges()
{
    String wildcard_raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: *\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(wildcard_raw);

    @assert(status_is(wildcard_raw, 200));
    @assert(
        wildcard_raw.contains(
            "Content-Encoding: gzip\r\n"
        )
    );
    @assert(
        !wildcard_raw.contains(
            "Content-Encoding: deflate\r\n"
        )
    );

    String wildcard_compressed = body_part(
        wildcard_raw
    );

    char[] wildcard_decoded = gzip::uncompress_bytes(
        http::localmem,
        (char[])wildcard_compressed
    )!;
    defer http::localmem.free(
        wildcard_decoded
    );

    @assert((String)wildcard_decoded == LARGE_TEXT);

    String none_raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: "
        "gzip;q=0, deflate;q=0, identity;q=0\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(none_raw);

    @assert(status_is(none_raw, 200));
    @assert(
        !none_raw.contains(
            "Content-Encoding: gzip\r\n"
        )
    );
    @assert(
        !none_raw.contains(
            "Content-Encoding: deflate\r\n"
        )
    );
    @assert(body_part(none_raw) == LARGE_TEXT);

    String equal_raw = fetch_raw(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: "
        "gzip;q=0.5, deflate;q=0.5\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(equal_raw);

    @assert(status_is(equal_raw, 200));
    @assert(
        equal_raw.contains(
            "Content-Encoding: gzip\r\n"
        )
    );
    @assert(
        !equal_raw.contains(
            "Content-Encoding: deflate\r\n"
        )
    );

    String vary_raw = fetch_raw(
        "GET /vary HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(vary_raw);

    @assert(status_is(vary_raw, 200));
    @assert(
        vary_raw.contains(
            "Vary: Origin, Accept-Encoding\r\n"
        )
    );
    @assert(
        count_occurrences(
            vary_raw,
            "Accept-Encoding"
        ) == 1
    );

    String vary_existing_raw = fetch_raw(
        "GET /vary-existing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(
        vary_existing_raw
    );

    @assert(status_is(vary_existing_raw, 200));
    @assert(
        vary_existing_raw.contains(
            "Vary: Origin, Accept-Encoding\r\n"
        )
    );
    @assert(
        count_occurrences(
            vary_existing_raw,
            "Accept-Encoding"
        ) == 1
    );

    sz old_min_size = http::compress_get_min_size();

    http::compress_set_min_size(0);
    defer http::compress_set_min_size(
        old_min_size
    );

    String incompressible_raw = fetch_raw(
        "GET /incompressible HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept-Encoding: gzip\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(
        incompressible_raw
    );

    @assert(status_is(incompressible_raw, 200));
    @assert(
        !incompressible_raw.contains(
            "Content-Encoding: gzip\r\n"
        )
    );
    @assert(
        !incompressible_raw.contains(
            "Content-Encoding: deflate\r\n"
        )
    );
    @assert(
        incompressible_raw.contains(
            "Vary: Accept-Encoding\r\n"
        )
    );
    @assert(
        body_part(incompressible_raw) ==
            INCOMPRESSIBLE_TEXT
    );
}


// Main

fn void? test_main(void* arg)
{
    http::compress_reset();
    defer http::compress_reset();

    http::compress_set_min_size(DEFAULT_MIN_SIZE);

    Application app;
    app.init();
    defer app.deinit();

    app.use(&http::middleware_compress);

    app.get("/large", &large_text_handler)!;
    app.head("/large", &large_text_handler)!;
    app.get("/small", &small_text_handler)!;
    app.get("/json", &json_handler)!;
    app.get("/binary", &binary_handler)!;
    app.get("/encoded", &encoded_handler)!;
    app.get("/no-content", &no_content_handler)!;
    app.get("/vary", &vary_handler)!;
    app.get("/vary-existing", &vary_existing_handler)!;
    app.get("/incompressible", &incompressible_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(SERVER_START_DELAY_US)!;

    test_compress_gzip()!;
    test_compress_deflate()!;
    test_compress_prefers_gzip()!;
    test_compress_prefers_deflate()!;
    test_compress_identity()!;
    test_compress_no_accept_encoding()!;
    test_compress_small_body()!;
    test_compress_json()!;
    test_compress_binary_skipped()!;
    test_compress_existing_encoding_skipped()!;
    test_compress_204_skipped()!;
    test_compress_head_skipped()!;
    test_compress_disabled_gzip()!;
    test_compress_min_size()!;
    test_compress_keepalive_pipeline()!;
    test_compress_negotiation_edges()!;

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
