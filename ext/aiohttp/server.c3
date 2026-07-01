// server.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;
import ext::aio;
import c::errno;


// Faults

faultdef SERVER_CLOSED;
faultdef READ_ERROR;
faultdef WRITE_ERROR;
faultdef REQUEST_INCOMPLETE;
faultdef REQUEST_TIMEOUT;
faultdef CLIENT_CLOSED;
faultdef SLOW_CLIENT;
faultdef WRITE_TIMEOUT;

// Configuration

const ulong READ_TIMEOUT_US = 30_000_000;
const ulong WRITE_TIMEOUT_US = 30_000_000;

const sz SLOW_READ_MIN_BYTES = 16;
const sz MAX_CONSECUTIVE_SLOW_READS = 64;

// Limits

const sz READ_CHUNK_SIZE = 8192;
const sz MAX_REQUEST_BYTES = MAX_HEADER_BYTES + MAX_BODY_BYTES;
const sz FILE_CHUNK_SIZE = 64 * 1024;


ulong read_timeout_us = READ_TIMEOUT_US;
ulong write_timeout_us = WRITE_TIMEOUT_US;

sz slow_read_min_bytes = SLOW_READ_MIN_BYTES;
sz max_consecutive_slow_reads = MAX_CONSECUTIVE_SLOW_READS;

fn void set_read_timeout_us(ulong timeout_us)
{
    read_timeout_us = timeout_us == 0 ? READ_TIMEOUT_US : timeout_us;
}

fn ulong get_read_timeout_us()
{
    return read_timeout_us;
}

fn void set_write_timeout_us(ulong timeout_us)
{
    write_timeout_us = timeout_us == 0 ? WRITE_TIMEOUT_US : timeout_us;
}

fn ulong get_write_timeout_us()
{
    return write_timeout_us;
}

fn void set_slow_read_limit(sz min_bytes, sz max_consecutive_reads)
{
    slow_read_min_bytes = min_bytes > 0 ? min_bytes : SLOW_READ_MIN_BYTES;
    max_consecutive_slow_reads = max_consecutive_reads > 0
        ? max_consecutive_reads
        : MAX_CONSECUTIVE_SLOW_READS;
}

fn void reset_flow_control()
{
    read_timeout_us = READ_TIMEOUT_US;
    write_timeout_us = WRITE_TIMEOUT_US;

    slow_read_min_bytes = SLOW_READ_MIN_BYTES;
    max_consecutive_slow_reads = MAX_CONSECUTIVE_SLOW_READS;
}

// File response writer

