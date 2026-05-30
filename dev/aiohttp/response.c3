// response.c3

module ext::aiohttp;

import std::io;
import std::collections::list;
import ext::mem;
import ext::debug;


// 
// Response
// 

struct Response
{
    ushort status;
    Headers headers;
    char[] body;
    bool owns_body;
}

// 
// Status helpers
// 

fn String status_text(ushort status)
{
    switch (status)
    {
        case 100: return "Continue";
        case 101: return "Switching Protocols";

        case 200: return "OK";
        case 201: return "Created";
        case 202: return "Accepted";
        case 203: return "Non-Authoritative Information";
        case 204: return "No Content";
        case 205: return "Reset Content";
        case 206: return "Partial Content";

        case 300: return "Multiple Choices";
        case 301: return "Moved Permanently";
        case 302: return "Moved Temporarily";
        case 303: return "See Other";
        case 304: return "Not Modified";
        case 307: return "Temporary Redirect";
        case 308: return "Permanent Redirect";

        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 408: return "Request Timeout";
        case 409: return "Conflict";
        case 410: return "Gone";
        case 413: return "Payload Too Large";
        case 414: return "URI Too Long";
        case 415: return "Unsupported Media Type";
        case 418: return "I'm a teapot";
        case 422: return "Unprocessable Entity";
        case 429: return "Too Many Requests";

        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 502: return "Bad Gateway";
        case 503: return "Service Unavailable";
        case 504: return "Gateway Timeout";

        default: return "Unknown";
    }
}

fn bool status_allows_body(ushort status)
{
    // RFC behavior:
    // 1xx, 204, 304 must not include a body.
    if (status >= 100 && status < 200) return false;
    if (status == 204) return false;
    if (status == 304) return false;
    return true;
}

// 
// Internal helpers
// 

fn char[] bytes_clone(char[] data)
{
    if (data.len == 0) return {};

    char* p = localmem.malloc(data.len);
    p[0:data.len] = data[0:data.len];

    return p[0:data.len];
}

fn void body_free(char[] body)
{
    if (body.ptr != null && body.len > 0)
    {
        localmem.free(body);
    }
}

// 
// Lifecycle
// 

fn void Response.init(&self)
{
    self.status = 200;
    self.headers.init();
    self.body = {};
    self.owns_body = false;
}

fn void Response.free(&self)
{
    self.headers.free();

    if (self.owns_body) body_free(self.body);

    self.status = 0;
    self.body = {};
    self.owns_body = false;
}

fn Response* response_new()
{
    Response* res = localmem.alloc(Response);
    res.init();
    return res;
}

fn void response_free(Response* res)
{
    if (res == null) return;

    res.free();
    localmem.free(res);
}

// 
// Basic mutators
// 

fn void Response.set_status(&self, ushort status)
{
    self.status = status;
}

fn void Response.header(&self, String name, String value)
{
    self.headers.set(name, value);
}

fn void Response.add_header(&self, String name, String value)
{
    self.headers.add(name, value);
}

fn void Response.content_type(&self, String value)
{
    self.headers.content_type(value);
}

fn void Response.content_length(&self, sz value)
{
    self.headers.content_length(value);
}

fn void Response.set_cookie(&self, String value)
{
    self.headers.set_cookie(value);
}

fn void Response.set_body_copy(&self, char[] body)
{
    if (self.owns_body) body_free(self.body);

    self.body = bytes_clone(body);
    self.owns_body = true;
}

fn void Response.set_body_borrowed(&self, char[] body)
{
    if (self.owns_body) body_free(self.body);

    self.body = body;
    self.owns_body = false;
}

fn void Response.set_text(&self, String text)
{
    self.content_type("text/plain; charset=utf-8");
    self.set_body_copy((char[])text);
}

fn void Response.set_html(&self, String html)
{
    self.content_type("text/html; charset=utf-8");
    self.set_body_copy((char[])html);
}

fn void Response.set_json(&self, String json)
{
    self.content_type("application/json; charset=utf-8");
    self.set_body_copy((char[])json);
}

// 
// Constructors
// 

fn Response* response_empty(ushort status)
{
    Response* res = response_new();
    res.status = status;
    return res;
}

fn Response* response_body(char[] body)
{
    Response* res = response_new();
    res.set_body_copy(body);
    return res;
}

fn Response* response_text(String text)
{
    Response* res = response_new();
    res.set_text(text);
    return res;
}

fn Response* response_html(String html)
{
    Response* res = response_new();
    res.set_html(html);
    return res;
}

fn Response* response_json(String json)
{
    Response* res = response_new();
    res.set_json(json);
    return res;
}

fn Response* response_redirect(String location, ushort status = 302)
{
    Response* res = response_new();

    res.status = status;
    res.headers.set("Location", location);

    return res;
}

fn Response* response_not_found()
{
    Response* res = response_new();

    res.status = 404;
    res.set_text("404 Not Found");

    return res;
}

fn Response* response_internal_error()
{
    Response* res = response_new();

    res.status = 500;
    res.set_text("500 Internal Server Error");

    return res;
}

// 
// Serialization length
// 

fn sz Response.status_line_len(&self)
{
    String reason = status_text(self.status);

    // HTTP/1.1 + space + 3 digits + space + reason + CRLF
    return 8 + 1 + 3 + 1 + reason.len + 2;
}

fn sz Response.body_len_for_wire(&self)
{
    if (!status_allows_body(self.status)) return 0;
    return self.body.len;
}

// Header block length, including auto Content-Length if needed.
fn sz Response.headers_len_for_wire(&self)
{
    sz n = self.headers.serialized_len();

    if (!self.headers.has("Content-Length"))
    {
        String len_str = string::tformat("%d", self.body_len_for_wire());
        n += "Content-Length".len + 2 + len_str.len + 2;
    }

    if (!self.headers.has("Connection"))
    {
        n += "Connection".len + 2 + "close".len + 2;
    }

    return n;
}

fn sz Response.serialized_len(&self)
{
    return self.status_line_len()
        + self.headers_len_for_wire()
        + 2
        + self.body_len_for_wire();
}

// 
// Serialization
// 

fn sz write_string(char[] out, sz pos, String s)
{
    out[pos:s.len] = s[0:s.len];
    return pos + s.len;
}

fn sz write_char(char[] out, sz pos, char c)
{
    out[pos] = c;
    return pos + 1;
}

fn sz write_crlf(char[] out, sz pos)
{
    out[pos++] = '\r';
    out[pos++] = '\n';
    return pos;
}

fn sz write_status_code(char[] out, sz pos, ushort status)
{
    out[pos++] = (char)('0' + ((status / 100) % 10));
    out[pos++] = (char)('0' + ((status / 10) % 10));
    out[pos++] = (char)('0' + (status % 10));

    return pos;
}

// Appends full HTTP response into caller-owned buffer.
//
// Returns bytes written.
// Returns 0 if buffer is too small.
fn sz Response.write_to(&self, char[] out)
{
    sz need = self.serialized_len();
    if (out.len < need) return 0;

    sz pos = 0;
    String reason = status_text(self.status);

    // Status line:
    // HTTP/1.1 200 OK\r\n
    pos = write_string(out, pos, "HTTP/1.1");
    pos = write_char(out, pos, ' ');
    pos = write_status_code(out, pos, self.status);
    pos = write_char(out, pos, ' ');
    pos = write_string(out, pos, reason);
    pos = write_crlf(out, pos);

    // Existing headers.
    sz hlen = self.headers.write_to(out[pos:out.len - pos]);
    if (hlen == 0 && self.headers.len() > 0) return 0;
    pos += hlen;

    // Auto Content-Length.
    if (!self.headers.has("Content-Length"))
    {
        String len_str = string::tformat("%d", self.body_len_for_wire());

        pos = write_string(out, pos, "Content-Length");
        pos = write_string(out, pos, ": ");
        pos = write_string(out, pos, len_str);
        pos = write_crlf(out, pos);
    }

    // Default Connection: close.
    // Later keep-alive support can override this at server layer.
    if (!self.headers.has("Connection"))
    {
        pos = write_string(out, pos, "Connection");
        pos = write_string(out, pos, ": ");
        pos = write_string(out, pos, "close");
        pos = write_crlf(out, pos);
    }

    // Empty line.
    pos = write_crlf(out, pos);

    // Body.
    sz body_len = self.body_len_for_wire();
    if (body_len > 0)
    {
        out[pos:body_len] = self.body[0:body_len];
        pos += body_len;
    }

    return pos;
}

fn String? Response.serialize(&self)
{
    sz n = self.serialized_len();

    if (n == 0) return "";

    char* p = localmem.malloc(n + 1)!;
    char[] out = p[0:n];

    sz written = self.write_to(out);
    p[written] = 0;

    return (String)p[0:written];
}

// 
// Debug
// 

fn void Response.dump(&self)
{
    io::printfn("HTTP/1.1 %d %s", self.status, status_text(self.status));
    self.headers.dump();
    io::printfn("Content-Length: %d", self.body_len_for_wire());
    io::printfn("");
    io::printfn("%s", (String)self.body);
}

// eof