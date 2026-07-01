// request.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;
import ext::encoding::simdjson;

// Faults

faultdef BAD_REQUEST;
faultdef REQUEST_TOO_LARGE;
faultdef INVALID_METHOD;
faultdef INVALID_VERSION;
faultdef INVALID_HEADER;
faultdef BODY_INCOMPLETE;


// Limits

const sz MAX_REQUEST_LINE_LEN = 8192;
const sz MAX_HEADER_BYTES = 64 * 1024;
const sz MAX_BODY_BYTES = 16 * 1024 * 1024;


// Request

struct Request
{
    String method;
    String target;
    String path;
    String query_string;
    String version;
    
    String remote_ip;
    
    Headers headers;

    char[] body;
    bool owns_body;
}


// Internal string helpers


fn bool method_valid(String method) @local
{
    if (method.len == 0) return false;

    for (sz i = 0; i < method.len; i++)
    {
        if (!is_token_char(method[i])) return false;
    }

    return true;
}

fn bool version_valid(String version) @local
{
    if (version == "HTTP/1.0") return true;
    if (version == "HTTP/1.1") return true;
    return false;
}



// Lifecycle

fn void Request.init(&self)
{
    self.method = "";
    self.target = "";
    self.path = "";
    self.query_string = "";
    self.version = "";
    self.remote_ip = "";

    self.headers.init();

    self.body = {};
    self.owns_body = false;
}

fn void Request.free(&self)
{
    str_free(self.method);
    str_free(self.target);
    str_free(self.path);
    str_free(self.query_string);
    str_free(self.version);
    str_free(self.remote_ip);

    self.headers.free();

    if (self.owns_body) bytes_free(self.body);

    self.method = "";
    self.target = "";
    self.path = "";
    self.query_string = "";
    self.version = "";
    self.remote_ip = "";

    self.body = {};
    self.owns_body = false;
}

fn Request*? request_new()
{
    Request* req = localmem.alloc(Request)!;
    req.init();
    return req;
}

fn void request_free(Request* req)
{
    if (req == null) return;

    req.free();
    localmem.free(req);
}


// Accessors

fn String? Request.header(&self, String name)
{
    return self.headers.get(name)!;
}

fn bool Request.has_body(&self) @inline
{
    return self.body.len > 0;
}

fn String Request.body_text(&self) @inline
{
    return (String)self.body;
}

fn simdjson::ParseResult? Request.parse_json(&self, Allocator alloc, bool allow_comma = true, bool allow_comment = true)
{
    return simdjson::parse(alloc, self.body, allow_comma, allow_comment)!;
}

fn sz? Request.content_length(&self)
{
    sz found = 0;
    sz value = 0;

    for (sz i = 0; i < self.headers.items.len(); i++)
    {
        Header* h = &self.headers.items[i];

        if (!str_iequals(h.name, "Content-Length")) continue;

        sz n = parse_sz(h.value.trim())!;

        if (found > 0 && n != value)
        {
            return BAD_REQUEST~;
        }

        value = n;
        found++;
    }

    return value;
}

fn bool Request.is_http_11(&self) @inline
{
    return self.version == "HTTP/1.1";
}

fn bool Request.is_http_10(&self) @inline
{
    return self.version == "HTTP/1.0";
}


// Request target split

fn void Request.set_target_parts(&self, String target)
{
    str_free(self.target);
    str_free(self.path);
    str_free(self.query_string);

    self.target = str_clone(target);

    sz q = find_char(target, '?');

    if (q < 0)
    {
        self.path = str_clone(target);
        self.query_string = "";
        return;
    }

    sz qi = (sz)q;

    self.path = str_clone(target[0:qi]);
    self.query_string = str_clone(target[qi + 1:target.len - qi - 1]);
}


// Request line parser

fn void? Request.parse_request_line(&self, String line)
{
    if (line.len == 0 || line.len > MAX_REQUEST_LINE_LEN) return BAD_REQUEST~;

    sz sp1 = -1;
    sz sp2 = -1;

    for (sz i = 0; i < line.len; i++)
    {
        if (line[i] == ' ')
        {
            if (sp1 < 0)
            {
                sp1 = (sz)i;
            }
            else
            {
                sp2 = (sz)i;
                break;
            }
        }
    }

    if (sp1 <= 0 || sp2 <= sp1 + 1) return BAD_REQUEST~;

    sz a = (sz)sp1;
    sz b = (sz)sp2;

    String method = line[0:a];
    String target = line[a + 1:b - a - 1];
    String version = line[b + 1:line.len - b - 1];

    // warn("(%s)", method);
    if (!method_valid(method)) return INVALID_METHOD~;

    if (target.len == 0) return BAD_REQUEST~;

    if (!version_valid(version)) return INVALID_VERSION~;

    str_free(self.method);
    str_free(self.version);

    self.method = str_clone(method);
    self.set_target_parts(target);
    self.version = str_clone(version);
}


// Header parser

fn void? Request.parse_header_line(&self, String line) @maydiscard
{
    if (line.len == 0) return;

    sz colon = find_char(line, ':');
    if (colon <= 0) return INVALID_HEADER~;

    sz c = (sz)colon;

    String name = line[0:c];
    String value = line[c + 1:line.len - c - 1].trim();

    // Headers.add() already validates header name.
    // But invalid names should be parse errors, not silently ignored.
    if (!is_valid_name(name)) return INVALID_HEADER~;

    self.headers.add(name, value)!;
}

fn void? Request.parse_headers_block(&self, char[] block) @maydiscard
{
    sz pos = 0;

    sz[2]? p = find_line_end(block, pos);
    if (catch err = p) return BAD_REQUEST~;

    sz line_end = p[0];
    
    String request_line = (String)block[0:(sz)line_end];
    self.parse_request_line(request_line)!;

    pos = (sz)line_end + p[1];

    while (pos < block.len)
    {
        sz[2]? pp = find_line_end(block, pos);
        if (catch err = pp) return BAD_REQUEST~;

        sz end = pp[0];

        if (end == pos) break;

        String line = (String)block[pos:end - pos];
        self.parse_header_line(line)!;

        pos = end + pp[1];
    }
}

fn bool Request.has_transfer_encoding(&self)
{
    if (catch self.header("Transfer-Encoding"))
    {
        return false;
    }

    return true;
}

// Body

fn void? Request.set_body_copy(&self, char[] body)
{
    if (body.len > MAX_BODY_BYTES)
    {
        return REQUEST_TOO_LARGE~;
    }

    if (self.owns_body)
    {
        bytes_free(self.body);
    }

    if (body.len == 0)
    {
        self.body = {};
        self.owns_body = false;
        return;
    }

    self.body = bytes_clone(body)!;
    self.owns_body = true;
}

fn void? Request.set_body_borrowed(&self, char[] body)
{
    if (body.len > MAX_BODY_BYTES)
    {
        return REQUEST_TOO_LARGE~;
    }

    if (self.owns_body)
    {
        bytes_free(self.body);
    }

    self.body = body;
    self.owns_body = false;
}


// Public parser

fn Request*? request_parse(char[] raw)
{
    sz[2]? p = find_header_end(raw);
    if (catch err = p) return BAD_REQUEST~;

    sz header_end = p[0];
    sz body_start = p[0]+p[1];
    sz gap = p[1];
    
    if (header_end > MAX_HEADER_BYTES)
    {
        return REQUEST_TOO_LARGE~;
    }

    Request* req = request_new()!;
    defer catch request_free(req);

    char[] header_block = raw[0:header_end + gap/2];
    req.parse_headers_block(header_block)!;

    sz available_body = raw.len - body_start;

    char[] raw_body = raw[body_start:raw.len - body_start];
    
    if (req.has_transfer_encoding())
    {
        if (!req.is_chunked())
        {
            return BAD_REQUEST~;
        }
    
        if (req.headers.has("Content-Length"))
        {
            return BAD_REQUEST~;
        }
    
        ChunkedDecodeResult decoded = chunked_decode(raw_body)!;
        defer bytes_free(decoded.body);
    
        if (decoded.body.len > 0)
        {
            req.set_body_copy(decoded.body)!;
        }
        else
        {
            req.body = {};
            req.owns_body = false;
        }
    
        return req;
    }
    
    sz content_len = req.content_length()!;
    
    if (content_len > MAX_BODY_BYTES)
    {
        return REQUEST_TOO_LARGE~;
    }
    
    if (available_body < content_len)
    {
        return BODY_INCOMPLETE~;
    }
    
    if (content_len > 0)
    {
        req.set_body_copy(raw[body_start:content_len])!;
    }
    
    return req;
}


// Incremental parser helpers

fn bool request_headers_complete(char[] raw)
{
    if (try find_header_end(raw)) return true;
    return false;
}

fn sz? request_expected_total_len(char[] raw)
{
    sz[2]? p = find_header_end(raw);
    if (catch err = p)
    {
        return BODY_INCOMPLETE~;
    }

    sz header_end = p[0];
    sz body_start = p[0] + p[1];
    sz gap = p[1];

    if (header_end > MAX_HEADER_BYTES)
    {
        return REQUEST_TOO_LARGE~;
    }

    Request* tmp = request_new()!;
    defer request_free(tmp);

    char[] header_block = raw[0:header_end + gap / 2];
    tmp.parse_headers_block(header_block)!;

    if (tmp.is_chunked())
    {
        if (tmp.headers.has("Content-Length"))
        {
            return BAD_REQUEST~;
        }

        ChunkedDecodeResult decoded = chunked_decode(raw[body_start:raw.len - body_start])!;
        defer localmem.free(decoded.body);

        return body_start + decoded.consumed;
    }

    sz content_len = tmp.content_length()!;

    if (content_len > MAX_BODY_BYTES)
    {
        return REQUEST_TOO_LARGE~;
    }

    return body_start + content_len;
}

fn bool request_message_complete(char[] raw)
{
    sz? n = request_expected_total_len(raw);
    if (catch err = n) return false;

    return raw.len >= n;
}


// Debug

fn void Request.dump(&self)
{
    io::printfn("%s %s %s", self.method, self.target, self.version);
    self.headers.dump();

    io::printfn("");
    if (self.body.len > 0)
    {
        io::printfn("%s", (String)self.body);
    }
}

// eof