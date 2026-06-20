// test_advanced_all.c3

// Advanced integration tests for multipart parser,
// chunked request edge cases, read timeout,
// file/stat compatibility, server lifecycle,
// and duplicate Set-Cookie behavior.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::advanced_all;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::aio::path;
import ext::io::stat;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18099;

const String ROOT = "zz_advanced_all";
const String FILE_PATH = "zz_advanced_all/file.txt";
const String BIN_PATH = "zz_advanced_all/bin.dat";
const String DIR_PATH = "zz_advanced_all/dir";
const String LINK_PATH = "zz_advanced_all/link.txt";

fn bool contains(char[] a, char[] b) @inline
{
    return ((String)a).contains((String)b);
}
 
fn sz find_string(String s, String needle) @inline
{
    return s.index_of(needle) ?? -1;
}

fn String body_part(String raw)
{
    sz idx = find_string(raw, "\r\n\r\n");
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool has_header(String raw, String header)
{
    return contains(raw, header);
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;
    String prefix = string::bformat(buf[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
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

fn void cleanup_files()
{
    if (catch path::remove(LINK_PATH)) {}
    if (catch path::remove(FILE_PATH)) {}
    if (catch path::remove(BIN_PATH)) {}

    char[256] cmd;
    string::bformat(cmd[..], "rm -rf %s", ROOT);
    stdlib::system(&cmd[0]);
}

fn void? write_all_file(String file_path, char[] data)
{
    aio::File* f = aio::file_open(file_path, "wb")!;
    defer f.close();

    sz total = 0;

    while (total < data.len)
    {
        sz n = f.write(data[total:data.len - total])!;

        if (n <= 0)
        {
            return aio::http::HTTP_WRITE_ERROR~;
        }

        total += n;
    }
}

fn void? setup_files()
{
    cleanup_files();

    path::makedirs(ROOT, 0o777, true)!;
    path::makedirs(DIR_PATH, 0o777, true)!;

    write_all_file(FILE_PATH, (char[])"advanced file")!;
}

fn String? fetch_raw(String request)
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
        sz? n = client.read_timeout(buf[..], 2_000_000);

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

fn String? fetch_raw_split(String[] parts, ulong delay_us = 20_000)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    bool write_failed = false;
    fault write_error = aio::NONE;

    for (sz i = 0; i < parts.len; i++)
    {
        if (catch err = client.write_all((char[])parts[i]))
        {
            write_failed = true;
            write_error = err;
            break;
        }

        if (delay_us > 0)
        {
            aio::sleep((uint)(delay_us / 1000))!;
        }
    }

    DString out;
    out.init(aio::http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? n = client.read_timeout(buf[..], 2_000_000);

        if (catch err = n)
        {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            if (write_failed)
            {
                warn("split write failed first: %s", write_error);
                break;
            }

            return err~;
        }

        if (n == 0) break;

        out.append(buf[0:n]);
    }

    client.close();

    String raw = out.copy_str(aio::http::localmem);

    if (write_failed)
    {
        warn("split write failed: %s", write_error);
        warn("partial response:\n%s", raw);
    }

    return raw;
}

// Handlers

fn Response*? chunked_echo_handler(Ctx* c)
{
    char[] body = c.body();

    if ((String)body != "Wikipedia")
    {
        c.status(500)!;
        return c.text("bad chunked body")!;
    }

    return c.text("chunked-ok")!;
}

fn Response*? chunked_upper_echo_handler(Ctx* c)
{
    char[] body = c.body();

    if ((String)body != "0123456789")
    {
        c.status(500)!;
        return c.text("bad chunked uppercase body")!;
    }

    return c.text("chunked-upper-ok")!;
}

fn Response*? multipart_parser_handler(Ctx* c)
{
//warn("-");
//c.dump();
//warn("-");
    String? field = c.multipart_value("field");
    if (catch err = field)
    {
        c.status(500)!;
        return c.text("missing parsed 'field'")!;
    }

    if (field != "hello multipart")
    {
        c.status(500)!;
        return c.text("bad parsed field")!;
    }

    String? second = c.multipart_value("second");
    if (catch err = second)
    {
        c.status(500)!;
        return c.text("missing 'second' field")!;
    }

    if (second != "two")
    {
        c.status(500)!;
        return c.text("bad second field")!;
    }

    return c.text("multipart-parser-ok")!;
}

fn Response*? multipart_file_handler(Ctx* c)
{
    MultipartPart* file = c.multipart_file_ref("upload");

    if (file == null)
    {
        c.status(500)!;
        return c.text("missing file")!;
    }

    if (file.filename != "hello world.txt")
    {
        c.status(500)!;
        return c.text("bad filename")!;
    }

    if (file.content_type != "text/plain")
    {
        c.status(500)!;
        return c.text("bad file content-type")!;
    }

    if (file.text() != "file body")
    {
        c.status(500)!;
        return c.text("bad file body")!;
    }

    return c.text("multipart-file-ok")!;
}

fn Response*? multipart_raw_guard_handler(Ctx* c)
{
    String? content_type = c.req_header("Content-Type");

    if (catch err = content_type)
    {
        c.status(400)!;
        return c.text("missing content-type")!;
    }

    if (!content_type.contains("multipart/form-data"))
    {
        c.status(400)!;
        return c.text("bad content-type")!;
    }

    char[] body = c.body();

    if (!contains(body, "name=\"field\"") || !contains(body, "hello multipart"))
    {
        c.status(500)!;
        return c.text("bad raw multipart body")!;
    }

    return c.text("multipart-raw-ok")!;
}

fn Response*? cookie_handler(Ctx* c)
{
    c.set_cookie("sid=abc; Path=/; HttpOnly; SameSite=Lax")!;
    c.set_cookie("theme=dark; Path=/; Max-Age=3600")!;

    return c.text("cookie-ok")!;
}

fn Response*? hello_handler(Ctx* c)
{
    return c.text("hello")!;
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

// 1. Multipart parser-level

fn void? test_multipart_parser_level()
{
    String body =
        "--AaB03x\r\n"
        "Content-Disposition: form-data; name=\"field\"\r\n"
        "\r\n"
        "hello multipart\r\n"
        "--AaB03x\r\n"
        "Content-Disposition: form-data; name=\"second\"\r\n"
        "\r\n"
        "two\r\n"
        "--AaB03x--\r\n";

    char[128] len_buf;
    String content_len = string::bformat(len_buf[..], "%d", body.len);

    String req = string::format(
        aio::http::localmem,
        "POST /multipart-parser HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=AaB03x\r\n"
        "Content-Length: %s\r\n"
        "Connection: close\r\n"
        "\r\n"
        "%s",
        content_len,
        body
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);
//warn("%s", raw);
    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "multipart-parser-ok"));
}

fn void? test_multipart_raw_guard()
{
    String body =
        "--BbC04y\r\n"
        "Content-Disposition: form-data; name=\"field\"\r\n"
        "\r\n"
        "hello multipart\r\n"
        "--BbC04y--\r\n";

    char[128] len_buf;
    String content_len = string::bformat(len_buf[..], "%d", body.len);

    String req = string::format(
        aio::http::localmem,
        "POST /multipart-raw HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; boundary=BbC04y\r\n"
        "Content-Length: %s\r\n"
        "Connection: close\r\n"
        "\r\n"
        "%s",
        content_len,
        body
    );
    defer aio::http::localmem.free(req);

    String raw = fetch_raw(req)!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "multipart-raw-ok"));
}

// 2. Chunked request split-read / edge cases

fn void? test_chunked_request_split_reads()
{
    String[4] parts = {
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4\r\n",

        "Wiki\r\n",

        "5\r\npedia\r\n",

        "0\r\n\r\n",
    };

    String raw = fetch_raw_split(parts[..])!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "chunked-ok"));
}

fn void? test_chunked_request_extension_and_uppercase_hex()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4;ext=value\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "chunked-ok"));
}

fn void? test_chunked_request_malformed_size()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "Z\r\n"
        "bad\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 400));
}

// 3. Read timeout / slow client

fn void? test_read_timeout_incomplete_headers()
{
    ulong old_timeout = aio::http::http_get_read_timeout_us();
    aio::http::http_set_read_timeout_us(200_000);
    defer aio::http::http_set_read_timeout_us(old_timeout);

    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])"GET /hello HTTP/1.1\r\nHost: localhost\r\n")!;

    DString out;
    out.init(aio::http::localmem, 4096);
    defer out.free();

    char[4096] buf;

    while (true)
    {
        sz? n = client.read_timeout(buf[..], 1_500_000);

        if (catch err = n)
        {
            if (err == aio::TIMEOUT) break;
            if (err == aio::CLOSED) break;

            return err~;
        }

        if (n == 0) break;

        out.append(buf[0:n]);
    }

    String raw = out.str_view();

    @assert(status_is(raw, 408));

    client.close();
}

