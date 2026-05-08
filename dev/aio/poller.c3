// poller.c3

module ext::aio;

faultdef ASYNC_IO_ERROR;

const uint IO_READABLE = 0x01;
const uint IO_WRITABLE = 0x02;
const uint IO_ERROR    = 0x04;
const uint IO_HANGUP   = 0x08;

struct IoWaiter @private {
    Waiter base;

    int fd;
    uint events;
    uint revents;

    IoWaiter* next;
}

fn void IoWaiter.init(&self, Task* task, int fd, uint events)
{
    self.base.init(task);

    self.fd = fd;
    self.events = events;
    self.revents = 0;

    self.next = null;
}

fn bool IoWaiter.readable(&self) @inline
{
    return (self.revents & IO_READABLE) != 0;
}

fn bool IoWaiter.writable(&self) @inline
{
    return (self.revents & IO_WRITABLE) != 0;
}

fn bool IoWaiter.error(&self) @inline
{
    return (self.revents & IO_ERROR) != 0;
}

fn bool IoWaiter.hangup(&self) @inline
{
    return (self.revents & IO_HANGUP) != 0;
}

fn void? wait_readable(int fd)
{
    Task* task = current_task();

    if (task == null) {
        return ASYNC_INVALID_STATE~;
    }

    EventLoop* loop = task.loop;

    if (loop == null || loop.poller == null) {
        return ASYNC_INVALID_STATE~;
    }

    IoWaiter waiter;
    waiter.init(task, fd, IO_READABLE);

    loop.poller.add(&waiter)!;

    task.suspend(&waiter.base);

    waiter.base.check()!;

    if (waiter.error()) {
        return ASYNC_IO_ERROR~;
    }

    return;
}

fn void? wait_writable(int fd)
{
    Task* task = current_task();

    if (task == null) {
        return ASYNC_INVALID_STATE~;
    }

    EventLoop* loop = task.loop;

    if (loop == null || loop.poller == null) {
        return ASYNC_INVALID_STATE~;
    }

    IoWaiter waiter;
    waiter.init(task, fd, IO_WRITABLE);

    loop.poller.add(&waiter)!;

    task.suspend(&waiter.base);

    waiter.base.check()!;

    if (waiter.error()) {
        return ASYNC_IO_ERROR~;
    }

    return;
}

