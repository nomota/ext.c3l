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

    Sleep* next;
}

fn ulong clock_now() @inline // micro second
{
    return (ulong) clock::now()/1_000; // nano to micro
}

fn void Sleep.init(&self, Task* task, ulong deadline_us)
{
    self.waiter.init(task);
    self.deadline_us = deadline_us;
    self.next = null;
}

fn void EventLoop.add_sleep(&self, Sleep* sleep) // private
{
    if (sleep == null) return;

    sleep.next = null;

    if (self.sleep_head == null) {
        self.sleep_head = sleep;
        return;
    }

    if (sleep.deadline_us < self.sleep_head.deadline_us) {
        sleep.next = self.sleep_head;
        self.sleep_head = sleep;
        return;
    }

    Sleep* prev = self.sleep_head;
    Sleep* cur = self.sleep_head.next;

    while (cur != null && cur.deadline_us <= sleep.deadline_us) {
        prev = cur;
        cur = cur.next;
    }

    sleep.next = cur;
    prev.next = sleep;
}

fn void EventLoop.process_sleeps(&self) // private
{
    ulong now = clock_now();

    while (self.sleep_head != null) {
        Sleep* sleep = self.sleep_head;

        if (sleep.deadline_us > now) break;

        self.sleep_head = sleep.next;
        sleep.next = null;
        sleep.waiter.wake();
    }
}

fn ulong EventLoop.next_sleep_delay_us(&self) // private
{
    if (self.sleep_head == null) return 0;

    ulong now = clock_now();
    if (self.sleep_head.deadline_us <= now) return 0;

    ulong delay = self.sleep_head.deadline_us - now;

    return delay;
}

fn void EventLoop.remove_sleep(&self, Sleep* sleep) // private
{
    if (sleep == null) return;

    Sleep* prev = null;
    Sleep* cur = self.sleep_head;

    while (cur != null)
    {
        if (cur == sleep)
        {
            if (prev == null)
            {
                self.sleep_head = cur.next;
            }
            else
            {
                prev.next = cur.next;
            }

            cur.next = null;
            return;
        }

        prev = cur;
        cur = cur.next;
    }
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