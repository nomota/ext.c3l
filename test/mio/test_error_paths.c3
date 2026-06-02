// test_error_paths.c3

// Error-path test for ext::mio
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import ext::mio;
import ext::debug;

const ushort BAD_CONNECT_PORT = 19999;

fn void expect_register_fail(mio::Poll* poll, mio::Fd fd, mio::Interest interest, String what)
{
    if (catch err = poll.register(fd, interest))
    {
        return;
    }

    @assert(false, what);
}

fn void expect_reregister_fail(mio::Poll* poll, mio::Fd fd, mio::Interest interest, String what)
{
    if (catch err = poll.reregister(fd, interest))
    {
        return;
    }

    @assert(false, what);
}

fn void expect_deregister_fail(mio::Poll* poll, mio::Fd fd, String what)
{
    if (catch err = poll.deregister(fd))
    {
        return;
    }

    @assert(false, what);
}

fn void expect_poll_fail(mio::Poll* poll, mio::Events* events, int timeout, String what)
{
    if (catch err = poll.poll(events, timeout))
    {
        return;
    }

    @assert(false, what);
}

fn void test_create_errors()
{
    if (catch err = mio::poll_new(0))
    {
    }
    else
    {
        @assert(false, "poll_new(0) should fail");
    }

    if (catch err = mio::events_new(0))
    {
    }
    else
    {
        @assert(false, "events_new(0) should fail");
    }
}

fn void test_poll_errors()
{
    mio::Poll* poll = mio::poll_new(8)!!;
    defer poll.free();

    mio::Events events = mio::events_new(8)!!;
    defer events.free();

    expect_poll_fail(
        poll,
        null,
        0,
        "poll(null events) should fail"
    );

    poll.poll(&events, 0)!!;
    @assert(events.is_empty(), "poll(timeout=0) should return no events");

    poll.poll(&events, 10)!!;
    @assert(events.is_empty(), "poll(short timeout) should return no events");
}

fn void test_registration_errors()
{
    mio::Poll* poll = mio::poll_new(16)!!;
    defer poll.free();

    mio::Events events = mio::events_new(16)!!;
    defer events.free();

    mio::Fd invalid_fd = (mio::Fd)-1;

    expect_register_fail(
        poll,
        invalid_fd,
        mio::want_read(),
        "register(invalid fd) should fail"
    );

    expect_reregister_fail(
        poll,
        invalid_fd,
        mio::want_read(),
        "reregister(invalid fd) should fail"
    );

    expect_deregister_fail(
        poll,
        invalid_fd,
        "deregister(invalid fd) should fail"
    );

    mio::UdpSocket sock = mio::udp_bind("127.0.0.1", 0)!!;
    defer sock.close();

    poll.register(sock.fd, mio::want_read())!!;

    expect_register_fail(
        poll,
        sock.fd,
        mio::want_read(),
        "duplicate register should fail"
    );

    poll.reregister(sock.fd, mio::want_readwrite())!!;

    poll.deregister(sock.fd)!!;

    expect_deregister_fail(
        poll,
        sock.fd,
        "second deregister should fail"
    );

    expect_reregister_fail(
        poll,
        sock.fd,
        mio::want_read(),
        "reregister after deregister should fail"
    );

    poll.poll(&events, 0)!!;
    @assert(events.is_empty(), "poll after deregister should have no events");
}

fn void test_closed_fd_errors()
{
    mio::Poll* poll = mio::poll_new(16)!!;
    defer poll.free();

    mio::UdpSocket sock = mio::udp_bind("127.0.0.1", 0)!!;
    mio::Fd fd = sock.fd;

    sock.close();

    expect_register_fail(
        poll,
        fd,
        mio::want_read(),
        "register(closed fd) should fail"
    );

    expect_reregister_fail(
        poll,
        fd,
        mio::want_read(),
        "reregister(closed fd) should fail"
    );

    expect_deregister_fail(
        poll,
        fd,
        "deregister(closed fd) should fail"
    );
}

fn void test_tcp_connect_refused()
{
    mio::Poll* poll = mio::poll_new(16)!!;
    defer poll.free();

    mio::Events events = mio::events_new(16)!!;
    defer events.free();

    mio::TcpStream client = mio::tcp_connect("127.0.0.1", BAD_CONNECT_PORT)!!;
    defer client.close();

    poll.register(client.fd, mio::want_write())!!;

    bool got_result = false;

    for (int tries = 0; tries < 50 && !got_result; tries++)
    {
        poll.poll(&events, 100)!!;

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;
            if (event.fd != client.fd) continue;

            if (event.write || event.error || event.hup)
            {
                got_result = true;
                break;
            }
        }
    }

    @assert(got_result, "connect refused did not produce completion event");

    int err = client.take_error();
    @assert(err != 0, "connect to unused port should fail");

    poll.deregister(client.fd)!!;
}

fn void main()
{
    test_create_errors();
    test_poll_errors();
    test_registration_errors();
    test_closed_fd_errors();
    test_tcp_connect_refused();

    warn("OK");
}

// eof