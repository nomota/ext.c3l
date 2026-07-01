// test_advanced_all.c3

// Advanced integration tests for multipart parsing,
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

fn bool contains(char[] text, char[] needle) @inline
{
    return ((String)text).contains((String)needle);
}

fn String body_part(String raw)
{
    sz idx = raw.index_of("\r\n\r\n") ?? -1;
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;
    String prefix = string::bformat(buf[..], "HTTP/1.1 %d ", status);

    return raw.starts_with(prefix);
}

fn sz count_occurrences(String text, String needle)
{
    if (needle.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos + needle.len <= text.len)
    {
        sz idx = text[pos..].index_of(needle) ?? -1;
        if (idx < 0) break;

        count++;
        pos += idx + needle.len;
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
    aio::File* file = aio::file_open(file_path, "wb")!;
    defer file.close();

    sz total = 0;

    while (total < data.len)
    {
        sz n = file.write(data[total:data.len - total])!;

        if (n <= 0)
        {
            return http::WRITE_ERROR~;
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
    out.init(http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? read_result = client.read_timeout(buf[..], 2_000_000);

        if (catch err = read_result)
        {
            if (err == aio::TIMEOUT || err == aio::CLOSED) break;

            return err~;
        }

        sz n = read_result;
        if (n == 0) break;

        out.append(buf[0:n]);
    }

    return out.copy_str(http::localmem);
}

fn String? fetch_raw_split(String[] parts, ulong delay_us = 20_000)
{
    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    for (sz i = 0; i < parts.len; i++)
    {
        client.write_all((char[])parts[i])!;

        if (delay_us > 0 && i + 1 < parts.len)
        {
            aio::sleep((uint)(delay_us / 1000))!;
        }
    }

    DString out;
    out.init(http::localmem, 4096);
    defer catch out.free();

    char[4096] buf;

    while (true)
    {
        sz? read_result = client.read_timeout(buf[..], 2_000_000);

        if (catch err = read_result)
        {
            if (err == aio::TIMEOUT || err == aio::CLOSED) break;

            return err~;
        }

        sz n = read_result;
        if (n == 0) break;

        out.append(buf[0:n]);
    }

    return out.copy_str(http::localmem);
}

// Handlers

fn Response*? chunked_echo_handler(Ctx* c)
{
    if ((String)c.body() != "Wikipedia")
    {
        c.status(500)!;
        return c.text("bad chunked body")!;
    }

    return c.text("chunked-ok")!;
}

fn Response*? chunked_upper_echo_handler(Ctx* c)
{
    if ((String)c.body() != "0123456789")
    {
        c.status(500)!;
        return c.text("bad chunked uppercase body")!;
    }

    return c.text("chunked-upper-ok")!;
}

fn Response*? multipart_parser_handler(Ctx* c)
{
    String? field_result = c.multipart_value("field");

    if (catch field_error = field_result)
    {
        c.status(500)!;
        return c.text("missing parsed 'field'")!;
    }

    String field = field_result;

    if (field != "hello multipart")
    {
        c.status(500)!;
        return c.text("bad parsed field")!;
    }

    String? second_result = c.multipart_value("second");

    if (catch second_error = second_result)
    {
        c.status(500)!;
        return c.text("missing 'second' field")!;
    }

    String second = second_result;

    if (second != "two")
    {
        c.status(500)!;
        return c.text("bad second field")!;
    }

    return c.text("multipart-parser-ok")!;
}

fn Response*? multipart_raw_guard_handler(Ctx* c)
{
    String? content_type_result = c.req_header("Content-Type");

    if (catch header_error = content_type_result)
    {
        c.status(400)!;
        return c.text("missing content-type")!;
    }

    String content_type = content_type_result;

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
        if (!server.closed)
        {
            warn("server failed: %s", err);
            return err~;
        }
    }
}

fn void wake_server()
{
    aio::Stream*? stream_result = aio::stream_connect(HOST, PORT);

    if (catch connect_error = stream_result)
    {
        return;
    }

    aio::Stream* stream = stream_result;
    stream.close();
    stream.free();
}

// Multipart tests

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

    String request = string::format(
        http::localmem,
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
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

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

    String request = string::format(
        http::localmem,
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
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "multipart-raw-ok"));
}

// Chunked request tests

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
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "chunked-ok"));
}

fn void? test_chunked_request_extension()
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
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "chunked-ok"));
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
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "chunked-upper-ok"));
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
    defer http::localmem.free(raw);

    @assert(status_is(raw, 400));
}

// Read timeout test

fn void? test_read_timeout_incomplete_headers()
{
    ulong old_timeout = http::get_read_timeout_us();
    http::set_read_timeout_us(200_000);
    defer http::set_read_timeout_us(old_timeout);

    aio::Stream* client = aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])"GET /hello HTTP/1.1\r\nHost: localhost\r\n")!;

    DString out;
    out.init(http::localmem, 4096);
    defer out.free();

    char[4096] buf;

    while (true)
    {
        sz? read_result = client.read_timeout(buf[..], 1_500_000);

        if (catch err = read_result)
        {
            if (err == aio::TIMEOUT || err == aio::CLOSED) break;

            return err~;
        }

        sz n = read_result;
        if (n == 0) break;

        out.append(buf[0:n]);
    }

    @assert(status_is(out.str_view(), 408));
}

// File/stat compatibility test

fn void? test_file_open_modes_and_statinfo()
{
    aio::File* write_file = aio::file_open(BIN_PATH, "wb")!;

    char[] data = (char[])"abc123";
    sz written = write_file.write(data)!;

    @assert(written == data.len);

    write_file.close();

    aio::File* read_file = aio::file_open(BIN_PATH, "rb")!;

    char[32] buf;
    sz n = read_file.read(buf[..])!;

    read_file.close();

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

// Server lifecycle tests

fn void? test_server_is_alive()
{
    String raw = fetch_raw(
        "GET /hello HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(contains(body_part(raw), "hello"));
}

fn void? test_server_is_stopped()
{
    aio::Stream*? client_result = aio::stream_connect(HOST, PORT);

    if (catch connect_error = client_result)
    {
        return;
    }

    aio::Stream* client = client_result;
    client.close();
    client.free();

    @assert(false);
}

// Duplicate Set-Cookie tests

fn void? test_duplicate_set_cookie_response_serialize()
{
    Response* response = http::response_text("ok")!;
    defer http::response_free(response);

    response.set_cookie("sid=abc; Path=/; HttpOnly; SameSite=Lax")!;
    response.set_cookie("theme=dark; Path=/; Max-Age=3600")!;

    String wire = response.serialize()!;
    defer http::localmem.free(wire);

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
    defer http::localmem.free(raw);

    @assert(status_is(raw, 200));
    @assert(count_occurrences(raw, "Set-Cookie: ") == 2);
    @assert(contains(raw, "Set-Cookie: sid=abc; Path=/; HttpOnly; SameSite=Lax\r\n"));
    @assert(contains(raw, "Set-Cookie: theme=dark; Path=/; Max-Age=3600\r\n"));
    @assert(contains(body_part(raw), "cookie-ok"));
}

fn void? test_main(void* arg)
{
    setup_files()!;
    defer cleanup_files();

    test_file_open_modes_and_statinfo()!;
    test_duplicate_set_cookie_response_serialize()!;

    Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!;
    app.get("/cookie", &cookie_handler)!;

    app.post("/chunked", &chunked_echo_handler)!;
    app.post("/chunked-upper", &chunked_upper_echo_handler)!;
    app.post("/multipart-parser", &multipart_parser_handler)!;
    app.post("/multipart-raw", &multipart_raw_guard_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_server_is_alive()!;

    test_multipart_parser_level()!;
    test_multipart_raw_guard()!;

    test_chunked_request_split_reads()!;
    test_chunked_request_uppercase_hex()!;
    test_chunked_request_extension()!;
    test_chunked_request_malformed_size()!;

    test_read_timeout_incomplete_headers()!;
    test_duplicate_set_cookie_wire()!;

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    test_server_is_stopped()!;

    warn("OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof