// test_pipe.c3

// test reader/writer task through pipe

module test_pipe;

import ext::aio;
import ext::aio::io;
import ext::debug;

const String TEST_MSG = "hello";

struct PipeTest
{
    Fd rfd;
    Fd wfd;
    char[128] buf;
    sz read_n;
    sz write_n;
}

fn void? reader_task(void* arg)
{
    PipeTest* test = (PipeTest*)arg;
    @assert(test != null, "reader_task: null arg");

    warn("reader: wait readable");

    sz n = io::async_read(test.rfd, &test.buf)!;

    test.read_n = n;

    @assert(n == TEST_MSG.len, "reader: read length mismatch");
    @assert((String)test.buf[0:n] == TEST_MSG, "reader: read content mismatch");

    warn("reader: got '%s'", (String)test.buf[0:n]);
}

fn void? writer_task(void* arg)
{
    PipeTest* test = (PipeTest*)arg;
    @assert(test != null, "writer_task: null arg");

    warn("writer: sleep");

    aio::sleep(100)!;

    sz n = io::async_write(test.wfd, TEST_MSG)!;

    test.write_n = n;

    @assert(n == TEST_MSG.len, "writer: write length mismatch");

    warn("writer: wrote %d '%s'", n, TEST_MSG);
}

fn void? main_task(void* arg)
{
    Fd[2] fds = io::pipe_open()!;

    PipeTest test = {
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

    io::fd_close(fds[0]);
    io::fd_close(fds[1]);

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}