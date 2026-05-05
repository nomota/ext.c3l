# ext::fiber for C3

A C3 port of Go's Fiber web framework, built on top of [ext::asyncio](../asyncio/README.md).
Unlike Flask, Fiber's request and response are unified in a single `Ctx` object per fiber.
Middleware chains work by calling `ctx.next()` from within a handler.

### Available modules

| Module | Description |
|--------|-------------|
| `ext::fiber` | FiberApp, FiberConfig, Ctx, RouterGroup, Route, static files |
| `ext::fiber::ws` | WebSocket upgrade, WsConn read/write |
| `ext::fiber::sse` | Server-Sent Events, SseWriter |
| `ext::fiber::session` | Session middleware, SessionStore, FiberSession |
| `ext::fiber::middleware` | Built-in middleware configs: cors, limiter, cache, compress, logger, recover, requestid, basicauth, proxy, timeout |

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.

### Files

* [fiber.c3](fiber.c3): FiberApp, FiberConfig, lifecycle, helpers
* [fiber.ctx.c3](fiber.ctx.c3): Ctx, request accessors, response methods, locals
* [fiber.router.c3](fiber.router.c3): RouterGroup, Route, URL building, static files
* [fiber.ws.c3](fiber.ws.c3): WebSocket handler and WsConn
* [fiber.sse.c3](fiber.sse.c3): Server-Sent Events and SseWriter
* [fiber.session.c3](fiber.session.c3): SessionStore and FiberSession
* [fiber.middleware.c3](fiber.middleware.c3): Built-in middleware config structs and constructors

---

### Constants

```c3
import ext::fiber;

// HTTP method bitmask flags (combinable with |)
const int HTTP_GET     = 0x001;
const int HTTP_POST    = 0x002;
const int HTTP_PUT     = 0x004;
const int HTTP_DELETE  = 0x008;
const int HTTP_PATCH   = 0x010;
const int HTTP_HEAD    = 0x020;
const int HTTP_OPTIONS = 0x040;
const int HTTP_CONNECT = 0x080;
const int HTTP_TRACE   = 0x100;
const int HTTP_ANY     = 0x1FF; // match any method

// HTTP status codes
const int HTTP_200 = 200;
const int HTTP_201 = 201;
const int HTTP_204 = 204;
const int HTTP_301 = 301;
const int HTTP_302 = 302;
const int HTTP_304 = 304;
const int HTTP_400 = 400;
const int HTTP_401 = 401;
const int HTTP_402 = 402;
const int HTTP_403 = 403;
const int HTTP_404 = 404;
const int HTTP_405 = 405;
const int HTTP_408 = 408;
const int HTTP_409 = 409;
const int HTTP_410 = 410;
const int HTTP_415 = 415;
const int HTTP_422 = 422;
const int HTTP_429 = 429;
const int HTTP_500 = 500;
const int HTTP_501 = 501;
const int HTTP_502 = 502;
const int HTTP_503 = 503;

// MIME types
const String MIME_JSON        = "application/json";
const String MIME_XML         = "application/xml";
const String MIME_TEXT        = "text/plain";
const String MIME_HTML        = "text/html";
const String MIME_OCTET       = "application/octet-stream";
const String MIME_MULTIPART   = "multipart/form-data";
const String MIME_FORM        = "application/x-www-form-urlencoded";
const String MIME_SSE         = "text/event-stream";

// Common header name strings
const String HEADER_CONTENT_TYPE    = "Content-Type";
const String HEADER_CONTENT_LENGTH  = "Content-Length";
const String HEADER_AUTHORIZATION   = "Authorization";
const String HEADER_ACCEPT          = "Accept";
const String HEADER_CACHE_CONTROL   = "Cache-Control";
const String HEADER_X_REQUEST_ID    = "X-Request-ID";
const String HEADER_X_FORWARDED_FOR = "X-Forwarded-For";
const String HEADER_VARY            = "Vary";
const String HEADER_ETAG            = "ETag";
const String HEADER_LOCATION        = "Location";

// Network type constants for FiberConfig.network
const int NETWORK_TCP  = 0;
const int NETWORK_TCP4 = 1;
const int NETWORK_TCP6 = 2;

// Compression level constants for CompressConfig.level
const int COMPRESS_DEFAULT     = 0;
const int COMPRESS_BEST_SPEED  = 1;
const int COMPRESS_BEST_SIZE   = 2;

// WebSocket message type constants
const int WS_TEXT   = 1;
const int WS_BINARY = 2;
const int WS_CLOSE  = 8;
const int WS_PING   = 9;
const int WS_PONG   = 10;

// Cookie SameSite policy
const int SAMESITE_LAX    = 0;
const int SAMESITE_STRICT = 1;
const int SAMESITE_NONE   = 2;
```

---

### Fault types

```c3
import ext::fiber;

fault FiberFault {
    BAD_REQUEST,            // 400
    UNAUTHORIZED,           // 401
    PAYMENT_REQUIRED,       // 402
    FORBIDDEN,              // 403
    NOT_FOUND,              // 404
    METHOD_NOT_ALLOWED,     // 405
    REQUEST_TIMEOUT,        // 408
    CONFLICT,               // 409
    GONE,                   // 410
    UNSUPPORTED_MEDIA_TYPE, // 415
    UNPROCESSABLE_ENTITY,   // 422
    TOO_MANY_REQUESTS,      // 429
    INTERNAL_SERVER_ERROR,  // 500
    NOT_IMPLEMENTED,        // 501
    BAD_GATEWAY,            // 502
    SERVICE_UNAVAILABLE,    // 503
    NEXT_NOT_CALLED,        // middleware did not call ctx.next()
    ROUTE_NOT_FOUND,        // no matching route
    BODY_PARSE_ERROR,       // body decoding failed
    PARAMS_PARSE_ERROR,     // path param decoding failed
    QUERY_PARSE_ERROR,      // query param decoding failed
    WS_UPGRADE_FAILED,      // WebSocket handshake error
    WS_CLOSED,              // peer closed the WebSocket connection
    SEND_FILE_ERROR,        // file not found or permission denied
}
```

---

### Callback aliases

```c3
import ext::fiber;

// Handler: the primary handler and middleware function signature.
// Return NO_ERR to continue; return a FiberFault to trigger the error handler.
// Call ctx.next() inside middleware to invoke the next handler in the chain.
alias Handler = fn fault?(Ctx*);

// ErrorHandler: the global error handler; receives the Ctx and the fault raised.
// Must send a response and return NO_ERR.
alias ErrorHandler = fn fault?(Ctx*, fault);

// KeyGenerator: extracts a cache or rate-limit key from the current request.
alias KeyGenerator = fn String(Ctx*);

// LimitReached: called by the rate limiter when a client exceeds its quota.
alias LimitReached = fn fault?(Ctx*);

// SkipFunc: predicate for skip middleware; return true to bypass the middleware.
alias SkipFunc = fn bool(Ctx*);

// StreamWriter: callback for streaming response bodies (SSE, chunked downloads).
// Receives an SseWriter for SSE or an AioFile-backed writer for raw chunked output.
alias StreamWriter = fn void(SseWriter*);

// RawStreamWriter: for non-SSE chunked responses; write raw bytes into buf.
// Return the number of bytes written, or 0 to signal end of stream.
alias RawStreamWriter = fn usz(char* buf, usz cap, void* ctx);

// WsHandler: coroutine invoked after a WebSocket upgrade.
alias WsHandler = fn void(WsConn*);

// BasicAuthAuthorizer: callback for basic-auth credential validation.
alias BasicAuthAuthorizer = fn bool(String user, String password);

// ProxyModifier: called before forwarding a request to a backend.
alias ProxyModifier = fn fault?(Ctx*);
```

---

### Structs

#### Application config

```c3
import ext::fiber;

// FiberConfig: options passed to fiber::new_app()
struct FiberConfig {
    bool   strict_routing;           // if true, /foo and /foo/ are different routes
    bool   case_sensitive;           // if true, /Foo and /foo are different routes
    bool   immutable;                // if true, ctx string values are copied and stable
    bool   unescape_path;            // unescape percent-encoding before route matching
    bool   etag;                     // automatically compute and set ETag on responses
    bool   get_only;                 // reject all non-GET requests at the app level
    bool   disable_keepalive;
    bool   disable_default_date;     // omit the Date header from responses
    bool   disable_default_content_type;
    bool   disable_header_normalizing;
    bool   disable_startup_message;
    bool   enable_trusted_proxy_check;
    bool   enable_ip_validation;
    bool   enable_print_routes;      // print registered routes on startup
    bool   stream_request_body;      // stream large request bodies instead of buffering

    usz    body_limit;               // max request body size in bytes (default 4 MiB)
    usz    concurrency;              // max concurrent connections (default 256 KiB)
    usz    read_buffer_size;         // per-connection read buffer (default 4096)
    usz    write_buffer_size;        // per-connection write buffer (default 4096)

    ulong  read_timeout_us;          // microseconds; 0 = no timeout
    ulong  write_timeout_us;
    ulong  idle_timeout_us;

    String server_header;            // value of the Server response header
    String compressed_file_suffix;   // suffix for pre-compressed static files (default ".fiber.gz")
    String proxy_header;             // header to read real client IP from (e.g. "X-Forwarded-For")
    String app_name;

    int    network;                  // NETWORK_TCP | NETWORK_TCP4 | NETWORK_TCP6

    String* trusted_proxies;         // array of trusted proxy IP strings / CIDR ranges
    usz     trusted_proxy_count;

    ErrorHandler error_handler;      // global error handler; null uses the default
}

// StaticConfig: options for serving a static directory
struct StaticConfig {
    bool   compress;                 // serve pre-compressed .gz / .br files when available
    bool   byte_range;               // enable Range header support
    bool   browse;                   // enable directory listing
    String index;                    // directory index filename (default "index.html")
    ulong  cache_duration_us;        // how long to cache open file handles (microseconds)
    int    max_age;                  // Cache-Control max-age in seconds
}
```

#### Routing

```c3
import ext::fiber;

// Route: a registered URL rule returned by named-route lookups
struct Route {
    String   method;    // "GET" | "POST" | ...
    String   path;      // original URL pattern e.g. "/items/:id"
    String   name;      // name set via .name(); empty if not named
    Handler* handlers;  // middleware chain followed by the terminal handler
    usz      handler_count;
}

// RouterGroup: a route group created by app.group() or group.group()
// Behaves like Fiber's Router / Group; holds a URL prefix and optional middleware
struct RouterGroup {
    String    prefix;         // URL prefix for all routes in this group
    Handler*  middlewares;    // middleware applied to every route in this group
    usz       middleware_count;
    FiberApp* app;            // back-reference to the owning application
}
```

#### Request / Response context

```c3
import ext::fiber;

// FileHeader: metadata for a single uploaded file (from a multipart form)
struct FileHeader {
    String filename;       // original filename as sent by the client
    String content_type;   // MIME type declared by the client
    usz    size;           // file size in bytes
    char*  data;           // buffered file bytes; null if stream_request_body is true
    usz    data_len;
}

// FormatEntry: one MIME-type-to-handler mapping used by ctx.format()
struct FormatEntry {
    String  mimetype;
    Handler handler;
}

// Cookie: a Set-Cookie descriptor for outgoing responses
struct Cookie {
    String key;
    String value;
    String path;       // default "/"
    String domain;
    int    max_age;    // seconds; -1 means session cookie
    long   expires;    // unix timestamp; -1 means not set
    bool   secure;
    bool   httponly;
    int    samesite;   // SAMESITE_LAX | SAMESITE_STRICT | SAMESITE_NONE
}

// Ctx: the unified per-fiber request and response context.
// Every handler and middleware receives a Ctx*.
// Handlers may read request state and write response state through this struct.
struct Ctx {
    // These fields are read-only; do not assign to them directly
    String method;       // "GET" | "POST" | ...
    String path;         // matched path e.g. "/items/1"
    String original_url; // full URL with query string
    String base_url;     // scheme + host without path
    String hostname;     // host without port
    String port;         // port string e.g. "8080"
    String protocol;     // "http" | "https"
    bool   secure;       // true when protocol is https
    bool   is_xhr;       // true when X-Requested-With is XMLHttpRequest

    // Locals: per-request opaque pointer store (equivalent to fiber.Locals)
    String* local_keys;
    void**  local_values;
    usz     local_count;
    usz     local_cap;

    FiberApp* app;       // the owning application
    Route*    route;     // the matched route; null inside global middleware
}
```

