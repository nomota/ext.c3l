// io.win32.c3

module ext::mio @if(env::WIN32) @link("ws2_32");

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

faultdef REGISTER_FAILED, POLL_ERROR, IO_ERROR, ADDR_ERROR, OPERATION_ABORTED;

alias Fd = winbase::Handle;

macro bool fd_invalid(Fd fd)
{
    return fd == null || fd == winbase::INVALID_HANDLE_VALUE;
}

macro Fd fd_null()
{
    return winbase::INVALID_HANDLE_VALUE;
}

const sz MAX_EVENTS = 4096;
const sz IOCP_OP_POOL = 4096;

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
    bool closing;
    winbase::Handle handle;

    winbase::DWord transferred;

    winsock2::WSABuf wsabuf;
    winbase::DWord flags;

    winsock2::SockAddrStorage from_addr;
    int from_len;

    winsock2::SockAddrStorage to_addr;
    int to_len;

    char[128] addr_buf;
    
    bool failed;
    fault error;
}

// poll result
struct Event 
{
    Fd fd;
    bool error;
    bool readable;
    bool writable;
}

struct Context @local
{
    IocpOp[IOCP_OP_POOL] op_pool;
    winbase::Handle iocp;

    sz active_op_count;

    HashMap{Fd, IocpOp*} read_assoc;
    HashMap{Fd, IocpOp*} write_assoc;

    HashMap{Fd, bool} socket_fds;
    HashMap{Fd, bool} iocp_assoc;
    
    bool io_shutting_down;

    winbase::OverlappedEntry[MAX_EVENTS] entries;
    
    HashMap{Fd, IocpOp*} poll_read_fds;
    HashMap{Fd, IocpOp*} poll_write_fds;
}

tlocal Context* ctx @local = null;
LocalAllocator localmem = null;

fn IocpOp* op_alloc()
{
    @assert(ctx != null);

    for (sz i = 0; i < IOCP_OP_POOL; i++)
    {
        if (!ctx.op_pool[i].active)
        {
            ctx.op_pool[i] = {};
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

fn bool iocp_associate(Fd fd, IocpOp* op, bool is_write)
{
    if (fd_invalid(fd)) return false;

    if (catch ctx.iocp_assoc[fd])
    {
        winbase::Handle result = winbase::createIoCompletionPort(
            fd,
            ctx.iocp,
            (uptr)fd,
            0
        );

        if (result == null) return false;

        ctx.iocp_assoc[fd] = true;
    }

    if (is_write)
    {
        ctx.write_assoc[fd] = op;
    }
    else
    {
        ctx.read_assoc[fd] = op;
    }

    return true;
}

fn void init()
{
    if (ctx != null) return;
    if (localmem == null) localmem = mem;

    ctx = localmem.alloc(Context)!!;
    *ctx = {
        .iocp = null,
        .active_op_count = 0,
        .io_shutting_down = false,
    };

    ctx.read_assoc.init(localmem);
    ctx.write_assoc.init(localmem);
    ctx.socket_fds.init(localmem);
    ctx.iocp_assoc.init(localmem);
    ctx.poll_read_fds.init(localmem);
    ctx.poll_write_fds.init(localmem);
    
    winsock2::WSAData wsa;
    @assert(winsock2::wsaStartup(0x0202, &wsa) == 0, "aio: WSAStartup failed");

    ctx.iocp = winbase::createIoCompletionPort(winbase::INVALID_HANDLE_VALUE, null, 0, 1);
    @assert(ctx.iocp != null, "aio: CreateIoCompletionPort failed");
}

fn void deinit()
{
    if (ctx == null) return;

    ctx.io_shutting_down = true;

    ctx.poll_read_fds.@each(; fd, op)
    {
        if (op != null && op.active) op_free(op);
    };
    
    ctx.poll_write_fds.@each(; fd, op)
    {
        if (op != null && op.active) op_free(op);
    };
    
    ctx.poll_read_fds.clear();
    ctx.poll_write_fds.clear();

    ctx.read_assoc.clear();
    ctx.write_assoc.clear();

    for (sz i = 0; i < IOCP_OP_POOL; i++)
    {
        if (!ctx.op_pool[i].active) continue;

        Fd fd = ctx.op_pool[i].handle;
        if (!fd_invalid(fd))
        {
            winbase::cancelIoEx(fd, null);
        }
    }

    sz spin = 0;
    while (ctx.active_op_count > 0 && spin < 1000)
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
        if (!ok && removed == 0) 
        {
            spin++;
            continue;
        }
        spin = 0;
        for (winbase::ULong i = 0; i < removed; i++)
        {
            winbase::Overlapped* ov = ctx.entries[i].lpOverlapped;
            if (ov == null) continue;

            IocpOp* op = (IocpOp*)ov;
            if (!op.active) continue;

            op.transferred = ctx.entries[i].dwNumberOfBytesTransferred;

            op_free(op);
        }
    }

    @assert(ctx.active_op_count == 0, "aio/win32: pending IOCP ops remain at destroy");

    if (ctx.iocp != null)
    {
        winbase::closeHandle(ctx.iocp);
    }

    winsock2::wsaCleanup();

    ctx.read_assoc.free();
    ctx.write_assoc.free();
    ctx.iocp_assoc.free();
    ctx.socket_fds.free();
    
    ctx.poll_read_fds.free();
    ctx.poll_write_fds.free();    
    localmem.free(ctx);
    ctx = null;
}

fn void unregister(Fd fd) @private
{
    if (ctx == null) return;
    if (fd_invalid(fd)) return;
    
    winbase::cancelIoEx(fd, null);

    for (sz i = 0; i < IOCP_OP_POOL; i++)
    {
        IocpOp* op = &ctx.op_pool[i];

        if (op.active && op.handle == fd)
        {
            op.cancel_requested = true;
            op.closing = true;
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
    // (void)aio::current_loop().threadsafe.process();
}

fn void? push_event(Event[] revents, sz* idx, Fd fd, bool error, bool readable, bool writable) @local
{
    if (*idx >= revents.len) return POLL_ERROR~;

    revents[*idx] = {
        .fd = fd,
        .error = error,
        .readable = readable,
        .writable = writable,
    };

    (*idx)++;
}

fn bool op_result(IocpOp* op, winbase::DWord* bytes) @private
{
    if (op.is_socket)
    {
        winbase::DWord flags = 0;

        winsock2::Bool ok = winsock2::wsaGetOverlappedResult(
            (winsock2::Socket)op.handle,
            &op.ov,
            bytes,
            winsock2::FALSE,
            &flags
        );

        return ok != 0;
    }

    winbase::Bool ok = winbase::getOverlappedResult(
        op.handle,
        &op.ov,
        bytes,
        winbase::FALSE
    );

    return ok != 0;
}

fn void? poll(Event[] revents, sz* n_revents, ulong timeout_us)
{
    if (ctx == null)
    {
        *n_revents = 0;
        return;
    }
    ctx.entries = {};
    
    winbase::ULong removed = 0;
    
    ulong ms = timeout_us / 1000;
    if (timeout_us > 0 && ms == 0) ms = 1;
    winbase::DWord timeout_ms = ms > 0xFFFFFFFE ? winbase::INFINITE : (winbase::DWord)ms;
    
    winbase::Bool ok = winbase::getQueuedCompletionStatusEx(
        ctx.iocp,
        &ctx.entries[0],
        MAX_EVENTS,
        (ulong*)&removed,
        timeout_ms,
        winbase::FALSE
    );

    if (!ok && removed == 0)
    {
        *n_revents = 0;
        return;
    }
    
    sz idx = 0;
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

        if (op.closing)
        {
            op_free(op);
            continue;
        }
        
        if (op.cancel_requested)
        {
            op.failed = true;
            op.error = OPERATION_ABORTED;

            push_event(revents, &idx, op.handle, true, !op.is_write, op.is_write)!;
            if (op.is_write)
            {
                ctx.poll_write_fds[op.handle] = op;
            }
            else
            {
                ctx.poll_read_fds[op.handle] = op;
            }
            continue;
        }

        winbase::DWord bytes = 0;
        bool ok2 = op_result(op, &bytes);
        op.transferred = bytes;
        
        if (!ok2)
        {
            op.failed = true;
            op.error = IO_ERROR;

            push_event(revents, &idx, op.handle, true, !op.is_write, op.is_write)!;
            if (op.is_write)
            {
                ctx.poll_write_fds[op.handle] = op;
            }
            else
            {
                ctx.poll_read_fds[op.handle] = op;
            }
            continue;
        }

        if (op.is_accept || op.is_connect)
        {
            push_event(revents, &idx, op.handle, false, true, false)!;
            ctx.poll_read_fds[op.handle] = op;
            continue;
        }

        if (op.is_write)
        {
            push_event(revents, &idx, op.handle, false, false, true)!;
            ctx.poll_write_fds[op.handle] = op;
            continue;
        }

        push_event(revents, &idx, op.handle, false, true, false)!;
        ctx.poll_read_fds[op.handle] = op;
    }
    
    *n_revents = idx;
}

fn void? register_read(Fd fd, void* buf, sz len) @private
{
    if (ctx.io_shutting_down) return REGISTER_FAILED~;

    IocpOp* op = op_alloc();
    op.is_write = false;
    op.is_socket = fd_is_socket(fd);
    op.handle = fd;

    if (!iocp_associate(fd, op, is_write: false))
    {
        op_free(op);
        return REGISTER_FAILED~;
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
            (void)ctx.read_assoc.remove(fd);
            op_free(op);
            return REGISTER_FAILED~;
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
        (void)ctx.read_assoc.remove(fd);
        op_free(op);
        return REGISTER_FAILED~;
    }
}

fn sz? async_read(Fd fd, char[] buf)
{
    if (ctx == null) return IO_ERROR~;
    if (fd_invalid(fd)) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;
    if (catch ctx.read_assoc[fd])
    {
        if (catch err = register_read(fd, buf.ptr, buf.len))
        {
            return err~;
        }
        return errno::E_WOULD_BLOCK~;
    }

    if (catch ctx.poll_read_fds[fd])
    {
        return errno::E_WOULD_BLOCK~;
    }
    
    IocpOp* op = (IocpOp*)ctx.poll_read_fds[fd];
    if (op.is_recvfrom)
    {
        return errno::E_INVALID_ARG~;
    }

    if (op.failed)
    {
        (void)ctx.read_assoc.remove(fd);
        (void)ctx.poll_read_fds.remove(fd);
        fault err = op.error;
        op_free(op);
    
        return err~;
    }
    
    winbase::DWord n = op.transferred;

    if (n > (winbase::DWord)buf.len)
    {
        n = (winbase::DWord)buf.len;
    }
    (void)ctx.poll_read_fds.remove(fd);
    (void)ctx.read_assoc.remove(fd);
    op_free(op);

    return (sz)n;
}

fn void? register_write(Fd fd, void* data, sz len) @private
{
    if (ctx.io_shutting_down) return REGISTER_FAILED~;

    IocpOp* op = op_alloc();
    op.is_write = true;
    op.is_socket = fd_is_socket(fd);
    op.handle = fd;

    if (!iocp_associate(fd, op, is_write: true))
    {
        op_free(op);
        return REGISTER_FAILED~;
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
            (void)ctx.write_assoc.remove(fd);
            op_free(op);
            return REGISTER_FAILED~;
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
        (void)ctx.write_assoc.remove(fd);
        op_free(op);
        return REGISTER_FAILED~;
    }
}

fn sz? async_write(Fd fd, char[] buf)
{
    if (ctx == null) return IO_ERROR~;
    if (fd_invalid(fd)) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;
    if (catch ctx.write_assoc[fd])
    {
        if (catch err = register_write(fd, buf.ptr, buf.len))
        {
            return err~;
        }
        return errno::E_WOULD_BLOCK~;
    }

    if (catch ctx.poll_write_fds[fd])
    {
        return errno::E_WOULD_BLOCK~;
    }
    
    IocpOp* op = (IocpOp*)ctx.poll_write_fds[fd];
    if (op.failed)
    {
        (void)ctx.write_assoc.remove(fd);
        (void)ctx.poll_write_fds.remove(fd);
        fault err = op.error;
        op_free(op);
    
        return err~;
    }
    
    winbase::DWord n = op.transferred;

    if (n > (winbase::DWord)buf.len)
    {
        n = (winbase::DWord)buf.len;
    }
    (void)ctx.poll_write_fds.remove(fd);
    (void)ctx.write_assoc.remove(fd);
    op_free(op);

    return (sz)n;
}

fn void? register_recvfrom(Fd fd, void* buf, sz len) @private
{
    if (ctx.io_shutting_down) return REGISTER_FAILED~;

    IocpOp* op = op_alloc();
    op.is_write = false;
    op.is_socket = true;
    op.is_recvfrom = true;
    op.handle = fd;
    op.flags = 0;
    op.from_len = winsock2::SockAddrStorage::size;
    op.wsabuf.buf = buf;
    op.wsabuf.len = (winbase::DWord)len;

    if (!iocp_associate(fd, op, false))
    {
        op_free(op);
        return REGISTER_FAILED~;
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
        (void)ctx.read_assoc.remove(fd);
        op_free(op);
        return REGISTER_FAILED~;
    }
}

fn sz? async_recvfrom(Fd fd, char[] buf, char* ip_str, sz* ip_len, ushort* port)
{
    if (ctx == null) return IO_ERROR~;
    if (fd_invalid(fd)) return errno::E_INVALID_ARG~;

    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (ip_len == null) return errno::E_INVALID_ARG~;
    if (port == null) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;

    if (catch ctx.read_assoc[fd])
    {
        if (catch err = register_recvfrom(fd, buf.ptr, buf.len))
        {
            return err~;
        }
        return errno::E_WOULD_BLOCK~;
    }

    if (catch ctx.poll_read_fds[fd])
    {
        return errno::E_WOULD_BLOCK~;
    }

    IocpOp* op = (IocpOp*)ctx.poll_read_fds[fd];
    if (!op.is_recvfrom)
    {
        return errno::E_INVALID_ARG~;
    }

    if (op.failed)
    {
        (void)ctx.read_assoc.remove(fd);
        (void)ctx.poll_read_fds.remove(fd);
        fault err = op.error;
        op_free(op);
    
        return err~;
    }
    
    winbase::DWord n = op.transferred;

    if (n > (winbase::DWord)buf.len)
    {
        n = (winbase::DWord)buf.len;
    }

    ushort family = ((winsock2::SockAddrIn*)&op.from_addr).sin_family;
    
    if (family == (ushort)winsock2::AF_INET6) 
    {
        winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)&op.from_addr;
        char* p = ws2tcpip::inet_ntop(winsock2::AF_INET6, &a6.sin6_addr, ip_str, 46);
        if (p == null)
        {
            (void)ctx.poll_read_fds.remove(fd);
            (void)ctx.read_assoc.remove(fd);
            op_free(op);
            return IO_ERROR~;
        }
    
        *ip_len = (sz)string::strlen(ip_str);
        *port = winsock2::ntohs(a6.sin6_port);
    }
    else if (family == (ushort)winsock2::AF_INET)
    {
        winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)&op.from_addr;
        char* p = ws2tcpip::inet_ntop(winsock2::AF_INET, &a4.sin_addr, ip_str, 16);
        if (p == null)
        {
            (void)ctx.poll_read_fds.remove(fd);
            (void)ctx.read_assoc.remove(fd);
            op_free(op);
            return IO_ERROR~;
        }
    
        *ip_len = (sz)string::strlen(ip_str);
        *port = winsock2::ntohs(a4.sin_port);
    }
    else
    {
        (void)ctx.poll_read_fds.remove(fd);
        (void)ctx.read_assoc.remove(fd);
        op_free(op);
        return errno::E_INVALID_ARG~;
    }
    (void)ctx.poll_read_fds.remove(fd);
    (void)ctx.read_assoc.remove(fd);
    op_free(op);

    return (sz)n;
}

fn void? register_sendto(Fd fd, char* buf, sz buf_len, char* ip_str, ushort port)
{
    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (ctx.io_shutting_down) return REGISTER_FAILED~;

    IocpOp* op = op_alloc();
    op.is_write = true;
    op.is_socket = true;
    op.handle = fd;
    op.flags = 0;
    op.wsabuf.buf = buf;
    op.wsabuf.len = (winbase::DWord)buf_len;

    winsock2::SockAddr* dest_addr;

    if (string::strchr(ip_str, ':') != null)
    {
        winsock2::SockAddrIn6* a6 = (winsock2::SockAddrIn6*)&op.to_addr;
        *a6 = {};

        if (ws2tcpip::inet_pton(winsock2::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            op_free(op);
            return ADDR_ERROR~;
        }

        a6.sin6_family = (ushort)winsock2::AF_INET6;
        a6.sin6_port = winsock2::htons(port);

        dest_addr = (winsock2::SockAddr*)a6;
        op.to_len = @sizeof(*a6);
    }
    else
    {
        winsock2::SockAddrIn* a4 = (winsock2::SockAddrIn*)&op.to_addr;
        *a4 = {};

        if (ws2tcpip::inet_pton(winsock2::AF_INET, ip_str, &a4.sin_addr) != 1)
        {
            op_free(op);
            return ADDR_ERROR~;
        }

        a4.sin_family = (ushort)winsock2::AF_INET;
        a4.sin_port = winsock2::htons(port);

        dest_addr = (winsock2::SockAddr*)a4;
        op.to_len = @sizeof(*a4);
    }

    if (!iocp_associate(fd, op, true))
    {
        op_free(op);
        return REGISTER_FAILED~;
    }

    int rc = winsock2::wsaSendTo(
        (winsock2::Socket)fd,
        &op.wsabuf,
        1,
        null,
        0,
        dest_addr,
        op.to_len,
        &op.ov,
        null
    );
    if (rc != 0 && winsock2::wsaGetLastError() != winsock2::WSA_IO_PENDING)
    {
        (void)ctx.write_assoc.remove(fd);
        op_free(op);
        return REGISTER_FAILED~;
    }
}

fn sz? async_sendto(Fd fd, char[] buf, char* ip_str, ushort port)
{
    if (ctx == null) return IO_ERROR~;
    if (fd_invalid(fd)) return errno::E_INVALID_ARG~;

    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;
    
    if (catch ctx.write_assoc[fd])
    {
        if (catch err = register_sendto(fd, buf.ptr, buf.len, ip_str, port))
        {
            return err~;
        }
        return errno::E_WOULD_BLOCK~;
    }

    if (catch ctx.poll_write_fds[fd])
    {
        return errno::E_WOULD_BLOCK~;
    }

    IocpOp* op = (IocpOp*)ctx.poll_write_fds[fd];
    if (op.failed)
    {
        (void)ctx.write_assoc.remove(fd);
        (void)ctx.poll_write_fds.remove(fd);
        fault err = op.error;
        op_free(op);
    
        return err~;
    }
    
    winbase::DWord n = op.transferred;

    if (n > (winbase::DWord)buf.len)
    {
        n = (winbase::DWord)buf.len;
    }
    (void)ctx.poll_write_fds.remove(fd);
    (void)ctx.write_assoc.remove(fd);
    op_free(op);

    return (sz)n;
}

fn Fd[2]? pipe_open()
{
    winbase::SecurityAttributes sa = {};
    sa.nLength = @sizeof(sa);
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
        return IO_ERROR~;
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
        return IO_ERROR~;
    }

    winbase::Bool ok = winbase::connectNamedPipe(rh, null);
    if (!ok)
    {
        winbase::DWord err = winbase::getLastError();
        if (err != winbase::ERROR_PIPE_CONNECTED)
        {
            winbase::closeHandle(wh);
            winbase::closeHandle(rh);
            return IO_ERROR~;
        }
    }

    fd_set_socket(rh, false);
    fd_set_socket(wh, false);

    return { rh, wh };
}

fn void free_polled_ops(Fd fd) @local
{
    IocpOp*? rop = ctx.poll_read_fds[fd];
    if (try rop)
    {
        if (rop != null && rop.active) op_free(rop);
    }

    IocpOp*? wop = ctx.poll_write_fds[fd];
    if (try wop)
    {
        if (wop != null && wop.active) op_free(wop);
    }

    (void)ctx.poll_read_fds.remove(fd);
    (void)ctx.poll_write_fds.remove(fd);
}

fn void fd_close(Fd fd)
{
    if (ctx == null) return;
    if (fd_invalid(fd)) return;

    free_polled_ops(fd);    
    unregister(fd);

    bool is_sock = ctx.socket_fds[fd] ?? false;

    ctx.socket_fds.remove(fd);
    
    (void)ctx.read_assoc.remove(fd);
    (void)ctx.write_assoc.remove(fd);
    (void)ctx.iocp_assoc.remove(fd);
    
    if (is_sock)
    {
        winsock2::closesocket((winsock2::Socket)(iptr)fd);
    }
    else
    {
        winbase::closeHandle(fd);
    }
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
    
    if (fd_invalid(h)) return fd_null();

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

    if (fd_invalid(h)) return fd_null();

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
    
    if (fd_invalid(h)) return fd_null();

    fd_set_socket(h, false);

    return h;
}

// eof