// test_echo.c3

// Basic TCP echo test for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import ext::mio;
import ext::debug;

const ushort TEST_PORT = 19090;

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::TcpListener listener = mio::tcp_listen("127.0.0.1", TEST_PORT)!!;
    defer listener.close();

    poll.register(listener.fd, mio::want_read())!!;

    mio::TcpStream client = mio::tcp_connect("127.0.0.1", TEST_PORT)!!;
    defer client.close();

    poll.register(client.fd, mio::want_write())!!;

    mio::TcpStream server;
    bool accepted = false;
    bool client_connected = false;

    while (!accepted || !client_connected)
    {
        poll.poll(&events, 1000)!!;
        @assert(!events.is_empty(), "poll() timed out before accept/connect");

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            if (event.fd == listener.fd && event.read && !accepted)
            {
                char[64] ip_buf;
                ushort port;
                server = listener.accept(ip_buf[..], &port)!!;
                accepted = true;

                poll.register(server.fd, mio::want_read())!!;
                continue;
            }

            if (event.fd == client.fd && (event.write || event.error || event.hup) && !client_connected)
            {
                int err = client.take_error();
                @assert(err == 0, "client error");  
                client_connected = true;
                poll.reregister(client.fd, mio::want_read())!!;
                continue;
            }
        }
    }

    defer server.close();

    char[] msg = "hello mio tcp";
    sz written = client.write(msg)!!;

    @assert(written == (sz)msg.len, "client write failed or partial write");

    bool server_readable = false;

    while (!server_readable)
    {
        poll.poll(&events, 1000)!!;
        @assert(!events.is_empty(), "poll() timed out before server read");

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            if (event.fd == server.fd && event.read)
            {
                server_readable = true;
                break;
            }
        }
    }

    char[128] server_buf;
    sz server_n = server.read(server_buf[..])!!;

    @assert(server_n == written, "server read wrong byte count");

    String server_text = (String)server_buf[0:server_n];
    @assert(server_text == "hello mio tcp", "server read text mismatch");

    sz echoed = server.write(server_buf[0:server_n])!!;

    @assert(echoed == server_n, "server echo write failed or partial write");

    bool client_readable = false;

    while (!client_readable)
    {
        poll.poll(&events, 1000)!!;
        @assert(!events.is_empty(), "poll() timed out before client read");

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            if (event.fd == client.fd && event.read)
            {
                client_readable = true;
                break;
            }
        }
    }

    char[128] client_buf;
    sz client_n = client.read(client_buf[..])!!;

    @assert(client_n == echoed, "client read wrong byte count");

    String client_text = (String)client_buf[0:client_n];
    @assert(client_text == "hello mio tcp", "client read text mismatch");

    poll.deregister(client.fd)!!;
    poll.deregister(server.fd)!!;
    poll.deregister(listener.fd)!!;

    warn("OK");
}

// eof