// test_no_body.c3

// No-body response semantics tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::no_body;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18092;

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

fn String response_body(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0) return "";

    sz body_start = header_end + 4;

    return response[
        body_start:response.len - body_start
    ];
}

fn sz? header_only_expected_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    return header_end + 4;
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

fn String? ResponseReader.read_header_only_response(&self)
{
    if (self.stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    while (true)
    {
        String text = self.buffer.str_view();

        sz? expected_total =
            header_only_expected_len(text);

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

fn String? ResponseReader.read_until_close(&self)
{
    if (self.stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    while (true)
    {
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

    if (self.buffer.len() == 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    return self.buffer.copy_str(http::localmem);
}

fn http::Response*? get_handler(
    http::Context* c
)
{
    return c.text("hello")!;
}

fn http::Response*? no_content_handler(
    http::Context* c
)
{
    c.status(204)!;

    return c.text("should-not-send")!;
}

fn http::Response*? not_modified_handler(
    http::Context* c
)
{
    c.status(304)!;

    return c.text("should-not-send")!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/", &get_handler)!!;
    app.get("/no-content", &no_content_handler)!!;
    app.get("/not-modified", &not_modified_handler)!!;
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

fn String? request_header_only(String request)
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!;
    defer reader.free();

    stream.write_all((char[])request)!;

    String response =
        reader.read_header_only_response()!;

    stream.close();

    return response;
}

fn String? request_until_close(String request)
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!;
    defer reader.free();

    stream.write_all((char[])request)!;

    String response = reader.read_until_close()!;

    stream.close();

    return response;
}

fn void test_head_200_no_body()
{
    String response = request_header_only(
        "HEAD / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "HEAD 200 status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 5\r\n",
        "HEAD 200 content length mismatch"
    );

    @assert(
        response_body(response).len == 0,
        "HEAD 200 body should be empty"
    );
}

fn void test_head_404_no_body()
{
    String response = request_header_only(
        "HEAD /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 404 Not Found\r\n",
        "HEAD 404 status mismatch"
    );

    @assert(
        response_body(response).len == 0,
        "HEAD 404 body should be empty"
    );
}

fn void test_head_get_fallback_204_no_body()
{
    String response = request_header_only(
        "HEAD /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 204 No Content\r\n",
        "HEAD fallback 204 status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 0\r\n",
        "HEAD fallback 204 content length mismatch"
    );

    @assert(
        response_body(response).len == 0,
        "HEAD fallback 204 body should be empty"
    );
}

fn void test_204_no_body_even_if_handler_sets_body()
{
    String response = request_until_close(
        "GET /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 204 No Content\r\n",
        "204 status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 0\r\n",
        "204 content length mismatch"
    );

    @assert(
        !response.contains("should-not-send"),
        "204 body should be suppressed"
    );

    @assert(
        response_body(response).len == 0,
        "204 body should be empty"
    );
}

fn void test_304_no_body_even_if_handler_sets_body()
{
    String response = request_until_close(
        "GET /not-modified HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 304 Not Modified\r\n",
        "304 status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 0\r\n",
        "304 content length mismatch"
    );

    @assert(
        !response.contains("should-not-send"),
        "304 body should be suppressed"
    );

    @assert(
        response_body(response).len == 0,
        "304 body should be empty"
    );
}

fn void test_fetch_raw_204_status()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = app.fetch_raw((char[])
        "GET /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(
        res.status == 204,
        "fetch 204 status mismatch"
    );

    @assert(
        res.body_kind == http::BodyKind.BODY_BYTES,
        "fetch 204 body kind mismatch"
    );

    @assert(
        (String)res.body == "should-not-send",
        "fetch 204 handler body mismatch"
    );
}

fn void test_fetch_raw_304_status()
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::Response* res = app.fetch_raw((char[])
        "GET /not-modified HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(res);

    @assert(
        res.status == 304,
        "fetch 304 status mismatch"
    );

    @assert(
        res.body_kind == http::BodyKind.BODY_BYTES,
        "fetch 304 body kind mismatch"
    );

    @assert(
        (String)res.body == "should-not-send",
        "fetch 304 handler body mismatch"
    );
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

    test_head_200_no_body();
    test_head_404_no_body();
    test_head_get_fallback_204_no_body();

    test_204_no_body_even_if_handler_sets_body();
    test_304_no_body_even_if_handler_sets_body();

    test_fetch_raw_204_status();
    test_fetch_raw_304_status();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_no_body: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof