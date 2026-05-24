// net.posix.c3

// Net functions for aio

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::net @if(!env::WIN32);

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
import ext::fiber;
import ext::aio;
import ext::aio::io;

const int DEFAULT_BACKLOG = 128;

struct Context @local
{
    HashMap{String, IpList*} dns_cache;
}

tlocal Context* ctx @local = null;

fn void init()
{
    if (ctx != null) return;
    aio::init();
    ctx = aio::localmem.alloc(Context)!!;

    ctx.dns_cache.init(aio::localmem);
}

fn void deinit()
{
    if (ctx == null) return;
    
    ctx.dns_cache.@each(; key, iplist)
    {
        iplist.free();
    };
    ctx.dns_cache.free();
    aio::localmem.free(ctx);
    ctx = null;
}

// caller needs to free result
fn String? peer_ip(Fd fd)
{
    if (io::fd_invalid(fd)) return aio::INVALID_STATE~;

    socket::SockAddrStorage peer = {};
    socket::SockLen peer_len = socket::SockAddrStorage.sizeof;

    int rc = socket::getpeername(
        fd,
        (socket::SockAddr*)&peer,
        &peer_len
    );
    if (rc != 0) return aio::ADDR_ERROR~;

    String? ip = sockaddr_to_string((socket::SockAddr*)&peer);
    if (catch err = ip) return err~;

    return ip;
}

fn void socket_close(Fd fd)
{
    if (io::fd_invalid(fd)) return;

    io::fd_close(fd);
}

fn Fd? socket_new(int family, int type) @private
{
    Fd fd = socket::socket(family, type, 0);

    if (fd < 0) return errno::get_fault()~;

    if (!io::set_nonblocking(fd))
    {
        io::fd_close(fd);
        return aio::IO_ERROR~;
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
    if (buf.len == 0) return aio::ADDR_ERROR~;
    if (str.len+1 > buf.len) return aio::ADDR_ERROR~;

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
            return aio::ADDR_ERROR~;
        }
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = in::htons(port);
        string::memcpy(addr, &a6, $sizeof(a6));
        *len = $sizeof(a6);
    }
    else 
    {
        a4.sin_family = (ushort)socket::AF_INET;
        a4.sin_port = in::htons(port);
        if (in::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1) 
        {
            return aio::ADDR_ERROR~;
        }
        string::memcpy(addr, &a4, $sizeof(a4));
        *len = $sizeof(a4);
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
        CInt.sizeof
    );
    if (rc < 0) return aio::BIND_ERROR~;

    rc = socket::bind(
        fd,
        (socket::SockAddr*)&addr,
        len
    );
    if (rc < 0) return aio::BIND_ERROR~;
}

fn void? tcp_listen(Fd fd, int backlog = DEFAULT_BACKLOG)
{
    int rc = socket::listen(fd, backlog);

    if (rc < 0) return aio::LISTEN_ERROR~;
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
        return aio::ADDR_ERROR~;
    }

    if (p == null) return aio::ADDR_ERROR~;

    return ((String)p[0:string::strlen(p)]).copy(aio::localmem);
}

fn Fd? tcp_accept(Fd server_fd)
{
    while (true)
    {
        socket::SockAddrStorage addr;
        socket::SockLen len = socket::SockAddrStorage.sizeof;

        Fd fd = socket::accept(
            server_fd,
            (socket::SockAddr*)&addr,
            &len
        );

        if (fd >= 0)
        {
            if (!io::set_nonblocking(fd))
            {
                io::fd_close(fd);
                return aio::IO_ERROR~;
            }
            
            return fd;
        }

        int err = errno::errno();
        if (err == errno::EINTR) continue;
        if (err == errno::EBADF || err == errno::EINVAL) return aio::CLOSED~;

        if (!io::would_block()) return aio::ACCEPT_ERROR~;
    
        io::wait_readable(server_fd)!;
    }
}

fn void? tcp_connect(Fd fd, String ip, ushort port)
{
    socket::SockAddrStorage addr;
    socket::SockLen len;
    make_sockaddr(ip, port, &addr, &len)!;

    int rc = socket::connect(
        fd,
        (socket::SockAddr*)&addr,
        len
    );
    if (rc == 0) return;
    
    int err = errno::errno();
    if (err == errno::EISCONN) return;

    if (err != errno::EINPROGRESS &&
        err != errno::EALREADY &&
        err != errno::EWOULDBLOCK)
    {
        return aio::CONNECT_ERROR~;
    }
    
    io::wait_writable(fd)!;

    int so_error = 0;
    socket::SockLen opt_len = CInt.sizeof;
    rc = socket::getsockopt(
        fd,
        socket::SOL_SOCKET,
        socket::SO_ERROR,
        &so_error,
        &opt_len
    );

    if (rc < 0) return aio::CONNECT_ERROR~;

    if (so_error != 0)
    {
        warn("connect failed so_error=%d", so_error);
        return aio::CONNECT_ERROR~;
    }
}

fn int? ip_family(String ip) @private
{
    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;

    if (string::strchr(ip_str, ':') != null)
    {
        return socket::AF_INET6;
    }

    return socket::AF_INET;
}

fn Fd? udp_bind_ip(String ip, ushort port)
{
    int family = ip_family(ip)!;
    Fd fd = udp_socket(family)!;    
    defer (catch err) { socket_close(fd); }
    
    socket_bind(fd, ip, port)!;

    return fd;
}

fn Fd? udp_sendto_ip(String ip, ushort port, char[] data, Fd fd = fd_null())
{
    bool new_fd = false;

    if (fd == io::fd_null())
    {
        int family = ip_family(ip)!;
        fd = udp_socket(family)!;
        new_fd = true;
    }

    defer (catch err) { if (new_fd) socket_close(fd); }

    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;

    io::async_sendto(fd, data, ip_str, port)!;

    return fd;
}

fn Fd? tcp_listen_ip(String ip, ushort port, int backlog = DEFAULT_BACKLOG)
{
    int family = ip_family(ip)!;
    Fd fd = tcp_socket(family)!;
    defer (catch err) { socket_close(fd); }
    
    socket_bind(fd, ip, port)!;

    tcp_listen(fd, backlog)!;

    return fd;
}

fn Fd? tcp_connect_ip(String ip, ushort port)
{
    int family = ip_family(ip)!;
    Fd fd = tcp_socket(family)!;
    defer (catch err) { socket_close(fd); }
    
    tcp_connect(fd, ip, port)!;

    return fd;
}

faultdef DNS_LOOKUP_ERROR;

struct IpList @private
{
    ulong expire_us; // micro seconds
    List{String} ips;
}

fn void IpList.free(&self)
{
    foreach (ip: self.ips)
    {
        aio::localmem.free(ip);
    }
    self.ips.free();
    aio::localmem.free(self);
}

fn List{String}? dns_resolve(String host, ushort port)
{
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    netdb::AddrInfo hints = {};
    hints.ai_family = netdb::AF_UNSPEC;
    hints.ai_socktype = socket::SOCK_STREAM;

    char[256] host_buf;
    char* host_cstr = str2cptr(host, host_buf[..])!;

    netdb::AddrInfo* res = null;
    if (netdb::getaddrinfo(host_cstr, &port_str[0], &hints, &res) != 0) return DNS_LOOKUP_ERROR~;
    defer netdb::freeaddrinfo(res);

    List{String} ips;
    ips.init(aio::localmem);
    
    netdb::AddrInfo* rp = res;
    while (rp != null) {
        socket::SockAddr* addr = rp.ai_addr;
        String ip = sockaddr_to_string(addr)!;
        ips.push(ip);
        rp = rp.ai_next;
    }
    
    return ips;
}

const ulong DNS_CACHE_TTL_US @private = 60_000_000; // 60 sec

faultdef NOT_FOUND, EXPIRED;

fn IpList*? cache_lookup(String key)
{
    if (! ctx.dns_cache.has_key(key)) return NOT_FOUND~;
    IpList* item = ctx.dns_cache[key]!;
    if (item.expire_us < aio::clock_now())
    {
        ctx.dns_cache.remove(key);
        item.free();
        return EXPIRED~;
    }
    return item;
}

fn void? cache_store(String key, List{String} ips) @maydiscard
{
    IpList*? old = cache_lookup(key);
    if (try old)
    {
        ctx.dns_cache.remove(key);
        old.free();
    }

    IpList* item = aio::localmem.alloc(IpList)!;
    *item = {
        .expire_us = aio::clock_now() + DNS_CACHE_TTL_US,
        .ips = ips,
    };

    ctx.dns_cache[key] = item;
}

faultdef HOST_TOO_LONG;

fn List{String}? host_lookup(String host, ushort port)
{
    char[128] buf;
    if (host.len > 120) return HOST_TOO_LONG~;
    stdio::snprintf(&buf[0], buf.len, "%.*s:%d", (int)host.len, host.ptr, (int)port);
    String key = (String)buf[0:string::strlen(&buf[0])];
    
    IpList*? item = cache_lookup(key);
    if (try item) return item.ips;
    
    List{String} ips2 = dns_resolve(host, port)!;
    cache_store(key, ips2);

    return ips2;
}

fn Fd? udp_bind_host(String host, ushort port)
{
    List{String} ips = host_lookup(host, port)!;
    foreach (ip: ips)
    {
        Fd fd = udp_bind_ip(ip, port)!;
        return fd;
    }

    return aio::BIND_ERROR~;
}

fn Fd? udp_sendto_host(String host, ushort port, char[] data, Fd fd = fd_null())
{
    List{String} ips = host_lookup(host, port)!;
    foreach (ip: ips)
    {
        Fd fd2 = udp_sendto_ip(ip, port, data, fd)!;
        return fd2;
    }

    return aio::SENDTO_ERROR~;
}

fn Fd? tcp_listen_host(String host, ushort port, int backlog = DEFAULT_BACKLOG)
{
    List{String} ips = host_lookup(host, port)!;
    foreach (ip: ips)
    {
        Fd fd = tcp_listen_ip(ip, port, backlog)!;
        return fd;
    }

    return aio::LISTEN_ERROR~;
}

fn Fd? tcp_connect_host(String host, ushort port)
{
    List{String} ips = host_lookup(host, port)!;
    foreach (ip: ips)
    {
        Fd fd = tcp_connect_ip(ip, port)!;
        return fd;
    }

    return aio::CONNECT_ERROR~;
}


// eof