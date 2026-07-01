// response.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;
import ext::aio;

alias StreamWriter = fn void?(aio::Stream*, void*);

enum BodyKind
{
    BODY_EMPTY,
    BODY_BYTES,
    BODY_STREAM,
    BODY_FILE,
}


// Response

struct Response
{
    ushort status;
    Headers headers;

    BodyKind body_kind;
    char[] body;

    StreamWriter stream_writer;
    void* stream_arg;

    String file_path;
    sz file_offset;
    sz file_size;

    bool owns_body;
    bool owns_file_path;
}


// Status helpers

fn String status_text(ushort status)
{
    switch (status) {
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
        case 416: return "Range Not Satisfiable";
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
    if (status >= 100 && status < 200) return false;
    if (status == 204) return false;
    if (status == 304) return false;
    return true;
}

// Lifecycle

fn void Response.init(&self)
{
    self.status = 200;
    self.headers.init();

    self.body_kind = BODY_EMPTY;
    self.body = {};
    self.owns_body = false;

    self.stream_writer = null;
    self.stream_arg = null;

    self.file_path = "";
    self.file_offset = 0;
    self.file_size = 0;
    self.owns_file_path = false;
}

fn void Response.free(&self)
{
    self.headers.free();

    if (self.owns_body) bytes_free(self.body);

    if (self.owns_file_path && self.file_path.len > 0) {
        localmem.free(self.file_path);
    }

    self.status = 0;

    self.body_kind = BODY_EMPTY;
    self.body = {};
    self.owns_body = false;

    self.stream_writer = null;
    self.stream_arg = null;

    self.file_path = "";
    self.file_offset = 0;
    self.file_size = 0;
    self.owns_file_path = false;
}

fn Response*? response_new()
{
    Response* res = localmem.alloc(Response)!;
    res.init();
    return res;
}

fn void response_free(Response* res)
{
    if (res == null) return;

    res.free();
    localmem.free(res);
}


// Basic mutators

faultdef INVALID_STATUS;
faultdef INVALID_FILE_RANGE;

fn void? Response.set_status(&self, ushort status) @maydiscard
{
    if (status < 100 || status > 599) return INVALID_STATUS~;

    self.status = status;

    if (!status_allows_body(status)) {
        self.headers.remove("Transfer-Encoding");
        self.headers.remove("Content-Length");
    }
}

fn void? Response.header(&self, String name, String value) @maydiscard
{
    self.headers.set(name, value)!;
}

fn void? Response.add_header(&self, String name, String value) @maydiscard
{
    self.headers.add(name, value)!;
}

fn void? Response.content_type(&self, String value) @maydiscard
{
    self.headers.content_type(value)!;
}

fn void? Response.content_length(&self, sz value) @maydiscard
{
    self.headers.content_length(value)!;
}

fn void? Response.set_cookie(&self, String value) @maydiscard
{
    self.headers.set_cookie(value)!;
}

fn void Response.clear_file_state(&self)
{
    if (self.owns_file_path && self.file_path.len > 0) {
        localmem.free(self.file_path);
    }

    self.file_path = "";
    self.file_offset = 0;
    self.file_size = 0;
    self.owns_file_path = false;
}

fn void Response.clear_stream_state(&self)
{
    self.stream_writer = null;
    self.stream_arg = null;
}

fn void Response.clear_body_state(&self)
{
    if (self.owns_body) bytes_free(self.body);

    self.body = {};
    self.owns_body = false;
}

fn void? Response.set_body_copy(&self, char[] body) @maydiscard
{
    self.clear_stream_state();
    self.clear_file_state();
    self.clear_body_state();

    self.headers.remove("Transfer-Encoding");
    self.headers.remove("Content-Length");

    self.body_kind = body.len == 0 ? BODY_EMPTY : BODY_BYTES;
    self.body = bytes_clone(body)!;
    self.owns_body = body.len > 0;
}

fn void Response.set_body_borrowed(&self, char[] body)
{
    self.clear_stream_state();
    self.clear_file_state();
    self.clear_body_state();

    self.headers.remove("Transfer-Encoding");
    self.headers.remove("Content-Length");

    self.body_kind = body.len == 0 ? BODY_EMPTY : BODY_BYTES;
    self.body = body;
    self.owns_body = false;
}

fn void? Response.set_text(&self, String text) @maydiscard
{
    self.content_type("text/plain; charset=utf-8")!;
    self.set_body_copy((char[])text)!;
}

fn void? Response.set_html(&self, String html) @maydiscard
{
    self.content_type("text/html; charset=utf-8")!;
    self.set_body_copy((char[])html)!;
}

fn void? Response.set_json(&self, String json) @maydiscard
{
    self.content_type("application/json; charset=utf-8")!;
    self.set_body_copy((char[])json)!;
}


// Constructors

fn Response*? response_stream(StreamWriter writer, void* arg)
{
    if (writer == null) return BAD_REQUEST~;

    Response* res = response_empty(200)!;
    defer catch response_free(res);

    res.body_kind = BODY_STREAM;
    res.stream_writer = writer;
    res.stream_arg = arg;

    res.headers.remove("Content-Length");
    res.headers.set("Transfer-Encoding", "chunked")!;

    return res;
}

fn Response*? response_file_range(String path, sz offset, sz length)
{
    if (path.len == 0) return BAD_REQUEST~;
    if (offset < 0 || length < 0) return INVALID_FILE_RANGE~;

    Response* res = response_empty(200)!;
    defer catch response_free(res);

    res.body_kind = BODY_FILE;
    res.file_path = path.copy(localmem);
    res.file_offset = offset;
    res.file_size = length;
    res.owns_file_path = true;

    res.headers.remove("Transfer-Encoding");
    res.headers.content_length(length)!;
    res.headers.set("Content-Type", content_type_from_path(path))!;

    return res;
}

fn Response*? response_file(String path, sz file_size = 0)
{
    return response_file_range(path, 0, file_size)!;
}

fn Response*? response_empty(ushort status)
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_status(status)!;
    return res;
}

fn Response*? response_body(char[] body)
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_body_copy(body)!;
    return res;
}

fn Response*? response_text(String text)
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_text(text)!;
    return res;
}

fn Response*? response_html(String html)
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_html(html)!;
    return res;
}

fn Response*? response_json(String json)
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_json(json)!;
    return res;
}

fn Response*? response_redirect(String location, ushort status = 302)
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_status(status)!;
    res.headers.set("Location", location)!;

    return res;
}

fn Response*? response_not_found()
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_status(404)!;
    res.set_text("404 Not Found")!;

    return res;
}

fn Response*? response_internal_error()
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_status(500)!;
    res.set_text("500 Internal Server Error")!;

    return res;
}


// Serialization length

fn sz Response.status_line_len(&self)
{
    String reason = status_text(self.status);
    return 8 + 1 + 3 + 1 + reason.len + 2;
}

fn bool Response.is_streaming(&self) @inline
{
    return self.body_kind == BODY_STREAM || self.body_kind == BODY_FILE;
}

fn bool Response.is_file(&self) @inline
{
    return self.body_kind == BODY_FILE;
}

fn bool Response.is_chunked(&self) @inline
{
    return self.body_kind == BODY_STREAM;
}

fn sz Response.body_len_for_wire(&self)
{
    if (!status_allows_body(self.status)) return 0;
    if (self.body_kind != BODY_BYTES) return 0;

    return self.body.len;
}

fn sz Response.content_length_for_wire(&self)
{
    if (!status_allows_body(self.status)) return 0;

    switch (self.body_kind) {
        case BODY_BYTES:
            return self.body.len;

        case BODY_FILE:
            return self.file_size > 0 ? self.file_size : 0;

        case BODY_EMPTY:
        case BODY_STREAM:
            return 0;
    }
}

fn sz Response.headers_len_for_wire(&self)
{
    sz n = self.headers.serialized_len();
    bool no_body = !status_allows_body(self.status);
    bool switching_protocols = self.status == 101;

    if (!switching_protocols &&
        (no_body || self.body_kind != BODY_STREAM) &&
        !self.headers.has("Content-Length")) {
        String len_str = string::tformat("%d", self.content_length_for_wire());
        n += "Content-Length".len + 2 + len_str.len + 2;
    }

    if (!switching_protocols &&
        !no_body &&
        self.body_kind == BODY_STREAM &&
        !self.headers.has("Transfer-Encoding")) {
        n += "Transfer-Encoding".len + 2 + "chunked".len + 2;
    }

    if (!self.headers.has("Connection")) {
        n += "Connection".len + 2 + "close".len + 2;
    }

    return n;
}

fn sz Response.serialized_len(&self)
{
    return self.status_line_len() + self.headers_len_for_wire() + 2 + self.body_len_for_wire();
}

fn sz write_status_code(char[] out, sz pos, ushort status) @local
{
    pos = write_int(out, pos, (int)status);
    return pos;
}

fn void? write_hex(aio::Stream* stream, usz value) @local
{
    char[32] buf;
    sz pos = 0;

    if (value == 0) {
        buf[pos++] = '0';
    } else {
        char[16] hex = {
            '0', '1', '2', '3', '4', '5', '6', '7',
            '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
        };

        char[32] rev;
        sz n = 0;

        while (value > 0) {
            rev[n++] = hex[value & 15];
            value >>= 4;
        }

        while (n > 0) {
            buf[pos++] = rev[--n];
        }
    }

    stream.write_all(buf[0:pos])!;
}

fn void? write_chunk(aio::Stream* stream, char[] data, ulong timeout_us = 0)
{
    if (stream == null) return BAD_REQUEST~;
    if (data.len == 0) return;
    
    if (timeout_us == 0) timeout_us = get_write_timeout_us();
    
    char[32] buf;
    String size_line = string::bformat(buf[..], "%x\r\n", data.len);
    
    stream.write_all_timeout(size_line, timeout_us)!;
    stream.write_all_timeout(data, timeout_us)!;
    stream.write_all_timeout((char[])"\r\n", timeout_us)!;
}

