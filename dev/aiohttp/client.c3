// client.c3

// Asynchronous HTTP client API.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::request;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::mem;
import ext::debug;
import ext::encoding::simdjson;


// Faults

faultdef INVALID_URL;
faultdef INVALID_OPTIONS;
faultdef UNSUPPORTED_SCHEME;
faultdef INVALID_RESPONSE;
faultdef RESPONSE_TOO_LARGE;
faultdef RESPONSE_INCOMPLETE;
faultdef INVALID_STATUS;
faultdef INVALID_CONTENT_LENGTH;
faultdef INVALID_CHUNKED_RESPONSE;
faultdef INVALID_AUTH;
faultdef TOO_MANY_REDIRECTS;


// Constants

const ulong DEFAULT_TIMEOUT_US = 30_000_000;
const sz DEFAULT_MAX_RESPONSE_BYTES = 16 * 1024 * 1024;

const sz CLIENT_READ_CHUNK_SIZE = 8192;
const uint DEFAULT_MAX_REDIRECTS = 5;
const sz CLIENT_MAX_HEADER_BYTES = 64 * 1024;

// Allocator

LocalAllocator localmem = null;

fn void init() @init
{
    static bool initialized = false;
    
    if (initialized) return;
    
    if (http::localmem == null) http::init();
    if (localmem == null) localmem = http::localmem;
    
    initialized = true;
}


// Authentication

enum AuthKind
{
    AUTH_NONE,
    AUTH_BEARER,
    AUTH_CUSTOM,
}

struct Auth
{
    AuthKind kind;
    String scheme;
    String value;
}

fn void Auth.clear(&self)
{
    self.kind = AUTH_NONE;
    self.scheme = "";
    self.value = "";
}

fn void Auth.bearer(&self, String token)
{
    self.kind = AUTH_BEARER;
    self.scheme = "Bearer";
    self.value = token;
}

fn void Auth.custom(&self, String scheme, String value)
{
    self.kind = AUTH_CUSTOM;
    self.scheme = scheme;
    self.value = value;
}

fn bool Auth.empty(&self) @inline
{
    return self.kind == AUTH_NONE || self.value.len == 0;
}


// Parsed URL

struct Url
{
    String scheme;
    String host;
    ushort port;
    String target;

    bool owns_scheme;
    bool owns_host;
    bool owns_target;
}

fn void Url.init(&self)
{
    self.scheme = "";
    self.host = "";
    self.port = 0;
    self.target = "/";

    self.owns_scheme = false;
    self.owns_host = false;
    self.owns_target = false;
}

fn void Url.free(&self)
{
    if (self.owns_scheme && self.scheme.ptr != null && self.scheme.len > 0) {
        http::str_free(self.scheme);
    }

    if (self.owns_host && self.host.ptr != null && self.host.len > 0) {
        http::str_free(self.host);
    }

    if (self.owns_target && self.target.ptr != null && self.target.len > 0) {
        http::str_free(self.target);
    }

    self.init();
}

fn ushort? parse_port(String text)
{
    if (text.len == 0) return INVALID_URL~;

    sz? value = text.to_long();
    if (catch err = value) return INVALID_URL~;

    if (value <= 0 || value > 65535) return INVALID_URL~;

    return (ushort)value;
}

