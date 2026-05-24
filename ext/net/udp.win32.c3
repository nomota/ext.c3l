// udp.win32.c3 - Windows implementation with IPv4/IPv6 support

module ext::net::udp @if(env::WIN32);

import c::winsock2;
import c::ws2tcpip;
import c::errno;

import ext::net::wsa;

typedef UdpSocket = inline winsock2::Socket;

fn int detect_ip_version(String ip) @local
{
    foreach (c : ip)
    {
        if (c == ':') return winsock2::AF_INET6;
    }
    return winsock2::AF_INET;
}

fn bool would_block() @inline @local
{
    int err = winsock2::wsaGetLastError();
    return err == errno::EAGAIN
        || err == errno::EWOULDBLOCK
        || err == errno::EINPROGRESS
        || err == errno::EALREADY
        || err == errno::WSA_IO_PENDING;
}

fn fault socket_fault() @inline @local
{
    if (would_block()) return errno::E_WOULD_BLOCK;

    return errno::wsa_fault();
}

fn UdpSocket? new(int version = winsock2::AF_INET)
{
    UdpSocket sock = (UdpSocket)winsock2::socket(
        version,
        winsock2::SOCK_DGRAM,
        winsock2::IPPROTO_UDP
    );

    if (sock == winsock2::INVALID_SOCKET)
    {
        return socket_fault()~;
    }

    return sock;
}

// opt_ip == "*"  binds IPv4 INADDR_ANY.
// opt_ip == "::" binds IPv6 in6addr_any.
// Host names are not resolved; pass numeric IPv4/IPv6 addresses only.
fn void? UdpSocket.bind(sock, ushort port, String opt_ip = "*") @maydiscard
{
    int option = 1;
    int r = winsock2::setsockopt(
        sock,
        winsock2::SOL_SOCKET,
        winsock2::SO_REUSEADDR,
        (char*)&option,
        $sizeof(option)
    );

    if (r == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }

    int version = detect_ip_version(opt_ip);

    if (version == winsock2::AF_INET6)
    {
        winsock2::SockAddrIn6 adr = {};
        adr.sin6_family = winsock2::AF_INET6;

        if (opt_ip == "::")
        {
            adr.sin6_addr = {};
        }
        else
        {
            char[128] ip_buf;
            char* ip_cstr = str2cptr(opt_ip, &ip_buf);

            int rc = ws2tcpip::inet_pton(winsock2::AF_INET6, ip_cstr, &adr.sin6_addr);
            if (rc == 0) return errno::E_INVALID_ARG~;
            if (rc < 0)
            {
                return socket_fault()~;
            }
        }

        adr.sin6_port = winsock2::htons(port);

        if (winsock2::bind(sock, (winsock2::SockAddr*)&adr, $sizeof(adr)) == winsock2::SOCKET_ERROR)
        {
            return socket_fault()~;
        }
    }
    else
    {
        winsock2::SockAddrIn adr = {};
        adr.sin_family = winsock2::AF_INET;

        if (opt_ip == "*")
        {
            adr.sin_addr.s_addr = winsock2::htonl(winsock2::INADDR_ANY);
        }
        else
        {
            winsock2::InAddr addr;
            char[128] ip_buf;
            char* ip_cstr = str2cptr(opt_ip, &ip_buf);

            int rc = ws2tcpip::inet_pton(winsock2::AF_INET, ip_cstr, &addr);
            if (rc == 0) return errno::E_INVALID_ARG~;
            if (rc < 0)
            {
                return socket_fault()~;
            }

            adr.sin_addr = addr;
        }

        adr.sin_port = winsock2::htons(port);

        if (winsock2::bind(sock, (winsock2::SockAddr*)&adr, $sizeof(adr)) == winsock2::SOCKET_ERROR)
        {
            return socket_fault()~;
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

fn usz? UdpSocket.recvfrom(sock, char[] msgbuf, char[] ip = &__null__, ushort* port = null)
{
    if (msgbuf.len == 0) return 0;

    winsock2::SockAddrStorage adr = {};
    int size = $sizeof(adr);

    int len = winsock2::recvfrom(
        sock,
        msgbuf.ptr,
        (int)msgbuf.len,
        0,
        (winsock2::SockAddr*)&adr,
        &size
    );

    if (len == winsock2::SOCKET_ERROR)
    {
        if (wsa::would_block())
        {
            return errno::F_WOULDBLOCK~;
        }
        return socket_fault()~;
    }

    bool want_ip = ip != &__null__;
    bool want_port = port != null;

    if (want_ip && want_port)
    {
        if (adr.ss_family == winsock2::AF_INET6)
        {
            winsock2::SockAddrIn6* adr6 = (winsock2::SockAddrIn6*)&adr;

            if (ws2tcpip::inet_ntop(winsock2::AF_INET6, &adr6.sin6_addr, ip.ptr, (ulong)ip.len) == null)
            {
                return socket_fault()~;
            }
            *port = winsock2::ntohs(adr6.sin6_port);
        }
        else
        {
            winsock2::SockAddrIn* adr4 = (winsock2::SockAddrIn*)&adr;

            if (ws2tcpip::inet_ntop(winsock2::AF_INET, &adr4.sin_addr, ip.ptr, (ulong)ip.len) == null)
            {
                return socket_fault()~;
            }

            *port = winsock2::ntohs(adr4.sin_port);
        }
    }

    return (usz)len;
}

fn usz? UdpSocket.sendto(sock, char[] msgbuf, String ip, ushort port)
{
    if (msgbuf.len == 0) return 0;

    int version = detect_ip_version(ip);

    if (version == winsock2::AF_INET6)
    {
        winsock2::SockAddrIn6 adr = {};
        adr.sin6_family = winsock2::AF_INET6;
        adr.sin6_port = winsock2::htons(port);

        char[128] ip_buf;
        char* ip_cstr = str2cptr(ip, &ip_buf);

        int rc = ws2tcpip::inet_pton(winsock2::AF_INET6, ip_cstr, &adr.sin6_addr);
        if (rc == 0) return errno::E_INVALID_ARG~;
        if (rc < 0)
        {
            return socket_fault()~;
        }

        int len = winsock2::sendto(
            sock,
            msgbuf.ptr,
            (int)msgbuf.len,
            0,
            (winsock2::SockAddr*)&adr,
            $sizeof(adr)
        );

        if (len == winsock2::SOCKET_ERROR)
        {
            return socket_fault()~;
        }

        return (usz)len;
    }
    else
    {
        winsock2::SockAddrIn adr = {};
        adr.sin_family = winsock2::AF_INET;
        adr.sin_port = winsock2::htons(port);

        winsock2::InAddr addr;
        char[128] ip_buf;
        char* ip_cstr = str2cptr(ip, &ip_buf);

        int rc = ws2tcpip::inet_pton(winsock2::AF_INET, ip_cstr, &addr);
        if (rc == 0) return errno::E_INVALID_ARG~;
        if (rc < 0) return socket_fault()~;

        adr.sin_addr = addr;

        int len = winsock2::sendto(
            sock,
            msgbuf.ptr,
            (int)msgbuf.len,
            0,
            (winsock2::SockAddr*)&adr,
            $sizeof(adr)
        );

        if (len == winsock2::SOCKET_ERROR)
        {
            return socket_fault()~;
        }

        return (usz)len;
    }
}

fn usz? UdpSocket.send(sock, char[] buf)
{
    if (buf.len == 0) return 0;

    int n = winsock2::send(sock, buf.ptr, (int)buf.len, 0);
    if (n == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }

    return (usz)n;
}

fn usz? UdpSocket.recv(sock, char[] buf)
{
    if (buf.len == 0)
    {
        return 0;
    }

    int n = winsock2::recv(sock, buf.ptr, (int)buf.len, 0);
    if (n == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }

    return (usz)n;
}

fn void? UdpSocket.set_non_blocking(sock) @maydiscard
{
    uint mode = 1;
    int r = winsock2::ioctlsocket(sock, winsock2::FIONBIO, &mode);
    if (r == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }
}

fn void? UdpSocket.set_blocking(sock) @maydiscard
{
    uint mode = 0;
    int r = winsock2::ioctlsocket(sock, winsock2::FIONBIO, &mode);
    if (r == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }
}

fn void? UdpSocket.close(sock) @maydiscard
{
    int r = winsock2::closesocket(sock);
    if (r == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }
}

// eof