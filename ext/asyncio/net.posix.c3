// net.posix.c3

// Net functions for asyncio

// Nomota <hiongun@gmail.com>; MIT License

module ext::asyncio @if(!env::WIN32);

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
import ext::thread::fiber;

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

fn int socket_new(int family, int type) @private
{
    int sock = socket::socket(family, type, 0);
    if (sock < 0) {
        return -1;
    }
    set_nonblocking(sock);
    return sock;
}

fn void socket_close(int sock)
{
    String? ip = ips[sock];
    if (try ip) {
        ip.free(localmem);
        ips.remove(sock);
    }
    unregister(sock);
    unistd::close(sock);
}

fn int socket(String ipversion, String proto)
{
    int family = socket::AF_INET;
    if (ipversion == "IPV6") {
        family = socket::AF_INET6;
    }
    int type = socket::SOCK_STREAM;
    if (proto == "UDP") {
        type = socket::SOCK_DGRAM;
    }
    return socket_new(family, type);
}

alias ClientHandler = fn void(Stream*);

fn void store_ip_addr(int sock, netdb::AddrInfo* res) @private
{
    void *addr;
    if (res.ai_family == socket::AF_INET) { // IPv4
        in::SockAddrIn *ipv4 = (in::SockAddrIn*)res.ai_addr;
        addr = &(ipv4.sin_addr);
    } else { // IPv6
        in::SockAddrIn6 *ipv6 = (in::SockAddrIn6*)res.ai_addr;
        addr = &(ipv6.sin6_addr);
    }
    
    // Convert binary IP to String
    char[64] ipstr;
    inet::inet_ntop(res.ai_family, addr, &ipstr[0], 64);
    ips[sock] = ((String)ipstr[0:string::strlen(&ipstr[0])]).copy(localmem);
}

fn int? _resolve_and_connect(char* host, ushort port) @private
{
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    netdb::AddrInfo hints = {};
    // string::memset(&hints, 0, hints.sizeof);
    hints.ai_family = netdb::AF_UNSPEC;
    hints.ai_socktype = socket::SOCK_STREAM;

    netdb::AddrInfo* res = null;
    if (netdb::getaddrinfo(host, &port_str[0], &hints, &res) != 0) return IO_ERROR~;
    defer netdb::freeaddrinfo(res);

    EventLoop* loop = asyncio::get_running_loop();

    int fd = -1;
    netdb::AddrInfo* rp = res;
    while (rp != null) {
        fd = socket_new(rp.ai_family, rp.ai_socktype);
        if (fd < 0) { rp = rp.ai_next; continue; }

        int rc = socket::connect(fd, rp.ai_addr, rp.ai_addrlen);
        if (rc == 0) {
            store_ip_addr(fd, rp);
            break;
        }
        
        if (errno::errno() == errno::EINPROGRESS) {
            Future* wfut = loop.create_future();
            register_write(fd, wfut);

            void*? wres = wfut.await();
            wfut.free();
            if (catch err = wres) {
                socket_close(fd);
                return err~;
            }

            int err = 0; 
            socket::SockLen elen = $sizeof(err);
            socket::getsockopt(fd, socket::SOL_SOCKET, socket::SO_ERROR, &err, &elen);
            if (err == 0) {
                store_ip_addr(fd, rp);
                break;
            }
            socket_close(fd);
            fd = -1;
            rp = rp.ai_next;
            continue;
        }
        
        socket_close(fd);
        fd = -1;
        rp = rp.ai_next;
    }

    if (fd < 0) return IO_ERROR~;
    return fd;
}


fn Stream*? open_connection(String host_str, ushort port) 
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);
    int fd = _resolve_and_connect(host, port)!;
    return stream_new(fd); // close() must be done at caller
}

