// sys.mman.h.c3

// ========== Linux ==========

module c::sys::mman @if(env::LINUX);

// Function Declarations
extern fn void* mmap(void* addr, sz length, int prot, int flags, int fd, long offset);
extern fn int munmap(void* addr, sz length);
extern fn int mprotect(void* addr, sz len, int prot);
extern fn int msync(void* addr, sz length, int flags);
extern fn int mlock(void* addr, sz len);
extern fn int munlock(void* addr, sz len);
extern fn int mlockall(int flags);
extern fn int munlockall();
extern fn int madvise(void* addr, sz length, int advice);
extern fn int mincore(void* addr, sz length, char* vec);
extern fn int shm_open(char* name, int oflag, uint mode);
extern fn int shm_unlink(char* name);
extern fn void* mremap(void* old_address, sz old_size, sz new_size, int flags, ...);
extern fn int mlock2(void* addr, sz len, int flags);
extern fn int pkey_alloc(uint flags, uint access_rights);
extern fn int pkey_free(int pkey);
extern fn int pkey_mprotect(void* addr, sz len, int prot, int pkey);
extern fn int pkey_get(int pkey);
extern fn int pkey_set(int pkey, uint access_rights);
extern fn int memfd_create(char* name, uint flags);

// Constants
const int PROT_NONE = 0x0;
const int PROT_READ = 0x1;
const int PROT_WRITE = 0x2;
const int PROT_EXEC = 0x4;
const int PROT_GROWSDOWN = 0x01000000;
const int PROT_GROWSUP = 0x02000000;

const int MAP_SHARED = 0x01;
const int MAP_PRIVATE = 0x02;
const int MAP_SHARED_VALIDATE = 0x03;
const int MAP_TYPE = 0x0f;
const int MAP_FIXED = 0x10;
const int MAP_ANONYMOUS = 0x20;
const int MAP_ANON = MAP_ANONYMOUS;
const int MAP_GROWSDOWN = 0x00100;
const int MAP_DENYWRITE = 0x00800;
const int MAP_EXECUTABLE = 0x01000;
const int MAP_LOCKED = 0x02000;
const int MAP_NORESERVE = 0x04000;
const int MAP_POPULATE = 0x08000;
const int MAP_NONBLOCK = 0x10000;
const int MAP_STACK = 0x20000;
const int MAP_HUGETLB = 0x40000;
const int MAP_SYNC = 0x80000;
const int MAP_FIXED_NOREPLACE = 0x100000;

const int MAP_HUGE_SHIFT = 26;
const int MAP_HUGE_MASK = 0x3f;
const int MAP_HUGE_2MB = (21 << MAP_HUGE_SHIFT);
const int MAP_HUGE_1GB = (30 << MAP_HUGE_SHIFT);

const iptr MAP_FAILED = -1;

const int MS_ASYNC = 1;
const int MS_INVALIDATE = 2;
const int MS_SYNC = 4;

const int MADV_NORMAL = 0;
const int MADV_RANDOM = 1;
const int MADV_SEQUENTIAL = 2;
const int MADV_WILLNEED = 3;
const int MADV_DONTNEED = 4;
const int MADV_FREE = 8;
const int MADV_REMOVE = 9;
const int MADV_DONTFORK = 10;
const int MADV_DOFORK = 11;
const int MADV_HWPOISON = 100;
const int MADV_SOFT_OFFLINE = 101;
const int MADV_MERGEABLE = 12;
const int MADV_UNMERGEABLE = 13;
const int MADV_HUGEPAGE = 14;
const int MADV_NOHUGEPAGE = 15;
const int MADV_DONTDUMP = 16;
const int MADV_DODUMP = 17;
const int MADV_WIPEONFORK = 18;
const int MADV_KEEPONFORK = 19;
const int MADV_COLD = 20;
const int MADV_PAGEOUT = 21;

const int MCL_CURRENT = 1;
const int MCL_FUTURE = 2;
const int MCL_ONFAULT = 4;

const int MREMAP_MAYMOVE = 1;
const int MREMAP_FIXED = 2;
const int MREMAP_DONTUNMAP = 4;

const int MLOCK_ONFAULT = 0x01;

const uint MFD_CLOEXEC = 0x0001;
const uint MFD_ALLOW_SEALING = 0x0002;
const uint MFD_HUGETLB = 0x0004;

// ========== Darwin ==========

module c::sys::mman @if(env::DARWIN);

// Function Declarations
extern fn void* mmap(void* addr, sz length, int prot, int flags, int fd, long offset);
extern fn int munmap(void* addr, sz length);
extern fn int mprotect(void* addr, sz len, int prot);
extern fn int msync(void* addr, sz length, int flags);
extern fn int mlock(void* addr, sz len);
extern fn int munlock(void* addr, sz len);
extern fn int mlockall(int flags);
extern fn int munlockall();
extern fn int madvise(void* addr, sz length, int advice);
extern fn int mincore(void* addr, sz length, char* vec);
extern fn int shm_open(char* name, int oflag, uint mode);
extern fn int shm_unlink(char* name);
extern fn int minherit(void* addr, sz len, int inherit);

// Constants
const int PROT_NONE = 0x00;
const int PROT_READ = 0x01;
const int PROT_WRITE = 0x02;
const int PROT_EXEC = 0x04;

const int MAP_SHARED = 0x0001;
const int MAP_PRIVATE = 0x0002;
const int MAP_FIXED = 0x0010;
const int MAP_RENAME = 0x0020;
const int MAP_NORESERVE = 0x0040;
const int MAP_RESERVED0080 = 0x0080;
const int MAP_NOEXTEND = 0x0100;
const int MAP_HASSEMAPHORE = 0x0200;
const int MAP_NOCACHE = 0x0400;
const int MAP_JIT = 0x0800;
const int MAP_FILE = 0x0000;
const int MAP_ANON = 0x1000;
const int MAP_ANONYMOUS = MAP_ANON;
const int MAP_RESILIENT_CODESIGN = 0x2000;
const int MAP_RESILIENT_MEDIA = 0x4000;
const int MAP_32BIT = 0x8000;

const iptr MAP_FAILED = -1;

const int MS_ASYNC = 0x0001;
const int MS_INVALIDATE = 0x0002;
const int MS_SYNC = 0x0010;
const int MS_KILLPAGES = 0x0004;
const int MS_DEACTIVATE = 0x0008;

const int MADV_NORMAL = 0;
const int MADV_RANDOM = 1;
const int MADV_SEQUENTIAL = 2;
const int MADV_WILLNEED = 3;
const int MADV_DONTNEED = 4;
const int MADV_FREE = 5;
const int MADV_ZERO_WIRED_PAGES = 6;
const int MADV_FREE_REUSABLE = 7;
const int MADV_FREE_REUSE = 8;
const int MADV_CAN_REUSE = 9;

const int MCL_CURRENT = 0x0001;
const int MCL_FUTURE = 0x0002;

const int MAP_INHERIT_SHARE = 0;
const int MAP_INHERIT_COPY = 1;
const int MAP_INHERIT_NONE = 2;
const int MAP_INHERIT_DONATE_COPY = 3;

const int INHERIT_SHARE = 0;
const int INHERIT_COPY = 1;
const int INHERIT_NONE = 2;
const int INHERIT_DONATE_COPY = 3;

const int PSHMNAMLEN = 31;

// ========== FreeBSD ==========

module c::sys::mman @if(env::FREEBSD);

// Function Declarations
extern fn void* mmap(void* addr, sz length, int prot, int flags, int fd, long offset);
extern fn int munmap(void* addr, sz length);
extern fn int mprotect(void* addr, sz len, int prot);
extern fn int msync(void* addr, sz length, int flags);
extern fn int mlock(void* addr, sz len);
extern fn int munlock(void* addr, sz len);
extern fn int mlockall(int flags);
extern fn int munlockall();
extern fn int madvise(void* addr, sz length, int advice);
extern fn int mincore(void* addr, sz length, char* vec);
extern fn int shm_open(char* name, int oflag, uint mode);
extern fn int shm_unlink(char* name);
extern fn int minherit(void* addr, sz len, int inherit);

// Constants
const int PROT_NONE = 0x00;
const int PROT_READ = 0x01;
const int PROT_WRITE = 0x02;
const int PROT_EXEC = 0x04;

const int MAP_SHARED = 0x0001;
const int MAP_PRIVATE = 0x0002;
const int MAP_FIXED = 0x0010;
const int MAP_RENAME = 0x0020;
const int MAP_NORESERVE = 0x0040;
const int MAP_NOEXTEND = 0x0100;
const int MAP_HASSEMAPHORE = 0x0200;
const int MAP_STACK = 0x0400;
const int MAP_NOSYNC = 0x0800;
const int MAP_FILE = 0x0000;
const int MAP_ANON = 0x1000;
const int MAP_ANONYMOUS = MAP_ANON;
const int MAP_GUARD = 0x00002000;
const int MAP_EXCL = 0x00004000;
const int MAP_NOCORE = 0x00020000;
const int MAP_PREFAULT_READ = 0x00040000;
const int MAP_32BIT = 0x00080000;

const iptr MAP_FAILED = -1;

const int MS_ASYNC = 0x0001;
const int MS_INVALIDATE = 0x0002;
const int MS_SYNC = 0x0000;

const int MADV_NORMAL = 0;
const int MADV_RANDOM = 1;
const int MADV_SEQUENTIAL = 2;
const int MADV_WILLNEED = 3;
const int MADV_DONTNEED = 4;
const int MADV_FREE = 5;
const int MADV_NOSYNC = 6;
const int MADV_AUTOSYNC = 7;
const int MADV_NOCORE = 8;
const int MADV_CORE = 9;
const int MADV_PROTECT = 10;

const int MCL_CURRENT = 0x0001;
const int MCL_FUTURE = 0x0002;

const int INHERIT_SHARE = 0;
const int INHERIT_COPY = 1;
const int INHERIT_NONE = 2;
const int INHERIT_ZERO = 3;

const int PSHMNAMLEN = 31;

// ========== NetBSD ==========

module c::sys::mman @if(env::NETBSD);

// Function Declarations
extern fn void* mmap(void* addr, sz length, int prot, int flags, int fd, long offset);
extern fn int munmap(void* addr, sz length);
extern fn int mprotect(void* addr, sz len, int prot);
extern fn int msync(void* addr, sz length, int flags);
extern fn int mlock(void* addr, sz len);
extern fn int munlock(void* addr, sz len);
extern fn int mlockall(int flags);
extern fn int munlockall();
extern fn int madvise(void* addr, sz length, int advice);
extern fn int mincore(void* addr, sz length, char* vec);
extern fn int shm_open(char* name, int oflag, uint mode);
extern fn int shm_unlink(char* name);
extern fn int minherit(void* addr, sz len, int inherit);

// Constants
const int PROT_NONE = 0x00;
const int PROT_READ = 0x01;
const int PROT_WRITE = 0x02;
const int PROT_EXEC = 0x04;

const int MAP_SHARED = 0x0001;
const int MAP_PRIVATE = 0x0002;
const int MAP_FIXED = 0x0010;
const int MAP_RENAME = 0x0020;
const int MAP_NORESERVE = 0x0040;
const int MAP_INHERIT = 0x0080;
const int MAP_HASSEMAPHORE = 0x0200;
const int MAP_TRYFIXED = 0x0400;
const int MAP_WIRED = 0x0800;
const int MAP_FILE = 0x0000;
const int MAP_ANON = 0x1000;
const int MAP_ANONYMOUS = MAP_ANON;
const int MAP_STACK = 0x2000;

const iptr MAP_FAILED = -1;

const int MS_ASYNC = 0x0001;
const int MS_INVALIDATE = 0x0002;
const int MS_SYNC = 0x0004;

const int MADV_NORMAL = 0;
const int MADV_RANDOM = 1;
const int MADV_SEQUENTIAL = 2;
const int MADV_WILLNEED = 3;
const int MADV_DONTNEED = 4;
const int MADV_FREE = 6;

const int MCL_CURRENT = 0x0001;
const int MCL_FUTURE = 0x0002;

const int MAP_INHERIT_SHARE = 0;
const int MAP_INHERIT_COPY = 1;
const int MAP_INHERIT_NONE = 2;
const int MAP_INHERIT_DONATE_COPY = 3;
const int MAP_INHERIT_ZERO = 4;

const int PSHMNAMLEN = 31;

// ========== OpenBSD ==========

module c::sys::mman @if(env::OPENBSD);

// Function Declarations
extern fn void* mmap(void* addr, sz length, int prot, int flags, int fd, long offset);
extern fn int munmap(void* addr, sz length);
extern fn int mprotect(void* addr, sz len, int prot);
extern fn int msync(void* addr, sz length, int flags);
extern fn int mlock(void* addr, sz len);
extern fn int munlock(void* addr, sz len);
extern fn int mlockall(int flags);
extern fn int munlockall();
extern fn int madvise(void* addr, sz length, int advice);
extern fn int mincore(void* addr, sz length, char* vec);
extern fn int shm_open(char* name, int oflag, uint mode);
extern fn int shm_unlink(char* name);
extern fn int minherit(void* addr, sz len, int inherit);
extern fn int mimmutable(void* addr, sz len);
extern fn void* mquery(void* addr, sz len, int prot, int flags, int fd, long offset);

// Constants
const int PROT_NONE = 0x00;
const int PROT_READ = 0x01;
const int PROT_WRITE = 0x02;
const int PROT_EXEC = 0x04;

const int MAP_SHARED = 0x0001;
const int MAP_PRIVATE = 0x0002;
const int MAP_FIXED = 0x0010;
const int MAP_RENAME = 0x0020;
const int MAP_NORESERVE = 0x0040;
const int MAP_INHERIT = 0x0080;
const int MAP_NOEXTEND = 0x0100;
const int MAP_HASSEMAPHORE = 0x0200;
const int MAP_TRYFIXED = 0x0400;
const int MAP_FILE = 0x0000;
const int MAP_ANON = 0x1000;
const int MAP_ANONYMOUS = MAP_ANON;
const int MAP_STACK = 0x4000;
const int MAP_CONCEAL = 0x8000;

const iptr MAP_FAILED = -1;

const int MS_ASYNC = 0x0001;
const int MS_SYNC = 0x0002;
const int MS_INVALIDATE = 0x0004;

const int MADV_NORMAL = 0;
const int MADV_RANDOM = 1;
const int MADV_SEQUENTIAL = 2;
const int MADV_WILLNEED = 3;
const int MADV_DONTNEED = 4;
const int MADV_SPACEAVAIL = 5;
const int MADV_FREE = 6;

const int MCL_CURRENT = 0x0001;
const int MCL_FUTURE = 0x0002;

const int MAP_INHERIT_SHARE = 0;
const int MAP_INHERIT_COPY = 1;
const int MAP_INHERIT_NONE = 2;
const int MAP_INHERIT_ZERO = 3;

const int PSHMNAMLEN = 31;

// eof