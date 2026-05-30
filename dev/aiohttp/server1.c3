// server1.c3

import ext::httpserver;
import ext::debug;
import ext::mem;
import ext::asyncio;



// 
// Handlers
// 

fn Response* index_handler(Ctx* c)
{
    String? sid = c.cookie("session_id");

    if (catch err = sid) {
        // session_id not received
        c.set_cookie("session_id=abc123; Path=/; HttpOnly; SameSite=Lax");
        c.set_cookie("theme=dark; Path=/; Max-Age=3600; SameSite=Lax");

        return c.text("No session cookie. New cookies were set.");
    }

    // set new cookie
    c.set_cookie("last_visit=now; Path=/; Max-Age=3600; SameSite=Lax");

    return c.text("session_id cookie received");
}

fn Response* profile_handler(Ctx* c)
{
    String? theme = c.cookie("theme");

    if (catch err = theme) {
        c.set_cookie("theme=light; Path=/; Max-Age=3600; SameSite=Lax");
        return c.text("theme cookie was missing. default theme=light was set.");
    }

    if (theme == "dark") {
        return c.text("Current theme is dark");
    }

    return c.text("Current theme is not dark");
}

fn Response* logout_handler(Ctx* c)
{
    // delete cookie:
    // same name, path 
    // Max-Age=0 or Expires=past date
    
    // c.set_cookie("session_id=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax");
    // c.set_cookie("theme=; Path=/; Max-Age=0; SameSite=Lax");
    
    c.delete_cookie("session_id")!!;
    c.delete_cookie("theme")!!;

    return c.text("Logged out. Cookies deleted.");
}

fn Response* old_page(Ctx* c)
{
    // 302 temporary redirect
    return c.redirect("/new-page", 302);
}

fn Response* new_page(Ctx* c)
{
    return c.text("This is the new page");
}

fn Response* permanent_redirect(Ctx* c)
{
    // 301 permanent redirect
    return c.redirect("/new-page", 301);
}

fn Response* http_default_handler(Ctx* c)
{
    return c.text("Hello from ext::httpserver");
}

fn Response* user_file(Ctx* c)
{
    String? user_id = c.param("user_id");
    if (catch err = user_id) {
        c.status(400);
        return c.text("missing user_id");
    }
warn("user_id: %s", user_id);
    String? rest = c.splat();
    if (catch err = rest) {
        c.status(400);
        return c.text("missing file path");
    }

    return c.json(string::tformat(
        "{\"user_id\":\"%s\",\"file\":\"%s\"}",
        user_id,
        rest
    ));
}

fn Response* echo_body(Ctx* c)
{
    if (!c.has_body()) {
        c.status(400);
        return c.text("missing body");
    }

    return c.body_response(c.body());
}

fn Response* login_handler(Ctx* c)
{
    String? username = c.form("username");
    if (catch err = username) {
        c.status(400);
        return c.text("missing username");
    }

    String? password = c.form("password");
    if (catch err = password) {
        c.status(400);
        return c.text("missing password");
    }

    return c.json(string::tformat(
        "{\"username\":\"%s\",\"ok\":true}",
        username
    ));
}

fn Response* echo_text(Ctx* c)
{
    if (!c.req_is_text()) {
        c.status(415);
        return c.text("unsupported media type");
    }

    return c.text(c.req_text());
}

fn Response* echo_json(Ctx* c)
{
    if (!c.req_is_json()) {
        c.status(415);
        return c.text("unsupported media type");
    }

    return c.json(c.req_json_text());
}

fn void http_server_coro()
{
    Application app;
    app.init();
    defer app.free();

    // middleware example
    app.use(&httpserver::middleware_logger);
    app.use(&httpserver::middleware_powered_by);

   // app.get("/", &http_default_handler)!!;
    
    // cookie example
    app.get("/", &index_handler)!!;
    app.get("/profile", &profile_handler)!!;
    app.get("/logout", &logout_handler)!!;

    // redirection example
    app.get("/old-page", &old_page)!!;
    app.get("/new-page", &new_page)!!;
    app.get("/moved", &permanent_redirect)!!;

    // path param and wildcard splat example
    app.get("/users/:user_id/files/*", &user_file)!!;

    // POST body echo
    app.post("/echo", &echo_body)!!;

    // Form example
    app.post("/login", &login_handler)!!;

    // text body example
    app.post("/echo-text", &echo_text)!!;

    // json body example
    app.post("/echo-json", &echo_json)!!;

    app.listen(8080)!!;
}

fn void main()
{
  @assert_leak() {
    asyncio::run(&http_server_coro);
  };
}

/* -----------------------------------
Correspondind curl commands to test this server

```bash
curl -i http://127.0.0.1:8080/
```

Set-Cookie: session_id=abc123; Path=/; HttpOnly; SameSite=Lax
Set-Cookie: theme=dark; Path=/; Max-Age=3600; SameSite=Lax

No session cookie. New cookies were set.

```bash
curl -i -c cookies.txt http://127.0.0.1:8080/
curl -i -b cookies.txt http://127.0.0.1:8080/
```

on second response:

Set-Cookie: last_visit=now; Path=/; Max-Age=3600; SameSite=Lax

session_id cookie received

```bash
curl -i \
  -H 'Cookie: session_id=my-session; theme=dark' \
  http://127.0.0.1:8080/
```

session_id cookie received

```bash
curl -i http://127.0.0.1:8080/profile
```

theme cookie was missing. default theme=light was set.

```bash
curl -i \
  -H 'Cookie: theme=dark' \
  http://127.0.0.1:8080/profile
```

Current theme is dark

```bash
curl -i \
  -H 'Cookie: theme=light' \
  http://127.0.0.1:8080/profile
```

Current theme is not dark

```bash
curl -i http://127.0.0.1:8080/logout
```

Set-Cookie: session_id=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax
Set-Cookie: theme=; Path=/; Max-Age=0; SameSite=Lax

Logged out. Cookies deleted.

```bash
curl -i -c cookies.txt http://127.0.0.1:8080/
curl -i -b cookies.txt http://127.0.0.1:8080/
curl -i -b cookies.txt -c cookies.txt http://127.0.0.1:8080/logout
curl -i -b cookies.txt http://127.0.0.1:8080/
```

No cookie -> cookie set login -> logout -> no cookie


```bash
curl -i http://127.0.0.1:8080/old-page
```

HTTP/1.1 302 Found
Location: /new-page

```bash
curl -i -L http://127.0.0.1:8080/old-page
```

This is the new page 

```bash
curl -i http://127.0.0.1:8080/moved
```

HTTP/1.1 301 Moved Permanently
Location: /new-page

```bash
curl -i http://127.0.0.1:8080/users/kim/files/docs/report.pdf
```

{"user_id":"kim","file":"docs/report.pdf"}

```bash
curl -i 'http://127.0.0.1:8080/users/kim%20lee/files/docs/my%20file.pdf'
```

{"user_id":"kim lee","file":"docs/my file.pdf"}

```bash
curl -i http://127.0.0.1:8080/not-found
```

HTTP/1.1 404 Not Found 

```bash
curl -i -X POST http://127.0.0.1:8080/profile
```

HTTP/1.1 405 Method Not Allowed

```bash 
curl -i -X POST http://127.0.0.1:8080/echo \
  -H 'Content-Type: text/plain' \
  --data 'hello c3'
```

hello c3

```bash
curl -i -X POST http://127.0.0.1:8080/login \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'username=kim%20lee&password=hello+world'
```

{"username":"kim lee","ok":true}


```c3 
curl -i -X POST http://127.0.0.1:8080/echo-text \
  -H 'Content-Type: text/plain' \
  --data 'hello c3 text'
```

hello c3 text

```c3
curl -i -X POST http://127.0.0.1:8080/echo-json \
  -H 'Content-Type: application/json' \
  --data '{"hello":"c3"}'
```

{"hello":"c3"}



*/