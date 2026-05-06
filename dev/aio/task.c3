// task.c3

module ext::aio;

import ext::mem;
import c::stdlib;
import ext::thread::fiber;

tlocal LocalAllocator localmem = {};

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
}

fn Task* current_task()
{
    return current_loop().current;
}

tlocal EventLoop* cur_loop = null; // move to event.c3

fn EventLoop* current_loop()
{
    return cur_loop;
}

struct EventLoop {
    Task* current;
    Fiber* fiber;
}

fn void EventLoop.call_soon(&self, Task* t)
{
}

fn Task* EventLoop.new_task(&self, TaskFn entry)
{
    Task* t = localmem.alloc(Task);

    *t = {
        .stack_size = 64_000,
        .state = TASK_NEW,
        .loop = self,
        .fiber = null,
        .entry = entry,
        .error = NONE,
        .waiting_on = null,
        .join_waiter = null,
        .next_ready = null,
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

tlocal Task* trampoline_task = null;

fn void fiber_trampoline()
{
    Task* t = trampoline_task;

    t.loop.current = t;
    
    t.state = TASK_RUNNING;

    t.entry(); // call fiber coruotine

    t.state = TASK_DONE;
    t.error = NONE;

    fiber::done(); // return to the main loop
}

// Advance one step of a Task's execution
fn void Task.step(&self)
{
    if (self.state == TASK_NEW) {
        self.state = TASK_RUNNING;
        trampoline_task = self;
        self.fiber = fiber::create(self.stack_size, &fiber_trampoline);
    }
    
    if (self.state == TASK_DONE) {
        if (self.join_waiter != null) {
            self.join_waiter.wake();
            self.join_waiter = null;
        }
        self.loop.current = null;
        return;
    }
    
    self.loop.current = self;
    fiber::switch_to(self.fiber);

}

fn void Task.suspend(&self, Waiter* waiter)
{
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
    
    self.state = TASK_READY;
}

fn void Task.resume(&self)
{
    if (self.state == TASK_DONE) return;
    if (self.state == TASK_CANCELLED) return;
    if (self.state == TASK_FAILED) return;

    self.state = TASK_RUNNING;

    Task* prev = current_task();

    self.step();

    self.loop.current = prev;
}

faultdef NONE, ASYNC_CANCELLED, ASYNC_FAILED, ASYNC_INVALID_STATE;

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

    if (current == null) {
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