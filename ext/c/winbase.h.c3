// winbase.h.c3l - C3 bindings for winbase.h (Windows Base API)

// Requires Windows platform

module c::winbase @if(env::WIN32);

alias Byte = char;
alias Word = ushort;
alias DWord = uint;
alias QWord = ulong;
alias DWordPtr = usz;
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

// ============================================================
// Constants - Handle Values
// ============================================================

const Handle INVALID_HANDLE_VALUE       = (Handle)(uptr)uptr.max;
const Handle NULL_HANDLE                = (Handle)0;

// ============================================================
// Constants - INFINITE / Timeout
// ============================================================

const uint INFINITE                     = 0xFFFFFFFF;
const uint IGNORE                       = 0;

// ============================================================
// Constants - Wait Results
// ============================================================

const DWord WAIT_FAILED                 = 0xFFFFFFFF;
const DWord WAIT_OBJECT_0               = 0x00000000;
const DWord WAIT_ABANDONED              = 0x00000080;
const DWord WAIT_ABANDONED_0            = 0x00000080;
const DWord WAIT_IO_COMPLETION          = 0x000000C0;
const DWord WAIT_TIMEOUT                = 0x00000102;

// ============================================================
// Constants - File Attributes
// ============================================================

const DWord FILE_ATTRIBUTE_READONLY             = 0x00000001;
const DWord FILE_ATTRIBUTE_HIDDEN               = 0x00000002;
const DWord FILE_ATTRIBUTE_SYSTEM               = 0x00000004;
const DWord FILE_ATTRIBUTE_DIRECTORY            = 0x00000010;
const DWord FILE_ATTRIBUTE_ARCHIVE              = 0x00000020;
const DWord FILE_ATTRIBUTE_DEVICE               = 0x00000040;
const DWord FILE_ATTRIBUTE_NORMAL               = 0x00000080;
const DWord FILE_ATTRIBUTE_TEMPORARY            = 0x00000100;
const DWord FILE_ATTRIBUTE_SPARSE_FILE          = 0x00000200;
const DWord FILE_ATTRIBUTE_REPARSE_POINT        = 0x00000400;
const DWord FILE_ATTRIBUTE_COMPRESSED           = 0x00000800;
const DWord FILE_ATTRIBUTE_OFFLINE              = 0x00001000;
const DWord FILE_ATTRIBUTE_NOT_CONTENT_INDEXED  = 0x00002000;
const DWord FILE_ATTRIBUTE_ENCRYPTED            = 0x00004000;
const DWord FILE_ATTRIBUTE_VIRTUAL              = 0x00010000;
const DWord FILE_ATTRIBUTE_RECALL_ON_OPEN       = 0x00040000;
const DWord FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS= 0x00400000;
const DWord INVALID_FILE_ATTRIBUTES             = 0xFFFFFFFF;

// ============================================================
// Constants - File Flags
// ============================================================

const DWord FILE_FLAG_WRITE_THROUGH         = 0x80000000;
const DWord FILE_FLAG_OVERLAPPED            = 0x40000000;
const DWord FILE_FLAG_NO_BUFFERING          = 0x20000000;
const DWord FILE_FLAG_RANDOM_ACCESS         = 0x10000000;
const DWord FILE_FLAG_SEQUENTIAL_SCAN       = 0x08000000;
const DWord FILE_FLAG_DELETE_ON_CLOSE       = 0x04000000;
const DWord FILE_FLAG_BACKUP_SEMANTICS      = 0x02000000;
const DWord FILE_FLAG_POSIX_SEMANTICS       = 0x01000000;
const DWord FILE_FLAG_SESSION_AWARE         = 0x00800000;
const DWord FILE_FLAG_OPEN_REPARSE_POINT    = 0x00200000;
const DWord FILE_FLAG_OPEN_NO_RECALL        = 0x00100000;
const DWord FILE_FLAG_FIRST_PIPE_INSTANCE   = 0x00080000;

// ============================================================
// Constants - File Access Rights
// ============================================================

const DWord GENERIC_READ                = 0x80000000;
const DWord GENERIC_WRITE               = 0x40000000;
const DWord GENERIC_EXECUTE             = 0x20000000;
const DWord GENERIC_ALL                 = 0x10000000;

const DWord FILE_READ_DATA              = 0x0001;
const DWord FILE_LIST_DIRECTORY         = 0x0001;
const DWord FILE_WRITE_DATA             = 0x0002;
const DWord FILE_ADD_FILE               = 0x0002;
const DWord FILE_APPEND_DATA            = 0x0004;
const DWord FILE_ADD_SUBDIRECTORY       = 0x0004;
const DWord FILE_CREATE_PIPE_INSTANCE   = 0x0004;
const DWord FILE_READ_EA                = 0x0008;
const DWord FILE_WRITE_EA               = 0x0010;
const DWord FILE_EXECUTE                = 0x0020;
const DWord FILE_TRAVERSE               = 0x0020;
const DWord FILE_DELETE_CHILD           = 0x0040;
const DWord FILE_READ_ATTRIBUTES        = 0x0080;
const DWord FILE_WRITE_ATTRIBUTES       = 0x0100;
const DWord FILE_ALL_ACCESS             = 0x001F01FF;

// ============================================================
// Constants - File Share Mode
// ============================================================

const DWord FILE_SHARE_NONE             = 0x00000000;
const DWord FILE_SHARE_READ             = 0x00000001;
const DWord FILE_SHARE_WRITE            = 0x00000002;
const DWord FILE_SHARE_DELETE           = 0x00000004;

// ============================================================
// Constants - File Creation Disposition
// ============================================================

const DWord CREATE_NEW                  = 1;
const DWord CREATE_ALWAYS               = 2;
const DWord OPEN_EXISTING               = 3;
const DWord OPEN_ALWAYS                 = 4;
const DWord TRUNCATE_EXISTING           = 5;

// ============================================================
// Constants - File Move Method (SetFilePointer)
// ============================================================

const DWord FILE_BEGIN                  = 0;
const DWord FILE_CURRENT                = 1;
const DWord FILE_END                    = 2;

// ============================================================
// Constants - Standard Handles
// ============================================================

const DWord STD_INPUT_HANDLE            = (DWord)-10;
const DWord STD_OUTPUT_HANDLE           = (DWord)-11;
const DWord STD_ERROR_HANDLE            = (DWord)-12;

// ============================================================
// Constants - Global/Local Memory Flags
// ============================================================

const uint GMEM_FIXED                   = 0x0000;
const uint GMEM_MOVEABLE                = 0x0002;
const uint GMEM_NOCOMPACT               = 0x0010;
const uint GMEM_NODISCARD               = 0x0020;
const uint GMEM_ZEROINIT                = 0x0040;
const uint GMEM_MODIFY                  = 0x0080;
const uint GMEM_DISCARDABLE             = 0x0100;
const uint GMEM_NOT_BANKED              = 0x1000;
const uint GMEM_SHARE                   = 0x2000;
const uint GMEM_DDESHARE                = 0x2000;
const uint GMEM_NOTIFY                  = 0x4000;
const uint GMEM_LOWER                   = GMEM_NOT_BANKED;
const uint GMEM_VALID_FLAGS             = 0x7F72;
const uint GMEM_INVALID_HANDLE          = 0x8000;
const uint GHND                         = (GMEM_MOVEABLE | GMEM_ZEROINIT);
const uint GPTR                         = (GMEM_FIXED | GMEM_ZEROINIT);

const uint LMEM_FIXED                   = 0x0000;
const uint LMEM_MOVEABLE                = 0x0002;
const uint LMEM_NOCOMPACT               = 0x0010;
const uint LMEM_NODISCARD               = 0x0020;
const uint LMEM_ZEROINIT                = 0x0040;
const uint LMEM_MODIFY                  = 0x0080;
const uint LMEM_DISCARDABLE             = 0x0F00;
const uint LMEM_VALID_FLAGS             = 0x0F72;
const uint LMEM_INVALID_HANDLE          = 0x8000;
const uint LHND                         = (LMEM_MOVEABLE | LMEM_ZEROINIT);
const uint LPTR                         = (LMEM_FIXED | LMEM_ZEROINIT);
const uint NONZEROLHND                  = LMEM_MOVEABLE;
const uint NONZEROLPTR                  = LMEM_FIXED;

// ============================================================
// Constants - Virtual Memory
// ============================================================

const DWord MEM_COMMIT                  = 0x00001000;
const DWord MEM_RESERVE                 = 0x00002000;
const DWord MEM_DECOMMIT                = 0x00004000;
const DWord MEM_RELEASE                 = 0x00008000;
const DWord MEM_FREE                    = 0x00010000;
const DWord MEM_PRIVATE                 = 0x00020000;
const DWord MEM_MAPPED                  = 0x00040000;
const DWord MEM_RESET                   = 0x00080000;
const DWord MEM_TOP_DOWN                = 0x00100000;
const DWord MEM_WRITE_WATCH             = 0x00200000;
const DWord MEM_PHYSICAL                = 0x00400000;
const DWord MEM_ROTATE                  = 0x00800000;
const DWord MEM_LARGE_PAGES             = 0x20000000;
const DWord MEM_4MB_PAGES               = 0x80000000;
const DWord MEM_64K_PAGES               = (MEM_LARGE_PAGES | MEM_PHYSICAL);
const DWord MEM_RESET_UNDO              = 0x01000000;
const DWord MEM_UNMAP_WITH_TRANSIENT_BOOST = 0x00000001;
const DWord MEM_COALESCE_PLACEHOLDERS   = 0x00000001;
const DWord MEM_PRESERVE_PLACEHOLDER    = 0x00000002;
const DWord MEM_REPLACE_PLACEHOLDER     = 0x00004000;

// Page Protection
const DWord PAGE_NOACCESS               = 0x01;
const DWord PAGE_READONLY               = 0x02;
const DWord PAGE_READWRITE              = 0x04;
const DWord PAGE_WRITECOPY              = 0x08;
const DWord PAGE_EXECUTE                = 0x10;
const DWord PAGE_EXECUTE_READ           = 0x20;
const DWord PAGE_EXECUTE_READWRITE      = 0x40;
const DWord PAGE_EXECUTE_WRITECOPY      = 0x80;
const DWord PAGE_GUARD                  = 0x100;
const DWord PAGE_NOCACHE                = 0x200;
const DWord PAGE_WRITECOMBINE           = 0x400;
const DWord PAGE_TARGETS_INVALID        = 0x40000000;
const DWord PAGE_TARGETS_NO_UPDATE      = 0x40000000;

// ============================================================
// Constants - FormatMessage
// ============================================================

const DWord FORMAT_MESSAGE_ALLOCATE_BUFFER  = 0x00000100;
const DWord FORMAT_MESSAGE_IGNORE_INSERTS   = 0x00000200;
const DWord FORMAT_MESSAGE_FROM_STRING      = 0x00000400;
const DWord FORMAT_MESSAGE_FROM_HMODULE     = 0x00000800;
const DWord FORMAT_MESSAGE_FROM_SYSTEM      = 0x00001000;
const DWord FORMAT_MESSAGE_ARGUMENT_ARRAY   = 0x00002000;
const DWord FORMAT_MESSAGE_MAX_WIDTH_MASK   = 0x000000FF;

// ============================================================
// Constants - Process Creation Flags
// ============================================================

const DWord DEBUG_PROCESS                       = 0x00000001;
const DWord DEBUG_ONLY_THIS_PROCESS             = 0x00000002;
const DWord CREATE_SUSPENDED                    = 0x00000004;
const DWord DETACHED_PROCESS                    = 0x00000008;
const DWord CREATE_NEW_CONSOLE                  = 0x00000010;
const DWord NORMAL_PRIORITY_CLASS               = 0x00000020;
const DWord IDLE_PRIORITY_CLASS                 = 0x00000040;
const DWord HIGH_PRIORITY_CLASS                 = 0x00000080;
const DWord REALTIME_PRIORITY_CLASS             = 0x00000100;
const DWord CREATE_NEW_PROCESS_GROUP            = 0x00000200;
const DWord CREATE_UNICODE_ENVIRONMENT          = 0x00000400;
const DWord CREATE_SEPARATE_WOW_VDM             = 0x00000800;
const DWord CREATE_SHARED_WOW_VDM               = 0x00001000;
const DWord CREATE_FORCEDOS                     = 0x00002000;
const DWord BELOW_NORMAL_PRIORITY_CLASS         = 0x00004000;
const DWord ABOVE_NORMAL_PRIORITY_CLASS         = 0x00008000;
const DWord INHERIT_PARENT_AFFINITY             = 0x00010000;
const DWord INHERIT_CALLER_PRIORITY             = 0x00020000;
const DWord CREATE_PROTECTED_PROCESS            = 0x00040000;
const DWord EXTENDED_STARTUPINFO_PRESENT        = 0x00080000;
const DWord PROCESS_MODE_BACKGROUND_BEGIN       = 0x00100000;
const DWord PROCESS_MODE_BACKGROUND_END         = 0x00200000;
const DWord CREATE_SECURE_PROCESS               = 0x00400000;
const DWord CREATE_BREAKAWAY_FROM_JOB           = 0x01000000;
const DWord CREATE_PRESERVE_CODE_AUTHZ_LEVEL    = 0x02000000;
const DWord CREATE_DEFAULT_ERROR_MODE           = 0x04000000;
const DWord CREATE_NO_WINDOW                    = 0x08000000;
const DWord PROFILE_USER                        = 0x10000000;
const DWord PROFILE_KERNEL                      = 0x20000000;
const DWord PROFILE_SERVER                      = 0x40000000;
const DWord CREATE_IGNORE_SYSTEM_DEFAULT        = 0x80000000;

// ============================================================
// Constants - Thread Priority
// ============================================================

const int THREAD_PRIORITY_IDLE              = -15;
const int THREAD_PRIORITY_LOWEST            = -2;
const int THREAD_PRIORITY_BELOW_NORMAL      = -1;
const int THREAD_PRIORITY_NORMAL            = 0;
const int THREAD_PRIORITY_ABOVE_NORMAL      = 1;
const int THREAD_PRIORITY_HIGHEST           = 2;
const int THREAD_PRIORITY_TIME_CRITICAL     = 15;
const int THREAD_PRIORITY_ERROR_RETURN      = 0x7FFFFFFF;

// ============================================================
// Constants - Startup Info Flags
// ============================================================

const DWord STARTF_USESHOWWINDOW        = 0x00000001;
const DWord STARTF_USESIZE              = 0x00000002;
const DWord STARTF_USEPOSITION          = 0x00000004;
const DWord STARTF_USECOUNTCHARS        = 0x00000008;
const DWord STARTF_USEFILLATTRIBUTE     = 0x00000010;
const DWord STARTF_RUNFULLSCREEN        = 0x00000020;
const DWord STARTF_FORCEONFEEDBACK      = 0x00000040;
const DWord STARTF_FORCEOFFFEEDBACK     = 0x00000080;
const DWord STARTF_USESTDHANDLES        = 0x00000100;
const DWord STARTF_USEHOTKEY            = 0x00000200;
const DWord STARTF_TITLEISLINKNAME      = 0x00000800;
const DWord STARTF_TITLEISAPPID         = 0x00001000;
const DWord STARTF_PREVENTPINNING       = 0x00002000;
const DWord STARTF_UNTRUSTEDSOURCE      = 0x00008000;

// ============================================================
// Constants - Error Modes
// ============================================================

const DWord SEM_FAILCRITICALERRORS      = 0x0001;
const DWord SEM_NOGPFAULTERRORBOX       = 0x0002;
const DWord SEM_NOALIGNMENTFAULTEXCEPT  = 0x0004;
const DWord SEM_NOOPENFILEERRORBOX      = 0x8000;

// ============================================================
// Constants - Pipe
// ============================================================

const DWord PIPE_ACCESS_INBOUND         = 0x00000001;
const DWord PIPE_ACCESS_OUTBOUND        = 0x00000002;
const DWord PIPE_ACCESS_DUPLEX          = 0x00000003;

const DWord PIPE_TYPE_BYTE              = 0x00000000;
const DWord PIPE_TYPE_MESSAGE           = 0x00000004;
const DWord PIPE_READMODE_BYTE          = 0x00000000;
const DWord PIPE_READMODE_MESSAGE       = 0x00000002;
const DWord PIPE_WAIT                   = 0x00000000;
const DWord PIPE_NOWAIT                 = 0x00000001;
const DWord PIPE_ACCEPT_REMOTE_CLIENTS  = 0x00000000;
const DWord PIPE_REJECT_REMOTE_CLIENTS  = 0x00000008;

const DWord PIPE_UNLIMITED_INSTANCES    = 255;

const DWord NMPWAIT_WAIT_FOREVER        = 0xFFFFFFFF;
const DWord NMPWAIT_NOWAIT              = 0x00000001;
const DWord NMPWAIT_USE_DEFAULT_WAIT    = 0x00000000;

// ============================================================
// Constants - Drive Types
// ============================================================

const uint DRIVE_UNKNOWN                = 0;
const uint DRIVE_NO_ROOT_DIR            = 1;
const uint DRIVE_REMOVABLE              = 2;
const uint DRIVE_FIXED                  = 3;
const uint DRIVE_REMOTE                 = 4;
const uint DRIVE_CDROM                  = 5;
const uint DRIVE_RAMDISK                = 6;

// ============================================================
// Constants - File Type
// ============================================================

const DWord FILE_TYPE_UNKNOWN           = 0x0000;
const DWord FILE_TYPE_DISK              = 0x0001;
const DWord FILE_TYPE_CHAR              = 0x0002;
const DWord FILE_TYPE_PIPE              = 0x0003;
const DWord FILE_TYPE_REMOTE            = 0x8000;

// ============================================================
// Constants - File Mapping
// ============================================================

const DWord PAGE_READONLY_SECTION       = 0x02;
const DWord PAGE_READWRITE_SECTION      = 0x04;
const DWord PAGE_WRITECOPY_SECTION      = 0x08;
const DWord PAGE_EXECUTE_SECTION        = 0x10;
const DWord PAGE_EXECUTE_READ_SECTION   = 0x20;
const DWord PAGE_EXECUTE_READWRITE_SECTION = 0x40;

const DWord SEC_COMMIT                  = 0x08000000;
const DWord SEC_IMAGE                   = 0x01000000;
const DWord SEC_IMAGE_NO_EXECUTE        = 0x11000000;
const DWord SEC_LARGE_PAGES             = 0x80000000;
const DWord SEC_NOCACHE                 = 0x10000000;
const DWord SEC_RESERVE                 = 0x04000000;
const DWord SEC_WRITECOMBINE            = 0x40000000;

const DWord FILE_MAP_WRITE              = 0x0002;
const DWord FILE_MAP_READ               = 0x0004;
const DWord FILE_MAP_ALL_ACCESS         = 0x000F001F;
const DWord FILE_MAP_EXECUTE            = 0x0020;
const DWord FILE_MAP_COPY               = 0x00000001;
const DWord FILE_MAP_RESERVE            = 0x80000000;
const DWord FILE_MAP_TARGETS_INVALID    = 0x40000000;
const DWord FILE_MAP_LARGE_PAGES        = 0x20000000;

// ============================================================
// Constants - Mutex / Event / Semaphore
// ============================================================

const DWord MUTEX_MODIFY_STATE          = 0x0001;
const DWord MUTEX_ALL_ACCESS            = 0x1F0001;
const DWord EVENT_MODIFY_STATE          = 0x0002;
const DWord EVENT_ALL_ACCESS            = 0x1F0003;
const DWord SEMAPHORE_MODIFY_STATE      = 0x0002;
const DWord SEMAPHORE_ALL_ACCESS        = 0x1F0003;

// ============================================================
// Constants - CopyFile / MoveFile Flags
// ============================================================

const DWord MOVEFILE_REPLACE_EXISTING       = 0x00000001;
const DWord MOVEFILE_COPY_ALLOWED           = 0x00000002;
const DWord MOVEFILE_DELAY_UNTIL_REBOOT     = 0x00000004;
const DWord MOVEFILE_WRITE_THROUGH          = 0x00000008;
const DWord MOVEFILE_CREATE_HARDLINK        = 0x00000010;
const DWord MOVEFILE_FAIL_IF_NOT_TRACKABLE  = 0x00000020;

// ============================================================
// Constants - GetTempPath / GetTempFileName
// ============================================================

const DWord MAX_PATH                    = 260;

// ============================================================
// Constants - Console
// ============================================================

const DWord ATTACH_PARENT_PROCESS       = 0xFFFFFFFF;

// ============================================================
// Constants - Fiber
// ============================================================

const DWord FIBER_FLAG_FLOAT_SWITCH     = 0x1;

// ============================================================
// Typedefs - Basic Types (from wintypes)
// ============================================================

// These should be defined in your wintypes module, referenced here for clarity:
// Handle, DWord, Word, Bool, LPStr, LPWStr, LPCStr, LPCWStr, WChar, Char
// HModule, HInstance, HLocal, HGlobal, HFile

alias HFile   = Handle;

// ============================================================
// Structs - Security
// ============================================================

struct SecurityAttributes {
    DWord nLength;
    void*   lpSecurityDescriptor;
    Bool bInheritHandle;
}

// ============================================================
// Structs - Overlapped I/O
// ============================================================

struct Overlapped {
    uptr    internal;
    uptr    internalHigh;
    union {
        struct {
            DWord offset;
            DWord offsetHigh;
        }
        void*   pointer;
    }
    Handle  hEvent;
}

struct OverlappedEntry {
    uptr        lpCompletionKey;
    Overlapped* lpOverlapped;
    uptr        internal;
    DWord dwNumberOfBytesTransferred;
}

// ============================================================
// Structs - FileTime / System Time
// ============================================================

struct FileTime {
    DWord dwLowDateTime;
    DWord dwHighDateTime;
}

struct SystemTime {
    Word wYear;
    Word wMonth;
    Word wDayOfWeek;
    Word wDay;
    Word wHour;
    Word wMinute;
    Word wSecond;
    Word wMilliseconds;
}

struct TimeZoneInformation {
    int[32]  szStandardName;
    SystemTime stStandardDate;
    int     bias;
    int     standardBias;
    int     daylightBias;
    int[32]  szDaylightName;
    SystemTime stDaylightDate;
}

// ============================================================
// Structs - FindData
// ============================================================

struct Win32FindDataA {
    DWord dwFileAttributes;
    FileTime ftCreationTime;
    FileTime ftLastAccessTime;
    FileTime ftLastWriteTime;
    DWord nFileSizeHigh;
    DWord nFileSizeLow;
    DWord dwReserved0;
    DWord dwReserved1;
    char[MAX_PATH] cFileName;
    char[14] cAlternateFileName;
}

struct Win32FindDataW {
    DWord dwFileAttributes;
    FileTime ftCreationTime;
    FileTime ftLastAccessTime;
    FileTime ftLastWriteTime;
    DWord nFileSizeHigh;
    DWord nFileSizeLow;
    DWord dwReserved0;
    DWord dwReserved1;
    WChar[MAX_PATH] cFileName;
    WChar[14] cAlternateFileName;
}

// ============================================================
// Structs - Startup Info
// ============================================================

struct StartupInfoA {
    DWord cb;
    char*   lpReserved;
    char*   lpDesktop;
    char*   lpTitle;
    DWord dwX;
    DWord dwY;
    DWord dwXSize;
    DWord dwYSize;
    DWord dwXCountChars;
    DWord dwYCountChars;
    DWord dwFillAttribute;
    DWord dwFlags;
    Word    wShowWindow;
    Word    cbReserved2;
    char*   lpReserved2;
    Handle  hStdInput;
    Handle  hStdOutput;
    Handle  hStdError;
}

struct StartupInfoW {
    DWord cb;
    WChar*  lpReserved;
    WChar*  lpDesktop;
    WChar*  lpTitle;
    DWord dwX;
    DWord dwY;
    DWord dwXSize;
    DWord dwYSize;
    DWord dwXCountChars;
    DWord dwYCountChars;
    DWord dwFillAttribute;
    DWord dwFlags;
    Word    wShowWindow;
    Word    cbReserved2;
    char*   lpReserved2;
    Handle  hStdInput;
    Handle  hStdOutput;
    Handle  hStdError;
}

// ============================================================
// Structs - Process Information
// ============================================================

struct ProcessInformation {
    Handle  hProcess;
    Handle  hThread;
    DWord dwProcessId;
    DWord dwThreadId;
}

// ============================================================
// Structs - Memory
// ============================================================

struct MemoryBasicInformation {
    void*   baseAddress;
    void*   allocationBase;
    DWord allocationProtect;
    uptr    regionSize;
    DWord state;
    DWord protect;
    DWord type;
}

struct MemoryBasicInformation32 {
    DWord baseAddress;
    DWord allocationBase;
    DWord allocationProtect;
    DWord regionSize;
    DWord state;
    DWord protect;
    DWord type;
}

struct MemoryBasicInformation64 {
    ulong   baseAddress;
    ulong   allocationBase;
    DWord allocationProtect;
    DWord __alignment_1;
    ulong   regionSize;
    DWord state;
    DWord protect;
    DWord type;
    DWord __alignment_2;
}

// ============================================================
// Structs - System Info
// ============================================================

struct SystemInfo {
    union {
        DWord dwOemId;
        struct {
            Word wProcessorArchitecture;
            Word wReserved;
        }
    }
    DWord dwPageSize;
    void* lpMinimumApplicationAddress;
    void* lpMaximumApplicationAddress;
    uptr  dwActiveProcessorMask;
    DWord dwNumberOfProcessors;
    DWord dwProcessorType;
    DWord dwAllocationGranularity;
    Word  wProcessorLevel;
    Word  wProcessorRevision;
}

// ============================================================
// Structs - Pipe
// ============================================================

struct SecurityDescriptor {
    char    revision;
    char    sbz1;
    Word    control;
    void*   owner;
    void*   group;
    void*   sacl;
    void*   dacl;
}

// ============================================================
// Structs - File Notification
// ============================================================

struct FileNotifyInformation {
    DWord nextEntryOffset;
    DWord action;
    DWord fileNameLength;
    WChar   fileName; // variable length
}

// File Notify Actions
const DWord FILE_ACTION_ADDED               = 0x00000001;
const DWord FILE_ACTION_REMOVED             = 0x00000002;
const DWord FILE_ACTION_MODIFIED            = 0x00000003;
const DWord FILE_ACTION_RENAMED_OLD_NAME    = 0x00000004;
const DWord FILE_ACTION_RENAMED_NEW_NAME    = 0x00000005;

// File Notify Change Flags
const DWord FILE_NOTIFY_CHANGE_FILE_NAME    = 0x00000001;
const DWord FILE_NOTIFY_CHANGE_DIR_NAME     = 0x00000002;
const DWord FILE_NOTIFY_CHANGE_ATTRIBUTES   = 0x00000004;
const DWord FILE_NOTIFY_CHANGE_SIZE         = 0x00000008;
const DWord FILE_NOTIFY_CHANGE_LAST_WRITE   = 0x00000010;
const DWord FILE_NOTIFY_CHANGE_LAST_ACCESS  = 0x00000020;
const DWord FILE_NOTIFY_CHANGE_CREATION     = 0x00000040;
const DWord FILE_NOTIFY_CHANGE_SECURITY     = 0x00000100;

// ============================================================
// Structs - Condition Variable / Critical Section
// ============================================================

struct CriticalSection {
    void*   debugInfo;
    int     lockCount;
    int     recursionCount;
    Handle  owningThread;
    Handle  lockSemaphore;
    uptr    spinCount;
}

struct ConditionVariable {
    void*   ptr;
}

struct SRWLock {
    void*   ptr;
}

// ============================================================
// Callback Types
// ============================================================

alias LPThreadStartRoutine  = fn DWord (void* lp_parameter);
alias LPFiberStartRoutine = fn void (void* lp_fiber_parameter);
alias TimerAPCRoutine  = fn void (void* arg_to_completion_routine, DWord timer_low_value, DWord timer_high_value);
alias FileIOCompletionRoutine  = fn void (DWord dw_error_code, DWord dw_number_of_bytes_transferred, Overlapped* lp_overlapped);
alias HandlerRoutine  = fn Bool (DWord ctrl_type);

// ============================================================
// Functions - Error Handling
// ============================================================

extern fn DWord getLastError() @cname("GetLastError");
extern fn void setLastError(DWord dw_err_code) @cname("SetLastError");
extern fn DWord formatMessageA(DWord dw_flags, void* lp_source, DWord dw_message_id, DWord dw_language_id, char* lp_buffer, DWord n_size, void* arguments) @cname("FormatMessageA");
extern fn DWord formatMessageW(DWord dw_flags, void* lp_source, DWord dw_message_id, DWord dw_language_id, WChar* lp_buffer, DWord n_size, void* arguments) @cname("FormatMessageW");

// ============================================================
// Functions - Handle
// ============================================================

extern fn Bool closeHandle(Handle h_object) @cname("CloseHandle");
extern fn Bool duplicateHandle(Handle h_source_process_handle, Handle h_source_handle, Handle h_target_process_handle, Handle* lp_target_handle, DWord dw_desired_access, Bool b_inherit_handle, DWord dw_options) @cname("DuplicateHandle");
extern fn Bool setHandleInformation(Handle h_object, DWord dw_mask, DWord dw_flags) @cname("SetHandleInformation");
extern fn Bool getHandleInformation(Handle h_object, DWord* lp_flags) @cname("GetHandleInformation");
extern fn Bool compareObjectHandles(Handle h_first, Handle h_second) @cname("CompareObjectHandles");

// ============================================================
// Functions - File Operations
// ============================================================

extern fn Handle createFileA(char* lp_file_name, DWord dw_desired_access, DWord dw_share_mode, SecurityAttributes* lp_security_attributes, DWord dw_creation_disposition, DWord dw_flags_and_attributes, Handle h_template_file) @cname("CreateFileA");
extern fn Handle createFileW(WChar* lp_file_name, DWord dw_desired_access, DWord dw_share_mode, SecurityAttributes* lp_security_attributes, DWord dw_creation_disposition, DWord dw_flags_and_attributes, Handle h_template_file) @cname("CreateFileW");
extern fn Bool readFile(Handle h_file, void* lp_buffer, DWord n_number_of_bytes_to_read, DWord* lp_number_of_bytes_read, Overlapped* lp_overlapped) @cname("ReadFile");
extern fn Bool writeFile(Handle h_file, void* lp_buffer, DWord n_number_of_bytes_to_write, DWord* lp_number_of_bytes_written, Overlapped* lp_overlapped) @cname("WriteFile");
extern fn Bool readFileEx(Handle h_file, void* lp_buffer, DWord n_number_of_bytes_to_read, Overlapped* lp_overlapped, FileIOCompletionRoutine lp_completion_routine) @cname("ReadFileEx");
extern fn Bool writeFileEx(Handle h_file, void* lp_buffer, DWord n_number_of_bytes_to_write, Overlapped* lp_overlapped, FileIOCompletionRoutine lp_completion_routine) @cname("WriteFileEx");
extern fn Bool flushFileBuffers(Handle h_file) @cname("FlushFileBuffers");
extern fn DWord setFilePointer(Handle h_file, int l_distance_to_move, int* lp_distance_to_move_high, DWord dw_move_method) @cname("SetFilePointer");
extern fn Bool setFilePointerEx(Handle h_file, long li_distance_to_move, long* lp_new_file_pointer, DWord dw_move_method) @cname("SetFilePointerEx");
extern fn Bool setEndOfFile(Handle h_file) @cname("SetEndOfFile");
extern fn Bool getFileSizeEx(Handle h_file, long* lp_file_size) @cname("GetFileSizeEx");
extern fn DWord getFileSize(Handle h_file, DWord* lp_file_size_high) @cname("GetFileSize");
extern fn DWord getFileType(Handle h_file) @cname("GetFileType");
extern fn DWord getFileAttributesA(char* lp_file_name) @cname("GetFileAttributesA");
extern fn DWord getFileAttributesW(WChar* lp_file_name) @cname("GetFileAttributesW");
extern fn Bool setFileAttributesA(char* lp_file_name, DWord dw_file_attributes) @cname("SetFileAttributesA");
extern fn Bool setFileAttributesW(WChar* lp_file_name, DWord dw_file_attributes) @cname("SetFileAttributesW");
extern fn Bool getFileTime(Handle h_file, FileTime* lp_creation_time, FileTime* lp_last_access_time, FileTime* lp_last_write_time) @cname("GetFileTime");
extern fn Bool setFileTime(Handle h_file, FileTime* lp_creation_time, FileTime* lp_last_access_time, FileTime* lp_last_write_time) @cname("SetFileTime");
extern fn Bool lockFile(Handle h_file, DWord dw_file_offset_low, DWord dw_file_offset_high, DWord n_number_of_bytes_to_lock_low, DWord n_number_of_bytes_to_lock_high) @cname("LockFile");
extern fn Bool unlockFile(Handle h_file, DWord dw_file_offset_low, DWord dw_file_offset_high, DWord n_number_of_bytes_to_unlock_low, DWord n_number_of_bytes_to_unlock_high) @cname("UnlockFile");
extern fn Bool lockFileEx(Handle h_file, DWord dw_flags, DWord dw_reserved, DWord n_number_of_bytes_to_lock_low, DWord n_number_of_bytes_to_lock_high, Overlapped* lp_overlapped) @cname("LockFileEx");
extern fn Bool unlockFileEx(Handle h_file, DWord dw_reserved, DWord n_number_of_bytes_to_unlock_low, DWord n_number_of_bytes_to_unlock_high, Overlapped* lp_overlapped) @cname("UnlockFileEx");
extern fn Bool deleteFileA(char* lp_file_name) @cname("DeleteFileA");
extern fn Bool deleteFileW(WChar* lp_file_name) @cname("DeleteFileW");
extern fn Bool copyFileA(char* lp_existing_file_name, char* lp_new_file_name, Bool b_fail_if_exists) @cname("CopyFileA");
extern fn Bool copyFileW(WChar* lp_existing_file_name, WChar* lp_new_file_name, Bool b_fail_if_exists) @cname("CopyFileW");
extern fn Bool moveFileA(char* lp_existing_file_name, char* lp_new_file_name) @cname("MoveFileA");
extern fn Bool moveFileW(WChar* lp_existing_file_name, WChar* lp_new_file_name) @cname("MoveFileW");
extern fn Bool moveFileExA(char* lp_existing_file_name, char* lp_new_file_name, DWord dw_flags) @cname("MoveFileExA");
extern fn Bool moveFileExW(WChar* lp_existing_file_name, WChar* lp_new_file_name, DWord dw_flags) @cname("MoveFileExW");
extern fn Bool createHardLinkA(char* lp_file_name, char* lp_existing_file_name, SecurityAttributes* lp_security_attributes) @cname("CreateHardLinkA");
extern fn Bool createHardLinkW(WChar* lp_file_name, WChar* lp_existing_file_name, SecurityAttributes* lp_security_attributes) @cname("CreateHardLinkW");

// ============================================================
// Functions - File Search / Directory
// ============================================================

extern fn Handle findFirstFileA(char* lp_file_name, Win32FindDataA* lp_find_file_data) @cname("FindFirstFileA");
extern fn Handle findFirstFileW(WChar* lp_file_name, Win32FindDataW* lp_find_file_data) @cname("FindFirstFileW");
extern fn Bool findNextFileA(Handle h_find_file, Win32FindDataA* lp_find_file_data) @cname("FindNextFileA");
extern fn Bool findNextFileW(Handle h_find_file, Win32FindDataW* lp_find_file_data) @cname("FindNextFileW");
extern fn Bool findClose(Handle h_find_file) @cname("FindClose");
extern fn Bool createDirectoryA(char* lp_path_name, SecurityAttributes* lp_security_attributes) @cname("CreateDirectoryA");
extern fn Bool createDirectoryW(WChar* lp_path_name, SecurityAttributes* lp_security_attributes) @cname("CreateDirectoryW");
extern fn Bool removeDirectoryA(char* lp_path_name) @cname("RemoveDirectoryA");
extern fn Bool removeDirectoryW(WChar* lp_path_name) @cname("RemoveDirectoryW");
extern fn DWord getCurrentDirectoryA(DWord n_buffer_length, char* lp_buffer) @cname("GetCurrentDirectoryA");
extern fn DWord getCurrentDirectoryW(DWord n_buffer_length, WChar* lp_buffer) @cname("GetCurrentDirectoryW");
extern fn Bool setCurrentDirectoryA(char* lp_path_name) @cname("SetCurrentDirectoryA");
extern fn Bool setCurrentDirectoryW(WChar* lp_path_name) @cname("SetCurrentDirectoryW");
extern fn DWord getTempPathA(DWord n_buffer_length, char* lp_buffer) @cname("GetTempPathA");
extern fn DWord getTempPathW(DWord n_buffer_length, WChar* lp_buffer) @cname("GetTempPathW");
extern fn uint getTempFileNameA(char* lp_path_name, char* lp_prefix_string, uint u_unique, char* lp_temp_file_name) @cname("GetTempFileNameA");
extern fn uint getTempFileNameW(WChar* lp_path_name, WChar* lp_prefix_string, uint u_unique, WChar* lp_temp_file_name) @cname("GetTempFileNameW");
extern fn DWord getFullPathNameA(char* lp_file_name, DWord n_buffer_length, char* lp_buffer, char** lp_file_part) @cname("GetFullPathNameA");
extern fn DWord getFullPathNameW(WChar* lp_file_name, DWord n_buffer_length, WChar* lp_buffer, WChar** lp_file_part) @cname("GetFullPathNameW");
extern fn DWord getShortPathNameA(char* lp_sz_long_path, char* lp_sz_short_path, DWord cch_buffer) @cname("GetShortPathNameA");
extern fn DWord getShortPathNameW(WChar* lp_sz_long_path, WChar* lp_sz_short_path, DWord cch_buffer) @cname("GetShortPathNameW");
extern fn DWord getLongPathNameA(char* lp_sz_short_path, char* lp_sz_long_path, DWord cch_buffer) @cname("GetLongPathNameA");
extern fn DWord getLongPathNameW(WChar* lp_sz_short_path, WChar* lp_sz_long_path, DWord cch_buffer) @cname("GetLongPathNameW");
extern fn DWord getDriveTypeA(char* lp_root_path_name) @cname("GetDriveTypeA");
extern fn DWord getDriveTypeW(WChar* lp_root_path_name) @cname("GetDriveTypeW");
extern fn DWord getLogicalDrives() @cname("GetLogicalDrives");
extern fn DWord getLogicalDriveStringsA(DWord n_buffer_length, char* lp_buffer) @cname("GetLogicalDriveStringsA");
extern fn DWord getLogicalDriveStringsW(DWord n_buffer_length, WChar* lp_buffer) @cname("GetLogicalDriveStringsW");
extern fn Bool getDiskFreeSpaceA(char* lp_root_path_name, DWord* lp_sectors_per_cluster, DWord* lp_bytes_per_sector, DWord* lp_number_of_free_clusters, DWord* lp_total_number_of_clusters) @cname("GetDiskFreeSpaceA");
extern fn Bool getDiskFreeSpaceW(WChar* lp_root_path_name, DWord* lp_sectors_per_cluster, DWord* lp_bytes_per_sector, DWord* lp_number_of_free_clusters, DWord* lp_total_number_of_clusters) @cname("GetDiskFreeSpaceW");
extern fn Bool getDiskFreeSpaceExA(char* lp_directory_name, ulong* lp_free_bytes_available, ulong* lp_total_number_of_bytes, ulong* lp_total_number_of_free_bytes) @cname("GetDiskFreeSpaceExA");
extern fn Bool getDiskFreeSpaceExW(WChar* lp_directory_name, ulong* lp_free_bytes_available, ulong* lp_total_number_of_bytes, ulong* lp_total_number_of_free_bytes) @cname("GetDiskFreeSpaceExW");

// ============================================================
// Functions - File Change Notification
// ============================================================

extern fn Handle findFirstChangeNotificationA(char* lp_path_name, Bool b_watch_subtree, DWord dw_notify_filter) @cname("FindFirstChangeNotificationA");
extern fn Handle findFirstChangeNotificationW(WChar* lp_path_name, Bool b_watch_subtree, DWord dw_notify_filter) @cname("FindFirstChangeNotificationW");
extern fn Bool findNextChangeNotification(Handle h_change_handle) @cname("FindNextChangeNotification");
extern fn Bool findCloseChangeNotification(Handle h_change_handle) @cname("FindCloseChangeNotification");
extern fn Bool readDirectoryChangesW(Handle h_directory, void* lp_buffer, DWord n_buffer_length, Bool b_watch_subtree, DWord dw_notify_filter, DWord* lp_bytes_returned, Overlapped* lp_overlapped, FileIOCompletionRoutine lp_completion_routine) @cname("ReadDirectoryChangesW");

// ============================================================
// Functions - Memory Management
// ============================================================

extern fn void*  virtualAlloc(void* lp_address, uptr dw_size, DWord fl_allocation_type, DWord fl_protect) @cname("VirtualAlloc");
extern fn void* virtualAllocEx(Handle h_process, void* lp_address, uptr dw_size, DWord fl_allocation_type, DWord fl_protect) @cname("VirtualAllocEx");
extern fn Bool virtualFree(void* lp_address, uptr dw_size, DWord dw_free_type) @cname("VirtualFree");
extern fn Bool virtualFreeEx(Handle h_process, void* lp_address, uptr dw_size, DWord dw_free_type) @cname("VirtualFreeEx");
extern fn Bool virtualProtect(void* lp_address, uptr dw_size, DWord fl_new_protect, DWord* lp_fl_old_protect) @cname("VirtualProtect");
extern fn Bool virtualProtectEx(Handle h_process, void* lp_address, uptr dw_size, DWord fl_new_protect, DWord* lp_fl_old_protect) @cname("VirtualProtectEx");
extern fn uptr virtualQuery(void* lp_address, MemoryBasicInformation* lp_buffer, uptr dw_length) @cname("VirtualQuery");
extern fn uptr virtualQueryEx(Handle h_process, void* lp_address, MemoryBasicInformation* lp_buffer, uptr dw_length) @cname("VirtualQueryEx");
extern fn Bool virtualLock(void* lp_address, uptr dw_size) @cname("VirtualLock");
extern fn Bool virtualUnlock(void* lp_address, uptr dw_size) @cname("VirtualUnlock");

extern fn HGlobal globalAlloc(uint u_flags, uptr dw_bytes) @cname("GlobalAlloc");
extern fn HGlobal globalReAlloc(HGlobal h_mem, uptr dw_bytes, uint u_flags) @cname("GlobalReAlloc");
extern fn HGlobal globalFree(HGlobal h_mem) @cname("GlobalFree");
extern fn void* globalLock(HGlobal h_mem) @cname("GlobalLock");
extern fn Bool globalUnlock(HGlobal h_mem) @cname("GlobalUnlock");
extern fn uptr globalSize(HGlobal h_mem) @cname("GlobalSize");

extern fn HLocal localAlloc(uint u_flags, uptr u_bytes) @cname("LocalAlloc");
extern fn HLocal localReAlloc(HLocal h_mem, uptr u_bytes, uint u_flags) @cname("LocalReAlloc");
extern fn HLocal localFree(HLocal h_mem) @cname("LocalFree");
extern fn void* localLock(HLocal h_mem) @cname("LocalLock");
extern fn Bool localUnlock(HLocal h_mem) @cname("LocalUnlock");
extern fn uptr localSize(HLocal h_mem) @cname("LocalSize");

extern fn uptr getLargePageMinimum() @cname("GetLargePageMinimum");

// ============================================================
// Functions - Memory Mapped Files
// ============================================================

extern fn Handle createFileMappingA(Handle h_file, SecurityAttributes* lp_file_mapping_attributes, DWord fl_protect, DWord dw_maximum_size_high, DWord dw_maximum_size_low, char* lp_name) @cname("CreateFileMappingA");
extern fn Handle createFileMappingW(Handle h_file, SecurityAttributes* lp_file_mapping_attributes, DWord fl_protect, DWord dw_maximum_size_high, DWord dw_maximum_size_low, WChar* lp_name) @cname("CreateFileMappingW");
extern fn Handle openFileMappingA(DWord dw_desired_access, Bool b_inherit_handle, char* lp_name) @cname("OpenFileMappingA");
extern fn Handle openFileMappingW(DWord dw_desired_access, Bool b_inherit_handle, WChar* lp_name) @cname("OpenFileMappingW");
extern fn void* mapViewOfFile(Handle h_file_mapping_object, DWord dw_desired_access, DWord dw_file_offset_high, DWord dw_file_offset_low, uptr dw_number_of_bytes_to_map) @cname("MapViewOfFile");
extern fn void* mapViewOfFileEx(Handle h_file_mapping_object, DWord dw_desired_access, DWord dw_file_offset_high, DWord dw_file_offset_low, uptr dw_number_of_bytes_to_map, void* lp_base_address) @cname("MapViewOfFileEx");
extern fn Bool unmapViewOfFile(void* lp_base_address) @cname("UnmapViewOfFile");
extern fn Bool flushViewOfFile(void* lp_base_address, uptr dw_number_of_bytes_to_flush) @cname("FlushViewOfFile");

// ============================================================
// Functions - Synchronization
// ============================================================

extern fn void sleep(DWord dw_milliseconds) @cname("Sleep");
extern fn DWord sleepEx(DWord dw_milliseconds, Bool b_alertable) @cname("SleepEx");
extern fn DWord waitForSingleObject(Handle h_handle, DWord dw_milliseconds) @cname("WaitForSingleObject");
extern fn DWord waitForSingleObjectEx(Handle h_handle, DWord dw_milliseconds, Bool b_alertable) @cname("WaitForSingleObjectEx");
extern fn DWord waitForMultipleObjects(DWord n_count, Handle* lp_handles, Bool b_wait_all, DWord dw_milliseconds) @cname("WaitForMultipleObjects");
extern fn DWord waitForMultipleObjectsEx(DWord n_count, Handle* lp_handles, Bool b_wait_all, DWord dw_milliseconds, Bool b_alertable) @cname("WaitForMultipleObjectsEx");

// Mutex
extern fn Handle createMutexA(SecurityAttributes* lp_mutex_attributes, Bool b_initial_owner, char* lp_name) @cname("CreateMutexA");
extern fn Handle createMutexW(SecurityAttributes* lp_mutex_attributes, Bool b_initial_owner, WChar* lp_name) @cname("CreateMutexW");
extern fn Handle openMutexA(DWord dw_desired_access, Bool b_inherit_handle, char* lp_name) @cname("OpenMutexA");
extern fn Handle openMutexW(DWord dw_desired_access, Bool b_inherit_handle, WChar* lp_name) @cname("OpenMutexW");
extern fn Bool releaseMutex(Handle h_mutex) @cname("ReleaseMutex");

// Event
extern fn Handle createEventA(SecurityAttributes* lp_event_attributes, Bool b_manual_reset, Bool b_initial_state, char* lp_name) @cname("CreateEventA");
extern fn Handle createEventW(SecurityAttributes* lp_event_attributes, Bool b_manual_reset, Bool b_initial_state, WChar* lp_name) @cname("CreateEventW");
extern fn Handle openEventA(DWord dw_desired_access, Bool b_inherit_handle, char* lp_name) @cname("OpenEventA");
extern fn Handle openEventW(DWord dw_desired_access, Bool b_inherit_handle, WChar* lp_name) @cname("OpenEventW");
extern fn Bool setEvent(Handle h_event) @cname("SetEvent");
extern fn Bool resetEvent(Handle h_event) @cname("ResetEvent");
extern fn Bool pulseEvent(Handle h_event) @cname("PulseEvent");

// Semaphore
extern fn Handle createSemaphoreA(SecurityAttributes* lp_semaphore_attributes, int l_initial_count, int l_maximum_count, char* lp_name) @cname("CreateSemaphoreA");
extern fn Handle createSemaphoreW(SecurityAttributes* lp_semaphore_attributes, int l_initial_count, int l_maximum_count, WChar* lp_name) @cname("CreateSemaphoreW");
extern fn Handle openSemaphoreA(DWord dw_desired_access, Bool b_inherit_handle, char* lp_name) @cname("OpenSemaphoreA");
extern fn Handle openSemaphoreW(DWord dw_desired_access, Bool b_inherit_handle, WChar* lp_name) @cname("OpenSemaphoreW");
extern fn Bool releaseSemaphore(Handle h_semaphore, int l_release_count, int* lp_previous_count) @cname("ReleaseSemaphore");

// Waitable Timer
extern fn Handle createWaitableTimerA(SecurityAttributes* lp_timer_attributes, Bool b_manual_reset, char* lp_timer_name) @cname("CreateWaitableTimerA");
extern fn Handle createWaitableTimerW(SecurityAttributes* lp_timer_attributes, Bool b_manual_reset, WChar* lp_timer_name) @cname("CreateWaitableTimerW");
extern fn Handle openWaitableTimerA(DWord dw_desired_access, Bool b_inherit_handle, char* lp_timer_name) @cname("OpenWaitableTimerA");
extern fn Handle openWaitableTimerW(DWord dw_desired_access, Bool b_inherit_handle, WChar* lp_timer_name) @cname("OpenWaitableTimerW");
extern fn Bool setWaitableTimer(Handle h_timer, long* lp_due_time, int l_period, TimerAPCRoutine pfn_completion_routine, void* lp_arg_to_completion_routine, Bool f_resume) @cname("SetWaitableTimer");
extern fn Bool cancelWaitableTimer(Handle h_timer) @cname("CancelWaitableTimer");

// Critical Section
extern fn void initializeCriticalSection(CriticalSection* lp_critical_section) @cname("InitializeCriticalSection");
extern fn Bool initializeCriticalSectionAndSpinCount( CriticalSection* lp_critical_section, DWord dw_spin_count) @cname("InitializeCriticalSectionAndSpinCount");
extern fn void deleteCriticalSection(CriticalSection* lp_critical_section) @cname("DeleteCriticalSection");
extern fn void enterCriticalSection(CriticalSection* lp_critical_section) @cname("EnterCriticalSection");
extern fn Bool tryEnterCriticalSection(CriticalSection* lp_critical_section) @cname("TryEnterCriticalSection");
extern fn void leaveCriticalSection(CriticalSection* lp_critical_section) @cname("LeaveCriticalSection");

// Slim reader/Writer Lock
extern fn void initializeSRWLock(SRWLock* srw_lock) @cname("InitializeSRWLock");
extern fn void acquireSRWLockExclusive(SRWLock* srw_lock) @cname("AcquireSRWLockExclusive");
extern fn void acquireSRWLockShared(SRWLock* srw_lock) @cname("AcquireSRWLockShared");
extern fn void releaseSRWLockExclusive(SRWLock* srw_lock) @cname("ReleaseSRWLockExclusive");
extern fn void releaseSRWLockShared(SRWLock* srw_lock) @cname("ReleaseSRWLockShared");
extern fn Bool tryAcquireSRWLockExclusive(SRWLock* srw_lock) @cname("TryAcquireSRWLockExclusive");
extern fn Bool tryAcquireSRWLockShared(SRWLock* srw_lock) @cname("TryAcquireSRWLockShared");

// Condition Variable
extern fn void initializeConditionVariable(ConditionVariable* condition_variable) @cname("InitializeConditionVariable");
extern fn Bool sleepConditionVariableCS(ConditionVariable* condition_variable, CriticalSection* critical_section, DWord dw_milliseconds) @cname("SleepConditionVariableCS");
extern fn Bool sleepConditionVariableSRW(ConditionVariable* condition_variable, SRWLock* srw_lock, DWord dw_milliseconds, ulong flags) @cname("SleepConditionVariableSRW");
extern fn void wakeConditionVariable(ConditionVariable* condition_variable) @cname("WakeConditionVariable");
extern fn void wakeAllConditionVariable(ConditionVariable* condition_variable) @cname("WakeAllConditionVariable");

// interlocked
extern fn int interlockedIncrement(int* lp_addend) @cname("InterlockedIncrement");
extern fn int interlockedDecrement(int* lp_addend) @cname("InterlockedDecrement");
extern fn int interlockedExchange(int* target, int value) @cname("InterlockedExchange");
extern fn int interlockedCompareExchange(int* destination, int exchange, int comperand) @cname("InterlockedCompareExchange");
extern fn long interlockedIncrement64(long* lp_addend) @cname("InterlockedIncrement64");
extern fn long interlockedDecrement64(long* lp_addend) @cname("InterlockedDecrement64");
extern fn long interlockedExchange64(long* target, long value) @cname("InterlockedExchange64");
extern fn long interlockedCompareExchange64(long* destination, long exchange, long comperand) @cname("InterlockedCompareExchange64");

// ============================================================
// Functions - Process and Thread
// ============================================================

extern fn Handle getCurrentProcess() @cname("GetCurrentProcess");
extern fn DWord getCurrentProcessId() @cname("GetCurrentProcessId");
extern fn Handle getCurrentThread() @cname("GetCurrentThread");
extern fn DWord getCurrentThreadId() @cname("GetCurrentThreadId");
extern fn void exitProcess(uint u_exit_code) @cname("ExitProcess") @noreturn;
extern fn void exitThread(DWord dw_exit_code) @cname("ExitThread") @noreturn;
extern fn Bool terminateProcess(Handle h_process, uint u_exit_code) @cname("TerminateProcess");
extern fn Bool terminateThread(Handle h_thread, DWord dw_exit_code) @cname("TerminateThread");
extern fn Bool getExitCodeProcess(Handle h_process, DWord* lp_exit_code) @cname("GetExitCodeProcess");
extern fn Bool getExitCodeThread(Handle h_thread, DWord* lp_exit_code) @cname("GetExitCodeThread");
extern fn Handle createThread(SecurityAttributes* lp_thread_attributes, uptr dw_stack_size, LPThreadStartRoutine lp_start_address, void* lp_parameter, DWord dw_creation_flags, DWord* lp_thread_id) @cname("CreateThread");
extern fn Handle createRemoteThread(Handle h_process, SecurityAttributes* lp_thread_attributes, uptr dw_stack_size, LPThreadStartRoutine lp_start_address, void* lp_parameter, DWord dw_creation_flags, DWord* lp_thread_id) @cname("CreateRemoteThread");
extern fn Bool createProcessA(char* lp_application_name, char* lp_command_line, SecurityAttributes* lp_process_attributes, SecurityAttributes* lp_thread_attributes, Bool b_inherit_handles, DWord dw_creation_flags, void* lp_environment, char* lp_current_directory, StartupInfoA* lp_startup_info,  ProcessInformation* lp_process_information) @cname("CreateProcessA");
extern fn Bool createProcessW(WChar* lp_application_name, WChar* lp_command_line, SecurityAttributes* lp_process_attributes, SecurityAttributes* lp_thread_attributes, Bool b_inherit_handles, DWord dw_creation_flags, void* lp_environment, WChar* lp_current_directory, StartupInfoW* lp_startup_info, ProcessInformation* lp_process_information) @cname("CreateProcessW");
extern fn DWord resumeThread(Handle h_thread) @cname("ResumeThread");
extern fn DWord suspendThread(Handle h_thread) @cname("SuspendThread");
extern fn Bool setThreadPriority(Handle h_thread, int n_priority) @cname("SetThreadPriority");
extern fn int getThreadPriority(Handle h_thread) @cname("GetThreadPriority");
extern fn void getStartupInfoA(StartupInfoA* lp_startup_info) @cname("GetStartupInfoA");
extern fn void getStartupInfoW(StartupInfoW* lp_startup_info) @cname("GetStartupInfoW");
extern fn char* getCommandLineA() @cname("GetCommandLineA");
extern fn WChar* getCommandLineW() @cname("GetCommandLineW");

// TLS (Thread local Storage)
extern fn DWord tlsAlloc() @cname("TlsAlloc");
extern fn void* tlsGetValue(DWord dw_tls_index) @cname("TlsGetValue");
extern fn Bool tlsSetValue(DWord dw_tls_index, void* lp_tls_value) @cname("TlsSetValue");
extern fn Bool tlsFree(DWord dw_tls_index) @cname("TlsFree");

// Fiber
extern fn void* convertThreadToFiber(void* lp_parameter) @cname("ConvertThreadToFiber");
extern fn void* createFiber(uptr dw_stack_size, LPFiberStartRoutine lp_start_address, void* lp_parameter) @cname("CreateFiber");
extern fn void deleteFiber(void* lp_fiber) @cname("DeleteFiber");
extern fn void switchToFiber(void* lp_fiber) @cname("SwitchToFiber");
extern fn void* getFiberData() @cname("GetFiberData");
extern fn void* getCurrentFiber() @cname("GetCurrentFiber");

// ============================================================
// Functions - Pipe
// ============================================================

extern fn Bool createPipe(Handle* h_read_pipe, Handle* h_write_pipe, SecurityAttributes* lp_pipe_attributes, DWord n_size) @cname("CreatePipe");
extern fn Handle createNamedPipeA(char* lp_name, DWord dw_open_mode, DWord dw_pipe_mode, DWord n_max_instances, DWord n_out_buffer_size, DWord n_in_buffer_size, DWord n_default_time_out, SecurityAttributes* lp_security_attributes) @cname("CreateNamedPipeA");
extern fn Handle createNamedPipeW(WChar* lp_name, DWord dw_open_mode, DWord dw_pipe_mode, DWord n_max_instances, DWord n_out_buffer_size, DWord n_in_buffer_size, DWord n_default_time_out, SecurityAttributes* lp_security_attributes) @cname("CreateNamedPipeW");
extern fn Bool connectNamedPipe(Handle h_named_pipe, Overlapped* lp_overlapped) @cname("ConnectNamedPipe");
extern fn Bool disconnectNamedPipe(Handle h_named_pipe) @cname("DisconnectNamedPipe");
extern fn Bool waitNamedPipeA(char* lp_named_pipe_name, DWord n_time_out) @cname("WaitNamedPipeA");
extern fn Bool waitNamedPipeW(WChar* lp_named_pipe_name, DWord n_time_out) @cname("WaitNamedPipeW");
extern fn Bool peekNamedPipe(Handle h_named_pipe, void* lp_buffer, DWord n_buffer_size, DWord* lp_bytes_read, DWord* lp_total_bytes_avail, DWord* lp_bytes_left_this_message) @cname("PeekNamedPipe");
extern fn Bool transactNamedPipe(Handle h_named_pipe, void* lp_in_buffer, DWord n_in_buffer_size, void* lp_out_buffer, DWord n_out_buffer_size, DWord* lp_bytes_read, Overlapped* lp_overlapped) @cname("TransactNamedPipe");
extern fn Bool getNamedPipeInfo(Handle h_named_pipe, DWord* lp_flags, DWord* lp_out_buffer_size, DWord* lp_in_buffer_size, DWord* lp_max_instances) @cname("GetNamedPipeInfo");
extern fn Bool setNamedPipeHandleState(Handle h_named_pipe, DWord* lp_mode, DWord* lp_max_collection_count, DWord* lp_collect_data_timeout) @cname("SetNamedPipeHandleState");

// ============================================================
// Functions - Console
// ============================================================

extern fn Handle getStdHandle(DWord n_std_handle) @cname("GetStdHandle");
extern fn Bool setStdHandle(DWord n_std_handle, Handle h_handle) @cname("SetStdHandle");
extern fn Bool allocConsole() @cname("AllocConsole");
extern fn Bool freeConsole() @cname("FreeConsole");
extern fn Bool attachConsole(DWord dw_process_id) @cname("AttachConsole");

// ============================================================
// Functions - Module / Library
// ============================================================

extern fn HModule loadLibraryA(char* lp_lib_file_name) @cname("LoadLibraryA");
extern fn HModule loadLibraryW(WChar* lp_lib_file_name) @cname("LoadLibraryW");
extern fn HModule loadLibraryExA(char* lp_lib_file_name, Handle h_file, DWord dw_flags) @cname("LoadLibraryExA");
extern fn HModule loadLibraryExW(WChar* lp_lib_file_name, Handle h_file, DWord dw_flags) @cname("LoadLibraryExW");
extern fn Bool freeLibrary(HModule h_lib_module) @cname("FreeLibrary");
extern fn void* getProcAddress(HModule h_module, char* lp_proc_name) @cname("GetProcAddress");
extern fn DWord getModuleFileNameA(HModule h_module, char* lp_filename, DWord n_size) @cname("GetModuleFileNameA");
extern fn DWord getModuleFileNameW(HModule h_module, WChar* lp_filename, DWord n_size) @cname("GetModuleFileNameW");
extern fn HModule getModuleHandleA(char* lp_module_name) @cname("GetModuleHandleA");
extern fn HModule getModuleHandleW(WChar* lp_module_name) @cname("GetModuleHandleW");

// ============================================================
// Functions - Time
// ============================================================

extern fn void getSystemTime(SystemTime* lp_system_time) @cname("GetSystemTime");
extern fn void getLocalTime(SystemTime* lp_system_time) @cname("GetLocalTime");
extern fn Bool setSystemTime(SystemTime* lp_system_time) @cname("SetSystemTime");
extern fn Bool setLocalTime(SystemTime* lp_system_time) @cname("SetLocalTime");
extern fn DWord getTickCount() @cname("GetTickCount");
extern fn ulong getTickCount64() @cname("GetTickCount64");
extern fn Bool queryPerformanceCounter(long* lp_performance_count) @cname("QueryPerformanceCounter");
extern fn Bool queryPerformanceFrequency(long* lp_frequency) @cname("QueryPerformanceFrequency");
extern fn void getSystemTimeAsFileTime(FileTime* lp_system_time_as_file_time) @cname("GetSystemTimeAsFileTime");
extern fn Bool systemTimeToFileTime(SystemTime* lp_system_time, FileTime* lp_file_time) @cname("SystemTimeToFileTime");
extern fn Bool fileTimeToSystemTime(FileTime* lp_file_time, SystemTime* lp_system_time) @cname("FileTimeToSystemTime");
extern fn Bool fileTimeToLocalFileTime(FileTime* lp_file_time, FileTime* lp_local_file_time) @cname("FileTimeToLocalFileTime");
extern fn Bool localFileTimeToFileTime(FileTime* lp_local_file_time, FileTime* lp_file_time) @cname("LocalFileTimeToFileTime");
extern fn int compareFileTime(FileTime* lp_file_time_1, FileTime* lp_file_time_2) @cname("CompareFileTime");
extern fn Bool getTimeZoneInformation(TimeZoneInformation* lp_time_zone_information) @cname("GetTimeZoneInformation");

// ============================================================
// Functions - System Info
// ============================================================

extern fn void getSystemInfo(SystemInfo* lp_system_info) @cname("GetSystemInfo");
extern fn void getNativeSystemInfo(SystemInfo* lp_system_info) @cname("GetNativeSystemInfo");
extern fn DWord getVersion() @cname("GetVersion");
extern fn DWord getWindowsDirectoryA(char* lp_buffer, uint u_size) @cname("GetWindowsDirectoryA");
extern fn DWord getWindowsDirectoryW(WChar* lp_buffer, uint u_size) @cname("GetWindowsDirectoryW");
extern fn DWord getSystemDirectoryA(char* lp_buffer, uint u_size) @cname("GetSystemDirectoryA");
extern fn DWord getSystemDirectoryW(WChar* lp_buffer, uint u_size) @cname("GetSystemDirectoryW");
extern fn DWord getSystemWindowsDirectoryA(char* lp_buffer, uint u_size) @cname("GetSystemWindowsDirectoryA");
extern fn DWord getSystemWindowsDirectoryW(WChar* lp_buffer, uint u_size) @cname("GetSystemWindowsDirectoryW");
extern fn DWord getComputerNameA(char* lp_buffer, DWord* n_size) @cname("GetComputerNameA");
extern fn DWord getComputerNameW(WChar* lp_buffer, DWord* n_size) @cname("GetComputerNameW");
extern fn Bool setComputerNameA(char* lp_computer_name) @cname("SetComputerNameA");
extern fn Bool setComputerNameW(WChar* lp_computer_name) @cname("SetComputerNameW");

// ============================================================
// Functions - Environment
// ============================================================

extern fn DWord getEnvironmentVariableA(char* lp_name, char* lp_buffer, DWord n_size) @cname("GetEnvironmentVariableA");
extern fn DWord getEnvironmentVariableW(WChar* lp_name, WChar* lp_buffer, DWord n_size) @cname("GetEnvironmentVariableW");
extern fn Bool setEnvironmentVariableA(char* lp_name, char* lp_value) @cname("SetEnvironmentVariableA");
extern fn Bool setEnvironmentVariableW(WChar* lp_name, WChar* lp_value) @cname("SetEnvironmentVariableW");
extern fn char*  getEnvironmentStringsA() @cname("GetEnvironmentStringsA");
extern fn WChar* getEnvironmentStringsW() @cname("GetEnvironmentStringsW");
extern fn Bool freeEnvironmentStringsA(char* lp_sz_environment_block) @cname("FreeEnvironmentStringsA");
extern fn Bool freeEnvironmentStringsW(WChar* lp_sz_environment_block) @cname("FreeEnvironmentStringsW");
extern fn DWord expandEnvironmentStringsA(char* lp_src, char* lp_dst, DWord n_size) @cname("ExpandEnvironmentStringsA");
extern fn DWord expandEnvironmentStringsW(WChar* lp_src, WChar* lp_dst, DWord n_size) @cname("ExpandEnvironmentStringsW");

// ============================================================
// Functions - I/O Completion Port
// ============================================================

extern fn Handle createIoCompletionPort(Handle h_file_handle, Handle h_existing_completion_port, uptr completion_key, DWord dw_number_of_concurrent_threads) @cname("CreateIoCompletionPort");
extern fn Bool getQueuedCompletionStatus(Handle h_completion_port, DWord* lp_number_of_bytes_transferred, uptr* lp_completion_key, Overlapped** lp_overlapped, DWord dw_milliseconds) @cname("GetQueuedCompletionStatus");
extern fn Bool postQueuedCompletionStatus(Handle h_completion_port, DWord dw_number_of_bytes_transferred, uptr dw_completion_key, Overlapped* lp_overlapped) @cname("PostQueuedCompletionStatus");
extern fn Bool getQueuedCompletionStatusEx(Handle h_completion_port, OverlappedEntry* lp_completion_port_entries,  ulong ul_count, ulong* ul_num_entries_removed, DWord dw_milliseconds, Bool f_alertable) @cname("GetQueuedCompletionStatusEx");
extern fn Bool cancelIo(Handle h_file) @cname("CancelIo");
extern fn Bool cancelIoEx(Handle h_file, Overlapped* lp_overlapped) @cname("CancelIoEx");
extern fn Bool cancelSynchronousIo(Handle h_thread) @cname("CancelSynchronousIo");

// ============================================================
// Functions - Misc
// ============================================================

extern fn void outputDebugStringA(char* lp_output_string) @cname("OutputDebugStringA");
extern fn void outputDebugStringW(WChar* lp_output_string) @cname("OutputDebugStringW");
extern fn Bool isDebuggerPresent() @cname("IsDebuggerPresent");
extern fn void debugBreak() @cname("DebugBreak");
extern fn DWord getErrorMode() @cname("GetErrorMode");
extern fn DWord setErrorMode(DWord u_mode) @cname("SetErrorMode"); 
extern fn Bool beep(DWord dw_freq, DWord dw_duration) @cname("Beep");
extern fn Bool queryFullProcessImageNameA(Handle h_process, DWord dw_flags, char* lp_exe_name, DWord* lp_size) @cname("QueryFullProcessImageNameA");
extern fn Bool queryFullProcessImageNameW(Handle h_process, DWord dw_flags, WChar* lp_exe_name, DWord* lp_size) @cname("QueryFullProcessImageNameW");
extern fn Bool setConsoleCtrlHandler(HandlerRoutine handler_routine, Bool add) @cname("SetConsoleCtrlHandler");
extern fn void raiseException(DWord dw_exception_code, DWord dw_exception_flags, DWord n_number_of_arguments, uptr* lp_arguments) @cname("RaiseException") @noreturn;






// ============================================================
// Constants - Common Error Codes
// ============================================================

const DWord ERROR_SUCCESS                       = 0;
const DWord ERROR_INVALID_FUNCTION             = 1;
const DWord ERROR_FILE_NOT_FOUND               = 2;
const DWord ERROR_PATH_NOT_FOUND               = 3;
const DWord ERROR_TOO_MANY_OPEN_FILES          = 4;
const DWord ERROR_ACCESS_DENIED                = 5;
const DWord ERROR_INVALID_HANDLE               = 6;
const DWord ERROR_NOT_ENOUGH_MEMORY            = 8;
const DWord ERROR_INVALID_DATA                 = 13;
const DWord ERROR_OUTOFMEMORY                  = 14;
const DWord ERROR_INVALID_DRIVE                = 15;
const DWord ERROR_NO_MORE_FILES                = 18;
const DWord ERROR_NOT_READY                    = 21;
const DWord ERROR_BAD_LENGTH                   = 24;
const DWord ERROR_SHARING_VIOLATION            = 32;
const DWord ERROR_LOCK_VIOLATION               = 33;
const DWord ERROR_HANDLE_EOF                   = 38;
const DWord ERROR_NOT_SUPPORTED                = 50;
const DWord ERROR_FILE_EXISTS                  = 80;
const DWord ERROR_INVALID_PARAMETER            = 87;
const DWord ERROR_BROKEN_PIPE                  = 109;
const DWord ERROR_OPEN_FAILED                  = 110;
const DWord ERROR_BUFFER_OVERFLOW              = 111;
const DWord ERROR_DISK_FULL                    = 112;
const DWord ERROR_CALL_NOT_IMPLEMENTED         = 120;
const DWord ERROR_INSUFFICIENT_BUFFER          = 122;
const DWord ERROR_INVALID_NAME                 = 123;
const DWord ERROR_MOD_NOT_FOUND                = 126;
const DWord ERROR_PROC_NOT_FOUND               = 127;
const DWord ERROR_WAIT_NO_CHILDREN             = 128;
const DWord ERROR_ALREADY_EXISTS               = 183;
const DWord ERROR_ENVVAR_NOT_FOUND             = 203;
const DWord ERROR_FILENAME_EXCED_RANGE         = 206;
const DWord ERROR_DIRECTORY                    = 267;
const DWord ERROR_OPERATION_ABORTED            = 995;
const DWord ERROR_IO_INCOMPLETE                = 996;
const DWord ERROR_IO_PENDING                   = 997;
const DWord ERROR_NOACCESS                     = 998;
const DWord ERROR_NO_MORE_ITEMS                = 259;
const DWord ERROR_PARTIAL_COPY                 = 299;
const DWord ERROR_TIMEOUT                      = 1460;
const DWord ERROR_ABANDONED_WAIT_0             = 735;
const DWord ERROR_NOT_OWNER                    = 288;
const DWord ERROR_PIPE_BUSY                    = 231;
const DWord ERROR_PIPE_NOT_CONNECTED           = 233;
const DWord ERROR_MORE_DATA                    = 234;
const DWord ERROR_NO_DATA                      = 232;
const DWord ERROR_PIPE_CONNECTED               = 535;
const DWord ERROR_PIPE_LISTENING               = 536;
const DWord WAIT_OBJECT_0_ERROR                = 0x80070000; // HRESULT conversion
const DWord ERROR_GEN_FAILURE                  = 31;
const DWord ERROR_INVALID_BLOCK                = 9;

