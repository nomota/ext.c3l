// test_live_concurrent.c3

// Live concurrent client and keep-alive policy tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::live_concurrent_keepalive;

import std::io;
import ext::aio;
import ext::aiohttp;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18083;
const sz CLIENT_COUNT = 20;

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

fn bool contains(String haystack, String needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn sz find_string(String s, String needle)
{
    if (needle.len == 0) return 0;
    if (s.len < needle.len) return -1;

    for (sz i = 0; i + needle.len <= s.len; i++)
    {
        if (s[i:needle.len] == needle) return i;
    }

    return -1;
}

fn String trim(String s)
{
    sz start = 0;
    sz end = s.len;

    while (start < end && (s[start] == ' ' || s[start] == '\t'))
    {
        start++;
    }

    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t'))
    {
        end--;
    }

    return s[start:end - start];
}

fn sz? parse_decimal(String s)
{
    if (s.len == 0) return aiohttp::BAD_REQUEST~;

    sz n = 0;

    for (sz i = 0; i < s.len; i++)
    {
        char c = s[i];

        if (c < '0' || c > '9') return aiohttp::BAD_REQUEST~;

        n = n * 10 + (sz)(c - '0');
    }

    return n;
}

fn sz? response_content_length(String header_block)
{
    sz pos = 0;

    while (pos < header_block.len)
    {
        sz rel = find_string(header_block[pos..], "\r\n");

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

        sz colon = find_string(line, ":");
        if (colon <= 0) continue;

        String name = line[0:colon];
        String value = trim(line[colon + 1:line.len - colon - 1]);

        if (aiohttp::str_iequals(name, "Content-Length"))
        {
            return parse_decimal(value)!;
        }
    }

    return aiohttp::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = find_string(response, "\r\n\r\n");
    if (header_end < 0) return aiohttp::BODY_INCOMPLETE~;

    String header_block = response[0:header_end];

    sz clen = response_content_length(header_block)!;

    return header_end + 4 + clen;
}

fn String? read_response(aio::Stream* stream)
{
    DString buf;
    buf.init(aiohttp::localmem, 4096);
    defer catch buf.free();

    sz expected = -1;

    while (true)
    {
        char[1024] tmp;

        sz n = stream.read(tmp[..])!;
        if (n == 0) break;

        buf.append(tmp[0:n]);

        String text = buf.str_view();

        if (expected < 0)
        {
            sz? total = response_expected_total_len(text);
            if (try total)
            {
                expected = total;
            }
        }

        if (expected >= 0 && buf.len() >= expected)
        {
            return text.copy(aiohttp::localmem);
        }

        if (buf.len() > 1024 * 1024)
        {
            return aiohttp::REQUEST_TOO_LARGE~;
        }
    }

    if (expected >= 0 && buf.len() < expected)
    {
        return aiohttp::BODY_INCOMPLETE~;
    }

    return buf.str_view().copy(aiohttp::localmem);
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

fn aiohttp::Response*? home_handler(aiohttp::Context* c)
{
    return c.text("home")!!;
}

fn aiohttp::Response*? id_handler(aiohttp::Context* c)
{
    String id = c.param("id")!!;

    return c.text(id)!!;
}

fn aiohttp::Response*? echo_handler(aiohttp::Context* c)
{
    return c.text(c.req_text())!!;
}

fn aiohttp::Response*? slow_handler(aiohttp::Context* c)
{
    aio::sleep(10)!!;

    return c.text("slow")!!;
}

fn void setup_app(aiohttp::Application* app)
{
    app.init();

    app.get("/", &home_handler)!!;
    app.get("/id/:id", &id_handler)!!;
    app.get("/slow", &slow_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    aiohttp::Application* app = (aiohttp::Application*)arg;

    app.serve(HOST, PORT)!;
}

fn void? client_task(void* arg)
{
    ClientCase* tc = (ClientCase*)arg;

    if (catch err = run_client_case(tc))
    {
        tc.ok = false;
        tc.done = true;
        clients_done++;
        return err~;
    }

    tc.ok = true;
    tc.done = true;
    clients_done++;
}

fn void? run_client_case(ClientCase* tc)
{
    String response = request_once(tc.request)!;
    defer aiohttp::localmem.free(response);

    if (!contains(response, "HTTP/1.1 200 OK\r\n"))
    {
        return aiohttp::BAD_REQUEST~;
    }

    if (!contains(response, tc.expected_body))
    {
        return aiohttp::BAD_REQUEST~;
    }
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
            clients[i].expected_body = "\r\n\r\nhome";
        }
        else if ((i % 3) == 1)
        {
            clients[i].request =
                "GET /id/42 HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";
            clients[i].expected_body = "\r\n\r\n42";
        }
        else
        {
            clients[i].request =
                "GET /slow HTTP/1.1\r\n"
                "Host: localhost\r\n"
                "Connection: close\r\n"
                "\r\n";
            clients[i].expected_body = "\r\n\r\nslow";
        }
    }

    clients_done = 0;
}

fn void? test_concurrent_clients()
{
    setup_clients();

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        aio::spawn(&client_task, &clients[i])!;
    }

    while (clients_done < CLIENT_COUNT)
    {
        aio::sleep(1)!;
    }

    for (sz i = 0; i < CLIENT_COUNT; i++)
    {
        @assert(clients[i].done, "client should be done");
        @assert(clients[i].ok, "client should be ok");
    }
}

fn void test_http11_default_keep_alive_header()
{
    String response = request_once(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "HTTP/1.1 default status mismatch");
    @assert(contains(response, "Connection: keep-alive\r\n"), "HTTP/1.1 default keep-alive header mismatch");
    @assert(contains(response, "\r\n\r\nhome"), "HTTP/1.1 default body mismatch");
}

fn void test_http11_connection_close_header()
{
    String response = request_once(
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "HTTP/1.1 close status mismatch");
    @assert(contains(response, "Connection: close\r\n"), "HTTP/1.1 close header mismatch");
    @assert(contains(response, "\r\n\r\nhome"), "HTTP/1.1 close body mismatch");
}

fn void test_http10_default_close_header()
{
    String response = request_once(
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "HTTP/1.0 status mismatch");
    @assert(contains(response, "Connection: close\r\n"), "HTTP/1.0 default close header mismatch");
    @assert(contains(response, "\r\n\r\nhome"), "HTTP/1.0 body mismatch");
}

fn void test_http10_keep_alive_request_header()
{
    String response = request_once(
        "GET / HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "Connection: keep-alive\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "HTTP/1.0 keep-alive status mismatch");
    @assert(contains(response, "Connection: close\r\n"), "HTTP/1.0 keep-alive current policy mismatch");
    @assert(contains(response, "\r\n\r\nhome"), "HTTP/1.0 keep-alive body mismatch");
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
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "POST echo status mismatch");
    @assert(contains(response, "\r\n\r\nhello"), "POST echo body mismatch");
}

fn void? main_task(void* arg)
{
    aiohttp::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::spawn(&server_task, &app)!;

    aio::sleep(100)!;

    test_concurrent_clients()!;

    test_http11_default_keep_alive_header();
    test_http11_connection_close_header();
    test_http10_default_close_header();
    test_http10_keep_alive_request_header();

    test_post_concurrent_path_still_works();

    aio::current_loop().stop()!;

    io::printfn("test_live_concurrent_keepalive: OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof