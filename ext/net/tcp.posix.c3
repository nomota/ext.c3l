// tcp.c3 - IPv4/IPv6 Support

module ext::net::tcp @if(!env::WIN32);

import c::netinet::in;
import c::sys::socket;
import c::unistd;
import c::fcntl;
import c::errno;

typedef TcpSocket = inline int;

fn char*? str2cptr(String str, char[] buf) @inline @local
{
    if (buf.len == 0 || str.len+1 > buf.len) return errno::E_INVALID_ARG~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn int detect_ip_version(String ip) @inline @local
{
    foreach (c : ip)
    {
        if (c == ':') return socket::AF_INET6;
    }
    return socket::AF_INET;
}

fn bool would_block() @inline @local
{
    int err = errno::errno();
    return err == errno::EAGAIN
        || err == errno::EWOULDBLOCK
        || err == errno::EINPROGRESS
        || err == errno::EALREADY;
}

fn fault socket_fault() @inline @local
{
    if (would_block()) return errno::E_WOULD_BLOCK;

    return errno::get_fault();
}

fn TcpSocket? new(int version = socket::AF_INET)
{
    TcpSocket sock = (TcpSocket)socket::socket((int)version, socket::SOCK_STREAM, 0);
    if (sock == -1)
    {
        return errno::get_fault()~;
    }
    return sock;
}

// opt_ip == "*"  binds IPv4 INADDR_ANY.
// opt_ip == "::" binds IPv6 in6addr_any.
// Host names are not resolved; pass numeric IPv4/IPv6 addresses only.
fn void? TcpSocket.listen(sock, ushort port, String opt_ip = "*", int backlog = 128) @maydiscard
{
    int option = 1;

    int r = socket::setsockopt(sock, socket::SOL_SOCKET, socket::SO_REUSEADDR, (void*)&option, $sizeof(option));
    if (r < 0) return errno::get_fault()~;

    r = socket::setsockopt(sock, socket::SOL_SOCKET, socket::SO_REUSEPORT, (void*)&option, $sizeof(option));
    if (r < 0)
    {
        return errno::get_fault()~;
    }

    int version = detect_ip_version(opt_ip);

    if (version == socket::AF_INET6)
    {
        SockAddrIn6 adr = {};
        adr.sin6_family = socket::AF_INET6;

        if (opt_ip == "::")
        {
            adr.sin6_addr = {};
        }
        else
        {
            char[128] ip_buf;
            char* ip_cstr = str2cptr(opt_ip, &ip_buf)!;

            int rc = in::inet_pton(socket::AF_INET6, ip_cstr, &adr.sin6_addr);
            if (rc == 0) return errno::E_INVALID_ARG~;
            if (rc < 0)
            {
                return errno::get_fault()~;
            }
        }

        adr.sin6_port = in::htons(port);

        if (socket::bind(sock, (SockAddr*)&adr, $sizeof(adr)) < 0)
        {
            return errno::get_fault()~;
        }
    }
    else
    {
        SockAddrIn adr = {};
        adr.sin_family = socket::AF_INET;

        if (opt_ip == "*")
        {
            adr.sin_addr.s_addr = in::htonl(in::INADDR_ANY);
        }
        else
        {
            char[128] ip_buf;
            char* ip_cstr = str2cptr(opt_ip, &ip_buf)!;

            int rc = in::inet_pton(socket::AF_INET, ip_cstr, &adr.sin_addr);
            if (rc == 0) return errno::E_INVALID_ARG~;
            if (rc < 0)
            {
                return errno::get_fault()~;
            }
        }

        adr.sin_port = in::htons(port);

        if (socket::bind(sock, (SockAddr*)&adr, $sizeof(adr)) < 0)
        {
            return errno::get_fault()~;
        }
    }

    r = socket::listen(sock, backlog);
    if (r < 0)
    {
        return errno::get_fault()~;
    }
}

fn TcpSocket? new_listen(ushort port, String opt_ip = "*", int backlog = 128)
{
    int version = detect_ip_version(opt_ip);
    TcpSocket sock = new(version)!;
    defer catch (void)sock.close();

    sock.listen(port, opt_ip, backlog)!;
    
    return sock;
}

char[1] __null__;

fn TcpSocket? TcpSocket.accept(sock, char[] ip = &__null__, ushort* port = null)
{
    SockAddrStorage adr = {};
    SockLen size = $sizeof(adr);

    TcpSocket s = (TcpSocket)socket::accept(sock, (SockAddr*)&adr, &size);
    if (s < 0) return socket_fault()~;

    bool want_ip = ip != &__null__;
    bool want_port = port != null;

    if (want_ip && want_port)
    {
        if (adr.ss_family == socket::AF_INET6)
        {
            SockAddrIn6* adr6 = (SockAddrIn6*)&adr;

            if (in::inet_ntop(socket::AF_INET6, &adr6.sin6_addr, ip.ptr, ip.len) == null)
            {
                (void)s.close();
                return errno::get_fault()~;
            }
            
            *port = in::ntohs(adr6.sin6_port);
        }
        else
        {
            SockAddrIn* adr4 = (SockAddrIn*)&adr;

            if (in::inet_ntop(socket::AF_INET, &adr4.sin_addr, ip.ptr, ip.len) == null)
            {
                (void)s.close();
                return errno::get_fault()~;
            }
            *port = in::ntohs(adr4.sin_port);
        }
    }

    return s;
}

fn void? TcpSocket.connect(sock, String ip, ushort port) @maydiscard
{
    int version = detect_ip_version(ip);

    if (version == socket::AF_INET6)
    {
        SockAddrIn6 adr = {};
        adr.sin6_family = socket::AF_INET6;
        adr.sin6_port = in::htons(port);

        char[128] ip_buf;
        char* ip_cstr = str2cptr(ip, &ip_buf)!;

        int rc = in::inet_pton(socket::AF_INET6, ip_cstr, &adr.sin6_addr);
        if (rc == 0) return errno::E_INVALID_ARG~;
        if (rc < 0)
        {
            return errno::get_fault()~;
        }

        int r = socket::connect(sock, (SockAddr*)&adr, $sizeof(adr));
        if (r < 0)
        {
            return socket_fault()~;
        }
    }
    else
    {
        SockAddrIn adr = {};
        adr.sin_family = socket::AF_INET;
        adr.sin_port = in::htons(port);

        char[128] ip_buf;
        char* ip_cstr = str2cptr(ip, &ip_buf)!;

        int rc = in::inet_pton(socket::AF_INET, ip_cstr, &adr.sin_addr);
        if (rc == 0) return errno::E_INVALID_ARG~;
        if (rc < 0)
        {
            return errno::get_fault()~;
        }

        int r = socket::connect(sock, (SockAddr*)&adr, $sizeof(adr));
        if (r < 0)
        {
            return socket_fault()~;
        }
    }
}

fn TcpSocket? new_connect(String ip, ushort port)
{
    int version = detect_ip_version(ip);
    TcpSocket sock = new(version)!;
    defer catch (void)sock.close();

    sock.connect(ip, port)!;
    
    return sock;
}

fn usz? TcpSocket.send(sock, char[] buf)
{
    if (buf.len == 0) return 0;

    isz n = socket::send(sock, buf.ptr, buf.len, 0);
    if (n < 0) return socket_fault()~;

    return (usz)n;
}

// Blocking mode only.
fn usz? TcpSocket.write(sock, char[] buf)
{
    usz sent = 0;

    while (sent < buf.len)
    {
        usz n = sock.send(buf[sent:buf.len - sent])!;
        if (n == 0)
        {
            return errno::EOF~;
        }
        sent += n;
    }

    return sent;
}

fn usz? TcpSocket.recv(sock, char[] buf)
{
    if (buf.len == 0) return 0;

    isz n = socket::recv(sock, buf.ptr, buf.len, 0);
    if (n < 0) return socket_fault()~;

    return (usz)n;
}

macro usz? TcpSocket.read(sock, char[] buf)
{
    return sock.recv(buf);
}

// Blocking mode only.
// Do not use this on non-blocking sockets because partial line state is not preserved.
fn usz? TcpSocket.readline(sock, char[] line)
{
    if (line.len < 2)
    {
        if (line.len == 1) line[0] = '\0';
        return errno::EOF~;
    }

    usz n = 0;
    while (n < line.len - 1)
    {
        char c;
        isz r = socket::recv(sock, &c, 1, 0);
        if (r < 0)
        {
            return socket_fault()~;
        }
        if (r == 0) break;

        line[n] = c;
        n++;

        if (c == '\n') break;
    }

    if (n == 0)
    {
        return errno::EOF~;
    }

    line[n] = '\0';
    return n;
}

fn void? TcpSocket.set_non_blocking(sock) @maydiscard
{
    int flags = fcntl::fcntl(sock, fcntl::F_GETFL, 0);
    if (flags < 0) return errno::get_fault()~;

    int r = fcntl::fcntl(sock, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK);
    if (r < 0) return errno::get_fault()~;
}

fn void? TcpSocket.set_blocking(sock) @maydiscard
{
    int flags = fcntl::fcntl(sock, fcntl::F_GETFL, 0);
    if (flags < 0) return errno::get_fault()~;

    int r = fcntl::fcntl(sock, fcntl::F_SETFL, flags & ~fcntl::O_NONBLOCK);
    if (r < 0) return errno::get_fault()~;
}

fn void? TcpSocket.close(sock) @maydiscard
{
    int r = unistd::close(sock);
    if (r < 0) return errno::get_fault()~;
}

// eof