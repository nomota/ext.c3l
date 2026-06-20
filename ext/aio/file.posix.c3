// file.posix.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::io @if(env::POSIX);

import c::unistd;
import c::fcntl;
import c::errno;
import c::sys::stat;
import ext::mem;


faultdef NONE;
faultdef FILE_PATH_TOO_LONG;
faultdef FILE_INVALID_SIZE;


const sz FILE_PATH_BUFFER_SIZE = 512;


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


// String helpers

fn char*? str2cptr(String str, char[] buf) @inline @local
{
    if (buf.len == 0) return FILE_PATH_TOO_LONG~;
    if (str.len >= buf.len) return FILE_PATH_TOO_LONG~;

    if (str.len > 0) {
        buf[0:str.len] = str[0:str.len];
    }

    buf[str.len] = 0;

    return &buf[0];
}


// File loading

fn void* file_load_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    char[FILE_PATH_BUFFER_SIZE] path_buf;
    char*? path_cstr = str2cptr(arg.name, path_buf[..]);

    if (catch err = path_cstr) {
        arg.error = err;
        return v_arg;
    }

    Fd fd = fcntl::open(path_cstr, fcntl::O_RDONLY, 0);

    if (fd < 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    defer unistd::close(fd);

    stat::Stat_t st;

    if (stat::fstat(fd, &st) < 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (st.st_size < 0) {
        arg.error = FILE_INVALID_SIZE;
        return v_arg;
    }

    sz size = (sz)st.st_size;

    if (size == 0) {
        arg.buf = {};
        arg.result = 0;
        return v_arg;
    }

    arg.buf = localmem.alloc_array(char, size)!;

    sz total = 0;

    while (total < size) {
        sz n = unistd::read(fd, arg.buf[total..].ptr, size - total);

        if (n < 0) {
            arg.error = errno::get_fault();
            localmem.free(arg.buf);
            arg.buf = {};
            arg.result = 0;

            return v_arg;
        }

        if (n == 0) break;

        total += n;
    }

    if (total == 0) {
        localmem.free(arg.buf);
        arg.buf = {};
    } else if (total < size) {
        arg.buf = arg.buf[0:total];
    }

    arg.result = total;

    return v_arg;
}

fn char[]? file_load(String name)
{
    Arg arg = {
        .error = NONE,
        .name = name,
    };

    Arg*? result = aio::run_in_executor(&file_load_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.buf;
}


// File open

fn void* file_open_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    char[FILE_PATH_BUFFER_SIZE] path_buf;
    char*? path_cstr = str2cptr(arg.name, path_buf[..]);

    if (catch err = path_cstr) {
        arg.error = err;
        return v_arg;
    }

    int flags;

    switch (arg.mode) {
        case "r":
        case "rb":
            flags = fcntl::O_RDONLY;

        case "r+":
        case "rb+":
        case "r+b":
            flags = fcntl::O_RDWR;

        case "w":
        case "wb":
            flags = fcntl::O_WRONLY | fcntl::O_CREAT | fcntl::O_TRUNC;

        case "w+":
        case "wb+":
        case "w+b":
            flags = fcntl::O_RDWR | fcntl::O_CREAT | fcntl::O_TRUNC;

        case "a":
        case "ab":
            flags = fcntl::O_WRONLY | fcntl::O_CREAT | fcntl::O_APPEND;

        case "a+":
        case "ab+":
        case "a+b":
            flags = fcntl::O_RDWR | fcntl::O_CREAT | fcntl::O_APPEND;

        default:
            arg.error = errno::E_INVALID_ARG;
            return v_arg;
    }

    Fd fd = fcntl::open(path_cstr, flags, arg.permission);

    if (fd < 0) {
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

    Arg*? result = aio::run_in_executor(&file_open_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.fd;
}


// File close

fn void* file_close_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    if (unistd::close(arg.fd) < 0) {
        arg.error = errno::get_fault();
    }

    return v_arg;
}

fn void? file_close(Fd fd) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? result = aio::run_in_executor(&file_close_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;
}


// File seek

fn void* file_seek_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long offset = unistd::lseek(arg.fd, arg.pos, arg.whence);

    if (offset < 0) {
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

    Arg*? result = aio::run_in_executor(&file_seek_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.offset;
}


// File position

fn void* file_tell_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long offset = unistd::lseek(arg.fd, 0, unistd::SEEK_CUR);

    if (offset < 0) {
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

    Arg*? result = aio::run_in_executor(&file_tell_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.offset;
}


// File truncate

fn void* file_truncate_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    if (unistd::ftruncate(arg.fd, arg.pos) < 0) {
        arg.error = errno::get_fault();
    }

    return v_arg;
}

fn void? file_truncate(Fd fd, long pos) @maydiscard
{
    if (pos < 0) return errno::E_INVALID_ARG~;

    Arg arg = {
        .error = NONE,
        .fd = fd,
        .pos = pos,
    };

    Arg*? result = aio::run_in_executor(&file_truncate_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;
}


// File flush

fn void* file_flush_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    if (unistd::fsync(arg.fd) < 0) {
        arg.error = errno::get_fault();
    }

    return v_arg;
}

fn void? file_flush(Fd fd) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? result = aio::run_in_executor(&file_flush_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;
}


// File size

fn void* file_size_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    stat::Stat_t st;

    if (stat::fstat(arg.fd, &st) < 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (st.st_size < 0) {
        arg.error = FILE_INVALID_SIZE;
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

    Arg*? result = aio::run_in_executor(&file_size_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.offset;
}


// File read

fn void* file_read_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    sz n = unistd::read(arg.fd, arg.buf.ptr, arg.buf.len);

    if (n < 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.result = n;

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

    Arg*? result = aio::run_in_executor(&file_read_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.result;
}


// File write

fn void* file_write_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    sz total = 0;

    while (total < arg.buf.len) {
        char[] remaining = arg.buf[total..];
        sz n = unistd::write(arg.fd, remaining.ptr, remaining.len);

        if (n > 0) {
            total += n;
            continue;
        }

        if (n == 0) break;

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

    Arg*? result = aio::run_in_executor(&file_write_blocking, &arg);

    if (catch err = result) return err~;

    if (result.error != NONE) {
        if (result.result > 0) return result.result;

        return result.error~;
    }

    return result.result;
}


// Standard descriptors

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