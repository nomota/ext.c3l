// server1.c3
// example_web.c3

module example;

import std::io;
import c::stdio;
import ext::aiohttp::web;
import ext::mem;
import ext::debug;

// 
// 1. Handlers
// 

// GET /
fn Response*? handle_root(Request* req)
{
    for (usz i = 0; i < req.headers.len(); i++) {
        Header h = req.headers.get_at(i);
        warn("%s: %s", h.name, h.value);
    }

    for (usz i = 0; i < req.cookies.len(); i++) {
        KeyVal h = req.cookies.get_at(i);
        warn("Cookie %s=%s", h.name, h.value);
    }

    warn("req.host: %s", req.host);
    
    Response* resp = web::response_new(200, "Welcome to the aiohttp server!\n");
warn("set_cookie");
    resp.set_cookie("K", "V");
    resp.set_cookie("x", "y", path:"/", domain:"google.com",
        secure:false, httponly:true, samesite:"Lax", 
        max_age:10, expires:"eex");
    
    return resp;
}


// GET /{name}
fn Response*? handle_greet(Request* req)
{
    String name = req.match_info.get("name") ?? "Anonymous";;

    char[256] buf;
    int n = stdio::snprintf(&buf[0], buf.len, "Hello, %s!", name.ptr);
    
    return web::response_new(
        200,
        "", // empty text
        &buf[0], // body
        n, // body len
        "text/plain",
        "utf-8",
    );
}


// 
// 2. Application setup
// 

fn void main()
{
    warn("web::app_new()");
    Application* app = web::app_new();

    // 
    // 3. Routes
    // 

    warn("app.router.add_get()");
    app.router.add_get("/", &handle_root);
    app.router.add_get("/{name}", &handle_greet);

    // 
    // 4. Run
    // 

    warn("web::run_app(port:8080)");
    web::run_app(app, port:8080, server_header:"My test server v1.0");
}


/*
# Python example

from aiohttp import web

# 1. Define your request handlers
async def handle_root(request):
    return web.Response(text="Welcome to the aiohttp server!")

async def handle_greet(request):
    name = request.match_info.get('name', "Anonymous")
    return web.Response(text=f"Hello, {name}!")

# 2. Create the Application instance
app = web.Application()

# 3. Register routes
app.add_routes([
    web.get('/', handle_root),
    web.get('/{name}', handle_greet)
])

# 4. Run the app
if __name__ == '__main__':
    web.run_app(app, port=8080)

*/