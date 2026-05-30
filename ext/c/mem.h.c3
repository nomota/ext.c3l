// mem.h.c3 

// sys/mman.h, string.h (memory ops), stdlib.h (heap allocation)

module c::mem @if(!env::WIN32);

// Protection flags
const int PROT_NONE  = 0x00; // No access
const int PROT_READ  = 0x01; // Read access
const int PROT_WRITE = 0x02; // Write access
const int PROT_EXEC  = 0x04; // Execute access

// Common map flags
const int MAP_SHARED  = 0x0001; // Share changes with other mappings
const int MAP_PRIVATE = 0x0002; // Changes are private (copy-on-write)
const int MAP_FIXED   = 0x0010; // Interpret addr exactly

// MAP_FAILED = (void *)-1
const uptr MAP_FAILED = uptr::max;

// POSIX madvise hints (portable values)
const int POSIX_MADV_NORMAL     = 0; // No special treatment
const int POSIX_MADV_RANDOM     = 1; // Expect random page references
const int POSIX_MADV_SEQUENTIAL = 2; // Expect sequential page references
const int POSIX_MADV_WILLNEED   = 3; // Will need these pages
const int POSIX_MADV_DONTNEED   = 4; // Don't need these pages

alias Off = long; // off_t

// sys/mman.h
extern fn void* mmap(void* addr, sz length, int prot, int flags, int fd, Off offset);
extern fn int munmap(void* addr, sz length);
extern fn int mprotect(void* addr, sz length, int prot);
extern fn int msync(void* addr, sz length, int flags);
extern fn int mlock(void* addr, sz length);
extern fn int munlock(void* addr, sz length);
extern fn int mlockall(int flags);
extern fn int munlockall();
extern fn int madvise(void* addr, sz length, int advice);
extern fn int posix_madvise(void* addr, sz length, int advice);
extern fn int shm_open(ZString name, int oflag, uint mode);
extern fn int shm_unlink(ZString name);
extern fn int posix_memalign(void** memptr, sz alignment, sz size);

// string.h — memory functions
extern fn void* memcpy(void* dest, void* src, sz n);
extern fn void* memmove(void* dest, void* src, sz n);
extern fn void* memset(void* s, int c, sz n);
extern fn int memcmp(void* s1, void* s2, sz n);
extern fn void* memchr(void* s, int c, sz n);
extern fn void* memccpy(void* dest, void* src, int c, sz n);

// stdlib.h — heap allocation
extern fn void* malloc(sz size);
extern fn void* calloc(sz nmemb, sz size);
extern fn void* realloc(void* ptr, sz size);
extern fn void  free(void* ptr);
extern fn void* aligned_alloc(sz alignment, sz size);



module c::mem @if(env::LINUX);

// Linux-specific map flags
const int MAP_ANONYMOUS       = 0x00000020; // Anonymous mapping (no file)
const int MAP_ANON            = MAP_ANONYMOUS;
const int MAP_GROWSDOWN       = 0x00000100; // Stack-like segment, grows downward
const int MAP_DENYWRITE       = 0x00000800; // ETXTBSY if file is written
const int MAP_EXECUTABLE      = 0x00001000; // Mark it as executable
const int MAP_LOCKED          = 0x00002000; // Lock pages in memory
const int MAP_NORESERVE       = 0x00004000; // Don't check for reservations
const int MAP_POPULATE        = 0x00008000; // Populate (prefault) pagetables
const int MAP_NONBLOCK        = 0x00010000; // Do not block on IO
const int MAP_STACK           = 0x00020000; // Allocation suitable for stacks
const int MAP_HUGETLB         = 0x00040000; // Create huge page mapping
const int MAP_SYNC            = 0x00080000; // Perform synchronous page faults
const int MAP_FIXED_NOREPLACE = 0x00100000; // MAP_FIXED, but don't unmap underlying mapping
const int MAP_SHARED_VALIDATE = 0x00000003; // MAP_SHARED + validate flags

// mremap flags
const int MREMAP_MAYMOVE   = 1; // Mapping may be moved
const int MREMAP_FIXED     = 2; // New address is specified
const int MREMAP_DONTUNMAP = 4; // Don't unmap old mapping

