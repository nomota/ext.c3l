// future.c3

module ext::asyncio;

import std::io;
import std::thread;
import std::time::clock;
import c::stdlib;
import c::errno;
import ext::debug;
import ext::mem;
import ext::thread::fiber;

// ----------------------------------------
//  Configuration constants
// ----------------------------------------

const usz MAX_CALLBACK = 8;

// ----------------------------------------
//  Type aliases
// ----------------------------------------

// Coroutine: zero-argument function (runs on top of a fiber)
alias Coroutine = fn void();

// Done callback: (completed Future*, user context)
alias CallbackCtx = void*;
alias Callback = fn void(Future*, CallbackCtx);

// ----------------------------------------
//  Future
// ----------------------------------------

struct Future {
    EventLoop* loop;
    State state;
    void* result;
    fault error;
    Callback[MAX_CALLBACK] callbacks;
    CallbackCtx[MAX_CALLBACK] contexts;
    usz num_callbacks;
    String cancel_message;
    usz num_cancel_requested;
    bool queued; // ready-queue
    bool running_step; // prevent reentering step()
    bool queued_for_free;
}

fn void future_init(Future* f, EventLoop* loop) @inline @private
{
    *f = {
        .loop = loop,
        .state = State.PENDING,
        .result = null,
        .error = NONE,
        .num_callbacks = 0,
        .cancel_message = "",
        .num_cancel_requested = 0,
        .queued = false,
        .running_step = false,
        .queued_for_free = false,
    };
}

fn Future* future_new(EventLoop* loop) @private
{
    Future* f = localmem.alloc(Future);
    future_init(f, loop);
    return f;
}

fn void Future.free(&self)
{
    if (self.result != null) localmem.free(self.result);
    localmem.free(self);
}

fn void Future.defer_free(&self)
{
    self.add_done_callback(&_cancel_free_future, self);
}

fn bool Future.done(&self)
{
    return (self.state == State.CANCELLED || self.state == State.FINISHED);
}

fn bool Future.cancelled(&self)
{
    return self.state == State.CANCELLED;
}

fn int Future.cancelling(&self)
{
    return (int)self.num_cancel_requested;
}

// result must be free'd by caller

fn void*? Future.get_result(&self)
{
    if (self.state == State.PENDING || self.state == State.SUSPENDED) {
        self.set_exception(INVALID_STATE_ERR);
        return INVALID_STATE_ERR~;
    }
    if (self.state == State.CANCELLED) {
        self.set_exception(CANCELLED_ERR);
        return CANCELLED_ERR~;
    }
    return self.result;
}

fn fault Future.get_error(&self)
{
    return self.error;
}

<*
   data must be a heap allocated value
*>
fn void? Future.set_result(&self, void* data) @maydiscard
{
    if (self.state != State.PENDING) {
        self.set_exception(INVALID_STATE_ERR);
        return INVALID_STATE_ERR~;
    }
    if (self.result != null) localmem.free(self.result);
    self.state = State.FINISHED;
    self.result = data;

    if (self.loop != null && self.loop.closing) {
        self.num_callbacks = 0;
        return;
    }

    self._fire_callbacks();
}

fn void Future.set_exception(&self, fault err)
{
    if (self.done()) return;
    self.error = err;
}

fn void Future.cancel(&self, String msg = "")
{
    if (self.done()) return;
    self.state = State.CANCELLED;
    self.cancel_message = msg;
    self.num_cancel_requested += 1;

    if (self.loop != null && self.loop.closing) {
        self.num_callbacks = 0;
        return;
    }

    self._fire_callbacks();
}

fn void Future.add_done_callback(&self, Callback cb, CallbackCtx ctx = null)
{
    // If already done, schedule callbacks immediately
    if (self.done()) {
        cb(self, ctx);
        return;
    }
    
    if (self.num_callbacks >= MAX_CALLBACK) {
        self.set_exception(MAX_CALLBACK_EXCEEDED);
        return;
    }
    self.callbacks[self.num_callbacks] = cb;
    self.contexts[self.num_callbacks] = ctx;
    self.num_callbacks += 1;
}

fn usz Future.remove_done_callback(&self, Callback cb)
{
    usz removed = 0;
    usz i = 0;
    while (i < self.num_callbacks) {
        if (self.callbacks[i] == cb) {
            // Shift subsequent entries down by one
            for (usz j = i + 1; j < self.num_callbacks; j++) {
                self.callbacks[j-1] = self.callbacks[j];
                self.contexts [j-1] = self.contexts [j];
            }
            self.num_callbacks--;
            removed++;
            // Do not advance i: re-check the shifted element
        } else {
            i++;
        }
    }
    return removed;
}

fn EventLoop* Future.get_loop(&self)
{
    return self.loop;
}

// Suspend the current Task until this Future completes.
// Returns CANCELLED_ERR if the task was cancelled while waiting.
fn void*? Future.await(&self) @maydiscard
{
    if (self.done()) return self.result;

    Task* cur = self.loop.current;
    @assert(cur != null, "asyncio: await() called outside a task");

    cur.state = State.SUSPENDED;
    cur.awaiting = self;

    fiber::yield(); // yield control back to EventLoop

    cur.awaiting = null;

    // Cancellation checkpoint: if this task was cancelled while suspended,
    // propagate as a fault so the coroutine unwinds immediately.
    if (cur.cancelling() > 0 || self.cancelled()) return CANCELLED_ERR~;

    return self.result;
}

// Internal: fire all registered callbacks then reset the list
fn void Future._fire_callbacks(&self)
{
    usz n = self.num_callbacks;
    self.num_callbacks = 0;   // clear first to prevent re-entrant double-fire
    for (usz i = 0; i < n; i++) {
        self.callbacks[i](self, self.contexts[i]);
    }
}

// ----------------------------------------
//  wait_for only context
// ----------------------------------------

struct WaitForCtx {
    Task* waiter; // Task to wake
    Future* timer; // timeout Future
    bool fired; // prevent duplicate wakeup
}

// invoked when src or timer gets fired
fn void _wait_for_wakeup(Future* completed, CallbackCtx ctxp)
{
    WaitForCtx* ctx = (WaitForCtx*)ctxp;
    
    if (ctx.fired) return;
    ctx.fired = true;

    Task* t = ctx.waiter;

    if (t.loop != null && t.loop.closing) return;

    if (!t.done()) {
        t.state = State.PENDING;
        t.loop._enqueue(t);
    }
}

fn void? Future.wait_for(&self, ulong timeout_us) @maydiscard
{
    if (self.done()) return self.error~;

    EventLoop* lp  = self.loop;
    Task* cur = lp.current;
    @assert(cur != null, "asyncio: wait_for() called outside a task");

    // timeout Future 
    Future* timer = lp.create_future();
    lp._timer_push(clock_now() + timeout_us, timer);

    // callback context
    WaitForCtx ctx = {
        .waiter = cur,
        .timer = timer,
        .fired = false,
    };

    // either one, whichever fires first 
    self.add_done_callback(&_wait_for_wakeup, &ctx);
    timer.add_done_callback(&_wait_for_wakeup, &ctx);

    // suspend once
    cur.state = State.SUSPENDED;
    cur.awaiting = null;
    fiber::yield();

    // check cancel
    if (cur.cancelling() > 0) {
        lp._cancel_timer_future(timer);
        return CANCELLED_ERR~;
    }

    bool timed_out = !self.done();
    if (timed_out) self.cancel("timeout");

    // cleanup timeout Future
    self.remove_done_callback(&_wait_for_wakeup);
    lp._cancel_timer_future(timer);

    return timed_out ? TIMEOUT~ : self.error~;
}

// ----------------------------------------
//  Task  (Future inline-inherited)
// ----------------------------------------

struct Task {
    inline Future fut; // directly inherits Future fields and methods
    Coroutine coro;
    fiber::Fiber* fiber;
    usz stack_size;
    Future* fut_waiter; // the Future currently being waited on
    Future* awaiting; // set inside Future.await()
    bool must_cancel;
    String name;
    // fut.result stores the return value set by _trampoline
    bool autofree;
    void* arg;
}

// Thread-local variables used by the fiber entry point
tlocal Task* _init_task;
tlocal void* _return_value;

// Actual fiber entry function
fn void _trampoline()
{
    Task* t = _init_task;
    _init_task = null;

    t.coro(); // run the coroutine

    if (t.must_cancel) {
        t.state = State.CANCELLED;
        t.error = CANCELLED_ERR;
        t._fire_callbacks();
    } else {
        t.state  = State.FINISHED;
        t.result = _return_value;
        _return_value = null;
        t._fire_callbacks();
    }

    fiber::done(); // return to the main loop
}

