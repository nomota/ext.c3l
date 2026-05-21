// file.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import ext::mem;
import c::errno;
import ext::aio::io;

faultdef FILE_CLOSED, FILE_EOF, INVALID_FD;

struct File
{
    Fd fd;
    bool closed;
    bool owns_fd;
}

fn File*? file_from_fd(Fd fd, bool owns_fd = true) @private
{
    if (io::fd_invalid(fd)) return INVALID_FD~;

    File* f = localmem.alloc(File)!;
    *f = {
        .fd = fd,
        .closed = false,
        .owns_fd = owns_fd,
    };

    return f;
}

fn File*? file_open(String path, String mode, int permission = 0o644)
{
    Fd fd = io::file_open(path, mode, permission)!;
    defer (catch err) { io::file_close(fd); }
    return file_from_fd(fd, true)!;
}

fn bool File.is_closed(&self) @inline
{
    return self.closed || io::fd_invalid(self.fd);
}

fn void File.close(&self)
{
    if (self.closed) return;

    if (self.owns_fd && !io::fd_invalid(self.fd))
    {
        io::file_close(self.fd);
    }

    self.fd = io::fd_null();
    self.closed = true;
}

fn void File.free(&self)
{
    if (!self.closed) self.close();

    localmem.free(self);
}

fn usz? File.read(&self, char[] buf)
{
    if (self.is_closed()) return FILE_CLOSED~;
    if (buf.len == 0) return 0;

    return io::file_read(self.fd, buf)!;
}

fn usz? File.write(&self, char[] data) @maydiscard
{
    if (self.is_closed()) return FILE_CLOSED~;
    if (data.len == 0) return 0;

    return io::file_write(self.fd, data)!;
}

fn void? File.write_all(&self, char[] data) @maydiscard
{
    if (self.is_closed()) return FILE_CLOSED~;

    usz sent = 0;

    while (sent < data.len)
    {
        char[] part = data[sent..];

        usz n = self.write(part)!;

        if (n == 0) return FILE_CLOSED~;

        sent += n;
    }
}

fn void? File.read_exact(&self, char[] buf)
{
    if (self.is_closed()) return FILE_CLOSED~;

    usz got = 0;

    while (got < buf.len)
    {
        char[] part = buf[got..];

        usz n = self.read(part)!;

        if (n == 0) return FILE_EOF~;

        got += n;
    }
}

fn long? File.seek(&self, long offset, int whence)
{
    if (self.is_closed()) return FILE_CLOSED~;

    return io::file_seek(self.fd, offset, whence);
}

fn long? File.tell(&self)
{
    if (self.is_closed()) return FILE_CLOSED~;

    return io::file_tell(self.fd);
}

fn void? File.truncate(&self, long size) @maydiscard
{
    if (self.is_closed()) return FILE_CLOSED~;

    io::file_truncate(self.fd, size);
}

fn void? File.flush(&self) @maydiscard
{
    if (self.is_closed()) return FILE_CLOSED~;

    io::file_flush(self.fd);
}

fn long? File.size(&self)
{
    if (self.is_closed()) return FILE_CLOSED~;

    return io::file_size(self.fd);
}

fn File*? stdin()
{
    Fd fd = io::fd_stdin();

    return file_from_fd(fd, false)!;
}

fn File*? stdout()
{
    Fd fd = io::fd_stdout();

    return file_from_fd(fd, false)!;
}

fn File*? stderr()
{
    Fd fd = io::fd_stderr();

    return file_from_fd(fd, false)!;
}

// eof