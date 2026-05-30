// io.h.c3

module c::io;

// ========== Linux ==========

module c::io @if(env::LINUX);

// Linux does not have io.h as a standard header
// File I/O operations are in unistd.h and fcntl.h
// 
// For POSIX file operations, use:
// - unistd module for read(), write(), close(), lseek(), etc.
// - fcntl module for open(), fcntl(), etc.
//
// This module provides compatibility wrappers if needed

// Compatibility note: Some functions may be available through unistd.h
// but are not part of a separate io.h on Linux

// If you need low-level I/O on Linux, import:
// import unistd;
// import fcntl;

// ========== Darwin (macOS) ==========

module c::io @if(env::DARWIN);

// macOS does not have io.h as a standard header
// File I/O operations are in unistd.h and fcntl.h
//
// For POSIX file operations, use:
// - unistd module
// - fcntl module

// ========== FreeBSD ==========

module c::io @if(env::FREEBSD);

// FreeBSD does not have io.h as a standard header
// Use unistd.h and fcntl.h instead

// ========== NetBSD ==========

module c::io @if(env::NETBSD);

// NetBSD does not have io.h as a standard header
// Use unistd.h and fcntl.h instead

// ========== OpenBSD ==========

module c::io @if(env::OPENBSD);

// OpenBSD does not have io.h as a standard header
// Use unistd.h and fcntl.h instead

// ========== Windows ==========

module c::io @if(env::WIN32);

// Windows io.h - Low-level I/O functions

// File operations
extern fn int _open(char* filename, int oflag, ...);
extern fn int _wopen(ushort* filename, int oflag, ...);
extern fn int _sopen(char* filename, int oflag, int shflag, ...);
extern fn int _wsopen(ushort* filename, int oflag, int shflag, ...);
extern fn int _sopen_s(int* pfh, char* filename, int oflag, int shflag, int pmode);
extern fn int _wsopen_s(int* pfh, ushort* filename, int oflag, int shflag, int pmode);

extern fn int _close(int fd);
extern fn int _read(int fd, void* buffer, uint count);
extern fn int _write(int fd, void* buffer, uint count);

// File positioning
extern fn long _lseek(int fd, long offset, int origin);
extern fn long _lseeki64(int fd, long offset, int origin);
extern fn long _tell(int fd);
extern fn long _telli64(int fd);

// File information
extern fn int _eof(int fd);
extern fn long _filelength(int fd);
extern fn long _filelengthi64(int fd);

// File modification
extern fn int _chsize(int fd, long size);
extern fn int _chsize_s(int fd, long size);
extern fn int _commit(int fd);

// File duplication
extern fn int _dup(int fd);
extern fn int _dup2(int fd1, int fd2);

// Pipe
extern fn int _pipe(int* pfds, uint psize, int textmode);

// Terminal
extern fn int _isatty(int fd);

// File access and permissions
extern fn int _access(char* path, int mode);
extern fn int _waccess(ushort* path, int mode);
extern fn int _access_s(char* path, int mode);
extern fn int _waccess_s(ushort* path, int mode);
extern fn int _chmod(char* filename, int pmode);
extern fn int _wchmod(ushort* filename, int pmode);

// Temporary files
extern fn int _umask(int pmode);
extern fn char* _mktemp(char* template);
extern fn ushort* _wmktemp(ushort* template);
extern fn int _mktemp_s(char* template, sz sizeInChars);
extern fn int _wmktemp_s(ushort* template, sz sizeInWords);

// File removal
extern fn int _unlink(char* filename);
extern fn int _wunlink(ushort* filename);

// Text/Binary mode
extern fn int _setmode(int fd, int mode);
extern fn int _get_osfhandle(int fd);
extern fn int _open_osfhandle(iptr osfhandle, int flags);

// Locking
extern fn int _locking(int fd, int mode, long nbytes);

// Finding files
extern fn long _findfirst(char* filespec, void* fileinfo);
extern fn long _findfirsti64(char* filespec, void* fileinfo);
extern fn long _wfindfirst(ushort* filespec, void* fileinfo);
extern fn long _wfindfirsti64(ushort* filespec, void* fileinfo);
extern fn int _findnext(long handle, void* fileinfo);
extern fn int _findnexti64(long handle, void* fileinfo);
extern fn int _wfindnext(long handle, void* fileinfo);
extern fn int _wfindnexti64(long handle, void* fileinfo);
extern fn int _findclose(long handle);

// File attribute structures
struct Finddata32T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    uint size;
    char[260] name;
}

struct Finddata32I64T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    long size;
    char[260] name;
}

struct Finddata64I32T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    uint size;
    char[260] name;
}

struct Finddata64T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    long size;
    char[260] name;
}

// Wide character versions
struct WFinddata32T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    uint size;
    ushort[260] name;
}

struct WFinddata32I64T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    long size;
    ushort[260] name;
}

struct WFinddata64I32T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    uint size;
    ushort[260] name;
}

struct WFinddata64T {
    uint attrib;
    long time_create;
    long time_access;
    long time_write;
    long size;
    ushort[260] name;
}

// File open flags (oflag for _open)
const int _O_RDONLY = 0x0000;      // Open for reading only
const int _O_WRONLY = 0x0001;      // Open for writing only
const int _O_RDWR = 0x0002;        // Open for reading and writing
const int _O_APPEND = 0x0008;      // Append mode
const int _O_CREAT = 0x0100;       // Create if doesn't exist
const int _O_TRUNC = 0x0200;       // Truncate to 0 length
const int _O_EXCL = 0x0400;        // Exclusive open
const int _O_TEXT = 0x4000;        // Text mode
const int _O_BINARY = 0x8000;      // Binary mode
const int _O_RANDOM = 0x0010;      // Random access hint
const int _O_SEQUENTIAL = 0x0020;  // Sequential access hint
const int _O_TEMPORARY = 0x0040;   // Temporary file
const int _O_NOINHERIT = 0x0080;   // Don't inherit on exec
const int _O_SHORT_LIVED = 0x1000; // Short-lived file
const int _O_WTEXT = 0x10000;      // UTF-16 text mode
const int _O_U16TEXT = 0x20000;    // UTF-16 no BOM
const int _O_U8TEXT = 0x40000;     // UTF-8

// Compatibility aliases (without underscore)
const int O_RDONLY = _O_RDONLY;
const int O_WRONLY = _O_WRONLY;
const int O_RDWR = _O_RDWR;
const int O_APPEND = _O_APPEND;
const int O_CREAT = _O_CREAT;
const int O_TRUNC = _O_TRUNC;
const int O_EXCL = _O_EXCL;
const int O_TEXT = _O_TEXT;
const int O_BINARY = _O_BINARY;

// Share flags (shflag for _sopen)
const int _SH_DENYRW = 0x10;       // Deny read/write
const int _SH_DENYWR = 0x20;       // Deny write
const int _SH_DENYRD = 0x30;       // Deny read
const int _SH_DENYNO = 0x40;       // Deny none
const int _SH_SECURE = 0x80;       // Secure mode

const int SH_DENYRW = _SH_DENYRW;
const int SH_DENYWR = _SH_DENYWR;
const int SH_DENYRD = _SH_DENYRD;
const int SH_DENYNO = _SH_DENYNO;

// Permission modes (pmode)
const int _S_IREAD = 0x0100;       // Read permission
const int _S_IWRITE = 0x0080;      // Write permission
const int _S_IEXEC = 0x0040;       // Execute permission

const int S_IREAD = _S_IREAD;
const int S_IWRITE = _S_IWRITE;
const int S_IEXEC = _S_IEXEC;

// Access modes (mode for _access)
const int _A_NORMAL = 0x00;        // Normal file
const int _A_RDONLY = 0x01;        // Read-only file
const int _A_HIDDEN = 0x02;        // Hidden file
const int _A_SYSTEM = 0x04;        // System file
const int _A_SUBDIR = 0x10;        // Subdirectory
const int _A_ARCH = 0x20;          // Archive file

// File attribute constants
const int _A_VOLID = 0x08;         // Volume label

// Access permission constants for _access
const int F_OK = 0;                // Test for existence
const int X_OK = 1;                // Test for execute permission
const int W_OK = 2;                // Test for write permission
const int R_OK = 4;                // Test for read permission

// Seek origins (origin for _lseek)
const int SEEK_SET = 0;            // Beginning of file
const int SEEK_CUR = 1;            // Current position
const int SEEK_END = 2;            // End of file

// Locking modes (mode for _locking)
const int _LK_UNLCK = 0;           // Unlock
const int _LK_LOCK = 1;            // Lock (blocking)
const int _LK_NBLCK = 2;           // Lock (non-blocking)
const int _LK_RLCK = 3;            // Lock for writing (blocking)
const int _LK_NBRLCK = 4;          // Lock for writing (non-blocking)

const int LK_UNLCK = _LK_UNLCK;
const int LK_LOCK = _LK_LOCK;
const int LK_NBLCK = _LK_NBLCK;
const int LK_RLCK = _LK_RLCK;
const int LK_NBRLCK = _LK_NBRLCK;

// Setmode flags
const int _O_RAW = _O_BINARY;

// POSIX compatibility (deprecated, _ versions)
extern fn int open(char* filename, int oflag, ...) @cname("_open");
extern fn int close(int fd) @cname("_close");
extern fn int read(int fd, void* buffer, uint count) @cname("_read");
extern fn int write(int fd, void* buffer, uint count) @cname("_write");
extern fn long lseek(int fd, long offset, int origin) @cname("_lseek");
extern fn int dup(int fd) @cname("_dup");
extern fn int dup2(int fd1, int fd2) @cname("_dup2");
extern fn int access(char* path, int mode) @cname("_access");
extern fn int chmod(char* filename, int pmode) @cname("_chmod");
extern fn int umask(int pmode) @cname("_umask");
extern fn int unlink(char* filename) @cname("_unlink");
extern fn int isatty(int fd) @cname("_isatty");

