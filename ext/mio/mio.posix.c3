// mio.posix.c3

// POSIX TCP/UDP sockets for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::POSIX);

import c::errno;
import c::unistd;
import c::fcntl;
import c::string;
import c::sys::socket;
import c::netinet::in;
import c::arpa::inet;

faultdef NET_ADDR_ERROR, NET_SOCKET_ERROR, NET_BIND_ERROR, NET_LISTEN_ERROR, NET_ACCEPT_ERROR, NET_CONNECT_ERROR;

const int DEFAULT_BACKLOG = 128;

struct TcpListener
{
    Fd fd;
    bool closed;
}

struct TcpStream
{
    Fd fd;
    bool closed;
}

struct UdpSocket
{
    Fd fd;
    bool closed;
}

fn int fd_to_socket(Fd fd) @inline @private
{
    return (int)fd;
}

fn Fd socket_to_fd(int sock) @inline @private
{
    return (Fd)sock;
}

fn void? set_nonblock_fd(Fd fd)
{
    int rawfd = (int)fd;

    int flags = fcntl::fcntl(rawfd, fcntl::F_GETFL, 0);
    if (flags < 0) return errno::get_fault()~;

    if (fcntl::fcntl(rawfd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? set_reuseaddr_fd(Fd fd)
{
    int yes = 1;

    if (socket::setsockopt(
        fd_to_socket(fd),
        socket::SOL_SOCKET,
        socket::SO_REUSEADDR,
        &yes,
        (socket::SockLen)@sizeof(yes)) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? peer_addr_fd(Fd fd, char[] ip_buf, ushort* port)
{
    if (fd_invalid(fd)) return errno::E_INVALID_ARG~;

    socket::SockAddrStorage peer = {};
    socket::SockLen peer_len = socket::SockAddrStorage::size;

    int rc = socket::getpeername(
        fd_to_socket(fd),
        (socket::SockAddr*)&peer,
        &peer_len
    );
    if (rc != 0) return errno::get_fault()~;

    sockaddr_to_addr((socket::SockAddr*)&peer, ip_buf, port)!;
}

fn void socket_close_fd(Fd fd)
{
    if (fd_invalid(fd)) return;

    unistd::close(fd);
}

fn Fd? socket_new_fd(int family, int type) @private
{
    Fd fd = (Fd)socket::socket(family, type, 0);

    if (fd < 0) return errno::get_fault()~;

    if (catch err = set_nonblock_fd(fd))
    {
        socket_close_fd(fd);
        return err~;
    }

    return fd;
}

fn Fd? tcp_socket_fd(int family = socket::AF_INET)
{
    return socket_new_fd(family, socket::SOCK_STREAM);
}

fn Fd? udp_socket_fd(int family = socket::AF_INET)
{
    return socket_new_fd(family, socket::SOCK_DGRAM);
}

fn char*? str2cptr(String str, char[] buf) @inline @private
{
    if (buf.len == 0) return NET_ADDR_ERROR~;
    if (str.len + 1 > buf.len) return NET_ADDR_ERROR~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn bool ip_is_v6(String ip) @private
{
    for (sz i = 0; i < ip.len; i++)
    {
        if (ip[i] == ':') return true;
    }

    return false;
}

fn int socket_family_from_ip(String ip)
{
    if (ip_is_v6(ip)) return socket::AF_INET6;
    return socket::AF_INET;
}

fn void? make_sockaddr(String ip, ushort port, socket::SockAddrStorage* addr, socket::SockLen* len) @maydiscard
{
    if (addr == null) return MIO_INVALID~;
    if (len == null) return MIO_INVALID~;

    *addr = {};
    *len = 0;

    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;

    if (ip_is_v6(ip))
    {
        in::SockAddrIn6 a6 = {};

        if (inet::inet_pton(socket::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return NET_ADDR_ERROR~;
        }

        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = in::htons(port);

        string::memcpy(addr, &a6, @sizeof(a6));
        *len = (socket::SockLen)@sizeof(a6);

        return;
    }

    in::SockAddrIn a4 = {};

    if (inet::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1)
    {
        return NET_ADDR_ERROR~;
    }

    a4.sin_family = (ushort)socket::AF_INET;
    a4.sin_port = in::htons(port);

    string::memcpy(addr, &a4, @sizeof(a4));
    *len = (socket::SockLen)@sizeof(a4);
}

fn void? sockaddr_to_addr(socket::SockAddr* addr, char[] ip_buf, ushort* port)
{
    if (addr == null) return MIO_INVALID~;
    if (ip_buf.len == 0) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    char* p = null;

    if (addr.sa_family == socket::AF_INET)
    {
        in::SockAddrIn* a4 = (in::SockAddrIn*)addr;

        p = inet::inet_ntop(
            socket::AF_INET,
            &a4.sin_addr,
            ip_buf.ptr,
            (socket::SockLen)ip_buf.len
        );

        *port = in::ntohs(a4.sin_port);
    }
    else if (addr.sa_family == socket::AF_INET6)
    {
        in::SockAddrIn6* a6 = (in::SockAddrIn6*)addr;

        p = inet::inet_ntop(
            socket::AF_INET6,
            &a6.sin6_addr,
            ip_buf.ptr,
            (socket::SockLen)ip_buf.len
        );

        *port = in::ntohs(a6.sin6_port);
    }
    else
    {
        return NET_ADDR_ERROR~;
    }

    if (p == null) return NET_ADDR_ERROR~;
}

fn int? socket_family_fd(Fd fd)
{
    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    if (socket::getsockname(fd_to_socket(fd), (socket::SockAddr*)&addr, &len) < 0)
    {
        return errno::get_fault()~;
    }

    return ((socket::SockAddr*)&addr).sa_family;
}

fn void? socket_bind_fd(Fd fd, String ip, ushort port)
{
    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    make_sockaddr(ip, port, &addr, &len)!;

    if (socket::bind(fd_to_socket(fd), (socket::SockAddr*)&addr, len) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? socket_bind_any_fd(Fd fd, int family)
{
    if (family == socket::AF_INET6)
    {
        in::SockAddrIn6 a6 = {};
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = 0;

        if (socket::bind(fd_to_socket(fd), (socket::SockAddr*)&a6, @sizeof(a6)) != 0)
        {
            return errno::get_fault()~;
        }

        return;
    }

    in::SockAddrIn a4 = {};
    a4.sin_family = (ushort)socket::AF_INET;
    a4.sin_port = 0;

    if (socket::bind(fd_to_socket(fd), (socket::SockAddr*)&a4, @sizeof(a4)) != 0)
    {
        return errno::get_fault()~;
    }
}

fn void? tcp_listen_fd(Fd fd, int backlog = DEFAULT_BACKLOG)
{
    int rc = socket::listen(fd_to_socket(fd), backlog);

    if (rc < 0) return errno::get_fault()~;
}

fn TcpListener? tcp_listen(String ip, ushort port, int backlog = DEFAULT_BACKLOG)
{
    int family = socket_family_from_ip(ip);

    Fd fd = tcp_socket_fd(family)!;
    
    defer catch socket_close_fd(fd);

    set_reuseaddr_fd((Fd)fd)!;

    socket_bind_fd((Fd)fd, ip, port)!;

    tcp_listen_fd((Fd)fd, backlog)!;
    
    return {
        .fd = (Fd)fd,
        .closed = false,
    };
}

fn bool connect_ok_or_pending(fault err)
{
    return
        err == errno::E_IN_PROGRESS ||
        err == errno::E_AGAIN ||
        err == errno::E_ALREADY ||
        err == errno::E_WOULD_BLOCK ||
        err == errno::E_IS_CONNECTED;
}

fn void? tcp_connect_fd(Fd fd, String ip, ushort port)
{
    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    make_sockaddr(ip, port, &addr, &len)!;

    int rc = socket::connect(fd_to_socket(fd), (socket::SockAddr*)&addr, len);
    if (rc < 0)
    {
        fault err = errno::get_fault();

        if (!connect_ok_or_pending(err))
        {
            return err~;
        }
    }
}

fn TcpStream? tcp_connect(String ip, ushort port)
{
    int family = socket_family_from_ip(ip);

    Fd fd = tcp_socket_fd(family)!;

    defer catch socket_close_fd(fd);

    tcp_connect_fd((Fd)fd, ip, port)!;
    
    return {
        .fd = (Fd)fd,
        .closed = false,
    };
}

fn int take_error_fd(Fd fd)
{
    int err = 0;
    socket::SockLen len = (socket::SockLen)@sizeof(err);

    if (socket::getsockopt(
        fd_to_socket(fd),
        socket::SOL_SOCKET,
        socket::SO_ERROR,
        &err,
        &len) < 0)
    {
        return -1;
    }

    return err;
}

fn int TcpStream.take_error(&self)
{
    return take_error_fd(self.fd);
}

fn Fd? tcp_accept_fd(Fd server_fd, void* peer = null)
{
    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    if (peer == null) peer = &addr;
    
    int fd = socket::accept(fd_to_socket(server_fd), (socket::SockAddr*)peer, &len);
    if (fd < 0)
    {
        return errno::get_fault()~;
    }

    defer catch unistd::close(fd);

    set_nonblock_fd((Fd)fd)!;

    return (Fd)fd;
}

fn TcpStream? TcpListener.accept(&self, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;
    if (ip_buf.len == 0) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    socket::SockAddrStorage addr = {};
    
    Fd fd = tcp_accept_fd(self.fd, &addr)!;
    
    sockaddr_to_addr((socket::SockAddr*)&addr, ip_buf, port)!;

    return {
        .fd = (Fd)fd,
        .closed = false,
    };
}

fn sz? tcp_read_fd(Fd fd, char[] buf)
{
    sz n = unistd::read((int)fd, buf.ptr, buf.len);
    if (n < 0) return errno::get_fault()~;

    return (sz)n;
}

fn sz? TcpStream.read(&self, char[] buf)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;

    return tcp_read_fd(self.fd, buf)!;
}

fn sz? tcp_write_fd(Fd fd, char[] buf)
{
    sz n = unistd::write((int)fd, buf.ptr, buf.len);
    if (n < 0) return errno::get_fault()~;

    return (sz)n;
}

fn sz? TcpStream.write(&self, char[] buf)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;

    return tcp_write_fd(self.fd, buf)!;
}

fn void TcpListener.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.fd))
    {
        unistd::close((int)self.fd);
    }

    self.fd = -1;
    self.closed = true;
}

fn void TcpStream.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.fd))
    {
        unistd::close((int)self.fd);
    }

    self.fd = -1;
    self.closed = true;
}

fn UdpSocket? udp_bind(String ip, ushort port)
{
    int family = socket_family_from_ip(ip);

    Fd fd = udp_socket_fd(family)!;
    
    defer catch socket_close_fd(fd);

    set_reuseaddr_fd((Fd)fd)!;

    socket_bind_fd((Fd)fd, ip, port)!;

    return {
        .fd = (Fd)fd,
        .closed = false,
    };
}

fn UdpSocket? udp_socket(int family = socket::AF_INET)
{
    Fd fd = udp_socket_fd(family)!;
    
    defer catch socket_close_fd(fd);

    return {
        .fd = (Fd)fd,
        .closed = false,
    };
}

fn sz? udp_recvfrom_fd(Fd fd, char[] buf, char[] ip_buf, ushort* port)
{
    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    sz n = socket::recvfrom(
        fd_to_socket(fd),
        buf.ptr,
        buf.len,
        0,
        (socket::SockAddr*)&addr,
        &len
    );

    if (n < 0) return errno::get_fault()~;

    sockaddr_to_addr((socket::SockAddr*)&addr, ip_buf, port)!;

    return (sz)n;
}

fn sz? UdpSocket.recv_from(&self, char[] buf, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;
    if (ip_buf.len == 0) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    return udp_recvfrom_fd(self.fd, buf, ip_buf,port)!;
}

fn sz? udp_sendto_fd(Fd fd, char[] buf, String ip, ushort port)
{
    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    make_sockaddr(ip, port, &addr, &len)!;

    sz n = socket::sendto(
        fd_to_socket(fd),
        buf.ptr,
        buf.len,
        0,
        (socket::SockAddr*)&addr,
        len
    );

    if (n < 0) return errno::get_fault()~;

    return (sz)n;
}

fn sz? UdpSocket.send_to(&self, char[] buf, String ip, ushort port)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;

    return udp_sendto_fd(self.fd, buf, ip, port)!;
}

fn void UdpSocket.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.fd))
    {
        unistd::close((int)self.fd);
    }

    self.fd = -1;
    self.closed = true;
}

fn Waker*? waker_new()
{
    int[2] fds;

    if (unistd::pipe(&fds) < 0)
    {
        return errno::get_fault()~;
    }

    defer (catch err)
    {
        unistd::close(fds[0]);
        unistd::close(fds[1]);
    }

    set_nonblock_fd((Fd)fds[0])!;
    set_nonblock_fd((Fd)fds[1])!;

    Waker* waker = localmem.alloc(Waker)!;

    *waker = {
        .read_fd = (Fd)fds[0],
        .write_fd = (Fd)fds[1],
        .closed = false,
    };

    return waker;
}

fn Fd Waker.fd(&self) @inline
{
    return self.read_fd;
}

fn void? Waker.wake(&self)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.write_fd)) return MIO_INVALID~;

    char[1] buf = { 1 };

    sz n = unistd::write((int)self.write_fd, &buf[0], 1);
    if (n < 0)
    {
        fault err = errno::get_fault();

        if (err == errno::E_AGAIN || err == errno::E_WOULD_BLOCK)
        {
            return;
        }

        return err~;
    }
}

fn void? Waker.drain(&self)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.read_fd)) return MIO_INVALID~;

    char[64] buf;

    while (true)
    {
        sz n = unistd::read((int)self.read_fd, &buf[0], buf.len);
        if (n > 0) continue;

        if (n == 0) return;

        fault err = errno::get_fault();

        if (err == errno::E_AGAIN || err == errno::E_WOULD_BLOCK)
        {
            return;
        }

        return err~;
    }
}

