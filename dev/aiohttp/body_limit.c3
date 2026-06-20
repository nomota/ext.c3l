// body_limit.c3

// Request body size limit middleware for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::debug;

// Faults

faultdef BODY_LIMIT_EXCEEDED;


// Configuration

const sz DEFAULT_BODY_LIMIT = 16 * 1024 * 1024;

tlocal sz body_limit_bytes = DEFAULT_BODY_LIMIT;


// Configuration API

fn void set_body_limit(sz max_bytes)
{
    if (max_bytes <= 0)
    {
        body_limit_bytes = DEFAULT_BODY_LIMIT;
        return;
    }

    body_limit_bytes = max_bytes;
}

fn sz get_body_limit()
{
    return body_limit_bytes;
}

fn void reset_body_limit()
{
    body_limit_bytes = DEFAULT_BODY_LIMIT;
}


// Helpers

fn bool request_method_may_have_body(String method) @inline @local
{
    if (str_iequals(method, "POST")) return true;
    if (str_iequals(method, "PUT")) return true;
    if (str_iequals(method, "PATCH")) return true;
    if (str_iequals(method, "DELETE")) return true;

    return false;
}

fn bool request_body_exceeds_limit(Request* req, sz max_bytes)
{
    if (req == null) return false;
    if (max_bytes < 0) return false;

    return req.body.len > max_bytes;
}

fn Response*? body_limit_response(Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.status(413)!;
    return c.text("413 Payload Too Large")!;
}


// Middleware

fn Response*? middleware_body_limit(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (c.req == null) return CONTEXT_NOT_READY~;

    if (!request_method_may_have_body(c.method()))
    {
        return next(c)!;
    }

    if (request_body_exceeds_limit(c.req, body_limit_bytes))
    {
        return body_limit_response(c)!;
    }

    return next(c)!;
}


// Explicit limit helper

fn Response*? body_limit(Ctx* c, Next next, sz max_bytes)
{
    if (c == null) return CONTEXT_NOT_READY~;
    if (c.req == null) return CONTEXT_NOT_READY~;

    if (max_bytes < 0)
    {
        return next(c)!;
    }

    if (request_body_exceeds_limit(c.req, max_bytes))
    {
        return body_limit_response(c)!;
    }

    return next(c)!;
}


// Size helpers

fn void set_body_limit_kib(sz kib)
{
    if (kib <= 0)
    {
        reset_body_limit();
        return;
    }

    set_body_limit(kib * 1024);
}

fn void set_body_limit_mib(sz mib)
{
    if (mib <= 0)
    {
        reset_body_limit();
        return;
    }

    set_body_limit(mib * 1024 * 1024);
}


// Debug

fn void body_limit_dump()
{
    warn("body_limit = %d bytes", body_limit_bytes);
}

// eof