fn void? write_last_chunk(aio::Stream* stream, ulong timeout_us = 0)
{
    if (stream == null) return BAD_REQUEST~;

    if (timeout_us == 0) timeout_us = get_write_timeout_us();

    stream.write_all_timeout((char[])"0\r\n\r\n", timeout_us)!;
}


// Appends the HTTP response header and in-memory body into caller-owned buffer.
//
// BODY_FILE and BODY_STREAM content is written separately by the server.
fn sz Response.write_to(&self, char[] out)
{
    sz need = self.serialized_len();
    if (out.len < need) return 0;

    sz pos = 0;
    String reason = status_text(self.status);

    pos = write_string(out, pos, "HTTP/1.1");
    pos = write_char(out, pos, ' ');
    pos = write_status_code(out, pos, self.status);
    pos = write_char(out, pos, ' ');
    pos = write_string(out, pos, reason);
    pos = write_crlf(out, pos);

    sz header_len = self.headers.write_to(out[pos:out.len - pos]);
    if (header_len == 0 && self.headers.len() > 0) return 0;

    pos += header_len;

    bool no_body = !status_allows_body(self.status);
    bool switching_protocols = self.status == 101;
    
    if (!switching_protocols &&
        (no_body || self.body_kind != BODY_STREAM) &&
        !self.headers.has("Content-Length")) {
        String len_str = string::tformat("%d", self.content_length_for_wire());
    
        pos = write_string(out, pos, "Content-Length");
        pos = write_string(out, pos, ": ");
        pos = write_string(out, pos, len_str);
        pos = write_crlf(out, pos);
    }
    
    if (!switching_protocols &&
        !no_body &&
        self.body_kind == BODY_STREAM &&
        !self.headers.has("Transfer-Encoding")) {
        pos = write_string(out, pos, "Transfer-Encoding");
        pos = write_string(out, pos, ": ");
        pos = write_string(out, pos, "chunked");
        pos = write_crlf(out, pos);
    }
    
    if (!self.headers.has("Connection")) {
        pos = write_string(out, pos, "Connection");
        pos = write_string(out, pos, ": ");
        pos = write_string(out, pos, "close");
        pos = write_crlf(out, pos);
    }

    pos = write_crlf(out, pos);

    sz body_len = self.body_len_for_wire();

    if (self.body_kind == BODY_BYTES && body_len > 0) {
        out[pos:body_len] = self.body[0:body_len];
        pos += body_len;
    }

    return pos;
}

faultdef RESPONSE_SERIALIZE_ERROR;

fn String? Response.serialize(&self)
{
    sz n = self.serialized_len();

    if (n == 0) return "";

    char* p = localmem.malloc(n + 1)!;
    char[] out = p[0:n];

    sz written = self.write_to(out);

    if (written != n) {
        localmem.free(p);
        return RESPONSE_SERIALIZE_ERROR~;
    }

    p[written] = 0;

    return (String)p[0:written];
}

fn String? Response.serialize_headers_only(&self, bool force_no_body = false)
{
    DString out;
    out.init(localmem, 1024);
    defer catch out.free();

    out.appendf("HTTP/1.1 %d %s\r\n", self.status, status_text(self.status))!;

    bool switching_protocols = self.status == 101;

    if (switching_protocols) {
        self.headers.remove("Transfer-Encoding");
        self.headers.remove("Content-Length");
    } else if (force_no_body || !status_allows_body(self.status)) {
        self.headers.remove("Transfer-Encoding");

        if (!self.headers.has("Content-Length")) {
            self.headers.content_length(0)!;
        }
    } else if (self.body_kind == BODY_STREAM || self.body_kind == BODY_FILE) {
        self.headers.remove("Content-Length");
        self.headers.set("Transfer-Encoding", "chunked")!;
    } else if (!self.headers.has("Content-Length")) {
        self.headers.content_length(self.body_len_for_wire())!;
    }

    if (!self.headers.has("Connection")) {
        self.headers.connection("close")!;
    }

    String headers = self.headers.serialize()!;
    defer localmem.free(headers);

    out.append(headers);
    out.append("\r\n");

    return out.copy_str(localmem);
}

// Debug

fn void Response.dump(&self)
{
    io::printfn("HTTP/1.1 %d %s", self.status, status_text(self.status));
    self.headers.dump();
    io::printfn("Content-Length: %d", self.content_length_for_wire());

    if (self.body_kind == BODY_FILE) {
        io::printfn("File-Path: %s", self.file_path);
        io::printfn("File-Offset: %d", self.file_offset);
        io::printfn("File-Size: %d", self.file_size);
    }

    io::printfn("");

    if (self.body_kind == BODY_BYTES) {
        io::printfn("%s", (String)self.body);
    }
}

// eof