fn void Waker.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.read_fd))
    {
        unistd::close((int)self.read_fd);
    }

    if (!fd_invalid(self.write_fd))
    {
        unistd::close((int)self.write_fd);
    }

    self.read_fd = -1;
    self.write_fd = -1;
    self.closed = true;
}

fn void Waker.free(&self)
{
    self.close();
    localmem.free(self);
}

fn void? socket_local_addr(Fd fd, char[] ip_buf, ushort* port) @private
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (ip_buf.len == 0) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    if (socket::getsockname((int)fd, (socket::SockAddr*)&addr, &len) < 0)
    {
        return errno::get_fault()~;
    }

    return sockaddr_to_addr((socket::SockAddr*)&addr, ip_buf, port)!;
}

fn void? socket_peer_addr(Fd fd, char[] ip_buf, ushort* port) @private
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (ip_buf.len == 0) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    socket::SockAddrStorage addr = {};
    socket::SockLen len = (socket::SockLen)@sizeof(addr);

    if (socket::getpeername((int)fd, (socket::SockAddr*)&addr, &len) < 0)
    {
        return errno::get_fault()~;
    }

    return sockaddr_to_addr((socket::SockAddr*)&addr, ip_buf, port)!;
}

fn void? TcpListener.local_addr(&self, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    return socket_local_addr(self.fd, ip_buf, port)!;
}

fn void? TcpStream.local_addr(&self, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    return socket_local_addr(self.fd, ip_buf, port)!;
}

fn void? TcpStream.peer_addr(&self, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    return socket_peer_addr(self.fd, ip_buf, port)!;
}

fn void? UdpSocket.local_addr(&self, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    return socket_local_addr(self.fd, ip_buf, port)!;
}

// eof