// ============================================================
// Constants - Process / Thread Access Rights
// ============================================================

const DWord PROCESS_TERMINATE                  = 0x0001;
const DWord PROCESS_CREATE_THREAD              = 0x0002;
const DWord PROCESS_SET_SESSIONID              = 0x0004;
const DWord PROCESS_VM_OPERATION               = 0x0008;
const DWord PROCESS_VM_READ                    = 0x0010;
const DWord PROCESS_VM_WRITE                   = 0x0020;
const DWord PROCESS_DUP_HANDLE                 = 0x0040;
const DWord PROCESS_CREATE_PROCESS             = 0x0080;
const DWord PROCESS_SET_QUOTA                  = 0x0100;
const DWord PROCESS_SET_INFORMATION            = 0x0200;
const DWord PROCESS_QUERY_INFORMATION          = 0x0400;
const DWord PROCESS_SUSPEND_RESUME             = 0x0800;
const DWord PROCESS_QUERY_LIMITED_INFORMATION  = 0x1000;
const DWord PROCESS_ALL_ACCESS                 = 0x001FFFFF;

const DWord THREAD_TERMINATE                   = 0x0001;
const DWord THREAD_SUSPEND_RESUME              = 0x0002;
const DWord THREAD_GET_CONTEXT                 = 0x0008;
const DWord THREAD_SET_CONTEXT                 = 0x0010;
const DWord THREAD_QUERY_INFORMATION           = 0x0040;
const DWord THREAD_SET_INFORMATION             = 0x0020;
const DWord THREAD_SET_THREAD_TOKEN            = 0x0080;
const DWord THREAD_IMPERSONATE                 = 0x0100;
const DWord THREAD_DIRECT_IMPERSONATION        = 0x0200;
const DWord THREAD_SET_LIMITED_INFORMATION     = 0x0400;
const DWord THREAD_QUERY_LIMITED_INFORMATION   = 0x0800;
const DWord THREAD_RESUME                      = 0x1000;
const DWord THREAD_ALL_ACCESS                  = 0x001FFFFF;

// ============================================================
// Constants - Heap Flags
// ============================================================

const DWord HEAP_NO_SERIALIZE                  = 0x00000001;
const DWord HEAP_GROWABLE                      = 0x00000002;
const DWord HEAP_GENERATE_EXCEPTIONS           = 0x00000004;
const DWord HEAP_ZERO_MEMORY                   = 0x00000008;
const DWord HEAP_REALLOC_IN_PLACE_ONLY         = 0x00000010;
const DWord HEAP_TAIL_CHECKING_ENABLED         = 0x00000020;
const DWord HEAP_FREE_CHECKING_ENABLED         = 0x00000040;
const DWord HEAP_DISABLE_COALESCE_ON_FREE      = 0x00000080;
const DWord HEAP_CREATE_ALIGN_16               = 0x00010000;
const DWord HEAP_CREATE_ENABLE_TRACING         = 0x00020000;
const DWord HEAP_CREATE_ENABLE_EXECUTE         = 0x00040000;

// ============================================================
// Constants - IOCP / Completion Notification Modes
// ============================================================

const char FILE_SKIP_COMPLETION_PORT_ON_SUCCESS = 0x1;
const char FILE_SKIP_SET_EVENT_ON_HANDLE        = 0x2;

// ============================================================
// Constants - Job Object
// ============================================================

const DWord JOB_OBJECT_ASSIGN_PROCESS          = 0x0001;
const DWord JOB_OBJECT_SET_ATTRIBUTES          = 0x0002;
const DWord JOB_OBJECT_QUERY                   = 0x0004;
const DWord JOB_OBJECT_TERMINATE               = 0x0008;
const DWord JOB_OBJECT_SET_SECURITY_ATTRIBUTES = 0x0010;
const DWord JOB_OBJECT_ALL_ACCESS              = 0x001F001F;

// ============================================================
// Constants - DuplicateHandle Options
// ============================================================

const DWord DUPLICATE_CLOSE_SOURCE             = 0x00000001;
const DWord DUPLICATE_SAME_ACCESS              = 0x00000002;

// ============================================================
// Constants - IsWow64Process / Machine
// ============================================================

const ushort PROCESSOR_ARCHITECTURE_INTEL       = 0;
const ushort PROCESSOR_ARCHITECTURE_MIPS        = 1;
const ushort PROCESSOR_ARCHITECTURE_ALPHA       = 2;
const ushort PROCESSOR_ARCHITECTURE_PPC         = 3;
const ushort PROCESSOR_ARCHITECTURE_SHX         = 4;
const ushort PROCESSOR_ARCHITECTURE_ARM         = 5;
const ushort PROCESSOR_ARCHITECTURE_IA64        = 6;
const ushort PROCESSOR_ARCHITECTURE_AMD64       = 9;
const ushort PROCESSOR_ARCHITECTURE_ARM64       = 12;
const ushort PROCESSOR_ARCHITECTURE_UNKNOWN     = 0xFFFF;

// ============================================================
// Structs - File Information
// ============================================================

struct ByHandleFileInformation {
    DWord    dwFileAttributes;
    FileTime ftCreationTime;
    FileTime ftLastAccessTime;
    FileTime ftLastWriteTime;
    DWord    dwVolumeSerialNumber;
    DWord    nFileSizeHigh;
    DWord    nFileSizeLow;
    DWord    nNumberOfLinks;
    DWord    nFileIndexHigh;
    DWord    nFileIndexLow;
}

// ============================================================
// Structs - Heap
// ============================================================

// PROCESS_HEAP_ENTRY
struct ProcessHeapEntry {
    void*  lpData;
    DWord  cbData;
    char   cbOverhead;
    char   iRegionIndex;
    Word   wFlags;
    union {
        struct {
            Handle hMem;
            DWord[3] dwReserved;
        }
        struct {
            DWord dwCommittedSize;
            DWord dwUncommittedSize;
            void* lpFirstBlock;
            void* lpLastBlock;
        }
    }
}

// ============================================================
// Structs - Job Object
// ============================================================

struct JobObjectBasicLimitInformation {
    long    perProcessUserTimeLimit;
    long    perJobUserTimeLimit;
    DWord   limitFlags;
    uptr    minimumWorkingSetSize;
    uptr    maximumWorkingSetSize;
    DWord   activeProcessLimit;
    uptr    affinity;
    DWord   priorityClass;
    DWord   schedulingClass;
}

struct IoCounters {
    ulong readOperationCount;
    ulong writeOperationCount;
    ulong otherOperationCount;
    ulong readTransferCount;
    ulong writeTransferCount;
    ulong otherTransferCount;
}

struct JobObjectBasicAndIoAccountingInformation {
    JobObjectBasicLimitInformation basicInfo;
    IoCounters ioInfo;
}

struct JobObjectExtendedLimitInformation {
    JobObjectBasicLimitInformation basicLimitInformation;
    IoCounters ioInfo;
    uptr       processMemoryLimit;
    uptr       jobMemoryLimit;
    uptr       peakProcessMemoryUsed;
    uptr       peakJobMemoryUsed;
}


// ============================================================
// Structs - InitOnce (one-time initialization)
// ============================================================

struct InitOnce {
    void* ptr;
}

alias InitOnceCallback = fn Bool (InitOnce* init_once, void* parameter, void** context);

// InitOnce flags
const DWord INIT_ONCE_CHECK_ONLY               = 0x00000001;
const DWord INIT_ONCE_ASYNC                    = 0x00000002;
const DWord INIT_ONCE_INIT_FAILED              = 0x00000004;

// ============================================================
// Functions - Overlapped Result
// ============================================================

extern fn Bool getOverlappedResult(
    Handle     h_file,
    Overlapped* lp_overlapped,
    DWord*     lp_number_of_bytes_transferred,
    Bool       b_wait
) @cname("GetOverlappedResult");

extern fn Bool getOverlappedResultEx(
    Handle     h_file,
    Overlapped* lp_overlapped,
    DWord*     lp_number_of_bytes_transferred,
    DWord      dw_milliseconds,
    Bool       b_alertable
) @cname("GetOverlappedResultEx");

// ============================================================
// Functions - Process / Thread Open
// ============================================================

extern fn Handle openProcess(DWord dw_desired_access, Bool b_inherit_handle, DWord dw_process_id) @cname("OpenProcess");
extern fn Handle openThread(DWord dw_desired_access, Bool b_inherit_handle, DWord dw_thread_id) @cname("OpenThread");
extern fn Bool isWow64Process(Handle h_process, Bool* wow64_process) @cname("IsWow64Process");
extern fn DWord getThreadId(Handle thread) @cname("GetThreadId");
extern fn DWord getProcessId(Handle process) @cname("GetProcessId");
extern fn Bool getProcessAffinityMask(Handle h_process, uptr* lp_process_affinity_mask, uptr* lp_system_affinity_mask) @cname("GetProcessAffinityMask");
extern fn Bool setProcessAffinityMask(Handle h_process, uptr dw_process_affinity_mask) @cname("SetProcessAffinityMask");
extern fn uptr setThreadAffinityMask(Handle h_thread, uptr dw_thread_affinity_mask) @cname("SetThreadAffinityMask");
extern fn Bool getProcessTimes(Handle h_process, FileTime* lp_creation_time, FileTime* lp_exit_time, FileTime* lp_kernel_time, FileTime* lp_user_time) @cname("GetProcessTimes");
extern fn Bool getThreadTimes(Handle h_thread, FileTime* lp_creation_time, FileTime* lp_exit_time, FileTime* lp_kernel_time, FileTime* lp_user_time) @cname("GetThreadTimes");
extern fn Bool getProcessWorkingSetSize(Handle h_process, uptr* lp_minimum_working_set_size, uptr* lp_maximum_working_set_size) @cname("GetProcessWorkingSetSize");
extern fn Bool setProcessWorkingSetSize(Handle h_process, uptr dw_minimum_working_set_size, uptr dw_maximum_working_set_size) @cname("SetProcessWorkingSetSize");

// Thread description (Windows 10+)
extern fn int setThreadDescription(Handle h_thread, WChar* lp_thread_description) @cname("SetThreadDescription");
extern fn int getThreadDescription(Handle h_thread, WChar** pp_sz_thread_description) @cname("GetThreadDescription");

// ============================================================
// Functions - IOCP Completion Notification
// ============================================================

extern fn Bool setFileCompletionNotificationModes(Handle file_handle, char flags) @cname("SetFileCompletionNotificationModes");
extern fn Bool bindIoCompletionCallback(Handle file_handle, FileIOCompletionRoutine function, DWord flags) @cname("BindIoCompletionCallback");

// ============================================================
// Functions - Device I/O
// ============================================================

extern fn Bool deviceIoControl(
    Handle  h_device,
    DWord   dw_io_control_code,
    void*   lp_in_buffer,
    DWord   n_in_buffer_size,
    void*   lp_out_buffer,
    DWord   n_out_buffer_size,
    DWord*  lp_bytes_returned,
    Overlapped* lp_overlapped
) @cname("DeviceIoControl");

// ============================================================
// Functions - File Information
// ============================================================

extern fn Bool getFileInformationByHandle(Handle h_file, ByHandleFileInformation* lp_file_information) @cname("GetFileInformationByHandle");
extern fn Bool setFileInformationByHandle(Handle h_file, int file_information_class, void* lp_file_information, DWord dw_buffer_size) @cname("SetFileInformationByHandle");
extern fn Bool getFileInformationByHandleEx(Handle h_file, int file_information_class, void* lp_file_information, DWord dw_buffer_size) @cname("GetFileInformationByHandleEx");


// CreateSymbolicLink
const DWord SYMBOLIC_LINK_FLAG_FILE             = 0x0;
const DWord SYMBOLIC_LINK_FLAG_DIRECTORY        = 0x1;
const DWord SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = 0x2;

extern fn Bool createSymbolicLinkA(char* lp_symlink_file_name, char* lp_target_file_name, DWord dw_flags) @cname("CreateSymbolicLinkA");
extern fn Bool createSymbolicLinkW(WChar* lp_symlink_file_name, WChar* lp_target_file_name, DWord dw_flags) @cname("CreateSymbolicLinkW");

// ============================================================
// Functions - Heap
// ============================================================

extern fn void* getProcessHeap() @cname("GetProcessHeap");
extern fn DWord getProcessHeaps(DWord number_of_heaps, void** process_heaps) @cname("GetProcessHeaps");
extern fn void* heapCreate(DWord fl_options, uptr dw_initial_size, uptr dw_maximum_size) @cname("HeapCreate");
extern fn Bool heapDestroy(void* h_heap) @cname("HeapDestroy");
extern fn void* heapAlloc(void* h_heap, DWord dw_flags, uptr dw_bytes) @cname("HeapAlloc");
extern fn void* heapReAlloc(void* h_heap, DWord dw_flags, void* lp_mem, uptr dw_bytes) @cname("HeapReAlloc");
extern fn Bool heapFree(void* h_heap, DWord dw_flags, void* lp_mem) @cname("HeapFree");
extern fn uptr heapSize(void* h_heap, DWord dw_flags, void* lp_mem) @cname("HeapSize");
extern fn Bool heapValidate(void* h_heap, DWord dw_flags, void* lp_mem) @cname("HeapValidate");
extern fn Bool heapCompact(void* h_heap, DWord dw_flags) @cname("HeapCompact");
extern fn Bool heapLock(void* h_heap) @cname("HeapLock");
extern fn Bool heapUnlock(void* h_heap) @cname("HeapUnlock");
extern fn Bool heapWalk(void* h_heap, ProcessHeapEntry* lp_entry) @cname("HeapWalk");

// ============================================================
// Functions - APC / Signaling
// ============================================================

alias APCProc = fn void (uptr dw_param);

extern fn DWord queueUserAPC(APCProc pfn_apc, Handle h_thread, uptr dw_data) @cname("QueueUserAPC");
extern fn DWord signalObjectAndWait(Handle h_object_to_signal, Handle h_object_to_wait_on, DWord dw_milliseconds, Bool b_alertable) @cname("SignalObjectAndWait");

// ============================================================
// Functions - Waitable Timer (Extended)
// ============================================================

extern fn Handle createWaitableTimerExA(SecurityAttributes* lp_timer_attributes, char* lp_timer_name, DWord dw_flags, DWord dw_desired_access) @cname("CreateWaitableTimerExA");
extern fn Handle createWaitableTimerExW(SecurityAttributes* lp_timer_attributes, WChar* lp_timer_name, DWord dw_flags, DWord dw_desired_access) @cname("CreateWaitableTimerExW");

const DWord CREATE_WAITABLE_TIMER_MANUAL_RESET  = 0x00000001;
const DWord CREATE_WAITABLE_TIMER_HIGH_RESOLUTION = 0x00000002;

// ============================================================
// Functions - InitOnce (one-time initialization)
// ============================================================

extern fn void initOnceInitialize(InitOnce* init_once) @cname("InitOnceInitialize");
extern fn Bool initOnceExecuteOnce(InitOnce* init_once, InitOnceCallback init_fn, void* parameter, void** context) @cname("InitOnceExecuteOnce");
extern fn Bool initOnceBeginInitialize(InitOnce* lp_init_once, DWord dw_flags, Bool* f_pending, void** lp_context) @cname("InitOnceBeginInitialize");
extern fn Bool initOnceComplete(InitOnce* lp_init_once, DWord dw_flags, void* lp_context) @cname("InitOnceComplete");

// ============================================================
// Functions - Job Object
// ============================================================

extern fn Handle createJobObjectA(SecurityAttributes* lp_job_attributes, char* lp_name) @cname("CreateJobObjectA");
extern fn Handle createJobObjectW(SecurityAttributes* lp_job_attributes, WChar* lp_name) @cname("CreateJobObjectW");
extern fn Handle openJobObjectA(DWord dw_desired_access, Bool b_inherit_handle, char* lp_name) @cname("OpenJobObjectA");
extern fn Handle openJobObjectW(DWord dw_desired_access, Bool b_inherit_handle, WChar* lp_name) @cname("OpenJobObjectW");
extern fn Bool assignProcessToJobObject(Handle h_job, Handle h_process) @cname("AssignProcessToJobObject");
extern fn Bool terminateJobObject(Handle h_job, uint u_exit_code) @cname("TerminateJobObject");
extern fn Bool isProcessInJob(Handle process_handle, Handle job_handle, Bool* result) @cname("IsProcessInJob");
extern fn Bool setInformationJobObject(Handle h_job, int job_object_information_class, void* lp_job_object_information, DWord cb_job_object_information_length) @cname("SetInformationJobObject");
extern fn Bool queryInformationJobObject(Handle h_job, int job_object_information_class, void* lp_job_object_information, DWord cb_job_object_information_length, DWord* lp_return_length) @cname("QueryInformationJobObject");

// ============================================================
// Functions - Console I/O (보충)
// ============================================================

extern fn Bool writeConsoleA(Handle h_console_output, void* lp_buffer, DWord n_number_of_chars_to_write, DWord* lp_number_of_chars_written, void* lp_reserved) @cname("WriteConsoleA");
extern fn Bool writeConsoleW(Handle h_console_output, void* lp_buffer, DWord n_number_of_chars_to_write, DWord* lp_number_of_chars_written, void* lp_reserved) @cname("WriteConsoleW");
extern fn Bool readConsoleA(Handle h_console_input, void* lp_buffer, DWord n_number_of_chars_to_read, DWord* lp_number_of_chars_read, void* p_input_control) @cname("ReadConsoleA");
extern fn Bool readConsoleW(Handle h_console_input, void* lp_buffer, DWord n_number_of_chars_to_read, DWord* lp_number_of_chars_read, void* p_input_control) @cname("ReadConsoleW");

// ============================================================
// Functions - High-Resolution Time
// ============================================================

extern fn void getSystemTimePreciseAsFileTime(FileTime* lp_system_time_as_file_time) @cname("GetSystemTimePreciseAsFileTime");

// ============================================================
// Functions - Wow64
// ============================================================

extern fn Bool wow64DisableWow64FsRedirection(void** old_value) @cname("Wow64DisableWow64FsRedirection");
extern fn Bool wow64RevertWow64FsRedirection(void* ol_value) @cname("Wow64RevertWow64FsRedirection");
extern fn Bool isWow64Process2(Handle h_process, ushort* p_process_machine, ushort* p_native_machine) @cname("IsWow64Process2");

// ============================================================
// Functions - Debug
// ============================================================

struct ExceptionRecord {
    DWord exceptionCode;
    DWord exceptionFlags;
    void* exceptionRecord;   // ExceptionRecord*
    void* exceptionAddress;
    DWord numberParameters;
    uptr[15] exceptionInformation;
}

struct ExceptionDebugInfo {
    ExceptionRecord exceptionRecord;
    DWord firstChance;
}

struct CreateThreadDebugInfo {
    Handle hThread;
    void*  lpThreadLocalBase;
    void*  lpStartAddress;
}

struct CreateProcessDebugInfo {
    Handle  hFile;
    Handle  hProcess;
    Handle  hThread;
    void*   lpBaseOfImage;
    DWord   dwDebugInfoFileOffset;
    DWord   nDebugInfoSize;
    void*   lpThreadLocalBase;
    void*   lpStartAddress;
    void*   lpImageName;
    Word    fUnicode;
}

struct ExitThreadDebugInfo {
    DWord dwExitCode;
}

struct ExitProcessDebugInfo {
    DWord dwExitCode;
}

struct LoadDllDebugInfo {
    Handle  hFile;
    void*   lpBaseOfDll;
    DWord   dwDebugInfoFileOffset;
    DWord   nDebugInfoSize;
    void*   lpImageName;
    Word    fUnicode;
}

struct UnloadDllDebugInfo {
    void* lpBaseOfDll;
}

struct OutputDebugStringInfo {
    char* lpDebugStringData;
    Word  fUnicode;
    Word  nDebugStringLength;
}

struct RipInfo {
    DWord dwError;
    DWord dwType;
}

struct DebugEvent {
    DWord dwDebugEventCode;
    DWord dwProcessId;
    DWord dwThreadId;
    union {
        ExceptionDebugInfo    exception;
        CreateThreadDebugInfo createThread;
        CreateProcessDebugInfo createProcessInfo;
        ExitThreadDebugInfo   exitThread;
        ExitProcessDebugInfo  exitProcess;
        LoadDllDebugInfo      loadDll;
        UnloadDllDebugInfo    unloadDll;
        OutputDebugStringInfo outputDebugString;
        RipInfo               ripInfo;
    }
}

// Debug event codes
const DWord EXCEPTION_DEBUG_EVENT       = 1;
const DWord CREATE_THREAD_DEBUG_EVENT   = 2;
const DWord CREATE_PROCESS_DEBUG_EVENT  = 3;
const DWord EXIT_THREAD_DEBUG_EVENT     = 4;
const DWord EXIT_PROCESS_DEBUG_EVENT    = 5;
const DWord LOAD_DLL_DEBUG_EVENT        = 6;
const DWord UNLOAD_DLL_DEBUG_EVENT      = 7;
const DWord OUTPUT_DEBUG_STRING_EVENT   = 8;
const DWord RIP_EVENT                   = 9;

const DWord DBG_CONTINUE                = 0x00010002;
const DWord DBG_EXCEPTION_NOT_HANDLED   = 0x80010001;
const DWord DBG_REPLY_LATER             = 0x40010001;

extern fn Bool waitForDebugEvent(DebugEvent* lp_debug_event, DWord dw_milliseconds) @cname("WaitForDebugEvent");
extern fn Bool continueDebugEvent(DWord dw_process_id, DWord dw_thread_id, DWord dw_continue_status) @cname("ContinueDebugEvent");
extern fn Bool debugActiveProcess(DWord dw_process_id) @cname("DebugActiveProcess");
extern fn Bool debugActiveProcessStop(DWord dw_process_id) @cname("DebugActiveProcessStop");
extern fn Bool debugSetProcessKillOnExit(Bool kill_on_exit) @cname("DebugSetProcessKillOnExit");
extern fn Bool debugBreakProcess(Handle process) @cname("DebugBreakProcess");
extern fn Bool checkRemoteDebuggerPresent(Handle h_process, Bool* b_debugger_present) @cname("CheckRemoteDebuggerPresent");

// ============================================================
// Functions - Process Memory
// ============================================================

extern fn Bool readProcessMemory(Handle h_process, void* lp_base_address, void* lp_buffer, uptr n_size, uptr* lp_number_of_bytes_read) @cname("ReadProcessMemory");
extern fn Bool writeProcessMemory(Handle h_process, void* lp_base_address, void* lp_buffer, uptr n_size, uptr* lp_number_of_bytes_written) @cname("WriteProcessMemory");
