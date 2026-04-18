// aiohttpmtypes.c3

module ext::aiohttp;

import std::encoding::base64;

// Shared types for ext::aiohttp.
//
// This file is the foundation of both the client (aiohttp.client.c3) and
// the server (aiohttp.web.c3). It must be compiled first.
//
// Url parsing and percent-encoding live in util.url.c3 (same module).
// WebSocket frame types (WsMsgType, WsCloseCode, WsMessage) are declared here
// and used by both util.ws.c3 and the client/server implementations.

//  faults 

faultdef NONE,
    CONNECTION_FAILED,    // TCP connect failed
    TIMEOUT,              // request or socket timed out
    SSL_ERROR,            // TLS handshake or certificate error
    TOO_MANY_REDIRECTS,   // redirect loop exceeded limit
    INVALID_URL,          // malformed URL string
    RESPONSE_ERROR,       // server response could not be parsed
    WS_ERROR,             // WebSocket protocol error
    CANCELLED;            // request was cancelled


//  HTTP method 

enum HttpMethod : int {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    HEAD,
    OPTIONS,
}

fn String HttpMethod.str(self) @inline
{
    switch (self) {
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

fn HttpMethod? http_method_from_str(String s)
{
    if (s == "GET")     return HttpMethod.GET;
    if (s == "POST")    return HttpMethod.POST;
    if (s == "PUT")     return HttpMethod.PUT;
    if (s == "PATCH")   return HttpMethod.PATCH;
    if (s == "DELETE")  return HttpMethod.DELETE;
    if (s == "HEAD")    return HttpMethod.HEAD;
    if (s == "OPTIONS") return HttpMethod.OPTIONS;
    return RESPONSE_ERROR~;
}

//  URL 
//
// Url fields are zero-copy slices when produced by url_parse().
// When built manually, fields are owned strings.
//
// url_parse()    → defined in util.url.c3
// Url.to_string() → defined in util.url.c3

struct Url {
    String scheme;    // "http" | "https" | "ws" | "wss"
    String host;      // hostname or IP (IPv6 without brackets)
    ushort port;      // 0 = use scheme default
    String path;      // "/" if absent
    String query;     // without leading "?"
    String fragment;  // without leading "#"
    String raw;       // original string (zero-copy source)
}

// Convenience: true for TLS schemes.
fn bool Url.is_tls(&self) @inline
{
    return self.scheme == "https" || self.scheme == "wss";
}

// Effective port: returns scheme default when port == 0.
fn ushort Url.effective_port(&self) @inline
{
    if (self.port != 0) return self.port;
    return scheme_default_port(self.scheme);
}

//  Headers 

const usz HEADERS_INIT_CAP @private = 16;

struct Header {
    String name;
    String value;
}

struct Headers {
    Header* entries;
    usz     count;
    usz     capacity;
}

// Case-insensitive header name comparison.
fn bool hdr_ieq(String a, String b) @private @inline
{
    if (a.len != b.len) return false;
    for (usz i = 0; i < a.len; i++) {
        char ca = a[i]; if (ca >= 'A' && ca <= 'Z') ca = (char)(ca | 0x20);
        char cb = b[i]; if (cb >= 'A' && cb <= 'Z') cb = (char)(cb | 0x20);
        if (ca != cb) return false;
    }
    return true;
}

fn Headers* headers_new()
{
    Headers* h = localmem.alloc(Headers);
    h.entries  = localmem.malloc(HEADERS_INIT_CAP * Header.sizeof);
    h.count    = 0;
    h.capacity = HEADERS_INIT_CAP;
    return h;
}

fn void headers_grow(Headers* h) @private
{
    usz new_cap = h.capacity * 2;
    Header* new_buf = localmem.malloc(new_cap * Header.sizeof);
    for (usz i = 0; i < h.count; i++) new_buf[i] = h.entries[i];
    localmem.free(h.entries);
    h.entries  = new_buf;
    h.capacity = new_cap;
}

fn void Headers.free(&self)
{
    localmem.free(self.entries);
    localmem.free(self);
}

// Case-insensitive lookup. Returns RESPONSE_ERROR if absent.
fn String? Headers.get(&self, String name)
{
    for (usz i = 0; i < self.count; i++) {
        if (hdr_ieq(self.entries[i].name, name)) return self.entries[i].value;
    }
    return RESPONSE_ERROR~;
}

// Set (overwrite first match, or append if absent).
fn void Headers.set(&self, String name, String value)
{
    for (usz i = 0; i < self.count; i++) {
        if (hdr_ieq(self.entries[i].name, name)) {
            self.entries[i].value = value;
            return;
        }
    }
    self.add(name, value);
}

// Always appends (allows duplicate header names — e.g. Set-Cookie).
fn void Headers.add(&self, String name, String value)
{
    if (self.count >= self.capacity) headers_grow(self);
    self.entries[self.count++] = (Header){ name, value };
}

// Remove all headers with this name (case-insensitive).
fn void Headers.del(&self, String name)
{
    usz dst = 0;
    for (usz i = 0; i < self.count; i++) {
        if (!hdr_ieq(self.entries[i].name, name)) {
            self.entries[dst++] = self.entries[i];
        }
    }
    self.count = dst;
}

fn Header Headers.get_at(&self, usz idx)
{
    return self.entries[idx];
}

fn usz Headers.len(&self) @inline { return self.count; }

// True if header name is present (case-insensitive).
fn bool Headers.has(&self, String name)
{
    for (usz i = 0; i < self.count; i++) {
        if (hdr_ieq(self.entries[i].name, name)) return true;
    }
    return false;
}

//  Cookie 

struct Cookie {
    String name;
    String value;
    String domain;    // "" = any domain
    String path;      // "" = any path (treated as "/")
    long   expires;   // Unix timestamp. 0 = session cookie
    bool   secure;
    bool   http_only;
    String same_site; // "Strict" | "Lax" | "None" | ""
}

//  CookieJar 

const usz COOKIEJAR_INIT_CAP @private = 32;

struct CookieJar {
    Cookie* cookies;
    usz     count;
    usz     capacity;
    bool    unsafe_ips; // allow cookies for bare-IP hosts (RFC 6265 §5.3 exception)
}

struct DummyCookieJar { // ignores all cookies (e.g. for pure API clients)
    bool dummy;
}

fn CookieJar* cookiejar_new(bool unsafe_ips = false)
{
    CookieJar* jar = localmem.alloc(CookieJar);
    jar.cookies = (Cookie*)localmem.malloc(COOKIEJAR_INIT_CAP * Cookie.sizeof);
    jar.count      = 0;
    jar.capacity   = COOKIEJAR_INIT_CAP;
    jar.unsafe_ips = unsafe_ips;
    return jar;
}

fn void CookieJar.free(&self)
{
    localmem.free(self.cookies);
    localmem.free(self);
}

fn void cookiejar_grow(CookieJar* jar) @private
{
    usz new_cap = jar.capacity * 2;
    Cookie* nb  = (Cookie*)localmem.malloc(new_cap * Cookie.sizeof);
    for (usz i = 0; i < jar.count; i++) nb[i] = jar.cookies[i];
    localmem.free(jar.cookies);
    jar.cookies  = nb;
    jar.capacity = new_cap;
}

// True if host looks like a bare IP address (simplified: no dots-in-label check).
fn bool is_ip_host(String host) @private
{
    // IPv6 literals have ':' characters
    foreach (c : host) { if (c == ':') return true; }
    // IPv4: all chars are digits or dots, at least one dot
    bool has_dot = false;
    foreach (c : host) {
        if (c == '.') { has_dot = true; continue; }
        if (c >= '0' && c <= '9') continue;
        return false; // letter → hostname
    }
    return has_dot;
}

// Domain match per RFC 6265 §5.1.3.
// cookie_domain may be empty (host-only) or prefixed with ".".
fn bool domain_match(String cookie_domain, String host) @private
{
    if (cookie_domain.len == 0) return true; // host-only: matched at store time
    // strip leading dot for comparison
    String cd = cookie_domain;
    if (cd.len > 0 && cd[0] == '.') cd = (String) cd[1:cd.len - 1];
    // exact match
    if (cd == host) return true;
    // suffix match: host ends with "." + cd
    if (host.len > cd.len + 1 &&
        host[host.len - cd.len - 1] == '.' &&
        (String) host[host.len - cd.len: cd.len] == cd) {
        return true;
    }
    return false;
}

// Path match per RFC 6265 §5.1.4.
fn bool path_match(String cookie_path, String req_path) @private
{
    if (cookie_path.len == 0 || cookie_path == "/") return true;
    if (req_path.len < cookie_path.len) return false;
    // request path must start with cookie_path
    for (usz i = 0; i < cookie_path.len; i++) {
        if (req_path[i] != cookie_path[i]) return false;
    }
    // must be followed by '/', end-of-string, or cookie_path ends with '/'
    if (req_path.len == cookie_path.len) return true;
    if (req_path[cookie_path.len] == '/') return true;
    if (cookie_path[cookie_path.len - 1] == '/') return true;
    return false;
}

// Ingest Set-Cookie values into the jar.
// response_url is used for domain/path defaults and IP filtering.
fn void CookieJar.update(&self, Cookie* incoming, usz count, Url* response_url)
{
    for (usz i = 0; i < count; i++) {
        Cookie* c = &incoming[i];

        // reject IP-targeted cookies unless unsafe_ips
        if (!self.unsafe_ips && is_ip_host(response_url.host)) continue;

        // domain default: host-only if domain is empty
        String effective_domain = c.domain.len > 0 ? c.domain : response_url.host;

        // path default: directory of the request path
        String effective_path = c.path;
        if (effective_path.len == 0) {
            // RFC 6265 §5.1.4 default path
            usz last_slash = 0;
            for (usz j = 0; j < response_url.path.len; j++) {
                if (response_url.path[j] == '/') last_slash = j;
            }
            effective_path = (last_slash == 0) ? "/" :
                (String)response_url.path[0:last_slash];
        }

        // look for existing cookie with same (name, domain, path) to overwrite
        bool found = false;
        for (usz j = 0; j < self.count; j++) {
            Cookie* existing = &self.cookies[j];
            if (existing.name   == c.name &&
                existing.domain == effective_domain &&
                existing.path   == effective_path) {
                existing.value     = c.value;
                existing.expires   = c.expires;
                existing.secure    = c.secure;
                existing.http_only = c.http_only;
                existing.same_site = c.same_site;
                found = true;
                break;
            }
        }

        if (!found) {
            if (self.count >= self.capacity) cookiejar_grow(self);
            Cookie nc   = *c;
            nc.domain   = effective_domain;
            nc.path     = effective_path;
            self.cookies[self.count++] = nc;
        }
    }
}

// Return cookies applicable to url. Result is heap-allocated; caller must free.
fn Cookie* CookieJar.filter(&self, Url* url, usz* out_count)
{
    // count matching cookies first
    usz matches = 0;
    for (usz i = 0; i < self.count; i++) {
        Cookie* c = &self.cookies[i];
        if (!domain_match(c.domain, url.host)) continue;
        if (!path_match(c.path, url.path))     continue;
        if (c.secure && !url.is_tls())         continue;
        matches++;
    }

    *out_count = matches;
    if (matches == 0) return null;

    Cookie* result = (Cookie*)localmem.malloc(matches * Cookie.sizeof);
    usz idx = 0;
    for (usz i = 0; i < self.count; i++) {
        Cookie* c = &self.cookies[i];
        if (!domain_match(c.domain, url.host)) continue;
        if (!path_match(c.path, url.path))     continue;
        if (c.secure && !url.is_tls())         continue;
        result[idx++] = *c;
    }
    return result;
}

fn Cookie CookieJar.get_at(&self, usz idx) { return self.cookies[idx]; }
fn usz    CookieJar.len(&self) @inline     { return self.count; }

//  ClientTimeout 

struct ClientTimeout {
    ulong total_us;        // total wall-clock budget (connect + read). 0 = unlimited
    ulong connect_us;      // pool wait + TCP connect timeout
    ulong sock_connect_us; // TCP connect only (subset of connect_us)
    ulong sock_read_us;    // per-read() call timeout
}

// Sensible default: 30 s total, no per-phase limit.
const ClientTimeout TIMEOUT_DEFAULT = { .total_us = 30_000_000 };

// No timeout at all (use with care).
const ClientTimeout TIMEOUT_NONE = { 0, 0, 0, 0 };

//  TlsConfig 

struct TlsConfig {
    bool   verify_peer; // default true — set false only for testing
    String ca_file;     // PEM CA bundle path. "" = use system default
    String cert_file;   // client certificate for mutual TLS. "" = none
    String key_file;    // private key matching cert_file. "" = none
}

const TlsConfig TLS_DEFAULT = { .verify_peer = true };

//  BasicAuth 

struct BasicAuth {
    String username;
    String password;
}

// Encode as "Basic <base64(username:password)>".
// Uses the provided allocator. Caller must free the result.
fn String BasicAuth.encode(&self, Allocator alloc)
{
    localmem = alloc;
    
    usz cred_len = self.username.len + 1 + self.password.len;
    char* cred = localmem.malloc(cred_len);
    defer localmem.free(cred);
    usz ci = 0;
    for (usz i = 0; i < self.username.len; i++) cred[ci++] = self.username[i];
    cred[ci++] = ':';
    for (usz i = 0; i < self.password.len; i++) cred[ci++] = self.password[i];

    String b64 = base64::encode(alloc, cred[0:cred_len]);
    defer b64.free(alloc);
    // "Basic " (6) + b64
    char* out = localmem.malloc(6 + b64.len + 1);
    out[0]='B'; out[1]='a'; out[2]='s'; out[3]='i'; out[4]='c'; out[5]=' ';
    for (usz i = 0; i < b64.len; i++) out[6 + i] = b64[i];
    out[6 + b64.len] = 0;
    return (String) out[0: 6 + b64.len];
}

//  WebSocket types 

enum WsMsgType : int {
    TEXT,
    BINARY,
    PING,
    PONG,
    CLOSE,
    ERROR,
}

constdef WsCloseCode : inline ushort {
    NORMAL_CLOSURE   = 1000,
    GOING_AWAY       = 1001,
    UNSUPPORTED_DATA = 1003,
    INVALID_PAYLOAD  = 1007,
    POLICY_VIOLATION = 1008,
    MESSAGE_TOO_BIG  = 1009,
    INTERNAL_ERROR   = 1011,
}

// WsMessage is a heap-owning decoded WebSocket message.
// Produced by ClientWs.receive() / WebSocketResponse.receive().
// Free with WsMessage.free() when done.
struct WsMessage {
    WsMsgType type;
    char* data;     // heap-allocated payload bytes
    usz data_len;
    String extra;    // close reason string (slice into data) or error description
}

fn void WsMessage.free(&self)
{
    if (self.data != null) {
        localmem.free(self.data);
        self.data     = null;
        self.data_len = 0;
    }
}

// Convenience: view payload as a String (not null-terminated).
fn String WsMessage.as_str(&self) @inline
{
    return (String) self.data[0:self.data_len];
}

//  FormData 

const usz FORMDATA_INIT_CAP @private = 8;

struct FormDataField {
    String name;
    char*  data;
    usz    data_len;
    String filename;      // "" = plain text field
    String content_type;  // "" = auto-detect
}

struct FormData {
    FormDataField* fields;
    usz            count;
    usz            capacity;
}

fn FormData* formdata_new()
{
    FormData* f = localmem.alloc(FormData);
    f.fields    = localmem.malloc(FORMDATA_INIT_CAP * FormDataField.sizeof);
    f.count     = 0;
    f.capacity  = FORMDATA_INIT_CAP;
    return f;
}

fn void formdata_grow(FormData* f) @private
{
    usz new_cap       = f.capacity * 2;
    FormDataField* nb = localmem.malloc(new_cap * FormDataField.sizeof);
    for (usz i = 0; i < f.count; i++) nb[i] = f.fields[i];
    localmem.free(f.fields);
    f.fields   = nb;
    f.capacity = new_cap;
}

fn void FormData.free(&self)
{
    localmem.free(self.fields);
    localmem.free(self);
}

// Add a binary field (or file upload when filename != "").
fn void FormData.add_field(
    &self,
    String name,
    char*  data,
    usz    data_len,
    String filename     = "",
    String content_type = "",
)
{
    if (self.count >= self.capacity) formdata_grow(self);
    self.fields[self.count++] = (FormDataField){
        .name         = name,
        .data         = data,
        .data_len     = data_len,
        .filename     = filename,
        .content_type = content_type,
    };
}

// Add a plain text field (no filename, content_type auto).
fn void FormData.add_str(&self, String name, String value)
{
    self.add_field(name, (char*)value.ptr, value.len);
}

//  HTTP status helpers 

// Map a numeric status code to a standard reason phrase.
fn String http_reason(int status)
{
    switch (status) {
        case 100: return "Continue";
        case 101: return "Switching Protocols";
        case 200: return "OK";
        case 201: return "Created";
        case 202: return "Accepted";
        case 204: return "No Content";
        case 206: return "Partial Content";
        case 301: return "Moved Permanently";
        case 302: return "Found";
        case 303: return "See Other";
        case 304: return "Not Modified";
        case 307: return "Temporary Redirect";
        case 308: return "Permanent Redirect";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 409: return "Conflict";
        case 410: return "Gone";
        case 413: return "Request Entity Too Large";
        case 422: return "Unprocessable Entity";
        case 429: return "Too Many Requests";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 502: return "Bad Gateway";
        case 503: return "Service Unavailable";
        default:  return "Unknown";
    }
}

fn bool http_status_is_success(int status) @inline { return status >= 200 && status < 300; }
fn bool http_status_is_redirect(int status) @inline { return status >= 300 && status < 400; }
fn bool http_status_is_error(int status) @inline    { return status >= 400; }
fn bool http_status_is_client_err(int status) @inline { return status >= 400 && status < 500; }
fn bool http_status_is_server_err(int status) @inline { return status >= 500; }
