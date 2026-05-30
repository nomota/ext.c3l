// udp.posix.c3 - IPv4/IPv6 Support

module ext::net::udp @if(!env::WIN32);

import c::netinet::in;
import c::sys::socket;
import c::unistd;
import c::fcntl;
import c::errno;

typedef UdpSocket = inline int;

fn char*? str2cptr(String str, char[] buf) @inline @local
{
    if (buf.len == 0 || str.len+1 > buf.len) return errno::E_INVALID_ARG~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn int detect_ip_version(String ip)
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

fn UdpSocket? new(int version = socket::AF_INET)
{
    UdpSocket sock = (UdpSocket)socket::socket((int)version, socket::SOCK_DGRAM, 0);
    if (sock == -1)
    {
        return errno::get_fault()~;
    }
    return sock;
}

// opt_ip == "*"  binds IPv4 INADDR_ANY.
// opt_ip == "::" binds IPv6 in6addr_any.
// Host names are not resolved; pass numeric IPv4/IPv6 addresses only.
fn void? UdpSocket.bind(sock, ushort port, String opt_ip = "*") @maydiscard
{
    int option = 1;

    int r = socket::setsockopt(
        sock,
        socket::SOL_SOCKET,
        socket::SO_REUSEADDR,
        (void*)&option,
        @sizeof(option)
    );
    if (r < 0) return errno::get_fault()~;

    r = socket::setsockopt(
        sock,
        socket::SOL_SOCKET,
        socket::SO_REUSEPORT,
        (void*)&option,
        @sizeof(option)
    );
    if (r < 0) return errno::get_fault()~;

    int version = detect_ip_version(opt_ip);

    if (version == socket::AF_INET6)
    {
        in::SockAddrIn6 adr = {};
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

        if (socket::bind(sock, (socket::SockAddr*)&adr, @sizeof(adr)) < 0)
        {
            return errno::get_fault()~;
        }
    }
    else
    {
        in::SockAddrIn adr = {};
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

        if (socket::bind(sock, (socket::SockAddr*)&adr, @sizeof(adr)) < 0)
        {
            return errno::get_fault()~;
        }
    }
}

fn UdpSocket? new_bind(ushort port, String ip = "*")
{
    int version = detect_ip_version(ip);
    UdpSocket sock = new(version)!;
    defer catch (void)sock.close();

    sock.bind(port, ip)!;
    
    return sock;
}

char[1] __null__;

fn sz? UdpSocket.recvfrom(sock, char[] msgbuf, char[] ip = &__null__, ushort* port = null)
{
    if (msgbuf.len == 0) return 0;

    socket::SockAddrStorage adr = {};
    socket::SockLen size = @sizeof(adr);

    sz len = socket::recvfrom(
        sock,
        msgbuf.ptr,
        msgbuf.len,
        0,
        (socket::SockAddr*)&adr,
        &size
    );

    if (len < 0) return socket_fault()~;

    bool want_ip = ip != &__null__;
    bool want_port = port != null;

    if (want_ip && want_port)
    {
        if (adr.ss_family == socket::AF_INET6)
        {
            in::SockAddrIn6* adr6 = (in::SockAddrIn6*)&adr;

            if (in::inet_ntop(socket::AF_INET6, &adr6.sin6_addr, ip.ptr, ip.len) == null)
            {
                return errno::get_fault()~;
            }

            *port = in::ntohs(adr6.sin6_port);
        }
        else
        {
            in::SockAddrIn* adr4 = (in::SockAddrIn*)&adr;

            if (in::inet_ntop(socket::AF_INET, &adr4.sin_addr, ip.ptr, ip.len) == null)
            {
                return errno::get_fault()~;
            }

            *port = in::ntohs(adr4.sin_port);
        }
    }

    return (sz)len;
}

fn sz? UdpSocket.sendto(sock, char[] msgbuf, String ip, ushort port)
{
    if (msgbuf.len == 0) return 0;

    int version = detect_ip_version(ip);

    if (version == socket::AF_INET6)
    {
        in::SockAddrIn6 adr = {};
        adr.sin6_family = socket::AF_INET6;
        adr.sin6_port = in::htons(port);

        char[128] ip_buf;
        char* ip_cstr = str2cptr(ip, &ip_buf)!;

        int rc = in::inet_pton(socket::AF_INET6, ip_cstr, &adr.sin6_addr);
        if (rc == 0) return errno::E_INVALID_ARG~;
        if (rc < 0) return errno::get_fault()~;

        sz len = socket::sendto(
            sock,
            msgbuf.ptr,
            msgbuf.len,
            0,
            (socket::SockAddr*)&adr,
            @sizeof(adr)
        );

        if (len < 0) return socket_fault()~;

        return (sz)len;
    }
    else
    {
        in::SockAddrIn adr = {};
        adr.sin_family = socket::AF_INET;
        adr.sin_port = in::htons(port);

        char[128] ip_buf;
        char* ip_cstr = str2cptr(ip, &ip_buf)!;

        int rc = in::inet_pton(socket::AF_INET, ip_cstr, &adr.sin_addr);
        if (rc == 0) return errno::E_INVALID_ARG~;
        if (rc < 0) return errno::get_fault()~;

        sz len = socket::sendto(
            sock,
            msgbuf.ptr,
            msgbuf.len,
            0,
            (socket::SockAddr*)&adr,
            @sizeof(adr)
        );

        if (len < 0) return socket_fault()~;

        return (sz)len;
    }
}

fn sz? UdpSocket.send(sock, char[] buf)
{
    if (buf.len == 0) return 0;

    sz n = socket::send(sock, buf.ptr, buf.len, 0);
    if (n < 0) return socket_fault()~;

    return (sz)n;
}

fn sz? UdpSocket.recv(sock, char[] buf)
{
    if (buf.len == 0) return 0;

    sz n = socket::recv(sock, buf.ptr, buf.len, 0);
    if (n < 0) return socket_fault()~;

    return (sz)n;
}

fn void? UdpSocket.set_non_blocking(sock) @maydiscard
{
    int flags = fcntl::fcntl(sock, fcntl::F_GETFL, 0);
    if (flags < 0) return errno::get_fault()~;

    int r = fcntl::fcntl(sock, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK);
    if (r < 0) return errno::get_fault()~;
}

fn void? UdpSocket.set_blocking(sock) @maydiscard
{
    int flags = fcntl::fcntl(sock, fcntl::F_GETFL, 0);
    if (flags < 0) return errno::get_fault()~;

    int r = fcntl::fcntl(sock, fcntl::F_SETFL, flags & ~fcntl::O_NONBLOCK);
    if (r < 0) return errno::get_fault()~;
}

fn void? UdpSocket.close(sock) @maydiscard
{
    int r = unistd::close(sock);
    if (r < 0) return errno::get_fault()~;
}

// eof