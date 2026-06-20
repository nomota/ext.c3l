// timer.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import ext::mem;

struct Timer
{
    Task* target;
    Task* timer_task;

    ulong timeout_us;
    bool active;
    bool cancelled;
    bool done;
}

fn void? timer_task_entry(void* arg) @local
{
    Timer* t = (Timer*)arg;
    if (t == null) return INVALID_ARG~;

    //ulong timeout_ms = (t.timeout_us + 999) / 1000;

    sleep((uint)t.timeout_us)!;

    t.done = true;

    if (t.cancelled)
    {
        localmem.free(t);
        return;
    }

    if (t.active)
    {
        Task* target = t.target;

        t.active = false;
        t.target = null;
        t.timer_task = null;

        if (target != null &&
            target.state != TASK_DONE &&
            target.state != TASK_CANCELLED &&
            target.state != TASK_FAILED)
        {
            target.cancel_timeout();
        }
    }
}

fn Timer*? Task.start_timer(&self, ulong timeout_us)
{
    if (timeout_us == 0) return INVALID_ARG~;

    EventLoop* loop = self.loop;
    if (loop == null) return INVALID_STATE~;

    Timer* timer = localmem.alloc(Timer)!;
    *timer = {
        .target = self,
        .timer_task = null,
        .timeout_us = timeout_us,
        .active = true,
        .cancelled = false,
        .done = false,
    };
    defer catch localmem.free(timer);

    Task* timer_task = loop.spawn(&timer_task_entry, timer)!;

    timer.timer_task = timer_task;

    return timer;
}

fn Timer*? start_timer(ulong timeout_us)
{
    Task* task = current_task()!;

    return task.start_timer(timeout_us)!;
}

fn void Timer.cancel(&self)
{
    self.active = false;
    self.cancelled = true;
    self.target = null;
    self.timer_task = null;

    if (self.done)
    {
        localmem.free(self);
    }
}

// eof