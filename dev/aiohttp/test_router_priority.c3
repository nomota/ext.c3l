// test_router_priority.c3

// Router priority tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::router_priority;

import std::io;
import ext::aio::http;
import ext::debug;

fn aio::http::Response*? static_handler(aio::http::Context* c)
{
    return c.text("static")!!;
}

fn aio::http::Response*? param_handler(aio::http::Context* c)
{
    String id = c.param("id")!!;
    return c.text(id)!!;
}

fn aio::http::Response*? wildcard_handler(aio::http::Context* c)
{
    String splat = c.splat()!!;
    return c.text(splat)!!;
}

fn aio::http::Response*? root_handler(aio::http::Context* c)
{
    return c.text("root")!!;
}

fn aio::http::Response*? api_handler(aio::http::Context* c)
{
    return c.text("api")!!;
}

fn aio::http::Response* fetch(aio::http::Application* app, char[] raw)
{
    return app.fetch_raw(raw)!!;
}

fn void test_static_beats_param()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/users/:id", &param_handler)!!;
    app.get("/users/me", &static_handler)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET /users/me HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "static beats param status mismatch");
    @assert((String)res.body == "static", "static beats param body mismatch");
}

fn void test_param_matches_when_no_static()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/users/:id", &param_handler)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET /users/42 HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "param status mismatch");
    @assert((String)res.body == "42", "param body mismatch");
}

fn void test_static_beats_wildcard()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/files/*", &wildcard_handler)!!;
    app.get("/files/index.html", &static_handler)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET /files/index.html HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "static beats wildcard status mismatch");
    @assert((String)res.body == "static", "static beats wildcard body mismatch");
}

fn void test_param_beats_wildcard()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/files/*", &wildcard_handler)!!;
    app.get("/files/:id", &param_handler)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET /files/readme HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "param beats wildcard status mismatch");
    @assert((String)res.body == "readme", "param beats wildcard body mismatch");
}

fn void test_wildcard_matches_deep_path()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/files/*", &wildcard_handler)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET /files/a/b/c.txt HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "wildcard deep status mismatch");
    @assert((String)res.body == "a/b/c.txt", "wildcard deep body mismatch");
}

fn void test_root_route()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/", &root_handler)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "root status mismatch");
    @assert((String)res.body == "root", "root body mismatch");
}

fn void test_trailing_slash_route_is_invalid()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    if (catch err = app.get("/users/", &root_handler))
    {
        @assert(err == aio::http::INVALID_ROUTE_PATH, "trailing slash route fault mismatch");
        return;
    }

    @assert(false, "trailing slash route should fail");
}

fn void test_mount_prefix_boundary()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    aio::http::Application api;
    api.init();
    defer api.deinit();

    api.get("/users", &api_handler)!!;

    app.route("/api", &api)!!;
    app.get("/apix/users", &static_handler)!!;

    aio::http::Response* res1 = fetch(&app, (char[])
        "GET /api/users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res1);

    aio::http::Response* res2 = fetch(&app, (char[])
        "GET /apix/users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res2);

    @assert(res1.status == 200, "mounted /api status mismatch");
    @assert((String)res1.body == "api", "mounted /api body mismatch");

    @assert(res2.status == 200, "/apix sibling status mismatch");
    @assert((String)res2.body == "static", "/apix sibling body mismatch");
}

fn void test_nested_mount()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    aio::http::Application api;
    api.init();
    defer api.deinit();

    aio::http::Application v1;
    v1.init();
    defer v1.deinit();

    v1.get("/users", &api_handler)!!;
    api.route("/v1", &v1)!!;
    app.route("/api", &api)!!;

    aio::http::Response* res = fetch(&app, (char[])
        "GET /api/v1/users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert(res.status == 200, "nested mount status mismatch");
    @assert((String)res.body == "api", "nested mount body mismatch");
}

fn void test_duplicate_route_registration()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    app.get("/dup", &static_handler)!!;

    if (catch err = app.get("/dup", &root_handler))
    {
        @assert(
            err == aio::http::INVALID_ROUTE_PATH,
            "duplicate route fault mismatch"
        );
        return;
    }

    aio::http::Response* res = fetch(&app, (char[])
        "GET /dup HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "\r\n"
    );
    defer aio::http::response_free(res);

    @assert((String)res.body == "static", "duplicate route should preserve first handler");
}

fn void test_invalid_route_path()
{
    aio::http::Application app;
    app.init();
    defer app.deinit();

    if (catch err = app.get("missing-leading-slash", &static_handler))
    {
        @assert(
            err == aio::http::INVALID_ROUTE_PATH,
            "invalid route path fault mismatch"
        );
        return;
    }

    @assert(false, "invalid route path should fail");
}

fn void main()
{
    test_static_beats_param();
    test_param_matches_when_no_static();
    test_static_beats_wildcard();
    test_param_beats_wildcard();
    test_wildcard_matches_deep_path();

    test_root_route();
    test_trailing_slash_route_is_invalid();

    test_mount_prefix_boundary();
    test_nested_mount();

    test_duplicate_route_registration();
    test_invalid_route_path();

    io::printfn("test_router_priority: OK");
}

// eof
