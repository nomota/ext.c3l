// test_static_security.c3

// Static file security and edge tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::static_security;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18093;

const String ROOT = "/tmp/aio::http_static_security";

const sz MAX_RESPONSE_BYTES = 1024 * 1024;
const ulong RESPONSE_READ_TIMEOUT_US = 5_000_000;

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

        return line[colon + 1:line.len - colon - 1].trim();
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

    if (extension >= 0) text = text[0:extension].trim();

    if (text.len == 0) return http::BAD_REQUEST~;

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

        if (
            chunk_size < 0 ||
            pos + chunk_size + 2 > wire_body.len
        )
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

struct ResponseReader
{
    aio::Stream* stream;
    DString buffer;
}

fn void? ResponseReader.init(
    &self,
    aio::Stream* stream
) @maydiscard
{
    if (stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    self.stream = stream;
    self.buffer.init(http::localmem, 4096);
}

fn void ResponseReader.free(&self)
{
    self.buffer.free();
    self.stream = null;
}

fn String? ResponseReader.read_response(&self)
{
    if (self.stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    while (true)
    {
        if (self.buffer.len() > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        char[1024] tmp;

        sz? maybe_n = self.stream.read_timeout(
            tmp[..],
            RESPONSE_READ_TIMEOUT_US
        );

        if (catch err = maybe_n)
        {
            if (err == aio::CLOSED)
            {
                break;
            }

            warn("read_response fault: %s", err);
            return err~;
        }

        sz n = maybe_n;

        if (n == 0) break;

        if (self.buffer.len() + n > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        self.buffer.append(tmp[0:n]);
    }

    if (self.buffer.len() == 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    return self.buffer.str_view().copy(http::localmem);
}

fn String body_part(String response)
{
    sz sep = response.index_of("\r\n\r\n") ?? -1;

    if (sep < 0) return "";

    return response[sep + 4:response.len - sep - 4];
}

fn void setup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_security"
    );

    (void)stdlib::system(
        "mkdir -p "
        "/tmp/aio::http_static_security/public/sub"
    );

    (void)stdlib::system(
        "printf 'index' > "
        "/tmp/aio::http_static_security/public/index.html"
    );

    (void)stdlib::system(
        "printf 'hello static' > "
        "/tmp/aio::http_static_security/public/hello.txt"
    );

    (void)stdlib::system(
        "printf 'nested' > "
        "/tmp/aio::http_static_security/public/sub/nested.txt"
    );

    (void)stdlib::system(
        "printf 'secret' > "
        "/tmp/aio::http_static_security/secret.txt"
    );
}

fn void cleanup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_security"
    );
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.static_files(
        "/static",
        "/tmp/aio::http_static_security/public"
    )!!;
}

fn void? server_task(void* arg)
{
    http::ApplicationServer* server =
        (http::ApplicationServer*)arg;

    server.serve()!;
}

fn String? request_once(String request)
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!;
    defer reader.free();

    stream.write_all((char[])request)!;

    String response = reader.read_response()!;

    stream.close();

    return response;
}

fn void test_static_fetch_raw_ok()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = app.fetch_raw((char[])
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(
        res.status == 200,
        "static fetch_raw status mismatch"
    );

    @assert(
        res.body_kind == http::BodyKind.BODY_FILE,
        "static fetch_raw body kind mismatch"
    );

    @assert(
        res.file_path ==
            "/tmp/aio::http_static_security/public/hello.txt",
        "static fetch_raw file path mismatch"
    );

    @assert(
        res.file_size == 12,
        "static fetch_raw file size mismatch"
    );

    @assert(
        res.body.len == 0,
        "static fetch_raw file response should not buffer body"
    );
}

fn void test_static_file_ok()
{
    String response = request_once(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "static file status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "hello static",
        "static file body mismatch"
    );
}

fn void test_static_nested_file_ok()
{
    String response = request_once(
        "GET /static/sub/nested.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "nested static status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        body == "nested",
        "nested static body mismatch"
    );
}

fn void test_static_missing_file_404()
{
    String response = request_once(
        "GET /static/missing.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 404 Not Found\r\n",
        "missing static status mismatch"
    );
}

fn void test_static_directory_request_rejected()
{
    String response = request_once(
        "GET /static/sub HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 403 Forbidden\r\n") ||
        response.contains("HTTP/1.1 404 Not Found\r\n"),
        "directory static request status mismatch"
    );
}

fn void test_static_dotdot_rejected()
{
    String response = request_once(
        "GET /static/../secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        !body.contains("secret"),
        "dotdot traversal leaked secret"
    );

    @assert(
        response.contains("HTTP/1.1 400 Bad Request\r\n") ||
        response.contains("HTTP/1.1 403 Forbidden\r\n") ||
        response.contains("HTTP/1.1 404 Not Found\r\n"),
        "dotdot traversal status mismatch"
    );
}

fn void test_static_encoded_dotdot_rejected()
{
    String response = request_once(
        "GET /static/%2e%2e/secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        !body.contains("secret"),
        "encoded dotdot traversal leaked secret"
    );

    @assert(
        response.contains("HTTP/1.1 400 Bad Request\r\n") ||
        response.contains("HTTP/1.1 403 Forbidden\r\n") ||
        response.contains("HTTP/1.1 404 Not Found\r\n"),
        "encoded dotdot traversal status mismatch"
    );
}

fn void test_static_double_encoded_dotdot_rejected()
{
    String response = request_once(
        "GET /static/%252e%252e/secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    String body = response_body_copy(response)!!;
    defer http::localmem.free(body);

    @assert(
        !body.contains("secret"),
        "double encoded dotdot traversal leaked secret"
    );

    @assert(
        response.contains("HTTP/1.1 400 Bad Request\r\n") ||
        response.contains("HTTP/1.1 403 Forbidden\r\n") ||
        response.contains("HTTP/1.1 404 Not Found\r\n"),
        "double encoded dotdot traversal status mismatch"
    );
}

fn void test_static_head_no_body()
{
    String response = request_once(
        "HEAD /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "static HEAD status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 12\r\n",
        "static HEAD content length mismatch"
    );

    @assert(
        body_part(response).len == 0,
        "static HEAD body should be empty"
    );
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < 200; i++)
    {
        aio::Stream*? maybe_stream =
            aio::stream_connect(HOST, PORT);

        if (catch err = maybe_stream)
        {
            aio::sleep(500_000)!;
            continue;
        }

        aio::Stream* stream = maybe_stream;

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void? main_task(void* arg)
{
    setup_files();
    defer cleanup_files();

    test_static_fetch_raw_ok();

    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_static_file_ok();
    test_static_nested_file_ok();

    test_static_missing_file_404();
    test_static_directory_request_rejected();

    test_static_dotdot_rejected();
    test_static_encoded_dotdot_rejected();
    test_static_double_encoded_dotdot_rejected();

    test_static_head_no_body();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_static_security: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof