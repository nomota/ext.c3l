# ext::flask for C3

A C3 port of Python's Flask web framework, built on top of [ext::asyncio](../asyncio/README.md).
Route handlers run as asyncio fibers, so all async I/O inside a handler looks synchronous.

### Available modules

| Module | Description |
|--------|-------------|
| `ext::flask` | Application, config, routing, request, response, session, blueprints |

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.

### Files

* [flask.c3](flask.c3): FlaskApp, config, lifecycle, server
* [flask.request.c3](flask.request.c3): Request, Headers, MultiDict, FileStorage, Authorization
* [flask.response.c3](flask.response.c3): Response, CacheControl, Cookie, streaming
* [flask.blueprint.c3](flask.blueprint.c3): Blueprint, nested blueprint registration
* [flask.session.c3](flask.session.c3): Session, signed-cookie storage
* [flask.routing.c3](flask.routing.c3): RouteRule, URL building, path parameter parsing
* [flask.globals.c3](flask.globals.c3): AppGlobals (equivalent to Python's flask.g)

---

### Constants

```c3
import ext::flask;

// HTTP method bitmask flags (combinable with |)
const int HTTP_GET     = 0x01;
const int HTTP_POST    = 0x02;
const int HTTP_PUT     = 0x04;
const int HTTP_DELETE  = 0x08;
const int HTTP_PATCH   = 0x10;
const int HTTP_HEAD    = 0x20;
const int HTTP_OPTIONS = 0x40;
const int HTTP_ANY     = 0x7F; // match any method

// HTTP status codes
const int HTTP_200 = 200;
const int HTTP_201 = 201;
const int HTTP_204 = 204;
const int HTTP_301 = 301;
const int HTTP_302 = 302;
const int HTTP_304 = 304;
const int HTTP_400 = 400;
const int HTTP_401 = 401;
const int HTTP_403 = 403;
const int HTTP_404 = 404;
const int HTTP_405 = 405;
const int HTTP_409 = 409;
const int HTTP_410 = 410;
const int HTTP_415 = 415;
const int HTTP_422 = 422;
const int HTTP_429 = 429;
const int HTTP_500 = 500;
const int HTTP_503 = 503;

// Cookie SameSite policy values
const int SAMESITE_LAX    = 0;
const int SAMESITE_STRICT = 1;
const int SAMESITE_NONE   = 2;

// Well-known config key strings
const String CFG_DEBUG                      = "DEBUG";
const String CFG_TESTING                    = "TESTING";
const String CFG_SECRET_KEY                 = "SECRET_KEY";
const String CFG_SESSION_COOKIE_NAME        = "SESSION_COOKIE_NAME";
const String CFG_SESSION_COOKIE_SECURE      = "SESSION_COOKIE_SECURE";
const String CFG_SESSION_COOKIE_HTTPONLY    = "SESSION_COOKIE_HTTPONLY";
const String CFG_SESSION_COOKIE_SAMESITE    = "SESSION_COOKIE_SAMESITE";
const String CFG_PERMANENT_SESSION_LIFETIME = "PERMANENT_SESSION_LIFETIME";
const String CFG_MAX_CONTENT_LENGTH         = "MAX_CONTENT_LENGTH";
const String CFG_JSON_SORT_KEYS             = "JSON_SORT_KEYS";
const String CFG_TEMPLATES_AUTO_RELOAD      = "TEMPLATES_AUTO_RELOAD";
const String CFG_SERVER_NAME                = "SERVER_NAME";
const String CFG_APPLICATION_ROOT           = "APPLICATION_ROOT";
const String CFG_PREFERRED_URL_SCHEME       = "PREFERRED_URL_SCHEME";

// Seek origin constants (mirror POSIX)
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
```

---

### Fault types

```c3
import ext::flask;

fault FlaskFault {
    BAD_REQUEST,            // 400
    UNAUTHORIZED,           // 401
    FORBIDDEN,              // 403
    NOT_FOUND,              // 404
    METHOD_NOT_ALLOWED,     // 405
    CONFLICT,               // 409
    GONE,                   // 410
    UNSUPPORTED_MEDIA_TYPE, // 415
    UNPROCESSABLE_ENTITY,   // 422
    TOO_MANY_REQUESTS,      // 429
    INTERNAL_SERVER_ERROR,  // 500
    SERVICE_UNAVAILABLE,    // 503
    ABORT,                  // explicit abort() with a custom status code
    SESSION_ERROR,          // session encoding or decoding failed
    CONFIG_ERROR,           // required config key is missing or has wrong type
    ROUTE_NOT_FOUND,        // no rule matched the incoming path
    JSON_PARSE_ERROR,       // request body is not valid JSON
    FILE_NOT_FOUND,         // send_file() target does not exist
    UPLOAD_TOO_LARGE,       // request body exceeds MAX_CONTENT_LENGTH
}
```

---

### Callback aliases

```c3
import ext::flask;

// RouteHandler: fiber coroutine invoked for a matched URL rule.
// Receives the current Request and must return a Response.
alias RouteHandler = fn Response*(Request*);

// BeforeRequestHook: called before the route handler on every request.
// Returning a non-null Response short-circuits the handler.
alias BeforeRequestHook = fn Response*(Request*);

// AfterRequestHook: called after the handler returns.
// Must return the (possibly modified) Response; never null.
alias AfterRequestHook = fn Response*(Request*, Response*);

// TeardownHook: called once the response has been delivered, even on error.
// exc is NO_ERR for a clean teardown.
alias TeardownHook = fn void(fault exc);

// ErrorHandler: converts a status code and description into a Response.
alias ErrorHandler = fn Response*(int status_code, String description);

// StreamGenerator: called repeatedly to produce body chunks.
// Write the next chunk into *chunk / *chunk_len; return true to continue,
// false when the stream is exhausted.
alias StreamGenerator = fn bool(char** chunk, usz* chunk_len, void* ctx);
```

---

### Structs

```c3
import ext::flask;

// HeaderEntry: a single HTTP header field
struct HeaderEntry {
    String key;   // field name (case-insensitive by HTTP convention)
    String value; // field value
}

// Headers: ordered, case-insensitive HTTP header collection
struct Headers {
    HeaderEntry* entries;
    usz          count;
    usz          capacity;
}

// MultiDictEntry: one entry in a multi-value key-value store
struct MultiDictEntry {
    String key;
    String value;
}

// MultiDict: ordered dictionary that allows multiple values per key.
// Used for query args, form data, cookies, and file fields.
struct MultiDict {
    MultiDictEntry* entries;
    usz             count;
    usz             capacity;
}

// FileStorage: one uploaded file from a multipart/form-data request
struct FileStorage {
    String filename;       // original filename as sent by the client
    String content_type;   // MIME type declared by the client
    usz    content_length; // declared byte length; 0 if unknown
    char*  stream;         // raw bytes of the file body
    usz    stream_len;     // number of bytes in stream
}

// Authorization: parsed HTTP Authorization header
struct Authorization {
    String scheme;    // "Basic" | "Bearer" | "Digest" | ...
    String username;  // non-empty only for Basic auth
    String password;  // non-empty only for Basic auth
    String token;     // non-empty only for Bearer auth
}

// CacheControl: HTTP Cache-Control directives for a Response
struct CacheControl {
    int  max_age;        // seconds; -1 means directive is absent
    bool no_cache;
    bool no_store;
    bool must_revalidate;
    bool public_flag;
    bool private_flag;
    bool immutable_flag;
}

// Cookie: a single outgoing Set-Cookie value
struct Cookie {
    String key;
    String value;
    int    max_age;  // seconds; -1 means session cookie
    long   expires;  // unix timestamp; -1 means not set
    String path;     // defaults to "/"
    String domain;   // empty means omit Domain attribute
    bool   secure;
    bool   httponly;
    int    samesite; // SAMESITE_LAX | SAMESITE_STRICT | SAMESITE_NONE
}

// ConfigEntry: one key-value pair in the application configuration
struct ConfigEntry {
    String key;
    String value; // all values are stored as strings; parse on read
}

// FlaskConfig: the application configuration store
struct FlaskConfig {
    ConfigEntry* entries;
    usz          count;
    usz          capacity;
}

// Request: the incoming HTTP request for the currently running fiber.
// Populated by the framework before invoking the RouteHandler.
struct Request {
    String  method;         // "GET" | "POST" | "PUT" | "DELETE" | "PATCH" | ...
    String  path;           // "/items/1"
    String  full_path;      // "/items/1?q=foo"
    String  url;            // fully qualified URL string
    String  base_url;       // URL without query string
    String  host;           // "example.com:5000"
    String  host_url;       // "http://example.com:5000/"
    String  scheme;         // "http" | "https"
    bool    is_secure;      // true when scheme is https
    bool    is_json;        // true when Content-Type is application/json

    Headers*   headers;
    MultiDict* args;        // parsed query string parameters
    MultiDict* form;        // application/x-www-form-urlencoded or multipart fields
    MultiDict* cookies;     // cookies sent by the client
    MultiDict* files;       // uploaded files; cast values to FileStorage*

    char*  data;            // raw request body bytes (null if consumed as form or files)
    usz    data_len;

    Authorization* authorization; // parsed Authorization header; null if absent
    String remote_addr;           // client IP address string
    String endpoint;              // name of the matched route endpoint
    MultiDict* view_args;         // path segment captures e.g. id from /items/<int:id>
    String content_type;
    usz    content_length;        // 0 if Content-Length header is absent
}

// Response: an outgoing HTTP response constructed by a route handler
struct Response {
    int    status_code;      // e.g. 200
    String status;           // e.g. "200 OK"
    char*  data;             // body bytes; null when using a StreamGenerator
    usz    data_len;

    Headers*     headers;
    String       content_type;     // full Content-Type value with params
    String       mimetype;         // MIME type without parameters
    String       charset;          // character set e.g. "utf-8"
    CacheControl cache_control;
    long         last_modified;    // unix timestamp; -1 if not set
    long         expires;          // unix timestamp; -1 if not set
    bool         direct_passthrough; // skip body processing when true

    StreamGenerator generator;     // non-null enables chunked streaming
    void*           generator_ctx; // opaque context passed to generator
}

// RouteRule: one registered URL rule bound to a handler function
struct RouteRule {
    String       path;          // URL pattern e.g. "/items/<int:id>"
    String       endpoint;      // name used with url_for(); defaults to handler name
    int          methods;       // bitmask of HTTP_GET | HTTP_POST | ...
    RouteHandler handler;
    bool         strict_slashes; // if false, trailing slash mismatch is tolerated
}

// Blueprint: a named collection of routes sharing a URL prefix and hooks
struct Blueprint {
    String name;
    String url_prefix;
    String template_folder;
    String static_folder;
    String static_url_path;
    String subdomain;

    RouteRule*         rules;
    usz                rule_count;
    usz                rule_cap;

    Blueprint**        children;   // nested child blueprints
    usz                child_count;

    BeforeRequestHook* before_hooks;
    usz                before_count;

    AfterRequestHook*  after_hooks;
    usz                after_count;

    ErrorHandler*      error_handlers;
    int*               error_codes;  // parallel array with error_handlers
    usz                error_handler_count;
}

// Session: per-request session store backed by a signed cookie.
// Keyed by the current fiber; automatically serialized on response send.
struct Session {
    MultiDict* data;
    bool       modified; // true if data was mutated since last load
    bool       permanent; // true uses PERMANENT_SESSION_LIFETIME instead of browser session
}

// AppGlobals: per-request scratch space equivalent to Python's flask.g.
// Lifetime is one request; reset before the next handler runs.
struct AppGlobals {
    String* keys;
    void**  values; // caller-managed pointers; framework does not free them
    usz     count;
    usz     capacity;
}

// FlaskApp: the central application object
struct FlaskApp {
    String name;
    String static_url_path;
    String static_folder;
    String template_folder;
    String instance_path;
    bool   host_matching;
    bool   subdomain_matching;

    FlaskConfig* config;

    RouteRule*  rules;
    usz         rule_count;
    usz         rule_cap;

    Blueprint** blueprints;
    usz         blueprint_count;

    BeforeRequestHook* before_hooks;
    usz                before_count;

    AfterRequestHook*  after_hooks;
    usz                after_count;

    TeardownHook*      teardown_hooks;      // called after each request
    usz                teardown_count;

    TeardownHook*      appctx_teardown_hooks; // called when app context is torn down
    usz                appctx_teardown_count;

    ErrorHandler*      error_handlers;
    int*               error_codes;         // parallel array with error_handlers
    usz                error_handler_count;

    asyncio::EventLoop* loop; // the underlying asyncio event loop driving the server
}
```

---

### API functions

#### FlaskApp lifecycle

```c3
import ext::flask;

FlaskApp* app = flask::new_app(String name); // allocate and initialize a new application

void app.free(); // release all resources held by the application
```

#### Configuration

```c3
import ext::flask;

// Read a config value as a raw string; returns null if key is absent
String? v = app.config.get(String key);

void app.config.set(String key, String value);

// Convenience typed accessors with a fallback default
bool b   = app.config.get_bool(String key, bool default_val);
int  n   = app.config.get_int(String key, int default_val);

// Bulk load: import KEY=VALUE environment variables after stripping prefix_
void app.config.from_envvar(String prefix);

// Bulk load from parallel arrays; count must equal the length of both arrays
void app.config.from_mapping(String* keys, String* values, usz count);
```

#### Route registration

```c3
import ext::flask;

void app.add_url_rule(
    String      path,
    String      endpoint,    // empty string defaults to the handler address as a name
    RouteHandler handler,
    int         methods,     // bitmask of HTTP_GET | HTTP_POST | ...
    bool        strict_slashes
);

// Shorthand for single-method registration
void app.get(String path, RouteHandler handler);
void app.post(String path, RouteHandler handler);
void app.put(String path, RouteHandler handler);
void app.patch(String path, RouteHandler handler);
void app.delete(String path, RouteHandler handler);
void app.options(String path, RouteHandler handler);
void app.head(String path, RouteHandler handler);
```

#### Blueprint registration

```c3
import ext::flask;

void app.register_blueprint(Blueprint* bp);

// register_blueprint_at overrides the blueprint url_prefix
void app.register_blueprint_at(Blueprint* bp, String url_prefix);
```

#### Lifecycle hooks

```c3
import ext::flask;

void app.add_before_request(BeforeRequestHook hook);

void app.add_after_request(AfterRequestHook hook);

// teardown_request hooks run after the response is delivered, even on error
void app.add_teardown_request(TeardownHook hook);

// appcontext teardown runs when the application context is popped
void app.add_teardown_appcontext(TeardownHook hook);

void app.add_error_handler(int status_code, ErrorHandler handler);
```

#### Running the server

```c3
import ext::flask;

// Blocking call: starts the asyncio event loop and serves requests
void? app.run(String host, ushort port) @maydiscard;

// Signal the event loop to stop after finishing in-flight requests
void app.stop();
```

#### URL building

```c3
import ext::flask;

// Build a URL for endpoint with named parameters.
// param_keys and param_values are parallel arrays of length param_count.
// Keys not matching path segments become query string parameters.
// external=true prepends scheme and host.
// Returns null when the endpoint is not registered.
String? url = flask::url_for(
    String  endpoint,
    String* param_keys,
    String* param_values,
    usz     param_count,
    bool    external
);
```

#### Per-fiber context accessors

```c3
import ext::flask;

// Return the Request bound to the currently running fiber
Request* req = flask::current_request();

// Return the Session bound to the currently running fiber
Session* sess = flask::current_session();

// Return the per-request AppGlobals (flask.g) for the current fiber
AppGlobals* g = flask::current_g();
```

#### Request helpers

```c3
import ext::flask;

// Parse the request body as JSON; returns the raw JSON bytes.
// force=true ignores Content-Type; silent=true returns null on parse error.
// Caller must free the returned slice.
char[]? json = req.get_json(bool force, bool silent);

// Return the raw request body bytes; caller must free.
// as_text=true ensures the slice is null-terminated.
char[]? raw = req.get_data(bool as_text);

// Query-string parameter lookup
String? v  = req.args.get(String key);

// Return all values for key in query string; caller must free the slice.
String[]? vs = req.args.getlist(Allocator alloc, String key);

// Form field lookup
String? v  = req.form.get(String key);

String[]? vs = req.form.getlist(Allocator alloc, String key);

// Cookie lookup
String? v = req.cookies.get(String key);

// Header lookup (case-insensitive); returns default_val when absent
String v = req.headers.get(String key, String default_val);

// Retrieve an uploaded file by its form field name; null if not uploaded
FileStorage*? f = req.files.get_file(String field_name);

// Read the entire uploaded file into a new allocation; caller must free
char[]? data = file.read(Allocator alloc);

// Write the uploaded file to dest_path on disk (uses aiofiles internally)
void? file.save(String dest_path);
```

#### Response construction

```c3
import ext::flask;

// General-purpose response builder
Response* resp = flask::make_response(
    char*  body,
    usz    body_len,
    int    status_code,
    String content_type
);

// Convenience: body is a null-terminated text string; Content-Type is text/html
Response* resp = flask::make_text_response(String text, int status_code);

// Convenience: body is a pre-serialized JSON string; Content-Type is application/json
Response* resp = flask::make_json_response(char* json_str, usz json_len, int status_code);

// HTTP redirect; code is typically HTTP_301 or HTTP_302
Response* resp = flask::redirect(String location, int code);

// Serve a file from disk with optional attachment disposition
Response* resp = flask::send_file(
    String path,
    String mimetype,
    bool   as_attachment,
    String download_name  // used in Content-Disposition when as_attachment is true
);

// Serve a file from a directory; directory is joined with filename safely
Response* resp = flask::send_from_directory(
    String directory,
    String filename,
    bool   as_attachment
);

// Streaming response: generator is called repeatedly until it returns false
Response* resp = flask::stream_response(
    StreamGenerator gen,
    void*           ctx,
    String          content_type
);

// Terminate the current handler with an HTTP error.
// Raises a FlaskFault that maps to status_code; the registered error handler fires.
void? flask::abort(int status_code) @maydiscard;
```

#### Response manipulation

```c3
import ext::flask;

void resp.set_status(int status_code);

void resp.set_content_type(String content_type);

void resp.set_header(String key, String value);

String resp.get_header(String key, String default_val);

void resp.set_cookie(
    String key,
    String value,
    int    max_age,  // seconds; -1 omits the attribute
    long   expires,  // unix timestamp; -1 omits the attribute
    String path,     // pass "" to use "/"
    String domain,   // pass "" to omit the attribute
    bool   secure,
    bool   httponly,
    int    samesite  // SAMESITE_LAX | SAMESITE_STRICT | SAMESITE_NONE
);

void resp.delete_cookie(String key, String path, String domain, bool secure, int samesite);

// ETag support
void resp.set_etag(String etag, bool weak);
String resp.get_etag(); // returns "" if no ETag is set

// Vary header
void resp.vary_add(String field_name);

void resp.free(); // prevent memory leak
```

#### Session

```c3
import ext::flask;

String? v = sess.get(String key); // null when key is absent

void sess.set(String key, String value); // insert or overwrite

void sess.pop(String key); // remove key if present; no-op otherwise

bool b = sess.has(String key);

void sess.clear(); // remove all keys
```

#### AppGlobals (g)

```c3
import ext::flask;

// Retrieve a stored pointer by key; returns null if not set
void* ptr = g.get(String key);

// Store an opaque pointer; the framework does not manage its lifetime
void g.set(String key, void* value);

// Remove a key; no-op if absent
void g.pop(String key);
```

#### Blueprint

```c3
import ext::flask;

Blueprint* bp = flask::new_blueprint(String name, String url_prefix);

void bp.free(); // prevent memory leak

void bp.add_url_rule(
    String       path,
    String       endpoint,
    RouteHandler handler,
    int          methods,
    bool         strict_slashes
);

// Shorthand for single-method registration under the blueprint
void bp.get(String path, RouteHandler handler);
void bp.post(String path, RouteHandler handler);
void bp.put(String path, RouteHandler handler);
void bp.patch(String path, RouteHandler handler);
void bp.delete(String path, RouteHandler handler);
void bp.options(String path, RouteHandler handler);

void bp.add_before_request(BeforeRequestHook hook);

void bp.add_after_request(AfterRequestHook hook);

void bp.add_error_handler(int status_code, ErrorHandler handler);

// Attach a child blueprint; child prefix is appended to bp prefix
void bp.register_blueprint(Blueprint* child);
```

#### Headers helpers

```c3
import ext::flask;

Headers* flask::headers_new(); // allocate an empty Headers collection

void headers.free(); // prevent memory leak

void headers.set(String key, String value); // overwrite existing key

void headers.add(String key, String value); // append without replacing

String headers.get(String key, String default_val); // case-insensitive lookup

bool headers.has(String key); // case-insensitive presence check

void headers.remove(String key); // remove all entries with this key
```

#### MultiDict helpers

```c3
import ext::flask;

MultiDict* flask::multidict_new(); // allocate an empty MultiDict

void multidict.free(); // prevent memory leak

// Return the first value for key; null when absent
String? multidict.get(String key);

// Return all values for key in insertion order; caller must free the slice
String[]? multidict.getlist(Allocator alloc, String key);

// Insert or overwrite; replaces only the first occurrence
void multidict.set(String key, String value);

// Append a new entry without removing existing ones
void multidict.add(String key, String value);

// Cast the stored void* for the given field name to FileStorage*; null if absent
FileStorage*? multidict.get_file(String key);
```

---

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.
