// file.posix.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::io @if(env::POSIX);

import std::io;
import c::stdlib;
import c::unistd;
import c::fcntl;
import c::string;
import c::errno;
import c::sys::stat;
import ext::debug;
import ext::mem;

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
    char[] buf;
    sz result;
    int permission;
}

fn char* str2cptr(String str, char[] buf) @inline @private
{
    sz len = (str.len <= buf.len-1)? str.len: buf.len-1;
    buf[0:len] = str[0:len];
    buf[len] = 0;
    return &buf[0];
}

fn void* file_open_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;
    
    char[256] buf;
    char* path_cstr = str2cptr(arg.name, &buf);
    
    int flags = 0;
    switch (arg.mode)
    {
      case "r": flags = fcntl::O_RDONLY;
      case "r+": flags = fcntl::O_RDWR;
      case "w": flags = fcntl::O_WRONLY | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "w+": flags = fcntl::O_RDWR | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "a": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_WRONLY;
      case "a+": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_RDWR;
      default:  
          arg.error = errno::E_INVALID_ARG;
          return v_arg;
    }

    Fd fd = fcntl::open(path_cstr, flags, arg.permission);
    if (fd < 0) 
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    
    arg.fd = fd;

    return v_arg;
}

fn Fd? file_open(String name, String mode, int permission = 0o0644)
{
    Arg arg = {
        .error = NONE,
        .name = name,
        .mode = mode,
        .permission = permission,
    };
    
    Arg*? a = aio::run_in_executor(&file_open_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.fd;
}

fn void* file_close_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    int rc = unistd::close(arg.fd);
    if (rc < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    
    return v_arg;
}

fn void? file_close(Fd fd) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_close_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

// off_t = long

fn void* file_seek_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;
    
    long offset = unistd::lseek(arg.fd, arg.pos, arg.whence);
    if (offset < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    arg.offset = offset;
    
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
    
    long offset = unistd::lseek(arg.fd, 0, unistd::SEEK_CUR);
    if (offset < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    arg.offset = offset;
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
    
    int rc = unistd::ftruncate(arg.fd, arg.pos);
    if (rc < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    
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

    int rc = unistd::fsync(arg.fd);
    if (rc < 0)
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

    stat::Stat_t st;
    int rc = stat::fstat(arg.fd, &st);
    if (rc < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = (long)st.st_size;

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

    sz n = unistd::read(arg.fd, arg.buf.ptr, arg.buf.len);
    if (n < 0)
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
        sz n = unistd::write(arg.fd, arg.buf.ptr + total, arg.buf.len - total);

        if (n > 0)
        {
            total += (sz)n;
            continue;
        }

        if (n == 0)
        {
            break;
        }

        arg.error = errno::get_fault();
        arg.result = total;

        return v_arg;
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
    set_nonblocking(0);
    return 0;
}

fn Fd fd_stdout()
{
    set_nonblocking(1);
    return 1;
}

fn Fd fd_stderr()
{
    set_nonblocking(2);
    return 2;
}

// eof