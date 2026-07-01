// timeout.c3

// Request handler timeout middleware for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::aio;


// Configuration

const ulong DEFAULT_REQUEST_TIMEOUT_US = 30_000_000;

tlocal ulong request_timeout_us = DEFAULT_REQUEST_TIMEOUT_US;


// Configuration API

fn void set_timeout_us(ulong timeout_us)
{
    if (timeout_us == 0)
    {
        request_timeout_us = DEFAULT_REQUEST_TIMEOUT_US;
        return;
    }

    request_timeout_us = timeout_us;
}

fn void set_timeout_ms(ulong timeout_ms)
{
    if (timeout_ms == 0)
    {
        request_timeout_us = DEFAULT_REQUEST_TIMEOUT_US;
        return;
    }

    request_timeout_us = timeout_ms * 1000;
}

fn ulong get_timeout_us()
{
    return request_timeout_us;
}

fn ulong get_timeout_ms()
{
    return request_timeout_us / 1000;
}

fn void reset_timeout()
{
    request_timeout_us = DEFAULT_REQUEST_TIMEOUT_US;
}


// Response

fn Response*? timeout_response(Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.status(504)!;
    return c.text("504 Gateway Timeout")!;
}


// Middleware

fn Response*? middleware_timeout(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    Task* task = aio::current_task()!;
    Timer* timer = task.start_timer(request_timeout_us)!;

    Response*? maybe_res = next(c);

    timer.cancel();

    if (catch err = maybe_res)
    {
        if (err == aio::TIMEOUT)
        {
            return timeout_response(c)!;
        }

        return err~;
    }

    return maybe_res;
}


// Explicit timeout helper

fn Response*? timeout(Ctx* c, Next next, ulong timeout_us)
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (timeout_us == 0)
    {
        return timeout_response(c)!;
    }

    Task* task = aio::current_task()!;
    Timer* timer = task.start_timer(timeout_us)!;

    Response*? maybe_res = next(c);

    timer.cancel();

    if (catch err = maybe_res)
    {
        if (err == aio::TIMEOUT)
        {
            return timeout_response(c)!;
        }

        return err~;
    }

    return maybe_res;
}

// eof