// io.posix.c3

module ext::asyncio @if(!env::WIN32 && !env::LINUX);

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

const usz MAX_EVENTS = 1024;
const usz MAX_FD_WATCH  = 4096;

struct FdWatch {
    int fd;
    bool active;
    bool epoll_registered; // true once the fd has been added to epoll/kqueue
    Future* read_fut;
    Future* write_fut;
}

tlocal FdWatch[MAX_FD_WATCH] _fd_table;
tlocal usz _fd_count;
tlocal int _poll_fd; // epoll fd or kqueue fd

tlocal bool initialized = false;
fn void io_init() @private
{
    if (initialized) return;
    initialized = true;
    for (usz i = 0; i < MAX_FD_WATCH; i++) {
        _fd_table[i] = {};
    }

    $switch:
      $case env::LINUX:
        _poll_fd = epoll::epoll_create1(0);
        @assert(_poll_fd >= 0, "asyncio: epoll_create1 failed");
      $case env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        _poll_fd = event::kqueue();
        @assert(_poll_fd >= 0, "asyncio: kqueue failed");
      $default:
        _poll_fd = -1; // select-based: no fd needed
    $endswitch
}

fn void io_destroy() @private
{
    unistd::close(_poll_fd);
}

fn bool set_nonblocking(int fd) 
{
    int flags = fcntl::fcntl(fd, fcntl::F_GETFL, 0);
    if (flags < 0) return false;
    return fcntl::fcntl(fd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK) == 0;
}

fn FdWatch* _find_or_create(int fd) 
{
    @assert(fd >= 0 && (usz)fd < MAX_FD_WATCH, "asyncio: fd out of range");
    FdWatch* w = &_fd_table[fd];
    if (!w.active) {
        *w = { fd, true, false, null, null };
        _fd_count++;
    }
    return w;
}

fn FdWatch* _find(int fd) 
{
    if (fd < 0 || (usz)fd >= MAX_FD_WATCH) return null;
    FdWatch* w = &_fd_table[fd];
    return w.active ? w : null;
}

// Pass the FdWatch* so we can read/set epoll_registered.
fn void _epoll_ctl(FdWatch* w, bool want_read, bool want_write) 
{
    $if env::LINUX:
        epoll::EpollEvent ev;
        ev.events = 0;
        if (want_read)  ev.events |= epoll::EPOLLIN;
        if (want_write) ev.events |= epoll::EPOLLOUT;
        ev.data.fd = w.fd;
        // Use ADD for the first registration, MOD for subsequent updates.
        int op = w.epoll_registered ? epoll::EPOLL_CTL_MOD : epoll::EPOLL_CTL_ADD;
        int r = epoll::epoll_ctl(_poll_fd, op, w.fd, &ev);
        if (r != -1) {
            w.epoll_registered = true;
        }
    $endif
}

fn void _kqueue_ctl(FdWatch* w, bool want_read, bool want_write) 
{
    $if env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        event::Kevent[4] changes;
        usz n = 0;
        if (want_read) {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_READ, event::EV_ADD | event::EV_ENABLE, 0, 0, null);
        } else if (w.epoll_registered) {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_READ,  event::EV_DELETE, 0, 0, null);
        }
        if (want_write) {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_WRITE, event::EV_ADD | event::EV_ENABLE, 0, 0, null);
        } else if (w.epoll_registered) {
            event::ev_set(&changes[n++], w.fd, event::EVFILT_WRITE, event::EV_DELETE, 0, 0, null);
        }
        if (n > 0) event::kevent(_poll_fd, changes, (int)n, null, 0, null);
        // w.epoll_registered = true;
        w.epoll_registered = want_read || want_write;
    $endif
}

fn void register_read(int fd, Future* future) @private
{
    FdWatch* w = _find_or_create(fd);
    if (w.read_fut != null) {
        w.read_fut.cancel("register_read: replaced");
    }
    w.read_fut = future;
    _epoll_ctl(w, true, w.write_fut != null);
    _kqueue_ctl(w, true, w.write_fut != null);
}

fn void register_write(int fd, Future* future) @private
{
    FdWatch* w = _find_or_create(fd);
    if (w.write_fut != null) {
        w.write_fut.cancel("register_write: replaced");
    }
    w.write_fut = future;
    _epoll_ctl(w, w.read_fut != null, true);
    _kqueue_ctl(w, w.read_fut != null, true);
}

fn void unregister(int fd) @private
{
    FdWatch* w = _find(fd);
    if (w == null) return;

    // Cancel any tasks waiting on this fd before tearing down.
    if (w.read_fut)  {
        w.read_fut.cancel("fd unregistered");
        w.read_fut  = null;
    }
    if (w.write_fut) {
        w.write_fut.cancel("fd unregistered");
        w.write_fut = null;
    }

    $switch:
      $case env::LINUX:
        epoll::epoll_ctl(_poll_fd, epoll::EPOLL_CTL_DEL, fd, null);
      $case env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        event::Kevent[2] ch;
        event::ev_set(&ch[0], fd, event::EVFILT_READ,  event::EV_DELETE, 0, 0, null);
        event::ev_set(&ch[1], fd, event::EVFILT_WRITE, event::EV_DELETE, 0, 0, null);
        event::kevent(_poll_fd, ch, 2, null, 0, null);
    $endswitch

    w.active = false;
    w.epoll_registered = false;
    _fd_count--;
}

fn bool io_pending() @inline @private
{ 
    return _fd_count > 0; 
}

fn void io_poll(ulong timeout_us) @private
{
    if (_fd_count == 0) return;

    $switch:
      $case env::LINUX:
        epoll::EpollEvent[MAX_EVENTS] events;
        ulong ms = timeout_us / 1000;
        int timeout_ms = ms > 2_147_483_647 ? -1 : (int)ms;  // -1 = infinit waiting
        int n = epoll::epoll_wait(_poll_fd, &events, MAX_EVENTS, timeout_ms);
        //int n = epoll::epoll_wait(_poll_fd, &events, MAX_EVENTS, (int)(timeout_us / 1000));
        for (int i = 0; i < n; i++) {
            int fd = events[i].data.fd;
            uint evs = events[i].events;
            FdWatch* w = _find(fd);
            if (w == null) continue;
            if ((evs & (epoll::EPOLLERR | epoll::EPOLLHUP))) {
                if (w.read_fut) { 
                    w.read_fut.set_exception(IO_ERROR);
                    w.read_fut.cancel("io error");
                    w.read_fut  = null; 
                }
                if (w.write_fut) { 
                    w.write_fut.set_exception(IO_ERROR);
                    w.write_fut.cancel("io error");
                    w.write_fut = null; 
                }
                unregister(fd);
                continue;
            }
 
            if ((evs & epoll::EPOLLIN)  && w.read_fut) { 
                Future* f = w.read_fut;
                w.read_fut  = null;
                f.set_result(null);
            }
            if ((evs & epoll::EPOLLOUT) && w.write_fut) {
                Future* f = w.write_fut;
                w.write_fut = null;
                f.set_result(null);
            }
       }

      $case env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD:
        event::Kevent[MAX_EVENTS] events;
        event::TimeSpec ts = { (long)(timeout_us / 1_000_000), (long)((timeout_us % 1_000_000) * 1000) };
        int n = event::kevent(_poll_fd, null, 0, &events, MAX_EVENTS, &ts);
        for (int i = 0; i < n; i++) {
            int fd = (int)events[i].ident;
            FdWatch* w = _find(fd);
            if (w == null) continue;
            if ((events[i].flags & event::EV_ERROR)) {
                if (w.read_fut) { 
                    w.read_fut.set_exception(IO_ERROR);
                    w.read_fut.cancel("io error"); 
                    w.read_fut  = null;
                }
                if (w.write_fut) { 
                    w.write_fut.set_exception(IO_ERROR);
                    w.write_fut.cancel("io error");
                    w.write_fut = null;
                }
                unregister(fd);
                continue;
            }

            bool eof = (events[i].flags & event::EV_EOF) != 0;
        
            if (events[i].filter == event::EVFILT_READ && w.read_fut) {
                Future* f = w.read_fut;
                w.read_fut = null;
                f.set_result(null); // caller read() 0 && eof handle
            }
            if (events[i].filter == event::EVFILT_WRITE && w.write_fut) {
                if (eof) {
                    Future* f = w.write_fut;
                    w.write_fut = null;
                    f.set_exception(IO_ERROR);
                } else {
                    Future* f = w.write_fut;
                    w.write_fut = null;
                    f.set_result(null);
                }
            }

        }

      $default:
        select::FdSet rfds;
        select::FdSet wfds;
        select::FdSet efds;
        
        select::fd_zero(&rfds); select::fd_zero(&wfds); select::fd_zero(&efds);
        int maxfd = -1;
        for (usz i = 0; i < MAX_FD_WATCH; i++) {
            FdWatch* w = &_fd_table[i];
            if (!w.active) continue;
            if (w.read_fut)  { select::fd_set(w.fd, &rfds); select::fd_set(w.fd, &efds); }
            if (w.write_fut) { select::fd_set(w.fd, &wfds); select::fd_set(w.fd, &efds); }
            if (w.fd > maxfd) maxfd = w.fd;
        }
        if (maxfd < 0) return;
        select::TimeVal tv = { (long)(timeout_us / 1_000_000), (long)(timeout_us % 1_000_000) };
        select::select(maxfd + 1, &rfds, &wfds, &efds, &tv);
        for (usz i = 0; i < MAX_FD_WATCH; i++) {
            FdWatch* w = &_fd_table[i];
            if (!w.active) continue;
            if (select::fd_isset(w.fd, &efds)) {
                if (w.read_fut)  { 
                    w.read_fut.set_exception(IO_ERROR);
                    w.read_fut.cancel("io error");
                    w.read_fut  = null;
                }
                if (w.write_fut) { 
                    w.write_fut.set_exception(IO_ERROR);
                    w.write_fut.cancel("io error");
                    w.write_fut = null;
                }
                unregister(w.fd);
                continue;
            }
            if (select::fd_isset(w.fd, &rfds) && w.read_fut)  { Future* f = w.read_fut;  w.read_fut  = null; f.set_result(null); }
            if (select::fd_isset(w.fd, &wfds) && w.write_fut) { Future* f = w.write_fut; w.write_fut = null; f.set_result(null); }
        }
    $endswitch
}

fn bool _would_block() 
{
    int e = errno::errno();
    return e == errno::EAGAIN || e == errno::EWOULDBLOCK;
}

fn usz? async_read(int fd, void* buf, usz len) 
{
    EventLoop* loop = asyncio::get_running_loop();

    while (true) {
        isz n = unistd::read(fd, buf, len);
        if (n >= 0) return n;
        if (!_would_block()) return errno::get_fault()~;
    
        Future* fut = loop.create_future();
        register_read(fd, fut);
    
        void*? res = fut.await();
        fault ferror = fut.error;
        // fut.free();
    
        if (catch err = res) {
            FdWatch* w = _find(fd);
            if (w != null) w.read_fut = null;
            fut.free();
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        fut.free();
    }
}

fn usz? async_write(int fd, void* buf, usz len) 
{
    EventLoop* loop = asyncio::get_running_loop();

    usz total = 0;
    while (total < len) {
        isz n = unistd::write(fd, (char*)buf + total, len - total);
        if (n > 0)  { total += (usz)n; continue; }
        if (n == 0) break;
        if (!_would_block()) {
            if (total > 0) return total;
            return errno::get_fault()~;
        }
        Future* fut = loop.create_future();
        register_write(fd, fut);
        
        void*? res = fut.await();
        fault ferror = fut.error;
        // fut.free();
        
        if (catch err = res) {
            FdWatch* w = _find(fd);
            if (w != null) w.write_fut = null;
            fut.free();
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        fut.free();
    }
    return total;
}

fn usz? async_recvfrom(int fd, void* buf, usz len, char* ip_str, usz* ip_len, ushort* port) 
{
   EventLoop* loop = asyncio::get_running_loop();

    while (true) {
        socket::SockAddrStorage ss;
        socket::SockLen sslen = $sizeof(ss);

        isz n = socket::recvfrom(fd, buf, len, 0, (socket::SockAddr*)&ss, &sslen);
        if (n >= 0) {
            // sender addr extraction
            if (ip_str != null || port != null) {
                if (ss.ss_family == (ushort)socket::AF_INET6) {
                    in::SockAddrIn6* a6 = (in::SockAddrIn6*)&ss;
                    in::inet_ntop(socket::AF_INET6, &a6.sin6_addr, ip_str, 46);
                    *ip_len = (usz)string::strlen(ip_str);
                    *port = in::ntohs(a6.sin6_port);
                } else {
                    in::SockAddrIn* a4 = (in::SockAddrIn*)&ss;
                    in::inet_ntop(socket::AF_INET, &a4.sin_addr, ip_str, 16);
                    *ip_len = (usz)string::strlen(ip_str);
                    *port = in::ntohs(a4.sin_port);
                }
            }
            return n;
        }

        if (!_would_block()) return errno::get_fault()~;

        Future* fut = loop.create_future();
        register_read(fd, fut);

        void*? res = fut.await();
        fault ferror = fut.error;
        // fut.free();

        if (catch err = res) {
            FdWatch* w = _find(fd);
            if (w != null) w.read_fut = null;
            fut.free();
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        fut.free();
    }
}

fn usz? async_sendto(int fd, void* buf, usz len, char* ip_str, ushort port) 
{
   EventLoop* loop = asyncio::get_running_loop();

    // dest address
    socket::SockAddr* dest_addr;
    socket::SockLen dest_len;

    in::SockAddrIn a4;
    in::SockAddrIn6 a6;

    if (string::strchr(ip_str, ':') != null) {
        if (in::inet_pton(socket::AF_INET6, ip_str, &a6.sin6_addr) != 1) {
            return errno::get_fault()~;
        }
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port = in::htons(port);
        dest_addr = (socket::SockAddr*)&a6;
        dest_len = $sizeof(a6);
    } else {
        a4.sin_family = (ushort)socket::AF_INET;
        a4.sin_port = in::htons(port);
        if (in::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1) {
            return errno::get_fault()~;
        }
        dest_addr = (socket::SockAddr*)&a4;
        dest_len = $sizeof(a4);
    }

    while (true) {
        isz n = socket::sendto(fd, (char*)buf, len, 0, dest_addr, dest_len);
        if (n > 0) return (usz)n;
        if (n == 0) break;

        if (!_would_block()) {
            return errno::get_fault()~;
        }

        Future* fut = loop.create_future();
        register_write(fd, fut);

        void*? res = fut.await();
        fault ferror = fut.error;
        // fut.free();

        if (catch err = res) {
            FdWatch* w = _find(fd);
            if (w != null) w.write_fut = null;
            fut.free();
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        fut.free();
    }
    return 0;
}

/*
fn char* str2cptr(String str, char[] buf) @inline @private
{
    usz len = (str.len <= buf.len-1)? str.len: buf.len-1;
    string::memcpy(&buf[0], &str[0], len);
    buf[len] = 0;
    return &buf[0];
}
*/

fn int? open_file(String path, String mode)
{
    char[256] buf;
    char* path_cstr = str2cptr(path, &buf);
    
    int flags = 0;
    switch (mode) {
      case "r": flags = fcntl::O_RDONLY;
      case "r+": flags = fcntl::O_CREAT | fcntl::O_RDWR;
      case "w": flags = fcntl::O_RDWR | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "w+": flags = fcntl::O_RDWR | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "a": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_WRONLY;
      case "a+": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_RDWR;
      default: return errno::E_INVALID_ARG~;
    }
    stat::umask(0);
    int fd = fcntl::open(path_cstr, flags, 0o644);
    if (fd < 0) {
        return errno::get_fault()~;
    }
    set_nonblocking(fd);
    return fd;
}

fn void close_file(int fd) 
{
    unregister(fd);
    unistd::close(fd);
}

// off_t = long

fn long io_seek(int fd, long pos, int whence)
{
    return unistd::lseek(fd, pos, whence);
}

fn long io_tell(int fd)
{
    return unistd::lseek(fd, 0, unistd::SEEK_CUR);
}

fn int io_truncate(int fd, long pos)
{
    return unistd::ftruncate(fd, pos);
}

fn void io_flush(int fd)
{
    unistd::fsync(fd);
}

fn long io_size(int fd)
{
    stat::Stat_t st;
    stat::fstat(fd, &st);
    return (long)st.st_size;
}

fn int io_stdin()
{
    set_nonblocking(0);
    return 0;
}

fn int io_stdout()
{
    set_nonblocking(1);
    return 1;
}

fn int io_stderr()
{
    set_nonblocking(2);
    return 2;
}
