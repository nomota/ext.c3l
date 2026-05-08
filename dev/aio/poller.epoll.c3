// poller.epoll.c3

module ext::aio @if(env::LINUX);

import ext::mem;
import ext::debug;
import c::unistd;
import c::errno;
import c::sys::epoll;

const int MAX_EPOLL_EVENTS @private = 64;

struct Poller @private {
    int epfd;
}

fn Poller* poller_new()
{
    Poller* p = localmem.alloc(Poller);

    p.epfd = epoll::epoll_create1(0);

    if (p.epfd < 0) {
        // 초기 단계에서는 null 반환보다 epfd=-1로 두고 add/poll에서 에러 처리
        p.epfd = -1;
    }

    return p;
}

fn void Poller.free(&self)
{
    if (self.epfd >= 0) {
        unistd::close(self.epfd);
        self.epfd = -1;
    }

    localmem.free(self);
}

fn uint io_events_to_epoll(uint events)
{
    uint ep = 0;

    if ((events & IO_READABLE) != 0) {
        ep |= epoll::EPOLLIN;
    }

    if ((events & IO_WRITABLE) != 0) {
        ep |= epoll::EPOLLOUT;
    }

    ep |= epoll::EPOLLERR;
    ep |= epoll::EPOLLHUP;
    ep |= epoll::EPOLLONESHOT;

    return ep;
}

fn uint epoll_events_to_io(uint events)
{
    uint io = 0;

    if ((events & epoll::EPOLLIN) != 0) {
        io |= IO_READABLE;
    }

    if ((events & epoll::EPOLLOUT) != 0) {
        io |= IO_WRITABLE;
    }

    if ((events & epoll::EPOLLERR) != 0) {
        io |= IO_ERROR;
    }

    if ((events & epoll::EPOLLHUP) != 0) {
        io |= IO_HANGUP;
    }

    return io;
}

fn void? Poller.add(&self, IoWaiter* waiter)
{
    if (self.epfd < 0) {
        return ASYNC_IO_ERROR~;
    }

    if (waiter == null) {
        return ASYNC_INVALID_STATE~;
    }

    epoll::EpollEvent ev;
    ev.events = io_events_to_epoll(waiter.events);
    ev.data.ptr = waiter;

    int rc = epoll::epoll_ctl(self.epfd, epoll::EPOLL_CTL_ADD, waiter.fd, &ev);

    if (rc < 0) {
        warn("epoll add failed fd=%d errno=%d", waiter.fd, errno::errno());

        // 이미 등록되어 있으면 MOD로 재시도.
        rc = epoll::epoll_ctl(self.epfd, epoll::EPOLL_CTL_MOD, waiter.fd, &ev);
    }

    if (rc < 0) {
        warn("epoll add failed fd=%d errno=%d", waiter.fd, errno::errno());

        return ASYNC_IO_ERROR~;
    }

    return;
}

fn void? Poller.remove(&self, int fd)
{
    if (self.epfd < 0) {
        return ASYNC_IO_ERROR~;
    }

    epoll::EpollEvent ev;

    int rc = epoll::epoll_ctl(self.epfd, epoll::EPOLL_CTL_DEL, fd, &ev);

    if (rc < 0) {
        // DEL은 이미 제거된 fd일 수 있으므로 초기 구현에서는 무시해도 된다.
        return;
    }

    return;
}

fn void? Poller.poll(&self, int timeout_ms)
{
    if (self.epfd < 0) {
        return ASYNC_IO_ERROR~;
    }

    epoll::EpollEvent[MAX_EPOLL_EVENTS] events;

    int n = epoll::epoll_wait(self.epfd, &events[0], MAX_EPOLL_EVENTS, timeout_ms);

    if (n < 0) {
        warn("epoll_wait n=%d", n);
        // EINTR은 에러로 보지 않는다.
        if (errno::errno() == errno::EINTR) {
            return;
        }

        return ASYNC_IO_ERROR~;
    }

    for (int i = 0; i < n; i++) {
        IoWaiter* waiter = (IoWaiter*)events[i].data.ptr;

        if (waiter == null) {
            continue;
        }

        waiter.revents = epoll_events_to_io(events[i].events);

        warn("poll event fd=%d revents=%x", waiter.fd, waiter.revents);

        // oneshot이므로 이 waiter는 여기서 깨우고 끝난다.
        waiter.base.wake();
    }

    return;
}
