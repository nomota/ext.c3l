// test_disconnect.c3

// Client disconnect tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::disconnect;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18091;

const ulong TEST_READ_TIMEOUT_US = 100_000;
const ulong DEFAULT_READ_TIMEOUT_US = 5_000_000;
const ulong RESPONSE_READ_TIMEOUT_US = 5_000_000;

const sz MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const sz LARGE_RESPONSE_SIZE = 1024 * 1024;
const sz LARGE_RESPONSE_CHUNK_SIZE = 4096;

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

        if (!aio::http::str_iequals(name, "Content-Length"))
        {
            continue;
        }

        String value =
            line[colon + 1:line.len - colon - 1].trim();

        return value.to_long()!;
    }

    return aio::http::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return aio::http::BODY_INCOMPLETE~;
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

fn String response_body(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0) return "";

    sz body_start = header_end + 4;

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
        return aio::http::CONTEXT_NOT_READY~;
    }

    self.stream = stream;
    self.buffer.init(aio::http::localmem, 4096);
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

fn String? ResponseReader.read_response(&self)
{
    if (self.stream == null)
    {
        return aio::http::CONTEXT_NOT_READY~;
    }

    while (true)
    {
        String text = self.buffer.str_view();

        sz? expected_total =
            response_expected_total_len(text);

        if (try expected_total)
        {
            if (self.buffer.len() >= expected_total)
            {
                String response =
                    text[0:expected_total].copy(
                        aio::http::localmem
                    );

                self.consume(expected_total);

                return response;
            }
        }

        if (self.buffer.len() >= MAX_RESPONSE_BYTES)
        {
            return aio::http::REQUEST_TOO_LARGE~;
        }

        char[4096] tmp;

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
            return aio::http::REQUEST_TOO_LARGE~;
        }

        self.buffer.append(tmp[0:n]);
    }

    if (self.buffer.len() > 0)
    {
        String response =
            self.buffer.str_view().copy(aio::http::localmem);

        self.buffer.clear();

        return response;
    }

    return aio::http::BODY_INCOMPLETE~;
}

fn aio::http::Response*? home_handler(
    aio::http::Context* c
)
{
    return c.text("home")!;
}

fn aio::http::Response*? echo_handler(
    aio::http::Context* c
)
{
    return c.text(c.req_text())!;
}

fn aio::http::Response*? large_handler(
    aio::http::Context* c
)
{
    DString body;
    body.init(aio::http::localmem, LARGE_RESPONSE_SIZE);
    defer body.free();

    char[LARGE_RESPONSE_CHUNK_SIZE] chunk;

    for (sz i = 0; i < chunk.len; i++)
    {
        chunk[i] = 'x';
    }

    sz remaining = LARGE_RESPONSE_SIZE;

    while (remaining > 0)
    {
        sz n = remaining;

        if (n > LARGE_RESPONSE_CHUNK_SIZE)
        {
            n = LARGE_RESPONSE_CHUNK_SIZE;
        }

        body.append(chunk[0:n]);
        remaining -= n;
    }

    return c.text(body.str_view())!;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.get("/", &home_handler)!!;
    app.get("/large", &large_handler)!!;
    app.post("/echo", &echo_handler)!!;
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

fn void test_disconnect_before_header_complete()
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!!;

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
    )!!;

    stream.close();
    stream.free();

    aio::sleep(20_000)!!;
}

fn void test_disconnect_during_body()
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!!;

    stream.write_all((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 10\r\n"
        "\r\n"
        "hello"
    )!!;

    stream.close();
    stream.free();

    aio::sleep(20_000)!!;
}

fn void test_disconnect_after_request_write()
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!!;

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    stream.close();
    stream.free();

    aio::sleep(20_000)!!;
}

fn void test_disconnect_before_reading_large_response()
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!!;

    stream.write_all((char[])
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    stream.close();
    stream.free();

    aio::sleep(50_000)!!;
}

fn void test_server_still_responds_after_disconnects()
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String response = reader.read_response()!!;
    defer aio::http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "server after disconnect status mismatch"
    );

    assert_response_contains(
        response,
        "Content-Length: 4\r\n",
        "server after disconnect content length mismatch"
    );

    @assert(
        response_body(response) == "home",
        "server after disconnect body mismatch"
    );

    stream.close();
}

fn void test_many_aborted_clients()
{
    for (sz i = 0; i < 20; i++)
    {
        aio::Stream* stream =
            aio::stream_connect(HOST, PORT)!!;

        stream.write_all((char[])
            "GET / HTTP/1.1\r\n"
            "Host: localhost\r\n"
        )!!;

        stream.close();
        stream.free();
    }

    aio::sleep(100_000)!!;

    test_server_still_responds_after_disconnects();
}

fn void? main_task(void* arg)
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::http_set_read_timeout_us(
        TEST_READ_TIMEOUT_US
    );

    defer aio::http::http_set_read_timeout_us(
        DEFAULT_READ_TIMEOUT_US
    );

    aio::http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_disconnect_before_header_complete();
    test_disconnect_during_body();
    test_disconnect_after_request_write();
    test_disconnect_before_reading_large_response();

    test_server_still_responds_after_disconnects();
    test_many_aborted_clients();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_disconnect: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof