// test_live_concurrent.c3

// Live concurrent client and keep-alive policy tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::live_concurrent_keepalive;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18083;
const sz CLIENT_COUNT = 20;
const sz MAX_RESPONSE_BYTES = 1024 * 1024;

struct ClientCase
{
    sz id;
    String request;
    String expected_body;
    bool done;
    bool ok;
}

ClientCase[CLIENT_COUNT] clients;
sz clients_done = 0;

fn sz? response_content_length(String header_block)
{
    sz pos = 0;

    while (pos < header_block.len)
    {
        sz rel =
            header_block[pos..].index_of("\r\n") ?? -1;

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

        if (!aio::http::str_iequals(name, "Content-Length"))
        {
            continue;
        }

        sz content_length = value.to_long()!;
        if (content_length < 0) return aio::http::BAD_REQUEST~;

        return content_length;
    }

    return aio::http::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = response.index_of("\r\n\r\n") ?? -1;
    if (header_end < 0) return aio::http::BODY_INCOMPLETE~;

    String header_block = response[0:header_end];

    sz content_length =
        response_content_length(header_block)!;

    if (content_length > MAX_RESPONSE_BYTES)
    {
        return aio::http::REQUEST_TOO_LARGE~;
    }

    sz total = header_end + 4 + content_length;

    if (total < header_end)
    {
        return aio::http::REQUEST_TOO_LARGE~;
    }

    return total;
}

fn String? read_response(aio::Stream* stream)
{
    if (stream == null) return aio::http::BAD_REQUEST~;

    DString buf;
    buf.init(aio::http::localmem, 4096);
    defer buf.free();

    sz expected = -1;

    while (true)
    {
        char[1024] tmp;

        sz n = stream.read(tmp[..])!;
        if (n == 0) break;

        buf.append(tmp[0:n]);

        if (buf.len() > MAX_RESPONSE_BYTES)
        {
            return aio::http::REQUEST_TOO_LARGE~;
        }

        String response = buf.str_view();

        if (expected < 0)
        {
            sz? total =
                response_expected_total_len(response);

            if (try total)
            {
                expected = total;

                if (expected > MAX_RESPONSE_BYTES)
                {
                    return aio::http::REQUEST_TOO_LARGE~;
                }
            }
        }

        if (expected >= 0 && buf.len() >= expected)
        {
            return response[0:expected].copy(
                aio::http::localmem
            );
        }
    }

    if (expected < 0)
    {
        return aio::http::BODY_INCOMPLETE~;
    }

    if (buf.len() < expected)
    {
        return aio::http::BODY_INCOMPLETE~;
    }

    return buf.str_view()[0:expected].copy(
        aio::http::localmem
    );
}

fn String? request_once(String request)
{
    aio::Stream* stream =
        aio::stream_connect(HOST, PORT)!;
    defer stream.free();

    stream.write_all((char[])request)!;

    String response = read_response(stream)!;

    stream.close();

    return response;
}

fn aio::http::Response*? home_handler(aio::http::Context* c)
{
    return c.text("home")!!;
}

fn aio::http::Response*? id_handler(aio::http::Context* c)
{
    String id = c.param("id")!!;

    return c.text(id)!!;
}

fn aio::http::Response*? echo_handler(aio::http::Context* c)
{
    return c.text(c.req_text())!!;
}

fn aio::http::Response*? slow_handler(aio::http::Context* c)
{
    aio::sleep(100)!;

    return c.text("slow")!!;
}