#### Application

```c3
import ext::fiber;

// FiberApp: the central application object
struct FiberApp {
    FiberConfig config;

    Route*       routes;
    usz          route_count;
    usz          route_cap;

    RouterGroup* groups;
    usz          group_count;

    asyncio::EventLoop* loop; // the underlying asyncio event loop
}
```

#### Middleware configs

```c3
import ext::fiber;
import ext::fiber::middleware;

// CorsConfig: options for the CORS middleware
struct CorsConfig {
    String  allow_origins;      // comma-separated origin patterns; "*" allows all
    String  allow_methods;      // comma-separated method list
    String  allow_headers;      // comma-separated header names
    String  expose_headers;     // comma-separated headers exposed to the browser
    bool    allow_credentials;
    int     max_age;            // preflight cache duration in seconds
    SkipFunc next;              // if not null, skip when next(ctx) is true
}

// LimiterConfig: options for the rate-limiter middleware
struct LimiterConfig {
    int          max;               // max requests per window
    ulong        expiration_us;     // window duration in microseconds
    KeyGenerator key_generator;     // extract the rate-limit key; default uses IP
    LimitReached limit_reached;     // response sent when limit is exceeded
    void*        storage;           // opaque persistent storage backend; null = in-memory
    SkipFunc     next;
}

// CacheConfig: options for the response-cache middleware
struct CacheConfig {
    ulong        expiration_us;     // how long to cache a response (microseconds)
    bool         cache_control;     // honor Cache-Control headers from upstream
    KeyGenerator key_generator;     // default uses request path
    void*        storage;           // opaque storage backend; null = in-memory
    SkipFunc     next;
}

// CompressConfig: options for the gzip/deflate compress middleware
struct CompressConfig {
    int      level; // COMPRESS_DEFAULT | COMPRESS_BEST_SPEED | COMPRESS_BEST_SIZE
    SkipFunc next;
}

// LoggerConfig: options for the request-logger middleware
struct LoggerConfig {
    String format;       // format string; tokens: ${time} ${method} ${path} ${status} ${latency}
    String time_format;  // strftime-style time format; default "2006-01-02 15:04:05"
    String time_zone;    // IANA time zone name; default "UTC"
    int    output_fd;    // file descriptor for log output; default asyncio::stdout()
}

// RecoverConfig: options for the panic-recovery middleware
struct RecoverConfig {
    bool enable_stack_trace;
    // stack_trace_handler is called with the context and the recovered value
    // signature: fn void(Ctx*, String panic_value, String stack_trace)
    fn void(Ctx*, String, String) stack_trace_handler;
}

// RequestIdConfig: options for the request-ID injection middleware
struct RequestIdConfig {
    String header;            // response header name; default "X-Request-ID"
    fn String() generator;   // ID generator; default produces a UUID v4
}

// BasicAuthConfig: options for HTTP Basic Authentication middleware
struct BasicAuthConfig {
    String              realm;       // WWW-Authenticate realm string
    BasicAuthAuthorizer authorizer;  // credential validator
}

// ProxyConfig: options for the reverse-proxy / load-balancer middleware
struct ProxyConfig {
    String*       servers;         // backend URL strings
    usz           server_count;
    ProxyModifier modify_request;  // called before forwarding; null for no modification
}

// TimeoutConfig: options for the request-timeout middleware
struct TimeoutConfig {
    ulong   timeout_us;   // max handler duration in microseconds
    Handler handler;      // the handler to wrap with a timeout
}
```

