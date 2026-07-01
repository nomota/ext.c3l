// request_id.c3

// Request ID middleware for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::aio;


// Request ID configuration

const String REQUEST_ID_HEADER = "X-Request-Id";
const sz REQUEST_ID_MAX_LEN = 128;


// Helpers

fn bool char_allowed(char c) @inline @local
{
    if (c >= 'a' && c <= 'z') return true;
    if (c >= 'A' && c <= 'Z') return true;
    if (c >= '0' && c <= '9') return true;

    if (c == '-') return true;
    if (c == '_') return true;
    if (c == '.') return true;
    if (c == ':') return true;

    return false;
}

fn bool request_id_valid(String value) @local
{
    if (value.len == 0) return false;
    if (value.len > REQUEST_ID_MAX_LEN) return false;

    for (sz i = 0; i < value.len; i++)
    {
        if (!char_allowed(value[i]))
        {
            return false;
        }
    }

    return true;
}

tlocal ulong request_id_counter = 0;

fn String? request_id_generate()
{
    request_id_counter++;

    ulong now = aio::time_us();

    return string::format(localmem, "%x-%x", now, request_id_counter);
}

fn String? request_id_from_request(Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    String? value = c.req_header(REQUEST_ID_HEADER);

    if (try value)
    {
        value = value.trim();

        if (request_id_valid(value))
        {
            return value.copy(localmem);
        }
    }

    return request_id_generate()!;
}


// Context request ID

fn String? Context.request_id(&self)
{
    if (self.req == null) return CONTEXT_NOT_READY~;

    String? value = self.req_header(REQUEST_ID_HEADER);

    if (catch err = value)
    {
        return err~;
    }

    value = value.trim();

    if (!request_id_valid(value))
    {
        return NOT_FOUND~;
    }

    return value;
}


// Middleware

fn Response*? middleware_request_id(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    String request_id = request_id_from_request(c)!;
    defer localmem.free(request_id);

    c.req.headers.set(REQUEST_ID_HEADER, request_id)!;

    Response* res = next(c)!;

    c.header(REQUEST_ID_HEADER, request_id)!;

    return res;
}


// Debug middleware

fn Response*? middleware_request_id_debug(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    String request_id = request_id_from_request(c)!;
    defer localmem.free(request_id);

    c.req.headers.set(REQUEST_ID_HEADER, request_id)!;

    io::printfn(
        "[request-id=%s] %s %s",
        request_id,
        c.method(),
        c.path()
    );

    Response* res = next(c)!;

    c.header(REQUEST_ID_HEADER, request_id)!;

    return res;
}

// eof