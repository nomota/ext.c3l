// web.router.c3

module ext::aiohttp::web;

import ext::debug;

// HTTP request router — used internally by Application.
//
// Supports two pattern styles (same as Python aiohttp):
//   Static segment : "/users/me"
//   Named param    : "/users/{id}"
//   Regex param    : "/api/{ver:\d+}/items"
//   Wildcard tail  : "/static/{path:.*}"   (matches slashes too)
//
// Matching rules:
//   - Patterns are matched in registration order (first match wins).
//   - Static segments are compared byte-by-byte (case-sensitive).
//   - Named params capture one path segment (stops at '/').
//   - Regex params run a small built-in regex subset on the segment:
//       \d  digit
//       \w  word char [a-zA-Z0-9_]
//       \s  whitespace
//       .   any char (except '/' unless followed by *)
//       *   zero-or-more of previous
//       +   one-or-more of previous
//       ?   zero-or-one of previous
//       ^$  anchored automatically (whole segment must match)
//   - match_info is filled as a Headers* with {name → captured value} pairs.
//   - A trailing '/' in the pattern is optional: "/foo" matches "/foo/".
//
// WebSocket routes are stored separately (WsHandler fn type) and matched
// the same way, then dispatched with a separate lookup (router_match_ws).
//
// Memory:
//   All pattern strings are stored as slices of the original String passed
//   to router_add — the caller must keep those strings alive.
//   match_info entries are slices into the request path — no extra alloc.

//  constants 

const usz ROUTER_MAX_ROUTES   @private = 256;
const usz ROUTER_MAX_SEGMENTS @private = 32;   // max segments per pattern
const usz ROUTER_MAX_PARAMS   @private = 16;   // max {params} per pattern
const usz ROUTER_REGEX_MAX    @private = 64;   // max regex string length

//  type aliases 

alias RequestHandler = fn Response*?(Request*);
alias NextHandler    = fn Response*?(Request*);
alias MiddlewareFn   = fn Response*?(Request*, NextHandler next);
alias AppHook        = fn void?(Application*);
alias WsHandler      = fn void?(Request*, WebSocketResponse*);

//  segment kinds 

enum SegKind : char @private {
    STATIC,   // literal text
    PARAM,    // {name}    — one segment, no regex
    REGEX,    // {name:re} — one segment, regex constrained
    WILDCARD, // {name:.*} — matches rest of path including '/'
}

struct Segment @private {
    SegKind kind;
    String  text;   // static: literal. param/regex/wildcard: param name
    char[ROUTER_REGEX_MAX] re; // regex string (only REGEX kind)
    usz  re_len;
}

//  compiled route 

struct CompiledRoute @private {
    HttpMethod method;
    bool       is_ws;           // true = WsHandler, false = RequestHandler
    RequestHandler handler;     // valid when !is_ws
    WsHandler  ws_handler;      // valid when is_ws
    String     name;            // for url_for()
    String     raw_pattern;     // original pattern string (for url_for)

    Segment[ROUTER_MAX_SEGMENTS] segs;
    usz seg_count;

    // param names in order (parallel to matched captures)
    String[ROUTER_MAX_PARAMS] param_names;
    usz param_count;

    bool trailing_slash; // pattern ends with '/'
}

//  router 

struct RouterInner @private {
    CompiledRoute[ROUTER_MAX_ROUTES] routes;
    usz route_count;
}

//  match result 

struct RouteMatch {
    bool            found;
    RequestHandler  handler;
    WsHandler       ws_handler;
    bool            is_ws;
    // captured path params as slice pairs into the request path
    String[ROUTER_MAX_PARAMS] param_values;
    usz param_count;
    // parallel param names from the compiled route
    String[ROUTER_MAX_PARAMS] param_names;
}

//  private: mini regex engine 
//
// Matches a null-terminated regex string against a string slice.
// Only the subset documented in the module header is supported.
// Returns the number of chars consumed from s, or -1 on mismatch.

fn bool re_match_class(char c, char cls) @private @inline
{
    switch (cls) {
        case 'd': return c >= '0' && c <= '9';
        case 'w': return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                         (c >= '0' && c <= '9') || c == '_';
        case 's': return c == ' ' || c == '\t' || c == '\r' || c == '\n';
        default:  return c == cls; // literal escaped char
    }
}

// Try to match re[ri..] against s[si..si+slen).
// Returns matched length in s, or usz.max on failure.

fn usz re_match_one(char* re, usz ri, usz re_len, char sc, bool allow_slash) @private @inline
{
    if (ri >= re_len) return 0;
    char rc = re[ri];
    if (rc == '.') return (allow_slash || sc != '/') ? 1 : 0;
    if (rc == '\\' && ri + 1 < re_len) {
        return re_match_class(sc, re[ri + 1]) ? 1 : 0;
    }
    return (sc == rc) ? 1 : 0;
}

fn usz re_match(char* re, usz re_len, char* s, usz si, usz slen)
{
    usz ri = 0;
    while (ri < re_len) {
        char rc = re[ri];

        // determine current atom length (1 or 2 for \d etc.)
        usz atom_re_len = (rc == '\\' && ri + 1 < re_len) ? 2 : 1;

        // peek quantifier
        char quant = 0;
        if (ri + atom_re_len < re_len) {
            char q = re[ri + atom_re_len];
            if (q == '*' || q == '+' || q == '?') quant = q;
        }

        bool allow_slash = (rc == '.' && quant == '*'); // ".*" matches slashes

        if (quant == '*' || quant == '+') {
            usz min_count = (quant == '+') ? 1 : 0;
            usz count = 0;
            while (si + count < slen) {
                usz m = re_match_one(re, ri, re_len, s[si + count], allow_slash);
                if (m == 0) break;
                count++;
            }
            if (count < min_count) return (usz)-1;
            ri += atom_re_len + 1;
            si += count;
        } else if (quant == '?') {
            usz m = (si < slen) ? re_match_one(re, ri, re_len, s[si], allow_slash) : 0;
            ri += atom_re_len + 1;
            si += m;
        } else {
            if (si >= slen) return usz.max;
            usz m = re_match_one(re, ri, re_len, s[si], false);
            if (m == 0) return usz.max;
            ri += atom_re_len;
            si++;
        }
    }
    return si;
}

//  private: pattern compiler 

// Split path into segments at '/'. Returns segment count.
// Segments are stored as slices into path.
fn usz split_path(String path, String* out_segs, usz cap) @private
{
    warn("path: %s", path);
    usz count = 0;
    usz i = 0;
    if (i < path.len && path[i] == '/') i++; // skip leading '/'
    while (i < path.len && count < cap) {
        usz start = i;
        while (i < path.len && path[i] != '/') i++;
        if (i > start || (i == start && i < path.len)) {
            out_segs[count++] = path[start: i - start];
        }
        if (i < path.len) i++; // skip '/'
    }
    warn("count: %d", count);
    return count;
}

// Compile a route pattern string into a CompiledRoute.
fn void compile_pattern(CompiledRoute* r, String pattern) @private
{
    warn("compile_pattern(%s)", pattern);
    
    r.raw_pattern    = pattern;
    r.seg_count      = 0;
    r.param_count    = 0;
    r.trailing_slash = pattern.len > 1 && pattern[pattern.len - 1] == '/';

    // split on '/'
    String[ROUTER_MAX_SEGMENTS] path_segs;
    usz nseg = split_path(pattern, &path_segs[0], ROUTER_MAX_SEGMENTS);
    warn("nseg = %d", nseg);
    
    for (usz si = 0; si < nseg && r.seg_count < ROUTER_MAX_SEGMENTS; si++) {
        String seg = path_segs[si];
        Segment* s = &r.segs[r.seg_count++];

        if (seg.len >= 2 && seg[0] == '{' && seg[seg.len - 1] == '}') {
            // named param or regex param
            String inner = seg[1:seg.len - 2]; // strip { }

            // find ':' separator
            usz colon = inner.len;
            for (usz k = 0; k < inner.len; k++) {
                if (inner[k] == ':') { colon = k; break; }
            }

            String pname = inner[0:colon];
            if (r.param_count < ROUTER_MAX_PARAMS) {
                r.param_names[r.param_count++] = pname;
            }
            s.text = pname;

            if (colon < inner.len) {
                // regex variant
                String re_str = inner[colon + 1: inner.len - colon - 1];
                usz rlen = re_str.len < ROUTER_REGEX_MAX ? re_str.len : ROUTER_REGEX_MAX;
                for (usz k = 0; k < rlen; k++) s.re[k] = re_str[k];
                s.re_len = rlen;

                // wildcard shortcut: ".*"
                if (rlen == 2 && s.re[0] == '.' && s.re[1] == '*') {
                    s.kind = SegKind.WILDCARD;
                } else {
                    s.kind = SegKind.REGEX;
                }
            } else {
                s.kind   = SegKind.PARAM;
                s.re_len = 0;
            }
        } else {
            s.kind   = SegKind.STATIC;
            s.text   = seg;
            s.re_len = 0;
        }
    }
}

