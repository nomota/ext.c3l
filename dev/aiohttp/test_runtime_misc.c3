// test_runtime_misc.c3

// Tests server shutdown, statinfo, and duplicate Set-Cookie behavior.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::runtime_misc;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::aio::path;
import ext::io::stat;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18098;

const String ROOT = "zz_runtime_misc";
const String FILE_PATH = "zz_runtime_misc/file.txt";
const String DIR_PATH = "zz_runtime_misc/dir";
const String LINK_PATH = "zz_runtime_misc/link.txt";

fn bool contains(char[] a, char[] b) @inline
{
    return ((String)a).contains((String)b);
}

fn sz find_string(String s, String needle)
{
    return s.index_of(needle) ?? -1;
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

fn void? write_all_file(String file_path, char[] data)
{
    aio::File* f = aio::file_open(file_path, "w")!;
    defer f.close();

    sz total = 0;

    while (total < data.len)
    {
        sz n = f.write(data[total:data.len - total])!;

        if (n <= 0)
        {
            return http::STATIC_READ_ERROR~;
        }

        total += n;
    }
}

fn void cleanup_files()
{
    if (catch path::remove(LINK_PATH)) {}
    if (catch path::remove(FILE_PATH)) {}

    char[256] cmd;
    string::bformat(cmd[..], "rm -rf %s > /dev/null", ROOT);
    stdlib::system(&cmd[0]);
}

fn void? setup_files()
{
    cleanup_files();

    path::makedirs(ROOT, 0o777, true)!;
    path::makedirs(DIR_PATH, 0o777, true)!;

    write_all_file(FILE_PATH, (char[])"runtime misc file")!;
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

    return out.copy_str(http::localmem);
}

fn Response*? hello_handler(Ctx* c)
{
    return c.text("hello")!;
}

fn Response*? cookie_handler(Ctx* c)
{
    c.set_cookie("a=1; Path=/")!;
    c.set_cookie("b=2; Path=/")!;

    return c.text("cookie-ok")!;
}

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

fn void? test_statinfo()
{
    stat::StatInfo file_info = path::statinfo(FILE_PATH)!;

    @assert(file_info.is_file);
    @assert(!file_info.is_dir);
    @assert(!file_info.is_link);
    @assert(file_info.size == "runtime misc file".len);

    stat::StatInfo dir_info = path::statinfo(DIR_PATH)!;

    @assert(!dir_info.is_file);
    @assert(dir_info.is_dir);
    @assert(!dir_info.is_link);

    if (catch path::remove(LINK_PATH)) {}

    if (catch path::symlink("file.txt", LINK_PATH))
    {
        return;
    }

    stat::StatInfo link_info = path::statinfo(LINK_PATH)!;

    @assert(link_info.is_link);
}

fn void? test_set_cookie_duplicate()
{
    Response* res = http::response_text("ok")!;
    defer http::response_free(res);

    res.set_cookie("a=1; Path=/")!;
    res.set_cookie("b=2; Path=/")!;

    String wire = res.serialize()!;
    defer http::localmem.free(wire);

    @assert(count_occurrences(wire, "Set-Cookie: ") == 2);
    @assert(contains(wire, "Set-Cookie: a=1; Path=/\r\n"));
    @assert(contains(wire, "Set-Cookie: b=2; Path=/\r\n"));
}

fn void? test_set_cookie_wire()
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
    @assert(contains(raw, "Set-Cookie: a=1; Path=/\r\n"));
    @assert(contains(raw, "Set-Cookie: b=2; Path=/\r\n"));
    @assert(contains(body_part(raw), "cookie-ok"));
}

fn void? test_server_shutdown(ApplicationServer* server)
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

    server.stop()!;
    wake_server();
    server.wait_closed()!;

    aio::Stream*? client = aio::stream_connect(HOST, PORT);

    if (catch err = client)
    {
        return;
    }

    client.close();
    client.free();

    @assert(false);
}

fn void? test_main(void* arg)
{
    setup_files()!;

    test_statinfo()!;
    test_set_cookie_duplicate()!;

    Application app;
    app.init();
    defer app.deinit();

    app.get("/hello", &hello_handler)!;
    app.get("/cookie", &cookie_handler)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;
    aio::sleep(200)!;

    test_set_cookie_wire()!;
    test_server_shutdown(&server)!;

    cleanup_files();

    warn("OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof