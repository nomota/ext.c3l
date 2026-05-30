// datagram.c3

module ext::asyncio;

import std::io;
import ext::debug;
import ext::mem;

struct Datagram {
    int fd;
    bool closed;
    fault error;
}

fn Datagram* datagram_new(int fd) @private // called at loop.open_datagram(ip, port)
{
    Datagram* d = localmem.alloc(Datagram);
    *d = {
        .fd = fd,
        .closed = false,
        .error = NONE,
    };
    
    set_nonblocking(fd);
    
    return d;
}

fn void Datagram.free(&self) // private
{
    localmem.free(self);
}

fn sz? Datagram.sendto(&self, char[] data, char[] ip, short port)
{
    char[64] ipaddr;
    ipaddr[0:ip.len] = ip[0:ip.len];
    ipaddr[ip.len] = 0;
    sz? n = async_sendto(self.fd, data.ptr, data.len, &ipaddr[0], port);
    if (catch err = n) {
        self.error = err;
        return err~;
    }
    return n;
}

fn sz? Datagram.recvfrom(&self, char[] data, char[] ip, sz* ip_len, ushort* port)
{
    sz? n = async_recvfrom(self.fd, data.ptr, data.len, ip.ptr, ip_len, port);
    if (catch err = n) {
        self.error = err;
        return err~;
    }
    return n;
}

fn sz? EventLoop.sock_sendto(&self, int sock_fd, char[] data, char[] ip, short port)
{
    char[64] ipaddr;
    ipaddr[0:ip.len] = ip[0:ip.len];
    ipaddr[ip.len] = 0;
    sz? n = async_sendto(sock_fd, data.ptr, data.len, &ipaddr[0], port);
    if (catch err = n) {
        // self.error = err;
        return err~;
    }
    return n;
}

fn sz? EventLoop.sock_recvfrom(&self, int sock_fd, char[] data, char[] ip, sz* ip_len, ushort* port)
{
    sz? n = async_recvfrom(sock_fd, data.ptr, data.len, ip.ptr, ip_len, port);
    if (catch err = n) {
        // self.error = err;
        return err~;
    }
    return n;
}

fn void Datagram.close(&self) 
{
    if (self.closed) return;
    self.closed = true;
    socket_close(self.fd);
    self.free();
}