fn int? _resolve_and_datagram(char* host, ushort port) @private
{
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    netdb::AddrInfo hints = {};
    hints.ai_family = netdb::AF_UNSPEC;
    hints.ai_socktype = socket::SOCK_DGRAM;
    hints.ai_protocol = 0;
    // host == null or "" -> INADDR_ANY
    hints.ai_flags = netdb::AI_PASSIVE;

    netdb::AddrInfo* res = null;
    char* bind_host = (host != null && host[0] != 0) ? host : null;
    if (netdb::getaddrinfo(bind_host, &port_str[0], &hints, &res) != 0) {
        return IO_ERROR~;
    }
    defer netdb::freeaddrinfo(res);

    int fd = -1;
    netdb::AddrInfo* rp = res;
    while (rp != null) {
        fd = socket_new(rp.ai_family, rp.ai_socktype);
        if (fd < 0) { rp = rp.ai_next; continue; }

        int yes = 1;
        socket::setsockopt(fd, socket::SOL_SOCKET, socket::SO_REUSEADDR, (char*)&yes, $sizeof(yes));
        socket::setsockopt(fd, socket::SOL_SOCKET, socket::SO_REUSEPORT, (char*)&yes, $sizeof(yes));
        store_ip_addr(fd, rp);
        break;
    }

    if (fd < 0) return IO_ERROR~;
    return fd;
}

fn Datagram*? open_datagram(String host_str, ushort port)
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);

    int fd = _resolve_and_datagram(host, port)!;
    return datagram_new(fd); // close() must be done at caller
}


fn int? _resolve_and_bind(char* host, ushort port) @private
{
    char[16] port_str;
    stdio::snprintf(&port_str[0], 16, "%d", (int)port);

    netdb::AddrInfo hints = {};
    hints.ai_family = netdb::AF_UNSPEC;
    hints.ai_socktype = socket::SOCK_DGRAM;
    hints.ai_protocol = 0;
    // host == null or "" -> INADDR_ANY
    hints.ai_flags = netdb::AI_PASSIVE;

    netdb::AddrInfo* res = null;
    char* bind_host = (host != null && host[0] != 0) ? host : null;
    if (netdb::getaddrinfo(bind_host, &port_str[0], &hints, &res) != 0) {
        return IO_ERROR~;
    }
    defer netdb::freeaddrinfo(res);

    int fd = -1;
    netdb::AddrInfo* rp = res;
    while (rp != null) {
        fd = socket_new(rp.ai_family, rp.ai_socktype);
        if (fd < 0) { rp = rp.ai_next; continue; }

        int yes = 1;
        socket::setsockopt(fd, socket::SOL_SOCKET, socket::SO_REUSEADDR, (char*)&yes, $sizeof(yes));
        socket::setsockopt(fd, socket::SOL_SOCKET, socket::SO_REUSEPORT, (char*)&yes, $sizeof(yes));

        if (socket::bind(fd, rp.ai_addr, rp.ai_addrlen) == 0) {
            store_ip_addr(fd, rp);
            break; // success
        }

        socket_close(fd);
        fd = -1;
        rp = rp.ai_next;
    }

    if (fd < 0) return IO_ERROR~;
    return fd;
}

fn Datagram*? bind_endpoint(String host_str, ushort port)
{
    char[256] buf;
    char* host = str2cptr(host_str, &buf);

    int fd = _resolve_and_bind(host, port)!;
    return datagram_new(fd); // close() must be done at caller
}

struct Server {
    int listen_fd;
    bool running;
    ushort port;
    ClientHandler handler;
    Task* accept_task;
    
    Transport* transport; // protocol.c3
}

fn Server* server_new() @private
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
    if (conn == null) { unistd::close(fd); return; }
    handler(conn); // close() must be called in handler
}

fn String get_ip(socket::SockAddrStorage* ss)
{
    char[47] ip_buf = {};
    usz ip_len = 0;
    if (ss.ss_family == (ushort)socket::AF_INET6) {
        in::SockAddrIn6* a6 = (in::SockAddrIn6*)ss;
        in::inet_ntop(socket::AF_INET6, &a6.sin6_addr, &ip_buf[0], 46);
        ip_len = (usz)string::strlen(&ip_buf[0]);
    } else {
        in::SockAddrIn* a4 = (in::SockAddrIn*)ss;
        in::inet_ntop(socket::AF_INET, &a4.sin_addr, &ip_buf[0], 16);
        ip_len = (usz)string::strlen(&ip_buf[0]);
    }
    return ((String)ip_buf[0:ip_len]).copy(localmem);
}
    

