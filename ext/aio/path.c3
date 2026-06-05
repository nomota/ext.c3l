// path.c3

// async path operations on top of `aio`

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::path;

import std::collections::list;
import std::io;
import c::string;
import c::stdlib;
import ext::debug;
import ext::mem;
import ext::aio;
import ext::aio::io;
import ext::io::stat;
import ext::io::dir;
import ext::io::cfile;

faultdef NONE;

struct Stat
{
    long st_mtime;
    long st_size;
}

struct Arg @local
{
    String path;
    String path2;

    Stat stat;
    fault error;

    uint mode;
    bool exist_ok;

    sz n;
    sz size;

    Allocator allocx;
    List{String} files;

    char[] buf;

    bool exists;
    bool isfile;
    bool isdir;
    bool islink;
}

faultdef STAT_FILE_NOT_FOUND;

fn void* _stat(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (!stat::exists(a.path))
    {
        a.error = STAT_FILE_NOT_FOUND;
        return (void*)a;
    }

    long? size = stat::size(a.path);
    if (catch err = size)
    {
        a.error = err;
        return (void*)a;
    }
    
    long? mtime = stat::last_modified(a.path);
    if (catch err = mtime)
    {
        a.error = err;
        return (void*)a;
    }

    a.stat = {
        .st_size = size,
        .st_mtime = mtime,
    };

    return (void*)a;
}

fn Stat? stat(String path)
{
    Arg arg = {
        .path = path,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_stat, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.stat;
}

fn void* _rename(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (catch err = cfile::rename(a.path, a.path2))
    {
        a.error = err;
    }

    return (void*)a;
}

fn void? rename(String path, String path2) @maydiscard
{
    Arg arg = {
        .path = path,
        .path2 = path2,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_rename, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _replace(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (cfile::exists(a.path2))
    {
        if (catch err = cfile::remove(a.path2))
        {
            a.error = err;
            return (void*)a;
        }
    }

    if (catch err = cfile::rename(a.path, a.path2))
    {
        a.error = err;
        return (void*)a;
    }

    return (void*)a;
}

fn void? replace(String path, String path2) @maydiscard
{
    Arg arg = {
        .path = path,
        .path2 = path2,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_replace, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _remove(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (catch err = cfile::remove(a.path))
    {
        a.error = err;
        return (void*)a;
    }

    return (void*)a;
}

fn void? remove(String path) @maydiscard
{
    Arg arg = {
        .path = path,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_remove, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn sz? sendfile(Fd to_sock, Fd from_fd, long offset, long count)
{
    if (count <= 0) return 0;

    io::file_seek(from_fd, offset, 0)!;

    sz written = 0;

    while (written < count)
    {
        char[1024] buf;

        sz remaining = (sz)count - written;
        sz want = remaining < (sz)buf.len ? remaining : (sz)buf.len;

        sz n = io::file_read(from_fd, buf[0:want])!;
        if (n == 0) break;

        sz m = io::async_write(to_sock, buf[0:n])!;
        if (m == 0) break;

        written += m;
    }

    return written;
}

fn void* _mkdir(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (catch err = dir::make_dir(a.path, false, a.mode))
    {
        a.error = err;
        return (void*)a;
    }

    return (void*)a;
}

fn void? mkdir(String path, uint mode = 0o777) @maydiscard
{
    Arg arg = {
        .path = path,
        .mode = mode,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_mkdir, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

faultdef MKDIR_FILE_EXIST;

fn void* _makedirs(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (dir::exists(a.path))
    {
        if (!a.exist_ok) a.error = MKDIR_FILE_EXIST;
        return (void*)a;
    }

    if (catch err = dir::make_dir(a.path, true, a.mode))
    {
        a.error = err;
        return (void*)a;
    }

    return (void*)a;
}

fn void? makedirs(String path, uint mode = 0o777, bool exist_ok = true) @maydiscard
{
    Arg arg = {
        .path = path,
        .mode = mode,
        .exist_ok = exist_ok,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_makedirs, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

faultdef RMDIR_FILE_NOT_FOUND;

fn void* _removedirs(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (!dir::exists(a.path))
    {
        a.error = RMDIR_FILE_NOT_FOUND;
        return (void*)a;
    }

    String path = a.path;

    while (path.len > 0)
    {
        List{String}? files = dir::list_dir(mem, path);
        if (catch err = files)
        {
            a.error = err;
            return (void*)a;
        }

        if (files.len() > 0)
        {
            files.free();
            return (void*)a;
        }

        files.free();

        if (catch err = dir::remove_dir(path))
        {
            a.error = err;
            return (void*)a;
        }

        sz idx;

        sz? slash = path.rindex_of_char('/');
        if (catch err = slash)
        {
            sz? backslash = path.rindex_of_char('\\');
            if (catch err2 = backslash)
            {
                return (void*)a;
            }

            idx = backslash;
        }
        else
        {
            idx = slash;
        }

        path = path[0:idx];
    }

    return (void*)a;
}

fn void? removedirs(String path) @maydiscard
{
    Arg arg = {
        .path = path,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_removedirs, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _listdir(void* arg) @local
{
    Arg* a = (Arg*)arg;

    List{String}? files = dir::list_dir(a.allocx, a.path);
    if (catch err = files)
    {
        a.error = err;
        return (void*)a;
    }

    a.files = files;

    return (void*)a;
}

<*
 returned List{String} must be freed properly, not only list itself, but also containing strings
*>
fn List{String}? listdir(Allocator allocx, String path)
{
    Arg arg = {
        .path = path,
        .allocx = allocx,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_listdir, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.files;
}

alias DirIterator = dir::DirIterator;
alias DirEntry = dir::DirEntry;

fn DirIterator? scandir(Allocator allocx, String path)
{
    return dir::scan_dir(allocx, path)!;
}

fn void* _link(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (catch err = stat::link(a.path, a.path2))
    {
        a.error = err;
        return (void*)a;
    }

    return (void*)a;
}

fn void? link(String path, String path2) @maydiscard
{
    Arg arg = {
        .path = path,
        .path2 = path2,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_link, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _symlink(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (catch err = stat::symlink(a.path, a.path2))
    {
        a.error = err;
        return (void*)a;
    }

    return (void*)a;
}

fn void? symlink(String path, String path2) @maydiscard
{
    Arg arg = {
        .path = path,
        .path2 = path2,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_symlink, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _readlink(void* arg) @local
{
    Arg* a = (Arg*)arg;

    sz? n = stat::read_link(a.path, a.buf);
    if (catch err = n)
    {
        a.error = err;
        return (void*)a;
    }

    a.n = n;

    return (void*)a;
}

fn sz? readlink(String path, char[] buf) @maydiscard
{
    Arg arg = {
        .path = path,
        .buf = buf,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_readlink, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.n;
}

fn void* _getsize(void* arg) @local
{
    Arg* a = (Arg*)arg;

    sz? size = cfile::size(a.path);
    if (catch err = size)
    {
        a.error = err;
        return (void*)a;
    }

    a.size = size;

    return (void*)a;
}

fn sz? getsize(String path)
{
    Arg arg = {
        .path = path,
        .error = NONE,
    };

    Arg*? a = aio::run_in_executor(&_getsize, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.size;
}

fn void* _exists(void* arg) @local
{
    Arg* a = (Arg*)arg;
    a.exists = cfile::exists(a.path);

    return (void*)a;
}

fn bool exists(String path)
{
    Arg arg = {
        .path = path,
    };

    Arg*? a = aio::run_in_executor(&_exists, &arg);
    if (catch err = a) return false;

    return a.exists;
}

fn void* _isfile(void* arg) @local
{
    Arg* a = (Arg*)arg;
    a.isfile = cfile::is_file(a.path);

    return (void*)a;
}

fn bool isfile(String path)
{
    Arg arg = {
        .path = path,
    };

    Arg*? a = aio::run_in_executor(&_isfile, &arg);
    if (catch err = a) return false;

    return a.isfile;
}

fn void* _isdir(void* arg) @local
{
    Arg* a = (Arg*)arg;
    a.isdir = cfile::is_dir(a.path);

    return (void*)a;
}

fn bool isdir(String path)
{
    Arg arg = {
        .path = path,
    };

    Arg*? a = aio::run_in_executor(&_isdir, &arg);
    if (catch err = a) return false;

    return a.isdir;
}

fn void* _islink(void* arg) @local
{
    Arg* a = (Arg*)arg;
    a.islink = cfile::is_link(a.path);

    return (void*)a;
}

fn bool islink(String path)
{
    Arg arg = {
        .path = path,
    };

    Arg*? a = aio::run_in_executor(&_islink, &arg);
    if (catch err = a) return false;

    return a.islink;
}

// eof