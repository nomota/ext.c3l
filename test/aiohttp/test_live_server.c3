// test_live_server.c3

// Live TCP server tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::live_server;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18080;

fn http::Response*? home_handler(http::Context* c)
{
    return c.text("home")!;
}

fn http::Response*? echo_handler(http::Context* c)
{
    return c.text(c.req_text())!;
}

fn http::Response*? user_handler(http::Context* c)
{
    String id = c.param("id")!;

    return c.text(id)!;
}

fn http::Response*? query_handler(http::Context* c)
{
    String q = c.query("q")!;

    return c.text(q)!;
}

fn http::Response*? cookie_handler(http::Context* c)
{
    c.cookie_set_default("sid", "abc")!;

    return c.text("cookie")!;
}

fn http::Response*? middleware_header(
    http::Context* c,
    http::Next next
)
{
    http::Response* res = next(c)!;

    c.header("X-Live-Test", "yes")!;

    return res;
}

fn void setup_app(http::Application* app)
{
    app.init();

    app.use(&middleware_header);
    app.get("/", &home_handler)!!;
    app.get("/users/:id", &user_handler)!!;
    app.get("/query", &query_handler)!!;
    app.get("/cookie", &cookie_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    http::Application* app = (http::Application*)arg;

    app.serve(HOST, PORT)!;
}

fn aio::Stream*? connect_client()
{
    return aio::stream_connect(HOST, PORT)!;
}

fn sz? response_content_length(String header_block)
{
    sz pos = 0;

    while (pos < header_block.len)
    {
        sz line_end = header_block[pos..].index_of("\r\n") ?? -1;

        String line;

        if (line_end < 0)
        {
            line = header_block[pos:header_block.len - pos];
            pos = header_block.len;
        }
        else
        {
            line = header_block[pos:line_end];
            pos += line_end + 2;
        }

        if (line.len == 0) continue;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) continue;

        String name = line[0:colon];
        String value = line[colon + 1:line.len - colon - 1].trim();

        if (http::str_iequals(name, "Content-Length"))
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

fn String? read_response(aio::Stream* stream)
{
    if (stream == null) return http::BAD_REQUEST~;

    DString buf;
    buf.init(http::localmem, 4096);
    defer buf.free();

    while (true)
    {
        char[1024] tmp;

        sz n = stream.read(tmp[..])!;
        if (n == 0) break;

        buf.append(tmp[0:n]);

        String text = buf.str_view();

        sz? total = response_expected_total_len(text);

        if (try total)
        {
            if (buf.len() >= total)
            {
                return text[0:total].copy(http::localmem);
            }
        }

        if (buf.len() > 1024 * 1024)
        {
            return http::REQUEST_TOO_LARGE~;
        }
    }

    return buf.str_view().copy(http::localmem);
}

fn String? request_once(String request)
{
    aio::Stream* stream = connect_client()!;
    defer stream.free();

    stream.write_all((char[])request)!;

    String response = read_response(stream)!;

    stream.close();

    return response;
}

fn void test_live_get_root()
{
    String response = request_once(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "GET / status mismatch"
    );
    @assert(
        response.contains("Content-Length: 4\r\n"),
        "GET / content length mismatch"
    );
    @assert(
        response.contains("X-Live-Test: yes\r\n"),
        "middleware header missing"
    );
    @assert(
        response.contains("\r\n\r\nhome"),
        "GET / body mismatch"
    );
}

fn void test_live_param()
{
    String response = request_once(
        "GET /users/kim%20lee HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "param status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nkim lee"),
        "param body mismatch"
    );
}

fn void test_live_query()
{
    String response = request_once(
        "GET /query?q=hello+world HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "query status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nhello world"),
        "query body mismatch"
    );
}

fn void test_live_post_echo()
{
    String response = request_once(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 5\r\n"
        "Connection: close\r\n"
        "\r\n"
        "hello"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "POST echo status mismatch"
    );
    @assert(
        response.contains("\r\n\r\nhello"),
        "POST echo body mismatch"
    );
}

fn void test_live_cookie()
{
    String response = request_once(
        "GET /cookie HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "cookie status mismatch"
    );
    @assert(
        response.contains(
            "Set-Cookie: sid=abc; Path=/; SameSite=Lax\r\n"
        ),
        "set-cookie missing"
    );
    @assert(
        response.contains("\r\n\r\ncookie"),
        "cookie body mismatch"
    );
}

fn void test_live_404()
{
    String response = request_once(
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 404 Not Found\r\n"),
        "404 status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n404 Not Found"),
        "404 body mismatch"
    );
}

fn void test_live_405()
{
    String response = request_once(
        "POST / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 0\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 405 Method Not Allowed\r\n"),
        "405 status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n405 Method Not Allowed"),
        "405 body mismatch"
    );
}

fn void test_live_bad_request()
{
    String response = request_once(
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 400 Bad Request\r\n"),
        "bad request status mismatch"
    );
    @assert(
        response.contains("\r\n\r\n400 Bad Request"),
        "bad request body mismatch"
    );
}

fn void test_live_sequential_clients()
{
    for (sz i = 0; i < 5; i++)
    {
        String response = request_once(
            "GET / HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Connection: close\r\n"
            "\r\n"
        )!!;

        @assert(
            response.contains("HTTP/1.1 200 OK\r\n"),
            "sequential client status mismatch"
        );
        @assert(
            response.contains("\r\n\r\nhome"),
            "sequential client body mismatch"
        );

        http::localmem.free(response);
    }
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


fn void? main_task(void* arg)
{
    http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::spawn(&server_task, &app)!;

    wait_server_ready()!;

    test_live_get_root();
    test_live_param();
    test_live_query();
    test_live_post_echo();
    test_live_cookie();
    test_live_404();
    test_live_405();
    test_live_bad_request();
    test_live_sequential_clients();

    aio::current_loop().stop()!;

    io::printfn("test_live_server: OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof