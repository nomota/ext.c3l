// tcp.win32.c3

// Windows implementation with IPv4/IPv6 support

// Nomota <hiongun@gmail.com>; MIT License

module ext::net::tcp @if(env::WIN32);

import c::winsock2;
import c::ws2tcpip;
import c::errno;

import ext::net::wsa;

typedef TcpSocket = inline winsock2::Socket;

fn int detect_ip_version(String ip) @inline @local
{
    foreach (c : ip)
    {
        if (c == ':') return winsock2::AF_INET6;
    }
    return winsock2::AF_INET;
}

fn char*? str2cptr(String str, char[] buf) @inline @local
{
    if (buf.len == 0 || str.len+1 > buf.len) return errno::E_INVALID_ARG~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn bool would_block() @inline @local
{
    int err = winsock2::wsaGetLastError();
    return err == errno::EAGAIN
        || err == errno::EWOULDBLOCK
        || err == errno::EINPROGRESS
        || err == errno::EALREADY;
}

fn fault socket_fault() @inline @local
{
    if (would_block()) return errno::E_WOULD_BLOCK;

    return errno::wsa_fault();
}

fn TcpSocket? new(int version = winsock2::AF_INET)
{
    TcpSocket sock = (TcpSocket)winsock2::socket(
        version,
        winsock2::SOCK_STREAM,
        winsock2::IPPROTO_TCP
    );
    if (sock == winsock2::INVALID_SOCKET)
    {
        return socket_fault()~;
    }
    return sock;
}

// ipv6 wildcard opt_ip == "::"
fn void? TcpSocket.listen(sock, ushort port, String opt_ip = "*", int backlog = 128) @maydiscard
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

    r = winsock2::listen(sock, backlog);
    if (r == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
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
    winsock2::SockAddrStorage adr = {};
    int size = $sizeof(adr);

    TcpSocket s = (TcpSocket)winsock2::accept(sock, (winsock2::SockAddr*)&adr, &size);
    if (s == winsock2::INVALID_SOCKET)
    {
        return socket_fault()~;
    }

    if (ip != &__null__ && port != null)
    {
        if (adr.ss_family == winsock2::AF_INET6)
        {
            winsock2::SockAddrIn6* adr6 = (winsock2::SockAddrIn6*)&adr;
            if (ws2tcpip::inet_ntop(winsock2::AF_INET6, &adr6.sin6_addr, ip.ptr, (ulong)ip.len) == null)
            {
                (void)s.close();
                return socket_fault()~;
            }
            *port = winsock2::ntohs(adr6.sin6_port);
        }
        else
        {
            winsock2::SockAddrIn* adr4 = (winsock2::SockAddrIn*)&adr;
            if (ws2tcpip::inet_ntop(winsock2::AF_INET, &adr4.sin_addr, ip.ptr, (ulong)ip.len) == null)
            {
                (void)s.close();
                return socket_fault()~;
            }
            *port = winsock2::ntohs(adr4.sin_port);
        }
    }

    return s;
}

fn void? TcpSocket.connect(sock, String ip, ushort port) @maydiscard
{
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
        if (rc < 0) return socket_fault()~;

        int r = winsock2::connect(sock, (winsock2::SockAddr*)&adr, $sizeof(adr));
        if (r == winsock2::SOCKET_ERROR)
        {
            return socket_fault()~;
        }
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

        int r = winsock2::connect(sock, (winsock2::SockAddr*)&adr, $sizeof(adr));
        if (r == winsock2::SOCKET_ERROR)
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
    if (buf.len) return 0;

    int n = winsock2::send(sock, buf.ptr, (int)buf.len, 0);
    if (n == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }
    
    return (usz)n;
}

// only for blocking mode
fn usz? TcpSocket.write(sock, char[] buf)
{
    usz sent = 0;

    while (sent < buf.len)
    {
        usz n = sock.send(buf[sent:buf.len - sent])!;
        if (n == 0) return errno::EOF~;
        
        sent += n;
    }
    return sent;
}

fn usz? TcpSocket.recv(sock, char[] buf)
{
    if (buf.len == 0) return 0;

    int n = winsock2::recv(sock, buf.ptr, (int)buf.len, 0);
    if (n == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }
    return (usz)n;
}

macro usz? TcpSocket.read(sock, char[] buf)
{
    return sock.recv(buf);
}

// blocking mode only
fn usz? TcpSocket.readline(sock, char[] line)
{
    if (line.len == 0) return errno::EOF~;

    if (line.len == 1)
    {
        line[0] = '\0';
        return errno::EOF~;
    }

    usz n = 0;
    while (n < line.len - 1)
    {
        char c;
        int r = winsock2::recv(sock, &c, 1, 0);
        if (r == winsock2::SOCKET_ERROR)
        {
            return socket_fault()~;
        }
        if (r == 0) break;

        line[n] = c;
        n++;

        if (c == '\n') break;
    }

    if (n == 0) return errno::EOF~;

    line[n] = '\0';
    return (usz)n;
}

fn void? TcpSocket.set_non_blocking(sock) @maydiscard
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


fn void? TcpSocket.close(sock) @maydiscard
{
    int r = winsock2::closesocket(sock);
    if (r == winsock2::SOCKET_ERROR)
    {
        return socket_fault()~;
    }
}

// eof