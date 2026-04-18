// loop.c3

module ext::asyncio;

import std::io;
import std::thread;
import std::time::clock;
import c::stdlib;
import c::errno;
import ext::debug;
import ext::mem;
import ext::thread::fiber;

enum State : char {
    INIT,
    PENDING,
    SUSPENDED,
    CANCELLED,
    FINISHED,
}

faultdef NONE, IO_ERROR, CANCELLED_ERR, INVALID_STATE_ERR, MAX_CALLBACK_EXCEEDED, TIMEOUT, QUEUE_FULL, QUEUE_EMPTY, GENERAL_ERROR;

// ---------------------------------------
//  sleep / convenience functions
// ---------------------------------------

// Yield the current Task for one tick (give CPU to other Tasks).
// Returns CANCELLED_ERR if the task was cancelled while waiting.
fn void? sleep_zero() @maydiscard
{
    EventLoop* loop = get_running_loop();

    Task* cur = loop.current;
    @assert(cur != null, "asyncio: sleep_zero() called outside a task");
    cur.state = State.PENDING;
    loop._enqueue(cur);
    fiber::yield();

    // Cancellation checkpoint
    if (cur.cancelling() > 0) return CANCELLED_ERR~;
}

fn ulong clock_now() @inline // micro second
{
    return (ulong) clock::now()/1000; // nano to micro
}

fn void? sleep_us(ulong us) @maydiscard
{
    EventLoop* loop = get_running_loop();
    if (loop == null || loop.closing) return;
    Future* f = loop.create_future();
    loop._timer_push(clock_now()+us, f);

    defer {
        if (loop != null && !loop.closed) {
            loop._cancel_timer_future(f);
        }
    }
    
    f.await()!;  // propagates CANCELLED_ERR if cancelled
}

fn void? sleep_ms(ulong ms) @maydiscard
{
    sleep_us(ms * 1_000)!;
}

fn void? sleep(double s) @maydiscard
{
    sleep_us((ulong)(s * 1_000_000))!;
}

// ---------------------------------------
//  shield / gather / wait_any / as_completed
// ---------------------------------------

// Thread-locals used by the shield relay coroutine
tlocal Future* _shield_src = null;
tlocal Future* _shield_dst = null;

fn void _shield_relay()
{
    Future* src = _shield_src;
    Future* dst = _shield_dst;
    _shield_src = null;
    _shield_dst = null;
    // shield_relay itself is not user-cancellable; ignore fault and let src finish
    void* res = src.await() ?? null;
    if (!dst.done()) dst.set_result(res);
}

// Protect fut from external cancellation; returns a new proxy Future
fn Future* shield(Future* fut)
    {
    @assert(_shield_src == null, "shield() is running, no two shield() at the same time");
    Future* outer = fut.loop.create_future();
    outer.add_done_callback(&_cancel_free_future, outer);
    _shield_src = fut;
    _shield_dst = outer;
    Task* t = task_new(outer.loop, &_shield_relay, "shield_relay");
    t.add_done_callback(&_cancel_free_task, t);
    return outer;
}

// Wait for all Tasks to complete.
// Returns CANCELLED_ERR if the calling task is cancelled while waiting.
fn void? gather(Task*[] tasks) @maydiscard
{
    usz len = tasks.len;
    while (true) {
        bool all_done = true;
        for (usz i = 0; i < len; i++) {
            if (tasks[i] == null) continue;
            if (!tasks[i].done()) {
                all_done = false;
                break;
            } else {
                Task* t = tasks[i];
                tasks[i] = tasks[len-1];
                tasks[len-1] = null;
                len--;
                t.defer_free();
            }
        }
        if (all_done) {
            break;
        }
        sleep_zero()!;
    }
    for (usz i = 0; i < len; i++) {
        tasks[i].defer_free();
    }
}

// Return the index of the first Future to complete.
// Returns CANCELLED_ERR if the calling task is cancelled while waiting.
fn usz? wait_any(Future** futs, usz count) @maydiscard
{
    while (true) {
        for (usz i = 0; i < count; i++) {
            if (futs[i].done()) return i;
        }
        sleep_zero()!;
    }
}

// Invoke cb in completion order.
// Returns CANCELLED_ERR if the calling task is cancelled while waiting.
alias CompletedCallback = fn void(Task*, usz);
fn void? as_completed(Task** tasks, usz count, CompletedCallback cb) @maydiscard
{
    @assert(count <= cfg.task_queue_size, "too many tasks as_completed");
    
    bool[] flags = mem_alloc_array(bool, cfg.task_queue_size);
    defer mem_free(flags);
    
    usz done = 0;
    while (done < count) {
        for (usz i = 0; i < count; i++) {
            if (!flags[i] && tasks[i].done()) {
                flags[i] = true;
                done++;
                cb(tasks[i], i);
            }
        }
        if (done < count) sleep_zero()!;
    }
}

// ---------------------------------------
//  Timer (min-heap)
// ---------------------------------------

struct TimerEntry {
    ulong deadline_us;
    Future* future;
    bool cancelled;
}

// ---------------------------------------
//  CallbackHandle
//  Returned by call_soon() / call_lat()er / call_at().
//  The caller can cancel() it before it fires.
// ---------------------------------------

alias SoonCallback = fn void(void*);

struct CallbackHandle {
    SoonCallback cb;
    void* arg;
    bool cancelled;
}

fn CallbackHandle* callbackhandle_new(SoonCallback cb, void* arg) @private
{
    CallbackHandle* h = mem_alloc(CallbackHandle);
    *h = { cb, arg, false };
    return h;
}

// Cancel this callback before it fires.
// Safe to call even if already fired or cancelled.
fn void CallbackHandle.cancel(&self)
{
    self.cancelled = true;
}

fn void CallbackHandle.free(&self)
{
    mem_free(self);
}

// ---------------------------------------
//  CallbackTimerEntry  (separate heap from Future timers)
// ---------------------------------------

struct CallbackTimerEntry {
    ulong deadline_us;
    CallbackHandle* handle;
}

// ---------------------------------------
//  EventLoop
// ---------------------------------------

struct EventLoopConfig {
    usz task_queue_size;
    usz timer_queue_size;
    usz soon_queue_size;
    bool initialized;
}

tlocal EventLoopConfig cfg;

fn void set_eventloop_config(usz taskq=1024, usz timerq=512, usz soonq=512)
{
    if (cfg.initialized) {
        warn("Already initialized");
        return;
    }
    cfg = { taskq, timerq, soonq, true };
    mem::set_allocator(mem);
}

struct EventLoop {
    Task*[] queue;
    usz q_head;
    usz q_tail;
    usz q_count;
    usz q_cap;
    
    TimerEntry[] timers;
    usz timer_count;
    usz timer_cap;
    Task* current; // currently executing Task
    fiber::Fiber* main_fiber; // fiber representing the loop itself
    bool running;
    bool closed;

    CallbackHandle*[] soon_queue;
    usz soon_head;
    usz soon_tail;
    usz soon_count;
    usz soon_cap;
    
    CallbackTimerEntry[] cb_timers;
    usz cb_timer_count;
    usz cb_timer_cap;

    thread::Mutex ts_mutex;
    CallbackHandle*[] ts_queue;
    usz ts_count;
    
    Future*[] to_free;
    usz to_free_count;
    usz to_free_cap;

    Task*[] to_free_tasks;
    usz to_free_task_count;
    usz to_free_task_cap;
    
    bool closing;
    
    Task*[] all_tasks;
    usz all_task_count;
    usz all_task_cap;
}

tlocal EventLoop* loop;

fn EventLoop* new_event_loop()
{
    if (!cfg.initialized) {
        set_eventloop_config(); // default
    }
    
    io_init();
    
    EventLoop* lp = mem_alloc(EventLoop);
    *lp = {};
    lp.q_cap = cfg.task_queue_size;
    lp.queue = mem_alloc_array(Task*, lp.q_cap);
    lp.q_count = 0;
    
    lp.timer_cap = cfg.timer_queue_size;
    lp.timers = mem_alloc_array(TimerEntry, lp.timer_cap);
    lp.timer_count = 0;

    lp.soon_cap = cfg.soon_queue_size;
    lp.soon_queue = mem_alloc_array(CallbackHandle*, lp.soon_cap);
    lp.soon_count = 0;
    
    lp.ts_queue = mem_alloc_array(CallbackHandle*, lp.soon_cap);
    lp.ts_count = 0;
    
    lp.cb_timer_cap  = cfg.timer_queue_size;
    lp.cb_timers = mem_alloc_array(CallbackTimerEntry, lp.cb_timer_cap);
    lp.cb_timer_count = 0;

    lp.ts_mutex.init()!!;
    lp.main_fiber = fiber::active();

    lp.to_free_cap = 256;
    lp.to_free = mem_alloc_array(Future*, lp.to_free_cap);
    lp.to_free_count = 0;

    lp.to_free_task_cap = 128;
    lp.to_free_tasks = mem_alloc_array(Task*, lp.to_free_task_cap);
    lp.to_free_task_count = 0;
    
    lp.closing = false;

    lp.all_task_cap = 256;
    lp.all_tasks = mem_alloc_array(Task*, lp.all_task_cap);
    lp.all_task_count = 0;
    
    return lp;
}

fn void EventLoop.free(&self)
{
    self.ts_mutex.destroy()!!;

    mem_free(self.queue);
    mem_free(self.timers);
    mem_free(self.soon_queue);
    mem_free(self.ts_queue);
    mem_free(self.cb_timers);
    mem_free(self.all_tasks);
    mem_free(self.to_free);
    mem_free(self.to_free_tasks);

    mem_free(self);
}

fn void set_event_loop(EventLoop* lp)
{
    loop = lp;
}

fn EventLoop* get_running_loop()
{
    return loop;
}

fn void EventLoop._enqueue(&self, Task* task)
{
    if (task == null) return;
    if (self.closing) return;
    if (task.queued_for_free) return;
    if (task.done() || task.state == State.CANCELLED) return;
    if (task.queued) return;
    
    task.queued = true;

    @assert(self.q_count < self.q_cap, "asyncio: task queue overflow. Set by calling\nasyncio::set_eventloop_config(queue_size=1024, timer=512, soon_queue=512)");
    self.queue[self.q_tail] = task;
    self.q_tail = (self.q_tail + 1) % self.q_cap;
    self.q_count++;
}

fn Task* EventLoop._dequeue(&self)
{
    if (self.q_count == 0) return null;
    Task* t = self.queue[self.q_head];
    if (t != null) t.queued = false;
    self.q_head = (self.q_head + 1) % self.q_cap;
    self.q_count--;
    return t;
}

// -- Timer min-heap operations --

fn void EventLoop._timer_push(&self, ulong deadline_us, Future* fut)
{
    @assert(self.timer_count < self.timer_cap, "asyncio: timer queue overflow. Set by calling\nasyncio::set_eventloop_config(queue_size=1024, timer=512, soon_queue=512)");
    usz i = self.timer_count++;
    self.timers[i] = { deadline_us, fut, false };
    // Sift up
    while (i > 0) {
        usz p = (i - 1) / 2;
        if (self.timers[p].deadline_us <= self.timers[i].deadline_us) break;
        TimerEntry tmp = self.timers[p];
        self.timers[p] = self.timers[i];
        self.timers[i] = tmp;
        i = p;
    }
}

fn void EventLoop._timer_pop(&self)
{
    if (self.timer_count == 0) return;
    self.timers[0] = self.timers[--self.timer_count];
    // Sift down
    usz i = 0;
    while (true) {
        usz l = 2*i + 1;
        usz r = 2*i + 2;
        usz s = i;
        if (l < self.timer_count && self.timers[l].deadline_us < self.timers[s].deadline_us) s = l;
        if (r < self.timer_count && self.timers[r].deadline_us < self.timers[s].deadline_us) s = r;
        if (s == i) break;
        TimerEntry tmp = self.timers[i];
        self.timers[i] = self.timers[s];
        self.timers[s] = tmp;
        i = s;
    }
}

fn void EventLoop._fire_timers(&self)
{
    ulong now = clock_now();
    while (self.timer_count > 0 && self.timers[0].deadline_us <= now) {
        TimerEntry te = self.timers[0];
        self._timer_pop();
        if (te.future == null) continue;
        if (!te.cancelled && !te.future.done()) {
            te.future.set_result(null);
        }
    }
}

fn void EventLoop._cancel_timer_future(&self, Future* fut)
{
    for (usz i = 0; i < self.timer_count; i++) {
        if (self.timers[i].future == fut) {
            self.timers[i].cancelled = true;
            // self.timers[i].future.cancel("timer cancel");
            // self.timers[i].future.free();
            self.timers[i].future = null;
            break;
        }
    }
    fut.cancel("timer cancelled");
    fut.free();
}

fn void EventLoop._register_task(&self, Task* t)
{
    if (t == null) return;

    if (self.all_task_count == self.all_task_cap) {
        usz new_cap = self.all_task_cap * 2;
        Task*[] arr = mem_alloc_array(Task*, new_cap);
        for (usz i = 0; i < self.all_task_count; i++) arr[i] = self.all_tasks[i];
        mem_free(self.all_tasks);
        self.all_tasks = arr;
        self.all_task_cap = new_cap;
    }
    self.all_tasks[self.all_task_count++] = t;
    // warn("**** _register_task %d %s", self.all_task_count, t.name);
}

fn void EventLoop._unregister_task(&self, Task* t)
{
    if (t == null) return;
    // warn("_unregister_task n=%d %s", self.all_task_count, t.name);
    for (usz i = 0; i < self.all_task_count; i++) {
        // warn("tasks[%d] %s", i, self.all_tasks[i].name);

        if (self.all_tasks[i] == t) {
            usz last = self.all_task_count - 1;
            self.all_tasks[i] = self.all_tasks[last];
            self.all_tasks[last] = null;
            self.all_task_count--;
            return;
        }
    }
}

fn void _cancel_free_future(Future* fut, CallbackCtx ctx)
{
    if (fut == null) return;
    fut.loop._defer_free_future(fut);
}

fn void EventLoop._defer_free_future(&self, Future* f)
{
    if (f == null) return;
    if (f.queued_for_free) return;
    f.queued_for_free = true;

    if (self.to_free_count == self.to_free_cap) {
        usz new_cap = self.to_free_cap * 2;
        Future*[] arr = mem_alloc_array(Future*, new_cap);
        for (usz i = 0; i < self.to_free_count; i++) arr[i] = self.to_free[i];
        mem_free(self.to_free);
        self.to_free = arr;
        self.to_free_cap = new_cap;
    }
    self.to_free[self.to_free_count++] = f;
}

fn void EventLoop._flush_deferred_future_frees(&self)
{
    for (usz i = 0; i < self.to_free_count; i++) {
        Future* f = self.to_free[i];
        self.to_free[i] = null;
        if (f == null) continue;

        f.free();
    }
    self.to_free_count = 0;
}

fn void _cancel_free_task(Future* fut, CallbackCtx ctx)
{
    if (fut == null) return;
    fut.loop._defer_free_task((Task*)fut);
}

fn void EventLoop._defer_free_task(&self, Task* t)
{
    if (t == null) return;

    if (self.to_free_task_count == self.to_free_task_cap) {
        usz new_cap = self.to_free_task_cap * 2;
        Task*[] arr = mem_alloc_array(Task*, new_cap);
        for (usz i = 0; i < self.to_free_task_count; i++) arr[i] = self.to_free_tasks[i];
        mem_free(self.to_free_tasks);
        self.to_free_tasks = arr;
        self.to_free_task_cap = new_cap;
    }

    self.to_free_tasks[self.to_free_task_count++] = t;
}

fn void EventLoop._flush_deferred_task_frees(&self)
{
    for (usz i = 0; i < self.to_free_task_count; i++) {
        Task* t = self.to_free_tasks[i];
        self.to_free_tasks[i] = null;
        if (t == null) continue;
        // warn("%s", $$FUNC);
        t.free();
    }
    self.to_free_task_count = 0;
}

// ---------------------------------------
//  create_task  (helper callable inside run())
// ---------------------------------------

fn Task* EventLoop.create_task(&self, Coroutine coro, String name = "", usz stack_size = 128_000, bool autofree = false, void* arg = null)
{
    // @assert(self.running, "asyncio: create_task() called outside run()");
    Task* task = task_new(self, coro, name, stack_size, autofree, arg);
    if (self.current != null) {
        while (task.state == State.INIT) {
            asyncio::sleep_zero(); // assure parameter passing to coro (_init_task to _trampoline) without interference
        }
    }
    return task;
}

// ---------------------------------------
//  EventLoop — control methods
// ---------------------------------------

// Return the loop-internal monotonic clock value in microseconds.
// Use this instead of raw clock::now() when scheduling relative to the loop.
fn ulong EventLoop.time(&self)
{
    return clock_now();
}

// Return true if the loop is currently running (between run/run_forever and stop/close).
fn bool EventLoop.is_running(&self)
{
    return self.running;
}

// Return true if close() has been called on this loop.
fn bool EventLoop.is_closed(&self)
{
    return self.closed;
}

// Allocate a new Future already bound to this loop.
// Equivalent to Python's loop.create_future().
fn Future* EventLoop.create_future(&self)
{
    return future_new(self);
}

// Stop the loop after the current iteration finishes.
// If the loop is running run_forever(), it will exit cleanly.
// If it is inside run(), the current task batch finishes first.
fn void EventLoop.stop(&self)
{
    self.running = false;
}

// Release all resources held by the loop.
// Must be called after run() / run_forever() returns.
// Cancels any pending callback handles.

fn void EventLoop.close(&self)
{
    if (self.closing) return;
    self.closing = true;
    
    @assert(!self.running, "asyncio: cannot close a running loop");

    // Cancel and free all pending call_soon handles
    while (self.soon_count > 0) {
        CallbackHandle* h = self.soon_queue[self.soon_head];
        self.soon_head = (self.soon_head + 1) % self.soon_cap;
        self.soon_count--;
        h.cancel();
        h.free();
    }

    // Cancel and free all pending callback-timer handles
    for (usz i = 0; i < self.cb_timer_count; i++) {
        self.cb_timers[i].handle.cancel();
        self.cb_timers[i].handle.free();
        self.cb_timers[i] = {};
    }
    self.cb_timer_count = 0;

    // Drain thread-safe queue
    self.ts_mutex.lock()!!;
    for (usz i = 0; i < self.ts_count; i++) {
        self.ts_queue[i].cancel();
        self.ts_queue[i].free();
        //self.ts_queue[i] = null;
    }
    self.ts_count = 0;
    self.ts_mutex.unlock()!!;

    self.closed  = true;
    self.running = false;

    // Free all tasks owned by loop (even if pending/suspended)
    usz task_count = self.all_task_count;
    self.all_task_count = 0; // prevent _unregister_task loop

    for (usz i = 0; i < task_count; i++) {
        Task* t = self.all_tasks[i];

        if (t == null) continue;

        if (t.fut_waiter != null) {
            t.fut_waiter.cancel("loop closing");

            t.fut_waiter = null;
        }
        self.all_tasks[i] = null;

        t.free();
    }
    self.all_task_count = 0;

    // Cancel and free all pending Future timers (sleep_us etc)
    for (usz i = 0; i < self.timer_count; i++) {
        Future* f = self.timers[i].future;
        if (f != null) {
            self.timers[i].cancelled = true;
            self.timers[i].future = null;
            self.timers[i] = {};
            f.cancel("loop closing");
            f.free();
        }
    }
    self.timer_count = 0;

    self._flush_deferred_future_frees();
    self._flush_deferred_task_frees();

    io_destroy();
    
    fiber::deinit();
}