#### Session

```c3
import ext::fiber::session;

// SessionConfig: options for creating a SessionStore
struct SessionConfig {
    ulong  expiration_us;    // session lifetime in microseconds
    String key_lookup;       // "cookie:<name>" | "header:<name>" | "query:<name>"
    bool   cookie_secure;
    bool   cookie_httponly;
    int    cookie_samesite;  // SAMESITE_LAX | SAMESITE_STRICT | SAMESITE_NONE
    void*  storage;          // opaque persistent storage; null = in-memory
}

// SessionStore: a configured session manager; create once per application
struct SessionStore {
    SessionConfig config;
}

// FiberSession: the per-request session retrieved from a SessionStore
struct FiberSession {
    String* keys;
    void**  values;
    usz     count;
    usz     capacity;
}
```

#### WebSocket

```c3
import ext::fiber::ws;

// WsConfig: options for the WebSocket upgrade
struct WsConfig {
    ulong   handshake_timeout_us; // upgrade handshake deadline in microseconds
    usz     read_buffer_size;
    usz     write_buffer_size;
    String* origins;              // allowed Origin header values; null = allow all
    usz     origin_count;
}

// WsConn: an active WebSocket connection handed to a WsHandler
struct WsConn {
    String* local_keys;    // Locals inherited from the HTTP upgrade request
    void**  local_values;
    usz     local_count;
}
```

#### Server-Sent Events

```c3
import ext::fiber::sse;

// SseWriter: passed to a StreamWriter callback to emit SSE events
struct SseWriter {
    int output_fd; // underlying file descriptor; use the write methods, not this directly
}
```

---

### API functions

#### FiberApp lifecycle

```c3
import ext::fiber;

FiberApp* app = fiber::new_app(FiberConfig cfg); // create and configure a new app

void app.free(); // release all resources
```

#### Running the server

```c3
import ext::fiber;

// Start listening on addr (e.g. ":8080" or "0.0.0.0:8080"); blocks until stopped
void? app.listen(String addr) @maydiscard;

// Start with TLS; cert_file and key_file are filesystem paths
void? app.listen_tls(String addr, String cert_file, String key_file) @maydiscard;

// Start with mutual TLS; ca_file is the client CA certificate path
void? app.listen_mutual_tls(String addr, String cert_file, String key_file, String ca_file) @maydiscard;

// Graceful shutdown: waits for in-flight requests to complete
void? app.shutdown() @maydiscard;

// Graceful shutdown with a deadline in microseconds
void? app.shutdown_with_timeout(ulong timeout_us) @maydiscard;
```

#### Route registration on FiberApp

```c3
import ext::fiber;

// Register a handler for an explicit method string and path pattern.
// handlers is a middleware chain; the last entry is the terminal handler.
Route* app.add(String method, String path, Handler* handlers, usz handler_count);

// Shorthand per-method registration; each accepts one or more chained handlers
Route* app.get(String path, Handler* handlers, usz handler_count);
Route* app.post(String path, Handler* handlers, usz handler_count);
Route* app.put(String path, Handler* handlers, usz handler_count);
Route* app.patch(String path, Handler* handlers, usz handler_count);
Route* app.delete(String path, Handler* handlers, usz handler_count);
Route* app.head(String path, Handler* handlers, usz handler_count);
Route* app.options(String path, Handler* handlers, usz handler_count);
Route* app.connect(String path, Handler* handlers, usz handler_count);
Route* app.trace(String path, Handler* handlers, usz handler_count);

// Register handlers for all HTTP methods
Route* app.all(String path, Handler* handlers, usz handler_count);

// Assign a name to a route for URL building
Route* route.name(String name); // chainable: returns the same Route*

// Look up a named route; null if not found
Route* route = app.get_route(String name);
```

#### Global middleware registration

```c3
import ext::fiber;

// Register middleware for all routes (path="" means all paths)
void app.use(String path, Handler* middlewares, usz middleware_count);

// Convenience: register middleware without a path prefix (matches everything)
void app.use_all(Handler* middlewares, usz middleware_count);
```

#### Route groups

```c3
import ext::fiber;

// Create a sub-router for path; optionally attach middleware to the group
RouterGroup* group = app.group(String prefix, Handler* middlewares, usz middleware_count);

// Same shorthand methods as FiberApp, scoped to the group prefix
Route* group.get(String path, Handler* handlers, usz handler_count);
Route* group.post(String path, Handler* handlers, usz handler_count);
Route* group.put(String path, Handler* handlers, usz handler_count);
Route* group.patch(String path, Handler* handlers, usz handler_count);
Route* group.delete(String path, Handler* handlers, usz handler_count);
Route* group.head(String path, Handler* handlers, usz handler_count);
Route* group.options(String path, Handler* handlers, usz handler_count);
Route* group.all(String path, Handler* handlers, usz handler_count);
Route* group.add(String method, String path, Handler* handlers, usz handler_count);

// Nest a sub-group under this group
RouterGroup* subgroup = group.group(String prefix, Handler* middlewares, usz middleware_count);

// Register global middleware for all routes in this group
void group.use(Handler* middlewares, usz middleware_count);
```

#### Static file serving

```c3
import ext::fiber;

// Serve all files under fs_root at the URL prefix; uses default StaticConfig
void app.static_dir(String url_prefix, String fs_root);

// Serve with custom options
void app.static_dir_cfg(String url_prefix, String fs_root, StaticConfig cfg);
```

#### URL building

```c3
import ext::fiber;

// Build a URL for a named route filling in named path segments.
// param_keys and param_values are parallel arrays of length param_count.
// Extra keys become query parameters.
// Returns null when the named route does not exist.
String? url = route.build_url(String* param_keys, String* param_values, usz param_count);

// Same but callable from inside a handler; looks up by name on app.get_route()
String? url = ctx.get_route_url(String name, String* param_keys, String* param_values, usz param_count);
```

#### Ctx: request accessors

```c3
import ext::fiber;

// Client IP; respects FiberConfig.proxy_header when set
String ip = ctx.ip();

// All IPs from X-Forwarded-For in order; caller must free the slice
String[]? ips = ctx.ips(Allocator alloc);

// Path parameter (always a string; use the typed helpers for conversion)
String v = ctx.params(String name);           // "" when param absent
int?   n = ctx.params_int(String name);       // null on parse error
float? f = ctx.params_float(String name);

// Query string parameter
String v = ctx.query(String name, String default_val);
int?   n = ctx.query_int(String name, int default_val);
bool?  b = ctx.query_bool(String name);
float? f = ctx.query_float(String name);

// Request header (case-insensitive); returns default_val when absent
String v = ctx.get(String name, String default_val);

// All request headers as a flat array of HeaderEntry; caller must free
HeaderEntry[]? hdrs = ctx.get_req_headers(Allocator alloc);

// Cookie value; returns default_val when absent
String v = ctx.cookies(String name, String default_val);

// Raw request body bytes; caller does not own this slice (valid for request lifetime)
char[] body = ctx.body();

// Form field (application/x-www-form-urlencoded or multipart)
String v = ctx.form_value(String field);

// Uploaded file by form field name
FileHeader*? fh = ctx.form_file(String field);

// Save an uploaded file to dest_path (uses aiofiles internally); caller supplies path
void? ctx.save_file(FileHeader* fh, String dest_path);

// Content-Type check; type is a short name such as "json" or "html"
bool b = ctx.is(String type);

// Content negotiation: return best-match MIME type from offers, or "" for no match
String best = ctx.accepts(String* offers, usz count);

// Whether the request is from the same host as the server
bool b = ctx.is_from_local();

// Whether a 304 Not Modified response is appropriate (based on ETag / Last-Modified)
bool b = ctx.fresh();

// Locals: per-request opaque pointer store
void  ctx.locals_set(String key, void* value);
void* ctx.locals_get(String key); // null when key is absent
```

#### Ctx: response methods

```c3
import ext::fiber;

// Set the response status code; returns ctx for chaining
Ctx* ctx.status(int code);

// Send a raw byte slice as the response body
fault? ctx.send(char[] data);

// Send a string as the response body
fault? ctx.send_string(String s);

// Send pre-serialized JSON bytes; sets Content-Type to application/json
fault? ctx.json(char* json_str, usz json_len);

// Send pre-serialized XML bytes; sets Content-Type to application/xml
fault? ctx.xml(char* xml_str, usz xml_len);

// Send a file from disk; use_fs_cache=true keeps the file handle open between requests
fault? ctx.send_file(String path, bool use_fs_cache);

// Send a file as a download attachment with Content-Disposition
fault? ctx.download(String path, String filename);

// Start a streaming response using a RawStreamWriter callback
fault? ctx.send_stream(RawStreamWriter writer, void* writer_ctx);

// Write bytes or string to the buffer without finishing the response
void ctx.write(char[] data);
void ctx.write_string(String s);

// HTTP redirect; code defaults to 302 when 0
fault? ctx.redirect(String location, int code);

// Redirect to the Referer header value; falls back to fallback_url
fault? ctx.redirect_back(String fallback_url);

// Set a response header field (overwrites existing)
void ctx.set(String key, String value);

// Append a value to a response header (does not overwrite)
void ctx.append(String key, String value);

// Set Content-Type by file extension or short name (e.g. "pdf", "json")
void ctx.type_ext(String ext_or_name);

// Add header names to the Vary field
void ctx.vary(String* field_names, usz count);

// Set an outgoing cookie
void ctx.cookie(Cookie* c);

// Clear one cookie by name (sends a Max-Age=0 Set-Cookie)
void ctx.clear_cookie(String name);

// Clear all outgoing cookies
void ctx.clear_all_cookies();

// Content negotiation: call the handler whose MIME type best matches Accept
fault? ctx.format(FormatEntry* entries, usz count);

// Set Content-Disposition: attachment with optional filename
void ctx.attachment(String filename); // pass "" to omit filename

// Set the Links header for pagination
void ctx.links(String* urls, String* rels, usz pair_count);

// Retrieve the current value of a response header already set
String ctx.get_resp_header(String key, String default_val);

// All currently set response headers; caller must free
HeaderEntry[]? ctx.get_resp_headers(Allocator alloc);

// Render a named template with key-value data.
// keys and values are parallel arrays; result is written as the response body.
fault? ctx.render(String template_name, String* keys, void** values, usz data_count);
fault? ctx.render_layout(String template_name, String layout, String* keys, void** values, usz data_count);

// Invoke the next handler in the middleware chain; must be called from middleware
fault? ctx.next();
```

#### Error handling

```c3
import ext::fiber;

// Construct a FiberFault with an associated status code and message.
// Return this from a handler to trigger the global ErrorHandler.
fault? fiber::new_error(int status_code, String message) @maydiscard;

// Pre-defined convenience faults (same semantics as fiber.ErrXxx in Go)
fault FIBER_ERR_BAD_REQUEST;            // 400
fault FIBER_ERR_UNAUTHORIZED;           // 401
fault FIBER_ERR_PAYMENT_REQUIRED;       // 402
fault FIBER_ERR_FORBIDDEN;              // 403
fault FIBER_ERR_NOT_FOUND;              // 404
fault FIBER_ERR_METHOD_NOT_ALLOWED;     // 405
fault FIBER_ERR_REQUEST_TIMEOUT;        // 408
fault FIBER_ERR_CONFLICT;               // 409
fault FIBER_ERR_GONE;                   // 410
fault FIBER_ERR_UNPROCESSABLE_ENTITY;   // 422
fault FIBER_ERR_TOO_MANY_REQUESTS;      // 429
fault FIBER_ERR_INTERNAL_SERVER_ERROR;  // 500
fault FIBER_ERR_NOT_IMPLEMENTED;        // 501
fault FIBER_ERR_BAD_GATEWAY;            // 502
fault FIBER_ERR_SERVICE_UNAVAILABLE;    // 503
```

