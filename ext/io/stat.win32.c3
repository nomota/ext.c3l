// stat.win32.c3

// provides following functions for Windows systems.
// exists() statinfo() size() last_modified()
// is_dir() is_file() is_link()
// is_readable() is_writeable()
// is_executable()
// read_link()
// umask(), change_mode()
// link(), symlink()

// Nomota <hiongun@gmail.com>; MIT License

module ext::io::stat @if(env::WIN32);

import c::errno;
import c::ioapiset;
import c::windows;
import c::winbase;
import c::fileapi;
import c::sys::stat;
import ext::debug;

const int MAX_PATH = 1024;

struct StatInfo
{
    sz size;
    long mtime;

    bool is_file;
    bool is_dir;
    bool is_link;
}

fn Char16*? utf8to16(String path, Char16[] wpath) @private
{
    if (path.len == 0) return errno::E_INVALID_ARG~;

    Char16[] tmp = path.to_utf16(tmem)!;

    if (tmp.len >= wpath.len) return errno::E_INVALID_ARG~;

    wpath[0:tmp.len] = tmp[0:tmp.len];
    wpath[tmp.len] = 0;

    for (sz i = 0; i < tmp.len; i++)
    {
        if (wpath[i] == (Char16)'/')
        {
            wpath[i] = (Char16)'\\';
        }
    }

    return wpath.ptr;
}

fn sz file_size_from_attr(fileapi::Win32FileAttributeData* info) @private
{
    ulong high = (ulong)info.nFileSizeHigh;
    ulong low = (ulong)info.nFileSizeLow;

    return (sz)((high << 32) | low);
}

fn long filetime_from_attr(fileapi::Win32FileAttributeData* info) @private
{
    ulong high = (ulong)info.ftLastWriteTime_high;
    ulong low = (ulong)info.ftLastWriteTime_low;

    return (long)((high << 32) | low);
}

fn StatInfo? statinfo(String path)
{
    Char16[MAX_PATH] wpath;
    Char16* name = utf8to16(path, wpath[..])!;

    fileapi::Win32FileAttributeData info;

    if (!fileapi::getFileAttributesExW(name, 0, &info))
    {
        return errno::get_fault()~;
    }

    winbase::DWord attrs = info.dwFileAttributes;

    bool is_dir = (attrs & windows::FILE_ATTRIBUTE_DIRECTORY) != 0;
    bool is_link = (attrs & windows::FILE_ATTRIBUTE_REPARSE_POINT) != 0;

    return {
        .size = file_size_from_attr(&info),
        .mtime = filetime_from_attr(&info),
        .is_dir = is_dir,
        .is_file = !is_dir && !is_link,
        .is_link = is_link,
    };
}

fn bool exists(String path)
{
    Char16[MAX_PATH] wpath;
    Char16*? name = utf8to16(path, wpath[..]);

    if (catch err = name) return false;

    winbase::DWord attrs = winbase::getFileAttributesW(name);

    return attrs != windows::INVALID_FILE_ATTRIBUTES;
}

fn sz? size(String path)
{
    Char16[MAX_PATH] wpath;
    Char16* name = utf8to16(path, wpath[..])!;

    fileapi::Win32FileAttributeData info;

    if (!fileapi::getFileAttributesExW(name, 0, &info))
    {
        return errno::get_fault()~;
    }

    return file_size_from_attr(&info);
}

fn long? last_modified(String path)
{
    Char16[MAX_PATH] wpath;
    Char16* name = utf8to16(path, wpath[..])!;

    fileapi::Win32FileAttributeData info;

    if (!fileapi::getFileAttributesExW(name, 0, &info))
    {
        return errno::get_fault()~;
    }

    return filetime_from_attr(&info);
}

fn bool is_dir(String path)
{
    Char16[MAX_PATH] wpath;
    Char16*? name = utf8to16(path, wpath[..]);

    if (catch err = name) return false;

    winbase::DWord attrs = winbase::getFileAttributesW(name);

    if (attrs == windows::INVALID_FILE_ATTRIBUTES) return false;

    return (attrs & windows::FILE_ATTRIBUTE_DIRECTORY) != 0;
}

fn bool is_file(String path)
{
    Char16[MAX_PATH] wpath;
    Char16*? name = utf8to16(path, wpath[..]);

    if (catch err = name) return false;

    winbase::DWord attrs = winbase::getFileAttributesW(name);

    if (attrs == windows::INVALID_FILE_ATTRIBUTES) return false;

    if ((attrs & windows::FILE_ATTRIBUTE_DIRECTORY) != 0) return false;
    if ((attrs & windows::FILE_ATTRIBUTE_REPARSE_POINT) != 0) return false;

    return true;
}

fn bool is_link(String path)
{
    Char16[MAX_PATH] wpath;
    Char16*? name = utf8to16(path, wpath[..]);

    if (catch err = name) return false;

    winbase::DWord attrs = winbase::getFileAttributesW(name);

    if (attrs == windows::INVALID_FILE_ATTRIBUTES) return false;

    return (attrs & windows::FILE_ATTRIBUTE_REPARSE_POINT) != 0;
}

fn sz? read_link(String path, char[] output)
{
    if (output.len == 0) return errno::E_INVALID_ARG~;

    Char16[MAX_PATH] wpath;
    Char16* name = utf8to16(path, wpath[..])!;

    windows::Handle handle = windows::createFileW(
        name,
        0,
        windows::FILE_SHARE_READ | windows::FILE_SHARE_WRITE | windows::FILE_SHARE_DELETE,
        null,
        windows::OPEN_EXISTING,
        windows::FILE_FLAG_OPEN_REPARSE_POINT | windows::FILE_FLAG_BACKUP_SEMANTICS,
        windows::INVALID_HANDLE_VALUE
    );

    if (handle == windows::INVALID_HANDLE_VALUE)
    {
        return errno::get_fault()~;
    }

    defer windows::closeHandle(handle);

    char[16384] buffer;
    winbase::DWord bytes_returned = 0;

    if (!ioapiset::deviceIoControl(
        handle,
        ioapiset::FSCTL_GET_REPARSE_POINT,
        null,
        0,
        buffer[..].ptr,
        16384,
        &bytes_returned,
        null
    ))
    {
        return errno::get_fault()~;
    }

    ioapiset::ReparseDataBuffer* reparse = (ioapiset::ReparseDataBuffer*)buffer[..].ptr;

    if (reparse.reparseTag != ioapiset::IO_REPARSE_TAG_SYMLINK)
    {
        return errno::E_GENERAL_ERR~;
    }

    Char16* target = (Char16*)&reparse.pathBuffer[reparse.printNameOffset / 2];
    sz len = reparse.printNameLength / 2;

    String s = string::from_utf16(tmem, target[0:len])!;

    if (s.len >= output.len) return errno::E_GENERAL_ERR~;

    output[0:s.len] = s[0:s.len];
    output[s.len] = 0;

    return s.len;
}

fn bool is_readable(String path)
{
    Char16[MAX_PATH] wpath;
    Char16*? name = utf8to16(path, wpath[..]);

    if (catch err = name) return false;

    windows::Handle handle = windows::createFileW(
        name,
        windows::GENERIC_READ,
        windows::FILE_SHARE_READ | windows::FILE_SHARE_WRITE | windows::FILE_SHARE_DELETE,
        null,
        windows::OPEN_EXISTING,
        0,
        windows::INVALID_HANDLE_VALUE
    );

    if (handle == windows::INVALID_HANDLE_VALUE) return false;

    defer windows::closeHandle(handle);

    return true;
}

fn bool is_writeable(String path)
{
    Char16[MAX_PATH] wpath;
    Char16*? name = utf8to16(path, wpath[..]);

    if (catch err = name) return false;

    windows::Handle handle = windows::createFileW(
        name,
        windows::GENERIC_WRITE,
        windows::FILE_SHARE_READ | windows::FILE_SHARE_WRITE | windows::FILE_SHARE_DELETE,
        null,
        windows::OPEN_EXISTING,
        0,
        windows::INVALID_HANDLE_VALUE
    );

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

    switch (ext_lower)
    {
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
    Char16[MAX_PATH] wpath;
    Char16* name = utf8to16(file, wpath[..])!;

    winbase::DWord attrs = winbase::getFileAttributesW(name);

    if (attrs == windows::INVALID_FILE_ATTRIBUTES)
    {
        return errno::get_fault()~;
    }

    if (mode & 0o0200)
    {
        attrs &= ~windows::FILE_ATTRIBUTE_READONLY;
    }
    else
    {
        attrs |= windows::FILE_ATTRIBUTE_READONLY;
    }

    if (!winbase::setFileAttributesW(name, attrs))
    {
        return errno::get_fault()~;
    }
}

fn void? link(String oldpath, String newpath) @maydiscard
{
    Char16[MAX_PATH] wold_buf;
    Char16* wold = utf8to16(oldpath, wold_buf[..])!;

    Char16[MAX_PATH] wnew_buf;
    Char16* wnew = utf8to16(newpath, wnew_buf[..])!;

    windows::Bool r = winbase::createHardLinkW(wnew, wold, null);

    if (!r)
    {
        return errno::get_fault()~;
    }
}

fn void? symlink(String oldpath, String newpath) @maydiscard
{
    Char16[MAX_PATH] wold_buf;
    Char16* wold = utf8to16(oldpath, wold_buf[..])!;

    Char16[MAX_PATH] wnew_buf;
    Char16* wnew = utf8to16(newpath, wnew_buf[..])!;

    uint flags = 0;

    if (is_dir(oldpath))
    {
        flags = 1;
    }

    windows::Bool r = winbase::createSymbolicLinkW(wnew, wold, flags);

    if (!r)
    {
        return errno::get_fault()~;
    }
}

// eof