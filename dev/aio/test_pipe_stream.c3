// test_pipe_stream.c3

import ext::aio;
import ext::debug;

import c::unistd;
import c::fcntl;
import c::errno;

int pipe_r = -1;
int pipe_w = -1;

fn void set_nonblocking(int fd)
{
    int flags = fcntl::fcntl(fd, fcntl::F_GETFL, 0);
    if (flags < 0) return;

    fcntl::fcntl(fd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK);
}

fn void reader_task()
{
    Stream* s = aio::stream_new(pipe_r);

    char[128] buf;

    warn("reader: read");

    isz n = s.read(buf[:127])!!;

    if (n > 0) {
        buf[(usz)n] = 0;
        warn("reader: got '%s'", (String)buf[0:n]);
    }

    s.free();
}

fn void writer_task()
{
    Stream* s = aio::stream_new(pipe_w);

    aio::sleep(100)!!;

    warn("writer: write");

    s.write_all("hello stream")!!;

    s.free();
}

fn void main_task()
{
    int[2] fds;

    int rc = unistd::pipe((CInt[2]*)&fds[0]);

    if (rc < 0) {
        warn("pipe failed errno=%d", errno::errno());
        return;
    }

    pipe_r = fds[0];
    pipe_w = fds[1];

    set_nonblocking(pipe_r);
    set_nonblocking(pipe_w);

    EventLoop* loop = aio::current_loop();

    Task* r = loop.spawn(&reader_task);
    Task* w = loop.spawn(&writer_task);

    r.join()!!;
    w.join()!!;

    warn("main done");
}

fn void main()
{
    aio::run(&main_task);
}