// mio.epoll.c3

// Linux epoll backend for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::LINUX);

import c::errno;
import c::unistd;
import c::sys::epoll;
import ext::mem;

struct SysPoll
{
    int epfd;
    epoll::EpollEvent[] raw_events;
    sz capacity;
}

fn uint Interest.to_epoll(&self)
{
    uint flags = 0;

    if (self.read) flags |= epoll::EPOLLIN;
    if (self.write) flags |= epoll::EPOLLOUT;

    return flags;
}

fn void epoll_to_event(uint flags, Event* event) @private
{
    if ((flags & epoll::EPOLLIN) != 0) event.read = true;
    if ((flags & epoll::EPOLLOUT) != 0) event.write = true;
    if ((flags & epoll::EPOLLERR) != 0) event.error = true;
    if ((flags & epoll::EPOLLHUP) != 0) event.hup = true;
    if ((flags & epoll::EPOLLRDHUP) != 0) event.hup = true;
}

fn epoll::EpollEvent epoll_event_new(Fd fd, Interest interest) @private
{
    epoll::EpollEvent event;

    event.events = interest.to_epoll();
    event.data.u64 = (ulong)fd;

    return event;
}

fn void? SysPoll.init(&self, sz event_capacity)
{
    if (event_capacity == 0) return MIO_INVALID~;

    self.epfd = -1;
    self.raw_events = {};
    self.capacity = 0;

    int epfd = epoll::epoll_create1(epoll::EPOLL_CLOEXEC);
    if (epfd < 0) return errno::get_fault()~;

    self.epfd = epfd;

    defer (catch err)
    {
        if (self.epfd >= 0)
        {
            unistd::close(self.epfd);
            self.epfd = -1;
        }

        if (self.raw_events.len > 0)
        {
            localmem.free(self.raw_events);
            self.raw_events = {};
        }

        self.capacity = 0;
    }

    self.raw_events = localmem.alloc_array(epoll::EpollEvent, event_capacity)!;
    self.capacity = event_capacity;
}

fn void SysPoll.free(&self)
{
    if (self.epfd >= 0)
    {
        unistd::close(self.epfd);
    }

    if (self.raw_events.ptr != null)
    {
        localmem.free(self.raw_events.ptr);
    }

    self.epfd = -1;
    self.raw_events = {};
    self.capacity = 0;
}

fn void? SysPoll.wait(&self, Events* events, long timeout_ms)
{
    if (events == null) return MIO_INVALID~;
    if (self.epfd < 0) return MIO_CLOSED~;

    events.clear();

    sz capacity = self.capacity;
    if (events.capacity() < capacity)
    {
        capacity = events.capacity();
    }

    if (capacity == 0) return MIO_INVALID~;

    int n = epoll::epoll_wait(
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
        epoll::EpollEvent* raw = &self.raw_events[i];

        Event event = {};
        event.fd = (Fd)raw.data.u64;
        epoll_to_event(raw.events, &event);

        if (events.push(event) == null)
        {
            return MIO_FULL~;
        }
    }
}

fn void? SysPoll.register(&self, Fd fd, Interest interest)
{
    if (self.epfd < 0) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    epoll::EpollEvent event = epoll_event_new(fd, interest);

    if (epoll::epoll_ctl(self.epfd, epoll::EPOLL_CTL_ADD, (int)fd, &event) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? SysPoll.reregister(&self, Fd fd, Interest interest)
{
    if (self.epfd < 0) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    epoll::EpollEvent event = epoll_event_new(fd, interest);

    if (epoll::epoll_ctl(self.epfd, epoll::EPOLL_CTL_MOD, (int)fd, &event) < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? SysPoll.deregister(&self, Fd fd)
{
    if (self.epfd < 0) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;

    if (epoll::epoll_ctl(self.epfd, epoll::EPOLL_CTL_DEL, (int)fd, null) < 0)
    {
        return errno::get_fault()~;
    }
}

// eof