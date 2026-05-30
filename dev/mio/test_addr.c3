// test_addr.c3

// Socket address test for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import ext::mio;
import ext::debug;

const ushort TEST_PORT = 19093;

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::TcpListener listener = mio::tcp_listen("127.0.0.1", TEST_PORT)!!;
    defer listener.close();

    char[64] listener_ip;
    ushort listener_port = 0;

    listener.local_addr(listener_ip[..], &listener_port)!!;

    @assert(listener_port == TEST_PORT, "listener local port mismatch");

    poll.register(listener.fd, mio::want_read())!!;

    mio::TcpStream client = mio::tcp_connect("127.0.0.1", TEST_PORT)!!;
    defer client.close();

    poll.register(client.fd, mio::want_write())!!;

    mio::TcpStream server;
    bool accepted = false;
    bool connected = false;

    char[64] accepted_ip;
    ushort accepted_port = 0;

    while (!accepted || !connected)
    {
        poll.poll(&events, 1000)!!;
        @assert(!events.is_empty(), "poll() timed out before accept/connect");

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            if (event.fd == listener.fd && event.read && !accepted)
            {
                server = listener.accept(accepted_ip[..], &accepted_port)!!;
                accepted = true;

                @assert(accepted_port != 0, "accepted peer port was not set");

                poll.register(server.fd, mio::want_read())!!;
                continue;
            }

            if (event.fd == client.fd && (event.write || event.error || event.hup) && !connected)
            {
                int err = client.take_error();
                @assert(err == 0, "client connect failed");

                connected = true;
                poll.reregister(client.fd, mio::want_read())!!;
                continue;
            }
        }
    }

    defer server.close();

    char[64] client_local_ip;
    ushort client_local_port = 0;

    char[64] client_peer_ip;
    ushort client_peer_port = 0;

    char[64] server_local_ip;
    ushort server_local_port = 0;

    char[64] server_peer_ip;
    ushort server_peer_port = 0;

    client.local_addr(client_local_ip[..], &client_local_port)!!;
    client.peer_addr(client_peer_ip[..], &client_peer_port)!!;

    server.local_addr(server_local_ip[..], &server_local_port)!!;
    server.peer_addr(server_peer_ip[..], &server_peer_port)!!;

    @assert(client_local_port != 0, "client local port was not set");
    @assert(client_peer_port == TEST_PORT, "client peer port mismatch");

    @assert(server_local_port == TEST_PORT, "server local port mismatch");
    @assert(server_peer_port == client_local_port, "server peer port mismatch");

    @assert(accepted_port == client_local_port, "accepted peer port mismatch");

    poll.deregister(client.fd)!!;
    poll.deregister(server.fd)!!;
    poll.deregister(listener.fd)!!;

    warn("OK");
}

// eof