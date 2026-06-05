// test_keepalive.c3

// Actual keep-alive and pipelining tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::keepalive;

import std::io;
import ext::aio;
import ext::aiohttp;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18084;


// 
// String helpers
// 

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


// 
// Response parsing helpers
// 

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


// 
// ResponseReader
// 

struct ResponseReader
{
    aio::Stream* stream;
    DString buffer;
}

fn void? ResponseReader.init(&self, aio::Stream* stream) @maydiscard
{
    self.stream = stream;
    self.buffer.init(aiohttp::localmem, 4096);
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
    if (self.stream == null) return aiohttp::CONTEXT_NOT_READY~;

    sz expected = -1;

    while (true)
    {
        String text = self.buffer.str_view();

        if (expected < 0 && text.len > 0)
        {
            if (catch err = response_expected_total_len(text))
            {
                if (err != aiohttp::BODY_INCOMPLETE)
                {
                    return err~;
                }
            }
            else
            {
                expected = response_expected_total_len(text)!!;
            }
        }

        if (expected >= 0 && self.buffer.len() >= expected)
        {
            String out = self.buffer.str_view()[0:expected].copy(aiohttp::localmem);
            self.consume(expected);
            return out;
        }

        if (self.buffer.len() > 1024 * 1024)
        {
            return aiohttp::REQUEST_TOO_LARGE~;
        }

        char[1024] tmp;

        sz n = self.stream.read(tmp[..])!;
        if (n == 0) break;

        self.buffer.append(tmp[0:n]);
    }

    if (expected >= 0 && self.buffer.len() < expected)
    {
        return aiohttp::BODY_INCOMPLETE~;
    }

    if (self.buffer.len() > 0)
    {
        String out = self.buffer.str_view().copy(aiohttp::localmem);
        self.buffer.clear();
        return out;
    }

    return aiohttp::BODY_INCOMPLETE~;
}


// 
// App handlers
// 

fn aiohttp::Response*? one_handler(aiohttp::Context* c)
{
    return c.text("one")!!;
}

fn aiohttp::Response*? two_handler(aiohttp::Context* c)
{
    return c.text("two")!!;
}

fn aiohttp::Response*? three_handler(aiohttp::Context* c)
{
    return c.text("three")!!;
}

fn aiohttp::Response*? echo_handler(aiohttp::Context* c)
{
    return c.text(c.req_text())!!;
}

fn aiohttp::Response*? id_handler(aiohttp::Context* c)
{
    String id = c.param("id")!!;

    return c.text(id)!!;
}

fn void setup_app(aiohttp::Application* app)
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
    aiohttp::ApplicationServer* server = (aiohttp::ApplicationServer*)arg;

    server.serve()!;
}

