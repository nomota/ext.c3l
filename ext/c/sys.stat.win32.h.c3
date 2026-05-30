// sys.stat.win32.h.c3

module c::sys::stat @if(env::WIN32);

alias Dword = uint;
alias Handle = void*;
alias Bool = int;
alias LPCWstr = Char16*;
alias Long = long;

const Handle INVALID_HANDLE_VALUE = (Handle)uptr::max;
const Dword GENERIC_READ = 0x80000000;
const Dword GENERIC_WRITE = 0x40000000;
const Dword FILE_SHARE_READ = 0x00000001;
const Dword FILE_SHARE_WRITE = 0x00000002;
const Dword OPEN_EXISTING = 3;
const Dword FILE_ATTRIBUTE_DIRECTORY = 0x10;
const Dword FILE_ATTRIBUTE_NORMAL = 0x80;
const Dword FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
const Dword FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
const Dword INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF;
const Dword IO_REPARSE_TAG_SYMLINK = 0xA000000C;
const Dword IO_REPARSE_TAG_MOUNT_POINT = 0xA0000003;
const Dword FSCTL_GET_REPARSE_POINT = 0x900a8;

const Dword ERROR_FILE_NOT_FOUND = 2;
const Dword ERROR_PATH_NOT_FOUND = 3;
const Dword ERROR_ACCESS_DENIED = 5;
const Dword ERROR_SHARING_VIOLATION = 32;
const Dword ERROR_INVALID_NAME = 123;
const Dword ERROR_FILENAME_EXCED_RANGE = 206;

struct Win32FileAttributeData {
    Dword dwFileAttributes;
    Dword ftCreationTime_low;
    Dword ftCreationTime_high;
    Dword ftLastAccessTime_low;
    Dword ftLastAccessTime_high;
    Dword ftLastWriteTime_low;
    Dword ftLastWriteTime_high;
    Dword nFileSizeHigh;
    Dword nFileSizeLow;
}

struct Win32FindDataW {
    Dword dwFileAttributes;
    Dword ftCreationTime_low;
    Dword ftCreationTime_high;
    Dword ftLastAccessTime_low;
    Dword ftLastAccessTime_high;
    Dword ftLastWriteTime_low;
    Dword ftLastWriteTime_high;
    Dword nFileSizeHigh;
    Dword nFileSizeLow;
    Dword dwReserved0;
    Dword dwReserved1;
    ushort[260] cFileName;
    ushort[14] cAlternateFileName;
}

struct ReparseDataBuffer {
    Dword reparseTag;
    ushort reparseDataLength;
    ushort reserved;
    ushort substituteNameOffset;
    ushort substituteNameLength;
    ushort printNameOffset;
    ushort printNameLength;
    Dword flags;
    ushort[1] pathBuffer;
}

faultdef 
    PATH_NOT_FOUND,
    PERMISSION_DENIED,
    PATH_TOO_LONG,
    SHARING_VIOLATION,
    INVALID_NAME,
    IO_ERROR,
    GENERAL_ERR;

extern fn Bool getFileAttributesExW(
    LPCWstr filename, 
    int info_level, 
    void* file_info
) @cname("GetFileAttributesExW");

extern fn Dword getFileAttributesW(
    LPCWstr filename
) @cname("GetFileAttributesW");

extern fn Handle createFileW(
    LPCWstr filename,
    Dword access,
    Dword share_mode, 
    void* security, 
    Dword creation,
    Dword flags, 
    Handle template
) @cname("CreateFileW");

extern fn Bool closeHandle(Handle handle) @cname("CloseHandle");

extern fn Bool getFileSizeEx(Handle file, Long* size) @cname("GetFileSizeEx");

extern fn Bool deviceIoControl(
    Handle device, 
    Dword control_code, 
    void* in_buffer, 
    Dword in_size,
    void* out_buffer, 
    Dword out_size, 
    Dword* bytes_returned, 
    void* overlapped
) @cname("DeviceIoControl");

extern fn Handle findFirstFileW(
    LPCWstr filename, 
    Win32FindDataW* find_data
) @cname("FindFirstFileW");

extern fn Bool findClose(Handle find_file) @cname("FindClose");

extern fn Dword getLastError() @cname("GetLastError");

/*
fn fault win_error_to_fault()
{
    Dword err = getLastError();
    
    switch (err)
    {
        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:
            return PATH_NOT_FOUND;
        case ERROR_ACCESS_DENIED:
            return PERMISSION_DENIED;
        case ERROR_SHARING_VIOLATION:
            return SHARING_VIOLATION;
        case ERROR_INVALID_NAME:
            return INVALID_NAME;
        case ERROR_FILENAME_EXCED_RANGE:
            return PATH_TOO_LONG;
        default:
            return GENERAL_ERR;
    }
}

fn sz? utf8to16(String path, Char16[] wpath) 
{
    Char16[]? p2 = path.to_utf16(mem);
    if (catch err = p2) return err~;
    defer free(p2);
    
    if (p2.len >= wpath.len-1) return PATH_TOO_LONG~;
    
    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;
    return p2.len;
}

fn bool file_exists(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return false;
    
    Dword attrs = getFileAttributesW(&wpath[0]);
    return attrs != INVALID_FILE_ATTRIBUTES;
}

fn long? file_size(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return err~;
    
    Win32FileAttributeData file_info;
    if (!getFileAttributesExW(&wpath[0], 0, &file_info)) {
        return win_error_to_fault()~;
    }
    
    long size = ((long)file_info.nFileSizeHigh << 32) | (long)file_info.nFileSizeLow;
    return size;
}

fn long? last_modified(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return err~;
    
    Win32FileAttributeData file_info;
    if (!getFileAttributesExW(&wpath[0], 0, &file_info)) {
        return win_error_to_fault()~;
    }
    
    long filetime = ((long)file_info.ftLastWriteTime_high << 32) | (long)file_info.ftLastWriteTime_low;
    return filetime;
}

fn bool is_dir(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return false;
    
    Dword attrs = getFileAttributesW(&wpath[0]);
    if (attrs == INVALID_FILE_ATTRIBUTES) return false;
    
    return (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

fn bool is_file(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return false;
    
    Dword attrs = getFileAttributesW(&wpath[0]);
    if (attrs == INVALID_FILE_ATTRIBUTES) return false;
    
    return (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

fn bool is_link(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return false;
    
    Dword attrs = getFileAttributesW(&wpath[0]);
    if (attrs == INVALID_FILE_ATTRIBUTES) return false;
    
    return (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
}

fn sz? read_link(String path, char[] output) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return err~;
    
    Handle handle = createFileW(
        &wpath[0], 0, 
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        null, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT,
        INVALID_HANDLE_VALUE);
    
    if (handle == INVALID_HANDLE_VALUE) {
        return win_error_to_fault()~;
    }
    
    defer closeHandle(handle);
    
    char[16384] buffer;
    Dword bytes_returned;
    
    if (!deviceIoControl(handle, FSCTL_GET_REPARSE_POINT, null, 0,
        &buffer, 16384, &bytes_returned, null)) {
        return win_error_to_fault()~;
    }
    
    ReparseDataBuffer* reparse = (ReparseDataBuffer*)&buffer;
    
    if ((reparse.reparseTag != IO_REPARSE_TAG_SYMLINK) && 
        (reparse.reparseTag != IO_REPARSE_TAG_MOUNT_POINT)) {
        return GENERAL_ERR~;
    }

    Char16* target = (Char16*)&reparse.pathBuffer[reparse.printNameOffset / 2];
    sz len = reparse.printNameLength / 2;
    
    String? s = string::from_utf16(tmem, target[0:len]);
    if (catch err = s) return GENERAL_ERR~;
    defer s.free(tmem);
    
    if (s.len >= output.len) return PATH_TOO_LONG~;
    
    output[0:s.len] = s[0:s.len];
    output[s.len] = 0;
    
    return (sz)s.len;
}

fn bool is_readable(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return false;
    
    Handle handle = createFileW(
        &wpath[0], GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        null, OPEN_EXISTING, 0, INVALID_HANDLE_VALUE);
    
    if (handle == INVALID_HANDLE_VALUE) return false;
    
    defer closeHandle(handle);
    return true;
}

fn bool is_writeable(String path) 
{
    Char16[260] wpath;
    sz? n = utf8to16(path, &wpath);
    if (catch err = n) return false;

    Handle handle = createFileW(
        &wpath[0], GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        null, OPEN_EXISTING, 0, INVALID_HANDLE_VALUE);
    
    if (handle == INVALID_HANDLE_VALUE) return false;
    
    defer closeHandle(handle);
    return true;
}

fn bool is_executable(String path) 
{
    if (!file_exists(path)) return false;
    if (is_dir(path)) return false;
    
    sz? idx = path.rindex_of_char('.');
    if (catch idx) return false;
    
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
*/
