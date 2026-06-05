// test_middleware_edge.c3

// Middleware edge tests for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module test::middleware_edge;

import std::io;
import ext::aiohttp;
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

fn aiohttp::Response*? home_handler(aiohttp::Context* c)
{
    return c.text("home")!!;
}

fn aiohttp::Response*? api_handler(aiohttp::Context* c)
{
    return c.text("api")!!;
}

fn aiohttp::Response*? replacement_handler(aiohttp::Context* c)
{
    aiohttp::Response* res = aiohttp::response_text("handler replacement")!!;
    res.header("X-Handler-Replaced", "yes")!!;

    return res;
}

fn aiohttp::Response*? before_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    c.header("X-Before", "1")!!;

    return next(c)!!;
}

fn aiohttp::Response*? after_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    aiohttp::Response* res = next(c)!!;

    c.header("X-After", "1")!!;

    return res;
}

fn aiohttp::Response*? block_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    c.status(401)!!;
    return c.text("blocked")!!;
}

fn aiohttp::Response*? replace_after_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    aiohttp::Response* old = next(c)!!;
    @assert(old != null, "old response should not be null");

    aiohttp::Response* res = aiohttp::response_text("middleware replacement")!!;
    res.header("X-Middleware-Replaced", "yes")!!;

    return res;
}

fn aiohttp::Response*? order_one_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    c.header("X-Order", "1")!!;

    aiohttp::Response* res = next(c)!!;

    c.add_header("X-Order", "4")!!;

    return res;
}

fn aiohttp::Response*? order_two_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    c.add_header("X-Order", "2")!!;

    aiohttp::Response* res = next(c)!!;

    c.add_header("X-Order", "3")!!;

    return res;
}

fn aiohttp::Response*? path_marker_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    c.header("X-Path-Middleware", "yes")!!;

    return next(c)!!;
}

fn aiohttp::Response*? null_next_probe_middleware(aiohttp::Context* c, aiohttp::Next next)
{
    aiohttp::Response* res = next(c)!!;

    @assert(res != null, "next should return response");

    return res;
}

fn aiohttp::Request* parse_request(char[] raw)
{
    return aiohttp::request_parse(raw)!!;
}

fn aiohttp::Response* fetch_raw(aiohttp::Application* app, char[] raw)
{
    return app.fetch_raw(raw)!!;
}

fn String serialize_response(aiohttp::Response* res)
{
    return res.serialize()!!;
}

fn void test_global_before_after()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&before_middleware);
    app.use(&after_middleware);
    app.get("/", &home_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "global before/after status mismatch");
    @assert((String)res.body == "home", "global before/after body mismatch");
    @assert(res.headers.get("X-Before")!! == "1", "before header mismatch");
    @assert(res.headers.get("X-After")!! == "1", "after header mismatch");
}

fn void test_block_middleware_without_next()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&block_middleware);
    app.get("/", &home_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 401, "block middleware status mismatch");
    @assert((String)res.body == "blocked", "block middleware body mismatch");
}

fn void test_block_middleware_stops_later_middleware()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&block_middleware);
    app.use(&after_middleware);
    app.get("/", &home_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 401, "block stops later status mismatch");
    @assert((String)res.body == "blocked", "block stops later body mismatch");
    @assert(!res.headers.has("X-After"), "later middleware should not run");
}

fn void test_middleware_replaces_response()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&replace_after_middleware);
    app.get("/", &home_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "middleware replacement status mismatch");
    @assert((String)res.body == "middleware replacement", "middleware replacement body mismatch");
    @assert(res.headers.get("X-Middleware-Replaced")!! == "yes", "middleware replacement header mismatch");
}

fn void test_handler_replaces_response_with_middleware()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&after_middleware);
    app.get("/", &replacement_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "handler replacement status mismatch");
    @assert((String)res.body == "handler replacement", "handler replacement body mismatch");
    @assert(res.headers.get("X-Handler-Replaced")!! == "yes", "handler replacement header mismatch");
    @assert(res.headers.get("X-After")!! == "1", "after header on replacement mismatch");
}

fn void test_middleware_order()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&order_one_middleware);
    app.use(&order_two_middleware);
    app.get("/", &home_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "middleware order status mismatch");
    @assert(res.headers.len() >= 4, "middleware order headers len mismatch");

    String wire = serialize_response(res);
    defer aiohttp::localmem.free(wire);

    @assert(contains(wire, "X-Order: 1\r\n"), "order 1 missing");
    @assert(contains(wire, "X-Order: 2\r\n"), "order 2 missing");
    @assert(contains(wire, "X-Order: 3\r\n"), "order 3 missing");
    @assert(contains(wire, "X-Order: 4\r\n"), "order 4 missing");

    sz p1 = find_string(wire, "X-Order: 1\r\n");
    sz p2 = find_string(wire, "X-Order: 2\r\n");
    sz p3 = find_string(wire, "X-Order: 3\r\n");
    sz p4 = find_string(wire, "X-Order: 4\r\n");

    @assert(p1 >= 0 && p2 >= 0 && p3 >= 0 && p4 >= 0, "order header positions missing");
    @assert(p1 < p2, "order 1 should come before 2");
    @assert(p2 < p3, "order 2 should come before 3");
    @assert(p3 < p4, "order 3 should come before 4");
}

fn sz find_string(String s, String needle)
{
    if (needle.len == 0) return 0;
    if (s.len < needle.len) return -1;

    for (sz i = 0; i + needle.len <= s.len; i++)
    {
        if (s[i:needle.len] == needle) return i;
    }

    return -1;
}

fn void test_path_middleware_matches_prefix()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;
    app.get("/api", &api_handler)!!;
    app.get("/api/users", &api_handler)!!;

    aiohttp::Response* res1 = fetch_raw(&app, (char[])
        "GET /api HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res1);

    aiohttp::Response* res2 = fetch_raw(&app, (char[])
        "GET /api/users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res2);

    @assert(res1.headers.get("X-Path-Middleware")!! == "yes", "path middleware /api mismatch");
    @assert(res2.headers.get("X-Path-Middleware")!! == "yes", "path middleware /api/users mismatch");
}

fn void test_path_middleware_does_not_match_prefix_sibling()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;
    app.get("/apix", &home_handler)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET /apix HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 200, "path sibling status mismatch");
    @assert(!res.headers.has("X-Path-Middleware"), "path middleware should not match /apix");
}

fn void test_path_middleware_root_matches_all()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/", &path_marker_middleware)!!;
    app.get("/", &home_handler)!!;
    app.get("/x", &home_handler)!!;

    aiohttp::Response* res1 = fetch_raw(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res1);

    aiohttp::Response* res2 = fetch_raw(&app, (char[])
        "GET /x HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res2);

    @assert(res1.headers.get("X-Path-Middleware")!! == "yes", "root middleware / mismatch");
    @assert(res2.headers.get("X-Path-Middleware")!! == "yes", "root middleware /x mismatch");
}

fn void test_invalid_middleware_path()
{
    aiohttp::MiddlewareStack stack;
    stack.init();
    defer stack.free();

    if (catch err = stack.use_path("api", &path_marker_middleware))
    {
        @assert(err == aiohttp::INVALID_MIDDLEWARE_PATH, "invalid middleware path fault mismatch");
        return;
    }

    @assert(false, "invalid middleware path should fail");
}

