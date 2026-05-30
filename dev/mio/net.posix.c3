// net.posix.c3

// Net functions for aio

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(!env::WIN32);

import std::io;
import c::stdio;
import c::string;
import c::stdlib;
import c::netinet::in;
import c::arpa::inet;
import c::netdb;
import c::sys::socket;
import c::unistd;
import c::fcntl;
import c::errno;
import ext::debug;
import ext::mem;
import std::collections::map;
import std::collections::list;

const int DEFAULT_BACKLOG = 128;

faultdef BIND_ERROR, LISTEN_ERROR, CONNECT_ERROR, SENDTO_ERROR;

struct Context @local
{
    HashMap{String, IpList*} dns_cache;
}

tlocal Context* ctx @local = null;

fn void net_init()
{
    if (ctx != null) return;
    if (localmem == null) localmem = mem;
    
    ctx = localmem.alloc(Context)!!;

    ctx.dns_cache.init(localmem);
}

fn void net_deinit()
{
    if (ctx == null) return;
    
    ctx.dns_cache.@each(; key, iplist)
    {
        iplist.free();
    };
    ctx.dns_cache.free();
    localmem.free(ctx);
    ctx = null;
}

// caller needs to free result
fn String? peer_ip(Fd fd)
{
    if (fd_invalid(fd)) return INVALID_STATE~;

    socket::SockAddrStorage peer = {};
    socket::SockLen peer_len = socket::SockAddrStorage::size;

    int rc = socket::getpeername(
        fd,
        (socket::SockAddr*)&peer,
        &peer_len
    );
    if (rc != 0) return ADDR_ERROR~;

    String? ip = sockaddr_to_string((socket::SockAddr*)&peer);
    if (catch err = ip) return err~;

    return ip;
}

fn void socket_close(Fd fd)
{
    if (fd_invalid(fd)) return;

    fd_close(fd);
}

fn Fd? socket_new(int family, int type) @private
{
    Fd fd = socket::socket(family, type, 0);

    if (fd < 0) return errno::get_fault()~;

    if (!set_nonblocking(fd))
    {
        fd_close(fd);
        return IO_ERROR~;
    }

    return fd;
}

fn Fd? tcp_socket(int family = socket::AF_INET)
{
    return socket_new(family, socket::SOCK_STREAM);
}

fn Fd? udp_socket(int family = socket::AF_INET)
{
    return socket_new(family, socket::SOCK_DGRAM);
}

fn char*? str2cptr(String str, char[] buf) @inline @local
{
    if (buf.len == 0) return ADDR_ERROR~;
    if (str.len+1 > buf.len) return ADDR_ERROR~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn void? make_sockaddr(String ip, ushort port, socket::SockAddrStorage* addr, socket::SockLen* len) @maydiscard
{
    in::SockAddrIn a4 = {};
    in::SockAddrIn6 a6 = {};

    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;
    
    if (string::strchr(ip_str, ':') != null) 
    {
        if (in::inet_pton(socket::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return ADDR_ERROR~;
        }
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = in::htons(port);
        string::memcpy(addr, &a6, @sizeof(a6));
        *len = @sizeof(a6);
    }
    else 
    {
        a4.sin_family = (ushort)socket::AF_INET;
        a4.sin_port = in::htons(port);
        if (in::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1) 
        {
            return ADDR_ERROR~;
        }
        string::memcpy(addr, &a4, @sizeof(a4));
        *len = @sizeof(a4);
    }
}

fn void? socket_bind(Fd fd, String ip, ushort port)
{
    socket::SockAddrStorage addr;
    socket::SockLen len;
    make_sockaddr(ip, port, &addr, &len)!;

    int yes = 1;
    int rc = socket::setsockopt(
        fd,
        socket::SOL_SOCKET,
        socket::SO_REUSEADDR,
        &yes,
        CInt::size
    );
    if (rc < 0) return BIND_ERROR~;

    rc = socket::bind(
        fd,
        (socket::SockAddr*)&addr,
        len
    );
    if (rc < 0) return BIND_ERROR~;
}

fn void? tcp_listen(Fd fd, int backlog = DEFAULT_BACKLOG)
{
    int rc = socket::listen(fd, backlog);

    if (rc < 0) return LISTEN_ERROR~;
}

fn String? sockaddr_to_string(socket::SockAddr* addr)
{
    char[64] buf;
    char* p = null;

    if (addr.sa_family == socket::AF_INET)
    {
        in::SockAddrIn* a4 = (in::SockAddrIn*)addr;

        p = inet::inet_ntop(
            socket::AF_INET,
            &a4.sin_addr,
            &buf[0],
            (socket::SockLen)buf.len
        );
    }
    else if (addr.sa_family == socket::AF_INET6)
    {
        in::SockAddrIn6* a6 = (in::SockAddrIn6*)addr;

        p = inet::inet_ntop(
            socket::AF_INET6,
            &a6.sin6_addr,
            &buf[0],
            (socket::SockLen)buf.len
        );
    }
    else
    {
        return ADDR_ERROR~;
    }

    if (p == null) return ADDR_ERROR~;

    return ((String)p[0:string::strlen(p)]).copy(localmem);
}

fn Fd? tcp_accept(Fd server_fd)
{
    socket::SockAddrStorage addr;
    socket::SockLen len = socket::SockAddrStorage::size;

    Fd fd = socket::accept(
        server_fd,
        (socket::SockAddr*)&addr,
        &len
    );

    if (fd >= 0)
    {
        if (!set_nonblocking(fd))
        {
            fd_close(fd);
            return IO_ERROR~;
        }
            
        return fd;
    }

    if (!would_block()) return errno::get_fault()~;
    return errno::E_WOULD_BLOCK~;
}

fn bool in_progress() @local
{
    int e = errno::errno();
    return e == errno::EINPROGRESS || e == errno::EALREADY;
}

fn void? tcp_connect(Fd fd, String ip, ushort port)
{
    if (ctx.
    socket::SockAddrStorage addr;
    socket::SockLen len;
    make_sockaddr(ip, port, &addr, &len)!;

    int rc = socket::connect(
        fd,
        (socket::SockAddr*)&addr,
        len
    );
    if (rc == 0) return;
    
    if (!would_block() && !in_progress()) return errno::get_fault()~;
    return errno::E_WOULD_BLOCK~;
}

