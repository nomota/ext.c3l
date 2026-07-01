// test_static_large.c3

// Static file size, binary, and content-type tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::static_large_limit;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18098;

const sz LARGE_FILE_SIZE = 16 * 1024 * 1024 + 1;
const sz MAX_RESPONSE_BYTES = 32 * 1024 * 1024;

const ulong RESPONSE_READ_TIMEOUT_US = 5_000_000;

macro void assert_response_contains(
    String response,
    String expected,
    String message
)
{
    if (!response.contains(expected))
    {
        warn("");
        warn("Unexpected response:");
        warn("--------------------");
        if (response.len < 256) {
            io::printfn("%s", response);
        } else {
            io::printfn("%s ... %d", response[0:256], response.len);
        }
        warn("--------------------");
        warn("Expected: %s", expected);
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
    buffer.init(http::localmem, 8192);
    defer catch buffer.free();

    while (true)
    {
        if (buffer.len() >= MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        char[8192] tmp;

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
        "rm -rf /tmp/aio::http_static_large_limit"
    );

    (void)stdlib::system(
        "mkdir -p "
        "/tmp/aio::http_static_large_limit/public"
    );

    (void)stdlib::system(
        "printf '' > "
        "/tmp/aio::http_static_large_limit/public/empty.txt"
    );

    (void)stdlib::system(
        "printf 'plain text' > "
        "/tmp/aio::http_static_large_limit/public/plain.txt"
    );

    (void)stdlib::system(
        "printf '<html></html>' > "
        "/tmp/aio::http_static_large_limit/public/index.html"
    );

    (void)stdlib::system(
        "printf 'body { color: black; }' > "
        "/tmp/aio::http_static_large_limit/public/style.css"
    );

    (void)stdlib::system(
        "printf 'console.log(1);' > "
        "/tmp/aio::http_static_large_limit/public/app.js"
    );

    (void)stdlib::system(
        "printf '{\"ok\":true}' > "
        "/tmp/aio::http_static_large_limit/public/data.json"
    );

    (void)stdlib::system(
        "printf 'unknown' > "
        "/tmp/aio::http_static_large_limit/public/file.unknown"
    );

    (void)stdlib::system(
        "python3 - <<'PY'\n"
        "with open("
        "'/tmp/aio::http_static_large_limit/public/binary.bin', "
        "'wb'"
        ") as f:\n"
        "    f.write(bytes([0, 1, 2, 65, 66, 0, 255]))\n"
        "with open("
        "'/tmp/aio::http_static_large_limit/public/large.txt', "
        "'w'"
        ") as f:\n"
        "    f.write('x' * (16 * 1024 * 1024 + 1))\n"
        "PY"
    );
}

fn void cleanup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_large_limit"
    );
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.static_files(
        "/static",
        "/tmp/aio::http_static_large_limit/public"
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

fn void test_zero_byte_file()
{
    String response = request_once(
        "GET /static/empty.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "zero-byte static status mismatch"
    );

    @assert(
        response_is_chunked(response),
        "zero-byte static response should be chunked"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body.len == 0,
        "zero-byte static body should be empty"
    );
}

fn void test_binary_file_preserved()
{
    String response = request_once(
        "GET /static/binary.bin HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "binary static status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Type: application/octet-stream\r\n",
        "binary static content type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body.len == 7,
        "binary static body len mismatch"
    );

    @assert(body[0] == 0, "binary static byte 0 mismatch");
    @assert(body[1] == 1, "binary static byte 1 mismatch");
    @assert(body[2] == 2, "binary static byte 2 mismatch");
    @assert(body[3] == 'A', "binary static byte 3 mismatch");
    @assert(body[4] == 'B', "binary static byte 4 mismatch");
    @assert(body[5] == 0, "binary static byte 5 mismatch");
    @assert(body[6] == 255, "binary static byte 6 mismatch");
}

fn void test_text_content_type()
{
    String response = request_once(
        "GET /static/plain.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "txt content-type status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Type: text/plain; charset=utf-8\r\n",
        "txt content-type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "plain text",
        "txt body mismatch"
    );
}

fn void test_html_content_type()
{
    String response = request_once(
        "GET /static/index.html HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "Content-Type: text/html; charset=utf-8\r\n",
        "html content-type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "<html></html>",
        "html body mismatch"
    );
}

fn void test_css_content_type()
{
    String response = request_once(
        "GET /static/style.css HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "Content-Type: text/css; charset=utf-8\r\n",
        "css content-type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "body { color: black; }",
        "css body mismatch"
    );
}

fn void test_js_content_type()
{
    String response = request_once(
        "GET /static/app.js HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "Content-Type: application/javascript; charset=utf-8\r\n",
        "js content-type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "console.log(1);",
        "js body mismatch"
    );
}

fn void test_json_content_type()
{
    String response = request_once(
        "GET /static/data.json HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "Content-Type: application/json; charset=utf-8\r\n",
        "json content-type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "{\"ok\":true}",
        "json body mismatch"
    );
}

fn void test_unknown_content_type()
{
    String response = request_once(
        "GET /static/file.unknown HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "unknown content-type status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Type: application/octet-stream\r\n",
        "unknown content-type mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "unknown",
        "unknown content body mismatch"
    );
}

fn void test_large_static_file()
{
    String response = request_once(
        "GET /static/large.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "large static status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Type: text/plain; charset=utf-8\r\n",
        "large static content type mismatch"
    );

    assert_response_contains(
        response,
        "Accept-Ranges: bytes\r\n",
        "large static Accept-Ranges mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body.len == LARGE_FILE_SIZE,
        "large static body length mismatch"
    );

    @assert(
        body[0] == 'x',
        "large static first byte mismatch"
    );

    @assert(
        body[body.len - 1] == 'x',
        "large static last byte mismatch"
    );

    for (sz i = 0; i < body.len; i += 1024 * 1024) {
        @assert(
            body[i] == 'x',
            "large static sampled byte mismatch"
        );
    }
}

fn void test_too_long_static_path()
{
    DString request;
    request.init(http::localmem, 4096);
    defer request.free();

    request.append("GET /static/");

    for (sz i = 0; i < 1024; i++)
    {
        request.append("a");
    }

    request.append(".txt HTTP/1.1\r\n");
    request.append("Host: localhost\r\n");
    request.append("Connection: close\r\n");
    request.append("\r\n");

    String response = request_once(
        request.str_view()
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 404 Not Found\r\n") ||
        response.contains("HTTP/1.1 400 Bad Request\r\n") ||
        response.contains(
            "HTTP/1.1 414 URI Too Long\r\n"
        ),
        "too long static path status mismatch"
    );
}

fn void? main_task(void* arg)
{
    setup_files();
    defer cleanup_files();

    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_zero_byte_file();
    test_binary_file_preserved();

    test_text_content_type();
    test_html_content_type();
    test_css_content_type();
    test_js_content_type();
    test_json_content_type();
    test_unknown_content_type();

    test_large_static_file();    
    
    test_too_long_static_path();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_static_large_limit: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof