// mio.win32.c3

// Windows TCP/UDP sockets for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::WIN32) @link("ws2_32");

import c::errno;
import c::winsock2;
import c::ws2tcpip;
import c::winbase;
import c::string;
import ext::debug;

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

bool winsock_inited = false;

fn void init_winsock() @init
{
    if (winsock_inited) return;

    winsock2::WSAData data;
    int rc = winsock2::wsaStartup(0x0202, &data);

    @assert(rc == 0, "WSAStartup failed");

    winsock_inited = true;
}

fn winsock2::Socket fd_to_socket(Fd fd) @inline @private
{
    return (winsock2::Socket)fd;
}

fn Fd socket_to_fd(winsock2::Socket sock) @inline @private
{
    return (Fd)sock;
}

fn bool socket_invalid(winsock2::Socket sock) @inline @private
{
    return sock == winsock2::INVALID_SOCKET;
}

fn int last_socket_error() @private
{
    return winsock2::wsaGetLastError();
}

fn fault socket_fault()
{
    return errno::wsa_fault();
}

fn void? set_nonblock(Fd fd)
{
    winsock2::Socket sock = fd_to_socket(fd);

    uint mode = 1;
    if (winsock2::ioctlsocket(sock, winsock2::FIONBIO, &mode) != 0)
    {
        return socket_fault()~;
    }
}

fn void? set_reuseaddr(Fd fd) @private
{
    winsock2::Socket sock = fd_to_socket(fd);

    int yes = 1;
    if (winsock2::setsockopt(
        sock,
        winsock2::SOL_SOCKET,
        winsock2::SO_REUSEADDR,
        (char*)&yes,
        (int)@sizeof(yes)) != 0)
    {
        return socket_fault()~;
    }
}

fn char*? str2cptr(String str, char[] buf) @inline @private
{
    if (buf.len == 0) return NET_ADDR_ERROR~;
    if (str.len+1 > buf.len) return NET_ADDR_ERROR~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn void? make_sockaddr(String ip, ushort port, winsock2::SockAddrStorage* addr, winsock2::SockLen* len) @maydiscard
{
    if (addr == null) return MIO_INVALID~;
    if (len == null) return MIO_INVALID~;
    
    winsock2::SockAddrIn a4 = {};
    winsock2::SockAddrIn6 a6 = {};

    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;
    
    *addr = {};
    if (string::strchr(ip_str, ':') != null) 
    {
        if (winsock2::inet_pton(winsock2::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return NET_ADDR_ERROR~;
        }
        a6.sin6_family = (ushort)winsock2::AF_INET6;
        a6.sin6_port = winsock2::htons(port);
        string::memcpy(addr, &a6, @sizeof(a6));
        *len = @sizeof(a6);
    }
    else 
    {
        a4.sin_family = (ushort)winsock2::AF_INET;
        a4.sin_port = winsock2::htons(port);
        if (winsock2::inet_pton(winsock2::AF_INET, ip_str, &a4.sin_addr) != 1) 
        {
            return NET_ADDR_ERROR~;
        }
        string::memcpy(addr, &a4, @sizeof(a4));
        *len = @sizeof(a4);
    }
}

fn void? sockaddr_to_addr(winsock2::SockAddr* addr, char[] ip_buf, ushort* port)
{
    char* p = null;
    
    if (addr.sa_family == winsock2::AF_INET)
    {
        winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)addr;
        p = winsock2::inet_ntop(
            winsock2::AF_INET,
            &a4.sin_addr,
            ip_buf.ptr,
            (winsock2::SockLen)ip_buf.len
        );
        *port = winsock2::ntohs(a4.sin_port);
    }
    else if (addr.sa_family == winsock2::AF_INET6)
    {
        winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)addr;

        p = winsock2::inet_ntop(
            winsock2::AF_INET6,
            &a6.sin6_addr,
            ip_buf.ptr,
            (winsock2::SockLen)ip_buf.len
        );
        *port = winsock2::ntohs(a6.sin6_port);
    }
    else
    {
        return NET_ADDR_ERROR~;
    }

    if (p == null) return NET_ADDR_ERROR~;
}

fn int? socket_family(Fd fd) @private
{
    winsock2::SockAddrStorage addr = {};
    int len = winsock2::SockAddrStorage::size;

    if (winsock2::getsockname((winsock2::Socket)fd, (winsock2::SockAddr*)&addr, &len) != 0)
    {
        return NET_ADDR_ERROR~;
    }

    return ((winsock2::SockAddr*)&addr).sa_family;
}

fn int socket_family_from_ip(String ip) @private
{
    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!!;

    if (string::strchr(ip_str, ':') != null) return winsock2::AF_INET6;
    return winsock2::AF_INET;
}

fn void? socket_bind(Fd fd, String ip, ushort port)
{
    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = @sizeof(addr);
    make_sockaddr(ip, port, &addr, &len)!;

    // bind to address
    int b = winsock2::bind((winsock2::Socket) fd, (winsock2::SockAddr*)&addr, len);
    if (b != 0) return socket_fault()~;
}

fn TcpListener? tcp_listen(String ip, ushort port, int backlog = DEFAULT_BACKLOG)
{
    int family = socket_family_from_ip(ip);
    winsock2::Socket sock = winsock2::socket(family, winsock2::SOCK_STREAM, winsock2::IPPROTO_TCP);
    if (socket_invalid(sock)) return socket_fault()~;

    defer catch winsock2::closesocket(sock);

    set_reuseaddr(socket_to_fd(sock))!;
    set_nonblock(socket_to_fd(sock))!;

    socket_bind(socket_to_fd(sock), ip, port)!;
    
    if (winsock2::listen(sock, backlog) != 0)
    {
        return socket_fault()~;
    }

    return {
        .fd = socket_to_fd(sock),
        .closed = false,
    };
}

fn TcpStream? tcp_connect(String ip, ushort port)
{
    int family = socket_family_from_ip(ip);

    winsock2::Socket sock = winsock2::socket(family, winsock2::SOCK_STREAM, winsock2::IPPROTO_TCP);
    if (socket_invalid(sock)) return socket_fault()~;

    defer catch winsock2::closesocket(sock);

    set_nonblock(socket_to_fd(sock))!;

    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = @sizeof(addr);
    make_sockaddr(ip, port, &addr, &len)!;

    int rc = winsock2::connect(sock, (winsock2::SockAddr*)&addr, len);
    if (rc != 0)
    {
        int err = last_socket_error();

        if (err != winsock2::WSAEWOULDBLOCK && err != winsock2::WSAEINPROGRESS && err != winsock2::WSAEALREADY)
        {
            return socket_fault()~;
        }
    }

    return {
        .fd = socket_to_fd(sock),
        .closed = false,
    };
}

fn int TcpStream.take_error(&self)
{
    int err = 0;
    int len = (int)@sizeof(err);

    if (winsock2::getsockopt(
        fd_to_socket(self.fd),
        winsock2::SOL_SOCKET,
        winsock2::SO_ERROR,
        (char*)&err,
        &len) != 0)
    {
        return last_socket_error();
    }

    return err;
}

fn TcpStream? TcpListener.accept(&self, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;
    if (ip_buf.len < 8) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = @sizeof(addr);
 
    winsock2::Socket sock = winsock2::accept(
        fd_to_socket(self.fd),
        (winsock2::SockAddr*)&addr,
        (int*)&len
    );
    if (socket_invalid(sock))
    {
        return socket_fault()~;
    }

    defer catch winsock2::closesocket(sock);

    set_nonblock(socket_to_fd(sock))!;

    sockaddr_to_addr((winsock2::SockAddr*)&addr, ip_buf, port)!;

    return {
        .fd = socket_to_fd(sock),
        .closed = false,
    };
}

fn sz? TcpStream.read(&self, char[] buf)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;

    int n = winsock2::recv(fd_to_socket(self.fd), buf.ptr, (int)buf.len, 0);
    if (n < 0) return socket_fault()~;

    return (sz)n;
}

fn sz? TcpStream.write(&self, char[] buf)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;

    int n = winsock2::send(fd_to_socket(self.fd), buf.ptr, (int)buf.len, 0);
    if (n < 0) return socket_fault()~;

    return (sz)n;
}

fn void TcpListener.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.fd))
    {
        winsock2::closesocket(fd_to_socket(self.fd));
    }

    self.fd = -1;
    self.closed = true;
}

fn void TcpStream.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.fd))
    {
        winsock2::closesocket(fd_to_socket(self.fd));
    }

    self.fd = -1;
    self.closed = true;
}

fn UdpSocket? udp_bind(String ip, ushort port)
{
    int family = socket_family_from_ip(ip);

    winsock2::Socket sock = winsock2::socket(family, winsock2::SOCK_DGRAM, winsock2::IPPROTO_UDP);
    if (socket_invalid(sock)) return socket_fault()~;

    defer catch winsock2::closesocket(sock);

    set_reuseaddr(socket_to_fd(sock))!;
    set_nonblock(socket_to_fd(sock))!;

    socket_bind(socket_to_fd(sock), ip, port)!;
    
    return {
        .fd = socket_to_fd(sock),
        .closed = false,
    };
}

fn UdpSocket? udp_socket(int family = winsock2::AF_INET)
{
    winsock2::Socket sock = winsock2::socket(family, winsock2::SOCK_DGRAM, winsock2::IPPROTO_UDP);
    if (socket_invalid(sock)) return socket_fault()~;

    defer catch winsock2::closesocket(sock);

    set_nonblock(socket_to_fd(sock))!;

    return {
        .fd = socket_to_fd(sock),
        .closed = false,
    };
}

fn sz? UdpSocket.recv_from(&self, char[] buf, char[] ip_buf, ushort* port)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;
    if (ip_buf.len < 8) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;
    
    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = @sizeof(addr);

    int n = winsock2::recvfrom(
        fd_to_socket(self.fd),
        buf.ptr,
        (int)buf.len,
        0,
        (winsock2::SockAddr*)&addr,
        (int*)&len
    );
    if (n < 0) return socket_fault()~;
    
    sockaddr_to_addr((winsock2::SockAddr*)&addr, ip_buf, port)!;

    return (sz)n;
}

fn sz? UdpSocket.send_to(&self, char[] buf, String ip, ushort port)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.fd)) return MIO_INVALID~;

    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = @sizeof(addr);
    make_sockaddr(ip, port, &addr, &len)!;
    
    int n = winsock2::sendto(
        fd_to_socket(self.fd),
        buf.ptr,
        (int)buf.len,
        0,
        (winsock2::SockAddr*)&addr,
        (int)len
    );
    if (n < 0) return socket_fault()~;

    return (sz)n;
}

fn void UdpSocket.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.fd))
    {
        winsock2::closesocket(fd_to_socket(self.fd));
    }

    self.fd = -1;
    self.closed = true;
}

fn winsock2::SockAddrIn? get_socket_addr(Fd fd) @private
{
    winsock2::SockAddrIn addr = {};
    int len = (int)@sizeof(addr);

    if (winsock2::getsockname(
        fd_to_socket(fd),
        (winsock2::SockAddr*)&addr,
        &len) != 0)
    {
        return socket_fault()~;
    }

    return addr;
}

fn Waker*? waker_new()
{
    UdpSocket read_sock = udp_bind("127.0.0.1", 0)!;
    UdpSocket write_sock = udp_socket()!;

    defer (catch err)
    {
        read_sock.close();
        write_sock.close();
    }

    Waker* waker = localmem.alloc(Waker)!;
    *waker = {
        .read_fd = read_sock.fd,
        .write_fd = write_sock.fd,
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
    if (fd_invalid(self.read_fd)) return MIO_INVALID~;
    if (fd_invalid(self.write_fd)) return MIO_INVALID~;

    winsock2::SockAddrIn addr = get_socket_addr(self.read_fd)!;

    char[1] buf = { 1 };

    int n = winsock2::sendto(
        fd_to_socket(self.write_fd),
        &buf[0],
        1,
        0,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    if (n < 0)
    {
        return socket_fault()~;
    }
}

fn void? Waker.drain(&self)
{
    if (self.closed) return MIO_CLOSED~;
    if (fd_invalid(self.read_fd)) return MIO_INVALID~;

    char[64] buf;

    while (true)
    {
        int n = winsock2::recv(
            fd_to_socket(self.read_fd),
            &buf[0],
            (int)buf.len,
            0
        );

        if (n > 0) continue;
        if (n == 0) return;

        int err = last_socket_error();

        if (err == winsock2::WSAEWOULDBLOCK)
        {
            return;
        }

        return socket_fault()~;
    }
}

fn void Waker.close(&self)
{
    if (self.closed) return;

    if (!fd_invalid(self.read_fd))
    {
        winsock2::closesocket(fd_to_socket(self.read_fd));
    }

    if (!fd_invalid(self.write_fd))
    {
        winsock2::closesocket(fd_to_socket(self.write_fd));
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
    if (ip_buf.len < 8) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = (winsock2::SockLen)@sizeof(addr);

    if (winsock2::getsockname((int)fd, (winsock2::SockAddr*)&addr, (int*)&len) < 0)
    {
        return errno::get_fault()~;
    }

    return sockaddr_to_addr((winsock2::SockAddr*)&addr, ip_buf, port)!;
}

fn void? socket_peer_addr(Fd fd, char[] ip_buf, ushort* port) @private
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (ip_buf.len < 8) return MIO_INVALID~;
    if (port == null) return MIO_INVALID~;

    winsock2::SockAddrStorage addr = {};
    winsock2::SockLen len = (winsock2::SockLen)@sizeof(addr);

    if (winsock2::getpeername((int)fd, (winsock2::SockAddr*)&addr, (int*)&len) < 0)
    {
        return errno::get_fault()~;
    }

    return sockaddr_to_addr((winsock2::SockAddr*)&addr, ip_buf, port)!;
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