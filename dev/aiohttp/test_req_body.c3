// test_req_body.c3

// Tests chunked request body, multipart wire edge cases,
// and static content-type behavior.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::req_body;

import std::io;
import c::stdlib;
import ext::aio;
import ext::aio::http;
import ext::aio::path;
import ext::debug;

const String HOST = "127.0.0.1";
const ushort PORT = 18097;

const sz MAX_RESPONSE_BYTES = 1024 * 1024;

const String ROOT = "zz_root";
const String HTML_FILE = "zz_root/index.html";
const String CSS_FILE = "zz_root/app.css";
const String JS_FILE = "zz_root/app.js";
const String JSON_FILE = "zz_root/data.json";
const String PNG_FILE = "zz_root/image.png";
const String WASM_FILE = "zz_root/module.wasm";

fn String body_part(String raw)
{
    sz idx = raw.index_of("\r\n\r\n") ?? -1;
    if (idx < 0) return "";

    return raw[idx + 4..];
}

fn bool has_header(String raw, String header)
{
    return raw.contains(header);
}

fn bool status_is(String raw, ushort status)
{
    char[64] buf;

    String prefix = string::bformat(
        buf[..],
        "HTTP/1.1 %d ",
        status
    );

    return raw.starts_with(prefix);
}

fn sz? response_content_length(String header_block)
{
    sz pos = 0;

    while (pos < header_block.len)
    {
        sz line_end =
            header_block[pos..].index_of("\r\n") ?? -1;

        String line;

        if (line_end < 0)
        {
            line = header_block[pos..];
            pos = header_block.len;
        }
        else
        {
            line = header_block[pos:line_end];
            pos += line_end + 2;
        }

        if (line.len == 0) continue;

        sz colon = line.index_of(":") ?? -1;
        if (colon <= 0) continue;

        String name = line[0:colon];
        String value = line[colon + 1..].trim();

        if (!http::str_iequals(name, "Content-Length"))
        {
            continue;
        }

        sz content_length = value.to_long()!;

        if (content_length < 0)
        {
            return http::BAD_REQUEST~;
        }

        return content_length;
    }

    return http::NOT_FOUND~;
}

fn sz? response_expected_total_len(String response)
{
    sz header_end =
        response.index_of("\r\n\r\n") ?? -1;

    if (header_end < 0)
    {
        return http::BODY_INCOMPLETE~;
    }

    String header_block = response[0:header_end];

    sz content_length =
        response_content_length(header_block)!;

    if (content_length > MAX_RESPONSE_BYTES)
    {
        return http::REQUEST_TOO_LARGE~;
    }

    sz total = header_end + 4 + content_length;

    if (total < header_end)
    {
        return http::REQUEST_TOO_LARGE~;
    }

    return total;
}

fn void? write_all_file(String file_path, char[] data)
{
    aio::File* file = aio::file_open(file_path, "w")!;
    defer file.close();

    sz total = 0;

    while (total < data.len)
    {
        sz n = file.write(
            data[total:data.len - total]
        )!;

        if (n <= 0)
        {
            return http::STATIC_READ_ERROR~;
        }

        total += n;
    }
}

fn void cleanup_files()
{
    if (catch path::remove(HTML_FILE)) {}
    if (catch path::remove(CSS_FILE)) {}
    if (catch path::remove(JS_FILE)) {}
    if (catch path::remove(JSON_FILE)) {}
    if (catch path::remove(PNG_FILE)) {}
    if (catch path::remove(WASM_FILE)) {}

    char[256] cmd;

    string::bformat(
        cmd[..],
        "rm -rf %s",
        ROOT
    );

    stdlib::system(&cmd[0]);
}

fn void? setup_files()
{
    cleanup_files();

    path::makedirs(ROOT, 0o777, true)!;

    write_all_file(
        HTML_FILE,
        (char[])"<html>ok</html>"
    )!;

    write_all_file(
        CSS_FILE,
        (char[])"body { color: black; }"
    )!;

    write_all_file(
        JS_FILE,
        (char[])"console.log('ok');"
    )!;

    write_all_file(
        JSON_FILE,
        (char[])"{\"ok\":true}"
    )!;

    write_all_file(
        PNG_FILE,
        (char[])"PNGDATA"
    )!;

    write_all_file(
        WASM_FILE,
        (char[])"WASMDATA"
    )!;
}

fn String? fetch_raw(String request)
{
    aio::Stream* client =
        aio::stream_connect(HOST, PORT)!;
    defer client.free();

    client.write_all((char[])request)!;

    DString out;
    out.init(http::localmem, 4096);
    defer out.free();

    sz expected = -1;

    while (true)
    {
        char[4096] buf;

        sz? read_result =
            client.read_timeout(buf[..], 2_000_000);

        if (catch err = read_result)
        {
            if (err == aio::TIMEOUT)
            {
                if (expected >= 0 &&
                    out.len() < expected)
                {
                    return http::BODY_INCOMPLETE~;
                }

                break;
            }

            if (err == aio::CLOSED)
            {
                break;
            }

            return err~;
        }

        sz n = read_result;

        if (n == 0) break;

        out.append(buf[0:n]);

        if (out.len() > MAX_RESPONSE_BYTES)
        {
            return http::REQUEST_TOO_LARGE~;
        }

        String response = out.str_view();

        if (expected < 0)
        {
            sz? total =
                response_expected_total_len(response);

            if (try total)
            {
                expected = total;
            }
        }

        if (expected >= 0 && out.len() >= expected)
        {
            client.close();

            return response[0:expected].copy(
                http::localmem
            );
        }
    }

    client.close();

    if (expected >= 0 && out.len() < expected)
    {
        return http::BODY_INCOMPLETE~;
    }

    return out.copy_str(http::localmem);
}

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

fn Response*? multipart_raw_handler(Ctx* c)
{
    String? content_type =
        c.req_header("Content-Type");

    if (catch err = content_type)
    {
        c.status(400)!;
        return c.text("missing content-type")!;
    }

    char[] body = c.body();

    if (!content_type.contains("multipart/form-data"))
    {
        c.status(400)!;
        return c.text("bad content-type")!;
    }

    if (!((String)body).contains("name=\"field\""))
    {
        c.status(500)!;
        return c.text(
            "missing multipart field marker"
        )!;
    }

    if (!((String)body).contains("hello multipart"))
    {
        c.status(500)!;
        return c.text(
            "missing multipart value"
        )!;
    }

    return c.text("multipart-ok")!;
}

fn Response*? multipart_missing_boundary_handler(Ctx* c)
{
    String? content_type =
        c.req_header("Content-Type");

    if (catch err = content_type)
    {
        c.status(400)!;
        return c.text("missing content-type")!;
    }

    if (content_type.contains("boundary="))
    {
        c.status(500)!;
        return c.text("unexpected boundary")!;
    }

    return c.text(
        "multipart-missing-boundary-ok"
    )!;
}

fn void? server_task(void* arg)
{
    ApplicationServer* server =
        (ApplicationServer*)arg;

    if (catch err = server.serve())
    {
        return;
    }
}

fn void? wake_server()
{
    aio::Stream*? stream_result =
        aio::stream_connect(HOST, PORT);

    if (catch err = stream_result)
    {
        return;
    }

    aio::Stream* stream = stream_result;

    stream.close();
    stream.free();
}

fn void? wait_server_ready()
{
    for (sz i = 0; i < 200; i++)
    {
        aio::Stream*? stream_result =
            aio::stream_connect(HOST, PORT);

        if (catch err = stream_result)
        {
            aio::sleep(10_000)!;
            continue;
        }

        aio::Stream* stream = stream_result;

        stream.close();
        stream.free();

        return;
    }

    return aio::CONNECT_ERROR~;
}

fn void? test_chunked_request_ok()
{
    String raw = fetch_raw(
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Connection: close\r\n"
        "\r\n"
        "4\r\n"
        "Wiki\r\n"
        "5\r\n"
        "pedia\r\n"
        "0\r\n"
        "\r\n"
    )!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "chunked request status mismatch"
    );

    @assert(
        body_part(raw).contains("chunked-ok"),
        "chunked response body mismatch"
    );
}

