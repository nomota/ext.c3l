// stat.posix.c3

// provides following functions for Posix systems.
// statinfo() exists() size() last_modified()
// is_dir() is_file() is_link()
// is_readable() is_writeable()
// is_executable()
// read_link(), umask(), change_mode()

// Nomota <hiongun@gmail.com>; MIT License

module ext::io::stat @if(env::POSIX);

import c::errno;
import c::unistd;
import c::sys::stat;

const int MAX_PATH = 1024;

struct StatInfo
{
    sz size;
    long mtime;

    bool is_file;
    bool is_dir;
    bool is_link;
}

fn char*? path_to_cstr(String path, char[] buffer) @inline
{
    if (path.len == 0) return errno::E_INVALID~;
    if (path.len >= buffer.len) return errno::E_ARG_TOO_BIG~;

    buffer[0:path.len] = path[0:path.len];
    buffer[path.len] = 0;

    return buffer.ptr;
}

fn StatInfo stat_info_from_stat(Stat_t* st, bool is_link) @inline
{
    return {
        .size = (sz)st.st_size,
        .mtime = st.st_mtime,
        .is_file = (st.st_mode & stat::S_IFMT) == stat::S_IFREG,
        .is_dir = (st.st_mode & stat::S_IFMT) == stat::S_IFDIR,
        .is_link = is_link,
    };
}

fn StatInfo? statinfo(String path)
{
    char[MAX_PATH] pbuf;
    char* zpath = path_to_cstr(path, pbuf[..])!;

    Stat_t lst;
    if (stat::lstat(zpath, &lst) != 0)
    {
        return errno::get_fault()~;
    }

    bool link = (lst.st_mode & stat::S_IFMT) == stat::S_IFLNK;

    if (!link)
    {
        return stat_info_from_stat(&lst, false);
    }

    Stat_t st;
    if (stat::stat(zpath, &st) != 0)
    {
        return errno::get_fault()~;
    }

    return stat_info_from_stat(&st, true);
}

fn sz? size(String path)
{
    char[MAX_PATH] pbuf;
    char* zpath = path_to_cstr(path, pbuf[..])!;

    Stat_t st;
    if (stat::stat(zpath, &st) != 0)
    {
        return errno::get_fault()~;
    }

    return (sz)st.st_size;
}

fn bool exists(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    return unistd::access(zpath, stat::F_OK) == 0;
}

fn bool is_dir(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    Stat_t st;
    if (stat::stat(zpath, &st) != 0) return false;

    return (st.st_mode & stat::S_IFMT) == stat::S_IFDIR;
}

fn bool is_file(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    Stat_t st;
    if (stat::stat(zpath, &st) != 0) return false;

    return (st.st_mode & stat::S_IFMT) == stat::S_IFREG;
}

fn bool is_link(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    Stat_t st;
    if (stat::lstat(zpath, &st) != 0) return false;

    return (st.st_mode & stat::S_IFMT) == stat::S_IFLNK;
}

fn long? last_modified(String path)
{
    char[MAX_PATH] pbuf;
    char* zpath = path_to_cstr(path, pbuf[..])!;

    Stat_t st;
    if (stat::stat(zpath, &st) != 0)
    {
        return errno::get_fault()~;
    }

    return st.st_mtime;
}

fn bool is_readable(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    return unistd::access(zpath, stat::R_OK) == 0;
}

fn bool is_writeable(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    return unistd::access(zpath, stat::W_OK) == 0;
}

fn bool is_executable(String path)
{
    char[MAX_PATH] pbuf;
    char*? zpath = path_to_cstr(path, pbuf[..]);

    if (catch err = zpath) return false;

    return unistd::access(zpath, stat::X_OK) == 0;
}

fn sz? read_link(String path, char[] output)
{
    if (output.len == 0) return errno::E_INVALID~;

    char[MAX_PATH] pbuf;
    char* zpath = path_to_cstr(path, pbuf[..])!;

    CLong n = unistd::readlink(zpath, output.ptr, (CULong)(output.len - 1));
    if (n < 0)
    {
        return errno::get_fault()~;
    }

    output[(sz)n] = 0;

    return (sz)n;
}

fn void? change_mode(String file, Mode_t mode) @maydiscard
{
    char[MAX_PATH] pbuf;
    char* zpath = path_to_cstr(file, pbuf[..])!;

    int r = stat::chmod(zpath, mode);
    if (r != 0) return errno::get_fault()~;
}

fn void? link(String oldpath, String newpath) @maydiscard
{
    char[MAX_PATH] pold;
    char* zold = path_to_cstr(oldpath, pold[..])!;

    char[MAX_PATH] pnew;
    char* znew = path_to_cstr(newpath, pnew[..])!;

    int r = unistd::link(zold, znew);
    if (r < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? symlink(String oldpath, String newpath) @maydiscard
{
    char[MAX_PATH] pold;
    char* zold = path_to_cstr(oldpath, pold[..])!;

    char[MAX_PATH] pnew;
    char* znew = path_to_cstr(newpath, pnew[..])!;

    int r = unistd::symlink(zold, znew);
    if (r < 0)
    {
        return errno::get_fault()~;
    }
}

// eof