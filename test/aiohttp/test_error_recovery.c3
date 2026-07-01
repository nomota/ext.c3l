// test_error_recovery.c3

// Error recovery tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::error_recovery;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18097;

const sz MAX_RESPONSE_BYTES = 1024 * 1024;
const ulong RESPONSE_TIMEOUT_US = 2_000_000;
const ulong SERVER_RETRY_DELAY_US = 10_000;
const sz SERVER_READY_RETRIES = 200;
const sz RECOVERY_TEST_COUNT = 20;


fn sz count_occurrences(String text, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= text.len)
    {
        sz idx = text[pos..].index_of(needle) ?? -1;
        if (idx < 0) break;

        count++;
        pos += idx + needle.len;
    }

    return count;
}

fn String body_part(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;
    if (header_end < 0) return "";

    return response[header_end + 4..];
}

fn bool status_is(String response, ushort status)
{
    char[64] buf;
    String prefix = string::bformat(
        buf[..],
        "HTTP/1.1 %d ",
        status
    );

    return response.starts_with(prefix);
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
            line = header_block[pos..];
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
        String value = line[colon + 1..].trim();

        if (!http::str_iequals(name, "Content-Length"))
        {
            continue;
        }

        sz length = value.to_long()!;
        if (length < 0) return http::BAD_REQUEST~;

        return length;
    }

    return http::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;
    if (header_end < 0) return http::BODY_INCOMPLETE~;

    String header_block = response[0:header_end];

    sz? content_length = response_content_length(header_block);

    if (catch err = content_length)
    {
        return header_end + 4;
    }

    return header_end + 4 + content_length;
}

fn String? read_response(aio::Stream* stream)
{
    DString buffer;
    buffer.init(http::localmem, 4096);
    defer catch buffer.free();

    char[1024] tmp;

    while (true)
    {
        String current = buffer.str_view();

        sz? expected = response_expected_total_len(current);

        if (try expected)
        {
            if (buffer.len() >= expected)
            {
                return current[0:expected].copy(
                    http::localmem
                );
            }
        }

        if (buffer.len() > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        sz? n = stream.read_timeout(
            tmp[..],
            RESPONSE_TIMEOUT_US
        );

        if (catch err = n)
        {
            current = buffer.str_view();

            sz? final_expected =
                response_expected_total_len(current);

            if (try final_expected)
            {
                if (buffer.len() >= final_expected)
                {
                    return current[0:final_expected].copy(
                        http::localmem
                    );
                }
            }

            return err~;
        }

        if (n == 0) break;

        buffer.append(tmp[0:n]);
    }

    if (buffer.len() == 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    String current = buffer.str_view();

    sz? expected = response_expected_total_len(current);

    if (try expected)
    {
        if (buffer.len() >= expected)
        {
            return current[0:expected].copy(
                http::localmem
            );
        }
    }

    return http::BODY_INCOMPLETE~;
}

fn String? request_once(String request)
{
    aio::Stream* stream = aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    stream.write_all((char[])request)!;

    String response = read_response(stream)!;

    stream.close();

    return response;
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < SERVER_READY_RETRIES; i++)
    {
        aio::Stream*? stream = aio::stream_connect(
            HOST,
            PORT
        );

        if (catch err = stream)
        {
            aio::sleep(SERVER_RETRY_DELAY_US)!;
            continue;
        }

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void wake_server()
{
    aio::Stream*? stream = aio::stream_connect(HOST, PORT);

    if (catch err = stream)
    {
        return;
    }

    stream.close();
    stream.free();
}


// Response reader

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

    char[1024] tmp;

    while (true)
    {
        String current = self.buffer.str_view();

        sz? expected = response_expected_total_len(current);

        if (try expected)
        {
            if (self.buffer.len() >= expected)
            {
                String response = current[0:expected].copy(
                    http::localmem
                );

                self.consume(expected);

                return response;
            }
        }

        if (self.buffer.len() > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        sz? n = self.stream.read_timeout(
            tmp[..],
            RESPONSE_TIMEOUT_US
        );

        if (catch err = n)
        {
            current = self.buffer.str_view();

            sz? final_expected =
                response_expected_total_len(current);

            if (try final_expected)
            {
                if (self.buffer.len() >= final_expected)
                {
                    String response =
                        current[0:final_expected].copy(
                            http::localmem
                        );

                    self.consume(final_expected);

                    return response;
                }
            }

            return err~;
        }

        if (n == 0) break;

        self.buffer.append(tmp[0:n]);
    }

    if (self.buffer.len() == 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    String current = self.buffer.str_view();

    sz? expected = response_expected_total_len(current);

    if (try expected)
    {
        if (self.buffer.len() >= expected)
        {
            String response = current[0:expected].copy(
                http::localmem
            );

            self.consume(expected);

            return response;
        }
    }

    return http::BODY_INCOMPLETE~;
}


// Handlers

fn http::Response*? ok_handler(http::Context* c)
{
    return c.text("ok")!;
}

fn http::Response*? fault_handler(
    http::Context* c
)
{
    return http::BAD_REQUEST~;
}

fn http::Response*? fault_500_handler(
    http::Context* c
)
{
    return http::STATIC_READ_ERROR~;
}

fn http::Response*? middleware_fault(
    http::Context* c,
    http::Next next
)
{
    return http::BAD_REQUEST~;
}

fn http::Response*? middleware_fault_after(
    http::Context* c,
    http::Next next
)
{
    http::Response* response = next(c)!;

    @assert(
        response != null,
        "middleware after fault test missing response"
    );

    return http::BAD_REQUEST~;
}


// Application and server

fn void? setup_app(http::Application* app)
{
    app.init();

    app.get("/ok", &ok_handler)!;
    app.get("/fault", &fault_handler)!;
    app.get("/fault500", &fault_500_handler)!;
}

fn void? server_task(void* arg)
{
    http::ApplicationServer* server =
        (http::ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
}


// Tests

fn void test_ok_before_errors()
{
    String response = request_once(
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        status_is(response, 200),
        "ok before errors status mismatch"
    );
    @assert(
        body_part(response) == "ok",
        "ok before errors body mismatch"
    );
}

fn void test_handler_fault_returns_error()
{
    String response = request_once(
        "GET /fault HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        status_is(response, 400) ||
        status_is(response, 500),
        "handler fault status mismatch"
    );
}

fn void test_handler_fault500_returns_500()
{
    String response = request_once(
        "GET /fault500 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        status_is(response, 500),
        "handler fault500 status mismatch"
    );
}

fn void test_server_recovers_after_handler_fault()
{
    test_handler_fault_returns_error();

    String response = request_once(
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        status_is(response, 200),
        "server recovery after handler fault status mismatch"
    );
    @assert(
        body_part(response) == "ok",
        "server recovery after handler fault body mismatch"
    );
}

fn void test_bad_request_then_new_client_ok()
{
    String bad = request_once(
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(bad);

    @assert(
        status_is(bad, 400),
        "bad request status mismatch"
    );

    String good = request_once(
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(good);

    @assert(
        status_is(good, 200),
        "new client after bad request status mismatch"
    );
    @assert(
        body_part(good) == "ok",
        "new client after bad request body mismatch"
    );
}

fn void test_malformed_second_pipelined_request()
{
    aio::Stream* stream = aio::stream_connect(
        HOST,
        PORT
    )!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String first = reader.read_response()!!;
    defer http::localmem.free(first);

    String second = reader.read_response()!!;
    defer http::localmem.free(second);

    @assert(
        status_is(first, 200),
        "pipelined first good status mismatch"
    );
    @assert(
        body_part(first) == "ok",
        "pipelined first good body mismatch"
    );
    @assert(
        status_is(second, 400),
        "pipelined malformed second status mismatch"
    );

    stream.close();
}

fn void test_first_pipelined_fault_then_server_recovers()
{
    aio::Stream* stream = aio::stream_connect(
        HOST,
        PORT
    )!!;
    defer stream.free();

    ResponseReader reader;
    reader.init(stream)!!;
    defer reader.free();

    stream.write_all((char[])
        "GET /fault HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String first = reader.read_response()!!;
    defer http::localmem.free(first);

    @assert(
        status_is(first, 400) ||
        status_is(first, 500),
        "pipelined first fault status mismatch"
    );

    stream.close();

    String good = request_once(
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(good);

    @assert(
        status_is(good, 200),
        "server after pipelined fault status mismatch"
    );
    @assert(
        body_part(good) == "ok",
        "server after pipelined fault body mismatch"
    );
}

fn void test_middleware_fault_fetch_raw()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_fault);
    app.get("/ok", &ok_handler)!!;

    http::Response* response = app.fetch_raw((char[])
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(response);

    @assert(
        response.status == 400 ||
        response.status == 500,
        "middleware fault fetch_raw status mismatch"
    );
}

fn void test_middleware_after_fault_fetch_raw()
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_fault_after);
    app.get("/ok", &ok_handler)!!;

    http::Response* response = app.fetch_raw((char[])
        "GET /ok HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer http::response_free(response);

    @assert(
        response.status == 400 ||
        response.status == 500,
        "middleware after fault fetch_raw status mismatch"
    );
}

fn void test_many_recoveries()
{
    for (sz i = 0; i < RECOVERY_TEST_COUNT; i++)
    {
        String bad = request_once(
            "BAD_REQUEST_LINE\r\n"
            "Host: localhost\r\n"
            "Connection: close\r\n"
            "\r\n"
        )!!;

        @assert(
            status_is(bad, 400),
            "many recoveries bad status mismatch"
        );

        http::localmem.free(bad);

        String good = request_once(
            "GET /ok HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Connection: close\r\n"
            "\r\n"
        )!!;

        @assert(
            status_is(good, 200),
            "many recoveries good status mismatch"
        );
        @assert(
            body_part(good) == "ok",
            "many recoveries good body mismatch"
        );

        http::localmem.free(good);
    }
}


// Main

fn void? main_task(void* arg)
{
    http::Application app;
    setup_app(&app)!;
    defer app.deinit();

    http::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_ok_before_errors();
    test_server_recovers_after_handler_fault();
    test_handler_fault500_returns_500();

    test_bad_request_then_new_client_ok();
    test_malformed_second_pipelined_request();
    test_first_pipelined_fault_then_server_recovers();

    test_many_recoveries();

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    test_middleware_fault_fetch_raw();
    test_middleware_after_fault_fetch_raw();

    io::printfn("test_error_recovery: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof