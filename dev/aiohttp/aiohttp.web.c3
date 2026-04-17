// aiohttp.web.c3

module ext::aiohttp::web;

import ext::aiohttp;
import ext::asyncio;
import ext::serializer::http;
import ext::aiofiles;
import ext::aiofiles::os;
import ext::mem;

// HTTP/1.1 server implementation.
//
// Dependencies (ext::aiohttp module, same compilation unit):
//   aiohttp.types.c3       — shared types
//   util.url.c3    — url_parse, aiohttp::pct_decode
//   util.ws.c3     — WsDecoder, aiohttp::ws_frame_encode_alloc
//   util.chunk.c3  — chunk_encode, chunk_encode_final
//   web.router.c3  — RouterInner, router_match, router_match_ws
//   web.middleware.c3 — MwTable, mw_chain_call
//   web.static.c3  — static_handler_make
//
// External:
//   ext::asyncio            — start_server, Stream
//   ext::serializer::http   — parse_request, decode helpers
//   ext::aiofiles           — FileResponse body reading

//  constants 

const usz REQ_READ_BUFSZ  @private = 32_000;
const usz RESP_SCRATCH_SZ @private = 8192;
const usz APP_MAX_STATE   @private = 64;
const usz APP_MAX_HOOKS   @private = 32;
const usz APP_MAX_MW      @private = 32;

//  faults 

faultdef
    BAD_REQUEST,
    UNAUTHORIZED,
    FORBIDDEN,
    NOT_FOUND,
    METHOD_NOT_ALLOWED,
    CONFLICT,
    UNPROCESSABLE,
    TOO_MANY_REQUESTS,
    INTERNAL_SERVER_ERROR,
    NOT_IMPLEMENTED,
    BAD_GATEWAY,
    SERVICE_UNAVAILABLE;


tlocal LocalAllocator localmem = {};

//  Application 

struct AppStateEntry {
    String key;
    void*  value;
}

struct Application {
    Router*       router;
    MiddlewareFn[APP_MAX_MW] middlewares;
    usz           middleware_count;
    usz           client_max_size;
    AppHook[APP_MAX_HOOKS] startup_hooks;
    usz           startup_count;
    AppHook[APP_MAX_HOOKS] shutdown_hooks;
    usz           shutdown_count;
    AppHook[APP_MAX_HOOKS] cleanup_hooks;
    usz           cleanup_count;
    AppStateEntry[APP_MAX_STATE] state;
    usz           state_count;
}

fn Application* app_new(usz client_max_size = 1024 * 1024)
{
    Application* app = localmem.alloc(Application);
    app.router = localmem.alloc(Router);
    app.middleware_count = 0;
    app.client_max_size  = client_max_size;
    app.startup_count    = 0;
    app.shutdown_count   = 0;
    app.cleanup_count    = 0;
    app.state_count      = 0;
    router_init(&app.router.inner);
    return app;
}

fn void Application.free(&self)
{
    localmem.free(self.router);
    localmem.free(self);
}

fn void Application.add_middleware(&self, MiddlewareFn mw)
{
    if (self.middleware_count < APP_MAX_MW) {
        self.middlewares[self.middleware_count++] = mw;
    }
}

fn void Application.on_startup(&self, AppHook hook)
{
    if (self.startup_count < APP_MAX_HOOKS) {
        self.startup_hooks[self.startup_count++] = hook;
    }
}

fn void Application.on_shutdown(&self, AppHook hook)
{
    if (self.shutdown_count < APP_MAX_HOOKS) {
        self.shutdown_hooks[self.shutdown_count++] = hook;
    }
}

fn void Application.on_cleanup(&self, AppHook hook)
{
    if (self.cleanup_count < APP_MAX_HOOKS) {
        self.cleanup_hooks[self.cleanup_count++] = hook;
    }
}

fn void? Application.set_state(&self, String key, void* value) @maydiscard
{
    for (usz i = 0; i < self.state_count; i++) {
        if (self.state[i].key == key) { self.state[i].value = value; return; }
    }
    if (self.state_count >= APP_MAX_STATE) return INTERNAL_SERVER_ERROR~;
    self.state[self.state_count++] = (AppStateEntry){ key, value };
}

fn void* Application.get_state(&self, String key)
{
    for (usz i = 0; i < self.state_count; i++) {
        if (self.state[i].key == key) return self.state[i].value;
    }
    return null;
}

fn void? Application.add_routes(&self, RouteTable* rt) @maydiscard
{
    for (usz i = 0; i < rt.count; i++) {
        Route* r = &rt.routes[i];
        if (r.is_ws) {
            router_add_ws(&self.router.inner, r.pattern, r.ws_handler, r.name)!;
        } else {
            router_add(&self.router.inner, r.method, r.pattern, r.handler, r.name)!;
        }
    }
}

//  RouteTable 

const usz ROUTETABLE_INIT_CAP @private = 32;

struct Route {
    HttpMethod     method;
    String         pattern;
    RequestHandler handler;
    WsHandler      ws_handler;
    bool           is_ws;
    String         name;
}

struct RouteTable {
    Route* routes;
    usz    count;
    usz    capacity;
}

struct Router {
    RouteTable  routes;   // public facing (for add_routes compatibility)
    RouterInner inner;    // internal compiled routes
}

fn RouteTable* routetable_new()
{
    RouteTable* rt = localmem.alloc(RouteTable);
    rt.routes = localmem.malloc(ROUTETABLE_INIT_CAP * Route.sizeof);
    rt.count    = 0;
    rt.capacity = ROUTETABLE_INIT_CAP;
    return rt;
}

fn void RouteTable.free(&self)
{
    localmem.free(self.routes);
    localmem.free(self);
}

fn void RouteTable.grow(&self)
{
    usz nc = self.capacity * 2;
    Route* nb = localmem.malloc(nc * Route.sizeof);
    for (usz i = 0; i < self.count; i++) { nb[i] = self.routes[i];
    }
    localmem.free(self.routes);
    self.routes = nb;
    self.capacity = nc;
}

fn void RouteTable.add(&self, HttpMethod m, bool is_ws, String pattern, RequestHandler h, WsHandler wh, String name)
{
    if (self.count >= self.capacity) self.grow();
    self.routes[self.count++] = (Route){
        .method = m, .pattern = pattern, .handler = h,
        .ws_handler = wh, .is_ws = is_ws, .name = name,
    };
}

fn void RouteTable.get(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.GET, false, p, h, null, name);
fn void RouteTable.post(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.POST, false, p, h, null, name);
fn void RouteTable.put(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.PUT, false, p, h, null, name);
fn void RouteTable.patch(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.PATCH, false, p, h, null, name);
fn void RouteTable.delete(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.DELETE, false, p, h, null, name);
fn void RouteTable.head(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.HEAD, false, p, h, null, name);
fn void RouteTable.options(&self, String p, RequestHandler h, String name = "") => self.add(HttpMethod.OPTIONS, false, p, h, null, name);
fn void RouteTable.ws(&self, String p, WsHandler wh, String name = "") => self.add(HttpMethod.GET, true,  p, null, wh, name);
// fn void RouteTable.add(&self, HttpMethod m, String p, RequestHandler h, String name = "") => self.add(m, false, p, h, null, name);

fn void Router.add_get    (&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.GET,     p, h, name)!!;
fn void Router.add_post   (&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.POST,    p, h, name)!!;
fn void Router.add_put    (&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.PUT,     p, h, name)!!;
fn void Router.add_patch  (&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.PATCH,   p, h, name)!!;
fn void Router.add_delete (&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.DELETE,  p, h, name)!!;
fn void Router.add_head   (&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.HEAD,    p, h, name)!!;
fn void Router.add_options(&self, String p, RequestHandler h, String name = "") => router_add(&self.inner, HttpMethod.OPTIONS, p, h, name)!!;
fn void Router.add_ws     (&self, String p, WsHandler wh, String name = "")     => router_add_ws(&self.inner, p, wh, name)!!;

fn void? Router.add_static(&self, String url_prefix, String fs_path) @maydiscard
{
    RequestHandler? h = static_handler_make(url_prefix, fs_path);
    if (catch err = h) return err~;
    
    // register as wildcard GET route
    char[512] pat_buf;
    usz pj = 0;
    foreach (c : url_prefix) pat_buf[pj++] = c;
    String tail = "/{path:.*}";
    foreach (c : tail) pat_buf[pj++] = c;
    
    // copy??? can it be free'd?
    String pat = (String)pat_buf[0:pj];
    router_add(&self.inner, HttpMethod.GET, pat.copy(localmem), h, "")!;
}

fn aiohttp::Url? Router.url_for(&self, String route_name, Headers* params = null)
{
    String path = router_url_for(&self.inner, route_name, params, tmem);
    if (path.len == 0) return aiohttp::INVALID_URL~;
    return aiohttp::url_parse(path);
}

//  MultipartReader 

struct BodyPart {
    Headers* headers;
    char*    data;
    usz      data_len;
    String   name;
    String   filename;
}

struct MultipartReader {
    char*  body;
    usz    body_len;
    String boundary;
    usz    pos;
    bool   done;
}

fn void BodyPart.free(&self)
{
    if (self.headers != null) { 
        self.headers.free();
        self.headers = null;
    }
    localmem.free(self);
}

fn BodyPart? MultipartReader.next(&self)
{
    if (self.done) return NOT_FOUND~;

    // find "--boundary"
    char[128] delim_buf;
    usz dlen = 0;
    delim_buf[dlen++] = '-'; delim_buf[dlen++] = '-';
    foreach (c : self.boundary) { if (dlen < 126) delim_buf[dlen++] = c; }
    String delim = (String) delim_buf[0:dlen];

    // scan for delimiter at current pos
    char* body = self.body + self.pos;
    usz   rem  = self.body_len > self.pos ? self.body_len - self.pos : 0;

    usz di = rem;
    for (usz i = 0; i + delim.len <= rem; i++) {
        bool match = true;
        for (usz k = 0; k < delim.len; k++) {
            if (body[i + k] != delim[k]) { match = false; break; }
        }
        if (match) { di = i; break; }
    }
    if (di >= rem) { self.done = true; return NOT_FOUND~; }

    usz part_start = di + dlen;
    if (part_start + 2 <= rem && body[part_start] == '-' && body[part_start+1] == '-') {
        self.done = true;
        return NOT_FOUND~;
    }
    // skip CRLF after boundary
    if (part_start + 1 < rem && body[part_start] == '\r') part_start += 2;

    // find next delimiter for end of part
    usz next_di = rem;
    for (usz i = part_start; i + delim.len <= rem; i++) {
        bool match = true;
        for (usz k = 0; k < delim.len; k++) {
            if (body[i + k] != delim[k]) { match = false; break; }
        }
        if (match) { next_di = i; break; }
    }

    // parse part headers
    BodyPart* bp = localmem.alloc(BodyPart);
    bp.headers = aiohttp::headers_new();
    bp.name = "";
    bp.filename = "";

    usz p = part_start;
    while (p < next_di) {
        usz line_start = p;
        while (p < next_di && !(body[p] == '\r' && p+1 < next_di && body[p+1] == '\n')) p++;
        if (p == line_start) { p += 2; break; } // blank line
        String line = (String) body[line_start: p - line_start];
        p += 2;
        // find ':'
        usz colon = line.len;
        for (usz k = 0; k < line.len; k++) { if (line[k] == ':') { colon = k; break; } }
        if (colon < line.len) {
            String hname = line[0: colon];
            usz vs = colon + 1;
            while (vs < line.len && line[vs] == ' ') vs++;
            String hval = line[vs: line.len - vs];
            bp.headers.add(hname, hval);

            // extract name/filename from Content-Disposition
            if (hname == "Content-Disposition" || hname == "content-disposition") {
                // parse name="..." filename="..."
                usz qi = 0;
                while (qi < hval.len) {
                    if (hval[qi] == 'n' && qi + 5 < hval.len &&
                        hval[qi+1]=='a' && hval[qi+2]=='m' && hval[qi+3]=='e' && hval[qi+4]=='=') {
                        qi += 5;
                        if (qi < hval.len && hval[qi] == '"') qi++;
                        usz qs = qi;
                        while (qi < hval.len && hval[qi] != '"') qi++;
                        bp.name = (String) hval[qs: qi - qs];
                        if (qi < hval.len) qi++;
                    } else if (hval[qi] == 'f' && qi + 9 < hval.len &&
                               hval[qi+1]=='i' && hval[qi+2]=='l' && hval[qi+3]=='e' &&
                               hval[qi+4]=='n' && hval[qi+5]=='a' && hval[qi+6]=='m' &&
                               hval[qi+7]=='e' && hval[qi+8]=='=') {
                        qi += 9;
                        if (qi < hval.len && hval[qi] == '"') qi++;
                        usz qs = qi;
                        while (qi < hval.len && hval[qi] != '"') qi++;
                        bp.filename = (String) hval[qs: qi - qs];
                        if (qi < hval.len) qi++;
                    } else { qi++; }
                }
            }
        }
    }

    // part data: body[p .. next_di - 2] (strip trailing CRLF)
    usz data_end = next_di;
    if (data_end >= 2 && body[data_end-2] == '\r' && body[data_end-1] == '\n') data_end -= 2;
    bp.data     = body + p;
    bp.data_len = data_end > p ? data_end - p : 0;

    self.pos = self.pos + next_di;
    return *bp;
}

fn void MultipartReader.free(&self) { localmem.free(self); }

//  Request 

struct Request {
    HttpMethod   method;
    aiohttp::Url          url;
    String       path;
    Headers*     headers;
    Headers*     query;
    Headers*     match_info;
    Headers*     cookies;
    bool         can_read_body;
    Application* app;
    
    // private
    Stream*      stream;
    char*        raw_body;
    usz          raw_body_len;
    usz          content_length;
    bool         is_chunked;
    bool         body_read;
}

fn char*? Request.read(&self, usz* out_len)
{
    if (self.body_read) { *out_len = self.raw_body_len; return self.raw_body; }
    if (!self.can_read_body || self.stream == null) {
        *out_len = 0; return null;
    }

    char[REQ_READ_BUFSZ] raw;
    if (self.is_chunked) {
        ChunkDecoder dec; dec.init();
        usz cap = 8192;
        char* buf = localmem.malloc(cap);
        usz len = 0;
        ChunkFrame frame;
        while (!dec.done()) {
            usz n = self.stream.read(&raw);
            if (n == 0) break;
            dec.feed(&raw[0], n)!!;
            while (dec.next(&frame)) {
                if (frame.is_final) break;
                if (len + frame.data_len > cap) {
                    usz nc = (cap + frame.data_len) * 2;
                    char* nb = localmem.malloc(nc);
                    for (usz i = 0; i < len; i++) nb[i] = buf[i];
                    localmem.free(buf); buf = nb; cap = nc;
                }
                for (usz i = 0; i < frame.data_len; i++) buf[len++] = frame.data[i];
            }
        }
        self.raw_body = buf; self.raw_body_len = len;
    } else {
        usz total = self.content_length;
        char* buf = localmem.malloc(total > 0 ? total : 1);
        usz len = 0;
        while (total == 0 || len < total) {
            usz want = REQ_READ_BUFSZ;
            if (total > 0 && total - len < want) want = total - len;
            usz n = self.stream.read((char[]) buf[len:want]);
            if (n == 0) break;
            len += n;
        }
        self.raw_body = buf; self.raw_body_len = len;
    }
    self.body_read = true;
    *out_len = self.raw_body_len;
    return self.raw_body;
}

fn String? Request.text(&self)
{
    usz len;
    char*? raw = self.read(&len);
    if (catch err = raw) return err~;
    return (String) raw[0:len];
}

fn String? Request.json_text(&self) => self.text();

fn Headers*? Request.post(&self)
{
    usz len;
    char*? raw = self.read(&len);
    if (catch err = raw) return err~;

    String ct = self.headers.get("content-type") ?? "";
    bool is_urlenc = false;
    usz? idx = ct.index_of("application/x-www-form-urlencoded");
    if (try idx) is_urlenc = true;

    Headers* form = aiohttp::headers_new();
    if (!is_urlenc) return form;

    // parse "key=value&key2=value2"
    String body = (String) raw[0:len];
    usz pos = 0;
    while (pos < body.len) {
        usz key_start = pos;
        while (pos < body.len && body[pos] != '=') pos++;
        String key = body[key_start:pos - key_start];
        if (pos < body.len) pos++;
        usz val_start = pos;
        while (pos < body.len && body[pos] != '&') pos++;
        String val = body[val_start:pos - val_start];
        if (pos < body.len) pos++;

        String dk = aiohttp::pct_decode(localmem, key, true);
        String dv = aiohttp::pct_decode(localmem, val, true);
        form.add(dk, dv);
    }
    return form;
}

fn MultipartReader*? Request.multipart(&self)
{
    String ct = self.headers.get("content-type") ?? "";
    // extract boundary
    String boundary = "";
    usz bi = 0;
    while (bi < ct.len) {
        if (ct[bi] == 'b' && bi + 9 <= ct.len) {
            bool match = true;
            const String BND = "boundary=";
            for (usz k = 0; k < 9; k++) {
                if (ct[bi + k] != BND[k]) { match = false; break; }
            }
            if (match) {
                bi += 9;
                usz bs = bi;
                while (bi < ct.len && ct[bi] != ';' && ct[bi] != ' ') bi++;
                boundary = ct[bs:bi - bs];
                break;
            }
        }
        bi++;
    }
    if (boundary.len == 0) return BAD_REQUEST~;

    usz len;
    char*? raw = self.read(&len);
    if (catch err = raw) return err~;

    MultipartReader* mr = (MultipartReader*)localmem.malloc($sizeof(MultipartReader));
    mr.body     = raw;
    mr.body_len = len;
    mr.boundary = boundary;
    mr.pos      = 0;
    mr.done     = false;
    return mr;
}

//  Response 

struct Response {
    int      status;
    String   reason;
    Headers* headers;
    char*    body;
    usz      body_len;
    String   content_type;
    String   charset;
}

fn Response* response_new(
    int    status       = 200,
    String text         = "",
    char*  body         = null,
    usz    body_len     = 0,
    String content_type = "text/plain",
    String charset      = "utf-8",
)
{
    Response* r = localmem.alloc(Response);
    r.status       = status;
    r.reason       = aiohttp::http_reason(status);
    r.headers      = aiohttp::headers_new();
    r.content_type = content_type;
    r.charset      = charset;

    if (text.len > 0) {
        r.body     = (char*)text.ptr;
        r.body_len = text.len;
    } else {
        r.body     = body;
        r.body_len = body_len;
    }
    return r;
}

fn Response* json_response(String json_str, int status = 200)
{
    return response_new(
        status,
        "", // ????
        (char*)json_str.ptr,
        json_str.len,
        "application/json",
        "utf-8",
    );
}

fn void Response.free(&self)
{
    if (self.headers != null) { 
        self.headers.free(); 
        self.headers = null;
    }
    localmem.free(self);
}

fn void Response.set_header(&self, String name, String value)
{
    self.headers.set(name, value);
}

fn void Response.set_cookie(&self, Cookie* c)
{
    // build "Set-Cookie: name=value; Path=/; ..."
    char[512] buf; 
    OBuf b = { &buf[0], 512, 0 };
    
    b.put(c.name); b.putc('='); b.put(c.value);
    if (c.path.len > 0) { b.put("; Path=");  b.put(c.path);   }
    if (c.domain.len > 0) { b.put("; Domain="); b.put(c.domain); }
    if (c.secure) b.put("; Secure");
    if (c.http_only) b.put("; HttpOnly");
    if (c.same_site.len > 0) { b.put("; SameSite="); b.put(c.same_site); }
    self.headers.add("Set-Cookie", b.str().copy(localmem));
}

