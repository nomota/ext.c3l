// buffered.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import ext::mem;
import c::string;

faultdef BUFFER_TOO_SMALL;

const usz DEFAULT_BUFFER_SIZE @private = 8192;

struct BufferedStream
{
    Stream* stream;

    char[] buf;
    usz start;
    usz end;

    bool owns_stream;
    bool closed;
}

fn BufferedStream*? buffered_new(Stream* stream, usz buffer_size = DEFAULT_BUFFER_SIZE, bool owns_stream = false)
{
    if (stream == null) return INVALID_ARG~;
    if (buffer_size == 0) buffer_size = DEFAULT_BUFFER_SIZE;

    BufferedStream* bs = localmem.alloc(BufferedStream)!;
    char[] buf = localmem.alloc_array(char, buffer_size)!;
    *bs = {
        .stream = stream,
        .buf = buf,
        .start = 0,
        .end = 0,
        .owns_stream = owns_stream,
        .closed = false,
    };

    return bs;
}

fn void BufferedStream.free(&self)
{
    if (self.buf.len > 0)
    {
        localmem.free(self.buf);
        self.buf = {};
    }

    if (self.owns_stream && self.stream != null)
    {
        self.stream.close();
        self.stream.free();
        self.stream = null;
    }

    localmem.free(self);
}

fn bool BufferedStream.is_closed(&self) @inline
{
    return self.closed || self.stream == null;
}

fn usz BufferedStream.available(&self) @inline
{
    return self.end - self.start;
}

fn char[] BufferedStream.pending(&self) @inline
{
    return self.buf[self.start:self.available()];
}

fn void BufferedStream.compact(&self)
{
    if (self.start == 0) return;

    usz n = self.available();

    if (n > 0)
    {
        string::memmove(self.buf.ptr, self.buf.ptr + self.start, n);
    }

    self.start = 0;
    self.end = n;
}

fn usz? BufferedStream.fill(&self)
{
    if (self.is_closed()) return CLOSED~;

    if (self.start > 0 && (self.end == self.buf.len || self.start >= self.buf.len / 2))
    {
        self.compact();
    }
    
    if (self.end == self.buf.len)
    {
        return BUFFER_TOO_SMALL~;
    }

    char[] dst = self.buf[self.end..];

    usz n = self.stream.read(dst)!;

    if (n > 0) self.end += n;

    return n;
}

fn usz? BufferedStream.read(&self, char[] out)
{
    if (self.is_closed()) return CLOSED~;
    if (out.len == 0) return 0;

    usz copied = 0;

    while (copied < out.len)
    {
        usz avail = self.available();

        if (avail == 0)
        {
            usz n = self.fill()!;

            if (n == 0) break;

            avail = self.available();
        }

        usz want = out.len - copied;
        usz take = avail;

        if (take > want) take = want;

        string::memcpy(out.ptr + copied, self.buf.ptr + self.start, take);

        self.start += take;
        copied += take;

        if (copied > 0) break;
    }

    return copied;
}

fn void? BufferedStream.read_exact(&self, char[] out)
{
    usz got = 0;

    while (got < out.len)
    {
        usz n = self.read(out[got..])!;

        if (n == 0) return CLOSED~;

        got += n;
    }
}

fn isz find_bytes(char[] haystack, String needle) @private
{
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return -1;

    usz limit = haystack.len - needle.len;

    for (usz i = 0; i <= limit; i++)
    {
        bool matched = true;

        for (usz j = 0; j < needle.len; j++)
        {
            if (haystack[i + j] != needle[j])
            {
                matched = false;
                break;
            }
        }

        if (matched) return (isz)i;
    }

    return -1;
}

fn usz? BufferedStream.read_until(&self, char[] out, String delim)
{
    if (self.is_closed()) return CLOSED~;
    if (delim.len == 0) return INVALID_STATE~;

    usz written = 0;

    while (true)
    {
        char[] pending = self.pending();

        isz pos = find_bytes(pending, delim);

        if (pos >= 0)
        {
            usz take = (usz)pos + delim.len;

            if (written + take > out.len) return BUFFER_TOO_SMALL~;

            string::memcpy(out.ptr + written, self.buf.ptr + self.start, take);

            self.start += take;
            written += take;

            return written;
        }

        usz keep = 0;

        if (delim.len > 1 && pending.len >= delim.len - 1)
        {
            keep = delim.len - 1;
        }
        else if (delim.len > 1)
        {
            keep = pending.len;
        }

        usz take = pending.len - keep;

        if (take > 0)
        {
            if (written + take > out.len) return BUFFER_TOO_SMALL~;

            string::memcpy(out.ptr + written, self.buf.ptr + self.start, take);

            self.start += take;
            written += take;
        }

        usz n = self.fill()!;

        if (n == 0)
        {
            pending = self.pending();

            if (pending.len > 0)
            {
                if (written + pending.len > out.len) return BUFFER_TOO_SMALL~;

                string::memcpy(out.ptr + written, self.buf.ptr + self.start, pending.len);

                self.start += pending.len;
                written += pending.len;
            }

            return written;
        }
    }
}

fn usz? BufferedStream.read_line(&self, char[] out)
{
    return self.read_until(out, "\n");
}

fn usz? BufferedStream.read_crlf_line(&self, char[] out)
{
    return self.read_until(out, "\r\n");
}

fn usz? BufferedStream.write(&self, char[] data) @maydiscard
{
    if (self.is_closed()) return CLOSED~;

    return self.stream.write(data[..]);
}

fn void? BufferedStream.write_all(&self, char[] data) @maydiscard
{
    if (self.is_closed()) return CLOSED~;

    self.stream.write_all(data[..])!;
}

fn void? BufferedStream.flush(&self) @maydiscard
{
    if (self.is_closed()) return CLOSED~;
}

fn void BufferedStream.close(&self)
{
    if (self.closed) return;

    self.closed = true;

    if (self.stream != null)
    {
        self.stream.close();
    }
}

// eof