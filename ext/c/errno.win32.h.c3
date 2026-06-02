// errno.win32.h.c3

module c::errno @if(env::WIN32);

extern fn long getLastError() @cname("GetLastError");
extern fn void setLastError(long err) @cname("SetLastError");
extern fn int wsaGetLastError() @cname("WSAGetLastError");

fn long errno() @inline
{
    return getLastError();
}

fn void set_errno(long err) @inline
{
    setLastError(err);
}

fn fault get_fault()
{
    return errno_to_fault(getLastError());
}

fn fault wsa_fault()
{
    return errno_to_fault((long)wsaGetLastError());
}

fn fault errno_to_fault(long err)
{
    switch (err)
    {
        case ERROR_SUCCESS:
            return F_SUCCESS;

        case ERROR_INVALID_FUNCTION:
            return E_INVALID;

        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:
        case ERROR_MOD_NOT_FOUND:
        case ERROR_PROC_NOT_FOUND:
        case ERROR_NO_MORE_FILES:
        case ERROR_NO_MORE_ITEMS:
        case ERROR_NO_MORE_SEARCH_HANDLES:
            return E_NOT_FOUND;

        case ERROR_TOO_MANY_OPEN_FILES:
        case WSAEMFILE:
            return E_TOO_MANY_FILES;

        case ERROR_ACCESS_DENIED:
        case WSAEACCES:
            return E_ACCESS_DENIED;

        case ERROR_INVALID_HANDLE:
        case WSAEBADF:
            return E_BAD_FILE_DESC;

        case ERROR_ARENA_TRASHED:
        case ERROR_INVALID_BLOCK:
        case ERROR_OUT_OF_STRUCTURES:
            return E_IO;

        case ERROR_NOT_ENOUGH_MEMORY:
        case ERROR_OUTOFMEMORY:
            return E_NO_MEMORY;

        case ERROR_BAD_ENVIRONMENT:
        case ERROR_BAD_FORMAT:
        case ERROR_BAD_EXE_FORMAT:
        case ERROR_INVALID_EXE_SIGNATURE:
        case ERROR_EXE_MARKED_INVALID:
        case ERROR_EXE_MACHINE_TYPE_MISMATCH:
            return E_EXEC_FORMAT;

        case ERROR_INVALID_ACCESS:
        case ERROR_INVALID_DATA:
        case WSAEINVAL:
            return E_INVALID;

        case ERROR_INVALID_DRIVE:
        case ERROR_BAD_UNIT:
        case ERROR_DEV_NOT_EXIST:
            return E_NO_DEVICE;

        case ERROR_CURRENT_DIRECTORY:
        case ERROR_DIR_NOT_ROOT:
            return E_NOT_DIRECTORY;

        case ERROR_NOT_SAME_DEVICE:
            return E_CROSS_DEVICE;

        case ERROR_WRITE_PROTECT:
            return E_READ_ONLY_FS;

        case ERROR_NOT_READY:
        case ERROR_NETWORK_BUSY:
        case ERROR_SHARING_PAUSED:
        case ERROR_REQ_NOT_ACCEP:
        case ERROR_REDIR_PAUSED:
        case ERROR_BUSY_DRIVE:
        case ERROR_PATH_BUSY:
        case ERROR_BUSY:
        case ERROR_DEVICE_SUPPORT_IN_PROGRESS:
        case ERROR_PIPE_BUSY:
            return E_BUSY;

        case ERROR_BAD_COMMAND:
        case ERROR_BAD_LENGTH:
        case ERROR_INVALID_LEVEL:
        case ERROR_INVALID_CATEGORY:
        case ERROR_INVALID_VERIFY_SWITCH:
        case ERROR_INVALID_FLAG_NUMBER:
        case ERROR_INVALID_ORDINAL:
            return E_INVALID;

        case ERROR_CRC:
        case ERROR_SEEK:
        case ERROR_NOT_DOS_DISK:
        case ERROR_SECTOR_NOT_FOUND:
        case ERROR_WRITE_FAULT:
        case ERROR_READ_FAULT:
        case ERROR_GEN_FAILURE:
        case ERROR_NET_WRITE_FAULT:
        case ERROR_OPEN_FAILED:
        case ERROR_UNEXP_NET_ERR:
        case ERROR_BAD_NET_RESP:
        case ERROR_NET_OPEN_FAILED:
            return E_IO;

        case ERROR_OUT_OF_PAPER:
            return E_NO_SPACE;

        case ERROR_SHARING_VIOLATION:
        case ERROR_LOCK_VIOLATION:
        case ERROR_LOCK_FAILED:
        case ERROR_LOCKED:
            return E_BUSY;

        case ERROR_WRONG_DISK:
        case ERROR_DISK_CHANGE:
            return E_IO;

        case ERROR_HANDLE_EOF:
            return EOF;

        case ERROR_HANDLE_DISK_FULL:
        case ERROR_DISK_FULL:
        case ERROR_NO_SPOOL_SPACE:
            return E_NO_SPACE;

        case ERROR_NOT_SUPPORTED:
        case ERROR_CALL_NOT_IMPLEMENTED:
            return E_NOT_IMPLEMENTED;

        case ERROR_DUP_NAME:
        case ERROR_FILE_EXISTS:
        case ERROR_ALREADY_EXISTS:
            return E_EXISTS;

        case ERROR_BAD_NETPATH:
        case ERROR_BAD_NET_NAME:
        case ERROR_NETNAME_DELETED:
            return E_NOT_FOUND;

        case ERROR_TOO_MANY_CMDS:
        case ERROR_TOO_MANY_NAMES:
        case ERROR_TOO_MANY_SESS:
        case ERROR_TOO_MANY_SEMAPHORES:
        case ERROR_TOO_MANY_SEM_REQUESTS:
        case ERROR_TOO_MANY_POSTS:
        case ERROR_TOO_MANY_THREADS:
            return E_TOO_MANY_REFS;

        case ERROR_NETWORK_ACCESS_DENIED:
            return E_ACCESS_DENIED;

        case ERROR_BAD_DEV_TYPE:
            return E_NOT_SOCKET;

        case ERROR_CANNOT_MAKE:
            return E_PERMISSION;

        case ERROR_INVALID_PASSWORD:
            return E_ACCESS_DENIED;

        case ERROR_INVALID_PARAMETER:
        case ERROR_BAD_ARGUMENTS:
            return E_INVALID_ARG;

        case ERROR_NO_PROC_SLOTS:
        case ERROR_MAX_THRDS_REACHED:
            return E_AGAIN;

        case ERROR_SEM_TIMEOUT:
        case WAIT_TIMEOUT:
        case WSAETIMEDOUT:
            return E_TIMED_OUT;

        case ERROR_INSUFFICIENT_BUFFER:
        case ERROR_BUFFER_OVERFLOW:
            return E_NO_BUFFER;

        case ERROR_INVALID_NAME:
        case ERROR_BAD_PATHNAME:
        case ERROR_FILENAME_EXCED_RANGE:
        case WSAENAMETOOLONG:
            return E_NAME_TOO_LONG;

        case ERROR_WAIT_NO_CHILDREN:
        case ERROR_CHILD_NOT_COMPLETE:
            return E_NO_CHILD;

        case ERROR_DIRECT_ACCESS_HANDLE:
            return E_BAD_FILE_DESC;

        case ERROR_NEGATIVE_SEEK:
        case ERROR_SEEK_ON_DEVICE:
            return E_ILLEGAL_SEEK;

        case ERROR_DIR_NOT_EMPTY:
        case WSAENOTEMPTY:
            return E_NOT_EMPTY;

        case ERROR_DIRECTORY:
            return E_IS_DIRECTORY;

        case ERROR_NOT_OWNER:
            return E_PERMISSION;

        case ERROR_PARTIAL_COPY:
        case ERROR_INVALID_ADDRESS:
        case WSAEFAULT:
            return E_BAD_ADDRESS;

        case ERROR_OPLOCK_NOT_GRANTED:
        case ERROR_INVALID_OPLOCK_PROTOCOL:
        case ERROR_DELETE_PENDING:
            return E_BUSY;

        case ERROR_DISK_TOO_FRAGMENTED:
            return E_NO_SPACE;

        case ERROR_SCOPE_NOT_FOUND:
            return E_NOT_FOUND;

        case ERROR_FAIL_NOACTION_REBOOT:
        case ERROR_FAIL_SHUTDOWN:
        case ERROR_FAIL_RESTART:
            return E_IO;

        case ERROR_ARITHMETIC_OVERFLOW:
            return E_OVERFLOW;

        case ERROR_PIPE_CONNECTED:
            return E_IS_CONNECTED;

        case ERROR_PIPE_LISTENING:
            return E_AGAIN;

        case ERROR_BROKEN_PIPE:
            return E_BROKEN_PIPE;

        case ERROR_BAD_PIPE:
            return E_IO;

        case ERROR_NO_DATA:
            return E_NO_MESSAGE;

        case ERROR_PIPE_NOT_CONNECTED:
            return E_NOT_CONNECTED;

        case ERROR_MORE_DATA:
            return E_MSG_TOO_LONG;

        case ERROR_VC_DISCONNECTED:
            return E_CONN_RESET;

        case ERROR_INVALID_EA_NAME:
        case ERROR_EA_LIST_INCONSISTENT:
        case ERROR_EA_FILE_CORRUPT:
        case ERROR_EA_TABLE_FULL:
        case ERROR_INVALID_EA_HANDLE:
            return E_INVALID;

        case ERROR_EAS_DIDNT_FIT:
            return E_NO_SPACE;

        case ERROR_EAS_NOT_SUPPORTED:
            return E_NOT_IMPLEMENTED;

        case ERROR_MR_MID_NOT_FOUND:
            return E_NOT_FOUND;

        case ERROR_CANCEL_VIOLATION:
        case WSAECANCELLED:
        case WSA_E_CANCELLED:
            return E_CANCELED;

        case ERROR_FILE_TOO_LARGE:
            return E_FILE_TOO_BIG;

        case ERROR_FORMS_AUTH_REQUIRED:
            return E_ACCESS_DENIED;

        case ERROR_VIRUS_INFECTED:
        case ERROR_VIRUS_DELETED:
            return E_PERMISSION;

        case ERROR_ILLEGAL_CHARACTER:
        case ERROR_UNDEFINED_CHARACTER:
            return E_ILLEGAL_SEQUENCE;

        case ERROR_STACK_OVERFLOW_READ:
            return E_OVERFLOW;

        case ERROR_BAD_COMPRESSION_BUFFER:
        case ERROR_INVALID_VARIANT:
            return E_INVALID;

        case ERROR_NO_MORE_MATCHES:
        case ERROR_RANGE_NOT_FOUND:
            return E_NOT_FOUND;

        case ERROR_FLOAT_MULTIPLE_FAULTS:
        case ERROR_FLOAT_MULTIPLE_TRAPS:
            return E_DOMAIN;

        case ERROR_NOINTERFACE:
            return E_NOT_IMPLEMENTED;

        case ERROR_DRIVER_FAILED_INIT:
        case ERROR_DRIVER_FAILED_PRIOR_UNLOAD:
        case ERROR_DEVICE_ENUMERATION_ERROR:
        case ERROR_INVALID_DEVICE_OBJECT_PARAMETER:
        case ERROR_DRIVER_DATABASE_ERROR:
        case ERROR_CORRUPT_SYSTEM_FILE:
        case ERROR_FAILED_DRIVER_ENTRY:
            return E_IO;

        case ERROR_INSUFFICIENT_POWER:
        case ERROR_SYSTEM_SHUTDOWN:
            return E_SHUTDOWN;

        case WSAEINTR:
            return E_INTERRUPTED;

        case WSAEWOULDBLOCK:
            return E_WOULD_BLOCK;

        case WSAEINPROGRESS:
            return E_IN_PROGRESS;

        case WSAEALREADY:
            return E_ALREADY;

        case WSAENOTSOCK:
            return E_NOT_SOCKET;

        case WSAEDESTADDRREQ:
            return E_DEST_ADDR_REQUIRED;

        case WSAEMSGSIZE:
            return E_MSG_TOO_LONG;

        case WSAEPROTOTYPE:
            return E_PROTO_WRONG_TYPE;

        case WSAENOPROTOOPT:
            return E_NO_PROTO_OPTION;

        case WSAEPROTONOSUPPORT:
            return E_PROTO_NOT_SUPPORTED;

        case WSAESOCKTNOSUPPORT:
            return E_SOCKET_TYPE_NOT_SUPPORTED;

        case WSAEOPNOTSUPP:
            return E_OP_NOT_SUPPORTED;

        case WSAEPFNOSUPPORT:
            return E_PROTO_FAMILY_NOT_SUPPORTED;

        case WSAEAFNOSUPPORT:
            return E_ADDR_FAMILY_NOT_SUPPORTED;

        case WSAEADDRINUSE:
            return E_ADDR_IN_USE;

        case WSAEADDRNOTAVAIL:
            return E_ADDR_NOT_AVAIL;

        case WSAENETDOWN:
            return E_NET_DOWN;

        case WSAENETUNREACH:
            return E_NET_UNREACHABLE;

        case WSAENETRESET:
            return E_NET_RESET;

        case WSAECONNABORTED:
            return E_CONN_ABORTED;

        case WSAECONNRESET:
            return E_CONN_RESET;

        case WSAENOBUFS:
            return E_NO_BUFFER;

        case WSAEISCONN:
            return E_IS_CONNECTED;

        case WSAENOTCONN:
            return E_NOT_CONNECTED;

        case WSAESHUTDOWN:
            return E_SHUTDOWN;

        case WSAETOOMANYREFS:
            return E_TOO_MANY_REFS;

        case WSAECONNREFUSED:
            return E_CONN_REFUSED;

        case WSAELOOP:
            return E_TOO_MANY_SYMLINKS;

        case WSAEHOSTDOWN:
            return E_HOST_DOWN;

        case WSAEHOSTUNREACH:
            return E_HOST_UNREACHABLE;

        case WSAEPROCLIM:
            return E_AGAIN;

        case WSAEUSERS:
            return E_TOO_MANY_USERS;

        case WSAEDQUOT:
            return E_DISK_QUOTA;

        case WSAESTALE:
            return E_STALE_HANDLE;

        case WSAEREMOTE:
            return E_REMOTE;

        case WSASYSNOTREADY:
        case WSAVERNOTSUPPORTED:
        case WSANOTINITIALISED:
            return E_NOT_CONNECTED;

        case WSAEDISCON:
            return E_CONN_RESET;

        case WSAENOMORE:
        case WSA_E_NO_MORE:
            return E_NOT_FOUND;

        case WSAEINVALIDPROCTABLE:
        case WSAEINVALIDPROVIDER:
        case WSAEPROVIDERFAILEDINIT:
        case WSASYSCALLFAILURE:
            return E_IO;

        case WSASERVICE_NOT_FOUND:
        case WSATYPE_NOT_FOUND:
        case WSAHOST_NOT_FOUND:
        case WSANO_DATA:
            return E_NOT_FOUND;

        case WSAEREFUSED:
            return E_CONN_REFUSED;

        case WSATRY_AGAIN:
            return E_AGAIN;

        case WSANO_RECOVERY:
            return E_GENERAL_ERR;

        case WSA_QOS_RECEIVERS:
        case WSA_QOS_SENDERS:
        case WSA_QOS_NO_SENDERS:
        case WSA_QOS_NO_RECEIVERS:
        case WSA_QOS_REQUEST_CONFIRMED:
        case WSA_QOS_ADMISSION_FAILURE:
        case WSA_QOS_POLICY_FAILURE:
        case WSA_QOS_BAD_STYLE:
        case WSA_QOS_BAD_OBJECT:
        case WSA_QOS_TRAFFIC_CTRL_ERROR:
        case WSA_QOS_GENERIC_ERROR:
        case WSA_QOS_ESERVICETYPE:
        case WSA_QOS_EFLOWSPEC:
        case WSA_QOS_EPROVSPECBUF:
        case WSA_QOS_EFILTERSTYLE:
        case WSA_QOS_EFILTERTYPE:
        case WSA_QOS_EFILTERCOUNT:
        case WSA_QOS_EOBJLENGTH:
        case WSA_QOS_EFLOWCOUNT:
        case WSA_QOS_EUNKOWNPSOBJ:
        case WSA_QOS_EPOLICYOBJ:
        case WSA_QOS_EFLOWDESC:
        case WSA_QOS_EPSFLOWSPEC:
        case WSA_QOS_EPSFILTERSPEC:
        case WSA_QOS_ESDMODEOBJ:
        case WSA_QOS_ESHAPERATEOBJ:
        case WSA_QOS_RESERVED_PETYPE:
            return E_PROTOCOL;

        default:
            return E_GENERAL_ERR;
    }
}

// common fault names 
faultdef E_ARG_TOO_BIG, E_ACCESS_DENIED, E_ADDR_IN_USE, E_ADDR_NOT_AVAIL, E_ADDR_FAMILY_NOT_SUPPORTED, E_AGAIN, E_ALREADY, E_BAD_FILE_DESC, E_BAD_MESSAGE, E_BUSY, E_CANCELED, E_NO_CHILD, E_CONN_ABORTED, E_CONN_REFUSED, E_CONN_RESET, E_DEADLOCK, E_DEST_ADDR_REQUIRED, E_DOMAIN, E_DISK_QUOTA, E_EXISTS, E_BAD_ADDRESS, E_FILE_TOO_BIG, E_HOST_DOWN, E_HOST_UNREACHABLE, E_ID_REMOVED, E_ILLEGAL_SEQUENCE, E_IN_PROGRESS, E_INTERRUPTED, E_INVALID, E_IO, E_IS_CONNECTED, E_IS_DIRECTORY, E_TOO_MANY_SYMLINKS, E_TOO_MANY_FILES, E_TOO_MANY_LINKS, E_MSG_TOO_LONG, E_NAME_TOO_LONG, E_NET_DOWN, E_NET_RESET, E_NET_UNREACHABLE, E_FILE_TABLE_OVERFLOW, E_NO_BUFFER, E_NO_DEVICE, E_NOT_FOUND, E_EXEC_FORMAT, E_NO_LOCK, E_NO_MEMORY, E_NO_MESSAGE, E_NO_PROTO_OPTION, E_NO_SPACE, E_NOT_IMPLEMENTED, E_NOT_BLOCK_DEVICE, E_NOT_CONNECTED, E_NOT_DIRECTORY, E_NOT_EMPTY, E_NOT_RECOVERABLE, E_NOT_SOCKET, E_NOT_TTY, E_NO_SUCH_DEVICE, E_OP_NOT_SUPPORTED, E_OVERFLOW, E_OWNER_DEAD, E_PERMISSION, E_PROTO_FAMILY_NOT_SUPPORTED, E_BROKEN_PIPE, E_PROTOCOL, E_PROTO_NOT_SUPPORTED, E_PROTO_WRONG_TYPE, E_OUT_OF_RANGE, E_REMOTE, E_READ_ONLY_FS, E_SHUTDOWN, E_SOCKET_TYPE_NOT_SUPPORTED, E_ILLEGAL_SEEK, E_NO_SUCH_PROCESS, E_STALE_HANDLE, E_TIMED_OUT, E_TOO_MANY_REFS, E_TEXT_BUSY, E_TOO_MANY_USERS, E_WOULD_BLOCK, E_CROSS_DEVICE, EOF, E_INVALID_INPUT, E_INVALID_ARG, E_GENERAL_ERR;

faultdef F_SUCCESS;

// Error mapping win error to posix errno

const int EPERM = 1;
const int ENOENT = 2;
const int ESRCH = 3;
const int EINTR = 4;
const int EIO = 5;
const int ENXIO = 6;
const int E2BIG = 7;
const int ENOEXEC = 8;
const int EBADF = 9;
const int ECHILD = 10;
const int EAGAIN = 11;
const int ENOMEM = 12;
const int EACCES = 13;
const int EFAULT = 14;
const int ENOTBLK = 15;
const int EBUSY = 16;
const int EEXIST = 17;
const int EXDEV = 18;
const int ENODEV = 19;
const int ENOTDIR = 20;
const int EISDIR = 21;
const int EINVAL = 22;
const int ENFILE = 23;
const int EMFILE = 24;
const int ENOTTY = 25;
const int ETXTBSY = 26;
const int EFBIG = 27;
const int ENOSPC = 28;
const int ESPIPE = 29;
const int EROFS = 30;
const int EMLINK = 31;
const int EPIPE = 32;
const int EDOM = 33;
const int ERANGE = 34;
const int EDEADLK = 35;
const int ENAMETOOLONG = 36;
const int ENOLCK = 37;
const int ENOSYS = 38;
const int ENOTEMPTY = 39;
const int ELOOP = 40;
const int EWOULDBLOCK = 41; // 11 Eagain
const int ENOMSG = 42;
const int EIDRM = 43;
const int ECHRNG = 44;
const int EL2NSYNC = 45;
const int EL3HLT = 46;
const int EL3RST = 47;
const int ELNRNG = 48;
const int EUNATCH = 49;
const int ENOCSI = 50;
const int EL2HLT = 51;
const int EBADE = 52;
const int EBADR = 53;
const int EXFULL = 54;
const int ENOANO = 55;
const int EBADRQC = 56;
const int EBADSLT = 57;
const int EDEADLOCK = 58; // == 35
const int EBFONT = 59;
const int ENOSTR = 60;
const int ENODATA = 61;
const int ETIME = 62;
const int ENOSR = 63;
const int ENONET = 64;
const int ENOPKG = 65;
const int EREMOTE = 66;
const int ENOLINK = 67;
const int EADV = 68;
const int ESRMNT = 69;
const int ECOMM = 70;
const int EPROTO = 71;
const int EMULTIHOP = 72;
const int EDOTDOT = 73;
const int EBADMSG = 74;
const int EOVERFLOW = 75;
const int ENOTUNIQ = 76;
const int EBADFD = 77;
const int EREMCHG = 78;
const int ELIBACC = 79;
const int ELIBBAD = 80;
const int ELIBSCN = 81;
const int ELIBMAX = 82;
const int ELIBEXEC = 83;
const int EILSEQ = 84;
const int ERESTART = 85;
const int ESTRPIPE = 86;
const int EUSERS = 87;
const int ENOTSOCK = 88;
const int EDESTADDRREQ = 89;
const int EMSGSIZE = 90;
const int EPROTOTYPE = 91;
const int ENOPROTOOPT = 92;
const int EPROTONOSUPPORT = 93;
const int ESOCKTNOSUPPORT = 94;
const int EOPNOTSUPP = 95;
const int EPFNOSUPPORT = 96;
const int EAFNOSUPPORT = 97;
const int EADDRINUSE = 98;
const int EADDRNOTAVAIL = 99;
const int ENETDOWN = 100;
const int ENETUNREACH = 101;
const int ENETRESET = 102;
const int ECONNABORTED = 103;
const int ECONNRESET = 104;
const int ENOBUFS = 105;
const int EISCONN = 106;
const int ENOTCONN = 107;
const int ESHUTDOWN = 108;
const int ETOOMANYREFS = 109;
const int ETIMEDOUT = 110;
const int ECONNREFUSED = 111;
const int EHOSTDOWN = 112;
const int EHOSTUNREACH = 113;
const int EALREADY = 114;
const int EINPROGRESS = 115;
const int ESTALE = 116;
const int EUCLEAN = 117;
const int ENOTNAM = 118;
const int ENAVAIL = 119;
const int EISNAM = 120;
const int EREMOTEIO = 121;
const int EDQUOT = 122;
const int ENOMEDIUM = 123;
const int EMEDIUMTYPE = 124;
const int ECANCELED = 125;
const int ENOKEY = 126;
const int EKEYEXPIRED = 127;
const int EKEYREVOKED = 128;
const int EKEYREJECTED = 129;
const int EOWNERDEAD = 130;
const int ENOTRECOVERABLE = 131;
const int ERFKILL = 132;
const int EHWPOISON = 133;

alias DWord = uint;

fn int win_error_to_errno(DWord error)
{
    switch (error)
    {
  case errno::ERROR_ACCESS_DENIED: return EACCES;
  case errno::ERROR_ALREADY_EXISTS: return EEXIST;
  case errno::ERROR_BAD_COMMAND: return EACCES;
  case errno::ERROR_BAD_EXE_FORMAT: return ENOEXEC;
  case errno::ERROR_BAD_LENGTH: return EACCES;
  case errno::ERROR_BAD_NETPATH: return ENOENT;
  case errno::ERROR_BAD_NET_NAME: return ENOENT;
  case errno::ERROR_BAD_NET_RESP: return ENETDOWN;
  case errno::ERROR_BAD_PATHNAME: return ENOENT;
  case errno::ERROR_BROKEN_PIPE: return EPIPE;
  case errno::ERROR_CANNOT_MAKE: return EACCES;
  case errno::ERROR_COMMITMENT_LIMIT: return ENOMEM;
  case errno::ERROR_CONNECTION_ABORTED: return ECONNABORTED;
  case errno::ERROR_CONNECTION_ACTIVE: return EISCONN;
  case errno::ERROR_CONNECTION_REFUSED: return ECONNREFUSED;
  case errno::ERROR_CRC: return EACCES;
  case errno::ERROR_DIR_NOT_EMPTY: return ENOTEMPTY;
  case errno::ERROR_DISK_FULL: return ENOSPC;
  case errno::ERROR_DUP_NAME: return EADDRINUSE;
  case errno::ERROR_FILENAME_EXCED_RANGE: return ENOENT;
  case errno::ERROR_FILE_NOT_FOUND: return ENOENT;
  case errno::ERROR_GEN_FAILURE: return EACCES;
  case errno::ERROR_GRACEFUL_DISCONNECT: return EPIPE;
  case errno::ERROR_HOST_DOWN: return EHOSTUNREACH;
  case errno::ERROR_HOST_UNREACHABLE: return EHOSTUNREACH;
  case errno::ERROR_INSUFFICIENT_BUFFER: return EFAULT;
  case errno::ERROR_INVALID_ADDRESS: return EADDRNOTAVAIL;
  case errno::ERROR_INVALID_FUNCTION: return EINVAL;
  case errno::ERROR_INVALID_HANDLE: return EBADF;
  case errno::ERROR_INVALID_NETNAME: return EADDRNOTAVAIL;
  case errno::ERROR_INVALID_PARAMETER: return EINVAL;
  case errno::ERROR_INVALID_USER_BUFFER: return EMSGSIZE;
  case errno::ERROR_IO_PENDING: return EINPROGRESS;
  case errno::ERROR_LOCK_VIOLATION: return EACCES;
  case errno::ERROR_MORE_DATA: return EMSGSIZE;
  case errno::ERROR_NETNAME_DELETED: return ECONNABORTED;
  case errno::ERROR_NETWORK_ACCESS_DENIED: return EACCES;
  case errno::ERROR_NETWORK_BUSY: return ENETDOWN;
  case errno::ERROR_NETWORK_UNREACHABLE: return ENETUNREACH;
  case errno::ERROR_NOACCESS: return EFAULT;
  case errno::ERROR_NONPAGED_SYSTEM_RESOURCES: return ENOMEM;
  case errno::ERROR_NOT_ENOUGH_MEMORY: return ENOMEM;
  case errno::ERROR_NOT_ENOUGH_QUOTA: return ENOMEM;
  case errno::ERROR_NOT_FOUND: return ENOENT;
  case errno::ERROR_NOT_LOCKED: return EACCES;
  case errno::ERROR_NOT_READY: return EACCES;
  case errno::ERROR_NOT_SAME_DEVICE: return EXDEV;
  case errno::ERROR_NOT_SUPPORTED: return EOPNOTSUPP;
  case errno::ERROR_NO_MORE_FILES: return ENOENT;
  case errno::ERROR_NO_SYSTEM_RESOURCES: return ENOMEM;
  case errno::ERROR_OPERATION_ABORTED: return EINTR;
  case errno::ERROR_OUT_OF_PAPER: return EACCES;
  case errno::ERROR_PAGED_SYSTEM_RESOURCES: return ENOMEM;
  case errno::ERROR_PAGEFILE_QUOTA: return ENOMEM;
  case errno::ERROR_PATH_NOT_FOUND: return ENOENT;
  case errno::ERROR_PIPE_NOT_CONNECTED: return EPIPE;
  case errno::ERROR_PORT_UNREACHABLE: return ECONNRESET;
  case errno::ERROR_PROTOCOL_UNREACHABLE: return ENETUNREACH;
  case errno::ERROR_REM_NOT_LIST: return ECONNREFUSED;
  case errno::ERROR_REQUEST_ABORTED: return EINTR;
  case errno::ERROR_REQ_NOT_ACCEP: return EWOULDBLOCK;
  case errno::ERROR_SECTOR_NOT_FOUND: return EACCES;
  case errno::ERROR_SEM_TIMEOUT: return ETIMEDOUT;
  case errno::ERROR_SHARING_VIOLATION: return EACCES;
  case errno::ERROR_TOO_MANY_NAMES: return ENOMEM;
  case errno::ERROR_TOO_MANY_OPEN_FILES: return EMFILE;
  case errno::ERROR_UNEXP_NET_ERR: return ECONNABORTED;
  case errno::ERROR_WAIT_NO_CHILDREN: return ECHILD;
  case errno::ERROR_WORKING_SET_QUOTA: return ENOMEM;
  case errno::ERROR_WRITE_PROTECT: return EACCES;
  case errno::ERROR_WRONG_DISK: return EACCES;
  case errno::WSAEACCES: return EACCES;
  case errno::WSAEADDRINUSE: return EADDRINUSE;
  case errno::WSAEADDRNOTAVAIL: return EADDRNOTAVAIL;
  case errno::WSAEAFNOSUPPORT: return EAFNOSUPPORT;
  // case errno::WSAECONNABORTED: return ECONNABORTED;
  // case errno::WSAECONNREFUSED: return ECONNREFUSED;
  case errno::WSAECONNRESET: return ECONNRESET;
  case errno::WSAEDISCON: return EPIPE;
  case errno::WSAEFAULT: return EFAULT;
  // case errno::WSAEHOSTDOWN: return EHOSTUNREACH;
  // case errno::WSAEHOSTUNREACH: return EHOSTUNREACH;
  case errno::WSAEINPROGRESS: return EBUSY;
  case errno::WSAEINTR: return EINTR;
  case errno::WSAEINVAL: return EINVAL;
  case errno::WSAEISCONN: return EISCONN;
  case errno::WSAEMSGSIZE: return EMSGSIZE;
  case errno::WSAENETDOWN: return ENETDOWN;
  case errno::WSAENETRESET: return EHOSTUNREACH;
  // case errno::WSAENETUNREACH: return ENETUNREACH;
  case errno::WSAENOBUFS: return ENOMEM;
  case errno::WSAENOTCONN: return ENOTCONN;
  case errno::WSAENOTSOCK: return ENOTSOCK;
  case errno::WSAEOPNOTSUPP: return EOPNOTSUPP;
  case errno::WSAEPROCLIM: return ENOMEM;
  case errno::WSAESHUTDOWN: return EPIPE;
  case errno::WSAETIMEDOUT: return ETIMEDOUT;
  case errno::WSAEWOULDBLOCK: return EWOULDBLOCK;
  case errno::WSANOTINITIALISED: return ENETDOWN;
  case errno::WSASYSNOTREADY: return ENETDOWN;
  case errno::WSAVERNOTSUPPORTED: return ENOSYS;
    }

    return EINVAL;
}


// alias uint = long;

// Windows ERROR_ Constants

// Success

const uint ERROR_SUCCESS = 0;


// General Errors (0-499)

const uint ERROR_INVALID_FUNCTION = 1;
const uint ERROR_FILE_NOT_FOUND = 2;
const uint ERROR_PATH_NOT_FOUND = 3;
const uint ERROR_TOO_MANY_OPEN_FILES = 4;
const uint ERROR_ACCESS_DENIED = 5;
const uint ERROR_INVALID_HANDLE = 6;
const uint ERROR_ARENA_TRASHED = 7;
const uint ERROR_NOT_ENOUGH_MEMORY = 8;
const uint ERROR_INVALID_BLOCK = 9;
const uint ERROR_BAD_ENVIRONMENT = 10;
const uint ERROR_BAD_FORMAT = 11;
const uint ERROR_INVALID_ACCESS = 12;
const uint ERROR_INVALID_DATA = 13;
const uint ERROR_OUTOFMEMORY = 14;
const uint ERROR_INVALID_DRIVE = 15;
const uint ERROR_CURRENT_DIRECTORY = 16;
const uint ERROR_NOT_SAME_DEVICE = 17;
const uint ERROR_NO_MORE_FILES = 18;
const uint ERROR_WRITE_PROTECT = 19;
const uint ERROR_BAD_UNIT = 20;
const uint ERROR_NOT_READY = 21;
const uint ERROR_BAD_COMMAND = 22;
const uint ERROR_CRC = 23;
const uint ERROR_BAD_LENGTH = 24;
const uint ERROR_SEEK = 25;
const uint ERROR_NOT_DOS_DISK = 26;
const uint ERROR_SECTOR_NOT_FOUND = 27;
const uint ERROR_OUT_OF_PAPER = 28;
const uint ERROR_WRITE_FAULT = 29;
const uint ERROR_READ_FAULT = 30;
const uint ERROR_GEN_FAILURE = 31;
const uint ERROR_SHARING_VIOLATION = 32;
const uint ERROR_LOCK_VIOLATION = 33;
const uint ERROR_WRONG_DISK = 34;
const uint ERROR_SHARING_BUFFER_EXCEEDED = 36;
const uint ERROR_HANDLE_EOF = 38;
const uint ERROR_HANDLE_DISK_FULL = 39;
const uint ERROR_NOT_SUPPORTED = 50;
const uint ERROR_REM_NOT_LIST = 51;
const uint ERROR_DUP_NAME = 52;
const uint ERROR_BAD_NETPATH = 53;
const uint ERROR_NETWORK_BUSY = 54;
const uint ERROR_DEV_NOT_EXIST = 55;
const uint ERROR_TOO_MANY_CMDS = 56;
const uint ERROR_ADAP_HDW_ERR = 57;
const uint ERROR_BAD_NET_RESP = 58;
const uint ERROR_UNEXP_NET_ERR = 59;
const uint ERROR_BAD_REM_ADAP = 60;
const uint ERROR_PRINTQ_FULL = 61;
const uint ERROR_NO_SPOOL_SPACE = 62;
const uint ERROR_PRINT_CANCELLED = 63;
const uint ERROR_NETNAME_DELETED = 64;
const uint ERROR_NETWORK_ACCESS_DENIED = 65;
const uint ERROR_BAD_DEV_TYPE = 66;
const uint ERROR_BAD_NET_NAME = 67;
const uint ERROR_TOO_MANY_NAMES = 68;
const uint ERROR_TOO_MANY_SESS = 69;
const uint ERROR_SHARING_PAUSED = 70;
const uint ERROR_REQ_NOT_ACCEP = 71;
const uint ERROR_REDIR_PAUSED = 72;
const uint ERROR_FILE_EXISTS = 80;
const uint ERROR_CANNOT_MAKE = 82;
const uint ERROR_FAIL_I24 = 83;
const uint ERROR_OUT_OF_STRUCTURES = 84;
const uint ERROR_ALREADY_ASSIGNED = 85;
const uint ERROR_INVALID_PASSWORD = 86;
const uint ERROR_INVALID_PARAMETER = 87;
const uint ERROR_NET_WRITE_FAULT = 88;
const uint ERROR_NO_PROC_SLOTS = 89;
const uint ERROR_TOO_MANY_SEMAPHORES = 100;
const uint ERROR_EXCL_SEM_ALREADY_OWNED = 101;
const uint ERROR_SEM_IS_SET = 102;
const uint ERROR_TOO_MANY_SEM_REQUESTS = 103;
const uint ERROR_INVALID_AT_INTERRUPT_TIME = 104;
const uint ERROR_SEM_OWNER_DIED = 105;
const uint ERROR_SEM_USER_LIMIT = 106;
const uint ERROR_DISK_CHANGE = 107;
const uint ERROR_DRIVE_LOCKED = 108;
const uint ERROR_BROKEN_PIPE = 109;
const uint ERROR_OPEN_FAILED = 110;
const uint ERROR_BUFFER_OVERFLOW = 111;
const uint ERROR_DISK_FULL = 112;
const uint ERROR_NO_MORE_SEARCH_HANDLES = 113;
const uint ERROR_INVALID_TARGET_HANDLE = 114;
const uint ERROR_INVALID_CATEGORY = 117;
const uint ERROR_INVALID_VERIFY_SWITCH = 118;
const uint ERROR_BAD_DRIVER_LEVEL = 119;
const uint ERROR_CALL_NOT_IMPLEMENTED = 120;
const uint ERROR_SEM_TIMEOUT = 121;
const uint ERROR_INSUFFICIENT_BUFFER = 122;
const uint ERROR_INVALID_NAME = 123;
const uint ERROR_INVALID_LEVEL = 124;
const uint ERROR_NO_VOLUME_LABEL = 125;
const uint ERROR_MOD_NOT_FOUND = 126;
const uint ERROR_PROC_NOT_FOUND = 127;
const uint ERROR_WAIT_NO_CHILDREN = 128;
const uint ERROR_CHILD_NOT_COMPLETE = 129;
const uint ERROR_DIRECT_ACCESS_HANDLE = 130;
const uint ERROR_NEGATIVE_SEEK = 131;
const uint ERROR_SEEK_ON_DEVICE = 132;


// Directory and Path Errors (133-206)

const uint ERROR_IS_JOIN_TARGET = 133;
const uint ERROR_IS_JOINED = 134;
const uint ERROR_IS_SUBSTED = 135;
const uint ERROR_NOT_JOINED = 136;
const uint ERROR_NOT_SUBSTED = 137;
const uint ERROR_JOIN_TO_JOIN = 138;
const uint ERROR_SUBST_TO_SUBST = 139;
const uint ERROR_JOIN_TO_SUBST = 140;
const uint ERROR_SUBST_TO_JOIN = 141;
const uint ERROR_BUSY_DRIVE = 142;
const uint ERROR_SAME_DRIVE = 143;
const uint ERROR_DIR_NOT_ROOT = 144;
const uint ERROR_DIR_NOT_EMPTY = 145;
const uint ERROR_IS_SUBST_PATH = 146;
const uint ERROR_IS_JOIN_PATH = 147;
const uint ERROR_PATH_BUSY = 148;
const uint ERROR_IS_SUBST_TARGET = 149;
const uint ERROR_SYSTEM_TRACE = 150;
const uint ERROR_INVALID_EVENT_COUNT = 151;
const uint ERROR_TOO_MANY_MUXWAITERS = 152;
const uint ERROR_INVALID_LIST_FORMAT = 153;
const uint ERROR_LABEL_TOO_LONG = 154;
const uint ERROR_TOO_MANY_TCBS = 155;
const uint ERROR_SIGNAL_REFUSED = 156;
const uint ERROR_DISCARDED = 157;
const uint ERROR_NOT_LOCKED = 158;
const uint ERROR_BAD_THREADID_ADDR = 159;
const uint ERROR_BAD_ARGUMENTS = 160;
const uint ERROR_BAD_PATHNAME = 161;
const uint ERROR_SIGNAL_PENDING = 162;
const uint ERROR_MAX_THRDS_REACHED = 164;
const uint ERROR_LOCK_FAILED = 167;
const uint ERROR_BUSY = 170;
const uint ERROR_DEVICE_SUPPORT_IN_PROGRESS = 171;
const uint ERROR_CANCEL_VIOLATION = 173;
const uint ERROR_ATOMIC_LOCKS_NOT_SUPPORTED = 174;
const uint ERROR_INVALID_SEGMENT_NUMBER = 180;
const uint ERROR_INVALID_ORDINAL = 182;
const uint ERROR_ALREADY_EXISTS = 183;
const uint ERROR_INVALID_FLAG_NUMBER = 186;
const uint ERROR_SEM_NOT_FOUND = 187;
const uint ERROR_INVALID_STARTING_CODESEG = 188;
const uint ERROR_INVALID_STACKSEG = 189;
const uint ERROR_INVALID_MODULETYPE = 190;
const uint ERROR_INVALID_EXE_SIGNATURE = 191;
const uint ERROR_EXE_MARKED_INVALID = 192;
const uint ERROR_BAD_EXE_FORMAT = 193;
const uint ERROR_ITERATED_DATA_EXCEEDS_64K = 194;
const uint ERROR_INVALID_MINALLOCSIZE = 195;
const uint ERROR_DYNLINK_FROM_INVALID_RING = 196;
const uint ERROR_IOPL_NOT_ENABLED = 197;
const uint ERROR_INVALID_SEGDPL = 198;
const uint ERROR_AUTODATASEG_EXCEEDS_64K = 199;
const uint ERROR_RING2SEG_MUST_BE_MOVABLE = 200;
const uint ERROR_RELOC_CHAIN_XEEDS_SEGLIM = 201;
const uint ERROR_INFLOOP_IN_RELOC_CHAIN = 202;
const uint ERROR_ENVVAR_NOT_FOUND = 203;
const uint ERROR_NO_SIGNAL_SENT = 205;
const uint ERROR_FILENAME_EXCED_RANGE = 206;


// System Errors (207-249)

const uint ERROR_RING2_STACK_IN_USE = 207;
const uint ERROR_META_EXPANSION_TOO_LONG = 208;
const uint ERROR_INVALID_SIGNAL_NUMBER = 209;
const uint ERROR_THREAD_1_INACTIVE = 210;
const uint ERROR_LOCKED = 212;
const uint ERROR_TOO_MANY_MODULES = 214;
const uint ERROR_NESTING_NOT_ALLOWED = 215;
const uint ERROR_EXE_MACHINE_TYPE_MISMATCH = 216;
const uint ERROR_EXE_CANNOT_MODIFY_SIGNED_BINARY = 217;
const uint ERROR_EXE_CANNOT_MODIFY_STRONG_SIGNED_BINARY = 218;
const uint ERROR_FILE_CHECKED_OUT = 220;
const uint ERROR_CHECKOUT_REQUIRED = 221;
const uint ERROR_BAD_FILE_TYPE = 222;
const uint ERROR_FILE_TOO_LARGE = 223;
const uint ERROR_FORMS_AUTH_REQUIRED = 224;
const uint ERROR_VIRUS_INFECTED = 225;
const uint ERROR_VIRUS_DELETED = 226;
const uint ERROR_PIPE_LOCAL = 229;
const uint ERROR_BAD_PIPE = 230;
const uint ERROR_PIPE_BUSY = 231;
const uint ERROR_NO_DATA = 232;
const uint ERROR_PIPE_NOT_CONNECTED = 233;
const uint ERROR_MORE_DATA = 234;
const uint ERROR_VC_DISCONNECTED = 240;
const uint ERROR_INVALID_EA_NAME = 254;
const uint ERROR_EA_LIST_INCONSISTENT = 255;


// Wait and Timeout Errors (258-288)

const uint WAIT_TIMEOUT = 258;
const uint ERROR_NO_MORE_ITEMS = 259;
const uint ERROR_CANNOT_COPY = 266;
const uint ERROR_DIRECTORY = 267;
const uint ERROR_EAS_DIDNT_FIT = 275;
const uint ERROR_EA_FILE_CORRUPT = 276;
const uint ERROR_EA_TABLE_FULL = 277;
const uint ERROR_INVALID_EA_HANDLE = 278;
const uint ERROR_EAS_NOT_SUPPORTED = 282;
const uint ERROR_NOT_OWNER = 288;


// Semaphore and Mutex Errors (298-300)

const uint ERROR_TOO_MANY_POSTS = 298;
const uint ERROR_PARTIAL_COPY = 299;
const uint ERROR_OPLOCK_NOT_GRANTED = 300;
const uint ERROR_INVALID_OPLOCK_PROTOCOL = 301;
const uint ERROR_DISK_TOO_FRAGMENTED = 302;
const uint ERROR_DELETE_PENDING = 303;


// Security and Access Control Errors (534-590)

const uint ERROR_MR_MID_NOT_FOUND = 317;
const uint ERROR_SCOPE_NOT_FOUND = 318;
const uint ERROR_FAIL_NOACTION_REBOOT = 350;
const uint ERROR_FAIL_SHUTDOWN = 351;
const uint ERROR_FAIL_RESTART = 352;
const uint ERROR_MAX_SESSIONS_REACHED = 353;
const uint ERROR_THREAD_MODE_ALREADY_BACKGROUND = 400;
const uint ERROR_THREAD_MODE_NOT_BACKGROUND = 401;
const uint ERROR_PROCESS_MODE_ALREADY_BACKGROUND = 402;
const uint ERROR_PROCESS_MODE_NOT_BACKGROUND = 403;
const uint ERROR_INVALID_ADDRESS = 487;


// User Profile and Registry Errors (500-699)

const uint ERROR_USER_PROFILE_LOAD = 500;
const uint ERROR_ARITHMETIC_OVERFLOW = 534;
const uint ERROR_PIPE_CONNECTED = 535;
const uint ERROR_PIPE_LISTENING = 536;
const uint ERROR_VERIFIER_STOP = 537;
const uint ERROR_ABIOS_ERROR = 538;
const uint ERROR_WX86_WARNING = 539;
const uint ERROR_WX86_ERROR = 540;
const uint ERROR_TIMER_NOT_CANCELED = 541;
const uint ERROR_UNWIND = 542;
const uint ERROR_BAD_STACK = 543;
const uint ERROR_INVALID_UNWIND_TARGET = 544;
const uint ERROR_INVALID_PORT_ATTRIBUTES = 545;
const uint ERROR_PORT_MESSAGE_TOO_LONG = 546;
const uint ERROR_INVALID_QUOTA_LOWER = 547;
const uint ERROR_DEVICE_ALREADY_ATTACHED = 548;
const uint ERROR_INSTRUCTION_MISALIGNMENT = 549;
const uint ERROR_PROFILING_NOT_STARTED = 550;
const uint ERROR_PROFILING_NOT_STOPPED = 551;
const uint ERROR_COULD_NOT_INTERPRET = 552;
const uint ERROR_PROFILING_AT_LIMIT = 553;
const uint ERROR_CANT_WAIT = 554;
const uint ERROR_CANT_TERMINATE_SELF = 555;
const uint ERROR_UNEXPECTED_MM_CREATE_ERR = 556;
const uint ERROR_UNEXPECTED_MM_MAP_ERROR = 557;
const uint ERROR_UNEXPECTED_MM_EXTEND_ERR = 558;
const uint ERROR_BAD_FUNCTION_TABLE = 559;
const uint ERROR_NO_GUID_TRANSLATION = 560;
const uint ERROR_INVALID_LDT_SIZE = 561;
const uint ERROR_INVALID_LDT_OFFSET = 563;
const uint ERROR_INVALID_LDT_DESCRIPTOR = 564;
const uint ERROR_TOO_MANY_THREADS = 565;
const uint ERROR_THREAD_NOT_IN_PROCESS = 566;
const uint ERROR_PAGEFILE_QUOTA_EXCEEDED = 567;
const uint ERROR_LOGON_SERVER_CONFLICT = 568;
const uint ERROR_SYNCHRONIZATION_REQUIRED = 569;
const uint ERROR_NET_OPEN_FAILED = 570;
const uint ERROR_IO_PRIVILEGE_FAILED = 571;
const uint ERROR_CONTROL_C_EXIT = 572;
const uint ERROR_MISSING_SYSTEMFILE = 573;
const uint ERROR_UNHANDLED_EXCEPTION = 574;
const uint ERROR_APP_INIT_FAILURE = 575;
const uint ERROR_PAGEFILE_CREATE_FAILED = 576;
const uint ERROR_INVALID_IMAGE_HASH = 577;
const uint ERROR_NO_PAGEFILE = 578;
const uint ERROR_ILLEGAL_FLOAT_CONTEXT = 579;
const uint ERROR_NO_EVENT_PAIR = 580;
const uint ERROR_DOMAIN_CTRLR_CONFIG_ERROR = 581;
const uint ERROR_ILLEGAL_CHARACTER = 582;
const uint ERROR_UNDEFINED_CHARACTER = 583;
const uint ERROR_FLOPPY_VOLUME = 584;
const uint ERROR_BIOS_FAILED_TO_CONNECT_INTERRUPT = 585;
const uint ERROR_BACKUP_CONTROLLER = 586;
const uint ERROR_MUTANT_LIMIT_EXCEEDED = 587;
const uint ERROR_FS_DRIVER_REQUIRED = 588;
const uint ERROR_CANNOT_LOAD_REGISTRY_FILE = 589;
const uint ERROR_DEBUG_ATTACH_FAILED = 590;


// System and Service Errors (591-699)

const uint ERROR_SYSTEM_PROCESS_TERMINATED = 591;
const uint ERROR_DATA_NOT_ACCEPTED = 592;
const uint ERROR_VDM_HARD_ERROR = 593;
const uint ERROR_DRIVER_CANCEL_TIMEOUT = 594;
const uint ERROR_REPLY_MESSAGE_MISMATCH = 595;
const uint ERROR_LOST_WRITEBEHIND_DATA = 596;
const uint ERROR_CLIENT_SERVER_PARAMETERS_INVALID = 597;
const uint ERROR_NOT_TINY_STREAM = 598;
const uint ERROR_STACK_OVERFLOW_READ = 599;
const uint ERROR_CONVERT_TO_LARGE = 600;
const uint ERROR_FOUND_OUT_OF_SCOPE = 601;
const uint ERROR_ALLOCATE_BUCKET = 602;
const uint ERROR_MARSHALL_OVERFLOW = 603;
const uint ERROR_INVALID_VARIANT = 604;
const uint ERROR_BAD_COMPRESSION_BUFFER = 605;
const uint ERROR_AUDIT_FAILED = 606;
const uint ERROR_TIMER_RESOLUTION_NOT_SET = 607;
const uint ERROR_INSUFFICIENT_LOGON_INFO = 608;
const uint ERROR_BAD_DLL_ENTRYPOINT = 609;
const uint ERROR_BAD_SERVICE_ENTRYPOINT = 610;
const uint ERROR_IP_ADDRESS_CONFLICT1 = 611;
const uint ERROR_IP_ADDRESS_CONFLICT2 = 612;
const uint ERROR_REGISTRY_QUOTA_LIMIT = 613;
const uint ERROR_NO_CALLBACK_ACTIVE = 614;
const uint ERROR_PWD_TOO_SHORT = 615;
const uint ERROR_PWD_TOO_RECENT = 616;
const uint ERROR_PWD_HISTORY_CONFLICT = 617;
const uint ERROR_UNSUPPORTED_COMPRESSION = 618;
const uint ERROR_INVALID_HW_PROFILE = 619;
const uint ERROR_INVALID_PLUGPLAY_DEVICE_PATH = 620;
const uint ERROR_QUOTA_LIST_INCONSISTENT = 621;
const uint ERROR_EVALUATION_EXPIRATION = 622;
const uint ERROR_ILLEGAL_DLL_RELOCATION = 623;
const uint ERROR_DLL_INIT_FAILED_LOGOFF = 624;
const uint ERROR_VALIDATE_CONTINUE = 625;
const uint ERROR_NO_MORE_MATCHES = 626;
const uint ERROR_RANGE_LIST_CONFLICT = 627;
const uint ERROR_SERVER_SID_MISMATCH = 628;
const uint ERROR_CANT_ENABLE_DENY_ONLY = 629;
const uint ERROR_FLOAT_MULTIPLE_FAULTS = 630;
const uint ERROR_FLOAT_MULTIPLE_TRAPS = 631;
const uint ERROR_NOINTERFACE = 632;
const uint ERROR_DRIVER_FAILED_INIT = 633;
const uint ERROR_DRIVER_FAILED_PRIOR_UNLOAD = 634;
const uint ERROR_DEVICE_ENUMERATION_ERROR = 635;
const uint ERROR_MOUNT_POINT_NOT_RESOLVED = 649;
const uint ERROR_INVALID_DEVICE_OBJECT_PARAMETER = 650;
const uint ERROR_MCA_OCCURED = 651;
const uint ERROR_DRIVER_DATABASE_ERROR = 652;
const uint ERROR_SYSTEM_HIVE_TOO_LARGE = 653;
const uint ERROR_DRIVER_FAILED_SLEEP = 654;
const uint ERROR_CORRUPT_SYSTEM_FILE = 655;
const uint ERROR_COMMITMENT_LIMIT = 455;
const uint ERROR_COMMITMENT_MINIMUM = 656;
const uint ERROR_PNP_RESTART_ENUMERATION = 657;
const uint ERROR_SYSTEM_IMAGE_BAD_SIGNATURE = 658;
const uint ERROR_PNP_REBOOT_REQUIRED = 659;
const uint ERROR_INSUFFICIENT_POWER = 660;
const uint ERROR_MULTIPLE_FAULT_VIOLATION = 661;
const uint ERROR_SYSTEM_SHUTDOWN = 662;
const uint ERROR_PORT_NOT_SET = 663;
const uint ERROR_DS_VERSION_CHECK_FAILURE = 664;
const uint ERROR_RANGE_NOT_FOUND = 665;
const uint ERROR_NOT_SAFE_MODE_DRIVER = 666;
const uint ERROR_FAILED_DRIVER_ENTRY = 667;
const uint ERROR_DEVICE_ENUMERATION_RETRY = 668;
const uint ERROR_DDI_TRY_AGAIN = 669;
const uint ERROR_DS_SCHEMA_UPDATE_DISALLOWED = 670;
const uint ERROR_DS_CANT_CREATE_UNDER_SCHEMA = 671;
const uint ERROR_DS_INSTALL_NO_SRC_SCH_VERSION = 672;
const uint ERROR_DS_INSTALL_NO_SCH_VERSION_IN_INIFILE = 673;
const uint ERROR_DS_INVALID_GROUP_TYPE = 674;
const uint ERROR_DS_NO_NEST_GLOBALGROUP_IN_MIXEDDOMAIN = 675;
const uint ERROR_DS_NO_NEST_LOCALGROUP_IN_MIXEDDOMAIN = 676;
const uint ERROR_DS_GLOBAL_CANT_HAVE_LOCAL_MEMBER = 677;
const uint ERROR_DS_GLOBAL_CANT_HAVE_UNIVERSAL_MEMBER = 678;
const uint ERROR_DS_UNIVERSAL_CANT_HAVE_LOCAL_MEMBER = 679;
const uint ERROR_DS_GLOBAL_CANT_HAVE_CROSSDOMAIN_MEMBER = 680;
const uint ERROR_DS_LOCAL_CANT_HAVE_CROSSDOMAIN_LOCAL_MEMBER = 681;
const uint ERROR_DS_HAVE_PRIMARY_MEMBERS = 682;
const uint ERROR_DS_STRING_SD_CONVERSION_FAILED = 683;
const uint ERROR_DS_NAMING_MASTER_GC = 684;
const uint ERROR_DS_DNS_LOOKUP_FAILURE = 685;
const uint ERROR_DS_COULDNT_UPDATE_SPNS = 686;
const uint ERROR_DS_CANT_RETRIEVE_SD = 687;
const uint ERROR_DS_KEY_NOT_UNIQUE = 688;
const uint ERROR_DS_WRONG_LINKED_ATT_SYNTAX = 689;
const uint ERROR_DS_SAM_NEED_BOOTKEY_PASSWORD = 690;
const uint ERROR_DS_SAM_NEED_BOOTKEY_FLOPPY = 691;
const uint ERROR_DS_CANT_START = 692;
const uint ERROR_DS_INIT_FAILURE = 693;
const uint ERROR_DS_NO_PKT_PRIVACY_ON_CONNECTION = 694;
const uint ERROR_DS_SOURCE_DOMAIN_IN_FOREST = 695;
const uint ERROR_DS_DESTINATION_DOMAIN_NOT_IN_FOREST = 696;
const uint ERROR_DS_DESTINATION_AUDITING_NOT_ENABLED = 697;
const uint ERROR_DS_CANT_FIND_DC_FOR_SRC_DOMAIN = 698;
const uint ERROR_DS_SRC_OBJ_NOT_GROUP_OR_USER = 699;


// Service and RPC Errors (700-999)

const uint ERROR_DS_SRC_SID_EXISTS_IN_FOREST = 700;
const uint ERROR_DS_SRC_AND_DST_OBJECT_CLASS_MISMATCH = 701;
const uint ERROR_SAM_INIT_FAILURE = 702;
const uint ERROR_DS_DRA_SCHEMA_INFO_SHIP = 703;
const uint ERROR_DS_DRA_SCHEMA_CONFLICT = 704;
const uint ERROR_DS_DRA_EARLIER_SCHEMA_CONFLICT = 705;
const uint ERROR_DS_DRA_OBJ_IS_REP_SOURCE = 706;
const uint ERROR_DS_DRA_DB_ERROR = 707;
const uint ERROR_DS_DRA_NO_REPLICA = 708;
const uint ERROR_DS_DRA_ACCESS_DENIED = 709;
const uint ERROR_DS_DRA_NOT_SUPPORTED = 710;
const uint ERROR_DS_DRA_RPC_CANCELLED = 711;
const uint ERROR_DS_DRA_SOURCE_DISABLED = 712;
const uint ERROR_DS_DRA_SINK_DISABLED = 713;
const uint ERROR_DS_DRA_NAME_COLLISION = 714;
const uint ERROR_DS_DRA_SOURCE_REINSTALLED = 715;
const uint ERROR_DS_DRA_MISSING_PARENT = 716;
const uint ERROR_DS_DRA_PREEMPTED = 717;
const uint ERROR_DS_DRA_ABANDON_SYNC = 718;
const uint ERROR_DS_DRA_SHUTDOWN = 719;
const uint ERROR_DS_DRA_INCOMPATIBLE_PARTIAL_SET = 720;
const uint ERROR_DS_DRA_SOURCE_IS_PARTIAL_REPLICA = 721;
const uint ERROR_DS_DRA_EXTN_CONNECTION_FAILED = 722;
const uint ERROR_DS_INSTALL_SCHEMA_MISMATCH = 723;
const uint ERROR_DS_DUP_LINK_ID = 724;
const uint ERROR_DS_NAME_ERROR_RESOLVING = 725;
const uint ERROR_DS_NAME_ERROR_NOT_FOUND = 726;
const uint ERROR_DS_NAME_ERROR_NOT_UNIQUE = 727;
const uint ERROR_DS_NAME_ERROR_NO_MAPPING = 728;
const uint ERROR_DS_NAME_ERROR_DOMAIN_ONLY = 729;
const uint ERROR_DS_NAME_ERROR_NO_SYNTACTICAL_MAPPING = 730;
const uint ERROR_DS_CONSTRUCTED_ATT_MOD = 731;
const uint ERROR_DS_WRONG_OM_OBJ_CLASS = 732;
const uint ERROR_DS_DRA_REPL_PENDING = 733;
const uint ERROR_DS_DS_REQUIRED = 734;
const uint ERROR_DS_INVALID_LDAP_DISPLAY_NAME = 735;
const uint ERROR_DS_NON_BASE_SEARCH = 736;
const uint ERROR_DS_CANT_RETRIEVE_ATTS = 737;
const uint ERROR_DS_BACKLINK_WITHOUT_LINK = 738;
const uint ERROR_DS_EPOCH_MISMATCH = 739;
const uint ERROR_DS_SRC_NAME_MISMATCH = 740;
const uint ERROR_DS_SRC_AND_DST_NC_IDENTICAL = 741;
const uint ERROR_DS_DST_NC_MISMATCH = 742;
const uint ERROR_DS_NOT_AUTHORITIVE_FOR_DST_NC = 743;
const uint ERROR_DS_SRC_GUID_MISMATCH = 744;
const uint ERROR_DS_CANT_MOVE_DELETED_OBJECT = 745;
const uint ERROR_DS_PDC_OPERATION_IN_PROGRESS = 746;
const uint ERROR_DS_CROSS_DOMAIN_CLEANUP_REQD = 747;
const uint ERROR_DS_ILLEGAL_XDOM_MOVE_OPERATION = 748;
const uint ERROR_DS_CANT_WITH_ACCT_GROUP_MEMBERSHPS = 749;
const uint ERROR_DS_NC_MUST_HAVE_NC_PARENT = 750;
const uint ERROR_DS_CR_IMPOSSIBLE_TO_VALIDATE = 751;
const uint ERROR_DS_DST_DOMAIN_NOT_NATIVE = 752;
const uint ERROR_DS_MISSING_INFRASTRUCTURE_CONTAINER = 753;
const uint ERROR_DS_CANT_MOVE_ACCOUNT_GROUP = 754;
const uint ERROR_DS_CANT_MOVE_RESOURCE_GROUP = 755;
const uint ERROR_DS_INVALID_SEARCH_FLAG = 756;
const uint ERROR_DS_NO_TREE_DELETE_ABOVE_NC = 757;
const uint ERROR_DS_COULDNT_LOCK_TREE_FOR_DELETE = 758;
const uint ERROR_DS_COULDNT_IDENTIFY_OBJECTS_FOR_TREE_DELETE = 759;
const uint ERROR_DS_SAM_INIT_FAILURE_CONSOLE = 760;
const uint ERROR_DS_SENSITIVE_GROUP_VIOLATION = 761;
const uint ERROR_DS_CANT_MOD_PRIMARYGROUPID = 762;
const uint ERROR_DS_ILLEGAL_BASE_SCHEMA_MOD = 763;
const uint ERROR_DS_NONSAFE_SCHEMA_CHANGE = 764;
// const uint ERROR_DS_SCHEMA_UPDATE_DISALLOWED = 765;
// const uint ERROR_DS_CANT_CREATE_UNDER_SCHEMA = 766;
// const uint ERROR_DS_INSTALL_NO_SRC_SCH_VERSION = 767;
// const uint ERROR_DS_INSTALL_NO_SCH_VERSION_IN_INIFILE = 768;
// const uint ERROR_DS_INVALID_GROUP_TYPE = 769;
// const uint ERROR_DS_NO_NEST_GLOBALGROUP_IN_MIXEDDOMAIN = 770;
// const uint ERROR_DS_NO_NEST_LOCALGROUP_IN_MIXEDDOMAIN = 771;
// const uint ERROR_DS_GLOBAL_CANT_HAVE_LOCAL_MEMBER = 772;
// const uint ERROR_DS_GLOBAL_CANT_HAVE_UNIVERSAL_MEMBER = 773;
// const uint ERROR_DS_UNIVERSAL_CANT_HAVE_LOCAL_MEMBER = 774;
// const uint ERROR_DS_GLOBAL_CANT_HAVE_CROSSDOMAIN_MEMBER = 775;
// const uint ERROR_DS_LOCAL_CANT_HAVE_CROSSDOMAIN_LOCAL_MEMBER = 776;
// const uint ERROR_DS_HAVE_PRIMARY_MEMBERS = 777;
// const uint ERROR_DS_STRING_SD_CONVERSION_FAILED = 778;
// const uint ERROR_DS_NAMING_MASTER_GC = 779;
// const uint ERROR_DS_DNS_LOOKUP_FAILURE = 780;
// const uint ERROR_DS_COULDNT_UPDATE_SPNS = 781;
// const uint ERROR_DS_CANT_RETRIEVE_SD = 782;
// const uint ERROR_DS_KEY_NOT_UNIQUE = 783;
// const uint ERROR_DS_WRONG_LINKED_ATT_SYNTAX = 784;
// const uint ERROR_DS_SAM_NEED_BOOTKEY_PASSWORD = 785;
// const uint ERROR_DS_SAM_NEED_BOOTKEY_FLOPPY = 786;
// const uint ERROR_DS_CANT_START = 787;
// const uint ERROR_DS_INIT_FAILURE = 788;
// const uint ERROR_DS_NO_PKT_PRIVACY_ON_CONNECTION = 789;
// const uint ERROR_DS_SOURCE_DOMAIN_IN_FOREST = 790;
// const uint ERROR_DS_DESTINATION_DOMAIN_NOT_IN_FOREST = 791;
// const uint ERROR_DS_DESTINATION_AUDITING_NOT_ENABLED = 792;
// const uint ERROR_DS_CANT_FIND_DC_FOR_SRC_DOMAIN = 793;
// const uint ERROR_DS_SRC_OBJ_NOT_GROUP_OR_USER = 794;
// const uint ERROR_DS_SRC_SID_EXISTS_IN_FOREST = 795;
// const uint ERROR_DS_SRC_AND_DST_OBJECT_CLASS_MISMATCH = 796;
// const uint ERROR_SAM_INIT_FAILURE = 797;
// const uint ERROR_DS_DRA_SCHEMA_INFO_SHIP = 798;
// const uint ERROR_DS_DRA_SCHEMA_CONFLICT = 799;
const uint ERROR_IO_PENDING = 997;
const uint ERROR_NOACCESS = 998;

// Network and RPC Errors (1000-1999)

const uint ERROR_INVALID_NETNAME = 1214;
const uint ERROR_GRACEFUL_DISCONNECT = 1226;
const uint ERROR_CONNECTION_ACTIVE = 1230;
const uint ERROR_INVALID_USER_BUFFER = 1784;
const uint ERROR_INVALID_PIXEL_FORMAT = 2000;
const uint ERROR_BAD_DRIVER = 2001;
const uint ERROR_INVALID_WINDOW_STYLE = 2002;
const uint ERROR_METAFILE_NOT_SUPPORTED = 2003;
const uint ERROR_TRANSFORM_NOT_SUPPORTED = 2004;
const uint ERROR_CLIPPING_NOT_SUPPORTED = 2005;
const uint ERROR_INVALID_CMM = 2010;
const uint ERROR_INVALID_PROFILE = 2011;
const uint ERROR_TAG_NOT_FOUND = 2012;
const uint ERROR_TAG_NOT_PRESENT = 2013;
const uint ERROR_DUPLICATE_TAG = 2014;
const uint ERROR_PROFILE_NOT_ASSOCIATED_WITH_DEVICE = 2015;
const uint ERROR_PROFILE_NOT_FOUND = 2016;
const uint ERROR_INVALID_COLORSPACE = 2017;
const uint ERROR_ICM_NOT_ENABLED = 2018;
const uint ERROR_DELETING_ICM_XFORM = 2019;
const uint ERROR_INVALID_TRANSFORM = 2020;
const uint ERROR_COLORSPACE_MISMATCH = 2021;
const uint ERROR_INVALID_COLORINDEX = 2022;
const uint ERROR_PROFILE_DOES_NOT_MATCH_DEVICE = 2023;


// WinSock Errors (10000-11999)

const uint WSAEINTR = 10004;
const uint WSAEBADF = 10009;
const uint WSAEACCES = 10013;
const uint WSAEFAULT = 10014;
const uint WSAEINVAL = 10022;
const uint WSAEMFILE = 10024;
const uint WSAEWOULDBLOCK = 10035;
const uint WSAEINPROGRESS = 10036;
const uint WSAEALREADY = 10037;
const uint WSAENOTSOCK = 10038;
const uint WSAEDESTADDRREQ = 10039;
const uint WSAEMSGSIZE = 10040;
const uint WSAEPROTOTYPE = 10041;
const uint WSAENOPROTOOPT = 10042;
const uint WSAEPROTONOSUPPORT = 10043;
const uint WSAESOCKTNOSUPPORT = 10044;
const uint WSAEOPNOTSUPP = 10045;
const uint WSAEPFNOSUPPORT = 10046;
const uint WSAEAFNOSUPPORT = 10047;
const uint WSAEADDRINUSE = 10048;
const uint WSAEADDRNOTAVAIL = 10049;
const uint WSAENETDOWN = 10050;
const uint WSAENETUNREACH = 10051;
const uint ERROR_NETWORK_UNREACHABLE = 10051;
const uint WSAENETRESET = 10052;
const uint WSAECONNABORTED = 10053;
const uint ERROR_CONNECTION_ABORTED = 10053;
const uint WSAECONNRESET = 10054;
const uint WSAENOBUFS = 10055;
const uint WSAEISCONN = 10056;
const uint WSAENOTCONN = 10057;
const uint WSAESHUTDOWN = 10058;
const uint WSAETOOMANYREFS = 10059;
const uint WSAETIMEDOUT = 10060;
const uint WSAECONNREFUSED = 10061;
const uint ERROR_CONNECTION_REFUSED = 10061;
const uint WSAELOOP = 10062;
const uint WSAENAMETOOLONG = 10063;
const uint WSAEHOSTDOWN = 10064;
const uint ERROR_HOST_DOWN = 10064;
const uint WSAEHOSTUNREACH = 10065;
const uint ERROR_HOST_UNREACHABLE = 10065;
const uint WSAENOTEMPTY = 10066;
const uint WSAEPROCLIM = 10067;
const uint WSAEUSERS = 10068;
const uint WSAEDQUOT = 10069;
const uint WSAESTALE = 10070;
const uint WSAEREMOTE = 10071;
const uint WSASYSNOTREADY = 10091;
const uint WSAVERNOTSUPPORTED = 10092;
const uint WSANOTINITIALISED = 10093;
const uint WSAEDISCON = 10101;
const uint WSAENOMORE = 10102;
const uint WSAECANCELLED = 10103;
const uint WSAEINVALIDPROCTABLE = 10104;
const uint WSAEINVALIDPROVIDER = 10105;
const uint WSAEPROVIDERFAILEDINIT = 10106;
const uint WSASYSCALLFAILURE = 10107;
const uint WSASERVICE_NOT_FOUND = 10108;
const uint WSATYPE_NOT_FOUND = 10109;
const uint WSA_E_NO_MORE = 10110;
const uint WSA_E_CANCELLED = 10111;
const uint WSAEREFUSED = 10112;
const uint WSAHOST_NOT_FOUND = 11001;
const uint WSATRY_AGAIN = 11002;
const uint WSANO_RECOVERY = 11003;
const uint WSANO_DATA = 11004;
const uint WSA_QOS_RECEIVERS = 11005;
const uint WSA_QOS_SENDERS = 11006;
const uint WSA_QOS_NO_SENDERS = 11007;
const uint WSA_QOS_NO_RECEIVERS = 11008;
const uint WSA_QOS_REQUEST_CONFIRMED = 11009;
const uint WSA_QOS_ADMISSION_FAILURE = 11010;
const uint WSA_QOS_POLICY_FAILURE = 11011;
const uint WSA_QOS_BAD_STYLE = 11012;
const uint WSA_QOS_BAD_OBJECT = 11013;
const uint WSA_QOS_TRAFFIC_CTRL_ERROR = 11014;
const uint WSA_QOS_GENERIC_ERROR = 11015;
const uint WSA_QOS_ESERVICETYPE = 11016;
const uint WSA_QOS_EFLOWSPEC = 11017;
const uint WSA_QOS_EPROVSPECBUF = 11018;
const uint WSA_QOS_EFILTERSTYLE = 11019;
const uint WSA_QOS_EFILTERTYPE = 11020;
const uint WSA_QOS_EFILTERCOUNT = 11021;
const uint WSA_QOS_EOBJLENGTH = 11022;
const uint WSA_QOS_EFLOWCOUNT = 11023;
const uint WSA_QOS_EUNKOWNPSOBJ = 11024;
const uint WSA_QOS_EPOLICYOBJ = 11025;
const uint WSA_QOS_EFLOWDESC = 11026;
const uint WSA_QOS_EPSFLOWSPEC = 11027;
const uint WSA_QOS_EPSFILTERSPEC = 11028;
const uint WSA_QOS_ESDMODEOBJ = 11029;
const uint WSA_QOS_ESHAPERATEOBJ = 11030;
const uint WSA_QOS_RESERVED_PETYPE = 11031;

// Additional Windows ERROR_ constants used by c::wepoll

const uint ERROR_OPERATION_ABORTED = 995;
const uint ERROR_NOT_FOUND = 1168;

const uint ERROR_PORT_UNREACHABLE = 1234;
const uint ERROR_PROTOCOL_UNREACHABLE = 1233;
const uint ERROR_REQUEST_ABORTED = 1235;

const uint ERROR_NO_SYSTEM_RESOURCES = 1450;
const uint ERROR_NONPAGED_SYSTEM_RESOURCES = 1451;
const uint ERROR_PAGED_SYSTEM_RESOURCES = 1452;
const uint ERROR_WORKING_SET_QUOTA = 1453;
const uint ERROR_PAGEFILE_QUOTA = 1454;
const uint ERROR_NOT_ENOUGH_QUOTA = 1816;

// eof