// 
// Tests
// 

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
    defer aiohttp::localmem.free(r1);

    @assert(contains(r1, "HTTP/1.1 200 OK\r\n"), "first keep-alive status mismatch");
    @assert(contains(r1, "Connection: keep-alive\r\n"), "first keep-alive header mismatch");
    @assert(contains(r1, "\r\n\r\none"), "first keep-alive body mismatch");

    stream.write_all((char[])
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    @assert(contains(r2, "HTTP/1.1 200 OK\r\n"), "second keep-alive status mismatch");
    @assert(contains(r2, "Connection: close\r\n"), "second close header mismatch");
    @assert(contains(r2, "\r\n\r\ntwo"), "second keep-alive body mismatch");

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
    defer aiohttp::localmem.free(r1);

    stream.write_all((char[])
        "GET /two HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    stream.write_all((char[])
        "GET /three HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r3 = reader.read_response()!!;
    defer aiohttp::localmem.free(r3);

    @assert(contains(r1, "Connection: keep-alive\r\n"), "first of three keep-alive header mismatch");
    @assert(contains(r1, "\r\n\r\none"), "first of three body mismatch");

    @assert(contains(r2, "Connection: keep-alive\r\n"), "second of three keep-alive header mismatch");
    @assert(contains(r2, "\r\n\r\ntwo"), "second of three body mismatch");

    @assert(contains(r3, "Connection: close\r\n"), "third of three close header mismatch");
    @assert(contains(r3, "\r\n\r\nthree"), "third of three body mismatch");

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
    defer aiohttp::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    @assert(contains(r1, "HTTP/1.1 200 OK\r\n"), "first pipelined status mismatch");
    @assert(contains(r1, "Connection: keep-alive\r\n"), "first pipelined keep-alive header mismatch");
    @assert(contains(r1, "\r\n\r\none"), "first pipelined body mismatch");

    @assert(contains(r2, "HTTP/1.1 200 OK\r\n"), "second pipelined status mismatch");
    @assert(contains(r2, "Connection: close\r\n"), "second pipelined close header mismatch");
    @assert(contains(r2, "\r\n\r\ntwo"), "second pipelined body mismatch");

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
    defer aiohttp::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    String r3 = reader.read_response()!!;
    defer aiohttp::localmem.free(r3);

    @assert(contains(r1, "\r\n\r\none"), "first pipelined three body mismatch");
    @assert(contains(r2, "\r\n\r\ntwo"), "second pipelined three body mismatch");
    @assert(contains(r3, "\r\n\r\nthree"), "third pipelined three body mismatch");

    @assert(contains(r1, "Connection: keep-alive\r\n"), "first pipelined three keep-alive mismatch");
    @assert(contains(r2, "Connection: keep-alive\r\n"), "second pipelined three keep-alive mismatch");
    @assert(contains(r3, "Connection: close\r\n"), "third pipelined three close mismatch");

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
    defer aiohttp::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    @assert(contains(r1, "HTTP/1.1 200 OK\r\n"), "pipelined post status mismatch");
    @assert(contains(r1, "\r\n\r\nhello"), "pipelined post body mismatch");
    @assert(contains(r1, "Connection: keep-alive\r\n"), "pipelined post keep-alive mismatch");

    @assert(contains(r2, "HTTP/1.1 200 OK\r\n"), "pipelined get after post status mismatch");
    @assert(contains(r2, "\r\n\r\ntwo"), "pipelined get after post body mismatch");
    @assert(contains(r2, "Connection: close\r\n"), "pipelined get after post close mismatch");

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
    defer aiohttp::localmem.free(r1);

    stream.write_all((char[])
        "GET /id/beta HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!!;

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    @assert(contains(r1, "\r\n\r\nalpha"), "keep-alive route param alpha mismatch");
    @assert(contains(r2, "\r\n\r\nbeta"), "keep-alive route param beta mismatch");

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
    defer aiohttp::localmem.free(r1);

    @assert(contains(r1, "HTTP/1.1 200 OK\r\n"), "HTTP/1.0 keep-alive status mismatch");
    @assert(contains(r1, "Connection: close\r\n"), "HTTP/1.0 keep-alive current close policy mismatch");
    @assert(contains(r1, "\r\n\r\none"), "HTTP/1.0 keep-alive body mismatch");

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
    defer aiohttp::localmem.free(r1);

    String r2 = reader.read_response()!!;
    defer aiohttp::localmem.free(r2);

    @assert(contains(r1, "HTTP/1.1 200 OK\r\n"), "chunked pipelined post status mismatch");

    @assert(contains(r1, "\r\n\r\nWikipedia"), "chunked pipelined post body mismatch");
    @assert(contains(r1, "Connection: keep-alive\r\n"), "chunked pipelined post keep-alive mismatch");

    @assert(contains(r2, "\r\n\r\ntwo"), "chunked pipelined get body mismatch");
    @assert(contains(r2, "Connection: close\r\n"), "chunked pipelined get close mismatch");
}

// 
// Main
// 

fn void? main_task(void* arg)
{
    aiohttp::Application app;
    setup_app(&app);
    defer app.deinit();
    
    aiohttp::ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();
    
    aio::spawn(&server_task, &server)!;
    
    aio::sleep(100)!;
    
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
    aio::run(&main_task);
}

// eof