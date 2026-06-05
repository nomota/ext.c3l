// request.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import std::io;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef BAD_REQUEST;
faultdef REQUEST_TOO_LARGE;
faultdef INVALID_METHOD;
faultdef INVALID_VERSION;
faultdef INVALID_HEADER;
faultdef BODY_INCOMPLETE;


// 
// Limits
// 

const sz MAX_REQUEST_LINE_LEN = 8192;
const sz MAX_HEADER_BYTES = 64 * 1024;
const sz MAX_BODY_BYTES = 16 * 1024 * 1024;


// 
// Request
// 

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


// 
// Internal string helpers
// 

fn void bytes_free(char[] data)
{
    if (data.ptr != null && data.len > 0)
    {
        localmem.free(data);
    }
}

fn bool is_space(char c) @inline
{
    return c == ' ' || c == '\t';
}

fn bool is_digit(char c) @inline
{
    return c >= '0' && c <= '9';
}

fn bool is_token_char(char c)
{
    if (c <= 32 || c == 127) return false;

    switch (c)
    {
        case '(':
        case ')':
        case '<':
        case '>':
        case '@':
        case ',':
        case ';':
        case ':':
        case '\\':
        case '"':
        case '/':
        case '[':
        case ']':
        case '?':
        case '=':
        case '{':
        case '}':
            return false;
        default:
            return true;
    }
}

fn String trim_spaces(String s)
{
    sz start = 0;
    sz end = s.len;

    while (start < end && is_space(s[start]))
    {
        start++;
    }

    while (end > start && is_space(s[end - 1]))
    {
        end--;
    }

    return s[start:end - start];
}

fn bool method_valid(String method)
{
    if (method.len == 0) return false;

    for (sz i = 0; i < method.len; i++)
    {
        if (!is_token_char(method[i])) return false;
    }

    return true;
}

fn bool version_valid(String version)
{
    if (version == "HTTP/1.0") return true;
    if (version == "HTTP/1.1") return true;
    return false;
}

fn sz find_char(char[] data, char needle)
{
    for (sz i = 0; i < data.len; i++)
    {
        if (data[i] == needle) return (sz)i;
    }

    return -1;
}

fn sz[2]? find_line_end(char[] data, sz start)
{
    sz i = start;

    while (i < data.len)
    {
        if (i + 1 < data.len && data[i] == '\r' && data[i + 1] == '\n')
        {
            return { i, 2 };
        }

        if (data[i] == '\n')
        {
            return { i, 1 };
        }

        i++;
    }

    return NOT_FOUND~;
}

fn sz[2]? find_header_end(char[] data)
{
    if (data.len < 2) return NOT_FOUND~;

    for (sz i = 0; i < data.len; i++)
    {
        if (i+3 < data.len && 
            data[i] == '\r'
            && data[i + 1] == '\n'
            && data[i + 2] == '\r'
            && data[i + 3] == '\n')
        {
            return {i,4};
        }
        if (i+1 < data.len && 
            data[i] == '\n'
            && data[i + 1] == '\n')
        {
            return {i,2};
        }
    }

    return NOT_FOUND~;
}

fn sz? parse_sz(String s)
{
    if (s.len == 0) return BAD_REQUEST~;

    sz value = 0;

    for (sz i = 0; i < s.len; i++)
    {
        char c = s[i];
        if (!is_digit(c)) return BAD_REQUEST~;

        sz digit = (sz)(c - '0');

        // Simple overflow guard.
        if (value > ((sz::max - digit) / 10))
        {
            return REQUEST_TOO_LARGE~;
        }

        value = value * 10 + digit;
    }

    return value;
}


// 
// Lifecycle
// 

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


// 
// Accessors
// 

fn String? Request.header(&self, String name)
{
    return self.headers.get(name)!;
}

fn bool Request.has_body(&self) @inline
{
    return self.body.len > 0;
}

fn sz? Request.content_length(&self)
{
    String? v = self.headers.get("Content-Length");
    if (catch err = v) return 0;

    String s = trim_spaces(v);
    return parse_sz(s)!;
}

fn bool Request.is_http_11(&self) @inline
{
    return self.version == "HTTP/1.1";
}

fn bool Request.is_http_10(&self) @inline
{
    return self.version == "HTTP/1.0";
}


// 
// Request target split
// 

fn void Request.set_target_parts(&self, String target)
{
    str_free(self.target);
    str_free(self.path);
    str_free(self.query_string);

    self.target = str_clone(target);

    sz q = find_char((char[])target, '?');

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


// 
// Request line parser
// 

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


// 
// Header parser
// 

fn void? Request.parse_header_line(&self, String line) @maydiscard
{
    if (line.len == 0) return;

    sz colon = find_char((char[])line, ':');
    if (colon <= 0) return INVALID_HEADER~;

    sz c = (sz)colon;

    String name = line[0:c];
    String value = trim_spaces(line[c + 1:line.len - c - 1]);

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


// 
// Body
// 

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


// 
// Public parser
// 

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
    
    if (req.is_chunked())
    {
        ChunkedDecodeResult decoded = chunked_decode(raw_body)!;
        defer body_free(decoded.body);
    
        req.set_body_copy(decoded.body)!;
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


// 
// Incremental parser helpers
// 

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

    char[] raw_body = raw[body_start:raw.len - body_start];

    if (tmp.is_chunked())
    {
        sz chunked_len = chunked_expected_len(raw_body)!;
        return body_start + chunked_len;
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


// 
// Debug
// 

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