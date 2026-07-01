// loop.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import std::thread;
import std::collections::linkedlist;
import ext::mem;
import ext::debug;
import ext::fiber;

LocalAllocator localmem = null;

bool initialized = false;

fn void init()
{
    if (initialized) return;
    initialized = true;
    
    if (localmem == null) localmem = tmem;
    
    io::init();
    net::init();
}

fn void deinit()
{
    net::deinit();
    io::deinit();
    localmem = null;
    initialized = false;
}

faultdef NONE, CANCELLED, FAILED, INVALID_STATE, TIMEOUT, NO_LOOP;
faultdef IO_ERROR, POLL_ERROR, ADDR_ERROR, OUT_OF_MEMORY, EMPTY_QUEUE, FIBER_ERROR, INVALID_ARG;
faultdef SOCKET_ERROR, CONNECT_ERROR, BIND_ERROR, SENDTO_ERROR, LISTEN_ERROR, ACCEPT_ERROR;

struct EventLoop
{
    Fiber* fiber; // Event-loop/main fiber.
    Task* current;

    LinkedList{Task*} ready;
    LinkedList{Task*} tasks;

    LinkedList{Sleep*} sleeps;

    ThreadSafe threadsafe;
    
    bool running;
    bool stopping;
}

tlocal EventLoop* cur_loop @private = null;

fn EventLoop*? current_loop() @maydiscard
{
    init();
    if (cur_loop == null) return NO_LOOP~;
    return cur_loop;
}

fn Task*? current_task() @maydiscard
{
    init();
    EventLoop* loop = current_loop()!;
    if (loop == null) return NO_LOOP~;

    return loop.current;
}

fn EventLoop*? loop_new()
{
    init();
    EventLoop* loop = localmem.alloc(EventLoop)!;
    *loop = {
        .fiber = null,
        .current = null,
        .running = false,
        .stopping = false,
    };

    loop.ready.init(localmem);
    loop.tasks.init(localmem);
    loop.sleeps.init(localmem);
    
    loop.fiber = fiber::active();
    
    defer (catch err) {
        loop.tasks.free();
        loop.ready.free();
        loop.sleeps.free();
        localmem.free(loop);
    }
    
    loop.threadsafe.init(loop)!;
    
    return loop;
}

fn void EventLoop.free(&self)
{
    self.cancel_all_tasks();
    self.threadsafe.process();

    foreach(task: self.tasks.array_view()) {
        task.free();
    }
    self.tasks.free();
    
    self.ready.free();
    
    self.threadsafe.deinit();
    
    localmem.free(self);
}

fn bool EventLoop.has_live_tasks(&self)
{
    foreach (task: self.tasks.array_view()) {
        if (task == null) continue;

        if (task.state != TASK_DONE &&
            task.state != TASK_CANCELLED &&
            task.state != TASK_FAILED) {
            return true;
        }
    }

    return false;
}

fn bool EventLoop.has_work(&self)
{
    return self.has_ready() ||
        self.has_sleeps() ||
        self.has_live_tasks();
}

fn bool EventLoop.has_ready(&self) @inline
{
    return !self.ready.is_empty();
}

fn void EventLoop.push_ready(&self, Task* task)
{
    if (task == null) return;
    if (task.queued) return;

    task.queued = true;
    
    self.ready.push(task);
}

fn Task*? EventLoop.pop_ready(&self)
{
    if (self.ready.is_empty()) return EMPTY_QUEUE~;
    
    Task* task = self.ready.pop_first()!;
    task.queued = false;

    return task;
}

fn void EventLoop.drain_ready(&self)
{
    while (true) {
        self.threadsafe.process();
        self.process_sleeps();

        if (!self.has_ready()) break;

        self.run_once();
    }
}

fn void EventLoop.call_soon(&self, Task* task)
{
    if (task == null) return;

    if (task.state == TASK_DONE) return;
    if (task.state == TASK_CANCELLED) return;
    if (task.state == TASK_FAILED) return;

    task.mark_ready();
    self.push_ready(task);
}

fn Task*? EventLoop.spawn(&self, TaskFn entry, void* arg = null, bool detached = true)
{
    Task* task = self.task_new(entry, arg)!;

    task.detached = detached;
    
    self.tasks.push(task);
    
    self.call_soon(task);

    return task;
}

fn Task*? spawn(TaskFn task, void* arg = null, bool detached = true)
{
    EventLoop* loop = current_loop()!;
    return loop.spawn(task, arg, detached)!;
}

fn Task*? EventLoop.spawn_joinable(&self, TaskFn task, void* arg = null)
{
    return self.spawn(task, arg, detached: false)!;
}

fn Task*? spawn_joinable(TaskFn task, void* arg = null)
{
    EventLoop* loop = current_loop()!;
    return loop.spawn_joinable(task, arg)!;
}

fn void EventLoop.reap_task(&self, Task* task)
{
    if (task == null) return;

    self.ready.remove_first_match(task);
    self.remove_task_sleeps(task);
    self.tasks.remove_first_match(task);
    
    task.queued = false;
    task.free();
}

fn void EventLoop.cancel_all_tasks(&self)
{
    foreach (task: self.tasks.array_view()) {
        if (task == null) continue;

        if (task.state == TASK_DONE) continue;
        if (task.state == TASK_CANCELLED) continue;
        if (task.state == TASK_FAILED) continue;

        task.cancel();
    }

    for (sz i = 0; i < self.tasks.len(); i++) {
        Task* task = self.tasks.get(i);
        if (task == null) continue;
        if (!task.detached) continue;

        if (task.state == TASK_DONE ||
            task.state == TASK_CANCELLED ||
            task.state == TASK_FAILED)
        {
            self.reap_task(task);
            i--;
        }
    }
}

