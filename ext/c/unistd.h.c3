// unistd.h.c3

// unistd.h C3 Extern Mapping

module c::unistd @if(!env::WIN32);

// Function Declarations

// Process Control Functions
extern fn Pid fork() ;
extern fn Pid vfork() ;

extern fn CInt execv(char* path, char** argv) ;
extern fn CInt execve(char* path, char** argv, char** envp) ;
extern fn CInt execvp(char* file, char** argv) ;
extern fn CInt execl(char* path, char* arg, ...) ;
extern fn CInt execle(char* path, char* arg, ...) ;
extern fn CInt execlp(char* file, char* arg, ...) ;
extern fn CInt fexecve(CInt fd, char** argv, char** envp) ;

extern fn Pid getpid() ;
extern fn Pid getppid() ;
extern fn Pid gettid() ;  // Linux specific - thread ID
extern fn Pid getpgrp() ;
extern fn Pid getpgid(Pid pid) ;
extern fn CInt setpgid(Pid pid, Pid pgid) ;
extern fn CInt setpgrp() ;

extern fn Pid getsid(Pid pid) ;
extern fn Pid setsid() ;

extern fn CInt daemon(CInt nochdir, CInt noclose) ;

// File Descriptor Operations
extern fn Ssize read(CInt fd, void* buf, sz count) ;
extern fn Ssize write(CInt fd, void* buf, sz count) ;
extern fn Ssize pread(CInt fd, void* buf, sz count, Off offset) ;
extern fn Ssize pwrite(CInt fd, void* buf, sz count, Off offset) ;
extern fn Ssize pread64(CInt fd, void* buf, sz count, Off64 offset) ;
extern fn Ssize pwrite64(CInt fd, void* buf, sz count, Off64 offset) ;

extern fn Ssize readv(CInt fd, IoVec* iov, CInt iovcnt) ;
extern fn Ssize writev(CInt fd, IoVec* iov, CInt iovcnt) ;
extern fn Ssize preadv(CInt fd, IoVec* iov, CInt iovcnt, Off offset) ;
extern fn Ssize pwritev(CInt fd, IoVec* iov, CInt iovcnt, Off offset) ;
extern fn Ssize preadv2(CInt fd, IoVec* iov, CInt iovcnt, Off offset, CInt flags) ;
extern fn Ssize pwritev2(CInt fd, IoVec* iov, CInt iovcnt, Off offset, CInt flags) ;

extern fn CInt close(CInt fd) ;
extern fn CInt dup(CInt oldfd) ;
extern fn CInt dup2(CInt oldfd, CInt newfd) ;
extern fn CInt dup3(CInt oldfd, CInt newfd, CInt flags) ;

extern fn CInt pipe(CInt[2]* pipefd) ;
extern fn CInt pipe2(CInt[2]* pipefd, CInt flags) ;

extern fn Off lseek(CInt fd, Off offset, CInt whence) ;
extern fn Off64 lseek64(CInt fd, Off64 offset, CInt whence) ;

extern fn CInt fsync(CInt fd) ;
extern fn CInt fdatasync(CInt fd) ;
extern fn void sync() ;
extern fn CInt syncfs(CInt fd) ;

extern fn CInt ftruncate(CInt fd, Off length) ;
extern fn CInt ftruncate64(CInt fd, Off64 length) ;

// Advanced I/O operations (Linux specific)
extern fn Ssize splice(CInt fd_in, Off64* off_in, CInt fd_out, Off64* off_out, sz len, CUInt flags) ;
extern fn Ssize tee(CInt fd_in, CInt fd_out, sz len, CUInt flags) ;
extern fn Ssize vmsplice(CInt fd, IoVec* iov, CULong nr_segs, CUInt flags) ;
extern fn CInt sync_file_range(CInt fd, Off64 offset, Off64 nbytes, CUInt flags) ;
extern fn Ssize readahead(CInt fd, Off64 offset, sz count) ;
extern fn Ssize copy_file_range(CInt fd_in, Off64* off_in, CInt fd_out, Off64* off_out, sz len, CUInt flags) ;

// File allocation
extern fn CInt fallocate(CInt fd, CInt mode, Off offset, Off len) ;
extern fn CInt posix_fallocate(CInt fd, Off offset, Off len) ;
extern fn CInt posix_fallocate64(CInt fd, Off64 offset, Off64 len) ;

// File advice
extern fn CInt posix_fadvise(CInt fd, Off offset, Off len, CInt advice) ;
extern fn CInt posix_fadvise64(CInt fd, Off64 offset, Off64 len, CInt advice) ;

// File System Operations
extern fn CInt access(char* pathname, CInt mode) ;
extern fn CInt faccessat(CInt dirfd, char* pathname, CInt mode, CInt flags) ;

extern fn CInt chdir(char* path) ;
extern fn CInt fchdir(CInt fd) ;
extern fn char* getcwd(char* buf, sz size) ;
extern fn char* get_current_dir_name() ;

extern fn CInt chown(char* pathname, Uid owner, Gid group) ;
extern fn CInt fchown(CInt fd, Uid owner, Gid group) ;
extern fn CInt lchown(char* pathname, Uid owner, Gid group) ;
extern fn CInt fchownat(CInt dirfd, char* pathname, Uid owner, Gid group, CInt flags) ;

extern fn CInt link(char* oldpath, char* newpath) ;
extern fn CInt linkat(CInt olddirfd, char* oldpath, CInt newdirfd, char* newpath, CInt flags) ;
extern fn CInt symlink(char* target, char* linkpath) ;
extern fn CInt symlinkat(char* target, CInt newdirfd, char* linkpath) ;

extern fn CInt unlink(char* pathname) ;
extern fn CInt unlinkat(CInt dirfd, char* pathname, CInt flags) ;
extern fn CInt rmdir(char* pathname) ;

extern fn Ssize readlink(char* pathname, char* buf, sz bufsiz) ;
extern fn Ssize readlinkat(CInt dirfd, char* pathname, char* buf, sz bufsiz) ;

extern fn CInt truncate(char* path, Off length) ;
extern fn CInt truncate64(char* path, Off64 length) ;

extern fn CInt chroot(char* path) ;

// User and Group ID Functions
extern fn Uid getuid() ;
extern fn Uid geteuid() ;
extern fn CInt setuid(Uid uid) ;
extern fn CInt seteuid(Uid uid) ;
extern fn CInt setreuid(Uid ruid, Uid euid) ;

extern fn Gid getgid() ;
extern fn Gid getegid() ;
extern fn CInt setgid(Gid gid) ;
extern fn CInt setegid(Gid gid) ;
extern fn CInt setregid(Gid rgid, Gid egid) ;

extern fn CInt getgroups(CInt size, Gid* list) ;
extern fn CInt setgroups(sz size, Gid* list) ;
extern fn CInt initgroups(char* user, Gid group) ;

extern fn CInt getresuid(Uid* ruid, Uid* euid, Uid* suid) ;
extern fn CInt setresuid(Uid ruid, Uid euid, Uid suid) ;

extern fn CInt getresgid(Gid* rgid, Gid* egid, Gid* sgid) ;
extern fn CInt setresgid(Gid rgid, Gid egid, Gid sgid) ;

// Filesystem UID/GID (Linux specific)
extern fn CInt setfsuid(Uid fsuid) ;
extern fn CInt setfsgid(Gid fsgid) ;

// Login information
extern fn char* getlogin() ;
extern fn CInt getlogin_r(char* name, sz size) ;
extern fn char* cuserid(char* s) ;

// Process Termination and Sleep
extern fn void _exit(CInt status) ;

extern fn CUInt alarm(CUInt seconds) ;
extern fn CUInt sleep(CUInt seconds) ;
extern fn CInt usleep(CUInt usec) ;
extern fn CInt pause() ;

// Terminal Control
extern fn CInt isatty(CInt fd) ;
extern fn char* ttyname(CInt fd) ;
extern fn CInt ttyname_r(CInt fd, char* buf, sz buflen) ;
extern fn char* ctermid(char* s) ;

extern fn Pid tcgetpgrp(CInt fd) ;
extern fn CInt tcsetpgrp(CInt fd, Pid pgrp) ;

// Random/Entropy
extern fn CInt getentropy(void* buffer, sz length) ;
extern fn Ssize getrandom(void* buf, sz buflen, CUInt flags) ;

// Priority Control
extern fn CInt nice(CInt inc) ;
extern fn CInt getpriority(CInt which, CUInt who) ;
extern fn CInt setpriority(CInt which, CUInt who, CInt prio) ;

// I/O Permissions (x86/x86_64 specific)
extern fn CInt ioperm(CULong from, CULong num, CInt turn_on) ;
extern fn CInt iopl(CInt level) ;

// Profiling
extern fn CInt profil(CUShort* buf, sz bufsiz, sz offset, CUInt scale) ;

// Hostname and Domain
extern fn CInt gethostname(char* name, sz len) ;
extern fn CInt sethostname(char* name, sz len) ;

extern fn CInt getdomainname(char* name, sz len) ;
extern fn CInt setdomainname(char* name, sz len) ;

extern fn CLong gethostid() ;
extern fn CInt sethostid(CLong hostid) ;

// System Configuration
extern fn CLong sysconf(CInt name) ;
extern fn CLong pathconf(char* path, CInt name) ;
extern fn CLong fpathconf(CInt fd, CInt name) ;
extern fn sz confstr(CInt name, char* buf, sz len) ;

extern fn CInt getpagesize() ;
extern fn CInt getdtablesize() ;

// System Management (requires privileges)
extern fn CInt reboot(CInt cmd) ;
extern fn CInt acct(char* filename) ;
extern fn CInt vhangup() ;
extern fn CLong syscall(CLong number, ...) ;
extern fn CInt pivot_root(char* new_root, char* put_old) ;

// Swap management
extern fn CInt swapon(char* path, CInt swapflags) ;
extern fn CInt swapoff(char* path) ;

// File Locking
extern fn CInt lockf(CInt fd, CInt cmd, Off len) ;

// Option Parsing (getopt)
extern fn CInt getopt(CInt argc, char** argv, char* optstring) ;


module c::unistd @if (env::LINUX);

// Vectored I/O
struct IoVec 
{
    void* iov_base;
    sz iov_len;
}

// Global Variables

extern sz optind ;
extern CInt optopt ;
extern char* optarg ;
extern CInt opterr ;

// Type Definitions

// Basic POSIX types
alias Pid = CInt;
alias Uid = CUInt;
alias Gid = CUInt;
alias Off = CLong;
alias Off64 = CLongLong;
alias Ssize = CLong;
alias Mode = CUInt;
alias UShort = CUShort;

// Constants

// Flags for various functions
const int F_OK = 0;    // Test for existence
const int R_OK = 4;    // Test for read permission
const int W_OK = 2;    // Test for write permission
const int X_OK = 1;    // Test for execute permission

// Seek whence values
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
const int SEEK_DATA = 3;  // Linux 3.1+
const int SEEK_HOLE = 4;  // Linux 3.1+

// File descriptor values
const int STDIN_FILENO = 0;
const int STDOUT_FILENO = 1;
const int STDERR_FILENO = 2;

// lockf() commands
const int F_ULOCK = 0;  // Unlock
const int F_LOCK = 1;   // Lock
const int F_TLOCK = 2;  // Test and lock
const int F_TEST = 3;   // Test

// sysconf() constants (common ones)
const int _SC_ARG_MAX = 0;
const int _SC_CHILD_MAX = 1;
const int _SC_CLK_TCK = 2;
const int _SC_NGROUPS_MAX = 3;
const int _SC_OPEN_MAX = 4;
const int _SC_PAGESIZE = 30;
const int _SC_PAGE_SIZE = 30;
const int _SC_NPROCESSORS_ONLN = 84;
const int _SC_NPROCESSORS_CONF = 83;
const int _SC_PHYS_PAGES = 85;
const int _SC_AVPHYS_PAGES = 86;

// confstr() constants
const int _CS_PATH = 0;
const int _CS_GNU_LIBC_VERSION = 2;
const int _CS_GNU_LIBPTHREAD_VERSION = 3;

// splice() flags
const int SPLICE_F_MOVE = 1;
const int SPLICE_F_NONBLOCK = 2;
const int SPLICE_F_MORE = 4;
const int SPLICE_F_GIFT = 8;

// sync_file_range() flags
const int SYNC_FILE_RANGE_WAIT_BEFORE = 1;
const int SYNC_FILE_RANGE_WRITE = 2;
const int SYNC_FILE_RANGE_WAIT_AFTER = 4;

// posix_fadvise() advice
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// fallocate() modes
const int FALLOC_FL_KEEP_SIZE = 1;
const int FALLOC_FL_PUNCH_HOLE = 2;
const int FALLOC_FL_COLLAPSE_RANGE = 8;
const int FALLOC_FL_ZERO_RANGE = 16;
const int FALLOC_FL_INSERT_RANGE = 32;

// reboot() commands
const ulong LINUX_REBOOT_CMD_RESTART = 0x01234567;
const ulong LINUX_REBOOT_CMD_HALT = 0xCDEF0123;
const ulong LINUX_REBOOT_CMD_POWER_OFF = 0x4321FEDC;
const ulong LINUX_REBOOT_CMD_RESTART2 = 0xA1B2C3D4;
const ulong LINUX_REBOOT_CMD_SW_SUSPEND = 0xD000FCE2;
const ulong LINUX_REBOOT_CMD_KEXEC = 0x45584543;

// getpriority/setpriority which values
const int PRIO_PROCESS = 0;
const int PRIO_PGRP = 1;
const int PRIO_USER = 2;

// getrandom() flags
const int GRND_NONBLOCK = 0x0001;
const int GRND_RANDOM = 0x0002;

// preadv2/pwritev2 flags
const ulong RWF_HIPRI = 0x00000001;
const ulong RWF_DSYNC = 0x00000002;
const ulong RWF_SYNC = 0x00000004;
const ulong RWF_NOWAIT = 0x00000008;
const ulong RWF_APPEND = 0x00000010;


module c::unistd @if (env::DARWIN);

// Vectored I/O
struct IoVec 
{
    void* iov_base;
    sz iov_len;
}

// Global Variables

extern sz optind ;
extern CInt optopt ;
extern char* optarg ;
extern CInt opterr ;
extern CInt optreset ;  // Darwin specific

// Type Definitions

// Basic POSIX types
alias Pid = CInt;
alias Uid = CUInt;
alias Gid = CUInt;
alias Off = CLongLong;  // macOS uses 64-bit off_t
alias Off64 = CLongLong;
alias Ssize = CLong;
alias Mode = CUShort;  // Different from Linux
alias UShort = CUShort;

// Constants

// Flags for various functions
const int F_OK = 0;    // Test for existence
const int R_OK = 4;    // Test for read permission
const int W_OK = 2;    // Test for write permission
const int X_OK = 1;    // Test for execute permission

// Seek whence values
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
const int SEEK_DATA = 4;   // macOS 10.15+
const int SEEK_HOLE = 3;   // macOS 10.15+

// File descriptor values
const int STDIN_FILENO = 0;
const int STDOUT_FILENO = 1;
const int STDERR_FILENO = 2;

// lockf() commands
const int F_ULOCK = 0;  // Unlock
const int F_LOCK = 1;   // Lock
const int F_TLOCK = 2;  // Test and lock
const int F_TEST = 3;   // Test

// sysconf() constants (Darwin values)
const int _SC_ARG_MAX = 1;
const int _SC_CHILD_MAX = 2;
const int _SC_CLK_TCK = 3;
const int _SC_NGROUPS_MAX = 4;
const int _SC_OPEN_MAX = 5;
const int _SC_PAGESIZE = 29;
const int _SC_PAGE_SIZE = 29;
const int _SC_NPROCESSORS_ONLN = 58;
const int _SC_NPROCESSORS_CONF = 57;
const int _SC_PHYS_PAGES = 200;

// confstr() constants
const int _CS_PATH = 1;
const int _CS_DARWIN_USER_DIR = 65536;
const int _CS_DARWIN_USER_TEMP_DIR = 65537;
const int _CS_DARWIN_USER_CACHE_DIR = 65538;

// posix_fadvise() advice
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// getpriority/setpriority which values
const int PRIO_PROCESS = 0;
const int PRIO_PGRP = 1;
const int PRIO_USER = 2;

// Darwin reboot options (different from Linux)
const int RB_AUTOBOOT = 0;
const int RB_ASKNAME = 1;
const int RB_SINGLE = 2;
const int RB_HALT = 8;


module c::unistd @if (env::FREEBSD);

// Vectored I/O
struct IoVec 
{
    void* iov_base;
    sz iov_len;
}

// Global Variables

extern sz optind ;
extern CInt optopt ;
extern char* optarg ;
extern CInt opterr ;
extern CInt optreset ;  // BSD specific

// Type Definitions

// Basic POSIX types
alias Pid = CInt;
alias Uid = CUInt;
alias Gid = CUInt;
alias Off = CLongLong;  // FreeBSD uses 64-bit off_t
alias Off64 = CLongLong;
alias Ssize = CLong;
alias Mode = CUShort;
alias UShort = CUShort;

// Constants

// Flags for various functions
const int F_OK = 0;    // Test for existence
const int R_OK = 4;    // Test for read permission
const int W_OK = 2;    // Test for write permission
const int X_OK = 1;    // Test for execute permission

