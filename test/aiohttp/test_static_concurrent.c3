// test_static_concurrent.c3

// Concurrent static file tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::static_concurrent;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18094;

const sz CLIENT_COUNT = 24;
const sz LARGE_FILE_SIZE = 65536;

const sz MAX_RESPONSE_BYTES = 1024 * 1024;
const ulong RESPONSE_READ_TIMEOUT_US = 5_000_000;

struct ClientResult
{
    bool ok;
}

ClientResult[CLIENT_COUNT] results;

macro void assert_response_contains(
    String response,
    String expected,
    String message
)
{
    if (!response.contains(expected))
    {
        io::printfn("");
        io::printfn("Unexpected response:");
        io::printfn("--------------------");
        io::printfn("%s", response);
        io::printfn("--------------------");
        io::printfn("Expected: %s", expected);
    }

    @assert(response.contains(expected), message);
}

fn String? response_header(
    String response,
    String expected_name
)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    String header_block = response[0:header_end];

    sz pos = 0;

    while (pos < header_block.len)
    {
        sz rel = header_block[pos..].index_of("\r\n") ?? -1;

        String line;

        if (rel < 0)
        {
            line = header_block[pos:header_block.len - pos];
            pos = header_block.len;
        }
        else
        {
            line = header_block[pos:rel];
            pos += rel + 2;
        }

        if (line.len == 0) continue;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) continue;

        String name = line[0:colon];

        if (!http::str_iequals(name, expected_name))
        {
            continue;
        }

        return line[
            colon + 1:line.len - colon - 1
        ].trim();
    }

    return http::NOT_FOUND~;
}

fn bool response_is_chunked(String response)
{
    String? transfer_encoding = response_header(
        response,
        "Transfer-Encoding"
    );

    if (catch err = transfer_encoding)
    {
        return false;
    }

    return http::str_iequals(
        transfer_encoding.trim(),
        "chunked"
    );
}

fn sz? parse_hex_size(String value)
{
    String text = value.trim();

    sz extension = text.index_of(";") ?? -1;

    if (extension >= 0)
    {
        text = text[0:extension].trim();
    }

    if (text.len == 0)
    {
        return http::BAD_REQUEST~;
    }

    sz result = 0;

    for (sz i = 0; i < text.len; i++)
    {
        char c = text[i];
        char digit;

        if (c >= '0' && c <= '9')
        {
            digit = c - '0';
        }
        else if (c >= 'a' && c <= 'f')
        {
            digit = c - 'a' + 10;
        }
        else if (c >= 'A' && c <= 'F')
        {
            digit = c - 'A' + 10;
        }
        else
        {
            return http::BAD_REQUEST~;
        }

        result = result * 16 + digit;
    }

    return result;
}

fn String? response_body_copy(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    sz body_start = header_end + 4;

    if (body_start > response.len)
    {
        return http::BODY_INCOMPLETE~;
    }

    String wire_body = response[
        body_start:response.len - body_start
    ];

    if (!response_is_chunked(response))
    {
        return wire_body.copy(http::localmem);
    }

    DString decoded;
    decoded.init(http::localmem, wire_body.len);
    defer catch decoded.free();

    sz pos = 0;

    while (true)
    {
        if (pos >= wire_body.len)
        {
            return http::BODY_INCOMPLETE~;
        }

        sz line_len =
            wire_body[pos..].index_of("\r\n") ?? -1;

        if (line_len < 0)
        {
            return http::BODY_INCOMPLETE~;
        }

        String size_line = wire_body[pos:line_len];

        sz chunk_size = parse_hex_size(size_line)!;

        pos += line_len + 2;

        if (chunk_size == 0)
        {
            return decoded.copy_str(http::localmem);
        }

        if (pos + chunk_size + 2 > wire_body.len)
        {
            return http::BODY_INCOMPLETE~;
        }

        decoded.append(wire_body[pos:chunk_size]);

        pos += chunk_size;

        if (
            wire_body[pos] != '\r' ||
            wire_body[pos + 1] != '\n'
        )
        {
            return http::BAD_REQUEST~;
        }

        pos += 2;
    }
}

fn String? read_response(aio::Stream* stream)
{
    if (stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    DString buffer;
    buffer.init(http::localmem, 4096);
    defer catch buffer.free();

    while (true)
    {
        if (buffer.len() >= MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        char[4096] tmp;

        sz? maybe_n = stream.read_timeout(
            tmp[..],
            RESPONSE_READ_TIMEOUT_US
        );

        if (catch err = maybe_n)
        {
            if (err == aio::CLOSED)
            {
                break;
            }

            return err~;
        }

        sz n = maybe_n;

        if (n == 0) break;

        if (buffer.len() + n > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        buffer.append(tmp[0:n]);
    }

    if (buffer.len() == 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    return buffer.copy_str(http::localmem);
}

fn String? request_once(String request)
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    stream.write_all((char[])request)!;

    String response = read_response(stream)!;

    stream.close();

    return response;
}

fn void setup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_concurrent"
    );

    (void)stdlib::system(
        "mkdir -p "
        "/tmp/aio::http_static_concurrent/public/sub"
    );

    (void)stdlib::system(
        "printf 'hello static' > "
        "/tmp/aio::http_static_concurrent/public/hello.txt"
    );

    (void)stdlib::system(
        "printf 'nested' > "
        "/tmp/aio::http_static_concurrent/public/sub/nested.txt"
    );

    (void)stdlib::system(
        "python3 - <<'PY'\n"
        "with open("
        "'/tmp/aio::http_static_concurrent/public/large.txt', "
        "'w'"
        ") as f:\n"
        "    f.write('x' * 65536)\n"
        "PY"
    );
}

fn void cleanup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_concurrent"
    );
}

fn http::Response*? ping_handler(
    http::Context* c
)
{
    return c.text("pong")!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/ping", &ping_handler)!!;

    app.static_files(
        "/static",
        "/tmp/aio::http_static_concurrent/public"
    )!!;
}

fn void? server_task(void* arg)
{
    http::ApplicationServer* server =
        (http::ApplicationServer*)arg;

    if (server == null)
    {
        return http::SERVER_CLOSED~;
    }

    server.serve()!;
}

fn void validate_large_body(String body)
{
    @assert(
        body.len == LARGE_FILE_SIZE,
        "concurrent large static body length mismatch"
    );

    for (sz i = 0; i < body.len; i++)
    {
        @assert(
            body[i] == 'x',
            "concurrent large static body data mismatch"
        );
    }
}

fn void? client_task(void* arg)
{
    sz index = (sz)arg;
    int kind = (int)(index % 5);

    String request;
    String expected_status;

    switch (kind)
    {
        case 0:
            request =
                "GET /static/hello.txt HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            expected_status = "HTTP/1.1 200 OK\r\n";

        case 1:
            request =
                "GET /static/sub/nested.txt HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            expected_status = "HTTP/1.1 200 OK\r\n";

        case 2:
            request =
                "GET /ping HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            expected_status = "HTTP/1.1 200 OK\r\n";

        case 3:
            request =
                "GET /static/missing.txt HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            expected_status =
                "HTTP/1.1 404 Not Found\r\n";

        default:
            request =
                "GET /static/large.txt HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            expected_status = "HTTP/1.1 200 OK\r\n";
    }

    String response = request_once(request)!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        expected_status,
        "concurrent static status mismatch"
    );

    String body = response_body_copy(response)!;
    defer http::localmem.free(body);

switch (kind)
    {
        case 0:
            @assert(
                body == "hello static",
                "concurrent hello static body mismatch"
            );

        case 1:
            @assert(
                body == "nested",
                "concurrent nested static body mismatch"
            );

        case 2:
            @assert(
                body == "pong",
                "concurrent ping body mismatch"
            );

        case 3:
            // The exact 404 body is controlled by the application's
            // not-found handler. The status was checked above.
            break;
        default:
            validate_large_body(body);
    }
    
    results[index].ok = true;
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < 200; i++)
    {
        aio::Stream*? maybe_stream =
            aio::stream_connect(HOST, PORT);

        if (catch err = maybe_stream)
        {
            aio::sleep(100_000)!;
            continue;
        }

        aio::Stream* stream = maybe_stream;

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void? wait_clients()
{
    for (sz spin = 0; spin < 500; spin++)
    {
        bool done = true;

        for (sz i = 0; i < CLIENT_COUNT; i++)
        {
            if (!results[i].ok)
            {
                done = false;
                break;
            }
        }

        if (done) return;

        aio::sleep(100_000)!;
    }

    return aio::TIMEOUT~;
}

fn void? main_task(void* arg)
{
    setup_files();
    defer cleanup_files();

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        results[i] = {
            .ok = false,
        };
    }

    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        aio::spawn(&client_task, (void*)i)!;
    }

    wait_clients()!;

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        @assert(
            results[i].ok,
            "concurrent static client did not finish"
        );
    }

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_static_concurrent: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof