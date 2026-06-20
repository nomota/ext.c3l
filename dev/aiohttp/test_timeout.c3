// test_timeout.c3

// Request timeout tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::timeout;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18087;

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

        if (aio::http::str_iequals(name, "Content-Length"))
        {
            return value.to_long()!;
        }
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
    if (stream == null) return aio::http::CONTEXT_NOT_READY~;

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

        sz? total = response_expected_total_len(text);

        if (try total)
        {
            if (self.buffer.len() >= total)
            {
                String out = text[0:total].copy(aio::http::localmem);

                self.consume(total);

                return out;
            }
        }

        if (self.buffer.len() > 1024 * 1024)
        {
            return aio::http::REQUEST_TOO_LARGE~;
        }

        char[1024] tmp;

        sz n = self.stream.read(tmp[..])!;

        if (n == 0) break;

        self.buffer.append(tmp[0:n]);
    }

    if (self.buffer.len() > 0)
    {
        String out = self.buffer.str_view().copy(aio::http::localmem);

        self.buffer.clear();

        return out;
    }

    return aio::http::BODY_INCOMPLETE~;
}

fn aio::http::Response*? home_handler(aio::http::Context* c)
{
    return c.text("home")!;
}

fn aio::http::Response*? echo_handler(aio::http::Context* c)
{
    return c.text(c.req_text())!;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.get("/", &home_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    aio::http::ApplicationServer* server =
        (aio::http::ApplicationServer*)arg;

    server.serve()!;
}

fn void test_incomplete_header_timeout()
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

    String response = reader.read_response()!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 408 Request Timeout\r\n"),
        "incomplete header timeout status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n408 Request Timeout"),
        "incomplete header timeout body mismatch"
    );

    stream.close();
}

fn void test_incomplete_body_timeout()
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

    String response = reader.read_response()!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 408 Request Timeout\r\n"),
        "incomplete body timeout status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n408 Request Timeout"),
        "incomplete body timeout body mismatch"
    );

    stream.close();
}

fn void test_idle_keepalive_timeout()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String response1 = reader.read_response()!!;
    defer aio::http::localmem.free(response1);

    @assert(
        response1.contains("HTTP/1.1 200 OK\r\n"),
        "idle keepalive first status mismatch"
    );
    @assert(
        response1.contains("Connection: keep-alive\r\n"),
        "idle keepalive first connection mismatch"
    );
    @assert(
        response1.contains("\r\n\r\nhome"),
        "idle keepalive first body mismatch"
    );

    String response2 = reader.read_response()!!;
    defer aio::http::localmem.free(response2);

    @assert(
        response2.contains("HTTP/1.1 408 Request Timeout\r\n"),
        "idle keepalive timeout status mismatch"
    );
    @assert(
        response2.contains("Connection: close\r\n"),
        "idle keepalive timeout close mismatch"
    );

    stream.close();
}

fn void test_complete_request_before_timeout()
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
        "Content-Length: 5\r\n"
        "Connection: close\r\n"
        "\r\n"
        "hello"
    )!!;

    String response = reader.read_response()!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "complete request status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nhello"),
        "complete request body mismatch"
    );

    stream.close();
}

fn void? main_task(void* arg)
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::http::http_set_read_timeout_us(100_000);

    aio::spawn(&server_task, &server)!;

    aio::sleep(5_000)!;

    test_incomplete_header_timeout();
    test_incomplete_body_timeout();
    test_idle_keepalive_timeout();
    test_complete_request_before_timeout();

    aio::http::http_set_read_timeout_us(5_000_000);

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_timeout: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof