// test_echo_thread.c3

// Threaded TCP echo test for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::errno;
import std::thread;
import c::unistd;
import ext::mio;
import ext::debug;

const ushort TEST_PORT = 19090;

const char[] TEST_MSG = "hello mio tcp threaded";

bool g_server_ready = false;
bool g_server_ok = false;
bool g_client_ok = false;

fn void wait_until_server_ready()
{
    while (!g_server_ready)
    {
        thread::sleep_ms(1);
    }
}

fn bool wait_for_event(
    String name,
    mio::Poll* poll,
    mio::Events* events,
    mio::Fd fd,
    bool want_read,
    bool want_write,
    bool accept_error
)
{
    while (true)
    {
        poll.poll(events, 1000)!!;

        if (events.is_empty())
        {
            continue;
            //warn("[timeout] %s fd=%d read=%d write=%d err=%d", name, fd, want_read, want_write, accept_error);

            //@assert(false, "poll() timed out");
        }

        // warn("[poll] %s events=%d", name, events.len);

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            // warn("[event] %s i=%d fd=%d read=%d write=%d error=%d hup=%d", name, i, event.fd, event.read, event.write, event.error, event.hup);

            if (event.fd != fd) continue;

            if (want_read && event.read) return true;
            if (want_write && event.write) return true;
            if (accept_error && (event.error || event.hup)) return true;
        }
    }
}

fn int server_thread(void* arg)
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::TcpListener listener = mio::tcp_listen("127.0.0.1", TEST_PORT)!!;
    defer listener.close();

    poll.register(listener.fd, mio::want_read())!!;

    g_server_ready = true;

    wait_for_event("server listener accept", poll, &events, listener.fd, true, false, true);

    char[64] ip_buf;
    ushort port;
    mio::TcpStream stream = listener.accept(ip_buf[..], &port)!!;
    defer stream.close();

    poll.register(stream.fd, mio::want_read())!!;

    wait_for_event("server stream read", poll, &events, stream.fd, true, false, true);

    char[256] buf;
    sz n = stream.read(buf[..])!!;

    @assert(n == (sz)TEST_MSG.len, "server read wrong byte count");

    String text = (String)buf[0:n];
    @assert(text == TEST_MSG, "server read text mismatch");

    sz written = stream.write(buf[0:n])!!;

    @assert(written == n, "server write failed or partial write");

    poll.deregister(stream.fd)!!;
    poll.deregister(listener.fd)!!;

    g_server_ok = true;

    return 0;
}

fn int client_thread(void* arg)
{
    wait_until_server_ready();

    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::TcpStream client = mio::tcp_connect("127.0.0.1", TEST_PORT)!!;
    defer client.close();

    poll.register(client.fd, mio::want_write())!!;

    wait_for_event("client stream write", poll, &events, client.fd, false, true, true);

    int err = client.take_error();
    @assert(err == 0);
    
    poll.reregister(client.fd, mio::want_read())!!;

    sz written = client.write(TEST_MSG)!!;

    @assert(written == (sz)TEST_MSG.len, "client write failed or partial write");

    wait_for_event("client stream read", poll, &events, client.fd, true, false, true);

    char[256] buf;
    sz n = client.read(buf[..])!!;

    @assert(n == written, "client read wrong byte count");

    String text = (String)buf[0:n];
    @assert(text == TEST_MSG, "client read text mismatch");

    poll.deregister(client.fd)!!;

    g_client_ok = true;

    return 0;
}

fn void main()
{
    Thread server;
    Thread client;

    server.create(&server_thread, null)!!;
    client.create(&client_thread, null)!!;

    client.join()!!;
    server.join()!!;

    @assert(g_server_ok, "server thread did not complete");
    @assert(g_client_ok, "client thread did not complete");

    warn("OK");
}

// eof