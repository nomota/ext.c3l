// server.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import std::io;
import ext::mem;
import ext::debug;
import ext::aio;
import c::errno;

// Faults

faultdef HTTP_SERVER_CLOSED;
faultdef HTTP_READ_ERROR;
faultdef HTTP_WRITE_ERROR;
faultdef HTTP_REQUEST_INCOMPLETE;


// Limits

const sz HTTP_READ_CHUNK_SIZE = 8192;
const sz HTTP_MAX_REQUEST_BYTES = MAX_HEADER_BYTES + MAX_BODY_BYTES;


// Server

struct ApplicationServer
{
    Application* app;
    String host;
    ushort port;
    bool owns_app;
    bool closed;
    Server* server;
}


// Active app binding

// The current aio server callback cannot capture app state directly.
// Keep the active application in thread-local storage.
//
// If multiple servers are run in the same thread, replace this with
// an explicit server callback context.
tlocal Application* current_http_app = null;


// Lifecycle

fn void ApplicationServer.init(&self, Application* app, String host, ushort port)
{
    self.app = app;
    self.host = str_clone(host);
    self.port = port;
    self.owns_app = false;
    self.closed = false;
    self.server = null;
}

fn void ApplicationServer.init_owned(&self, Application* app, String host, ushort port)
{
    self.app = app;
    self.host = str_clone(host);
    self.port = port;
    self.owns_app = true;
    self.closed = false;
    self.server = null;
}

fn void ApplicationServer.free(&self)
{
    if (self.server != null)
    {
        if (!self.closed)
        {
            self.server.close();
            self.server.wait_closed();
        }

        self.server.free();
        self.server = null;
    }

    if (self.owns_app && self.app != null)
    {
        self.app.free();
    }

    str_free(self.host);

    self.app = null;
    self.host = "";
    self.port = 0;
    self.owns_app = false;
    self.closed = true;
}

fn void? ApplicationServer.close(&self) @maydiscard
{
    if (self.closed) return;

    self.closed = true;

    if (self.server != null)
    {
        self.server.close();
    }
}

fn void? ApplicationServer.wait_closed(&self) @maydiscard
{
    if (self.server != null)
    {
        self.server.wait_closed()!;
    }
}

fn ApplicationServer*? http_server_new(Application* app, String host, ushort port)
{
    ApplicationServer* s = localmem.alloc(ApplicationServer)!;
    s.init(app, host, port);
    return s;
}

fn void http_server_free(ApplicationServer* s)
{
    if (s == null) return;

    s.free();
    localmem.free(s);
}


// Connection policy

fn bool request_wants_close(Request* req)
{
    if (req == null) return true;

    String? conn = req.header("Connection");
    if (catch err = conn)
    {
        if (req.is_http_10()) return true;
        return false;
    }

    if (str_iequals(trim_spaces(conn), "close"))
    {
        return true;
    }

    if (req.is_http_10() && !str_iequals(trim_spaces(conn), "keep-alive"))
    {
        return true;
    }

    return false;
}

fn void? response_apply_connection(Response* res, Request* req) @maydiscard
{
    if (res == null) return HTTP_WRITE_ERROR~;
    if (req == null) return HTTP_WRITE_ERROR~;

    if (request_wants_close(req))
    {
        res.header("Connection", "close")!;
        return;
    }

    if (req.is_http_11())
    {
        res.header("Connection", "keep-alive")!;
        return;
    }

    res.header("Connection", "close")!;
}

struct HttpConnection
{
    Stream* stream;
    DString buffer;
}

fn void? HttpConnection.init(&self, Stream* stream) @maydiscard
{
    self.stream = stream;
    self.buffer.init(localmem, HTTP_READ_CHUNK_SIZE);
}

fn void HttpConnection.free(&self)
{
    self.buffer.free();
    self.stream = null;
}

fn String HttpConnection.str_view(&self)
{
    return self.buffer.str_view();
}

fn char[] HttpConnection.bytes(&self)
{
    return (char[])self.buffer.str_view();
}

fn void HttpConnection.consume(&self, sz n)
{
    if (n <= 0) return;

    if (n >= self.buffer.len())
    {
        self.buffer.clear();
        return;
    }

    self.buffer.delete(0, (usz)n);
}

// Read request

struct HttpExpectedLen
{
    bool ok;
    sz value;
    fault err;
}

