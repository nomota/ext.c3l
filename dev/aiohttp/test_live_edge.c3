// test_live_edge.c3

// Live server edge tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::live_server_edge;

import std::io;
import ext::aio;
import ext::aiohttp;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18082;

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

    sz? clen = response_content_length(header_block);
    if (catch err = clen)
    {
        return header_end + 4;
    }

    return header_end + 4 + clen;
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
//warn("n %d", n);
        buf.append(tmp[0:n]);
//warn("buf.len() %d", buf.len());
        String text = buf.str_view();

        sz? total = response_expected_total_len(text);
        if (try total)
        {
//warn("total %d", total);
            if (buf.len() >= total)
            {
                return text.copy(aiohttp::localmem);
            }
        }

        if (buf.len() > 2 * 1024 * 1024)
        {
            return aiohttp::REQUEST_TOO_LARGE~;
        }
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

fn aiohttp::Response*? small_handler(aiohttp::Context* c)
{
    return c.text("small")!!;
}

fn aiohttp::Response*? large_handler(aiohttp::Context* c)
{
    DString body;
    body.init(aiohttp::localmem, 64 * 1024);
    defer body.free();

    for (sz i = 0; i < 64 * 1024; i++)
    {
        body.append((char[])"x");
    }
//warn("%d", body.len());
    return c.text(body.str_view())!!;
}

fn aiohttp::Response*? empty_handler(aiohttp::Context* c)
{
    return c.empty();
}

fn aiohttp::Response*? close_header_handler(aiohttp::Context* c)
{
    c.header("Connection", "close")!!;
    return c.text("close")!!;
}

fn aiohttp::Response*? status_204_handler(aiohttp::Context* c)
{
    c.status(204)!!;
    return c.empty();
}

fn aiohttp::Response*? echo_handler(aiohttp::Context* c)
{
    return c.text(c.req_text())!!;
}

fn void setup_app(aiohttp::Application* app)
{
    app.init();

    app.get("/small", &small_handler)!!;
    app.get("/large", &large_handler)!!;
    app.get("/empty", &empty_handler)!!;
    app.get("/close", &close_header_handler)!!;
    app.get("/no-content", &status_204_handler)!!;
    app.post("/echo", &echo_handler)!!;
}

fn void? server_task(void* arg)
{
    aiohttp::Application* app = (aiohttp::Application*)arg;

    app.serve(HOST, PORT)!;
}

fn void test_small_response()
{
    String response = request_once(
        "GET /small HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "small response status mismatch");
    @assert(contains(response, "Content-Length: 5\r\n"), "small response content length mismatch");
    @assert(contains(response, "\r\n\r\nsmall"), "small response body mismatch");
}

fn void test_large_response()
{
    String response = request_once(
        "GET /large HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "large response status mismatch");
    @assert(contains(response, "Content-Length: 65536\r\n"), "large response content length mismatch");

    sz sep = find_string(response, "\r\n\r\n");
//warn("%d", sep);
    @assert(sep >= 0, "large response missing header separator");

    String body = response[sep + 4:response.len - sep - 4];
//warn("%d", body.len);
    @assert(body.len == 65536, "large response body length mismatch");
    @assert(body[0] == 'x', "large response first byte mismatch");
    @assert(body[body.len - 1] == 'x', "large response last byte mismatch");
}

fn void test_empty_response()
{
    String response = request_once(
        "GET /empty HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "empty response status mismatch");
    @assert(contains(response, "Content-Length: 0\r\n"), "empty response content length mismatch");
    @assert(contains(response, "\r\n\r\n"), "empty response separator missing");

    sz sep = find_string(response, "\r\n\r\n");
    String body = response[sep + 4:response.len - sep - 4];

    @assert(body.len == 0, "empty response body should be empty");
}

fn void test_no_content_response()
{
    String response = request_once(
        "GET /no-content HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 204 No Content\r\n"), "204 status mismatch");
    @assert(contains(response, "Content-Length: 0\r\n"), "204 content length mismatch");

    sz sep = find_string(response, "\r\n\r\n");
    String body = response[sep + 4:response.len - sep - 4];

    @assert(body.len == 0, "204 response body should be empty");
}

fn void test_connection_close_response_header()
{
    String response = request_once(
        "GET /close HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "close header status mismatch");
    @assert(contains(response, "Connection: close\r\n"), "close header missing");
    @assert(contains(response, "\r\n\r\nclose"), "close header body mismatch");
}

fn void test_http10_default_close()
{
    String response = request_once(
        "GET /small HTTP/1.0\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "HTTP/1.0 status mismatch");
    @assert(contains(response, "Connection: close\r\n"), "HTTP/1.0 should close by default");
    @assert(contains(response, "\r\n\r\nsmall"), "HTTP/1.0 body mismatch");
}

fn void test_http11_default_keep_alive_header()
{
    String response = request_once(
        "GET /small HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "HTTP/1.1 status mismatch");
    @assert(contains(response, "Connection: keep-alive\r\n"), "HTTP/1.1 keep-alive header mismatch");
    @assert(contains(response, "\r\n\r\nsmall"), "HTTP/1.1 body mismatch");
}

fn void test_invalid_content_length_returns_400()
{
    String response = request_once(
        "POST /echo HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: abc\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 400 Bad Request\r\n"), "invalid content length status mismatch");
    @assert(contains(response, "\r\n\r\n400 Bad Request"), "invalid content length body mismatch");
}

fn void test_malformed_header_returns_400()
{
    String response = request_once(
        "GET /small HTTP/1.1\r\n"
        "BadHeader\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;
    defer aiohttp::localmem.free(response);

    @assert(contains(response, "HTTP/1.1 400 Bad Request\r\n"), "malformed header status mismatch");
    @assert(contains(response, "\r\n\r\n400 Bad Request"), "malformed header body mismatch");
}

fn void test_many_sequential_requests()
{
    for (sz i = 0; i < 20; i++)
    {
        String response = request_once(
            "GET /small HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Connection: close\r\n"
            "\r\n"
        )!!;
        defer aiohttp::localmem.free(response);

        @assert(contains(response, "HTTP/1.1 200 OK\r\n"), "many sequential status mismatch");
        @assert(contains(response, "\r\n\r\nsmall"), "many sequential body mismatch");
    }
}

fn void? main_task(void* arg)
{
    aiohttp::Application app;
    setup_app(&app);
    defer app.deinit();

    aio::spawn(&server_task, &app)!;

    aio::sleep(100)!;

    test_small_response();
    test_large_response();
    test_empty_response();
    test_no_content_response();

    test_connection_close_response_header();
    test_http10_default_close();
    test_http11_default_keep_alive_header();

    test_invalid_content_length_returns_400();
    test_malformed_header_returns_400();

    test_many_sequential_requests();

    aio::current_loop().stop()!;

    io::printfn("test_live_edge: OK");
} 

fn void main()
{
    aio::run(&main_task);
}

// eof