// dir.posix.c3

// This module provides directory operations for Posix systems.
// get_cur_dir() change_dir() make_dir() remove_dir()
// list_dir() is_dir() is_file()

// Nomota <hiongun@gmail.com>; MIT License

module ext::io::dir @if(!env::WIN32); // POSIX

import c::errno;
import c::dirent;
import c::sys::stat;
import c::string;
import c::stdio;
import c::unistd;
import ext::io::stat;
import std::collections::list;
import ext::debug;

const int MAX_PATH = 1024;

faultdef NO_MORE_ENTRY;

fn char*? path_to_cstr(String path, char[] buffer)
{
    if (path.len+1 >= buffer.len) return errno::E_NAME_TOO_LONG~;
    
    buffer[0:path.len] = path[0:path.len];
    buffer[path.len] = 0;

    return buffer.ptr;
}

<*
  returns String representation of buf
*>
fn String? get_cur_dir(char[] buf)
{
    // on success, result == buf.ptr
    char* result = unistd::getcwd(buf.ptr, buf.len);
    
    if (result == null) {
        return errno::get_fault()~;
    }
    
    return ((ZString)result).str_view();
}

fn void? change_dir(String path) @maydiscard
{
    if (path.len == 0) return errno::E_INVALID~;
    char[MAX_PATH] p2;
    char* zpath = path_to_cstr(path, &p2)!;
    
    if (unistd::chdir(zpath) != 0) {
        return errno::get_fault()~;
    }
}

fn void? make_dir(String path, bool recursive = false, CUInt mode = 0o755) @maydiscard
{
    if (path.len == 0) return errno::E_INVALID~;
    char[MAX_PATH] p2;
    char* zpath = path_to_cstr(path, &p2)!;
    
    stat::umask(0);
    if (!recursive) {
        if (stat::mkdir(zpath, mode) != 0) {
            return errno::get_fault()~;
        }
        return;
    }
    
    assert(path.len+1 <= MAX_PATH);
    
    // Recursive: create parent directories
    char[MAX_PATH] temp;
    temp[0:path.len] = path[0:path.len];
    temp[path.len] = 0;
    
    // Skip leading slashes
    sz start = 0;
    while (start < path.len && temp[start] == '/') {
        start++;
    }
    if (start >= path.len) {
        // Path is all slashes or empty after skipping leading slashes
        return;  // Already at root or nothing to create
    }
    // Create each component
    for (sz i = start; i <= path.len; i++) 
    {
        // Process at '/' or end of string
        if (i == path.len || temp[i] == '/') {
            // Skip consecutive slashes
            if (i > 0 && temp[i-1] == '/') continue;
            
            // Temporarily null-terminate
            char saved = temp[i];
            temp[i] = 0;
            
            // Try to create directory (ignore EEXIST)
            if (stat::mkdir(&temp[0], mode) != 0) {
                if (errno::errno() != errno::EEXIST) {
                    return errno::get_fault()~;
                }
            }
            
            // Restore character
            temp[i] = saved;
        }
    }
}

fn void? remove_dir(String path) @maydiscard
{
    char[MAX_PATH] p2;
    char* zpath = path_to_cstr(path, &p2)!;
    
    if (unistd::rmdir(zpath) != 0) {
        return errno::get_fault()~;
    }
}

<*
  returned List{String} must be freed properly, not only list itself, but also containing strings
*>
fn List{String}? list_dir(Allocator allocx, String path)
{
    char[MAX_PATH] p2;
    char* zpath = path_to_cstr(path, &p2)!;
    
    dirent::Dir* dir = dirent::opendir(zpath);
    if (dir == null) {
        return errno::get_fault()~;
    }
    defer dirent::closedir(dir);
    
    // Use a dynamic list
    List{String} entries;
    entries.init(allocx);
    defer (catch err) {
        foreach (e : entries) { e.free(allocx); }
        entries.free();
    }
    
    dirent::DirEnt* entry;
    while ((entry = dirent::readdir(dir))) {
        char* name = (char*)&entry.d_name[0];
        sz n = (sz)string::strlen(name);
        String name_s = (String)name[0:n];;

        // Skip "." and ".."
        if (name_s== "." || name_s == "..") continue;
        
        // Copy the name and add to list
        String name_copy = name_s.copy(allocx);
        entries.push(name_copy);
    }
    
    return entries;
}

struct DirIterator {
    dirent::Dir* dir;
    String path;
    Allocator allocx;
}

struct DirEntry {
    String path;
    String name;
    Allocator allocx;
}


fn DirIterator? scan_dir(Allocator allocx, String path)
{
    if (path[path.len-1] == '/') {
        path = path.trim_right("/");
    }
 
    char[MAX_PATH] p2;
    char* zpath = path_to_cstr(path, &p2)!;
    
    dirent::Dir* dir = dirent::opendir(zpath);
    if (dir == null) {
        return errno::get_fault()~;
    }
 
    return {
        .dir = dir,
        .path = path.copy(allocx),
        .allocx = allocx
    };
}

fn void DirIterator.close(&self)
{
    self.path.free(self.allocx);
    dirent::closedir(self.dir);
}

fn DirEntry? DirIterator.next(&self)
{
    dirent::DirEnt* entry;
    while ((entry = dirent::readdir(self.dir))) {
        char* name = (char*)&entry.d_name[0];
        sz n = (sz)string::strlen(name);
        String name_s = (String)name[0:n];

        // Skip "." and ".."
        if (name_s== "." || name_s == "..") continue;
        
        return {
            .path = self.path,
            .name = name_s.copy(self.allocx),
            .allocx = self.allocx,
        };
    }
    return NO_MORE_ENTRY~;
}

fn void DirEntry.free(&self)
{
    self.name.free(self.allocx);
}

// no boundary check, buf must be enough
fn String bcat(char[] buf, String... args)
{
    sz n = 0;
    foreach (arg: args) {
        buf[n:arg.len] = arg[0:arg.len];
        n += arg.len;
    }
    buf[n] = 0;
    return (String) buf[0:n];
}

fn long? DirEntry.last_modified(&self)
{
    char[256] buf;
    String fullpath = bcat(&buf, self.path, "/", self.name);
    return stat::last_modified(fullpath)!;
}

fn sz? DirEntry.size(&self)
{
    char[256] buf;
    String fullpath = bcat(&buf, self.path, "/", self.name);
    return stat::size(fullpath)!;
}

fn bool DirEntry.is_dir(&self)
{
    char[256] buf;
    String fullpath = bcat(&buf, self.path, "/", self.name);

    return stat::is_dir(fullpath);
}

fn bool DirEntry.is_file(&self)
{
    char[256] buf;
    String fullpath = bcat(&buf, self.path, "/", self.name);

    return stat::is_file(fullpath);
}

fn bool DirEntry.is_link(&self)
{
    char[256] buf;
    String fullpath = bcat(&buf, self.path, "/", self.name);

    return stat::is_link(fullpath);
}


fn bool exists(String path) => stat::exists(path);

fn long? last_modified(String path) => stat::last_modified(path);

fn bool is_dir(String path) => stat::is_dir(path);
fn bool is_file(String path) => stat::is_file(path);
fn bool is_link(String path) => stat::is_link(path);

fn bool is_readable(String path) => stat::is_readable(path);
fn bool is_writeable(String path) => stat::is_writeable(path);

fn sz? read_link(String link, char[] output) => stat::read_link(link, output);

fn void? change_mode(String path, Mode_t mode) @maydiscard => stat::change_mode(path, mode);
