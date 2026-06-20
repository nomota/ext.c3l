// test_static_prefix.c3

// Static route prefix tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::static_prefix;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18095;

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
        return aio::http::BODY_INCOMPLETE~;
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

        if (!aio::http::str_iequals(name, expected_name))
        {
            continue;
        }

        return line[
            colon + 1:line.len - colon - 1
        ].trim();
    }

    return aio::http::NOT_FOUND~;
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

    return aio::http::str_iequals(
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
        return aio::http::BAD_REQUEST~;
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
            return aio::http::BAD_REQUEST~;
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
        return aio::http::BODY_INCOMPLETE~;
    }

    sz body_start = header_end + 4;

    if (body_start > response.len)
    {
        return aio::http::BODY_INCOMPLETE~;
    }

    String wire_body = response[
        body_start:response.len - body_start
    ];

    if (!response_is_chunked(response))
    {
        return wire_body.copy(aio::http::localmem);
    }

    DString decoded;
    decoded.init(aio::http::localmem, wire_body.len);
    defer catch decoded.free();

    sz pos = 0;

    while (true)
    {
        if (pos >= wire_body.len)
        {
            return aio::http::BODY_INCOMPLETE~;
        }

        sz line_len =
            wire_body[pos..].index_of("\r\n") ?? -1;

        if (line_len < 0)
        {
            return aio::http::BODY_INCOMPLETE~;
        }

        String size_line = wire_body[pos:line_len];

        sz chunk_size = parse_hex_size(size_line)!;

        pos += line_len + 2;

        if (chunk_size == 0)
        {
            return decoded.copy_str(aio::http::localmem);
        }

        if (pos + chunk_size + 2 > wire_body.len)
        {
            return aio::http::BODY_INCOMPLETE~;
        }

        decoded.append(wire_body[pos:chunk_size]);

        pos += chunk_size;

        if (
            wire_body[pos] != '\r' ||
            wire_body[pos + 1] != '\n'
        )
        {
            return aio::http::BAD_REQUEST~;
        }

        pos += 2;
    }
}

fn String? read_response(aio::Stream* stream)
{
    if (stream == null)
    {
        return aio::http::CONTEXT_NOT_READY~;
    }

    DString buffer;
    buffer.init(aio::http::localmem, 4096);
    defer catch buffer.free();

    while (true)
    {
        if (buffer.len() >= MAX_RESPONSE_BYTES)
        {
            return aio::http::REQUEST_TOO_LARGE~;
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
            return aio::http::REQUEST_TOO_LARGE~;
        }

        buffer.append(tmp[0:n]);
    }

    if (buffer.len() == 0)
    {
        return aio::http::BODY_INCOMPLETE~;
    }

    return buffer.copy_str(aio::http::localmem);
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

fn void setup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_prefix"
    );

    (void)stdlib::system(
        "mkdir -p "
        "/tmp/aio::http_static_prefix/public/sub"
    );

    (void)stdlib::system(
        "printf 'index' > "
        "/tmp/aio::http_static_prefix/public/index.html"
    );

    (void)stdlib::system(
        "printf 'hello static' > "
        "/tmp/aio::http_static_prefix/public/hello.txt"
    );

    (void)stdlib::system(
        "printf 'nested' > "
        "/tmp/aio::http_static_prefix/public/sub/nested.txt"
    );

    (void)stdlib::system(
        "printf 'root asset' > "
        "/tmp/aio::http_static_prefix/public/root.txt"
    );

    (void)stdlib::system(
        "printf 'secret' > "
        "/tmp/aio::http_static_prefix/secret.txt"
    );
}

fn void cleanup_files()
{
    (void)stdlib::system(
        "rm -rf /tmp/aio::http_static_prefix"
    );
}

fn aio::http::Response*? dynamic_handler(
    aio::http::Context* c
)
{
    return c.text("dynamic")!;
}

fn aio::http::Response*? staticx_handler(
    aio::http::Context* c
)
{
    return c.text("staticx dynamic")!;
}

fn aio::http::Response*? static_method_handler(
    aio::http::Context* c
)
{
    return c.text("staticmethod dynamic")!;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.static_files(
        "/static",
        "/tmp/aio::http_static_prefix/public"
    )!!;

    app.get("/dynamic", &dynamic_handler)!!;
    app.get("/staticx/hello.txt", &staticx_handler)!!;
    app.get(
        "/staticmethod.txt",
        &static_method_handler
    )!!;
}

fn void? server_task(void* arg)
{
    aio::http::ApplicationServer* server =
        (aio::http::ApplicationServer*)arg;

    if (server == null)
    {
        return aio::http::HTTP_SERVER_CLOSED~;
    }

    server.serve()!;
}

