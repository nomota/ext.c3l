// test_shutdown.c3

// ApplicationServer shutdown tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::shutdown;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18086;

const usz SERVER_START_DELAY_US = 100_000;
const sz MAX_RESPONSE_BYTES = 1024 * 1024;

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
    sz content_length = response_content_length(header_block)!;

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
        else
        {
            if (catch err = total)
            {
                if (err != aio::http::BODY_INCOMPLETE)
                {
                    return err~;
                }
            }
        }

        if (self.buffer.len() > MAX_RESPONSE_BYTES)
        {
            return aio::http::REQUEST_TOO_LARGE~;
        }

        char[1024] tmp;

        sz n = self.stream.read(tmp[..])!;

        if (n == 0) break;

        self.buffer.append(tmp[0:n]);
    }

    return aio::http::BODY_INCOMPLETE~;
}

fn aio::http::Response*? home_handler(aio::http::Context* c)
{
    return c.text("home")!;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.get("/", &home_handler)!!;
}

fn void? server_task(void* arg)
{
    aio::http::ApplicationServer* server =
        (aio::http::ApplicationServer*)arg;

    server.serve()!;
}

fn String? request_once()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!;
    defer reader.free();

    stream.write_all((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;

    String response = reader.read_response()!;

    stream.close();

    return response;
}

fn void test_close_before_serve_is_safe()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::ApplicationServer server;
    server.init(&app, HOST, 18087);
    defer server.free();

    server.close()!!;
    server.close()!!;

    server.wait_closed()!!;
    server.wait_closed()!!;

    @assert(
        server.closed,
        "close before serve closed mismatch"
    );
    @assert(
        server.waited,
        "close before serve waited mismatch"
    );
}

fn void test_free_without_explicit_close_is_safe()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::ApplicationServer* server =
        aio::http::http_server_new(&app, HOST, 18088)!!;

    server.close()!!;
    server.wait_closed()!!;

    aio::http::http_server_free(server);
}

fn void test_live_close_wait_closed()
{
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!!;

    aio::sleep(SERVER_START_DELAY_US)!!;

    String response = request_once()!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "shutdown live status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nhome"),
        "shutdown live body mismatch"
    );

    server.close()!!;
    server.close()!!;

    server.wait_closed()!!;
    server.wait_closed()!!;

    @assert(
        server.closed,
        "live close closed mismatch"
    );
    @assert(
        server.waited,
        "live close waited mismatch"
    );
}

fn void? main_task(void* arg)
{
    test_close_before_serve_is_safe();
    test_free_without_explicit_close_is_safe();
    test_live_close_wait_closed();

    aio::current_loop().stop()!;

    io::printfn("test_shutdown: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof