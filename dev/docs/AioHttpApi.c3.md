# ext::aiohttp for C3

C3 port of Python aiohttp. Runs on top of [`ext::asyncio`](../asyncio/README.md),
Two modules: client(`ext::aiohttp`) and server(`ext::aiohttp::web`).

---

## Available modules

| Module | File | Description |
|------|------|------|
| `ext::aiohttp` | `aiohttp.types.c3` | Shared Types: Url, Headers, Cookie, ClientTimeout, TlsConfig, BasicAuth, WsMessage, FormData |
| `ext::aiohttp` | `aiohttp.c3` | HTTP Client: ClientSession, TcpConnector, ClientResponse, ClientWs |
| `ext::aiohttp::web` | `aiohttp.web.c3` | HTTP Server: Application, Router, Request, Response, StreamResponse, FileResponse, WebSocketResponse, AppRunner, TcpSite |

---

## Shared Types (`aiohttp.types.c3`)

```c3
module ext::aiohttp;

// Fault definitions

fault HttpClientError {
    CONNECTION_FAILED,
    TIMEOUT,
    SSL_ERROR,
    TOO_MANY_REDIRECTS,
    INVALID_URL,
    RESPONSE_ERROR,
    WS_ERROR,
    CANCELLED,
}

// HTTP method

enum HttpMethod : int {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    HEAD,
    OPTIONS,
}

// URL

struct Url {
    String scheme;
    String host;
    ushort port;
    String path;
    String query;
    String fragment;
    String raw;         // original raw string
}

fn Url? aiohttp::url_parse(String raw);       // parse URL, returns fault on invalid
fn String Url.to_string(&self);                 // rebuild URL string, must free

// Headers (case-insensitive key-value pairs)

struct Header {
    String name;
    String value;
}

struct Headers {
    Header* entries;
    usz     count;
    usz     capacity;
}

fn Headers*  aiohttp::headers_new();
fn void      Headers.free(&self);
fn String?   Headers.get(&self, String name);       // case-insensitive lookup
fn void      Headers.set(&self, String name, String value);
fn void      Headers.add(&self, String name, String value);
fn void      Headers.del(&self, String name);
fn Header    Headers.get_at(&self, usz idx);
fn usz       Headers.len(&self);

// Cookie

struct Cookie {
    String name;
    String value;
    String domain;
    String path;
    long   expires;     // unix timestamp, 0 = session cookie
    bool   secure;
    bool   http_only;
    String same_site;   // "Strict" | "Lax" | "None" | ""
}

// CookieJar

struct CookieJar {
    Cookie* cookies;
    usz     count;
    bool    unsafe;     // allow cookies for IP address targets
}

struct DummyCookieJar {} // ignores all cookies (for API usage)

fn CookieJar* aiohttp::cookiejar_new(bool unsafe_ips = false);
fn void       CookieJar.free(&self);
fn void       CookieJar.update(&self, Cookie* cookies, usz count, Url* response_url);
fn Cookie*    CookieJar.filter(&self, Url* url, usz* out_count); // must free result
fn Cookie     CookieJar.get_at(&self, usz idx);
fn usz        CookieJar.len(&self);

// Timeout

struct ClientTimeout {
    ulong total_us;         // total request timeout (connect+read). 0 = no limit
    ulong connect_us;       // connection pool wait + socket connect
    ulong sock_connect_us;  // socket connect only
    ulong sock_read_us;     // per single read() call
}

// TLS config (BearSSL wrapper)

struct TlsConfig {
    bool   verify_peer;     // default true
    String ca_file;         // PEM CA bundle path. "" = system default
    String cert_file;       // client certificate (mutual TLS). "" = none
    String key_file;        // client private key. "" = none
}

// Basic Auth

struct BasicAuth {
    String username;
    String password;
}

fn String BasicAuth.encode(&self); // "Basic <base64>", must free

// WebSocket types

enum WsMsgType : int {
    TEXT,
    BINARY,
    PING,
    PONG,
    CLOSE,
    ERROR,
}

enum WsCloseCode : ushort {
    NORMAL_CLOSURE   = 1000,
    GOING_AWAY       = 1001,
    UNSUPPORTED_DATA = 1003,
    INVALID_PAYLOAD  = 1007,
    POLICY_VIOLATION = 1008,
    MESSAGE_TOO_BIG  = 1009,
    INTERNAL_ERROR   = 1011,
}

struct WsMessage {
    WsMsgType type;
    char*     data;
    usz       data_len;
    String    extra;    // close reason or error string
}

fn void WsMessage.free(&self);

// FormData (multipart/form-data builder)

struct FormDataField {
    String name;
    char*  data;
    usz    data_len;
    String filename;        // "" = plain field
    String content_type;    // "" = auto-detect
}

struct FormData {
    FormDataField* fields;
    usz            count;
    usz            capacity;
}

fn FormData* aiohttp::formdata_new();
fn void      FormData.free(&self);
fn void      FormData.add_field(
    &self,
    String name,
    char*  data,
    usz    data_len,
    String filename     = "",
    String content_type = "",
);
fn void FormData.add_str(&self, String name, String value);
```

---

## HTTP Client (`aiohttp.c3`)

```c3
module ext::aiohttp;
import ext::asyncio;

// TcpConnector

struct TcpConnector {
    int        limit;                // total concurrent connections. default 100, 0=unlimited
    int        limit_per_host;       // per-host limit. default 0=unlimited
    TlsConfig* tls;                  // null = system default CA
    usz        read_bufsize;         // read buffer per connection. default 65536
    bool       use_dns_cache;        // default true
    ulong      ttl_dns_cache_us;     // DNS cache TTL. default 10_000_000 (10s)
    ulong      keepalive_timeout_us; // default 15_000_000 (15s)
    bool       force_close;          // close connection after each request. default false
    bool       closed;
}

fn TcpConnector* aiohttp::connector_new(
    int        limit                = 100,
    int        limit_per_host       = 0,
    TlsConfig* tls                  = null,
    usz        read_bufsize         = 65536,
    bool       use_dns_cache        = true,
    ulong      ttl_dns_cache_us     = 10_000_000,
    ulong      keepalive_timeout_us = 15_000_000,
    bool       force_close          = false,
);

fn void TcpConnector.close(&self);      // drain active connections then free (async)
fn int  TcpConnector.total_conns(&self);

// ClientSession

struct ClientSession {
    TcpConnector* connector;
    ClientTimeout timeout;
    Headers*      default_headers;
    BasicAuth*    auth;             // null = no auth
    CookieJar*    cookie_jar;       // null = use default CookieJar
    bool          raise_for_status; // true: automatically raise fault on 4xx/5xx
    bool          closed;
}

fn ClientSession* aiohttp::session_new(
    TcpConnector* connector        = null,  // null = create default connector
    ClientTimeout timeout          = { .total_us = 30_000_000 },
    Headers*      default_headers  = null,
    BasicAuth*    auth             = null,
    CookieJar*    cookie_jar       = null,
    bool          raise_for_status = false,
);

fn void ClientSession.close(&self);    // drain connections + free resources (async)

// HTTP methods
// All async (asyncio fiber-based). Returned ClientResponse* must be .release()'d.

fn ClientResponse*? ClientSession.get(
    &self,
    String     url,
    Headers*   params  = null,  // query parameters
    Headers*   headers = null,
    TlsConfig* tls     = null,
) @maydiscard;

fn ClientResponse*? ClientSession.post(
    &self,
    String     url,
    char*      data      = null,
    usz        data_len  = 0,
    String     json_str  = "",  // if non-empty, sets Content-Type: application/json
    FormData*  form      = null,
    Headers*   headers   = null,
    TlsConfig* tls       = null,
) @maydiscard;

fn ClientResponse*? ClientSession.put(
    &self,
    String     url,
    char*      data      = null,
    usz        data_len  = 0,
    String     json_str  = "",
    Headers*   headers   = null,
    TlsConfig* tls       = null,
) @maydiscard;

fn ClientResponse*? ClientSession.patch(
    &self,
    String     url,
    char*      data      = null,
    usz        data_len  = 0,
    String     json_str  = "",
    Headers*   headers   = null,
    TlsConfig* tls       = null,
) @maydiscard;

fn ClientResponse*? ClientSession.delete(
    &self,
    String     url,
    Headers*   headers = null,
    TlsConfig* tls     = null,
) @maydiscard;

fn ClientResponse*? ClientSession.head(
    &self,
    String     url,
    Headers*   headers = null,
    TlsConfig* tls     = null,
) @maydiscard;

fn ClientResponse*? ClientSession.options(
    &self,
    String     url,
    Headers*   headers = null,
    TlsConfig* tls     = null,
) @maydiscard;

fn ClientResponse*? ClientSession.request(
    &self,
    HttpMethod method,
    String     url,
    Headers*   params    = null,
    Headers*   headers   = null,
    char*      data      = null,
    usz        data_len  = 0,
    String     json_str  = "",
    FormData*  form      = null,
    TlsConfig* tls       = null,
) @maydiscard;

// ClientResponse

struct ClientResponse {
    int        status;
    String     reason;
    Url        url;
    Headers*   headers;
    CookieJar* cookies;    // cookies received from this response
    bool       released;
}

fn String?  ClientResponse.text(&self, String encoding = "utf-8"); // must free
fn char*?   ClientResponse.read(&self, usz* out_len);              // must free
fn String?  ClientResponse.json_text(&self);                       // must free
fn void     ClientResponse.raise_for_status(&self);                // 4xx/5xx -> fault
fn void     ClientResponse.release(&self);                         // return connection to pool
fn Stream*  ClientResponse.content(&self);                         // streaming body reader

// WebSocket client

struct ClientWs {
    bool   closed;
    String protocol;    // negotiated sub-protocol
    int    compress;    // negotiated per-message deflate level (0=off)
}

fn ClientWs*? ClientSession.ws_connect(
    &self,
    String     url,
    ulong      heartbeat_us        = 30_000_000,  // auto-ping interval. 0=disabled
    ulong      receive_timeout_us  = 30_000_000,
    int        compress            = 0,
    String*    protocols           = null,
    usz        protocols_count     = 0,
    TlsConfig* tls                 = null,
) @maydiscard;

fn void?    ClientWs.close(&self,
    WsCloseCode code    = WsCloseCode.NORMAL_CLOSURE,
    char*       message = null,
    usz         msg_len = 0,
) @maydiscard;

fn void?    ClientWs.send_str(&self, String data) @maydiscard;
fn void?    ClientWs.send_bytes(&self, char* data, usz len) @maydiscard;
fn void?    ClientWs.send_json(&self, String json_str) @maydiscard;
fn void?    ClientWs.ping(&self, char* message = null, usz msg_len = 0) @maydiscard;
fn void?    ClientWs.pong(&self, char* message = null, usz msg_len = 0) @maydiscard;

fn WsMessage?  ClientWs.receive(&self);
fn String?     ClientWs.receive_str(&self);                  // must free
fn char*?      ClientWs.receive_bytes(&self, usz* out_len);  // must free
fn String?     ClientWs.receive_json(&self);                 // must free

fn String      ClientWs.get_peername(&self);  // "host:port"
fn fault?      ClientWs.exception(&self);     // last error. null if none
fn void        ClientWs.free(&self);
```

---

## HTTP Server (`aiohttp.web.c3`)

```c3
module ext::aiohttp::web;
import ext::aiohttp;
import ext::asyncio;

// Fault definitions

fault HttpServerError {
    BAD_REQUEST,             // 400
    UNAUTHORIZED,            // 401
    FORBIDDEN,               // 403
    NOT_FOUND,               // 404
    METHOD_NOT_ALLOWED,      // 405
    CONFLICT,                // 409
    UNPROCESSABLE,           // 422
    TOO_MANY_REQUESTS,       // 429
    INTERNAL_SERVER_ERROR,   // 500
    NOT_IMPLEMENTED,         // 501
    BAD_GATEWAY,             // 502
    SERVICE_UNAVAILABLE,     // 503
}

// Handler / middleware type aliases

alias RequestHandler = fn Response*?(Request*);
alias NextHandler    = fn Response*?(Request*);
alias MiddlewareFn   = fn Response*?(Request*, NextHandler next);
alias AppHook        = fn void?(Application*);
alias WsHandler      = fn void?(Request*, WebSocketResponse*);

// Application

struct AppStateEntry {
    String key;
    void*  value;
}

struct Application {
    Router*        router;
    MiddlewareFn*  middlewares;
    usz            middleware_count;
    usz            client_max_size;   // default 1 MiB
    AppHook*       startup_hooks;
    usz            startup_count;
    AppHook*       shutdown_hooks;
    usz            shutdown_count;
    AppHook*       cleanup_hooks;
    usz            cleanup_count;
    AppStateEntry* state;
    usz            state_count;
}

fn Application* web::app_new(usz client_max_size = 1024 * 1024);
fn void         Application.free(&self);

fn void    Application.add_routes(&self, RouteTable* routes);
fn void    Application.add_middleware(&self, MiddlewareFn mw);
fn void    Application.on_startup(&self, AppHook hook);
fn void    Application.on_shutdown(&self, AppHook hook);
fn void    Application.on_cleanup(&self, AppHook hook);

fn void?   Application.set_state(&self, String key, void* value) @maydiscard;
fn void*   Application.get_state(&self, String key);   // null if not found

// Router & RouteTable

struct Route {
    HttpMethod     method;
    String         pattern;     // "/users/{id}" or r"/api/{ver:\d+}/"
    RequestHandler handler;
    String         name;        // for URL generation. "" = anonymous
}

struct RouteTable {
    Route* routes;
    usz    count;
    usz    capacity;
}

struct Router {
    RouteTable routes;
}

fn RouteTable* web::routetable_new();
fn void        RouteTable.free(&self);

// RouteTable decorator style (pass to app.add_routes())
fn void RouteTable.get    (&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.post   (&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.put    (&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.patch  (&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.delete (&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.head   (&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.options(&self, String pattern, RequestHandler h, String name = "");
fn void RouteTable.ws     (&self, String pattern, WsHandler h,      String name = "");
fn void RouteTable.add    (&self, HttpMethod m, String pattern, RequestHandler h, String name = "");

// Router inline style (app.router.add_get(...))
fn void Router.add_get    (&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_post   (&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_put    (&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_patch  (&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_delete (&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_head   (&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_options(&self, String pattern, RequestHandler h, String name = "");
fn void Router.add_ws     (&self, String pattern, WsHandler h,      String name = "");
fn void Router.add_static (&self, String url_prefix, String fs_path);

fn Url? Router.url_for(&self, String route_name, Headers* params = null); // reverse URL generation

// MultipartReader / BodyPart

struct BodyPart {
    Headers* headers;
    char*    data;
    usz      data_len;
    String   name;
    String   filename;
}

struct MultipartReader {
    // (internal)
}

fn BodyPart?  MultipartReader.next(&self);
fn void       MultipartReader.free(&self);
fn void       BodyPart.free(&self);

// Request

struct Request {
    HttpMethod   method;
    Url          url;
    String       path;
    Headers*     headers;
    Headers*     query;         // parsed ?key=val query string
    Headers*     match_info;    // path parameters {id: "42"}
    Headers*     cookies;
    bool         can_read_body;
    Application* app;
    // (internal)
}

fn char*?            Request.read(&self, usz* out_len);  // raw bytes, must free
fn String?           Request.text(&self);                 // must free
fn String?           Request.json_text(&self);            // must free
fn Headers*?         Request.post(&self);                 // parse form/urlencoded, must free
fn MultipartReader*? Request.multipart(&self);

// Response

struct Response {
    int      status;
    String   reason;
    Headers* headers;
    char*    body;
    usz      body_len;
    String   content_type;
    String   charset;
}

fn Response* web::response_new(
    int    status       = 200,
    String text         = "",
    char*  body         = null,
    usz    body_len     = 0,
    String content_type = "text/plain",
    String charset      = "utf-8",
);
fn Response* web::json_response(String json_str, int status = 200);
fn void      Response.free(&self);
fn void      Response.set_header(&self, String name, String value);
fn void      Response.set_cookie(&self, Cookie* cookie);
fn void      Response.del_cookie(&self, String name);

// HTTP error shortcut response builders (return from handler)
fn Response* web::http_bad_request          (String text = "Bad Request");
fn Response* web::http_unauthorized         (String text = "Unauthorized");
fn Response* web::http_forbidden            (String text = "Forbidden");
fn Response* web::http_not_found            (String text = "Not Found");
fn Response* web::http_method_not_allowed   (String text = "Method Not Allowed");
fn Response* web::http_internal_server_error(String text = "Internal Server Error");
fn Response* web::http_redirect             (String location, int status = 302);
fn Response* web::http_moved_permanently    (String location);

// StreamResponse

struct StreamResponse {
    int      status;
    String   reason;
    Headers* headers;
    bool     prepared;
    bool     eof_sent;
}

fn StreamResponse* web::stream_response_new(int status = 200);
fn void?           StreamResponse.prepare(&self, Request* request);
fn void?           StreamResponse.write(&self, char* data, usz len) @maydiscard;
fn void?           StreamResponse.write_eof(&self) @maydiscard;
fn void            StreamResponse.set_header(&self, String name, String value);
fn void            StreamResponse.set_cookie(&self, Cookie* cookie);
fn void            StreamResponse.free(&self);

// FileResponse

struct FileResponse {
    int      status;
    Headers* headers;
    String   filepath;
    String   content_type;  // "" = auto-detect from file extension
}

fn FileResponse* web::file_response_new(
    String filepath,
    int    status       = 200,
    String content_type = "",
);
fn void FileResponse.free(&self);

// WebSocketResponse (server-side)

struct WebSocketResponse {
    bool   closed;
    String protocol;    // negotiated sub-protocol
    int    compress;    // negotiated deflate level (0=off)
    // (internal)
}

fn WebSocketResponse* web::ws_response_new(
    ulong   heartbeat_us    = 0,   // 0 = disabled
    int     compress        = 0,
    String* protocols       = null,
    usz     protocols_count = 0,
);

fn void?  WebSocketResponse.prepare(&self, Request* request);

fn void?  WebSocketResponse.send_str  (&self, String data)              @maydiscard;
fn void?  WebSocketResponse.send_bytes(&self, char* data, usz len)      @maydiscard;
fn void?  WebSocketResponse.send_json (&self, String json_str)          @maydiscard;
fn void?  WebSocketResponse.ping      (&self, char* msg = null, usz len = 0) @maydiscard;
fn void?  WebSocketResponse.pong      (&self, char* msg = null, usz len = 0) @maydiscard;

// receive message
fn WsMessage? WebSocketResponse.receive(&self);

// iteration: while (ws.next(&msg)) { ... ws_message_free(&msg); }
fn bool       WebSocketResponse.next(&self, WsMessage* out_msg);

fn void       WebSocketResponse.close(&self, WsCloseCode code = WsCloseCode.NORMAL_CLOSURE);
fn void       WebSocketResponse.free(&self);

// AppRunner

struct AppRunner {
    Application* app;
    bool         running;
    // (internal)
}

fn AppRunner* web::runner_new(Application* app);
fn void?      AppRunner.setup(&self);    // run startup hooks
fn void?      AppRunner.cleanup(&self);  // run shutdown/cleanup hooks
fn void       AppRunner.free(&self);

// TcpSite

struct TcpSite {
    AppRunner* runner;
    String     host;
    ushort     port;
    ulong      shutdown_timeout_us;  // default 60_000_000 (60s)
    TlsConfig* tls;                  // null = plain HTTP
    int        backlog;              // default 128
}

fn TcpSite* web::tcpsite_new(
    AppRunner* runner,
    String     host                = "0.0.0.0",
    ushort     port                = 8080,
    ulong      shutdown_timeout_us = 60_000_000,
    TlsConfig* tls                 = null,
    int        backlog             = 128,
);

fn void? TcpSite.start(&self) @maydiscard;
fn void? TcpSite.stop(&self)  @maydiscard;
fn void  TcpSite.free(&self);

// Top-level entry point

fn void? web::run_app(
    Application* app,
    String       host = "0.0.0.0",
    ushort       port = 8080,
    TlsConfig*   tls  = null,
) @maydiscard;
```

---

## Example usage

### Client

```c3
import ext::asyncio;
import ext::aiohttp;

fn void main_coro() => @pool()
{
    ClientSession* session = aiohttp::session_new()!!;
    defer session.close();

    // GET request
    ClientResponse* resp = session.get("https://httpbin.org/get")!!;
    defer resp.release();

    resp.raise_for_status();
    usz len;
    char* body = resp.read(&len)!!;
    // defer free(body); // @pool()

    // POST JSON
    ClientResponse* resp2 = session.post(
        "https://httpbin.org/post",
        .json_str = `{"key":"value"}`,
    )!!;
    defer resp2.release();

    // streaming download
    ClientResponse* resp3 = session.get("https://example.com/large")!!;
    defer resp3.release();
    Stream* content = resp3.content();
    char[65536] chunk;
    usz n;
    while ((n = content.read(chunk[:])) > 0) {
        // process...
    }
}

fn void main() {
    asyncio::run(&main_coro);
}
```

### Server

```c3
import ext::asyncio;
import ext::aiohttp::web;

fn Response*? index_handler(Request* req) {
    return web::response_new(.text = "Hello, World!");
}

fn Response*? echo_handler(Request* req) {
    String? body = req.text()!;
    return web::json_response(body);
}

fn void? ws_handler(Request* req, WebSocketResponse* ws) {
    ws.prepare(req)!;
    WsMessage msg;
    while (ws.next(&msg)) {
        defer msg.free();
        if (msg.type == WsMsgType.TEXT) {
            ws.send_str(String.new_from_ptr(msg.data, msg.data_len))!;
        }
    }
}

fn void main_coro() => @pool()
{
    Application* app = web::app_new();
    // defer app.free(); // @pool()

    RouteTable* routes = web::routetable_new();
    // defer routes.free(); // @pool()
    routes.get("/",      &index_handler);
    routes.post("/echo", &echo_handler);
    routes.ws("/ws",     &ws_handler);
    app.add_routes(routes);

    web::run_app(app, .port = 8080)!!;
}

fn void main() {
    asyncio::run(&main_coro);
}
```

---

## File list

| File | Module | Description |
|------|------|------|
| `aiohttp.types.c3` | `ext::aiohttp` | Shared Types (Url, Headers, Cookie, CookieJar, ClientTimeout, TlsConfig, BasicAuth, WsMessage, FormData) |
| `aiohttp.c3`       | `ext::aiohttp` | Client (TcpConnector, ClientSession, ClientResponse, ClientWs) |
| `aiohttp.web.c3`   | `ext::aiohttp::web` | Server (Application, Router, Request, Response, StreamResponse, FileResponse, WebSocketResponse, AppRunner, TcpSite) |

Back to [ext.c3l](../../README.md) library.
