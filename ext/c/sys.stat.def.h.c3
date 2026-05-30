// sys.stat.def.h.c3


module c::sys::stat @if(env::WIN32);

extern fn CInt _wstat(Char16* path, Stat_t* stat) @if(env::ARCH_32_BIT) @private;
extern fn CInt _wstat64(Char16* path, Stat_t* stat) @if(env::ARCH_64_BIT) @private;

fn sz utf8to16(ZString zpath, Char16[] wpath) @private
{
    String path = zpath.str_view();
    Char16[]? p2 = path.to_utf16(mem);
    if (catch err = p2) return -1;
    defer free(p2);
    
    if (p2.len >= wpath.len-1) return -1;
    
    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;
    return p2.len;
}


fn CInt stat(ZString path, Stat_t* stbuf) 
{
    Char16[520] wpath;
    sz n = utf8to16(path, &wpath);
    if (n < 0) return -1;
    
    $if env::ARCH_32_BIT:
        return _wstat(&wpath[0], stbuf);
    $else
        return _wstat64(&wpath[0], stbuf);
    $endif
}

module c::sys::stat;

// Different definitions of `struct stat` on various combinations of following systems
//
// OS: LINUX, DARWIN(macOS), WIN32, FREEBSD, NETBSD, OPENBSD, ANDROID
// ARCH: x86_64, X86(32bit), AARCH64(arm64), ARM, PPC64


module c::sys::stat @if((env::LINUX || env::ANDROID) && 
    (env::ARCH_TYPE == X86_64 ||
     env::ARCH_TYPE == PPC64));

alias Ino_t = ulong;
alias Dev_t = ulong;
alias Mode_t = uint;

struct Stat_t
{
    ulong st_dev;       // 8 bytes
    ulong st_ino;       // 8 bytes
    ulong st_nlink;     // 8 bytes
    uint st_mode;       // 4 bytes
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    int __padding0;     // 4 bytes
    ulong st_rdev;      // 8 bytes 
    long st_size;       // 8 bytes
    long st_blksize;    // 8 bytes 
    long st_blocks;     // 8 bytes
    long st_atime;      // 8 bytes 
    long st_atime_nsec; // 8 bytes
    long st_mtime;      // 8 bytes 
    long st_mtime_nsec; // 8 bytes
    long st_ctime;      // 8 bytes 
    long st_ctime_nsec; // 8 bytes
    long[3] __unused;   // 24 bytes
} // 144 bytes


module c::sys::stat @if((env::LINUX || env::ANDROID) && env::ARCH_TYPE == AARCH64);

alias Ino_t = ulong;
alias Dev_t = ulong;
alias Mode_t = uint;

struct Stat_t
{
    ulong st_dev;        // 8 bytes
    ulong st_ino;        // 8 bytes
    uint st_mode;        // 4 bytes
    uint st_nlink;       // 4 bytes
    uint st_uid;         // 4 bytes
    uint st_gid;         // 4 bytes
    ulong st_rdev;       // 8 bytes 
    ulong __padding1;    // 8 bytes
    long st_size;        // 8 bytes
    int st_blksize;      // 4 bytes
    int __padding2;      // 4 bytes
    long st_blocks;      // 8 bytes
    long st_atime;       // 8 bytes 
    ulong st_atime_nsec; // 8 bytes
    long st_mtime;       // 8 bytes 
    ulong st_mtime_nsec; // 8 bytes
    long st_ctime;       // 8 bytes
    ulong st_ctime_nsec; // 8 bytes
    int[2] __unused;     // 8 bytes
} // 128 bytes


module c::sys::stat @if(env::LINUX && (env::ARCH_TYPE == X86 || env::ARCH_TYPE == ARM));

alias Ino_t = uint;
alias Dev_t = ulong;
alias Mode_t = uint;

struct Stat_t 
{
    ulong st_dev;       // 8 bytes
    uint __padding1;    // 2 bytes
    uint __st_ino;      // 4 bytes
    uint st_mode;       // 4 bytes
    uint st_nlink;      // 4 bytes
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    ulong st_rdev;      // 8 bytes 
    uint __padding2;    // 4 bytes
    long st_size;       // 8 bytes
    int st_blksize;     // 4 bytes
    long st_blocks;     // 8 bytes 
    int st_atime;       // 4 bytes 
    uint st_atime_nsec; // 4 bytes
    int st_mtime;       // 4 bytes 
    uint st_mtime_nsec; // 4 bytes
    int st_ctime;       // 4 bytes 
    uint st_ctime_nsec; // 4 bytes
    ulong st_ino;       // 8 bytes
} // 96 bytes


module c::sys::stat @if(env::DARWIN && (env::ARCH_TYPE == X86_64 || env::ARCH_TYPE == AARCH64));

alias Ino_t = ulong;
alias Dev_t = uint;
alias Mode_t = ushort;

struct Stat_t
{
    uint st_dev;        // 4 bytes
    ushort st_mode;     // 2 bytes
    ushort st_nlink;    // 2 bytes
    ulong st_ino;       // 8 bytes
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    uint st_rdev;       // 4 bytes
    int __padding;      // 4 bytes
    long st_atime;      // 8 bytes 
    long st_atime_nsec; // 8 bytes
    long st_mtime;      // 8 bytes 
    long st_mtime_nsec; // 8 bytes
    long st_ctime;      // 8 bytes 
    long st_ctime_nsec; // 8 bytes
    long st_btime;      // 8 bytes 
    long st_btime_nsec; // 8 bytes
    ulong st_size;      // 8 bytes
    ulong st_blocks;    // 8 bytes
    uint st_blksize;    // 4 bytes
    uint st_flags;      // 4 bytes
    uint st_gen;        // 4 bytes
    int st_lspare;      // 4 bytes 
    long[2] st_qspare;  // 16 bytes 
} // 144 bytes


module c::sys::stat @if(env::FREEBSD && (env::ARCH_TYPE == X86_64 || env::ARCH_TYPE == AARCH64));
// 2025 v13.x

alias Ino_t = ulong;
alias Dev_t = ulong;
alias Mode_t = ushort;

struct Stat_t
{
    ulong st_dev;       // 8 bytes
    ulong st_ino;       // 8 bytes
    ulong st_nlink;     // 8 bytes
    ushort st_mode;     // 2 bytes
    short st_bsdflags;  // 2 bytes 2025
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    int st_padding1;    // 4 bytes
    ulong st_rdev;      // 8 bytes
    long st_atime;      // 8 bytes 
    long st_atimensec;  // 8 bytes
    long st_mtime;      // 8 bytes 
    long st_mtimensec;  // 8 bytes
    long st_ctime;      // 8 bytes 
    long st_ctimensec;  // 8 bytes
    long st_birthtime;     // 8 bytes 
    long st_birthtimensec; // 8 bytes
    long st_size;       // 8 bytes
    long st_blocks;     // 8 bytes
    int st_blksize;     // 4 bytes
    uint st_flags;      // 4 bytes
    ulong st_gen;       // 8 bytes
    ulong st_filerev;   // 8 bytes 2025
    ulong[9] st_spare;  // 72 bytes 
} // 224 bytes

/* 2017
{
    ulong st_dev;       // 8 bytes
    ulong st_ino;       // 8 bytes
    ulong st_nlink;     // 8 bytes
    ushort st_mode;     // 2 bytes
    short st_padding0;  // 2 bytes
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    int st_padding1;    // 4 bytes
    ulong st_rdev;      // 8 bytes
    long st_atime;      // 8 bytes 
    long st_atimensec;  // 8 bytes
    long st_mtime;      // 8 bytes 
    long st_mtimensec;  // 8 bytes
    long st_ctime;      // 8 bytes 
    long st_ctimensec;  // 8 bytes
    long st_birthtime;     // 8 bytes 
    long st_birthtimensec; // 8 bytes
    long st_size;       // 8 bytes
    long st_blocks;     // 8 bytes
    int st_blksize;     // 4 bytes
    uint st_flags;      // 4 bytes
    ulong st_gen;       // 8 bytes
    ulong[10] st_spare;  // 80 bytes 
} // 224 bytes
*/


