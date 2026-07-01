// test_stream_file.c3

// Tests BODY_STREAM and BODY_FILE response metadata.

// Nomota <hiongun@gmail.com>; MIT License

module test::response_stream_file;

import std::io;
import ext::aio;
import ext::aio::http;
import ext::debug;

fn void? sample_stream_writer(aio::Stream* stream, void* arg)
{
    if (stream == null)
    {
        return http::BAD_REQUEST~;
    }

    http::write_chunk(stream, "hello")!;
    http::write_chunk(stream, " ")!;
    http::write_chunk(stream, "stream")!;
}

fn void test_response_stream_metadata()
{
    http::Response* res =
        http::response_stream(&sample_stream_writer, null)!!;
    defer http::response_free(res);

    @assert(
        res.body_kind == http::BodyKind.BODY_STREAM,
        "stream body kind mismatch"
    );
    @assert(
        res.is_streaming(),
        "stream response should be streaming"
    );
    @assert(
        res.stream_writer != null,
        "stream writer missing"
    );
    @assert(
        res.stream_arg == null,
        "stream argument mismatch"
    );

    String transfer_encoding =
        res.headers.get("Transfer-Encoding")!!;

    @assert(
        transfer_encoding == "chunked",
        "stream transfer encoding mismatch"
    );

    @assert(
        !res.headers.has("Content-Length"),
        "stream response should not have content length"
    );
    @assert(
        res.body_len_for_wire() == 0,
        "stream wire body length mismatch"
    );

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(
        wire.contains("HTTP/1.1 200 OK\r\n"),
        "stream status line mismatch"
    );
    @assert(
        wire.contains("Transfer-Encoding: chunked\r\n"),
        "stream transfer encoding header mismatch"
    );
    @assert(
        !wire.contains("Content-Length:"),
        "stream response contains content length"
    );
    @assert(
        !wire.contains("hello stream"),
        "stream body should not be serialized eagerly"
    );
}

fn void test_response_file_metadata()
{
    http::Response* res =
        http::response_file("public/index.html", 1234)!!;
    defer http::response_free(res);

    @assert(
        res.body_kind == http::BodyKind.BODY_FILE,
        "file body kind mismatch"
    );
    @assert(
        res.is_file(),
        "file response should be a file response"
    );
    @assert(
        res.is_streaming(),
        "file response should not be chunked streaming"
    );
    @assert(
        res.file_path == "public/index.html",
        "file path mismatch"
    );
    @assert(
        res.file_size == 1234,
        "file size mismatch"
    );
    @assert(
        res.owns_file_path,
        "file path ownership mismatch"
    );

    @assert(
        !res.headers.has("Transfer-Encoding"),
        "file response should not use transfer encoding"
    );

    String content_length =
        res.headers.get("Content-Length")!!;

    @assert(
        content_length == "1234",
        "file content length mismatch"
    );

    String content_type =
        res.headers.get("Content-Type")!!;

    @assert(
        content_type == "text/html; charset=utf-8",
        "file content type mismatch"
    );

    @assert(
        res.body_len_for_wire() == 0,
        "file serialized body length mismatch"
    );
    @assert(
        res.content_length_for_wire() == 1234,
        "file wire content length mismatch"
    );

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(
        wire.contains("HTTP/1.1 200 OK\r\n"),
        "file status line mismatch"
    );
    @assert(
        wire.contains("Content-Length: 1234\r\n"),
        "file content length header mismatch"
    );
    @assert(
        wire.contains(
            "Content-Type: text/html; charset=utf-8\r\n"
        ),
        "file content type header mismatch"
    );
    @assert(
        !wire.contains("Transfer-Encoding:"),
        "file response contains transfer encoding"
    );
}

fn void test_stream_replaced_by_body()
{
    http::Response* res =
        http::response_stream(&sample_stream_writer, null)!!;
    defer http::response_free(res);

    res.set_text("plain body")!!;

    @assert(
        res.body_kind == http::BodyKind.BODY_BYTES,
        "replaced stream body kind mismatch"
    );
    @assert(
        !res.is_streaming(),
        "replaced stream should not be streaming"
    );
    @assert(
        res.stream_writer == null,
        "replaced stream writer was not cleared"
    );
    @assert(
        res.stream_arg == null,
        "replaced stream argument was not cleared"
    );
    @assert(
        res.file_path == "",
        "replaced stream file path mismatch"
    );
    @assert(
        !res.owns_file_path,
        "replaced stream file ownership mismatch"
    );
    @assert(
        res.body_len_for_wire() == "plain body".len,
        "replaced stream body length mismatch"
    );

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(
        wire.contains("Content-Length: 10\r\n"),
        "replaced stream content length mismatch"
    );
    @assert(
        wire.contains("\r\n\r\nplain body"),
        "replaced stream wire body mismatch"
    );
}

fn void test_file_replaced_by_body()
{
    http::Response* res =
        http::response_file("public/app.js", 100)!!;
    defer http::response_free(res);

    res.set_text("changed")!!;

    @assert(
        res.body_kind == http::BodyKind.BODY_BYTES,
        "replaced file body kind mismatch"
    );
    @assert(
        !res.is_streaming(),
        "replaced file should not be streaming"
    );
    @assert(
        res.stream_writer == null,
        "replaced file stream writer mismatch"
    );
    @assert(
        res.stream_arg == null,
        "replaced file stream argument mismatch"
    );
    @assert(
        res.file_path == "",
        "replaced file path was not cleared"
    );
    @assert(
        res.file_size == -1 || res.file_size == 0,
        "replaced file size mismatch"
    );
    @assert(
        !res.owns_file_path,
        "replaced file path ownership mismatch"
    );
    @assert(
        res.body_len_for_wire() == "changed".len,
        "replaced file body length mismatch"
    );

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(
        wire.contains("Content-Length: 7\r\n"),
        "replaced file content length mismatch"
    );
    @assert(
        wire.contains("\r\n\r\nchanged"),
        "replaced file wire body mismatch"
    );
}

fn void test_no_body_status_clears_wire_body()
{
    http::Response* res =
        http::response_stream(&sample_stream_writer, null)!!;
    defer http::response_free(res);

    res.set_status(204)!!;

    @assert(
        res.body_kind == http::BodyKind.BODY_STREAM,
        "no-body status body kind mismatch"
    );
    @assert(
        res.is_streaming(),
        "no-body status metadata should remain streaming"
    );
    @assert(
        res.body_len_for_wire() == 0,
        "no-body status wire length mismatch"
    );

    String wire = res.serialize()!!;
    defer http::localmem.free(wire);

    @assert(
        wire.contains("HTTP/1.1 204 No Content\r\n"),
        "no-body status line mismatch"
    );
    @assert(
        !wire.contains("Transfer-Encoding: chunked\r\n"),
        "no-body status should not use chunked encoding"
    );
    @assert(
        wire.contains("Content-Length: 0\r\n"),
        "no-body status content length mismatch"
    );
    @assert(
        !wire.contains("\r\n\r\nhello"),
        "no-body status contains stream body"
    );
}

fn void main()
{
    test_response_stream_metadata();
    test_response_file_metadata();
    test_stream_replaced_by_body();
    test_file_replaced_by_body();
    test_no_body_status_clears_wire_body();

    io::printfn("test_stream_file: OK");
}

// eof