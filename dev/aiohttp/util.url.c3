// util.url.c3

module ext::aiohttp;

import ext::mem;

tlocal LocalAllocator localmem = {};

// URL parsing, serialization, and percent-encoding utilities.
//
// url_parse()       : zero-copy — all Url fields are slices into the original raw string.
// pct_encode/decode : allocate via a caller-supplied allocator.
// Url.to_string()   : allocates via a caller-supplied allocator; caller must free.
// query_build()     : builds "k=v&k2=v2" from a Headers* params list.

// private helpers

const char[16] PCT_HEX @private = "0123456789ABCDEF";

// True for RFC 3986 unreserved characters: ALPHA / DIGIT / "-" / "." / "_" / "~"
fn bool pct_unreserved(char c) @private @inline
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') ||
           c == '-' || c == '_' || c == '.' || c == '~';
}

// Hex character to numeric value (0–15). Returns 0 for invalid input.
fn uint hex_nibble(char c) @private @inline
{
    if (c >= '0' && c <= '9') return (uint)(c - '0');
    if (c >= 'A' && c <= 'F') return (uint)(c - 'A') + 10;
    if (c >= 'a' && c <= 'f') return (uint)(c - 'a') + 10;
    return 0;
}

// Zero-copy substring: raw[start .. end-1).
fn String str_sub(String s, usz start, usz end) @private @inline
{
    return s[start:end - start];
}

// Zero-copy suffix: raw[start .. end-of-string-1).
fn String str_from(String s, usz start) @private @inline
{
    return s[start:s.len - start];
}

// Copy n bytes from src into dst.
fn void raw_copy(char* dst, char* src, usz n) @private @inline
{
    mem::copy(dst, src, n);
}

// Default port for well-known schemes.
fn ushort scheme_default_port(String scheme) @private
{
    if (scheme == "https" || scheme == "wss") return 443;
    if (scheme == "http"  || scheme == "ws")  return 80;
    if (scheme == "ftp")                       return 21;
    return 0;
}

// Parse an ASCII decimal port string. Returns INVALID_URL on bad input.
fn ushort? parse_port(String s) @private
{
    if (s.len == 0 || s.len > 5) return INVALID_URL~;
    uint p = 0;
    for (usz i = 0; i < s.len; i++) {
        char c = s[i];
        if (c < '0' || c > '9') return INVALID_URL~;
        p = p * 10 + (uint)(c - '0');
    }
    if (p > 65535) return INVALID_URL~;
    return (ushort)p;
}

// percent encoding / decoding

// Percent-encode s per RFC 3986.
// safe_slash: keep '/' unencoded — use when encoding a full path.
// Returns a new allocated string. The caller owns the result.
fn String pct_encode(Allocator alloc, String s, bool safe_slash = false) @public
{
    localmem = alloc;
    
    usz out_len = 0;
    foreach (c : s) {
        out_len += (pct_unreserved(c) || (safe_slash && c == '/')) ? 1 : 3;
    }
    if (out_len == s.len) return s;

    char* buf = localmem.malloc(out_len);
    usz j = 0;
    foreach (c : s) {
        if (pct_unreserved(c) || (safe_slash && c == '/')) {
            buf[j++] = c;
        } else {
            uint b = (uint)c;
            buf[j++] = '%';
            buf[j++] = PCT_HEX[(b >> 4) & 0xF];
            buf[j++] = PCT_HEX[b & 0xF];
        }
    }
    return (String) buf[0:out_len];
}

// Percent-decode s.
// plus_space: convert '+' to ' ' — use when decoding query string values.
// Returns a new allocated string. The caller owns the result.
fn String pct_decode(Allocator alloc, String s, bool plus_space = false) @public
{
    localmem = alloc;

    // calculate output length without allocating
    usz out_len = 0;
    for (usz i = 0; i < s.len; i++) {
        if (s[i] == '%' && i + 2 < s.len) i += 2;
        out_len++;
    }
    if (out_len == s.len) return s;

    char* buf = localmem.malloc(out_len);
    usz j = 0;
    for (usz i = 0; i < s.len; i++) {
        char c = s[i];
        if (c == '%' && i + 2 < s.len) {
            buf[j++] = (char)((hex_nibble(s[i + 1]) << 4) | hex_nibble(s[i + 2]));
            i += 2;
        } else if (plus_space && c == '+') {
            buf[j++] = ' ';
        } else {
            buf[j++] = c;
        }
    }
    return (String) buf[0:out_len];
}

