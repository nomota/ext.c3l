// aiofiles.c3

// async file io on top of `asyncio`

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiofiles;

import std::io;
import std::collections::list;
import ext::debug;
import ext::mem;
import ext::asyncio;
import c::stdlib;
import c::string;
import c::errno;

faultdef NONE, OPEN_FAILED,
    CLOSED,
    READ_ERROR,
    WRITE_ERROR,
    SEEK_ERROR;

const usz READ_BUF_SIZE  = 4 * 1024;

struct AioFile {
    int fd;
    bool closed;
    bool eof;
    fault error;
    
    char[READ_BUF_SIZE] rbuf;
    usz rbuf_start;
    usz rbuf_end;
}

fn AioFile? open(String path, String mode = "r")
{
    int fd = asyncio::open_file(path, mode)!;

    return { 
        .fd = fd,
        .closed = false,
        .eof = false,
        .error = NONE,
        .rbuf_start = 0,
        .rbuf_end = 0,
    };
}

fn usz? file_size(String path)
{
    AioFile f = open(path)!;
    defer f.close();
    return f.size();
}

fn void AioFile.close(&self) 
{
    if (self.closed) return;

    asyncio::close_file(self.fd);
    
    self.closed = true;
}

fn usz? AioFile.write(&self, char[] buf)
{
    if (self.closed) return CLOSED~;
    
    usz n = asyncio::async_write(self.fd, buf.ptr, buf.len)!;
    
    return n;
}

<*
  use this if you are calling .seek() and .tell()
  default .read() and others do buffering, loosing exact position
*>
fn usz? AioFile.read_unbuffered(&self, char[] buf)
{
    if (self.closed) return CLOSED~;
    
    usz n = asyncio::async_read(self.fd, buf.ptr, buf.len)!;
    
    return n;
}


macro AioFile.writef(&self, String fmt, args...) 
{
    DString str; str.init(mem);
    defer str.free();
    str.appendf(fmt, ...args);

    return self.write((char[])str.str_view());
}

fn bool AioFile.at_eof(&self) @inline 
{
    return self.eof && self.rbuf_start == self.rbuf_end;
}

fn bool AioFile.fill(&self) @inline
{
    if (self.eof) return false;

    if (self.rbuf_start > 0) {
        usz remaining = self.rbuf_end - self.rbuf_start;
        if (remaining > 0) {
            string::memmove(&self.rbuf[0], &self.rbuf[self.rbuf_start], remaining);
        }
        self.rbuf_end = remaining;
        self.rbuf_start = 0;
    }

    if (self.rbuf_end >= READ_BUF_SIZE) return true;

    usz? n = asyncio::async_read(self.fd, &self.rbuf[self.rbuf_end], READ_BUF_SIZE - self.rbuf_end);
    if (catch err = n) {
        self.error = err;
        return false;
    }

    if (n > 0)  { 
        self.rbuf_end += (usz)n; 
        return true; 
    }
    if (n == 0) { self.eof = true; }
    return false;
}

fn usz AioFile.available(&self) @inline
{
    return self.rbuf_end - self.rbuf_start;
}

fn usz? AioFile.read(&self, char[] buf) 
{
    usz got = 0;
    char* dst = buf.ptr;
    while (got < buf.len) {
        while (self.available() == 0) {
            if (self.eof) return got;
            if (!self.fill()) return got;
        }
        if (self.error != NONE) {
            return self.error~;
        }
        usz take = buf.len - got;
        if (take > self.available()) take = self.available();
        string::memcpy(dst + got, &self.rbuf[self.rbuf_start], take);
        self.rbuf_start += take;
        got += take;
    }
    return got;
}

fn usz? AioFile.read_any(&self, char[] buf) 
{
    if (self.available() == 0) {
        if (self.eof) return 0;
        self.fill();
        if (self.available() == 0) return 0;
    }
    if (self.error != NONE) {
        return self.error~;
    }

    usz take = buf.len < self.available() ? buf.len : self.available();
    string::memcpy(buf.ptr, &self.rbuf[self.rbuf_start], take);
    self.rbuf_start += take;
    return take;
}

fn usz? AioFile.read_until(&self, char delim, char[] buf) 
{
    usz total = 0;
    char* dst = buf.ptr;
    while (total < buf.len) {
        while (self.available() == 0) {
            if (self.eof) return total;
            if (!self.fill()) return total;
        }

        if (self.error != NONE) {
            return self.error~;
        }

        char c = self.rbuf[self.rbuf_start++];
        dst[total++] = c;
        if (c == delim) return total;
    }
    return total;
}

fn usz? AioFile.readline(&self, char[] buf) 
{
    if (buf.len == 0) return 0;
    usz len = self.read_until('\n', buf[0:buf.len - 1])!;
    if (len == 0) return 0;
    if (len >= 2 && buf[len-2] == '\r') {
        buf[len-2] = '\0';
        return len - 2;
    }
    buf[len-1] = '\0';
    return len - 1;
}

fn void AioFile.flush(&self)
{
    asyncio::io_flush(self.fd);
}

fn long AioFile.seek(&self, long offset, int whence)
{
    return asyncio::io_seek(self.fd, offset, whence);
}

fn long AioFile.tell(&self)
{
    return asyncio::io_tell(self.fd);
}

fn void AioFile.truncate(&self, long size)
{
    asyncio::io_truncate(self.fd, size);
}

fn usz AioFile.size(&self)
{
    return (usz)asyncio::io_size(self.fd);
}

fn AioFile stdin()
{
    int fd = asyncio::io_stdin();
    return { .fd = fd, .closed = false };
}

fn AioFile stdout()
{
    int fd = asyncio::io_stdout();
    return { .fd = fd, .closed = false };
}

fn AioFile stderr()
{
    int fd = asyncio::io_stderr();
    return { .fd = fd, .closed = false };
}
