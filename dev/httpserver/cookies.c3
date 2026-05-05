// cookies.c3

module ext::httpserver;

import std::io;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef INVALID_COOKIE_NAME;
faultdef INVALID_COOKIE_HEADER;


// 
// Cookie helpers
// 

fn bool cookie_is_space(char c) @inline
{
    return c == ' ' || c == '\t';
}

fn String cookie_trim(String s)
{
    usz start = 0;
    usz end = s.len;

    while (start < end && cookie_is_space(s[start])) {
        start++;
    }

    while (end > start && cookie_is_space(s[end - 1])) {
        end--;
    }

    return s[start:end - start];
}

fn isz cookie_find_char(String s, char needle, usz start)
{
    for (usz i = start; i < s.len; i++) {
        if (s[i] == needle) return (isz)i;
    }

    return -1;
}

// Cookie name is close to token syntax.
// We intentionally reuse is_valid_name() from header.c3.
//
// Valid:
//   session_id
//   theme
//   csrf-token
//
// Invalid:
//   ""
//   "a b"
//   "a=b"
//   "a;b"
fn bool cookie_name_valid(String name)
{
    return is_valid_name(name);
}


// 
// Cookie pair parser
// 

// Parses one Cookie pair:
//
//   name=value
//
// Empty pair is ignored.
// Invalid pair is ignored instead of failing the whole request,
// because browsers and proxies can send messy Cookie headers.
fn void? cookie_parse_pair(Cookies* out, String pair)
{
    pair = cookie_trim(pair);

    if (pair.len == 0) return;

    isz eq = cookie_find_char(pair, '=', 0);

    if (eq <= 0) {
        // Ignore invalid cookie pair.
        return;
    }

    usz p = (usz)eq;

    String name = cookie_trim(pair[0:p]);
    String value = cookie_trim(pair[p + 1:pair.len - p - 1]);

    if (name.len == 0) return;

    if (!cookie_name_valid(name)) {
        return INVALID_COOKIE_NAME~;
    }

    // Cookie header values are not URL-decoded by default.
    // If the application wants encoded values, it can call url_decode().
    out.set(name, value);
}


// 
// Cookie header parser
// 

// Parses request Cookie header value:
//
//   session_id=abc123; theme=dark; count=10
//
// Result:
//   session_id => abc123
//   theme      => dark
//   count      => 10
fn void? cookies_parse_header(Cookies* out, String header)
{
    if (header.len == 0) return;

    usz start = 0;

    while (start <= header.len) {
        isz semi = cookie_find_char(header, ';', start);

        String pair;

        if (semi < 0) {
            pair = header[start:header.len - start];
            cookie_parse_pair(out, pair)!;
            break;
        }

        usz end = (usz)semi;
        pair = header[start:end - start];
        cookie_parse_pair(out, pair)!;

        start = end + 1;
    }
}


// Parses all Cookie headers from request headers.
//
// Although Cookie is usually sent as one header, this supports repeated
// Cookie headers because Headers allows duplicate names.
fn void? cookies_parse(Cookies* out, Headers* headers)
{
    for (usz i = 0; i < headers.len(); i++) {
        Header* h = &headers.items[i];

        if (!str_iequals(h.name, "Cookie")) {
            continue;
        }

        cookies_parse_header(out, h.value)!;
    }
}


// 
// Request cookie helpers
// 

// Parses cookies from Request.
// Caller owns returned Cookies and must call cookies.free().
fn Cookies? Request.cookies(&self)
{
    Cookies cookies;
    cookies.init();

    if (catch err = cookies_parse(&cookies, &self.headers)) {
        cookies.free();
        return err~;
    }

    return cookies;
}

// Convenience accessor.
//
// Returns an allocated copy.
// Caller must free the returned String with localmem.free().
fn String? Request.cookie_copy(&self, String name)
{
    Cookies cookies = self.cookies()!;
    defer cookies.free();

    String? value = cookies.get(name);
    if (catch err = value) {
        return err~;
    }

    return value.copy(localmem);
}


// 
// Context cookie cache
// 

// NOTE:
// To cache cookies in Context, add these fields to Context:
//
//   Cookies cookie_cache;
//   bool cookie_cache_ready;
//
// Then initialize/free them in Context.init()/Context.free().
// If you do not want to modify Context, use Request.cookies()
// or Request.cookie_copy() only.

fn void? Context.ensure_cookie_cache(&self)
{
    if (self.cookie_cache_ready) return;

    if (self.req == null) {
        return CONTEXT_NOT_READY~;
    }

    cookies_parse(&self.cookie_cache, &self.req.headers)!;
    self.cookie_cache_ready = true;
}

fn String? Context.cookie(&self, String name)
{
    self.ensure_cookie_cache()!;
    return self.cookie_cache.get(name);
}

fn bool Context.has_cookie(&self, String name)
{
    if (catch self.ensure_cookie_cache()) {
        return false;
    }

    return self.cookie_cache.has(name);
}

fn Cookies* Context.cookies(&self)
{
    if (catch self.ensure_cookie_cache()) {
        return null;
    }

    return &self.cookie_cache;
}


// 
// Set-Cookie builder
// 

struct CookieOptions {
    String path;
    String domain;
    String max_age;
    String expires;
    String same_site;
    bool http_only;
    bool secure;
}

fn void CookieOptions.init(&self)
{
    self.path = "";
    self.domain = "";
    self.max_age = "";
    self.expires = "";
    self.same_site = "";
    self.http_only = false;
    self.secure = false;
}

fn CookieOptions cookie_options_default()
{
    CookieOptions opt;
    opt.init();
    opt.path = "/";
    opt.same_site = "Lax";
    return opt;
}

fn usz cookie_option_len(CookieOptions* opt)
{
    usz n = 0;

    if (opt.path.len > 0) {
        n += "; Path=".len + opt.path.len;
    }

    if (opt.domain.len > 0) {
        n += "; Domain=".len + opt.domain.len;
    }

    if (opt.max_age.len > 0) {
        n += "; Max-Age=".len + opt.max_age.len;
    }

    if (opt.expires.len > 0) {
        n += "; Expires=".len + opt.expires.len;
    }

    if (opt.same_site.len > 0) {
        n += "; SameSite=".len + opt.same_site.len;
    }

    if (opt.http_only) {
        n += "; HttpOnly".len;
    }

    if (opt.secure) {
        n += "; Secure".len;
    }

    return n;
}

fn usz cookie_write_string(char[] out, usz pos, String s)
{
    out[pos:s.len] = s[0:s.len];
    return pos + s.len;
}

fn String? cookie_build(String name, String value, CookieOptions* opt)
{
    if (!cookie_name_valid(name)) {
        return INVALID_COOKIE_NAME~;
    }

    usz n = name.len + 1 + value.len + cookie_option_len(opt);

    char* p = localmem.malloc(n + 1);
    usz pos = 0;

    pos = cookie_write_string(p[0:n], pos, name);
    p[pos++] = '=';
    pos = cookie_write_string(p[0:n], pos, value);

    if (opt.path.len > 0) {
        pos = cookie_write_string(p[0:n], pos, "; Path=");
        pos = cookie_write_string(p[0:n], pos, opt.path);
    }

    if (opt.domain.len > 0) {
        pos = cookie_write_string(p[0:n], pos, "; Domain=");
        pos = cookie_write_string(p[0:n], pos, opt.domain);
    }

    if (opt.max_age.len > 0) {
        pos = cookie_write_string(p[0:n], pos, "; Max-Age=");
        pos = cookie_write_string(p[0:n], pos, opt.max_age);
    }

    if (opt.expires.len > 0) {
        pos = cookie_write_string(p[0:n], pos, "; Expires=");
        pos = cookie_write_string(p[0:n], pos, opt.expires);
    }

    if (opt.same_site.len > 0) {
        pos = cookie_write_string(p[0:n], pos, "; SameSite=");
        pos = cookie_write_string(p[0:n], pos, opt.same_site);
    }

    if (opt.http_only) {
        pos = cookie_write_string(p[0:n], pos, "; HttpOnly");
    }

    if (opt.secure) {
        pos = cookie_write_string(p[0:n], pos, "; Secure");
    }

    p[pos] = 0;
    return (String)p[0:pos];
}


// 
// Context Set-Cookie helpers
// 

// Low-level Set-Cookie.
// Example:
//   c.set_cookie("sid=abc; Path=/; HttpOnly; SameSite=Lax");
//
// This already exists in context.c3, but keeping this comment here
// documents the intended behavior:
//
//   fn void Context.set_cookie(&self, String value)
//   {
//       self.res.set_cookie(value);
//   }

// High-level cookie setter.
fn void? Context.cookie_set(&self, String name, String value, CookieOptions* opt) @maydiscard
{
    String? cookie = cookie_build(name, value, opt);
    if (catch err = cookie) {
        return err~;
    }
    defer localmem.free(cookie);

    self.set_cookie(cookie);
}

// High-level cookie setter with default options:
//   Path=/; SameSite=Lax
fn void? Context.cookie_set_default(&self, String name, String value) @maydiscard
{
    CookieOptions opt = cookie_options_default();

    self.cookie_set(name, value, &opt)!;
}

// Deletes cookie by sending:
//   Set-Cookie: name=; Path=/; Max-Age=0; SameSite=Lax
fn void? Context.delete_cookie(&self, String name) @maydiscard
{
    CookieOptions opt = cookie_options_default();
    opt.max_age = "0";

    self.cookie_set(name, "", &opt)!;
}

// Deletes cookie with explicit path.
fn void? Context.delete_cookie_path(&self, String name, String path) @maydiscard
{
    CookieOptions opt = cookie_options_default();
    opt.path = path;
    opt.max_age = "0";

    self.cookie_set(name, "", &opt)!;
}


// 
// Debug
// 

fn void cookies_dump(Cookies* cookies)
{
    cookies.dump();
}