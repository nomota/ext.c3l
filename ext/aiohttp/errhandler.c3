// errhandler.c3

// Custom not-found and error handlers for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

// Faults

faultdef ERROR_HANDLER_FAILED;

// Handler types

alias NotFoundHandler = fn Response*?(Ctx*);
alias ErrorHandler = fn Response*?(Ctx*, fault);

// Default handlers

fn Response*? default_not_found_handler(Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.status(404)!;
    return c.text("404 Not Found")!;
}

fn Response*? default_error_handler(Ctx* c, fault err)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.status(500)!;
    return c.text("500 Internal Server Error")!;
}

// Application configuration

fn void Application.set_not_found_handler(&self, NotFoundHandler handler)
{
    self.not_found_handler = handler;
}

fn void Application.set_error_handler(&self, ErrorHandler handler)
{
    self.error_handler = handler;
}

fn void Application.clear_not_found_handler(&self)
{
    self.not_found_handler = null;
}

fn void Application.clear_error_handler(&self)
{
    self.error_handler = null;
}

// Convenience names

fn void Application.not_found(&self, NotFoundHandler handler)
{
    self.set_not_found_handler(handler);
}

fn void Application.on_error(&self, ErrorHandler handler)
{
    self.set_error_handler(handler);
}

// Dispatch helpers

fn Response*? Application.handle_not_found(&self, Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (self.not_found_handler != null)
    {
        Response*? result = self.not_found_handler(c);

        if (catch err = result)
        {
            return self.handle_error(c, err)!;
        }

        return result;
    }

    return default_not_found_handler(c)!;
}

fn Response*? Application.handle_error(&self, Ctx* c, fault err)
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (self.error_handler != null)
    {
        Response*? result = self.error_handler(c, err);

        if (catch handler_err = result)
        {
            return default_error_handler(c, handler_err)!;
        }

        return result;
    }

    return default_error_handler(c, err)!;
}

// eof