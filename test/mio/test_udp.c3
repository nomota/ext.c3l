// test_udp.c3

// Basic UDP readiness test for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::netinet::in;
import ext::mio;
import ext::debug;
import c::string;

const ushort TEST_PORT = 19091;

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::UdpSocket server = mio::udp_bind("127.0.0.1", TEST_PORT)!!;
    defer server.close();

    poll.register(server.fd, mio::want_read())!!;

    mio::UdpSocket client = mio::udp_socket()!!;
    defer client.close();

    poll.register(client.fd, mio::want_read())!!;

    char[] msg = "hello mio udp";

    sz sent = client.send_to(msg, "127.0.0.1", TEST_PORT)!!;
    @assert(sent == (sz)msg.len, "client send_to failed or partial send");

    poll.poll(&events, 1000)!!;
    @assert(!events.is_empty(), "poll() timed out before server recv");

    bool server_readable = false;

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

    @assert(server_readable, "server socket was not readable");

    char[128] server_buf;
    char[64] ip_buf;
    ushort port;

    sz server_n = server.recv_from(server_buf[..], ip_buf[..], &port)!!;

    @assert(server_n == sent, "server recv_from wrong byte count");

    String server_text = (String)server_buf[0:server_n];
    @assert(server_text == "hello mio udp", "server received text mismatch");

    sz echoed = server.send_to(server_buf[0:server_n], (String)ip_buf[0:string::strlen(&ip_buf[0])], port)!!;

    @assert(echoed == server_n, "server echo send_to_addr failed or partial send");

    poll.poll(&events, 1000)!!;
    @assert(!events.is_empty(), "poll() timed out before client recv");

    bool client_readable = false;

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

    @assert(client_readable, "client socket was not readable");

    char[128] client_buf;

    sz client_n = client.recv_from(client_buf[..], ip_buf[..], &port)!!;

    @assert(client_n == echoed, "client recv_from wrong byte count");

    String client_text = (String)client_buf[0:client_n];
    @assert(client_text == "hello mio udp", "client received text mismatch");

    poll.deregister(client.fd)!!;
    poll.deregister(server.fd)!!;

    warn("OK");
}

// eof