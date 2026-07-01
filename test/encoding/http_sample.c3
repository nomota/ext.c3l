// http_sample.c3
// ext::encoding::http usage examples

module http_sample;

import ext::encoding::http;
import std::io;
import ext::debug;


// 
// 1. Basic GET request parsing
// 

fn void example_get_request()
{
    io::printfn("1. Basic GET request parsing");
    char[] raw = "GET /search?q=hello&lang=en HTTP/1.1\r\n"
                 "Host: example.com\r\n"
                 "User-Agent: Mozilla/5.0\r\n"
                 "Accept: text/html\r\n"
                 "Cookie: session=abc123; theme=dark\r\n"
                 "\r\n";

    http::Request req;
    char*? result = http::parse_request(raw.ptr, raw.ptr + raw.len, &req);
    if (catch err = result) {
        warn("parse error: %s", err);
        return;
    }

    io::printfn("=== GET Request ===");
    io::printfn("Method  : %s", req.method);   // GET
    io::printfn("URI     : %s", req.uri);       // /search?q=hello&lang=en
    io::printfn("Version : %s", req.version);   // 1.1

    // Headers
    io::printfn("--- Headers (%d) ---", req.n_headers);
    for (uint i = 0; i < req.n_headers; i++) {
        io::printfn("  %s: %s", req.headers[i].key, req.headers[i].value);
    }

    // URI decode → fills req.url
    req.decode_uri();
    io::printfn("--- URL ---");
    io::printfn("  host     : %s", req.url.host);      // example.com
    io::printfn("  path     : %s", req.url.path);      // /search
    io::printfn("  query    : %s", req.url.query);     // q=hello&lang=en

    // Query string → fills req.queries
    req.decode_query();
    io::printfn("--- Query (%d) ---", req.n_queries);
    for (sz i = 0; i < req.n_queries; i++) {
        io::printfn("  %s = %s", req.queries[i].key, req.queries[i].value);
        // q = hello
        // lang = en
    }

    // Cookies → fills req.cookies
    req.decode_cookies();
    io::printfn("--- Cookies (%d) ---", req.n_cookies);
    for (uint i = 0; i < req.n_cookies; i++) {
        io::printfn("  %s = %s", req.cookies[i].key, req.cookies[i].value);
        // session = abc123
        // theme   = dark
    }
}

// 
// 2. POST request — application/x-www-form-urlencoded
// 

fn void example_post_urlencoded()
{
    io::printfn("2. POST request, form data");
    char[] raw = "POST /login HTTP/1.1\r\n"
                 "Host: example.com\r\n"
                 "Content-Type: application/x-www-form-urlencoded\r\n"
                 "Content-Length: 27\r\n"
                 "\r\n"
                 "username=alice&password=1234";

    http::Request req;
    if (catch err = http::parse_request(raw.ptr, raw.ptr + raw.len, &req)) {
        warn("parse error: %s", err);
        return;
    }

    io::printfn("=== POST URL-encoded ===");

    // Content-Length / chunked → fills req.content_length
    req.decode_content_length();
    io::printfn("Content-Length: %d", req.content_length);  // 27

    // Form fields → fills req.form
    req.decode_form();
    io::printfn("--- Form (%d) ---", req.n_form);
    for (sz i = 0; i < req.n_form; i++) {
        io::printfn("  %s = %s", req.form[i].key, req.form[i].value);
        // username = alice
        // password = 1234
    }
}

// 
// 3. POST request — multipart/form-data (file upload)
// 

fn void example_post_multipart()
{
    io::printfn("3. POST request, file upload");
    char[] raw =
        "POST /upload HTTP/1.1\r\n"
        "Host: example.com\r\n"
        "Content-Type: multipart/form-data; boundary=----Boundary7MA\r\n"
        "Content-Length: 228\r\n"
        "\r\n"
        "------Boundary7MA\r\n"
        "Content-Disposition: form-data; name=\"title\"\r\n"
        "\r\n"
        "My Document\r\n"
        "------Boundary7MA\r\n"
        "Content-Disposition: form-data; name=\"file\"; filename=\"doc.txt\"\r\n"
        "Content-Type: text/plain\r\n"
        "\r\n"
        "Hello, world!\r\n"
        "------Boundary7MA--\r\n";

    http::Request req;
    if (catch err = http::parse_request(raw.ptr, raw.ptr + raw.len, &req)) {
        warn("parse error: %s", err);
        return;
    }

    io::printfn("=== POST Multipart ===");

    req.decode_content_length();
    req.decode_form();  // must call decode_content_length first

    // Text fields
    io::printfn("--- Form fields (%d) ---", req.n_form);
    for (sz i = 0; i < req.n_form; i++) {
        io::printfn("  %s = %s", req.form[i].key, req.form[i].value);
        // title = My Document
    }

    // File uploads
    io::printfn("--- Files (%d) ---", req.n_files);
    for (uint i = 0; i < req.n_files; i++) {
        http::FormFile* f = &req.files[i];
        io::printfn("  field    : %s", f.name);      // file
        io::printfn("  filename : %s", f.filename);  // doc.txt
        io::printfn("  mime     : %s", f.mime);      // text/plain
        io::printfn("  size     : %d bytes", f.data.len);
        io::printfn("  content  : %s", f.data);      // Hello, world!
    }
}

// 
// 4. Chunked transfer-encoding detection
// 

fn void example_chunked_request()
{
    io::printfn("4. Chunked transfer-encoding");
    char[] raw = "POST /data HTTP/1.1\r\n"
                 "Host: example.com\r\n"
                 "Transfer-Encoding: gzip, chunked\r\n"
                 "\r\n";

    http::Request req;
    if (catch err = http::parse_request(raw.ptr, raw.ptr + raw.len, &req)) {
        warn("parse error: %s", err);
        return;
    }

    req.decode_content_length();

    io::printfn("=== Chunked ===");
    io::printfn("chunked : %s", req.chunked ? "true" : "false");  // true
}

// 
// 5. HTTP response parsing + Set-Cookie decode
// 

fn void example_response()
{
    io::printfn("5. HTTP response, Set-Cookie");
    
    char[] raw = "HTTP/1.1 200 OK\r\n"
                 "Content-Type: text/html; charset=utf-8\r\n"
                 "Content-Length: 13\r\n"
                 "Set-Cookie: session=xyz789; Path=/; HttpOnly; Secure\r\n"
                 "Set-Cookie: lang=ko; Path=/; Max-Age=86400; SameSite=Lax\r\n"
                 "\r\n"
                 "Hello, world!";

    http::Response resp;
    if (catch err = http::parse_response(raw.ptr, raw.ptr + raw.len, &resp)) {
        warn("parse error: %s", err);
        return;
    }

    io::printfn("=== Response ===");
    io::printfn("Status  : %s", resp.status);   // 200
    io::printfn("Message : %s", resp.message);  // OK
    io::printfn("Body    : %s", (String)resp.body[0:13]);  // Hello, world!

    // Set-Cookie headers
    resp.decode_setcookies();
    io::printfn("--- Set-Cookie (%d) ---", resp.n_set_cookies);
    for (sz i = 0; i < resp.n_set_cookies; i++) {
        http::SetCookie* sc = &resp.set_cookies[i];
        io::printfn("  name      : %s", sc.name);
        io::printfn("  value     : %s", sc.value);
        io::printfn("  path      : %s", sc.path);
        io::printfn("  max_age   : %s", sc.max_age);
        io::printfn("  same_site : %s", sc.same_site);
        io::printfn("  http_only : %s", sc.http_only ? "true" : "false");
        io::printfn("  secure    : %s", sc.secure    ? "true" : "false");
        io::printfn("  ---");
        // i=0: session=xyz789; HttpOnly=true; Secure=true
        // i=1: lang=ko; Max-Age=86400; SameSite=Lax
    }
}

// 
// 6. Fault handling — INCOMPLETE vs ERROR
// 

fn void example_fault_handling()
{
    io::printfn("6. Fault handlng");
    // Truncated — only the request line, headers not yet received
    char[] partial = "GET /index.html HTTP/1.1\r\nHost: examp";

    http::Request req;
    if (catch err = http::parse_request(partial.ptr, partial.ptr + partial.len, &req)) {
        switch (err) {
            case http::INCOMPLETE:
                warn("need more data — buffer the socket and retry");
            case http::ERROR:
                warn("malformed request — close the connection");
            default:
                warn("unexpected fault: %s", err);
        }
        return;
    }
}

// 
// 7. URL parsing — full absolute URI
// 

fn void example_url_parsing()
{
    io::printfn("7. URL parsing");
    // Simulate a CONNECT / proxy request with an absolute URI
    char[] raw = "GET https://user:pass@api.example.com:8080/v1/items?page=2#top HTTP/1.1\r\n"
                 "Host: api.example.com:8080\r\n"
                 "\r\n";

    http::Request req;
    if (catch err = http::parse_request(raw.ptr, raw.ptr + raw.len, &req)) {
        warn("parse error: %s", err);
        return;
    }

    req.decode_uri();

    io::printfn("=== URL Parsing ===");
    http::Url* u = &req.url;
    io::printfn("protocol : %s", u.protocol);  // https
    io::printfn("user     : %s", u.user);       // user
    io::printfn("password : %s", u.password);   // pass
    io::printfn("host     : %s", u.host);       // api.example.com
    io::printfn("port     : %s", u.port);       // 8080
    io::printfn("path     : %s", u.path);       // /v1/items
    io::printfn("query    : %s", u.query);      // page=2
    io::printfn("fragment : %s", u.fragment);   // top
}

fn void main()
{
    example_get_request();
    io::printn("");
    example_post_urlencoded();
    io::printn("");
    example_post_multipart();
    io::printn("");
    example_chunked_request();
    io::printn("");
    example_response();
    io::printn("");
    example_fault_handling();
    io::printn("");
    example_url_parsing();
}
