// mio.c3

// Minimal readiness-based I/O poller

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio;

import ext::mem;

LocalAllocator localmem = null;

faultdef MIO_INVALID, MIO_CLOSED, MIO_FULL, MIO_UNSUPPORTED;

alias Fd = iptr;

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

fn Poll*? poll_new(sz event_capacity = 1024)
{
    if (event_capacity == 0) return MIO_INVALID~;

    Poll* poll = localmem.alloc(Poll)!;
    poll.sys.init(event_capacity)!;

    return poll;
}

fn void Poll.free(&self)
{
    self.sys.free();
    localmem.free(self);
}

fn void? Poll.poll(&self, Events* events, long timeout_ms = -1)
{
    if (events == null) return MIO_INVALID~;

    return self.sys.wait(events, timeout_ms)!;
}

fn void? Poll.register(&self, Fd fd, Interest interest)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    return self.sys.register(fd, interest)!;
}

fn void? Poll.reregister(&self, Fd fd, Interest interest)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    return self.sys.reregister(fd, interest)!;
}

fn void? Poll.deregister(&self, Fd fd)
{
    if (fd_invalid(fd)) return MIO_INVALID~;

    return self.sys.deregister(fd)!;
}

fn bool fd_invalid(Fd fd) @if(!env::WIN32) @inline
{
    return fd < 0;
}

fn bool fd_invalid(Fd fd) @if(env::WIN32) @inline
{
    return fd == 0 || fd == (Fd)-1;
}

// eof