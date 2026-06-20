// test_form_all.c3

// application/x-www-form-urlencoded integration tests for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::form_all;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18103;

fn bool contains(char[] a, char[] b) @inline
{
    return ((String)a).contains((String)b);
}

fn sz find_string(String s, String needle) @inline
{
    return s.index_of(needle) ?? -1;
}

fn sz count_occurrences(String s, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= s.len)
    {
        String rest = s[pos..];

        sz? idx = rest.index_of(needle);

        if (catch err = idx)
        {
            break;
        }

        count++;
        pos += (sz)idx + needle.len;
    }

    return count;
}

fn String body_part(String raw)
{
    sz idx = find_string(raw, "\r\n\r\n");
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;
    String prefix = string::bformat(buf[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
}

fn String? fetch_raw(String request, ulong read_timeout_us = 2_000_000)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString out;
    out.init(aio::http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? n = client.read_timeout(buf[..], read_timeout_us);

        if (catch err = n)
        {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            return err~;
        }

        if (n == 0) break;

        out.append(buf[0:n]);
    }

    client.close();

    return out.copy_str(aio::http::localmem);
}


// Handlers

fn Response*? form_basic_handler(Ctx* c)
{
    String? name = c.form("name");

    if (catch err = name)
    {
        c.status(500)!;
        return c.text("missing name")!;
    }

    String? lang = c.form("lang");

    if (catch err = lang)
    {
        c.status(500)!;
        return c.text("missing lang")!;
    }

    if (name != "Nomota Kim")
    {
        c.status(500)!;
        return c.text("bad name")!;
    }

    if (lang != "C3 language")
    {
        c.status(500)!;
        return c.text("bad lang")!;
    }

    return c.text("form-basic-ok")!;
}

fn Response*? form_empty_handler(Ctx* c)
{
    String? empty = c.form("empty");

    if (catch err = empty)
    {
        c.status(500)!;
        return c.text("missing empty")!;
    }

    String? missing_value = c.form("missing");

    if (catch err = missing_value)
    {
        c.status(500)!;
        return c.text("missing missing-value key")!;
    }

    if (empty != "")
    {
        c.status(500)!;
        return c.text("bad empty")!;
    }

    if (missing_value != "")
    {
        c.status(500)!;
        return c.text("bad missing-value")!;
    }

    return c.text("form-empty-ok")!;
}

fn Response*? form_duplicate_handler(Ctx* c)
{
    Query* form = c.forms();

    if (form == null)
    {
        c.status(500)!;
        return c.text("missing form")!;
    }

    sz count = 0;

    if (try form.get("tag"))
    {
        count++;
    }

    // This checks the public first-value behavior.
    String? first = c.form("tag");

    if (catch err = first)
    {
        c.status(500)!;
        return c.text("missing tag")!;
    }

    if (first != "one")
    {
        c.status(500)!;
        return c.text("bad first tag")!;
    }

    // Duplicate preservation is covered if Query exposes iteration/dump elsewhere.
    // Here we mainly ensure duplicate keys do not break parsing.
    return c.text("form-duplicate-ok")!;
}

fn Response*? form_has_handler(Ctx* c)
{
    if (!c.has_form("a"))
    {
        c.status(500)!;
        return c.text("missing a")!;
    }

    if (c.has_form("z"))
    {
        c.status(500)!;
        return c.text("unexpected z")!;
    }

    return c.text("form-has-ok")!;
}

fn Response*? form_unsupported_handler(Ctx* c)
{
    if (c.is_form_urlencoded())
    {
        c.status(500)!;
        return c.text("unexpected form type")!;
    }

    String? value = c.form("a");

    if (catch err = value)
    {
        return c.text("form-unsupported-ok")!;
    }

    c.status(500)!;
    return c.text("unexpected form value")!;
}

fn Response*? form_invalid_handler(Ctx* c)
{
    String? value = c.form("a");

    if (catch err = value)
    {
        c.status(400)!;
        return c.text("invalid-form-ok")!;
    }

    c.status(500)!;
    return c.text("unexpected form value")!;
}

fn Response*? form_empty_body_handler(Ctx* c)
{
    Query* form = c.forms();

    if (form == null)
    {
        c.status(500)!;
        return c.text("missing form")!;
    }

    if (c.has_form("a"))
    {
        c.status(500)!;
        return c.text("unexpected a")!;
    }

    return c.text("form-empty-body-ok")!;
}

// Server task

fn void? server_task(void* arg)
{
    ApplicationServer* server = (ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
}

fn void wake_server()
{
    aio::Stream*? s = aio::stream_connect(HOST, PORT);

    if (catch err = s)
    {
        return;
    }

    s.close();
    s.free();
}

// Tests

fn void? test_form_basic()
{
    String req = make_post(
        "/form-basic",
        "application/x-www-form-urlencoded",
        "name=Nomota+Kim&lang=C3%20language"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-basic-ok"));
}

fn void? test_form_content_type_with_charset()
{
    String req = make_post(
        "/form-basic",
        "application/x-www-form-urlencoded; charset=utf-8",
        "name=Nomota+Kim&lang=C3%20language"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-basic-ok"));
}

fn void? test_form_empty_and_missing_value()
{
    String req = make_post(
        "/form-empty",
        "application/x-www-form-urlencoded",
        "empty=&missing"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-empty-ok"));
}

fn void? test_form_duplicate_keys()
{
    String req = make_post(
        "/form-duplicate",
        "application/x-www-form-urlencoded",
        "tag=one&tag=two&tag=three"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-duplicate-ok"));
}

fn void? test_form_has()
{
    String req = make_post(
        "/form-has",
        "application/x-www-form-urlencoded",
        "a=1&b=2"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-has-ok"));
}

fn void? test_form_unsupported_content_type()
{
    String req = make_post(
        "/form-unsupported",
        "text/plain",
        "a=1"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-unsupported-ok"));
}

fn void? test_form_invalid_percent_short()
{
    String req = make_post(
        "/form-invalid",
        "application/x-www-form-urlencoded",
        "a=%"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 400));
    @assert(contains(body_part(raw), "invalid-form-ok"));
}

fn void? test_form_invalid_percent_hex()
{
    String req = make_post(
        "/form-invalid",
        "application/x-www-form-urlencoded",
        "a=%ZZ"
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 400));
    @assert(contains(body_part(raw), "invalid-form-ok"));
}

fn void? test_form_empty_body()
{
    String req = make_post(
        "/form-empty-body",
        "application/x-www-form-urlencoded",
        ""
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "form-empty-body-ok"));
}

fn String make_post_conn(String path, String content_type, String body, String connection)
{
    char[128] len_buf;
    String content_len = string::bformat(len_buf[..], "%d", body.len);

    return string::format(
        aio::http::localmem,
        "POST %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %s\r\n"
        "Connection: %s\r\n"
        "\r\n"
        "%s",
        path,
        content_type,
        content_len,
        connection,
        body
    );
}

fn String make_post(String path, String content_type, String body)
{
    return make_post_conn(path, content_type, body, "close");
}

fn void? test_form_keepalive_pipeline()
{
    String req1 = make_post_conn(
        "/form-basic",
        "application/x-www-form-urlencoded",
        "name=Nomota+Kim&lang=C3%20language",
        "keep-alive"
    );
    defer aio::http::localmem.free(req1);

    String req2 = make_post_conn(
        "/form-has",
        "application/x-www-form-urlencoded",
        "a=1&b=2",
        "close"
    );
    defer aio::http::localmem.free(req2);

    String both = string::format(
        aio::http::localmem,
        "%s%s",
        req1,
        req2
    );
    defer aio::http::localmem.free(both);

    String raw = fetch_raw(both)!;
    defer aio::http::localmem.free(raw);

    @assert(count_occurrences(raw, "HTTP/1.1 200 OK") == 2);
    @assert(contains(raw, "form-basic-ok"));
    @assert(contains(raw, "form-has-ok"));
    @assert(raw.index_of("form-basic-ok")! < raw.index_of("form-has-ok")!);
}

fn void? test_main(void* arg)
{
    Application app;
    app.init();
    defer app.deinit();

    app.post("/form-basic", &form_basic_handler)!;
    app.post("/form-empty", &form_empty_handler)!;
    app.post("/form-duplicate", &form_duplicate_handler)!;
    app.post("/form-has", &form_has_handler)!;
    app.post("/form-unsupported", &form_unsupported_handler)!;
    app.post("/form-invalid", &form_invalid_handler)!;
    app.post("/form-empty-body", &form_empty_body_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_form_basic()!;
    test_form_content_type_with_charset()!;
    test_form_empty_and_missing_value()!;
    test_form_duplicate_keys()!;
    test_form_has()!;
    test_form_unsupported_content_type()!;
    test_form_invalid_percent_short()!;
    test_form_invalid_percent_hex()!;
    test_form_empty_body()!;
    test_form_keepalive_pipeline()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    warn("OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof