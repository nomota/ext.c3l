// test_pipe_stream.c3

// test reader/writer task through Stream over pipe

module test_pipe_stream;

import ext::aio;
import ext::aio::io;
import ext::debug;

const String TEST_MSG = "hello stream";

struct PipeStreamTest
{
    Fd rfd;
    Fd wfd;
    char[128] buf;
    usz read_n;
    usz write_n;
}

fn void? reader_task(void* arg)
{
    PipeStreamTest* test = (PipeStreamTest*)arg;
    @assert(test != null, "reader_task: null arg");

    Stream* s = aio::stream_new(test.rfd)!;
    defer s.free();

    warn("reader: read");

    usz n = s.read(test.buf[0:127])!;

    test.read_n = n;

    @assert(n == TEST_MSG.len, "reader: read length mismatch");
    @assert((String)test.buf[0:n] == TEST_MSG, "reader: read content mismatch");

    warn("reader: got '%s'", (String)test.buf[0:n]);
}

fn void? writer_task(void* arg)
{
    PipeStreamTest* test = (PipeStreamTest*)arg;
    @assert(test != null, "writer_task: null arg");

    Stream* s = aio::stream_new(test.wfd)!;
    defer s.free();

    aio::sleep(100)!;

    warn("writer: write");

    s.write_all(TEST_MSG)!;

    test.write_n = TEST_MSG.len;

    @assert(test.write_n == TEST_MSG.len, "writer: write length mismatch");
}

fn void? main_task(void* arg)
{
    Fd[2] fds = io::pipe_open()!;

    PipeStreamTest test = {
        .rfd = fds[0],
        .wfd = fds[1],
        .read_n = 0,
        .write_n = 0,
    };

    Task* r = aio::spawn_joinable(&reader_task, &test)!;
    Task* w = aio::spawn_joinable(&writer_task, &test)!;

    r.join()!;
    w.join()!;

    @assert(test.write_n == TEST_MSG.len, "main: write_n mismatch");
    @assert(test.read_n == TEST_MSG.len, "main: read_n mismatch");
    @assert((String)test.buf[0:test.read_n] == TEST_MSG, "main: final buffer mismatch");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}