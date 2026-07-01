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

### Create a http application

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
    
    app.serve("127.0.0.1", 8080)!; // serve forver
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

Use `app.add("METHOD", "/path"  &handler)!` for another method:

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
// c.get("id") == 43, c.get("name") == nomota
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

    http::Application api; // api sub-part
    api.init();
    defer api.deinit();
    
    api.get("/users", &list_users)!; // register GET handler to api subpart i.e. "/api-v2/users"
    api.get("/users/:id", &show_user)!; // register GET handler to api subpart i.e. "/api-v2/users/:id"
    
    app.mount("/api-v2", &api)!; // mount a route api subpart to the main app, under exact path
    
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
    
    String page = "";
    if (c.has_header("page")) {
        page = c.req_header("page")!; // read header value from request
        resp_text = string::tformat("page:%s", page);
    }
    
    http::Headers* headers = c.req.headers; // member variable
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

JSON parsing uses [`ext::serializer::simdjson`](../serializer/simdjson/README.md). `ext::serializer::simdjson` is 5-times fater than `std::encoding::json`.

```c3
fn http::Response*? parse_document(http::Ctx* c)
{
    simdjson::ParseResult document = c.req_json()!; // read and parse json from request

    // Read fields with the simdjson API.
    JsonValue root = document.root();

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
    c.header("X-Powered-By", "ext::aio::http")!; // add header to every respone
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

### Send a file

```c3
fn http::Response*? download(http::Ctx* c)
{
    return c.file("data/report.pdf")!;
}
```

Supply a known size when available:

```c3
return c.file("data/report.pdf", file_size)!;
```

Send a range from a file:

```c3
return c.file_range("data/archive.bin", offset, length)!;
```

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

## Direct application dispatch

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

`ext::aio::request` supports one-off requests and persistent `Session` objects. Request operations must run inside an `ext::aio` task and event-loop context.

## One-off requests

```c3
import std::io;
import ext::aio::request;

fn void? fetch_example()
{
    request::Response response = request::get("http://example.com/")!;
    defer response.free();

    io::printfn("status: %d", response.status);
    io::printfn("body: %s", response.text());
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
if (catch err = request::get(url)) {
    io::printfn("request failed: %s", err);
    return err?;
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