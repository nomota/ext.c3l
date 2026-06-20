// test_keepalive.c3

// Actual keep-alive and pipelining tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::keepalive;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18084;

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

fn aio::http::Response*? one_handler(aio::http::Context* c)
{
    return c.text("one")!;
}

fn aio::http::Response*? two_handler(aio::http::Context* c)
{
    return c.text("two")!;
}

fn aio::http::Response*? three_handler(aio::http::Context* c)
{
    return c.text("three")!;
}

fn aio::http::Response*? echo_handler(aio::http::Context* c)
{
    return c.text(c.req_text())!;
}

fn aio::http::Response*? id_handler(aio::http::Context* c)
{
    String id = c.param("id")!;

    return c.text(id)!;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.get("/one", &one_handler)!!;
    app.get("/two", &two_handler)!!;
    app.get("/three", &three_handler)!!;
    app.get("/id/:id", &id_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    aio::http::ApplicationServer* server =
        (aio::http::ApplicationServer*)arg;

    server.serve()!;
}

fn void test_two_requests_one_connection()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "first keep-alive status mismatch"
    );
    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "first keep-alive header mismatch"
    );
    @assert(
        r1.contains("\r\n\r\none"),
        "first keep-alive body mismatch"
    );

    stream.write_all((char[])
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    @assert(
        r2.contains("HTTP/1.1 200 OK\r\n"),
        "second keep-alive status mismatch"
    );
    @assert(
        r2.contains("Connection: close\r\n"),
        "second close header mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "second keep-alive body mismatch"
    );

    stream.close();
}

fn void test_three_requests_one_connection()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    stream.write_all((char[])
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    stream.write_all((char[])
        "GET /three HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r3 = reader.read_response()!!;
    defer aio::http::localmem.free(r3);

    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "first of three keep-alive header mismatch"
    );
    @assert(
        r1.contains("\r\n\r\none"),
        "first of three body mismatch"
    );

    @assert(
        r2.contains("Connection: keep-alive\r\n"),
        "second of three keep-alive header mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "second of three body mismatch"
    );

    @assert(
        r3.contains("Connection: close\r\n"),
        "third of three close header mismatch"
    );
    @assert(
        r3.contains("\r\n\r\nthree"),
        "third of three body mismatch"
    );

    stream.close();
}

fn void test_pipelined_two_get_requests()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "first pipelined status mismatch"
    );
    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "first pipelined keep-alive header mismatch"
    );
    @assert(
        r1.contains("\r\n\r\none"),
        "first pipelined body mismatch"
    );

    @assert(
        r2.contains("HTTP/1.1 200 OK\r\n"),
        "second pipelined status mismatch"
    );
    @assert(
        r2.contains("Connection: close\r\n"),
        "second pipelined close header mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "second pipelined body mismatch"
    );

    stream.close();
}

fn void test_pipelined_three_get_requests()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /one HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
        "GET /three HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    String r3 = reader.read_response()!!;
    defer aio::http::localmem.free(r3);

    @assert(
        r1.contains("\r\n\r\none"),
        "first pipelined three body mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "second pipelined three body mismatch"
    );
    @assert(
        r3.contains("\r\n\r\nthree"),
        "third pipelined three body mismatch"
    );

    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "first pipelined three keep-alive mismatch"
    );
    @assert(
        r2.contains("Connection: keep-alive\r\n"),
        "second pipelined three keep-alive mismatch"
    );
    @assert(
        r3.contains("Connection: close\r\n"),
        "third pipelined three close mismatch"
    );

    stream.close();
}

fn void test_pipelined_post_then_get()
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
        "\r\n"
        "hello"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "pipelined post status mismatch"
    );
    @assert(
        r1.contains("\r\n\r\nhello"),
        "pipelined post body mismatch"
    );
    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "pipelined post keep-alive mismatch"
    );

    @assert(
        r2.contains("HTTP/1.1 200 OK\r\n"),
        "pipelined get after post status mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "pipelined get after post body mismatch"
    );
    @assert(
        r2.contains("Connection: close\r\n"),
        "pipelined get after post close mismatch"
    );

    stream.close();
}

fn void test_keep_alive_with_route_params()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /id/alpha HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    stream.write_all((char[])
        "GET /id/beta HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    @assert(
        r1.contains("\r\n\r\nalpha"),
        "keep-alive route param alpha mismatch"
    );
    @assert(
        r2.contains("\r\n\r\nbeta"),
        "keep-alive route param beta mismatch"
    );

    stream.close();
}

fn void test_http10_keep_alive_request_still_closes_after_response()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /one HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.0 keep-alive status mismatch"
    );
    @assert(
        r1.contains("Connection: close\r\n"),
        "HTTP/1.0 keep-alive current close policy mismatch"
    );
    @assert(
        r1.contains("\r\n\r\none"),
        "HTTP/1.0 keep-alive body mismatch"
    );

    stream.close();
}

fn void test_pipelined_chunked_post_then_get()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer aio::http::localmem.free(r1);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "chunked pipelined post status mismatch"
    );
    @assert(
        r1.contains("\r\n\r\nWikipedia"),
        "chunked pipelined post body mismatch"
    );
    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "chunked pipelined post keep-alive mismatch"
    );

    String r2 = reader.read_response()!!;
    defer aio::http::localmem.free(r2);

    @assert(
        r2.contains("HTTP/1.1 200 OK\r\n"),
        "chunked pipelined get status mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "chunked pipelined get body mismatch"
    );
    @assert(
        r2.contains("Connection: close\r\n"),
        "chunked pipelined get close mismatch"
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

    aio::spawn(&server_task, &server)!;

    aio::sleep(SERVER_START_DELAY_US)!;

    test_two_requests_one_connection();
    test_three_requests_one_connection();

    test_pipelined_two_get_requests();
    test_pipelined_three_get_requests();
    test_pipelined_post_then_get();

    test_keep_alive_with_route_params();
    test_http10_keep_alive_request_still_closes_after_response();

    test_pipelined_chunked_post_then_get();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_keepalive: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof