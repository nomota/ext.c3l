// cors.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import std::io;
import ext::mem;
import ext::debug;


// 
// CORS
// 

struct CorsOptions
{
    String allow_origin;
    String allow_methods;
    String allow_headers;
    String expose_headers;
    String max_age;
    bool allow_credentials;
}


// 
// Default options
// 

fn void CorsOptions.init(&self)
{
    self.allow_origin = "*";
    self.allow_methods = "GET, POST, PUT, PATCH, DELETE, OPTIONS";
    self.allow_headers = "Content-Type, Authorization";
    self.expose_headers = "";
    self.max_age = "86400";
    self.allow_credentials = false;
}

fn CorsOptions cors_options_default()
{
    CorsOptions opt;
    opt.init();
    return opt;
}


// 
// Global/tlocal CORS options
// 

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
    cors_options_ready = true;
}


// 
// Internal helpers
// 

fn bool cors_is_preflight(Ctx* c)
{
    if (c == null) return false;
    if (c.method() != "OPTIONS") return false;

    String? origin = c.req_header("Origin");
    if (catch err = origin) return false;

    String? req_method = c.req_header("Access-Control-Request-Method");
    if (catch err = req_method) return false;

    return true;
}

fn String cors_origin_for_response(Ctx* c, CorsOptions* opt)
{
    if (c == null) return "*";
    if (opt == null) return "*";

    if (opt.allow_origin == "*")
    {
        if (opt.allow_credentials)
        {
            // CORS does not allow:
            //   Access-Control-Allow-Origin: *
            // together with:
            //   Access-Control-Allow-Credentials: true
            //
            // So echo the request Origin when credentials are enabled.
            String? origin = c.req_header("Origin");
            if (try origin) return origin;
        }

        return "*";
    }

    return opt.allow_origin;
}

fn void? cors_apply_headers(Ctx* c, CorsOptions* opt) @maydiscard
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (opt == null) return;

    String origin = cors_origin_for_response(c, opt);

    c.header("Access-Control-Allow-Origin", origin)!;

    if (opt.allow_credentials)
    {
        c.header("Access-Control-Allow-Credentials", "true")!;
    }

    if (opt.expose_headers.len > 0)
    {
        c.header("Access-Control-Expose-Headers", opt.expose_headers)!;
    }

    // If we echo request Origin, response should vary by Origin.
    if (origin != "*")
    {
        c.header("Vary", "Origin")!;
    }
}

fn void? cors_apply_preflight_headers(Ctx* c, CorsOptions* opt) @maydiscard
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (opt == null) return;

    cors_apply_headers(c, opt)!;

    c.header("Access-Control-Allow-Methods", opt.allow_methods)!;

    if (opt.allow_headers.len > 0)
    {
        c.header("Access-Control-Allow-Headers", opt.allow_headers)!;
    }
    else
    {
        // If user did not configure allow_headers,
        // echo Access-Control-Request-Headers when present.
        String? req_headers = c.req_header("Access-Control-Request-Headers");
        if (try req_headers)
        {
            c.header("Access-Control-Allow-Headers", req_headers)!;
        }
    }

    if (opt.max_age.len > 0)
    {
        c.header("Access-Control-Max-Age", opt.max_age)!;
    }
}


// 
// Middleware
// 

fn Response*? cors_default(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    cors_init_default();

    if (cors_is_preflight(c))
    {
        cors_apply_preflight_headers(c, &cors_options)!;
        c.status(204)!;
        return c.empty();
    }

    Response* res = next(c)!;

    cors_apply_headers(c, &cors_options)!;

    return res;
}


// 
// Convenience option setters
// 

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


// 
// Strict configured middleware
// 

// Same implementation as cors_default, but separate name is useful
// when the application explicitly configured cors_options beforehand.
fn Response*? cors(Ctx* c, Next next)
{
    return cors_default(c, next)!;
}


// 
// Debug
// 

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
}

// eof