fn void? write_file_chunked(aio::Stream* client, String path, sz offset, sz length)
{
    if (client == null) return WRITE_ERROR~;
    if (path.len == 0) return READ_ERROR~;
    if (offset < 0 || length < 0) return READ_ERROR~;

    aio::File* file = aio::file_open(path, "rb")!;
    defer file.free();

    if (offset > 0) {
        long position = file.seek((long)offset, 0)!;

        if (position != (long)offset) {
            return READ_ERROR~;
        }
    }

    char[FILE_CHUNK_SIZE] buffer;
    sz remaining = length;

    while (remaining > 0) {
        sz read_size = remaining;

        if (read_size > FILE_CHUNK_SIZE) {
            read_size = FILE_CHUNK_SIZE;
        }

        sz n = file.read(buffer[0:read_size])!;

        if (n <= 0) {
            return REQUEST_INCOMPLETE~;
        }

        if (n > remaining) {
            return READ_ERROR~;
        }

        write_chunk(client, buffer[0:n])!;

        remaining -= n;
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


// Active application binding

// The current aio server callback cannot capture application state directly.
// Keep the active application in thread-local storage.
//
// If multiple servers run in the same thread, replace this with an explicit
// server callback context.

tlocal Application* current_app = null;


// Lifecycle

fn void ApplicationServer.init(&self, Application* app, String host, ushort port)
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

fn void ApplicationServer.init_owned(&self, Application* app, String host, ushort port)
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
    if (self.server != null) {
        if (!self.closed) {
            self.server.close();
            self.closed = true;
        }

        if (!self.waited) {
            self.server.wait_closed();
            self.waited = true;
        }

        self.server.free();
        self.server = null;
    }

    if (self.owns_app && self.app != null) {
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

    if (self.server != null) {
        self.server.close();
    }
}

fn void? ApplicationServer.wait_closed(&self) @maydiscard
{
    if (self.waited) return;

    if (self.server != null) {
        self.server.wait_closed()!;
    }

    self.waited = true;
}

fn ApplicationServer*? app_server_new(Application* app, String host, ushort port)
{
    ApplicationServer* server = localmem.alloc(ApplicationServer)!;

    server.init(app, host, port);

    return server;
}

fn void app_server_free(ApplicationServer* server)
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

    if (catch connection) {
        return req.is_http_10();
    }

    if (header_has_token(connection, "close")) {
        return true;
    }

    if (req.is_http_10() && !header_has_token(connection, "keep-alive")) {
        return true;
    }

    return false;
}

fn void? response_apply_connection(Response* res, Request* req) @maydiscard
{
    if (res == null) return WRITE_ERROR~;
    if (req == null) return WRITE_ERROR~;

    if (res.status == 101) {
        return;
    }

    if (request_wants_close(req)) {
        res.header("Connection", "close")!;
        return;
    }

    if (req.is_http_11()) {
        res.header("Connection", "keep-alive")!;
        return;
    }

    res.header("Connection", "close")!;
}

// HTTP connection

struct Connection @local
{
    Stream* stream;
    DString buffer;

    ulong read_timeout_us;
    ulong write_timeout_us;

    sz slow_read_count;
}

fn void? Connection.init(&self, Stream* stream, ulong read_timeout_us, ulong write_timeout_us) @maydiscard
{
    if (stream == null) return SERVER_CLOSED~;

    self.stream = stream;

    self.read_timeout_us = read_timeout_us;
    self.write_timeout_us = write_timeout_us;

    if (self.read_timeout_us == 0) {
        self.read_timeout_us = READ_TIMEOUT_US;
    }

    if (self.write_timeout_us == 0) {
        self.write_timeout_us = WRITE_TIMEOUT_US;
    }

    self.slow_read_count = 0;

    self.buffer.init(localmem, READ_CHUNK_SIZE);
}

fn void Connection.free(&self)
{
    self.buffer.free();

    self.stream = null;

    self.read_timeout_us = 0;
    self.write_timeout_us = 0;

    self.slow_read_count = 0;
}

fn String Connection.str_view(&self)
{
    return self.buffer.str_view();
}

fn char[] Connection.bytes(&self)
{
    return (char[])self.buffer.str_view();
}

fn void Connection.consume(&self, sz n)
{
    if (n <= 0) return;

    if (n >= self.buffer.len()) {
        self.buffer.clear();
        return;
    }

    self.buffer.delete(0, (usz)n);
}

fn void? Connection.record_read_progress(&self, sz bytes)
{
    if (bytes <= 0) return SLOW_CLIENT~;

    if (bytes < slow_read_min_bytes) {
        self.slow_read_count++;

        if (self.slow_read_count > max_consecutive_slow_reads) {
            return SLOW_CLIENT~;
        }

        return;
    }

    self.slow_read_count = 0;
}

// Expected request length

struct ExpectedLen @local
{
    bool ok;
    sz value;
    fault err;
}

fn ExpectedLen expected_len_from_buffer(char[] raw) @local
{
    sz[2]? header_pos = find_header_end(raw);

    if (catch err = header_pos) {
        return {
            .ok = false,
            .value = 0,
            .err = BODY_INCOMPLETE,
        };
    }

    sz header_end = header_pos[0];
    sz body_start = header_pos[0] + header_pos[1];
    sz gap = header_pos[1];

    if (header_end > MAX_HEADER_BYTES) {
        return {
            .ok = false,
            .value = 0,
            .err = REQUEST_TOO_LARGE,
        };
    }

    Request*? maybe_tmp = request_new();

    if (catch err = maybe_tmp) {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    Request* tmp = maybe_tmp;
    defer request_free(tmp);

    char[] header_block = raw[0:header_end + gap / 2];

    if (catch err = tmp.parse_headers_block(header_block)) {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    if (tmp.is_chunked()) {
        if (tmp.headers.has("Content-Length")) {
            return {
                .ok = false,
                .value = 0,
                .err = BAD_REQUEST,
            };
        }

        char[] body_input = raw[body_start:raw.len - body_start];
        sz? chunked_len = chunked_expected_len(body_input);

        if (catch err = chunked_len) {
            if (err == CHUNKED_BODY_INCOMPLETE) {
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

        if (chunked_len > MAX_BODY_BYTES) {
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

    if (catch err = maybe_content_len) {
        return {
            .ok = false,
            .value = 0,
            .err = err,
        };
    }

    sz content_len = maybe_content_len;

    if (content_len > MAX_BODY_BYTES) {
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

fn char[]? Connection.copy_pending(&self)
{
    char[] pending = self.bytes();

    if (pending.len == 0) return {};

    return bytes_clone(pending)!;
}

fn Request*? read_request(Connection* conn) @local
{
    if (conn == null) {
        return errno::E_INVALID_ARG~;
    }

    if (conn.stream == null) {
        return SERVER_CLOSED~;
    }

    while (true) {
        String view = conn.buffer.str_view();

        if (request_headers_complete((char[])view)) {
            ExpectedLen expected = expected_len_from_buffer((char[])view);

            if (!expected.ok) {
                if (expected.err != BODY_INCOMPLETE) {
                    return expected.err~;
                }
            } else if (conn.buffer.len() >= expected.value) {
                sz total = expected.value;
                char[] raw = ((char[])view)[0:total];

                Request* req = request_parse(raw)!;

                conn.consume(total);
                conn.slow_read_count = 0;
                
                req.remote_ip = conn.stream.peer_ip()!;

                return req;
            }
        }

        if (conn.buffer.len() >= MAX_REQUEST_BYTES) {
            return REQUEST_TOO_LARGE~;
        }

        char[READ_CHUNK_SIZE] buffer;
        sz? n = conn.stream.read_timeout(buffer[..], conn.read_timeout_us);

        if (catch err = n) {
            if (err == aio::TIMEOUT) {
                return REQUEST_TIMEOUT~;
            }

            if (err == aio::CLOSED) {
                if (conn.buffer.len() == 0) {
                    return CLIENT_CLOSED~;
                }

                return BODY_INCOMPLETE~;
            }

            return READ_ERROR~;
        }

        if (n == 0) {
            if (conn.buffer.len() == 0) {
                return CLIENT_CLOSED~;
            }
        
            return BODY_INCOMPLETE~;
        }
        
        conn.record_read_progress(n)!;

        if (conn.buffer.len() + n > MAX_REQUEST_BYTES) {
            return REQUEST_TOO_LARGE~;
        }

        conn.buffer.append(buffer[0:n]);
    }
}


// Write response


fn void? write_all(Stream* stream, String wire) @maydiscard @local
{
    return stream.write_all_timeout(wire, get_write_timeout_us());
}


fn void? write_response(Stream* stream, Response* res) @maydiscard @local
{
    if (stream == null) return WRITE_ERROR~;
    if (res == null) return WRITE_ERROR~;

    if (res.status == 101) {
        res.headers.remove("Transfer-Encoding");
        res.headers.remove("Content-Length");

        String wire = res.serialize_headers_only(true)!;
        defer localmem.free(wire);

        write_all(stream, wire)!;
        return;
    }

    if (!status_allows_body(res.status)) {
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

        write_all(stream, wire)!;
        return;
    }

    if (res.body_kind == BODY_STREAM) {
        String headers = res.serialize_headers_only()!;
        defer localmem.free(headers);

        write_all(stream, headers)!;

        res.stream_writer(stream, res.stream_arg)!;
        write_last_chunk(stream)!;
        return;
    }

    if (res.body_kind == BODY_FILE) {
        if (res.file_offset < 0 || res.file_size < 0) {
            return WRITE_ERROR~;
        }

        String headers = res.serialize_headers_only()!;
        defer localmem.free(headers);

        write_all(stream, headers)!;
        write_file_chunked(stream, res.file_path, res.file_offset, res.file_size)!;
        return;
    }

    String wire = res.serialize()!;
    defer localmem.free(wire);

    write_all(stream, wire)!;
}

fn void? write_response_for_request(Stream* stream, Response* res, Request* req) @maydiscard @local
{
    if (stream == null) return WRITE_ERROR~;
    if (res == null) return WRITE_ERROR~;
    if (req == null) return WRITE_ERROR~;

    if (!str_iequals(req.method, "HEAD")) {
        write_response(stream, res)!;
        return;
    }

    BodyKind old_kind = res.body_kind;
    char[] old_body = res.body;
    bool old_owns_body = res.owns_body;

    res.headers.remove("Transfer-Encoding");

    if (!status_allows_body(res.status)) {
        res.headers.content_length(0)!;
    } else if (old_kind == BODY_FILE) {
        if (res.file_size >= 0) {
            res.headers.content_length(res.file_size)!;
        } else {
            res.headers.content_length(0)!;
        }
    } else if (old_kind == BODY_STREAM) {
        res.headers.content_length(0)!;
    } else {
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

    write_all(stream, wire)!;
}

fn Response*? error_response(ushort status, String body)
{
    Response* res = response_text(body)!;

    res.set_status(status)!;
    res.header("Connection", "close")!;

    return res;
}


// Client handler

fn void? handle_client(Stream* stream) @local
{
    Application* app = current_app;

    char[256] error_buffer;

    if (app == null) {
        Response* res = error_response(
            500,
            string::bformat(error_buffer[..], "500 Internal Server Error\napp==null")
        )!;

        write_response(stream, res);

        response_free(res);
        stream.close();

        return;
    }

    Connection conn;
    conn.init(stream, get_read_timeout_us(), get_write_timeout_us())!;
    defer conn.free();

    while (true) {
        Request*? req = read_request(&conn);

        if (catch err = req) {
            if (
                err == CLIENT_CLOSED ||
                err == REQUEST_INCOMPLETE ||
                err == BODY_INCOMPLETE ||
                err == aio::CLOSED
            ) {
                stream.close();
                return;
            }

            Response* error_res;

            if (err == REQUEST_TIMEOUT) {
                error_res = error_response(408, "408 Request Timeout")!;
            } else if (err == REQUEST_TOO_LARGE) {
                error_res = error_response(413, "413 Payload Too Large")!;
            } else {
                error_res = error_response(400, "400 Bad Request")!;
            }

            write_response(stream, error_res);

            response_free(error_res);
            stream.close();

            return;
        }

        Context* c = context_new(req)!;
        
        Response*? res = app.fetch_context(c);
        
        if (catch err = res) {
            Context* failed_context = c;
        
            Response* error_res;
        
            if (err == NOT_FOUND) {
                error_res = error_response(404, "404 Not Found")!;
            } else if (err == WS_UNSUPPORTED_VERSION) {
                error_res = websocket_version_response()!;
                error_res.header("Connection", "close")!;
            } else if (err == WS_BAD_HANDSHAKE || err == WS_INVALID_KEY) {
                error_res = error_response(400, "400 Bad WebSocket Handshake")!;
            } else {
                error_res = error_response(
                    500,
                    string::bformat(error_buffer[..], "500 Internal Server Error\n%s", err)
                )!;
            }
        
            write_response(stream, error_res);
        
            response_free(error_res);
            context_free(failed_context);
            request_free(req);
        
            stream.close();
            return;
        }
        
        response_apply_connection(res, req)!;
        
        if (c.ws_upgrade) {
            if (res.status != 101 || c.ws_handler == null) {
                context_free(c);
                request_free(req);
        
                stream.close();
                return WS_BAD_HANDSHAKE~;
            }
        
            if (catch write_response_for_request(stream, res, req)) {
                context_free(c);
                request_free(req);
        
                stream.close();
                return;
            }
        
            char[] pending = conn.copy_pending()!;
            conn.buffer.clear();
        
            WebSocketHandler ws_handler = c.ws_handler;
            ulong ws_timeout = c.ws_read_timeout_us;
        
            context_free(c);
            request_free(req);
        
            WebSocketConnection ws;
            ws.init(stream, true, pending, true);
            ws.set_read_timeout_us(ws_timeout);
        
            if (catch err = ws.run(ws_handler)) {
                ws.abort();
                ws.deinit();
                return;
            }
        
            if (ws.is_open()) {
                if (catch ws.close(WS_CLOSE_NORMAL, "")) {
                    ws.abort();
                }
            }
            
            ws.deinit();
            return;
        }
        
        bool close_connection = request_wants_close(req);
        
        if (catch write_response_for_request(stream, res, req)) {
            context_free(c);
            request_free(req);
        
            stream.close();
            return;
        }
        
        context_free(c);
        request_free(req);
        
        if (close_connection) {
            stream.close();
            return;
        }
    }
}


// Serve

fn void? ApplicationServer.serve(&self)
{
    if (self.closed || self.app == null) {
        return SERVER_CLOSED~;
    }

    if (self.serving)  return SERVER_CLOSED~;

    Application* previous_app = current_app;
    current_app = self.app;

    defer current_app = previous_app;

    aio::Server* server = aio::start_server(&handle_client, self.host, self.port)!;

    self.server = server;
    self.serving = true;
    self.closed = false;
    self.waited = false;

    io::printfn("Listening on http://%s:%d", self.host, self.port);

    if (catch err = server.serve_forever()) {
        self.serving = false;

        if (!self.closed) {
            server.close();
            self.closed = true;
        }

        if (!self.waited) {
            server.wait_closed();
            self.waited = true;
        }

        return err~;
    }

    self.serving = false;

    if (!self.closed) {
        self.closed = true;
    }

    if (!self.waited) {
        server.wait_closed()!;
        self.waited = true;
    }
}

fn void? ApplicationServer.stop(&self) @maydiscard
{
    if (self.server == null) {
        return SERVER_CLOSED~;
    }

    self.server.stop();
}

fn void? serve(Application* app, String host, ushort port) @local
{
    ApplicationServer server;
    server.init(app, host, port);
    defer server.free();

    server.serve()!;
}


// Convenience serve helpers

fn void? Application.serve(&self, String host, ushort port)
{
    serve(self, host, port)!;
}

fn void? Application.listen(&self, ushort port)
{
    serve(self, "127.0.0.1", port)!;
}


// Debug default application example

fn Response*? default_handler(Context* c)
{
    return c.text("Hello from ext::aio::http")!;
}

fn void? server_example()
{
    Application app;
    app.init();
    defer app.deinit();

    app.use(&middleware_logger);
    app.use(&middleware_powered_by);

    app.get("/", &default_handler)!;

    app.listen(8080)!;
}

// eof