// 4. File/stat compatibility

fn void? test_file_open_modes_and_statinfo()
{
    aio::File* wf = aio::file_open(BIN_PATH, "wb")!;
    defer wf.close();

    char[] data = (char[])"abc123";
    sz written = wf.write(data)!;
    @assert(written == data.len);

    aio::File* rf = aio::file_open(BIN_PATH, "rb")!;
    defer rf.close();

    char[32] buf;
    sz n = rf.read(buf[..])!;

    @assert(n == data.len);
    @assert((String)buf[0:n] == "abc123");

    stat::StatInfo file_info = path::statinfo(BIN_PATH)!;

    @assert(file_info.is_file);
    @assert(!file_info.is_dir);
    @assert(!file_info.is_link);
    @assert(file_info.size == data.len);

    stat::StatInfo dir_info = path::statinfo(DIR_PATH)!;

    @assert(!dir_info.is_file);
    @assert(dir_info.is_dir);
    @assert(!dir_info.is_link);

    if (catch path::remove(LINK_PATH)) {}

    if (catch path::symlink("bin.dat", LINK_PATH))
    {
        return;
    }

    stat::StatInfo link_info = path::statinfo(LINK_PATH)!;

    @assert(link_info.is_link);
}

// 5. Server lifecycle deterministic test

fn void? test_server_is_alive()
{
    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "hello"));
}

fn void? test_server_is_stopped()
{
    aio::Stream*? client = aio::stream_connect(HOST, PORT);

    if (catch err = client)
    {
        return;
    }

    client.close();
    client.free();

    @assert(false);
}

// 6. Cookie attributes / duplicate Set-Cookie

fn void? test_duplicate_set_cookie_response_serialize()
{
    Response* res = aio::http::response_text("ok")!;
    defer aio::http::response_free(res);

    res.set_cookie("sid=abc; Path=/; HttpOnly; SameSite=Lax")!;
    res.set_cookie("theme=dark; Path=/; Max-Age=3600")!;

    String wire = res.serialize()!;
    defer aio::http::localmem.free(wire);

    @assert(count_occurrences(wire, "Set-Cookie: ") == 2);
    @assert(contains(wire, "Set-Cookie: sid=abc; Path=/; HttpOnly; SameSite=Lax\r\n"));
    @assert(contains(wire, "Set-Cookie: theme=dark; Path=/; Max-Age=3600\r\n"));
}

fn void? test_duplicate_set_cookie_wire()
{
    String raw = fetch_raw(
        "GET /cookie HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(count_occurrences(raw, "Set-Cookie: ") == 2);
    @assert(contains(raw, "Set-Cookie: sid=abc; Path=/; HttpOnly; SameSite=Lax\r\n"));
    @assert(contains(raw, "Set-Cookie: theme=dark; Path=/; Max-Age=3600\r\n"));
    @assert(contains(body_part(raw), "cookie-ok"));
}

fn void? test_chunked_request_uppercase_hex()
{
    String raw = fetch_raw(
        "POST /chunked-upper HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "A\r\n"
        "0123456789\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer aio::http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "chunked-upper-ok"));
}

fn void? test_main(void* arg)
{
    setup_files()!;

    test_file_open_modes_and_statinfo()!;
    test_duplicate_set_cookie_response_serialize()!;

    Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!;
    app.get("/cookie", &cookie_handler)!;

    app.post("/chunked", &chunked_echo_handler)!;
    app.post("/multipart-parser", &multipart_parser_handler)!;
    app.post("/multipart-raw", &multipart_raw_guard_handler)!;
    app.post("/chunked-upper", &chunked_upper_echo_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_server_is_alive()!;

    test_multipart_parser_level()!;
    test_multipart_raw_guard()!;
//warn("-");
    test_chunked_request_split_reads()!;
//warn("-");
    test_chunked_request_uppercase_hex()!;
    test_chunked_request_extension_and_uppercase_hex()!;
//warn("-");
    test_chunked_request_malformed_size()!;
//warn("-");
    test_read_timeout_incomplete_headers()!;
//warn("-");
    test_duplicate_set_cookie_wire()!;
//warn("-");
    server.stop()!;
    wake_server();
    server.wait_closed()!;

    test_server_is_stopped()!;

    cleanup_files();

    warn("OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof