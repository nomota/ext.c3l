// timer.c3

module ext::aio;

import std::time::clock;
import c::time;
import c::unistd;
import ext::debug;

struct TimerWaiter @private {
    Waiter base;

    ulong deadline_ms;

    TimerWaiter* next;
}

fn ulong clock_now() @inline // micro second
{
    return (ulong) clock::now()/1_000_000; // nano to milli
}

/* only on posix
fn ulong monotonic_ms()
{
    time::TimeSpec ts;

    time::clock_gettime(time::CLOCK_MONOTONIC, &ts);

    return (ulong)ts.tv_sec * 1000 + (ulong)ts.tv_nsec / 1_000_000;
}
*/

fn void TimerWaiter.init(&self, Task* task, ulong deadline_ms)
{
    self.base.init(task);
    self.deadline_ms = deadline_ms;
    self.next = null;
}

fn void EventLoop.add_timer(&self, TimerWaiter* timer)
{
    if (timer == null) return;

    timer.next = null;

    if (self.timer_head == null) {
        self.timer_head = timer;
        return;
    }

    if (timer.deadline_ms < self.timer_head.deadline_ms) {
        timer.next = self.timer_head;
        self.timer_head = timer;
        return;
    }

    TimerWaiter* prev = self.timer_head;
    TimerWaiter* cur = self.timer_head.next;

    while (cur != null && cur.deadline_ms <= timer.deadline_ms) {
        prev = cur;
        cur = cur.next;
    }

    timer.next = cur;
    prev.next = timer;
}

fn void EventLoop.process_timers(&self)
{
//warn("-");
    ulong now = clock_now();

    while (self.timer_head != null) {
        TimerWaiter* timer = self.timer_head;

        if (timer.deadline_ms > now) {
//warn("-");
            break;
        }

        self.timer_head = timer.next;
        timer.next = null;
//warn("-");
        timer.base.wake();
    }
}

fn ulong EventLoop.next_timer_delay_ms(&self)
{
    if (self.timer_head == null) {
 //warn("-");
        return 0;
    }

    ulong now = clock_now();
//warn("%d %d", now, self.timer_head.deadline_ms);
    if (self.timer_head.deadline_ms <= now) {
//warn("%d %d", now, self.timer_head.deadline_ms);
//warn("-");
        return 0;
    }

    ulong delay = self.timer_head.deadline_ms - now;
//warn("delay %d", delay);
    return delay;
}

fn void? sleep(ulong ms)
{
    Task* task = current_task();

    if (task == null) {
        return ASYNC_INVALID_STATE~;
    }

    EventLoop* loop = task.loop;

    if (loop == null) {
        return ASYNC_INVALID_STATE~;
    }

    TimerWaiter timer;
    timer.init(task, clock_now() + ms);

    loop.add_timer(&timer);

    task.suspend(&timer.base);

    timer.base.check()!;

    return;
}

