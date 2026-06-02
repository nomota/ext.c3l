// file.win32.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::io @if(env::WIN32) @link("ws2_32");

import std::io;
import c::stdio;
import c::stdlib;
import c::string;
import c::winbase;
import c::errno;
import ext::debug;
import ext::mem;
import ext::aio;

faultdef NONE;

struct Arg @local
{
    fault error;
    Fd fd;
    String name;
    String mode;
    long pos;
    int whence;
    long offset;
    int rc;
    char[] buf;
    sz result;
}

fn Char16*? utf8to16(String path, Char16[] wpath) @private
{
    if (path.len == 0) return errno::E_INVALID_ARG~;

    Char16[] p2 = path.to_utf16(tmem)!;

    if (p2.len >= wpath.len - 1) return errno::E_INVALID_ARG~;

    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;

    for (sz i = 0; i < p2.len; i++)
    {
        if (p2[i] == (Char16)'/')
        {
            wpath[i] = (Char16)'\\';
        }
    }

    return wpath.ptr;
}

fn void* file_open_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    winbase::DWord access = 0;
    winbase::DWord disposition = 0;
    winbase::DWord attributes = winbase::FILE_ATTRIBUTE_NORMAL;

    if (arg.mode == "r")
    {
        access = winbase::GENERIC_READ;
        disposition = winbase::OPEN_EXISTING;
    }
    else if (arg.mode == "r+")
    {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::OPEN_EXISTING;
    }
    else if (arg.mode == "w")
    {
        access = winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    }
    else if (arg.mode == "w+")
    {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    }
    else if (arg.mode == "a")
    {
        access = winbase::FILE_APPEND_DATA;
        disposition = winbase::OPEN_ALWAYS;
    }
    else if (arg.mode == "a+")
    {
        access = winbase::GENERIC_READ | winbase::FILE_APPEND_DATA;
        disposition = winbase::OPEN_ALWAYS;
    }
    else
    {
        arg.error = errno::E_INVALID_ARG;
        return v_arg;
    }

    winbase::DWord share = winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE | winbase::FILE_SHARE_DELETE;

    Char16[260] wbuf;
    Char16*? wpath = utf8to16(arg.name, &wbuf);
    if (catch err = wpath)
    {
        arg.error = err;
        return v_arg;
    }

    winbase::Handle h = winbase::createFileW(
        wpath,
        access,
        share,
        null,
        disposition,
        attributes,
        null
    );

    if (h == winbase::INVALID_HANDLE_VALUE)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (arg.mode[0] == 'a')
    {
        winbase::setFilePointerEx(h, 0, null, winbase::FILE_END);
    }

    arg.fd = h;

    return v_arg;
}

fn Fd? file_open(String name, String mode, int permission = 0o644)
{
    Arg arg = {
        .error = NONE,
        .name = name,
        .mode = mode,
    };
    
    Arg*? a = aio::run_in_executor(&file_open_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    fd_set_socket(a.fd, false);
    
    return a.fd;
}

fn void* file_close_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    int rc = winbase::closeHandle(arg.fd);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.rc = rc;

    return v_arg;
}

fn void? file_close(Fd fd) @maydiscard
{
    if (fd_invalid(fd)) return;

    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_close_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* file_seek_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    winbase::DWord method;

    switch (arg.whence)
    {
      case 0: method = winbase::FILE_BEGIN;
      case 1: method = winbase::FILE_CURRENT;
      case 2: method = winbase::FILE_END;
      default:
        arg.error = errno::E_INVALID_ARG;
        return v_arg;
    }

    long new_pos = 0;
    int rc = winbase::setFilePointerEx(arg.fd, arg.pos, &new_pos, method);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = new_pos;

    return v_arg;
}

fn long? file_seek(Fd fd, long pos, int whence) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
        .pos = pos,
        .whence = whence,
    };
    
    Arg*? a = aio::run_in_executor(&file_seek_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.offset;
}

fn void* file_tell_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long pos = 0;
    int rc = winbase::setFilePointerEx(arg.fd, 0, &pos, winbase::FILE_CURRENT);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = pos;

    return v_arg;
}

fn long? file_tell(Fd fd)
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };
    
    Arg*? a = aio::run_in_executor(&file_tell_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.offset;
}

fn void* file_truncate_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long old_pos = 0;

    int rc = winbase::setFilePointerEx(arg.fd, 0, &old_pos, winbase::FILE_CURRENT);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    rc = winbase::setFilePointerEx(arg.fd, arg.pos, null, winbase::FILE_BEGIN);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    rc = winbase::setEndOfFile(arg.fd);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    (void)winbase::setFilePointerEx(arg.fd, old_pos, null, winbase::FILE_BEGIN);

    return v_arg;
}

fn void? file_truncate(Fd fd, long pos) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
        .pos = pos,
    };
    
    Arg*? a = aio::run_in_executor(&file_truncate_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* file_flush_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    int rc = winbase::flushFileBuffers(arg.fd);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    return v_arg;
}

fn void? file_flush(Fd fd) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_flush_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* file_size_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long size = 0;
    int rc = winbase::getFileSizeEx(arg.fd, &size);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = size;

    return v_arg;
}

fn long? file_size(Fd fd)
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_size_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.offset;
}

fn void* file_read_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    winbase::DWord n = 0;

    int rc = winbase::readFile(
        arg.fd,
        arg.buf.ptr,
        (winbase::DWord)arg.buf.len,
        &n,
        null
    );

    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.result = (sz)n;

    return v_arg;
}

fn sz? file_read(Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    Arg arg = {
        .error = NONE,
        .fd = fd,
        .buf = buf,
    };

    Arg*? a = aio::run_in_executor(&file_read_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.result;
}

fn void* file_write_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    sz total = 0;

    while (total < arg.buf.len)
    {
        winbase::DWord n = 0;

        int rc = winbase::writeFile(
            arg.fd,
            arg.buf.ptr + total,
            (winbase::DWord)(arg.buf.len - total),
            &n,
            null
        );

        if (rc == 0)
        {
            arg.error = errno::get_fault();
            arg.result = total;
            return v_arg;
        }

        if (n == 0) break;

        total += (sz)n;
    }

    arg.result = total;

    return v_arg;
}

fn sz? file_write(Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    Arg arg = {
        .error = NONE,
        .fd = fd,
        .buf = buf,
    };

    Arg*? a = aio::run_in_executor(&file_write_blocking, &arg);

    if (catch err = a) return err~;

    if (a.error != NONE)
    {
        if (a.result > 0) return a.result;
        return a.error~;
    }

    return a.result;
}

fn Fd fd_stdin()
{
    winbase::Handle h = winbase::createFileA(
        "CONIN$",
        winbase::GENERIC_READ,
        winbase::FILE_SHARE_READ,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    fd_set_socket(h, false);

    return h;
}

fn Fd fd_stdout()
{
    winbase::Handle h = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    fd_set_socket(h, false);

    return h;
}

fn Fd fd_stderr()
{
    winbase::Handle h = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );
    
    fd_set_socket(h, false);

    return h;
}
