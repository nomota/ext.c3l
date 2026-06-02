// test_multi_udp.c3

// Multi-socket direct wepoll test
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::errno;
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

fn winsock2::Socket make_udp_socket()
{
    winsock2::Socket sock = winsock2::socket(
        winsock2::AF_INET,
        winsock2::SOCK_DGRAM,
        winsock2::IPPROTO_UDP
    );

    @assert(sock != winsock2::INVALID_SOCKET, "socket failed");

    uint nonblock = 1;
    int rc = winsock2::ioctlsocket(sock, winsock2::FIONBIO, &nonblock);
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

fn bool has_socket_event(wepoll::EPollEvent[] events, int n, winsock2::Socket sock)
{
    for (int i = 0; i < n; i++)
    {
        if (events[i].data.sock != (wepoll::Socket)sock) continue;
        if ((events[i].events & wepoll::EPOLLIN) == 0) continue;

        return true;
    }

    return false;
}

fn void add_socket(wepoll::EPollFd epfd, winsock2::Socket sock)
{
    wepoll::EPollEvent event = {};
    event.events = wepoll::EPOLLIN;
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

fn void main()
{
    winsock2::WSAData data;
    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    winsock2::Socket server1 = make_udp_socket();
    defer winsock2::closesocket(server1);

    winsock2::Socket server2 = make_udp_socket();
    defer winsock2::closesocket(server2);

    winsock2::Socket client1 = make_udp_socket();
    defer winsock2::closesocket(client1);

    winsock2::Socket client2 = make_udp_socket();
    defer winsock2::closesocket(client2);

    bind_udp(server1, 19101);
    bind_udp(server2, 19102);

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");

    defer wepoll::epoll_close(epfd);

    add_socket(epfd, server1);
    add_socket(epfd, server2);

    send_msg(client1, 19101, "one");
    send_msg(client2, 19102, "two");

    wepoll::EPollEvent[8] events;

    int n = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        1000
    );

    @assert(n > 0, "epoll_wait timed out for first batch");
    @assert(has_socket_event(events[..], n, server1), "server1 was not readable");
    @assert(has_socket_event(events[..], n, server2), "server2 was not readable");

    char[128] buf;

    String text1 = recv_msg(server1, buf[..]);
    @assert(text1 == "one", "server1 received text mismatch");

    String text2 = recv_msg(server2, buf[..]);
    @assert(text2 == "two", "server2 received text mismatch");

    del_socket(epfd, server1);

    send_msg(client1, 19101, "removed");
    send_msg(client2, 19102, "still here");

    n = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        1000
    );

    @assert(n > 0, "epoll_wait timed out after DEL");
    @assert(!has_socket_event(events[..], n, server1), "deleted server1 still produced event");
    @assert(has_socket_event(events[..], n, server2), "server2 was not readable after DEL");

    text2 = recv_msg(server2, buf[..]);
    @assert(text2 == "still here", "server2 second text mismatch");

    // Drain server1 manually. It should have data at Winsock level,
    // but it must not be reported by wepoll after EPOLL_CTL_DEL.
    text1 = recv_msg(server1, buf[..]);
    @assert(text1 == "removed", "server1 manual drain mismatch");

    warn("OK");
}

// eof