// handleapi.h.c3

module c::handleapi @if(env::WIN32);

alias Handle = void*;
alias Bool = int;

const uint HANDLE_FLAG_INHERIT = 0x00000001;
const uint HANDLE_FLAG_PROTECT_FROM_CLOSE = 0x00000002;

const uint DUPLICATE_CLOSE_SOURCE = 0x00000001;
const uint DUPLICATE_SAME_ACCESS = 0x00000002;

const Handle INVALID_HANDLE_VALUE = (Handle)(uptr::max);

extern fn Bool closeHandle(Handle h_object) @cname("CloseHandle");

extern fn Bool duplicateHandle(
    Handle h_source_process_handle,
    Handle h_source_handle,
    Handle h_target_process_handle,
    Handle* lp_target_handle,
    uint dw_desired_access,
    Bool b_inherit_handle,
    uint dw_options
) @cname("DuplicateHandle");

extern fn Bool compareObjectHandles(
    Handle h_first_object_handle,
    Handle h_second_object_handle
) @cname("CompareObjectHandles");

extern fn Bool getHandleInformation(
    Handle h_object,
    uint* lpdw_flags
) @cname("GetHandleInformation");

extern fn Bool setHandleInformation(
    Handle h_object,
    uint dw_mask,
    uint dw_flags
) @cname("SetHandleInformation");

// eof