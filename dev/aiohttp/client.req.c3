// client.req.c3

module ext::aiohttp;

import ext::asyncio;
import std::encoding::base64;

// HTTP/1.1 request serializer — client side.
//
// Builds a complete HTTP/1.1 request byte stream and writes it to a Stream*.
// No heap allocation for the header block: a stack-allocated scratch buffer
// (REQ_SCRATCH_SIZE) is used. Body data is written directly from the caller's
// pointer without copying.
//
// Supported body kinds (mutually exclusive, checked in priority order):
//   1. json_str  → Content-Type: application/json
//   2. form      → Content-Type: multipart/form-data; boundary=<b>
//   3. data/data_len → Content-Type: application/octet-stream (if not overridden)
//   4. (none)    → no body, no Content-Type
//
// Chunked transfer encoding is NOT used for the request body — Content-Length
// is always emitted. (aiohttp Python client behaves the same way for buffered
// bodies.)
//
// Query parameters:
//   If params != null, the encoded query string is appended to the URL path
//   before writing the request line.

//  constants 

const usz REQ_SCRATCH_SIZE  @private = 8192;   // header scratch buffer (stack)
const usz REQ_BOUNDARY_LEN  @private = 16;     // multipart boundary hex chars
const usz REQ_MAX_HEADERS   @private = 64;     // sanity cap on merged header list

//  private helpers 

// Append a string to the scratch buffer. Returns false on overflow.
fn bool scratch_put(char* buf, usz* j, usz cap, String s) @private @inline
{
    if (*j + s.len > cap) return false;
    for (usz i = 0; i < s.len; i++) buf[(*j)++] = s[i];
    return true;
}

fn bool scratch_putc(char* buf, usz* j, usz cap, char c) @private @inline
{
    if (*j >= cap) return false;
    buf[(*j)++] = c;
    return true;
}

// Format a usz integer as decimal into buf. Returns number of chars written.
fn usz fmt_decimal(char* buf, usz n) @private
{
    if (n == 0) { buf[0] = '0'; return 1; }
    char[20] tmp;
    usz len = 0;
    usz v = n;
    while (v > 0) { tmp[len++] = (char)('0' + v % 10); v /= 10; }
    for (usz i = 0; i < len; i++) buf[i] = tmp[len - 1 - i];
    return len;
}

// HTTP method name string.
fn String method_str(HttpMethod m) @private @inline
{
    switch (m) {
        case HttpMethod.GET:     return "GET";
        case HttpMethod.POST:    return "POST";
        case HttpMethod.PUT:     return "PUT";
        case HttpMethod.PATCH:   return "PATCH";
        case HttpMethod.DELETE:  return "DELETE";
        case HttpMethod.HEAD:    return "HEAD";
        case HttpMethod.OPTIONS: return "OPTIONS";
        default:                 return "GET";
    }
}

// Case-insensitive header name equality.
fn bool hdr_name_eq(String a, String b) @private
{
    if (a.len != b.len) return false;
    for (usz i = 0; i < a.len; i++) {
        char ca = a[i]; 
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca | 0x20);
        char cb = b[i]; 
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb | 0x20);
        if (ca != cb) return false;
    }
    return true;
}

// Generate a simple hex boundary string from a counter + clock value.
// Writes exactly REQ_BOUNDARY_LEN hex chars into out[REQ_BOUNDARY_LEN].
fn void make_boundary(char* out) @private
{
    const char[16] HEX = "0123456789abcdef";
    ulong seed = asyncio::clock_now();
    for (usz i = 0; i < REQ_BOUNDARY_LEN; i++) {
        out[i] = HEX[(seed >> (i * 4)) & 0xF];
    }
}

//  merged header list 
//
// Merge default_headers + per-request headers into a flat list,
// with per-request headers overriding defaults (case-insensitive key match).

struct MergedHeaders @private {
    Header[REQ_MAX_HEADERS] entries;
    usz    count;
}

fn void merged_init(MergedHeaders* m) @private { m.count = 0; }

fn void merged_add(MergedHeaders* m, String name, String value) @private
{
    // overwrite if key already present
    for (usz i = 0; i < m.count; i++) {
        if (hdr_name_eq(m.entries[i].name, name)) {
            m.entries[i].value = value;
            return;
        }
    }
    if (m.count >= REQ_MAX_HEADERS) return;
    m.entries[m.count++] = (Header){ name, value };
}

fn void merged_add_headers(MergedHeaders* m, Headers* h) @private
{
    if (h == null) return;
    for (usz i = 0; i < h.count; i++) {
        merged_add(m, h.entries[i].name, h.entries[i].value);
    }
}

fn bool merged_has(MergedHeaders* m, String name) @private
{
    for (usz i = 0; i < m.count; i++) {
        if (hdr_name_eq(m.entries[i].name, name)) return true;
    }
    return false;
}

//  request write context 

struct ReqCtx @private {
    char[REQ_SCRATCH_SIZE] scratch;
    usz                    scratch_len;
    char[REQ_BOUNDARY_LEN] boundary;
}

// non-optional stream.write() to optional
faultdef STREAM_WRITE_FAIL;

fn usz? s_write(Stream* s, char[] buf) @inline
{
    usz n = s.write(buf);
    if (n == 0) {
        return STREAM_WRITE_FAIL~;
    }
    return n;
}

//  multipart body builder 

// Calculate the total byte length of a multipart/form-data body.
fn usz multipart_body_len(FormData* form, char* boundary) @private
{
    usz total = 0;
    for (usz i = 0; i < form.count; i++) {
        FormDataField* f = &form.fields[i];
        // "--boundary\r\n"
        total += 2 + REQ_BOUNDARY_LEN + 2;
        // Content-Disposition header
        total += 38 + f.name.len; // 'Content-Disposition: form-data; name="' + name + '"'
        if (f.filename.len > 0) {
            total += 12 + f.filename.len; // '; filename="' + filename + '"'
        }
        total += 2; // "\r\n"
        // Content-Type header (if set or filename present)
        if (f.content_type.len > 0) {
            total += 14 + f.content_type.len + 2; // 'Content-Type: ' + ct + "\r\n"
        } else if (f.filename.len > 0) {
            total += 14 + 24 + 2; // 'Content-Type: application/octet-stream\r\n'
        }
        total += 2;             // blank line
        total += f.data_len;    // field data
        total += 2;             // "\r\n"
    }
    // "--boundary--\r\n"
    total += 2 + REQ_BOUNDARY_LEN + 4;
    return total;
}

// Write one multipart part to the stream.
fn void? write_multipart_part(Stream* s, FormDataField* f, char* boundary) @private
{
    char[512] hdr;
    
    OBuf buf = { &hdr[0], 512, 0 };

    buf.put("--");
    for (usz i = 0; i < REQ_BOUNDARY_LEN; i++) hdr[buf.cursor++] = boundary[i];
    buf.put("\r\n");
    buf.put("Content-Disposition: form-data; name=\"");
    buf.put(f.name);
    buf.put("\"");
    if (f.filename.len > 0) {
        buf.put("; filename=\"");
        buf.put(f.filename);
        buf.put("\"");
    }
    buf.put("\r\n");
    if (f.content_type.len > 0) {
        buf.put("Content-Type: ");
        buf.put(f.content_type);
        buf.put("\r\n");
    } else if (f.filename.len > 0) {
        buf.put("Content-Type: application/octet-stream\r\n");
    }
    buf.put("\r\n");

    s_write(s, buf.str())!;
    if (f.data_len > 0) s_write(s, f.data[0:f.data_len])!;
    s_write(s, "\r\n")!;
}

fn void? write_multipart_final(Stream* s, char* boundary) @private
{
    char[REQ_BOUNDARY_LEN + 6] tail;
    tail[0] = '-'; tail[1] = '-';
    for (usz i = 0; i < REQ_BOUNDARY_LEN; i++) tail[2 + i] = boundary[i];
    tail[REQ_BOUNDARY_LEN + 2] = '-';
    tail[REQ_BOUNDARY_LEN + 3] = '-';
    tail[REQ_BOUNDARY_LEN + 4] = '\r';
    tail[REQ_BOUNDARY_LEN + 5] = '\n';
    s_write(s, tail[0:REQ_BOUNDARY_LEN + 6])!;
}

//  public API 

// Write a complete HTTP/1.1 request to the stream.
//
// Parameters mirror ClientSession.request():
//   stream          : open TCP stream to the server
//   method          : HTTP verb
//   url             : parsed URL (used for path, query, host)
//   params          : extra query parameters appended to url.query
//   default_headers : session-level headers (lower priority)
//   req_headers     : per-request headers (override defaults)
//   auth            : Basic auth (adds Authorization header)
//   data / data_len : raw body bytes
//   json_str        : JSON body (sets Content-Type: application/json)
//   form            : FormData (sets Content-Type: multipart/form-data)
//   timeout         : not used here — caller wraps in asyncio timeout
//
fn void? req_write(
    Stream*        stream,
    HttpMethod     method,
    Url*           url,
    Headers*       params,
    Headers*       default_headers,
    Headers*       req_headers,
    BasicAuth*     auth,
    char*          data,
    usz            data_len,
    String         json_str,
    FormData*      form,
    Allocator      alloc,
)
{
    localmem = alloc;
    
    ReqCtx ctx;
    ctx.scratch_len = 0;

    OBuf buf = { &ctx.scratch[0], REQ_SCRATCH_SIZE, 0 };

    //  determine body kind and calculate Content-Length 
    bool has_json = json_str.len > 0;
    bool has_form = form != null && form.count > 0;
    bool has_data = !has_json && !has_form && data != null && data_len > 0;

    usz body_len = 0;
    if (has_json) {
        body_len = json_str.len;
    } else if (has_form) {
        body_len = multipart_body_len(form, &ctx.boundary[0]);
    } else if (has_data) {
        body_len = data_len;
    }

    // generate boundary now (needed for Content-Type and body_len)
    if (has_form) make_boundary(&ctx.boundary[0]);

    //  merge headers 
    MergedHeaders merged;
    merged_init(&merged);
    merged_add_headers(&merged, default_headers);
    merged_add_headers(&merged, req_headers);

    //  build request line 
    buf.put(method_str(method));
    buf.putc(' ');

    // path
    if (url.path.len > 0) {
        buf.put(url.path);
    } else {
        buf.putc('/');
    }

    // query string: original url.query + extra params
    bool has_q = url.query.len > 0 || (params != null && params.count > 0);
    if (has_q) {
        buf.putc('?');
        if (url.query.len > 0) {
            buf.put(url.query);
            if (params != null && params.count > 0) buf.putc('&');
        }
        if (params != null && params.count > 0) {
            // inline encode params directly into scratch (avoid alloc)
            for (usz pi = 0; pi < params.count; pi++) {
                if (pi > 0) buf.putc('&');
                Header* h = &params.entries[pi];
                // percent-encode key
                foreach (c : h.name) {
                    if (pct_unreserved(c)) {
                        buf.putc(c);
                    } else {
                        buf.putc('%');
                        buf.putc(PCT_HEX[(c >> 4) & 0xF]);
                        buf.putc(PCT_HEX[c & 0xF]);
                    }
                }
                buf.putc('=');
                foreach (c : h.value) {
                    if (pct_unreserved(c)) {
                        buf.putc(c);
                    } else {
                        buf.putc('%');
                        buf.putc(PCT_HEX[(c >> 4) & 0xF]);
                        buf.putc(PCT_HEX[c & 0xF]);
                    }
                }
            }
        }
    }

    buf.put(" HTTP/1.1\r\n");

    //  Host header 
    if (!merged_has(&merged, "host")) {
        buf.put("Host: ");
        buf.put(url.host);
        // emit non-default port
        if (url.port != 0 && url.port != scheme_default_port(url.scheme)) {
            buf.putc(':');
            char[6] pbuf;
            usz plen = fmt_decimal(&pbuf[0], (usz)url.port);
            for (usz i = 0; i < plen; i++) buf.putc(pbuf[i]);
        }
        buf.put("\r\n");
    }

    //  Connection header 
    if (!merged_has(&merged, "connection")) {
        buf.put("Connection: keep-alive\r\n");
    }

    //  Authorization (Basic Auth) 
    if (auth != null && !merged_has(&merged, "authorization")) {
        // "username:password" → base64
        usz cred_len = auth.username.len + 1 + auth.password.len;
        char* cred = localmem.malloc(cred_len);
        usz ci = 0;
        for (usz i = 0; i < auth.username.len; i++) cred[ci++] = auth.username[i];
        cred[ci++] = ':';
        for (usz i = 0; i < auth.password.len; i++) cred[ci++] = auth.password[i];
        String encoded = base64::encode(alloc, cred[0:cred_len]);
        buf.put("Authorization: Basic ");
        buf.put(encoded);
        buf.put("\r\n");
    }

    //  Content-Type 
    if (body_len > 0 && !merged_has(&merged, "content-type")) {
        if (has_json) {
            buf.put("Content-Type: application/json\r\n");
        } else if (has_form) {
            buf.put("Content-Type: multipart/form-data; boundary=");
            for (usz i = 0; i < REQ_BOUNDARY_LEN; i++) buf.putc(ctx.boundary[i]);
            buf.put("\r\n");
        } else {
            buf.put("Content-Type: application/octet-stream\r\n");
        }
    }

    //  Content-Length 
    if (body_len > 0 && !merged_has(&merged, "content-length")) {
        buf.put("Content-Length: ");
        char[20] lbuf;
        usz llen = fmt_decimal(&lbuf[0], body_len);
        for (usz i = 0; i < llen; i++) buf.putc(lbuf[i]);
        buf.put("\r\n");
    }

    //  merged custom headers 
    for (usz i = 0; i < merged.count; i++) {
        buf.put(merged.entries[i].name);
        buf.put(": ");
        buf.put(merged.entries[i].value);
        buf.put("\r\n");
    }

    //  blank line 
    buf.put("\r\n");

    //  flush header block 
    s_write(stream, buf.str())!;

    //  body 
    if (has_json) {
        s_write(stream, json_str[0:json_str.len])!;
    } else if (has_form) {
        for (usz i = 0; i < form.count; i++) {
            write_multipart_part(stream, &form.fields[i], &ctx.boundary[0])!;
        }
        write_multipart_final(stream, &ctx.boundary[0])!;
    } else if (has_data) {
        s_write(stream, data[0: data_len])!;
    }
}

// Convenience: build and write a URL-encoded form body.
// Sets Content-Type: application/x-www-form-urlencoded.
// fields is a Headers* treated as key=value pairs.
fn void? req_write_urlencoded(
    Stream*    stream,
    HttpMethod method,
    Url*       url,
    Headers*   fields,
    Headers*   default_headers,
    Headers*   req_headers,
    BasicAuth* auth,
    Allocator  alloc,
)
{
    localmem = alloc;
    
    // build body first to know its length
    char[REQ_SCRATCH_SIZE] body_buf;
    usz body_len = 0;
    if (fields != null) {
        for (usz i = 0; i < fields.count; i++) {
            if (i > 0) body_buf[body_len++] = '&';
            Header* h = &fields.entries[i];
            foreach (c : h.name) {
                if (pct_unreserved(c)) {
                    body_buf[body_len++] = c;
                } else {
                    body_buf[body_len++] = '%';
                    body_buf[body_len++] = PCT_HEX[(c >> 4) & 0xF];
                    body_buf[body_len++] = PCT_HEX[c & 0xF];
                }
            }
            body_buf[body_len++] = '=';
            foreach (c : h.value) {
                if (pct_unreserved(c)) {
                    body_buf[body_len++] = c;
                } else {
                    body_buf[body_len++] = '%';
                    body_buf[body_len++] = PCT_HEX[(c >> 4) & 0xF];
                    body_buf[body_len++] = PCT_HEX[c & 0xF];
                }
            }
        }
    }

    // add Content-Type to req_headers merge
    // (inject via a small synthetic Headers on stack)
    Header ct_hdr = { "Content-Type", "application/x-www-form-urlencoded" };
    Headers ct_wrap = { &ct_hdr, 1, 1 };

    // merge ct_wrap + req_headers by calling req_write with data pointer
    req_write(
        stream, method, url,
        null,           // no extra query params
        default_headers,
        &ct_wrap,       // content-type first so req_headers can override
        auth,
        &body_buf[0],  // data
        body_len,
        "",             // no json
        null,           // no multipart
        alloc,
    )!;
}
