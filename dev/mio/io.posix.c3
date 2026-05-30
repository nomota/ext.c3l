// io.posix.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::POSIX);

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

const sz MAX_EVENTS = 4096;
const sz MAX_FD_WATCH  = 20_000;
const sz MAX_SELECT_FD = 1024;

alias Fd = int;

macro bool fd_invalid(Fd fd)
{
    return fd < 0;
}

macro Fd fd_null()
{
    return -1;
}

struct FdWatch @local
{
    Fd fd;
    bool active;
    bool internal;
    bool want_read;
    bool want_write;
}

// poll result
struct Event 
{
    Fd fd;
    bool error;
    bool readable;
    bool writable;
}

struct IoContext @local
{
    FdWatch[MAX_FD_WATCH] fd_table;
    sz fd_count;
    Fd poll_fd; // epoll fd or kqueue fd

    // poll wake pipe
    Fd wake_r;
    Fd wake_w;
}

tlocal IoContext* ctx @local = null;
LocalAllocator localmem = null;

fn void init()
{
    if (ctx != null) return;
    if (localmem == null) localmem = mem;
    ctx = localmem.alloc(IoContext)!!;
    *ctx = {
        .fd_count = 0,
        .poll_fd = fd_null(),
        .wake_r = fd_null(),
        .wake_w = fd_null(),
    };    
    for (sz i = 0; i < MAX_FD_WATCH; i++)
    {
        ctx.fd_table[i] = {};
    }

    $switch:
      $case env::LINUX:
        ctx.poll_fd = epoll::epoll_create1(0);
        if (ctx.poll_fd < 0)
        {
            localmem.free(ctx);
            ctx = null;
            return;
        }
      $case env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        ctx.poll_fd = event::kqueue();
        if (ctx.poll_fd < 0)
        {
            localmem.free(ctx);
            ctx = null;
            return;
        }
      $default:
        ctx.poll_fd = -1; // select-based: no fd needed
    $endswitch
    
    Fd[2]? rw = pipe_open();
    if (catch err = rw)
    {
        warn("pipe_open() failed: %s", err);
    
        if (!fd_invalid(ctx.poll_fd)) unistd::close(ctx.poll_fd);
        localmem.free(ctx);
        ctx = null;
    
        return;
    }    
    ctx.wake_r = rw[0];
    ctx.wake_w = rw[1];
    
    FdWatch* wake = find_or_create(ctx.wake_r);
    wake.internal = true;
    $if env::LINUX:
        epoll_ctl(wake, true, false)!!;
    $elseif env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        kqueue_ctl(wake, true, false)!!;
    $else:
        wake.want_read = true;
    $endif
}

fn void deinit()
{
    if (ctx == null) return;

    if (!fd_invalid(ctx.poll_fd)) unistd::close(ctx.poll_fd);
    if (!fd_invalid(ctx.wake_r)) unistd::close(ctx.wake_r);
    if (!fd_invalid(ctx.wake_w)) unistd::close(ctx.wake_w);

    localmem.free(ctx);
    ctx = null;
}

fn bool set_nonblocking(Fd fd)
{
    int flags = fcntl::fcntl(fd, fcntl::F_GETFL, 0);
    if (flags < 0) return false;
    return fcntl::fcntl(fd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK) == 0;
}

fn FdWatch* find_or_create(Fd fd) @local
{
    @assert(fd >= 0);

    $if !env::LINUX && !(env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD):
        @assert((sz)fd < 1024);
    $else:
        @assert((sz)fd < MAX_FD_WATCH);
    $endif

    FdWatch* w = &ctx.fd_table[fd];
    if (!w.active)
    {
        *w = {
            .fd = fd,
            .active = true,
            .internal = false,
            .want_read = false,
            .want_write = false,
        };
        ctx.fd_count++;
    }
    return w;
}

fn FdWatch* find(Fd fd) @private
{
    if (fd < 0 || (sz)fd >= MAX_FD_WATCH) return null;
    FdWatch* w = &ctx.fd_table[fd];
    return w.active ? w : null;
}

fn void? epoll_ctl(FdWatch* w, bool want_read, bool want_write) @private
{
    $if env::LINUX:
        if (!want_read && !want_write)
        {
            if (w.want_read || w.want_write)
            {
                int r = epoll::epoll_ctl(ctx.poll_fd, epoll::EPOLL_CTL_DEL, w.fd, null);
                if (r < 0)
                {
                    return errno::get_fault()~;
                }
            }

            w.want_read = false;
            w.want_write = false;
        }

        epoll::EpollEvent ev;
        ev.events = 0;

        if (want_read) ev.events |= epoll::EPOLLIN;
        if (want_write) ev.events |= epoll::EPOLLOUT;

        ev.data.fd = w.fd;

        int op = (w.want_read || w.want_write) ? epoll::EPOLL_CTL_MOD : epoll::EPOLL_CTL_ADD;
        int r = epoll::epoll_ctl(ctx.poll_fd, op, w.fd, &ev);
        if (r < 0)
        {
            return errno::get_fault()~;
        }

        w.want_read = want_read;
        w.want_write = want_write;
    $endif
}

fn void? kqueue_ctl(FdWatch* w, bool want_read, bool want_write) @private
{
    $if env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        event::Kevent[4] changes;
        sz n = 0;
        if (want_read)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_READ, event::EV_ADD | event::EV_ENABLE, 0, 0, null);
        }
        else if (w.want_read)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_READ,  event::EV_DELETE, 0, 0, null);
        }
        
        if (want_write)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_WRITE, event::EV_ADD | event::EV_ENABLE, 0, 0, null);
        }
        else if (w.want_write)
        {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_WRITE, event::EV_DELETE, 0, 0, null);
        }
        
        if (n > 0)
        {
            int rc = event::kevent(ctx.poll_fd, changes, (int)n, null, 0, null);
            if (rc < 0) return errno::get_fault()~;
        }
        
        w.want_read = want_read;
        w.want_write = want_write;
    $endif
}

fn void? register_read(Fd fd) @private
{
    FdWatch* w = find_or_create(fd);
    $if env::LINUX:
        epoll_ctl(w, true, w.want_write)!;
    $elseif env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        kqueue_ctl(w, true, w.want_write)!;
    $else:
        w.want_read = true;
    $endif
}

fn void? register_write(Fd fd) @private
{
    FdWatch* w = find_or_create(fd);
    $if env::LINUX:
        epoll_ctl(w, w.want_read, true)!;
    $elseif env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        kqueue_ctl(w, w.want_read, true)!;
    $else:
        w.want_write = true;
    $endif
}

fn void unregister(Fd fd) @private
{
    FdWatch* w = find(fd);
    if (w == null) return;

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
    w.internal = false;
    w.want_read = false;
    w.want_write = false;

    ctx.fd_count--;
}

fn void poll_wake()
{
    if (ctx == null) return;
    if (fd_invalid(ctx.wake_w)) return;

    char[1] buf = { 1 };

    // Must be thread-safe raw write.
    (void)unistd::write(ctx.wake_w, &buf[0], 1);
}

fn void? poll_wakeup_handler() @maydiscard
{
    char[64] buf;

    while (true)
    {
        sz? n = unistd::read(ctx.wake_r, &buf[0], buf.len);

        if (catch err = n)
        {
            if (would_block()) break;
            break;
        }

        if (n == 0) break;

        if (n < buf.len) break;
    }

    // thread wake process here
}

fn bool pending() @inline 
{
    if (ctx == null) return false;
    
    for (sz i = 0; i < MAX_FD_WATCH; i++)
    {
        FdWatch* w = &ctx.fd_table[i];
        if (!w.active) continue;
        if (w.internal) continue;

        if (w.want_read) return true;
        if (w.want_write) return true;
    }

    return false;
}

faultdef POLL_ERROR;

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

fn void? poll(Event[] revents, sz *n_revents, ulong timeout_us) @if(env::LINUX)
{
    epoll::EpollEvent[MAX_EVENTS] events;

    ulong ms = timeout_us / 1000;
    if (timeout_us > 0 && ms == 0) ms = 1;
    int timeout_ms = ms > 2_147_483_647 ? 2_147_483_647 : (int)ms;

    int n = epoll::epoll_wait(ctx.poll_fd, &events, MAX_EVENTS, timeout_ms);
    if (n < 0)
    {
        if (errno::errno() == errno::EINTR)
        {
            *n_revents = 0;
            return;
        }
    
        return errno::get_fault()~;
    }
    
    sz idx = 0;
    for (int i = 0; i < n; i++)
    {
        Fd fd = events[i].data.fd;

        if (fd == ctx.wake_r)
        {
            poll_wakeup_handler();

            FdWatch* w = find(fd);
            if (w != null)
            {
                epoll_ctl(w, true, false)!;
            }

            continue;
        }

        uint evs = events[i].events;
        FdWatch* w = find(fd);
        if (w == null) continue;

        if ((evs & epoll::EPOLLERR) != 0)
        {
            push_event(revents, &idx, fd, true, false, false)!;
            
            epoll_ctl(w, false, false)!;
            continue;
        }

        bool readable = (evs & epoll::EPOLLIN) != 0;
        bool writable = (evs & epoll::EPOLLOUT) != 0;
        bool hup = (evs & epoll::EPOLLHUP) != 0;

        if ((readable || hup) && w.want_read)
        {
            push_event(revents, &idx, fd, false, true, false)!;
            
            epoll_ctl(w, false, w.want_write)!;
            continue;
        }
        
        if ((writable || hup) && w.want_write)
        {
            push_event(revents, &idx, fd, false, false, true)!;
             
            epoll_ctl(w, w.want_read, false)!;
            continue;
        }
    }

    *n_revents = idx;
}

fn void? poll(Event[] revents, sz* n_revents, ulong timeout_us) @if(env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD)
{
    event::Kevent[MAX_EVENTS] events;
 
    ulong sec = timeout_us / 1_000_000;
    ulong nsec = (timeout_us % 1_000_000) * 1000;
    if (sec > 2_147_483_647) sec = 2_147_483_647;
    event::TimeSpec ts = {
        (long)sec,
        (long)nsec,
    };   
    
    int n = event::kevent(ctx.poll_fd, null, 0, &events, MAX_EVENTS, &ts);
    if (n < 0)
    {
        if (errno::errno() == errno::EINTR)
        {
            *n_revents = 0;
            return;
        }
    
        return errno::get_fault()~;
    }

    sz idx = 0;
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
        if (((events[i].flags & event::EV_ERROR)) != 0)
        {
            push_event(revents, &idx, fd, true, false, false)!;
 
            unregister(fd);
            continue;
        }

        bool eof = (events[i].flags & event::EV_EOF) != 0;
        
        if (events[i].filter == event::EVFILT_READ && w.want_read)
        {
            push_event(revents, &idx, fd, false, true, false)!;
 
            kqueue_ctl(w, false, w.want_write)!;
            continue;
        }
        
        if (events[i].filter == event::EVFILT_WRITE && w.want_write)
        {
            if (eof)
            {
                push_event(revents, &idx, fd, true, false, false)!;
                
                kqueue_ctl(w, w.want_read, false)!;
                continue;
            }

            push_event(revents, &idx, fd, false, false, true)!;
             
            kqueue_ctl(w, w.want_read, false)!;
            continue;
        }
    }
    
    *n_revents = idx;
}

fn void? poll(Event[] revents, sz *n_revents, ulong timeout_us) @if(!env::LINUX && !(env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD))
{
    select::FdSet rfds;
    select::FdSet wfds;
    select::FdSet efds;
        
    select::fd_zero(&rfds);
    select::fd_zero(&wfds);
    select::fd_zero(&efds);
    int maxfd = -1;
    sz idx = 0;
    for (sz i = 0; i < MAX_FD_WATCH; i++)
    {
        FdWatch* w = &ctx.fd_table[i];
        if (!w.active) continue;
        
        if ((sz)w.fd >= MAX_SELECT_FD)
        {
            continue;
        }

        if (w.want_read)
        {
            select::fd_set(w.fd, &rfds);
            select::fd_set(w.fd, &efds);
        }
        if (w.want_write)
        {
            select::fd_set(w.fd, &wfds);
            select::fd_set(w.fd, &efds);
        }
        if (w.fd > maxfd) maxfd = w.fd;
    }
    if (maxfd < 0)
    {
        *n_revents = 0;
        return;
    }

    select::TimeVal tv = { (long)(timeout_us / 1_000_000), (long)(timeout_us % 1_000_000) };

    int rc = select::select(maxfd + 1, &rfds, &wfds, &efds, &tv);
    if (rc < 0)
    {
        if (errno::errno() == errno::EINTR)
        {
            *n_revents = 0;
            return;
        }
    
        return errno::get_fault()~;
    }
    if (rc == 0)
    {
        *n_revents = 0;
        return;
    }

    for (sz i = 0; i < MAX_FD_WATCH; i++)
    {
        FdWatch* w = &ctx.fd_table[i];
        if (!w.active) continue;
        
        if ((sz)w.fd >= MAX_SELECT_FD)
        {
            continue;
        }
        
        if (w.fd == ctx.wake_r && select::fd_isset(w.fd, &rfds))
        {
            poll_wakeup_handler();
            w.want_read = true;
            continue;
        }

        if (select::fd_isset(w.fd, &efds))
        {
            push_event(revents, &idx, w.fd, true, false, false)!;
 
            unregister(w.fd);
            continue;
        }
        
        if (select::fd_isset(w.fd, &rfds) && w.want_read)
        {
            push_event(revents, &idx, w.fd, false, true, false)!;
            w.want_read = false;
        }
        
        if (select::fd_isset(w.fd, &wfds) && w.want_write)
        {
            push_event(revents, &idx, w.fd, false, false, true)!;
            w.want_write = false;
        }
    }

    *n_revents = idx;
}

fn bool would_block() @inline
{
    int e = errno::errno();
    return e == errno::EAGAIN || e == errno::EWOULDBLOCK;
}

fn sz? async_read(Fd fd, char[] buf) 
{
    sz n = unistd::read(fd, buf.ptr, buf.len);
    if (n >= 0) return (sz)n;
    if (!would_block()) return errno::get_fault()~;
    return errno::E_WOULD_BLOCK~;
}

fn sz? async_write(Fd fd, char[] buf) 
{
    sz n = unistd::write(fd, buf.ptr, buf.len);
    if (n >= 0) return (sz)n;
    if (!would_block()) return errno::get_fault()~;
    return errno::E_WOULD_BLOCK~;
}

fn sz? async_recvfrom(Fd fd, char[] buf, char* ip_str, sz* ip_len, ushort* port) 
{
    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (ip_len == null) return errno::E_INVALID_ARG~;
    if (port == null) return errno::E_INVALID_ARG~;

    socket::SockAddrStorage ss;
    socket::SockLen sslen = @sizeof(ss);

    sz n = socket::recvfrom(fd, buf.ptr, buf.len, 0, (socket::SockAddr*)&ss, &sslen);
    if (n >= 0)
    {
        // sender addr extraction
        if (ss.ss_family == (ushort)socket::AF_INET6)
        {
            in::SockAddrIn6* a6 = (in::SockAddrIn6*)&ss;
            char* p = in::inet_ntop(socket::AF_INET6, &a6.sin6_addr, ip_str, 46);
            if (p == null) return errno::get_fault()~;
            *ip_len = (sz)string::strlen(ip_str);
            *port = in::ntohs(a6.sin6_port);
        }
        else if (ss.ss_family == (ushort)socket::AF_INET)
        {
            in::SockAddrIn* a4 = (in::SockAddrIn*)&ss;
            char* p = in::inet_ntop(socket::AF_INET, &a4.sin_addr, ip_str, 16);
            if (p == null) return errno::get_fault()~;
            *ip_len = (sz)string::strlen(ip_str);
            *port = in::ntohs(a4.sin_port);
        }
        else
        {
            return errno::E_INVALID_ARG~;
        }
        return (sz)n;
    }

    if (!would_block()) return errno::get_fault()~;
    return errno::E_WOULD_BLOCK~;
}

fn sz? async_sendto(Fd fd, char[] buf, char* ip_str, ushort port) 
{
    if (ip_str == null) return errno::E_INVALID_ARG~;

    socket::SockAddr* dest_addr;
    socket::SockLen dest_len;

    in::SockAddrIn a4 = {};
    in::SockAddrIn6 a6 = {};

    if (string::strchr(ip_str, ':') != null) 
    {
        if (in::inet_pton(socket::AF_INET6, ip_str, &a6.sin6_addr) != 1)
        {
            return errno::E_INVALID_ARG~;
        }
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = in::htons(port);
        dest_addr = (socket::SockAddr*)&a6;
        dest_len = @sizeof(a6);
    }
    else 
    {
        a4.sin_family = (ushort)socket::AF_INET;
        a4.sin_port = in::htons(port);
        if (in::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1) 
        {
            return errno::E_INVALID_ARG~;
        }
        dest_addr = (socket::SockAddr*)&a4;
        dest_len = @sizeof(a4);
    }

    sz n = socket::sendto(fd, buf.ptr, buf.len, 0, dest_addr, dest_len);
    if (n >= 0) return (sz)n;

    if (!would_block()) return errno::get_fault()~;
    return errno::E_WOULD_BLOCK~;
}

fn Fd[2]? pipe_open()
{
    CInt[2] fds;
    if (unistd::pipe(&fds) < 0) 
    {
        return errno::get_fault()~;
    }

    if (!set_nonblocking(fds[0]) || !set_nonblocking(fds[1]))
    {
        fault err = errno::get_fault();

        unistd::close(fds[0]);
        unistd::close(fds[1]);

        return err~;
    }

    return { (Fd)fds[0], (Fd)fds[1] };
}

// socket/pipe, pollable fd
fn void fd_close(Fd fd)
{
    if (fd_invalid(fd)) return;

    unregister(fd);
    unistd::close(fd);
}

// eof