// test_executor_pressure.c3

// Executor pressure tests for ext::aio::http
//
// This test verifies that many executor-backed static file reads do not block
// the event loop and do not prevent normal dynamic routes from responding.

// Nomota <hiongun@gmail.com>; MIT License

module test::executor_pressure;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18096;

const sz STATIC_CLIENTS = 24;
const sz PING_CLIENTS = 24;
const sz CLIENT_COUNT = STATIC_CLIENTS + PING_CLIENTS;

const sz LARGE_FILE_SIZE = 262144;
const sz MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

const ulong RESPONSE_READ_TIMEOUT_US = 5_000_000;
const ulong CLIENT_WAIT_INTERVAL_US = 10_000;
const sz CLIENT_WAIT_ATTEMPTS = 1000;

struct ClientResult
{
    bool done;
    bool ok;
}

ClientResult[CLIENT_COUNT] results;

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
        sz rel =
            header_block[pos..].index_of("\r\n") ?? -1;

        String line;

        if (rel < 0)
        {
            line = header_block[
                pos:header_block.len - pos
            ];

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

fn void? wait_server_ready()
{
    for (sz i = 0; i < 200; i++)
    {
        aio::Stream*? maybe_stream =
            aio::stream_connect(HOST, PORT);

        if (catch err = maybe_stream)
        {
            aio::sleep(10_000)!;
            continue;
        }

        aio::Stream* stream = maybe_stream;

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void setup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_executor_pressure"
    );

    (void)stdlib::system(
        "mkdir -p "
        "/tmp/aio::http_executor_pressure/public"
    );

    (void)stdlib::system(
        "python3 - <<'PY'\n"
        "with open("
        "'/tmp/aio::http_executor_pressure/public/large.txt', "
        "'w'"
        ") as f:\n"
        "    f.write('x' * 262144)\n"
        "with open("
        "'/tmp/aio::http_executor_pressure/public/small.txt', "
        "'w'"
        ") as f:\n"
        "    f.write('small')\n"
        "PY"
    );
}

fn void cleanup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_executor_pressure"
    );
}

fn http::Response*? ping_handler(
    http::Context* c
)
{
    return c.text("pong")!;
}

fn http::Response*? tiny_handler(
    http::Context* c
)
{
    return c.text("tiny")!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/ping", &ping_handler)!!;
    app.get("/tiny", &tiny_handler)!!;

    app.static_files(
        "/static",
        "/tmp/aio::http_executor_pressure/public"
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

fn bool check_static_large_response(String response)
{
    if (!response.contains("HTTP/1.1 200 OK\r\n"))
    {
        return false;
    }

    if (!response_is_chunked(response))
    {
        return false;
    }

    String? maybe_body = response_body_copy(response);

    if (catch err = maybe_body)
    {
        return false;
    }

    String body = maybe_body;
    defer http::localmem.free(body);

    if (body.len != LARGE_FILE_SIZE)
    {
        return false;
    }

    if (body[0] != 'x')
    {
        return false;
    }

    if (body[body.len - 1] != 'x')
    {
        return false;
    }

    for (sz i = 0; i < body.len; i++)
    {
        if (body[i] != 'x')
        {
            return false;
        }
    }

    return true;
}

fn bool check_text_response(
    String response,
    String expected_body
)
{
    if (!response.contains("HTTP/1.1 200 OK\r\n"))
    {
        return false;
    }

    String? maybe_body = response_body_copy(response);

    if (catch err = maybe_body)
    {
        return false;
    }

    String body = maybe_body;
    defer http::localmem.free(body);

    return body == expected_body;
}

fn void? static_client_task(void* arg)
{
    sz index = (sz)arg;

    defer
    {
        results[index].done = true;
    }

    String response = request_once(
        "GET /static/large.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(response);

    results[index].ok =
        check_static_large_response(response);
}

fn void? ping_client_task(void* arg)
{
    sz index = (sz)arg;

    defer
    {
        results[index].done = true;
    }

    String response = request_once(
        "GET /ping HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(response);

    results[index].ok =
        check_text_response(response, "pong");
}

fn void? tiny_client_task(void* arg)
{
    sz index = (sz)arg;

    defer
    {
        results[index].done = true;
    }

    String response = request_once(
        "GET /tiny HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(response);

    results[index].ok =
        check_text_response(response, "tiny");
}

fn void? wait_all_clients()
{
    for (
        sz spin = 0;
        spin < CLIENT_WAIT_ATTEMPTS;
        spin++
    )
    {
        bool done = true;

        for (sz i = 0; i < CLIENT_COUNT; i++)
        {
            if (!results[i].done)
            {
                done = false;
                break;
            }
        }

        if (done) return;

        aio::sleep(CLIENT_WAIT_INTERVAL_US)!;
    }

    return aio::TIMEOUT~;
}

fn void assert_all_clients_ok()
{
    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        @assert(
            results[i].done,
            "executor pressure client did not finish"
        );

        @assert(
            results[i].ok,
            "executor pressure client response mismatch"
        );
    }
}

fn void? main_task(void* arg)
{
    setup_files();
    defer cleanup_files();

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        results[i] = {
            .done = false,
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

    for (sz i = 0; i < STATIC_CLIENTS; i++)
    {
        aio::spawn(
            &static_client_task,
            (void*)i
        )!;
    }

    for (sz i = 0; i < PING_CLIENTS; i++)
    {
        sz index = STATIC_CLIENTS + i;

        if ((i % 2) == 0)
        {
            aio::spawn(
                &ping_client_task,
                (void*)index
            )!;
        }
        else
        {
            aio::spawn(
                &tiny_client_task,
                (void*)index
            )!;
        }
    }

    wait_all_clients()!;
    assert_all_clients_ok();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_executor_pressure: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof