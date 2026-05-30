// stat.win32.c3

module ext::io::stat @if(env::WIN32);

import c::errno;
import c::ioapiset;
import c::windows;
import c::winbase;
import c::fileapi;
import c::sys::stat;
import ext::debug;

fn Char16*? utf8to16(String path, Char16[] wpath) @private
{
    if (path.len == 0) return errno::F_BAD_LENGTH~;
    Char16[] p2 = path.to_utf16(tmem)!;
    // defer free(p2);
    
    if (p2.len >= wpath.len-1) return errno::F_BAD_LENGTH~;
    
    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;
    for (sz i = 0; i < p2.len; i++) {
        if (p2[i] == (Char16)'/') {
            wpath[i] = (Char16)'\\';
        }
    }

    return wpath.ptr;
}

fn bool exists(String path) 
{
    Char16[512] wpath;
    Char16*? name = utf8to16(path, &wpath);
    if (catch err = name) return false;

    winbase::DWord attrs = winbase::getFileAttributesW(name);
    return attrs != windows::INVALID_FILE_ATTRIBUTES;
}

fn sz? size(String path) 
{
    Char16[512] wpath;
    Char16* name = utf8to16(path, &wpath)!;
    
    fileapi::Win32FileAttributeData file_info;
    if (!fileapi::getFileAttributesExW(name, 0, &file_info)) {
        return errno::get_fault()~;
    }
    
    long size = ((long)file_info.nFileSizeHigh << 32) | (long)file_info.nFileSizeLow;
    return (sz)size;
}

fn long? last_modified(String path) 
{
    Char16[512] wpath;
    Char16* name = utf8to16(path, &wpath)!;
    
    fileapi::Win32FileAttributeData file_info;
    if (!fileapi::getFileAttributesExW(name, 0, &file_info)) {
        return errno::get_fault()~;
    }
    
    long filetime = ((long)file_info.ftLastWriteTime_high << 32) | (long)file_info.ftLastWriteTime_low;
    return filetime;
}

fn bool is_dir(String path) 
{
    Char16[512] wpath;
    Char16*? name = utf8to16(path, &wpath);
    if (catch err = name) return false;
  
    Dword attrs = fileapi::getFileAttributesW(name);
    if (attrs == windows::INVALID_FILE_ATTRIBUTES) return false;
    
    return (attrs & windows::FILE_ATTRIBUTE_DIRECTORY) != 0;
}

fn bool is_file(String path) 
{
    Char16[512] wpath;
    Char16*? name = utf8to16(path, &wpath);
    if (catch err = name) return false;
   
    Dword attrs = fileapi::getFileAttributesW(name);
    if (attrs == windows::INVALID_FILE_ATTRIBUTES) return false;
    
    return (attrs & windows::FILE_ATTRIBUTE_DIRECTORY) == 0;
}

fn bool is_link(String path) 
{
    Char16[512] wpath;
    Char16*? name = utf8to16(path, &wpath);
    if (catch err = name) return false;
    
    Dword attrs = fileapi::getFileAttributesW(name);
    if (attrs == windows::INVALID_FILE_ATTRIBUTES) return false;
    
    return (attrs & windows::FILE_ATTRIBUTE_REPARSE_POINT) != 0;
}

fn sz? read_link(String path, char[] output) 
{
    Char16[512] wpath;
    Char16* name = utf8to16(path, &wpath)!;
    
    windows::Handle handle = windows::createFileW(
        name, 0,
        windows::FILE_SHARE_READ | windows::FILE_SHARE_WRITE | windows::FILE_SHARE_DELETE,
        null, windows::OPEN_EXISTING,
        windows::FILE_FLAG_OPEN_REPARSE_POINT | windows::FILE_FLAG_BACKUP_SEMANTICS,
        windows::INVALID_HANDLE_VALUE);

    if (handle == windows::INVALID_HANDLE_VALUE) {
        return errno::get_fault()~;
    }
    
    defer windows::closeHandle(handle);
    
    char[16384] buffer;
    Dword bytes_returned;
    
    if (!ioapiset::deviceIoControl(handle, ioapiset::FSCTL_GET_REPARSE_POINT, null, 0,
        &buffer, 16384, &bytes_returned, null)) {
        return errno::get_fault()~;
    }
    
    ioapiset::ReparseDataBuffer* reparse = (ioapiset::ReparseDataBuffer*)&buffer;
    
    if ((reparse.reparseTag != ioapiset::IO_REPARSE_TAG_SYMLINK)) {
        return errno::GENERAL_ERR~;
    }

    Char16* target = (Char16*)&reparse.pathBuffer[reparse.printNameOffset / 2];
    sz len = reparse.printNameLength / 2;
    
    String s = string::from_utf16(tmem, target[0:len])!;
    // defer s.free(tmem);
    
    if (s.len >= output.len) return errno::F_BAD_LENGTH~;
    
    output[0:s.len] = s[0:s.len];
    output[s.len] = 0;
    
    return (sz)s.len;
}

fn bool is_readable(String path) 
{
    Char16[512] wpath;
    Char16*? name = utf8to16(path, &wpath);
    if (catch err = name) return false;
   
    windows::Handle handle = windows::createFileW(
        name, windows::GENERIC_READ,
        windows::FILE_SHARE_READ | windows::FILE_SHARE_WRITE,
        null, windows::OPEN_EXISTING, 0, windows::INVALID_HANDLE_VALUE);
    
    if (handle == windows::INVALID_HANDLE_VALUE) return false;
    
    defer windows::closeHandle(handle);
    return true;
}

fn bool is_writeable(String path) 
{
    Char16[512] wpath;
    Char16*? name = utf8to16(path, &wpath);
    if (catch err = name) return false;

    windows::Handle handle = windows::createFileW(
        name, windows::GENERIC_WRITE,
        windows::FILE_SHARE_READ | windows::FILE_SHARE_WRITE,
        null, windows::OPEN_EXISTING, 0, windows::INVALID_HANDLE_VALUE);
    
    if (handle == windows::INVALID_HANDLE_VALUE) return false;
    
    defer windows::closeHandle(handle);
    return true;
}

fn bool is_executable(String path) 
{
    if (!exists(path)) return false;
    if (is_dir(path)) return false;
    
    sz? idx = path.rindex_of_char('.');
    if (catch err = idx) return false;
    
    String ext = path[idx..];
    String ext_lower = ext.to_lower_tcopy();
    defer ext_lower.free(tmem);
    
    switch (ext_lower) {
        case ".exe":
        case ".bat":
        case ".cmd":
        case ".com":
        case ".msi":
        case ".ps1":
        case ".vbs":
            return true;
        default:
            return false;
    }
}

Mode_t win_umask_value = 0o022;
fn Mode_t umask(Mode_t mask)
{
    Mode_t old = win_umask_value;
    win_umask_value = mask & 0o777;
    return old;
}

fn void? change_mode(String file, Mode_t mode) @maydiscard
{
    Char16[512] wpath;
    Char16* name = utf8to16(file, &wpath)!;

    Dword attrs = windows::getFileAttributesW(name);
    if (attrs == windows::INVALID_FILE_ATTRIBUTES) {
        return errno::get_fault()~;
    }
    
    if (mode & 0o0200) { // owner write
        attrs &= ~windows::FILE_ATTRIBUTE_READONLY;
    } else {
        attrs |= windows::FILE_ATTRIBUTE_READONLY;
    }
    
    if (!windows::setFileAttributesW(name, attrs)) {
        return errno::get_fault()~;
    }
}

fn void? link(String old, String new) @maydiscard
{
    Char16[512] wpath1;
    Char16* wold = utf8to16(old, &wpath1)!;

    Char16[512] wpath2;
    Char16* wnew = utf8to16(new, &wpath2)!;

    windows::Bool r = winbase::createHardLinkW(wnew, wold, null);
    if (! r) {
        return errno::get_fault()~;
    }
}

fn void? symlink(String old, String new) @maydiscard
{
    Char16[512] wpath1;
    Char16* wold = utf8to16(old, &wpath1)!;

    Char16[512] wpath2;
    Char16* wnew = utf8to16(new, &wpath2)!;

    int flag = 0; // file 
    if (is_dir(old)) flag = 1; // dir
    
    // winbase::SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE (0x2)
    windows::Bool r = winbase::createSymbolicLinkW(wnew, wold, flag);
    if (! r) {
        return errno::get_fault()~;
    }
}