// URL parsing

// Parse a URL string into a Url struct.
// All returned String fields are zero-copy slices into raw — raw must outlive the Url.
// Returns INVALID_URL on malformed input.
//
// Supported format:
//   scheme "://" [userinfo "@"] host [":" port] ["/" path] ["?" query] ["#" fragment]
//
// userinfo is parsed and silently discarded (use BasicAuth for credentials).
fn Url? url_parse(String raw) @public
{
    Url url;
    url.raw = raw;

    // scheme
    usz si = 0;
    while (si < raw.len && raw[si] != ':') si++;

    // require "://" after scheme name
    if (si == 0 || si + 2 >= raw.len ||
        raw[si + 1] != '/' || raw[si + 2] != '/') {
        return INVALID_URL~;
    }
    url.scheme = str_sub(raw, 0, si);

    usz pos = si + 3; // skip "://"

    // authority (host[:port])
    usz auth_start = pos;
    while (pos < raw.len &&
           raw[pos] != '/' && raw[pos] != '?' && raw[pos] != '#') {
        pos++;
    }
    String authority = str_sub(raw, auth_start, pos);

    // strip "userinfo@" — scan for the last '@' inside authority
    usz at_pos = 0;
    bool has_at = false;
    for (usz i = 0; i < authority.len; i++) {
        if (authority[i] == '@') { at_pos = i; has_at = true; }
    }
    String hostport = has_at ? str_from(authority, at_pos + 1) : authority;

    if (hostport.len == 0) return INVALID_URL~;

    // IPv6 literal: "[::1]" or "[::1]:port"
    if (hostport[0] == '[') {
        usz close = 1;
        while (close < hostport.len && hostport[close] != ']') close++;
        if (close >= hostport.len) return INVALID_URL~;

        url.host = str_sub(hostport, 1, close); // strip brackets
        if (close + 1 < hostport.len && hostport[close + 1] == ':') {
            url.port = parse_port(str_from(hostport, close + 2))!;
        } else {
            url.port = scheme_default_port(url.scheme);
        }
    } else {
        // find last ':' to separate host from port
        usz colon = hostport.len; // sentinel: no colon found
        for (usz i = 0; i < hostport.len; i++) {
            if (hostport[i] == ':') colon = i;
        }
        if (colon < hostport.len) {
            url.host = str_sub(hostport, 0, colon);
            url.port = parse_port(str_from(hostport, colon + 1))!;
        } else {
            url.host = hostport;
            url.port = scheme_default_port(url.scheme);
        }
    }

    if (url.host.len == 0) return INVALID_URL~;

    // path
    if (pos < raw.len && raw[pos] == '/') {
        usz path_start = pos;
        while (pos < raw.len && raw[pos] != '?' && raw[pos] != '#') pos++;
        url.path = str_sub(raw, path_start, pos);
    } else {
        url.path = "/";
    }

    // query
    if (pos < raw.len && raw[pos] == '?') {
        pos++; // skip '?'
        usz q_start = pos;
        while (pos < raw.len && raw[pos] != '#') pos++;
        url.query = str_sub(raw, q_start, pos);
    }

    // fragment
    if (pos < raw.len && raw[pos] == '#') {
        url.fragment = str_from(raw, pos + 1);
    }

    return url;
}

// URL serialization

// Rebuild the URL as a string.
// Default ports (80/443/21) are omitted. Empty query/fragment are omitted.
// The returned string is null-terminated. The caller must free it.
fn String Url.to_string(&self, Allocator alloc)
{
    localmem = alloc;
    
    // Format port digits (if non-default)
    char[6] port_buf;
    usz port_len = 0;
    bool emit_port = self.port != 0 && self.port != scheme_default_port(self.scheme);
    if (emit_port) {
        uint p = (uint)self.port;
        do {
            port_buf[port_len++] = (char)('0' + p % 10);
            p /= 10;
        } while (p > 0);
        // reverse digits
        usz pi = 0;
        usz pj = port_len - 1;
        while (pi < pj) {
            char tmp = port_buf[pi];
            port_buf[pi] = port_buf[pj];
            port_buf[pj] = tmp;
            pi++;
            pj--;
        }
    }

    usz path_len = self.path.len > 0 ? self.path.len : 1; // at least "/"

    usz total = self.scheme.len + 3  // "://"
              + self.host.len
              + (emit_port ? 1 + port_len : 0)  // ":port"
              + path_len
              + (self.query.len    > 0 ? 1 + self.query.len    : 0)   // "?query"
              + (self.fragment.len > 0 ? 1 + self.fragment.len : 0);  // "#fragment"

    char* buf = localmem.malloc(total + 1);
    usz j = 0;

    // scheme + "://"
    raw_copy(buf + j, self.scheme.ptr, self.scheme.len);
    j += self.scheme.len;
    buf[j++] = ':'; buf[j++] = '/'; buf[j++] = '/';

    // host
    raw_copy(buf + j, self.host.ptr, self.host.len);
    j += self.host.len;

    // port
    if (emit_port) {
        buf[j++] = ':';
        raw_copy(buf + j, port_buf[0:port_len].ptr, port_len);
        j += port_len;
    }

    // path (always at least "/")
    if (self.path.len > 0) {
        raw_copy(buf + j, self.path.ptr, self.path.len);
        j += self.path.len;
    } else {
        buf[j++] = '/';
    }

    // query
    if (self.query.len > 0) {
        buf[j++] = '?';
        raw_copy(buf + j, self.query.ptr, self.query.len);
        j += self.query.len;
    }

    // fragment
    if (self.fragment.len > 0) {
        buf[j++] = '#';
        raw_copy(buf + j, self.fragment.ptr, self.fragment.len);
        j += self.fragment.len;
    }

    buf[j] = 0;
    return (String) buf[0:j];
}

// query string builder

// Build a percent-encoded query string from a Headers* params list.
// Output format: "key=value&key2=value2" (no leading '?').
// Both keys and values are percent-encoded (RFC 3986 unreserved safe).
// Returns "" if params is null or empty.
fn String query_build(Allocator alloc, Headers* params)
{
    localmem = alloc;

    if (params == null || params.count == 0) return "";

    // First pass: calculate total encoded output length.
    usz total = 0;
    for (usz i = 0; i < params.count; i++) {
        Header* h = &params.entries[i];
        if (i > 0) total++; // '&'
        foreach (c : h.name)  total += pct_unreserved(c) ? 1 : 3;
        total++; // '='
        foreach (c : h.value) total += pct_unreserved(c) ? 1 : 3;
    }

    char* buf = localmem.malloc(total + 1);
    usz j = 0;

    // Second pass: write encoded output.
    for (usz i = 0; i < params.count; i++) {
        Header* h = &params.entries[i];
        if (i > 0) buf[j++] = '&';

        foreach (c : h.name) {
            if (pct_unreserved(c)) {
                buf[j++] = c;
            } else {
                uint b = (uint)c;
                buf[j++] = '%';
                buf[j++] = PCT_HEX[(b >> 4) & 0xF];
                buf[j++] = PCT_HEX[b & 0xF];
            }
        }

        buf[j++] = '=';

        foreach (c : h.value) {
            if (pct_unreserved(c)) {
                buf[j++] = c;
            } else {
                uint b = (uint)c;
                buf[j++] = '%';
                buf[j++] = PCT_HEX[(b >> 4) & 0xF];
                buf[j++] = PCT_HEX[b & 0xF];
            }
        }
    }

    buf[j] = 0;
    return (String) buf[0:j];
}
