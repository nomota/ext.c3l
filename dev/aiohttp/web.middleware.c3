// web.middleware.c3

module ext::aiohttp::web;

import std::encoding::base64;
import std::io;

// HTTP middleware chain — used internally by Application.
//
// Python aiohttp middleware signature:
//   async def middleware(request, handler) -> Response
//
// C3 equivalent (from aiohttp.web.c3 type aliases):
//   alias MiddlewareFn = fn Response*?(Request*, NextHandler next);
//   alias NextHandler  = fn Response*?(Request*);
//
// Execution model:
//   Middleware is stored as a flat array in registration order.
//   mw_chain_call() wraps the array into a recursive NextHandler chain
//   at call time — no heap allocation required for the chain itself.
//
//   Given middlewares [A, B, C] and final handler H, the call graph is:
//     A(req, → B(req, → C(req, → H(req))))
//
//   Each middleware calls next(req) to proceed, or returns early to
//   short-circuit (e.g. auth rejection, cache hit).
//
// Stack frame:
//   MwFrame is allocated on the C stack by mw_chain_call().
//   Each recursive frame holds a pointer to the next frame.
//   Max recursion depth == middleware count (typically 1–5).
//
// Thread-safety:
//   All calls run on the event-loop fiber. No locking required.

//  constants 

const usz MW_MAX @private = 32; // maximum middleware per application

//  chain frame (stack-allocated per call) 

alias MwNextFn @private = fn Response*?(Request*, MwFrame*);

struct MwFrame @private {
    MiddlewareFn*  mws;        // pointer into Application.middlewares array
    usz            mw_count;   // total number of middlewares
    usz            index;      // current position in the chain
    RequestHandler final_handler;
}

// The NextHandler passed to each middleware is a thin closure-like trampoline.
// Since C3 does not have closures, we pass the frame pointer via a thread-local.
tlocal MwFrame* tl_mw_frame @private = null;

// Trampoline: called by middleware as next(req).
fn Response*? mw_next_trampoline(Request* req) @private
{
    MwFrame* frame = tl_mw_frame;
    if (frame == null) return aiohttp::RESPONSE_ERROR~;

    frame.index++;
    return mw_dispatch(req, frame);
}

// Dispatch to the next middleware or the final handler.
fn Response*? mw_dispatch(Request* req, MwFrame* frame) @private
{
    MwFrame* prev = tl_mw_frame;
    tl_mw_frame   = frame;

    Response*? result;

    if (frame.index >= frame.mw_count) {
        // reached end of chain — call the actual route handler
        result = frame.final_handler(req);
    } else {
        MiddlewareFn mw = frame.mws[frame.index];
        result = mw(req, &mw_next_trampoline);
    }

    tl_mw_frame = prev;
    return result;
}

//  middleware table 

struct MwTable {
    MiddlewareFn[MW_MAX] entries;
    usz count;
}

fn void mw_table_init(MwTable* t)
{
    t.count = 0;
}

// Append a middleware to the table. Returns false when the table is full.
fn bool mw_table_add(MwTable* t, MiddlewareFn mw)
{
    if (t.count >= MW_MAX) return false;
    t.entries[t.count++] = mw;
    return true;
}

//  chain execution 

// Run request through the full middleware chain, ending at final_handler.
// Middlewares are called in registration order (index 0 first).
// This is the only public entry point — called by the request dispatcher.
fn Response*? mw_chain_call(
    MwTable*       t,
    RequestHandler final_handler,
    Request*       req,
)
{
    MwFrame frame = {
        .mws           = &t.entries[0],
        .mw_count      = t.count,
        .index         = 0,
        .final_handler = final_handler,
    };
    return mw_dispatch(req, &frame);
}

//  built-in middleware helpers 
//
// Ready-to-use middleware factories. Each returns a MiddlewareFn that can be
// passed directly to Application.add_middleware().

// Error-handling middleware.
// Catches faults from inner handlers and converts them to HTTP error responses.
// Usage: app.add_middleware(mw_error_handler);
fn Response*? mw_error_handler(Request* req, NextHandler next)
{
    Response*? result = next(req);
    if (catch err = result) {
        switch (err) {
            case BAD_REQUEST:
                return http_bad_request();
            case UNAUTHORIZED:
                return http_unauthorized();
            case FORBIDDEN:
                return http_forbidden();
            case NOT_FOUND:
                return http_not_found();
            case METHOD_NOT_ALLOWED:
                return http_method_not_allowed();
            case INTERNAL_SERVER_ERROR:
                return http_internal_server_error();
            default:
                return http_internal_server_error();
        }
    }
    return result;
}

// CORS middleware factory state.
struct CorsConfig {
    String  allow_origin;     // "*" or specific origin
    String  allow_methods;    // "GET, POST, PUT, DELETE, OPTIONS"
    String  allow_headers;    // "Content-Type, Authorization"
    bool    allow_credentials;
    ulong   max_age_seconds;  // 0 = omit
}

// CORS middleware.
// Adds Access-Control-* headers to every response.
// Handles OPTIONS preflight by returning 204 immediately.
// cors must outlive the middleware invocation.
fn Response*? mw_cors(Request* req, NextHandler next, CorsConfig* cors) @private
{
    // preflight
    if (req.method == HttpMethod.OPTIONS) {
        Response* r = response_new(204);
        r.set_header("Access-Control-Allow-Origin",  cors.allow_origin);
        r.set_header("Access-Control-Allow-Methods", cors.allow_methods);
        r.set_header("Access-Control-Allow-Headers", cors.allow_headers);
        if (cors.allow_credentials) {
            r.set_header("Access-Control-Allow-Credentials", "true");
        }
        if (cors.max_age_seconds > 0) {
            char[20] age_buf;
            usz age_len = 0;
            ulong v = cors.max_age_seconds;
            do {
                age_buf[age_len++] = (char)('0' + v % 10);
                v /= 10;
            } while (v > 0);
            // reverse
            for (usz i = 0; i < age_len / 2; i++) {
                char tmp = age_buf[i];
                age_buf[i] = age_buf[age_len - 1 - i];
                age_buf[age_len - 1 - i] = tmp;
            }
            r.set_header("Access-Control-Max-Age",
                         (String) age_buf[0: age_len]);
        }
        return r;
    }

    Response*? result = next(req);
    if (catch err = result) return result;

    result.set_header("Access-Control-Allow-Origin", cors.allow_origin);
    if (cors.allow_credentials) {
        result.set_header("Access-Control-Allow-Credentials", "true");
    }
    return result;
}

// Trampoline to bind CorsConfig* into the MiddlewareFn signature.
// cors_config must be a pointer to a long-lived CorsConfig.
//
// Usage:
//   CorsConfig cors = { .allow_origin = "*", .allow_methods = "GET,POST" };
//   app.add_middleware(aiohttp::mw_cors_make(&cors));
//
// Because C3 lacks closures, we use a small per-config trampoline struct.

struct CorsMiddlewareSlot @private {
    CorsConfig* config;
    bool        in_use;
}

const usz CORS_SLOT_MAX @private = 4; // max simultaneous CORS configs
CorsMiddlewareSlot[CORS_SLOT_MAX] cors_slots @private;

macro MiddlewareFn? mw_cors_make(CorsConfig* cfg)
{
    for (usz $i = 0; $i < CORS_SLOT_MAX; $i++) {
        if (!cors_slots[$i].in_use) {
            cors_slots[$i] = (CorsMiddlewareSlot){ cfg, true };
            // return a lambda-like function bound to slot $i
            return fn Response*?(Request* req, NextHandler next) {
                return mw_cors(req, next, cors_slots[$i].config);
            };
        }
    }
    return null; // all slots occupied
}

// Request logging middleware.
// Prints "<METHOD> <path> → <status>" to stdout after handler completes.
// Usage: app.add_middleware(aiohttp::mw_logger);
fn Response*? mw_logger(Request* req, NextHandler next)
{
    Response*? result = next(req);
    int status = 0;
    if (catch err = result) {
        io::printfn("[aiohttp] %s %s → ERR(%s)",
            req.method, req.path, err);
        return err~;
    }
    if (result != null) status = result.status;
    io::printfn("[aiohttp] %s %s → %d", req.method, req.path, status);
    return result;
}

// Basic Auth guard middleware.
// Rejects requests missing a valid Authorization: Basic <b64> header.
// credentials: "username:password" plain text — compared after base64 decode.
//
// Usage:
//   app.add_middleware(aiohttp::mw_basic_auth_make("user:secret"));

struct BasicAuthSlot @private {
    String  credentials; // "user:password" plain
    bool    in_use;
}

const usz BASIC_AUTH_SLOT_MAX @private = 4;
BasicAuthSlot[BASIC_AUTH_SLOT_MAX] basic_auth_slots @private;

fn Response*? mw_basic_auth_check(
    Request*    req,
    NextHandler next,
    String      credentials,
) @private
{
    String? auth_hdr = req.headers.get("authorization");
    if (catch err = auth_hdr) return http_unauthorized();

    // must start with "Basic "
    if (auth_hdr.len < 7 ||
        auth_hdr[0] != 'B' || auth_hdr[1] != 'a' || auth_hdr[2] != 's' ||
        auth_hdr[3] != 'i' || auth_hdr[4] != 'c' || auth_hdr[5] != ' ') {
        return http_unauthorized();
    }

    String b64 = auth_hdr[6:auth_hdr.len - 6];
    
    char[] decoded = base64::decode(tmem, b64)!;
    String dec_str = (String) decoded;
    if (dec_str != credentials) {
        return http_unauthorized();
    }

    return next(req);
}

macro MiddlewareFn? mw_basic_auth_make(String credentials)
{
    for (usz $i = 0; $i < BASIC_AUTH_SLOT_MAX; $i++) {
        if (!basic_auth_slots[$i].in_use) {
            basic_auth_slots[$i] = (BasicAuthSlot){ credentials, true };
            return fn Response*?(Request* req, NextHandler next) {
                return mw_basic_auth_check(req, next, basic_auth_slots[$i].credentials);
            };
        }
    }
    return null;
}

// Max body size guard middleware.
// Rejects requests whose Content-Length exceeds max_bytes.
// Usage: app.add_middleware(aiohttp::mw_max_body_make(1024 * 1024));

struct MaxBodySlot @private {
    usz  max_bytes;
    bool in_use;
}

const usz MAX_BODY_SLOT_MAX @private = 4;
MaxBodySlot[MAX_BODY_SLOT_MAX] max_body_slots @private;

fn Response*? mw_max_body_check(
    Request*    req,
    NextHandler next,
    usz         max_bytes,
) @private
{
    String? cl_hdr = req.headers.get("content-length");
    if (catch err = cl_hdr) return next(req); // no body — pass through

    // parse content-length
    usz body_len = 0;
    foreach (c : cl_hdr) {
        if (c < '0' || c > '9') break;
        body_len = body_len * 10 + (usz)(c - '0');
    }

    if (body_len > max_bytes) {
        return response_new(
            413,
            "Request Entity Too Large",
        );
    }

    return next(req);
}

macro MiddlewareFn? mw_max_body_make(usz max_bytes)
{
    for (usz $i = 0; $i < MAX_BODY_SLOT_MAX; $i++) {
        if (!max_body_slots[$i].in_use) {
            max_body_slots[$i] = (MaxBodySlot){ max_bytes, true };
            return fn Response*?(Request* req, NextHandler next) {
                return mw_max_body_check(req, next, max_body_slots[$i].max_bytes);
            };
        }
    }
    return null;
}