fn void Response.del_cookie(&self, String name)
{
    // set cookie with expired date to delete it
    char[256] buf;
    OBuf b = { &buf[0], 256, 0 };
    
    b.put(name); b.put("=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
    self.headers.add("Set-Cookie", b.str().copy(localmem));
}

        
//  HTTP error shortcuts 

fn Response* http_bad_request          (String text = "Bad Request")           => response_new(400, text);
fn Response* http_unauthorized         (String text = "Unauthorized")           => response_new(401, text);
fn Response* http_forbidden            (String text = "Forbidden")              => response_new(403, text);
fn Response* http_not_found            (String text = "Not Found")              => response_new(404, text);
fn Response* http_method_not_allowed   (String text = "Method Not Allowed")     => response_new(405, text);
fn Response* http_internal_server_error(String text = "Internal Server Error")  => response_new(500, text);

fn Response* http_redirect(String location, int status = 302)
{
    Response* r = response_new(status);
    r.set_header("Location", location);
    return r;
}

fn Response* http_moved_permanently(String location)
    => http_redirect(location, 301);

//  response serializer 

fn void? write_response(Stream* s, Response* resp) @private
{
    char[RESP_SCRATCH_SZ] buf;
    OBuf b = { &buf[0], RESP_SCRATCH_SZ, 0 };

    b.put("HTTP/1.1 "); b.putn(resp.status); b.putc(' '); b.put(resp.reason); b.crlf();

    // Content-Type
    if (!resp.headers.has("content-type") && resp.content_type.len > 0) {
        b.put("Content-Type: "); 
        b.put(resp.content_type);
        if (resp.charset.len > 0) { b.put("; charset="); b.put(resp.charset); }
        b.crlf();
    }

    // Content-Length
    if (!resp.headers.has("content-length")) {
        b.put("Content-Length: "); b.putn((int)resp.body_len); b.crlf();
    }

    // Connection
    if (!resp.headers.has("connection")) { b.put("Connection: keep-alive"); b.crlf(); }

    // custom headers
    for (usz i = 0; i < resp.headers.count; i++) {
        b.put(resp.headers.entries[i].name);
        b.put(": ");
        b.put(resp.headers.entries[i].value);
        b.crlf();
    }
    b.crlf();
    s.write(b.str()); // ???

    if (resp.body_len > 0 && resp.body != null) {
        s.write(resp.body[0:resp.body_len ]); // ???
    }
}

//  StreamResponse 

struct StreamResponse {
    int      status;
    String   reason;
    Headers* headers;
    bool     prepared;
    bool     eof_sent;
    Stream*  stream;
}

fn StreamResponse* stream_response_new(int status = 200)
{
    StreamResponse* r = localmem.alloc(StreamResponse);
    r.status   = status;
    r.reason   = aiohttp::http_reason(status);
    r.headers  = aiohttp::headers_new();
    r.prepared = false;
    r.eof_sent = false;
    r.stream   = null;
    return r;
}

fn void StreamResponse.set_header(&self, String name, String value)
{
    self.headers.set(name, value);
}

fn void StreamResponse.set_cookie(&self, Cookie* c)
{
    // reuse Response.set_cookie logic via a temporary
    Response tmp; tmp.headers = self.headers;
    tmp.set_cookie(c);
}

fn void? StreamResponse.prepare(&self, Request* req)
{
    if (self.prepared) return;
    self.stream   = req.stream;
    self.prepared = true;

    char[RESP_SCRATCH_SZ] buf;    
    OBuf b = { &buf[0], RESP_SCRATCH_SZ, 0 };
    
    b.put("HTTP/1.1 "); b.putn(self.status); b.putc(' '); b.put(self.reason);
    b.crlf();
    b.put("Transfer-Encoding: chunked\r\n");
    if (!self.headers.has("connection")) b.put("Connection: keep-alive\r\n");
    for (usz i = 0; i < self.headers.count; i++) {
        b.put(self.headers.entries[i].name);
        b.put(": ");
        b.put(self.headers.entries[i].value);
        b.crlf();
    }
    b.crlf();
    self.stream.write(b.str()); // ????
}

fn void? StreamResponse.write(&self, char* data, usz len) @maydiscard
{
    if (!self.prepared || self.stream == null) return INTERNAL_SERVER_ERROR~;
    usz frame_sz = aiohttp::chunk_encoded_size(len);
    char* frame = localmem.malloc(frame_sz);
    defer localmem.free(frame);
    usz written = aiohttp::chunk_encode(frame, data, len);
    self.stream.write(frame[0:written]); // ????
}

fn void? StreamResponse.write_eof(&self) @maydiscard
{
    if (!self.prepared || self.eof_sent || self.stream == null) return;
    self.eof_sent = true;
    char[5] tail;
    usz n = aiohttp::chunk_encode_final(&tail[0]);
    self.stream.write(tail[0:n]); // ????
}

fn void StreamResponse.free(&self)
{
    if (!self.eof_sent) {
        (void)self.write_eof();
    }
    self.headers.free();
    localmem.free(self);
}

//  FileResponse 

struct FileResponse {
    int      status;
    Headers* headers;
    String   filepath;
    String   content_type;
}

fn FileResponse* file_response_new(
    String filepath,
    int status = 200,
    String content_type = "",
)
{
    FileResponse* r = localmem.alloc(FileResponse);
    r.status       = status;
    r.headers      = aiohttp::headers_new();
    r.filepath     = filepath;
    r.content_type = content_type;
    return r;
}

fn void FileResponse.free(&self)
{
    self.headers.free();
    localmem.free(self);
}

// Send FileResponse to stream — called by the request dispatcher.
fn void? file_response_send(FileResponse* fr, Stream* s) @private
{
    // delegate to static file handler
    StaticConfig cfg = {
        .url_prefix   = "",
        .fs_root      = "",
        .show_index   = false,
        .chunk_size   = 65536,
    };
    // open and stream the file directly
    AioFile? afile = aiofiles::open(fr.filepath, "rb");
    if (catch err = afile) {
        // send 404
        Response* err_r = http_not_found();
        (void)write_response(s, err_r);
        err_r.free();
        return;
    }

    usz file_size = 0;
    Stat? st = os::stat(fr.filepath);
    if (try st) {
        file_size = (usz)st.st_size;
    }
    
    // detect MIME if not set
    String mime = fr.content_type.len > 0 ? fr.content_type : static_mime(fr.filepath);

    // write header
    char[RESP_SCRATCH_SZ] buf; 
    OBuf b = { &buf[0], RESP_SCRATCH_SZ, 0 };
    
    b.put("HTTP/1.1 200 OK\r\nContent-Type: "); b.put(mime);
    b.put("\r\nContent-Length: "); b.putn((int)file_size);
    b.put("\r\nConnection: keep-alive\r\n");
    for (usz i = 0; i < fr.headers.count; i++) {
        b.put(fr.headers.entries[i].name); b.put(": ");
        b.put(fr.headers.entries[i].value); b.crlf();
    }
    b.crlf();
    s.write(b.str()); // ????

    // stream file body
    char[65536] chunk;
    while (true) {
        usz? n = afile.read_unbuffered(&chunk);
        if (catch err = n) break;
        if (n == 0) break;
        s.write(chunk[0:n]); // ????
    }
    afile.close();
}

//  WebSocketResponse 

struct WebSocketResponse {
    bool   closed;
    String protocol;
    int    compress;
    Stream*    stream;
    WsDecoder  decoder;
    ulong      heartbeat_us;
}

fn WebSocketResponse* ws_response_new(
    ulong   heartbeat_us    = 0,
    int     compress        = 0,
    String* protocols       = null,
    usz     protocols_count = 0,
)
{
    WebSocketResponse* ws = (WebSocketResponse*)localmem.malloc($sizeof(WebSocketResponse));
    ws.closed        = false;
    ws.protocol      = "";
    ws.compress      = compress;
    ws.stream        = null;
    ws.heartbeat_us  = heartbeat_us;
    ws.decoder.init(true, 0); // server: expects masked frames from client
    return ws;
}

fn void? WebSocketResponse.prepare(&self, Request* req)
{
    // validate Upgrade headers
    String? upgrade = req.headers.get("upgrade");
    if (catch err = upgrade) return BAD_REQUEST~;

    String? wskey = req.headers.get("sec-websocket-key");
    if (catch err = wskey) return BAD_REQUEST~;

    self.stream = req.stream;

    // build 101 response
    char[512] hs_buf;
    usz hs_len = aiohttp::ws_server_handshake_accept(&hs_buf[0], 512, wskey, self.protocol, localmem);
    self.stream.write(hs_buf[0:hs_len]); // ???
}

fn void? ws_server_send(WebSocketResponse* ws, WsMsgType type, char* data, usz len) @private
{
    if (ws.closed || ws.stream == null) return INTERNAL_SERVER_ERROR~;
    // server sends UNMASKED frames
    char[4] no_mask = { 0, 0, 0, 0 };
    String? frame = aiohttp::ws_frame_encode_alloc(localmem, type, data, len, false, no_mask);
    if (catch err = frame) return INTERNAL_SERVER_ERROR~;
    defer frame.free(localmem);

    ws.stream.write(frame[0:frame.len]); // ???
}

fn void? WebSocketResponse.send_str  (&self, String data) @maydiscard => ws_server_send(self, WsMsgType.TEXT,   (char*)data.ptr, data.len);
fn void? WebSocketResponse.send_bytes(&self, char* data, usz len) @maydiscard => ws_server_send(self, WsMsgType.BINARY, data, len);
fn void? WebSocketResponse.send_json (&self, String json_str) @maydiscard => ws_server_send(self, WsMsgType.TEXT,   (char*)json_str.ptr, json_str.len);
fn void? WebSocketResponse.ping(&self, char* msg = null, usz len = 0) @maydiscard => ws_server_send(self, WsMsgType.PING, msg, len);
fn void? WebSocketResponse.pong(&self, char* msg = null, usz len = 0) @maydiscard => ws_server_send(self, WsMsgType.PONG, msg, len);

fn WsMessage? WebSocketResponse.receive(&self)
{
    if (self.closed || self.stream == null) return INTERNAL_SERVER_ERROR~;
    char[REQ_READ_BUFSZ] raw;
    while (true) {
        WsFrame frame;
        bool? got = self.decoder.next(&frame);
        if (catch err = got) return INTERNAL_SERVER_ERROR~;
        if (got) {
            if (frame.type == WsMsgType.PING) {
                ws_server_send(self, WsMsgType.PONG, frame.data, frame.data_len)!;
                continue;
            }
            if (frame.type == WsMsgType.CLOSE) {
                self.closed = true;
                // echo CLOSE back
                char[4] no_mask = { 0,0,0,0 };
                char[4] cb;
                usz clen = aiohttp::ws_close_frame(&cb[0], WsCloseCode.NORMAL_CLOSURE, "", false, no_mask);
                self.stream.write(cb[0:clen]); // ???
                WsMessage msg; msg.type=WsMsgType.CLOSE; msg.data=null;
                msg.data_len=0; msg.extra=frame.close_reason;
                return msg;
            }
            char* buf = localmem.malloc(frame.data_len > 0 ? frame.data_len : 1);
            for (usz i = 0; i < frame.data_len; i++) buf[i] = frame.data[i];
            usz total = frame.data_len;
            while (!frame.fin) {
                WsFrame cont; bool? gc = self.decoder.next(&cont);
                if (catch err = gc) break;
                if (!gc) {
                    usz n = self.stream.read(&raw); if (n==0) break;
                    self.decoder.feed(&raw[0], n)!; continue;
                }
                char* nb = localmem.malloc(total + cont.data_len);
                for (usz i=0;i<total;i++) nb[i]=buf[i];
                for (usz i=0;i<cont.data_len;i++) nb[total+i]=cont.data[i];
                localmem.free(buf); buf=nb; total+=cont.data_len; frame.fin=cont.fin;
            }
            WsMessage msg; msg.type=frame.type; msg.data=buf;
            return msg;
        }
        usz n = self.stream.read(&raw); 
        if(n==0){self.closed=true; return INTERNAL_SERVER_ERROR~;}
        self.decoder.feed(&raw[0], n)!;
    }
}

fn bool WebSocketResponse.next(&self, WsMessage* out_msg)
{
    if (self.closed) return false;
    WsMessage? msg = self.receive();
    if (catch err = msg) return false;
    if (msg.type == WsMsgType.CLOSE) return false;
    *out_msg = msg;
    return true;
}

fn void? WebSocketResponse.close(&self, WsCloseCode code = WsCloseCode.NORMAL_CLOSURE) @maydiscard
{
    if (self.closed || self.stream == null) return;
    self.closed = true;
    char[4] no_mask = {0,0,0,0};
    char[140] cb;
    usz clen = aiohttp::ws_close_frame(&cb[0], code, "", false, no_mask);
    self.stream.write(cb[0:clen]); // ???
}

fn void WebSocketResponse.free(&self)
{
    if (!self.closed) self.close();
    localmem.free(self);
}

//  request dispatcher 

// Build Request from parsed http::Request + stream.
fn Request* build_request(http::Request* p, Stream* s, Application* app, Allocator alloc
) @private
{
    localmem = alloc;
    Request* req = localmem.alloc(Request);

    HttpMethod? meth = aiohttp::http_method_from_str(p.method);
    req.method = meth ?? HttpMethod.GET;

    // parse URL
    aiohttp::Url url_val = aiohttp::url_parse(p.uri) ?? (aiohttp::Url){ .path = p.uri };
    req.url  = url_val;
    req.path = p.uri;

    req.headers = aiohttp::headers_new();
    for (uint i = 0; i < p.n_headers; i++) {
        req.headers.add(p.headers[i].key, p.headers[i].value);
    }

    // query params
    req.query = aiohttp::headers_new();
    p.decode_query();
    for (usz i = 0; i < p.n_queries; i++) {
        String dk = aiohttp::pct_decode(localmem, p.queries[i].key, true);
        String dv = aiohttp::pct_decode(localmem, p.queries[i].value, true);
        req.query.add(dk, dv);
    }

    // cookies
    req.cookies = aiohttp::headers_new();
    p.decode_cookies();
    for (uint i = 0; i < p.n_cookies; i++) {
        req.cookies.add(p.cookies[i].key, p.cookies[i].value);
    }

    req.match_info   = aiohttp::headers_new();
    req.can_read_body = true;
    req.app          = app;
    req.stream       = s;
    req.raw_body     = null;
    req.raw_body_len = 0;
    req.body_read    = false;

    p.decode_content_length();
    req.content_length = p.content_length;
    req.is_chunked     = p.chunked;

    return req;
}

fn void request_free(Request* req) @private
{
    req.headers.free();
    req.query.free();
    req.cookies.free();
    req.match_info.free();
    if (req.raw_body != null) localmem.free(req.raw_body);
    localmem.free(req);
}

// Handle one HTTP connection (runs in a fiber spawned by asyncio::start_server).
fn void handle_connection(Stream* stream, Application* app) @private
{
    char[REQ_READ_BUFSZ * 2] buf;
    usz filled = 0;

    // Read until full request headers are available.
    bool got_req = false;
    while (filled < buf.len) {
        usz n = stream.read(buf[filled:buf.len - filled]);
        if (n == 0) return;
        filled += n;
        for (usz i = 0; i + 3 < filled; i++) {
            if (buf[i]=='\r'&&buf[i+1]=='\n'&&buf[i+2]=='\r'&&buf[i+3]=='\n') { got_req = true;
                break;
            }
        }
    }
    if (!got_req) return; // headers too large

    http::Request parsed;
    char*? body_ptr = http::parse_request(&buf[0], &buf[filled], &parsed);
    if (catch err = body_ptr) {
        // send 400
        Response* bad = http_bad_request();
        defer bad.free();
        (void)write_response(stream, bad);
        return;
    }

    Request* req = build_request(&parsed, stream, app, localmem);

    // check for WebSocket upgrade
    String? upgrade_hdr = req.headers.get("upgrade");
    bool is_ws_upgrade = false;
    if (try upgrade_hdr) {
        String uv = upgrade_hdr;
        if (uv.len >= 9) {
            bool match = true;
            const String WS = "websocket";
            for (usz k = 0; k < 9 && k < uv.len; k++) {
                char c = uv[k]; if (c>='A'&&c<='Z') c=(char)(c|0x20);
                if (c != WS[k]) { match = false; break; }
            }
            is_ws_upgrade = match;
        }
    }

    if (is_ws_upgrade) {
        RouteMatch ws_match;
        bool found = router_match_ws(&app.router.inner, req.path, &ws_match);
        if (!found) {
            Response* r = http_not_found();
            defer r.free();
            defer request_free(req);
            (void)write_response(stream, r);
            return;
        }
            
        // fill match_info
        req.match_info.free();
        req.match_info = router_match_info(&ws_match, localmem)!!;

        WebSocketResponse* ws = ws_response_new();
        defer ws.free();
        (void)ws.prepare(req);
        (void)ws_match.ws_handler(req, ws);
    } else {
        RouteMatch match;
        bool found = router_match(&app.router.inner, req.method, req.path, &match);
        if (!found) {
            Response* r = http_not_found();
            defer r.free();
            request_free(req);
            (void) write_response(stream, r);
            return;
        }
        req.match_info.free();
        req.match_info = router_match_info(&match, tmem)!!; // ?????

        // run middleware chain
        MwTable mw_table;
        mw_table_init(&mw_table);
        for (usz i = 0; i < app.middleware_count; i++) {
            mw_table_add(&mw_table, app.middlewares[i]);
        }

        Response*? resp = mw_chain_call(&mw_table, match.handler, req);
        if (catch errr = resp) {
            Response* err = http_internal_server_error();
            defer err.free();
            defer request_free(req);
            (void)write_response(stream, err);
            return;
        }

        if (resp != null) {
            defer resp.free();
            (void)write_response(stream, resp);
        }
    }
    request_free(req);
}

//  AppRunner 

struct AppRunner {
    Application* app;
    bool running;
}

fn AppRunner* runner_new(Application* app)
{
    AppRunner* r = localmem.alloc(AppRunner);
    r.app = app;
    r.running = false;
    return r;
}

fn void? AppRunner.setup(&self)
{
    for (usz i = 0; i < self.app.startup_count; i++) {
        self.app.startup_hooks[i](self.app)!;
    }
    self.running = true;
}

fn void? AppRunner.cleanup(&self) @maydiscard
{
    self.running = false;
    for (usz i = 0; i < self.app.cleanup_count; i++) {
        self.app.cleanup_hooks[i](self.app)!;
    }
    for (usz i = 0; i < self.app.shutdown_count; i++) {
        self.app.shutdown_hooks[i](self.app)!;
    }
}

fn void AppRunner.free(&self) { localmem.free(self); }

//  TcpSite 

struct TcpSite {
    AppRunner* runner;
    String     host;
    ushort     port;
    ulong      shutdown_timeout_us;
    TlsConfig* tls;
    int        backlog;
    Server*    server;
}

// Thread-local pointer so the fiber handler can reach the Application.
tlocal Application* tl_serving_app @private = null;

fn void tcp_client_handler(Stream* stream) @private
{
    handle_connection(stream, tl_serving_app);
    stream.close();
}

fn TcpSite* tcpsite_new(
    AppRunner* runner,
    String     host                = "0.0.0.0",
    ushort     port                = 8080,
    ulong      shutdown_timeout_us = 60_000_000,
    TlsConfig* tls                 = null,
    int        backlog             = 128,
)
{
    TcpSite* site = localmem.alloc(TcpSite);
    site.runner               = runner;
    site.host                 = host;
    site.port                 = port;
    site.shutdown_timeout_us  = shutdown_timeout_us;
    site.tls                  = tls;
    site.backlog              = backlog;
    site.server               = null;
    return site;
}

fn void? TcpSite.start(&self) @maydiscard
{
    self.runner.setup()!;
    tl_serving_app = self.runner.app;

    Server*? srv = asyncio::start_server(
        &tcp_client_handler, self.host, self.port
    );
    if (catch err = srv) return aiohttp::CONNECTION_FAILED~;
    self.server = srv;
    self.server.serve_forever()!;
}

fn void? TcpSite.stop(&self) @maydiscard
{
    if (self.server != null) self.server.stop();
    self.runner.cleanup()!;
}

fn void TcpSite.free(&self)
{
    if (self.server != null) { self.server.free(); self.server = null; }
    localmem.free(self);
}

//  top-level run_app 

fn void? run_app(
    Application* app,
    String       host = "0.0.0.0",
    ushort       port = 8080,
    TlsConfig*   tls  = null,
) @maydiscard
{
    AppRunner* runner = runner_new(app);
    TcpSite*   site   = tcpsite_new(runner, host, port, 60_000_000, tls, 128);
    site.start()!;
    site.stop()!;
    site.free();
    runner.free();
}
