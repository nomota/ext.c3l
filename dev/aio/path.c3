// path.c3

// async path operations on top of `asyncio`

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
    int mode;
    bool exist_ok;
    usz n;
    Allocator allocx;
    List{String} files;
    char[] buf;
    usz size;
    bool exists;
    bool isfile;
    bool isdir;
    bool islink;
}

faultdef STAT_FILE_NOT_FOUND;

fn void* _stat(void* arg) @local
{
    Arg* a = (Arg*)arg;

    if (! stat::exists(a.path))
    {
        a.error = STAT_FILE_NOT_FOUND;
        return (void*) a;
    }
    Stat? stat = { 
        .st_size = stat::size(a.path),
        .st_mtime = stat::last_modified(a.path),
    };
    if (catch err = stat)
    {
        a.error = err;
        return (void*) a;
    }
    a.stat = stat;
    
    return (void*) a;
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
    Arg* a = (Arg*) arg;
    
    if (catch err = cfile::rename(a.path, a.path2))
    {
        a.error = err;
    }

    return (void*) a;
}

fn void? rename(String path, String path2) @maydiscard
{
    Arg arg = { .path = path, .path2 = path2, .error = NONE };

    Arg*? a = aio::run_in_executor(&_rename, &arg);
    if (catch err = a) return err~;

    if (a.error != NONE) return a.error~;
}

fn void* _replace(void* arg) @local
{
    Arg* a = (Arg*) arg;
    
    if (cfile::exists(a.path2))
    {
        if (catch err = cfile::remove(a.path2))
        {
            a.error = err;
            return (void*) a;
        }
    }
    
    if (catch err = cfile::rename(a.path, a.path2))
    {
        a.error = err;
        return (void*) a;
    }
    
    return (void*) a;
}

fn void? replace(String path, String path2) @maydiscard
{
    Arg arg = { .path = path, .path2 = path2, .error = NONE };
    Arg*? a = aio::run_in_executor(&_replace, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _remove(void* arg) @local
{
    Arg* a = (Arg*) arg;
    
    if (catch err = cfile::remove(a.path)) 
    {
        a.error = err;
        return (void*) a;
    }
    
    return (void*) a;
}

fn void? remove(String path) @maydiscard
{
    Arg arg = { .path = path, .error = NONE };
    Arg*? a = aio::run_in_executor(&_remove, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn usz? sendfile(int to_sock, int from_fd, long offset, long count)
{
    io::file_seek(from_fd, offset, 0);
    usz written = 0;
    while (written < count)
    {
        char[1024] buf;
        usz n = io::file_read(from_fd, &buf)!;
        n = io::file_write(to_sock, &buf)!;
        written += n;
    }
    return written;
}

fn void* _mkdir(void* arg) @local
{
    Arg* a = (Arg*) arg;

    if (catch err = dir::make_dir(a.path, false, a.mode))
    {
        a.error = err;
        return (void*) a;
    }
    
    return (void*) a;
}

fn void? mkdir(String path, int mode=0o777) @maydiscard
{
    Arg arg = { .path = path, .mode = mode, .error = NONE };
    Arg*? a = aio::run_in_executor(&_mkdir, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

faultdef MKDIR_FILE_EXIST;

fn void* _makedirs(void* arg) @local
{
    Arg* a = (Arg*) arg;

    if (dir::exists(a.path))
    {
        if (! a.exist_ok) a.error = MKDIR_FILE_EXIST;
        return (void*) a;
    }

    if (catch err = dir::make_dir(a.path, true, a.mode))
    {
        a.error = err;
        return (void*) a;
    }

    return (void*) a;
}

fn void? makedirs(String path, int mode=0o777, bool exist_ok=true) @maydiscard
{
    Arg arg = { .path = path, .mode = mode, .exist_ok = exist_ok, .error = NONE };

    Arg*? a = aio::run_in_executor(&_makedirs, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

faultdef RMDIR_FILE_NOT_FOUND;

fn void* _removedirs(void* arg) @local
{
    Arg* a = (Arg*) arg;

    if (! dir::exists(a.path))
    {
        a.error = RMDIR_FILE_NOT_FOUND;
        return (void*)a;
    }
    
    String path = a.path;
    
    while (path.len > 0) {
        List{String}? files = dir::list_dir(mem, path);
        if (catch err = files)
        {
            a.error = err;
            return (void*) a;
        }
        if (files.len() > 0)
        {
            files.free();
            return (void*) a;
        }
        files.free();
        
        dir::remove_dir(path);
        usz? idx = path.rindex_of_char('/');
        if (catch idx)
        {
            idx = path.rindex_of_char('\\');
            if (catch idx) return (void*) a;
            path = path[0:idx];
        }
        else
        {
            path = path[0:idx];
        }
    }
    
    return (void*) a;
}

fn void? removedirs(String path, int mode=0o777) @maydiscard
{
    Arg arg = { .path = path, .error = NONE };
    Arg*? a = aio::run_in_executor(&_removedirs, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _listdir(void* arg) @local
{
    Arg* a = (Arg*) arg;

    List{String}? files = dir::list_dir(a.allocx, a.path);
    if (catch err = files)
    {
        a.error = err;
        return (void*) a;
    }
    
    a.files = files;
    
    return (void*) a;
}

<*
 returned List{String} must be freed properly, not only list itself, but also containing strings
*>
fn List{String}? listdir(Allocator allocx, String path)
{
    Arg arg = { .path = path, .allocx = allocx, .error = NONE };
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

/*
fn void DirIterator.close(&self)
{
    self.close();
}

fn DirEntry? DirIterator.next(&self)
{
    return self.next();
}

fn long? DirEntry.last_modified(&self)
{
    return self.last_modified();
}

fn usz? DirEntry.size(&self)
{
    return self.size();
}


fn bool DirEntry.is_file(&self)
{
    return self.is_file();
}

fn bool DirEntry.is_dir(&self)
{
    return self.is_dir();
}

fn bool DirEntry.is_link(&self)
{
    return self.is_link();
}

fn void DirEntry.free(&self)
{
    return self.free();
}
*/

fn void* _link(void* arg) @local
{
    Arg* a = (Arg*) arg;

    if (catch err = stat::link(a.path, a.path2))
    {
        a.error = err;
        return (void*) a;
    }
    
    return (void*) a;
}

fn void? link(String path, String path2) @maydiscard
{
    Arg arg = {
        .path = path, 
        .path2 = path2, 
        .error = NONE
    };
    Arg*? a = aio::run_in_executor(&_link, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _symlink(void* arg) @local
{
    Arg* a = (Arg*) arg;

    if (catch err = stat::symlink(a.path, a.path2))
    {
        a.error = err;
        return (void*) a;
    }
    
    return (void*) a;
}

fn void? symlink(String path, String path2) @maydiscard
{
    Arg arg = {
        .path = path, 
        .path2 = path2, 
        .error = NONE
    };
    Arg*? a = aio::run_in_executor(&_symlink, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* _readlink(void* arg) @local
{
    Arg* a = (Arg*) arg;

    usz? n = stat::read_link(a.path, a.buf);
    if (catch err = n)
    {
        a.error = err;
        return (void*) a;
    }
    a.n = n;
    
    return (void*) a;
}

fn usz? readlink(String path, char[] buf) @maydiscard
{
    Arg arg = {
        .path = path, 
        .buf = buf, 
        .error = NONE
    };
    Arg*? a = aio::run_in_executor(&_readlink, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.n;
}

fn void* _getsize(void* arg) @local
{
    Arg* a = (Arg*) arg;
    
    usz? size = cfile::size(a.path);
    if (catch err = size)
    {
        a.error = err;
        return (void*) a;
    }
    a.size = size;
    
    return (void*) a;
}

fn usz? getsize(String path)
{
    Arg arg = { .path = path, .error = NONE };
    Arg*? a = aio::run_in_executor(&_getsize, &arg);
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
        
    return a.size;
}

fn void* _exists(void* arg) @local
{
    Arg* a = (Arg*) arg;
    a.exists = cfile::exists(a.path);

    return (void*) a;
}

fn bool exists(String path)
{
    Arg arg = { .path = path };
    Arg*? a = aio::run_in_executor(&_exists, &arg);
    if (catch err = a) return false;

    return a.exists;
}

fn void* _isfile(void* arg) @local
{
    Arg* a = (Arg*) arg;
    
    a.isfile = cfile::is_file(a.path);
    
    return (void*) a;
}

fn bool isfile(String path)
{
    Arg arg = { .path = path };
    Arg*? a = aio::run_in_executor(&_isfile, &arg);
    if (catch err = a) return false;

    return a.isfile;
}

fn void* _isdir(void* arg) @local
{
    Arg* a = (Arg*) arg;
    
    a.isdir = cfile::is_dir(a.path);
    
    return (void*) a;
}

fn bool isdir(String path)
{
    Arg arg = { .path = path };
    Arg*? a = aio::run_in_executor(&_isdir, &arg);
    if (catch err = a) return false;

    return a.isdir;
}

fn void* _islink(void* arg) @local
{
    Arg* a = (Arg*) arg;
    
    a.islink = cfile::is_link(a.path);
    
    return (void*) a;
}

fn bool islink(String path)
{
    Arg arg = { .path = path };
    Arg*? a = aio::run_in_executor(&_islink, &arg);
    if (catch err = a) return false;
    
    return a.islink;
}

// eof