//  private: path matcher 

fn bool match_route(
    CompiledRoute*  r,
    HttpMethod      method,
    bool            want_ws,
    String          path,
    RouteMatch*     out,
) @private
{
    if (r.is_ws != want_ws) return false;
    if (!want_ws && r.method != method) return false;

    // split request path into segments
    String[ROUTER_MAX_SEGMENTS] req_segs;
    usz nreq = split_path(path, &req_segs[0], ROUTER_MAX_SEGMENTS);

    // allow trailing-slash flexibility:
    // pattern "/foo" matches "/foo" and "/foo/"
    // pattern "/foo/" matches "/foo/" and "/foo"
    usz npat = r.seg_count;

    if (nreq != npat) {
        // allow one-segment difference if it's just a trailing slash
        bool ok = false;
        if (nreq == npat + 1 && req_segs[nreq - 1].len == 0) ok = true;
        if (npat == nreq + 1 && r.trailing_slash) ok = true;
        if (!ok) return false;
        if (nreq > npat) nreq = npat; // ignore trailing empty segment
    }

    usz cap_idx = 0;

    for (usz si = 0; si < npat; si++) {
        Segment* ps = &r.segs[si];
        String   rs = (si < nreq) ? req_segs[si] : "";

        switch (ps.kind) {
            case SegKind.STATIC:
                if (rs.len != ps.text.len) return false;
                for (usz k = 0; k < rs.len; k++) {
                    if (rs[k] != ps.text[k]) return false;
                }

            case SegKind.PARAM:
                if (rs.len == 0) return false;
                if (cap_idx < ROUTER_MAX_PARAMS) {
                    out.param_values[cap_idx] = rs;
                    cap_idx++;
                }

            case SegKind.REGEX:
                if (rs.len == 0) return false;
                usz end = re_match(&ps.re[0], ps.re_len, rs.ptr, 0, rs.len);
                if (end != rs.len) return false; // must consume whole segment
                if (cap_idx < ROUTER_MAX_PARAMS) {
                    out.param_values[cap_idx] = rs;
                    cap_idx++;
                }

            case SegKind.WILDCARD:
                // consume rest of path (join remaining segments)
                // find start of this segment in the original path
                usz path_off = (usz)(rs.ptr - path.ptr);
                String tail = path[path_off: path.len - path_off];
                if (cap_idx < ROUTER_MAX_PARAMS) {
                    out.param_values[cap_idx] = tail;
                    cap_idx++;
                }
                si = npat; // done
                break;
        }
    }

    out.found        = true;
    out.is_ws        = r.is_ws;
    out.handler      = r.handler;
    out.ws_handler   = r.ws_handler;
    out.param_count  = cap_idx;
    for (usz i = 0; i < cap_idx; i++) {
        out.param_names[i] = r.param_names[i];
    }
    return true;
}

//  public API 

// Initialise a RouterInner (embedded in Router).
fn void router_init(RouterInner* ri)
{
    ri.route_count = 0;
}

