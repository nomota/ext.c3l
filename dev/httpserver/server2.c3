// server2.c3


import ext::httpserver;
import ext::asyncio;
import ext::debug;
import ext::aiofiles::os::path;

fn Response* api_hello(Ctx* c)
{
    return c.json("{\"message\":\"hello\"}");
}

fn void http_server_coro()
{
    Application app;
    app.init();
    defer app.free();

    app.use(&httpserver::middleware_logger);

  if (false) {
    // Default:
    // Access-Control-Allow-Origin: *
    app.use(&httpserver::cors_default);
  }

  if (true) {
    // Turn on Credential
    httpserver::cors_allow_credentials(true);
    httpserver::cors_allow_origin("*");
    httpserver::cors_allow_headers("Content-Type, Authorization");
    httpserver::cors_allow_methods("GET, POST, PUT, PATCH, DELETE, OPTIONS");

    app.use(&httpserver::cors);
  }

    app.get("/api/hello", &api_hello)!!;

    app.static_files("/static", "./public")!!;

    app.listen(8080)!!;
}

fn void main()
{
    asyncio::run(&http_server_coro);
}



/* -------------------------------

(1)
On default setting:
```bash
curl -i http://127.0.0.1:8080/api/hello \
  -H 'Origin: http://localhost:3000'
```

expected header:

Access-Control-Allow-Origin: *                
(2)
Preflight request:
```bash
curl -i -X OPTIONS http://127.0.0.1:8080/api/hello \
  -H 'Origin: http://localhost:3000' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: Content-Type, Authorization'
```
expected:

HTTP/1.1 204 No Content
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400


(3)
on Credential
```bash
curl -i http://127.0.0.1:8080/api/hello \
  -H 'Origin: http://localhost:3000' \
  -H 'Cookie: session_id=abc123'
```
expected:

Access-Control-Allow-Origin: http://localhost:3000
Access-Control-Allow-Credentials: true
Vary: Origin 

(4)
static static_files
```bash 
curl -i http://127.0.0.1:8080/static/index.html
curl -i http://127.0.0.1:8080/static/app.js
curl -i http://127.0.0.1:8080/static/style.css
```

*/