fn Url? parse_url(String raw)
{
    sz fragment = raw.index_of("#") ?? -1;
    if (fragment >= 0) {
        raw = raw[0:fragment];
    }
    
    Url url;
    url.init();

    sz scheme_end = raw.index_of("://") ?? -1;
    if (scheme_end <= 0) return INVALID_URL~;

    String scheme = raw[0:scheme_end];
    if (!http::str_iequals(scheme, "http")) return UNSUPPORTED_SCHEME~;

    sz authority_start = scheme_end + 3;
    if (authority_start >= raw.len) return INVALID_URL~;

    String rest = raw[authority_start..];

    sz path_pos = rest.index_of("/") ?? -1;
    sz query_pos = rest.index_of("?") ?? -1;

    sz authority_len = rest.len;

    if (path_pos >= 0 && path_pos < authority_len) {
        authority_len = path_pos;
    }

    if (query_pos >= 0 && query_pos < authority_len) {
        authority_len = query_pos;
    }

    if (authority_len <= 0) return INVALID_URL~;

    String authority = rest[0:authority_len];
    String host = authority;
    ushort port = 80;

    if (authority.starts_with("[")) {
        sz close = authority.index_of("]") ?? -1;
        if (close <= 1) return INVALID_URL~;

        host = authority[1:close - 1];

        if (close + 1 < authority.len) {
            if (authority[close + 1] != ':') return INVALID_URL~;
            port = parse_port(authority[close + 2..])!;
        }
    } else {
        sz colon = authority.index_of(":") ?? -1;

        if (colon >= 0) {
            if (colon == 0 || colon + 1 >= authority.len) return INVALID_URL~;

            host = authority[0:colon];
            port = parse_port(authority[colon + 1..])!;
        }
    }

    if (host.len == 0) return INVALID_URL~;

    String target = "/";

    if (authority_len < rest.len) {
        target = rest[authority_len..];

        if (target.starts_with("?")) {
            DString out;
            out.init(localmem, target.len + 2);
            defer out.free();

            out.append((char[])"/");
            out.append((char[])target);

            target = out.copy_str(localmem);
            url.owns_target = true;
        } else {
            target = http::str_clone(target);
            url.owns_target = true;
        }
    } else {
        target = http::str_clone("/");
        url.owns_target = true;
    }
    

    url.scheme = http::str_clone(scheme);
    url.host = http::str_clone(host);
    url.port = port;
    url.target = target;
    
    url.owns_scheme = true;
    url.owns_host = true;

    return url;
}


// Session

struct Session
{
    http::Cookies cookies;

    ulong timeout_us;
    sz max_response_bytes;
    uint max_redirects;

    bool follow_redirects;
}

fn Session*? session_new()
{
    Session* session = localmem.alloc(Session)!;
    session.init();

    return session;
}

fn void Session.init(&self)
{
    self.cookies.init();

    self.timeout_us = DEFAULT_TIMEOUT_US;
    self.max_response_bytes = DEFAULT_MAX_RESPONSE_BYTES;
    self.max_redirects = DEFAULT_MAX_REDIRECTS;

    self.follow_redirects = true;
}

fn void Session.deinit(&self)
{
    self.cookies.free();

    self.timeout_us = 0;
    self.max_response_bytes = 0;
    self.max_redirects = 0;

    self.follow_redirects = false;
}

fn void Session.free(&self)
{
    self.deinit();
    localmem.free(self);
}


// Options

struct Options
{
    http::Query query;
    http::Headers headers;
    http::Cookies cookies;
    Auth auth;

    char[] data;
    char[] json;

    ulong timeout_us;
}

fn void Options.init(&self)
{
    self.query.init();
    self.headers.init();
    self.cookies.init();
    self.auth.clear();

    self.data = {};
    self.json = {};

    self.timeout_us = 0;
}

fn void Options.clear(&self)
{
    self.query.clear();
    self.headers.clear();
    self.cookies.clear();
    self.auth.clear();

    self.data = {};
    self.json = {};

    self.timeout_us = 0;
}

fn void Options.free(&self)
{
    self.query.free();
    self.headers.free();
    self.cookies.free();
    self.auth.clear();

    self.data = {};
    self.json = {};

    self.timeout_us = 0;
}

fn void? Options.validate(&self)
{
    if (self.data.len > 0 && self.json.len > 0) return INVALID_OPTIONS~;

    if (!self.auth.empty()) {
        if (self.auth.scheme.len == 0) return INVALID_AUTH~;
        if (self.auth.scheme.contains("\r") || self.auth.scheme.contains("\n")) return INVALID_AUTH~;
        if (self.auth.value.contains("\r") || self.auth.value.contains("\n")) return INVALID_AUTH~;
    }
}


// Response

struct Response
{
    ushort status;
    http::Headers headers;
    char[] body;

    String url;

    bool owns_body;
    bool owns_url;
}

fn void Response.init(&self)
{
    self.status = 0;
    self.headers.init();
    self.body = {};
    self.url = "";

    self.owns_body = false;
    self.owns_url = false;
}