fn void setup_app(aio::http::Application* app)
{
    app.init();

    app.get("/", &home_handler)!!;
    app.get("/id/:id", &id_handler)!!;
    app.get("/slow", &slow_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    aio::http::Application* app =
        (aio::http::Application*)arg;

    app.serve(HOST, PORT)!;
}

fn void? run_client_case(ClientCase* tc)
{
    String response = request_once(tc.request)!;
    defer aio::http::localmem.free(response);

    if (!response.contains("HTTP/1.1 200 OK\r\n"))
    {
        warn(
            "client %d: status mismatch\n%s",
            tc.id,
            response
        );

        return aio::http::BAD_REQUEST~;
    }

    if (!response.contains(tc.expected_body))
    {
        warn(
            "client %d: body mismatch, expected=%s\n%s",
            tc.id,
            tc.expected_body,
            response
        );

        return aio::http::BAD_REQUEST~;
    }
}

fn void? client_task(void* arg)
{
    ClientCase* tc = (ClientCase*)arg;

    tc.ok = true;

    if (catch err = run_client_case(tc))
    {
        warn(
            "client %d failed: %s",
            tc.id,
            err
        );

        tc.ok = false;
    }

    tc.done = true;
    clients_done++;
}

fn void setup_clients()
{
    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        clients[i].id = i;
        clients[i].done = false;
        clients[i].ok = false;

        if ((i % 3) == 0)
        {
            clients[i].request =
                "GET / HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            clients[i].expected_body =
                "\r\n\r\nhome";
        }
        else if ((i % 3) == 1)
        {
            clients[i].request =
                "GET /id/42 HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            clients[i].expected_body =
                "\r\n\r\n42";
        }
        else
        {
            clients[i].request =
                "GET /slow HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";

            clients[i].expected_body =
                "\r\n\r\nslow";
        }
    }

    clients_done = 0;
}

fn void? test_concurrent_clients()
{
    setup_clients();

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        aio::spawn(
            &client_task,
            &clients[i]
        )!;
    }

    while (clients_done < CLIENT_COUNT)
    {
        aio::sleep(1)!;
    }

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        @assert(
            clients[i].done,
            "client should be done"
        );

        @assert(
            clients[i].ok,
            "client should be ok"
        );
    }
}

fn void test_http11_default_keep_alive_header()
{
    String response = request_once(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.1 default status mismatch"
    );

    @assert(
        response.contains(
            "Connection: keep-alive\r\n"
        ),
        "HTTP/1.1 default keep-alive header mismatch"
    );

    @assert(
        response.contains("\r\n\r\nhome"),
        "HTTP/1.1 default body mismatch"
    );
}

fn void test_http11_connection_close_header()
{
    String response = request_once(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.1 close status mismatch"
    );

    @assert(
        response.contains("Connection: close\r\n"),
        "HTTP/1.1 close header mismatch"
    );

    @assert(
        response.contains("\r\n\r\nhome"),
        "HTTP/1.1 close body mismatch"
    );
}

fn void test_http10_default_close_header()
{
    String response = request_once(
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.0 status mismatch"
    );

    @assert(
        response.contains("Connection: close\r\n"),
        "HTTP/1.0 default close header mismatch"
    );

    @assert(
        response.contains("\r\n\r\nhome"),
        "HTTP/1.0 body mismatch"
    );
}

fn void test_http10_keep_alive_request_header()
{
    String response = request_once(
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
    )!!;
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "HTTP/1.0 keep-alive status mismatch"
    );

    @assert(
        response.contains("Connection: close\r\n"),
        "HTTP/1.0 keep-alive current policy mismatch"
    );

    @assert(
        response.contains("\r\n\r\nhome"),
        "HTTP/1.0 keep-alive body mismatch"
    );
}

fn void test_post_concurrent_path_still_works()
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
    defer aio::http::localmem.free(response);

    @assert(
        response.contains("HTTP/1.1 200 OK\r\n"),
        "POST echo status mismatch"
    );

    @assert(
        response.contains("\r\n\r\nhello"),
        "POST echo body mismatch"
    );
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
    aio::http::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::spawn(&server_task, &app)!;

    wait_server_ready()!;

    test_concurrent_clients()!;

    test_http11_default_keep_alive_header();
    test_http11_connection_close_header();
    test_http10_default_close_header();
    test_http10_keep_alive_request_header();

    test_post_concurrent_path_still_works();

    aio::current_loop().stop()!;

    io::printfn("test_live_concurrent: OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof