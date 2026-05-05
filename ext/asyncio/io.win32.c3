// io.win32.c3

module ext::asyncio @if(env::WIN32) @link("ws2_32");

import std::io;
import std::collections::map;
import c::stdio;
import c::stdlib;
import c::string;
import c::winbase;
import c::winsock2;
import c::ws2tcpip;
import c::errno;
import ext::debug;
import ext::mem;

const usz MAX_EVENTS = 1024;
const usz MAX_FD_WATCH = 2048;

const usz IOCP_OP_POOL = 1024;   // maximum OVERLAPPED tasks
// IOCP_BUF_SIZE removed: I/O buffers are caller-provided.

// On completion, OS returns Overlapped* as the first field.
// Access other fields by casting to IocpOp*.
// Overlapped must be the first in struct.
//
// Buffers (read targets, write sources) are caller-provided and must
// remain valid for the duration of the I/O — i.e. until the awaiting
// fiber's `await` returns.  The typical caller holds the buffer on
// its own fiber stack or heap, which naturally satisfies this.
//
// CAVEAT: `unregister(fd)` cancels the awaiting future preemptively
// (before the kernel's abort packet has been dequeued from IOCP).
// If a caller frees its buffer right after that cancel, the kernel
// may still write to it once the abort completion arrives.  To make
// this fully safe, defer `fut.cancel()` to io_poll (when the abort
// packet is observed) — left as a follow-up.

struct IocpOp {
    winbase::Overlapped ov; // must be first
    bool active;
    bool is_write;
    bool is_socket; // true=socket(WSARecv/Send), false=file(ReadFile/WriteFile)
    bool is_recvfrom;
    winbase::Handle handle;
    Future* future;

    winbase::DWord transferred;  // bytes transferred

    // for sockets (WSARecv / WSASend / WSARecvFrom / WSASendTo)
    winsock2::WSABuf wsabuf;
    winbase::DWord flags;

    // for recvfrom
    winsock2::SockAddrStorage from_addr;
    int from_len;

    // bool cancel_requested;

    ulong file_offset;
}

tlocal IocpOp[IOCP_OP_POOL] _op_pool;
tlocal winbase::Handle _iocp;

// IOCP op pool manage
tlocal usz _active_op_count;

fn IocpOp* _op_alloc()
{
    for (usz i = 0; i < IOCP_OP_POOL; i++) {
        if (!_op_pool[i].active) {
            string::memset(&_op_pool[i], 0, IocpOp.sizeof);
            _op_pool[i].active = true;
            _active_op_count++;
            return &_op_pool[i];
        }
    }
    @assert(false, "asyncio/iocp: operation pool exhausted");
    return null;
}

fn void _op_free(IocpOp* op)
{
    op.active = false;
    _active_op_count--;
}

// Handle Type identification
// GetFileType() == FILE_TYPE_PIPE -> pipe
// GetFileType() == FILE_TYPE_DISK -> file
// GetFileType() == FILE_TYPE_CHAR -> terminal
// For socket, GetFileType returns FILE_TYPE_UNKNOWN, WSASocket

fn bool _is_socket(winbase::Handle h)
{
    // getsockopt returns WSAENOTSOCK if no socket
    int err = 0;
    int len = $sizeof(err);
    int rc  = winsock2::getsockopt((winsock2::Socket)h, winsock2::SOL_SOCKET, winsock2::SO_ERROR, (char*)&err, &len);
    if (rc == 0) return true;
    if (winsock2::wsaGetLastError() == winsock2::WSAENOTSOCK) return false;
    @assert(false, "getsockopt() failed");
    return false;
}

// connect handle to iocp
tlocal HashMap{int, bool} _iocp_assoc;
fn bool _iocp_associate(winbase::Handle h)
{
    int key = (int)(iptr)h;
    // already associated: skip re-registration
    if (try _iocp_assoc[key]) return true;

    winbase::Handle result = winbase::createIoCompletionPort(
        h, _iocp,
        (uptr)h, // completion key = handle itself
        0);
    if (result == null) return false;

    _iocp_assoc[key] = true;
    return true;
}

tlocal bool initialized = false;
fn void io_init()
{
    if (initialized) return;
    initialized = true;

    // Winsock initialize
    winsock2::WSAData wsa;
    @assert(winsock2::wsaStartup(0x0202, &wsa) == 0, "asyncio: WSAStartup failed");

    // create IOCP (threads 1)
    _iocp = winbase::createIoCompletionPort(winbase::INVALID_HANDLE_VALUE, null, 0, 1);
    @assert(_iocp != null, "asyncio: CreateIoCompletionPort failed");
}

tlocal bool _io_shutting_down = false;

fn void io_destroy()
{
    if (!initialized) return;

    // 1. no more I/O
    _io_shutting_down = true;

    // 2. all pending handle, CancelIoEx
    for (usz i = 0; i < IOCP_OP_POOL; i++) {
        if (!_op_pool[i].active) continue;

        winbase::Handle h = _op_pool[i].handle;
        if (h != null && h != winbase::INVALID_HANDLE_VALUE) {
            // duplicate allowed
            winbase::cancelIoEx(h, null);
        }
    }

    // 3. completion drain
    while (_active_op_count > 0) {
        winbase::OverlappedEntry[MAX_EVENTS] entries;
        winbase::ULong removed = 0;

        winbase::Bool ok = winbase::getQueuedCompletionStatusEx(
            _iocp,
            &entries[0],
            MAX_EVENTS,
            (ulong*)&removed,
            50, // ms
            winbase::FALSE
        );

        if (!ok && removed == 0) {
            continue;
        }

        for (winbase::ULong i = 0; i < removed; i++) {
            winbase::Overlapped* ov = entries[i].lpOverlapped;
            if (ov == null) continue;

            IocpOp* op = (IocpOp*)ov;
            if (!op.active) continue;

            Future* fut = op.future;
            op.transferred = entries[i].dwNumberOfBytesTransferred;

            if (fut != null && !fut.done()) {
                fut.set_exception(IO_ERROR);
                fut.cancel("io destroyed");
            }

            _op_free(op);
        }
    }

    // 4. _active_op_count == 0
    @assert(_active_op_count == 0, "asyncio/win32: pending IOCP ops remain at destroy");

    winbase::closeHandle(_iocp);
    _iocp = null;

    winsock2::wsaCleanup();
    initialized = false;
    _io_shutting_down = false;
}

fn bool set_nonblocking(int fd)
{
    winbase::Handle h = (winbase::Handle) (iptr)fd;
    if (_is_socket(h)) {
        // Win32 IOCP/OVERLAPPED sockets should stay in blocking mode.

        // uint mode = 1;
        // return winsock2::ioctlsocket((winsock2::Socket)fd, winsock2::FIONBIO, &mode) == 0;
    }
    return true; // For files, OVERLAPPED is nonblocking
}



// Public API

fn void register_read(int fd, void* buf, usz len, Future* future, ulong offset) @private
{
    if (_io_shutting_down) {
        future.set_exception(IO_ERROR);
        future.cancel("io shutting down");
        return;
    }

    winbase::Handle h = (winbase::Handle)(iptr)fd;
    bool is_sock = _is_socket(h);

    IocpOp* op = _op_alloc();
    op.is_write = false;
    op.is_socket = is_sock;
    op.handle = h;
    op.future = future;
    op.file_offset = offset;

    if (!_iocp_associate(h)) {
        future.set_exception(IO_ERROR);
        future.cancel("iocp associate failed");
        _op_free(op);
        return;
    }

    if (is_sock) {
        op.wsabuf.buf = buf;                       // caller buffer
        op.wsabuf.len = (winbase::DWord)len;
        op.flags = 0;
        int rc = winsock2::wsaRecv((winsock2::Socket)h, &op.wsabuf, 1, null, &op.flags, &op.ov, null);
        if (rc == 0) return;
        if (winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING) {
            future.set_exception(IO_ERROR);
            future.cancel("io error");
            _op_free(op);
        }
    } else {
        ulong pos = io_tell((int)(iptr)h);
        op.ov.offset = (uint)pos;
        op.ov.offsetHigh = (uint)(pos >> 32);

        winbase::Bool rc = winbase::readFile(h, buf, (winbase::DWord)len, null, &op.ov); // caller buffer
        if (rc) return;
        if (winbase::getLastError() != winbase::ERROR_IO_PENDING) {
            future.set_exception(IO_ERROR);
            future.cancel("io error");
            _op_free(op);
        }

        // IO_PENDING: return immediately, io_poll will resolve the future
    }
}

fn void register_write(int fd, Future* future) @private
{
    @assert(false, "not used on win32/iocp");
}

fn void _start_write(int fd, void* data, usz len, Future* future, ulong offset)
{
    if (_io_shutting_down) {
        future.set_exception(IO_ERROR);
        future.cancel("io shutting down");
        return;
    }

    winbase::Handle h = (winbase::Handle)(iptr)fd;
    bool is_sock = _is_socket(h);

    IocpOp* op = _op_alloc();
    op.is_write = true;
    op.is_socket = is_sock;
    op.handle = h;
    op.future = future;
    op.file_offset = offset;

    if (!is_sock) {
        op.ov.offset = (winbase::DWord)(offset & 0xFFFFFFFF);
        op.ov.offsetHigh = (winbase::DWord)(offset >> 32);
    }

    // No memcpy: caller's buffer is passed directly to the kernel.

    if (!_iocp_associate(h)) {
        future.set_exception(IO_ERROR);
        future.cancel("iocp associate failed");
        _op_free(op);
        return;
    }

    if (is_sock) {
        op.wsabuf.buf = data;                       // caller buffer
        op.wsabuf.len = (winbase::DWord)len;
        int rc = winsock2::wsaSend((winsock2::Socket)h, &op.wsabuf, 1, null, 0, &op.ov, null);
        if (rc == 0) return;
        if (winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING) {
            future.set_exception(IO_ERROR);
            future.cancel("io error");
            _op_free(op);
        }
    } else {
        ulong pos = io_tell((int)(iptr)h);
        op.ov.offset = (uint)pos;
        op.ov.offsetHigh = (uint)(pos >> 32);
        winbase::Bool rc = winbase::writeFile(h, data, (winbase::DWord)len, null, &op.ov); // caller buffer
        if (rc) return;
        if (winbase::getLastError() != winbase::ERROR_IO_PENDING) {
            future.set_exception(IO_ERROR);
            future.cancel("io error");
            _op_free(op);
        }

        // IO_PENDING: return immediately, io_poll will resolve the future
    }
}


fn void unregister(int fd)
{
    _iocp_assoc.remove(fd);

    winbase::Handle h = (winbase::Handle)(iptr)fd;

    winbase::cancelIoEx((winbase::Handle)(iptr)fd, null);

    for (usz i = 0; i < IOCP_OP_POOL; i++) {
        if (_op_pool[i].active && _op_pool[i].handle == h) {
            _op_pool[i].future.cancel("fd unregistered");
            // _op_pool[i].cancel_requested = true;
            // _op_free, on abort completion packet arrive at poll()
        }
    }
}

fn bool io_pending() @inline
{
    return _active_op_count > 0;
}


fn void io_poll(ulong timeout_us)
{
    if (_active_op_count == 0) return;

    winbase::OverlappedEntry[MAX_EVENTS] entries;
    winbase::ULong removed = 0;

    winbase::DWord timeout_ms = (timeout_us / 1000 > 0xFFFFFFFE) ? winbase::INFINITE : (winbase::DWord)(timeout_us / 1000);
    winbase::Bool ok = winbase::getQueuedCompletionStatusEx(_iocp, &entries[0], MAX_EVENTS, (ulong*)&removed, timeout_ms, winbase::FALSE);

    if (!ok && removed == 0) return;

    for (winbase::ULong i = 0; i < removed; i++) {
        winbase::Overlapped* ov = entries[i].lpOverlapped;
        if (ov == null) continue;

        IocpOp* op = (IocpOp*)ov;
        if (!op.active) {
            continue;
        }

        winbase::DWord transferred = entries[i].dwNumberOfBytesTransferred;
        op.transferred = transferred;

        Future* fut = op.future;
        if (fut.done()) {
            _op_free(op);   // cancelIoEx abort packet: future is already cancelled
            continue;
        }

        if (transferred > 0) {
            fut.set_result((void*)op); // Alert! non-heap value, don't free fut.await() result
            continue;
        }

        if (!op.is_write) {
            fut.set_result(null); // EOF: caller gets read() == 0
        } else {
            fut.set_exception(IO_ERROR);
        }
        _op_free(op);
    }
}

fn usz? async_read(int fd, void* out_buf, usz max_len)
{
    EventLoop* loop = asyncio::get_running_loop();

    Future* fut = loop.create_future();
    register_read(fd, out_buf, max_len, fut, 0);

    void*? raw  = fut.await();
    fault ferror = fut.error;

    fut.result = null; // non-allocated
    fut.free();

    if (catch err = raw) {
        if (ferror == IO_ERROR) return IO_ERROR~;
        return err~;
    }
    if (raw == null) return 0;  // EOF (null = 0 bytes transferred)

    IocpOp* op = (IocpOp*)raw;
    winbase::DWord n = op.transferred;
    if (n > (winbase::DWord)max_len) n = (winbase::DWord)max_len;

    // No memcpy: kernel wrote directly into out_buf.

    // Update file position
    curPos[fd] = ((ulong)op.ov.offsetHigh << 32 | op.ov.offset) + n;

    _op_free(op);
    return (usz)n;
}

fn usz? async_write(int fd, void* buf, usz len)
{
    EventLoop* loop = asyncio::get_running_loop();
    ulong offset = 0;
    usz total = 0;
    while (total < len) {
        Future* fut = loop.create_future();
        _start_write(fd, (char*)buf + total, len - total, fut, offset);

        void*? raw = fut.await();
        fault ferror = fut.error;

        fut.result = null; // non-allocated
        fut.free();

        if (catch err = raw) {
            if (total > 0) return total;
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }

        if (raw == null) {
            if (total > 0) return total;
            return IO_ERROR~;
        }

        IocpOp* op = (IocpOp*)raw;
        winbase::DWord written = op.transferred;

        // Update file position
        curPos[fd] = ((ulong)op.ov.offsetHigh << 32 | op.ov.offset) + written;

        _op_free(op);

        total += (usz)written;
        offset += (ulong)written;
    }
    return total;
}

fn void _start_recvfrom(int fd, void* buf, usz len, Future* future)
{
    if (_io_shutting_down) {
        future.set_exception(IO_ERROR);
        future.cancel("io shutting down");
        return;
    }

    winbase::Handle h = (winbase::Handle)(iptr)fd;

    IocpOp* op = _op_alloc();
    op.is_write  = false;
    op.is_socket = true;
    op.handle = h;
    op.future = future;
    op.flags = 0;
    op.from_len = winsock2::SockAddrStorage.sizeof;

    op.wsabuf.buf = buf;                            // caller buffer
    op.wsabuf.len = (winbase::DWord)len;

    if (!_iocp_associate(h)) {
        future.set_exception(IO_ERROR);
        future.cancel("iocp associate failed");
        _op_free(op);
        return;
    }

    int rc = winsock2::wsaRecvFrom(
        (winsock2::Socket)h,
        &op.wsabuf, 1,
        null, &op.flags,
        (winsock2::SockAddr*)&op.from_addr, &op.from_len,
        &op.ov, null
    );
    if (rc == 0) return;
    if (winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING) {
        future.set_exception(IO_ERROR);
        future.cancel("io error");
        _op_free(op);
    }
}

fn usz? async_recvfrom(int fd, void* buf, usz len, char* ip_str, usz* ip_len, ushort* port)
{
    EventLoop* loop = asyncio::get_running_loop();

    Future* fut = loop.create_future();
    _start_recvfrom(fd, buf, len, fut);

    void*? raw = fut.await();
    fault ferror = fut.error;

    fut.result = null; // non-allocated
    fut.free();

    if (catch err = raw) {
        if (ferror == IO_ERROR) return IO_ERROR~;
        return err~;
    }
    if (raw == null) return IO_ERROR~;

    IocpOp* op = (IocpOp*)raw;
    winbase::DWord n = op.transferred;
    if (n > (winbase::DWord)len) n = (winbase::DWord)len;

    // No memcpy: kernel wrote directly into caller's buf.

    // extract sender addr
    if (ip_str != null || port != null) {
        ushort family = ((winsock2::SockAddrIn*)&op.from_addr).sin_family;
        if (family == (ushort)winsock2::AF_INET6) {
            winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)&op.from_addr;
            ws2tcpip::inet_ntop(winsock2::AF_INET6, &a6.sin6_addr, ip_str, 46);
            *ip_len = (usz)string::strlen(ip_str);
            *port = winsock2::ntohs(a6.sin6_port);
        } else {
            winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)&op.from_addr;
            ws2tcpip::inet_ntop(winsock2::AF_INET, &a4.sin_addr, ip_str, 16);
            *ip_len = (usz)string::strlen(ip_str);
            *port = winsock2::ntohs(a4.sin_port);
        }
    }

    _op_free(op);
    return (usz)n;
}

fn usz? async_sendto(int fd, void* buf, usz len, char* ip_str, ushort port)
{
   EventLoop* loop = asyncio::get_running_loop();

    winsock2::SockAddr* dest_addr;
    int dest_len;
    winsock2::SockAddrIn a4 = {};
    winsock2::SockAddrIn6 a6 = {};

    if (ws2tcpip::inet_pton(winsock2::AF_INET6, ip_str, &a6.sin6_addr) == 1) {
        a6.sin6_family = (ushort)winsock2::AF_INET6;
        a6.sin6_port = winsock2::htons(port);
        dest_addr = (winsock2::SockAddr*)&a6;
        dest_len = $sizeof(a6);
    } else if (ws2tcpip::inet_pton(winsock2::AF_INET, ip_str, &a4.sin_addr) == 1) {
        a4.sin_family = (ushort)winsock2::AF_INET;
        a4.sin_port = winsock2::htons(port);
        dest_addr = (winsock2::SockAddr*)&a4;
        dest_len = $sizeof(a4);
    } else {
        return IO_ERROR~;
    }

    usz total = 0;
    while (total < len) {
        IocpOp* op = _op_alloc();
        op.is_write = true;
        op.is_socket = true;
        op.handle = (winbase::Handle)(iptr)fd;
        op.flags = 0;

        // No memcpy: caller buffer used directly, sliced by current offset.
        op.wsabuf.buf = (char*)buf + total;
        op.wsabuf.len = (winbase::DWord)(len - total);

        _iocp_associate(op.handle);

        Future* fut = loop.create_future();
        op.future = fut;

        int rc = winsock2::wsaSendTo(
            (winsock2::Socket)fd,
            &op.wsabuf, 1,
            null, 0,
            dest_addr, dest_len,
            &op.ov, null
        );
        if (rc != 0 && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING) {
            fut.free();
            _op_free(op);
            return total > 0 ? total : IO_ERROR~;
        }

        void*? raw = fut.await();
        fault ferror = fut.error;

        fut.result = null; // non-allocated
        fut.free();

        if (catch err = raw) {
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        if (raw == null) return total > 0 ? total : IO_ERROR~;

        IocpOp* completed = (IocpOp*)raw;
        total += (usz)completed.transferred;
        _op_free(completed);
    }
    return total;
}

// additional functions window specific

fn Char16*? utf8to16(String path, Char16[] wpath) @private
{
    if (path.len == 0) return errno::F_INVAL~;
    Char16[] p2 = path.to_utf16(tmem)!;
    //defer free(p2);

    if (p2.len >= wpath.len-1) return errno::F_BAD_LENGTH~;

    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;
    for (usz i = 0; i < p2.len; i++) {
        if (p2[i] == (Char16)'/') {
            wpath[i] = (Char16)'\\';
        }
    }

    return wpath.ptr;
}

fn int? open_file(String path, String mode)
{
    winbase::DWord access = 0;
    winbase::DWord disposition = 0;
    winbase::DWord attributes = winbase::FILE_ATTRIBUTE_NORMAL;

    if (mode == "r") {
        access = winbase::GENERIC_READ;
        disposition = winbase::OPEN_EXISTING;
    } else if (mode == "r+") {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::OPEN_EXISTING;
    } else if (mode == "w") {
        access = winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    } else if (mode == "w+") {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    } else if (mode == "a") {
        access = winbase::FILE_APPEND_DATA; // or GENERIC_WRITE
        disposition = winbase::OPEN_ALWAYS;
    } else if (mode == "a+") {
        access = winbase::GENERIC_READ | winbase::FILE_APPEND_DATA;
        disposition = winbase::OPEN_ALWAYS;
    } else {
        return errno::E_INVALID_ARG~;
    }

    // Overlapped IO for asynchronous
    winbase::DWord flags = attributes | winbase::FILE_FLAG_OVERLAPPED;

    winbase::DWord share = winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE | winbase::FILE_SHARE_DELETE;

    Char16[260] wbuf;
    Char16*? wpath = utf8to16(path, &wbuf);
    if (catch err = wpath) {
        return err~;
    }

    winbase::Handle h = winbase::createFileW(wpath, access, share, null, disposition, flags, null);
    if (h == winbase::INVALID_HANDLE_VALUE) {
        return errno::get_fault()~;
    }

    // For append mode, seek to end
    if (mode[0] == 'a') {
        // windows::setFilePointerEx(h, 0, null, windows::FILE_END);
        winbase::Overlapped ol = {};
        ol.offset = 0xFFFFFFFF;     // Special value for "End of File"
        ol.offsetHigh = 0xFFFFFFFF;
        long file_size;
        winbase::getFileSizeEx(h, &file_size);
        curPos[(int)(iptr)h] = file_size;
    }

    return (int) (iptr) h;
}

struct PipePair {
    int read_fd;
    int write_fd;
    winbase::Overlapped _pipe_conn_ov;
}

// tlocal winbase::Overlapped _pipe_conn_ov;
tlocal int static_counter = 0;
fn PipePair? create_pipe_async()
{
    winbase::SecurityAttributes sa;
    sa.nLength = $sizeof(sa);
    sa.lpSecurityDescriptor = null;
    sa.bInheritHandle = winbase::TRUE;

    winbase::Handle rh;
    winbase::Handle wh;

    char[64] name;
    winbase::DWord pid = winbase::getCurrentProcessId();
    static_counter += 1;
    stdio::sprintf(&name[0], "\\\\.\\pipe\\asyncio_%lu_%lu", pid, (winbase::DWord)static_counter);

    rh = winbase::createNamedPipeA(&name[0], winbase::PIPE_ACCESS_INBOUND | winbase::FILE_FLAG_OVERLAPPED, winbase::PIPE_TYPE_BYTE | winbase::PIPE_READMODE_BYTE | winbase::PIPE_WAIT, 1, 65536, 65536, 0, &sa);

    // set async connect waiting, before CreateFile wh
    // _pipe_conn_ov = {};
    winbase::Overlapped _pipe_conn_ov = {};

    winbase::Bool b = winbase::connectNamedPipe(rh, &_pipe_conn_ov);   // OVERLAPPED, returns immediately
    if (b != winbase::TRUE) {
        winbase::DWord err = winbase::getLastError();
        if (err != winbase::ERROR_IO_PENDING && err != winbase::ERROR_PIPE_CONNECTED) {
            return IO_ERROR~;
        }
    }

    wh = winbase::createFileA(&name[0], winbase::GENERIC_WRITE, 0, &sa, winbase::OPEN_EXISTING, winbase::FILE_ATTRIBUTE_NORMAL | winbase::FILE_FLAG_OVERLAPPED, null);

    return { (int)(iptr)rh, (int)(iptr)wh, _pipe_conn_ov };
}

fn void close_file(int fd)
{
    unregister(fd);
    curPos.remove(fd);

    if (_is_socket((winbase::Handle)(iptr)fd)) {
        winsock2::closesocket((winsock2::Socket)(iptr)fd);
    } else {
        winbase::closeHandle((winbase::Handle)(iptr)fd);
    }
}

// off_t = long

tlocal HashMap{int,long} curPos; // remembers current position after every file operation

fn long io_seek(int fd, long pos, int whence)
{
    if (whence == 0) { // SEEK_SET
        curPos[fd] = pos;
    } else if (whence == 1) {
        curPos[fd] += pos;
    } else {
        long size;
        winbase::getFileSizeEx((winbase::Handle)(iptr)fd, &size);
        curPos[fd] = size+pos;
    }
    return (long)io_tell(fd);
}

fn long io_tell(int fd)
{
    long? pos = curPos[fd];
    if (catch err = pos) {
        return 0;
    }
    return pos;;
}

fn int io_truncate(int fd, long pos)
{
    winbase::setFilePointerEx((winbase::Handle)(iptr)fd, pos, null, winbase::FILE_BEGIN);
    winbase::setEndOfFile((winbase::Handle)(iptr)fd);
    return 0;
}

fn void io_flush(int fd)
{
    winbase::flushFileBuffers((winbase::Handle) (iptr)fd);
}

fn long io_size(int fd)
{
    long size;
    winbase::getFileSizeEx((winbase::Handle) (iptr)fd, &size);
    return (long) size;
}

fn int io_stdin()
{
   // winbase::Handle h = winbase::getStdHandle(winbase::STD_INPUT_HANDLE);

    winbase::Handle h = winbase::createFileA(
        "CONIN$",
        winbase::GENERIC_READ,
        winbase::FILE_SHARE_READ,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    return (int)(iptr)h;
}

fn int io_stdout()
{
    // winbase::Handle h = winbase::getStdHandle(winbase::STD_OUTPUT_HANDLE);

    winbase::Handle h = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    return (int)(iptr)h;
}

fn int io_stderr()
{
    // winbase::Handle h = winbase::getStdHandle(winbase::STD_ERROR_HANDLE);

    winbase::Handle h = winbase::createFileA(
        "CONOUT$", // CONERR$ not exists
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    return (int)(iptr)h;
}