// madvise hints
const int MADV_NORMAL      = 0;   // No special treatment
const int MADV_RANDOM      = 1;   // Expect random page references
const int MADV_SEQUENTIAL  = 2;   // Expect sequential page references
const int MADV_WILLNEED    = 3;   // Will need these pages
const int MADV_DONTNEED    = 4;   // Don't need these pages
const int MADV_FREE        = 8;   // Free pages, but don't decommit
const int MADV_REMOVE      = 9;   // Remove these pages and resources
const int MADV_DONTFORK    = 10;  // Don't copy on fork
const int MADV_DOFORK      = 11;  // Undo MADV_DONTFORK
const int MADV_HWPOISON    = 100; // Poison a page for testing
const int MADV_MERGEABLE   = 12;  // KSM may merge identical pages
const int MADV_UNMERGEABLE = 13;  // KSM won't merge identical pages
const int MADV_HUGEPAGE    = 14;  // Encourage transparent huge pages
const int MADV_NOHUGEPAGE  = 15;  // Discourage transparent huge pages
const int MADV_DONTDUMP    = 16;  // Exclude from core dump
const int MADV_DODUMP      = 17;  // Undo MADV_DONTDUMP
const int MADV_WIPEONFORK  = 18;  // Zero memory on fork
const int MADV_KEEPONFORK  = 19;  // Undo MADV_WIPEONFORK
const int MADV_COLD        = 20;  // Deactivate pages
const int MADV_PAGEOUT     = 21;  // Reclaim these pages

// msync flags
const int MS_ASYNC      = 1; // Sync asynchronously
const int MS_INVALIDATE = 2; // Invalidate the caches
const int MS_SYNC       = 4; // Synchronous memory sync

// mlockall flags
const int MCL_CURRENT = 1; // Lock all currently mapped pages
const int MCL_FUTURE  = 2; // Lock all future mapped pages
const int MCL_ONFAULT = 4; // Lock pages when they are faulted in

// memfd_create flags
const int MFD_CLOEXEC       = 0x0001; // Set FD_CLOEXEC on the new fd
const int MFD_ALLOW_SEALING = 0x0002; // Allow file sealing
const int MFD_HUGETLB       = 0x0004; // Use hugetlb pages

// Linux-specific functions
extern fn void* mremap(void* oldAddr, sz oldSize, sz newSize, int flags, ...);
extern fn int memfd_create(ZString name, uint flags);
extern fn int mlock2(void* addr, sz length, uint flags);

// GNU extensions
extern fn void* memrchr(void* s, int c, sz n);
extern fn void* memmem(void* haystack, sz haystackLen, void* needle, sz needleLen);
extern fn void* mempcpy(void* dest, void* src, sz n);

// glibc heap extensions
extern fn void* valloc(sz size);
extern fn void* memalign(sz alignment, sz size);
extern fn sz malloc_usable_size(void* ptr);



module c::mem @if(env::DARWIN);

// Darwin-specific map flags
const int MAP_ANONYMOUS          = 0x1000; // Anonymous mapping (no file)
const int MAP_ANON               = MAP_ANONYMOUS;
const int MAP_NOCACHE            = 0x0400; // Don't cache pages for this mapping
const int MAP_JIT                = 0x0800; // Mapping suitable for JIT
const int MAP_RESILIENT_CODESIGN = 0x2000; // Codesigning resilient mapping
const int MAP_RESILIENT_MEDIA    = 0x4000; // Media resilient mapping

// madvise hints
const int MADV_NORMAL           = 0; // No special treatment
const int MADV_RANDOM           = 1; // Expect random page references
const int MADV_SEQUENTIAL       = 2; // Expect sequential page references
const int MADV_WILLNEED         = 3; // Will need these pages
const int MADV_DONTNEED         = 4; // Don't need these pages
const int MADV_FREE             = 5; // Pages are free to reclaim
const int MADV_ZERO_WIRED_PAGES = 6; // Zero wired pages rather than disconnect
const int MADV_FREE_REUSABLE    = 7; // Pages may be reused (malloc hint)
const int MADV_FREE_REUSE       = 8; // Mark pages as reused (malloc hint)
const int MADV_CAN_REUSE        = 9; // Caller may reuse pages

// msync flags
const int MS_ASYNC      = 0x0001; // Sync asynchronously
const int MS_INVALIDATE = 0x0002; // Invalidate the caches
const int MS_SYNC       = 0x0010; // Synchronous memory sync

// mlockall flags
const int MCL_CURRENT = 0x0001; // Lock all currently mapped pages
const int MCL_FUTURE  = 0x0002; // Lock all future mapped pages

// Darwin heap extensions
extern fn sz malloc_size(void* ptr);
extern fn sz malloc_good_size(sz size);

// BSD extensions
extern fn void* memrchr(void* s, int c, sz n);
extern fn void* memmem(void* haystack, sz haystackLen, void* needle, sz needleLen);



module c::mem @if(env::FREEBSD);

// FreeBSD-specific map flags
const int MAP_ANONYMOUS     = 0x00001000; // Anonymous mapping (no file)
const int MAP_ANON          = MAP_ANONYMOUS;
const int MAP_STACK         = 0x00000400; // Stack-like segment
const int MAP_NOSYNC        = 0x00000800; // Don't include in msync or sync
const int MAP_NOCORE        = 0x00020000; // Don't include in core dump
const int MAP_PREFAULT_READ = 0x00040000; // Prefault mapping for reading
const int MAP_32BIT         = 0x00080000; // Map in low 2GB of address space

// madvise hints
const int MADV_NORMAL     = 0;  // No special treatment
const int MADV_RANDOM     = 1;  // Expect random page references
const int MADV_SEQUENTIAL = 2;  // Expect sequential page references
const int MADV_WILLNEED   = 3;  // Will need these pages
const int MADV_DONTNEED   = 4;  // Don't need these pages
const int MADV_FREE       = 5;  // Pages are free to reclaim
const int MADV_NOSYNC     = 6;  // Don't sync pages to disk
const int MADV_AUTOSYNC   = 7;  // Undo MADV_NOSYNC
const int MADV_NOCORE     = 8;  // Don't include in core dump
const int MADV_CORE       = 9;  // Undo MADV_NOCORE
const int MADV_PROTECT    = 10; // Protect process from swapping

// msync flags
const int MS_ASYNC      = 0x0001; // Sync asynchronously
const int MS_INVALIDATE = 0x0002; // Invalidate the caches
const int MS_SYNC       = 0x0010; // Synchronous memory sync

// mlockall flags
const int MCL_CURRENT = 0x0001; // Lock all currently mapped pages
const int MCL_FUTURE  = 0x0002; // Lock all future mapped pages

// BSD extensions
extern fn void* memrchr(void* s, int c, sz n);
extern fn void* memmem(void* haystack, sz haystackLen, void* needle, sz needleLen);



module c::mem @if(env::NETBSD);

// NetBSD-specific map flags
const int MAP_ANONYMOUS = 0x00001000; // Anonymous mapping (no file)
const int MAP_ANON      = MAP_ANONYMOUS;
const int MAP_WIRED     = 0x00000800; // Lock pages in memory

// madvise hints
const int MADV_NORMAL     = 0; // No special treatment
const int MADV_RANDOM     = 1; // Expect random page references
const int MADV_SEQUENTIAL = 2; // Expect sequential page references
const int MADV_WILLNEED   = 3; // Will need these pages
const int MADV_DONTNEED   = 4; // Don't need these pages
const int MADV_SPACEAVAIL = 5; // Ensure space availability
const int MADV_FREE       = 6; // Pages are free to reclaim

// msync flags
const int MS_ASYNC      = 0x0001; // Sync asynchronously
const int MS_INVALIDATE = 0x0002; // Invalidate the caches
const int MS_SYNC       = 0x0010; // Synchronous memory sync

// mlockall flags
const int MCL_CURRENT = 0x0001; // Lock all currently mapped pages
const int MCL_FUTURE  = 0x0002; // Lock all future mapped pages

// BSD extensions
extern fn void* memrchr(void* s, int c, sz n);
extern fn void* memmem(void* haystack, sz haystackLen, void* needle, sz needleLen);



module c::mem @if(env::OPENBSD);

// OpenBSD-specific map flags
const int MAP_ANONYMOUS = 0x00001000; // Anonymous mapping (no file)
const int MAP_ANON      = MAP_ANONYMOUS;
const int MAP_STACK     = 0x00004000; // Stack-like segment
const int MAP_CONCEAL   = 0x00008000; // Exclude from core dumps and procfs

// madvise hints
const int MADV_NORMAL     = 0; // No special treatment
const int MADV_RANDOM     = 1; // Expect random page references
const int MADV_SEQUENTIAL = 2; // Expect sequential page references
const int MADV_WILLNEED   = 3; // Will need these pages
const int MADV_DONTNEED   = 4; // Don't need these pages
const int MADV_SPACEAVAIL = 5; // Ensure space availability
const int MADV_FREE       = 6; // Pages are free to reclaim

// msync flags
const int MS_ASYNC      = 0x0001; // Sync asynchronously
const int MS_INVALIDATE = 0x0002; // Invalidate the caches
const int MS_SYNC       = 0x0010; // Synchronous memory sync

// mlockall flags
const int MCL_CURRENT = 0x0001; // Lock all currently mapped pages
const int MCL_FUTURE  = 0x0002; // Lock all future mapped pages

// BSD extensions
extern fn void* memrchr(void* s, int c, sz n);
extern fn void* memmem(void* haystack, sz haystackLen, void* needle, sz needleLen);
