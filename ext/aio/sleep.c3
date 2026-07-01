// sleep.c3

module ext::aio;

import std::time::clock;
import c::time;
import c::unistd;
import ext::debug;

struct Sleep @private
{
    Waiter waiter;

    ulong deadline_us;
}

fn ulong clock_now() @inline // micro second
{
    return (ulong) clock::now()/1_000; // nano to micro
}

fn ulong time_ms() @inline // mili second
{
    return (ulong) clock::now()/1_000_000; // nano to mili
}

fn ulong time_us() @inline // micro second
{
    return (ulong) clock::now()/1_000; // nano to micro
}

fn void Sleep.init(&self, Task* task, ulong deadline_us)
{
    self.waiter.init(task);
    self.deadline_us = deadline_us;
}

fn void EventLoop.add_sleep(&self, Sleep* sleep) // private
{
    if (sleep == null) return;

    bool inserted = false;
    for (sz i = 0; i < self.sleeps.len(); i++) {
        Sleep* s = self.sleeps.get(i);
        if (sleep.deadline_us < s.deadline_us) {
            self.sleeps.insert_at(i, sleep);
            inserted = true;
            break;
        }
    }
    if (!inserted) self.sleeps.push(sleep);
}

fn void EventLoop.process_sleeps(&self) // private
{
    ulong now = clock_now();

    while (self.sleeps.len() > 0) {
        Sleep* s = self.sleeps.get(0);
        if (s == null) {
            self.sleeps.remove_at(0);
            continue;
        }
        if (s.deadline_us > now) break;
        self.sleeps.remove_at(0);
        s.waiter.wake();
    }
}

fn void EventLoop.remove_task_sleeps(&self, Task* task)
{
    sz i = 0;
    while (i < self.sleeps.len()) {
        Sleep* s = self.sleeps.get(i);
        Task* t = s.waiter.task;
        if (t == task) {
            s.waiter.active = false;
            s.waiter.task = null;
            self.sleeps.remove_at(i);
            continue;
        }
        
        i++;
    }

}

fn ulong EventLoop.next_sleep_delay_us(&self) // private
{
    if (self.sleeps.len() == 0) return 0;

    ulong now = clock_now();
    if (self.sleeps.get(0).deadline_us <= now) return 0;

    ulong delay = self.sleeps.get(0).deadline_us - now;

    return delay;
}

fn void EventLoop.remove_sleep(&self, Sleep* sleep) // private
{
    if (sleep == null) return;

    self.sleeps.remove_first_match(sleep);
}

fn void? sleep(ulong us) @maydiscard
{
    Task* task = current_task()!;

    EventLoop* loop = task.loop;
    if (loop == null) return INVALID_STATE~;

    Sleep sleep;
    sleep.init(task, clock_now() + us);

    loop.add_sleep(&sleep);

    task.suspend(&sleep.waiter);
    
    loop.remove_sleep(&sleep);

    sleep.waiter.check()!;
}

// eof