fn void Response.free(&self)
{
    self.headers.free();

    if (self.owns_body && self.body.ptr != null) {
        localmem.free(self.body.ptr);
    }

    if (self.owns_url && self.url.ptr != null && self.url.len > 0) {
        http::str_free(self.url);
    }

    self.status = 0;
    self.body = {};
    self.url = "";

    self.owns_body = false;
    self.owns_url = false;
}

fn bool Response.ok(&self) @inline
{
    return self.status >= 200 && self.status < 300;
}

fn bool Response.redirect(&self) @inline
{
    return self.status >= 300 && self.status < 400;
}

fn bool Response.client_error(&self) @inline
{
    return self.status >= 400 && self.status < 500;
}

fn bool Response.server_error(&self) @inline
{
    return self.status >= 500 && self.status < 600;
}

fn String Response.text(&self) @inline
{
    return (String)self.body;
}

fn String? Response.header(&self, String name)
{
    return self.headers.get(name);
}

fn simdjson::ParseResult? Response.json(&self)
{
    if (self.body.len == 0) return INVALID_RESPONSE~;

    return simdjson::parse(localmem, self.body);
}


// Encoding helpers

fn bool is_unreserved(char c) @inline
{
    if (c >= 'a' && c <= 'z') return true;
    if (c >= 'A' && c <= 'Z') return true;
    if (c >= '0' && c <= '9') return true;

    return c == '-' || c == '.' || c == '_' || c == '~';
}

fn char hex_digit(char value) @inline
{
    if (value < 10) return '0' + value;
    return 'A' + value - 10;
}

fn void append_percent_encoded(DString* out, String value)
{
    for (sz i = 0; i < value.len; i++) {
        char c = value[i];

        if (is_unreserved(c)) {
            out.append(c);
            continue;
        }

        out.append('%');
        out.append(hex_digit((c >> 4) & 0x0f));
        out.append(hex_digit(c & 0x0f));
    }
}

fn String? build_target(Url* url, http::Query* query)
{
    if (url == null || query == null) return INVALID_URL~;

    if (query.empty()) return http::str_clone(url.target);

    DString out;
    out.init(localmem, url.target.len + query.len() * 16 + 16);
    defer out.free();

    out.append((char[])url.target);

    bool has_query = url.target.contains("?");
    bool needs_separator = !url.target.ends_with("?") && !url.target.ends_with("&");

    for (sz i = 0; i < query.len(); i++) {
        String name = query.name_at(i)!;
        String value = query.value_at(i)!;

        if (i == 0) {
            if (!has_query) {
                out.append('?');
            } else if (needs_separator) {
                out.append('&');
            }
        } else {
            out.append('&');
        }

        append_percent_encoded(&out, name);
        out.append('=');
        append_percent_encoded(&out, value);
    }

    return out.copy_str(localmem);
}

// Request header helpers

fn void append_header(DString* out, String name, String value)
{
    out.append((char[])name);
    out.append((char[])": ");
    out.append((char[])value);
    out.append((char[])"\r\n");
}

fn void append_host_header(DString* out, Url* url)
{
    out.append((char[])"Host: ");

    if (url.host.contains(":")) {
        out.append('[');
        out.append((char[])url.host);
        out.append(']');
    } else {
        out.append((char[])url.host);
    }

    if (url.port != 80) {
        char[16] port_buf;
        String port = string::bformat(port_buf[..], ":%d", url.port);
        out.append((char[])port);
    }

    out.append((char[])"\r\n");
}

fn void append_authorization(DString* out, Auth* auth)
{
    if (auth == null || auth.empty()) return;

    out.append("Authorization: ");
    out.append(auth.scheme);
    out.append(' ');
    out.append(auth.value);
    out.append("\r\n");
}

