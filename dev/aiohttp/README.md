// aiohttp README.md

# ext::aiohttp

Asynchronous HTTP client and server framework on top of the
[ext::asyncio](../asyncio/README.md) framework.

This module follows mostly the [Python's aiohttp API](PythonAPI.md), while
adapting the programming model to C3: explicit response objects, fault-returning
I/O operations, and event-loop based asynchronous execution.

`ext::aiohttp` provides:

* HTTP/1.1 client
* HTTP/1.1 web server
* routing with path parameters
* middleware chain
* request and response helpers
* cookie/header utilities
* form and multipart helpers
* streaming response
* static file response
* WebSocket client/server helpers
* URL, chunked-transfer, and WebSocket protocol utilities

### Available modules

| Module | Description |
|--------|-------------|
| `ext::aiohttp` | Shared HTTP types: `HttpMethod`, `Url`, `Headers`, `CookieJar`, `ClientTimeout`, `TlsConfig`, `BasicAuth`, `FormData`, `WsMessage` |
| `ext::aiohttp` | HTTP client API: `ClientSession`, `TcpConnector`, request methods, response reading, WebSocket client |
| `ext::aiohttp::web` | HTTP server API: `Application`, router, request/response handling, middleware, streaming response, file response, WebSocket server, `run_app()` |
| `ext::aiohttp::web` | Built-in middleware helpers: error handler, logger, CORS, basic auth, max body size |
| `ext::aiohttp` | URL parsing, percent encode/decode, query string building |
| `ext::aiohttp` | Chunked transfer encoding and decoding |
| `ext::aiohttp` | WebSocket handshake, frame encoding, frame decoding |

This is a part of extended C3 library.  
Back to [ext.c3l](../../README.md) library.

### Files

* [aiohttp.types.c3](aiohttp.types.c3)
* [aiohttp.client.c3](aiohttp.client.c3)
* [aiohttp.web.c3](aiohttp.web.c3)
* [client.dns.c3](client.dns.c3)
* [client.pool.c3](client.pool.c3)
* [client.req.c3](client.req.c3)
* [util.url.c3](util.url.c3)
* [util.chunk.c3](util.chunk.c3)
* [util.ws.c3](util.ws.c3)
* [web.middleware.c3](web.middleware.c3)

### API functions

Following functions follow Python-like behavior, all of them are
asynchronous/non-blocking under the framework of `asyncio`.

## Server API

Basic web server:

```c3
import ext::aiohttp::web;
import c::stdio;

fn Response*? handle_root(Request* req)
{
    return web::response_new(200, "Welcome to the aiohttp server!");
}

fn Response*? handle_greet(Request* req)
{
    String name = req.match_info.get("name") ?? "Anonymous";

    char[256] buf;
    int n = stdio::snprintf(&buf[0], buf.len, "Hello, %s!", name.ptr);

    return web::response_new(
        200,
        "", // empty text
        &buf[0], // body
        n, // body len
        "text/plain",
        "utf-8",
    );
}

fn void main()
{
    Application* app = web::app_new();

    app.router.add_get("/", &handle_root);
    app.router.add_get("/{name}", &handle_greet);

    web::run_app(app, port: 8080)!!;
}
```

Application:

```c3
import ext::aiohttp::web;

/*
fn Application* app_new(usz client_max_size = 1024 * 1024)
*/
Application* app = web::app_new();
Application* app = web::app_new(1024 * 1024);

void app.free();

void app.on_startup(AppHook hook);
void app.on_shutdown(AppHook hook);
void app.on_cleanup(AppHook hook);

void? app.set_state(String key, void* value);
void* value = app.get_state(String key);
```

Routing:

```c3 
import ext::aiohttp::web;

RouteTable* routes = web::routetable_new();

routes.get("/", handle_root);
routes.get("/{name}", handle_greet);
routes.post("/submit", handle_submit);
routes.put("/items/{id}", handle_put);
routes.patch("/items/{id}", handle_patch);
routes.delete("/items/{id}", handle_delete);
routes.head("/items/{id}", handle_head);
routes.options("/items", handle_options);
routes.ws("/ws", handle_ws);

app.add_routes(routes)!!;
```

Or add routes directly to the application router:
    
```c3 
import ext::aiohttp::web;

app.router.add_get("/", handle_root);
app.router.add_post("/submit", handle_submit);
app.router.add_static("/static", "./public")!!;
```

Named routes and URL building:

```c3 
import ext::aiohttp::web;

app.router.add_get("/users/{id}", handle_user, "user_detail");

Headers* params = headers_new();
params.set("id", "42");

aiohttp::Url? url = app.router.url_for("user_detail", params);
```

Request handlers:

```c3 
import ext::aiohttp::web;

fn Response*? handler(Request* req)
{
    HttpMethod method = req.method;
    String path = req.path;
    aiohttp::Url url = req.url;

    Headers* headers = req.headers;
    Headers* query = req.query;
    Headers* match_info = req.match_info;
    Headers* cookies = req.cookies;

    return web::response_new(200, "OK");
}
```

Request body:

```c3 
import ext::aiohttp::web;

fn Response*? echo(Request* req)
{
    usz len;
    char*? body = req.read(&len);
    if (catch err = body) return err~;

    return web::response_new(
        200,
        "OK",
        body,
        len,
        "text/plain",
        "utf-8",
    );
}

Text and JSON body:

```c3 
import ext::aiohttp::web;

String? text = req.text();
String? json = req.json_text();
```

URL encoded form:

```c3 
import ext::aiohttp::web;

Headers*? form = req.post();
String username = form.get("username") ?? "";
```

Multipart form:

```c3 
import ext::aiohttp::web;

MultipartReader*? reader = req.multipart();
if (catch err = reader) return err~;

BodyPart? part = reader.next();
while (try part) {
    String name = part.name;
    String filename = part.filename;
    String content_type = part.content_type;
    char* data = part.data;
    usz len = part.data_len;

    part.free();
    part = reader.next();
}

reader.free();
```

Response:

```c3
Response* r = web::response_new(200, "Hello");
Response* r = web::response_new(404, "Not Found");
Response* r = web::json_response("{\"ok\":true}");

r.set_header("X-App", "ext::aiohttp");
r.set_cookie(&cookie);

return r;
```

HTTP error helpers:

```c3 
import ext::aiohttp::web;

return web::http_bad_request();
return web::http_unauthorized();
return web::http_forbidden();
return web::http_not_found();
return web::http_method_not_allowed();
return web::http_internal_server_error();

return web::http_redirect("/login");
return web::http_moved_permanently("/new-path");
```

Streaming response:

```c3 
import ext::aiohttp::web;

fn Response*? stream_handler(Request* req)
{
    StreamResponse* resp = web::stream_response_new(200);
    resp.set_header("Content-Type", "text/plain");

    resp.prepare(req)!!;

    resp.write("hello\n".ptr, 6)!!;
    resp.write("world\n".ptr, 6)!!;
    resp.write_eof()!!;

    resp.free();

    return null;
}
```

File response:

```c3 
import ext::aiohttp::web;

fn Response*? download(Request* req)
{
    FileResponse* fr = web::file_response_new("./public/file.txt");
    web::file_response_send(fr, req.stream)!!;
    fr.free();

    return null;
}
```

WebSocket server:

```c3
import ext::aiohttp::web;

fn void ws_handler(Request* req, WebSocketResponse* ws)
{
    ws.prepare(req)!!;

    while (true) {
        WsMessage? msg = ws.receive();
        if (catch err = msg) break;

        switch (msg.type) {
            case WsMsgType.TEXT:
                ws.send_str(msg.as_str())!!;

            case WsMsgType.BINARY:
                ws.send_bytes(msg.data, msg.len)!!;

            case WsMsgType.PING:
                ws.pong()!!;

            case WsMsgType.CLOSE:
                msg.free();
                break;

            default:
        }

        msg.free();
    }

    ws.close()!!;
}

app.router.add_ws("/ws", ws_handler);
```

Application runner and TCP site:

```c3 
import ext::aiohttp::web;

Application* app = web::app_new();

AppRunner* runner = web::runner_new(app);
runner.setup()!!;

TcpSite* site = web::tcpsite_new(runner, "0.0.0.0", 8080);
site.start()!!;

// later
site.stop()!!;
runner.cleanup()!!;

site.free();
runner.free();
```

Simple run:

```c3 
import ext::aiohttp::web;

web::run_app(app, port: 8080)!!;
```

## Middleware

Middleware follows the same conceptual model as Python aiohttp middleware:

```python
async def middleware(request, handler):
    return await handler(request)
```

C3 equivalent:

```c3 
import ext::aiohttp::web;

fn Response*? middleware(Request* req, NextHandler next)
{
    return next(req);
}
```

Logger middleware:

```c3 
import ext::aiohttp::web;

fn Response*? logger(Request* req, NextHandler next)
{
    io::printfn("%s %s", req.method.str(), req.path);
    return next(req);
}

app.add_middleware(&logger);
```

Short-circuit middleware:

```c3
import ext::aiohttp::web;

fn Response*? auth_required(Request* req, NextHandler next)
{
    String token = req.headers.get("Authorization") ?? "";
    if (token.len == 0) {
        return http_unauthorized("Missing Authorization header");
    }

    return next(req);
}

app.add_middleware(&auth_required);
```

Built-in middleware helpers:

```
import ext::aiohttp::web;

app.add_middleware(mw_error_handler);
app.add_middleware(mw_logger);

CorsConfig cors = {
    .allow_origin = "*",
    .allow_methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS",
    .allow_headers = "Content-Type,Authorization",
};

MiddlewareFn? cors_mw = mw_cors_make(&cors);
app.add_middleware(cors_mw!!);

MiddlewareFn? auth_mw = mw_basic_auth_make("user:password");
app.add_middleware(auth_mw!!);

MiddlewareFn? limit_mw = mw_max_body_make(1024 * 1024);
app.add_middleware(limit_mw!!);
```

## Client API

Create a session:

```c3 
import ext::aiohttp;

ClientSession* session = aiohttp::session_new();

/*
fn ClientSession* session_new(
    TcpConnector* connector        = null,
    ClientTimeout timeout          = { .total_us = 30_000_000 },
    Headers*      default_headers  = null,
    BasicAuth*    auth             = null,
    CookieJar*    cookie_jar       = null,
    bool          raise_for_status = false,
)
*/
```

Simple GET:

```c3
import ext::aiohttp;

ClientResponse*? resp = session.get("http://example.com/");
if (catch err = resp) return err~;

io::printfn("status = %d", resp.status);

String? text = resp.text();
if (try text) {
    io::printfn("%s", text);
}

resp.release();
session.close();
```

Request methods:

```c3
import ext::aiohttp;

ClientResponse*? r = session.request(HttpMethod.GET, "http://example.com/");
ClientResponse*? r = session.get("http://example.com/");
ClientResponse*? r = session.post("http://example.com/", data, data_len);
ClientResponse*? r = session.put("http://example.com/", data, data_len);
ClientResponse*? r = session.patch("http://example.com/", data, data_len);
ClientResponse*? r = session.delete("http://example.com/");
ClientResponse*? r = session.head("http://example.com/");
ClientResponse*? r = session.options("http://example.com/");
```

Query parameters:

```c3 
import ext::aiohttp;

Headers* params = aiohttp::headers_new();
params.set("q", "c3");
params.set("page", "1");

/*
fn ClientResponse*? ClientSession.get(&self,
    String url,
    Headers* params = null,
    Headers* headers = null,
    TlsConfig* tls = null)
*/
ClientResponse*? resp = session.get(
    "http://example.com/search",
    params,
);
```

Custom headers:

```c3
import ext::aiohttp;

Headers* headers = aiohttp::headers_new();
headers.set("User-Agent", "ext::aiohttp");
headers.set("Accept", "application/json");

ClientResponse*? resp = session.get(
    "http://example.com/api",
    null, // params
    headers,
);
```

POST JSON:

```c3 
import ext::aiohttp;
/*
fn ClientResponse*? ClientSession.post(&self,
    String url,
    char* data = null,
    usz data_len = 0,
    String json_str = "",
    FormData* form = null,
    Headers* headers = null,
    TlsConfig* tls = null) 
*/
ClientResponse*? resp = session.post(
    "http://example.com/api",
    null, // data
    0, // data_len
    "{\"name\":\"c3\"}", // json_str
);
```

POST form-data:

```c3 
import ext::aiohttp;

FormData* form = aiohttp::formdata_new();

form.add_str("name", "c3");
form.add_field(
    "file",
    (char*)data.ptr,
    data.len,
    "hello.txt",
    "text/plain",
);

ClientResponse*? resp = session.post(
    "http://example.com/upload",
    null, // data
    0, // data_len
    null, // json_str
    form,
);

form.free();
```

Response API:

```c3
import ext::aiohttp;

int status = resp.status;
String reason = resp.reason;
Headers* headers = resp.headers;
CookieJar* cookies = resp.cookies;

usz len;
char*? body = resp.read(&len);

String? text = resp.text();
String? json = resp.json_text();

resp.raise_for_status();

Stream* content = resp.content();

resp.release();
```

Connector:

```c3 
import ext::aiohttp;

/*
fn TcpConnector* connector_new(
    int        limit                = 100,
    int        limit_per_host       = 0,
    TlsConfig* tls                  = null,
    usz        read_bufsize         = 65536,
    bool       use_dns_cache        = true,
    ulong      ttl_dns_cache_us     = 10_000_000,
    ulong      keepalive_timeout_us = 15_000_000,
    bool       force_close          = false,
)
*/

TcpConnector* connector = aiohttp::connector_new(
    100, // limit: 100,
    10, // limit_per_host: 10,
    null, // TlsConfig*
    65_536, // read_bufsize
    true, // use_dns_cache
    10_000_000, // ttl_dns_cache_us
    15_000_000, // keepalive_timeout_us
);

/*
fn ClientSession* session_new(
    TcpConnector* connector        = null,
    ClientTimeout timeout          = { .total_us = 30_000_000 },
    Headers*      default_headers  = null,
    BasicAuth*    auth             = null,
    CookieJar*    cookie_jar       = null,
    bool          raise_for_status = false,
)
*/

ClientSession* session = aiohttp::session_new(connector);

int total = connector.total_conns();

session.close();
```

Timeout:

```c3 
import ext::aiohttp;

ClientTimeout timeout = {
    .total_us = 30_000_000,
};

TcpConnector* connector = null;
ClientSession* session = aiohttp::session_new(connector, timeout);
```

TLS configuration:

* Note: TLS is not yet supported

```c3 
import ext::aiohttp;

TlsConfig tls = {
    .verify_peer = true,
};

ClientResponse*? resp = session.get(
    "https://example.com/",
    null, // params
    null, // headers
    &tls,
);
```

Basic auth:

```c3 
import ext::aiohttp;

BasicAuth auth = {
    .login = "user",
    .password = "password",
};

/*
fn ClientSession* session_new(
    TcpConnector* connector        = null,
    ClientTimeout timeout          = { .total_us = 30_000_000 },
    Headers*      default_headers  = null,
    BasicAuth*    auth             = null,
    CookieJar*    cookie_jar       = null,
    bool          raise_for_status = false,
)
*/
TcpConnector* connector = null;
ClientTimeout timeout = {};
Headers* headers = null;

ClientSession* session = aiohttp::session_new(connector, timeout, headers, &auth);
```

Cookie jar:

```c3 
import ext::aiohttp;

TcpConnector* connector = null;
ClientTimeout timeout = {};
Headers* headers = null;
BasicAuth* auth = null;

CookieJar* jar = aiohttp::cookiejar_new();

ClientSession* session = aiohttp::session_new(connector, timeout, headers, auth, jar);
```

Client WebSocket:

```c3 
import ext::aiohttp;

ClientSession* session = aiohttp::session_new();

ClientWs*? ws = session.ws_connect("ws://localhost:8080/ws");
if (catch err = ws) return err~;

ws.send_str("hello")!!;

WsMessage? msg = ws.receive();
if (try msg) {
    if (msg.type == WsMsgType.TEXT) {
        io::printfn("received: %s", msg.as_str());
    }
    msg.free();
}

ws.close()!!;
ws.free();

session.close();
```

WebSocket send helpers:

```c3 
import ext::aiohttp;

ws.send_str("hello")!!;
ws.send_bytes(data, len)!!;
ws.send_json("{\"op\":\"ping\"}")!!;
ws.ping()!!;
ws.pong()!!;
```

WebSocket receive helpers:

```c3
import ext::aiohttp;

WsMessage? msg = ws.receive();

String? text = ws.receive_str();

usz len;
char*? data = ws.receive_bytes(&len);

String? json = ws.receive_json();
```

Shared types

HTTP method:

```c3
import ext::aiohttp;

HttpMethod m = HttpMethod.GET;
String s = m.str();

HttpMethod? m = http_method_from_str("POST");
```

Headers:

```c3
import ext::aiohttp;

Headers* h = aiohttp::headers_new();

h.set("Content-Type", "application/json");
h.add("Set-Cookie", "a=1");

String ct = h.get("Content-Type") ?? "";
bool has_ct = h.has("Content-Type");

Header first = h.get_at(0);
usz count = h.len();

h.del("Content-Type");
h.free();
```

Cookies:

```c3 
import ext::aiohttp;

CookieJar* jar = aiohttp::cookiejar_new();

Cookie cookie = {
    .name = "sid",
    .value = "123",
    .path = "/",
    .http_only = true,
};

jar.update(&cookie, 1, &url);

usz count;
Cookie* cookies = jar.filter(&url, &count);

jar.free();
```

FormData:

```c3 
import ext::aiohttp;

FormData* form = aiohttp::formdata_new();

form.add_str("name", "value");

form.add_field(
    "file",
    data,
    data_len,
    "file.txt",
    "text/plain",
);

form.free();
```

Status helpers:

```c3 
import ext::aiohttp;

String reason = aiohttp::http_reason(200);

bool ok = aiohttp::http_status_is_success(200);
bool redirect = aiohttp::http_status_is_redirect(302);
bool err = aiohttp::http_status_is_error(500);
bool client_err = aiohttp::http_status_is_client_err(404);
bool server_err = aiohttp::http_status_is_server_err(500);
```

URL utilities

```c3 
import ext::aiohttp;

aiohttp::Url? url = aiohttp::url_parse("https://example.com:8443/path?q=1");

bool tls = url.is_tls();
ushort port = url.effective_port();

String encoded = aiohttp::pct_encode(localmem, "hello world", false);
String decoded = aiohttp::pct_decode(localmem, "hello%20world", false);

String full = url.to_string(localmem);
```

Query building:

```c3 
import ext::aiohttp;

Headers* params = aiohttp::headers_new();
params.set("q", "c3");
params.set("page", "1");

String query = aiohttp::query_build(localmem, params);
```

Chunked transfer utilities

```c3 
import ext::aiohttp;

usz size = aiohttp::chunk_encoded_size(data_len);

char* out = localmem.malloc(size);
usz n = aiohttp::chunk_encode(out, data, data_len);

char[16] final_chunk;
usz final_len = aiohttp::chunk_encode_final(&final_chunk[0]);
```

Chunk decoder:

```c3 
import ext::aiohttp;

ChunkDecoder dec;
dec.init();

dec.feed(data, len)!!;

ChunkFrame frame;
while (dec.next(&frame)) {
    if (frame.is_final) break;

    char* chunk_data = frame.data;
    usz chunk_len = frame.data_len;
}

bool done = dec.done();
```

WebSocket utilities

Low-level WebSocket helpers are available for protocol implementation.

```c3 
import ext::aiohttp;

String accept = aiohttp::ws_accept_key(localmem, client_key);

usz frame_size = aiohttp::ws_frame_size(payload_len, true);

String? frame = aiohttp::ws_frame_encode_alloc(
    localmem,
    WsMsgType.TEXT,
    data,
    len,
    true,
);
```

Decoder:

```c3 
import ext::aiohttp;

/*
fn void WsDecoder.init(&self, bool expect_masked, usz max_payload = 0)
*/
WsDecoder dec;
dec.init(true);

dec.feed(data, len)!!;

WsFrame frame;
while (dec.next(&frame)!!) {
    switch (frame.type) {
        case WsMsgType.TEXT:
        case WsMsgType.BINARY:
        case WsMsgType.PING:
        case WsMsgType.PONG:
        case WsMsgType.CLOSE:
        default:
    }
}
```

Examples

../../examples/aiohttp/web_hello.c3

../../examples/aiohttp/web_routes.c3

../../examples/aiohttp/web_middleware.c3

../../examples/aiohttp/web_static.c3

../../examples/aiohttp/websocket_server.c3

../../examples/aiohttp/client_get.c3

../../examples/aiohttp/client_post.c3

../../examples/aiohttp/websocket_client.c3


This is a part of extended C3 library.  
Back to [ext.c3l](../../README.md) library.