fn void? test_chunked_request_malformed()
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

    @assert(
        status_is(raw, 400),
        "malformed chunked status mismatch"
    );
}

fn void? test_multipart_wire_body()
{
    String body =
        "--AaB03x\r\n"
        "Content-Disposition: form-data; "
        "name=\"field\"\r\n"
        "\r\n"
        "hello multipart\r\n"
        "--AaB03x--\r\n";

    char[128] len_buf;

    String content_length = string::bformat(
        len_buf[..],
        "%d",
        body.len
    );

    String request = string::format(
        http::localmem,
        "POST /multipart HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data; "
        "boundary=AaB03x\r\n"
        "Content-Length: %s\r\n"
        "Connection: close\r\n"
        "\r\n"
        "%s",
        content_length,
        body
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "multipart status mismatch"
    );

    @assert(
        body_part(raw).contains("multipart-ok"),
        "multipart response body mismatch"
    );
}

fn void? test_multipart_missing_boundary_wire()
{
    String body =
        "--AaB03x\r\n"
        "Content-Disposition: form-data; "
        "name=\"field\"\r\n"
        "\r\n"
        "hello multipart\r\n"
        "--AaB03x--\r\n";

    char[128] len_buf;

    String content_length = string::bformat(
        len_buf[..],
        "%d",
        body.len
    );

    String request = string::format(
        http::localmem,
        "POST /multipart-missing-boundary HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: multipart/form-data\r\n"
        "Content-Length: %s\r\n"
        "Connection: close\r\n"
        "\r\n"
        "%s",
        content_length,
        body
    );
    defer http::localmem.free(request);

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "multipart missing boundary status mismatch"
    );

    @assert(
        body_part(raw).contains(
            "multipart-missing-boundary-ok"
        ),
        "multipart missing boundary body mismatch"
    );
}

fn void? assert_static_content_type(
    String request_path,
    String expected
)
{
    char[512] request_buf;

    String request = string::bformat(
        request_buf[..],
        "GET %s HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n"
        "\r\n",
        request_path
    );

    String raw = fetch_raw(request)!;
    defer http::localmem.free(raw);

    @assert(
        status_is(raw, 200),
        "static response status mismatch"
    );

    @assert(
        has_header(raw, expected),
        "static content type mismatch"
    );
}

fn void? test_static_content_types()
{
    assert_static_content_type(
        "/static/index.html",
        "Content-Type: text/html; charset=utf-8\r\n"
    )!;

    assert_static_content_type(
        "/static/app.css",
        "Content-Type: text/css; charset=utf-8\r\n"
    )!;

    assert_static_content_type(
        "/static/app.js",
        "Content-Type: application/javascript; "
        "charset=utf-8\r\n"
    )!;

    assert_static_content_type(
        "/static/data.json",
        "Content-Type: application/json; "
        "charset=utf-8\r\n"
    )!;

    assert_static_content_type(
        "/static/image.png",
        "Content-Type: image/png\r\n"
    )!;

    assert_static_content_type(
        "/static/module.wasm",
        "Content-Type: application/wasm\r\n"
    )!;
}

fn void? test_main(void* arg)
{
    setup_files()!;
    defer cleanup_files();

    Application app;
    app.init();
    defer app.deinit();

    app.post(
        "/chunked",
        &chunked_echo_handler
    )!;

    app.post(
        "/multipart",
        &multipart_raw_handler
    )!;

    app.post(
        "/multipart-missing-boundary",
        &multipart_missing_boundary_handler
    )!;

    app.static_files("/static", ROOT)!;

    ApplicationServer server;
    server.init(&app, HOST, PORT);
    defer server.free();

    aio::spawn(&server_task, &server)!;

    wait_server_ready()!;

    test_chunked_request_ok()!;
    test_chunked_request_malformed()!;
    test_multipart_wire_body()!;
    test_multipart_missing_boundary_wire()!;
    test_static_content_types()!;

    server.stop()!;
    wake_server()!;
    server.wait_closed()!;

    io::printfn("test_req_body: OK");
}

fn void main()
{
    aio::run(&test_main)!!;
}

// eof