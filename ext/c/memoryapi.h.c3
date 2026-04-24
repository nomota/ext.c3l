// memoryapi.h.c3

// Windows Memory API
// C3 mapping for memoryapi.h

// Nomota <hiongun@gmail.com>; MIT License

module c::memoryapi @if(env::WIN32);

// Common Windows types
alias Handle = void*;
alias DWord = uint;
alias Bool = int;
alias PVoid = void*;
alias Size = ulong;
alias ULongPtr = uptr;
alias LongPtr = iptr;
alias ULong = ulong;

// Memory allocation types
const uint MEM_COMMIT = 0x00001000;
const uint MEM_RESERVE = 0x00002000;
const uint MEM_RESET = 0x00080000;
const uint MEM_RESET_UNDO = 0x01000000;
const uint MEM_LARGE_PAGES = 0x20000000;
const uint MEM_PHYSICAL = 0x00400000;
const uint MEM_TOP_DOWN = 0x00100000;
const uint MEM_WRITE_WATCH = 0x00200000;

// Memory deallocation types
const uint MEM_DECOMMIT = 0x00004000;
const uint MEM_RELEASE = 0x00008000;
const uint MEM_COALESCE_PLACEHOLDERS = 0x00000001;
const uint MEM_PRESERVE_PLACEHOLDER = 0x00000002;

// Memory protection constants
const uint PAGE_NOACCESS = 0x01;
const uint PAGE_READONLY = 0x02;
const uint PAGE_READWRITE = 0x04;
const uint PAGE_WRITECOPY = 0x08;
const uint PAGE_EXECUTE = 0x10;
const uint PAGE_EXECUTE_READ = 0x20;
const uint PAGE_EXECUTE_READWRITE = 0x40;
const uint PAGE_EXECUTE_WRITECOPY = 0x80;
const uint PAGE_GUARD = 0x100;
const uint PAGE_NOCACHE = 0x200;
const uint PAGE_WRITECOMBINE = 0x400;
const uint PAGE_GRAPHICS_NOACCESS = 0x0800;
const uint PAGE_GRAPHICS_READONLY = 0x1000;
const uint PAGE_GRAPHICS_READWRITE = 0x2000;
const uint PAGE_GRAPHICS_EXECUTE = 0x4000;
const uint PAGE_GRAPHICS_EXECUTE_READ = 0x8000;
const uint PAGE_GRAPHICS_EXECUTE_READWRITE = 0x10000;
const uint PAGE_GRAPHICS_COHERENT = 0x20000;
const uint PAGE_ENCLAVE_THREAD_CONTROL = 0x80000000;
const uint PAGE_REVERT_TO_FILE_MAP = 0x80000000;
const uint PAGE_TARGETS_NO_UPDATE = 0x40000000;
const uint PAGE_TARGETS_INVALID = 0x40000000;
const uint PAGE_ENCLAVE_UNVALIDATED = 0x20000000;
const uint PAGE_ENCLAVE_DECOMMIT = 0x10000000;

// Section access flags
const uint SECTION_QUERY = 0x0001;
const uint SECTION_MAP_WRITE = 0x0002;
const uint SECTION_MAP_READ = 0x0004;
const uint SECTION_MAP_EXECUTE = 0x0008;
const uint SECTION_EXTEND_SIZE = 0x0010;
const uint SECTION_MAP_EXECUTE_EXPLICIT = 0x0020;
const uint SECTION_ALL_ACCESS = 0x000F001F;

// File mapping flags
const uint FILE_MAP_WRITE = SECTION_MAP_WRITE;
const uint FILE_MAP_READ = SECTION_MAP_READ;
const uint FILE_MAP_ALL_ACCESS = SECTION_ALL_ACCESS;
const uint FILE_MAP_EXECUTE = SECTION_MAP_EXECUTE_EXPLICIT;
const uint FILE_MAP_COPY = 0x00000001;
const uint FILE_MAP_RESERVE = 0x80000000;
const uint FILE_MAP_TARGETS_INVALID = 0x40000000;
const uint FILE_MAP_LARGE_PAGES = 0x20000000;

// Memory state flags
const uint MEM_FREE = 0x00010000;
const uint MEM_PRIVATE = 0x00020000;
const uint MEM_MAPPED = 0x00040000;
const uint MEM_IMAGE = 0x01000000;

// Heap flags
const uint HEAP_NO_SERIALIZE = 0x00000001;
const uint HEAP_GROWABLE = 0x00000002;
const uint HEAP_GENERATE_EXCEPTIONS = 0x00000004;
const uint HEAP_ZERO_MEMORY = 0x00000008;
const uint HEAP_REALLOC_IN_PLACE_ONLY = 0x00000010;
const uint HEAP_TAIL_CHECKING_ENABLED = 0x00000020;
const uint HEAP_FREE_CHECKING_ENABLED = 0x00000040;
const uint HEAP_DISABLE_COALESCE_ON_FREE = 0x00000080;
const uint HEAP_CREATE_ALIGN_16 = 0x00010000;
const uint HEAP_CREATE_ENABLE_TRACING = 0x00020000;
const uint HEAP_CREATE_ENABLE_EXECUTE = 0x00040000;
const uint HEAP_MAXIMUM_TAG = 0x0FFF;
const uint HEAP_PSEUDO_TAG_FLAG = 0x8000;
const uint HEAP_TAG_SHIFT = 18;

// Structures
struct MemoryBasicInformation {
    PVoid baseAddress;
    PVoid allocationBase;
    DWord allocationProtect;
    ushort partitionId;
    Size regionSize;
    DWord state;
    DWord protect;
    DWord type;
}

struct Win32MemoryRangeEntry {
    PVoid virtualAddress;
    Size numberOfBytes;
}

struct Win32MemoryRegionInformation {
    PVoid allocationBase;
    DWord allocationProtect;
    DWord regionType;
    Size regionSize;
}

// Memory management functions
extern fn PVoid virtualAlloc(
    PVoid address,
    Size size,
    DWord allocationType,
    DWord protect
) @cname("VirtualAlloc");

extern fn PVoid virtualAllocEx(
    Handle process,
    PVoid address,
    Size size,
    DWord allocationType,
    DWord protect
) @cname("VirtualAllocEx");

extern fn Bool virtualFree(
    PVoid address,
    Size size,
    DWord freeType
) @cname("VirtualFree");

extern fn Bool virtualFreeEx(
    Handle process,
    PVoid address,
    Size size,
    DWord freeType
) @cname("VirtualFreeEx");

extern fn Bool virtualProtect(
    PVoid address,
    Size size,
    DWord newProtect,
    DWord* oldProtect
) @cname("VirtualProtect");

extern fn Bool virtualProtectEx(
    Handle process,
    PVoid address,
    Size size,
    DWord newProtect,
    DWord* oldProtect
) @cname("VirtualProtectEx");

extern fn Size virtualQuery(
    PVoid address,
    MemoryBasicInformation* buffer,
    Size length
) @cname("VirtualQuery");

extern fn Size virtualQueryEx(
    Handle process,
    PVoid address,
    MemoryBasicInformation* buffer,
    Size length
) @cname("VirtualQueryEx");

extern fn Bool virtualLock(
    PVoid address,
    Size size
) @cname("VirtualLock");

extern fn Bool virtualUnlock(
    PVoid address,
    Size size
) @cname("VirtualUnlock");

extern fn PVoid virtualAlloc2(
    Handle process,
    PVoid baseAddress,
    Size size,
    DWord allocationType,
    DWord pageProtection,
    void* extendedParameters,
    ULong parameterCount
) @cname("VirtualAlloc2");

extern fn PVoid mapViewOfFile3(
    Handle fileMappingObject,
    Handle process,
    PVoid baseAddress,
    ulong offset,
    Size viewSize,
    DWord allocationType,
    DWord pageProtection,
    void* extendedParameters,
    ULong parameterCount
) @cname("MapViewOfFile3");

extern fn Bool virtualUnlockEx(
    Handle process,
    PVoid address,
    Size size
) @cname("VirtualUnlockEx");

extern fn ULong getWriteWatch(
    DWord flags,
    PVoid baseAddress,
    Size regionSize,
    PVoid* addresses,
    ULongPtr* count,
    DWord* granularity
) @cname("GetWriteWatch");

extern fn ULong resetWriteWatch(
    PVoid baseAddress,
    Size regionSize
) @cname("ResetWriteWatch");

extern fn Bool readProcessMemory(
    Handle process,
    PVoid baseAddress,
    PVoid buffer,
    Size size,
    Size* numberOfBytesRead
) @cname("ReadProcessMemory");

extern fn Bool writeProcessMemory(
    Handle process,
    PVoid baseAddress,
    PVoid buffer,
    Size size,
    Size* numberOfBytesWritten
) @cname("WriteProcessMemory");

// File mapping functions
extern fn Handle createFileMappingA(
    Handle file,
    void* fileMappingAttributes,
    DWord protect,
    DWord maximumSizeHigh,
    DWord maximumSizeLow,
    char* name
) @cname("CreateFileMappingA");

extern fn Handle createFileMappingW(
    Handle file,
    void* fileMappingAttributes,
    DWord protect,
    DWord maximumSizeHigh,
    DWord maximumSizeLow,
    short* name
) @cname("CreateFileMappingW");

extern fn Handle openFileMappingA(
    DWord desiredAccess,
    Bool inheritHandle,
    char* name
) @cname("OpenFileMappingA");

extern fn Handle openFileMappingW(
    DWord desiredAccess,
    Bool inheritHandle,
    short* name
) @cname("OpenFileMappingW");

extern fn PVoid mapViewOfFile(
    Handle fileMappingObject,
    DWord desiredAccess,
    DWord fileOffsetHigh,
    DWord fileOffsetLow,
    Size numberOfBytesToMap
) @cname("MapViewOfFile");

extern fn PVoid mapViewOfFileEx(
    Handle fileMappingObject,
    DWord desiredAccess,
    DWord fileOffsetHigh,
    DWord fileOffsetLow,
    Size numberOfBytesToMap,
    PVoid baseAddress
) @cname("MapViewOfFileEx");

extern fn Bool unmapViewOfFile(PVoid baseAddress) @cname("UnmapViewOfFile");

extern fn Bool unmapViewOfFileEx(PVoid baseAddress, DWord unmapFlags) @cname("UnmapViewOfFileEx");

extern fn Bool flushViewOfFile(
    PVoid baseAddress,
    Size numberOfBytesToFlush
) @cname("FlushViewOfFile");

// Heap functions
extern fn Handle getProcessHeap() @cname("GetProcessHeap");

extern fn DWord getProcessHeaps(DWord numberOfHeaps, Handle* processHeaps) @cname("GetProcessHeaps");

extern fn Handle heapCreate(
    DWord options,
    Size initialSize,
    Size maximumSize
) @cname("HeapCreate");

extern fn Bool heapDestroy(Handle heap) @cname("HeapDestroy");

extern fn PVoid heapAlloc(
    Handle heap,
    DWord flags,
    Size bytes
) @cname("HeapAlloc");

extern fn PVoid heapRealloc(
    Handle heap,
    DWord flags,
    PVoid mem,
    Size bytes
) @cname("HeapReAlloc");

extern fn Bool heapFree(
    Handle heap,
    DWord flags,
    PVoid mem
) @cname("HeapFree");

extern fn Size heapSize(
    Handle heap,
    DWord flags,
    PVoid mem
) @cname("HeapSize");

extern fn Bool heapValidate(
    Handle heap,
    DWord flags,
    PVoid mem
) @cname("HeapValidate");

extern fn Size heapCompact(
    Handle heap,
    DWord flags
) @cname("HeapCompact");

extern fn Bool heapLock(Handle heap) @cname("HeapLock");

extern fn Bool heapUnlock(Handle heap) @cname("HeapUnlock");

extern fn Bool heapWalk(
    Handle heap,
    void* entry
) @cname("HeapWalk");

extern fn Bool heapSetInformation(
    Handle heap,
    int heapInformationClass,
    PVoid heapInformation,
    Size heapInformationLength
) @cname("HeapSetInformation");

extern fn Bool heapQueryInformation(
    Handle heap,
    int heapInformationClass,
    PVoid heapInformation,
    Size heapInformationLength,
    Size* returnLength
) @cname("HeapQueryInformation");

// Global and Local memory functions (legacy, but still available)
extern fn Handle globalAlloc(DWord flags, Size bytes) @cname("GlobalAlloc");

extern fn Handle globalRealloc(Handle mem, Size bytes, DWord flags) @cname("GlobalReAlloc");

extern fn Size globalSize(Handle mem) @cname("GlobalSize");

extern fn PVoid globalLock(Handle mem) @cname("GlobalLock");

extern fn Bool globalUnlock(Handle mem) @cname("GlobalUnlock");

extern fn Handle globalFree(Handle mem) @cname("GlobalFree");

extern fn Handle localAlloc(DWord flags, Size bytes) @cname("LocalAlloc");

extern fn Handle localRealloc(Handle mem, Size bytes, DWord flags) @cname("LocalReAlloc");

extern fn Size localSize(Handle mem) @cname("LocalSize");

extern fn PVoid localLock(Handle mem) @cname("LocalLock");

extern fn Bool localUnlock(Handle mem) @cname("LocalUnlock");

extern fn Handle localFree(Handle mem) @cname("LocalFree");

// Memory mapped file information
extern fn Bool getMappedFileNameA(
    Handle process,
    PVoid address,
    char* filename,
    DWord size
) @cname("GetMappedFileNameA");

extern fn Bool getMappedFileNameW(
    Handle process,
    PVoid address,
    short* filename,
    DWord size
) @cname("GetMappedFileNameW");

// Additional memory management
extern fn Bool allocateUserPhysicalPages(
    Handle process,
    ULongPtr* numberOfPages,
    ULongPtr* pageArray
) @cname("AllocateUserPhysicalPages");

extern fn Bool freeUserPhysicalPages(
    Handle process,
    ULongPtr* numberOfPages,
    ULongPtr* pageArray
) @cname("FreeUserPhysicalPages");

extern fn Bool mapUserPhysicalPages(
    PVoid virtualAddress,
    ULongPtr numberOfPages,
    ULongPtr* pageArray
) @cname("MapUserPhysicalPages");

extern fn Bool mapUserPhysicalPagesScatter(
    PVoid* virtualAddresses,
    ULongPtr numberOfPages,
    ULongPtr* pageArray
) @cname("MapUserPhysicalPagesScatter");

extern fn Bool prefetchVirtualMemory(
    Handle process,
    ULongPtr numberOfEntries,
    Win32MemoryRangeEntry* virtualAddresses,
    DWord flags
) @cname("PrefetchVirtualMemory");

extern fn Bool offerVirtualMemory(
    PVoid virtualAddress,
    Size size,
    int priority
) @cname("OfferVirtualMemory");

extern fn Bool reclaimVirtualMemory(
    PVoid virtualAddress,
    Size size
) @cname("ReclaimVirtualMemory");

extern fn Bool discardVirtualMemory(
    PVoid virtualAddress,
    Size size
) @cname("DiscardVirtualMemory");

extern fn Bool setProcessValidCallTargets(
    Handle process,
    PVoid virtualAddress,
    Size regionSize,
    DWord numberOfOffsets,
    void* offsetInformation
) @cname("SetProcessValidCallTargets");

// Memory notification
extern fn Handle createMemoryResourceNotification(int notificationType) @cname("CreateMemoryResourceNotification");

extern fn Bool queryMemoryResourceNotification(
    Handle resourceNotificationHandle,
    Bool* resourceState
) @cname("QueryMemoryResourceNotification");

// Constants for memory notifications
const int LOW_MEMORY_RESOURCE_NOTIFICATION = 0;
const int HIGH_MEMORY_RESOURCE_NOTIFICATION = 1;

// Invalid handle value
const ulong INVALID_HANDLE_VALUE = 0xFFFFFFFFFFFFFFFF;

// Global/Local memory flags
const uint GMEM_FIXED = 0x0000;
const uint GMEM_MOVEABLE = 0x0002;
const uint GMEM_ZEROINIT = 0x0040;
const uint GPTR = 0x0040;
const uint GHND = 0x0042;

const uint LMEM_FIXED = 0x0000;
const uint LMEM_MOVEABLE = 0x0002;
const uint LMEM_ZEROINIT = 0x0040;
const uint LPTR = 0x0040;
const uint LHND = 0x0042;
