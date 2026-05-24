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
}

fn void? timer_task_entry(void* arg) @local
{
    Timer* t = (Timer*)arg;
    if (t == null) return INVALID_ARG~;

    sleep(t.timeout_us)!;

    if (!t.active) return;

    Task* target = t.target;

    if (target != null &&
        target.state != TASK_DONE &&
        target.state != TASK_CANCELLED &&
        target.state != TASK_FAILED)
    {
        target.cancel_timeout();
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
    self.target = null;
    
    if (self.timer_task != null)
    {
        self.timer_task.cancel();
        self.timer_task = null;
    }
    
    localmem.free(self);
}

// eof