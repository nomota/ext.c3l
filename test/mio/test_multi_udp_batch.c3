// test_multi_udp_batch.c3

// Multi UDP batching test for ext::mio
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import ext::mio;
import ext::debug;

const int SOCKET_COUNT = 40;
const int BATCH_SIZE = 4;
const ushort BASE_PORT = 19420;

fn int find_socket_index(mio::UdpSocket[] sockets, mio::Fd fd)
{
    for (int i = 0; i < sockets.len; i++)
    {
        if (sockets[i].fd == fd) return i;
    }

    return -1;
}

fn void close_all(mio::UdpSocket[] sockets)
{
    for (int i = 0; i < sockets.len; i++)
    {
        if (sockets[i].fd < 0) continue;

        sockets[i].close();
        sockets[i].fd = (mio::Fd)-1;
    }
}

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(BATCH_SIZE)!!;
    defer events.free();

    mio::UdpSocket[SOCKET_COUNT] servers;

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        servers[i].fd = (mio::Fd)-1;
    }

    defer close_all(servers[..]);

    mio::UdpSocket client = mio::udp_socket()!!;
    defer client.close();

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        ushort port = BASE_PORT + (ushort)i;

        servers[i] = mio::udp_bind("127.0.0.1", port)!!;
        poll.register(servers[i].fd, mio::want_read())!!;
    }

    char[] msg = "m";

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        ushort port = BASE_PORT + (ushort)i;

        sz sent = client.send_to(msg, "127.0.0.1", port)!!;
        @assert(sent == (sz)msg.len, "send_to failed or partial send");
    }

    bool[SOCKET_COUNT] seen;
    int seen_count = 0;
    int poll_count = 0;

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        seen[i] = false;
    }

    char[64] ip_buf;
    char[32] recv_buf;
    ushort peer_port = 0;

    while (seen_count < SOCKET_COUNT)
    {
        poll.poll(&events, 1000)!!;

        @assert(!events.is_empty(), "poll() timed out before all UDP sockets were readable");
        @assert(events.len <= BATCH_SIZE, "Events returned more than its capacity");

        poll_count++;

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            @assert(event.read, "expected readable UDP event");

            int index = find_socket_index(servers[..], event.fd);
            @assert(index >= 0, "event for unknown UDP socket");

            if (seen[index]) continue;

            sz n = servers[index].recv_from(recv_buf[..], ip_buf[..], &peer_port)!!;

            @assert(n == (sz)msg.len, "recv_from wrong byte count");

            String text = (String)recv_buf[0:n];
            @assert(text == "m", "received text mismatch");

            seen[index] = true;
            seen_count++;
        }
    }

    @assert(poll_count >= 2, "batching did not require multiple poll calls");

    poll.poll(&events, 50)!!;
    @assert(events.is_empty(), "poll should time out after all UDP sockets were drained");

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        poll.deregister(servers[i].fd)!!;
    }

    warn("OK");
}

// eof