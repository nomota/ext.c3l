// README.md of ext::httpserver

# ext::httpserver

An efficient HTTP server framework for C3, built on top of `ext::asyncio` and inspired by the clean, minimal API style of Hono for JavaScript.

`ext::httpserver` provides a compact API for defining routes, reading requests, building responses, using middleware, extracting route parameters, parsing query strings, and serving HTTP requests.

The framework is designed around a simple request lifecycle:

```text
raw HTTP request
  -> Request
  -> Router.match()
  -> Context
  -> MiddlewareStack
  -> Handler
  -> Response
  -> serialized HTTP response
```

## Status

This module is currently a minimal HTTP/1.1 framework implementation.

Implemented:

- HTTP request parsing
- HTTP response serialization
- Header storage with duplicate header support
- Route matching
- Route params such as `/users/:id`
- Wildcard splat routes such as `/static/*`
- Query string parsing
- Percent decoding
- Middleware chain
- Request/Response integrated `Context`
- Basic server integration
- Cookie read/write through headers

Not yet implemented:

- chunked transfer decoding
- multipart form parsing
- full keep-alive / pipelining buffering
- automatic JSON serialization
- WebSocket upgrade
- TLS integration
- static file serving
- body streaming
- builtin authentication in middleware
- gzip/deflate compression
- CORS helpers
- structured access logging
- multi thread/cpu optimization
- 
## Module

```c3
module ext::httpserver;
```

Typical imports:

```c3
import std::io;
import ext::httpserver;
import ext::asyncio;
```

## Quick start

```c3
module examples::hello;

import ext::httpserver;
import ext::asyncio;

fn Response* hello_handler(Ctx* c)
{
    return c.text("Hello, ext::httpserver!");
}

fn void main_coro() // coroutine
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &hello_handler)!!;

    app.listen(8080)!!;
}

fn void main() 
{
    asyncio::run(&main_coro);
}
```

Then open:

```text
http://127.0.0.1:8080/
```

Expected response:

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 23
Connection: close

Hello, ext::httpserver!
```

## Application

The main application type is `Application`.

```c3
struct Application {
    Router router;
    MiddlewareStack middlewares;
}
```

### Lifecycle

```c3
fn void Application.init(&self);
fn void Application.free(&self);
fn void Application.clear(&self);

fn Application* application_new();
fn void application_free(Application* app);
```

Stack usage:

```c3
Application app;
app.init();
defer app.free();
```

Heap usage:

```c3
Application* app = application_new();
defer application_free(app);
```

## Routing

Routes are registered directly on `Application`.

```c3
fn void? Application.get(&self, String path, Handler handler);
fn void? Application.post(&self, String path, Handler handler);
fn void? Application.put(&self, String path, Handler handler);
fn void? Application.patch(&self, String path, Handler handler);
fn void? Application.delete(&self, String path, Handler handler);
fn void? Application.options(&self, String path, Handler handler);
fn void? Application.head(&self, String path, Handler handler);
fn void? Application.add(&self, String method, String path, Handler handler);
```

Handler type:

```c3
alias Handler = fn Response*(Ctx* c);
```

Example:

```c3
import ext::httpserver;
import ext::asyncio;

fn Response* home(Ctx* c)
{
    return c.text("Home");
}

fn Response* create_user(Ctx* c)
{
    return c.json(`{"ok":true}`);
}

fn void main_coro()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &home)!!;
    app.post("/users", &create_user)!!;

    app.listen(8080)!!;
}

fn void main() 
{
    asyncio::run(&main_coro);
}

```

## Route path parameters

Routes can contain named parameters with colon.

```c3
app.get("/users/:user_id", &user_detail)!!;
```

Read parameters through `Ctx.param()`:

```c3
fn Response* user_detail(Ctx* c)
{
    String? id = c.param("user_id");

    if (catch err = id) {
        c.status(400);
        return c.text("missing id");
    }

    return c.text(id);
}
```

Route parameter names must start with an alphabetic character or `_`.

Allowed examples:

```text
/users/:user_id/posts/:post_id   // multiple path params in a single route
:id
:user_id
:file-name
```

Invalid examples:

```text
:
:123
:user.id
```

## Wildcard routes

Wildcard routes use `*`.

```c3
app.get("/static/*", &static_handler)!!;
```

Read the wildcard capture through `Ctx.splat()`:

```c3
fn Response* static_handler(Ctx* c)
{
    String? rest_path = c.splat(); 

    if (catch err = rest_path) {
        return c.text("missing path");
    }
    
    String content = read_file(rest_path);

    return c.text(content);
}
```

Example:

```text
Route: /static/*
Path:  /static/css/app.css
Splat: css/app.css
```

## Mounting child apps

Use `Application.route()` to mount another app under a prefix.

```c3

import ext::httpserver;
import ext::asyncio;

fn Response* users(Ctx* c)
{
    return c.text("users");
}

fn void main_coro()
{
    Application api;
    api.init();
    defer api.free();

    api.get("/users", &users)!!;

    Application app;
    app.init();
    defer app.free();

    app.route("/api", &api)!!;

    app.listen(8080)!!;
}

fn void main()
{
    asyncio::run(&main_coro);
}

```

Result:

```text
GET /api/users
```

Currently `route()` mounts routes only. Child middleware composition can be added later.

## Context

The `Context` object is passed to every handler and middleware.

```c3
struct Context {
    Request* req;
    Response* res;
    Params params;
    Query query_cache;
    bool query_cache_ready;
}

alias Ctx = Context; // use Ctx
```
* Note: Context is an integrated object, covering both request reading and response generating.

Common APIs for Request reading:

```c3
// methods for reading Request

fn ushort Ctx.get_status(&self);
fn String Ctx.method(&self);
fn String Ctx.path(&self);
fn String Ctx.target(&self); // path?query_string

fn String? Ctx.req_header(&self, String name);
fn char[] Ctx.body(&self);
fn bool Ctx.has_body(&self);

fn String? Ctx.form(&self, String name);
fn String? Ctx.cookie(&self, String name);
fn String? Ctx.param(&self, String name); // route path param with :name
fn String? Ctx.splat(&self); // wildcard('*') part of a route path

fn String? Ctx.query(&self, String name);
fn bool Ctx.has_query(&self, String name);
fn Query* Ctx.queries(&self);
```

Common APIs for Response generating:

```c3 
// methods for setting Response

fn void Ctx.status(&self, ushort status);
fn void Ctx.header(&self, String name, String value);
fn void Ctx.add_header(&self, String name, String value);
fn void Ctx.content_type(&self, String value);
fn void Ctx.set_cookie(&self, String value);
void? Context.delete_cookie(&self, String name);

CookieOptions opt = cookie_options_default();
    opt.http_only = true;
    opt.same_site = "Lax";
    opt.max_age = "0"; // seconds
fn void Ctx.cookie_set(&self, name, value, &opt);
void? Context.delete_cookie_path(&self, String name, String path);

fn Response* Ctx.text(&self, String text);
fn Response* Ctx.html(&self, String html);
fn Response* Ctx.json(&self, String json);
fn Response* Ctx.body_response(&self, char[] body);
fn Response* Ctx.empty(&self);
fn Response* Ctx.redirect(&self, String location, ushort status = 302);
fn Response* Ctx.not_found(&self);
fn Response* Ctx.internal_error(&self);
```

### Text response

```c3
fn Response* hello(Ctx* c)
{
    return c.text("hello");
}
```

This sets:

```http
Content-Type: text/plain; charset=utf-8
```

### HTML response

```c3
fn Response* page(Ctx* c)
{
    return c.html(`<h1>Hello</h1>`);
}
```

This sets:

```http
Content-Type: text/html; charset=utf-8
```

### JSON response

```c3
fn Response* api(Ctx* c)
{
    return c.json("{\"message\":\"hello\"}");
}
```

This sets:

```http
Content-Type: application/json; charset=utf-8
```

The current version expects JSON as a string. It does not yet serialize arbitrary C3 values.

### Status code

```c3
fn Response* created(Ctx* c)
{
    c.status(201);
    return c.json("{\"created\":true}");
}
```

### Custom headers

```c3
fn Response* handler(Ctx* c)
{
    c.header("X-App", "demo");
    return c.text("ok");
}
```

### Redirect

```c3
fn Response* redirect_home(Ctx* c)
{
    return c.redirect("/", 302);
}
```

## Request

`Request` stores parsed HTTP request data.

```c3
struct Request {
    String method;
    String target;
    String path;
    String query_string;
    String version;

    Headers headers;

    char[] body;
    bool owns_body;
}
```

Lifecycle:

```c3
fn void Request.init(&self);
fn void Request.free(&self);

fn Request* request_new();
fn void request_free(Request* req);
```

Accessors:

```c3
fn String? Request.header(&self, String name);
fn bool Request.has_body(&self);
fn sz? Request.content_length(&self);
fn bool Request.is_http_11(&self);
fn bool Request.is_http_10(&self);
```

Parser:

```c3
fn Request*? request_parse(char[] raw);
fn bool request_headers_complete(char[] raw);
fn sz? request_expected_total_len(char[] raw);
fn bool request_message_complete(char[] raw);
```

Example:

```c3
char[] raw = (char[])"GET /hello?name=c3 HTTP/1.1\r\nHost: localhost\r\n\r\n";

Request*? req = request_parse(raw);
if (catch err = req) {
    // handle BAD_REQUEST, REQUEST_TOO_LARGE, etc.
}

defer request_free(req);

io::printfn("%s %s", req.method, req.path);
```

## Response

`Response` stores HTTP status, headers, and body.

```c3
struct Response {
    ushort status;
    Headers headers;
    char[] body;
    bool owns_body;
}
```

Lifecycle:

```c3
fn void Response.init(&self);
fn void Response.free(&self);

fn Response* response_new();
fn void response_free(Response* res);
```

Constructors:

```c3
fn Response* response_empty(ushort status);
fn Response* response_body(char[] body);
fn Response* response_text(String text);
fn Response* response_html(String html);
fn Response* response_json(String json);
fn Response* response_redirect(String location, ushort status = 302);
fn Response* response_not_found();
fn Response* response_internal_error();
```

Mutators:

```c3
fn void Response.set_status(&self, ushort status);
fn void Response.header(&self, String name, String value);
fn void Response.add_header(&self, String name, String value);
fn void Response.content_type(&self, String value);
fn void Response.content_length(&self, sz value);
fn void Response.set_cookie(&self, String value);
fn void Response.set_body_copy(&self, char[] body);
fn void Response.set_body_borrowed(&self, char[] body);
fn void Response.set_text(&self, String text);
fn void Response.set_html(&self, String html);
fn void Response.set_json(&self, String json);
```

Serialization:

```c3
fn sz Response.serialized_len(&self);
fn sz Response.write_to(&self, char[] out);
fn String Response.serialize(&self);
```

Example:

```c3
Response* res = response_text("hello");
defer response_free(res);

String wire = res.serialize();
defer localmem.free(wire);

io::printfn("%s", wire);
```

`Content-Length` is automatically added during serialization if missing.

`Connection` is also added by default if missing.


## Query strings

Query strings are parsed into `Query`.


APIs:

```c3
fn String? url_decode(String s);
fn String? query_decode(String s);
fn void? query_parse(Query* out, String query_string);

fn Query? Request.query_params(&self);
fn String? Request.query_copy(&self, String name);

fn String? Request.decoded_path(&self);
```

Example:

```c3
fn Response* search(Ctx* c)
{
    String? q = c.query("q");

    if (catch err = q) {
        return c.text("missing query");
    }

    return c.text(q);
}
```

For repeated query access, prefer the context cache:

```c3
fn Response* handler(Ctx* c)
{
    Query* q = c.queries();

    if (q == null) {
        c.status(400);
        return c.text("bad query");
    }

    String? page = q.get("page");

    if (catch err = page) {
        return c.text("page missing");
    }

    return c.text(page);
}
```

Supported query forms:

```text
a=1
a=
flag
a=hello+world
a=%E2%9C%93
```

Behavior:

```text
+      -> space in query values
%XX    -> decoded byte
flag   -> value ""
```

## Path Params

Route parameters use path  `Params`.

APIs:

```c3
fn void params_init(Params* params);
fn void params_free(Params* params);
fn void params_clear(Params* params);

fn void? Params.put(&self, String name, String value);
fn void? Params.add_param(&self, String name, String value);
fn String? Params.get_param(&self, String name);
fn bool Params.has_param(&self, String name);
fn bool Params.delete_param(&self, String name);

fn void? Params.copy_from(&self, Params* other);
fn Params? params_clone(Params* src);

fn void? Params.set_splat(&self, String value);
fn String? Params.splat(&self);

fn void? Params.put_decoded(&self, String name, String raw_value);
fn void? Params.set_splat_decoded(&self, String raw_value);
```

Most users should access route params through `Context`:

```c3
String? id = c.param("id");
String? rest = c.splat();
```

## Middleware

Middleware follows a Hono-style chain.

```c3
alias Next = fn Response*(Ctx* c);
alias Middleware = fn Response*(Ctx* c, Next next);
```

Register middleware:

```c3
app.use(&middleware_logger);
app.use_path("/api", &auth_middleware)!!;
```

Global middleware:

```c3
fn Response* logger(Ctx* c, Next next)
{
    io::printfn("%s %s", c.method(), c.path());

    Response* res = next(c);

    if (res != null) {
        io::printfn("-> %d", res.status);
    }

    return res;
}
```

Path middleware:

```c3
import ext::httpserver;
import ext::asyncio;

fn Response* api_auth(Ctx* c, Next next)
{
    String? auth = c.req_header("Authorization");

    if (catch err = auth) {
        c.status(401);
        return c.text("Unauthorized");
    }

    return next(c);
}

fn void main_coro()
{
    Application app;
    app.init();
    defer app.free();

    app.use_path("/api", &api_auth)!!;

    app.get("/api/users", &users_handler)!!;

    app.listen(8080)!!;
}

fn void main()
{
    asyncio::run(&main_coro);
}
```

Early return middleware:

```c3
fn Response* block_all(Ctx* c, Next next)
{
    c.status(403);
    return c.text("Forbidden");
}
```

Middleware is executed in registration order.

## Built-in middleware

```c3
fn Response* middleware_logger(Ctx* c, Next next);
fn Response* middleware_powered_by(Ctx* c, Next next);
```

Example:

```c3
app.use(&httpserver::middleware_logger);
app.use(&httpserver::middleware_powered_by);
```

`middleware_powered_by` adds:

```http
X-Powered-By: ext::httpserver
```

### CORS

```c3 
    // Default:
    // Access-Control-Allow-Origin: *
    app.use(&httpserver::cors_default);

    // Turn on Credential
    httpserver::cors_allow_credentials(true);
    httpserver::cors_allow_origin("*");
    httpserver::cors_allow_headers("Content-Type, Authorization");
    httpserver::cors_allow_methods("GET, POST, PUT, PATCH, DELETE, OPTIONS");

    app.use(&httpserver::cors);
```


## Cookies

Cookies are represented through HTTP headers.

To send cookies, use `Ctx.set_cookie()`:

```c3
fn Response* login(Ctx* c)
{
    c.set_cookie("session_id=abc123; Path=/; HttpOnly; SameSite=Lax");
    return c.text("logged in");
}
```

To delete cookies:

```c3
fn Response* logout(Ctx* c)
{
    c.set_cookie("session_id=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax");
    return c.text("logged out");
}
```


Full cookie example:

```c3
fn Response* index(Ctx* c)
{
    String? sid = c.cookie("session_id");

    if (catch err = sid) {
        c.set_cookie("session_id=abc123; Path=/; HttpOnly; SameSite=Lax");
        c.set_cookie("theme=dark; Path=/; Max-Age=3600; SameSite=Lax");

        return c.text("No session cookie. New cookies were set.");
    }

    c.set_cookie("last_visit=now; Path=/; Max-Age=3600; SameSite=Lax");

    return c.text("session_id cookie received");
}
```

Because `Headers` allows repeated names, multiple `Set-Cookie` headers are preserved.

## Server

Basic serving APIs:

```c3
fn void? Application.serve(&self, String host, ushort port);
fn void? Application.listen(&self, ushort port);

fn void? http_serve(Application* app, String host, ushort port);
```

Example:

```c3
fn Response* hello(Ctx* c)
{
    return c.text("hello");
}

fn void main_coro()
{
    Application app;
    app.init();
    defer app.free();

    app.get("/", &hello)!!;

    app.serve("127.0.0.1", 8080)!!;
}

fn void main()
{
    asyncio::run(&main_coro);
}
```

`listen(port)` is shorthand for:

```c3
app.serve("127.0.0.1", port);
```

The current server implementation closes the connection after one request. This avoids unsafe behavior with pipelined data until per-connection buffered parsing is implemented.

## Raw fetch API

You can dispatch a parsed `Request` manually:

```c3
Response* Application.fetch(&self, Request* req);
```

Example:

```c3
Request* req = request_new();
defer request_free(req);

// fill req fields manually...

Response* res = app.fetch(req);
defer response_free(res);
```

You can also parse and dispatch a raw HTTP request:

```c3
Response* Application.fetch_raw(&self, char[] raw);
```

Example:

```c3
char[] raw = (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

Response* res = app.fetch_raw(raw);
defer response_free(res);

String wire = res.serialize();
defer localmem.free(wire);

io::printfn("%s", wire);
```

## Error behavior

Typical parser faults:

```c3
BAD_REQUEST
REQUEST_TOO_LARGE
INVALID_METHOD
INVALID_VERSION
INVALID_HEADER
BODY_INCOMPLETE
INVALID_URL_ENCODING
```

Router faults:

```c3
ROUTE_NOT_FOUND
METHOD_NOT_ALLOWED
INVALID_ROUTE_PATH
```

Middleware fault:

```c3
INVALID_MIDDLEWARE_PATH
```

`Application.fetch()` converts routing errors into normal responses:

```text
ROUTE_NOT_FOUND      -> 404 Not Found
METHOD_NOT_ALLOWED   -> 405 Method Not Allowed
other errors         -> 500 Internal Server Error
```

`Application.fetch_raw()` converts request parsing errors into:

```text
REQUEST_TOO_LARGE -> 413 Payload Too Large
other parse errors -> 400 Bad Request
```

## Memory ownership

This module uses `localmem` / `LocalAllocator` from `ext::mem`.

Important ownership rules:

### Request

`request_parse()` returns an owned `Request*`.

```c3
Request* req = request_parse(raw)!!;
defer request_free(req);
```

### Response

Handlers return `Response*`.

When using `Application.fetch()` or `Application.fetch_raw()`, the caller owns the returned response.

```c3
Response* res = app.fetch(req);
defer response_free(res);
```

Inside handlers, prefer using `Context` response builders:

```c3
return c.text("ok");
```

### Query

`Ctx.query()` returns a string owned by the context query cache. It is valid until `Ctx.free()`.

`Request.query_copy()` returns an allocated copy. The caller must free it.

### Headers

`Headers.add()` and `Headers.set()` copy name and value into the header list.

```c3
headers.set("Content-Type", "text/plain");
```

The caller does not need to keep the original strings alive.

## Complete example

```c3
module examples::app;

import std::io;
import ext::httpserver;
import ext::asyncio;

fn Response* home(Ctx* c)
{
    return c.text("Hello");
}

fn Response* user(Ctx* c)
{
    String? id = c.param("id");

    if (catch err = id) {
        c.status(400);
        return c.text("missing id");
    }

    return c.json(string::tformat("{\"id\":\"%s\"}", id));
}

fn Response* search(Ctx* c)
{
    String? q = c.query("q");

    if (catch err = q) {
        return c.text("missing query");
    }

    return c.text(q);
}

fn Response* auth(Ctx* c, Next next)
{
    String? token = c.req_header("Authorization");

    if (catch err = token) {
        c.status(401);
        return c.text("Unauthorized");
    }

    return next(c);
}

fn void main_coro()
{
    Application app;
    app.init();
    defer app.free();

    app.use(&middleware_logger);
    app.use(&middleware_powered_by);

    app.get("/", &home)!!;
    app.get("/users/:id", &user)!!;

    app.use_path("/api", &auth)!!;
    app.get("/api/search", &search)!!;

    app.listen(8080)!!;
}

fn void main()
{
    asyncio::run(&main_coro);
}
```

## Suggested file layout

```text
ext/httpserver/
  header.c3
  response.c3
  request.c3
  url.c3
  params.c3
  router.c3
  context.c3
  middleware.c3
  application.c3
  server.c3
  README.md
```

## Design notes

`ext::httpserver` intentionally follows a Hono-like simple programming model, but it is adapted to C3:

- explicit memory ownership
- explicit fault handling
- no closures for middleware `next`
- duplicate headers preserved
- route params owned by `Context`
- query params cached by `Context`
- response builders return `Response*`

The goal is a small, understandable HTTP framework that works naturally with C3 and can later grow into a richer async web framework.
