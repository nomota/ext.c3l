// task.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import ext::mem;
import ext::debug;
import c::stdlib;
import ext::fiber;

enum TaskState : char
{
    TASK_NEW,
    TASK_READY,
    TASK_RUNNING,
    TASK_WAITING,
    TASK_DONE,
    TASK_CANCELLED,
    TASK_FAILED,
}

alias TaskFn = fn void?(void*);

struct Task
{
    TaskState state;

    EventLoop* loop;
    Fiber* fiber;

    TaskFn entry;
    void* arg;
    
    fault error;

    Waiter* waiting_on;
    Waiter* join_waiter;

    bool queued;
    bool detached;

    bool cancel_requested;
    bool timeout_requested;
}

fn Task*? EventLoop.task_new(&self, TaskFn entry, void* arg = null)
{
    if (entry == null) return INVALID_ARG~;
    
    Task* t = localmem.alloc(Task)!;
    *t = {
        .state = TASK_NEW,
        .loop = self,
        .fiber = null,
        .entry = entry,
        .arg = arg,
        .error = NONE,
        .waiting_on = null,
        .join_waiter = null,
        .detached = false,
        .queued = false,
        .cancel_requested = false,
        .timeout_requested = false,
    };
    
    t.fiber = fiber::create(&fiber_trampoline, arg:t)!;
    if (t.fiber == null)
    {
        localmem.free(t);
        return FIBER_ERROR~;
    }
    t.state = TASK_READY;

    return t;
}

fn void Task.free(&self)
{
    if (self.fiber != null)
    {
        fiber::delete(self.fiber);
        self.fiber = null;
    }

    localmem.free(self);
}

fn void fiber_trampoline()
{
    Task* t = (Task*)fiber::active().arg;

    t.loop.current = t;
    t.state = TASK_RUNNING;

    if (catch err = t.entry(t.arg))
    {
        t.error = err;
        warn("task aborted: %s", err);
        
        if (err == CANCELLED || err == TIMEOUT)
        {
            t.state = TASK_CANCELLED;
        }
        else
        {
            t.state = TASK_FAILED;
        }
    }
    else
    {
        t.error = NONE;
        t.state = TASK_DONE;
    }

    t.waiting_on = null;

    if (t.join_waiter != null)
    {
        t.join_waiter.wake();
        t.join_waiter = null;
    }

    t.loop.current = null;

    fiber::done();
}

// Advance one step of a Task's execution
fn void Task.resume(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;
    if (self.state == TASK_FAILED) return;

    if (self.fiber == null) return;

    Task* prev = self.loop.current;

    self.loop.current = self;
    self.state = TASK_RUNNING;

    fiber::switch_to(self.fiber);

    // Returned from suspend() or fiber::done().
    if (self.state == TASK_RUNNING)
    {
        // Task yielded without setting WAITING/DONE.
        // Keep it runnable.
        self.state = TASK_READY;
    }
    
    self.loop.current = prev;
}

fn void Task.suspend(&self, Waiter* waiter)
{
    self.waiting_on = waiter;
    self.state = TASK_WAITING;

    fiber::switch_to(self.loop.fiber);
}

fn void Task.yield(&self)
{
    self.state = TASK_WAITING;

    fiber::switch_to(self.loop.fiber);
}

fn void Task.mark_ready(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;
    if (self.state == TASK_FAILED) return;

    self.waiting_on = null;

    self.state = TASK_READY;
}

fn void Task.cancel(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;

    self.cancel_requested = true;
    self.error = CANCELLED;

    if (self.waiting_on != null)
    {
        self.waiting_on.cancel();
        return;
    }

    self.state = TASK_CANCELLED;

    if (self.join_waiter != null)
    {
        self.join_waiter.cancel();
        self.join_waiter = null;
    }
}

fn void Task.cancel_timeout(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;

    self.cancel_requested = true;
    self.timeout_requested = true;
    self.error = TIMEOUT;

    if (self.waiting_on != null)
    {
        self.waiting_on.cancel(TIMEOUT);
        return;
    }

    self.state = TASK_CANCELLED;

    if (self.join_waiter != null)
    {
        self.join_waiter.cancel(TIMEOUT);
        self.join_waiter = null;
    }
}

fn void? Task.check(&self) @maydiscard
{
    if (self.error != NONE) return self.error~;

    if (self.state == TASK_CANCELLED) return CANCELLED~;
}

faultdef JOIN_DETACHED, JOIN_NO_TASK, JOIN_NO_WAITER, JOIN_TASK_CANCELLED, JOIN_TASK_FAILED;

fn void? Task.join(&self) @maydiscard
{
    if (self.detached) return JOIN_DETACHED~;

    if (self.state != TASK_DONE &&
        self.state != TASK_CANCELLED &&
        self.state != TASK_FAILED)
    {
        Task* current = self.loop.current;

        if (current == null || current == self) return JOIN_NO_TASK~;

        if (self.join_waiter != null) return JOIN_NO_WAITER~;

        Waiter waiter;
        waiter.init(current);

        self.join_waiter = &waiter;

        current.suspend(&waiter);

        waiter.check();
    }

    TaskState state = self.state;
    EventLoop* loop = self.loop;

    if (loop != null) loop.reap_task(self);
}

// eof