fn void test_static_prefix_file_ok()
{
    String response = request_once(
        "GET /static/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "static prefix file status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer aio::http::localmem.free(body);

    @assert(
        body == "hello static",
        "static prefix file body mismatch"
    );
}

fn void test_static_prefix_nested_ok()
{
    String response = request_once(
        "GET /static/sub/nested.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "static prefix nested status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer aio::http::localmem.free(body);

    @assert(
        body == "nested",
        "static prefix nested body mismatch"
    );
}

fn void test_static_prefix_base_path_policy()
{
    String response = request_once(
        "GET /static HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    bool ok =
        response.contains("HTTP/1.1 200 OK\r\n");

    bool not_found =
        response.contains("HTTP/1.1 404 Not Found\r\n");

    @assert(
        ok || not_found,
        "static prefix base path status mismatch"
    );

    if (ok)
    {
        String body = response_body_copy(response)!!;
        defer aio::http::localmem.free(body);

        @assert(
            body == "index",
            "static prefix base index body mismatch"
        );
    }
}

fn void test_static_prefix_slash_path_policy()
{
    String response = request_once(
        "GET /static/ HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    bool ok =
        response.contains("HTTP/1.1 200 OK\r\n");

    bool not_found =
        response.contains("HTTP/1.1 404 Not Found\r\n");

    @assert(
        ok || not_found,
        "static prefix slash path status mismatch"
    );

    if (ok)
    {
        String body = response_body_copy(response)!!;
        defer aio::http::localmem.free(body);

        @assert(
            body == "index",
            "static prefix slash index body mismatch"
        );
    }
}

fn void test_static_prefix_does_not_match_staticx()
{
    String response = request_once(
        "GET /staticx/hello.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "staticx dynamic status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer aio::http::localmem.free(body);

    @assert(
        body == "staticx dynamic",
        "staticx dynamic body mismatch"
    );

    @assert(
        body != "hello static",
        "static prefix wrongly matched /staticx"
    );
}

fn void test_static_prefix_does_not_match_staticmethod()
{
    String response = request_once(
        "GET /staticmethod.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "staticmethod dynamic status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer aio::http::localmem.free(body);

    @assert(
        body == "staticmethod dynamic",
        "staticmethod dynamic body mismatch"
    );

    @assert(
        body != "hello static",
        "static prefix wrongly matched /staticmethod.txt"
    );
}

fn void test_static_prefix_missing_file()
{
    String response = request_once(
        "GET /static/missing.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 404 Not Found\r\n",
        "static prefix missing status mismatch"
    );
}

fn void test_static_prefix_dotdot_rejected()
{
    String response = request_once(
        "GET /static/../secret.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    String body = response_body_copy(response)!!;
    defer aio::http::localmem.free(body);

    @assert(
        !body.contains("secret"),
        "static prefix dotdot leaked secret"
    );

    @assert(
        response.contains(
            "HTTP/1.1 400 Bad Request\r\n"
        ) ||
        response.contains(
            "HTTP/1.1 403 Forbidden\r\n"
        ) ||
        response.contains(
            "HTTP/1.1 404 Not Found\r\n"
        ),
        "static prefix dotdot status mismatch"
    );
}

fn void test_static_prefix_encoded_slash_policy()
{
    String response = request_once(
        "GET /static/sub%2fnested.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    bool ok =
        response.contains("HTTP/1.1 200 OK\r\n");

    @assert(
        ok ||
        response.contains(
            "HTTP/1.1 400 Bad Request\r\n"
        ) ||
        response.contains(
            "HTTP/1.1 403 Forbidden\r\n"
        ) ||
        response.contains(
            "HTTP/1.1 404 Not Found\r\n"
        ),
        "static prefix encoded slash status mismatch"
    );

    if (ok)
    {
        String body = response_body_copy(response)!!;
        defer aio::http::localmem.free(body);

        @assert(
            body == "nested",
            "static prefix encoded slash body mismatch"
        );
    }
}

fn void test_dynamic_route_still_works()
{
    String response = request_once(
        "GET /dynamic HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "dynamic route status mismatch"
    );

    String body = response_body_copy(response)!!;
    defer aio::http::localmem.free(body);

    @assert(
        body == "dynamic",
        "dynamic route body mismatch"
    );
}

fn void? main_task(void* arg)
{
    setup_files();
    defer cleanup_files();

    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_static_prefix_file_ok();
    test_static_prefix_nested_ok();

    test_static_prefix_base_path_policy();
    test_static_prefix_slash_path_policy();

    test_static_prefix_does_not_match_staticx();
    test_static_prefix_does_not_match_staticmethod();

    test_static_prefix_missing_file();
    test_static_prefix_dotdot_rejected();
    test_static_prefix_encoded_slash_policy();

    test_dynamic_route_still_works();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_static_prefix: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof