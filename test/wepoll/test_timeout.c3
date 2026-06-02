// test_timeout.c3

// Timeout / empty wait direct wepoll test
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::winbase;
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

const ushort TEST_PORT = 19151;

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

fn bool has_event(wepoll::EPollEvent[] events, int n, winsock2::Socket sock, uint mask)
{
    for (int i = 0; i < n; i++)
    {
        if (events[i].data.sock != (wepoll::Socket)sock) continue;
        if ((events[i].events & mask) == 0) continue;

        return true;
    }

    return false;
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

fn void main()
{
    winsock2::WSAData data;

    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");

    defer wepoll::epoll_close(epfd);

    wepoll::EPollEvent[8] events;

    int n = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        0
    );

    @assert(n == 0, "empty timeout=0 wait should return 0");

    n = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        50
    );

    @assert(n == 0, "empty timeout=50 wait should return 0");

    winsock2::Socket server = make_udp_socket();
    defer winsock2::closesocket(server);

    winsock2::Socket client = make_udp_socket();
    defer winsock2::closesocket(client);

    bind_udp(server, TEST_PORT);

    add_socket(epfd, server, wepoll::EPOLLIN);

    n = wait_events(epfd, events[..], 50);
    @assert(n == 0, "registered socket without data should time out");

    send_msg(client, TEST_PORT, "timeout-test");

    n = wait_events(epfd, events[..], 1000);
    @assert(n > 0, "socket did not become readable");
    @assert(has_event(events[..], n, server, wepoll::EPOLLIN), "server missing EPOLLIN");

    char[128] buf;

    String text = recv_msg(server, buf[..]);
    @assert(text == "timeout-test", "received text mismatch");

    n = wait_events(epfd, events[..], 50);
    @assert(n == 0, "socket should time out after draining data");

    del_socket(epfd, server);

    send_msg(client, TEST_PORT, "after-del");

    n = wait_events(epfd, events[..], 100);
    @assert(n == 0, "deleted socket should not produce events");

    text = recv_msg(server, buf[..]);
    @assert(text == "after-del", "manual drain after DEL mismatch");

    warn("OK");
}

// eof