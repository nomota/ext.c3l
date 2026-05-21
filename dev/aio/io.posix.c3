// io.posix.c3

module ext::aio::io @if(env::POSIX);

import std::io;
import c::stdlib;
import c::unistd;
import c::fcntl;
import c::string;
import c::netinet::in;
import c::sys::epoll;
import c::sys::event;
import c::sys::select;
import c::sys::socket;
import c::errno;
import c::sys::stat;
import ext::debug;
import ext::mem;

const usz MAX_EVENTS = 4096;
const usz MAX_FD_WATCH  = 20_000;

alias Fd = int;

macro bool fd_invalid(Fd fd)
{
    return fd < 0;
}

macro Fd fd_null()
{
    return -1;
}

struct FdWatch @private
{
    Fd fd;
    bool active;
    bool internal;
    bool poll_read_registered;
    bool poll_write_registered;
    Future* read_fut;
    Future* write_fut;
}

struct IoContext @private
{
    FdWatch[MAX_FD_WATCH] fd_table;
    usz fd_count;
    Fd poll_fd; // epoll fd or kqueue fd

    // poll wake pipe
    Fd wake_r;
    Fd wake_w;
}

tlocal IoContext* ctx @private = null;

fn void init() @init
{
    if (ctx != null) return;
    aio::init();
    ctx = aio::localmem.alloc(IoContext)!!;
    *ctx = {
        .fd_count = 0,
        .poll_fd = fd_null(),
        .wake_r = fd_null(),
        .wake_w = fd_null(),
    };    
    for (usz i = 0; i < MAX_FD_WATCH; i++) 
    {
        ctx.fd_table[i] = {};
    }

    $switch:
      $case env::LINUX:
        ctx.poll_fd = epoll::epoll_create1(0);
        @assert(ctx.poll_fd >= 0);
      $case env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        ctx.poll_fd = event::kqueue();
        @assert(ctx.poll_fd >= 0);
      $default:
        ctx.poll_fd = -1; // select-based: no fd needed
    $endswitch
    
    Fd[2]? rw = io::pipe_open();
    if (catch err = rw)
    {
        warn("pipe_open() failed: %s", err);
    
        if (!fd_invalid(ctx.poll_fd)) unistd::close(ctx.poll_fd);
        aio::localmem.free(ctx);
        ctx = null;
    
        return;
    }    
    ctx.wake_r = rw[0];
    ctx.wake_w = rw[1];
    
    FdWatch* wake = find_or_create(ctx.wake_r);
    wake.internal = true;
    epoll_ctl(wake, true, false);
    kqueue_ctl(wake, true, false);
}

fn void deinit() @finalizer
{
    if (ctx == null) return;

    if (!fd_invalid(ctx.poll_fd)) unistd::close(ctx.poll_fd);
    if (!fd_invalid(ctx.wake_r)) unistd::close(ctx.wake_r);
    if (!fd_invalid(ctx.wake_w)) unistd::close(ctx.wake_w);

    aio::localmem.free(ctx);
    ctx = null;
}

fn bool set_nonblocking(Fd fd)
{
    int flags = fcntl::fcntl(fd, fcntl::F_GETFL, 0);
    if (flags < 0) return false;
    return fcntl::fcntl(fd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK) == 0;
}

fn FdWatch* find_or_create(Fd fd) @private
{
    @assert(fd >= 0 && (usz)fd < MAX_FD_WATCH);
    FdWatch* w = &ctx.fd_table[fd];
    if (!w.active)
    {
        *w = {
            .fd = fd,
            .active = true,
            .internal = false,
            .poll_read_registered = false,
            .poll_write_registered = false,
            .read_fut = null,
            .write_fut = null,
        };       
        ctx.fd_count++;
    }
    return w;
}

fn FdWatch* find(Fd fd) @private
{
    if (fd < 0 || (usz)fd >= MAX_FD_WATCH) return null;
    FdWatch* w = &ctx.fd_table[fd];
    return w.active ? w : null;
}

fn void epoll_ctl(FdWatch* w, bool want_read, bool want_write) @private
{
    $if env::LINUX:
        if (!want_read && !want_write)
        {
            if (w.poll_read_registered || w.poll_write_registered)
            {
                epoll::epoll_ctl(ctx.poll_fd, epoll::EPOLL_CTL_DEL, w.fd, null);
                w.poll_read_registered = want_read;
                w.poll_write_registered = want_write;
            }

            return;
        }

        epoll::EpollEvent ev;
        ev.events = 0;

        if (want_read) ev.events |= epoll::EPOLLIN;
        if (want_write) ev.events |= epoll::EPOLLOUT;

        ev.data.fd = w.fd;

        int op = (w.poll_read_registered || w.poll_write_registered) ? epoll::EPOLL_CTL_MOD : epoll::EPOLL_CTL_ADD;
        int r = epoll::epoll_ctl(ctx.poll_fd, op, w.fd, &ev);

        if (r != -1)
        {
            w.poll_read_registered = want_read;
            w.poll_write_registered = want_write;
        }
    $endif
}

fn void kqueue_ctl(FdWatch* w, bool want_read, bool want_write) @private
{
    $if env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        event::Kevent[4] changes;
        usz n = 0;
        if (want_read)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_READ, event::EV_ADD | event::EV_ENABLE, 0, 0, null);
        }
        else if (w.poll_read_registered)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_READ,  event::EV_DELETE, 0, 0, null);
        }
        
        if (want_write)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_WRITE, event::EV_ADD | event::EV_ENABLE, 0, 0, null);
        }
        else if (w.poll_write_registered)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_WRITE, event::EV_DELETE, 0, 0, null);
        }
        
        if (n > 0)
        {
            int rc = event::kevent(ctx.poll_fd, changes, (int)n, null, 0, null);
            if (rc < 0) return;
        }
        
        w.poll_read_registered = want_read;
        w.poll_write_registered = want_write;
    $endif
}

fn void register_read(Fd fd, Future* future) @private
{
    FdWatch* w = find_or_create(fd);
    if (w.read_fut != null)
    {
        w.read_fut.cancel();
    }
    w.read_fut = future;
    epoll_ctl(w, true, w.write_fut != null);
    kqueue_ctl(w, true, w.write_fut != null);
}

fn void register_write(Fd fd, Future* future) @private
{
    FdWatch* w = find_or_create(fd);
    if (w.write_fut != null)
    {
        w.write_fut.cancel();
    }
    w.write_fut = future;
    epoll_ctl(w, w.read_fut != null, true);
    kqueue_ctl(w, w.read_fut != null, true);
}

fn void unregister(Fd fd) @private
{
    FdWatch* w = find(fd);
    if (w == null) return;

    // Cancel any tasks waiting on this fd before tearing down.
    if (w.read_fut)
    {
        w.read_fut.cancel();
        w.read_fut  = null;
    }
    if (w.write_fut)
    {
        w.write_fut.cancel();
        w.write_fut = null;
    }

    $switch:
      $case env::LINUX:
        epoll::epoll_ctl(ctx.poll_fd, epoll::EPOLL_CTL_DEL, fd, null);
      $case env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        event::Kevent[2] ch;
        event::ev_set(&ch[0], fd, event::EVFILT_READ, event::EV_DELETE, 0, 0, null);
        event::ev_set(&ch[1], fd, event::EVFILT_WRITE, event::EV_DELETE, 0, 0, null);
        event::kevent(ctx.poll_fd, ch, 2, null, 0, null);
    $endswitch

    w.active = false;
    w.poll_read_registered = false;
    w.poll_write_registered = false;

    ctx.fd_count--;
}

fn void? wait_readable(Fd fd) @maydiscard
{
    Future* fut = aio::future_new()!; defer fut.free();
        
    register_read(fd, fut);
    
    void*? res = fut.await();
    if (catch err = res)
    {
        FdWatch* w = find(fd);
        if (w != null && w.read_fut == fut)
        {
            w.read_fut = null;
            epoll_ctl(w, false, w.write_fut != null);
            kqueue_ctl(w, false, w.write_fut != null);
        }        
        if (fut.error == aio::IO_ERROR)
        {
            return aio::IO_ERROR~;
        }
        return err~;
    }
}

fn void? wait_writable(Fd fd) @maydiscard
{
    Future* fut = aio::future_new()!; defer fut.free();
        
    register_write(fd, fut);
    
    void*? res = fut.await();
    if (catch err = res)
    {
        FdWatch* w = find(fd);
        if (w != null && w.write_fut == fut)
        {
            w.write_fut = null;
            epoll_ctl(w, w.read_fut != null, false);
            kqueue_ctl(w, w.read_fut != null, false);
        }        
        if (fut.error == aio::IO_ERROR) return aio::IO_ERROR~;
        return err~;
    }
}

fn void poll_wake()
{
    if (ctx == null) return;
    if (io::fd_invalid(ctx.wake_w)) return;

    char[1] buf = { 1 };

    // Must be thread-safe raw write.
    (void)unistd::write(ctx.wake_w, &buf[0], 1);
}

fn void? poll_wakeup_handler() @maydiscard
{
    char[64] buf;

    while (true)
    {
        usz? n = unistd::read(ctx.wake_r, &buf[0], buf.len);

        if (catch err = n)
        {
            if (would_block()) break;
            break;
        }

        if (n == 0) break;

        if (n < buf.len) break;
    }

    aio::current_loop().threadsafe.process()!;
}

fn bool pending() @inline 
{
    for (usz i = 0; i < MAX_FD_WATCH; i++)
    {
        FdWatch* w = &ctx.fd_table[i];
        if (!w.active) continue;
        if (w.internal) continue;

        if (w.read_fut != null) return true;
        if (w.write_fut != null) return true;
    }

    return false;
}

fn void poll(ulong timeout_us) @if(env::LINUX)
{
    epoll::EpollEvent[MAX_EVENTS] events;
    ulong ms = timeout_us / 1000;
    int timeout_ms = ms > 2_147_483_647 ? -1 : (int)ms;
    int n = epoll::epoll_wait(ctx.poll_fd, &events, MAX_EVENTS, timeout_ms);
    
    for (int i = 0; i < n; i++)
    {
        Fd fd = events[i].data.fd;

        if (fd == ctx.wake_r)
        {
            poll_wakeup_handler();

            FdWatch* w = find(fd);
            if (w != null)
            {
                epoll_ctl(w, true, false);
            }

            continue;
        }

        uint evs = events[i].events;
        FdWatch* w = find(fd);
        if (w == null) continue;

        if ((evs & epoll::EPOLLERR) != 0)
        {
            if (w.read_fut)
            { 
                Future* f = w.read_fut;
                w.read_fut = null;
                f.cancel(aio::POLL_ERROR);
            }

            if (w.write_fut)
            { 
                Future* f = w.write_fut;
                w.write_fut = null;
                f.cancel(aio::POLL_ERROR);
            }

            epoll_ctl(w, false, false);
            continue;
        }

        bool readable = (evs & epoll::EPOLLIN) != 0;
        bool writable = (evs & epoll::EPOLLOUT) != 0;
        bool hup = (evs & epoll::EPOLLHUP) != 0;

        if ((readable || hup) && w.read_fut)
        {
            Future* f = w.read_fut;
            w.read_fut = null;

            epoll_ctl(w, false, w.write_fut != null);

            f.set_result(null);
            continue;
        }
        
        if (writable && w.write_fut)
        {
            Future* f = w.write_fut;
            w.write_fut = null;

            epoll_ctl(w, w.read_fut != null, false);

            f.set_result(null);
            continue;
        }

        if (hup)
        {
            if (w.write_fut)
            {
                Future* f = w.write_fut;
                w.write_fut = null;
                epoll_ctl(w, w.read_fut != null, false);
                f.cancel(aio::POLL_ERROR);
            }

            continue;
        }
    }
}

fn void poll(ulong timeout_us) @if(env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD)
{
    event::Kevent[MAX_EVENTS] events;
    event::TimeSpec ts = { (long)(timeout_us / 1_000_000), (long)((timeout_us % 1_000_000) * 1000) };
    int n = event::kevent(ctx.poll_fd, null, 0, &events, MAX_EVENTS, &ts);
    for (int i = 0; i < n; i++)
    {
        int fd = (int)events[i].ident;
        if (fd == ctx.wake_r)
        {
            poll_wakeup_handler();
            continue;
        }

        FdWatch* w = find(fd);
        if (w == null) continue;
        if ((events[i].flags & event::EV_ERROR))
        {
            if (w.read_fut)
            { 
                w.read_fut.cancel(aio::POLL_ERROR);
                w.read_fut  = null;
            }
            if (w.write_fut)
            { 
                w.write_fut.cancel(aio::POLL_ERROR);
                w.write_fut = null;
            }
            unregister(fd);
            continue;
        }

        bool eof = (events[i].flags & event::EV_EOF) != 0;
        
        if (events[i].filter == event::EVFILT_READ && w.read_fut)
        {
            Future* f = w.read_fut;
            w.read_fut = null;
            kqueue_ctl(w, false, w.write_fut != null);
            f.set_result(null); // caller read() 0 && eof handle
        }
        if (events[i].filter == event::EVFILT_WRITE && w.write_fut)
        {
            Future* f = w.write_fut;
            w.write_fut = null;
        
            kqueue_ctl(w, w.read_fut != null, false);
        
            if (eof)
            {
                f.cancel(aio::POLL_ERROR);
            }
            else
            {
                f.set_result(null);
            }
        }
    }
}

fn void poll(ulong timeout_us) @if(false)
{
    select::FdSet rfds;
    select::FdSet wfds;
    select::FdSet efds;
        
    select::fd_zero(&rfds);
    select::fd_zero(&wfds);
    select::fd_zero(&efds);
    int maxfd = -1;
    for (usz i = 0; i < MAX_FD_WATCH; i++)
    {
        FdWatch* w = &ctx.fd_table[i];
        if (!w.active) continue;
        if (w.read_fut)
        {
            select::fd_set(w.fd, &rfds);
            select::fd_set(w.fd, &efds);
        }
        if (w.write_fut)
        {
            select::fd_set(w.fd, &wfds);
            select::fd_set(w.fd, &efds);
        }
        if (w.fd > maxfd) maxfd = w.fd;
    }
    if (maxfd < 0) return;
    select::TimeVal tv = { (long)(timeout_us / 1_000_000), (long)(timeout_us % 1_000_000) };
    select::select(maxfd + 1, &rfds, &wfds, &efds, &tv);
    for (usz i = 0; i < MAX_FD_WATCH; i++)
    {
        FdWatch* w = &ctx.fd_table[i];
        if (!w.active) continue;
        if (select::fd_isset(w.fd, &efds))
        {
            if (w.read_fut)
            { 
                w.read_fut.cancel(aio::POLL_ERROR);
                w.read_fut  = null;
            }
            if (w.write_fut)
            { 
                w.write_fut.cancel(aio::POLL_ERROR);
                w.write_fut = null;
            }
            unregister(w.fd);
            continue;
        }
        if (select::fd_isset(w.fd, &rfds) && w.read_fut)
        {
            Future* f = w.read_fut;
            w.read_fut = null;
            f.set_result(null);
        }
        if (select::fd_isset(w.fd, &wfds) && w.write_fut)
        {
            Future* f = w.write_fut;
            w.write_fut = null;
            f.set_result(null);
        }
    }
}

fn bool would_block() @inline
{
    int e = errno::errno();
    return e == errno::EAGAIN || e == errno::EWOULDBLOCK;
}

fn usz? async_read(Fd fd, char[] buf) 
{
    while (true)
    {
        isz n = unistd::read(fd, buf.ptr, buf.len);
        if (n >= 0) return (usz)n;
        if (!would_block()) return errno::get_fault()~;

        wait_readable(fd)!;
    }
}

fn usz? async_write(Fd fd, char[] buf) 
{
    usz total = 0;
    while (total < buf.len)
    {
        isz n = unistd::write(fd, buf.ptr + total, buf.len - total);
        if (n > 0) { total += (usz)n; continue; }
        if (n == 0) break;
        if (!would_block())
        {
            if (total > 0) return total;
            return errno::get_fault()~;
        }
        
        wait_writable(fd)!;
    }
    return total;
}

fn usz? async_recvfrom(Fd fd, char[] buf, char* ip_str, usz* ip_len, ushort* port) 
{
    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (ip_len == null) return errno::E_INVALID_ARG~;
    if (port == null) return errno::E_INVALID_ARG~;

    while (true)
    {
        socket::SockAddrStorage ss;
        socket::SockLen sslen = $sizeof(ss);

        isz n = socket::recvfrom(fd, buf.ptr, buf.len, 0, (socket::SockAddr*)&ss, &sslen);
        if (n >= 0)
        {
            // sender addr extraction
            if (ss.ss_family == (ushort)socket::AF_INET6)
            {
                in::SockAddrIn6* a6 = (in::SockAddrIn6*)&ss;
                in::inet_ntop(socket::AF_INET6, &a6.sin6_addr, ip_str, 46);
                *ip_len = (usz)string::strlen(ip_str);
                *port = in::ntohs(a6.sin6_port);
            }
            else
            {
                in::SockAddrIn* a4 = (in::SockAddrIn*)&ss;
                in::inet_ntop(socket::AF_INET, &a4.sin_addr, ip_str, 16);
                *ip_len = (usz)string::strlen(ip_str);
                *port = in::ntohs(a4.sin_port);
            }

            return (usz)n;
        }

        if (!would_block()) return errno::get_fault()~;

        wait_readable(fd)!;
    }
}

fn usz? async_sendto(Fd fd, char[] buf, char* ip_str, ushort port) 
{
    socket::SockAddr* dest_addr;
    socket::SockLen dest_len;

    in::SockAddrIn a4;
    in::SockAddrIn6 a6;

    if (string::strchr(ip_str, ':') != null) 
    {
        if (in::inet_pton(socket::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return errno::get_fault()~;
        }
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = in::htons(port);
        dest_addr = (socket::SockAddr*)&a6;
        dest_len = $sizeof(a6);
    }
    else 
    {
        a4.sin_family = (ushort)socket::AF_INET;
        a4.sin_port = in::htons(port);
        if (in::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1) 
        {
            return errno::get_fault()~;
        }
        dest_addr = (socket::SockAddr*)&a4;
        dest_len = $sizeof(a4);
    }

    while (true)
    {
        isz n = socket::sendto(fd, buf.ptr, buf.len, 0, dest_addr, dest_len);
        if (n >= 0) return (usz)n;

        if (!would_block()) return errno::get_fault()~;

        wait_writable(fd)!;
    }
}

fn Fd[2]? pipe_open()
{
    CInt[2] fds;
    if (unistd::pipe(&fds) < 0) 
    {
        return errno::get_fault()~;
    }
    
    set_nonblocking(fds[0]);
    set_nonblocking(fds[1]);
    
    return { (Fd)fds[0], (Fd)fds[1] };
}

// socket/pipe, pollable fd
fn void fd_close(Fd fd)
{
    unregister(fd);
    unistd::close(fd);
}

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
    char[] buf;
    usz result;
    int permission;
}

fn char* str2cptr(String str, char[] buf) @inline @private
{
    usz len = (str.len <= buf.len-1)? str.len: buf.len-1;
    buf[0:len] = str[0:len];
    buf[len] = 0;
    return &buf[0];
}

fn void* file_open_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;
    
    char[256] buf;
    char* path_cstr = str2cptr(arg.name, &buf);
    
    int flags = 0;
    switch (arg.mode)
    {
      case "r": flags = fcntl::O_RDONLY;
      case "r+": flags = fcntl::O_RDWR;
      case "w": flags = fcntl::O_WRONLY | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "w+": flags = fcntl::O_RDWR | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "a": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_WRONLY;
      case "a+": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_RDWR;
      default:  
          arg.error = errno::E_INVALID_ARG;
          return v_arg;
    }

    Fd fd = fcntl::open(path_cstr, flags, arg.permission);
    if (fd < 0) 
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    
    arg.fd = fd;

    return v_arg;
}

fn Fd? file_open(String name, String mode, int permission = 0o0644)
{
    Arg arg = {
        .error = NONE,
        .name = name,
        .mode = mode,
        .permission = permission,
    };
    
    Arg*? a = aio::run_in_executor(&file_open_blocking, &arg);
    
    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
    
    return a.fd;
}

fn void* file_close_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;

    int rc = unistd::close(arg.fd);
    if (rc < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    
    return v_arg;
}

fn void? file_close(Fd fd) @maydiscard
{
    Arg arg = {
        .error = NONE,
        .fd = fd,
    };

    Arg*? a = aio::run_in_executor(&file_close_blocking, &arg);

    if (catch err = a) return err~;
    if (a.error != NONE) return a.error~;
}

// off_t = long

fn void* file_seek_blocking(void* v_arg) @local
{
    Arg* arg = (Arg*)v_arg;
    
    long offset = unistd::lseek(arg.fd, arg.pos, arg.whence);
    if (offset < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    arg.offset = offset;
    
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
    
    long offset = unistd::lseek(arg.fd, 0, unistd::SEEK_CUR);
    if (offset < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    arg.offset = offset;
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
    
    int rc = unistd::ftruncate(arg.fd, arg.pos);
    if (rc < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }
    
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

    int rc = unistd::fsync(arg.fd);
    if (rc < 0)
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

    stat::Stat_t st;
    int rc = stat::fstat(arg.fd, &st);
    if (rc < 0)
    {
        arg.error = errno::get_fault();
        return v_arg;
    }

    arg.offset = (long)st.st_size;

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

    isz n = unistd::read(arg.fd, arg.buf.ptr, arg.buf.len);
    if (n < 0)
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
        isz n = unistd::write(arg.fd, arg.buf.ptr + total, arg.buf.len - total);

        if (n > 0)
        {
            total += (usz)n;
            continue;
        }

        if (n == 0)
        {
            break;
        }

        arg.error = errno::get_fault();
        arg.result = total;

        return v_arg;
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
    set_nonblocking(0);
    return 0;
}

fn Fd fd_stdout()
{
    set_nonblocking(1);
    return 1;
}

fn Fd fd_stderr()
{
    set_nonblocking(2);
    return 2;
}

// eof