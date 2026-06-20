// server.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

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
faultdef HTTP_REQUEST_TIMEOUT;
faultdef HTTP_CLIENT_CLOSED;

const ulong HTTP_READ_TIMEOUT_US = 5_000_000;

// Limits

const sz HTTP_READ_CHUNK_SIZE = 8192;
const sz HTTP_MAX_REQUEST_BYTES = MAX_HEADER_BYTES + MAX_BODY_BYTES;

const sz FILE_CHUNK_SIZE = 64 * 1024;

fn void? write_file_chunked(aio::Stream* client, String path) @private
{
    aio::File* file = aio::file_open(path, "r")!;
    defer file.free();

    char[FILE_CHUNK_SIZE] buf;

    while (true)
    {
        sz n = file.read(buf[..])!;

        if (n == 0) break;

        write_chunk(client, buf[0:n])!;
    }

    write_last_chunk(client)!;
}

// Server

struct ApplicationServer
{
    Application* app;
    Server* server;

    String host;
    ushort port;

    bool owns_app;
    bool serving;
    bool closed;
    bool waited;
}

// Active app binding

// The current aio server callback cannot capture app state directly.
// Keep the active application in thread-local storage.
//
// If multiple servers are run in the same thread, replace this with
// an explicit server callback context.
tlocal Application* current_http_app = null;

// Read timeout configuration

// This is intentionally not thread-local.
//
// The configured timeout is copied into each HttpConnection when the
// connection handler starts. Changing this value affects new connections.
ulong http_read_timeout_us = HTTP_READ_TIMEOUT_US;

fn void http_set_read_timeout_us(ulong timeout_us)
{
    if (timeout_us == 0)
    {
        http_read_timeout_us = HTTP_READ_TIMEOUT_US;
        return;
    }

    http_read_timeout_us = timeout_us;
}

fn ulong http_get_read_timeout_us()
{
    return http_read_timeout_us;
}

// Lifecycle

fn void ApplicationServer.init(
    &self,
    Application* app,
    String host,
    ushort port
)
{
    self.app = app;
    self.server = null;

    self.host = str_clone(host);
    self.port = port;

    self.owns_app = false;
    self.serving = false;
    self.closed = false;
    self.waited = false;
}

fn void ApplicationServer.init_owned(
    &self,
    Application* app,
    String host,
    ushort port
)
{
    self.app = app;
    self.server = null;

    self.host = str_clone(host);
    self.port = port;

    self.owns_app = true;
    self.serving = false;
    self.closed = false;
    self.waited = false;
}

