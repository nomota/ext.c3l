// windows.h.c3

module c::windows @if(env::WIN32);

//
// Basic Windows Types
//

// Basic integer types
alias Byte = char;
alias Word = ushort;
alias DWord = uint;
alias QWord = ulong;
alias DWordPtr = sz;
alias Long = int;
alias ULong = uint;
alias LongLong = long;
alias ULongLong = ulong;

// Pointer types
alias PVoid = void*;
alias LPVoid = void*;
alias LPCVoid = void*;

// String types
alias Char = char;
alias WChar = ushort;
alias TChar = char;  // ANSI by default, use WChar for Unicode
alias LPStr = char*;
alias LPCStr = char*;
alias LPWStr = ushort*;
alias LPCWStr = ushort*;
alias LPTStr = char*;
alias LPCTStr = char*;

// Boolean
alias Bool = int;
const Bool TRUE = 1;
const Bool FALSE = 0;

// Handles (opaque pointers)
alias Handle = void*;
alias HInstance = void*;
alias HModule = void*;
alias HWnd = void*;
alias HMenu = void*;
alias HIcon = void*;
alias HCursor = void*;
alias HBrush = void*;
alias HFont = void*;
alias HBitmap = void*;
alias HRgn = void*;
alias HPalette = void*;
alias HAccel = void*;
alias HGlobal = void*;
alias HLocal = void*;

// Special handle values
const Handle INVALID_HANDLE_VALUE = (Handle)(uptr::max);
const Handle NULL_HANDLE = (Handle)0;

//
// Error Codes
//

const DWord ERROR_SUCCESS = 0;
const DWord ERROR_INVALID_FUNCTION = 1;
const DWord ERROR_FILE_NOT_FOUND = 2;
const DWord ERROR_PATH_NOT_FOUND = 3;
const DWord ERROR_TOO_MANY_OPEN_FILES = 4;
const DWord ERROR_ACCESS_DENIED = 5;
const DWord ERROR_INVALID_HANDLE = 6;
const DWord ERROR_NOT_ENOUGH_MEMORY = 8;
const DWord ERROR_INVALID_DATA = 13;
const DWord ERROR_OUTOFMEMORY = 14;
const DWord ERROR_NO_MORE_FILES = 18;
const DWord ERROR_SHARING_VIOLATION = 32;
const DWord ERROR_HANDLE_EOF = 38;
const DWord ERROR_NOT_SUPPORTED = 50;
const DWord ERROR_ALREADY_EXISTS = 183;
const DWord ERROR_MORE_DATA = 234;
const DWord ERROR_NO_MORE_ITEMS = 259;
const DWord ERROR_DIRECTORY = 267;
const DWord ERROR_IO_PENDING = 997;

// Error handling functions
extern fn DWord getLastError() @cname("GetLastError");
extern fn void setLastError(DWord dwErrCode) @cname("SetLastError");
extern fn DWord formatMessageA(DWord dwFlags, LPCVoid lpSource, DWord dwMessageId, DWord dwLanguageId, LPStr lpBuffer, DWord nSize, void* arguments) @cname("FormatMessageA");
extern fn DWord formatMessageW(DWord dwFlags, LPCVoid lpSource, DWord dwMessageId, DWord dwLanguageId, LPWStr lpBuffer, DWord nSize, void* arguments) @cname("FormatMessageW");

// FormatMessage flags
const DWord FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000;
const DWord FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200;
const DWord FORMAT_MESSAGE_ALLOCATE_BUFFER = 0x00000100;

//
// File Operations
//

// File access modes
const DWord GENERIC_READ = 0x80000000;
const DWord GENERIC_WRITE = 0x40000000;
const DWord GENERIC_EXECUTE = 0x20000000;
const DWord GENERIC_ALL = 0x10000000;

// File share modes
const DWord FILE_SHARE_READ = 0x00000001;
const DWord FILE_SHARE_WRITE = 0x00000002;
const DWord FILE_SHARE_DELETE = 0x00000004;

// File creation dispositions
const DWord CREATE_NEW = 1;
const DWord CREATE_ALWAYS = 2;
const DWord OPEN_EXISTING = 3;
const DWord OPEN_ALWAYS = 4;
const DWord TRUNCATE_EXISTING = 5;

// File attributes
const DWord FILE_ATTRIBUTE_READONLY = 0x00000001;
const DWord FILE_ATTRIBUTE_HIDDEN = 0x00000002;
const DWord FILE_ATTRIBUTE_SYSTEM = 0x00000004;
const DWord FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
const DWord FILE_ATTRIBUTE_ARCHIVE = 0x00000020;
const DWord FILE_ATTRIBUTE_DEVICE = 0x00000040;
const DWord FILE_ATTRIBUTE_NORMAL = 0x00000080;
const DWord FILE_ATTRIBUTE_TEMPORARY = 0x00000100;
const DWord FILE_ATTRIBUTE_SPARSE_FILE = 0x00000200;
const DWord FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
const DWord FILE_ATTRIBUTE_COMPRESSED = 0x00000800;
const DWord FILE_ATTRIBUTE_OFFLINE = 0x00001000;
const DWord FILE_ATTRIBUTE_NOT_CONTENT_INDEXED = 0x00002000;
const DWord FILE_ATTRIBUTE_ENCRYPTED = 0x00004000;

// File flags
const DWord FILE_FLAG_WRITE_THROUGH = 0x80000000;
const DWord FILE_FLAG_OVERLAPPED = 0x40000000;
const DWord FILE_FLAG_NO_BUFFERING = 0x20000000;
const DWord FILE_FLAG_RANDOM_ACCESS = 0x10000000;
const DWord FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;
const DWord FILE_FLAG_DELETE_ON_CLOSE = 0x04000000;
const DWord FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
const DWord FILE_FLAG_POSIX_SEMANTICS = 0x01000000;
const DWord FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
const DWord INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF;


// File seek methods
const DWord FILE_BEGIN = 0;
const DWord FILE_CURRENT = 1;
const DWord FILE_END = 2;

// File time structure
struct FileTime
{
    DWord dwLowDateTime;
    DWord dwHighDateTime;
}

// File information structures
struct Win32FindDataA
{
    DWord dwFileAttributes;
    FileTime ftCreationTime;
    FileTime ftLastAccessTime;
    FileTime ftLastWriteTime;
    DWord nFileSizeHigh;
    DWord nFileSizeLow;
    DWord dwReserved0;
    DWord dwReserved1;
    char[260] cFileName;      // MAX_PATH
    char[14] cAlternateFileName;
}

struct Win32FindDataW
{
    DWord dwFileAttributes;
    FileTime ftCreationTime;
    FileTime ftLastAccessTime;
    FileTime ftLastWriteTime;
    DWord nFileSizeHigh;
    DWord nFileSizeLow;
    DWord dwReserved0;
    DWord dwReserved1;
    ushort[260] cFileName;    // MAX_PATH
    ushort[14] cAlternateFileName;
}

struct ByHandleFileInformation
{
    DWord dwFileAttributes;
    FileTime ftCreationTime;
    FileTime ftLastAccessTime;
    FileTime ftLastWriteTime;
    DWord dwVolumeSerialNumber;
    DWord nFileSizeHigh;
    DWord nFileSizeLow;
    DWord nNumberOfLinks;
    DWord nFileIndexHigh;
    DWord nFileIndexLow;
}

// File functions
extern fn Handle createFileA(
    LPCStr lpFileName, 
    DWord dwDesiredAccess, 
    DWord dwShareMode,
    void* lpSecurityAttributes, 
    DWord dwCreationDisposition,
    DWord dwFlagsAndAttributes, 
    Handle hTemplateFile
) @cname("CreateFileA");

extern fn Handle createFileW(
    LPCWStr lpFileName, 
    DWord dwDesiredAccess, 
    DWord dwShareMode,
    void* lpSecurityAttributes, 
    DWord dwCreationDisposition,
    DWord dwFlagsAndAttributes, 
    Handle hTemplateFile
) @cname("CreateFileW");

extern fn Bool readFile(
    Handle hFile, 
    LPVoid lpBuffer, 
    DWord nNumberOfBytesToRead,
    DWord* lpNumberOfBytesRead, 
    void* lpOverlapped
) @cname("ReadFile");

extern fn Bool writeFile(
    Handle hFile, 
    LPCVoid lpBuffer, 
    DWord nNumberOfBytesToWrite,
    DWord* lpNumberOfBytesWritten, 
    void* lpOverlapped
) @cname("WriteFile");

extern fn Bool closeHandle(Handle hObject) @cname("CloseHandle");

extern fn DWord setFilePointer(
    Handle hFile, 
    Long lDistanceToMove, 
    Long* lpDistanceToMoveHigh,
    DWord dwMoveMethod
) @cname("SetFilePointer");

extern fn Bool setFilePointerEx(
    Handle hFile, 
    LongLong liDistanceToMove,
    LongLong* lpNewFilePointer, 
    DWord dwMoveMethod
) @cname("SetFilePointerEx");

extern fn Bool getFileTime(
    Handle hFile, 
    FileTime* lpCreationTime, 
    FileTime* lpLastAccessTime,
    FileTime* lpLastWriteTime
) @cname("GetFileTime");

extern fn Bool setFileTime(
    Handle hFile, 
    FileTime* lpCreationTime, 
    FileTime* lpLastAccessTime,
    FileTime* lpLastWriteTime
) @cname("SetFileTime");

extern fn DWord getFileSize(
    Handle hFile, 
    DWord* lpFileSizeHigh
) @cname("GetFileSize");

extern fn Bool getFileSizeEx(Handle hFile, LongLong* lpFileSize) @cname("GetFileSizeEx");
extern fn DWord getFileAttributesA(LPCStr lpFileName) @cname("GetFileAttributesA");
extern fn DWord getFileAttributesW(LPCWStr lpFileName) @cname("GetFileAttributesW");
extern fn Bool setFileAttributesA(LPCStr lpFileName, DWord dwFileAttributes) @cname("SetFileAttributesA");
extern fn Bool setFileAttributesW(LPCWStr lpFileName, DWord dwFileAttributes) @cname("SetFileAttributesW");
extern fn Bool deleteFileA(LPCStr lpFileName) @cname("DeleteFileA");
extern fn Bool deleteFileW(LPCWStr lpFileName) @cname("DeleteFileW");
extern fn Bool copyFileA(LPCStr lpExistingFileName, LPCStr lpNewFileName, Bool bFailIfExists) @cname("CopyFileA");
extern fn Bool copyFileW(LPCWStr lpExistingFileName, LPCWStr lpNewFileName, Bool bFailIfExists) @cname("CopyFileW");
extern fn Bool moveFileA(LPCStr lpExistingFileName, LPCStr lpNewFileName) @cname("MoveFileA");
extern fn Bool moveFileW(LPCWStr lpExistingFileName, LPCWStr lpNewFileName) @cname("MoveFileW");
extern fn Bool getFileInformationByHandle(Handle hFile, ByHandleFileInformation* lpFileInformation) @cname("GetFileInformationByHandle");
extern fn Bool flushFileBuffers(Handle hFile) @cname("FlushFileBuffers");

// Directory functions
extern fn Bool createDirectoryA(LPCStr lpPathName, void* lpSecurityAttributes) @cname("CreateDirectoryA");
extern fn Bool createDirectoryW(LPCWStr lpPathName, void* lpSecurityAttributes) @cname("CreateDirectoryW");
extern fn Bool removeDirectoryA(LPCStr lpPathName) @cname("RemoveDirectoryA");
extern fn Bool removeDirectoryW(LPCWStr lpPathName) @cname("RemoveDirectoryW");
extern fn DWord getCurrentDirectoryA(DWord nBufferLength, LPStr lpBuffer) @cname("GetCurrentDirectoryA");
extern fn DWord getCurrentDirectoryW(DWord nBufferLength, LPWStr lpBuffer) @cname("GetCurrentDirectoryW");
extern fn Bool setCurrentDirectoryA(LPCStr lpPathName) @cname("SetCurrentDirectoryA");
extern fn Bool setCurrentDirectoryW(LPCWStr lpPathName) @cname("SetCurrentDirectoryW");

// Find file functions
extern fn Handle findFirstFileA(LPCStr lpFileName, Win32FindDataA* lpFindFileData) @cname("FindFirstFileA");
extern fn Handle findFirstFileW(LPCWStr lpFileName, Win32FindDataW* lpFindFileData) @cname("FindFirstFileW");
extern fn Bool findNextFileA(Handle hFindFile, Win32FindDataA* lpFindFileData) @cname("FindNextFileA");
extern fn Bool findNextFileW(Handle hFindFile, Win32FindDataW* lpFindFileData) @cname("FindNextFileW");
extern fn Bool findClose(Handle hFindFile) @cname("FindClose");

//
// Memory Management
//

// Memory allocation flags
const DWord MEM_COMMIT = 0x00001000;
const DWord MEM_RESERVE = 0x00002000;
const DWord MEM_RESET = 0x00080000;
const DWord MEM_RELEASE = 0x00008000;
const DWord MEM_DECOMMIT = 0x00004000;

// Memory protection flags
const DWord PAGE_NOACCESS = 0x01;
const DWord PAGE_READONLY = 0x02;
const DWord PAGE_READWRITE = 0x04;
const DWord PAGE_WRITECOPY = 0x08;
const DWord PAGE_EXECUTE = 0x10;
const DWord PAGE_EXECUTE_READ = 0x20;
const DWord PAGE_EXECUTE_READWRITE = 0x40;
const DWord PAGE_EXECUTE_WRITECOPY = 0x80;
const DWord PAGE_GUARD = 0x100;
const DWord PAGE_NOCACHE = 0x200;
const DWord PAGE_WRITECOMBINE = 0x400;

// Heap flags
const DWord HEAP_NO_SERIALIZE = 0x00000001;
const DWord HEAP_GENERATE_EXCEPTIONS = 0x00000004;
const DWord HEAP_ZERO_MEMORY = 0x00000008;

// Memory functions
extern fn LPVoid virtualAlloc(LPVoid lpAddress, sz dwSize, DWord flAllocationType,
    DWord flProtect) @cname("VirtualAlloc");
extern fn Bool virtualFree(LPVoid lpAddress, sz dwSize, DWord dwFreeType) @cname("VirtualFree");
extern fn Bool virtualProtect(LPVoid lpAddress, sz dwSize, DWord flNewProtect,
    DWord* lpflOldProtect) @cname("VirtualProtect");
extern fn sz virtualQuery(LPCVoid lpAddress, void* lpBuffer, sz dwLength) @cname("VirtualQuery");

// Heap functions
extern fn Handle getProcessHeap() @cname("GetProcessHeap");
extern fn Handle heapCreate(DWord flOptions, sz dwInitialSize, sz dwMaximumSize) @cname("HeapCreate");
extern fn Bool heapDestroy(Handle hHeap) @cname("HeapDestroy");
extern fn LPVoid heapAlloc(Handle hHeap, DWord dwFlags, sz dwBytes) @cname("HeapAlloc");
extern fn LPVoid heapReAlloc(Handle hHeap, DWord dwFlags, LPVoid lpMem, sz dwBytes) @cname("HeapReAlloc");
extern fn Bool heapFree(Handle hHeap, DWord dwFlags, LPVoid lpMem) @cname("HeapFree");
extern fn sz heapSize(Handle hHeap, DWord dwFlags, LPCVoid lpMem) @cname("HeapSize");
extern fn Bool heapValidate(Handle hHeap, DWord dwFlags, LPCVoid lpMem) @cname("HeapValidate");

// Global memory functions (legacy but still used)
extern fn HGlobal globalAlloc(uint uFlags, sz dwBytes) @cname("GlobalAlloc");
extern fn HGlobal globalReAlloc(HGlobal hMem, sz dwBytes, uint uFlags) @cname("GlobalReAlloc");
extern fn HGlobal globalFree(HGlobal hMem) @cname("GlobalFree");
extern fn LPVoid globalLock(HGlobal hMem) @cname("GlobalLock");
extern fn Bool globalUnlock(HGlobal hMem) @cname("GlobalUnlock");
extern fn sz globalSize(HGlobal hMem) @cname("GlobalSize");

//
// Process and Thread Management
//

// Process creation flags
const DWord DEBUG_PROCESS = 0x00000001;
const DWord DEBUG_ONLY_THIS_PROCESS = 0x00000002;
const DWord CREATE_SUSPENDED = 0x00000004;
const DWord DETACHED_PROCESS = 0x00000008;
const DWord CREATE_NEW_CONSOLE = 0x00000010;
const DWord CREATE_NEW_PROCESS_GROUP = 0x00000200;
const DWord CREATE_UNICODE_ENVIRONMENT = 0x00000400;
const DWord CREATE_NO_WINDOW = 0x08000000;

// Thread priority
const int THREAD_PRIORITY_IDLE = -15;
const int THREAD_PRIORITY_LOWEST = -2;
const int THREAD_PRIORITY_BELOW_NORMAL = -1;
const int THREAD_PRIORITY_NORMAL = 0;
const int THREAD_PRIORITY_ABOVE_NORMAL = 1;
const int THREAD_PRIORITY_HIGHEST = 2;
const int THREAD_PRIORITY_TIME_CRITICAL = 15;

// Wait results
const DWord WAIT_OBJECT_0 = 0x00000000;
const DWord WAIT_ABANDONED = 0x00000080;
const DWord WAIT_TIMEOUT = 0x00000102;
const DWord WAIT_FAILED = 0xFFFFFFFF;
const DWord INFINITE = 0xFFFFFFFF;

// Exit codes
const DWord STILL_ACTIVE = 259;

// Security attributes
struct SecurityAttributes
{
    DWord nLength;
    LPVoid lpSecurityDescriptor;
    Bool bInheritHandle;
}

// Process information
struct ProcessInformation
{
    Handle hProcess;
    Handle hThread;
    DWord dwProcessId;
    DWord dwThreadId;
}

// Startup info
struct StartupInfoA
{
    DWord cb;
    LPStr lpReserved;
    LPStr lpDesktop;
    LPStr lpTitle;
    DWord dwX;
    DWord dwY;
    DWord dwXSize;
    DWord dwYSize;
    DWord dwXCountChars;
    DWord dwYCountChars;
    DWord dwFillAttribute;
    DWord dwFlags;
    Word wShowWindow;
    Word cbReserved2;
    Byte* lpReserved2;
    Handle hStdInput;
    Handle hStdOutput;
    Handle hStdError;
}

struct StartupInfoW
{
    DWord cb;
    LPWStr lpReserved;
    LPWStr lpDesktop;
    LPWStr lpTitle;
    DWord dwX;
    DWord dwY;
    DWord dwXSize;
    DWord dwYSize;
    DWord dwXCountChars;
    DWord dwYCountChars;
    DWord dwFillAttribute;
    DWord dwFlags;
    Word wShowWindow;
    Word cbReserved2;
    Byte* lpReserved2;
    Handle hStdInput;
    Handle hStdOutput;
    Handle hStdError;
}

// Process functions
extern fn Bool createProcessA(LPCStr lpApplicationName, LPStr lpCommandLine, SecurityAttributes* lpProcessAttributes, SecurityAttributes* lpThreadAttributes, Bool bInheritHandles, DWord dwCreationFlags, LPVoid lpEnvironment, LPCStr lpCurrentDirectory, StartupInfoA* lpStartupInfo, ProcessInformation* lpProcessInformation) @cname("CreateProcessA");
extern fn Bool createProcessW(LPCWStr lpApplicationName, LPWStr lpCommandLine,
    SecurityAttributes* lpProcessAttributes,
    SecurityAttributes* lpThreadAttributes,
    Bool bInheritHandles, DWord dwCreationFlags,
    LPVoid lpEnvironment, LPCWStr lpCurrentDirectory,
    StartupInfoW* lpStartupInfo,
    ProcessInformation* lpProcessInformation) @cname("CreateProcessW");
extern fn Handle getCurrentProcess() @cname("GetCurrentProcess");
extern fn DWord getCurrentProcessId() @cname("GetCurrentProcessId");
extern fn Bool terminateProcess(Handle hProcess, uint uExitCode) @cname("TerminateProcess");
extern fn Bool getExitCodeProcess(Handle hProcess, DWord* lpExitCode) @cname("GetExitCodeProcess");
extern fn Handle openProcess(DWord dwDesiredAccess, Bool bInheritHandle, DWord dwProcessId) @cname("OpenProcess");
alias Thrfn = fn DWord(LPVoid);
// Thread functions
extern fn Handle createThread(SecurityAttributes* lpThreadAttributes, sz dwStackSize,
    Thrfn lpStartAddress, LPVoid lpParameter,
    DWord dwCreationFlags, DWord* lpThreadId) @cname("CreateThread");
extern fn Handle getCurrentThread() @cname("GetCurrentThread");
extern fn DWord getCurrentThreadId() @cname("GetCurrentThreadId");
extern fn Bool terminateThread(Handle hThread, DWord dwExitCode) @cname("TerminateThread");
extern fn DWord suspendThread(Handle hThread) @cname("SuspendThread");
extern fn DWord resumeThread(Handle hThread) @cname("ResumeThread");
extern fn void exitThread(DWord dwExitCode) @cname("ExitThread");
extern fn Bool getExitCodeThread(Handle hThread, DWord* lpExitCode) @cname("GetExitCodeThread");
extern fn int getThreadPriority(Handle hThread) @cname("GetThreadPriority");
extern fn Bool setThreadPriority(Handle hThread, int nPriority) @cname("SetThreadPriority");
extern fn DWord waitForSingleObject(Handle hHandle, DWord dwMilliseconds) @cname("WaitForSingleObject");
extern fn DWord waitForMultipleObjects(DWord nCount, Handle* lpHandles, Bool bWaitAll,
    DWord dwMilliseconds) @cname("WaitForMultipleObjects");

// Exit process
extern fn void exitProcess(uint uExitCode) @cname("ExitProcess") @noreturn;

//
// Synchronization
//

// Synchronization functions
extern fn Handle createMutexA(SecurityAttributes* lpMutexAttributes, Bool bInitialOwner,
    LPCStr lpName) @cname("CreateMutexA");
extern fn Handle createMutexW(SecurityAttributes* lpMutexAttributes, Bool bInitialOwner,
    LPCWStr lpName) @cname("CreateMutexW");
extern fn Handle openMutexA(DWord dwDesiredAccess, Bool bInheritHandle, LPCStr lpName) @cname("OpenMutexA");
extern fn Handle openMutexW(DWord dwDesiredAccess, Bool bInheritHandle, LPCWStr lpName) @cname("OpenMutexW");
extern fn Bool releaseMutex(Handle hMutex) @cname("ReleaseMutex");

extern fn Handle createEventA(SecurityAttributes* lpEventAttributes, Bool bManualReset,
    Bool bInitialState, LPCStr lpName) @cname("CreateEventA");
extern fn Handle createEventW(SecurityAttributes* lpEventAttributes, Bool bManualReset,
    Bool bInitialState, LPCWStr lpName) @cname("CreateEventW");
extern fn Handle openEventA(DWord dwDesiredAccess, Bool bInheritHandle, LPCStr lpName) @cname("OpenEventA");
extern fn Handle openEventW(DWord dwDesiredAccess, Bool bInheritHandle, LPCWStr lpName) @cname("OpenEventW");
extern fn Bool setEvent(Handle hEvent) @cname("SetEvent");
extern fn Bool resetEvent(Handle hEvent) @cname("ResetEvent");
extern fn Bool pulseEvent(Handle hEvent) @cname("PulseEvent");

extern fn Handle createSemaphoreA(SecurityAttributes* lpSemaphoreAttributes,
    Long lInitialCount, Long lMaximumCount, LPCStr lpName) @cname("CreateSemaphoreA");
extern fn Handle createSemaphoreW(SecurityAttributes* lpSemaphoreAttributes,
    Long lInitialCount, Long lMaximumCount, LPCWStr lpName) @cname("CreateSemaphoreW");
extern fn Handle openSemaphoreA(DWord dwDesiredAccess, Bool bInheritHandle, LPCStr lpName) @cname("OpenSemaphoreA");
extern fn Handle openSemaphoreW(DWord dwDesiredAccess, Bool bInheritHandle, LPCWStr lpName) @cname("OpenSemaphoreW");
extern fn Bool releaseSemaphore(Handle hSemaphore, Long lReleaseCount, Long* lpPreviousCount) @cname("ReleaseSemaphore");

// Critical section
struct CriticalSection
{
    void* debugInfo;
    Long lockCount;
    Long recursionCount;
    Handle owningThread;
    Handle lockSemaphore;
    DWordPtr spinCount;
}

extern fn void initializeCriticalSection(CriticalSection* lpCriticalSection) @cname("InitializeCriticalSection");
extern fn Bool initializeCriticalSectionAndSpinCount(CriticalSection* lpCriticalSection,
    DWord dwSpinCount) @cname("InitializeCriticalSectionAndSpinCount");
extern fn void enterCriticalSection(CriticalSection* lpCriticalSection) @cname("EnterCriticalSection");
extern fn Bool tryEnterCriticalSection(CriticalSection* lpCriticalSection) @cname("TryEnterCriticalSection");
extern fn void leaveCriticalSection(CriticalSection* lpCriticalSection) @cname("LeaveCriticalSection");
extern fn void deleteCriticalSection(CriticalSection* lpCriticalSection) @cname("DeleteCriticalSection");

// Interlocked operations
extern fn Long interlockedIncrement(Long* lpAddend) @cname("InterlockedIncrement");
extern fn Long interlockedDecrement(Long* lpAddend) @cname("InterlockedDecrement");
extern fn Long interlockedExchange(Long* target, Long value) @cname("InterlockedExchange");
extern fn Long interlockedExchangeAdd(Long* addend, Long value) @cname("InterlockedExchangeAdd");
extern fn Long interlockedCompareExchange(Long* destination, Long exchange, Long comparand) @cname("InterlockedCompareExchange");

//
// System Information
//

// System info structure
struct SystemInfo
{
    union
    {
        DWord dwOemId;
        struct
        {
            Word wProcessorArchitecture;
            Word wReserved;
        }
    }
    DWord dwPageSize;
    LPVoid lpMinimumApplicationAddress;
    LPVoid lpMaximumApplicationAddress;
    DWordPtr dwActiveProcessorMask;
    DWord dwNumberOfProcessors;
    DWord dwProcessorType;
    DWord dwAllocationGranularity;
    Word wProcessorLevel;
    Word wProcessorRevision;
}

// System functions
extern fn void getSystemInfo(SystemInfo* lpSystemInfo) @cname("GetSystemInfo");
extern fn DWord getTickCount() @cname("GetTickCount");
extern fn ULongLong getTickCount64() @cname("GetTickCount64");
extern fn Bool queryPerformanceCounter(LongLong* lpPerformanceCount) @cname("QueryPerformanceCounter");
extern fn Bool queryPerformanceFrequency(LongLong* lpFrequency) @cname("QueryPerformanceFrequency");

// System time
struct SystemTime
{
    Word wYear;
    Word wMonth;
    Word wDayOfWeek;
    Word wDay;
    Word wHour;
    Word wMinute;
    Word wSecond;
    Word wMilliseconds;
}

extern fn void getSystemTime(SystemTime* lpSystemTime) @cname("GetSystemTime");
extern fn void getLocalTime(SystemTime* lpSystemTime) @cname("GetLocalTime");
extern fn Bool setSystemTime(SystemTime* lpSystemTime) @cname("SetSystemTime");
extern fn Bool setLocalTime(SystemTime* lpSystemTime) @cname("SetLocalTime");
extern fn Bool systemTimeToFileTime(SystemTime* lpSystemTime, FileTime* lpFileTime) @cname("SystemTimeToFileTime");
extern fn Bool fileTimeToSystemTime(FileTime* lpFileTime, SystemTime* lpSystemTime) @cname("FileTimeToSystemTime");

//
// Console Functions
//

// Console constants
const DWord STD_INPUT_HANDLE = (DWord)(-10);
const DWord STD_OUTPUT_HANDLE = (DWord)(-11);
const DWord STD_ERROR_HANDLE = (DWord)(-12);

// Console functions
extern fn Handle getStdHandle(DWord nStdHandle) @cname("GetStdHandle");
extern fn Bool setStdHandle(DWord nStdHandle, Handle hHandle) @cname("SetStdHandle");
extern fn Bool allocConsole() @cname("AllocConsole");
extern fn Bool freeConsole() @cname("FreeConsole");
extern fn Bool attachConsole(DWord dwProcessId) @cname("AttachConsole");
extern fn Bool setConsoleTitleA(LPCStr lpConsoleTitle) @cname("SetConsoleTitleA");
extern fn Bool setConsoleTitleW(LPCWStr lpConsoleTitle) @cname("SetConsoleTitleW");
extern fn DWord getConsoleTitleA(LPStr lpConsoleTitle, DWord nSize) @cname("GetConsoleTitleA");
extern fn DWord getConsoleTitleW(LPWStr lpConsoleTitle, DWord nSize) @cname("GetConsoleTitleW");

//
// Module/Library Functions
//

// LoadLibrary flags
const DWord LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
const DWord LOAD_WITH_ALTERED_SEARCH_PATH = 0x00000008;
const DWord LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x00000020;

extern fn HModule loadLibraryA(LPCStr lpLibFileName) @cname("LoadLibraryA");
extern fn HModule loadLibraryW(LPCWStr lpLibFileName) @cname("LoadLibraryW");
extern fn HModule loadLibraryExA(LPCStr lpLibFileName, Handle hFile, DWord dwFlags) @cname("LoadLibraryExA");
extern fn HModule loadLibraryExW(LPCWStr lpLibFileName, Handle hFile, DWord dwFlags) @cname("LoadLibraryExW");
extern fn Bool freeLibrary(HModule hLibModule) @cname("FreeLibrary");
extern fn void* getProcAddress(HModule hModule, LPCStr lpProcName) @cname("GetProcAddress");
extern fn HModule getModuleHandleA(LPCStr lpModuleName) @cname("GetModuleHandleA");
extern fn HModule getModuleHandleW(LPCWStr lpModuleName) @cname("GetModuleHandleW");
extern fn DWord getModuleFileNameA(HModule hModule, LPStr lpFilename, DWord nSize) @cname("GetModuleFileNameA");
extern fn DWord getModuleFileNameW(HModule hModule, LPWStr lpFilename, DWord nSize) @cname("GetModuleFileNameW");

//
// String and Character Functions
//

extern fn int multiByteToWideChar(
    uint codePage, 
    DWord dwFlags, 
    LPCStr lpMultiByteStr,
    int cbMultiByte, 
    LPWStr lpWideCharStr, 
    int cchWideChar
) @cname("MultiByteToWideChar");

extern fn int wideCharToMultiByte(
    uint codePage, 
    DWord dwFlags, 
    LPCWStr lpWideCharStr,
    int cchWideChar, 
    LPStr lpMultiByteStr, 
    int cbMultiByte,
    LPCStr lpDefaultChar, 
    Bool* lpUsedDefaultChar
) @cname("WideCharToMultiByte");

const uint CP_ACP = 0;   // ANSI code page
const uint CP_UTF8 = 65001; // UTF-8 code page

//
// Miscellaneous
//

extern fn void sleep(DWord dwMilliseconds) @cname("Sleep");
extern fn void outputDebugStringA(LPCStr lpOutputString) @cname("OutputDebugStringA");
extern fn void outputDebugStringW(LPCWStr lpOutputString) @cname("OutputDebugStringW");
extern fn Bool isDebuggerPresent() @cname("IsDebuggerPresent");
extern fn void debugBreak() @cname("DebugBreak");

// GetVersion (deprecated but still used)
extern fn DWord getVersion() @cname("GetVersion");

// Environment variables
extern fn DWord getEnvironmentVariableA(LPCStr lpName, LPStr lpBuffer, DWord nSize) @cname("GetEnvironmentVariableA");
extern fn DWord getEnvironmentVariableW(LPCWStr lpName, LPWStr lpBuffer, DWord nSize) @cname("GetEnvironmentVariableW");
extern fn Bool setEnvironmentVariableA(LPCStr lpName, LPCStr lpValue) @cname("SetEnvironmentVariableA");
extern fn Bool setEnvironmentVariableW(LPCWStr lpName, LPCWStr lpValue) @cname("SetEnvironmentVariableW");

// Command line
extern fn LPStr getCommandLineA() @cname("GetCommandLineA");
extern fn LPWStr getCommandLineW() @cname("GetCommandLineW");

// Computer name
extern fn Bool getComputerNameA(LPStr lpBuffer, DWord* nSize) @cname("GetComputerNameA");
extern fn Bool getComputerNameW(LPWStr lpBuffer, DWord* nSize) @cname("GetComputerNameW");

//
// Macros and Helper Functions
//

// LOWORD/HIWORD macros
macro Word loword(DWord dw) => ((Word)((DWordPtr)(dw) & 0xFFFF));
macro Word hiword(DWord dw) => ((Word)((DWordPtr)(dw) >> 16));

// LOBYTE/HIBYTE macros
macro Byte lobyte(Word w) => ((Byte)((DWordPtr)(w) & 0xFF));
macro Byte hibyte(Word w) => ((Byte)((DWordPtr)(w) >> 8));

// MAKEWORD/MAKELONG macros
macro Word makeword(Byte lo, Byte hi) => ((Word)(((Byte)(lo)) | ((Word)((Byte)(hi))) << 8));
macro DWord makelong(Word lo, Word hi) => ((DWord)(((Word)(lo)) | ((DWord)((Word)(hi))) << 16));

// Success/failure checks
macro Bool succeeded(Long hr) => ((Long)(hr) >= 0);
macro Bool failed(Long hr) => ((Long)(hr) < 0);

// eof