// socket.posix.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio @if(env::POSIX);

import c::unistd;
import c::errno;
import c::fcntl;
import c::string;
import c::stdlib;
import c::stdio;

import c::sys::socket;
import c::netinet::in;
import c::arpa::inet;

import std::collections::map;
import ext::debug;

faultdef ASYNC_ADDR_ERROR, ASYNC_CONNECT_ERROR, ASYNC_BIND_ERROR, ASYNC_LISTEN_ERROR, ASYNC_ACCEPT_ERROR;

const int DEFAULT_BACKLOG @private = 128;

HashMap{int, String} ips;
bool ips_inited = false;

fn void ips_init()
{
    if (ips_inited) return;

    ips.init(localmem);
    ips_inited = true;
}

fn void socket_forget_ip(int fd)
{
    if (!ips_inited) return;

    if (ips.has_key(fd)) {
        (void)ips[fd].free(localmem);
        ips.remove(fd);
    }
}

fn void? set_nonblocking(int fd) @maydiscard @private
{
    int flags = fcntl::fcntl(fd, fcntl::F_GETFL, 0);

    if (flags < 0) {
        return errno::get_fault()~;
    }

    int rc = fcntl::fcntl(fd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK);

    if (rc < 0) {
        return errno::get_fault()~;
    }

    return;
}

fn int? tcp_socket(int family = socket::AF_INET)
{
    int fd = socket::socket(family, socket::SOCK_STREAM, 0);

    if (fd < 0) {
        return errno::get_fault()~;
    }

    if (catch err = set_nonblocking(fd)) {
        unistd::close(fd);
        return err~;
    }

    return fd;
}

fn void? make_sockaddr_ipv4(String host, ushort port, in::SockAddrIn* addr) @maydiscard
{
    string::memset(addr, 0, in::SockAddrIn.sizeof);

    addr.sin_family = socket::AF_INET;
    addr.sin_port = in::htons(port);

    char[256] host_buf;

    if (host.len >= host_buf.len) {
        return ASYNC_ADDR_ERROR~;
    }

    string::memcpy(&host_buf[0], host.ptr, host.len);
    host_buf[host.len] = 0;

    int rc = inet::inet_pton(socket::AF_INET, &host_buf[0], &addr.sin_addr);

    if (rc <= 0) {
        return ASYNC_ADDR_ERROR~;
    }

    return;
}

fn void? tcp_bind(int fd, String host, ushort port)
{
    in::SockAddrIn addr;

    make_sockaddr_ipv4(host, port, &addr)!;

    int yes = 1;

    int rc = socket::setsockopt(
        fd,
        socket::SOL_SOCKET,
        socket::SO_REUSEADDR,
        &yes,
        CInt.sizeof
    );

    if (rc < 0) {
        return errno::get_fault()~;
    }

    rc = socket::bind(
        fd,
        (socket::SockAddr*)&addr,
        in::SockAddrIn.sizeof
    );

    if (rc < 0) {
        return errno::get_fault()~;
    }

    return;
}

fn void? tcp_listen(int fd, int backlog = DEFAULT_BACKLOG)
{
    int rc = socket::listen(fd, backlog);

    if (rc < 0) {
        return errno::get_fault()~;
    }

    return;
}

fn String? sockaddr_ipv4_to_string(in::SockAddrIn* addr)
{
    char[64] buf;

    char* p = inet::inet_ntop(
        socket::AF_INET,
        &addr.sin_addr,
        &buf[0],
        buf.len
    );

    if (p == null) {
        return ASYNC_ADDR_ERROR~;
    }

    String ip = ((String)p[0:string::strlen(p)]).copy(localmem);
    return ip;
}

fn int? tcp_accept(int server_fd)
{
    while (true) {
        in::SockAddrIn addr;
        socket::SockLen len = in::SockAddrIn.sizeof;

        int client_fd = socket::accept(
            server_fd,
            (socket::SockAddr*)&addr,
            &len
        );

        if (client_fd >= 0) {
            set_nonblocking(client_fd)!;

            ips_init();
            String ip = sockaddr_ipv4_to_string(&addr)!;
            if (ips.has_key(client_fd)) {
                (void)ips[client_fd].free(localmem);
                ips.remove(client_fd);
            }
            
            ips[client_fd] = ip;
            return client_fd;
        }

        int err = errno::errno();

        if (err == errno::EINTR) {
            continue;
        }

        if (err == errno::EAGAIN || err == errno::EWOULDBLOCK) {
            wait_readable(server_fd)!;
            continue;
        }

        return ASYNC_ACCEPT_ERROR~;
    }

    // return ASYNC_ACCEPT_ERROR~;
}

fn void? tcp_connect(int fd, String host, ushort port)
{
    in::SockAddrIn addr;

    make_sockaddr_ipv4(host, port, &addr)!;

    int rc = socket::connect(
        fd,
        (socket::SockAddr*)&addr,
        in::SockAddrIn.sizeof
    );

    if (rc == 0) {
        return;
    }

    int err = errno::errno();

    if (err != errno::EINPROGRESS &&
        err != errno::EALREADY &&
        err != errno::EWOULDBLOCK) {
        return ASYNC_CONNECT_ERROR~;
    }

    wait_writable(fd)!;

    int so_error = 0;
    socket::SockLen len = CInt.sizeof;

    rc = socket::getsockopt(
        fd,
        socket::SOL_SOCKET,
        socket::SO_ERROR,
        &so_error,
        &len
    );

    if (rc < 0) {
        return ASYNC_CONNECT_ERROR~;
    }

    if (so_error != 0) {
        warn("connect failed so_error=%d", so_error);

        return ASYNC_CONNECT_ERROR~;
    }

    return;
}

fn Stream*? open_connection(String host, ushort port)
{
    int fd = tcp_socket()!;

    if (catch err = tcp_connect(fd, host, port)) {
        unistd::close(fd);
        return err~;
    }

    return stream_new(fd);
}

fn int? tcp_listen_socket(String host, ushort port, int backlog = DEFAULT_BACKLOG)
{
    int fd = tcp_socket()!;

    if (catch err = tcp_bind(fd, host, port)) {
        unistd::close(fd);
        return err~;
    }

    if (catch err = tcp_listen(fd, backlog)) {
        unistd::close(fd);
        return err~;
    }

    return fd;
}

