// mio.wepoll.c3

// Windows wepoll backend for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::WIN32) @link("ws2_32");

import c::errno;
import c::wepoll;
import c::winsock2;
import ext::mem;

struct SysPoll
{
    wepoll::EPollFd epfd;
    wepoll::EPollEvent[] raw_events;
    sz capacity;
}

fn uint interest_to_wepoll(Interest interest) @private
{
    uint flags = 0;

    if (interest.read) flags |= wepoll::EPOLLIN;
    if (interest.write) flags |= wepoll::EPOLLOUT;

    return flags;
}

fn void wepoll_to_event(uint flags, Event* event) @private
{
    if ((flags & wepoll::EPOLLIN) != 0) event.read = true;
    if ((flags & wepoll::EPOLLOUT) != 0) event.write = true;
    if ((flags & wepoll::EPOLLERR) != 0) event.error = true;
    if ((flags & wepoll::EPOLLHUP) != 0) event.hup = true;
    if ((flags & wepoll::EPOLLRDHUP) != 0) event.hup = true;
}

fn wepoll::EPollEvent wepoll_event_new(Fd fd, Interest interest) @private
{
    wepoll::EPollEvent event = {};

    event.events = interest_to_wepoll(interest);
    event.data.u64 = (ulong)fd;

    return event;
}

fn void? SysPoll.init(&self, sz event_capacity)
{
    if (event_capacity == 0) return MIO_INVALID~;

    self.epfd = null;
    self.raw_events = {};
    self.capacity = 0;

    wepoll::EPollFd epfd = wepoll::epoll_create(1);
    if (epfd == null)
    {
        return errno::get_fault()~;
    }

    self.epfd = epfd;

    defer (catch err)
    {
        if (self.epfd != null)
        {
            wepoll::epoll_close(self.epfd);
            self.epfd = null;
        }

        if (self.raw_events.ptr != null)
        {
            localmem.free(self.raw_events.ptr);
            self.raw_events = {};
        }

        self.capacity = 0;
    }

    self.raw_events = localmem.alloc_array(wepoll::EPollEvent, event_capacity)!;
    self.capacity = event_capacity;
}

fn void SysPoll.free(&self)
{
    if (self.epfd != null)
    {
        wepoll::epoll_close(self.epfd);
    }

    if (self.raw_events.ptr != null)
    {
        localmem.free(self.raw_events.ptr);
    }

    self.epfd = null;
    self.raw_events = {};
    self.capacity = 0;
}

fn void? SysPoll.wait(&self, Events* events, long timeout_ms)
{
    if (events == null) return MIO_INVALID~;
    if (self.epfd == null) return MIO_CLOSED~;

    events.clear();

    sz capacity = self.capacity;
    if (events.capacity() < capacity)
    {
        capacity = events.capacity();
    }

    if (capacity == 0) return MIO_INVALID~;

    int n = wepoll::epoll_wait(
        self.epfd,
        self.raw_events.ptr,
        (int)capacity,
        (int)timeout_ms
    );

    if (n < 0)
    {
        return errno::get_fault()~;
    }

    for (int i = 0; i < n; i++)
    {
        wepoll::EPollEvent* raw = &self.raw_events[i];

        Event event = {};
        event.fd = (Fd)raw.data.u64;

        wepoll_to_event(raw.events, &event);

        if (events.push(event) == null)
        {
            return MIO_FULL~;
        }
    }
}

fn void? SysPoll.register(&self, Fd fd, Interest interest)
{
    if (self.epfd == null) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    wepoll::EPollEvent event = wepoll_event_new(fd, interest);

    if (wepoll::epoll_ctl(self.epfd, wepoll::EPOLL_CTL_ADD, (winsock2::Socket)fd, &event) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? SysPoll.reregister(&self, Fd fd, Interest interest)
{
    if (self.epfd == null) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    wepoll::EPollEvent event = wepoll_event_new(fd, interest);

    if (wepoll::epoll_ctl(self.epfd, wepoll::EPOLL_CTL_MOD, (winsock2::Socket)fd, &event) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? SysPoll.deregister(&self, Fd fd)
{
    if (self.epfd == null) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;

    if (wepoll::epoll_ctl(self.epfd, wepoll::EPOLL_CTL_DEL, (winsock2::Socket)fd, null) < 0)
    {
        return errno::get_fault()~;
    }
}

// eof