// net.c3

// Net functions for aio, built on ext::mio
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::net;

import std::io;
import c::stdio;
import c::string;
import c::stdlib;
import c::errno;
import std::collections::map;
import std::collections::list;
import ext::debug;
import ext::mem;
import ext::aio;
import ext::aio::io;
import ext::mio;

import c::winsock2;
import c::ws2tcpip;

import c::netdb;
import c::sys::socket;
import c::netinet::in;
import c::arpa::inet;

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
    io::init();

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

fn void socket_close(mio::Fd fd)
{
    if (io::fd_invalid(fd)) return;

    io::fd_close(fd);
}

fn mio::Fd? tcp_socket(int family = mio::socket_family_from_ip("127.0.0.1"))
{
    return mio::tcp_socket_fd(family)!;
}

fn mio::Fd? udp_socket(int family = mio::socket_family_from_ip("127.0.0.1"))
{
    return mio::udp_socket_fd(family)!;
}

fn int? ip_family(String ip)
{
    return mio::socket_family_from_ip(ip);
}

fn char*? str2cptr(String str, char[] buf) @inline @local
{
    if (buf.len == 0) return aio::ADDR_ERROR~;
    if (str.len + 1 > buf.len) return aio::ADDR_ERROR~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

// caller should free
fn String? addr_buf_to_string(char[] buf)
{
    sz len = (sz)string::strlen(&buf[0]);
    return ((String)buf[0:len]).copy(aio::localmem);
}

// caller should free
fn String? peer_ip(mio::Fd fd)
{
    if (io::fd_invalid(fd)) return aio::INVALID_STATE~;

    char[128] ip_buf;
    ushort port = 0;

    mio::peer_addr_fd(fd, ip_buf[..], &port)!;

    return addr_buf_to_string(ip_buf[..])!;
}

fn void? socket_bind(mio::Fd fd, String ip, ushort port)
{
    mio::set_reuseaddr_fd(fd)!;
    mio::socket_bind_fd(fd, ip, port)!;
}

fn void? tcp_listen(mio::Fd fd, int backlog = DEFAULT_BACKLOG)
{
    mio::tcp_listen_fd(fd, backlog)!;
}

fn mio::Fd? tcp_accept(mio::Fd server_fd)
{
    while (true)
    {
        mio::Fd? fd = mio::tcp_accept_fd(server_fd);

        if (catch err = fd)
        {
            if (is_would_block(err))
            {
                io::wait_readable(server_fd)!;
                continue;
            }

            if (is_closed_error(err))
            {
                return aio::CLOSED~;
            }

            return aio::ACCEPT_ERROR~;
        }

        return fd;
    }
}

fn void? tcp_connect(mio::Fd fd, String ip, ushort port)
{
    if (catch err = mio::tcp_connect_fd(fd, ip, port))
    {
        if (!is_connect_pending(err))
        {
            return aio::CONNECT_ERROR~;
        }
    }

    io::wait_writable(fd)!;

    int so_error = mio::take_error_fd(fd);
    if (so_error != 0)
    {
        //warn("connect failed so_error=%d", so_error);
        return aio::CONNECT_ERROR~;
    }
}

fn bool is_would_block(fault err)
{
    return
        err == errno::E_AGAIN ||
        err == errno::E_WOULD_BLOCK ||
        err == errno::E_IN_PROGRESS ||
        err == errno::E_ALREADY;
}

fn bool is_connect_pending(fault err)
{
    return
        err == errno::E_IN_PROGRESS ||
        err == errno::E_AGAIN ||
        err == errno::E_ALREADY ||
        err == errno::E_WOULD_BLOCK ||
        err == errno::E_IS_CONNECTED;
}

fn bool is_closed_error(fault err)
{
    return
        err == errno::E_BAD_FILE_DESC ||
        err == errno::E_INVALID ||
        err == aio::CLOSED;
}

fn mio::Fd? udp_bind_ip(String ip, ushort port)
{
    int family = ip_family(ip)!;

    mio::Fd fd = udp_socket(family)!;
    defer (catch err) { socket_close(fd); }

    socket_bind(fd, ip, port)!;

    return fd;
}

fn mio::Fd? udp_sendto_ip(String ip, ushort port, char[] data, mio::Fd fd = io::fd_null())
{
    bool new_fd = false;

    if (fd == io::fd_null())
    {
        int family = ip_family(ip)!;

        fd = udp_socket(family)!;
        new_fd = true;
    }

    defer (catch err)
    {
        if (new_fd) socket_close(fd);
    }
    
    io::async_sendto(fd, data, ip, port)!;

    return fd;
}

fn mio::Fd? tcp_listen_ip(String ip, ushort port, int backlog = DEFAULT_BACKLOG)
{
    int family = ip_family(ip)!;

    mio::Fd fd = tcp_socket(family)!;
    defer (catch err) { socket_close(fd); }

    socket_bind(fd, ip, port)!;
    tcp_listen(fd, backlog)!;

    return fd;
}

fn mio::Fd? tcp_connect_ip(String ip, ushort port)
{
    int family = ip_family(ip)!;

    mio::Fd fd = tcp_socket(family)!;
    defer (catch err) { socket_close(fd); }

    tcp_connect(fd, ip, port)!;

    return fd;
}

faultdef DNS_LOOKUP_ERROR;

struct IpList @private
{
    ulong expire_us;
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

fn String? sockaddr_to_string_posix(void* raw_addr) @if(env::POSIX)
{
    socket::SockAddr* addr = (socket::SockAddr*)raw_addr;

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

fn String? sockaddr_to_string_win32(void* raw_addr) @if(env::WIN32)
{
    winsock2::SockAddr* addr = (winsock2::SockAddr*)raw_addr;

    char[64] buf;
    char* p = null;

    if (addr.sa_family == winsock2::AF_INET)
    {
        winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)addr;

        p = winsock2::inet_ntop(
            winsock2::AF_INET,
            &a4.sin_addr,
            &buf[0],
            (winsock2::SockLen)buf.len
        );
    }
    else if (addr.sa_family == winsock2::AF_INET6)
    {
        winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)addr;

        p = winsock2::inet_ntop(
            winsock2::AF_INET6,
            &a6.sin6_addr,
            &buf[0],
            (winsock2::SockLen)buf.len
        );
    }
    else
    {
        return aio::ADDR_ERROR~;
    }

    if (p == null) return aio::ADDR_ERROR~;

    return ((String)p[0:string::strlen(p)]).copy(aio::localmem);
}

faultdef NONE @local;

struct Arg @local
{
    fault error;
    String host;
    ushort port;
    List{String} ips;
}

fn void* dns_resolve_blocking(void* v_arg) @local @if(env::POSIX)
{
    Arg* arg = (Arg*)v_arg;
    
    String host = arg.host;
    ushort port = arg.port;
    
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    netdb::AddrInfo hints = {};
    hints.ai_family = netdb::AF_UNSPEC;
    hints.ai_socktype = socket::SOCK_STREAM;

    char[256] host_buf;
    char*? host_cstr = str2cptr(host, host_buf[..]);
    if (catch err = host_cstr)
    {
        arg.error = err;
        return v_arg;
    }
    netdb::AddrInfo* res = null;

    if (netdb::getaddrinfo(host_cstr, &port_str[0], &hints, &res) != 0)
    {
        arg.error = DNS_LOOKUP_ERROR;
        return v_arg;
    }

    defer netdb::freeaddrinfo(res);

    arg.ips.init(aio::localmem);

    netdb::AddrInfo* rp = res;

    while (rp != null)
    {
        String? ip = sockaddr_to_string_posix(rp.ai_addr);
        if (catch err = ip)
        {
            arg.error = err;
            return v_arg;
        }

        arg.ips.push(ip);

        rp = rp.ai_next;
    }

    return v_arg;
}

fn void* dns_resolve_blocking(void* v_arg) @local @if(env::WIN32)
{
    Arg* arg = (Arg*)v_arg;
    
    String host = arg.host;
    ushort port = arg.port;

    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    ws2tcpip::AddrInfo hints = {};
    hints.ai_family = winsock2::AF_UNSPEC;
    hints.ai_socktype = winsock2::SOCK_STREAM;
    hints.ai_protocol = winsock2::IPPROTO_TCP;

    char[256] host_buf;
    char*? host_cstr = str2cptr(host, host_buf[..]);
    if (catch err = host_cstr)
    {
        arg.error = err;
        return v_arg;
    }

    ws2tcpip::AddrInfo* res = null;

    int rc = ws2tcpip::getaddrinfo(
        host_cstr,
        &port_str[0],
        &hints,
        &res
    );

    if (rc != 0)
    {
        arg.error = DNS_LOOKUP_ERROR;
        return v_arg;
    }

    defer ws2tcpip::freeaddrinfo(res);

    arg.ips.init(aio::localmem);

    ws2tcpip::AddrInfo* rp = res;

    while (rp != null)
    {
        String? ip = sockaddr_to_string_win32(rp.ai_addr);
        if (catch err = ip)
        {
            arg.error = err;
            return v_arg;
        }

        arg.ips.push(ip);

        rp = rp.ai_next;
    }

    return v_arg;
}

fn List{String}? dns_resolve(String host, ushort port) @local
{
    Arg arg = {
        .error = NONE,
        .host = host,
        .port = port,
    };
    
    Arg*? a = aio::run_in_executor(&dns_resolve_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.ips;
}

const ulong DNS_CACHE_TTL_US @private = 60_000_000;

faultdef NOT_FOUND, EXPIRED;

fn IpList*? cache_lookup(String key)
{
    if (!ctx.dns_cache.has_key(key)) return NOT_FOUND~;

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

    stdio::snprintf(
        &buf[0],
        buf.len,
        "%.*s:%d",
        (int)host.len,
        host.ptr,
        (int)port
    );

    String key = (String)buf[0:string::strlen(&buf[0])];

    IpList*? item = cache_lookup(key);
    if (try item) return item.ips;

    List{String} ips = dns_resolve(host, port)!;

    cache_store(key, ips)!;

    return ips;
}

fn mio::Fd? udp_bind_host(String host, ushort port)
{
    List{String} ips = host_lookup(host, port)!;

    foreach (ip: ips)
    {
        mio::Fd fd = udp_bind_ip(ip, port)!;
        return fd;
    }

    return aio::BIND_ERROR~;
}

fn mio::Fd? udp_sendto_host(String host, ushort port, char[] data, mio::Fd fd = io::fd_null())
{
    List{String} ips = host_lookup(host, port)!;

    foreach (ip: ips)
    {
        mio::Fd fd2 = udp_sendto_ip(ip, port, data, fd)!;
        return fd2;
    }

    return aio::SENDTO_ERROR~;
}

fn mio::Fd? tcp_listen_host(String host, ushort port, int backlog = DEFAULT_BACKLOG)
{
    List{String} ips = host_lookup(host, port)!;

    foreach (ip: ips)
    {
        mio::Fd fd = tcp_listen_ip(ip, port, backlog)!;
        return fd;
    }

    return aio::LISTEN_ERROR~;
}

fn mio::Fd? tcp_connect_host(String host, ushort port)
{
    List{String} ips = host_lookup(host, port)!;

    foreach (ip: ips)
    {
        mio::Fd fd = tcp_connect_ip(ip, port)!;
        return fd;
    }

    return aio::CONNECT_ERROR~;
}

// eof