// Seek whence values
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
const int SEEK_DATA = 3;  // FreeBSD 8.0+
const int SEEK_HOLE = 4;  // FreeBSD 8.0+

// File descriptor values
const int STDIN_FILENO = 0;
const int STDOUT_FILENO = 1;
const int STDERR_FILENO = 2;

// lockf() commands
const int F_ULOCK = 0;  // Unlock
const int F_LOCK = 1;   // Lock
const int F_TLOCK = 2;  // Test and lock
const int F_TEST = 3;   // Test

// sysconf() constants (FreeBSD values)
const int _SC_ARG_MAX = 1;
const int _SC_CHILD_MAX = 2;
const int _SC_CLK_TCK = 3;
const int _SC_NGROUPS_MAX = 4;
const int _SC_OPEN_MAX = 5;
const int _SC_PAGESIZE = 47;
const int _SC_PAGE_SIZE = 47;
const int _SC_NPROCESSORS_ONLN = 58;
const int _SC_NPROCESSORS_CONF = 57;
const int _SC_PHYS_PAGES = 121;

// confstr() constants
const int _CS_PATH = 1;

// posix_fadvise() advice
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// getpriority/setpriority which values
const int PRIO_PROCESS = 0;
const int PRIO_PGRP = 1;
const int PRIO_USER = 2;

// getrandom() flags (FreeBSD 12.0+)
const int GRND_NONBLOCK = 0x0001;
const int GRND_RANDOM = 0x0002;
const int GRND_INSECURE = 0x0004;  // FreeBSD specific

// FreeBSD reboot options
const int RB_AUTOBOOT = 0;
const int RB_ASKNAME = 0x001;
const int RB_SINGLE = 0x002;
const int RB_NOSYNC = 0x004;
const int RB_HALT = 0x008;
const int RB_INITNAME = 0x010;
const int RB_DFLTROOT = 0x020;
const int RB_KDB = 0x040;
const int RB_RDONLY = 0x080;
const int RB_DUMP = 0x100;
const int RB_MINIROOT = 0x200;
const int RB_VERBOSE = 0x800;
const int RB_SERIAL = 0x1000;
const int RB_CDROM = 0x2000;
const int RB_POWEROFF = 0x4000;
const int RB_GDB = 0x8000;
const int RB_MUTE = 0x10000;
const int RB_SELFTEST = 0x20000;
const int RB_PAUSE = 0x100000;
const int RB_REROOT = 0x200000;
const int RB_POWERCYCLE = 0x400000;
const int RB_PROBE = 0x10000000;


module c::unistd @if (env::OPENBSD);

// Vectored I/O
struct IoVec 
{
    void* iov_base;
    sz iov_len;
}

// Global Variables

extern sz optind ;
extern CInt optopt ;
extern char* optarg ;
extern CInt opterr ;
extern CInt optreset ;  // BSD specific

// Type Definitions

// Basic POSIX types
alias Pid = CInt;
alias Uid = CUInt;
alias Gid = CUInt;
alias Off = CLongLong;  // OpenBSD uses 64-bit off_t
alias Off64 = CLongLong;
alias Ssize = CLong;
alias Mode = CUInt;
alias UShort = CUShort;

// Constants

// Flags for various functions
const int F_OK = 0;    // Test for existence
const int R_OK = 4;    // Test for read permission
const int W_OK = 2;    // Test for write permission
const int X_OK = 1;    // Test for execute permission

// Seek whence values
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
// OpenBSD does not have SEEK_DATA/SEEK_HOLE

// File descriptor values
const int STDIN_FILENO = 0;
const int STDOUT_FILENO = 1;
const int STDERR_FILENO = 2;

// lockf() commands
const int F_ULOCK = 0;  // Unlock
const int F_LOCK = 1;   // Lock
const int F_TLOCK = 2;  // Test and lock
const int F_TEST = 3;   // Test

// sysconf() constants (OpenBSD values)
const int _SC_ARG_MAX = 1;
const int _SC_CHILD_MAX = 2;
const int _SC_CLK_TCK = 3;
const int _SC_NGROUPS_MAX = 4;
const int _SC_OPEN_MAX = 5;
const int _SC_PAGESIZE = 28;
const int _SC_PAGE_SIZE = 28;
const int _SC_NPROCESSORS_ONLN = 503;
const int _SC_NPROCESSORS_CONF = 502;
const int _SC_PHYS_PAGES = 500;

// confstr() constants
const int _CS_PATH = 1;

// posix_fadvise() advice (OpenBSD does not support posix_fadvise)
// But we define constants for compatibility
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// getpriority/setpriority which values
const int PRIO_PROCESS = 0;
const int PRIO_PGRP = 1;
const int PRIO_USER = 2;

// getentropy is native to OpenBSD
// getrandom() was added in OpenBSD 7.5

// OpenBSD reboot options
const int RB_AUTOBOOT = 0;
const int RB_ASKNAME = 0x001;
const int RB_SINGLE = 0x002;
const int RB_NOSYNC = 0x004;
const int RB_HALT = 0x008;
const int RB_INITNAME = 0x010;
const int RB_DFLTROOT = 0x020;
const int RB_KDB = 0x040;
const int RB_RDONLY = 0x080;
const int RB_DUMP = 0x100;
const int RB_MINIROOT = 0x200;
const int RB_CONFIG = 0x400;
const int RB_TIMEBAD = 0x800;
const int RB_POWERDOWN = 0x1000;
const int RB_SERCONS = 0x2000;
const int RB_USERREQ = 0x4000;
const int RB_RESET = 0x8000;
const int RB_GOODRANDOM = 0x10000;


module c::unistd @if (env::NETBSD);

// Vectored I/O
struct IoVec 
{
    void* iov_base;
    sz iov_len;
}

// Global Variables

extern sz optind ;
extern CInt optopt ;
extern char* optarg ;
extern CInt opterr ;
extern CInt optreset ;  // BSD specific

// Type Definitions

// Basic POSIX types
alias Pid = CInt;
alias Uid = CUInt;
alias Gid = CUInt;
alias Off = CLongLong;  // NetBSD uses 64-bit off_t
alias Off64 = CLongLong;
alias Ssize = CLong;
alias Mode = CUInt;
alias UShort = CUShort;

// Constants

// Flags for various functions
const int F_OK = 0;    // Test for existence
const int R_OK = 4;    // Test for read permission
const int W_OK = 2;    // Test for write permission
const int X_OK = 1;    // Test for execute permission

// Seek whence values
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
// NetBSD does not have SEEK_DATA/SEEK_HOLE

// File descriptor values
const int STDIN_FILENO = 0;
const int STDOUT_FILENO = 1;
const int STDERR_FILENO = 2;

// lockf() commands
const int F_ULOCK = 0;  // Unlock
const int F_LOCK = 1;   // Lock
const int F_TLOCK = 2;  // Test and lock
const int F_TEST = 3;   // Test

// sysconf() constants (NetBSD values)
const int _SC_ARG_MAX = 1;
const int _SC_CHILD_MAX = 2;
const int _SC_CLK_TCK = 3;
const int _SC_NGROUPS_MAX = 4;
const int _SC_OPEN_MAX = 5;
const int _SC_PAGESIZE = 28;
const int _SC_PAGE_SIZE = 28;
const int _SC_NPROCESSORS_ONLN = 1002;
const int _SC_NPROCESSORS_CONF = 1001;
const int _SC_PHYS_PAGES = 1000;

// confstr() constants
const int _CS_PATH = 1;

// posix_fadvise() advice
const int POSIX_FADV_NORMAL = 0;
const int POSIX_FADV_RANDOM = 1;
const int POSIX_FADV_SEQUENTIAL = 2;
const int POSIX_FADV_WILLNEED = 3;
const int POSIX_FADV_DONTNEED = 4;
const int POSIX_FADV_NOREUSE = 5;

// getpriority/setpriority which values
const int PRIO_PROCESS = 0;
const int PRIO_PGRP = 1;
const int PRIO_USER = 2;

// getrandom() flags (NetBSD 10.0+)
const int GRND_NONBLOCK = 0x0001;
const int GRND_RANDOM = 0x0002;
const int GRND_INSECURE = 0x0004;  // NetBSD specific

// NetBSD reboot options
const int RB_AUTOBOOT = 0;
const int RB_ASKNAME = 0x001;
const int RB_SINGLE = 0x002;
const int RB_NOSYNC = 0x004;
const int RB_HALT = 0x008;
const int RB_INITNAME = 0x010;
const int RB_KDB = 0x040;
const int RB_RDONLY = 0x080;
const int RB_DUMP = 0x100;
const int RB_MINIROOT = 0x200;
const int RB_STRING = 0x400;
const int RB_POWERDOWN = 0x800;
const int RB_USERCONF = 0x1000;
