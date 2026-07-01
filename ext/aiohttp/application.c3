// application.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import c::errno;
import ext::mem;


// Application app

struct Application
{
    Router router;
    MiddlewareStack middlewares;
    NotFoundHandler not_found_handler;
    ErrorHandler error_handler;
}


// Lifecycle

fn void Application.init(&self)
{
    self.router.init();
    self.middlewares.init();

    self.not_found_handler = null;
    self.error_handler = null;
}

fn void Application.deinit(&self)
{
    self.router.free();
    self.middlewares.free();

    self.not_found_handler = null;
    self.error_handler = null;
}

fn void Application.clear(&self)
{
    self.router.clear();
    self.middlewares.clear();

    self.not_found_handler = null;
    self.error_handler = null;
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


// Middleware API

fn void Application.use(&self, Middleware middleware)
{
    self.middlewares.use(middleware);
}

fn void? Application.use_path(&self, String path, Middleware middleware) @maydiscard
{
    self.middlewares.use_path(path, middleware)!;
}


// Route API

fn void? Application.add(&self, String method, String path, Handler handler) @maydiscard
{
    self.router.add(method, path, handler)!;
}

fn void? Application.get(&self, String path, Handler handler) @maydiscard
{
    self.router.get(path, handler)!;
}

fn void? Application.post(&self, String path, Handler handler) @maydiscard
{
    self.router.post(path, handler)!;
}

fn void? Application.put(&self, String path, Handler handler) @maydiscard
{
    self.router.put(path, handler)!;
}

fn void? Application.patch(&self, String path, Handler handler) @maydiscard
{
    self.router.patch(path, handler)!;
}

fn void? Application.delete(&self, String path, Handler handler) @maydiscard
{
    self.router.delete(path, handler)!;
}

fn void? Application.options(&self, String path, Handler handler) @maydiscard
{
    self.router.options(path, handler)!;
}

fn void? Application.head(&self, String path, Handler handler) @maydiscard
{
    self.router.head(path, handler)!;
}


// Mount child app

fn void? Application.mount(&self, String prefix, Application* child) @maydiscard
{
    if (child == null) return errno::E_INVALID_ARG~;

    self.router.mount(prefix, &child.router)!;
}


// Built-in fallback handlers

fn Response*? not_found_handler(Context* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    return c.not_found("route")!;
}

fn Response*? method_not_allowed_handler(Context* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.status(405)!;
    return c.text("405 Method Not Allowed")!;
}


// Internal error response helpers

fn Response*? status_response(ushort status, String body) @local
{
    Response* res = response_empty(status)!;
    defer (catch err) response_free(res);

    res.set_text(body)!;

    return res;
}

fn Response*? bad_request_response() @local
{
    return status_response(400, "400 Bad Request")!;
}

fn Response*? payload_too_large_response() @local
{
    return status_response(413, "413 Payload Too Large")!;
}

fn Response*? internal_error_response() @local
{
    return status_response(500, "500 Internal Server Error")!;
}

fn bool is_bad_request_error(fault err) @local
{
    return err == BAD_REQUEST ||
           err == INVALID_METHOD ||
           err == INVALID_VERSION ||
           err == INVALID_HEADER ||
           err == BODY_INCOMPLETE ||
           err == INVALID_CHUNKED_BODY ||
           err == CHUNKED_BODY_INCOMPLETE;
}


// Response ownership

fn Response* detach_response(Context* c, Response* res) @local
{
    if (c != null && res == c.res) c.res = null;

    return res;
}


// Error dispatch

fn Response*? Application.dispatch_context_error(&self, Context* c, fault dispatch_error)
{
    if (c == null) return response_internal_error()!;

    Response*? res = self.handle_error(c, dispatch_error);

    if (catch err = res)
    {
        return response_internal_error()!;
    }

    return detach_response(c, res);
}


// Matched route dispatch

fn Response*? Application.dispatch_match(&self, Request* req, RouteMatch* match)
{
    if (req == null) return response_internal_error()!;
    if (match == null) return response_internal_error()!;

    Context* c = context_new_with_params(req, &match.params)!;
    defer context_free(c);

    Response*? res = middleware_run(&self.middlewares, c, match.handler);

    if (catch err = res)
    {
        return self.dispatch_context_error(c, err)!;
    }

    return detach_response(c, res);
}


// Fallback dispatch

fn Response*? Application.dispatch_fallback(&self, Request* req, Handler fallback)
{
    if (req == null) return response_internal_error()!;

    Context* c = context_new(req)!;
    defer context_free(c);

    Response*? res = middleware_run(&self.middlewares, c, fallback);

    if (catch err = res)
    {
        return self.dispatch_context_error(c, err)!;
    }

    return detach_response(c, res);
}

fn Response*? Application.dispatch_not_found(&self, Request* req)
{
    Handler handler = self.not_found_handler;

    if (handler == null)
    {
        handler = &not_found_handler;
    }

    return self.dispatch_fallback(req, handler)!;
}

fn Response*? Application.dispatch_method_not_allowed(&self, Request* req)
{
    return self.dispatch_fallback(req, &method_not_allowed_handler)!;
}

fn Response*? Application.dispatch_router_error(&self, Request* req, fault router_error)
{
    if (req == null) return response_internal_error()!;

    Context* c = context_new(req)!;
    defer context_free(c);

    return self.dispatch_context_error(c, router_error)!;
}


// HEAD fallback

fn Response*? Application.dispatch_head_fallback(&self, Request* req, fault match_error)
{
    if (!str_iequals(req.method, "HEAD")) return match_error~;

    if (match_error != ROUTE_NOT_FOUND && match_error != METHOD_NOT_ALLOWED)
    {
        return match_error~;
    }

    RouteMatch? get_match = self.router.match("GET", req.path);

    if (catch err = get_match)
    {
        return match_error~;
    }

    defer get_match.free();

    return self.dispatch_match(req, &get_match)!;
}


// Main Hono-like entrypoint.
//
// Caller owns returned Response* and must call response_free().

fn Response*? Application.fetch(&self, Request* req)
{
    if (req == null) return response_internal_error()!;

    RouteMatch? match = self.router.match(req.method, req.path);

    if (catch err = match)
    {
        if (str_iequals(req.method, "HEAD") && (err == ROUTE_NOT_FOUND || err == METHOD_NOT_ALLOWED))
        {
            Response*? head_res = self.dispatch_head_fallback(req, err);

            if (try head_res)
            {
                return head_res;
            }
        }

        if (err == METHOD_NOT_ALLOWED)
        {
            return self.dispatch_method_not_allowed(req)!;
        }

        if (err == ROUTE_NOT_FOUND)
        {
            return self.dispatch_not_found(req)!;
        }

        return self.dispatch_router_error(req, err)!;
    }

    defer match.free();

    return self.dispatch_match(req, &match)!;
}


// Convenience: parse raw request and fetch

// Parses a raw HTTP request and dispatches it.
// Caller owns returned Response*.

fn Response*? Application.fetch_raw(&self, char[] raw)
{
    Request*? req = request_parse(raw);

    if (catch err = req)
    {
        if (err == REQUEST_TOO_LARGE)
        {
            return payload_too_large_response()!;
        }

        return bad_request_response()!;
    }

    defer request_free(req);

    Response*? res = self.fetch(req);

    if (catch err = res)
    {
        if (err == REQUEST_TOO_LARGE)
        {
            return payload_too_large_response()!;
        }

        if (is_bad_request_error(err))
        {
            return bad_request_response()!;
        }

        return internal_error_response()!;
    }

    return res;
}


fn bool is_websocket_handshake_error(fault err) @local
{
    return err == WS_BAD_HANDSHAKE ||
           err == WS_UNSUPPORTED_VERSION ||
           err == WS_INVALID_KEY;
}

fn Response*? Application.handle_context_dispatch_error(&self, Context* c, fault dispatch_error)
{
    if (is_websocket_handshake_error(dispatch_error)) {
        return dispatch_error~;
    }

    Response*? result = self.handle_error(c, dispatch_error);

    if (catch err = result) {
        Response* fallback = response_internal_error()!;
        c.with_response(fallback);
        return c.res;
    }

    Response* res = result;

    if (res == null) return c.res;
    if (res != c.res) c.with_response(res);

    return c.res;
}

fn Response*? Application.dispatch_match_context(&self, Context* c, RouteMatch* match)
{
    if (c == null || c.req == null) return CONTEXT_NOT_READY~;
    if (match == null) return CONTEXT_NOT_READY~;

    c.set_params(&match.params)!;

    Response*? result = middleware_run(&self.middlewares, c, match.handler);

    if (catch err = result) {
        return self.handle_context_dispatch_error(c, err)!;
    }

    Response* res = result;

    if (res == null) return c.res;
    if (res != c.res) c.with_response(res);

    return c.res;
}

fn Response*? Application.dispatch_fallback_context(&self, Context* c, Handler fallback)
{
    if (c == null || c.req == null) return CONTEXT_NOT_READY~;
    if (fallback == null) return CONTEXT_NOT_READY~;

    Response*? result = middleware_run(&self.middlewares, c, fallback);

    if (catch err = result) {
        return self.handle_context_dispatch_error(c, err)!;
    }

    Response* res = result;

    if (res == null) return c.res;
    if (res != c.res) c.with_response(res);

    return c.res;
}

fn Response*? Application.dispatch_head_fallback_context(&self, Context* c, fault match_error)
{
    if (c == null || c.req == null) return CONTEXT_NOT_READY~;
    if (!str_iequals(c.req.method, "HEAD")) return match_error~;

    if (match_error != ROUTE_NOT_FOUND && match_error != METHOD_NOT_ALLOWED) {
        return match_error~;
    }

    RouteMatch? get_match = self.router.match("GET", c.req.path);

    if (catch get_match) {
        return match_error~;
    }

    defer get_match.free();

    return self.dispatch_match_context(c, &get_match)!;
}

fn Response*? Application.fetch_context(&self, Context* c)
{
    if (c == null || c.req == null) return CONTEXT_NOT_READY~;

    Request* req = c.req;
    RouteMatch? match = self.router.match(req.method, req.path);

    if (catch err = match) {
        if (str_iequals(req.method, "HEAD") && (err == ROUTE_NOT_FOUND || err == METHOD_NOT_ALLOWED)) {
            Response*? head_res = self.dispatch_head_fallback_context(c, err);

            if (try head_res) {
                return head_res;
            }
        }

        if (err == METHOD_NOT_ALLOWED) {
            return self.dispatch_fallback_context(c, &method_not_allowed_handler)!;
        }

        if (err == ROUTE_NOT_FOUND) {
            Handler handler = self.not_found_handler;

            if (handler == null) {
                handler = &not_found_handler;
            }

            return self.dispatch_fallback_context(c, handler)!;
        }

        return self.handle_context_dispatch_error(c, err)!;
    }

    defer match.free();

    return self.dispatch_match_context(c, &match)!;
}

// Debug

fn void Application.dump(&self)
{
    io::printfn("routes:");
    self.router.dump();

    io::printfn("middlewares:");
    self.middlewares.dump();

    io::printfn("not_found_handler: %s", self.not_found_handler != null ? "configured" : "default");
    io::printfn("error_handler: %s", self.error_handler != null ? "configured" : "default");
}

// eof