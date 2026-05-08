// task.c3

module ext::aio;

import ext::mem;
import ext::debug;
import c::stdlib;
import ext::fiber;

enum TaskState : char {
    TASK_NEW,
    TASK_READY,
    TASK_RUNNING,
    TASK_WAITING,
    TASK_DONE,
    TASK_CANCELLED,
    TASK_FAILED,
}

alias TaskFn = fn void();

struct Task {
    uint stack_size;
    
    TaskState state;

    EventLoop* loop;
    Fiber* fiber;

    TaskFn entry;

    fault error;

    Waiter* waiting_on;
    Waiter* join_waiter;

    Task* next_ready;
    
    bool queued;
}

fn Task* EventLoop.task_new(&self, TaskFn entry)
{
    Task* t = localmem.alloc(Task);

    *t = {
        .stack_size = 256_000,
        .state = TASK_NEW,
        .loop = self,
        .fiber = null,
        .entry = entry,
        .error = NONE,
        .waiting_on = null,
        .join_waiter = null,
        .next_ready = null,
        .queued = false,
    };

    return t;
}

fn void Task.free(&self)
{
    if (self.fiber != null) {
        fiber::delete(self.fiber);
        self.fiber = null;
    }

    localmem.free(self);
}

fn void fiber_trampoline()
{
// warn("fiber_trampoline enter");

    Task* t = (Task*)fiber::active().arg;

    t.loop.current = t;
    
    t.state = TASK_RUNNING;

    t.entry(); // call fiber coruotine

    if (t.error == ASYNC_CANCELLED) {
        t.state = TASK_CANCELLED;
    } else {
        t.state = TASK_DONE;
        t.error = NONE;
    }

    t.waiting_on = null;

    if (t.join_waiter != null) {
        t.join_waiter.wake();
        t.join_waiter = null;
    }

    t.loop.current = null;

    fiber::done(); // return to the main loop
}

// Advance one step of a Task's execution
fn void Task.resume(&self)
{
// warn("resume %s", self.state);
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;
    if (self.state == TASK_FAILED) return;

    if (self.state == TASK_NEW) {
// warn("-");
        self.state = TASK_RUNNING;
        self.fiber = fiber::create(self.stack_size, &fiber_trampoline , self);
        self.state = TASK_READY;
    }
    
    if (self.fiber == null) return;

    Task* prev = self.loop.current;

    self.loop.current = self;
    self.state = TASK_RUNNING;
// warn("-");
    fiber::switch_to(self.fiber);

    // Returned from suspend() or fiber::done().
    if (self.state == TASK_RUNNING) {
// warn("-");
        // Task yielded without setting WAITING/DONE.
        // Keep it runnable.
        self.state = TASK_READY;
    }
    
    self.loop.current = prev;
}

fn void Task.suspend(&self, Waiter* waiter)
{
// warn("task suspend");

    self.waiting_on = waiter;
    
    self.state = TASK_WAITING;

    fiber::switch_to(self.loop.fiber); // to main fiber
}

fn void Task.mark_ready(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;
    if (self.state == TASK_FAILED) return;

    self.waiting_on = null;

    if (self.state == TASK_NEW) return;

    self.state = TASK_READY;
}

fn void Task.cancel(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;

    self.error = ASYNC_CANCELLED;

    if (self.waiting_on != null) {
        self.waiting_on.cancel();
        return;
    }

    self.state = TASK_CANCELLED;

    if (self.join_waiter != null) {
        self.join_waiter.cancel();
        self.join_waiter = null;
    }
}

fn void? Task.join(&self)
{
    if (self.state == TASK_DONE) {
        if (self.error != NONE) return self.error~;
        return;
    }

    if (self.state == TASK_CANCELLED) {
        return ASYNC_CANCELLED~;
    }

    if (self.state == TASK_FAILED) {
        if (self.error != NONE) return self.error~;
        return ASYNC_FAILED~;
    }

    Task* current = self.loop.current;

    if (current == null || current == self) {
warn("-");
        return ASYNC_INVALID_STATE~;
    }

    if (self.join_waiter != null) {
warn("-");
        return ASYNC_INVALID_STATE~;
    }

    Waiter waiter;
    waiter.init(current);

    self.join_waiter = &waiter;

    current.suspend(&waiter);

    waiter.check()!;

    if (self.error != NONE) {
        return self.error~;
    }
}

