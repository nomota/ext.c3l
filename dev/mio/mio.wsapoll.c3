// mio.wsapoll.c3

// Windows WSAPoll backend for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::WIN32) @link("ws2_32");

import c::errno;
import c::winsock2;
import ext::mem;
import ext::debug;

struct PollEntry
{
    Fd fd;
    Interest interest;
    bool used;
}

struct SysPoll
{
    winsock2::WSAPollFd[] raw_events;
    PollEntry[] entries;
    sz capacity;
    sz len;
}

fn short interest_to_wsapoll(Interest interest) @private
{
    short flags = 0;

    if (interest.read) flags |= winsock2::POLLIN;
    if (interest.write) flags |= winsock2::POLLOUT;

    return flags;
}

fn void wsapoll_to_event(short flags, Event* event) @private
{
    if ((flags & winsock2::POLLIN) != 0) event.read = true;
    if ((flags & winsock2::POLLOUT) != 0) event.write = true;
    if ((flags & winsock2::POLLERR) != 0) event.error = true;
    if ((flags & winsock2::POLLHUP) != 0) event.hup = true;
    if ((flags & winsock2::POLLNVAL) != 0) event.error = true;
}

fn sz? SysPoll.find(&self, Fd fd)
{
    for (sz i = 0; i < self.len; i++)
    {
        if (!self.entries[i].used) continue;
        if (self.entries[i].fd == fd) return i;
    }

    return MIO_INVALID~;
}

fn void? SysPoll.init(&self, sz event_capacity)
{
    if (event_capacity == 0) return MIO_INVALID~;

    self.raw_events = {};
    self.entries = {};
    self.capacity = 0;
    self.len = 0;

    self.raw_events = localmem.alloc_array(winsock2::WSAPollFd, event_capacity)!;

    defer (catch err)
    {
        if (self.raw_events.ptr != null)
        {
            localmem.free(self.raw_events.ptr);
            self.raw_events = {};
        }

        if (self.entries.ptr != null)
        {
            localmem.free(self.entries.ptr);
            self.entries = {};
        }

        self.capacity = 0;
        self.len = 0;
    }

    self.entries = localmem.alloc_array(PollEntry, event_capacity)!;
    self.capacity = event_capacity;
    self.len = 0;
}

fn void SysPoll.free(&self)
{
    if (self.raw_events.ptr != null)
    {
        localmem.free(self.raw_events.ptr);
    }

    if (self.entries.ptr != null)
    {
        localmem.free(self.entries.ptr);
    }

    self.raw_events = {};
    self.entries = {};
    self.capacity = 0;
    self.len = 0;
}

fn void? SysPoll.wait(&self, Events* events, long timeout_ms)
{
    if (events == null) return MIO_INVALID~;

    events.clear();

    if (self.capacity == 0) return MIO_CLOSED~;

    for (sz i = 0; i < self.len; i++)
    {
        PollEntry* entry = &self.entries[i];

        self.raw_events[i] = {
            .fd = (winsock2::Socket)entry.fd,
            .events = interest_to_wsapoll(entry.interest),
            .revents = 0,
        };
    }

    int n = winsock2::wsaPoll(
        self.raw_events.ptr,
        (uint)self.len,
        (int)timeout_ms
    );

    if (n < 0)
    {
        return errno::wsa_fault()~;
    }

    if (n == 0) return;

    for (sz i = 0; i < self.len; i++)
    {
        winsock2::WSAPollFd* raw = &self.raw_events[i];

        if (raw.revents == 0) continue;

        Event event = {};
        event.fd = (Fd)raw.fd;

        wsapoll_to_event(raw.revents, &event);

        if (events.push(event) == null)
        {
            return MIO_FULL~;
        }
    }
}

fn bool SysPoll.contains(&self, Fd fd) @inline
{
    for (sz i = 0; i < self.len; i++)
    {
        if (self.entries[i].fd == fd) return true;
    }

    return false;
}

fn void? SysPoll.register(&self, Fd fd, Interest interest)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;
    if (self.len >= self.capacity) return MIO_FULL~;

    if (self.contains(fd)) return MIO_INVALID~;

    self.entries[self.len] = {
        .fd = fd,
        .interest = interest,
        .used = true,
    };

    self.len++;
}

fn void? SysPoll.reregister(&self, Fd fd, Interest interest)
{
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    sz index = self.find(fd)!;

    self.entries[index].interest = interest;
}

fn void? SysPoll.deregister(&self, Fd fd)
{
    if (fd_invalid(fd)) return MIO_INVALID~;

    sz index = self.find(fd)!;

    if (index + 1 < self.len)
    {
        self.entries[index] = self.entries[self.len - 1];
    }

    self.entries[self.len - 1] = {};
    self.len--;
}

// eof