fn void? append_cookies(DString* out, http::Cookies* session_cookies, http::Cookies* request_cookies) @maydiscard
{
    bool has_session = session_cookies != null && !session_cookies.empty();
    bool has_request = request_cookies != null && !request_cookies.empty();

    if (!has_session && !has_request) return;

    out.append("Cookie: ");

    bool first = true;

    if (has_session) {
        for (sz i = 0; i < session_cookies.len(); i++) {
            String name = session_cookies.name_at(i)!;
            String value = session_cookies.value_at(i)!;

            if (has_request && request_cookies.has(name)) continue;

            if (!first) out.append("; ");
            first = false;

            out.append(name);
            out.append('=');
            out.append(value);
        }
    }

    if (has_request) {
        for (sz i = 0; i < request_cookies.len(); i++) {
            String name = request_cookies.name_at(i)!;
            String value = request_cookies.value_at(i)!;

            if (!first) out.append("; ");
            first = false;

            out.append(name);
            out.append('=');
            out.append(value);
        }
    }

    out.append("\r\n");
}

fn void? append_custom_headers(DString* out, http::Headers* headers) @maydiscard
{
    for (sz i = 0; i < headers.len(); i++) {
        String name = headers.name_at(i)!;
        String value = headers.value_at(i)!;

        if (http::str_iequals(name, "Host")) continue;
        if (http::str_iequals(name, "Connection")) continue;
        if (http::str_iequals(name, "Content-Length")) continue;
        if (http::str_iequals(name, "Cookie")) continue;
        if (http::str_iequals(name, "Authorization")) continue;

        append_header(out, name, value);
    }
}


fn bool method_allows_request_body(String method) @inline
{
    return method != "GET" && method != "HEAD";
}

fn String? build_session_request(Session* session, String method, Url* url, String target, Options* options)
{
    char[] body = {};
    
    if (method_allows_request_body(method)) {
        body = options.data;
    
        if (options.json.len > 0) {
            body = options.json;
        }
    }
    
    DString out;
    out.init(localmem, 1024 + body.len);
    defer out.free();

    out.append((char[])method);
    out.append(' ');
    out.append((char[])target);
    out.append((char[])" HTTP/1.1\r\n");

    append_host_header(&out, url);
    append_custom_headers(&out, &options.headers);
    append_authorization(&out, &options.auth);

    if (!options.headers.has("User-Agent")) {
        append_header(&out, "User-Agent", "ext-aio-request/1.0");
    }

    if (!options.headers.has("Accept")) {
        append_header(&out, "Accept", "*/*");
    }

    if (body.len > 0 && options.json.len > 0 && !options.headers.has("Content-Type")) {
        append_header(&out, "Content-Type", "application/json");
    }

    append_cookies(&out, &session.cookies, &options.cookies);

    if (body.len > 0 || method == "POST" || method == "PUT" || method == "PATCH") {
        char[32] length_buf;
        String length = string::bformat(length_buf[..], "%d", body.len);
        append_header(&out, "Content-Length", length);
    }

    append_header(&out, "Connection", "close");
    out.append((char[])"\r\n");

    if (body.len > 0) {
        out.append(body);
    }

    return out.copy_str(localmem);
}


// Response parsing

fn sz find_crlf(String text, sz start)
{
    if (start < 0 || start >= text.len) return -1;

    sz relative = text[start..].index_of("\r\n") ?? -1;
    if (relative < 0) return -1;

    return start + relative;
}

fn ushort? parse_status_line(String line)
{
    if (!line.starts_with("HTTP/1.")) return INVALID_STATUS~;

    sz first_space = line.index_of(" ") ?? -1;
    if (first_space < 0 || first_space + 4 > line.len) return INVALID_STATUS~;

    String status_text = line[first_space + 1:3];

    int? parsed = status_text.to_int();
    if (catch err = parsed) return INVALID_STATUS~;

    if (parsed < 100 || parsed > 999) return INVALID_STATUS~;

    return (ushort)parsed;
}

fn void? parse_headers(String block, http::Headers* headers)
{
    sz pos = 0;

    while (pos < block.len) {
        sz line_end = find_crlf(block, pos);
        if (line_end < 0) line_end = block.len;

        String line = block[pos:line_end - pos];
        if (line.len == 0) break;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) return INVALID_RESPONSE~;

        String name = line[0:colon].trim();
        String value = line[colon + 1..].trim();

        headers.add(name, value)!;

        if (line_end >= block.len) break;
        pos = line_end + 2;
    }
}

fn sz? response_content_length(http::Headers* headers)
{
    bool found = false;
    sz result = 0;

    for (sz i = 0; i < headers.len(); i++) {
        String name = headers.name_at(i)!;
        if (!http::str_iequals(name, "Content-Length")) continue;

        String value = headers.value_at(i)!.trim();

        sz? parsed = value.to_long();
        if (catch err = parsed) return INVALID_CONTENT_LENGTH~;
        if (parsed < 0) return INVALID_CONTENT_LENGTH~;

        if (found && parsed != result) return INVALID_CONTENT_LENGTH~;

        result = parsed;
        found = true;
    }

    if (!found) return INVALID_CONTENT_LENGTH~;

    return result;
}

fn bool header_has_token(String value, String token)
{
    sz pos = 0;

    while (pos <= value.len) {
        sz comma = value[pos..].index_of(",") ?? -1;
        String part;

        if (comma < 0) {
            part = value[pos..].trim();
            return http::str_iequals(part, token);
        }

        part = value[pos:comma].trim();
        if (http::str_iequals(part, token)) return true;

        pos += comma + 1;
    }

    return false;
}

fn bool response_is_chunked(http::Headers* headers)
{
    if (!headers.has("Transfer-Encoding")) return false;

    return header_has_token(headers.get("Transfer-Encoding") ?? "", "chunked");
}

fn int hex_value(char c) @inline
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;

    return -1;
}

fn sz? parse_chunk_size(String line)
{
    sz semicolon = line.index_of(";") ?? -1;

    if (semicolon >= 0) {
        line = line[0:semicolon];
    }

    line = line.trim();
    if (line.len == 0) return INVALID_CHUNKED_RESPONSE~;

    sz size = 0;

    for (sz i = 0; i < line.len; i++) {
        int digit = hex_value(line[i]);
        if (digit < 0) return INVALID_CHUNKED_RESPONSE~;

        if (size > (sz::max - digit) / 16) return RESPONSE_TOO_LARGE~;
        size = size * 16 + digit;
    }

    return size;
}

fn char[]? decode_chunked(String encoded, sz max_bytes)
{
    DString decoded;
    decoded.init(localmem, encoded.len);
    defer decoded.free();

    sz pos = 0;

    while (true) {
        sz line_end = find_crlf(encoded, pos);
        if (line_end < 0) return RESPONSE_INCOMPLETE~;

        sz chunk_size = parse_chunk_size(encoded[pos:line_end - pos])!;
        pos = line_end + 2;

        if (chunk_size == 0) {
            if (pos + 2 <= encoded.len && encoded[pos:2] == "\r\n") {
                pos += 2;
                break;
            }
        
            sz trailer_end = encoded[pos..].index_of("\r\n\r\n") ?? -1;
            if (trailer_end < 0) return RESPONSE_INCOMPLETE~;
        
            pos += trailer_end + 4;
            break;
        }

        if (chunk_size > max_bytes || decoded.len() > max_bytes - chunk_size) {
            return RESPONSE_TOO_LARGE~;
        }

        if (pos + chunk_size + 2 > encoded.len) return RESPONSE_INCOMPLETE~;

        decoded.append((char[])encoded[pos:chunk_size]);
        pos += chunk_size;

        if (encoded[pos:2] != "\r\n") return INVALID_CHUNKED_RESPONSE~;
        pos += 2;
    }

    String copied = decoded.copy_str(localmem);
    return (char[])copied;
}

fn void store_response_cookie(Session* session, String set_cookie)
{
    if (session == null || set_cookie.len == 0) return;

    sz semicolon = set_cookie.index_of(";") ?? -1;
    String pair = semicolon >= 0 ? set_cookie[0:semicolon] : set_cookie;

    sz equals = pair.index_of("=") ?? -1;
    if (equals <= 0) return;

    String name = pair[0:equals].trim();
    String value = pair[equals + 1..].trim();

    if (name.len == 0) return;

    session.cookies.set(name, value);
}

fn void? update_session_cookies(Session* session, http::Headers* headers) @maydiscard
{
    if (session == null || headers == null) return;

    for (sz i = 0; i < headers.len(); i++) {
        String name = headers.name_at(i)!;
        if (!http::str_iequals(name, "Set-Cookie")) continue;

        String value = headers.value_at(i)!;
        store_response_cookie(session, value);
    }
}

fn Response? parse_response(Session* session, String method, String raw, String url, sz max_bytes)
{
    sz header_end = raw.index_of("\r\n\r\n") ?? -1;
    if (header_end < 0) return RESPONSE_INCOMPLETE~;

    sz status_end = raw.index_of("\r\n") ?? -1;
    if (status_end <= 0 || status_end > header_end) return INVALID_RESPONSE~;

    Response response;
    response.init();
    defer catch response.free();

    response.status = parse_status_line(raw[0:status_end])!;

    sz headers_start = status_end + 2;
    parse_headers(raw[headers_start:header_end - headers_start], &response.headers)!;

    String encoded_body = raw[header_end + 4..];

    bool no_body = method == "HEAD" ||
                   response.status == 204 ||
                   response.status == 304 ||
                   (response.status >= 100 && response.status < 200);

    if (no_body) {
        response.body = {};
    } else if (response_is_chunked(&response.headers)) {
        response.body = decode_chunked(encoded_body, max_bytes)!;
        response.owns_body = true;
    } else if (response.headers.has("Transfer-Encoding")) {
        return INVALID_RESPONSE~;
    } else if (response.headers.has("Content-Length")) {
        sz length = response_content_length(&response.headers)!;

        if (length > max_bytes) return RESPONSE_TOO_LARGE~;
        if (encoded_body.len < length) return RESPONSE_INCOMPLETE~;

        if (length > 0) {
            String copied = encoded_body[0:length].copy(localmem);
            response.body = (char[])copied;
            response.owns_body = true;
        }
    } else {
        if (encoded_body.len > max_bytes) return RESPONSE_TOO_LARGE~;

        if (encoded_body.len > 0) {
            String copied = encoded_body.copy(localmem);
            response.body = (char[])copied;
            response.owns_body = true;
        }
    }

    response.url = http::str_clone(url);
    response.owns_url = true;

    update_session_cookies(session, &response.headers);

    return response;
}

// Transport

fn String? read_raw_response(aio::Stream* stream, ulong timeout_us, sz max_bytes)
{
    DString out;
    out.init(localmem, CLIENT_READ_CHUNK_SIZE);
    defer out.free();

    char[CLIENT_READ_CHUNK_SIZE] buffer;

    while (true) {
        sz? read_result = stream.read_timeout(buffer[..], timeout_us);

        if (catch err = read_result) {
            if (err == aio::CLOSED) break;
            return err~;
        }

        sz count = read_result;
        if (count == 0) break;

        if (count > max_bytes || out.len() > max_bytes - count) {
            return RESPONSE_TOO_LARGE~;
        }

        out.append(buffer[0:count]);
    }

    if (out.len() == 0) return RESPONSE_INCOMPLETE~;

    return out.copy_str(localmem);
}

// Request execution

fn Response? Session.request_once(&self, String method, String url, Options* options)
{
    Url parsed = parse_url(url)!;
    defer parsed.free();

    String target = build_target(&parsed, &options.query)!;
    defer http::str_free(target);

    String request_data = build_session_request(self, method, &parsed, target, options)!;
    defer localmem.free(request_data);

    ulong timeout_us = options.timeout_us > 0 ? options.timeout_us : self.timeout_us;
    if (timeout_us == 0) timeout_us = DEFAULT_TIMEOUT_US;

    aio::Stream* stream = aio::stream_connect(parsed.host, parsed.port)!;
    defer stream.free();

    stream.write_all_timeout((char[])request_data, timeout_us)!;

    sz max_wire_bytes = self.max_response_bytes + CLIENT_MAX_HEADER_BYTES;
    String raw = read_raw_response(stream, timeout_us, max_wire_bytes)!;

    defer localmem.free(raw);

    stream.close();

    return parse_response(self, method, raw, url, self.max_response_bytes);
}

fn bool redirect_status(ushort status) @inline
{
    return status == 301 ||
           status == 302 ||
           status == 303 ||
           status == 307 ||
           status == 308;
}

