// stream.c3

module ext::asyncio;

import std::io;

import c::stdlib;
import c::string;
import c::errno;
import ext::debug;
import ext::mem;

const usz READ_BUF_SIZE  = 4 * 1024;

struct Stream {
    int fd;
    bool eof;
    fault error;
    bool closed;
    
    char[READ_BUF_SIZE] rbuf;
    usz rbuf_start;
    usz rbuf_end;
    
    Stream* reader; // python StreamReader
    Stream* writer; // python StreamWriter
}

fn Stream* stream_new(int fd) @private
{
    Stream* s = mem_alloc(Stream);
    *s = {};
    s.fd = fd;
    s.eof = false;
    s.closed = false;
    s.error = NONE;
    s.rbuf_start = 0;
    s.rbuf_end = 0;
    s.reader = s;
    s.writer = s;
    
    set_nonblocking(fd);
    
    return s;
}

// close() calls _free()
fn void Stream._free(&self) 
{
    mem_free(self);
}

fn bool Stream.at_eof(&self) @inline 
{
    return self.eof && self.rbuf_start == self.rbuf_end;
}

faultdef EOF;

fn bool? Stream.fill(&self) @inline
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

    usz? n = async_read(self.fd, &self.rbuf[self.rbuf_end], READ_BUF_SIZE - self.rbuf_end);
    if (catch err = n) {
        self.error = err;
        return err~;
    }
    
    if (n > 0)  { 
        self.rbuf_end += (usz)n; 
        return true; 
    }
    if (n == 0) { self.eof = true; }
    return EOF~;
}

fn usz Stream.available(&self) @inline
{
    return self.rbuf_end - self.rbuf_start;
}

fn usz? Stream.read(&self, char[] buf) 
{
    usz got = 0;
    char* dst = buf.ptr;
    while (got < buf.len) {
        while (self.available() == 0) {
            if (self.eof) return got;
            if (!self.fill()!) return got;
        }
        usz take = buf.len - got;
        if (take > self.available()) take = self.available();
        string::memcpy(dst + got, &self.rbuf[self.rbuf_start], take);
        self.rbuf_start += take;
        got += take;
    }
    return got;
}

fn usz? Stream.read_any(&self, char[] buf) 
{
    if (self.available() == 0) {
        if (self.eof) return 0;
        self.fill()!;
        if (self.available() == 0) return 0;
    }
    usz take = buf.len < self.available() ? buf.len : self.available();
    string::memcpy(buf.ptr, &self.rbuf[self.rbuf_start], take);
    self.rbuf_start += take;
    return take;
}

fn usz? Stream.read_until(&self, char delim, char[] buf) 
{
    usz total = 0;
    char* dst = buf.ptr;
    while (total < buf.len) {
        while (self.available() == 0) {
            if (self.eof) return total;
            if (!self.fill()!) return total;
        }
        char c = self.rbuf[self.rbuf_start++];
        dst[total++] = c;
        if (c == delim) return total;
    }
    return total;
}

fn usz? Stream.readline(&self, char[] buf) 
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

fn bool? Stream.read_u32be(&self, uint* out)
{
    char[4] buf;
    if (self.read(&buf)! < 4) return false;
    *out = ((uint)buf[0] << 24) | ((uint)buf[1] << 16) | ((uint)buf[2] <<  8) | (uint)buf[3];
    return true;
}

fn usz? Stream.write(&self, char[] buf) 
{
    usz? n = async_write(self.fd, buf.ptr, buf.len);
    if (catch err = n) {
        self.error = err;
        return 0;
    }
    return n;
}


fn usz? Stream.write_u32be(&self, uint v) 
{
    char[4] buf = {
        (char)((v >> 24) & 0xFF), (char)((v >> 16) & 0xFF),
        (char)((v >>  8) & 0xFF), (char)( v        & 0xFF),
    };
    return self.write(&buf)!;
}

macro Stream.writef(&self, String fmt, args...) 
{
    DString str; str.init(_allox);
    defer str.free();
    str.appendf(fmt, ...args);

    return self.write((char[])str.str_view())!;
}

fn Stream* open_pipe(int pipe_fd) 
{
    return stream_new(pipe_fd);
}

fn Stream*? open_file_stream(String path, String mode)
{
    int fd = open_file(path, mode)!;
    
    if (fd < 0) return errno::get_fault()~;

    return stream_new(fd);
}

fn void Stream.close(&self) 
{
    if (self.closed) return;
    self.closed = true;
    
    close_file(self.fd);

    self._free();
}


module ext::asyncio @if(!env::WIN32);

import c::string;
import c::fcntl;
import c::unistd;
import c::errno;


fn Stream* stdin_stream() 
{
    return stream_new(0);
}

fn Stream* stdout_stream() 
{
    return stream_new(1);
}

fn Stream* stderr_stream() 
{
    return stream_new(2);
}


module ext::asyncio @if(env::WIN32);

import c::winbase;
import c::winsock2;


fn Stream* stdin_stream() 
{
    winbase::Handle h = winbase::getStdHandle(winbase::STD_INPUT_HANDLE);
    return stream_new((int)(iptr)h);
}

fn Stream* stdout_stream() 
{
    winbase::Handle h = winbase::getStdHandle(winbase::STD_OUTPUT_HANDLE);
    return stream_new((int)(iptr)h);
}

fn Stream* stderr_stream() 
{
    winbase::Handle h = winbase::getStdHandle(winbase::STD_ERROR_HANDLE);
    return stream_new((int)(iptr)h);
}
