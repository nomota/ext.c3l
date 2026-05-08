// stream.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import c::unistd;
import c::errno;
import c::string;
import ext::mem;
import ext::debug;

faultdef ASYNC_CLOSED;

struct Stream {
    int fd;
    bool closed;
}

fn Stream* stream_new(int fd)
{
    Stream* s = localmem.alloc(Stream);

    *s = {
        .fd = fd,
        .closed = false,
    };

    return s;
}

fn void Stream.free(&self)
{
    if (!self.closed) {
        self.close();
    }

    localmem.free(self);
}

fn void Stream.close(&self)
{
    if (self.closed) return;

    if (self.fd >= 0) {
        unistd::close(self.fd);
        self.fd = -1;
        socket_forget_ip(self.fd);
    }

    self.closed = true;
}

fn bool Stream.is_closed(&self) @inline
{
    return self.closed || self.fd < 0;
}

fn usz? Stream.read(&self, char[] buf)
{
    if (self.is_closed()) {
        return ASYNC_CLOSED~;
    }

    if (buf.len == 0) {
        return 0;
    }

    while (true) {
        isz n = unistd::read(self.fd, buf.ptr, buf.len);

        if (n >= 0) {
            return (usz)n;
        }

        int err = errno::errno();

        if (err == errno::EINTR) {
            continue;
        }

        if (err == errno::EAGAIN || err == errno::EWOULDBLOCK) {
            wait_readable(self.fd)!;
            continue;
        }

        return ASYNC_IO_ERROR~;
    }

    // return ASYNC_IO_ERROR~;
}

fn usz? Stream.write(&self, char[] data) @maydiscard
{
    if (self.is_closed()) {
        return ASYNC_CLOSED~;
    }

    if (data.len == 0) {
        return 0;
    }

    while (true) {
        isz n = unistd::write(self.fd, data.ptr, data.len);

        if (n >= 0) {
            return (usz)n;
        }

        int err = errno::errno();

        if (err == errno::EINTR) {
            continue;
        }

        if (err == errno::EAGAIN || err == errno::EWOULDBLOCK) {
            wait_writable(self.fd)!;
            continue;
        }

        return ASYNC_IO_ERROR~;
    }

    // return ASYNC_IO_ERROR~;
}

fn void? Stream.write_all(&self, char[] data) @maydiscard
{
    if (self.is_closed()) {
        return ASYNC_CLOSED~;
    }

    usz sent = 0;

    while (sent < data.len) {
        char[] part = data[sent..];

        isz n = self.write(part)!;

        if (n < 0) {
            return ASYNC_IO_ERROR~;
        }

        if (n == 0) {
            return ASYNC_CLOSED~;
        }

        sent += (usz)n;
    }

    return;
}

fn void? Stream.read_exact(&self, char[] buf)
{
    usz got = 0;

    while (got < buf.len) {
        char[] part = buf[got..];

        isz n = self.read(part)!;

        if (n < 0) {
            return ASYNC_IO_ERROR~;
        }

        if (n == 0) {
            return ASYNC_CLOSED~;
        }

        got += (usz)n;
    }

    return;
}

fn usz? Stream.read_until(&self, char[] buf, char delim)
{
    usz pos = 0;

    while (pos < buf.len) {
        char[1] ch;

        isz n = self.read(ch[..])!;

        if (n < 0) {
            return ASYNC_IO_ERROR~;
        }

        if (n == 0) {
            break;
        }

        buf[pos] = ch[0];
        pos += 1;

        if (ch[0] == delim) {
            break;
        }
    }

    return pos;
}

fn usz? Stream.read_line(&self, char[] buf)
{
    return self.read_until(buf, '\n');
}