fn void test_middleware_stack_direct_run()
{
    aiohttp::Request* req = parse_request((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::request_free(req);

    aiohttp::Context* c = aiohttp::context_new(req)!!;
    defer aiohttp::context_free(c);

    aiohttp::MiddlewareStack stack;
    stack.init();
    defer stack.free();

    stack.use(&before_middleware);
    stack.use(&after_middleware);

    aiohttp::Response* res = aiohttp::middleware_run(&stack, c, &home_handler)!!;

    @assert(res == c.res, "direct middleware response mismatch");
    @assert(res.headers.get("X-Before")!! == "1", "direct before header mismatch");
    @assert(res.headers.get("X-After")!! == "1", "direct after header mismatch");
    @assert((String)res.body == "home", "direct middleware body mismatch");
}

fn void test_middleware_run_null_stack()
{
    aiohttp::Request* req = parse_request((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::request_free(req);

    aiohttp::Context* c = aiohttp::context_new(req)!!;
    defer aiohttp::context_free(c);

    aiohttp::Response* res = aiohttp::middleware_run(null, c, &home_handler)!!;

    @assert(res == c.res, "null stack response mismatch");
    @assert((String)res.body == "home", "null stack body mismatch");
}

fn void test_middleware_null_handler_fault()
{
    aiohttp::Request* req = parse_request((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::request_free(req);

    aiohttp::Context* c = aiohttp::context_new(req)!!;
    defer aiohttp::context_free(c);

    aiohttp::MiddlewareStack stack;
    stack.init();
    defer stack.free();

    if (catch err = aiohttp::middleware_run(&stack, c, null))
    {
        @assert(err == aiohttp::CONTEXT_NOT_READY, "null handler fault mismatch");
        return;
    }

    @assert(false, "null handler should fail");
}

fn void test_current_chain_restored_after_run()
{
    aiohttp::Request* req = parse_request((char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::request_free(req);

    aiohttp::Context* c = aiohttp::context_new(req)!!;
    defer aiohttp::context_free(c);

    aiohttp::MiddlewareStack stack;
    stack.init();
    defer stack.free();
 
    stack.use(&null_next_probe_middleware);

    aiohttp::Response* res = aiohttp::middleware_run(&stack, c, &home_handler)!!;

    @assert(res == c.res, "restored chain first run response mismatch");
    @assert((String)res.body == "home", "restored chain first run body mismatch");

    if (catch err = aiohttp::middleware_next(c))
    {
        @assert(err == aiohttp::CONTEXT_NOT_READY, "middleware_next outside chain fault mismatch");
        return;
    }

    @assert(false, "middleware_next outside chain should fail");
}

fn void test_application_middleware_after_404()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use(&after_middleware);

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 404, "middleware after 404 status mismatch");
//warn("%s", (String)res.body);
    @assert(((String)res.body).index_of("404 Not Found")!! == 0, "middleware after 404 body mismatch");
    @assert(res.headers.get("X-After")!! == "1", "middleware after 404 header mismatch");
}

fn void test_application_path_middleware_after_404_path_match()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET /api/missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 404, "path middleware 404 status mismatch");
    @assert(res.headers.get("X-Path-Middleware")!! == "yes", "path middleware should run on matching 404");
}

fn void test_application_path_middleware_after_404_path_miss()
{
    aiohttp::Application app;
    app.init();
    defer app.deinit();

    app.use_path("/api", &path_marker_middleware)!!;

    aiohttp::Response* res = fetch_raw(&app, (char[])
        "GET /other/missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aiohttp::response_free(res);

    @assert(res.status == 404, "path middleware miss 404 status mismatch");
    @assert(!res.headers.has("X-Path-Middleware"), "path middleware should not run on nonmatching 404");
}

fn void main()
{
    test_global_before_after();
    test_block_middleware_without_next();
    test_block_middleware_stops_later_middleware();

    test_middleware_replaces_response();
    test_handler_replaces_response_with_middleware();
    test_middleware_order();

    test_path_middleware_matches_prefix();
    test_path_middleware_does_not_match_prefix_sibling();
    test_path_middleware_root_matches_all();
    test_invalid_middleware_path();

    test_middleware_stack_direct_run();
    test_middleware_run_null_stack();
    test_middleware_null_handler_fault();
    test_current_chain_restored_after_run();

    test_application_middleware_after_404();
    test_application_path_middleware_after_404_path_match();
    test_application_path_middleware_after_404_path_miss();

    io::printfn("test_middleware_edge: OK");
}

// eof 