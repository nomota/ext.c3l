// test_pipe.c3

// Basic pipe readiness test for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::unistd;
import ext::mio;
import ext::debug;

fn void main() @if(env::POSIX)
{
    int[2] fds;

    int rc = unistd::pipe(&fds);
    @assert(rc == 0, "pipe() failed");

    defer unistd::close(fds[0]);
    defer unistd::close(fds[1]);

    mio::Fd read_fd = (mio::Fd)fds[0];
    mio::Fd write_fd = (mio::Fd)fds[1];

    mio::set_nonblock_fd(read_fd)!!;
    mio::set_nonblock_fd(write_fd)!!;

    mio::Poll* poll = mio::poll_new(16)!!;
    defer poll.free();

    mio::Events events = mio::events_new(16)!!;
    defer events.free();

    poll.register(read_fd, mio::want_read())!!;

    char[] msg = "hello mio";
    sz written = unistd::write((int)write_fd, msg.ptr, msg.len);

    @assert(written == (sz)msg.len, "write() failed or partial write");

    poll.poll(&events, 1000)!!;

    @assert(!events.is_empty(), "poll() returned no events");

    bool got_readable = false;
    bool got_expected_fd = false;

    for (sz i = 0; i < events.len; i++)
    {
        mio::Event* event = events.get(i);
        if (event == null) continue;

        if (event.fd != read_fd) continue;

        got_expected_fd = true;
        @assert(event.read, "expected readable event");

        char[128] buf;
        sz n = unistd::read((int)read_fd, &buf[0], buf.len);

        @assert(n == written, "read() failed or wrong byte count");

        String text = (String)buf[0:n];

        @assert(text == "hello mio", "read text mismatch");

        got_readable = true;
    }

    @assert(got_expected_fd, "expected fd was not returned");
    @assert(got_readable, "readable event was not handled");

    poll.deregister(read_fd)!!;

    warn("OK");
}

fn void main() @if(env::WIN32)
{
    warn("OK, this is POSIX only test.");
}

// eof