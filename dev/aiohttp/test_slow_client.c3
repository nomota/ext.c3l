// test_slow_client.c3

// Slow client timeout/reset tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::slow_client;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18089;

const usz TEST_READ_TIMEOUT_US = 500_000;
const usz WITHIN_TIMEOUT_DELAY_US = 50_000;
const usz EXCEEDS_TIMEOUT_DELAY_US = 750_000;
const usz SERVER_START_DELAY_US = 100_000;
const usz DEFAULT_READ_TIMEOUT_US = 2_500_000;

const sz MAX_RESPONSE_BYTES = 1024 * 1024;

macro void assert_response_contains(
    String response,
    String expected,
    String message
)
{
    if (!response.contains(expected))
    {
        io::printfn("");
        warn("Unexpected response:");
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
        String value = line[colon + 1:line.len - colon - 1].trim();

        if (name == "Content-Length")
        {
            return value.to_long()!;
        }
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

    sz? content_length = response_content_length(header_block);

    if (catch err = content_length)
    {
        return header_end + 4;
    }

    return header_end + 4 + content_length;
}

struct ResponseReader
{
    aio::Stream* stream;
    DString buffer;
}

fn void? ResponseReader.init(&self, aio::Stream* stream) @maydiscard
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

fn String? ResponseReader.read_response(&self)
{
    if (self.stream == null)
    {
        return http::CONTEXT_NOT_READY~;
    }

    while (true)
    {
        String text = self.buffer.str_view();

        sz? total = response_expected_total_len(text);

        if (try total)
        {
            if (self.buffer.len() >= total)
            {
                String out = text[0:total].copy(http::localmem);

                self.consume(total);

                return out;
            }
        }

        if (self.buffer.len() > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        char[1024] tmp;

        sz n = self.stream.read(tmp[..])!;

        if (n == 0) break;

        self.buffer.append(tmp[0:n]);
    }

    if (self.buffer.len() > 0)
    {
        String out = self.buffer.str_view().copy(http::localmem);

        self.buffer.clear();

        return out;
    }

    return http::BODY_INCOMPLETE~;
}

fn http::Response*? home_handler(http::Context* c)
{
    return c.text("home")!;
}

fn http::Response*? echo_handler(http::Context* c)
{
    return c.text(c.req_text())!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.get("/", &home_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    http::ApplicationServer* server =
        (http::ApplicationServer*)arg;

    server.serve()!;
}

fn void test_slow_header_within_timeout()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
    )!!;

    aio::sleep(WITHIN_TIMEOUT_DELAY_US)!!;

    stream.write_all((char[])
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String response = reader.read_response()!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "slow header status mismatch"
    );
    assert_response_contains(
        response,
        "\r\n\r\nhome",
        "slow header body mismatch"
    );

    stream.close();
}

fn void test_slow_body_within_timeout()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 10\r\n"
        "Connection: close\r\n"
        "\r\n"
        "hello"
    )!!;

    aio::sleep(WITHIN_TIMEOUT_DELAY_US)!!;

    stream.write_all((char[])"world")!!;

    String response = reader.read_response()!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 200 OK\r\n",
        "slow body status mismatch"
    );
    assert_response_contains(
        response,
        "\r\n\r\nhelloworld",
        "slow body echo mismatch"
    );

    stream.close();
}

fn void test_slow_header_exceeds_timeout()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
    )!!;

    aio::sleep(EXCEEDS_TIMEOUT_DELAY_US)!!;

    String response = reader.read_response()!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 408 Request Timeout\r\n",
        "slow header timeout status mismatch"
    );
    assert_response_contains(
        response,
        "Connection: close\r\n",
        "slow header timeout close mismatch"
    );
    assert_response_contains(
        response,
        "\r\n\r\n408 Request Timeout",
        "slow header timeout body mismatch"
    );

    stream.close();
}

fn void test_slow_body_exceeds_timeout()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 10\r\n"
        "\r\n"
        "hello"
    )!!;

    aio::sleep(EXCEEDS_TIMEOUT_DELAY_US)!!;

    String response = reader.read_response()!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 408 Request Timeout\r\n",
        "slow body timeout status mismatch"
    );
    assert_response_contains(
        response,
        "Connection: close\r\n",
        "slow body timeout close mismatch"
    );
    assert_response_contains(
        response,
        "\r\n\r\n408 Request Timeout",
        "slow body timeout body mismatch"
    );

    stream.close();
}

fn void test_timeout_connection_is_closed()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
    )!!;

    aio::sleep(EXCEEDS_TIMEOUT_DELAY_US)!!;

    String response = reader.read_response()!!;
    defer http::localmem.free(response);

    assert_response_contains(
        response,
        "HTTP/1.1 408 Request Timeout\r\n",
        "timeout close status mismatch"
    );

    char[16] tmp;
    sz n = stream.read(tmp[..])!!;

    @assert(n == 0, "timeout connection should be closed");

    stream.close();
}

fn void? main_task(void* arg)
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    http::set_read_timeout_us(TEST_READ_TIMEOUT_US);

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    aio::sleep(SERVER_START_DELAY_US)!;

    test_slow_header_within_timeout();
    test_slow_body_within_timeout();

    test_slow_header_exceeds_timeout();
    test_slow_body_exceeds_timeout();
    test_timeout_connection_is_closed();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_slow_client: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof 