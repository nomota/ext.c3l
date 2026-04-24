// winnt.h.c3

// Windows NT Core Definitions
// C3 mapping for winnt.h

// Nomota <hiongun@gmail.com>; MIT License

module c::winnt @if(env::WIN32);

// 
// Basic type aliases
// 

alias Void     = void;
alias Char     = char;       // CHAR  (8-bit)
alias WChar    = ushort;     // WCHAR (UTF-16LE, 16-bit)
alias Short    = short;      // SHORT (16-bit)
alias Long     = int;        // LONG  (always 32-bit on Windows)
alias LongLong = long;       // LONGLONG (64-bit)
alias UChar    = char;       // UCHAR
alias UShort   = ushort;     // USHORT
alias ULong    = uint;       // ULONG (always 32-bit on Windows)
alias ULongLong = ulong;     // ULONGLONG (64-bit)
alias Boolean  = char;       // BOOLEAN (BYTE-sized)
alias Byte     = char;       // BYTE
alias Word     = ushort;     // WORD
alias DWord    = uint;       // DWORD
alias DWord32  = uint;       // DWORD32
alias DWord64  = ulong;      // DWORD64
alias QWord    = ulong;      // QWORD
alias Float    = float;
alias Double   = double;

// Pointer-sized integers
alias LongPtr  = iptr;       // LONG_PTR
alias ULongPtr = uptr;       // ULONG_PTR
alias DWordPtr = uptr;       // DWORD_PTR
alias SizeT    = uptr;       // SIZE_T
alias SSizeT   = iptr;       // SSIZE_T
alias HalfPtr  = int;        // HALF_PTR
alias UHalfPtr = uint;       // UHALF_PTR

// Explicit-width integer types
alias Int8   = ichar;
alias Int16  = short;
alias Int32  = int;
alias Int64  = long;
alias UInt8  = char;
alias UInt16 = ushort;
alias UInt32 = uint;
alias UInt64 = ulong;

// Pointer types
alias Handle  = void*;
alias PVoid   = void*;
alias LPVoid  = void*;
alias LPCVoid = void*;

// String pointer types
alias LPStr   = char*;
alias LPCStr  = char*;
alias LPWStr  = ushort*;
alias LPCWStr = ushort*;

// Status/error types
alias NtStatus = long;
alias HResult  = long;

// 
// Fundamental constants
// 

const int    TRUE  = 1;
const int    FALSE = 0;
const ulong  NULL  = 0;

const ulong INVALID_HANDLE_VALUE = 0xFFFFFFFFFFFFFFFF;
const DWord INFINITE             = 0xFFFFFFFF;
const DWord MAXIMUM_WAIT_OBJECTS = 64;

const DWord FLS_OUT_OF_INDEXES = 0xFFFFFFFF;
const DWord TLS_OUT_OF_INDEXES = 0xFFFFFFFF;

// 
// Wait return values
// 

const DWord WAIT_FAILED      = 0xFFFFFFFF;
const DWord WAIT_OBJECT_0    = 0x00000000;
const DWord WAIT_ABANDONED   = 0x00000080;
const DWord WAIT_ABANDONED_0 = 0x00000080;
const DWord WAIT_IO_COMPLETION = 0x000000C0;
const DWord WAIT_TIMEOUT     = 258;

// 
// Standard access rights
// 

const DWord DELETE                   = 0x00010000;
const DWord READ_CONTROL             = 0x00020000;
const DWord WRITE_DAC                = 0x00040000;
const DWord WRITE_OWNER              = 0x00080000;
const DWord SYNCHRONIZE              = 0x00100000;
const DWord STANDARD_RIGHTS_REQUIRED = 0x000F0000;
const DWord STANDARD_RIGHTS_READ     = READ_CONTROL;
const DWord STANDARD_RIGHTS_WRITE    = READ_CONTROL;
const DWord STANDARD_RIGHTS_EXECUTE  = READ_CONTROL;
const DWord STANDARD_RIGHTS_ALL      = 0x001F0000;
const DWord SPECIFIC_RIGHTS_ALL      = 0x0000FFFF;
const DWord ACCESS_SYSTEM_SECURITY   = 0x01000000;
const DWord MAXIMUM_ALLOWED          = 0x02000000;
const DWord GENERIC_READ             = 0x80000000;
const DWord GENERIC_WRITE            = 0x40000000;
const DWord GENERIC_EXECUTE          = 0x20000000;
const DWord GENERIC_ALL              = 0x10000000;

// 
// NTSTATUS codes
// 

const NtStatus STATUS_SUCCESS                  = 0x00000000;
const NtStatus STATUS_WAIT_0                   = 0x00000000;
const NtStatus STATUS_ABANDONED_WAIT_0         = 0x00000080;
const NtStatus STATUS_USER_APC                 = 0x000000C0;
const NtStatus STATUS_TIMEOUT                  = 0x00000102;
const NtStatus STATUS_PENDING                  = 0x00000103;
const NtStatus STATUS_SEGMENT_NOTIFICATION     = 0x40000005;
const NtStatus STATUS_GUARD_PAGE_VIOLATION     = 0x80000001;
const NtStatus STATUS_DATATYPE_MISALIGNMENT    = 0x80000002;
const NtStatus STATUS_BREAKPOINT               = 0x80000003;
const NtStatus STATUS_SINGLE_STEP             = 0x80000004;
const NtStatus STATUS_LONGJUMP                 = 0x80000026;
const NtStatus STATUS_ACCESS_VIOLATION         = 0xC0000005;
const NtStatus STATUS_IN_PAGE_ERROR            = 0xC0000006;
const NtStatus STATUS_INVALID_HANDLE           = 0xC0000008;
const NtStatus STATUS_INVALID_PARAMETER        = 0xC000000D;
const NtStatus STATUS_NO_MEMORY                = 0xC0000017;
const NtStatus STATUS_ILLEGAL_INSTRUCTION      = 0xC000001D;
const NtStatus STATUS_NONCONTINUABLE_EXCEPTION = 0xC0000025;
const NtStatus STATUS_INVALID_DISPOSITION      = 0xC0000026;
const NtStatus STATUS_ARRAY_BOUNDS_EXCEEDED    = 0xC000008C;
const NtStatus STATUS_FLOAT_DENORMAL_OPERAND   = 0xC000008D;
const NtStatus STATUS_FLOAT_DIVIDE_BY_ZERO     = 0xC000008E;
const NtStatus STATUS_FLOAT_INEXACT_RESULT     = 0xC000008F;
const NtStatus STATUS_FLOAT_INVALID_OPERATION  = 0xC0000090;
const NtStatus STATUS_FLOAT_OVERFLOW           = 0xC0000091;
const NtStatus STATUS_FLOAT_STACK_CHECK        = 0xC0000092;
const NtStatus STATUS_FLOAT_UNDERFLOW          = 0xC0000093;
const NtStatus STATUS_INTEGER_DIVIDE_BY_ZERO   = 0xC0000094;
const NtStatus STATUS_INTEGER_OVERFLOW         = 0xC0000095;
const NtStatus STATUS_PRIVILEGED_INSTRUCTION   = 0xC0000096;
const NtStatus STATUS_STACK_OVERFLOW           = 0xC00000FD;
const NtStatus STATUS_CONTROL_C_EXIT           = 0xC000013A;
const NtStatus STATUS_POSSIBLE_DEADLOCK        = 0xC0000194;

// 
// Exception codes
// 

const DWord EXCEPTION_ACCESS_VIOLATION         = 0xC0000005;
const DWord EXCEPTION_DATATYPE_MISALIGNMENT    = 0x80000002;
const DWord EXCEPTION_BREAKPOINT               = 0x80000003;
const DWord EXCEPTION_SINGLE_STEP             = 0x80000004;
const DWord EXCEPTION_ARRAY_BOUNDS_EXCEEDED    = 0xC000008C;
const DWord EXCEPTION_FLT_DENORMAL_OPERAND     = 0xC000008D;
const DWord EXCEPTION_FLT_DIVIDE_BY_ZERO       = 0xC000008E;
const DWord EXCEPTION_FLT_INEXACT_RESULT       = 0xC000008F;
const DWord EXCEPTION_FLT_INVALID_OPERATION    = 0xC0000090;
const DWord EXCEPTION_FLT_OVERFLOW             = 0xC0000091;
const DWord EXCEPTION_FLT_STACK_CHECK          = 0xC0000092;
const DWord EXCEPTION_FLT_UNDERFLOW            = 0xC0000093;
const DWord EXCEPTION_INT_DIVIDE_BY_ZERO       = 0xC0000094;
const DWord EXCEPTION_INT_OVERFLOW             = 0xC0000095;
const DWord EXCEPTION_PRIV_INSTRUCTION         = 0xC0000096;
const DWord EXCEPTION_IN_PAGE_ERROR            = 0xC0000006;
const DWord EXCEPTION_ILLEGAL_INSTRUCTION      = 0xC000001D;
const DWord EXCEPTION_NONCONTINUABLE_EXCEPTION = 0xC0000025;
const DWord EXCEPTION_STACK_OVERFLOW           = 0xC00000FD;
const DWord EXCEPTION_INVALID_DISPOSITION      = 0xC0000026;
const DWord EXCEPTION_GUARD_PAGE               = 0x80000001;
const DWord EXCEPTION_INVALID_HANDLE           = 0xC0000008;
const DWord EXCEPTION_POSSIBLE_DEADLOCK        = 0xC0000194;
const DWord CONTROL_C_EXIT                     = 0xC000013A;
const DWord EXCEPTION_MAXIMUM_PARAMETERS       = 15;

// Exception flags
const DWord EXCEPTION_NONCONTINUABLE  = 0x0001;
const DWord EXCEPTION_UNWINDING       = 0x0002;
const DWord EXCEPTION_EXIT_UNWIND     = 0x0004;
const DWord EXCEPTION_STACK_INVALID   = 0x0008;
const DWord EXCEPTION_NESTED_CALL     = 0x0010;
const DWord EXCEPTION_TARGET_UNWIND   = 0x0020;
const DWord EXCEPTION_COLLIDED_UNWIND = 0x0040;
const DWord EXCEPTION_UNWIND          = 0x0066;

// 
// Context flags (x64 / AMD64)
// 

const DWord CONTEXT_AMD64           = 0x00100000;
const DWord CONTEXT_CONTROL         = CONTEXT_AMD64 | 0x00000001;
const DWord CONTEXT_INTEGER         = CONTEXT_AMD64 | 0x00000002;
const DWord CONTEXT_SEGMENTS        = CONTEXT_AMD64 | 0x00000004;
const DWord CONTEXT_FLOATING_POINT  = CONTEXT_AMD64 | 0x00000008;
const DWord CONTEXT_DEBUG_REGISTERS = CONTEXT_AMD64 | 0x00000010;
const DWord CONTEXT_FULL            = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_FLOATING_POINT;
const DWord CONTEXT_ALL             = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_SEGMENTS
                                    | CONTEXT_FLOATING_POINT | CONTEXT_DEBUG_REGISTERS;
const DWord CONTEXT_XSTATE          = CONTEXT_AMD64 | 0x00000040;

// 
// Processor architecture constants
// 

const ushort PROCESSOR_ARCHITECTURE_INTEL          = 0;
const ushort PROCESSOR_ARCHITECTURE_MIPS           = 1;
const ushort PROCESSOR_ARCHITECTURE_ALPHA          = 2;
const ushort PROCESSOR_ARCHITECTURE_PPC            = 3;
const ushort PROCESSOR_ARCHITECTURE_SHX            = 4;
const ushort PROCESSOR_ARCHITECTURE_ARM            = 5;
const ushort PROCESSOR_ARCHITECTURE_IA64           = 6;
const ushort PROCESSOR_ARCHITECTURE_ALPHA64        = 7;
const ushort PROCESSOR_ARCHITECTURE_MSIL           = 8;
const ushort PROCESSOR_ARCHITECTURE_AMD64          = 9;
const ushort PROCESSOR_ARCHITECTURE_IA32_ON_WIN64  = 10;
const ushort PROCESSOR_ARCHITECTURE_NEUTRAL        = 11;
const ushort PROCESSOR_ARCHITECTURE_ARM64          = 12;
const ushort PROCESSOR_ARCHITECTURE_ARM32_ON_WIN64 = 13;
const ushort PROCESSOR_ARCHITECTURE_IA32_ON_ARM64  = 14;
const ushort PROCESSOR_ARCHITECTURE_UNKNOWN        = 0xFFFF;

// 
// Registry value types
// 

const DWord REG_NONE                       = 0;
const DWord REG_SZ                         = 1;
const DWord REG_EXPAND_SZ                  = 2;
const DWord REG_BINARY                     = 3;
const DWord REG_DWORD                      = 4;
const DWord REG_DWORD_LITTLE_ENDIAN        = 4;
const DWord REG_DWORD_BIG_ENDIAN           = 5;
const DWord REG_LINK                       = 6;
const DWord REG_MULTI_SZ                   = 7;
const DWord REG_RESOURCE_LIST              = 8;
const DWord REG_FULL_RESOURCE_DESCRIPTOR   = 9;
const DWord REG_RESOURCE_REQUIREMENTS_LIST = 10;
const DWord REG_QWORD                      = 11;
const DWord REG_QWORD_LITTLE_ENDIAN        = 11;

// 
// Language / Locale IDs
// 

const Word LANG_NEUTRAL   = 0x00;
const Word LANG_INVARIANT = 0x7F;
const Word LANG_ENGLISH   = 0x09;
const Word LANG_KOREAN    = 0x12;
const Word LANG_JAPANESE  = 0x11;
const Word LANG_CHINESE   = 0x04;
const Word LANG_FRENCH    = 0x0C;
const Word LANG_GERMAN    = 0x07;
const Word LANG_SPANISH   = 0x0A;
const Word LANG_ARABIC    = 0x01;
const Word LANG_RUSSIAN   = 0x19;

const Word SUBLANG_NEUTRAL            = 0x00;
const Word SUBLANG_DEFAULT            = 0x01;
const Word SUBLANG_SYS_DEFAULT        = 0x02;
const Word SUBLANG_CUSTOM_DEFAULT     = 0x03;
const Word SUBLANG_CUSTOM_UNSPECIFIED = 0x04;
const Word SUBLANG_UI_CUSTOM_DEFAULT  = 0x05;
const Word SUBLANG_ENGLISH_US         = 0x01;
const Word SUBLANG_ENGLISH_UK         = 0x02;
const Word SUBLANG_KOREAN             = 0x01;
const Word SUBLANG_JAPANESE           = 0x01;

// 
// Security: SID constants
// 

const char SID_REVISION                  = 1;
const DWord SID_MAX_SUB_AUTHORITIES      = 15;
const DWord SID_RECOMMENDED_SUB_AUTHORITIES = 1;

// SID identifier authority values (index into SidIdentifierAuthority.value[5])
const char SECURITY_NULL_SID_AUTHORITY             = 0;
const char SECURITY_WORLD_SID_AUTHORITY            = 1;
const char SECURITY_LOCAL_SID_AUTHORITY            = 2;
const char SECURITY_CREATOR_SID_AUTHORITY          = 3;
const char SECURITY_NON_UNIQUE_AUTHORITY           = 4;
const char SECURITY_NT_AUTHORITY                   = 5;
const char SECURITY_RESOURCE_MANAGER_AUTHORITY     = 9;

// 
// Security: ACE type constants
// 

const char ACCESS_ALLOWED_ACE_TYPE                  = 0x00;
const char ACCESS_DENIED_ACE_TYPE                   = 0x01;
const char SYSTEM_AUDIT_ACE_TYPE                    = 0x02;
const char SYSTEM_ALARM_ACE_TYPE                    = 0x03;
const char ACCESS_ALLOWED_COMPOUND_ACE_TYPE         = 0x04;
const char ACCESS_ALLOWED_OBJECT_ACE_TYPE           = 0x05;
const char ACCESS_DENIED_OBJECT_ACE_TYPE            = 0x06;
const char SYSTEM_AUDIT_OBJECT_ACE_TYPE             = 0x07;
const char SYSTEM_ALARM_OBJECT_ACE_TYPE             = 0x08;
const char ACCESS_ALLOWED_CALLBACK_ACE_TYPE         = 0x09;
const char ACCESS_DENIED_CALLBACK_ACE_TYPE          = 0x0A;
const char ACCESS_ALLOWED_CALLBACK_OBJECT_ACE_TYPE  = 0x0B;
const char ACCESS_DENIED_CALLBACK_OBJECT_ACE_TYPE   = 0x0C;
const char SYSTEM_AUDIT_CALLBACK_ACE_TYPE           = 0x0D;
const char SYSTEM_ALARM_CALLBACK_ACE_TYPE           = 0x0E;
const char SYSTEM_AUDIT_CALLBACK_OBJECT_ACE_TYPE    = 0x0F;
const char SYSTEM_ALARM_CALLBACK_OBJECT_ACE_TYPE    = 0x10;
const char SYSTEM_MANDATORY_LABEL_ACE_TYPE          = 0x11;

// ACE inheritance flags
const char OBJECT_INHERIT_ACE         = 0x01;
const char CONTAINER_INHERIT_ACE      = 0x02;
const char NO_PROPAGATE_INHERIT_ACE   = 0x04;
const char INHERIT_ONLY_ACE           = 0x08;
const char INHERITED_ACE              = 0x10;
const char SUCCESSFUL_ACCESS_ACE_FLAG = 0x40;
const char FAILED_ACCESS_ACE_FLAG     = 0x80;

// Security descriptor control bits
const Word SE_OWNER_DEFAULTED          = 0x0001;
const Word SE_GROUP_DEFAULTED          = 0x0002;
const Word SE_DACL_PRESENT             = 0x0004;
const Word SE_DACL_DEFAULTED           = 0x0008;
const Word SE_SACL_PRESENT             = 0x0010;
const Word SE_SACL_DEFAULTED           = 0x0020;
const Word SE_DACL_AUTO_INHERIT_REQ    = 0x0100;
const Word SE_SACL_AUTO_INHERIT_REQ    = 0x0200;
const Word SE_DACL_AUTO_INHERITED      = 0x0400;
const Word SE_SACL_AUTO_INHERITED      = 0x0800;
const Word SE_DACL_PROTECTED           = 0x1000;
const Word SE_SACL_PROTECTED           = 0x2000;
const Word SE_RM_CONTROL_VALID         = 0x4000;
const Word SE_SELF_RELATIVE            = 0x8000;

// 
// Token access rights and attributes
// 

const DWord TOKEN_ASSIGN_PRIMARY    = 0x0001;
const DWord TOKEN_DUPLICATE         = 0x0002;
const DWord TOKEN_IMPERSONATE       = 0x0004;
const DWord TOKEN_QUERY             = 0x0008;
const DWord TOKEN_QUERY_SOURCE      = 0x0010;
const DWord TOKEN_ADJUST_PRIVILEGES = 0x0020;
const DWord TOKEN_ADJUST_GROUPS     = 0x0040;
const DWord TOKEN_ADJUST_DEFAULT    = 0x0080;
const DWord TOKEN_ADJUST_SESSIONID  = 0x0100;
const DWord TOKEN_ALL_ACCESS        = STANDARD_RIGHTS_REQUIRED | 0x01FF;
const DWord TOKEN_READ              = STANDARD_RIGHTS_READ | TOKEN_QUERY;
const DWord TOKEN_WRITE             = STANDARD_RIGHTS_WRITE
                                    | TOKEN_ADJUST_PRIVILEGES
                                    | TOKEN_ADJUST_GROUPS
                                    | TOKEN_ADJUST_DEFAULT;
const DWord TOKEN_EXECUTE           = STANDARD_RIGHTS_EXECUTE;

// Privilege attributes
const DWord SE_PRIVILEGE_ENABLED_BY_DEFAULT = 0x00000001;
const DWord SE_PRIVILEGE_ENABLED            = 0x00000002;
const DWord SE_PRIVILEGE_REMOVED            = 0x00000004;
const DWord SE_PRIVILEGE_USED_FOR_ACCESS    = 0x80000000;

// Group SID attributes
const DWord SE_GROUP_MANDATORY          = 0x00000001;
const DWord SE_GROUP_ENABLED_BY_DEFAULT = 0x00000002;
const DWord SE_GROUP_ENABLED            = 0x00000004;
const DWord SE_GROUP_OWNER              = 0x00000008;
const DWord SE_GROUP_USE_FOR_DENY_ONLY  = 0x00000010;
const DWord SE_GROUP_INTEGRITY          = 0x00000020;
const DWord SE_GROUP_INTEGRITY_ENABLED  = 0x00000040;
const DWord SE_GROUP_LOGON_ID           = 0xC0000000;
const DWord SE_GROUP_RESOURCE           = 0x20000000;

// 
// PE image constants
// 

const ushort IMAGE_DOS_SIGNATURE          = 0x5A4D;  // "MZ"
const uint   IMAGE_NT_SIGNATURE           = 0x00004550;  // "PE\0\0"
const ushort IMAGE_NT_OPTIONAL_HDR32_MAGIC = 0x010B;
const ushort IMAGE_NT_OPTIONAL_HDR64_MAGIC = 0x020B;
const ushort IMAGE_ROM_OPTIONAL_HDR_MAGIC  = 0x0107;

// Image file characteristics
const ushort IMAGE_FILE_RELOCS_STRIPPED         = 0x0001;
const ushort IMAGE_FILE_EXECUTABLE_IMAGE        = 0x0002;
const ushort IMAGE_FILE_LINE_NUMS_STRIPPED      = 0x0004;
const ushort IMAGE_FILE_LOCAL_SYMS_STRIPPED     = 0x0008;
const ushort IMAGE_FILE_AGGRESIVE_WS_TRIM       = 0x0010;
const ushort IMAGE_FILE_LARGE_ADDRESS_AWARE     = 0x0020;
const ushort IMAGE_FILE_BYTES_REVERSED_LO       = 0x0080;
const ushort IMAGE_FILE_32BIT_MACHINE           = 0x0100;
const ushort IMAGE_FILE_DEBUG_STRIPPED          = 0x0200;
const ushort IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP = 0x0400;
const ushort IMAGE_FILE_NET_RUN_FROM_SWAP       = 0x0800;
const ushort IMAGE_FILE_SYSTEM                  = 0x1000;
const ushort IMAGE_FILE_DLL                     = 0x2000;
const ushort IMAGE_FILE_UP_SYSTEM_ONLY          = 0x4000;
const ushort IMAGE_FILE_BYTES_REVERSED_HI       = 0x8000;

// Image machine types
const ushort IMAGE_FILE_MACHINE_UNKNOWN   = 0x0000;
const ushort IMAGE_FILE_MACHINE_I386      = 0x014C;
const ushort IMAGE_FILE_MACHINE_AMD64     = 0x8664;
const ushort IMAGE_FILE_MACHINE_ARM       = 0x01C0;
const ushort IMAGE_FILE_MACHINE_ARM64     = 0xAA64;
const ushort IMAGE_FILE_MACHINE_ARMNT     = 0x01C4;
const ushort IMAGE_FILE_MACHINE_IA64      = 0x0200;

// Image section characteristics
const DWord IMAGE_SCN_CNT_CODE               = 0x00000020;
const DWord IMAGE_SCN_CNT_INITIALIZED_DATA   = 0x00000040;
const DWord IMAGE_SCN_CNT_UNINITIALIZED_DATA = 0x00000080;
const DWord IMAGE_SCN_MEM_EXECUTE            = 0x20000000;
const DWord IMAGE_SCN_MEM_READ               = 0x40000000;
const DWord IMAGE_SCN_MEM_WRITE              = 0x80000000;
const DWord IMAGE_SCN_MEM_SHARED             = 0x10000000;
const DWord IMAGE_SCN_MEM_NOT_CACHED         = 0x04000000;
const DWord IMAGE_SCN_MEM_NOT_PAGED          = 0x08000000;
const DWord IMAGE_SCN_MEM_DISCARDABLE        = 0x02000000;

// 
// Memory protection constants (PAGE_*)
// 

const DWord PAGE_NOACCESS                    = 0x00000001;
const DWord PAGE_READONLY                    = 0x00000002;
const DWord PAGE_READWRITE                   = 0x00000004;
const DWord PAGE_WRITECOPY                   = 0x00000008;
const DWord PAGE_EXECUTE                     = 0x00000010;
const DWord PAGE_EXECUTE_READ                = 0x00000020;
const DWord PAGE_EXECUTE_READWRITE           = 0x00000040;
const DWord PAGE_EXECUTE_WRITECOPY           = 0x00000080;
const DWord PAGE_GUARD                       = 0x00000100;
const DWord PAGE_NOCACHE                     = 0x00000200;
const DWord PAGE_WRITECOMBINE                = 0x00000400;
const DWord PAGE_GRAPHICS_NOACCESS           = 0x00000800;
const DWord PAGE_GRAPHICS_READONLY           = 0x00001000;
const DWord PAGE_GRAPHICS_READWRITE          = 0x00002000;
const DWord PAGE_GRAPHICS_EXECUTE            = 0x00004000;
const DWord PAGE_GRAPHICS_EXECUTE_READ       = 0x00008000;
const DWord PAGE_GRAPHICS_EXECUTE_READWRITE  = 0x00010000;
const DWord PAGE_GRAPHICS_COHERENT           = 0x00020000;
const DWord PAGE_ENCLAVE_THREAD_CONTROL      = 0x80000000;
const DWord PAGE_REVERT_TO_FILE_MAP          = 0x80000000;
const DWord PAGE_TARGETS_NO_UPDATE           = 0x40000000;
const DWord PAGE_TARGETS_INVALID             = 0x40000000;
const DWord PAGE_ENCLAVE_UNVALIDATED         = 0x20000000;
const DWord PAGE_ENCLAVE_DECOMMIT            = 0x10000000;

// Memory allocation types (MEM_*)
const DWord MEM_COMMIT                       = 0x00001000;
const DWord MEM_RESERVE                      = 0x00002000;
const DWord MEM_DECOMMIT                     = 0x00004000;
const DWord MEM_RELEASE                      = 0x00008000;
const DWord MEM_FREE                         = 0x00010000;
const DWord MEM_PRIVATE                      = 0x00020000;
const DWord MEM_MAPPED                       = 0x00040000;
const DWord MEM_RESET                        = 0x00080000;
const DWord MEM_TOP_DOWN                     = 0x00100000;
const DWord MEM_WRITE_WATCH                  = 0x00200000;
const DWord MEM_PHYSICAL                     = 0x00400000;
const DWord MEM_RESET_UNDO                   = 0x01000000;
const DWord MEM_IMAGE                        = 0x01000000;
const DWord MEM_LARGE_PAGES                  = 0x20000000;
const DWord MEM_COALESCE_PLACEHOLDERS        = 0x00000001;
const DWord MEM_PRESERVE_PLACEHOLDER         = 0x00000002;

// 
// Structures
// 

// LARGE_INTEGER (union — represented as 64-bit value)
struct LargeInteger {
    long quadPart;
}

struct ULargeInteger {
    ulong quadPart;
}

// LUID — locally unique identifier
struct Luid {
    DWord lowPart;
    Long  highPart;
}

// LUID_AND_ATTRIBUTES
struct LuidAndAttributes {
    Luid  luid;
    DWord attributes;
}

// LIST_ENTRY — doubly-linked list node
struct ListEntry {
    ListEntry* flink;
    ListEntry* blink;
}

// SINGLE_LIST_ENTRY — singly-linked list node
struct SingleListEntry {
    SingleListEntry* next;
}

// RTL_CRITICAL_SECTION_DEBUG
struct RtlCriticalSectionDebug {
    Word  type;
    Word  creatorBackTraceIndex;
    void* criticalSection;      // RTL_CRITICAL_SECTION*
    ListEntry processLocksList;
    DWord entryCount;
    DWord contentionCount;
    DWord[2] spare;
}

// RTL_CRITICAL_SECTION
struct RtlCriticalSection {
    RtlCriticalSectionDebug* debugInfo;
    Long     lockCount;
    Long     recursionCount;
    Handle   owningThread;
    Handle   lockSemaphore;
    ULongPtr spinCount;
}

// SID_IDENTIFIER_AUTHORITY
struct SidIdentifierAuthority {
    char[6] value;
}

// SID
struct Sid {
    char   revision;
    char   subAuthorityCount;
    SidIdentifierAuthority identifierAuthority;
    DWord[1] subAuthority;
}

// ACL
struct Acl {
    char  aclRevision;
    char  sbz1;
    Word  aclSize;
    Word  aceCount;
    Word  sbz2;
}

// ACE_HEADER
struct AceHeader {
    char aceType;
    char aceFlags;
    Word aceSize;
}

// ACCESS_ALLOWED_ACE
struct AccessAllowedAce {
    AceHeader header;
    DWord     mask;
    DWord     sidStart;
}

// ACCESS_DENIED_ACE
struct AccessDeniedAce {
    AceHeader header;
    DWord     mask;
    DWord     sidStart;
}

// SYSTEM_AUDIT_ACE
struct SystemAuditAce {
    AceHeader header;
    DWord     mask;
    DWord     sidStart;
}

// SECURITY_DESCRIPTOR
struct SecurityDescriptor {
    char  revision;
    char  sbz1;
    Word  control;
    Sid*  owner;
    Sid*  group;
    Acl*  sacl;
    Acl*  dacl;
}

// SID_AND_ATTRIBUTES
struct SidAndAttributes {
    Sid*  sid;
    DWord attributes;
}

// TOKEN_USER
struct TokenUser {
    SidAndAttributes user;
}

// TOKEN_GROUPS
struct TokenGroups {
    DWord groupCount;
    SidAndAttributes[1] groups;
}

// TOKEN_PRIVILEGES
struct TokenPrivileges {
    DWord privilegeCount;
    LuidAndAttributes[1] privileges;
}

// TOKEN_OWNER
struct TokenOwner {
    Sid* owner;
}

// TOKEN_PRIMARY_GROUP
struct TokenPrimaryGroup {
    Sid* primaryGroup;
}

// TOKEN_DEFAULT_DACL
struct TokenDefaultDacl {
    Acl* defaultDacl;
}

// PRIVILEGE_SET
struct PrivilegeSet {
    DWord privilegeCount;
    DWord control;
    LuidAndAttributes[1] privilege;
}

// EXCEPTION_RECORD
struct ExceptionRecord {
    DWord       exceptionCode;
    DWord       exceptionFlags;
    ExceptionRecord* exceptionRecord;
    PVoid       exceptionAddress;
    DWord       numberParameters;
    ULongPtr[15] exceptionInformation; // EXCEPTION_MAXIMUM_PARAMETERS = 15
}

// M128a — 128-bit SSE register
struct M128a {
    ulong low;
    long  high;
}

// XMM_SAVE_AREA32 — FPU/XMM save area
struct XmmSaveArea32 {
    ushort controlWord;
    ushort statusWord;
    char   tagWord;
    char   reserved1;
    ushort errorOpcode;
    DWord  errorOffset;
    ushort errorSelector;
    ushort reserved2;
    DWord  dataOffset;
    ushort dataSelector;
    ushort reserved3;
    DWord  mxCsr;
    DWord  mxCsrMask;
    M128a[8]  floatRegisters;
    M128a[16] xmmRegisters;
    char[96]  reserved4;
}

// CONTEXT (x64 / AMD64)
struct Context {
    // Register parameter home addresses
    ulong p1Home;
    ulong p2Home;
    ulong p3Home;
    ulong p4Home;
    ulong p5Home;
    ulong p6Home;

    // Control flags
    DWord contextFlags;
    DWord mxCsr;

    // Segment registers and processor flags
    ushort segCs;
    ushort segDs;
    ushort segEs;
    ushort segFs;
    ushort segGs;
    ushort segSs;
    DWord  eFlags;

    // Debug registers
    ulong dr0;
    ulong dr1;
    ulong dr2;
    ulong dr3;
    ulong dr6;
    ulong dr7;

    // Integer registers
    ulong rax;
    ulong rcx;
    ulong rdx;
    ulong rbx;
    ulong rsp;
    ulong rbp;
    ulong rsi;
    ulong rdi;
    ulong r8;
    ulong r9;
    ulong r10;
    ulong r11;
    ulong r12;
    ulong r13;
    ulong r14;
    ulong r15;

    // Program counter
    ulong rip;

    // Floating point / SSE state
    XmmSaveArea32 fltSave;

    // Vector registers
    M128a[26] vectorRegister;
    ulong     vectorControl;

    // Special debug control registers
    ulong debugControl;
    ulong lastBranchToRip;
    ulong lastBranchFromRip;
    ulong lastExceptionToRip;
    ulong lastExceptionFromRip;
}

// EXCEPTION_POINTERS
struct ExceptionPointers {
    ExceptionRecord* exceptionRecord;
    Context*         contextRecord;
}

// MEMORY_BASIC_INFORMATION (duplicate from memoryapi for standalone use)
struct MemoryBasicInformation {
    PVoid baseAddress;
    PVoid allocationBase;
    DWord allocationProtect;
    ushort partitionId;
    uptr  regionSize;
    DWord state;
    DWord protect;
    DWord type;
}

// 
// IMAGE structures (PE format)
// 

// IMAGE_DOS_HEADER
struct ImageDosHeader {
    ushort magic;           // MZ signature
    ushort lastPageBytes;
    ushort pages;
    ushort relocations;
    ushort headerParagraphs;
    ushort minAlloc;
    ushort maxAlloc;
    ushort initialSs;
    ushort initialSp;
    ushort checksum;
    ushort initialIp;
    ushort initialCs;
    ushort relocTableOffset;
    ushort overlayNumber;
    ushort[4] reserved1;
    ushort oemId;
    ushort oemInfo;
    ushort[10] reserved2;
    Long   lfaNew;          // Offset to PE header
}

// IMAGE_FILE_HEADER
struct ImageFileHeader {
    ushort machine;
    ushort numberOfSections;
    DWord  timeDateStamp;
    DWord  pointerToSymbolTable;
    DWord  numberOfSymbols;
    ushort sizeOfOptionalHeader;
    ushort characteristics;
}

// IMAGE_DATA_DIRECTORY
struct ImageDataDirectory {
    DWord virtualAddress;
    DWord size;
}

const DWord IMAGE_NUMBEROF_DIRECTORY_ENTRIES = 16;

// IMAGE_OPTIONAL_HEADER64
struct ImageOptionalHeader64 {
    ushort magic;
    char   majorLinkerVersion;
    char   minorLinkerVersion;
    DWord  sizeOfCode;
    DWord  sizeOfInitializedData;
    DWord  sizeOfUninitializedData;
    DWord  addressOfEntryPoint;
    DWord  baseOfCode;
    ulong  imageBase;
    DWord  sectionAlignment;
    DWord  fileAlignment;
    ushort majorOperatingSystemVersion;
    ushort minorOperatingSystemVersion;
    ushort majorImageVersion;
    ushort minorImageVersion;
    ushort majorSubsystemVersion;
    ushort minorSubsystemVersion;
    DWord  win32VersionValue;
    DWord  sizeOfImage;
    DWord  sizeOfHeaders;
    DWord  checkSum;
    ushort subsystem;
    ushort dllCharacteristics;
    ulong  sizeOfStackReserve;
    ulong  sizeOfStackCommit;
    ulong  sizeOfHeapReserve;
    ulong  sizeOfHeapCommit;
    DWord  loaderFlags;
    DWord  numberOfRvaAndSizes;
    ImageDataDirectory[16] dataDirectory;
}

// IMAGE_NT_HEADERS64
struct ImageNtHeaders64 {
    DWord              signature;
    ImageFileHeader    fileHeader;
    ImageOptionalHeader64 optionalHeader;
}

// IMAGE_SECTION_HEADER
const DWord IMAGE_SIZEOF_SHORT_NAME = 8;

struct ImageSectionHeader {
    char[8] name;
    DWord   virtualSize;
    DWord   virtualAddress;
    DWord   sizeOfRawData;
    DWord   pointerToRawData;
    DWord   pointerToRelocations;
    DWord   pointerToLinenumbers;
    ushort  numberOfRelocations;
    ushort  numberOfLinenumbers;
    DWord   characteristics;
}

// IMAGE_IMPORT_DESCRIPTOR
struct ImageImportDescriptor {
    DWord originalFirstThunk; // RVA to original unbound IAT
    DWord timeDateStamp;
    DWord forwarderChain;
    DWord name;
    DWord firstThunk;         // RVA to IAT
}

// IMAGE_EXPORT_DIRECTORY
struct ImageExportDirectory {
    DWord  characteristics;
    DWord  timeDateStamp;
    ushort majorVersion;
    ushort minorVersion;
    DWord  name;
    DWord  base;
    DWord  numberOfFunctions;
    DWord  numberOfNames;
    DWord  addressOfFunctions;
    DWord  addressOfNames;
    DWord  addressOfNameOrdinals;
}

// 
// RTL memory utility functions (ntdll exports)
// 

extern fn void rtlMoveMemory(
    PVoid destination,
    PVoid source,
    uptr  length
) @cname("RtlMoveMemory");

extern fn void rtlCopyMemory(
    PVoid destination,
    PVoid source,
    uptr  length
) @cname("RtlCopyMemory");

extern fn void rtlFillMemory(
    PVoid destination,
    uptr  length,
    char  fill
) @cname("RtlFillMemory");

extern fn void rtlZeroMemory(
    PVoid destination,
    uptr  length
) @cname("RtlZeroMemory");

extern fn void rtlCopyBytes(
    PVoid destination,
    PVoid source,
    uptr  length
) @cname("RtlCopyBytes");

extern fn void rtlZeroBytes(
    PVoid destination,
    uptr  length
) @cname("RtlZeroBytes");

extern fn void rtlFillBytes(
    PVoid destination,
    uptr  length,
    char  fill
) @cname("RtlFillBytes");

// 
// RTL critical section functions (ntdll exports)
// 

extern fn Long rtlInitializeCriticalSection(
    RtlCriticalSection* criticalSection
) @cname("RtlInitializeCriticalSection");

extern fn Long rtlInitializeCriticalSectionAndSpinCount(
    RtlCriticalSection* criticalSection,
    DWord               spinCount
) @cname("RtlInitializeCriticalSectionAndSpinCount");

extern fn Long rtlDeleteCriticalSection(
    RtlCriticalSection* criticalSection
) @cname("RtlDeleteCriticalSection");

extern fn Long rtlEnterCriticalSection(
    RtlCriticalSection* criticalSection
) @cname("RtlEnterCriticalSection");

extern fn Long rtlLeaveCriticalSection(
    RtlCriticalSection* criticalSection
) @cname("RtlLeaveCriticalSection");

extern fn Boolean rtlTryEnterCriticalSection(
    RtlCriticalSection* criticalSection
) @cname("RtlTryEnterCriticalSection");
