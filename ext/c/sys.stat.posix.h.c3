// sys.stat.posix.h.c3

module c::sys::stat @if(!env::WIN32); // Posix

import c::errno;

extern fn CInt stat(char* path, Stat_t* buf);
extern fn CInt lstat(char* path, Stat_t* buf);
extern fn CInt fstat(CInt fd, Stat_t* buf);

extern fn CInt access(char* path, CInt mode);
extern fn CLong readlink(char* path, char* buf, CULong bufsize);
extern fn CInt chmod(char* path, Mode_t mode);
extern fn CInt mkdir(char *pathname, Mode_t mode);
extern fn Mode_t umask(Mode_t);

// File mode constants
const CUInt S_IFMT   = 0o170000;  // Bit mask for file type
const CUInt S_IFSOCK = 0o140000;  // Socket
const CUInt S_IFLNK  = 0o120000;  // Symbolic link
const CUInt S_IFREG  = 0o100000;  // Regular file
const CUInt S_IFBLK  = 0o060000;  // Block device
const CUInt S_IFDIR  = 0o040000;  // Directory
const CUInt S_IFCHR  = 0o020000;  // Character device
const CUInt S_IFIFO  = 0o010000;  // FIFO

// Permission bits
const CUInt S_ISUID  = 0o4000;    // Set UID bit
const CUInt S_ISGID  = 0o2000;    // Set GID bit
const CUInt S_ISVTX  = 0o1000;    // Sticky bit
const CUInt S_IRWXU  = 0o0700;    // Owner permissions
const CUInt S_IRUSR  = 0o0400;    // Owner read
const CUInt S_IWUSR  = 0o0200;    // Owner write
const CUInt S_IXUSR  = 0o0100;    // Owner execute
const CUInt S_IRWXG  = 0o0070;    // Group permissions
const CUInt S_IRWXO  = 0o0007;    // Other permissions

// Access mode constants
const CInt F_OK = 0;  // File exists
const CInt R_OK = 4;  // Read permission
const CInt W_OK = 2;  // Write permission
const CInt X_OK = 1;  // Execute permission

const int MAX_PATH = 1024;

/*
// Helper macro to convert String to ZString safely
macro ZString? path_to_zstr(String path, char[] buffer)
{
    if (path.len >= buffer.len) return errno::E_GENERAL_ERR~;
    buffer[0:path.len] = path[0:path.len];
    buffer[path.len] = 0;  // Add null terminator
    return (ZString)&buffer[0];
}


fn ulong? file_size(String path)
{
    char[MAX_PATH] p2; 
    ZString zpath = path_to_zstr(path, &p2)!;
    
    Stat_t st;
    if (stat(zpath, &st) != 0) {
        return errno::get_fault()~;
    }
    
    return (ulong)st.st_size;
}

fn bool file_exists(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    return access(zpath, F_OK) == 0;
}

fn bool is_dir(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    Stat_t st;
    if (stat(zpath, &st) != 0) return false;
    
    return (st.st_mode & S_IFMT) == S_IFDIR;
}

fn bool is_file(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    Stat_t st;
    if (stat(zpath, &st) != 0) return false;
    
    return (st.st_mode & S_IFMT) == S_IFREG;
}

fn bool is_link(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    Stat_t st;
    // lstat doesn't follow symbolic links
    if (lstat(zpath, &st) != 0) return false;
    
    return (st.st_mode & S_IFMT) == S_IFLNK;
}

fn long? last_modified(String path)
{
    char[MAX_PATH] p2; 
    ZString zpath = path_to_zstr(path, &p2)!;
    
    Stat_t st;
    if (stat(zpath, &st) != 0) {
        return errno::get_fault()~;
    }
    
    return st.st_mtime;  // Macro handles platform differences
}

fn bool is_readable(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    return access(zpath, R_OK) == 0;
}

fn bool is_writeable(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    return access(zpath, W_OK) == 0;
}

fn bool is_executable(String path)
{
    char[MAX_PATH] p2; 
    ZString? zpath = path_to_zstr(path, &p2);
    if (catch zpath) return false;
    
    return access(zpath, X_OK) == 0;
}

fn sz? read_link(String path, char[] output)
{
    char[MAX_PATH] p2; 
    ZString zpath = path_to_zstr(path, &p2)!;
    
    // Check for empty buffer
    if (output.len == 0) {
        return errno::E_GENERAL_ERR~;
    }
    
    CLong n = readlink(zpath, output.ptr, (CULong)output.len-1);
    
    if (n < 0) {
        return errno::get_fault()~;
    }
    
    output[n] = 0;
    return (sz)n;
}

*/
