module test_pipe;

import ext::aio;
import ext::debug;

import c::unistd;
import c::fcntl;
import c::errno;
import c::string;
import c::stdio;

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
    warn("reader: wait readable");

    aio::wait_readable(pipe_r)!!;

    char[128] buf;

    isz n = unistd::read(pipe_r, &buf[0], 128);

    if (n < 0) {
        warn("reader: read failed errno=%d", errno::errno());
        return;
    }

    buf[(usz)n] = 0;

    warn("reader: got '%s'", (String)buf[0
    :n]);
}

fn void writer_task()
{
    warn("writer: sleep");

    aio::sleep(100)!!;

    char* msg = "hello";

    isz n = unistd::write(pipe_w, msg, 5);

    warn("writer: wrote %d '%s'", n, (String)msg[0:5]);
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

    unistd::close(pipe_r);
    unistd::close(pipe_w);

    warn("main done");
}

fn void main()
{
    aio::run(&main_task);
}

