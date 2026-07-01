// cookies.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;
import c::errno;

// 
// Faults
// 

faultdef INVALID_COOKIE_NAME;
faultdef INVALID_COOKIE_VALUE;
faultdef INVALID_COOKIE_OPTION;

fn bool value_valid(String value) @local
{
    for (sz i = 0; i < value.len; i++)
    {
        char c = value[i];

        if (c == '\r') return false;
        if (c == '\n') return false;
        if (c == ';') return false;
        if (c == 0) return false;
    }

    return true;
}


fn bool same_site_valid(String value) @local
{
    if (value.len == 0) return true;

    if (str_iequals(value, "Lax")) return true;
    if (str_iequals(value, "Strict")) return true;
    if (str_iequals(value, "None")) return true;

    return false;
}

fn bool max_age_valid(String value) @local
{
    if (value.len == 0) return true;

    for (sz i = 0; i < value.len; i++)
    {
        char c = value[i];

        if (c < '0' || c > '9') return false;
    }

    return true;
}

fn bool options_valid(CookieOptions* opt) @local
{
    if (opt == null) return true;

    if (!value_valid(opt.path)) return false;
    if (!value_valid(opt.domain)) return false;
    if (!max_age_valid(opt.max_age)) return false;
    if (!value_valid(opt.expires)) return false;
    if (!value_valid(opt.same_site)) return false;

    if (!same_site_valid(opt.same_site)) return false;

    if (str_iequals(opt.same_site, "None") && !opt.secure)
    {
        return false;
    }

    return true;
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
fn bool name_valid(String name) @local
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
fn void? parse_pair(Cookies* out, String pair) @local @maydiscard
{
    if (out == null) return errno::E_INVALID_ARG~;

    pair = pair.trim();

    if (pair.len == 0) return;

    sz eq = find_char(pair, '=', 0);

    if (eq <= 0)
    {
        // Ignore invalid cookie pair.
        return;
    }

    sz p = (sz)eq;

    String name = pair[0:p].trim();
    String value = pair[p + 1:pair.len - p - 1].trim();

    if (name.len == 0) return;

    if (!name_valid(name)) return;

    // Cookie header values are not URL-decoded by default.
    // If the application wants encoded values, it can call url_decode().
    out.set(name, value)!;
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
fn void? parse_header(Cookies* out, String header) @local @maydiscard
{
    if (out == null) return errno::E_INVALID_ARG~;
    if (header.len == 0) return;

    sz start = 0;

    while (start <= header.len)
    {
        sz semi = find_char(header, ';', start);

        String pair;

        if (semi < 0)
        {
            pair = header[start:header.len - start];
            parse_pair(out, pair)!;
            break;
        }

        sz end = (sz)semi;
        pair = header[start:end - start];
        parse_pair(out, pair)!;

        start = end + 1;
    }
}


// Parses all Cookie headers from request headers.
//
// Although Cookie is usually sent as one header, this supports repeated
// Cookie headers because Headers allows duplicate names.
fn void? cookies_parse(Cookies* out, Headers* headers) @maydiscard
{
    if (out == null) return errno::E_INVALID_ARG~;
    if (headers == null) return errno::E_INVALID_ARG~;

    for (sz i = 0; i < headers.len(); i++) 
    {
        Header* h = &headers.items[i];

        if (!str_iequals(h.name, "Cookie"))
        {
            continue;
        }

        parse_header(out, h.value)!;
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

    if (catch err = cookies_parse(&cookies, &self.headers))
    {
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
    if (catch err = value) return err~;

    return value.copy(localmem);
}


// 
// Context cookie cache
// 

fn void? Context.ensure_cookie_cache(&self)
{
    if (self.cookie_cache_ready) return;

    if (self.req == null) return CONTEXT_NOT_READY~;

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
    if (catch self.ensure_cookie_cache())
    {
        return false;
    }

    return self.cookie_cache.has(name);
}

fn Cookies* Context.cookies(&self)
{
    if (catch self.ensure_cookie_cache())
    {
        return null;
    }

    return &self.cookie_cache;
}


// 
// Set-Cookie builder
// 

struct CookieOptions
{
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

fn sz cookie_option_len(CookieOptions* opt)
{
    if (opt == null) return 0;

    sz n = 0;

    if (opt.path.len > 0)
    {
        n += "; Path=".len + opt.path.len;
    }

    if (opt.domain.len > 0)
    {
        n += "; Domain=".len + opt.domain.len;
    }

    if (opt.max_age.len > 0)
    {
        n += "; Max-Age=".len + opt.max_age.len;
    }

    if (opt.expires.len > 0)
    {
        n += "; Expires=".len + opt.expires.len;
    }

    if (opt.same_site.len > 0)
    {
        n += "; SameSite=".len + opt.same_site.len;
    }

    if (opt.http_only)
    {
        n += "; HttpOnly".len;
    }

    if (opt.secure)
    {
        n += "; Secure".len;
    }

    return n;
}


fn String? cookie_build(String name, String value, CookieOptions* opt = null)
{
    if (!name_valid(name)) return INVALID_COOKIE_NAME~;
    if (!value_valid(value)) return INVALID_COOKIE_VALUE~;
    if (!options_valid(opt)) return INVALID_COOKIE_OPTION~;

    sz n = name.len + 1 + value.len + cookie_option_len(opt);

    char* p = localmem.malloc(n + 1)!;
    sz pos = 0;

    pos = write_string(p[0:n], pos, name);
    p[pos++] = '=';
    pos = write_string(p[0:n], pos, value);

    if (opt != null && opt.path.len > 0)
    {
        pos = write_string(p[0:n], pos, "; Path=");
        pos = write_string(p[0:n], pos, opt.path);
    }

    if (opt != null && opt.domain.len > 0)
    {
        pos = write_string(p[0:n], pos, "; Domain=");
        pos = write_string(p[0:n], pos, opt.domain);
    }

    if (opt != null && opt.max_age.len > 0)
    {
        pos = write_string(p[0:n], pos, "; Max-Age=");
        pos = write_string(p[0:n], pos, opt.max_age);
    }

    if (opt != null && opt.expires.len > 0)
    {
        pos = write_string(p[0:n], pos, "; Expires=");
        pos = write_string(p[0:n], pos, opt.expires);
    }

    if (opt != null && opt.same_site.len > 0)
    {
        pos = write_string(p[0:n], pos, "; SameSite=");
        pos = write_string(p[0:n], pos, opt.same_site);
    }

    if (opt != null && opt.http_only)
    {
        pos = write_string(p[0:n], pos, "; HttpOnly");
    }

    if (opt != null && opt.secure)
    {
        pos = write_string(p[0:n], pos, "; Secure");
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
fn void? Context.cookie_set(&self, String name, String value, CookieOptions* opt = null) @maydiscard
{
    String? cookie = cookie_build(name, value, opt);
    if (catch err = cookie) return err~;
    defer localmem.free(cookie);

    self.set_cookie(cookie)!;
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
    if (cookies == null) return;
    
    cookies.dump();
}

// eof