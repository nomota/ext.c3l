// application.c3

module ext::aiohttp;

import std::io;
import ext::mem;
import ext::debug;


// 
// Application app
// 

struct Application {
    Router router;
    MiddlewareStack middlewares;
}


// 
// Lifecycle
// 

fn void Application.init(&self)
{
    self.router.init();
    self.middlewares.init();
}

fn void Application.deinit(&self)
{
    self.router.free();
    self.middlewares.free();
}

fn void Application.clear(&self)
{
    self.router.clear();
    self.middlewares.clear();
}

fn Application*? application_new()
{
    Application* app = localmem.alloc(Application)!;
    app.init();
    return app;
}

fn void Application.free(&self)
{
    self.deinit();
    localmem.free(self);
}


// 
// Middleware API
// 

fn void Application.use(&self, Middleware middleware)
{
    self.middlewares.use(middleware);
}

fn void? Application.use_path(&self, String path, Middleware middleware)
{
    self.middlewares.use_path(path, middleware)!;
}


// 
// Route API
// 

fn void? Application.add(&self, String method, String path, Handler handler)
{
    self.router.add(method, path, handler)!;
}

fn void? Application.get(&self, String path, Handler handler)
{
    self.router.get(path, handler)!;
}

fn void? Application.post(&self, String path, Handler handler)
{
    self.router.post(path, handler)!;
}

fn void? Application.put(&self, String path, Handler handler)
{
    self.router.put(path, handler)!;
}

fn void? Application.patch(&self, String path, Handler handler)
{
    self.router.patch(path, handler)!;
}

fn void? Application.delete(&self, String path, Handler handler)
{
    self.router.delete(path, handler)!;
}

fn void? Application.options(&self, String path, Handler handler)
{
    self.router.options(path, handler)!;
}

fn void? Application.head(&self, String path, Handler handler)
{
    self.router.head(path, handler)!;
}


// 
// Mount child app
// 

// Mounts all child routes under prefix.
//
// Example:
//   api.get("/users", handler)
//   app.route("/api", &api)!!
//
// Result:
//   GET /api/users
//
// This mounts routes only.
// Middleware inheritance/composition can be added later.
fn void? Application.route(&self, String prefix, Application* child)
{
    if (child == null) return INVALID_ARG~;

    self.router.mount(prefix, &child.router)!;
}


// 
// Built-in fallback handlers
// 

fn Response* http_not_found_handler(Context* c)
{
    return c.not_found();
}

fn Response* http_method_not_allowed_handler(Context* c)
{
    c.status(405);
    return c.text("405 Method Not Allowed");
}

fn Response* http_internal_error_handler(Context* c)
{
    return c.internal_error();
}


// 
// Dispatch
// 

fn Response* Application.dispatch_match(&self, Request* req, RouteMatch* match)
{
    Context* c = context_new_with_params(req, &match.params);
    defer context_free(c);

    Response* res = middleware_run(&self.middlewares, c, match.handler);

    // context_free(c) would free c.res.
    // Therefore detach response ownership before Context is freed.
    if (res == c.res) {
        c.res = null;
    }

    return res;
}

fn Response* Application.dispatch_error(&self, Request* req, Handler fallback)
{
    Context* c = context_new(req);
    defer context_free(c);

    Response* res = middleware_run(&self.middlewares, c, fallback);

    if (res == c.res) {
        c.res = null;
    }

    return res;
}

// Main Hono-like entrypoint.
//
// Caller owns returned Response* and must call response_free().
fn Response* Application.fetch(&self, Request* req)
{
    if (req == null) {
        Response* res = response_internal_error();
        return res;
    }

    RouteMatch? m = self.router.match(req.method, req.path);

    if (catch err = m) {
        if (err == METHOD_NOT_ALLOWED) {
            return self.dispatch_error(req, &http_method_not_allowed_handler);
        }

        if (err == ROUTE_NOT_FOUND) {
            return self.dispatch_error(req, &http_not_found_handler);
        }

        return self.dispatch_error(req, &http_internal_error_handler);
    }

    Response* res = self.dispatch_match(req, &m);
    m.free();

    return res;
}


// 
// Convenience: parse raw request and fetch
// 

// Parses a raw HTTP request and dispatches it.
// Caller owns returned Response*.
fn Response* Application.fetch_raw(&self, char[] raw)
{
    Request*? req = request_parse(raw);

    if (catch err = req) {
        if (err == REQUEST_TOO_LARGE) {
            Response* res = response_empty(413);
            res.set_text("413 Payload Too Large");
            return res;
        }

        Response* res = response_empty(400);
        res.set_text("400 Bad Request");
        return res;
    }

    defer request_free(req);

    return self.fetch(req);
}


// 
// Debug
// 

fn void Application.dump(&self)
{
    io::printfn("routes:");
    self.router.dump();

    io::printfn("middlewares:");
    self.middlewares.dump();
}