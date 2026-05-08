// loop.c3

module ext::aio;

import c::unistd;
import ext::mem;
import ext::debug;
import ext::fiber;

LocalAllocator localmem = {};

faultdef NONE, ASYNC_CANCELLED, ASYNC_FAILED, ASYNC_INVALID_STATE;

struct EventLoop {
    Fiber* fiber; // event-loop/main fiber
    Task* current;

    Task* ready_head;
    Task* ready_tail;

    TimerWaiter* timer_head;

    Poller* poller;

    bool running;
    bool stopping;
}

tlocal EventLoop* cur_loop = null;

fn EventLoop* current_loop()
{
    return cur_loop;
}

fn Task* current_task()
{
    EventLoop* loop = current_loop();
    if (loop == null) return null;
    return loop.current;
}

fn EventLoop* loop_new()
{
    if (localmem == (LocalAllocator){}) {
        localmem = tmem;
    }
    
    EventLoop* loop = localmem.alloc(EventLoop);

    *loop = {
        .fiber = null,
        .current = null,
        .ready_head = null,
        .ready_tail = null,
        .timer_head = null,
        .poller = null,
        .running = false,
        .stopping = false,
    };

    loop.fiber = fiber::active();
    loop.poller = poller_new();
    
    return loop;
}

fn void EventLoop.free(&self)
{
    // drain tasks in ready queue
    Task* t = self.ready_head;

    while (t != null) {
        Task* next = t.next_ready;
        t.next_ready = null;
        t.free();
        t = next;
    }

    self.ready_head = null;
    self.ready_tail = null;
    
    if (self.poller != null) {
        self.poller.free();
        self.poller = null;
    }
    
    localmem.free(self);
}

fn bool EventLoop.has_ready(&self) @inline
{
    return self.ready_head != null;
}

fn void EventLoop.push_ready(&self, Task* task)
{
    if (task == null) return;
    if (task.queued) return;

    task.queued = true;

    task.next_ready = null;

    if (self.ready_tail == null) {
        self.ready_head = task;
        self.ready_tail = task;
        return;
    }

    self.ready_tail.next_ready = task;
    self.ready_tail = task;
}

fn Task* EventLoop.pop_ready(&self)
{
    Task* task = self.ready_head;
    if (task == null) return null;

    self.ready_head = task.next_ready;

    if (self.ready_head == null) {
        self.ready_tail = null;
    }

    task.next_ready = null;

    task.queued = false;

    return task;
}

fn void EventLoop.call_soon(&self, Task* task)
{
    if (task == null) return;

    if (task.state == TASK_DONE) return;
    if (task.state == TASK_CANCELLED) return;
    if (task.state == TASK_FAILED) return;
// warn(".mark_ready()");
    task.mark_ready();
    self.push_ready(task);
}

fn Task* EventLoop.spawn(&self, TaskFn entry)
{
    Task* task = self.task_new(entry);
// warn(".call_soon()");
    self.call_soon(task);
    return task;
}

fn void EventLoop.stop(&self)
{
    self.stopping = true;
}

fn bool EventLoop.has_timers(&self) @inline
{
    return self.timer_head != null;
}

fn int EventLoop.compute_poll_timeout(&self)
{
    if (self.has_ready()) return 0;

    if (self.has_timers()) {
        ulong delay = self.next_timer_delay_ms();

        if (delay > 1000) delay = 1000;

        return (int)delay;
    }

    return -1; // infinite
}

fn void EventLoop.run_once(&self)
{
    Task* task = self.pop_ready();

    if (task == null) return;

    if (task.state == TASK_DONE) return;
    if (task.state == TASK_CANCELLED) return;
    if (task.state == TASK_FAILED)return;
    if (task.state == TASK_WAITING) return;
    
    task.resume();

    switch (task.state) {
        case TASK_READY:
            self.push_ready(task);

        case TASK_RUNNING:
            // 보통 step()에서 loop로 돌아오면 RUNNING으로 남으면 안 됨.
            // 그래도 안전하게 다시 ready로 보낸다.
            task.state = TASK_READY;
            self.push_ready(task);

        case TASK_WAITING:
            // Waiter.wake()가 나중에 call_soon()으로 다시 넣는다.
            break;
        case TASK_DONE:
            // join_waiter가 있을 수 있으므로 바로 free하면 위험할 수 있다.
            // 1차 구현에서는 join 대상 task는 사용자가 free하거나,
            // run_until_complete에서 처리하게 둔다.
            break;
        case TASK_CANCELLED:
            break;

        case TASK_FAILED:
            break;

        default:
            // TASK_NEW는 step() 안에서 처리됨.
    }
}

fn void EventLoop.run_forever(&self)
{
    EventLoop* prev_loop = cur_loop;
    cur_loop = self;

    self.running = true;
    self.stopping = false;

    while (!self.stopping) {
        self.process_timers();

        if (self.has_ready()) {
            self.run_once();
            continue;
        }

        int timeout = self.compute_poll_timeout();
    
        if (self.poller != null) {
            if (catch err = self.poller.poll(timeout)) {
                self.stopping = true;
            }
            continue;
        }

        if (self.has_timers()) {
            ulong delay = self.next_timer_delay_ms();

            if (delay > 10) delay = 10;

            if (delay > 0) {
                unistd::usleep((uint)(delay * 1000));
            }

            continue;
        }

        self.run_once();
    }

    self.running = false;
    cur_loop = prev_loop;
}

fn void EventLoop.run_until_complete(&self, Task* main_task)
{
    if (main_task == null) return;

    EventLoop* prev_loop = cur_loop;
    cur_loop = self;

    self.running = true;
    self.stopping = false;
// warn("-");
    self.call_soon(main_task);

    while (!self.stopping)
    {
        // 반드시 매 loop마다 먼저 만료 timer를 ready queue로 옮긴다.
        self.process_timers();

        if (main_task.state == TASK_DONE ||
            main_task.state == TASK_CANCELLED ||
            main_task.state == TASK_FAILED) {
            break;
        }

        if (self.has_ready()) {
            self.run_once();
            continue;
        }

        int timeout = self.compute_poll_timeout();
    
        if (self.poller != null) {
            if (catch err = self.poller.poll(timeout)) {
                self.stopping = true;
            }
            continue;
        }

        if (self.has_timers()) {
            ulong delay = self.next_timer_delay_ms();

            if (delay > 10) delay = 10;

            if (delay > 0) {
                c::unistd::usleep((uint)(delay * 1000));
            }

            continue;
        }

        // ready도 timer도 없으면 deadlock/idle.
        break;
    }

    self.running = false;
    cur_loop = prev_loop;
}

fn void run(TaskFn main)
{
    EventLoop* loop = loop_new();

    Task* main_task = loop.task_new(main);
    loop.run_until_complete(main_task);

    if (main_task.state == TASK_DONE ||
        main_task.state == TASK_CANCELLED ||
        main_task.state == TASK_FAILED) {
        main_task.free();
    }

    loop.free();
}

fn void yield()
{
    Task* task = current_task();
    if (task == null) return;

    EventLoop* loop = task.loop;
    if (loop == null) return;

    task.state = TASK_READY;
    loop.push_ready(task);

    fiber::switch_to(loop.fiber);
}
