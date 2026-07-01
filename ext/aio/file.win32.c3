// file.win32.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::io @if(env::WIN32) @link("ws2_32");

import c::winbase;
import c::errno;
import ext::mem;
import ext::aio;


faultdef NONE;
faultdef FILE_PATH_TOO_LONG;
faultdef FILE_INVALID_SIZE;


const sz FILE_PATH_BUFFER_SIZE = 512;
const sz MAX_WIN32_IO_SIZE = 0x7fffffff;


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
}


// UTF-8 path conversion

fn Char16*? utf8to16(String path, Char16[] wpath) @local
{
    if (path.len == 0) return errno::E_INVALID_ARG~;
    if (wpath.len == 0) return FILE_PATH_TOO_LONG~;

    Char16[] converted = path.to_utf16(tmem)!;

    if (converted.len >= wpath.len) return FILE_PATH_TOO_LONG~;

    if (converted.len > 0) {
        wpath[0:converted.len] = converted[0:converted.len];
    }

    wpath[converted.len] = 0;

    for (sz i = 0; i < converted.len; i++) {
        if (wpath[i] == (Char16)'/') {
            wpath[i] = (Char16)'\\';
        }
    }

    return &wpath[0];
}


// File loading

fn void* file_load_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    Char16[FILE_PATH_BUFFER_SIZE] path_buf;
    Char16*? path = utf8to16(arg.name, path_buf[..]);

    if (catch err = path) {
        arg.error = err;
        return v_arg;
    }

    winbase::DWord share = winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE | winbase::FILE_SHARE_DELETE;

    winbase::Handle handle = winbase::createFileW(
        path,
        winbase::GENERIC_READ,
        share,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (handle == winbase::INVALID_HANDLE_VALUE) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    defer winbase::closeHandle(handle);

    long file_size = 0;

    if (winbase::getFileSizeEx(handle, &file_size) == 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (file_size < 0) {
        arg.error = FILE_INVALID_SIZE;
        return v_arg;
    }

    sz size = (sz)file_size;

    if (size == 0) {
        arg.buf = {};
        arg.result = 0;
        return v_arg;
    }

    char[]? buf = aio::localmem.alloc_array(char, size);
    if (catch err = buf) {
        arg.error = err;
        return v_arg;
    }
    arg.buf = buf;
    
    sz total = 0;

    while (total < size) {
        sz remaining = size - total;
        winbase::DWord request_size = (winbase::DWord)(remaining > MAX_WIN32_IO_SIZE ? MAX_WIN32_IO_SIZE : remaining);
        winbase::DWord n = 0;

        int rc = winbase::readFile(handle, arg.buf[total..].ptr, request_size, &n, null);

        if (rc == 0) {
            arg.error = errno::get_fault();
            aio::localmem.free(arg.buf);

            arg.buf = {};
            arg.result = 0;

            return v_arg;
        }

        if (n == 0) break;

        total += (sz)n;
    }

    if (total == 0) {
        aio::localmem.free(arg.buf);
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

    winbase::DWord access;
    winbase::DWord disposition;

    switch (arg.mode) {
        case "r":
        case "rb":
            access = winbase::GENERIC_READ;
            disposition = winbase::OPEN_EXISTING;
        case "r+":
        case "rb+":
        case "r+b":
            access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
            disposition = winbase::OPEN_EXISTING;
        case "w":
        case "wb":
            access = winbase::GENERIC_WRITE;
            disposition = winbase::CREATE_ALWAYS;
        case "w+":
        case "wb+":
        case "w+b":
            access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
            disposition = winbase::CREATE_ALWAYS;
        case "a":
        case "ab":
            access = winbase::FILE_APPEND_DATA;
            disposition = winbase::OPEN_ALWAYS;
        case "a+":
        case "ab+":
        case "a+b":
            access = winbase::GENERIC_READ | winbase::FILE_APPEND_DATA;
            disposition = winbase::OPEN_ALWAYS;
        default:
            arg.error = errno::E_INVALID_ARG;
            return v_arg;
    }

    Char16[FILE_PATH_BUFFER_SIZE] path_buf;
    Char16*? path = utf8to16(arg.name, path_buf[..]);

    if (catch err = path) {
        arg.error = err;
        return v_arg;
    }

    winbase::DWord share = winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE | winbase::FILE_SHARE_DELETE;

    winbase::Handle handle = winbase::createFileW(
        path,
        access,
        share,
        null,
        disposition,
        winbase::FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (handle == winbase::INVALID_HANDLE_VALUE) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (arg.mode.starts_with("a")) {
        if (winbase::setFilePointerEx(handle, 0, null, winbase::FILE_END) == 0) {
            arg.error = errno::get_fault();
            winbase::closeHandle(handle);

            return v_arg;
        }
    }

    arg.fd = handle;

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

    fd_set_socket(result.fd, false);

    return result.fd;
}


// File close

fn void* file_close_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    if (winbase::closeHandle(arg.fd) == 0) {
        arg.error = errno::get_fault();
    }

    return v_arg;
}

fn void? file_close(Fd fd) @maydiscard
{
    if (fd_invalid(fd)) return;

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

    winbase::DWord method;

    switch (arg.whence) {
        case 0:
            method = winbase::FILE_BEGIN;
        case 1:
            method = winbase::FILE_CURRENT;
        case 2:
            method = winbase::FILE_END;
        default:
            arg.error = errno::E_INVALID_ARG;
            return v_arg;
    }

    long new_position = 0;

    if (winbase::setFilePointerEx(arg.fd, arg.pos, &new_position, method) == 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = new_position;

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

    long position = 0;

    if (winbase::setFilePointerEx(arg.fd, 0, &position, winbase::FILE_CURRENT) == 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = position;

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

    long old_position = 0;

    if (winbase::setFilePointerEx(arg.fd, 0, &old_position, winbase::FILE_CURRENT) == 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (winbase::setFilePointerEx(arg.fd, arg.pos, null, winbase::FILE_BEGIN) == 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (winbase::setEndOfFile(arg.fd) == 0) {
        arg.error = errno::get_fault();
        (void)winbase::setFilePointerEx(arg.fd, old_position, null, winbase::FILE_BEGIN);

        return v_arg;
    }

    if (winbase::setFilePointerEx(arg.fd, old_position, null, winbase::FILE_BEGIN) == 0) {
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

    if (winbase::flushFileBuffers(arg.fd) == 0) {
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

    long size = 0;

    if (winbase::getFileSizeEx(arg.fd, &size) == 0) {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (size < 0) {
        arg.error = FILE_INVALID_SIZE;
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

    Arg*? result = aio::run_in_executor(&file_size_blocking, &arg);

    if (catch err = result) return err~;
    if (result.error != NONE) return result.error~;

    return result.offset;
}


// File read

fn void* file_read_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    sz request_length = arg.buf.len > MAX_WIN32_IO_SIZE ? MAX_WIN32_IO_SIZE : arg.buf.len;
    winbase::DWord n = 0;

    int rc = winbase::readFile(arg.fd, arg.buf.ptr, (winbase::DWord)request_length, &n, null);

    if (rc == 0) {
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
        sz request_length = remaining.len > MAX_WIN32_IO_SIZE ? MAX_WIN32_IO_SIZE : remaining.len;
        winbase::DWord n = 0;

        int rc = winbase::writeFile(arg.fd, remaining.ptr, (winbase::DWord)request_length, &n, null);

        if (rc == 0) {
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
    winbase::Handle handle = winbase::createFileA(
        "CONIN$",
        winbase::GENERIC_READ,
        winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (handle != winbase::INVALID_HANDLE_VALUE) {
        fd_set_socket(handle, false);
    }

    return handle;
}

fn Fd fd_stdout()
{
    winbase::Handle handle = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (handle != winbase::INVALID_HANDLE_VALUE) {
        fd_set_socket(handle, false);
    }

    return handle;
}

fn Fd fd_stderr()
{
    winbase::Handle handle = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (handle != winbase::INVALID_HANDLE_VALUE) {
        fd_set_socket(handle, false);
    }

    return handle;
}

// eof