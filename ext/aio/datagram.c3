// datagram.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import ext::mem;
import ext::aio::io;
import ext::aio::net;

faultdef DATAGRAM_CLOSED;

struct DatagramAddr
{
    char[64] ip;
    usz ip_len;
    ushort port;
}

struct Datagram
{
    Fd fd;
    bool closed;
    fault error;
}

fn Datagram*? datagram_new(Fd fd) @private
{
    Datagram* d = localmem.alloc(Datagram)!;
    *d = {
        .fd = fd,
        .closed = false,
        .error = NONE,
    };

    return d;
}

fn Datagram*? datagram_bind(String host, ushort port)
{
    Fd fd = net::udp_bind_host(host, port)!;
    return datagram_new(fd)!;
}

fn bool Datagram.is_closed(&self) @inline
{
    return self.closed || io::fd_invalid(self.fd);
}

fn void Datagram.close(&self)
{
    if (self.closed) return;

    if (!io::fd_invalid(self.fd))
    {
        io::fd_close(self.fd);
        self.fd = io::fd_null();
    }

    self.closed = true;
}

fn void Datagram.free(&self)
{
    if (!self.closed) self.close();

    localmem.free(self);
}

fn char* str2cptr(String str, char[] buf) @inline @private
{
    usz len = (str.len <= buf.len-1)? str.len: buf.len-1;
    buf[0:len] = str[0:len];
    buf[len] = 0;
    return &buf[0];
}

fn usz? Datagram.sendto(&self, char[] data, String ip, ushort port)
{
    if (self.is_closed()) return DATAGRAM_CLOSED~;

    char[128] buf;
    char* ip_str = str2cptr(ip, buf[..]);

    usz? n = io::async_sendto(self.fd, data, ip_str, port);

    if (catch err = n)
    {
        self.error = err;
        return err~;
    }

    return n;
}

fn usz? Datagram.recvfrom(&self, char[] data, DatagramAddr* from)
{
    if (self.is_closed()) return DATAGRAM_CLOSED~;

    usz? n = io::async_recvfrom(self.fd, data, &from.ip[0], &from.ip_len, &from.port);

    if (catch err = n)
    {
        self.error = err;
        return err~;
    }

    return n;
}

fn Datagram*? open_datagram()
{
    Fd fd = net::udp_socket()!;

    Datagram* d = datagram_new(fd)!;

    return d;
}

// eof