fn HttpExpectedLen http_expected_len_from_buffer(char[] raw)
{
    sz[2]? p = find_header_end(raw);
    if (catch err = p)
    {
        return {
            .ok = false,
            .value = 0,
            .err = BODY_INCOMPLETE,
        };
    }

    sz header_end = p[0];
    sz body_start = p[0] + p[1];
    sz gap = p[1];

    if (header_end > MAX_HEADER_BYTES)
    {
        return {
            .ok = false,
            .value = 0,
            .err = REQUEST_TOO_LARGE,
        };
    }

    Request*? tmp = request_new();
    if (catch err = tmp)
    {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }
    defer request_free(tmp);

    char[] header_block = raw[0:header_end + gap / 2];

    if (catch err = tmp.parse_headers_block(header_block))
    {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    if (catch err = tmp.content_length())
    {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    sz content_len = tmp.content_length()!!;

    if (content_len > MAX_BODY_BYTES)
    {
        return {
            .ok = false,
            .value = 0,
            .err = REQUEST_TOO_LARGE,
        };
    }

    return {
        .ok = true,
        .value = body_start + content_len,
        .err = aio::NONE,
    };
}

fn Request*? http_read_request(HttpConnection* conn)
{
    if (conn == null) return errno::E_INVALID_ARG~;
    if (conn.stream == null) return HTTP_SERVER_CLOSED~;

    while (true)
    {
        String view = conn.str_view();

        if (request_headers_complete((char[])view))
        {
            HttpExpectedLen expected = http_expected_len_from_buffer((char[])view);

            if (!expected.ok)
            {
                if (expected.err != BODY_INCOMPLETE)
                {
                    return expected.err~;
                }
            }
            else if (conn.buffer.len() >= expected.value)
            {
                char[] raw = ((char[])view)[0:expected.value];

                Request* req = request_parse(raw)!;

                conn.consume(expected.value);

                req.remote_ip = conn.stream.peer_ip()!;

                return req;
            }
        }

        if (conn.buffer.len() >= HTTP_MAX_REQUEST_BYTES)
        {
            return REQUEST_TOO_LARGE~;
        }

        char[HTTP_READ_CHUNK_SIZE] tmp;

        sz n = conn.stream.read(tmp[..])!;

        if (n == 0)
        {
            if (conn.buffer.len() == 0)
            {
                return HTTP_REQUEST_INCOMPLETE~;
            }

            return BODY_INCOMPLETE~;
        }

        if (conn.buffer.len() + n > HTTP_MAX_REQUEST_BYTES)
        {
            return REQUEST_TOO_LARGE~;
        }

        conn.buffer.append(tmp[0:n]);
    }
}

// Write response

fn void? http_write_response(Stream* stream, Response* res) @maydiscard
{
    if (stream == null) return HTTP_WRITE_ERROR~;
    if (res == null) return HTTP_WRITE_ERROR~;

    String wire = res.serialize()!;
    defer localmem.free(wire);

    if (wire.len == 0)
    {
        return HTTP_WRITE_ERROR~;
    }

    sz total = 0;

    while (total < wire.len)
    {
        sz? n = stream.write(((char[])wire)[total:wire.len - total]);
        if (catch err = n)
        {
            return HTTP_WRITE_ERROR~;
        }

        if (n <= 0)
        {
            return HTTP_WRITE_ERROR~;
        }

        total += n;
    }
//warn("%d", total);
}


// Client handler

fn void? http_handle_client(Stream* stream)
{
    Application* app = current_http_app;

    if (app == null)
    {
        Response* res = response_internal_error()!;
        defer response_free(res);

        http_write_response(stream, res);
        stream.close();
        return;
    }

    HttpConnection conn;
    conn.init(stream)!;
    defer conn.free();

    while (true)
    {
        Request*? req = http_read_request(&conn);

        if (catch err = req)
        {
            if (err == HTTP_REQUEST_INCOMPLETE)
            {
                stream.close();
                return;
            }

            Response* res;

            if (err == REQUEST_TOO_LARGE)
            {
                res = response_empty(413)!;
                res.set_text("413 Payload Too Large")!;
            }
            else
            {
                res = response_empty(400)!;
                res.set_text("400 Bad Request")!;
            }

            defer response_free(res);

            http_write_response(stream, res);
            stream.close();
            return;
        }

        defer request_free(req);

        Response* res = app.fetch(req)!;
        defer response_free(res);

        response_apply_connection(res, req);

        if (catch http_write_response(stream, res))
        {
            stream.close();
            return;
        }

        if (request_wants_close(req))
        {
            stream.close();
            return;
        }
    }
}

// Serve

fn void? ApplicationServer.serve(&self)
{
    if (self.closed || self.app == null)
    {
        return HTTP_SERVER_CLOSED~;
    }

    Application* prev = current_http_app;
    current_http_app = self.app;

    defer
    {
        current_http_app = prev;
    }

    io::printfn("Listening on http://%s:%d", self.host, self.port);

    aio::Server* srv = aio::start_server(&http_handle_client, self.host, self.port)!;
    self.server = srv;

    srv.serve_forever()!;

    if (!self.closed)
    {
        self.closed = true;
        srv.close();
    }

    srv.wait_closed()!;

    return;
}

fn void? ApplicationServer.stop(&self) @maydiscard
{
    self.server.stop();
}

fn void? http_serve(Application* app, String host, ushort port)
{
    ApplicationServer server;
    server.init(app, host, port);
    defer server.free();

    server.serve()!;
}


// Convenience serve helpers

fn void? Application.serve(&self, String host, ushort port)
{
    http_serve(self, host, port)!;
}

fn void? Application.listen(&self, ushort port)
{
    http_serve(self, "127.0.0.1", port)!;
}


// Debug default app example

fn Response*? http_default_handler(Context* c)
{
    return c.text("Hello from ext::aiohttp")!;
}

fn void? http_server_example()
{
    Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_logger);
    app.use(&middleware_powered_by);

    app.get("/", &http_default_handler)!;

    app.listen(8080)!;
}

// eof