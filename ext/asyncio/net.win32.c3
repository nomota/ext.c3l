// net.win32.c3

// Net functions for asyncio

// Nomota <hiongun@gmail.com>; MIT License

module ext::asyncio @if(env::WIN32) @link("ws2_32");

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

tlocal HashMap{int,String} ips @private; // IP addr cache

fn String? socket_ip(int fd)
{
    return ips[fd]!;
}

fn char* str2cptr(String str, char[] buf) @inline @private
{
    usz len = (str.len <= buf.len-1)? str.len: buf.len-1;
    string::memcpy(&buf[0], &str[0], len);
    buf[len] = 0;
    return &buf[0];
}

// _resolve_and_bind_win, _resolve_and_datagram, socket()
fn void _disable_conn_reset(winsock2::Socket sock) @private
{
    int off = 0;
    winbase::DWord dummy;
    winsock2::wsaIoctl(
        sock, winsock2::SIO_UDP_CONNRESET,
        &off, $sizeof(off),
        null, 0, &dummy, null, null
    );
}

fn int socket_new(int family, int type)
{
    winsock2::Socket sock = winsock2::wsaSocketW(family, type, 0,
            null, 0, winsock2::WSA_FLAG_OVERLAPPED
        );
    if (sock == winsock2::INVALID_SOCKET) { return -1;
    }

    // IOCP socket connect
    // _iocp_associate((winbase::Handle)sock);
    if (!_iocp_associate((winbase::Handle)sock)) {
        winsock2::closesocket(sock);
        return -1;
    }
    _disable_conn_reset(sock);
    return (int)sock;
}

fn void socket_close(int fd)
{
    String? ip = ips[sock];
    if (try ip) {
        ip.free(localmem);
        ips.remove(sock);
    }
    unregister(fd);
    winsock2::closesocket((winsock2::Socket)(iptr)fd);
}

fn int socket(String ipversion, String proto)
{
    int family = winsock2::AF_INET;
    if (ipversion == "IPV6") {
        family = winsock2::AF_INET6;
    }
    int type = winsock2::SOCK_STREAM;
    if (proto == "UDP") {
        type = winsock2::SOCK_DGRAM;
    }
    return socket_new(family, type);
}

alias ClientHandler = fn void(Stream*);

fn void store_ip_addr(int sock, netdb::AddrInfo* res) @private
{
    void *addr;
    if (res.ai_family == winsock2::AF_INET) { // IPv4
        winsock2::SockAddrIn *ipv4 = (winsock2::SockAddrIn*)res.ai_addr;
        addr = &(ipv4.sin_addr);
    } else { // IPv6
        winsock2::SockAddrIn6 *ipv6 = (winsock2::SockAddrIn6*)res.ai_addr;
        addr = &(ipv6.sin6_addr);
    }
    
    // Convert binary IP to String
    char[64] ipstr;
    winsock2::inet_ntop(res.ai_family, addr, &ipstr[0], 64);
    ips[sock] = ((String)ipstr[0:string::strlen(&ipstr[0])]).copy(localmem);
}

alias ConnectExFn = fn winbase::Bool(
    winsock2::Socket s,
    winsock2::SockAddr* name,
    int namelen,
    void* lpSendBuffer,
    winbase::DWord dwSendDataLength,
    winbase::DWord* lpdwBytesSent,
    winbase::Overlapped* lpOverlapped
);

tlocal ConnectExFn _connectEx;

fn void _load_connectex(winsock2::Socket s) @private
{
    if (_connectEx != null) return;
    guiddef::Guid guid = mswsock::WSAID_CONNECTEX;
    winbase::DWord bytes = 0;
    int rr =  winsock2::wsaIoctl(
        s,
        winsock2::SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guid, $sizeof(guid),
        &_connectEx, $sizeof(_connectEx),
        &bytes, null, null
    );
    if (rr != 0) _connectEx = null;
}

fn int? _resolve_and_connect_win(char* host, ushort port) 
{
    EventLoop* loop = asyncio::get_running_loop();
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    ws2tcpip::AddrInfo hints = {};

    hints.ai_family = winsock2::AF_UNSPEC;
    hints.ai_socktype = winsock2::SOCK_STREAM;

    ws2tcpip::AddrInfo* res = null;
    if (ws2tcpip::getaddrinfo(host, &port_str[0], &hints, &res) != 0) { return IO_ERROR~;
    }
    defer ws2tcpip::freeaddrinfo(res);

    int result = -1;
    ws2tcpip::AddrInfo* rp = res;
    while (rp != null) {
        int fd = socket_new(
            rp.ai_family, rp.ai_socktype);
            
        if (fd < 0) { rp = rp.ai_next; continue; }
        
        winsock2::Socket sock = (winsock2::Socket)(iptr)fd;

        _load_connectex(sock);
        if (_connectEx == null) {
            socket_close(fd);
            rp = rp.ai_next;
            continue;
        }

        if (rp.ai_family == winsock2::AF_INET) {
            winsock2::SockAddrIn local4 = {};
            local4.sin_family = winsock2::AF_INET;
            local4.sin_port = 0;
            local4.sin_addr.s_addr = 0; // INADDR_ANY
            if (winsock2::bind(sock, (winsock2::SockAddr*)&local4, $sizeof(local4)) != 0) {
                socket_close(fd);
                rp = rp.ai_next;

                continue;
            }
        } else if (rp.ai_family == winsock2::AF_INET6) {
            winsock2::SockAddrIn6 local6 = {};
            local6.sin6_family = winsock2::AF_INET6;
            local6.sin6_port = 0;
            // sin6_addr zero => in6addr_any
            if (winsock2::bind(sock, (winsock2::SockAddr*)&local6, $sizeof(local6)) != 0) {
                socket_close(fd);
                rp = rp.ai_next;

                continue;
            }
        } else {
            socket_close(fd);
            rp = rp.ai_next;
            continue;
        }

        Future* fut = loop.create_future();
        IocpOp* op = _op_alloc();
        op.future = fut;
        op.is_write = false;
        op.is_socket = true;
        op.handle = (winbase::Handle)sock;

        winbase::DWord sent = 0;
        winbase::Bool ok = _connectEx(
            sock, rp.ai_addr, (int)rp.ai_addrlen,
            null, 0, &sent, &op.ov
        );

        if (!ok && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING) {
            socket_close(fd);
            fut.free();
            _op_free(op);

            rp = rp.ai_next;
            continue;
        }

        void*? rr = fut.await();
        fut.free();
        if (catch err = rr) {
            socket_close(fd);
            rp = rp.ai_next;
            continue;
        } else if (rr != null) {
            _op_free((IocpOp*)rr);
        }

        int soerr = 0;
        int slen = $sizeof(soerr);
        winsock2::getsockopt(sock, winsock2::SOL_SOCKET, winsock2::SO_ERROR, (char*)&soerr, &slen);
        if (soerr != 0) {
            socket_close(fd);
            rp = rp.ai_next;
            continue;
        }
        
        if (winsock2::setsockopt(sock, winsock2::SOL_SOCKET, mswsock::SO_UPDATE_CONNECT_CONTEXT, null, 0) != 0) {
            socket_close(fd);
            continue;
        }

        store_ip_addr((int)sock, rp);
        result = (int)sock;
        break;
    }

    if (result == -1) return IO_ERROR~;
    return result;
}

fn Stream*? open_connection(String host_str, ushort port)
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);

    int fd = _resolve_and_connect_win(host, port)!;
    return stream_new(fd); // close() must be done at caller
}

fn int? _resolve_and_datagram(char* host, ushort port) @private
{
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    ws2tcpip::AddrInfo hints = {};
    hints.ai_family = winsock2::AF_UNSPEC;
    hints.ai_socktype = winsock2::SOCK_DGRAM;
    hints.ai_protocol = winsock2::IPPROTO_UDP;
    // host == null or "", bind with INADDR_ANY
    hints.ai_flags    = ws2tcpip::AI_PASSIVE;

    ws2tcpip::AddrInfo* res = null;
    char* bind_host = (host != null && host[0] != 0) ? host : null;
    if (ws2tcpip::getaddrinfo(bind_host, &port_str[0], &hints, &res) != 0) {
        return IO_ERROR~;
    }
    defer ws2tcpip::freeaddrinfo(res);

    int result = -1;
    ws2tcpip::AddrInfo* rp = res;
    while (rp != null) {
        int fd = socket_new(rp.ai_family, rp.ai_socktype);
        
        winsock2::Socket sock = (winsock2::Socket)(iptr)fd;

        if (fd < 0) { rp = rp.ai_next; continue; }

        int yes = 1;
        winsock2::setsockopt(sock, winsock2::SOL_SOCKET, winsock2::SO_REUSEADDR, (char*)&yes, $sizeof(yes));

        store_ip_addr(fd, rp);
        result = (int)sock;
        break;
    }

    if (result == -1) return asyncio::IO_ERROR~;
    return result;
}

