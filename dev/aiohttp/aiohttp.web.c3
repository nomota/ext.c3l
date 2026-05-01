// aiohttp.web.c3

module ext::aiohttp::web;

import ext::aiohttp;
import ext::asyncio;
import ext::serializer::http;
import ext::aiofiles;
import ext::aiofiles::os;
import ext::mem;
import ext::debug;
import ext::thread::fiber;

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
    if (localmem == (LocalAllocator){}) {
        if (aiohttp::localmem == (LocalAllocator){}) {
            aiohttp::localmem = tmem;
        }
        
        localmem = aiohttp::localmem;;
    }
    @assert(localmem != null, "error");
    
    Application* app = localmem.alloc(Application);
    app.router = localmem.alloc(Router);
    app.middleware_count = 0;
    app.client_max_size = client_max_size;
    app.startup_count = 0;
    app.shutdown_count = 0;
    app.cleanup_count = 0;
    app.state_count = 0;
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
    rt.count = 0;
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
fn void Router.add_ws     (&self, String p, WsHandler wh, String name = "") => router_add_ws(&self.inner, p, wh, name)!!;

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
    usz   rem = self.body_len > self.pos ? self.body_len - self.pos : 0;

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
    bp.data = body + p;
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
    char[] body;
    
    String host;
    usz          content_length;
    bool         is_chunked;
    bool         body_read;
}

faultdef NO_BODY;

// caller must not free
fn char[]? Request.read(&self)
{
    if (self.body_read) {
        return self.body;
    }
    if (!self.can_read_body || self.stream == null) {
        return NO_BODY~;
    }

    if (self.is_chunked) {
        ChunkDecoder dec; dec.init();
        usz cap = 8192;
        char* buf = localmem.malloc(cap);
        usz len = 0;
        
        if (self.body.len > 0) {
            dec.feed(self.body.ptr, self.body.len)!;
            len = self.body.len;

            localmem.free(self.body);
            self.body = {};
            len = self.body.len;
        }
        
        while (!dec.done()) {
            char[REQ_READ_BUFSZ] raw;
            usz n = self.stream.read(&raw)!;
            if (n == 0) break;
            dec.feed(&raw[0], n)!;

            ChunkFrame frame;
            while (dec.next(&frame)) {
                if (frame.is_final) break;
                if (len + frame.data_len > cap) {
                    usz nc = (cap + frame.data_len) * 2;
                    char* nb = localmem.malloc(nc);
                    nb[0:len] = buf[0:len];

                    localmem.free(buf);
                    buf = nb;
                    cap = nc;
                }
                buf[len:frame.data_len] = frame.data[0:frame.data_len];
            }
        }
        localmem.free(self.body);
        self.body = buf[0:len];
    } else {
        usz total = self.content_length;
        char* buf = localmem.malloc(total > 0 ? total : REQ_READ_BUFSZ);
        usz len = 0;
        
        if (self.body.len > 0) {
            buf[0:self.body.len] = self.body[0:self.body.len];
            localmem.free(self.body);
            len = self.body.len;
            self.body = {};
        }
        
        while (total == 0 || len < total) {
            usz want = REQ_READ_BUFSZ;
            if (total > 0 && total - len < want) want = total - len;
            usz n = self.stream.read(buf[len:want])!;
            if (n == 0) break;
            len += n;
        }
        localmem.free(self.body);
        self.body = buf[0:len];
    }
    self.body_read = true;

    return self.body;
}

// caller must not free
fn String? Request.text(&self)
{
    char[]? raw = self.read();
    if (catch err = raw) return err~;
    return (String) raw;
}

fn String? Request.json_text(&self) => self.text();

fn Headers*? Request.post(&self)
{
    char[]? raw = self.read();
    if (catch err = raw) return err~;

    String ct = self.headers.get("content-type") ?? "";
    bool is_urlenc = false;
    usz? idx = ct.index_of("application/x-www-form-urlencoded");
    if (try idx) is_urlenc = true;

    Headers* form = aiohttp::headers_new();
    if (!is_urlenc) return form;

    // parse "key=value&key2=value2"
    String body = (String) raw;
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

    char[]? raw = self.read();
    if (catch err = raw) return err~;

    MultipartReader* mr = (MultipartReader*)localmem.malloc($sizeof(MultipartReader));
    mr.body = raw.ptr;
    mr.body_len = raw.len;
    mr.boundary = boundary;
    mr.pos = 0;
    mr.done = false;
    return mr;
}

//  request dispatcher 

// Build Request from parsed http::Request + stream.
fn Request* build_request(http::Request* p, Stream* s, Application* app, char* body_ptr, usz body_len, Allocator alloc
) @private
{
    localmem = alloc;
    Request* req = localmem.alloc(Request);
warn("-");
    HttpMethod? meth = aiohttp::http_method_from_str(p.method);
    req.method = meth ?? HttpMethod.GET;

    String? host = p.get("Host");
    if (try host) {
        req.host = host;
    }
    // parse URL
    aiohttp::Url url_val = aiohttp::url_parse(p.uri) ?? (aiohttp::Url){ .path = p.uri };
    req.url = url_val;
    req.path = p.uri;
warn("-");
    aiohttp::localmem = alloc;
    req.headers = aiohttp::headers_new();
    for (uint i = 0; i < p.n_headers; i++) {
        req.headers.add(p.headers[i].key, p.headers[i].value);
    }
warn("-");
    // query params
    req.query = aiohttp::headers_new();
    p.decode_query();
    for (usz i = 0; i < p.n_queries; i++) {
        String dk = aiohttp::pct_decode(localmem, p.queries[i].key, true);
        String dv = aiohttp::pct_decode(localmem, p.queries[i].value, true);
        req.query.add(dk, dv);
    }
warn("-");
    // cookies
    req.cookies = aiohttp::headers_new();
    p.decode_cookies();
    for (uint i = 0; i < p.n_cookies; i++) {
        req.cookies.add(p.cookies[i].key, p.cookies[i].value);
    }
warn("-");
    req.match_info = aiohttp::headers_new();
    req.can_read_body = true;
    req.app = app;
    req.stream = s;
    
    if (body_len > 0) {
        req.body = localmem.alloc_array(char, body_len);
        req.body[0:body_len] = body_ptr[0:body_len];
    } else {
        req.body = {};
    }

    req.body_read = false;
    
warn("-");
    p.decode_content_length();
    req.content_length = p.content_length;
    req.is_chunked = p.chunked;
warn("-");
    return req;
}

fn void request_free(Request* req) @private
{
    if (req.headers != null) req.headers.free();
    if (req.query != null) req.query.free();
    if (req.cookies != null) req.cookies.free();
    if (req.match_info != null) req.match_info.free();
    if ((void*)req.body != null) localmem.free(req.body);
    localmem.free(req);
}

// Handle one HTTP connection (runs in a fiber spawned by asyncio::start_server).
fn void? handle_connection(Stream* stream, Application* app) @private
{
    char[REQ_READ_BUFSZ * 2] buf;
    usz filled = 0;

    // Read until full request headers are available.
    bool got_req = false;
    while (!got_req && filled < buf.len) {
warn("-");
        usz? n = stream.read_any(buf[filled:buf.len - filled]);
        if (catch err = n) {
            warn("%s", err);
            return;
        }
        if (n == 0) {
            warn("eof");
            return;
        }
        filled += n;
        
warn("buf[%s]", (String)buf[0:filled]);
        for (usz i = 0; i + 1 < filled; i++) {
            if (i+3 < filled && buf[i]=='\r'&&buf[i+1]=='\n'&&buf[i+2]=='\r'&&buf[i+3]=='\n') { got_req = true;
                break;
            }
            if (i+2 < filled && buf[i]=='\n'&&buf[i+1]=='\r'&&buf[i+2]=='\n') { got_req = true;
                break;
            }
            if (i+1 < filled && buf[i]=='\n'&&buf[i+1]=='\n') { got_req = true;
                break;
            }
        }
    }
    if (!got_req) {
        warn("header is too large");
        return; // headers too large
    }
    
    http::Request parsed;
    char*? body_ptr = http::parse_request(&buf[0], &buf[filled], &parsed);
    if (catch err = body_ptr) {
        warn("bad request");
        // send 400
        Response* bad = http_bad_request();
        defer bad.free();
        (void)write_response(stream, bad);
        return;
    }
    usz body_len = (usz)(&buf[filled] - body_ptr);

warn("header parsed");
    
    Request* req = build_request(&parsed, stream, app, body_ptr, body_len, localmem);
warn("-");
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
warn("-");
    if (is_ws_upgrade) {
        RouteMatch ws_match;
        bool found = router_match_ws(&app.router.inner, req.path, &ws_match);
warn("-");
        if (!found) {
            Response* r = http_not_found();
            defer r.free();
            defer request_free(req);
warn("-");
            (void)write_response(stream, r);
            return;
        }
            
        // fill match_info
        req.match_info.free();
        req.match_info = router_match_info(&ws_match, localmem)!;
warn("-");
        WebSocketResponse* ws = ws_response_new();
        defer ws.free();
        (void)ws.prepare(req);
        (void)ws_match.ws_handler(req, ws);
    } else {
        RouteMatch match;
        bool found = router_match(&app.router.inner, req.method, req.path, &match);
warn("-");
        if (!found) {
            Response* r = http_not_found();
            defer r.free();
            request_free(req);
warn("-");
            (void) write_response(stream, r);
            return;
        }
        req.match_info.free();
        req.match_info = router_match_info(&match, localmem)!;
warn("-");
        // run middleware chain
        MwTable mw_table;
        mw_table_init(&mw_table);
        for (usz i = 0; i < app.middleware_count; i++) {
            mw_table_add(&mw_table, app.middlewares[i]);
        }

        Response*? resp = mw_chain_call(&mw_table, match.handler, req);
warn("-");
        if (catch errr = resp) {
            Response* err = http_internal_server_error();
            defer err.free();
            defer request_free(req);
warn("-");
            (void)write_response(stream, err);
            return;
        }

        if (resp != null) {
            defer resp.free();
warn("-");
            (void)write_response(stream, resp);
        }
    }
warn("-");
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
    double      shutdown_timeout;
    TlsConfig* tls;
    int        backlog;
    Server*    server;
}

// Thread-local pointer so the fiber handler can reach the Application.
tlocal Application* serving_app @private = null;

fn void tcp_client_handler(Stream* stream) @private
{
  @pool() {
    warn("handle_connection()");
fiber::diag();

    if (catch err = handle_connection(stream, serving_app)) {
        warn("%s", err);
    }

    warn("stream.close()");
    stream.close();
  };
}

fn TcpSite* tcpsite_new(
    AppRunner* runner,
    String     host = "0.0.0.0",
    ushort     port = 8080,
    double      shutdown_timeout = 60.0,
    TlsConfig* tls = null,
    int        backlog = 128,
)
{
    TcpSite* site = localmem.alloc(TcpSite);
    site.runner = runner;
    site.host = host;
    site.port = port;
    site.shutdown_timeout = shutdown_timeout;
    site.tls = tls;
    site.backlog = backlog;
    site.server = null;
    return site;
}

fn void? TcpSite.start(&self) @maydiscard
{
    self.runner.setup()!;
    serving_app = self.runner.app;

    Server*? srv = asyncio::start_server(
        &tcp_client_handler, self.host, self.port
    );
    if (catch err = srv) return aiohttp::CONNECTION_FAILED~;
    self.server = srv;
    
    warn("srv.serve_forever()");
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

tlocal AppRunner* runner = null;
tlocal TcpSite* site = null;

fn void site_run_coro()
{
    if (catch err = site.start()) {
        warn("TcpSite.start() failed: %s", err);
        return;
    }
    warn("TcpSite.start() success");
    
    (void)site.stop();
    warn("site.stop()");
}

//  top-level run_app 

tlocal String g_server_header = "";

fn void? run_app(
    Application* app,
    String       host = "0.0.0.0",
    ushort       port = 8080,
    // String path = "/unix/domain/sock",
    double shutdown_timeout = 60,
    TlsConfig*   ssl_context = null,
    int backlog = 128,
    String server_header = "",
) @maydiscard
{
    warn("AppRunner new()");
    // AppRunner* 
    runner = runner_new(app);
    g_server_header = server_header;
    
    warn("TcpSite new %s:%d", host, port);
    // TcpSite* 
    site = tcpsite_new(runner, host, port, shutdown_timeout, ssl_context, backlog);

    asyncio::run(&site_run_coro);
    
    warn("site.free()");
    site.free();
    runner.free();
}
