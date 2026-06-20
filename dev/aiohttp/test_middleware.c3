// test_middleware.c3

// Middleware tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::middleware;

import std::io;
import ext::aio::http;
import ext::debug;

fn bool contains(String haystack, String needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn aio::http::Response*? home_handler(aio::http::Context* c)
{
    return c.text("home")!;
}

fn aio::http::Response*? api_handler(aio::http::Context* c)
{
    return c.text("api")!;
}

fn aio::http::Response*? blocked_handler(aio::http::Context* c)
{
    return c.text("blocked route")!;
}

fn aio::http::Response*? before_after_middleware(aio::http::Context* c, aio::http::Next next)
{
    c.header("X-Before", "1")!;

    aio::http::Response* res = next(c)!;

    c.header("X-After", "1")!;

    return res;
}

fn aio::http::Response*? short_circuit_middleware(aio::http::Context* c, aio::http::Next next)
{
    c.status(401)!;
    return c.text("unauthorized")!;
}

fn aio::http::Response*? path_marker_middleware(aio::http::Context* c, aio::http::Next next)
{
    aio::http::Response* res = next(c)!;

    c.header("X-Path-Middleware", "yes")!;

    return res;
}

fn aio::http::Response*? order_a_middleware(aio::http::Context* c, aio::http::Next next)
{
    c.header("X-Order-A-Before", "1")!;

    aio::http::Response* res = next(c)!;

    c.header("X-Order-A-After", "1")!;

    return res;
}

fn aio::http::Response*? order_b_middleware(aio::http::Context* c, aio::http::Next next)
{
    c.header("X-Order-B-Before", "1")!;

    aio::http::Response* res = next(c)!;

    c.header("X-Order-B-After", "1")!;

    return res;
}

fn void test_global_middleware_before_after()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&before_after_middleware);
    app.get("/", &home_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "global middleware status mismatch");
    @assert((String)res.body == "home", "global middleware body mismatch");

    String before = res.headers.get("X-Before")!!;
    String after = res.headers.get("X-After")!!;

    @assert(before == "1", "before middleware header missing");
    @assert(after == "1", "after middleware header missing");
}

fn void test_short_circuit_middleware()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&short_circuit_middleware);
    app.get("/blocked", &blocked_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET /blocked HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 401, "short-circuit status mismatch");
    @assert((String)res.body == "unauthorized", "short-circuit body mismatch");
}

fn void test_path_middleware_matches_prefix()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;
    app.get("/api/data", &api_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET /api/data HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "path middleware status mismatch");
    @assert((String)res.body == "api", "path middleware body mismatch");

    String marker = res.headers.get("X-Path-Middleware")!!;
    @assert(marker == "yes", "path middleware header missing");
}

fn void test_path_middleware_matches_exact_prefix()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;
    app.get("/api", &api_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "exact path middleware status mismatch");

    String marker = res.headers.get("X-Path-Middleware")!!;
    @assert(marker == "yes", "exact path middleware header missing");
}

fn void test_path_middleware_does_not_match_partial_prefix()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;
    app.get("/apix", &api_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET /apix HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "partial prefix status mismatch");
    @assert((String)res.body == "api", "partial prefix body mismatch");

    String? marker = res.headers.get("X-Path-Middleware");
    if (catch err = marker)
    {
        @assert(err == aio::http::NOT_FOUND, "unexpected missing marker fault");
        return;
    }

    @assert(false, "path middleware matched partial prefix");
}

fn void test_middleware_order()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&order_a_middleware);
    app.use(&order_b_middleware);
    app.get("/", &home_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    @assert(res.status == 200, "middleware order status mismatch");

    @assert(res.headers.get("X-Order-A-Before")!! == "1", "A before missing");
    @assert(res.headers.get("X-Order-B-Before")!! == "1", "B before missing");
    @assert(res.headers.get("X-Order-B-After")!! == "1", "B after missing");
    @assert(res.headers.get("X-Order-A-After")!! == "1", "A after missing");
}

fn void test_middleware_stack_len_empty_clear()
{
    aio::http::MiddlewareStack stack;
    stack.init();
    defer stack.free();

    @assert(stack.empty(), "new middleware stack should be empty");
    @assert(stack.len() == 0, "new middleware stack len mismatch");

    stack.use(&before_after_middleware);
    stack.use_path("/api", &path_marker_middleware)!!;

    @assert(!stack.empty(), "middleware stack should not be empty");
    @assert(stack.len() == 2, "middleware stack len after use mismatch");

    stack.clear();

    @assert(stack.empty(), "middleware stack should be empty after clear");
    @assert(stack.len() == 0, "middleware stack len after clear mismatch");
}

fn void test_invalid_middleware_path()
{
    aio::http::MiddlewareStack stack;
    stack.init();
    defer stack.free();

    if (catch err = stack.use_path("api", &path_marker_middleware))
    {
        @assert(err == aio::http::INVALID_MIDDLEWARE_PATH, "invalid middleware path fault mismatch");
        return;
    }

    @assert(false, "invalid middleware path accepted");
}

fn void test_powered_by_middleware()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&aio::http::middleware_powered_by);
    app.get("/", &home_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    String powered_by = res.headers.get("X-Powered-By")!!;
    @assert(powered_by == "ext::aio::http", "powered-by header mismatch");
}

fn void test_serialized_middleware_headers()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.use(&before_after_middleware);
    app.get("/", &home_handler)!!;

    aio::http::Response* res = app.fetch_raw(
        (char[])"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    )!!;
    defer aio::http::response_free(res);

    String wire = res.serialize()!!;
    defer aio::http::localmem.free(wire);

    @assert(contains(wire, "X-Before: 1\r\n"), "serialized before header missing");
    @assert(contains(wire, "X-After: 1\r\n"), "serialized after header missing");
    @assert(contains(wire, "\r\n\r\nhome"), "serialized body mismatch");
}

fn void main()
{
    test_global_middleware_before_after();
    test_short_circuit_middleware();
    test_path_middleware_matches_prefix();
    test_path_middleware_matches_exact_prefix();
    test_path_middleware_does_not_match_partial_prefix();
    test_middleware_order();
    test_middleware_stack_len_empty_clear();
    test_invalid_middleware_path();
    test_powered_by_middleware();
    test_serialized_middleware_headers();

    io::printfn("test_middleware: OK");
}

// eof