fn void? _accept_loop(Server* self) @private
{
    EventLoop* loop = asyncio::get_running_loop();

    while (self.running) {
        Future* afut = loop.create_future();
        register_read(self.listen_fd, afut);

        void*? res = afut.await();
        afut.free();
        
        if (catch err = res) {
            if (!self.running) break;
            return err~;
        }

        if (!self.running) break;

        while (true) {
            socket::SockAddrStorage addr;
            socket::SockLen alen = $sizeof(addr);
            int cfd = socket::accept(self.listen_fd, (socket::SockAddr*)&addr, &alen);
            if (cfd < 0) {
                int err = errno::errno();
                if (err == errno::ENFILE || err == errno::EMFILE) {
                    warn("too many files/sockets open at accept");
                    asyncio::sleep(0.1);
                }
                if (err != errno::EAGAIN && err != errno::EWOULDBLOCK) {
                    warn("accept error: %d", err);
                }
                break;
            }
            set_nonblocking(cfd);
            ips[cfd] = get_ip(&addr);

            ClientCtx* ctx = localmem.alloc(ClientCtx);
            *ctx = { cfd, self.handler };

            loop.create_task(&_client_task, "tcp_client", 256_000, true, ctx);
        }
    }
}


fn void serv_fn() @private
{
   EventLoop* loop = asyncio::get_running_loop();
    Task* self_task = loop.current;
    Server* server = (Server*)self_task.arg;

    if (catch err = _accept_loop(server)) {
        // warn("%s", err);
        if (server.running) {
            warn("accept loop exited unexpectedly");
        }
    }
}

faultdef INET_PTON_ERROR, BIND_ERROR;

fn Server*? start_server(ClientHandler handler, String host_str, ushort port) 
{
    char[64] buf;
    char* host = str2cptr(host_str, &buf);
   
    EventLoop* loop = asyncio::get_running_loop();
    
    short family = socket::AF_INET;
    if (string::strchr(host, ':') != null) {
        family = socket::AF_INET6;
    }
    
    int fd = socket::socket(family, socket::SOCK_STREAM, 0);
    @assert(fd >= 0, "asyncio::net: socket() failed");

    int yes = 1;
    socket::setsockopt(fd, socket::SOL_SOCKET, socket::SO_REUSEADDR, (char*)&yes, $sizeof(yes));
    set_nonblocking(fd);

    int b = 0;
    if (family == socket::AF_INET6) {
        in::SockAddrIn6 addr6 = {};
        addr6.sin6_family = family;
        addr6.sin6_port = in::htons(port);
        
        if (host[0] == 0) {
            addr6.sin6_addr = {}; // INADDR_ANY
        } else {
            if (in::inet_pton(family, host, &addr6.sin6_addr) != 1) {
                unistd::close(fd);
                return INET_PTON_ERROR~;
            }
        }

        b = socket::bind(fd, (socket::SockAddr*)&addr6, $sizeof(addr6));
    } else {
        in::SockAddrIn addr4 = {};
        addr4.sin_family = family;
        addr4.sin_port = in::htons(port);

        if (host[0] == 0) {
            addr4.sin_addr = {}; // INADDR_ANY
        } else {
            if (in::inet_pton(family, host, &addr4.sin_addr) != 1) {
                unistd::close(fd);
                return INET_PTON_ERROR~;
            }
        }
        
        b = socket::bind(fd, (socket::SockAddr*)&addr4, $sizeof(addr4));
    }
    
    if (b != 0) {
        unistd::close(fd);
        return BIND_ERROR~;
    }

    @assert(socket::listen(fd, 128) == 0, "asyncio::net: listen() failed");

    Server* server = server_new();
    
    *server = {
        .listen_fd = fd,
        .running = true,
        .port = port,
        .handler = handler,
        .accept_task = null,
        .transport = null,
    };

    return server; // free() at caller
}

fn void? Server.serve_forever(&self) @maydiscard
{
    EventLoop* loop = asyncio::get_running_loop();
   
    Task* t = loop.create_task(&serv_fn, "tcp_accept_loop", 64_000, false, self);
    
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
   if (!self.running && self.listen_fd < 0) return;

    self.running = false;

    if (self.listen_fd >= 0) {
        unregister(self.listen_fd);
        unistd::close(self.listen_fd);
        self.listen_fd = -1;
    }
    
    if (self.accept_task != null) self.accept_task.cancel();
}
