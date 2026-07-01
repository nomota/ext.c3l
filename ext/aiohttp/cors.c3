// cors.c3

// CORS middleware for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;

// CORS

struct CorsOptions
{
    // "*" or comma-separated list:
    //   "*"
    //   "https://a.com"
    //   "https://a.com, https://b.com"
    String allow_origin;

    // If empty, preflight echoes Access-Control-Request-Method.
    String allow_methods;

    // If empty, preflight echoes Access-Control-Request-Headers.
    String allow_headers;

    String expose_headers;
    String max_age;

    bool allow_credentials;

    // If false, non-CORS requests without Origin do not get CORS headers.
    bool always_send;

    // Adds Vary when response depends on request CORS headers.
    bool vary;

    ushort preflight_status;
}

// Default options

fn void CorsOptions.init(&self)
{
    self.allow_origin = "*";
    self.allow_methods = "GET, POST, PUT, PATCH, DELETE, OPTIONS";
    self.allow_headers = "Content-Type, Authorization";
    self.expose_headers = "";
    self.max_age = "86400";
    self.allow_credentials = false;
    self.always_send = false;
    self.vary = true;
    self.preflight_status = 204;
}

fn CorsOptions cors_options_default()
{
    CorsOptions opt;
    opt.init();
    return opt;
}

// Global/tlocal CORS options

tlocal CorsOptions cors_options = {};
tlocal bool cors_options_ready = false;

fn void cors_init_default()
{
    if (cors_options_ready) return;

    cors_options = cors_options_default();
    cors_options_ready = true;
}

fn void cors_set_options(CorsOptions* opt)
{
    if (opt == null) return;

    cors_options.allow_origin = opt.allow_origin;
    cors_options.allow_methods = opt.allow_methods;
    cors_options.allow_headers = opt.allow_headers;
    cors_options.expose_headers = opt.expose_headers;
    cors_options.max_age = opt.max_age;
    cors_options.allow_credentials = opt.allow_credentials;
    cors_options.always_send = opt.always_send;
    cors_options.vary = opt.vary;
    cors_options.preflight_status = opt.preflight_status;
    cors_options_ready = true;
}

// Internal helpers

fn bool cors_has_origin(Ctx* c)
{
    if (c == null) return false;

    String? origin = c.req_header("Origin");
    if (catch err = origin) return false;

    return origin.len > 0;
}

fn bool cors_is_preflight(Ctx* c)
{
    if (c == null) return false;
    if (c.method() != "OPTIONS") return false;

    String? origin = c.req_header("Origin");
    if (catch err = origin) return false;

    String? req_method = c.req_header("Access-Control-Request-Method");
    if (catch err = req_method) return false;

    return origin.len > 0 && req_method.len > 0;
}

fn bool cors_token_list_contains(String list, String value)
{
    if (value.len == 0) return false;

    sz start = 0;

    while (start <= list.len)
    {
        sz comma = -1;

        for (sz i = start; i < list.len; i++)
        {
            if (list[i] == ',')
            {
                comma = i;
                break;
            }
        }

        String part;

        if (comma < 0)
        {
            part = list[start:list.len - start].trim();
            return part == value;
        }

        part = list[start:comma - start].trim();

        if (part == value) return true;

        start = comma + 1;
    }

    return false;
}

fn bool cors_origin_allowed(String allow_origin, String origin)
{
    allow_origin = allow_origin.trim();

    if (allow_origin == "*") return true;
    if (origin.len == 0) return false;

    return cors_token_list_contains(allow_origin, origin);
}

fn String cors_origin_for_response(Ctx* c, CorsOptions* opt)
{
    if (opt == null) return "";

    String? origin_opt = c.req_header("Origin");

    if (catch err = origin_opt)
    {
        if (opt.always_send && opt.allow_origin == "*")
        {
            return "*";
        }

        return "";
    }

    String origin = origin_opt;

    if (!cors_origin_allowed(opt.allow_origin, origin))
    {
        return "";
    }

    if (opt.allow_origin == "*")
    {
        if (opt.allow_credentials)
        {
            return origin;
        }

        return "*";
    }

    return origin;
}

fn String cors_methods_for_preflight(Ctx* c, CorsOptions* opt)
{
    if (opt == null) return "";

    if (opt.allow_methods.len > 0)
    {
        return opt.allow_methods;
    }

    String? req_method = c.req_header("Access-Control-Request-Method");

    if (try req_method)
    {
        return req_method;
    }

    return "";
}

fn String cors_headers_for_preflight(Ctx* c, CorsOptions* opt)
{
    if (opt == null) return "";

    if (opt.allow_headers.len > 0)
    {
        return opt.allow_headers;
    }

    String? req_headers = c.req_header("Access-Control-Request-Headers");

    if (try req_headers)
    {
        return req_headers;
    }

    return "";
}

fn void? cors_apply_vary(Ctx* c, bool preflight) @maydiscard
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (preflight)
    {
        c.header("Vary", "Origin, Access-Control-Request-Method, Access-Control-Request-Headers")!;
        return;
    }

    c.header("Vary", "Origin")!;
}

fn void? cors_apply_headers(Ctx* c, CorsOptions* opt) @maydiscard
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (opt == null) return;

    if (!opt.always_send && !cors_has_origin(c))
    {
        return;
    }

    String origin = cors_origin_for_response(c, opt);

    if (origin.len == 0)
    {
        return;
    }

    c.header("Access-Control-Allow-Origin", origin)!;

    if (opt.allow_credentials)
    {
        c.header("Access-Control-Allow-Credentials", "true")!;
    }

    if (opt.expose_headers.len > 0)
    {
        c.header("Access-Control-Expose-Headers", opt.expose_headers)!;
    }

    if (opt.vary && origin != "*")
    {
        cors_apply_vary(c, false)!;
    }
}

fn void? cors_apply_preflight_headers(Ctx* c, CorsOptions* opt) @maydiscard
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (opt == null) return;

    String origin = cors_origin_for_response(c, opt);

    if (origin.len == 0)
    {
        return;
    }

    c.header("Access-Control-Allow-Origin", origin)!;

    if (opt.allow_credentials)
    {
        c.header("Access-Control-Allow-Credentials", "true")!;
    }

    String methods = cors_methods_for_preflight(c, opt);

    if (methods.len > 0)
    {
        c.header("Access-Control-Allow-Methods", methods)!;
    }

    String headers = cors_headers_for_preflight(c, opt);

    if (headers.len > 0)
    {
        c.header("Access-Control-Allow-Headers", headers)!;
    }

    if (opt.max_age.len > 0)
    {
        c.header("Access-Control-Max-Age", opt.max_age)!;
    }

    if (opt.vary)
    {
        cors_apply_vary(c, true)!;
    }
}

// Middleware

fn Response*? cors_default(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    cors_init_default();

    if (cors_is_preflight(c))
    {
        cors_apply_preflight_headers(c, &cors_options)!;
        c.status(cors_options.preflight_status)!;
        return c.empty();
    }

    Response* res = next(c)!;

    cors_apply_headers(c, &cors_options)!;

    return res;
}

// Same implementation as cors_default, but separate name is useful
// when the application explicitly configured cors_options beforehand.
fn Response*? cors(Ctx* c, Next next)
{
    return cors_default(c, next)!;
}

// Convenience option setters

fn void cors_allow_origin(String origin)
{
    cors_init_default();
    cors_options.allow_origin = origin;
}

fn void cors_allow_methods(String methods)
{
    cors_init_default();
    cors_options.allow_methods = methods;
}

fn void cors_allow_headers(String headers)
{
    cors_init_default();
    cors_options.allow_headers = headers;
}

fn void cors_expose_headers(String headers)
{
    cors_init_default();
    cors_options.expose_headers = headers;
}

fn void cors_max_age(String seconds)
{
    cors_init_default();
    cors_options.max_age = seconds;
}

fn void cors_allow_credentials(bool enabled)
{
    cors_init_default();
    cors_options.allow_credentials = enabled;
}

fn void cors_always_send(bool enabled)
{
    cors_init_default();
    cors_options.always_send = enabled;
}

fn void cors_vary(bool enabled)
{
    cors_init_default();
    cors_options.vary = enabled;
}

fn void cors_preflight_status(ushort status)
{
    cors_init_default();
    cors_options.preflight_status = status;
}

fn void cors_echo_request_headers()
{
    cors_init_default();
    cors_options.allow_headers = "";
}

fn void cors_echo_request_method()
{
    cors_init_default();
    cors_options.allow_methods = "";
}

// Debug

fn void cors_dump_options()
{
    cors_init_default();

    io::printfn("CORS:");
    io::printfn("  allow_origin      = %s", cors_options.allow_origin);
    io::printfn("  allow_methods     = %s", cors_options.allow_methods);
    io::printfn("  allow_headers     = %s", cors_options.allow_headers);
    io::printfn("  expose_headers    = %s", cors_options.expose_headers);
    io::printfn("  max_age           = %s", cors_options.max_age);
    io::printfn("  allow_credentials = %s", cors_options.allow_credentials ? "true" : "false");
    io::printfn("  always_send       = %s", cors_options.always_send ? "true" : "false");
    io::printfn("  vary              = %s", cors_options.vary ? "true" : "false");
    io::printfn("  preflight_status  = %d", cors_options.preflight_status);
}

// eof