// Set the return value of a task (call at the end of a coroutine)
fn void task_return(void* value)
{
    _return_value = value;
}

fn Task* task_new(EventLoop* loop, Coroutine coro, String name = "", usz stack_size = 128_000, bool autofree = false, void* arg = null) @private
{
    Task* t = localmem.alloc(Task);
    future_init(&t.fut, loop);
    t.coro = coro;
    t.name = name;
    t.stack_size = stack_size;
    t.state = State.INIT;
    t.autofree = autofree;
    t.arg = arg;

    loop._register_task(t);
    loop._enqueue(t);
    return t;
}

fn void Task.free(&self)
{
    // warn("Task.free %s %p", self.name, self.loop);
    if (self.loop != null && self.loop.all_task_count > 0) self.loop._unregister_task(self);

    if (self.result != null) {
        localmem.free(self.result);
    }
    if (self.fiber != null) {
        // warn("del fiber %s stack_size:%.dKB, filled:%dKB %.2f%% used.", self.name, self.fiber.stack_size/1024, fiber::stack_used(self.fiber)/1024, (float)fiber::stack_filled(self.fiber)/(float)self.fiber.stack_size*(float)100.0);
        fiber::delete(self.fiber);
        self.fiber = null;
    }
    self.loop = null;
    
    if (self.fut_waiter != null) {
        self.fut_waiter = null;
    }
    localmem.free(self);
}

fn void Task.defer_free(&self)
{
    self.add_done_callback(&_cancel_free_task, self);
}

fn String Task.get_name(&self)
{
    return self.name;
}

fn void Task.set_name(&self, String name)
{
    self.name = name;
}

fn void Task.cancel(&self, String msg = "")
{
    self.num_cancel_requested += 1;
    self.cancel_message = msg;
    if (self.done()) return;

    if (self.fut_waiter != null) {
        self.fut_waiter.cancel(msg);
        self.fut_waiter = null;
    }
    self.must_cancel = true;
}

fn void Task.uncancel(&self)
{
    if (self.num_cancel_requested > 0) self.num_cancel_requested--;
}

// Suspend current Task until this Task completes (delegates to Future.await)
fn void*? Task.await(&self) @maydiscard
{
    return self.fut.await()!;
}

// ----------------------------------------
//  Task scheduler callback
// ----------------------------------------

// Called when fut_waiter completes: re-enqueues the Task
fn void _task_wakeup(Future* fut, CallbackCtx ctx)
{
    Task* t = (Task*)ctx;
    t.fut_waiter = null;

   if (t.loop != null && t.loop.closing) return;
   
    if (!t.done()) {
        t.state = State.PENDING;
        t.loop._enqueue(t);
    }
}

// Advance one step of a Task's execution
fn void Task.step(&self)
{
    if (self.running_step) {
        return;
    }

    if (self.loop == null) return;
    if (self.loop.closing) return;
    if (self.queued_for_free) return;
    if (self.done() || self.state == State.CANCELLED) return;

    self.running_step = true;
    defer { self.running_step = false; }

    if (self.state == State.INIT) {
        _init_task = self;
        _return_value = null;
        self.state = State.PENDING;
        self.fiber = fiber::create((int)self.stack_size, &_trampoline);
    }

    // Switch into the fiber (runs until the coroutine yields or finishes)
    self.loop.current = self;
    
    fiber::switch_to(self.fiber);

    self.loop.current = null;

    // -- post-fiber return handling --

    if (self.done()) {
        // warn("Task.step: %s.done", self.name);
        if (self.autofree) self.defer_free();
        return;
    }

    if (self.awaiting != null) {
        // Suspended via Future.await(): register done callback and wait
        self.fut_waiter = self.awaiting;
        self.awaiting.add_done_callback(&_task_wakeup, self);
        self.awaiting = null;

        // If a cancel was requested, propagate it to the awaited Future
        if (self.must_cancel) {
            self.fut_waiter.cancel(self.cancel_message);
            self.must_cancel = false;
        }
        return;
    }

    // Bare yield (e.g. sleep_zero): task already re-enqueued, nothing to do here
}
