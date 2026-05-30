// errhandlingapi.h.c3

module c::errhandlingapi @if(env::WIN32);

alias Handle = void*;
alias Bool = int;
alias UIntPtr = uint*;

const uint SEM_FAILCRITICALERRORS = 0x0001;
const uint SEM_NOGPFAULTERRORBOX = 0x0002;
const uint SEM_NOALIGNMENTFAULTEXCEPT = 0x0004;
const uint SEM_NOOPENFILEERRORBOX = 0x8000;

const uint ERROR_CALL_NOT_IMPLEMENTED = 120;

const uint EXCEPTION_EXECUTE_HANDLER = 1;
const uint EXCEPTION_CONTINUE_SEARCH = 0;
const uint EXCEPTION_CONTINUE_EXECUTION = uint::max;

const uint EXCEPTION_ACCESS_VIOLATION = 0xC0000005;
const uint EXCEPTION_ARRAY_BOUNDS_EXCEEDED = 0xC000008C;
const uint EXCEPTION_BREAKPOINT = 0x80000003;
const uint EXCEPTION_DATATYPE_MISALIGNMENT = 0x80000002;
const uint EXCEPTION_FLT_DENORMAL_OPERAND = 0xC000008D;
const uint EXCEPTION_FLT_DIVIDE_BY_ZERO = 0xC000008E;
const uint EXCEPTION_FLT_INEXACT_RESULT = 0xC000008F;
const uint EXCEPTION_FLT_INVALID_OPERATION = 0xC0000090;
const uint EXCEPTION_FLT_OVERFLOW = 0xC0000091;
const uint EXCEPTION_FLT_STACK_CHECK = 0xC0000092;
const uint EXCEPTION_FLT_UNDERFLOW = 0xC0000093;
const uint EXCEPTION_ILLEGAL_INSTRUCTION = 0xC000001D;
const uint EXCEPTION_IN_PAGE_ERROR = 0xC0000006;
const uint EXCEPTION_INT_DIVIDE_BY_ZERO = 0xC0000094;
const uint EXCEPTION_INT_OVERFLOW = 0xC0000095;
const uint EXCEPTION_INVALID_DISPOSITION = 0xC0000026;
const uint EXCEPTION_NONCONTINUABLE_EXCEPTION = 0xC0000025;
const uint EXCEPTION_PRIV_INSTRUCTION = 0xC0000096;
const uint EXCEPTION_SINGLE_STEP = 0x80000004;
const uint EXCEPTION_STACK_OVERFLOW = 0xC00000FD;

const uint FAST_FAIL_EXCEPTION_CORRUPTED_LIST_ENTRY = 3;

struct ExceptionRecord {
    uint exception_code;
    uint exception_flags;
    ExceptionRecord* exception_record;
    void* exception_address;
    uint number_parameters;
    UIntPtr[15] exception_information;
}

struct ExceptionPointers {
    ExceptionRecord* exception_record;
    void* context_record;
}

alias VectoredExceptionHandler = fn int(ExceptionPointers* exception_info);
alias TopLevelExceptionFilter = fn int(ExceptionPointers* exception_info);

extern fn uint getLastError() @cname("GetLastError");

extern fn void setLastError(uint dw_err_code) @cname("SetLastError");

extern fn uint getErrorMode() @cname("GetErrorMode");

extern fn uint setErrorMode(uint u_mode) @cname("SetErrorMode");

extern fn void* addVectoredExceptionHandler(
    uint first,
    VectoredExceptionHandler handler
) @cname("AddVectoredExceptionHandler");

extern fn uint removeVectoredExceptionHandler(
    void* handle
) @cname("RemoveVectoredExceptionHandler");

extern fn void* addVectoredContinueHandler(
    uint first,
    VectoredExceptionHandler handler
) @cname("AddVectoredContinueHandler");

extern fn uint removeVectoredContinueHandler(
    void* handle
) @cname("RemoveVectoredContinueHandler");

extern fn void raiseException(
    uint dw_exception_code,
    uint dw_exception_flags,
    uint n_number_of_arguments,
    UIntPtr* lp_arguments
) @cname("RaiseException");

extern fn void raiseFailFastException(
    ExceptionRecord* p_exception_record,
    void* p_context_record,
    uint dw_flags
) @cname("RaiseFailFastException");

extern fn void fatalAppExitA(
    uint u_action,
    char* lp_message_text
) @cname("FatalAppExitA");

extern fn void fatalAppExitW(
    uint u_action,
    ushort* lp_message_text
) @cname("FatalAppExitW");

extern fn TopLevelExceptionFilter setUnhandledExceptionFilter(
    TopLevelExceptionFilter lp_top_level_exception_filter
) @cname("SetUnhandledExceptionFilter");

extern fn int unhandledExceptionFilter(
    ExceptionPointers* exception_info
) @cname("UnhandledExceptionFilter");

extern fn Bool getThreadErrorMode() @cname("GetThreadErrorMode");

extern fn Bool setThreadErrorMode(
    uint dw_new_mode,
    uint* lpdw_old_mode
) @cname("SetThreadErrorMode");

extern fn Bool terminateProcess(
    Handle h_process,
    uint u_exit_code
) @cname("TerminateProcess");

extern fn void restoreLastError(uint dw_err_code) @cname("RestoreLastError");
