// stream.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import c::errno;
import c::string;
import ext::mem;
import ext::debug;
import ext::aio::io;
import ext::aio::net;

faultdef CLOSED;

struct Stream
{
    Fd fd;
    bool closed;
}

fn Stream*? stream_new(Fd fd)
{
    Stream* s = localmem.alloc(Stream)!;
    *s = {
        .fd = fd,
        .closed = false,
    };

    return s;
}

fn Stream*? stream_listen(String host, ushort port, int backlog = DEFAULT_BACKLOG)
{
    Fd sock = net::tcp_listen_host(host, port, backlog)!;
    return stream_new(sock)!;
}

fn Stream*? stream_connect(String host, ushort port)
{
    Fd sock = net::tcp_connect_host(host, port)!;
    return stream_new(sock)!;
}

fn Stream*? Stream.accept(&self)
{
    Fd sock = net::tcp_accept(self.fd)!;
    return stream_new(sock)!;
}

fn void Stream.free(&self)
{
    if (!self.closed) self.close();

    localmem.free(self);
}

fn void Stream.close(&self)
{
    if (self.closed) return;

    if (!io::fd_invalid(self.fd))
    {
        net::socket_close(self.fd);
        self.fd = io::fd_null();
    }

    self.closed = true;
}

// caller should free
fn String? Stream.peer_ip(&self)
{
    if (io::fd_invalid(self.fd)) return CLOSED~;

    return net::peer_ip(self.fd)!;
}

fn bool Stream.is_closed(&self) @inline
{
    return self.closed || io::fd_invalid(self.fd);
}

fn sz? Stream.read(&self, char[] buf)
{
    if (self.is_closed()) return CLOSED~;

    return io::async_read(self.fd, buf);
}

fn sz? Stream.read_timeout(&self, char[] buf, ulong timeout_ms)
{
    Timer* timer = start_timer(timeout_ms)!;
    defer timer.cancel();

    return self.read(buf[..]);
}

fn sz? Stream.write(&self, char[] buf) @maydiscard
{
    if (self.is_closed()) return CLOSED~;

    return io::async_write(self.fd, buf);
}

fn void? Stream.write_all(&self, char[] data) @maydiscard
{
    if (self.is_closed()) return CLOSED~;

    sz sent = 0;

    while (sent < data.len)
    {
        char[] part = data[sent..];

        sz n = self.write(part)!;

        if (n == 0) return CLOSED~;

        sent += n;
    }
}

fn void? Stream.write_all_timeout(&self, char[] data, ulong timeout_ms)
{
    Timer* timer = start_timer(timeout_ms)!;
    defer timer.cancel();

    self.write_all(data[..])!;
}

fn void? Stream.read_exact(&self, char[] buf)
{
    sz got = 0;

    while (got < buf.len)
    {
        char[] part = buf[got..];

        sz n = self.read(part)!;

        if (n == 0) return CLOSED~;

        got += n;
    }
}

fn sz? Stream.read_until(&self, char[] buf, char delim)
{
    sz pos = 0;

    while (pos < buf.len)
    {
        char[1] ch;

        sz n = self.read(ch[..])!;

        if (n == 0) break;

        buf[pos] = ch[0];
        pos += 1;

        if (ch[0] == delim) break;
    }

    return pos;
}

fn sz? Stream.read_line(&self, char[] buf)
{
    return self.read_until(buf, '\n');
}


fn Stream*? stream_connect_timeout(String host, ushort port, ulong timeout_ms)
{
    Timer* timer = start_timer(timeout_ms)!;
    defer timer.cancel();

    return stream_connect(host, port);
}

// eof