module c::sys::stat @if(env::OPENBSD && (env::ARCH_TYPE == X86_64 || env::ARCH_TYPE == AARCH64));
// __BSD_VISIBLE, __POSIX_VISIBLE > 200809

alias Ino_t = ulong;
alias Dev_t = uint;
alias Mode_t = uint;

struct Stat_t
{
    uint st_mode;       // 4 bytes
    uint st_dev;        // 4 bytes
    ulong st_ino;       // 8 bytes
    uint st_nlink;      // 4 bytes
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    uint st_rdev;       // 4 bytes
    long st_atime;      // 8 bytes 
    long st_atimensec;  // 8 bytes
    long st_mtime;      // 8 bytes 
    long st_mtimensec;  // 8 bytes
    long st_ctime;      // 8 bytes 
    long st_ctimensec;  // 8 bytes
    long st_size;       // 8 bytes
    long st_blocks;     // 8 bytes
    int st_blksize;     // 4 bytes
    uint st_flags;      // 4 bytes
    uint st_gen;        // 4 bytes
    int __padding;      // 4 bytes
    long st_birthtime;     // 8 bytes 
    long st_birthtimensec; // 8 bytes
} // 128 bytes


module c::sys::stat @if(env::NETBSD && (env::ARCH_TYPE == X86_64 || env::ARCH_TYPE == AARCH64));

alias Ino_t = ulong;
alias Dev_t = ulong;
alias Mode_t = uint;

struct Stat_t
{
    ulong st_dev;       // 8 bytes
    uint st_mode;       // 4 bytes
    int __padding1;     // 4 bytes
    ulong st_ino;       // 8 bytes
    uint st_nlink;      // 4 bytes
    uint st_uid;        // 4 bytes
    uint st_gid;        // 4 bytes
    int __padding2;     // 4 bytes
    ulong st_rdev;      // 8 bytes
    long st_atime;      // 8 bytes 
    long st_atime_nsec; // 8 bytes
    long st_mtime;      // 8 bytes 
    long st_mtime_nsec; // 8 bytes
    long st_ctime;      // 8 bytes 
    long st_ctime_nsec; // 8 bytes
    long st_btime;      // 8 bytes 
    long st_btime_nsec; // 8 bytes
    long st_size;       // 8 bytes
    long st_blocks;     // 8 bytes
    int st_blksize;     // 4 bytes
    uint st_flags;      // 4 bytes
    uint st_gen;        // 4 bytes
    uint[2] st_spare;   // 8 bytes
    int __padding3;     // 4 bytes
} // 152 bytes


module c::sys::stat @if(env::WIN32 && env::ARCH_TYPE == X86_64);

alias Ino_t = ushort;
alias Dev_t = uint;
alias Mode_t = ushort;

struct Stat_t
{
    uint st_dev;        // 4 bytes
    ushort st_ino;      // 2 bytes 
    ushort st_mode;     // 2 bytes
    short st_nlink;     // 2 bytes
    short st_uid;       // 2 bytes
    short st_gid;       // 2 bytes
    ushort __pad1;      // 2 bytes
    uint st_rdev;       // 4 bytes
    uint __pad2;        // 4 bytes
    long st_size;       // 8 bytes
    long st_atime;      // 8 bytes
    long st_mtime;      // 8 bytes
    long st_ctime;      // 8 bytes
} // 56 bytes


module c::sys::stat @if(env::WIN32 && env::ARCH_TYPE == X86);

alias Ino_t = ushort;
alias Dev_t = uint;
alias Mode_t = ushort;

struct Stat_t
{
    uint st_dev;        // 4 bytes
    ushort st_ino;      // 2 bytes 
    ushort st_mode;     // 2 bytes
    short st_nlink;     // 2 bytes
    short st_uid;       // 2 bytes
    short st_gid;       // 2 bytes
    uint st_rdev;       // 4 bytes
    int st_size;        // 4 bytes
    int st_atime;       // 4 bytes
    int st_mtime;       // 4 bytes
    int st_ctime;       // 4 bytes
} // 34 bytes