// Run the loop forever until stop() is called.
// Unlike run(), no initial task is registered; the caller sets up tasks beforehand.
fn void EventLoop.run_forever(&self)
{
    @assert(!self.closed,  "asyncio: run_forever() called on a closed loop");
    @assert(!self.running, "asyncio: run_forever() called on an already running loop");

    self.running = true;

    while (self.running) {
        // 1. Drain thread-safe incoming queue into the main soon_queue
        self._drain_threadsafe();

        // 2. Fire all ready call_soon callbacks
        self._fire_soon();

        // 3. Fire expired timers (Future-based)
        self._fire_timers();

        // 4. Fire expired callback-timers
        self._fire_cb_timers();

        if (io_pending()) io_poll(0);

        // 5. Dequeue and execute the next ready Task
        Task* task = self._dequeue();

        if (task == null) {
            // Nothing to run right now; keep spinning while timers are pending
            if (self.timer_count == 0 && self.cb_timer_count == 0 && self.soon_count == 0 && !io_pending()) {
                // No work at all — stay alive only if stop() hasn't been called externally
                // (caller is expected to call stop() to exit run_forever)
                thread::sleep_ms(1);
                continue;
            }
            
            ulong timeout_us = 1_000;
            ulong now = clock_now();
            if (self.timer_count > 0) {
                ulong t = self.timers[0].deadline_us;
                ulong d = t > now ? t - now : 0;
                if (d < timeout_us) timeout_us = d;
            }
            if (self.cb_timer_count > 0) {
                ulong t = self.cb_timers[0].deadline_us;
                ulong d = t > now ? t - now : 0;
                if (d < timeout_us) timeout_us = d;
            }
        
            io_poll(timeout_us);

            continue;
        }

        if (task.state == State.CANCELLED) {
            if (task.fiber != null) {
                //fiber::delete(task.fiber);
                //task.fiber = null;
            }
            continue;
        }

        if (task.state == State.SUSPENDED) continue;

        task.step();

        self._flush_deferred_future_frees();
        self._flush_deferred_task_frees();
    }
}

// ---------------------------------------
//  EventLoop — callback scheduling
// ---------------------------------------

// Schedule cb(arg) to be called on the next loop iteration.

fn CallbackHandle* EventLoop.call_soon(&self, SoonCallback cb, void* arg = null)
{
    if (self.closing) return null;
    
    @assert(!self.closed, "asyncio: call_soon() on a closed loop");

    if (self.soon_count >= self.soon_cap) {
        warn("asyncio: soon queue overflow. Set by calling\nasyncio::set_eventloop_config(queue_size=1024, timer=512, soon_queue=512)");
        return null;
    }

    CallbackHandle* h = callbackhandle_new(cb, arg);
    self.soon_queue[self.soon_tail] = h;
    self.soon_tail = (self.soon_tail + 1) % self.soon_cap;
    self.soon_count++;
    return h;
}

// Schedule cb(arg) to be called after delay_us microseconds.

fn CallbackHandle* EventLoop.call_later_us(&self, ulong delay_us, SoonCallback cb, void* arg = null)
{
    if (self.closing) return null;
    return self.call_at_us(clock_now() + delay_us, cb, arg);
}

