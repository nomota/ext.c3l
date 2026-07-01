// context.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;
import c::errno;
import ext::encoding::simdjson;

faultdef CONTEXT_NOT_READY;

struct Context
{
    Request* req;
    Response* res;

    Params params;

    Query query_cache;
    bool query_cache_ready;

    Cookies cookie_cache;
    bool cookie_cache_ready;

    Query form_cache;
    bool form_cache_ready;

    MultipartForm multipart_cache;
    bool multipart_cache_ready;

    bool ws_upgrade;
    WebSocketHandler ws_handler;
    ulong ws_read_timeout_us;
}

alias Ctx = Context;


// Lifecycle

fn void? Context.init(&self, Request* req) @maydiscard
{
    self.req = req;
    self.res = response_new()!;

    self.params.init();

    self.query_cache.init();
    self.query_cache_ready = false;

    self.cookie_cache.init();
    self.cookie_cache_ready = false;

    self.form_cache.init();
    self.form_cache_ready = false;

    self.multipart_cache.init();
    self.multipart_cache_ready = false;
    
    self.ws_upgrade = false;
    self.ws_handler = null;
    self.ws_read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US;
}

fn void? Context.init_with_params(&self, Request* req, Params* params) @maydiscard
{
    if (params == null) return errno::E_INVALID_ARG~;

    self.req = req;
    self.res = response_new()!;

    self.params.init();
    self.params.copy_from(params)!;

    self.query_cache.init();
    self.query_cache_ready = false;

    self.cookie_cache.init();
    self.cookie_cache_ready = false;

    self.form_cache.init();
    self.form_cache_ready = false;

    self.multipart_cache.init();
    self.multipart_cache_ready = false;

    self.ws_upgrade = false;
    self.ws_handler = null;
    self.ws_read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US;
}

fn void Context.free(&self)
{
    if (self.res != null) response_free(self.res);

    self.params.free();
    self.query_cache.free();
    self.cookie_cache.free();
    self.form_cache.free();
    self.multipart_cache.free();

    self.req = null;
    self.res = null;

    self.query_cache_ready = false;
    self.cookie_cache_ready = false;
    self.form_cache_ready = false;
    self.multipart_cache_ready = false;

    self.ws_upgrade = false;
    self.ws_handler = null;
    self.ws_read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US;
}

fn Context*? context_new(Request* req)
{
    Context* c = localmem.alloc(Context)!;
    defer catch localmem.free(c);

    c.init(req)!;
    return c;
}

fn Context*? context_new_with_params(Request* req, Params* params)
{
    Context* c = localmem.alloc(Context)!;
    defer catch localmem.free(c);

    c.init_with_params(req, params)!;
    return c;
}

fn void context_free(Context* c)
{
    if (c == null) return;

    c.free();
    localmem.free(c);
}


// Request accessors

fn String Context.method(&self)
{
    if (self.req == null) return "";
    return self.req.method;
}

fn String Context.path(&self)
{
    if (self.req == null) return "";
    return self.req.path;
}

fn String Context.target(&self)
{
    if (self.req == null) return "";
    return self.req.target;
}

fn String? Context.req_header(&self, String name)
{
    if (self.req == null) return CONTEXT_NOT_READY~;
    return self.req.header(name);
}

fn bool Context.has_body(&self)
{
    if (self.req == null) return false;
    return self.req.has_body();
}

fn char[] Context.body(&self)
{
    if (self.req == null) return {};
    return self.req.body;
}

fn String Context.body_text(&self)
{
    if (self.req == null) return "";
    return self.req.body_text();
}

fn void? Context.set_params(&self, Params* params)
{
    if (params == null) return errno::E_INVALID_ARG~;

    self.params.free();
    self.params.init();
    self.params.copy_from(params)!;
}


fn simdjson::ParseResult? Context.req_json(&self, bool allow_comma = true, bool allow_comment = true)
{
    if (self.req == null) return CONTEXT_NOT_READY~;
    return self.req.parse_json(localmem, allow_comma, allow_comment)!;
}

fn simdjson::ParseResult? Context.req_json_with_allocator(&self, Allocator alloc, bool allow_comma = true, bool allow_comment = true)
{
    if (self.req == null) return CONTEXT_NOT_READY~;
    return self.req.parse_json(alloc, allow_comma, allow_comment)!;
}

fn Response*? Context.upgrade_websocket(&self, WebSocketHandler handler, ulong read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US)
{
    if (self.req == null || self.res == null) return CONTEXT_NOT_READY~;
    if (handler == null) return errno::E_INVALID_ARG~;

    Response* response = websocket_handshake_response(self.req)!;

    self.with_response(response);

    self.ws_upgrade = true;
    self.ws_handler = handler;
    self.ws_read_timeout_us = read_timeout_us;

    return self.res;
}

fn bool Context.is_websocket_upgrade(&self) @inline
{
    return self.ws_upgrade;
}

fn WebSocketHandler Context.websocket_handler(&self) @inline
{
    return self.ws_handler;
}

fn ulong Context.websocket_read_timeout_us(&self) @inline
{
    return self.ws_read_timeout_us;
}

// Params

fn String? Context.param(&self, String name)
{
    return self.params.get(name);
}

fn bool Context.has_param(&self, String name)
{
    return self.params.has(name);
}

fn String? Context.splat(&self)
{
    return self.params.splat();
}


// Query

fn void? Context.ensure_query_cache(&self)
{
    if (self.query_cache_ready) return;
    if (self.req == null) return CONTEXT_NOT_READY~;

    query_parse(&self.query_cache, self.req.query_string)!;
    self.query_cache_ready = true;
}

fn String? Context.query(&self, String name)
{
    self.ensure_query_cache()!;
    return self.query_cache.get(name);
}

fn bool Context.has_query(&self, String name)
{
    if (catch self.ensure_query_cache()) {
        return false;
    }

    return self.query_cache.has(name);
}

fn Query* Context.queries(&self)
{
    if (catch self.ensure_query_cache()) {
        return null;
    }

    return &self.query_cache;
}


// Response status/header

fn void? Context.status(&self, ushort status) @maydiscard
{
    if (self.res == null) return CONTEXT_NOT_READY~;
    self.res.set_status(status)!;
}

fn ushort Context.get_status(&self)
{
    if (self.res == null) return 0;
    return self.res.status;
}

fn void? Context.header(&self, String name, String value) @maydiscard
{
    if (self.res == null) return CONTEXT_NOT_READY~;
    self.res.header(name, value)!;
}

fn void? Context.add_header(&self, String name, String value) @maydiscard
{
    if (self.res == null) return CONTEXT_NOT_READY~;
    self.res.add_header(name, value)!;
}

fn void? Context.content_type(&self, String value) @maydiscard
{
    if (self.res == null) return CONTEXT_NOT_READY~;
    self.res.content_type(value)!;
}

fn void? Context.set_cookie(&self, String value) @maydiscard
{
    if (self.res == null) return CONTEXT_NOT_READY~;
    self.res.set_cookie(value)!;
}


// Response builders

fn Response*? Context.body_response(&self, char[] body)
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_body_copy(body)!;
    return self.res;
}

fn Response*? Context.text(&self, String text)
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_text(text)!;
    return self.res;
}

fn Response*? Context.html(&self, String html)
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_html(html)!;
    return self.res;
}

fn Response*? Context.json(&self, String json)
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_json(json)!;
    return self.res;
}

fn Response*? Context.empty(&self)
{
    if (self.res == null) return CONTEXT_NOT_READY~;
    return self.res;
}

fn Response*? Context.redirect(&self, String location, ushort status = 302)
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_status(status)!;
    self.res.header("Location", location)!;

    return self.res;
}

fn Response*? Context.not_found(&self, String what = "")
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_status(404)!;

    String text = string::format(localmem, "404 Not Found: %s", what);
    defer localmem.free(text);

    self.res.set_text(text)!;
    return self.res;
}

fn Response*? Context.internal_error(&self, String err = "")
{
    if (self.res == null) return CONTEXT_NOT_READY~;

    self.res.set_status(500)!;

    String text = string::format(localmem, "500 Internal Server Error: %s", err);
    defer localmem.free(text);

    self.res.set_text(text)!;
    return self.res;
}


// Response replacement

// Replaces the context response with another response.
//
// Usually handlers should use c.text(), c.json(), etc.
// This exists for cases where a handler builds Response manually.
fn Response* Context.with_response(&self, Response* res)
{
    if (res == null) return self.res;

    if (self.res != null && self.res != res) {
        response_free(self.res);
    }

    self.res = res;
    return self.res;
}

fn Response*? Context.stream(&self, StreamWriter writer, void* arg)
{
    Response* res = response_stream(writer, arg)!;
    self.with_response(res);

    return self.res;
}

fn Response*? Context.file_range(&self, String path, sz offset, sz length)
{
    Response* res = response_file_range(path, offset, length)!;
    self.with_response(res);

    return self.res;
}

fn Response*? Context.file(&self, String path, sz file_size = 0)
{
    return self.file_range(path, 0, file_size)!;
}


// Handler dispatch helper

fn Response*? context_call(Context* c, Handler handler)
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (handler == null) return CONTEXT_NOT_READY~;

    Response* res = handler(c)!;

    if (res == null) return c.res;
    if (res != c.res) c.with_response(res);

    return c.res;
}


// Debug

fn void Context.dump(&self)
{
    if (self.req != null) {
        io::printfn("%s %s", self.req.method, self.req.path);
    }

    io::printfn("params:");
    self.params.dump_params();

    if (self.query_cache_ready) {
        io::printfn("query:");
        self.query_cache.dump();
    }

    if (self.res != null) {
        io::printfn("response:");
        self.res.dump();
    }
}

// eof