fn Datagram*? open_datagram(String host_str, ushort port)
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);

    int fd = _resolve_and_datagram(host, port)!;
    return datagram_new(fd); // close() must be call at caller
}

fn int? _resolve_and_bind_win(char* host, ushort port) @private
{
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    ws2tcpip::AddrInfo hints = {};
    hints.ai_family = winsock2::AF_UNSPEC;
    hints.ai_socktype = winsock2::SOCK_DGRAM;
    hints.ai_protocol = winsock2::IPPROTO_UDP;
    // host == null or "", bind with INADDR_ANY
    hints.ai_flags    = ws2tcpip::AI_PASSIVE;

    ws2tcpip::AddrInfo* res = null;
    char* bind_host = (host != null && host[0] != 0) ? host : null;
    if (ws2tcpip::getaddrinfo(bind_host, &port_str[0], &hints, &res) != 0) {
        return IO_ERROR~;
    }
    defer ws2tcpip::freeaddrinfo(res);

    int result = -1;
    ws2tcpip::AddrInfo* rp = res;
    while (rp != null) {
        int fd = socket_new(rp.ai_family, rp.ai_socktype);
        
        winsock2::Socket sock = (winsock2::Socket)(iptr)fd;

        if (fd < 0) { rp = rp.ai_next; continue; }

        int yes = 1;
        // winsock2::setsockopt(sock, winsock2::SOL_SOCKET, winsock2::SO_REUSEADDR, (char*)&yes, $sizeof(yes));
        winsock2::setsockopt(sock, winsock2::SOL_SOCKET, winsock2::SO_EXCLUSIVEADDRUSE, (char*)&yes, $sizeof(yes));

        // bind to address
        int b = winsock2::bind(sock, rp.ai_addr, (int)rp.ai_addrlen);
        if (b != 0) {
            socket_close(fd);
            rp = rp.ai_next;
            continue;
        }

        store_ip_addr(fd, rp);
        result = (int)sock;
        break;
    }

    if (result == -1) return asyncio::IO_ERROR~;
    return result;
}

fn Datagram*? bind_endpoint(String host_str, ushort port) 
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);

    int fd = _resolve_and_bind_win(host, port)!;
    return datagram_new(fd); // close() must be call at caller
}

struct Server {
    int listen_fd;
    bool running;
    ushort port;
    int family;
    ClientHandler handler;
    Task* accept_task;

    Transport* transport; // protocol.c3
}

fn Server* server_new()
{
    Server* s = localmem.alloc(Server);
    *s = {};
    return s;
}

fn void Server.free(&self)
{
    @assert(self.accept_task == null, "Server.free(): accept task still running");
    if (self.transport != null) { // protocol.c3
        self.transport.free();
    }
    localmem.free(self);
}

struct ClientCtx @private {
    int fd;
    ClientHandler handler;
}

fn void _client_task() @private
{
    EventLoop* loop = asyncio::get_running_loop();
    Task* self = loop.current;
    ClientCtx* ctx = (ClientCtx*)self.arg;

    int fd = ctx.fd;
    ClientHandler handler = ctx.handler;

    localmem.free(ctx);
    self.arg = null;
    
    Stream* conn = stream_new(fd);
    if (conn == null) { 
        winsock2::closesocket((winsock2::Socket)fd);
        return;
    }

    handler(conn); // close() must be called in handler
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
);

tlocal AcceptExFn _acceptEx;

fn void _load_acceptex(winsock2::Socket s) 
{
    if (_acceptEx != null) return;
    guiddef::Guid guid = mswsock::WSAID_ACCEPTEX;
    winbase::DWord bytes = 0;
    int rr = winsock2::wsaIoctl(s, winsock2::SIO_GET_EXTENSION_FUNCTION_POINTER, &guid, $sizeof(guid), &_acceptEx, $sizeof(_acceptEx), &bytes, null, null);
    if (rr != 0) _acceptEx = null;
}

fn String get_ip(winsock2::SockAddrStorage* ss)
{
    char[47] ip_buf = {};
    usz ip_len = 0;

    ushort family = ((winsock2::SockAddrIn*)ss).sin_family;
    if (family == (ushort)winsock2::AF_INET6) {
        winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)ss;
        winsock2::inet_ntop(winsock2::AF_INET6, &a6.sin6_addr, &ip_buf[0], 46);
    } else {
        winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)ss;
        winsock2::inet_ntop(winsock2::AF_INET, &a4.sin_addr, &ip_buf[0], 16);
    }
    ip_len = (usz)string::strlen(&ip_buf[0]);

    return ((String)ip_buf[0:ip_len]).copy(localmem);
}

fn void _accept_loop_win(Server* self)
{
    winsock2::Socket listen_sock = (winsock2::Socket)self.listen_fd;
    _load_acceptex(listen_sock);
    @assert(_acceptEx != null, "_load_acceptex() failed");
  
    // AcceptEx buffer
    const usz ADDR_SIZE_EACH = 28 + 16;        // 44
    const usz ADDR_BUF_SIZE  = ADDR_SIZE_EACH * 2;  // 88 byte
    char[ADDR_BUF_SIZE] addr_buf;
    EventLoop* loop = asyncio::get_running_loop();
    while (self.running) {
        winsock2::Socket accept_sock = winsock2::wsaSocketW(self.family, winsock2::SOCK_STREAM, winsock2::IPPROTO_TCP, null, 0, winsock2::WSA_FLAG_OVERLAPPED
        );
        if (accept_sock == winsock2::INVALID_SOCKET) {
            if (catch asyncio::sleep_zero()) break;
            continue;
        }

        // _iocp_associate((winbase::Handle)accept_sock);
        if (!_iocp_associate((winbase::Handle)accept_sock)) {
            winsock2::closesocket(accept_sock);
            if (catch asyncio::sleep_zero()) break;
            continue;
        }
        
        winbase::DWord received = 0;

        Future* fut = loop.create_future();
        IocpOp* op = _op_alloc();
        op.future = fut;
        op.is_socket = true;
        op.is_write = false;
        op.handle = (winbase::Handle)accept_sock;

        winbase::Bool ok = _acceptEx(listen_sock, accept_sock, &addr_buf[0], 0, (winbase::DWord)ADDR_SIZE_EACH, (winbase::DWord)ADDR_SIZE_EACH, &received, &op.ov);

        if (!ok && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING) {
            winsock2::closesocket(accept_sock);
            fut.free();
            _op_free(op);
            if (catch asyncio::sleep_zero()) break;
            continue;
        }

        void*? rr = fut.await();
        fut.free();
        if (catch err = rr) {
            winsock2::closesocket(accept_sock);
            if (!self.running) break;
            continue;
        } else if (rr != null) {
            _op_free((IocpOp*)rr);
        }
        
        if (!self.running) {
            winsock2::closesocket(accept_sock);
            break;
        }
        
        if (winsock2::setsockopt(accept_sock, winsock2::SOL_SOCKET, mswsock::SO_UPDATE_ACCEPT_CONTEXT, (char*)&listen_sock, $sizeof(listen_sock)) != 0) {
            winsock2::closesocket(accept_sock);
            continue;
        }
        
        winsock2::SockAddrStorage peer;
        int peer_len = $sizeof(peer);
        if (winsock2::getpeername(accept_sock, (winsock2::SockAddr*)&peer, &peer_len) == 0) {
            ips[(int)accept_sock] = get_ip(&peer);
        }

        // @assert(_client_ctx_count < 256, "asyncio::net: client pool overflow");
        ClientCtx* ctx = localmem.alloc(ClientCtx);
        *ctx = { (int)accept_sock, self.handler };

        loop.create_task(&_client_task, "tcp_client", 128_000, true, ctx);
    }
}


// tlocal Server* _server_instance;

fn void serv_fn()
{
   EventLoop* loop = asyncio::get_running_loop();
    Task* self_task = loop.current;
    Server* server = (Server*)self_task.arg;

    _accept_loop_win(server);
}

fn Server*? start_server(ClientHandler handler, String host_str, ushort port) 
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);

    // EventLoop* loop = asyncio::get_running_loop();
    
    int family = winsock2::AF_INET;
    if (string::strchr(host, ':') != null) {
        family = winsock2::AF_INET6;
    }
    
    winsock2::Socket sock = winsock2::wsaSocketW(family, winsock2::SOCK_STREAM, winsock2::IPPROTO_TCP, null, 0, winsock2::WSA_FLAG_OVERLAPPED);
    @assert(sock != winsock2::INVALID_SOCKET, "asyncio::net: WSASocket failed");
    
    //._iocp_associate((winbase::Handle)sock);
    if (!_iocp_associate((winbase::Handle)sock)) {
        winsock2::closesocket(sock);
        return IO_ERROR~;
    }    
        
    int fd = (int)sock;

    int yes = 1;
    // winsock2::setsockopt(sock, winsock2::SOL_SOCKET, winsock2::SO_REUSEADDR, (char*)&yes, $sizeof(yes));
    winsock2::setsockopt(sock, winsock2::SOL_SOCKET, winsock2::SO_EXCLUSIVEADDRUSE, (char*)&yes, $sizeof(yes));

    // set_nonblocking(fd);

    int b;
    if (family == winsock2::AF_INET6) {
        winsock2::SockAddrIn6 addr6 = {};
        // string::memset(&addr6, 0, $sizeof(addr6));
        addr6.sin6_family = winsock2::AF_INET6;
        addr6.sin6_port = winsock2::htons(port);
        if (ws2tcpip::inet_pton(winsock2::AF_INET6, host, &addr6.sin6_addr) != 1) {
            winsock2::closesocket(sock);
            return IO_ERROR~;
        }

        b = winsock2::bind(sock, (winsock2::SockAddr*)&addr6, $sizeof(addr6));
    } else {
        winsock2::SockAddrIn addr4 = {};
        // string::memset(&addr4, 0, addr4.sizeof);
        addr4.sin_family = winsock2::AF_INET;
        addr4.sin_port = winsock2::htons(port);
        // ws2tcpip::inet_pton(winsock2::AF_INET, host, (winbase::PVoid)$sizeof(&addr4));
        if (ws2tcpip::inet_pton(winsock2::AF_INET, host, &addr4.sin_addr) != 1) {
            winsock2::closesocket(sock);
            return IO_ERROR~;
        }
        b = winsock2::bind((winsock2::Socket)fd, (winsock2::SockAddr*)&addr4, $sizeof(addr4));
    }
    
    if (b != 0) {
        winsock2::closesocket((winsock2::Socket)fd);
        return asyncio::IO_ERROR~;
    }

    @assert(winsock2::listen((winsock2::Socket)fd, 128) == 0, "asyncio::net: listen() failed");

    Server* server = server_new();
    // *server = { fd, true, port, family, handler, null, null };
    *server = {};
    server.listen_fd = fd;
    server.running = true;
    server.port = port;
    server.family = family;
    server.handler = handler;
    server.accept_task = null;
    server.transport = null;
    
    return server; // free at caller
}

fn void? Server.serve_forever(&self) @maydiscard
{
    EventLoop* loop = asyncio::get_running_loop();

    // _server_instance = server;
    
    Task* t = loop.create_task(&serv_fn, "tcp_accept_loop", 64_000, false, self);
    // asyncio::sleep_zero();
    // task.defer_free();
    self.accept_task = t;
    void*? res = t.await();
    if (self.accept_task == t) self.accept_task = null;
    t.free();
    if (catch err = res) {
        return err~;
    }
}

fn void Server.stop(&self) 
{
    self.running = false;
    
    int fd = self.listen_fd;
    if (fd >= 0) {
        self.listen_fd = -1;
        unregister(fd);
        winsock2::closesocket((winsock2::Socket)fd);
    }
    
    if (self.accept_task != null) self.accept_task.cancel();
}

