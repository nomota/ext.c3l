// server.c3

module ext::httpserver;

import std::io;
import ext::mem;
import ext::debug;
import ext::asyncio;


// 
// Faults
// 

faultdef HTTP_SERVER_CLOSED;
faultdef HTTP_READ_ERROR;
faultdef HTTP_WRITE_ERROR;
faultdef HTTP_REQUEST_INCOMPLETE;


// 
// Limits
// 

const sz HTTP_READ_CHUNK_SIZE = 8192;
const sz HTTP_MAX_REQUEST_BYTES = MAX_HEADER_BYTES + MAX_BODY_BYTES;


// 
// Server
// 

struct ApplicationServer {
    Application* app;
    String host;
    ushort port;
    bool owns_app;
    bool closed;
}


// 
// Active app binding
// 

// The current asyncio server callback usually cannot capture app state.
// So we keep active app in thread-local storage.
//
// If you later support multiple servers in same thread, replace this with
// a server callback object or listener context.
tlocal Application* current_http_app = null;


// 
// Lifecycle
// 

fn void ApplicationServer.init(&self, Application* app, String host, ushort port)
{
    self.app = app;
    self.host = str_clone(host);
    self.port = port;
    self.owns_app = false;
    self.closed = false;
}

fn void ApplicationServer.init_owned(&self, Application* app, String host, ushort port)
{
    self.app = app;
    self.host = str_clone(host);
    self.port = port;
    self.owns_app = true;
    self.closed = false;
}

fn void ApplicationServer.free(&self)
{
    if (self.owns_app && self.app != null) {
        application_free(self.app);
    }

    str_free(self.host);

    self.app = null;
    self.host = "";
    self.port = 0;
    self.owns_app = false;
    self.closed = true;
}

fn ApplicationServer* http_server_new(Application* app, String host, ushort port)
{
    ApplicationServer* s = localmem.alloc(ApplicationServer);
    s.init(app, host, port);
    return s;
}

fn void http_server_free(ApplicationServer* s)
{
    if (s == null) return;

    s.free();
    localmem.free(s);
}


// 
// Request buffer
// 

struct RequestBuffer {
    char[] data;
    sz cnt;
    sz cap;
}

fn void RequestBuffer.init(&self, Allocator alloc, sz capacity)
{
    self.data = localmem.alloc_array(char, capacity);
    self.cnt = 0;
    self.cap = capacity;
}

fn sz RequestBuffer.len(&self) @inline
{
    return self.cnt;
}

fn void RequestBuffer.free(&self)
{
    if (self.data.ptr != null && self.cap > 0) {
        localmem.free(self.data);
    }

    self.data = {};
    self.cnt = 0;
    self.cap = 0;
}

fn void? RequestBuffer.ensure_capacity(&self, sz need)
{
    if (self.cap >= need) return;

    sz new_cap = self.cap;
    if (new_cap == 0) new_cap = HTTP_READ_CHUNK_SIZE;

    while (new_cap < need) {
        new_cap *= 2;

        if (new_cap > HTTP_MAX_REQUEST_BYTES) {
            return REQUEST_TOO_LARGE~;
        }
    }

    char* p = localmem.malloc(new_cap);

    if (self.cnt > 0) {
        p[0:self.cnt] = self.data[0:self.cnt];
    }

    if (self.data.ptr != null && self.cap > 0) {
        localmem.free(self.data);
    }

    self.data = p[0:new_cap];
    self.cap = new_cap;
}

fn void? RequestBuffer.append(&self, char[] chunk)
{
    if (chunk.len == 0) return;

    if (self.cnt + chunk.len > HTTP_MAX_REQUEST_BYTES) {
        return REQUEST_TOO_LARGE~;
    }

    self.ensure_capacity(self.cnt + chunk.len)!;

    self.data[self.cnt:chunk.len] = chunk[0:chunk.len];
    self.cnt += chunk.len;
}

fn char[] RequestBuffer.bytes(&self)
{
    if (self.cnt == 0) return {};
    return self.data[0:self.cnt];
}

fn String RequestBuffer.str_view(&self)
{
    if (self.cnt == 0) return {};
    return (String)self.data[0:self.cnt];
}


// 
// Connection policy
// 

fn bool request_wants_close(Request* req)
{
    String? conn = req.header("Connection");

    if (catch err = conn) {
        if (req.is_http_10()) return true;
        return false;
    }

    if (str_iequals(conn, "close")) {
        return true;
    }

    if (req.is_http_10() && !str_iequals(conn, "keep-alive")) {
        return true;
    }

    return false;
}

fn void response_apply_connection(Response* res, Request* req)
{
    if (request_wants_close(req)) {
        res.header("Connection", "close");
        return;
    }

    if (req.is_http_11()) {
        res.header("Connection", "keep-alive");
        return;
    }

    res.header("Connection", "close");
}


// 
// Read request
// 

// Reads enough bytes for one HTTP request.
//
// This function assumes stream.read_some() exists.
// If your Stream API uses read(n), recv(), or read_available(),
// replace only this function.
fn Request*? http_read_request(Stream* stream)
{
    // RequestBuffer buf;
    DString buf;
    buf.init(localmem, 4096);
    defer buf.free();

    while (true) {
        char[HTTP_READ_CHUNK_SIZE] tmp;

        sz? n = stream.read_any(&tmp);
        if (catch err = n) {
            return HTTP_READ_ERROR~;
        }

        if (n == 0) {
            return HTTP_REQUEST_INCOMPLETE~;
        }

        buf.append(tmp[0:n]);

        if (!request_headers_complete(buf.str_view())) {
            continue;
        }

        sz? total = request_expected_total_len(buf.str_view());
        if (catch err = total) {
            if (err == BODY_INCOMPLETE) {
                continue;
            }
            return err~;
        }

        if (buf.len() < total) {
            continue;
        }
        
        Request* r = request_parse(buf.str_view())!;
        // r.dump();

        r.remote_ip = stream.get_ip();
warn("remote_ip:%s", r.remote_ip);
        return r;
    }
}


// 
// Write response
// 

fn void? http_write_response(Stream* stream, Response* res) @maydiscard
{
    String wire = res.serialize();
    defer localmem.free(wire);

    if (wire.len == 0) {
        return HTTP_WRITE_ERROR~;
    }

    sz? n = stream.write((char[])wire);
    if (catch err = n) {
        return HTTP_WRITE_ERROR~;
    }

    if (n < wire.len) {
        return HTTP_WRITE_ERROR~;
    }
}


// 
// Client handler
// 

fn void http_handle_client(Stream* stream)
{
    Application* app = current_http_app;

    if (app == null) {
        Response* res = response_internal_error();
        defer response_free(res);

        http_write_response(stream, res);
        stream.close();
        return;
    }

    while (true) {
        Request*? req = http_read_request(stream);
        if (catch err = req) {
            Response* res;

            if (err == REQUEST_TOO_LARGE) {
                res = response_empty(413);
                res.set_text("413 Payload Too Large");
            } else {
                res = response_empty(400);
                res.set_text("400 Bad Request");
            }

            defer response_free(res);

            http_write_response(stream, res);
            stream.close();
            return;
        }
        defer request_free(req);
        
        Response* res = app.fetch(req);
        defer response_free(res);

        response_apply_connection(res, req);
        if (catch http_write_response(stream, res)) {
            stream.close();
            return;
        }

        if (request_wants_close(req)) {
            stream.close();
            return;
        }

        // This first server version is safe for keep-alive only if
        // http_read_request() preserves unread bytes between requests.
        //
        // Current implementation does not preserve pipelined bytes.
        // Therefore close after one request unless you later add
        // per-connection buffered parsing.
        stream.close();
        return;
    }
}


// 
// Serve
// 

fn void? ApplicationServer.serve(&self)
{
    if (self.closed || self.app == null) {
        return HTTP_SERVER_CLOSED~;
    }

    Application* prev = current_http_app;
    current_http_app = self.app;

    defer {
        current_http_app = prev;
    }

    io::printfn("Listening on http://%s:%d", self.host, self.port);

    // Adjust this call to your ext::asyncio server API.
    Server*? srv = asyncio::start_server(&http_handle_client, self.host, self.port);
    if (catch err = srv) {
        io::printfn("asyncio::start_server() failed: %s", err);
        return err~;
    }
    srv.serve_forever();
    
    return;
}

fn void? http_serve(Application* app, String host, ushort port)
{
    ApplicationServer server;
    server.init(app, host, port);
    defer server.free();

    server.serve()!;
}


// 
// Convenience serve helpers
// 

fn void? Application.serve(&self, String host, ushort port)
{
    http_serve(self, host, port)!;
}

fn void? Application.listen(&self, ushort port)
{
    http_serve(self, "127.0.0.1", port)!;
}


// 
// Debug middleware-like default app example
// 

fn Response* http_default_handler(Context* c)
{
    return c.text("Hello from ext::httpserver");
}

fn void? http_server_example()
{
    Application app;
    app.init();
    defer app.free();

    app.use(&middleware_logger);
    app.use(&middleware_powered_by);

    app.get("/", &http_default_handler)!;

    app.listen(8080)!;
}