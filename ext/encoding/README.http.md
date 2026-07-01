# ext::encoding::http - HTTP parser for C3

`ext::encoding::http` is a zero-copy HTTP/1.x request and response parser for the [ext.c3l](../../README.md) library ecosystem. It parses raw byte buffers into `Request` and `Response` structs whose string fields are slices into the original buffer — no heap allocation is required. Decode helpers for URI, cookies, query strings, and form data (both `application/x-www-form-urlencoded` and `multipart/form-data`) are included, all accelerated by an 8-wide SIMD-style scan built on C3's native vector types.

## Available module

| Module | Description |
|--------|-------------|
| `ext::encoding::http` | HTTP/1.x parser: `Request`, `Response`, `Url`, `SetCookie`, `FormFile`, `KeyValue`, `parse_request()`, `parse_response()`, decode helpers |

### Files

* [http.c3](http.c3)

### Exqmples

* [../../test/encoding/http_sample.c3](../../test/encoding/http_sample.c3)

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.

---

## Types

### `KeyValue`

A key/value string pair used for headers, cookies, query parameters, and form fields.

```c3
struct KeyValue {
    String key;
    String value;
}
```

---

### `Url`

Parsed components of a URI. All fields are zero-length slices when the corresponding component is absent.

```c3
struct Url {
    String protocol;   // e.g. "https"
    String user;       // userinfo before '@'
    String password;   // password part of userinfo
    String host;       // hostname or IP
    String port;       // port string (not converted to int)
    String path;       // path component
    String query;      // query string (without leading '?')
    String fragment;   // fragment (without leading '#')
}
```

---

### `FormFile`

A single file-upload part extracted from a `multipart/form-data` body.

```c3
struct FormFile {
    String name;      // field name from Content-Disposition
    String filename;  // original filename from Content-Disposition
    String mime;      // Content-Type of this part
    String data;      // raw file bytes as a String slice
}
```

---

### `Request`

A fully parsed HTTP request. String fields are zero-copy slices into the original buffer.

```c3
const MAX = 64;

struct Request {
    String method;
    String uri;
    String version;

    String client_ip;
    ushort client_port;

    KeyValue[MAX] headers;
    uint n_headers;

    sz  content_length;  // decoded from Content-Length header
    bool chunked;         // true when Transfer-Encoding: chunked

    Url    url;
    String base_url;

    KeyValue[MAX] cookies;
    uint n_cookies;

    KeyValue[MAX] queries;
    sz n_queries;

    KeyValue[MAX] form;
    sz n_form;

    FormFile[MAX] files;
    uint n_files;

    String[MAX/4] ips;

    char* body;  // pointer to first byte after the header block
}
```

---

### `SetCookie`

Parsed attributes of a single `Set-Cookie` response header.

```c3
struct SetCookie {
    String name;
    String value;
    String domain;
    String path;
    String expires;
    String max_age;
    String same_site;
    bool http_only;
    bool secure;
}
```

---

### `Response`

A fully parsed HTTP response. String fields are zero-copy slices into the original buffer.

```c3
struct Response {
    String status;   // e.g. "404"
    String message;  // e.g. "Not Found"

    KeyValue[MAX] headers;
    uint n_headers;

    sz  content_length;
    bool chunked;

    SetCookie[MAX] set_cookies;
    sz n_set_cookies;

    char* body;
}
```

---

## Faults

| Fault | Meaning |
|-------|---------|
| `ERROR` | The input is malformed and cannot be recovered |
| `INCOMPLETE` | The input is valid so far but needs more data |

---

## API

### Parsing

```c3
import ext::encoding::http;

// Parse a complete HTTP request from a raw buffer.
// Returns a pointer to the first byte of the body, or propagates ERROR / INCOMPLETE.
char*? buf = http::parse_request(char* buf, char* end, Request* req);

// Parse a complete HTTP response from a raw buffer.
char*? buf = http::parse_response(char* buf, char* end, Response* resp);
```

**Example**

```c3
Request req;
char* body_start = http::parse_request(buf, buf + len, &req)!;

io::printfn("method : %s", req.method);
io::printfn("uri    : %s", req.uri);
io::printfn("version: %s", req.version);
for (uint i = 0; i < req.n_headers; i++) {
    io::printfn("%s: %s", req.headers[i].key, req.headers[i].value);
}
```

---

### Request — decode helpers

All helpers operate on data already stored in the `Request` struct after `parse_request()`.

```c3
bool ok = req.decode_uri();             // fills req.url (Url struct)
bool ok = req.decode_content_length();  // fills req.content_length / req.chunked
bool ok = req.decode_cookies();         // fills req.cookies / req.n_cookies
bool ok = req.decode_query();           // fills req.queries / req.n_queries
bool ok = req.decode_form();            // fills req.form / req.n_form / req.files / req.n_files
```

Each helper returns `true` when at least one value was decoded, `false` when the relevant header or body was absent or empty.

**Example — URI and query**

```c3
req.decode_uri();
io::printfn("host : %s", req.url.host);
io::printfn("path : %s", req.url.path);

req.decode_query();
for (sz i = 0; i < req.n_queries; i++) {
    io::printfn("%s = %s", req.queries[i].key, req.queries[i].value);
}
```

**Example — cookies**

```c3
req.decode_cookies();
for (uint i = 0; i < req.n_cookies; i++) {
    io::printfn("%s = %s", req.cookies[i].key, req.cookies[i].value);
}
```

**Example — form data**

```c3
req.decode_content_length();
req.decode_form();

// URL-encoded or multipart text fields
for (sz i = 0; i < req.n_form; i++) {
    io::printfn("%s = %s", req.form[i].key, req.form[i].value);
}

// Uploaded files (multipart only)
for (uint i = 0; i < req.n_files; i++) {
    FormFile* f = &req.files[i];
    io::printfn("file: %s (%s, %d bytes)", f.filename, f.mime, f.data.len);
}
```

---

### Response — decode helpers

```c3
bool ok = resp.decode_setcookies();  // fills resp.set_cookies / resp.n_set_cookies
```

**Example**

```c3
Response resp;
http::parse_response(buf, buf + len, &resp)!;
resp.decode_setcookies();

for (sz i = 0; i < resp.n_set_cookies; i++) {
    SetCookie* sc = &resp.set_cookies[i];
    io::printfn("%s=%s; Path=%s; Secure=%s",
        sc.name, sc.value, sc.path, sc.secure ? "true" : "false");
}
```

---

## Internal details

`parse_request` and `parse_response` are thin wrappers around `parse_http_req` / `parse_http_resp` (request/response line) and `parse_key_value` (header loop). None of the public parse functions allocate memory; all `String` fields are pointer-length slices into the caller-supplied buffer.

The character search hot path uses `find_char` / `find_chars`, which process 8 bytes at a time using C3's native vector type `char[<8>]` (`comp_eq` + `mask_to_int` + `ctz`). Tail bytes (< 8 remaining) fall back to a scalar loop. `find_boundary` is used for multipart delimiter scanning.

`decode_form` handles both `application/x-www-form-urlencoded` (delegating to `decode_query`) and `multipart/form-data`, including per-part `Content-Disposition` and `Content-Type` header parsing and trailing-CRLF stripping.

---

## Notes

- All `String` fields in `Request` and `Response` are slices of the **original input buffer**. The buffer must remain valid for as long as the struct is used.
- `MAX = 64` caps headers, cookies, query params, form fields, and file uploads per message. File uploads additionally have a `MAX/4 = 16` IP-forwarding-chain limit.
- `decode_content_length()` must be called before `decode_form()` so that `req.content_length` is set and the body slice is correct.
- Header name comparison throughout is case-insensitive via the `str_iequals` helper (branchless lowercase via bitwise OR).
- `Transfer-Encoding: chunked` detection in `decode_content_length()` handles comma-separated lists such as `"gzip, chunked"`.

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.
