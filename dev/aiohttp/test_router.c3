// test_router.c3

module test::aio::http_router;

import std::io;
import ext::aio::http;
import ext::debug;

fn aio::http::Response*? dummy_handler(aio::http::Ctx* c)
{
    return c.text("ok")!;
}

fn void test_exact_route()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    aio::http::RouteMatch m = r.match("GET", "/hello")!!;
    defer m.free();

    @assert(m.handler != null, "exact route handler is null");
}

fn void test_one_param()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/users/:id", &dummy_handler)!!;

    aio::http::RouteMatch m = r.match("GET", "/users/kim")!!;
    defer m.free();

    String id = m.params.get("id")!!;
    @assert(id == "kim", "one param mismatch");
}

fn void test_two_params()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/users/:user_id/posts/:post_id", &dummy_handler)!!;

    aio::http::RouteMatch m = r.match("GET", "/users/kim/posts/42")!!;
    defer m.free();

    String user_id = m.params.get("user_id")!!;
    String post_id = m.params.get("post_id")!!;

    @assert(user_id == "kim", "user_id mismatch");
    @assert(post_id == "42", "post_id mismatch");
}

fn void test_splat()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/files/*", &dummy_handler)!!;

    aio::http::RouteMatch m = r.match("GET", "/files/css/app.css")!!;
    defer m.free();

    String rest = m.params.splat()!!;
    @assert(rest == "css/app.css", "splat mismatch");
}

fn void test_param_percent_decode()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/users/:id", &dummy_handler)!!;

    aio::http::RouteMatch m = r.match("GET", "/users/kim%20lee")!!;
    defer m.free();

    String id = m.params.get("id")!!;
    @assert(id == "kim lee", "percent-decoded param mismatch");
}

fn void test_splat_percent_decode()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/files/*", &dummy_handler)!!;

    aio::http::RouteMatch m = r.match("GET", "/files/docs/my%20file.pdf")!!;
    defer m.free();

    String rest = m.params.splat()!!;
    @assert(rest == "docs/my file.pdf", "percent-decoded splat mismatch");
}

fn void test_not_found()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    aio::http::RouteMatch? m = r.match("GET", "/missing");
    if (catch err = m)
    {
        @assert(err == aio::http::ROUTE_NOT_FOUND, "expected ROUTE_NOT_FOUND");
        return;
    }

    m.free();
    @assert(false, "expected route not found");
}

fn void test_method_not_allowed()
{
    aio::http::Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    aio::http::RouteMatch? m = r.match("POST", "/hello");
    if (catch err = m)
    {
        @assert(err == aio::http::METHOD_NOT_ALLOWED, "expected METHOD_NOT_ALLOWED");
        return;
    }

    m.free();
    @assert(false, "expected method not allowed");
}

fn void test_mount()
{
    aio::http::Router api;
    api.init();
    defer api.free();

    api.get("/users", &dummy_handler)!!;

    aio::http::Router root;
    root.init();
    defer root.free();

    root.mount("/api", &api)!!;

    aio::http::RouteMatch m = root.match("GET", "/api/users")!!;
    defer m.free();

    @assert(m.handler != null, "mounted route handler is null");
}

fn void main()
{
    test_exact_route();
    test_one_param();
    test_two_params();
    test_splat();
    test_param_percent_decode();
    test_splat_percent_decode();
    test_not_found();
    test_method_not_allowed();
    test_mount();

    io::printfn("test_router: OK");
}

// eof