#### Built-in middleware constructors

```c3
import ext::fiber::middleware;

// Each constructor returns a Handler ready to pass to app.use_all() or app.get() etc.

Handler logger_new(LoggerConfig cfg);

Handler recover_new(RecoverConfig cfg);

Handler cors_new(CorsConfig cfg);

Handler limiter_new(LimiterConfig cfg);

Handler cache_new(CacheConfig cfg);

Handler compress_new(CompressConfig cfg);

Handler requestid_new(RequestIdConfig cfg);

Handler basicauth_new(BasicAuthConfig cfg);

Handler proxy_balancer(ProxyConfig cfg);

Handler timeout_new(TimeoutConfig cfg);

Handler etag_new(); // automatic ETag generation with no config

Handler favicon_new(String file_path); // serve favicon from file_path

// Conditionally skip a middleware when pred returns true
Handler skip_new(Handler wrapped, SkipFunc pred);

Handler encryptcookie_new(String key_32bytes); // AES-256 cookie encryption
```

#### Session

```c3
import ext::fiber::session;

SessionStore* store = session::new_store(SessionConfig cfg);

void store.free(); // prevent memory leak

// Retrieve or create the session for the current request
FiberSession*? sess = store.get(Ctx* ctx);

// Persist the session data (writes Set-Cookie if using cookie storage)
void? sess.save();

// Remove all keys from the session without invalidating it
void sess.destroy();

// Per-session key-value operations
void* sess.get(String key);         // null when key is absent
void  sess.set(String key, void* value);
void  sess.delete(String key);
bool  sess.has(String key);
String sess.id();                   // the session identifier string
```

#### WebSocket

```c3
import ext::fiber::ws;

// Wrap a WsHandler to produce an HTTP upgrade Handler.
// Place this as the terminal handler on a GET route.
Handler upgrade = ws::new(WsHandler handler, WsConfig cfg);

// Inside a WsHandler:

// Send a message; msg_type is WS_TEXT | WS_BINARY | WS_CLOSE | WS_PING | WS_PONG
fault? conn.write_message(int msg_type, char[] data);

// Receive one message; blocks the fiber until data arrives.
// msg_type is written to *out_type; caller must free returned slice.
char[]? conn.read_message(Allocator alloc, int* out_type);

// Convenience helpers
fault? conn.write_json(char* json_str, usz json_len);

// Locals inherited from the HTTP upgrade request
void* conn.locals_get(String key); // null when absent

// Path and query parameters from the upgrade URL
String conn.params(String name);
String conn.query(String name, String default_val);

// Header from the upgrade request
String conn.headers(String name, String default_val);

// Build a well-formed Close message payload
char[] ws::format_close(Allocator alloc, int code, String reason);
```

#### Server-Sent Events

```c3
import ext::fiber::sse;

// Set up an SSE response inside a regular GET handler.
// fiber sets headers and invokes writer in a dedicated fiber.
fault? ctx.sse(StreamWriter writer, void* writer_ctx);

// Inside a StreamWriter:

// Write a complete SSE event with optional id and event fields.
// Pass "" for id or event to omit the field.
void sse_writer.write_event(SseWriter* w, String id, String event, String data);

// Write a raw SSE comment (": comment\n\n")
void sse_writer.write_comment(SseWriter* w, String comment);

// Flush the underlying write buffer to the client
void sse_writer.flush(SseWriter* w);
```

---

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.
