// ext/aiohttp/README.md 

# ext::aio::http and ext::aio::request

Asynchronous HTTP server-side application and client libraries for C3.

- `ext::aio::http` provides routing, middleware, request and response helpers, cookies, CORS, compression, body limits, file responses, streaming, JSON parsing, and WebSocket upgrades.
- `ext::aio::request` provides an asynchronous HTTP client with sessions, cookies, redirects, query parameters, headers, authentication, request bodies, and response helpers.

This document is a usage guide.

## Requirements

- A recent C3 compiler
- [`ext.c3l` library](../../README.md)

Import the modules needed by the application:

```c3
import ext::aio; // async runtime
import ext::aio::http; // for server
import ext::aio::request; // for client
```

The HTTP client currently supports plain `http://` URLs. Passing an `https://` URL returns `UNSUPPORTED_SCHEME` fault.

## Module overview

| Module | Purpose |
|---|---|
| `ext::aio::http` | Build HTTP applications, register routes and middleware, read requests, and create responses |
| `ext::aio::request` | Send asynchronous outbound HTTP requests |


This module is part of the extended C3 library.

Back to [ext.c3l](../../README.md).

## HTTP application

### Create an http application

You need to create an application. Depending on where to allocate the application, you use different functions.

Use a stack-allocated `Application` when its lifetime is controlled by the current scope:

```c3
import ext::aio; // aio runtime
import ext::aio::http; // async http server library

fn void? app_task(void* arg) // aio async task
{
    http::Application app;
    app.init();
    defer app.deinit();

    // Register middleware and routes here.
    
    app.serve("127.0.0.1", 8080)!; // serve forever
}

fn void main()
{
    aio::run(&app_task)!!; // aio runtime
}
```

A heap-allocated application is also available:

```c3
import ext::aio; // aio async runtime
import ext::aio::http; // async http server

fn void? app_task(void* arg) // aio async task
{
    http::Application* app = http::application_new()!;
    defer app.free();

    // Register middleware and routes here.
    // ...
    
    app.serve("127.0.0.1", 8080)!; // serve forever
}

fn void main()
{
    aio::run(&app_task)!!; // aio runtime
}

```

Use `app.clear()` to remove all routes, middleware, and custom fallback handlers while keeping the application object reusable.

### Define route handlers

A handler receives a `http::Ctx*` (or `http::Context*`) and returns an optional `Response*?`:

```c3
import ext::aio;
import ext::aio::http;

fn http::Response*? hello_handler(http::Ctx* c) // handler
{
    return c.text("Hello, world!")!;
}

fn void? app_task(void* arg) // aio async task
{
    http::Application app;
    app.init();
    defer app.deinit();

    // Register routes here.
    app.get("/hello", &hello_handler); // register a GET handler, for exact path "/hello"
    
    app.serve("127.0.0.1", 8080)!; // serve forever
}

fn void main()
{
    aio::run(&app_task)!!; // aio runtime
}
```

Common response helpers include:

```c3
Ctx* c;
return c.text("plain text")!;
return c.html("<h1>Hello</h1>")!;
return c.json(`{"ok":true}`)!;
return c.empty()!;
return c.redirect("/login")!;
return c.redirect("/login", 303)!;
return c.not_found("user")!;
return c.internal_error("operation failed")!;
```

Set status and headers before creating the response body:

```c3
import ext::aio;
import ext::aio::http;

fn http::Response*? create_user_handler(http::Ctx* c)
{
    c.status(201)!; // set status for response
    c.header("X-Resource-Id", "42")!; // set header for response

    return c.json("{\"id\":42}")!; // json response
}

fn void? app_task(void* arg)
{
    http::Application app;
    app.init();
    defer app.deinit();

    // Register routes here.
    app.get("/create_user", &create_user_handler); // register a GET handler, for exact path "/create_user"
    
    app.serve("127.0.0.1", 8080)!; // serve forever
}

fn void main()
{
    aio::run(&app_task)!!;
}
```

Use `c.add_header(String key, String val)!` when a header may appear more than once.

### Register routes

Convenience methods are available for common HTTP methods:

```c3
app.get("/", &hello)!; // register GET handler, for exact path "/"
app.get("/users", &list_users)!; // register GET handler, for exact path "/users"
app.post("/users", &create_user)!; // register POST handler, for exact path "/users"
app.put("/users/:id", &replace_user)!; // register PUT handler, with path parameter "id"
app.patch("/users/:id", &update_user)!; // register PATCH handler, with path parameter "id"
app.delete("/users/:id", &delete_user)!; // register DELETE handler, with path parameter "id"
app.options("/api/*", &api_options)!; // register OPTIONS handler, with wildcard splatted path
app.head("/health", &health_head)!; // register HEAD handler, with exact path "/helth"
```

Use `app.add("METHOD", "/path",  &handler)!` for another method:

```c3
app.add("TRACE", "/debug", &trace_handler)!; // register TRACE handler, with exact path "/debug"
```

### Reading path parameters

Read a path parameter with `c.param(String name)`:

```c3
import ext::aio;
import ext::aio::http;

fn http::Response*? show_user(http::Ctx* c) // handler
{
    String id = c.param("id")!; // get path param, e.g. /users/23 => id = 23
    return c.text(id)!; // simple text response
}

fn void? app_task(void* arg)
{
    http::Application app;
    app.init();
    defer app.deinit();

    // Register routes here.
    app.get("/users/:id", &show_user)!; // register a GET handler, with a path parameter "id"
    
    app.serve("127.0.0.1", 8080)!;
}

fn void main()
{
    aio::run(&app_task)!!;
}
```

Use `c.has_param("name")` when a path parameter is optional.

Two or more path parameters can be defined like:

```c3
app.get("/users/:id/:name/profile", &show_user)!; // register GET handler, with two path parameters

// ex.
// GET /users/43/nomota/profile HTTP/1.0
// 
// c.param("id")! == 43
// c.param("name")! == nomota
```

Read a wildcard path with `c.splat()`:

```c3
import ext::aio;
import ext::aio::http;

fn http::Response*? show_asset_path(http::Ctx* c) // handler
{
    String wildcard_path = c.splat()!; // get the wildcard part of the path, e.g. /assets/office1/34 => c.splat() == "office1/33"
    return c.text(wildcard_path)!; // simple text response
}

fn void? app_task(void* arg) // async task
{
    http::Application app;
    app.init();
    defer app.deinit();

    // Register routes here.
    app.get("/assets/*", &show_asset_path)!; // register a GET handler, with wildcard (splat) part in the path
    
    app.serve("127.0.0.1", 8080)!;
}

fn void main()
{
    aio::run(&app_task)!!; // async runtime
}

```

* Note: wildcard must come at the end of the routing path.

```c3
// Route registration fails because a wildcard must be the final segment.
app.get("/assets/*/tail", &handler)!; // Runtime error: returns INVALID_ROUTE_PATH
```

### Mount a child application

A child router can be mounted below a prefix:

```c3
import ext::aio;
import ext::aio::http;

fn http::Response*? show_user(http::Ctx* c) // handler
{
    String id = c.param("id")!; // get path param, e.g. /users/23 => id = 23
    return c.text(id)!; // simple text response
}

fn void? app_task(void* arg)
{
    http::Application app; // main app
    app.init();
    defer app.deinit();

    http::Application api; // api child application
    api.init();
    defer api.deinit();
    
    api.get("/users", &list_users)!; // register GET handler to api subpart i.e. "/api-v2/users"
    api.get("/users/:id", &show_user)!; // register GET handler to api subpart i.e. "/api-v2/users/:id"
    
    app.mount("/api-v2", &api)!; // mount a route api subpart to the main app, under prefix
    
    app.serve("127.0.0.1", 8080)!;
}

fn void main()
{
    aio::run(&app_task)!!;
}
```

The child application must remain alive while the parent application uses its routes.

## Reading requests

### Reading method, path, and target

```c3
String method = c.method(); // get method from request
String path = c.path(); // get path from request
String target = c.target(); // get target from request. target = "path?query#fragment" part of the requested url
```

- `c.method()` returns the request method.
- `c.path()` returns the parsed path.
- `c.target()` returns the original request target (path?query#fragment), including its query string.

### Reading request headers

Header lookup is case-insensitive:

```c3
fn http::Response*? handler(http::Ctx* c) 
{
    String content_type = c.req_header("Content-Type")!; // get req header value, "content-type" also matches
    
    return c.text(content_type)!; // text response
}
```

Check optional headers without treating absence as an application error:

```c3
fn http::Response*? handler(http::Ctx* c) 
{
    String? request_id = c.req_header("X-Request-Id"); // get header from request
    if (catch err = request_id) { // unwrap request_id
        return c.internal_error("X-Request-Id header is missing")!; // error response
    }
    
    return c.text(request_id)!; // text response
}
```

Use `c.req.headers` to access the full parsed header collection.

```c3
fn http::Response*? header_handler(http::Ctx* c) // handler
{
    String resp_text = ""; 
    
    String? page = c.req_header("page"); // read header value from request
    if (try page) {
        resp_text = string::tformat("page:%s", page);
    }
    
    http::Headers headers = c.req.headers; // member variable
    for (sz i = 0; i < headers.len(); i++) {
        String name = headers.name_at(i)!;
        String value = headers.value_at(i)!;
        resp_text = string::tformat("%s %s:%s", resp_text, name, value);
    }
    
    return c.text(resp_text)!;
}
```


### Reading query parameters

```c3
fn http::Response*? search(http::Ctx* c) // handler
{
    String term = c.query("q")!; // get query value
    return c.text(term)!; // text response
}

fn void? app_task(void* arg)
{
    http::Application app; // main app
    app.init();
    defer app.deinit();

    // define route handlers
    app.get("/search", &search)!; // register GET handler
    
    app.serve("127.0.0.1", 8080)!;
}
```

Use `c.has_query("name")` for an optional value and `c.queries()` for the complete parsed collection:

```c3
fn http::Response*? search(http::Ctx* c) // handler
{
    String resp_text = ""; 
    
    String page = "";
    if (c.has_query("page")) {
        page = c.query("page")!; // read a query variable from request
        resp_text = string::tformat("page:%s", page);
    }
    
    http::Query* query = c.queries();
    for (sz i = 0; i < query.len(); i++) {
        String name = query.name_at(i)!;
        String value = query.value_at(i)!;
        resp_text = string::tformat("%s %s:%s", resp_text, name, value);
    }
    
    return c.text(resp_text)!;
}
```

### Reading request bodies

Check whether a body exists before requiring one:

```c3
if (!c.has_body()) {
    c.status(400)!;
    return c.text("request body required")!;
}
```

Read the request-owned body without copying:

```c3
char[] bytes = c.req_bytes();
String text = c.req_text();
String json_text = c.req_json_text();
```

These values are views into request-owned memory. Do not retain them after request processing finishes.

Use copy helpers when the data must outlive the request:

```c3
char[] owned_bytes = c.req_bytes_copy()!;
String owned_text = c.req_text_copy()!;
```

The caller owns copied values and must release them with the allocator used by the application.

```c3 
char[] owned_bytes = c.req_bytes_copy()!;
defer http::localmem.free(owned_bytes);

String owned_text = c.req_text_copy()!;
defer http::localmem.free(owned_text);
``` 

Content-type helpers include:

```c3
if (c.req_is_json()) { /* JSON media type */ }
if (c.req_is_text()) { /* text/plain */ }
if (c.req_is_html()) { /* text/html */ }
if (c.req_is_octet_stream()) { /* application/octet-stream */ }
```

Use `require_json()` or `require_text()` as simple guards:

```c3
fn http::Response*? accept_json(http::Ctx* c)
{
    if (!c.require_json()) {
        c.status(415)!;
        return c.text("application/json required")!;
    }

    return c.json(c.req_json_text())!;
}
```

### Parse JSON request

JSON parsing uses [`ext::encoding::simdjson`](../encoding/simdjson/README.md). `ext::encoding::simdjson` is 5-times faster than `std::encoding::json`.

```c3
fn http::Response*? parse_document(http::Ctx* c)
{
    simdjson::ParseResult document = c.req_json()!; // read and parse json from request

    // Read fields with the simdjson API.
    simdjson::JsonValue root = document.root();

    return c.json("{\"accepted\":true}")!; // json text response
}
```

Trailing commas and comments are allowed by default. For strict JSON:

```c3
simdjson::ParseResult document = c.req_json(allow_comma: false, allow_comment: false)!;
```

Use `req_json_with_allocator(alloc: mem, allow_comma: true, allow_comment: true)` when the parser must use a specific allocator.

#### `JsonValue` — type inspection (simdjson)

```c3
JsonValue v = result.root();

bool b = v.is_string();      // true if STRING
bool b = v.is_number();      // true if NUMBER
bool b = v.is_object();      // true if OBJECT
bool b = v.is_array();       // true if ARRAY
bool b = v.is_null();        // true if NULL
bool b = v.is_true();        // true if TRUE
bool b = v.is_false();       // true if FALSE
```

#### `JsonValue` — value extraction (simdjson)

```c3
JsonValue v = result.root();

bool     b = v.as_bool();      // true when type == TRUE, false otherwise (no fault)
String   s = v.as_str();       // zero-copy slice; raw JSON escapes are preserved
String   s = v.raw_num();      // raw source slice of a NUMBER (e.g. "-3.14e+2")
long?    l = v.as_long();      // TYPE_MISMATCH if not NUMBER; propagates to_long() faults
double?  d = v.as_double();    // TYPE_MISMATCH if not NUMBER; propagates to_double() faults
```

#### `JsonValue` — object access (simdjson)

```c3
JsonValue v = result.root();

sz n   = v.len(); // number of key-value pairs (0 if not an object)
JsonValue? child = v.get(String key); // key scan; TYPE_MISMATCH or KEY_NOT_FOUND on failure
```
#### `JsonValue` — array access (simdjson)

```c3
sz n = v.len(); // number of elements (0 if not an array)
JsonValue? elem = v.at(sz i);  // index-based access; TYPE_MISMATCH or INDEX_OUT_OF_RANGE on failure
```


## Cookies

### Reading request cookies

```c3
if (c.has_cookie("session_id")) {
    String session_id = c.cookie("session_id")!;
}
```

Use `c.cookies()` to access the full parsed cookie collection.

```c3
fn http::Response*? cookie_handler(http::Ctx* c) // handler
{
    String resp_text = ""; 
    
    String page = "";
    if (c.has_cookie("page")) {
        page = c.cookie("page")!; // read cookie value from request
        resp_text = string::tformat("page:%s", page);
    }
    
    http::Cookies* cookies = c.cookies();
    for (sz i = 0; i < cookies.len(); i++) {
        String name = cookies.name_at(i)!;
        String value = cookies.value_at(i)!;
        resp_text = string::tformat("%s %s:%s", resp_text, name, value);
    }
    
    return c.text(resp_text)!;
}
```

### Set response cookies

For giving a response cookie, you need to supply proper options as well as key/value pairs.

Low-level set-cookie is like this.

```c3
c.set_cookie("sid=abc; Path=/; HttpOnly; SameSite=Lax")!;
c.header("Set-Cookie", "sid=abc; Path=/; HttpOnly; SameSite=Lax")!;
```

You can build a set-cookie using `CookieOptions` for a proper options using `c.cookie_set(key, values, CookieOptions* options = null)`.


For explicit options:

```c3
http::CookieOptions options;
options.init();

options.path = "/";
options.http_only = true;
options.secure = true;
options.same_site = "Lax";
options.max_age = "3600";

c.cookie_set("session_id", "abc123", &options)!; // set cookie with options
```

For a cookie with default options:

```c3
c.cookie_set_default("theme", "dark")!; // set cookie with default options
```

`SameSite=None` requires `secure = true`.

Delete a cookie with the same path used when it was created:

```c3
c.delete_cookie("session_id")!;
c.delete_cookie_path("session_id", "/api")!;
```

## Middleware

You can define a chain of middlewares for various site-wide processing, e.g. for logging or for enforcing some site-wide policies like security, size limit or compression.

A middleware receives the current context and a `Next` callback:

```c3
fn http::Response*? add_server_header(http::Ctx* c, http::Next next) // middleware
{
    http::Response* response = next(c)!;
    c.header("X-Powered-By", "ext::aio::http")!; // add header to every response
    return response;
}
```

Register global middleware:

```c3
app.use(&add_server_header); // use middleware
```

Register middleware for a path prefix:

```c3
app.use_path("/api", &authenticate)!; // use middleware under a path
```

Middleware order matters. Register outer policies such as logging, error mapping, CORS, limits, or authentication in the order the application should execute them.

### Request body limits middleware

The default limit is 16 MiB.

Apply the built-in middleware:

```c3
app.use(&http::middleware_body_limit);
```

Configure the default limit:

```c3
http::set_body_limit(2 * 1024 * 1024);
http::set_body_limit_kib(512);
http::set_body_limit_mib(4);
http::reset_body_limit();
```

Apply a custom limit to selected routes:

```c3
fn http::Response*? avatar_limit(http::Ctx* c, http::Next next)
{
    return http::body_limit(c, next, 256 * 1024)!;
}

app.use_path("/avatar", &avatar_limit)!;
```

An oversized request receives `413 Payload Too Large`.

### Response compression middleware

```c3
http::compress_reset();
http::compress_set_min_size(1024);
http::enable_gzip(true);
http::enable_deflate(true);

app.use(&http::middleware_compress);
```

Compression is negotiated from `Accept-Encoding`. The middleware skips responses that should not be encoded, bodies below the configured threshold, pre-encoded responses, file responses, streaming responses, and unsupported media types.

### CORS middleware

Use the default policy:

```c3
app.use(&http::cors);
```

Configure an explicit policy before serving requests:

```c3
http::CorsOptions options;
options.init();

options.allow_origin = "https://app.example.com";
options.allow_methods = "GET, POST, PATCH, DELETE, OPTIONS";
options.allow_headers = "Content-Type, Authorization";
options.expose_headers = "X-Request-Id";
options.max_age = "86400";
options.allow_credentials = true;
options.preflight_status = 204;

http::cors_set_options(&options);
app.use(&http::cors);
```

A comma-separated origin list is supported. When credentials are enabled, configure explicit trusted origins rather than relying on a wildcard policy.

Individual configuration helpers are also available:

```c3
http::cors_allow_origin("https://app.example.com");
http::cors_allow_methods("GET, POST, OPTIONS");
http::cors_allow_headers("Content-Type, Authorization");
http::cors_expose_headers("X-Request-Id");
http::cors_max_age("3600");
http::cors_allow_credentials(true);
```

## Custom fallback and error responses

Install a custom not-found handler:

```c3
fn http::Response*? custom_not_found(http::Ctx* c)
{
    c.status(404)!;
    return c.json("{\"error\":\"not found\"}")!;
}

app.not_found(&custom_not_found);
```

Install a central error handler:

```c3
fn http::Response*? custom_error(http::Ctx* c, fault err)
{
    c.status(500)!;
    return c.json("{\"error\":\"internal server error\"}")!;
}

app.on_error(&custom_error);
```

Handler and middleware faults are routed through the configured error handler. Production responses should not expose raw internal fault details that reveals source code information.

## File and streaming responses

### Send a file content as a response

```c3
fn http::Response*? download(http::Ctx* c)
{
    return c.file("data/report.pdf")!;
}
```

You may want to supply appropriate header for the file:

```c3
fn http::Response*? download_handler(http::Ctx* c)
{
    c.header("Content-Disposition", "attachment; filename=\"manual.pdf\"")!; // set response header
    
    return c.file("/home/user/private/manual.pdf")!;
}
```

Send a part range of content from a file:

```c3
return c.file_range("data/archive.bin", offset, length)!;
```

* Note: here the file path is the underlying server's path, not url path.

`c.file()` receives a server filesystem path and does not represent a URL path.

Do not directly append untrusted request input:
```c3 
// Unsafe
String path = string::tformat("/srv/files/%s", c.query("name")!); // name could be  ../../etc/passwd  
return c.file(path)!;
```

Use a fixed allowlist or perform strict path normalization and containment checks.

### Static files 

You can designate a server directory as a static file folder relative to a certain url path.

```c3 
app.static_files("/", "/home/user/public_html")!;
```

> **Current limitation:** The static-file root is shared by static routes in the
> current thread. Registering `static_files()` again with another root replaces
> the previous root. Place related public directories below one common root.

A typical usage is like this:

```c3
import std::io;
import ext::aio;
import ext::aio::http;

const String PUBLIC_ROOT = "/home/user/myapp/public_html";
const String PRIVATE_ROOT = "/home/user/myapp/private";

fn http::Response*? download_handler(http::Ctx* c)
{
    c.header("Content-Disposition", "attachment; filename=\"manual.pdf\"")!;
    return c.file(string::tformat("%s/%s", PRIVATE_ROOT, "manual.pdf"))!;
}

fn void? app_task(void* arg)
{
    http::Application app;
    app.init();
    defer app.deinit();

    // dynamic file handling
    app.get("/download/manual", &download_handler);

    // static file handling
    app.static_files("/", PUBLIC_ROOT)!;

    app.serve("127.0.0.1", 8080)!;
}

fn void main()
{
    aio::run(&app_task)!!;
}
```

In this case path mapping is as follows.

```
GET /index.html
→ public_html/index.html

GET /css/style.css
→ public_html/css/style.css

GET /download/manual
→ private/manual.pdf
```

The implementation also:
* Maps an empty relative path to index.html
* Registers both GET and HEAD routes
* Rejects path traversal
* Rejects symbolic-link targets
* Does not provide directory listing
* Does not automatically map every nested directory to its index.html

Exact and parameterized routes take precedence over wildcard routes, so a route such as `/download/manual` can coexist with the static `/*`` route.

### Stream a response

```c3
fn void? write_stream(aio::Stream* stream, void* arg)
{
    stream.write_all((char[])"first chunk\n")!;
    stream.write_all((char[])"second chunk\n")!;
}

fn http::Response*? stream_log(http::Ctx* c)
{
    c.content_type("text/plain; charset=utf-8")!;
    return c.stream(&write_stream, null)!;
}
```

The callback writes directly to the client connection. Any object passed through `arg` must remain valid until streaming finishes.

## WebSocket upgrade

A WebSocket connection begins as an HTTP/1.1 request. The route handler validates the upgrade request and returns a 101 Switching Protocols response. After the handshake succeeds, the registered WebSocket session callback owns the connection until the callback returns.

Upgrade a valid WebSocket request from a route handler:

```c3
fn void? websocket_session(http::WebSocketConnection* connection)
{
    // Use the WebSocket connection API here.
}

fn http::Response*? websocket_route(http::Ctx* c)
{
    return c.upgrade_websocket(&websocket_session)!;
}

app.get("/ws", &websocket_route)!;
```

An optional read timeout is specified in microseconds:

```c3
return c.upgrade_websocket(&websocket_session, 30_000_000)!;
```

###  Complete echo server for WebSocket

The following server accepts text and binary messages and sends each message back to the client.

```c3
import std::io;
import ext::aio;
import ext::aio::http;

const String HOST = "127.0.0.1";
const ushort PORT = 8080;
const ulong WS_READ_TIMEOUT_US = 30_000_000;

fn void? websocket_session(http::WebSocketConnection* connection)
{
    io::printfn("WebSocket connected");

    while (connection.is_open()) {
        http::WebSocketMessage message = connection.receive()!;
        defer message.free();

        switch (message.opcode) {
            case http::WS_TEXT:
                String text = (String)message.data;

                io::printfn("Text message: %s", text);
                connection.send_text(text)!;

            case http::WS_BINARY:
                io::printfn("Binary message: %d bytes", message.data.len);
                connection.send_binary(message.data)!;

            case http::WS_PING:
                connection.send_pong(message.data)!;

            case http::WS_PONG:
                io::printfn("Pong received: %d bytes", message.data.len);

            case http::WS_CLOSE:
                io::printfn("Close message received");
                connection.close()!;
                return;

            default:
                connection.send_close(1002, "Unsupported WebSocket opcode")!;
                return;
        }
    }

    io::printfn("WebSocket disconnected");
}

fn http::Response*? websocket_route(http::Ctx* c)
{
    return c.upgrade_websocket(&websocket_session, WS_READ_TIMEOUT_US)!;
}

fn void? app_task(void* arg)
{
    http::Application app;
    app.init();
    defer app.deinit();

    app.get("/ws", &websocket_route)!;

    io::printfn("Listening on http://%s:%d", HOST, PORT);

    app.serve(HOST, PORT)!;
}

fn void main()
{
    aio::run(&app_task)!!;
}
```

### Connection lifecycle

The request initially enters the ordinary HTTP router:

```
GET /ws
    -> websocket_route()
    -> c.upgrade_websocket()
    -> HTTP 101 Switching Protocols
    -> websocket_session()
    -> receive/send loop
    -> close
```

The route must match before the WebSocket handshake is attempted.

```c3 
app.get("/ws", &websocket_route)!;
```

Therefore:

```
ws://127.0.0.1:8080/ws
```

matches the route, while:

```
ws://127.0.0.1:8080/ws/chat
```
does not match unless another route is registered.

For example:

```c3
app.get("/ws/:room", &websocket_route)!;
```

or:

```c3 
app.get("/ws/*", &websocket_route)!;
```

### Upgrade request requirements

A valid WebSocket client sends an HTTP/1.1 request containing headers similar to:

```
GET /ws HTTP/1.1
Host: 127.0.0.1:8080
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Version: 13
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
```

A normal HTTP request is not automatically converted into a WebSocket connection.

For example, this is not a complete WebSocket handshake:

```
GET /ws HTTP/1.1
Host: 127.0.0.1:8080
```

The recommended way to connect is through a WebSocket client library or the browser WebSocket API.

### Receiving messages

Use `connection.receive()` to wait for the next complete WebSocket message:

```c3 
http::WebSocketMessage message = connection.receive()!;
defer message.free();
```

A WebSocketMessage contains:

```c3
message.opcode
message.data
```

`message.opcode` identifies the message type:

```c3 
http::WS_TEXT
http::WS_BINARY
http::WS_PING
http::WS_PONG
http::WS_CLOSE
```

`message.data` contains the message payload.

The `connection` layer performs `WebSocket` frame parsing and message reassembly. `Application` code receives a complete message rather than manually joining continuation frames.

### Message ownership

A message returned by `connection.receive()` owns its payload. Always release it:

```c3 
http::WebSocketMessage message = connection.receive()!;
defer message.free();
```

The following value is valid only until `message.free()`:

```c3 
String text = (String)message.data;
```

Do not retain message.data after freeing the message. Copy the payload when it must outlive the current loop iteration.

### Text messages

Text messages contain UTF-8 data.

```c3
case http::WS_TEXT:
    String text = (String)message.data;

    io::printfn("Received: %s", text);
    connection.send_text("Message received")!;
```

Echo the original text:

```c3 
connection.send_text((String)message.data)!;
```

Send JSON as a text message:

```c3
connection.send_text("{\"type\":\"welcome\",\"message\":\"connected\"}")!;
```

WebSocket JSON does not require an HTTP Content-Type header. After the upgrade, data is transferred through WebSocket messages rather than HTTP request and response bodies.

### Binary messages

Binary messages may contain arbitrary bytes:

```c3 
case http::WS_BINARY:
    io::printfn("Received %d binary bytes", message.data.len);
    connection.send_binary(message.data)!;
```

For example:

```c3
char[4] response = { 0x01, 0x02, 0x03, 0x04 };
connection.send_binary(response[..])!;
```

Use text messages for UTF-8 text and JSON. Use binary messages for encoded files, serialized structures, compressed data, or application-specific binary protocols.

### Ping and pong

Ping and pong frames are control messages used to verify that the connection is still responsive.

Reply to a received ping with the same payload:

```c3 
case http::WS_PING:
    connection.send_pong(message.data)!;
``` 

Send a ping from the server:

```c3 
connection.send_ping((char[])"health-check")!;
```

A pong may contain the payload from the corresponding ping:

```c3 
case http::WS_PONG:
    io::printfn("Pong payload: %s", (String)message.data);
```

Ping payloads should remain small. They are control-frame payloads, not general application messages.

### Closing a connection

For a normal close:

```c3 
connection.close()!;
```

A close message with an explicit status code and reason can be sent with:

```c3 
connection.send_close(1000, "Normal closure")!;
```

Common close codes include:

| Code | Meaning |
|---:|---|
| `1000` | Normal closure |
| `1001` | Endpoint is going away |
| `1002` | Protocol error |
| `1003` | Unsupported data type |
| `1007` | Invalid message data |
| `1008` | Policy violation |
| `1009` | Message too large |
| `1011` | Unexpected server error |

When the peer sends a close message, stop the application message loop:

```c3 
case http::WS_CLOSE:
    connection.close()!;
    return;
```

Use `connection.abort()` only when the connection must be terminated immediately without completing the normal close handshake:

```c3 
connection.abort();
```

A normal application shutdown should prefer close().

### Connection state

Check whether the connection may continue processing messages:

```c3 
if (connection.is_open()) {
    connection.send_text("still connected")!;
}
```

Check whether the close handshake has started:

```c3 
if (connection.is_closing()) {
    return;
}
```

A common session loop is:

```c3
while (connection.is_open()) {
    http::WebSocketMessage message = connection.receive()!;
    defer message.free();

    // Process the message.
}
```

### Read timeout

The timeout passed to `c.upgrade_websocket()` is expressed in microseconds:

```c3 
return c.upgrade_websocket(&websocket_session, 30_000_000)!;
```

This example configures a 30-second read timeout.

The timeout applies while waiting for incoming WebSocket data. It is not the total allowed lifetime of the connection. A connection may remain active indefinitely as long as incoming activity satisfies the configured timeout policy.

The timeout can also be inspected or changed through the connection:

```c3 
ulong current_timeout = connection.get_read_timeout_us();

connection.set_read_timeout_us(60_000_000);
```

A timeout failure from `connection.receive()` normally ends the session unless the application explicitly handles that fault.

### Handling session errors

The simplest session propagates connection faults:

```c3
fn void? websocket_session(http::WebSocketConnection* connection)
{
    while (connection.is_open()) {
        http::WebSocketMessage message = connection.receive()!;
        defer message.free();

        if (message.opcode == http::WS_TEXT) {
            connection.send_text((String)message.data)!;
        }

        if (message.opcode == http::WS_CLOSE) {
            connection.close()!;
            return;
        }
    }
}
```

Returning a fault ends that connection's session. It does not normally terminate the entire HTTP server.

For local logging, place the message-processing loop in a separate function:

```c3
fn void? websocket_message_loop(http::WebSocketConnection* connection)
{
    while (connection.is_open()) {
        http::WebSocketMessage message = connection.receive()!;
        defer message.free();

        switch (message.opcode) {
            case http::WS_TEXT:
                connection.send_text((String)message.data)!;

            case http::WS_BINARY:
                connection.send_binary(message.data)!;

            case http::WS_PING:
                connection.send_pong(message.data)!;

            case http::WS_CLOSE:
                connection.close()!;
                return;

            default:
        }
    }
}

fn void? websocket_session(http::WebSocketConnection* connection)
{
    if (catch err = websocket_message_loop(connection)) {
        io::printfn("WebSocket session failed: %s", err);
        connection.abort();
    }
}
```

### Authentication before upgrade

Authentication must be performed while the request is still an HTTP request.

```c3 
fn http::Response*? websocket_route(http::Ctx* c)
{
    String? authorization = c.req_header("Authorization");

    if (catch err = authorization) {
        c.status(401)!;
        return c.text("Authorization required")!;
    }

    if (authorization != "Bearer example-token") {
        c.status(403)!;
        return c.text("Forbidden")!;
    }

    return c.upgrade_websocket(&websocket_session)!;
}
```

After `c.upgrade_websocket()` succeeds, the connection is no longer an ordinary HTTP request-response exchange.

Authentication may also be implemented as path middleware:

```
app.use_path("/ws", &authenticate_websocket)!; // register middleware
app.get("/ws", &websocket_route)!; // register GET handler
```

### Browser client example

The server can be tested from a browser:

```html 
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>WebSocket test</title>
</head>
<body>
    <button id="connect">Connect</button>
    <button id="send">Send</button>
    <button id="close">Close</button>

    <pre id="log"></pre>

    <script>
        let socket = null;

        const log = (message) => {
            document.getElementById("log").textContent += message + "\n";
        };

        document.getElementById("connect").onclick = () => {
            socket = new WebSocket("ws://127.0.0.1:8080/ws");
            socket.binaryType = "arraybuffer";

            socket.onopen = () => {
                log("connected");
            };

            socket.onmessage = (event) => {
                if (typeof event.data === "string") {
                    log("text: " + event.data);
                } else {
                    log("binary: " + event.data.byteLength + " bytes");
                }
            };

            socket.onclose = (event) => {
                log("closed: code=" + event.code + " reason=" + event.reason);
            };

            socket.onerror = () => {
                log("WebSocket error");
            };
        };

        document.getElementById("send").onclick = () => {
            if (socket !== null && socket.readyState === WebSocket.OPEN) {
                socket.send("Hello from the browser");
            }
        };

        document.getElementById("close").onclick = () => {
            if (socket !== null) {
                socket.close(1000, "Client finished");
            }
        };
    </script>
</body>
</html>
```

Opening this page and pressing Connect creates a WebSocket connection to:

```
ws://127.0.0.1:8080/ws
``` 

Pressing Send transmits a text message. The echo server returns the same message.

### Practical rules

Do not retain `Ctx*` inside the WebSocket session. The HTTP context belongs to the upgrade request, while the `WebSocketConnection*` represents the long-lived upgraded connection.

Free every received WebSocketMessage.

Do not perform blocking operating-system calls inside the session callback. `connection.receive()` and the connection send methods cooperate with the `ext::aio` event loop.

Avoid concurrent writes from several tasks to the same connection unless writes are explicitly serialized. A single writer per connection is the simplest design.

Use a bounded message size and an appropriate read timeout for public servers.

Validate authentication and request headers before calling `c.upgrade_websocket()`.

Use `connection.close()` for normal termination and `connection.abort()` only for unrecoverable connection failures.

## Direct application dispatch (for debugging/testing)

`Application.fetch()` is useful for tests, adapters, and embedded use with an already parsed request:

```c3
http::Response* response = app.fetch(request)!;
defer http::response_free(response);
```

`fetch_raw()` accepts one complete raw HTTP request:

```c3
String raw = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
http::Response* response = app.fetch_raw((char[])raw)!;
defer http::response_free(response);
```

Use the project server integration to accept network connections and dispatch requests to the application.

# HTTP client

`ext::aio::request` supports one-off requests and reusable `Session` objects. Request operations must run inside an `ext::aio` task and event-loop context.

A Session currently reuses cookies and configuration. It does not necessarily mean a persistent TCP connection or HTTP keep-alive pool.

## One-off requests

```c3
import std::io;
import ext::aio::request;

fn void? fetch_example(void* arg) // async task
{
    request::Response response = request::get("http://example.com/")!;
    defer response.free();

    io::printfn("status: %d", response.status);
    io::printfn("body: %s", response.text());
}

fn void main()
{
    aio::run(&fetch_example)!!;
}
```

Available convenience functions:

```c3
request::get(url, options);
request::post(url, options);
request::put(url, options);
request::patch(url, options);
request::delete(url, options);
request::head(url, options);
request::options(url, options);
```

## Request options

Initialize and free `Options` for each configured request:

```c3
request::Options options;
options.init();
defer options.free();
```

### Query parameters

```c3
options.query.set("q", "c3 language")!;
options.query.set("page", "2")!;

request::Response response = request::get("http://example.com/search", &options)!;
defer response.free();
```

Names and values are percent-encoded by the client.

### Headers

```c3
options.headers.set("Accept", "application/json")!;
options.headers.set("X-Request-Id", "req-123")!;
```

The client manages `Host`, `Connection`, `Content-Length`, `Cookie`, and `Authorization` from structured request state.

### Raw request body

```c3
options.data = (char[])"name=Kim&active=true";
options.headers.set("Content-Type", "application/x-www-form-urlencoded")!;

request::Response response = request::post("http://example.com/users", &options)!;
defer response.free();
```

### JSON request body

```c3
options.json = (char[])"{\"name\":\"Kim\"}";

request::Response response = request::post("http://example.com/users", &options)!;
defer response.free();
```

The client adds `Content-Type: application/json` unless it was set explicitly.

`data` and `json` are mutually exclusive. Setting both returns `INVALID_OPTIONS`.

### Authentication

Bearer authentication:

```c3
options.auth.bearer("access-token");
```

Custom authorization scheme:

```c3
options.auth.custom("ApiKey", "secret-value");
```

### Per-request cookies

```c3
options.cookies.set("theme", "dark")!;
```

A per-request cookie overrides a session cookie with the same name.

### Timeout

Set a per-request timeout in microseconds:

```c3
options.timeout_us = 5_000_000;
```

A zero value uses the session timeout.

## Sessions

A session retains cookies received through `Set-Cookie` and shares limits and redirect settings across requests:

The current session cookie store is a simple name/value store. It does not
implement full browser cookie-domain, path, expiry, or security-attribute
matching. Use a session only with trusted, related endpoints.

This is especially important because a single session used across unrelated hosts could send stored cookies more broadly than expected.

Avoid automatically following redirects to untrusted hosts when the request
contains authentication credentials or session cookies.

```c3
request::Session session;
session.init();
defer session.deinit();

session.timeout_us = 10_000_000;
session.max_response_bytes = 8 * 1024 * 1024;
session.max_redirects = 5;
session.follow_redirects = true;

request::Response login = session.get("http://example.com/login")!;
login.free();

request::Response account = session.get("http://example.com/account")!;
defer account.free();
```

A heap-allocated session is also available:

```c3
request::Session* session = request::session_new()!;
defer session.free();
```

Default session settings:

| Setting | Default |
|---|---:|
| Timeout | 30 seconds |
| Maximum response size | 16 MiB |
| Maximum redirects | 5 |
| Follow redirects | Enabled |

A session supports the same method helpers as the one-off API, plus a generic method:

```c3
session.get(url, options);
session.post(url, options);
session.put(url, options);
session.patch(url, options);
session.delete(url, options);
session.head(url, options);
session.options(url, options);
session.request("CUSTOM", url, options);
```

## Reading client responses

```c3
request::Response response = request::get("http://example.com/api")!;
defer response.free();

ushort status = response.status;
String final_url = response.url;
String text = response.text();
String content_type = response.header("Content-Type")!;
```

Status helpers:

```c3
if (response.ok()) { /* 2xx */ }
if (response.redirect()) { /* 3xx */ }
if (response.client_error()) { /* 4xx */ }
if (response.server_error()) { /* 5xx */ }
```

Parse a JSON response:

```c3
simdjson::ParseResult document = response.json()!;
```

Always call `response.free()` when finished. A response owns its headers, body buffer, and final URL.

## Redirect behavior

When `follow_redirects` is enabled, the client follows supported redirects up to `max_redirects`. The final URL is stored in `response.url`.

Disable automatic redirects when the original response must be inspected:

```c3
session.follow_redirects = false;
```

## Fault handling

Both modules use C3 faultable return values. Propagate a failure when the caller should decide how to handle it:

```c3
request::Response response = request::get(url)!;
```

Handle an expected failure directly:

```c3
fn void? fetch_url(String url)
{
    request::Response? result = request::get(url);
    if (catch err = result) {
        io::printfn("request failed: %s", err);
        return err~;
    }

    request::Response response = result;
    defer response.free();

    io::printfn("status: %d", response.status);
}
```

Common client faults include:

- `INVALID_URL`
- `INVALID_OPTIONS`
- `UNSUPPORTED_SCHEME`
- `INVALID_RESPONSE`
- `RESPONSE_TOO_LARGE`
- `RESPONSE_INCOMPLETE`
- `INVALID_AUTH`
- `TOO_MANY_REDIRECTS`

Use `Application.on_error()` on the server side to convert internal faults into stable HTTP responses.

## Recommended practices

1. Configure one long-lived `Application` during startup.
2. Keep handlers small and place business logic in separate service modules.
3. Register middleware deliberately; execution order affects behavior.
4. Use path middleware for authentication and API-specific policies.
5. Set explicit request-body and client-response size limits.
6. Use a `request::Session` when requests should share cookies or settings.
7. Free every owned application, session, options value, client response, and copied request body.
8. Do not retain request-owned strings or slices after the request finishes.
9. Return generic production error messages and log detailed faults separately.
10. Treat outbound response bodies as untrusted input even when the HTTP status is successful.

## Suggested project layout

```text
src/
  main.c3
  app.c3
  routes/
    users.c3
    health.c3
  middleware/
    auth.c3
  services/
    upstream.c3
```

## License

MIT License.


This module is part of the extended C3 library.

Back to [ext.c3l](../../README.md).


// eof