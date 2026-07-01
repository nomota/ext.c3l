// test_live_multipart.c3

// Live multipart/form-data tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::live_multipart;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18085;

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
        else
        {
            if (catch err = total)
            {
                if (err != http::BODY_INCOMPLETE)
                {
                    return err~;
                }
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

    return http::BODY_INCOMPLETE~;
}

fn String? build_multipart_request(
    String path,
    String body,
    bool close = true
)
{
    return string::format(
        http::localmem,
        "POST %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=----c3test\r\n"
        "Content-Length: %d\r\n"
        "%s"
        "\r\n"
        "%s",
        path,
        body.len,
        close ? "Connection: close\r\n" : "",
        body
    );
}

fn http::Response*? field_handler(http::Context* c)
{
    String value = c.multipart_value_copy("username")!;
    defer http::localmem.free(value);

    return c.text(value)!;
}

fn http::Response*? file_handler(http::Context* c)
{
    http::MultipartPart* file = c.multipart_file("avatar")!;
    defer http::multipart_part_free(file);

    @assert(
        file.filename == "avatar.txt",
        "live multipart filename mismatch"
    );
    @assert(
        file.content_type == "text/plain",
        "live multipart content type mismatch"
    );
    @assert(
        (String)file.body == "hello file",
        "live multipart file body mismatch"
    );

    return c.text(file.filename)!;
}

fn http::Response*? mixed_handler(http::Context* c)
{
    http::MultipartForm form = c.multipart()!;
    defer form.free();

    String username = form.value("username")!;
    http::MultipartPart* file = form.file("avatar");

    @assert(
        username == "nomota",
        "live mixed username mismatch"
    );
    @assert(
        file != null,
        "live mixed file missing"
    );
    @assert(
        file.filename == "avatar.txt",
        "live mixed filename mismatch"
    );
    @assert(
        (String)file.body == "hello file",
        "live mixed file body mismatch"
    );

    return c.text("mixed ok")!;
}

fn http::Response*? two_handler(http::Context* c)
{
    return c.text("two")!;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.post("/field", &field_handler)!!;
    app.post("/file", &file_handler)!!;
    app.post("/mixed", &mixed_handler)!!;
    app.get("/two", &two_handler)!!;
}

fn void? server_task(void* arg)
{
    http::ApplicationServer* server =
        (http::ApplicationServer*)arg;

    server.serve()!;
}

fn String? request_once(String request)
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!;
    defer reader.free();

    stream.write_all((char[])request)!;

    String response = reader.read_response()!;

    stream.close();

    return response;
}

fn void test_live_multipart_field()
{
    String body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    String request = build_multipart_request("/field", body)!!;
    defer http::localmem.free(request);

    String response = request_once(request)!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "live field status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nnomota"),
        "live field body mismatch"
    );
}

fn void test_live_multipart_file()
{
    String body =
        "------c3test\r\n"
        "Content-Disposition: form-data; "
        "name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n";

    String request = build_multipart_request("/file", body)!!;
    defer http::localmem.free(request);

    String response = request_once(request)!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "live file status mismatch"
    );
    @assert(
        response.contains("\r\n\r\navatar.txt"),
        "live file body mismatch"
    );
}

fn void test_live_multipart_mixed()
{
    String body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test\r\n"
        "Content-Disposition: form-data; "
        "name=\"avatar\"; filename=\"avatar.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "hello file\r\n"
        "------c3test--\r\n";

    String request = build_multipart_request("/mixed", body)!!;
    defer http::localmem.free(request);

    String response = request_once(request)!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "live mixed status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nmixed ok"),
        "live mixed body mismatch"
    );
}

fn void test_live_multipart_keepalive_then_get()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    String body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    String request =
        build_multipart_request("/field", body, false)!!;
    defer http::localmem.free(request);

    stream.write_all((char[])request)!!;

    String r1 = reader.read_response()!!;
    defer http::localmem.free(r1);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "live keepalive multipart status mismatch"
    );
    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "live keepalive multipart header mismatch"
    );
    @assert(
        r1.contains("\r\n\r\nnomota"),
        "live keepalive multipart body mismatch"
    );

    stream.write_all((char[])
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer http::localmem.free(r2);

    @assert(
        r2.contains("HTTP/1.1 200 OK\r\n"),
        "live keepalive get status mismatch"
    );
    @assert(
        r2.contains("Connection: close\r\n"),
        "live keepalive get close mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "live keepalive get body mismatch"
    );

    stream.close();
}

fn void test_live_multipart_pipelined_then_get()
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    String body =
        "------c3test\r\n"
        "Content-Disposition: form-data; name=\"username\"\r\n"
        "\r\n"
        "nomota\r\n"
        "------c3test--\r\n";

    String request =
        build_multipart_request("/field", body, false)!!;
    defer http::localmem.free(request);

    stream.write_all((char[])request)!!;

    stream.write_all((char[])
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r1 = reader.read_response()!!;
    defer http::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer http::localmem.free(r2);

    @assert(
        r1.contains("HTTP/1.1 200 OK\r\n"),
        "live pipelined multipart status mismatch"
    );
    @assert(
        r1.contains("\r\n\r\nnomota"),
        "live pipelined multipart body mismatch"
    );
    @assert(
        r1.contains("Connection: keep-alive\r\n"),
        "live pipelined multipart keep-alive mismatch"
    );

    @assert(
        r2.contains("HTTP/1.1 200 OK\r\n"),
        "live pipelined get status mismatch"
    );
    @assert(
        r2.contains("\r\n\r\ntwo"),
        "live pipelined get body mismatch"
    );
    @assert(
        r2.contains("Connection: close\r\n"),
        "live pipelined get close mismatch"
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

    aio::sleep(SERVER_START_DELAY_US)!;

    test_live_multipart_field();
    test_live_multipart_file();
    test_live_multipart_mixed();

    test_live_multipart_keepalive_then_get();
    test_live_multipart_pipelined_then_get();

    server.close()!;
    server.wait_closed()!;

    aio::current_loop().stop()!;

    io::printfn("test_live_multipart: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof