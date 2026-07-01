// recover.c3

// Recovery middleware for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::debug;


// Configuration

tlocal bool recover_log_enabled = true;
tlocal bool recover_expose_error = false;


// Configuration API

fn void set_recover_log(bool enabled)
{
    recover_log_enabled = enabled;
}

fn void set_recover_expose_error(bool enabled)
{
    recover_expose_error = enabled;
}


// Helpers

fn void recover_log_error(Ctx* c, fault err) @local
{
    if (!recover_log_enabled) return;

    if (c == null)
    {
        io::printfn("[recover] error=%s", err);
        return;
    }

    String? request_id = c.request_id();

    if (try request_id)
    {
        io::printfn(
            "[recover] request_id=%s method=%s path=%s error=%s",
            request_id,
            c.method(),
            c.path(),
            err
        );

        return;
    }

    io::printfn(
        "[recover] method=%s path=%s error=%s",
        c.method(),
        c.path(),
        err
    );
}

fn Response*? recover_response(Ctx* c, fault err)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.status(500)!;

    String? request_id = c.request_id();

    if (try request_id)
    {
        c.header(REQUEST_ID_HEADER, request_id)!;
    }

    if (recover_expose_error)
    {
        char[512] buf;

        String body = string::bformat(
            buf[..],
            "500 Internal Server Error\n%s",
            err
        );

        return c.text(body)!;
    }

    return c.text("500 Internal Server Error")!;
}


// Middleware

fn Response*? middleware_recover(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    Response*? maybe_res = next(c);

    if (catch err = maybe_res)
    {
        recover_log_error(c, err);
        return recover_response(c, err)!;
    }

    return maybe_res;
}


// Debug middleware

fn Response*? middleware_recover_debug(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    bool old_expose = recover_expose_error;
    recover_expose_error = true;

    defer
    {
        recover_expose_error = old_expose;
    }

    return middleware_recover(c, next)!;
}

// eof