fn void ApplicationServer.free(&self)
{
    if (self.server != null)
    {
        if (!self.closed)
        {
            self.server.close();
            self.closed = true;
        }

        if (!self.waited)
        {
            self.server.wait_closed();
            self.waited = true;
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
    self.serving = false;
    self.closed = true;
    self.waited = true;
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
    if (self.waited) return;

    if (self.server != null)
    {
        self.server.wait_closed()!;
    }

    self.waited = true;
}

fn ApplicationServer*? http_server_new(
    Application* app,
    String host,
    ushort port
)
{
    ApplicationServer* server = localmem.alloc(ApplicationServer)!;

    server.init(app, host, port);

    return server;
}

fn void http_server_free(ApplicationServer* server)
{
    if (server == null) return;

    server.free();
    localmem.free(server);
}

// Connection policy

fn bool request_wants_close(Request* req)
{
    if (req == null) return true;

    String? connection = req.header("Connection");

    if (catch err = connection)
    {
        return req.is_http_10();
    }

    String value = connection.trim();

    if (str_iequals(value, "close"))
    {
        return true;
    }

    if (req.is_http_10() && !str_iequals(value, "keep-alive"))
    {
        return true;
    }

    return false;
}

fn void? response_apply_connection(
    Response* res,
    Request* req
) @maydiscard
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

// HTTP connection

struct HttpConnection
{
    Stream* stream;
    DString buffer;
    ulong read_timeout_us;
}

fn void? HttpConnection.init(
    &self,
    Stream* stream,
    ulong read_timeout_us
) @maydiscard
{
    if (stream == null)
    {
        return HTTP_SERVER_CLOSED~;
    }

    self.stream = stream;
    self.read_timeout_us = read_timeout_us;

    if (self.read_timeout_us == 0)
    {
        self.read_timeout_us = HTTP_READ_TIMEOUT_US;
    }

    self.buffer.init(localmem, HTTP_READ_CHUNK_SIZE);
}

fn void HttpConnection.free(&self)
{
    self.buffer.free();

    self.stream = null;
    self.read_timeout_us = 0;
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

// Expected request length

struct HttpExpectedLen
{
    bool ok;
    sz value;
    fault err;
}

fn HttpExpectedLen http_expected_len_from_buffer(char[] raw)
{
    sz[2]? header_pos = find_header_end(raw);

    if (catch err = header_pos)
    {
        return {
            .ok = false,
            .value = 0,
            .err = BODY_INCOMPLETE,
        };
    }

    sz header_end = header_pos[0];
    sz body_start = header_pos[0] + header_pos[1];
    sz gap = header_pos[1];

    if (header_end > MAX_HEADER_BYTES)
    {
        return {
            .ok = false,
            .value = 0,
            .err = REQUEST_TOO_LARGE,
        };
    }

    Request*? maybe_tmp = request_new();

    if (catch err = maybe_tmp)
    {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    Request* tmp = maybe_tmp;
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

    if (tmp.is_chunked())
    {
        if (tmp.headers.has("Content-Length"))
        {
            return {
                .ok = false,
                .value = 0,
                .err = BAD_REQUEST,
            };
        }

        char[] body_input = raw[body_start:raw.len - body_start];

        sz? maybe_chunked_len = chunked_expected_len(body_input);

        if (catch err = maybe_chunked_len)
        {
            if (err == CHUNKED_BODY_INCOMPLETE)
            {
                return {
                    .ok = false,
                    .value = 0,
                    .err = BODY_INCOMPLETE,
                };
            }

            return {
                .ok = false,
                .value = 0,
                .err = err,
            };
        }

        sz chunked_len = maybe_chunked_len;

        if (chunked_len > MAX_BODY_BYTES)
        {
            return {
                .ok = false,
                .value = 0,
                .err = REQUEST_TOO_LARGE,
            };
        }

        return {
            .ok = true,
            .value = body_start + chunked_len,
            .err = aio::NONE,
        };
    }

    sz? maybe_content_len = tmp.content_length();

    if (catch err = maybe_content_len)
    {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    sz content_len = maybe_content_len;

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

// Read request

fn Request*? http_read_request(HttpConnection* conn)
{
    if (conn == null)
    {
        return errno::E_INVALID_ARG~;
    }

    if (conn.stream == null)
    {
        return HTTP_SERVER_CLOSED~;
    }

    while (true)
    {
        String view = conn.buffer.str_view();

        if (request_headers_complete((char[])view))
        {
            HttpExpectedLen expected =
                http_expected_len_from_buffer((char[])view);

            if (!expected.ok)
            {
                if (expected.err != BODY_INCOMPLETE)
                {
                    return expected.err~;
                }
            }
            else if (conn.buffer.len() >= expected.value)
            {
                sz total = expected.value;
                char[] raw = ((char[])view)[0:total];

                Request* req = request_parse(raw)!;

                conn.consume(total);

                req.remote_ip = conn.stream.peer_ip()!;

                return req;
            }
        }

        if (conn.buffer.len() >= HTTP_MAX_REQUEST_BYTES)
        {
            return REQUEST_TOO_LARGE~;
        }

        char[HTTP_READ_CHUNK_SIZE] tmp;

        sz? maybe_n = conn.stream.read_timeout(
            tmp[..],
            conn.read_timeout_us
        );

        if (catch err = maybe_n)
        {
            if (err == aio::TIMEOUT)
            {
                return HTTP_REQUEST_TIMEOUT~;
            }

            if (err == aio::CLOSED)
            {
                if (conn.buffer.len() == 0)
                {
                    return HTTP_CLIENT_CLOSED~;
                }

                return BODY_INCOMPLETE~;
            }

            return HTTP_READ_ERROR~;
        }

        sz n = maybe_n;

        if (n == 0)
        {
            if (conn.buffer.len() == 0)
            {
                return HTTP_CLIENT_CLOSED~;
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

fn void? http_write_all(
    Stream* stream,
    String wire
) @private
{
    if (stream == null) return HTTP_WRITE_ERROR~;
    if (wire.len == 0) return HTTP_WRITE_ERROR~;

    sz total = 0;

    while (total < wire.len)
    {
        sz? maybe_n = stream.write(
            ((char[])wire)[total:wire.len - total]
        );

        if (catch err = maybe_n)
        {
            return HTTP_WRITE_ERROR~;
        }

        sz n = maybe_n;

        if (n <= 0)
        {
            return HTTP_WRITE_ERROR~;
        }

        total += n;
    }
}

fn String? Response.serialize_headers_only(
    &self,
    bool force_no_body = false
)
{
    DString out;
    out.init(localmem, 1024);
    defer catch out.free();

    out.appendf(
        "HTTP/1.1 %d %s\r\n",
        self.status,
        status_text(self.status)
    )!;

    if (force_no_body || !status_allows_body(self.status))
    {
        self.headers.remove("Transfer-Encoding");

        if (!self.headers.has("Content-Length"))
        {
            self.headers.content_length(0)!;
        }
    }
    else if (
        self.body_kind == BODY_STREAM ||
        self.body_kind == BODY_FILE
    )
    {
        self.headers.remove("Content-Length");
        self.headers.set("Transfer-Encoding", "chunked")!;
    }
    else if (!self.headers.has("Content-Length"))
    {
        self.headers.content_length(self.body_len_for_wire())!;
    }

    if (!self.headers.has("Connection"))
    {
        self.headers.connection("close")!;
    }

    String headers = self.headers.serialize()!;
    defer localmem.free(headers);

    out.append(headers);
    out.append("\r\n");

    return out.copy_str(localmem);
}

fn void? http_write_response(
    Stream* stream,
    Response* res
) @maydiscard
{
    if (stream == null) return HTTP_WRITE_ERROR~;
    if (res == null) return HTTP_WRITE_ERROR~;

    if (!status_allows_body(res.status))
    {
        res.headers.remove("Transfer-Encoding");
        res.headers.content_length(0)!;

        BodyKind old_kind = res.body_kind;
        char[] old_body = res.body;
        bool old_owns_body = res.owns_body;

        res.body_kind = BODY_EMPTY;
        res.body = {};
        res.owns_body = false;

        String wire = res.serialize_headers_only(true)!;

        res.body_kind = old_kind;
        res.body = old_body;
        res.owns_body = old_owns_body;

        defer localmem.free(wire);

        http_write_all(stream, wire)!;
        return;
    }

    if (res.body_kind == BODY_STREAM)
    {
        String headers = res.serialize_headers_only()!;
        defer localmem.free(headers);

        http_write_all(stream, headers)!;

        res.stream_writer(stream, res.stream_arg)!;
        write_last_chunk(stream)!;

        return;
    }

    if (res.body_kind == BODY_FILE)
    {
        String headers = res.serialize_headers_only()!;
        defer localmem.free(headers);

        http_write_all(stream, headers)!;

        write_file_chunked(stream, res.file_path)!;

        return;
    }

    String wire = res.serialize()!;
    defer localmem.free(wire);

    http_write_all(stream, wire)!;
}

fn void? http_write_response_for_request(
    Stream* stream,
    Response* res,
    Request* req
) @maydiscard
{
    if (stream == null) return HTTP_WRITE_ERROR~;
    if (res == null) return HTTP_WRITE_ERROR~;
    if (req == null) return HTTP_WRITE_ERROR~;

    if (!str_iequals(req.method, "HEAD"))
    {
        http_write_response(stream, res)!;
        return;
    }

    BodyKind old_kind = res.body_kind;
    char[] old_body = res.body;
    bool old_owns_body = res.owns_body;

    res.headers.remove("Transfer-Encoding");

    if (!status_allows_body(res.status))
    {
        res.headers.content_length(0)!;
    }
    else if (old_kind == BODY_FILE)
    {
        if (res.file_size >= 0)
        {
            res.headers.content_length(res.file_size)!;
        }
        else
        {
            res.headers.content_length(0)!;
        }
    }
    else if (old_kind == BODY_STREAM)
    {
        res.headers.content_length(0)!;
    }
    else
    {
        res.headers.content_length(res.body_len_for_wire())!;
    }

    res.body_kind = BODY_EMPTY;
    res.body = {};
    res.owns_body = false;

    String wire = res.serialize_headers_only(true)!;

    res.body_kind = old_kind;
    res.body = old_body;
    res.owns_body = old_owns_body;

    defer localmem.free(wire);

    http_write_all(stream, wire)!;
}

fn Response*? http_error_response(
    ushort status,
    String body
)
{
    Response* res = response_text(body)!;

    res.set_status(status)!;
    res.header("Connection", "close")!;

    return res;
}

// Client handler

fn void? http_handle_client(Stream* stream)
{
    Application* app = current_http_app;

    char[256] error_buffer;

    if (app == null)
    {
        Response* res = http_error_response(
            500,
            string::bformat(
                error_buffer[..],
                "500 Internal Server Error\napp==null"
            )
        )!;

        http_write_response(stream, res);

        response_free(res);
        stream.close();

        return;
    }

    HttpConnection conn;
    conn.init(stream, http_get_read_timeout_us())!;
    defer conn.free();

    while (true)
    {
        Request*? maybe_req = http_read_request(&conn);

        if (catch err = maybe_req)
        {
            if (
                err == HTTP_CLIENT_CLOSED ||
                err == HTTP_REQUEST_INCOMPLETE ||
                err == BODY_INCOMPLETE ||
                err == aio::CLOSED
            )
            {
                stream.close();
                return;
            }

            Response* error_res;

            if (err == HTTP_REQUEST_TIMEOUT)
            {
                error_res = http_error_response(
                    408,
                    "408 Request Timeout"
                )!;
            }
            else if (err == REQUEST_TOO_LARGE)
            {
                error_res = http_error_response(
                    413,
                    "413 Payload Too Large"
                )!;
            }
            else
            {
                error_res = http_error_response(
                    400,
                    "400 Bad Request"
                )!;
            }

            http_write_response(stream, error_res);

            response_free(error_res);
            stream.close();

            return;
        }

        Request* req = maybe_req;

        Response*? maybe_res = app.fetch(req);

        if (catch err = maybe_res)
        {
            Response* error_res;

            if (err == NOT_FOUND)
            {
                error_res = http_error_response(
                    404,
                    "404 Not Found"
                )!;
            }
            else
            {
                error_res = http_error_response(
                    500,
                    string::bformat(
                        error_buffer[..],
                        "500 Internal Server Error\n%s",
                        err
                    )
                )!;
            }

            http_write_response(stream, error_res);

            response_free(error_res);
            request_free(req);

            stream.close();

            return;
        }

        Response* res = maybe_res;

        response_apply_connection(res, req);

        bool close_connection = request_wants_close(req);

        if (catch http_write_response_for_request(
            stream,
            res,
            req
        ))
        {
            response_free(res);
            request_free(req);

            stream.close();

            return;
        }

        response_free(res);
        request_free(req);

        if (close_connection)
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

    if (self.serving)
    {
        return HTTP_SERVER_CLOSED~;
    }

    Application* previous_app = current_http_app;
    current_http_app = self.app;

    defer
    {
        current_http_app = previous_app;
    }

    aio::Server* server = aio::start_server(
        &http_handle_client,
        self.host,
        self.port
    )!;

    self.server = server;
    self.serving = true;
    self.closed = false;
    self.waited = false;

    io::printfn(
        "Listening on http://%s:%d",
        self.host,
        self.port
    );

    if (catch err = server.serve_forever())
    {
        self.serving = false;

        if (!self.closed)
        {
            server.close();
            self.closed = true;
        }

        if (!self.waited)
        {
            server.wait_closed();
            self.waited = true;
        }

        return err~;
    }

    self.serving = false;

    if (!self.closed)
    {
        self.closed = true;
    }

    if (!self.waited)
    {
        server.wait_closed()!;
        self.waited = true;
    }
}

fn void? ApplicationServer.stop(&self) @maydiscard
{
    if (self.server == null)
    {
        return HTTP_SERVER_CLOSED~;
    }

    self.server.stop();
}

fn void? http_serve(
    Application* app,
    String host,
    ushort port
)
{
    ApplicationServer server;
    server.init(app, host, port);
    defer server.free();

    server.serve()!;
}

// Convenience serve helpers

fn void? Application.serve(
    &self,
    String host,
    ushort port
)
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
    return c.text("Hello from ext::aio::http")!;
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