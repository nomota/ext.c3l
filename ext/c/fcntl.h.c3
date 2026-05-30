// fcntl.h.linux.c3

module c::fcntl @if(env::LINUX);

// ========== Function Declarations ==========

// Main fcntl functions
extern fn int open(char* pathname, int flags, ...);
extern fn int openat(int dirfd, char* pathname, int flags, ...);
extern fn int creat(char* pathname, uint mode);
extern fn int fcntl(int fd, int cmd, ...);

// POSIX advisory locking
extern fn int flock(int fd, int operation);

// Additional utility functions
extern fn int posix_fadvise(int fd, long offset, long len, int advice);
extern fn int posix_fallocate(int fd, long offset, long len);

// Splice and pipe functions (Linux-specific)
extern fn long splice(int fd_in, long* off_in, int fd_out, long* off_out, sz len, uint flags);
extern fn long tee(int fd_in, int fd_out, sz len, uint flags);
extern fn long vmsplice(int fd, IovecPtr* iov, sz nr_segs, uint flags);

extern fn int fallocate(int fd, int mode, long offset, long len);

// Synchronization functions
extern fn int fsync(int fd);
extern fn int fdatasync(int fd);
extern fn void sync();
extern fn int syncfs(int fd);

// Read/Write with offset (pread/pwrite family)
extern fn sz pread(int fd, void* buf, sz count, long offset);
extern fn sz pwrite(int fd, void* buf, sz count, long offset);
extern fn sz preadv(int fd, IovecPtr* iov, int iovcnt, long offset);
extern fn sz pwritev(int fd, IovecPtr* iov, int iovcnt, long offset);
extern fn sz preadv2(int fd, IovecPtr* iov, int iovcnt, long offset, int flags);
extern fn sz pwritev2(int fd, IovecPtr* iov, int iovcnt, long offset, int flags);

// File descriptor duplication
extern fn int dup(int oldfd);
extern fn int dup2(int oldfd, int newfd);
extern fn int dup3(int oldfd, int newfd, int flags);

extern fn int name_to_handle_at(int dirfd, char* pathname, FileHandle* handle, int* mount_id, int flags);
extern fn int open_by_handle_at(int mount_fd, FileHandle* handle, int flags);

// Linux: readahead
extern fn sz readahead(int fd, long offset, sz count);

extern fn int sync_file_range(int fd, long offset, long nbytes, uint flags);

extern fn int memfd_create(char* name, uint flags);

// Copy file range (Linux)
extern fn sz copy_file_range(int fd_in, long* off_in, int fd_out, long* off_out, sz len, uint flags);

// ========== Type Definitions ==========

// Helper type for iovec
struct IovecPtr {
    void* iov_base;
    sz iov_len;
}

// File lock structure
struct Flock {
    short l_type;
    short l_whence;
    long l_start;
    long l_len;
    int l_pid;
}

// File owner structure for F_GETOWN_EX/F_SETOWN_EX
struct FOwnerEx {
    int type;
    int pid;
}

// Name to handle and open by handle (Linux)
struct FileHandle {
    uint handle_bytes;
    int handle_type;
    char* f_handle;  // Flexible array member
}

// ========== Constants ==========

// File control options
const int F_DUPFD = 0;
const int F_GETFD = 1;
const int F_SETFD = 2;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int F_GETLK = 5;
const int F_SETLK = 6;
const int F_SETLKW = 7;
const int F_SETOWN = 8;
const int F_GETOWN = 9;

// File descriptor flags
const int FD_CLOEXEC = 1;

// File status flags
const int O_RDONLY = 0x0000;
const int O_WRONLY = 0x0001;
const int O_RDWR = 0x0002;
const int O_ACCMODE = 0x0003;

const int O_CREAT = 0x0040;
const int O_EXCL = 0x0080;
const int O_NOCTTY = 0x0100;
const int O_TRUNC = 0x0200;
const int O_APPEND = 0x0400;
const int O_NONBLOCK = 0x0800;
const int O_SYNC = 0x1000;
const int O_ASYNC = 0x2000;
const int O_DIRECTORY = 0x10000;
const int O_NOFOLLOW = 0x20000;
const int O_CLOEXEC = 0x80000;

// Advisory locking
const int LOCK_SH = 1;  // Shared lock
const int LOCK_EX = 2;  // Exclusive lock
const int LOCK_NB = 4;  // Non-blocking
const int LOCK_UN = 8;  // Unlock

// Seek constants
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;

// Advice values for posix_fadvise
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// Splice flags
const uint SPLICE_F_MOVE = 1;
const uint SPLICE_F_NONBLOCK = 2;
const uint SPLICE_F_MORE = 4;
const uint SPLICE_F_GIFT = 8;

// AT_* flags for openat and related functions
const int AT_FDCWD = -100;
const int AT_SYMLINK_NOFOLLOW = 0x100;
const int AT_REMOVEDIR = 0x200;
const int AT_SYMLINK_FOLLOW = 0x400;
const int AT_EACCESS = 0x200;

// Additional F_* commands
const int F_DUPFD_CLOEXEC = 1030;
const int F_GETSIG = 11;
const int F_SETSIG = 10;
const int F_SETLEASE = 1024;
const int F_GETLEASE = 1025;
const int F_NOTIFY = 1026;
const int F_CANCELLK = 1029;
const int F_SETPIPE_SZ = 1031;
const int F_GETPIPE_SZ = 1032;
const int F_ADD_SEALS = 1033;
const int F_GET_SEALS = 1034;
const int F_GET_RW_HINT = 1035;
const int F_SET_RW_HINT = 1036;
const int F_GET_FILE_RW_HINT = 1037;
const int F_SET_FILE_RW_HINT = 1038;

// File sealing (memfd)
const int F_SEAL_SEAL = 0x0001;
const int F_SEAL_SHRINK = 0x0002;
const int F_SEAL_GROW = 0x0004;
const int F_SEAL_WRITE = 0x0008;
const int F_SEAL_FUTURE_WRITE = 0x0010;

// Directory notification
const int DN_ACCESS = 0x00000001;
const int DN_MODIFY = 0x00000002;
const int DN_CREATE = 0x00000004;
const int DN_DELETE = 0x00000008;
const int DN_RENAME = 0x00000010;
const int DN_ATTRIB = 0x00000020;
const uint DN_MULTISHOT = 0x80000000;

// Lock types
const int F_RDLCK = 0;
const int F_WRLCK = 1;
const int F_UNLCK = 2;

// More O_* flags
const int O_DSYNC = 0x1000;
const int O_DIRECT = 0x4000;
const int O_LARGEFILE = 0x8000;
const int O_NOATIME = 0x40000;
const int O_PATH = 0x200000;
const int O_TMPFILE = 0x410000;

// Access mode mask
const int O_NDELAY = O_NONBLOCK;

// RWH hints
const ulong RWH_WRITE_LIFE_NOT_SET = 0;
const ulong RWH_WRITE_LIFE_NONE = 1;
const ulong RWH_WRITE_LIFE_SHORT = 2;
const ulong RWH_WRITE_LIFE_MEDIUM = 3;
const ulong RWH_WRITE_LIFE_LONG = 4;
const ulong RWH_WRITE_LIFE_EXTREME = 5;

const int F_OWNER_TID = 0;
const int F_OWNER_PID = 1;
const int F_OWNER_PGRP = 2;

const int F_GETOWN_EX = 16;
const int F_SETOWN_EX = 15;

// Linux-specific: fallocate modes
const int FALLOC_FL_KEEP_SIZE = 0x01;
const int FALLOC_FL_PUNCH_HOLE = 0x02;
const int FALLOC_FL_NO_HIDE_STALE = 0x04;
const int FALLOC_FL_COLLAPSE_RANGE = 0x08;
const int FALLOC_FL_ZERO_RANGE = 0x10;
const int FALLOC_FL_INSERT_RANGE = 0x20;
const int FALLOC_FL_UNSHARE_RANGE = 0x40;

// RWF flags for preadv2/pwritev2
const int RWF_HIPRI = 0x00000001;
const int RWF_DSYNC = 0x00000002;
const int RWF_SYNC = 0x00000004;
const int RWF_NOWAIT = 0x00000008;
const int RWF_APPEND = 0x00000010;

// AT flags (additional)
const int AT_EMPTY_PATH = 0x1000;
const int AT_STATX_SYNC_TYPE = 0x6000;
const int AT_STATX_SYNC_AS_STAT = 0x0000;
const int AT_STATX_FORCE_SYNC = 0x2000;
const int AT_STATX_DONT_SYNC = 0x4000;
const int AT_RECURSIVE = 0x8000;

// Linux: sync_file_range
const uint SYNC_FILE_RANGE_WAIT_BEFORE = 1;
const uint SYNC_FILE_RANGE_WRITE = 2;
const uint SYNC_FILE_RANGE_WAIT_AFTER = 4;

// memfd_create (Linux)
const uint MFD_CLOEXEC = 0x0001;
const uint MFD_ALLOW_SEALING = 0x0002;
const uint MFD_HUGETLB = 0x0004;




module c::fcntl @if(env::DARWIN);

// ========== Function Declarations ==========

// Main fcntl functions
extern fn int open(char* pathname, int flags, ...);
extern fn int openat(int dirfd, char* pathname, int flags, ...);
extern fn int creat(char* pathname, uint mode);
extern fn int fcntl(int fd, int cmd, ...);

// POSIX advisory locking
extern fn int flock(int fd, int operation);

// Additional utility functions
extern fn int posix_fadvise(int fd, long offset, long len, int advice);
extern fn int posix_fallocate(int fd, long offset, long len);

// Synchronization functions
extern fn int fsync(int fd);
extern fn int fdatasync(int fd);
extern fn void sync();

// Read/Write with offset (pread/pwrite family)
extern fn sz pread(int fd, void* buf, sz count, long offset);
extern fn sz pwrite(int fd, void* buf, sz count, long offset);
extern fn sz preadv(int fd, IovecPtr* iov, int iovcnt, long offset);
extern fn sz pwritev(int fd, IovecPtr* iov, int iovcnt, long offset);

// File descriptor duplication
extern fn int dup(int oldfd);
extern fn int dup2(int oldfd, int newfd);

// ========== Type Definitions ==========

// Helper type for iovec
struct IovecPtr {
    void* iov_base;
    sz iov_len;
}

// File lock structure
struct Flock {
    long l_start;
    long l_len;
    int l_pid;
    short l_type;
    short l_whence;
}

// File owner structure for F_GETOWN_EX/F_SETOWN_EX
struct FOwnerEx {
    int type;
    int pid;
}

// radvisory structure for F_RDADVISE
struct Radvisory {
    long ra_offset;
    int ra_count;
}

// Log2 Physical block size structure for F_LOG2PHYS
struct Log2Phys {
    uint l2p_flags;
    long l2p_contigbytes;
    long l2p_devoffset;
}

// macOS: F_PREALLOCATE modes
struct FStore {
    uint fst_flags;
    int fst_posmode;
    long fst_offset;
    long fst_length;
    long fst_bytesalloc;
}

// ========== Constants ==========

// File control options
const int F_DUPFD = 0;
const int F_GETFD = 1;
const int F_SETFD = 2;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int F_GETOWN = 5;
const int F_SETOWN = 6;
const int F_GETLK = 7;
const int F_SETLK = 8;
const int F_SETLKW = 9;

// File descriptor flags
const int FD_CLOEXEC = 1;

// File status flags
const int O_RDONLY = 0x0000;
const int O_WRONLY = 0x0001;
const int O_RDWR = 0x0002;
const int O_ACCMODE = 0x0003;

const int O_NONBLOCK = 0x0004;
const int O_APPEND = 0x0008;
const int O_SHLOCK = 0x0010;
const int O_EXLOCK = 0x0020;
const int O_ASYNC = 0x0040;
const int O_SYNC = 0x0080;
const int O_NOFOLLOW = 0x0100;
const int O_CREAT = 0x0200;
const int O_TRUNC = 0x0400;
const int O_EXCL = 0x0800;
const int O_NOCTTY = 0x20000;
const int O_DIRECTORY = 0x100000;
const int O_SYMLINK = 0x200000;
const int O_CLOEXEC = 0x1000000;

// Advisory locking
const int LOCK_SH = 0x01;  // Shared lock
const int LOCK_EX = 0x02;  // Exclusive lock
const int LOCK_NB = 0x04;  // Non-blocking
const int LOCK_UN = 0x08;  // Unlock

// Seek constants
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
const int SEEK_HOLE = 3;
const int SEEK_DATA = 4;

// Advice values for posix_fadvise
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// AT_* flags for openat and related functions
const int AT_FDCWD = -2;
const int AT_EACCESS = 0x0010;
const int AT_SYMLINK_NOFOLLOW = 0x0020;
const int AT_SYMLINK_FOLLOW = 0x0040;
const int AT_REMOVEDIR = 0x0080;

// Additional F_* commands
const int F_DUPFD_CLOEXEC = 67;
const int F_RDADVISE = 44;
const int F_RDAHEAD = 45;
const int F_NOCACHE = 48;
const int F_GETPATH = 50;
const int F_PREALLOCATE = 42;
const int F_SETSIZE = 43;
const int F_RDLCK = 1;
const int F_UNLCK = 2;
const int F_WRLCK = 3;

// Additional F_* commands (macOS specific)
const int F_GETOWN_EX = 16;
const int F_SETOWN_EX = 15;
const int F_GETLKPID = 66;
const int F_SETBACKINGSTORE = 70;
const int F_GETCODEDIR = 72;
const int F_SETPROTECTIONCLASS = 64;
const int F_GETPROTECTIONCLASS = 63;

// More O_* flags
const int O_DSYNC = O_SYNC;
const int O_NDELAY = O_NONBLOCK;
const int O_EVTONLY = 0x8000;
const uint O_POPUP = 0x80000000;
const uint O_ALERT = 0x20000000;

const int F_OWNER_TID = 0;
const int F_OWNER_PID = 1;
const int F_OWNER_PGRP = 2;

// macOS: F_PREALLOCATE modes
const uint F_ALLOCATECONTIG = 0x02;
const uint F_ALLOCATEALL = 0x04;

const int F_PEOFPOSMODE = 3;
const int F_VOLPOSMODE = 4;

const uint F_LOG2PHYS_NEWINFO = 0x00000001;

// F_GETPATH max length
const int MAXPATHLEN = 1024;




module c::fcntl @if(env::FREEBSD);

// ========== Function Declarations ==========

// Main fcntl functions
extern fn int open(char* pathname, int flags, ...);
extern fn int openat(int dirfd, char* pathname, int flags, ...);
extern fn int creat(char* pathname, uint mode);
extern fn int fcntl(int fd, int cmd, ...);

// POSIX advisory locking
extern fn int flock(int fd, int operation);

// Additional utility functions
extern fn int posix_fadvise(int fd, long offset, long len, int advice);
extern fn int posix_fallocate(int fd, long offset, long len);

// Synchronization functions
extern fn int fsync(int fd);
extern fn int fdatasync(int fd);
extern fn void sync();

// Read/Write with offset (pread/pwrite family)
extern fn sz pread(int fd, void* buf, sz count, long offset);
extern fn sz pwrite(int fd, void* buf, sz count, long offset);
extern fn sz preadv(int fd, IovecPtr* iov, int iovcnt, long offset);
extern fn sz pwritev(int fd, IovecPtr* iov, int iovcnt, long offset);

// File descriptor duplication
extern fn int dup(int oldfd);
extern fn int dup2(int oldfd, int newfd);

// ========== Type Definitions ==========

// Helper type for iovec
struct IovecPtr {
    void* iov_base;
    sz iov_len;
}

// File lock structure
struct Flock {
    long l_start;
    long l_len;
    int l_pid;
    short l_type;
    short l_whence;
    int l_sysid;
}

// File owner structure for F_GETOWN_EX/F_SETOWN_EX
struct FOwnerEx {
    int type;
    int pid;
}

// FreeBSD: fspacectl (space control)
struct Spacectl_range {
    long r_offset;
    long r_len;
}

// FreeBSD: fhopen, fhstat, fhstatfs
struct FHandle {
    int fh_fsid_0;
    int fh_fsid_1;
    ushort fh_len;
    char[16] fh_data;
}

// ========== Constants ==========

// File control options
const int F_DUPFD = 0;
const int F_GETFD = 1;
const int F_SETFD = 2;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int F_GETOWN = 5;
const int F_SETOWN = 6;
const int F_GETLK = 11;
const int F_SETLK = 12;
const int F_SETLKW = 13;

// File descriptor flags
const int FD_CLOEXEC = 1;

// File status flags
const int O_RDONLY = 0x0000;
const int O_WRONLY = 0x0001;
const int O_RDWR = 0x0002;
const int O_ACCMODE = 0x0003;

const int O_NONBLOCK = 0x0004;
const int O_APPEND = 0x0008;
const int O_SHLOCK = 0x0010;
const int O_EXLOCK = 0x0020;
const int O_ASYNC = 0x0040;
const int O_FSYNC = 0x0080;
const int O_SYNC = 0x0080;
const int O_NOFOLLOW = 0x0100;
const int O_CREAT = 0x0200;
const int O_TRUNC = 0x0400;
const int O_EXCL = 0x0800;
const int O_NOCTTY = 0x8000;
const int O_DIRECT = 0x00010000;
const int O_DIRECTORY = 0x00020000;
const int O_EXEC = 0x00040000;
const int O_TTY_INIT = 0x00080000;
const int O_CLOEXEC = 0x00100000;
const int O_VERIFY = 0x00200000;

// Advisory locking
const int LOCK_SH = 0x01;  // Shared lock
const int LOCK_EX = 0x02;  // Exclusive lock
const int LOCK_NB = 0x04;  // Non-blocking
const int LOCK_UN = 0x08;  // Unlock

// Seek constants
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
const int SEEK_DATA = 3;
const int SEEK_HOLE = 4;

// Advice values for posix_fadvise
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// AT_* flags for openat and related functions
const int AT_FDCWD = -100;
const int AT_EACCESS = 0x0100;
const int AT_SYMLINK_NOFOLLOW = 0x0200;
const int AT_SYMLINK_FOLLOW = 0x0400;
const int AT_REMOVEDIR = 0x0800;

// Additional F_* commands
const int F_DUPFD_CLOEXEC = 17;
const int F_DUP2FD = 10;
const int F_DUP2FD_CLOEXEC = 18;
const int F_GETOWN_EX = 16;
const int F_SETOWN_EX = 15;
const int F_OGETLK = 7;
const int F_OSETLK = 8;
const int F_OSETLKW = 9;
const int F_RDAHEAD = 16;
const int F_READAHEAD = 15;
const int F_ADD_SEALS = 19;
const int F_GET_SEALS = 20;
const int F_ISUNIONSTACK = 21;
const int F_KINFO = 22;

// Lock types
const int F_RDLCK = 1;
const int F_UNLCK = 2;
const int F_WRLCK = 3;

// File sealing (similar to Linux)
const int F_SEAL_SEAL = 0x0001;
const int F_SEAL_SHRINK = 0x0002;
const int F_SEAL_GROW = 0x0004;
const int F_SEAL_WRITE = 0x0008;

// More O_* flags
const int O_DSYNC = O_SYNC;
const int O_NDELAY = O_NONBLOCK;

const int F_OWNER_TID = 0;
const int F_OWNER_PID = 1;
const int F_OWNER_PGRP = 2;

// AT flags (additional)
const int AT_BENEATH = 0x1000;
const int AT_RESOLVE_BENEATH = 0x2000;
const int AT_EMPTY_PATH = 0x4000;

const int SPACECTL_DEALLOC = 1;

// O_* FreeBSD extensions
const int O_SEARCH = O_EXEC;
const int O_PATH = O_SEARCH;
const int O_EMPTY_PATH = 0x02000000;
const int O_RESOLVE_BENEATH = 0x00800000;

// Cap rights for FreeBSD capability mode
const int CAP_FCNTL_GETFL = (1 << 3);
const int CAP_FCNTL_SETFL = (1 << 4);
const int CAP_FCNTL_GETOWN = (1 << 5);
const int CAP_FCNTL_SETOWN = (1 << 6);

// FreeBSD: F_READAHEAD amount
const int F_READAHEAD_MIN = 0;
const int F_READAHEAD_MAX = 128;




module c::fcntl @if(env::NETBSD);

// ========== Function Declarations ==========

// Main fcntl functions
extern fn int open(char* pathname, int flags, ...);
extern fn int openat(int dirfd, char* pathname, int flags, ...);
extern fn int creat(char* pathname, uint mode);
extern fn int fcntl(int fd, int cmd, ...);

// POSIX advisory locking
extern fn int flock(int fd, int operation);

// Additional utility functions
extern fn int posix_fadvise(int fd, long offset, long len, int advice);
extern fn int posix_fallocate(int fd, long offset, long len);

// Synchronization functions
extern fn int fsync(int fd);
extern fn int fdatasync(int fd);
extern fn void sync();

// Read/Write with offset (pread/pwrite family)
extern fn sz pread(int fd, void* buf, sz count, long offset);
extern fn sz pwrite(int fd, void* buf, sz count, long offset);
extern fn sz preadv(int fd, IovecPtr* iov, int iovcnt, long offset);
extern fn sz pwritev(int fd, IovecPtr* iov, int iovcnt, long offset);

// File descriptor duplication
extern fn int dup(int oldfd);
extern fn int dup2(int oldfd, int newfd);

// ========== Type Definitions ==========

// Helper type for iovec
struct IovecPtr {
    void* iov_base;
    sz iov_len;
}

// File lock structure
struct Flock {
    long l_start;
    long l_len;
    int l_pid;
    short l_type;
    short l_whence;
}

// File owner structure
struct FOwnerEx {
    int type;
    int pid;
}

// ========== Constants ==========

// File control options
const int F_DUPFD = 0;
const int F_GETFD = 1;
const int F_SETFD = 2;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int F_GETOWN = 5;
const int F_SETOWN = 6;
const int F_GETLK = 7;
const int F_SETLK = 8;
const int F_SETLKW = 9;

// File descriptor flags
const int FD_CLOEXEC = 1;

// File status flags
const int O_RDONLY = 0x00000000;
const int O_WRONLY = 0x00000001;
const int O_RDWR = 0x00000002;
const int O_ACCMODE = 0x00000003;

const int O_NONBLOCK = 0x00000004;
const int O_APPEND = 0x00000008;
const int O_SHLOCK = 0x00000010;
const int O_EXLOCK = 0x00000020;
const int O_ASYNC = 0x00000040;
const int O_SYNC = 0x00000080;
const int O_NOFOLLOW = 0x00000100;
const int O_CREAT = 0x00000200;
const int O_TRUNC = 0x00000400;
const int O_EXCL = 0x00000800;
const int O_NOCTTY = 0x00008000;
const int O_DSYNC = 0x00010000;
const int O_RSYNC = 0x00020000;
const int O_ALT_IO = 0x00040000;
const int O_DIRECT = 0x00080000;
const int O_NOSIGPIPE = 0x01000000;
const int O_CLOEXEC = 0x00400000;
const int O_DIRECTORY = 0x00200000;
const int O_SEARCH = 0x00800000;

// Advisory locking
const int LOCK_SH = 0x01;  // Shared lock
const int LOCK_EX = 0x02;  // Exclusive lock
const int LOCK_NB = 0x04;  // Non-blocking
const int LOCK_UN = 0x08;  // Unlock

// Seek constants
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;

// Advice values for posix_fadvise
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// AT_* flags for openat and related functions
const int AT_FDCWD = -100;
const int AT_EACCESS = 0x0100;
const int AT_SYMLINK_NOFOLLOW = 0x0200;
const int AT_SYMLINK_FOLLOW = 0x0400;
const int AT_REMOVEDIR = 0x0800;

// Additional F_* commands
const int F_DUPFD_CLOEXEC = 12;
const int F_CLOSEM = 10;
const int F_MAXFD = 11;
const int F_GETNOSIGPIPE = 13;
const int F_SETNOSIGPIPE = 14;

// Lock types
const int F_RDLCK = 1;
const int F_UNLCK = 2;
const int F_WRLCK = 3;

// More O_* flags
const int O_NDELAY = O_NONBLOCK;
const int O_FSYNC = O_SYNC;

const int F_OWNER_TID = 0;
const int F_OWNER_PID = 1;
const int F_OWNER_PGRP = 2;

// Access mode mask
const int FREAD = 0x00000001;
const int FWRITE = 0x00000002;

// File flags visible to open(2) and fcntl(2)
const int FAPPEND = O_APPEND;
const int FASYNC = O_ASYNC;
const int FFSYNC = O_SYNC;
const int FNONBLOCK = O_NONBLOCK;
const int FNDELAY = O_NONBLOCK;
const int FDSYNC = O_DSYNC;
const int FRSYNC = O_RSYNC;
const int FALTIO = O_ALT_IO;
const int FDIRECT = O_DIRECT;
const int FNOSIGPIPE = O_NOSIGPIPE;

// AT flags (additional)
const int AT_SYMLINK_NOFOLLOW_ANY = 0x1000;




module c::fcntl @if(env::OPENBSD);

// ========== Function Declarations ==========

// Main fcntl functions
extern fn int open(char* pathname, int flags, ...);
extern fn int openat(int dirfd, char* pathname, int flags, ...);
extern fn int creat(char* pathname, uint mode);
extern fn int fcntl(int fd, int cmd, ...);

// POSIX advisory locking
extern fn int flock(int fd, int operation);

// Additional utility functions
extern fn int posix_fadvise(int fd, long offset, long len, int advice);
extern fn int posix_fallocate(int fd, long offset, long len);

// Synchronization functions
extern fn int fsync(int fd);
extern fn int fdatasync(int fd);
extern fn void sync();

// Read/Write with offset (pread/pwrite family)
extern fn sz pread(int fd, void* buf, sz count, long offset);
extern fn sz pwrite(int fd, void* buf, sz count, long offset);
extern fn sz preadv(int fd, IovecPtr* iov, int iovcnt, long offset);
extern fn sz pwritev(int fd, IovecPtr* iov, int iovcnt, long offset);

// File descriptor duplication
extern fn int dup(int oldfd);
extern fn int dup2(int oldfd, int newfd);

// ========== Type Definitions ==========

// Helper type for iovec
struct IovecPtr {
    void* iov_base;
    sz iov_len;
}

// File lock structure
struct Flock {
    long l_start;
    long l_len;
    int l_pid;
    short l_type;
    short l_whence;
}

// File owner structure
struct FOwnerEx {
    int type;
    int pid;
}

// ========== Constants ==========

// File control options
const int F_DUPFD = 0;
const int F_GETFD = 1;
const int F_SETFD = 2;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int F_GETOWN = 5;
const int F_SETOWN = 6;
const int F_GETLK = 7;
const int F_SETLK = 8;
const int F_SETLKW = 9;

// File descriptor flags
const int FD_CLOEXEC = 1;

// File status flags
const int O_RDONLY = 0x0000;
const int O_WRONLY = 0x0001;
const int O_RDWR = 0x0002;
const int O_ACCMODE = 0x0003;

const int O_NONBLOCK = 0x0004;
const int O_APPEND = 0x0008;
const int O_SHLOCK = 0x0010;
const int O_EXLOCK = 0x0020;
const int O_ASYNC = 0x0040;
const int O_SYNC = 0x0080;
const int O_NOFOLLOW = 0x0100;
const int O_CREAT = 0x0200;
const int O_TRUNC = 0x0400;
const int O_EXCL = 0x0800;
const int O_NOCTTY = 0x8000;
const int O_CLOEXEC = 0x10000;
const int O_DIRECTORY = 0x20000;

// Advisory locking
const int LOCK_SH = 0x01;  // Shared lock
const int LOCK_EX = 0x02;  // Exclusive lock
const int LOCK_NB = 0x04;  // Non-blocking
const int LOCK_UN = 0x08;  // Unlock

// Seek constants
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;

// Advice values for posix_fadvise
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// AT_* flags for openat and related functions
const int AT_FDCWD = -100;
const int AT_EACCESS = 0x01;
const int AT_SYMLINK_NOFOLLOW = 0x02;
const int AT_SYMLINK_FOLLOW = 0x04;
const int AT_REMOVEDIR = 0x08;

// Additional F_* commands
const int F_DUPFD_CLOEXEC = 10;
const int F_ISATTY = 11;

// Lock types
const int F_RDLCK = 1;
const int F_UNLCK = 2;
const int F_WRLCK = 3;

// More O_* flags
const int O_DSYNC = O_SYNC;
const int O_RSYNC = O_SYNC;
const int O_NDELAY = O_NONBLOCK;

const int F_OWNER_TID = 0;
const int F_OWNER_PID = 1;
const int F_OWNER_PGRP = 2;

// Access mode mask
const int FREAD = 0x0001;
const int FWRITE = 0x0002;

// File flags visible to open(2) and fcntl(2)
const int FAPPEND = O_APPEND;
const int FASYNC = O_ASYNC;
const int FFSYNC = O_SYNC;
const int FNONBLOCK = O_NONBLOCK;
const int FNDELAY = O_NONBLOCK;
