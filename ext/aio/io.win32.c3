// io.win32.c3

module ext::aio::io @if(env::WIN32) @link("ws2_32");

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
import ext::aio;

alias Fd = winbase::Handle;

macro bool fd_invalid(Fd fd)
{
    return fd == null || fd == winbase::INVALID_HANDLE_VALUE;
}

macro Fd fd_null()
{
    return winbase::INVALID_HANDLE_VALUE;
}

const usz MAX_EVENTS = 4096;
const usz MAX_FD_WATCH = 20_000;
const usz IOCP_OP_POOL = 4096;

const uptr IOCP_WAKE_KEY = 1;

struct IocpOp
{
    winbase::Overlapped ov; // must be first

    bool active;
    bool is_write;
    bool is_socket;
    bool is_recvfrom;
    bool is_accept;
    bool is_connect;
    bool cancel_requested;

    winbase::Handle handle;
    Future* future;

    winbase::DWord transferred;

    winsock2::WSABuf wsabuf;
    winbase::DWord flags;

    winsock2::SockAddrStorage from_addr;
    int from_len;

    char[128] addr_buf;
}

struct Context @local
{
    IocpOp[IOCP_OP_POOL] op_pool;
    winbase::Handle iocp;

    usz active_op_count;

    HashMap{Fd, bool} iocp_assoc;
    HashMap{Fd, bool} socket_fds;

    bool io_shutting_down;

    winbase::OverlappedEntry[MAX_EVENTS] entries;
}

tlocal Context* ctx @local = null;

faultdef NONE;

struct Arg @local
{
    fault error;
    Fd fd;
    String name;
    String mode;
    long pos;
    int whence;
    long offset;
    int rc;
    char[] buf;
    usz result;
}

fn IocpOp* op_alloc()
{
    @assert(ctx != null);

    for (usz i = 0; i < IOCP_OP_POOL; i++) 
    {
        if (!ctx.op_pool[i].active)
        {
            string::memset(&ctx.op_pool[i], 0, IocpOp.sizeof);
            ctx.op_pool[i].active = true;
            ctx.active_op_count++;
            return &ctx.op_pool[i];
        }
    }

    @assert(false, "aio/iocp: operation pool exhausted");
    return null;
}

fn void op_free(IocpOp* op)
{
    if (op == null) return;

    @assert(op.active, "aio/iocp: double op_free");

    op.active = false;
    ctx.active_op_count--;
}

fn bool fd_is_socket(Fd fd)
{
    if (fd_invalid(fd)) return false;
    if (ctx == null) return false;

    return ctx.socket_fds[fd] ?? false;
}

fn void fd_set_socket(Fd fd, bool is_sock)
{
    if (fd_invalid(fd)) return;
    if (ctx == null) return;

    ctx.socket_fds[fd] = is_sock;
}

fn bool iocp_associate(Fd fd)
{
    if (fd_invalid(fd)) return false;
    if (try ctx.iocp_assoc[fd]) return true;

    winbase::Handle result = winbase::createIoCompletionPort(
        fd,
        ctx.iocp,
        (uptr)fd,
        0
    );

    if (result == null) return false;

    ctx.iocp_assoc[fd] = true;
    return true;
}

fn void init()
{
    if (ctx != null) return;

    aio::init();

    ctx = aio::localmem.alloc(Context)!!;
    *ctx = {
        .iocp = null,
        .active_op_count = 0,
        .io_shutting_down = false,
    };

    ctx.iocp_assoc.init(aio::localmem);
    ctx.socket_fds.init(aio::localmem);

    winsock2::WSAData wsa;
    @assert(winsock2::wsaStartup(0x0202, &wsa) == 0, "aio: WSAStartup failed");

    ctx.iocp = winbase::createIoCompletionPort(winbase::INVALID_HANDLE_VALUE, null, 0, 1);
    @assert(ctx.iocp != null, "aio: CreateIoCompletionPort failed");
}

fn void deinit()
{
    if (ctx == null) return;

    ctx.io_shutting_down = true;

    for (usz i = 0; i < IOCP_OP_POOL; i++) 
    {
        if (!ctx.op_pool[i].active) continue;

        Fd fd = ctx.op_pool[i].handle;
        if (!fd_invalid(fd))
        {
            winbase::cancelIoEx(fd, null);
        }
    }

    while (ctx.active_op_count > 0)
    {
        winbase::ULong removed = 0;

        winbase::Bool ok = winbase::getQueuedCompletionStatusEx(
            ctx.iocp,
            &ctx.entries[0],
            MAX_EVENTS,
            (ulong*)&removed,
            50,
            winbase::FALSE
        );

        if (!ok && removed == 0) continue;

        for (winbase::ULong i = 0; i < removed; i++)
        {
            winbase::Overlapped* ov = ctx.entries[i].lpOverlapped;
            if (ov == null) continue;

            IocpOp* op = (IocpOp*)ov;
            if (!op.active) continue;

            Future* fut = op.future;
            op.transferred = ctx.entries[i].dwNumberOfBytesTransferred;

            if (fut != null && !fut.done())
            {
                fut.cancel(aio::IO_ERROR);
            }

            op_free(op);
        }
    }

    @assert(ctx.active_op_count == 0, "aio/win32: pending IOCP ops remain at destroy");

    if (ctx.iocp != null)
    {
        winbase::closeHandle(ctx.iocp);
    }

    winsock2::wsaCleanup();

    ctx.iocp_assoc.free();
    ctx.socket_fds.free();

    aio::localmem.free(ctx);
    ctx = null;
}

fn bool set_nonblocking(Fd fd)
{
    return true;
}

fn void register_read(Fd fd, void* buf, usz len, Future* future) @private
{
    if (ctx.io_shutting_down)
    {
        future.cancel(aio::IO_ERROR);
        return;
    }

    IocpOp* op = op_alloc();
    op.is_write = false;
    op.is_socket = fd_is_socket(fd);
    op.handle = fd;
    op.future = future;

    if (!iocp_associate(fd))
    {
        future.cancel(aio::IO_ERROR);
        op_free(op);
        return;
    }

    if (op.is_socket)
    {
        op.wsabuf.buf = buf;
        op.wsabuf.len = (winbase::DWord)len;
        op.flags = 0;

        int rc = winsock2::wsaRecv(
            (winsock2::Socket)fd,
            &op.wsabuf,
            1,
            null,
            &op.flags,
            &op.ov,
            null
        );

        if (rc == 0) return;

        if (winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
        {
            future.cancel(aio::IO_ERROR);
            op_free(op);
        }

        return;
    }

    winbase::Bool rc = winbase::readFile(
        fd,
        buf,
        (winbase::DWord)len,
        null,
        &op.ov
    );

    if (rc) return;

    if (winbase::getLastError() != winbase::ERROR_IO_PENDING)
    {
        future.cancel(aio::IO_ERROR);
        op_free(op);
    }
}

fn void register_write(Fd fd, Future* future) @private
{
    @assert(false, "not used on win32/iocp");
}

fn void start_write(Fd fd, void* data, usz len, Future* future) @private
{
    if (ctx.io_shutting_down)
    {
        future.cancel(aio::IO_ERROR);
        return;
    }

    IocpOp* op = op_alloc();
    op.is_write = true;
    op.is_socket = fd_is_socket(fd);
    op.handle = fd;
    op.future = future;

    if (!iocp_associate(fd))
    {
        future.cancel(aio::IO_ERROR);
        op_free(op);
        return;
    }

    if (op.is_socket)
    {
        op.wsabuf.buf = data;
        op.wsabuf.len = (winbase::DWord)len;

        int rc = winsock2::wsaSend(
            (winsock2::Socket)fd,
            &op.wsabuf,
            1,
            null,
            0,
            &op.ov,
            null
        );

        if (rc == 0) return;

        if (winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
        {
            future.cancel(aio::IO_ERROR);
            op_free(op);
        }

        return;
    }

    winbase::Bool rc = winbase::writeFile(
        fd,
        data,
        (winbase::DWord)len,
        null,
        &op.ov
    );

    if (rc) return;

    if (winbase::getLastError() != winbase::ERROR_IO_PENDING)
    {
        future.cancel(aio::IO_ERROR);
        op_free(op);
    }
}

fn void unregister(Fd fd) @private
{
    if (ctx == null) return;
    if (fd_invalid(fd)) return;

    ctx.iocp_assoc.remove(fd);

    winbase::cancelIoEx(fd, null);

    for (usz i = 0; i < IOCP_OP_POOL; i++)
    {
        IocpOp* op = &ctx.op_pool[i];

        if (op.active && op.handle == fd)
        {
            op.cancel_requested = true;
        }
    }
}

fn bool pending() @inline
{
    if (ctx == null) return false;
    return ctx.active_op_count > 0;
}

fn void poll_wake()
{
    if (ctx == null) return;

    winbase::postQueuedCompletionStatus(
        ctx.iocp,
        0,
        IOCP_WAKE_KEY,
        null
    );
}

fn void poll_wakeup_handler()
{
    (void)aio::current_loop().threadsafe.process();
}

fn void poll(ulong timeout_us)
{
    if (ctx == null) return;

    ctx.entries = {};

    winbase::ULong removed = 0;
    winbase::DWord timeout_ms = (timeout_us / 1000 > 0xFFFFFFFE) ? winbase::INFINITE : (winbase::DWord)(timeout_us / 1000);

    winbase::Bool ok = winbase::getQueuedCompletionStatusEx(
        ctx.iocp,
        &ctx.entries[0],
        MAX_EVENTS,
        (ulong*)&removed,
        timeout_ms,
        winbase::FALSE
    );

    if (!ok && removed == 0) return;

    for (winbase::ULong i = 0; i < removed; i++)
    {
        uptr key = (uptr)ctx.entries[i].lpCompletionKey;
        winbase::Overlapped* ov = ctx.entries[i].lpOverlapped;

        if (ov == null)
        {
            if (key == IOCP_WAKE_KEY)
            {
                poll_wakeup_handler();
            }

            continue;
        }

        IocpOp* op = (IocpOp*)ov;
        if (!op.active) continue;

        op.transferred = ctx.entries[i].dwNumberOfBytesTransferred;

        Future* fut = op.future;
        if (fut == null)
        {
            op_free(op);
            continue;
        }

        if (fut.done())
        {
            op_free(op);
            continue;
        }

        if (op.cancel_requested)
        {
            fut.cancel(aio::POLL_ERROR);
            op_free(op);
            continue;
        }

        if (op.is_accept || op.is_connect)
        {
            fut.set_result((void*)op);
            continue;
        }

        if (op.transferred > 0)
        {
            fut.set_result((void*)op);
            continue;
        }

        if (!op.is_write)
        {
            fut.set_result(null);
        }
        else
        {
            fut.cancel(aio::POLL_ERROR);
        }

        op_free(op);
    }
}

fn usz? async_read(Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    Future* fut = aio::future_new()!;
    defer fut.free();
    
    register_read(fd, buf.ptr, buf.len, fut);

    void*? raw = fut.await();
    if (catch err = raw)
    {
        if (fut.error == aio::IO_ERROR) return aio::IO_ERROR~;
        return err~;
    }

    if (raw == null) return 0;

    IocpOp* op = (IocpOp*)raw;
    winbase::DWord n = op.transferred;

    if (n > (winbase::DWord)buf.len)
    {
        n = (winbase::DWord)buf.len;
    }

    op_free(op);

    return (usz)n;
}

fn usz? async_write(Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    usz total = 0;

    while (total < buf.len)
    {
        Future* fut = aio::future_new()!;
        defer fut.free();
        
        start_write(fd, buf.ptr + total, buf.len - total, fut);

        void*? raw = fut.await();
        if (catch err = raw)
        {
            if (total > 0) return total;
            if (fut.error == aio::IO_ERROR) return aio::IO_ERROR~;
            return err~;
        }

        if (raw == null)
        {
            if (total > 0) return total;
            return aio::IO_ERROR~;
        }

        IocpOp* op = (IocpOp*)raw;
        winbase::DWord written = op.transferred;

        op_free(op);

        if (written == 0) break;

        total += (usz)written;
    }
    
    return total;
}

fn void start_recvfrom(Fd fd, void* buf, usz len, Future* future) @private
{
    if (ctx.io_shutting_down)
    {
        future.cancel(aio::IO_ERROR);
        return;
    }

    IocpOp* op = op_alloc();
    op.is_write = false;
    op.is_socket = true;
    op.is_recvfrom = true;
    op.handle = fd;
    op.future = future;
    op.flags = 0;
    op.from_len = winsock2::SockAddrStorage.sizeof;
    op.wsabuf.buf = buf;
    op.wsabuf.len = (winbase::DWord)len;

    if (!iocp_associate(fd))
    {
        future.cancel(aio::IO_ERROR);
        op_free(op);
        return;
    }

    int rc = winsock2::wsaRecvFrom(
        (winsock2::Socket)fd,
        &op.wsabuf,
        1,
        null,
        &op.flags,
        (winsock2::SockAddr*)&op.from_addr,
        &op.from_len,
        &op.ov,
        null
    );

    if (rc == 0) return;

    if (winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
    {
        future.cancel(aio::IO_ERROR);
        op_free(op);
    }
}

fn usz? async_recvfrom(Fd fd, char[] buf, char* ip_str, usz* ip_len, ushort* port)
{
    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (ip_len == null) return errno::E_INVALID_ARG~;
    if (port == null) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;

    Future* fut = aio::future_new()!;
    defer fut.free();
    
    start_recvfrom(fd, buf.ptr, buf.len, fut);

    void*? raw = fut.await();
    if (catch err = raw)
    {
        if (fut.error == aio::IO_ERROR) return aio::IO_ERROR~;
        return err~;
    }

    if (raw == null) return aio::IO_ERROR~;

    IocpOp* op = (IocpOp*)raw;
    winbase::DWord n = op.transferred;

    if (n > (winbase::DWord)buf.len)
    {
        n = (winbase::DWord)buf.len;
    }

    ushort family = ((winsock2::SockAddrIn*)&op.from_addr).sin_family;
    if (family == (ushort)winsock2::AF_INET6) 
    {
        winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)&op.from_addr;
        ws2tcpip::inet_ntop(winsock2::AF_INET6, &a6.sin6_addr, ip_str, 46);
        *ip_len = (usz)string::strlen(ip_str);
        *port = winsock2::ntohs(a6.sin6_port);
    }
    else
    {
        winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)&op.from_addr;
        ws2tcpip::inet_ntop(winsock2::AF_INET, &a4.sin_addr, ip_str, 16);
        *ip_len = (usz)string::strlen(ip_str);
        *port = winsock2::ntohs(a4.sin_port);
    }

    op_free(op);

    return (usz)n;
}

fn usz? async_sendto(Fd fd, char[] buf, char* ip_str, ushort port)
{
    winsock2::SockAddr* dest_addr;
    int dest_len;

    winsock2::SockAddrIn a4 = {};
    winsock2::SockAddrIn6 a6 = {};

    if (string::strchr(ip_str, ':') != null)
    {
        if (ws2tcpip::inet_pton(winsock2::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return aio::ADDR_ERROR~;
        }

        a6.sin6_family = (ushort)winsock2::AF_INET6;
        a6.sin6_port = winsock2::htons(port);
        dest_addr = (winsock2::SockAddr*)&a6;
        dest_len = $sizeof(a6);
    }
    else 
    {
        if (ws2tcpip::inet_pton(winsock2::AF_INET, ip_str, &a4.sin_addr) != 1)
        {
            return aio::ADDR_ERROR~;
        }

        a4.sin_family = (ushort)winsock2::AF_INET;
        a4.sin_port = winsock2::htons(port);
        dest_addr = (winsock2::SockAddr*)&a4;
        dest_len = $sizeof(a4);
    }

    IocpOp* op = op_alloc();
    op.is_write = true;
    op.is_socket = true;
    op.handle = fd;
    op.flags = 0;
    op.wsabuf.buf = buf.ptr;
    op.wsabuf.len = (winbase::DWord)buf.len;

    if (!iocp_associate(fd))
    {
        op_free(op);
        return aio::IO_ERROR~;
    }

    Future* fut = aio::future_new()!;
    defer fut.free();

    op.future = fut;

    int rc = winsock2::wsaSendTo(
        (winsock2::Socket)fd,
        &op.wsabuf,
        1,
        null,
        0,
        dest_addr,
        dest_len,
        &op.ov,
        null
    );

    if (rc != 0 && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
    {
        op_free(op);
        return aio::IO_ERROR~;
    }

    void*? raw = fut.await();
    if (catch err = raw)
    {
        if (fut.error == aio::IO_ERROR) return aio::IO_ERROR~;
        return err~;
    }

    if (raw == null) return aio::IO_ERROR~;

    IocpOp* completed = (IocpOp*)raw;
    winbase::DWord n = completed.transferred;

    op_free(completed);

    return (usz)n;
}

fn Fd[2]? pipe_open()
{
    winbase::SecurityAttributes sa = {};
    sa.nLength = $sizeof(sa);
    sa.lpSecurityDescriptor = null;
    sa.bInheritHandle = winbase::FALSE;

    char[128] name;
    winbase::DWord pid = winbase::getCurrentProcessId();

    static int counter = 0;
    counter += 1;

    stdio::sprintf(
        &name[0],
        "\\\\.\\pipe\\aio_%lu_%lu",
        pid,
        (winbase::DWord)counter
    );

    winbase::Handle rh = winbase::createNamedPipeA(
        &name[0],
        winbase::PIPE_ACCESS_INBOUND | winbase::FILE_FLAG_OVERLAPPED,
        winbase::PIPE_TYPE_BYTE | winbase::PIPE_READMODE_BYTE | winbase::PIPE_WAIT,
        1,
        65536,
        65536,
        0,
        &sa
    );

    if (rh == winbase::INVALID_HANDLE_VALUE)
    {
        return aio::IO_ERROR~;
    }

    winbase::Handle wh = winbase::createFileA(
        &name[0],
        winbase::GENERIC_WRITE,
        0,
        &sa,
        winbase::OPEN_EXISTING,
        winbase::FILE_ATTRIBUTE_NORMAL | winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    if (wh == winbase::INVALID_HANDLE_VALUE)
    {
        winbase::closeHandle(rh);
        return aio::IO_ERROR~;
    }

    winbase::Bool ok = winbase::connectNamedPipe(rh, null);

    if (!ok)
    {
        winbase::DWord err = winbase::getLastError();

        if (err != winbase::ERROR_PIPE_CONNECTED)
        {
            winbase::closeHandle(wh);
            winbase::closeHandle(rh);
            return aio::IO_ERROR~;
        }
    }

    fd_set_socket(rh, false);
    fd_set_socket(wh, false);

    return { rh, wh };
}

fn void fd_close(Fd fd)
{
    if (fd_invalid(fd)) return;

    unregister(fd);

    bool sock = false;

    bool? is_sock = ctx.socket_fds[fd];
    if (catch err = is_sock)
    {
        sock = false;
    }
    else
    {
        sock = is_sock;
    }

    ctx.socket_fds.remove(fd);

    if (sock)
    {
        winsock2::closesocket((winsock2::Socket)(iptr)fd);
    }
    else
    {
        winbase::closeHandle(fd);
    }
}

fn Char16*? utf8to16(String path, Char16[] wpath) @private
{
    if (path.len == 0) return errno::F_INVAL~;

    Char16[] p2 = path.to_utf16(tmem)!;

    if (p2.len >= wpath.len - 1) return errno::F_BAD_LENGTH~;

    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;

    for (usz i = 0; i < p2.len; i++)
    {
        if (p2[i] == (Char16)'/')
        {
            wpath[i] = (Char16)'\\';
        }
    }

    return wpath.ptr;
}

fn void* file_open_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    winbase::DWord access = 0;
    winbase::DWord disposition = 0;
    winbase::DWord attributes = winbase::FILE_ATTRIBUTE_NORMAL;

    if (arg.mode == "r")
    {
        access = winbase::GENERIC_READ;
        disposition = winbase::OPEN_EXISTING;
    }
    else if (arg.mode == "r+")
    {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::OPEN_EXISTING;
    }
    else if (arg.mode == "w")
    {
        access = winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    }
    else if (arg.mode == "w+")
    {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    }
    else if (arg.mode == "a")
    {
        access = winbase::FILE_APPEND_DATA;
        disposition = winbase::OPEN_ALWAYS;
    }
    else if (arg.mode == "a+")
    {
        access = winbase::GENERIC_READ | winbase::FILE_APPEND_DATA;
        disposition = winbase::OPEN_ALWAYS;
    }
    else
    {
        arg.error = errno::E_INVALID_ARG;
        return v_arg;
    }

    winbase::DWord share = winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE | winbase::FILE_SHARE_DELETE;

    Char16[260] wbuf;
    Char16*? wpath = utf8to16(arg.name, &wbuf);
    if (catch err = wpath)
    {
        arg.error = err;
        return v_arg;
    }

    winbase::Handle h = winbase::createFileW(
        wpath,
        access,
        share,
        null,
        disposition,
        attributes,
        null
    );

    if (h == winbase::INVALID_HANDLE_VALUE)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    if (arg.mode[0] == 'a')
    {
        winbase::setFilePointerEx(h, 0, null, winbase::FILE_END);
    }

    arg.fd = h;

    return v_arg;
}

fn Fd? file_open(String name, String mode, int permission = 0o644)
{
    Arg arg = {
        .error = NONE,
        .name = name,
        .mode = mode,
    };
    
    Arg*? a = aio::run_in_executor(&file_open_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    fd_set_socket(a.fd, false);
    
    return a.fd;
}

fn void* file_close_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    int rc = winbase::closeHandle(arg.fd);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.rc = rc;

    return v_arg;
}

fn void? file_close(Fd fd) @maydiscard
{
    if (fd_invalid(fd)) return;

    ctx.socket_fds.remove(fd);
    ctx.iocp_assoc.remove(fd);

    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_close_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* file_seek_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    winbase::DWord method;

    switch (arg.whence)
    {
      case 0: method = winbase::FILE_BEGIN;
      case 1: method = winbase::FILE_CURRENT;
      case 2: method = winbase::FILE_END;
      default:
        arg.error = errno::E_INVALID_ARG;
        return v_arg;
    }

    long new_pos = 0;
    int rc = winbase::setFilePointerEx(arg.fd, arg.pos, &new_pos, method);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = new_pos;

    return v_arg;
}

fn long? file_seek(Fd fd, long pos, int whence) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
        .pos = pos,
        .whence = whence,
    };
    
    Arg*? a = aio::run_in_executor(&file_seek_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.offset;
}

fn void* file_tell_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long pos = 0;
    int rc = winbase::setFilePointerEx(arg.fd, 0, &pos, winbase::FILE_CURRENT);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = pos;

    return v_arg;
}

fn long? file_tell(Fd fd)
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };
    
    Arg*? a = aio::run_in_executor(&file_tell_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.offset;
}

fn void* file_truncate_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long old_pos = 0;

    int rc = winbase::setFilePointerEx(arg.fd, 0, &old_pos, winbase::FILE_CURRENT);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    rc = winbase::setFilePointerEx(arg.fd, arg.pos, null, winbase::FILE_BEGIN);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    rc = winbase::setEndOfFile(arg.fd);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    (void)winbase::setFilePointerEx(arg.fd, old_pos, null, winbase::FILE_BEGIN);

    return v_arg;
}

fn void? file_truncate(Fd fd, long pos) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
        .pos = pos,
    };
    
    Arg*? a = aio::run_in_executor(&file_truncate_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* file_flush_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    int rc = winbase::flushFileBuffers(arg.fd);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    return v_arg;
}

fn void? file_flush(Fd fd) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_flush_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

fn void* file_size_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    long size = 0;
    int rc = winbase::getFileSizeEx(arg.fd, &size);
    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = size;

    return v_arg;
}

fn long? file_size(Fd fd)
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_size_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.offset;
}

fn void* file_read_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    winbase::DWord n = 0;

    int rc = winbase::readFile(
        arg.fd,
        arg.buf.ptr,
        (winbase::DWord)arg.buf.len,
        &n,
        null
    );

    if (rc == 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.result = (usz)n;

    return v_arg;
}

fn usz? file_read(Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    Arg arg = {
        .error = NONE,
        .fd = fd,
        .buf = buf,
    };

    Arg*? a = aio::run_in_executor(&file_read_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;

    return a.result;
}

fn void* file_write_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    usz total = 0;

    while (total < arg.buf.len)
    {
        winbase::DWord n = 0;

        int rc = winbase::writeFile(
            arg.fd,
            arg.buf.ptr + total,
            (winbase::DWord)(arg.buf.len - total),
            &n,
            null
        );

        if (rc == 0)
        {
            arg.error = errno::get_fault();
            arg.result = total;
            return v_arg;
        }

        if (n == 0) break;

        total += (usz)n;
    }

    arg.result = total;

    return v_arg;
}

fn usz? file_write(Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    Arg arg = {
        .error = NONE,
        .fd = fd,
        .buf = buf,
    };

    Arg*? a = aio::run_in_executor(&file_write_blocking, &arg);

    if (catch err = a) return err~;

    if (a.error != NONE)
    {
        if (a.result > 0) return a.result;
        return a.error~;
    }

    return a.result;
}

fn Fd fd_stdin()
{
    winbase::Handle h = winbase::createFileA(
        "CONIN$",
        winbase::GENERIC_READ,
        winbase::FILE_SHARE_READ,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    fd_set_socket(h, false);

    return h;
}

fn Fd fd_stdout()
{
    winbase::Handle h = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );

    fd_set_socket(h, false);

    return h;
}

fn Fd fd_stderr()
{
    winbase::Handle h = winbase::createFileA(
        "CONOUT$",
        winbase::GENERIC_WRITE,
        winbase::FILE_SHARE_WRITE,
        null,
        winbase::OPEN_EXISTING,
        winbase::FILE_FLAG_OVERLAPPED,
        null
    );
    
    fd_set_socket(h, false);

    return h;
}

// eof