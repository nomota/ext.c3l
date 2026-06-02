// test_invalid_api.c3

// Invalid API / error-path direct wepoll test
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::winbase;
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

const ushort TEST_PORT = 19141;

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

fn void assert_fail(int rc, String what)
{
    @assert(rc < 0, what);
}

fn void assert_null(void* ptr, String what)
{
    @assert(ptr == null, what);
}

fn void assert_ok(int rc, String what)
{
    @assert(rc == 0, what);
}

fn void main()
{
    winsock2::WSAData data;

    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    wepoll::EPollFd bad_epfd;

    bad_epfd = wepoll::epoll_create(0);
    assert_null(bad_epfd, "epoll_create(0) should fail");

    bad_epfd = wepoll::epoll_create1(1);
    assert_null(bad_epfd, "epoll_create1(nonzero flags) should fail");

    wepoll::EPollEvent[8] events;

    rc = wepoll::epoll_wait(
        null,
        &events[0],
        events.len,
        0
    );

    assert_fail(rc, "epoll_wait(null epfd) should fail");

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");

    rc = wepoll::epoll_wait(
        epfd,
        &events[0],
        0,
        0
    );

    assert_fail(rc, "epoll_wait(maxevents=0) should fail");

    winsock2::Socket server = make_udp_socket();
    defer winsock2::closesocket(server);

    bind_udp(server, TEST_PORT);

    wepoll::EPollEvent event = {};
    event.events = wepoll::EPOLLIN;
    event.data.sock = (wepoll::Socket)server;

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_DEL,
        (wepoll::Socket)server,
        null
    );

    assert_fail(rc, "EPOLL_CTL_DEL for unregistered socket should fail");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_MOD,
        (wepoll::Socket)server,
        &event
    );

    assert_fail(rc, "EPOLL_CTL_MOD for unregistered socket should fail");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_ADD,
        (wepoll::Socket)server,
        &event
    );

    assert_ok(rc, "EPOLL_CTL_ADD should succeed");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_ADD,
        (wepoll::Socket)server,
        &event
    );

    assert_fail(rc, "duplicate EPOLL_CTL_ADD should fail");

    event.events = wepoll::EPOLLIN | wepoll::EPOLLONESHOT;
    event.data.sock = (wepoll::Socket)server;

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_MOD,
        (wepoll::Socket)server,
        &event
    );

    assert_ok(rc, "EPOLL_CTL_MOD should succeed");

    rc = wepoll::epoll_ctl(
        epfd,
        9999,
        (wepoll::Socket)server,
        &event
    );

    assert_fail(rc, "invalid epoll_ctl op should fail");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_DEL,
        (wepoll::Socket)server,
        null
    );

    assert_ok(rc, "EPOLL_CTL_DEL should succeed");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_DEL,
        (wepoll::Socket)server,
        null
    );

    assert_fail(rc, "second EPOLL_CTL_DEL should fail");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_MOD,
        (wepoll::Socket)server,
        &event
    );

    assert_fail(rc, "EPOLL_CTL_MOD after DEL should fail");

    rc = wepoll::epoll_close(epfd);
    assert_ok(rc, "epoll_close should succeed");

    rc = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        0
    );

    assert_fail(rc, "epoll_wait after epoll_close should fail");

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_ADD,
        (wepoll::Socket)server,
        &event
    );

    assert_fail(rc, "epoll_ctl after epoll_close should fail");

    rc = wepoll::epoll_close(epfd);
    assert_fail(rc, "second epoll_close should fail");

    warn("OK");
}

// eof