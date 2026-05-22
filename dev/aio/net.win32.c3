// net.win32.c3

// Net functions for aio

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::net @if(env::WIN32) @link("ws2_32");

import std::io;
import c::stdio;
import c::stdlib;
import c::string;
import c::errno;
import c::winbase;
import c::winsock2;
import c::ws2tcpip;
import c::guiddef;
import c::mswsock;
import ext::debug;
import ext::mem;
import std::collections::map;
import std::collections::list;
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

    winsock2::SockAddrStorage peer = {};
    int peer_len = winsock2::SockAddrStorage.sizeof;

    int rc = winsock2::getpeername(
        (winsock2::Socket)fd,
        (winsock2::SockAddr*)&peer,
        &peer_len
    );
    if (rc != 0) return aio::ADDR_ERROR~;

    String? ip = sockaddr_to_string((winsock2::SockAddr*)&peer);
    if (catch err = ip) return err~;

    return ip;
}

fn void socket_close(Fd fd)
{
    if (io::fd_invalid(fd)) return;

    io::fd_close(fd);
}

fn void disable_conn_reset(winsock2::Socket sock) @private
{
    int off = 0;
    winbase::DWord dummy;
    winsock2::wsaIoctl(
        sock, winsock2::SIO_UDP_CONNRESET,
        &off, $sizeof(off),
        null, 0, &dummy, null, null
    );
}

fn Fd? socket_new(int family, int type)
{
    winsock2::Socket sock = winsock2::wsaSocketW(family, type, 0,
            null, 0, winsock2::WSA_FLAG_OVERLAPPED
        );
    if (sock == winsock2::INVALID_SOCKET)
    {
        return errno::get_fault()~;
    }

    if (!io::iocp_associate((winbase::Handle)sock))
    {
        winsock2::closesocket(sock);
        return aio::SOCKET_ERROR~;
    }
    if (type == winsock2::SOCK_DGRAM)
    {
        disable_conn_reset(sock);
    }
    
    io::fd_set_socket((winbase::Handle)sock, true);

    return (winbase::Handle)sock;
}

fn Fd? tcp_socket(int family = winsock2::AF_INET)
{
    return socket_new(family, winsock2::SOCK_STREAM);
}

fn Fd? udp_socket(int family = winsock2::AF_INET)
{
    return socket_new(family, winsock2::SOCK_DGRAM);
}

fn char*? str2cptr(String str, char[] buf) @inline @private
{
    if (buf.len == 0) return aio::ADDR_ERROR~;
    if (str.len+1 > buf.len) return aio::ADDR_ERROR~;

    buf[0:str.len] = str[0:str.len];
    buf[str.len] = 0;

    return &buf[0];
}

fn void? make_sockaddr(String ip, ushort port, winsock2::SockAddrStorage* addr, winsock2::SockLen* len) @maydiscard
{
    winsock2::SockAddrIn a4 = {};
    winsock2::SockAddrIn6 a6 = {};

    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;
    
    if (string::strchr(ip_str, ':') != null) 
    {
        if (winsock2::inet_pton(winsock2::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return aio::ADDR_ERROR~;
        }
        a6.sin6_family = (ushort)winsock2::AF_INET6;
        a6.sin6_port = winsock2::htons(port);
        string::memcpy(addr, &a6, $sizeof(a6));
        *len = $sizeof(a6);
    }
    else 
    {
        a4.sin_family = (ushort)winsock2::AF_INET;
        a4.sin_port = winsock2::htons(port);
        if (winsock2::inet_pton(winsock2::AF_INET, ip_str, &a4.sin_addr) != 1) 
        {
            return aio::ADDR_ERROR~;
        }
        string::memcpy(addr, &a4, $sizeof(a4));
        *len = $sizeof(a4);
    }
}

fn void? socket_bind(Fd fd, String ip, ushort port)
{
    winsock2::SockAddrStorage addr;
    winsock2::SockLen len;
    make_sockaddr(ip, port, &addr, &len)!;

    int yes = 1;
    int rc = winsock2::setsockopt(
        (winsock2::Socket)fd,
        winsock2::SOL_SOCKET,
        winsock2::SO_EXCLUSIVEADDRUSE,
        (char*)&yes,
        $sizeof(yes)
    );
    if (rc != 0) return aio::BIND_ERROR~;

    // bind to address
    int b = winsock2::bind((winsock2::Socket) fd, (winsock2::SockAddr*)&addr, len);
    if (b != 0) {
        return aio::BIND_ERROR~;
    }
}

alias AcceptExFn = fn winbase::Bool(
    winsock2::Socket sListenSocket,
    winsock2::Socket sAcceptSocket,
    void* lpOutputBuffer,
    winbase::DWord dwReceiveDataLength,
    winbase::DWord dwLocalAddressLength,
    winbase::DWord dwRemoteAddressLength,
    winbase::DWord* lpdwBytesReceived,
    winbase::Overlapped* lpOverlapped
) @callconv("stdcall");

AcceptExFn acceptEx;

fn void load_acceptex(winsock2::Socket s) @private
{
    if (acceptEx != null) return;
    guiddef::Guid guid = mswsock::WSAID_ACCEPTEX;
    winbase::DWord bytes = 0;
    int rr = winsock2::wsaIoctl(s, winsock2::SIO_GET_EXTENSION_FUNCTION_POINTER, &guid, $sizeof(guid), &acceptEx, $sizeof(acceptEx), &bytes, null, null);
    if (rr != 0) acceptEx = null;
}

fn void? tcp_listen(Fd fd, int backlog = DEFAULT_BACKLOG)
{
    int rc = winsock2::listen((winsock2::Socket) fd, backlog);
    if (rc < 0) return aio::LISTEN_ERROR~;

    load_acceptex((winsock2::Socket) fd);
    
    if (acceptEx == null) {
        warn("load_acceptex() failed");
        return aio::LISTEN_ERROR~;
    }
}

fn String? sockaddr_to_string(winsock2::SockAddr* addr)
{
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

    String ip = ((String)p[0:string::strlen(p)]).copy(aio::localmem);

    return ip;
}

fn int? socket_family(Fd fd) @private
{
    winsock2::SockAddrStorage addr = {};
    int len = winsock2::SockAddrStorage.sizeof;

    if (winsock2::getsockname((winsock2::Socket)fd, (winsock2::SockAddr*)&addr, &len) != 0)
    {
        return aio::ADDR_ERROR~;
    }

    return ((winsock2::SockAddr*)&addr).sa_family;
}

fn void close_accept_socket(winsock2::Socket s) @private
{
    if (s != winsock2::INVALID_SOCKET)
    {
        socket_close((winbase::Handle)s);
    }
}

fn Fd? tcp_accept(Fd listen_fd)
{
    // AcceptEx buffer
    const usz ADDR_SIZE_EACH = 28 + 16;        // 44
    const usz ADDR_BUF_SIZE  = ADDR_SIZE_EACH * 2;  // 88 byte
    
    winsock2::Socket listen_sock = (winsock2::Socket)listen_fd;
    if (acceptEx == null)
    {
        load_acceptex(listen_sock);
        if (acceptEx == null) return aio::ACCEPT_ERROR~;
    }
    
    int family = socket_family(listen_fd)!;
    while (true)
    {
        winsock2::Socket accept_sock = winsock2::wsaSocketW(family, winsock2::SOCK_STREAM, winsock2::IPPROTO_TCP, null, 0, winsock2::WSA_FLAG_OVERLAPPED
        );
        if (accept_sock == winsock2::INVALID_SOCKET)
        {
            return aio::ACCEPT_ERROR~;
        }
        
        io::fd_set_socket((winbase::Handle)accept_sock, true);

        if (!io::iocp_associate((winbase::Handle)accept_sock))
        {
            close_accept_socket(accept_sock);
            return aio::ACCEPT_ERROR~;
        }
            
        winbase::DWord received = 0;
    
        Future* fut = aio::future_new()!;
        IocpOp* op = io::op_alloc();
        op.future = fut;
        op.is_socket = true;
        op.is_write = false;
        op.is_accept = true;
        op.handle = (winbase::Handle)accept_sock;
        
        winbase::Bool ok = acceptEx(listen_sock, accept_sock, &op.addr_buf[0], 0, (winbase::DWord)ADDR_SIZE_EACH, (winbase::DWord)ADDR_SIZE_EACH, &received, &op.ov);
    
        if (!ok && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
        {
            fut.free();
            io::op_free(op);
            close_accept_socket(accept_sock);
            return aio::ACCEPT_ERROR~;
        }
    
        void*? rr = fut.await();
        fut.free();
        
        if (catch err = rr)
        {
            close_accept_socket(accept_sock);
            return aio::ACCEPT_ERROR~;
        }
        
        if (rr == null)
        {
            io::op_free(op);
            close_accept_socket(accept_sock);
            return aio::ACCEPT_ERROR~;
        }
        
        io::op_free((IocpOp*)rr); 
        
        if (winsock2::setsockopt(accept_sock, winsock2::SOL_SOCKET, mswsock::SO_UPDATE_ACCEPT_CONTEXT, (char*)&listen_sock, $sizeof(listen_sock)) != 0)
        {
            close_accept_socket(accept_sock);
            continue;
        }

        return (winbase::Handle)accept_sock;
    }
}

alias ConnectExFn = fn winbase::Bool(
    winsock2::Socket s,
    winsock2::SockAddr* name,
    int namelen,
    void* lpSendBuffer,
    winbase::DWord dwSendDataLength,
    winbase::DWord* lpdwBytesSent,
    winbase::Overlapped* lpOverlapped
) @callconv("stdcall");

ConnectExFn connectEx;

fn void load_connectex(winsock2::Socket s) @private
{
    if (connectEx != null) return;
    guiddef::Guid guid = mswsock::WSAID_CONNECTEX;
    winbase::DWord bytes = 0;
    int rr =  winsock2::wsaIoctl(
        s,
        winsock2::SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guid, $sizeof(guid),
        &connectEx, $sizeof(connectEx),
        &bytes, null, null
    );
    if (rr != 0) connectEx = null;
}

fn void? socket_bind_any(Fd fd, int family) @private
{
    if (family == winsock2::AF_INET6)
    {
        winsock2::SockAddrIn6 a6 = {};
        a6.sin6_family = (ushort)winsock2::AF_INET6;
        a6.sin6_port = 0;

        if (winsock2::bind((winsock2::Socket)fd, (winsock2::SockAddr*)&a6, $sizeof(a6)) != 0)
        {
            return aio::BIND_ERROR~;
        }

        return;
    }

    winsock2::SockAddrIn a4 = {};
    a4.sin_family = (ushort)winsock2::AF_INET;
    a4.sin_port = 0;

    if (winsock2::bind((winsock2::Socket)fd, (winsock2::SockAddr*)&a4, $sizeof(a4)) != 0)
    {
        return aio::BIND_ERROR~;
    }
}

fn void? tcp_connect(Fd fd, String ip, ushort port) // unbound fd only
{
    load_connectex((winsock2::Socket) fd);
    if (connectEx == null) return aio::CONNECT_ERROR~;

    winsock2::SockAddrStorage addr;
    winsock2::SockLen len;
    make_sockaddr(ip, port, &addr, &len)!;

    int family = ((winsock2::SockAddr*)&addr).sa_family;
    socket_bind_any(fd, family)!;
    
    Future* fut = aio::future_new()!; defer fut.free();
    IocpOp* op = io::op_alloc();
    op.future = fut;
    op.is_write = false;
    op.is_socket = true;
    op.is_connect = true;
    op.handle = (winbase::Handle)fd;
    
    winbase::DWord sent = 0;
    winbase::Bool ok = connectEx(
        (winsock2::Socket)fd, (winsock2::SockAddr*)&addr, len,
        null, 0, &sent, &op.ov
    );

    if (!ok && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
    {
        io::op_free(op);
        return aio::CONNECT_ERROR~;
    }

    void*? rr = fut.await();
    
    if (catch err = rr)
    {
        return err~;
    }
    
    if (rr == null)
    {
        io::op_free(op);
        return aio::CONNECT_ERROR~;
    }
    
    io::op_free((IocpOp*)rr); 

    int soerr = 0;
    int slen = $sizeof(soerr);
    int rc = winsock2::getsockopt(
        (winsock2::Socket)fd,
        winsock2::SOL_SOCKET,
        winsock2::SO_ERROR,
        (char*)&soerr,
        &slen
    );
    if (rc != 0) return aio::CONNECT_ERROR~;
    if (soerr != 0) return aio::CONNECT_ERROR~;
    
    if (winsock2::setsockopt((winsock2::Socket)fd, winsock2::SOL_SOCKET, mswsock::SO_UPDATE_CONNECT_CONTEXT, null, 0) != 0)
    {
        return aio::CONNECT_ERROR~;
    }
}

fn int? ip_family(String ip) @private
{
    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..])!;

    if (string::strchr(ip_str, ':') != null)
    {
        return winsock2::AF_INET6;
    }

    return winsock2::AF_INET;
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

    ws2tcpip::AddrInfo hints = {};
    hints.ai_family = winsock2::AF_UNSPEC;
    hints.ai_socktype = winsock2::SOCK_STREAM;
    hints.ai_protocol = winsock2::IPPROTO_TCP;

    ws2tcpip::AddrInfo* res = null;

    char[256] host_buf;
    char* host_cstr = str2cptr(host, host_buf[..])!;

    int rc = ws2tcpip::getaddrinfo(
        host_cstr,
        &port_str[0],
        &hints,
        &res
    );
    if (rc != 0) return DNS_LOOKUP_ERROR~;

    defer ws2tcpip::freeaddrinfo(res);

    List{String} ips;
    ips.init(aio::localmem);

    ws2tcpip::AddrInfo* rp = res;
    while (rp != null)
    {
        winsock2::SockAddr* addr = rp.ai_addr;

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
    cache_store(key, ips2)!;

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