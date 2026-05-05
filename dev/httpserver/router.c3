// router.c3

module ext::httpserver;

import std::io;
import std::collections::list;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef ROUTE_NOT_FOUND;
faultdef METHOD_NOT_ALLOWED;
faultdef INVALID_ROUTE_PATH;


// 
// Handler
// 

// Context is defined later in context.c3.
// C3 module-level symbols can be resolved across files.
alias Handler = fn Response*(Context* c);


// 
// Route
// 

struct Route {
    String method;
    String path;
    Handler handler;
}

struct Router {
    List{Route} routes;
}

struct RouteMatch {
    Handler handler;
    Params params;
}


// 
// Internal helpers
// 

fn bool route_path_valid(String path)
{
    if (path.len == 0) return false;
    if (path[0] != '/') return false;
    return true;
}

fn bool method_eq(String a, String b)
{
    return str_iequals(a, b);
}

fn bool is_route_param(String seg)
{
    return seg.len > 1 && seg[0] == ':';
}

fn bool is_route_splat(String seg)
{
    return seg == "*";
}

fn String route_param_name(String seg)
{
    // ":id" -> "id"
    return seg[1:seg.len - 1];
}

fn isz find_slash_from(String s, usz start)
{
    for (usz i = start; i < s.len; i++) {
        if (s[i] == '/') return (isz)i;
    }

    return -1;
}

// Reads next path segment.
//
// Input:
//   path = "/users/123"
//   pos  = 1
//
// Output:
//   "users", pos = 7
//
// If no more segment exists, returns NOT_FOUND.
fn String? next_segment(String path, usz* pos)
{
    if (*pos >= path.len) {
        return NOT_FOUND~;
    }

    usz start = *pos;

    isz slash = find_slash_from(path, start);
    if (slash < 0) {
        *pos = path.len;
        return path[start:path.len - start];
    }

    usz end = (usz)slash;
    *pos = end + 1;

    return path[start:end - start];
}

// Returns the rest of path from current segment position.
//
// Used by splat route:
//
//   pattern: /files/*
//   path:    /files/css/app.css
//   splat:   css/app.css
fn String rest_path(String path, usz pos)
{
    if (pos >= path.len) return "";

    // If pos points to a slash, skip it.
    if (path[pos] == '/') {
        pos++;
    }

    if (pos >= path.len) return "";

    return path[pos:path.len - pos];
}


// 
// Route lifecycle
// 

fn void Route.free(&self)
{
    str_free(self.method);
    str_free(self.path);

    self.method = "";
    self.path = "";
    self.handler = null;
}

fn void RouteMatch.free(&self)
{
    self.params.free();
}


// 
// Router lifecycle
// 

fn void Router.init(&self)
{
    self.routes.init(localmem);
}

fn void Router.free(&self)
{
    for (usz i = 0; i < self.routes.len(); i++) {
        self.routes[i].free();
    }

    self.routes.free();
}

fn void Router.clear(&self)
{
    for (usz i = 0; i < self.routes.len(); i++) {
        self.routes[i].free();
    }

    self.routes.clear();
}

fn Router* router_new()
{
    Router* r = localmem.alloc(Router);
    r.init();
    return r;
}

fn void router_free(Router* r)
{
    if (r == null) return;

    r.free();
    localmem.free(r);
}


// 
// Add routes
// 

fn void? Router.add(&self, String method, String path, Handler handler)
{
    if (!route_path_valid(path)) {
        return INVALID_ROUTE_PATH~;
    }

    self.routes.push((Route){
        .method = str_clone(method),
        .path = str_clone(path),
        .handler = handler,
    });
}

fn void? Router.get(&self, String path, Handler handler)
{
    self.add("GET", path, handler)!;
}

fn void? Router.post(&self, String path, Handler handler)
{
    self.add("POST", path, handler)!;
}

fn void? Router.put(&self, String path, Handler handler)
{
    self.add("PUT", path, handler)!;
}

fn void? Router.patch(&self, String path, Handler handler)
{
    self.add("PATCH", path, handler)!;
}

fn void? Router.delete(&self, String path, Handler handler)
{
    self.add("DELETE", path, handler)!;
}

fn void? Router.options(&self, String path, Handler handler)
{
    self.add("OPTIONS", path, handler)!;
}

fn void? Router.head(&self, String path, Handler handler)
{
    self.add("HEAD", path, handler)!;
}


// 
// Path matching
// 

fn bool route_match_exact(String pattern, String path)
{
    return pattern == path;
}

// Matches one route pattern against request path.
//
// Supported:
//   /
//   /users
//   /users/:id
//   /files/*
//
// On success, fills params.
// On failure, clears params before returning false.
fn bool route_match_path(String pattern, String path, Params* params)
{
    params.clear();

    if (pattern == path) {
        return true;
    }

    if (pattern == "/" || path == "/") {
        return false;
    }

    usz ppos = 0;
    usz rpos = 0;

    // Both must start with slash.
    if (pattern.len == 0 || path.len == 0) return false;
    if (pattern[0] != '/' || path[0] != '/') return false;

    ppos = 1;
    rpos = 1;

    while (true) {
        bool pattern_done = ppos >= pattern.len;
        bool path_done = rpos >= path.len;

        if (pattern_done && path_done) {
            return true;
        }

        if (pattern_done && !path_done) {
            break;
        }

        String? pseg_opt = next_segment(pattern, &ppos);
        if (catch err = pseg_opt) {
            break;
        }

        String pseg = pseg_opt;

        // Wildcard splat consumes the rest of path.
        if (is_route_splat(pseg)) {
            String rest = rest_path(path, rpos);
            if (catch params.set_splat_decoded(rest)) {
                break;
            }
            return true;
        }

        if (path_done) {
            break;
        }

        String? rseg_opt = next_segment(path, &rpos);
        if (catch err = rseg_opt) {
            break;
        }

        String rseg = rseg_opt;

        if (is_route_param(pseg)) {
            String name = route_param_name(pseg);

            if (!param_name_valid(name)) {
                break;
            }

            if (catch params.put_decoded(name, rseg)) {
                break;
            }
            continue;
        }

        if (pseg != rseg) {
            break;
        }
    }

    params.clear();
    return false;
}


// 
// Match route
// 

fn RouteMatch? Router.match(&self, String method, String path)
{
    bool path_matched = false;

    for (usz i = 0; i < self.routes.len(); i++) {
        Route* route = &self.routes[i];

        Params params;
        params.init();

        bool matched = route_match_path(route.path, path, &params);

        if (!matched) {
            params.free();
            continue;
        }

        path_matched = true;

        if (!method_eq(route.method, method)) {
            params.free();
            continue;
        }

        return (RouteMatch){
            .handler = route.handler,
            .params = params,
        };
    }

    if (path_matched) {
        return METHOD_NOT_ALLOWED~;
    }

    return ROUTE_NOT_FOUND~;
}

fn bool Router.has_route(&self, String method, String path)
{
    RouteMatch? m = self.match(method, path);
    if (catch err = m) {
        return false;
    }

    m.free();
    return true;
}


// 
// Mount child router
// 

fn String join_paths(String prefix, String path)
{
    if (prefix == "/") {
        return str_clone(path);
    }

    if (path == "/") {
        return str_clone(prefix);
    }

    bool prefix_slash = prefix[prefix.len - 1] == '/';
    bool path_slash = path[0] == '/';

    usz extra = 0;

    if (!prefix_slash && !path_slash) {
        extra = 1;
    }

    usz n = prefix.len + path.len + extra;
    char* out = localmem.malloc(n + 1);

    usz pos = 0;

    out[pos:prefix.len] = prefix[0:prefix.len];
    pos += prefix.len;

    if (extra == 1) {
        out[pos++] = '/';
    }

    if (prefix_slash && path_slash) {
        out[pos:path.len - 1] = path[1:path.len - 1];
        pos += path.len - 1;
    } else {
        out[pos:path.len] = path[0:path.len];
        pos += path.len;
    }

    out[pos] = 0;
    return (String)out[0:pos];
}

fn void? Router.mount(&self, String prefix, Router* child)
{
    if (!route_path_valid(prefix)) {
        return INVALID_ROUTE_PATH~;
    }

    for (usz i = 0; i < child.routes.len(); i++) {
        Route* r = &child.routes[i];

        String joined = join_paths(prefix, r.path);
        defer localmem.free(joined);

        self.add(r.method, joined, r.handler)!;
    }
}


// 
// Debug
// 

fn void Router.dump(&self)
{
    for (usz i = 0; i < self.routes.len(); i++) {
        Route* r = &self.routes[i];
        io::printfn("%s %s", r.method, r.path);
    }
}