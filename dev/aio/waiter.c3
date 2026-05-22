// waiter.c3

module ext::aio;

enum WaiterState : char {
    WAITING,
    READY,
    CANCELLED,
}

struct Waiter {
    WaiterState state;
    Task* task;
    fault error;
    bool active;
}

fn void Waiter.init(&self, Task* task)
{
    *self = {
        .state = WAITING,
        .task = task,
        .error = NONE,
        .active = true,
    };
}

fn bool Waiter.done(&self) @inline
{
    return self.state == READY || self.state == CANCELLED;
}

fn bool Waiter.waiting(&self) @inline
{
    return self.state == WAITING;
}

fn bool Waiter.cancelled(&self) @inline
{
    return self.state == CANCELLED;
}

fn void Waiter.wake(&self)
{
    if (!self.active) return;
    if (self.state != WAITING) return;
    if (self.task == null) return;
    if (self.task.loop == null) return;

    self.state = READY;
    self.error = NONE;
    self.active = false;

    self.task.loop.call_soon(self.task);
}

fn void Waiter.cancel(&self, fault err = NONE)
{
    if (!self.active) return;
    if (self.state != WAITING) return;
    if (self.task == null) return;
    if (self.task.loop == null) return;

    self.state = CANCELLED;
    if (err == NONE)
    {
        self.error = CANCELLED;
    }
    else
    {
        self.error = err;
    }
    self.active = false;

    self.task.loop.call_soon(self.task);
}

fn void? Waiter.check(&self) @maydiscard
{
    if (self.state == CANCELLED)
    {
        if (self.error != NONE) return self.error~;
        return CANCELLED~;
    }

    if (self.error != NONE) return self.error~;

    return;
}

