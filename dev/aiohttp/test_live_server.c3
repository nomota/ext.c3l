// test_live_server.c3

// Live TCP server tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::live_server;

import std::io;
import ext::aio;
import ext::aiohttp;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18080;

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

fn aiohttp::Response*? home_handler(aiohttp::Context* c)
{
    return c.text("home")!!;
}

fn aiohttp::Response*? echo_handler(aiohttp::Context* c)
{
    return c.text(c.req_text())!!;
}

fn aiohttp::Response*? user_handler(aiohttp::Context* c)
{
    String id = c.param("id")!!;

    return c.text(id)!!;
}

fn aiohttp::Response*? query_handler(aiohttp::Context* c)
{
    String q = c.query("q")!!;

    return c.text(q)!!;
}

fn aiohttp::Response*? cookie_handler(aiohttp::Context* c)
{
    c.cookie_set_default("sid", "abc")!!;

    return c.text("cookie")!!;
}

fn aiohttp::Response*? middleware_header(aiohttp::Context* c, aiohttp::Next next)
{
    aiohttp::Response* res = next(c)!!;

    c.header("X-Live-Test", "yes")!!;

    return res;
}

fn void setup_app(aiohttp::Application* app)
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
    aiohttp::Application* app = (aiohttp::Application*)arg;

    app.serve(HOST, PORT)!;
}

fn aio::Stream*? connect_client()
{
    return aio::stream_connect(HOST, PORT)!;
}

fn String? read_response(aio::Stream* stream)
{
    DString buf;
    buf.init(aiohttp::localmem, 4096);
    defer catch buf.free();

    while (true)
    {
        char[1024] tmp;

        sz n = stream.read(tmp[..])!;
        if (n == 0) break;

        buf.append(tmp[0:n]);

        String text = buf.str_view();

        if (contains(text, "\r\n\r\n"))
        {
            sz? total = response_expected_total_len(text);
            if (try total)
            {
                if (buf.len() >= total)
                {
                    return text.copy(aiohttp::localmem);
                }
            }
        }

        if (buf.len() > 1024 * 1024)
        {
            return aiohttp::REQUEST_TOO_LARGE~;
        }
    }

    return buf.str_view().copy(aiohttp::localmem);
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
        sz line_end = find_string(header_block[pos..], "\r\n");
        if (line_end < 0) break;

        String line = header_block[pos:line_end];

        sz colon = find_string(line, ":");
        if (colon > 0)
        {
            String name = line[0:colon];
            String value = trim(line[colon + 1:line.len - colon - 1]);

            if (aiohttp::str_iequals(name, "Content-Length"))
            {
                return parse_decimal(value)!;
            }
        }

        pos += line_end + 2;
    }

    return aiohttp::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end = find_string(response, "\r\n\r\n");
    if (header_end < 0) return aiohttp::BODY_INCOMPLETE~;

    String header_block = response[0:header_end];

    sz? clen = response_content_length(header_block);
    if (catch err = clen)
    {
        return header_end + 4;
    }

    return header_end + 4 + clen;
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
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "GET / status mismatch");
    @assert(contains(response, "Content-Length: 4\r\n"), "GET / content length mismatch");
    @assert(contains(response, "X-Live-Test: yes\r\n"), "middleware header missing");
    @assert(contains(response, "\r\n\r\nhome"), "GET / body mismatch");
}

fn void test_live_param()
{
    String response = request_once(
        "GET /users/kim%20lee HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "param status mismatch");
    @assert(contains(response, "\r\n\r\nkim lee"), "param body mismatch");
}

fn void test_live_query()
{
    String response = request_once(
        "GET /query?q=hello+world HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "query status mismatch");
    @assert(contains(response, "\r\n\r\nhello world"), "query body mismatch");
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
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "POST echo status mismatch");
    @assert(contains(response, "\r\n\r\nhello"), "POST echo body mismatch");
}

fn void test_live_cookie()
{
    String response = request_once(
        "GET /cookie HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "cookie status mismatch");
    @assert(contains(response, "Set-Cookie: sid=abc; Path=/; SameSite=Lax\r\n"), "set-cookie missing");
    @assert(contains(response, "\r\n\r\ncookie"), "cookie body mismatch");
}

fn void test_live_404()
{
    String response = request_once(
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 404 Not Found\r\n"), "404 status mismatch");
    @assert(contains(response, "\r\n\r\n404 Not Found"), "404 body mismatch");
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
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 405 Method Not Allowed\r\n"), "405 status mismatch");
    @assert(contains(response, "\r\n\r\n405 Method Not Allowed"), "405 body mismatch");
}

fn void test_live_bad_request()
{
    String response = request_once(
        "BAD_REQUEST_LINE\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 400 Bad Request\r\n"), "bad request status mismatch");
    @assert(contains(response, "\r\n\r\n400 Bad Request"), "bad request body mismatch");
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
        defer aiohttp::localmem.free(response);

        @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "sequential client status mismatch");
        @assert(contains(response, "\r\n\r\nhome"), "sequential client body mismatch");
    }
}

fn void? main_task(void* arg)
{
    aiohttp::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::spawn(&server_task, &app)!;

    aio::sleep(100)!;

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
    aio::run(&main_task);
}

// eof