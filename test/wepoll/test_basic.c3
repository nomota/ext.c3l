// test_basic.c3

// Basic direct wepoll test
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::errno;
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

fn void main()
{
    winsock2::WSAData data;
    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    winsock2::Socket server = winsock2::socket(
        winsock2::AF_INET,
        winsock2::SOCK_DGRAM,
        winsock2::IPPROTO_UDP
    );

    @assert(server != winsock2::INVALID_SOCKET, "server socket failed");

    defer winsock2::closesocket(server);

    winsock2::Socket client = winsock2::socket(
        winsock2::AF_INET,
        winsock2::SOCK_DGRAM,
        winsock2::IPPROTO_UDP
    );

    @assert(client != winsock2::INVALID_SOCKET, "client socket failed");

    defer winsock2::closesocket(client);

    uint nonblock = 1;

    rc = winsock2::ioctlsocket(server, winsock2::FIONBIO, &nonblock);
    @assert(rc == 0, "server nonblock failed");

    rc = winsock2::ioctlsocket(client, winsock2::FIONBIO, &nonblock);
    @assert(rc == 0, "client nonblock failed");

    winsock2::SockAddrIn addr = {};
    addr.sin_family = (ushort)winsock2::AF_INET;
    addr.sin_port = winsock2::htons(19094);

    rc = winsock2::inet_pton(
        winsock2::AF_INET,
        "127.0.0.1",
        &addr.sin_addr
    );

    @assert(rc == 1, "inet_pton failed");

    rc = winsock2::bind(
        server,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    @assert(rc == 0, "bind failed");

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");

    defer wepoll::epoll_close(epfd);

    wepoll::EPollEvent event = {};
    event.events = wepoll::EPOLLIN;
    event.data.sock = server;

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_ADD,
        (wepoll::Socket)server,
        &event
    );

    @assert(rc == 0, "epoll_ctl ADD failed");

    char[] msg = "hello wepoll";

    int sent = winsock2::sendto(
        client,
        msg.ptr,
        (int)msg.len,
        0,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    @assert(sent == (int)msg.len, "sendto failed or partial send");

    wepoll::EPollEvent[8] events;

    int n = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        1000
    );

    @assert(n > 0, "epoll_wait timed out");

    bool got_read = false;

    for (int i = 0; i < n; i++)
    {
        if (events[i].data.sock != server) continue;

        @assert((events[i].events & wepoll::EPOLLIN) != 0, "expected EPOLLIN");

        got_read = true;
    }

    @assert(got_read, "server socket was not readable");

    char[128] buf;
    winsock2::SockAddrIn from = {};
    int from_len = (int)@sizeof(from);

    int received = winsock2::recvfrom(
        server,
        &buf[0],
        (int)buf.len,
        0,
        (winsock2::SockAddr*)&from,
        &from_len
    );

    @assert(received == sent, "recvfrom failed or wrong byte count");

    String text = (String)buf[0:received];
    @assert(text == "hello wepoll", "received text mismatch");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_DEL,
        (wepoll::Socket)server,
        null
    );

    @assert(rc == 0, "epoll_ctl DEL failed");

    warn("OK");
}

// eof