module test::httpserver_router;

import std::io;
import ext::httpserver;
import ext::debug;

fn Response* dummy_handler(Ctx* c)
{
    return c.text("ok");
}

fn void test_exact_route()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    RouteMatch m = r.match("GET", "/hello")!!;
    defer m.free();

    assert(m.handler != null);
}

fn void test_one_param()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/users/:id", &dummy_handler)!!;

    RouteMatch m = r.match("GET", "/users/kim")!!;
    defer m.free();

    String id = m.params.get("id")!!;
    assert(id == "kim");
}

fn void test_two_params()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/users/:user_id/posts/:post_id", &dummy_handler)!!;

    RouteMatch m = r.match("GET", "/users/kim/posts/42")!!;
    defer m.free();

    String user_id = m.params.get("user_id")!!;
    String post_id = m.params.get("post_id")!!;

    assert(user_id == "kim");
    assert(post_id == "42");
}

fn void test_splat()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/files/*", &dummy_handler)!!;

    RouteMatch m = r.match("GET", "/files/css/app.css")!!;
    defer m.free();

    String rest = m.params.splat()!!;
    assert(rest == "css/app.css");
}

fn void test_param_percent_decode()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/users/:id", &dummy_handler)!!;

    RouteMatch m = r.match("GET", "/users/kim%20lee")!!;
    defer m.free();

    String id = m.params.get("id")!!;
    assert(id == "kim lee");
}

fn void test_splat_percent_decode()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/files/*", &dummy_handler)!!;

    RouteMatch m = r.match("GET", "/files/docs/my%20file.pdf")!!;
    defer m.free();

    String rest = m.params.splat()!!;
    assert(rest == "docs/my file.pdf");
}

fn void test_not_found()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    RouteMatch? m = r.match("GET", "/missing");
    if (catch err = m) {
        assert(err == httpserver::ROUTE_NOT_FOUND);
        return;
    }

    @assert(false, "error");
}

fn void test_method_not_allowed()
{
    Router r;
    r.init();
    defer r.free();

    r.get("/hello", &dummy_handler)!!;

    RouteMatch? m = r.match("POST", "/hello");
    if (catch err = m) {
        assert(err == httpserver::METHOD_NOT_ALLOWED);
        return;
    }

    @assert(false, "error");
}

fn void test_mount()
{
    Router api;
    api.init();
    defer api.free();

    api.get("/users", &dummy_handler)!!;

    Router root;
    root.init();
    defer root.free();

    root.mount("/api", &api)!!;

    RouteMatch m = root.match("GET", "/api/users")!!;
    defer m.free();

    assert(m.handler != null);
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

    io::printfn("test_router: ok");
}