// Add a regular HTTP route.
fn void? router_add(
    RouterInner*   ri,
    HttpMethod     method,
    String         pattern,
    RequestHandler handler,
    String         name = "",
)
{
    warn("router_add(%s, %s)", method, pattern);
    if (ri.route_count >= ROUTER_MAX_ROUTES) return aiohttp::CONNECTION_FAILED~;
    CompiledRoute* r = &ri.routes[ri.route_count++];
    
    compile_pattern(r, pattern);
    
warn("-");
    r.method   = method;
    r.is_ws    = false;
    r.handler  = handler;
    r.name     = name;
    r.ws_handler = null;
}

// Add a WebSocket route.
fn void? router_add_ws(
    RouterInner* ri,
    String       pattern,
    WsHandler    handler,
    String       name = "",
)
{
    if (ri.route_count >= ROUTER_MAX_ROUTES) return aiohttp::CONNECTION_FAILED~;
    CompiledRoute* r = &ri.routes[ri.route_count++];
    
    compile_pattern(r, pattern);
    
    r.method     = HttpMethod.GET; // WS always starts with GET
    r.is_ws      = true;
    r.ws_handler = handler;
    r.name       = name;
    r.handler    = null;
}

// Match an incoming request path against all registered routes.
// Returns true and fills *out on match, false on 404.
fn bool router_match(
    RouterInner* ri,
    HttpMethod   method,
    String       path,
    RouteMatch*  out,
)
{
    out.found = false;
    for (usz i = 0; i < ri.route_count; i++) {
        if (match_route(&ri.routes[i], method, false, path, out)) return true;
    }
    return false;
}

// Match a WebSocket upgrade request.
fn bool router_match_ws(
    RouterInner* ri,
    String       path,
    RouteMatch*  out,
)
{
    out.found = false;
    for (usz i = 0; i < ri.route_count; i++) {
        if (match_route(&ri.routes[i], HttpMethod.GET, true, path, out)) return true;
    }
    return false;
}

// Build match_info Headers from a RouteMatch (allocates entries via alloc).
// The returned Headers* must be freed by the caller.
fn Headers*? router_match_info(RouteMatch* m, Allocator alloc)
{
    localmem = alloc;
    
    Headers* h = localmem.alloc(Headers);
    h.count    = 0;
    h.capacity = m.param_count;

    if (m.param_count == 0) {
        h.entries = null;
        return h;
    }

    h.entries = localmem.malloc(m.param_count * Header.sizeof);
    for (usz i = 0; i < m.param_count; i++) {
        h.entries[i] = (Header){ m.param_names[i], m.param_values[i] };
        h.count++;
    }
    return h;
}

// Reverse URL generation: fill in {params} from a Headers* key-value map.
// Returns "" if route name not found or params are missing.
fn String router_url_for(
    RouterInner* ri,
    String       route_name,
    Headers*     params,
    Allocator    alloc,
)
{
    localmem = alloc;
    
    // find named route
    CompiledRoute* found = null;
    for (usz i = 0; i < ri.route_count; i++) {
        if (ri.routes[i].name.len > 0 && ri.routes[i].name == route_name) {
            found = &ri.routes[i];
            break;
        }
    }
    if (found == null) return "";

    // build path by walking segments
    char[1024] buf;
    OBuf b = { &buf[0], 1024, 0 };
    
    usz pi = 0; // param index

    b.putc('/');
    for (usz si = 0; si < found.seg_count; si++) {
        if (si > 0) b.putc('/');
        Segment* seg = &found.segs[si];
        switch (seg.kind) {
            case SegKind.STATIC:
                b.put(seg.text);
            case SegKind.PARAM:
            case SegKind.REGEX:
            case SegKind.WILDCARD:
                // look up param name in provided Headers
                String val = "";
                if (params != null) {
                    for (usz k = 0; k < params.count; k++) {
                        if (params.entries[k].name == seg.text) {
                            val = params.entries[k].value;
                            break;
                        }
                    }
                }
                b.put(val);
                pi++;
        }
    }

    usz j = b.cursor;
    if (found.trailing_slash && (j == 0 || buf[j - 1] != '/')) b.putc('/');
    
    return b.str().copy(localmem);
}