fn String? resolve_redirect(String current_url, String location)
{
    if (location.starts_with("http://")) {
        return http::str_clone(location);
    }

    if (location.starts_with("https://")) {
        return UNSUPPORTED_SCHEME~;
    }

    Url current = parse_url(current_url)!;
    defer current.free();

    DString out;
    out.init(localmem, current_url.len + location.len + 16);
    defer out.free();

    out.append("http://");

    if (current.host.contains(":")) {
        out.append('[');
        out.append(current.host);
        out.append(']');
    } else {
        out.append(current.host);
    }

    if (current.port != 80) {
        char[16] port_buf;
        String port = string::bformat(port_buf[..], ":%d", current.port);
        out.append(port);
    }

    if (location.starts_with("?")) {
        String target = current.target;
        sz query = target.index_of("?") ?? -1;
    
        if (query >= 0) {
            target = target[0:query];
        }
    
        out.append(target);
        out.append(location);
    
        return out.copy_str(localmem);
    }

    if (location.starts_with("/")) {
        out.append(location);
        return out.copy_str(localmem);
    }

    String target = current.target;
    sz query = target.index_of("?") ?? -1;

    if (query >= 0) {
        target = target[0:query];
    }

    sz last_slash = -1;

    for (sz i = target.len - 1; i >= 0; i--) {
        if (target[i] == '/') {
            last_slash = i;
            break;
        }
    }

    if (last_slash < 0) {
        out.append('/');
    } else {
        out.append(target[0:last_slash + 1]);
    }

    out.append(location);

    return out.copy_str(localmem);
}

fn Response? Session.request(&self, String method, String url, Options* options = null)
{
    Options defaults;
    Options* request_options = options;

    if (request_options == null) {
        defaults.init();
        defer defaults.free();

        request_options = &defaults;
    }

    request_options.validate()!;

    String current_url = http::str_clone(url);
    defer http::str_free(current_url);

    String current_method = method;

    for (uint redirects = 0; ; redirects++) {
        Response response = self.request_once(current_method, current_url, request_options)!;

        if (!self.follow_redirects || !redirect_status(response.status)) {
            return response;
        }

        String? location_result = response.headers.get("Location");

        if (catch err = location_result) {
            return response;
        }

        if (redirects >= self.max_redirects) {
            response.free();
            return TOO_MANY_REDIRECTS~;
        }

        String location = location_result;
        
        String? next_url_result = resolve_redirect(current_url, location);
        if (catch err = next_url_result) {
            response.free();
            return err~;
        }
        
        String next_url = next_url_result;
        ushort status = response.status;
        
        response.free();
        http::str_free(current_url);
        
        current_url = next_url;

        if (status == 303 && current_method != "HEAD") {
            current_method = "GET";
        } else if ((status == 301 || status == 302) && current_method == "POST") {
            current_method = "GET";
        }
    }
}


// Session convenience API

fn Response? Session.get(&self, String url, Options* options = null)
{
    return self.request("GET", url, options);
}

fn Response? Session.post(&self, String url, Options* options = null)
{
    return self.request("POST", url, options);
}

fn Response? Session.put(&self, String url, Options* options = null)
{
    return self.request("PUT", url, options);
}

fn Response? Session.patch(&self, String url, Options* options = null)
{
    return self.request("PATCH", url, options);
}

fn Response? Session.delete(&self, String url, Options* options = null)
{
    return self.request("DELETE", url, options);
}

fn Response? Session.head(&self, String url, Options* options = null)
{
    return self.request("HEAD", url, options);
}

fn Response? Session.options(&self, String url, Options* options = null)
{
    return self.request("OPTIONS", url, options);
}


// Stateless convenience API

fn Response? get(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.get(url, options);
}

fn Response? post(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.post(url, options);
}

fn Response? put(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.put(url, options);
}

fn Response? patch(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.patch(url, options);
}

fn Response? delete(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.delete(url, options);
}

fn Response? head(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.head(url, options);
}

fn Response? options(String url, Options* options = null)
{
    Session session;
    session.init();
    defer session.deinit();

    return session.options(url, options);
}

// eof