// Convenience wrappers matching the sleep_* naming convention.
fn CallbackHandle* EventLoop.call_later_ms(&self, ulong delay_ms, SoonCallback cb, void* arg = null)
{
    if (self.closing) return null;
    return self.call_later_us(delay_ms * 1_000, cb, arg);
}

fn CallbackHandle* EventLoop.call_later(&self, double delay_sec, SoonCallback cb, void* arg = null)
{
    if (self.closing) return null;
    return self.call_later_us((ulong)(delay_sec * 1_000_000), cb, arg);
}

// Schedule cb(arg) to be called at an absolute loop timestamp (microseconds).
// Use loop.time() to get the current timestamp.

fn CallbackHandle* EventLoop.call_at_us(&self, ulong when_us, SoonCallback cb, void* arg = null)
{
    if (self.closing) return null;
    @assert(!self.closed, "asyncio: call_at() on a closed loop");
    if (self.cb_timer_count >= self.timer_cap) {
        warn("asyncio: cb_timer queue overflow");
        return null;
    }
    CallbackHandle* h = callbackhandle_new(cb, arg);
    self._cb_timer_push(when_us, h);
    
    return h;
}

fn CallbackHandle* EventLoop.call_at(&self, double when_sec, SoonCallback cb, void* arg = null)
{
    if (self.closing) return null;
    return self.call_at_us((ulong)(when_sec * 1_000_000), cb, arg);
}

// Thread-safe variant of call_soon.
// Safe to call from any OS thread; the callback will be executed on the event-loop thread.

fn CallbackHandle* EventLoop.call_soon_threadsafe(&self, SoonCallback cb, void* arg = null)
{
    // lock first: close/free prevent race
    self.ts_mutex.lock()!!;
    if (self.closing || self.closed) {
        self.ts_mutex.unlock()!!;
        return null;
    }

    if (self.ts_count >= self.soon_cap) {
        self.ts_mutex.unlock()!!;
        warn("asyncio: threadsafe queue overflow");
        return null;
    }

    CallbackHandle* h = callbackhandle_new(cb, arg);
    self.ts_queue[self.ts_count++] = h;
    self.ts_mutex.unlock()!!;
    
    return h;
}

// ---------------------------------------
//  Internal: drain / fire helpers
// ---------------------------------------

// Move all pending thread-safe callbacks into the main soon_queue.
// Called at the top of each loop iteration.
fn void EventLoop._drain_threadsafe(&self)
{
   self.ts_mutex.lock()!!;
    usz n = self.ts_count;
    if (n == 0) {
        self.ts_mutex.unlock()!!;
        return;
    }
    self.ts_count = 0;
    self.ts_mutex.unlock()!!;

    // ts_queue[0..n-1] is safe to read here:
    // ts_count was zeroed under the lock, so any new call_soon_threadsafe
    // will write starting at ts_queue[0] — no overlap until we're done.
    for (usz i = 0; i < n; i++) {
        CallbackHandle* h = self.ts_queue[i];
        if (h.cancelled) {
            h.free();
            continue;
        }

        if (self.soon_count < self.soon_cap) {
            self.soon_queue[self.soon_tail] = h;
            self.soon_tail  = (self.soon_tail + 1) % self.soon_cap;
            self.soon_count++;
        } else {
            warn("soon_queue overflow, discard a handle silently");
            h.free();
        }
    }
}

// Execute all currently queued call_soon callbacks in FIFO order.
// Callbacks added during this pass are deferred to the next iteration.
fn void EventLoop._fire_soon(&self)
{
    // Snapshot the count so newly added callbacks run next iteration, not this one
    usz n = self.soon_count;
    for (usz i = 0; i < n; i++) {
        CallbackHandle* h = self.soon_queue[self.soon_head];
        self.soon_head  = (self.soon_head + 1) % self.soon_cap;
        self.soon_count--;
        if (!h.cancelled) {
            h.cb(h.arg);
        }
        h.free();
    }
}

// ---------------------------------------
//  Internal: callback-timer min-heap
// ---------------------------------------

fn void EventLoop._cb_timer_push(&self, ulong deadline_us, CallbackHandle* h)
{
    usz i = self.cb_timer_count++;
    self.cb_timers[i] = { deadline_us, h };
    // Sift up
    while (i > 0) {
        usz p = (i - 1) / 2;
        if (self.cb_timers[p].deadline_us <= self.cb_timers[i].deadline_us) break;
        CallbackTimerEntry tmp = self.cb_timers[p];
        self.cb_timers[p] = self.cb_timers[i];
        self.cb_timers[i] = tmp;
        i = p;
    }
}

fn void EventLoop._cb_timer_pop(&self)
{
    if (self.cb_timer_count == 0) return;
    self.cb_timers[0] = self.cb_timers[--self.cb_timer_count];
    // Sift down
    usz i = 0;
    while (true) {
        usz l = 2*i + 1;
        usz r = 2*i + 2;
        usz s = i;
        if (l < self.cb_timer_count && self.cb_timers[l].deadline_us < self.cb_timers[s].deadline_us) s = l;
        if (r < self.cb_timer_count && self.cb_timers[r].deadline_us < self.cb_timers[s].deadline_us) s = r;
        if (s == i) break;
        CallbackTimerEntry tmp = self.cb_timers[i];
        self.cb_timers[i]  = self.cb_timers[s];
        self.cb_timers[s] = tmp;
        i = s;
    }
}

// Fire all callback-timers whose deadline has passed.
fn void EventLoop._fire_cb_timers(&self)
{
    ulong now = clock_now();
    while (self.cb_timer_count > 0 && self.cb_timers[0].deadline_us <= now) {
        CallbackTimerEntry te = self.cb_timers[0];
        self._cb_timer_pop();
        if (!te.handle.cancelled) {
            te.handle.cb(te.handle.arg);
        }
        te.handle.free();
    }
}

fn void run(Coroutine main_coro)
{
    loop = new_event_loop();
    loop.running = true;
    
    // Register the main coroutine as the first Task
    Task* tt = loop.create_task(main_coro, "main", 80_000);
    
    while (loop.running) {
        // 1. Drain thread-safe queue into soon_queue
        loop._drain_threadsafe();

        // 2. Fire all ready call_soon callbacks
        loop._fire_soon();

        // 3. Fire expired Future-based timers (sleep_us/ms/sec)
        loop._fire_timers();

        // 4. Fire expired callback-timers (call_later / call_at)
        loop._fire_cb_timers();

        if (io_pending()) io_poll(0);

        // 5. Dequeue next ready Task
        Task* task = loop._dequeue();

        if (task == null) {
            bool has_pending = loop.timer_count > 0 || loop.cb_timer_count > 0 || loop.soon_count > 0 || io_pending();
            if (!has_pending) {
                loop.running = false;
                break;
            }

            ulong timeout_us = 1_000;
            ulong now = clock_now();
            if (loop.timer_count > 0) {
                ulong t = loop.timers[0].deadline_us;
                ulong d = t > now ? t - now : 0;
                if (d < timeout_us) timeout_us = d;
            }
            if (loop.cb_timer_count > 0) {
                ulong t = loop.cb_timers[0].deadline_us;
                ulong d = t > now ? t - now : 0;
                if (d < timeout_us) timeout_us = d;
            }
        
            io_poll(timeout_us);

            continue;
        }

        if (task.state == State.CANCELLED) {
            if (task.fiber != null) {
                //fiber::delete(task.fiber);
                //task.fiber = null;
            }
            continue;
        }

        if (task.state == State.SUSPENDED) continue;

        task.step();
        
        loop._flush_deferred_future_frees();
        loop._flush_deferred_task_frees();
    }
    // tt.free();
    loop.close();
    loop.free();
}