fn void EventLoop.stop(&self)
{
    if (self.stopping) return;

    self.cancel_all_tasks();

    self.stopping = true;
}

fn void? stop() @maydiscard
{
    EventLoop* loop = current_loop()!;
    loop.stop();
}

fn bool EventLoop.has_sleeps(&self) @inline
{
    return self.sleeps.len() > 0;
}

fn ulong EventLoop.compute_poll_timeout(&self)
{
    if (self.has_ready()) return 0;

    self.threadsafe.lock.lock();
    bool has_threadsafe = self.threadsafe.head != null;
    self.threadsafe.lock.unlock();

    if (has_threadsafe) return 0;

    if (self.has_sleeps()) {
        ulong delay = self.next_sleep_delay_us();

        if (delay > 2_147_483_647) return 2_147_483_647;

        return (ulong)delay;
    }

    return -1; // Wait indefinitely.
}

fn void? EventLoop.run_once(&self) @maydiscard
{
    Task* task = self.pop_ready()!;

    if (task.state == TASK_WAITING) return;

    if (task.state == TASK_DONE ||
        task.state == TASK_CANCELLED ||
        task.state == TASK_FAILED) {
        if (task.detached) self.reap_task(task);
        return;
    }
    
    task.resume();

    switch (task.state) {
        case TASK_READY:
            self.push_ready(task);

        case TASK_RUNNING:
            task.state = TASK_READY;
            self.push_ready(task);

        case TASK_WAITING:
            break;

        case TASK_DONE:
        case TASK_CANCELLED:
        case TASK_FAILED:
            if (task.detached) self.reap_task(task);
            break;

        default: // Nothing
    }
}

fn void? EventLoop.run_forever(&self) @maydiscard
{
    EventLoop* prev_loop = cur_loop;
    cur_loop = self;

    self.running = true;
    self.stopping = false;

    while (!self.stopping) {
        self.threadsafe.process();
        self.process_sleeps();

        if (self.has_ready()) {
            self.run_once()!;
            continue;
        }

        ulong timeout = self.compute_poll_timeout();
        if (io::pending()) io::poll(timeout);
    }

    self.threadsafe.process();
    self.drain_ready();

    self.running = false;
    cur_loop = prev_loop;
}

fn void? EventLoop.run_until_complete(&self, Task* main_task) @maydiscard
{
    if (main_task == null) return;

    EventLoop* prev_loop = cur_loop;
    cur_loop = self;

    self.running = true;
    self.stopping = false;

    self.call_soon(main_task);

    while (!self.stopping) {
        self.threadsafe.process();
        self.process_sleeps();

        if (main_task.state == TASK_DONE || main_task.state == TASK_CANCELLED || main_task.state == TASK_FAILED) {
            break;
        }

        if (self.has_ready()) {
            self.run_once()!;
            continue;
        }

        ulong timeout = self.compute_poll_timeout();
        if (io::pending()) io::poll(timeout);
    }

    self.threadsafe.process();
    self.drain_ready();
    
    self.running = false;
    cur_loop = prev_loop;
}

fn void EventLoop.debug_state(&self) // local
{
    sz task_new = 0;
    sz task_ready = 0;
    sz task_running = 0;
    sz task_waiting = 0;
    sz task_done = 0;
    sz task_cancelled = 0;
    sz task_failed = 0;

    foreach (task: self.tasks.array_view()) {
        if (task == null) continue;

        switch (task.state) {
            case TASK_NEW: task_new++;
            case TASK_READY: task_ready++;
            case TASK_RUNNING: task_running++;
            case TASK_WAITING: task_waiting++;
            case TASK_DONE: task_done++;
            case TASK_CANCELLED: task_cancelled++;
            case TASK_FAILED: task_failed++;
            default:
        }
    }

    warn("sleeps=%d tasks=%d new=%d ready=%d running=%d waiting=%d done=%d cancelled=%d failed=%d",
        self.sleeps.len(),
        self.tasks.len(),
        task_new,
        task_ready,
        task_running,
        task_waiting,
        task_done,
        task_cancelled,
        task_failed
    );
}

fn void? EventLoop.run_main(&self, Task* main_task) @maydiscard
{
    if (main_task == null) return;

    EventLoop* prev_loop = cur_loop;
    cur_loop = self;

    self.running = true;
    self.stopping = false;

    self.call_soon(main_task);

    while (!self.stopping) {
//self.debug_state();
        self.threadsafe.process();
        self.process_sleeps();
        if (self.has_ready()) {
            self.run_once()!;
            continue;
        }

        if (main_task.state == TASK_DONE ||
            main_task.state == TASK_CANCELLED ||
            main_task.state == TASK_FAILED) {
            if (!self.has_work()) break;
        }

        if (!self.has_work()) break;

        ulong timeout = self.compute_poll_timeout();
        if (io::pending()) io::poll(timeout);
    }

    self.threadsafe.process();
    self.drain_ready();

    self.running = false;
    cur_loop = prev_loop;
}

fn void? run(TaskFn main, void* arg = null) @maydiscard
{
    EventLoop* loop = loop_new()!;

    Task* main_task = loop.task_new(main, arg)!;

    main_task.detached = false;
    loop.tasks.push(main_task);

    loop.run_main(main_task)!;

    if (main_task.state == TASK_DONE || main_task.state == TASK_CANCELLED || main_task.state == TASK_FAILED) {
        loop.reap_task(main_task);
    }

    loop.free();
    deinit();
}

fn void? yield() @maydiscard
{
    Task* task = current_task()!;

    EventLoop* loop = task.loop;
    if (loop == null) return;

    task.state = TASK_READY;
    loop.push_ready(task);

    fiber::switch_to(loop.fiber);
}

// eof