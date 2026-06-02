// test_tcp.c3

// TCP direct wepoll test
//
// Nomota <hiongun@gmail.com>; MIT License

import std::io;
import c::winbase;
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

const ushort TEST_PORT = 19111;

fn winsock2::Socket make_tcp_socket()
{
    winsock2::Socket sock = winsock2::socket(
        winsock2::AF_INET,
        winsock2::SOCK_STREAM,
        winsock2::IPPROTO_TCP
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

fn winsock2::Socket make_listener(ushort port)
{
    winsock2::Socket listener = make_tcp_socket();

    winsock2::SockAddrIn addr;
    make_addr(&addr, port);

    int rc = winsock2::bind(
        listener,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    @assert(rc == 0, "bind failed");

    rc = winsock2::listen(listener, 16);
    @assert(rc == 0, "listen failed");

    return listener;
}

fn void connect_client(winsock2::Socket client, ushort port)
{
    winsock2::SockAddrIn addr;
    make_addr(&addr, port);

    int rc = winsock2::connect(
        client,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    if (rc == 0) return;

    int err = winsock2::wsaGetLastError();

    @assert(
        err == winsock2::WSAEWOULDBLOCK ||
        err == winsock2::WSAEINPROGRESS ||
        err == winsock2::WSAEALREADY,
        "connect failed"
    );
}

fn winsock2::Socket accept_client(winsock2::Socket listener)
{
    winsock2::SockAddrIn addr = {};
    int addr_len = (int)@sizeof(addr);

    winsock2::Socket accepted = winsock2::accept(
        listener,
        (winsock2::SockAddr*)&addr,
        &addr_len
    );

    @assert(accepted != winsock2::INVALID_SOCKET, "accept failed");

    uint nonblock = 1;

    int rc = winsock2::ioctlsocket(
        accepted,
        winsock2::FIONBIO,
        &nonblock
    );

    @assert(rc == 0, "accepted FIONBIO failed");

    return accepted;
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

fn void mod_socket(wepoll::EPollFd epfd, winsock2::Socket sock, uint events)
{
    wepoll::EPollEvent event = {};
    event.events = events;
    event.data.sock = (wepoll::Socket)sock;

    int rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_MOD,
        (wepoll::Socket)sock,
        &event
    );

    @assert(rc == 0, "epoll_ctl MOD failed");
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
//warn("%d", winbase::getLastError());
//warn("%d", n);
    @assert(n >= 0, "epoll_wait failed");

    return n;
}

fn void main()
{
    winsock2::WSAData data;

    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    winsock2::Socket listener = make_listener(TEST_PORT);
    defer winsock2::closesocket(listener);

    winsock2::Socket client = make_tcp_socket();
    defer winsock2::closesocket(client);

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");

    defer wepoll::epoll_close(epfd);

    add_socket(epfd, listener, wepoll::EPOLLIN);

    connect_client(client, TEST_PORT);

    wepoll::EPollEvent[16] events;

    int n = wait_events(epfd, events[..], 1000);
    @assert(n > 0, "listener did not become readable");
    @assert(has_event(events[..], n, listener, wepoll::EPOLLIN), "listener missing EPOLLIN");

    winsock2::Socket accepted = accept_client(listener);
    defer winsock2::closesocket(accepted);

    add_socket(epfd, accepted, wepoll::EPOLLIN);

    char[] msg = "hello tcp wepoll";

    int sent = winsock2::send(
        client,
        msg.ptr,
        (int)msg.len,
        0
    );

    @assert(sent == (int)msg.len, "send failed or partial send");

    n = wait_events(epfd, events[..], 1000);
    @assert(n > 0, "accepted socket did not become readable");
    @assert(has_event(events[..], n, accepted, wepoll::EPOLLIN), "accepted missing EPOLLIN");

    char[128] buf;

    int received = winsock2::recv(
        accepted,
        &buf[0],
        (int)buf.len,
        0
    );

    @assert(received == sent, "recv failed or wrong byte count");

    String text = (String)buf[0:received];
    @assert(text == "hello tcp wepoll", "received text mismatch");

    mod_socket(epfd, accepted, wepoll::EPOLLOUT);

    n = wait_events(epfd, events[..], 1000);
    @assert(n > 0, "accepted socket did not become writable");
    @assert(has_event(events[..], n, accepted, wepoll::EPOLLOUT), "accepted missing EPOLLOUT");

    del_socket(epfd, accepted);
    del_socket(epfd, listener);

    warn("OK");
}

// eof