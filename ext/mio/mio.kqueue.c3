// mio.kqueue.c3

// BSD kqueue backend for ext::mio
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::mio @if(env::DARWIN || env::FREEBSD || env::OPENBSD || env::NETBSD);

import c::errno;
import c::unistd;
import c::sys::event;
import ext::mem;

struct SysPoll
{
    int kqfd;
    event::Kevent[] raw_events;
    sz capacity;
}

fn void kevent_set(
    event::Kevent* kev,
    Fd fd,
    short filter,
    ushort flags
) @local
{
    event::ev_set(
        kev,
        (event::UIntPtr)fd,
        filter,
        flags,
        0,
        0,
        null
    );
}

fn void kqueue_to_event(event::Kevent* raw, Event* event) @local
{
    event.fd = (Fd)raw.ident;

    if (raw.filter == event::EVFILT_READ)
    {
        event.read = true;
    }
    else if (raw.filter == event::EVFILT_WRITE)
    {
        event.write = true;
    }

    if ((raw.flags & event::EV_ERROR) != 0)
    {
        event.error = true;
    }

    if ((raw.flags & event::EV_EOF) != 0)
    {
        event.hup = true;
    }
}

fn sz kqueue_build_changes(Fd fd, Interest interest, event::Kevent[] changes, bool deleting = false) @local
{
    sz n = 0;

    if (deleting)
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_READ,
            event::EV_DELETE
        );

        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_WRITE,
            event::EV_DELETE
        );

        return n;
    }

    if (interest.read)
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_READ,
            event::EV_ADD | event::EV_ENABLE
        );
    }
    else
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_READ,
            event::EV_DELETE
        );
    }

    if (interest.write)
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_WRITE,
            event::EV_ADD | event::EV_ENABLE
        );
    }
    else
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_WRITE,
            event::EV_DELETE
        );
    }

    return n;
}

fn void? SysPoll.init(&self, sz event_capacity)
{
    if (event_capacity == 0) return MIO_INVALID~;

    self.kqfd = -1;
    self.raw_events = {};
    self.capacity = 0;

    int kqfd = event::kqueue();
    if (kqfd < 0) return errno::get_fault()~;

    self.kqfd = kqfd;

    defer (catch err)
    {
        if (self.kqfd >= 0)
        {
            unistd::close(self.kqfd);
            self.kqfd = -1;
        }

        if (self.raw_events.len > 0)
        {
            localmem.free(self.raw_events);
            self.raw_events = {};
        }

        self.capacity = 0;
    }

    self.raw_events = localmem.alloc_array(event::Kevent, event_capacity)!;
    self.capacity = event_capacity;
}

fn void SysPoll.free(&self)
{
    if (self.kqfd >= 0)
    {
        unistd::close(self.kqfd);
    }

    if (self.raw_events.ptr != null)
    {
        localmem.free(self.raw_events.ptr);
    }

    self.kqfd = -1;
    self.raw_events = {};
    self.capacity = 0;
}

fn void? SysPoll.wait(&self, Events* events, long timeout_ms)
{
    if (events == null) return MIO_INVALID~;
    if (self.kqfd < 0) return MIO_CLOSED~;

    events.clear();

    sz capacity = self.capacity;
    if (events.capacity() < capacity)
    {
        capacity = events.capacity();
    }

    if (capacity == 0) return MIO_INVALID~;

    event::TimeSpec* timeout_ptr = null;
    event::TimeSpec timeout = {};

    if (timeout_ms >= 0)
    {
        timeout.tv_sec = timeout_ms / 1000;
        timeout.tv_nsec = (timeout_ms % 1000) * 1_000_000;
        timeout_ptr = &timeout;
    }

    int n = event::kevent(
        self.kqfd,
        null,
        0,
        self.raw_events.ptr,
        (int)capacity,
        timeout_ptr
    );

    if (n < 0)
    {
        return errno::get_fault()~;
    }

    for (int i = 0; i < n; i++)
    {
        event::Kevent* raw = &self.raw_events[i];

        Event event = {};
        kqueue_to_event(raw, &event);

        if (events.push(event) == null)
        {
            return MIO_FULL~;
        }
    }
}

fn void? SysPoll.register(&self, Fd fd, Interest interest)
{
    if (self.kqfd < 0) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    event::Kevent[2] changes;
    sz n = 0;

    if (interest.read)
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_READ,
            event::EV_ADD | event::EV_ENABLE
        );
    }

    if (interest.write)
    {
        kevent_set(
            &changes[n++],
            fd,
            event::EVFILT_WRITE,
            event::EV_ADD | event::EV_ENABLE
        );
    }

    int rc = event::kevent(
        self.kqfd,
        &changes[0],
        (int)n,
        null,
        0,
        null
    );

    if (rc < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? SysPoll.reregister(&self, Fd fd, Interest interest)
{
    if (self.kqfd < 0) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;
    if (interest.is_empty()) return MIO_INVALID~;

    event::Kevent[2] changes;
    sz n = kqueue_build_changes(fd, interest, changes[..]);

    int rc = event::kevent(
        self.kqfd,
        &changes[0],
        (int)n,
        null,
        0,
        null
    );

    if (rc < 0)
    {
        return errno::get_fault()~;
    }
}

fn void? SysPoll.deregister(&self, Fd fd)
{
    if (self.kqfd < 0) return MIO_CLOSED~;
    if (fd_invalid(fd)) return MIO_INVALID~;

    event::Kevent[2] changes;
    sz n = kqueue_build_changes(fd, {}, changes[..], true);

    int rc = event::kevent(
        self.kqfd,
        &changes[0],
        (int)n,
        null,
        0,
        null
    );

    if (rc < 0)
    {
        fault err = errno::get_fault();

        if (err == errno::E_NOT_FOUND)
        {
            return;
        }

        return err~;
    }
}

// eof