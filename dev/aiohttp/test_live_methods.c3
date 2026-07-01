// test_live_methods.c3

// Live HTTP method semantics tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::live_methods;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18090;

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
        warn("Expected: %s", expected);
    }

    @assert(response.contains(expected), message);
}

fn sz? response_content_length(String header_block)
{
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

        if (!http::str_iequals(name, "Content-Length"))
        {
            continue;
        }

        String value =
            line[colon + 1:line.len - colon - 1].trim();

        return value.to_long()!;
    }

    return http::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    String header_block = response[0:header_end];

    sz? content_length =
        response_content_length(header_block);

    if (catch err = content_length)
    {
        return header_end + 4;
    }

    return header_end + 4 + content_length;
}

fn sz? head_response_expected_total_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    return header_end + 4;
}

fn String response_body(String response)
{
    sz separator = response.index_of("\r\n\r\n") ?? -1;

    if (separator < 0) return "";

    sz body_start = separator + 4;

    return response[
        body_start:response.len - body_start
    ];
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

fn void ResponseReader.consume(&self, sz n)
{
    if (n <= 0) return;

    if (n >= self.buffer.len())
    {
        self.buffer.clear();
        return;
    }

    self.buffer.delete(0, (usz)n);
}

fn String? ResponseReader.read_response(
    &self,
    bool is_head = false
)
{
    if (self.stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    while (true)
    {
        String text = self.buffer.str_view();

        sz? expected_total;

        if (is_head)
        {
            expected_total =
                head_response_expected_total_len(text);
        }
        else
        {
            expected_total =
                response_expected_total_len(text);
        }

        if (try expected_total)
        {
            if (self.buffer.len() >= expected_total)
            {
                String response =
                    text[0:expected_total].copy(
                        http::localmem
                    );

                self.consume(expected_total);

                return response;
            }
        }

        if (self.buffer.len() >= MAX_RESPONSE_BYTES)
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

    if (self.buffer.len() > 0)
    {
        String response =
            self.buffer.str_view().copy(http::localmem);

        self.buffer.clear();

        return response;
    }

    return http::BODY_INCOMPLETE~;
}

fn http::Response*? get_handler(
    http::Context* c
)
{
    return c.text("hello")!;
}

fn http::Response*? options_handler(
    http::Context* c
)
{
    c.header("Allow", "GET, HEAD, OPTIONS")!;

    return c.text("options")!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/", &get_handler)!!;
    app.options("/", &options_handler)!!;
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

fn String? request_once(
    String request,
    bool is_head = false
)
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!;
    defer reader.free();

    stream.write_all((char[])request)!;

    String response =
        reader.read_response(is_head)!;

    stream.close();

    return response;
}

fn void test_live_get_has_body()
{
    String response = request_once(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "GET status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 5\r\n",
        "GET content length mismatch"
    );

    @assert(
        response_body(response) == "hello",
        "GET body mismatch"
    );
}

fn void test_live_head_has_no_wire_body()
{
    String response = request_once(
        "HEAD / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n",
        true
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "HEAD status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 5\r\n",
        "HEAD content length mismatch"
    );
//warn(response);
    @assert(
        @ok(response.index_of("\r\n\r\n")),
        "HEAD separator missing"
    );

    @assert(
        response_body(response).len == 0,
        "HEAD response body should be empty"
    );
}

fn void test_live_options()
{
    String response = request_once(
        "OPTIONS / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "OPTIONS status mismatch"
    );

    assert_response_contains(
        response,
        "Allow: GET, HEAD, OPTIONS\r\n",
        "OPTIONS Allow header mismatch"
    );

    @assert(
        response_body(response) == "options",
        "OPTIONS body mismatch"
    );
}

fn void test_live_method_not_allowed()
{
    String response = request_once(
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 405 Method Not Allowed\r\n",
        "405 status mismatch"
    );

    @assert(
        response_body(response) ==
            "405 Method Not Allowed",
        "405 body mismatch"
    );
}

fn void test_live_head_keepalive_then_get()
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "HEAD / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String head_response =
        reader.read_response(true)!!;
    defer http::localmem.free(head_response);

    assert_response_contains(
        head_response,
        "HTTP/1.1 200 OK\r\n",
        "HEAD keepalive status mismatch"
    );

    assert_response_contains(
        head_response,
        "Connection: keep-alive\r\n",
        "HEAD keepalive connection mismatch"
    );

    assert_response_contains(
        head_response,
        "Content-Length: 5\r\n",
        "HEAD keepalive content length mismatch"
    );

    @assert(
        response_body(head_response).len == 0,
        "HEAD keepalive body should be empty"
    );

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String get_response =
        reader.read_response()!!;
    defer http::localmem.free(get_response);

    assert_response_contains(
        get_response,
        "HTTP/1.1 200 OK\r\n",
        "GET after HEAD status mismatch"
    );

    assert_response_contains(
        get_response,
        "Connection: close\r\n",
        "GET after HEAD close mismatch"
    );

    @assert(
        response_body(get_response) == "hello",
        "GET after HEAD body mismatch"
    );

    stream.close();
}

fn void? main_task(void* arg)
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_live_get_has_body();
    test_live_head_has_no_wire_body();
    test_live_options();
    test_live_method_not_allowed();
    test_live_head_keepalive_then_get();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_live_methods: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof