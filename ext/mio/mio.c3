// mio.c3

// Minimal readiness-based I/O poller

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio;

import std::thread;
import ext::mem;

LocalAllocator localmem = null;

faultdef MIO_INVALID, MIO_CLOSED, MIO_FULL, MIO_UNSUPPORTED;

alias Fd @if(env::POSIX) = int;
alias Fd @if(env::WIN32) = int;

fn bool fd_invalid(Fd fd) @inline
{
  $if !env::WIN32:
    return fd < 0;
  $else
    return fd == 0 || fd == (Fd)-1;
  $endif
}

fn Fd fd_null()@inline
{
  $if !env::WIN32:
    return -1;
  $else
    return 0;
  $endif
}

struct Interest
{
    bool read;
    bool write;
}

struct Event
{
    Fd fd;
    bool read;
    bool write;
    bool error;
    bool hup;
}

struct Events
{
    Event[] items;
    sz len;
}

struct Waker
{
    Fd read_fd;
    Fd write_fd;
    bool closed;
}

// Platform-specific poller.
// Defined by mio.epoll.c3, mio.wepoll.c3, mio.kqueue.c3, etc.
/*
interface SysPoll
{
    // Implemented by platform backend.
    
    fn void? init(sz event_capacity);
    
    fn void free();
    
    fn void? wait(Events* events, long timeout_ms);
    
    fn void? register(Fd fd, Interest interest);
    
    fn void? reregister(Fd fd, Interest interest);
    
    fn void? deregister(Fd fd);
}
*/

struct Poll
{
    SysPoll sys;
    Waker* waker;
    thread::Mutex mutex;
}

fn void init() @init
{
    if (localmem == null) localmem = mem;
}

fn Interest want_read() @inline
{
    return {
        .read = true,
        .write = false,
    };
}

fn Interest want_write() @inline
{
    return {
        .read = false,
        .write = true,
    };
}

fn Interest want_readwrite() @inline
{
    return {
        .read = true,
        .write = true,
    };
}

fn Interest Interest.add(&self, Interest other) @inline
{
    return {
        .read = self.read | other.read,
        .write = self.write | other.write,
    };
}

fn bool Interest.is_empty(&self) @inline
{
    return !self.read && !self.write;
}

fn Events? events_new(sz capacity)
{
    if (capacity == 0) return MIO_INVALID~;

    Events events;
    events.items = localmem.alloc_array(Event, capacity)!;
    events.len = 0;

    return events;
}

fn void Events.free(&self)
{
    if (self.items.len > 0)
    {
        localmem.free(self.items);
    }

    self.items = {};
    self.len = 0;
}

fn sz Events.capacity(&self) @inline
{
    return self.items.len;
}

fn bool Events.is_empty(&self) @inline
{
    return self.len == 0;
}

fn void Events.clear(&self) @inline
{
    self.len = 0;
}

fn Event* Events.get(&self, sz index) @inline
{
    if (index >= self.len) return null;
    return &self.items[index];
}

fn Event* Events.push(&self, Event event)
{
    if (self.len >= self.items.len) return null;

    self.items[self.len] = event;
    self.len++;

    return &self.items[self.len - 1];
}

fn void Events.remove_at(&self, sz idx)
{
    if (idx >= self.len) return;

    sz move_len = self.len - idx - 1;

    if (move_len > 0)
    {
        self.items[idx:move_len] = self.items[idx + 1:move_len];
    }

    self.len--;
}

fn Poll*? poll_new(sz event_capacity = 1024)
{
    if (event_capacity == 0) return MIO_INVALID~;

    Poll* poll = localmem.alloc(Poll)!;
    defer catch poll.free();
    
    poll.sys.init(event_capacity)!;
    
    poll.waker = waker_new()!;
    defer catch poll.waker.free();
    
    poll.mutex.init()!;
    poll.sys.register(poll.waker.fd(), want_read())!;

    return poll;
}

fn void Poll.free(&self)
{
    if (self.waker != null)
    {
        (void)self.sys.deregister(self.waker.fd());
        self.waker.free();
        self.waker = null;
    }

    self.sys.free();
    self.mutex.destroy();
    localmem.free(self);
}

fn void? Poll.poll(&self, Events* events, long timeout_ms = -1)
{
    if (events == null) return MIO_INVALID~;

    self.sys.wait(events, timeout_ms)!;

    sz found_i = -1;
    for (sz i = 0; i < events.len; i++)
    {
        mio::Event* event = events.get(i);
        if (event == null) continue;

        if (event.fd == self.waker.fd() && event.read)
        {
            self.waker.drain()!;
            found_i = i;
            break;
        }
    }
    if (found_i >= 0) events.remove_at(found_i);
}

fn void? Poll.wake(&self)
{
    if (self.waker == null) return MIO_CLOSED~;

    self.waker.wake()!;
}

fn void? Poll.register(&self, Fd fd, Interest interest)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;
    if (self.waker != null && fd == self.waker.fd()) return MIO_INVALID~;

    self.mutex.lock()!;
    defer (void)self.mutex.unlock();
    
    self.sys.register(fd, interest)!;

    self.waker.wake()!;
}

fn void? Poll.reregister(&self, Fd fd, Interest interest)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;
    if (self.waker != null && fd == self.waker.fd()) return MIO_INVALID~;
    
    self.mutex.lock()!;
    defer (void)self.mutex.unlock();
    
    self.sys.reregister(fd, interest)!;

    self.waker.wake()!;
}

fn void? Poll.deregister(&self, Fd fd)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (self.waker != null && fd == self.waker.fd()) return MIO_INVALID~;
    
    self.mutex.lock()!;
    defer (void)self.mutex.unlock();
    
    self.sys.deregister(fd)!;

    self.waker.wake()!;
}


// eof