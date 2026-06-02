// test_stress_udp.c3

// UDP stress / poll-group direct wepoll test
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::winbase;
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

const int SOCKET_COUNT = 40;
const ushort BASE_PORT = 19200;

fn winsock2::Socket make_udp_socket()
{
    winsock2::Socket sock = winsock2::socket(
        winsock2::AF_INET,
        winsock2::SOCK_DGRAM,
        winsock2::IPPROTO_UDP
    );

    @assert(sock != winsock2::INVALID_SOCKET, "socket failed");

    uint nonblock = 1;

    int rc = winsock2::ioctlsocket(
        sock,
        winsock2::FIONBIO,
        &nonblock
    );

    @assert(rc == 0, "ioctlsocket FIONBIO failed");

    return sock;
}

fn void make_addr(winsock2::SockAddrIn* addr, ushort port)
{
    *addr = {};
    addr.sin_family = (ushort)winsock2::AF_INET;
    addr.sin_port = winsock2::htons(port);

    int rc = winsock2::inet_pton(
        winsock2::AF_INET,
        "127.0.0.1",
        &addr.sin_addr
    );

    @assert(rc == 1, "inet_pton failed");
}

fn void bind_udp(winsock2::Socket sock, ushort port)
{
    winsock2::SockAddrIn addr;
    make_addr(&addr, port);

    int rc = winsock2::bind(
        sock,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    @assert(rc == 0, "bind failed");
}

fn void send_msg(winsock2::Socket client, ushort port, String msg)
{
    winsock2::SockAddrIn addr;
    make_addr(&addr, port);

    int sent = winsock2::sendto(
        client,
        msg.ptr,
        (int)msg.len,
        0,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    @assert(sent == (int)msg.len, "sendto failed or partial send");
}

fn String recv_msg(winsock2::Socket server, char[] buf)
{
    winsock2::SockAddrIn from = {};
    int from_len = (int)@sizeof(from);

    int received = winsock2::recvfrom(
        server,
        buf.ptr,
        (int)buf.len,
        0,
        (winsock2::SockAddr*)&from,
        &from_len
    );

    @assert(received > 0, "recvfrom failed");

    return (String)buf[0:received];
}

fn void add_socket(wepoll::EPollFd epfd, winsock2::Socket sock, uint events)
{
    wepoll::EPollEvent event = {};
    event.events = events;
    event.data.sock = (wepoll::Socket)sock;

    int rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_ADD,
        (wepoll::Socket)sock,
        &event
    );

    @assert(rc == 0, "epoll_ctl ADD failed");
}

fn void del_socket(wepoll::EPollFd epfd, winsock2::Socket sock)
{
    int rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_DEL,
        (wepoll::Socket)sock,
        null
    );

    @assert(rc == 0, "epoll_ctl DEL failed");
}

fn int find_socket_index(winsock2::Socket[] sockets, winsock2::Socket sock)
{
    for (int i = 0; i < sockets.len; i++)
    {
        if (sockets[i] == sock) return i;
    }

    return -1;
}

fn int wait_events(wepoll::EPollFd epfd, wepoll::EPollEvent[] events, int timeout)
{
    int n = wepoll::epoll_wait(
        epfd,
        events.ptr,
        events.len,
        timeout
    );

    @assert(n >= 0, "epoll_wait failed");

    return n;
}

fn void close_all(winsock2::Socket[] sockets)
{
    for (int i = 0; i < sockets.len; i++)
    {
        if (sockets[i] == winsock2::INVALID_SOCKET) continue;

        winsock2::closesocket(sockets[i]);
        sockets[i] = winsock2::INVALID_SOCKET;
    }
}

fn void main()
{
    winsock2::WSAData data;

    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    winsock2::Socket[SOCKET_COUNT] servers;
    winsock2::Socket client = winsock2::INVALID_SOCKET;

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        servers[i] = winsock2::INVALID_SOCKET;
    }

    defer close_all(servers[..]);

    client = make_udp_socket();
    defer winsock2::closesocket(client);

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");

    defer wepoll::epoll_close(epfd);

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        servers[i] = make_udp_socket();

        ushort port = BASE_PORT + (ushort)i;

        bind_udp(servers[i], port);
        add_socket(epfd, servers[i], wepoll::EPOLLIN);
    }

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        ushort port = BASE_PORT + (ushort)i;
        send_msg(client, port, "x");
    }

    wepoll::EPollEvent[SOCKET_COUNT] events;
    bool[SOCKET_COUNT] seen;
    int seen_count = 0;

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        seen[i] = false;
    }

    while (seen_count < SOCKET_COUNT)
    {
        int n = wait_events(epfd, events[..], 1000);
        @assert(n > 0, "stress wait timed out");

        for (int i = 0; i < n; i++)
        {
            winsock2::Socket sock = (winsock2::Socket)events[i].data.sock;
            int index = find_socket_index(servers[..], sock);

            @assert(index >= 0, "event for unknown socket");
            @assert((events[i].events & wepoll::EPOLLIN) != 0, "expected EPOLLIN");

            if (!seen[index])
            {
                seen[index] = true;
                seen_count++;
            }
        }
    }

    char[32] buf;

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        String text = recv_msg(servers[i], buf[..]);
        @assert(text == "x", "received text mismatch");
    }

    int n = wait_events(epfd, events[..], 50);
    @assert(n == 0, "stress sockets should time out after drain");

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        del_socket(epfd, servers[i]);
    }

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        ushort port = BASE_PORT + (ushort)i;
        send_msg(client, port, "z");
    }

    n = wait_events(epfd, events[..], 100);
    @assert(n == 0, "deleted stress sockets should not produce events");

    for (int i = 0; i < SOCKET_COUNT; i++)
    {
        String text = recv_msg(servers[i], buf[..]);
        @assert(text == "z", "manual drain after DEL mismatch");
    }

    warn("OK");
}

// eof