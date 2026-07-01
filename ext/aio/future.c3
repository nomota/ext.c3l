// future.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import std::collections::linkedlist;
import ext::mem;

faultdef FUTURE_DONE;

struct Future
{
    EventLoop* loop;

    bool is_done;
    bool is_cancelled;

    void* result;
    fault error;

    LinkedList{Waiter*} waiters;
}

fn Future*? future_new()
{
    EventLoop* loop = current_loop()!;
    if (loop == null) return null;

    Future* future = localmem.alloc(Future)!;
    *future = {
        .loop = loop,
        .is_done = false,
        .is_cancelled = false,
        .result = null,
        .error = NONE,
    };

    future.waiters.init(localmem);

    return future;
}

fn void Future.free(&self)
{
    if (!self.is_done) {
        self.cancel(CANCELLED);
    }

    self.waiters.free();
    localmem.free(self);
}

fn bool Future.done(&self) @inline
{
    return self.is_done;
}

fn bool Future.cancelled(&self) @inline
{
    return self.is_cancelled;
}

fn void Future.wake_all(&self) 
{
    while (!self.waiters.is_empty()) {
        Waiter* waiter = self.waiters.pop_first()!!;

        if (waiter != null) waiter.wake();
    }
}

fn void? Future.set_result(&self, void* result) @maydiscard
{
    if (self.is_done) return FUTURE_DONE~;

    self.result = result;
    self.error = NONE;
    self.is_cancelled = false;
    self.is_done = true;

    self.wake_all();
}

fn void*? Future.get_result(&self)
{
    if (!self.is_done) return INVALID_STATE~;

    if (self.is_cancelled) {
        if (self.error != NONE) return self.error~;
        return CANCELLED~;
    }

    if (self.error != NONE) return self.error~;

    return self.result;
}

fn void? Future.set_error(&self, fault err) @maydiscard
{
    if (self.is_done) return FUTURE_DONE~;
    if (err == NONE) return INVALID_STATE~;

    self.result = null;
    self.error = err;
    self.is_cancelled = false;
    self.is_done = true;

    self.wake_all();
}

fn void Future.cancel(&self, fault err = NONE)
{
    if (self.is_done) return;

    fault cancel_err = (err != NONE) ? err : CANCELLED;

    self.result = null;
    self.error = cancel_err;
    self.is_cancelled = true;
    self.is_done = true;

    while (!self.waiters.is_empty()) {
        Waiter* waiter = self.waiters.pop_first()!!;

        if (waiter != null) waiter.cancel(cancel_err);
    }
}

fn void*? Future.await_internal(&self, ulong timeout_us, bool use_timeout) // private
{
    if (self.is_done) {
        return self.get_result()!;
    }

    Task* task = self.loop.current;
    if (task == null) return INVALID_STATE~;

    Waiter waiter;
    waiter.init(task);

    self.waiters.push(&waiter);

    Timer* timer = null;

    if (use_timeout) {
        if (timeout_us == 0) {
            self.waiters.remove_first_match(&waiter);
            return TIMEOUT~;
        }

        Timer*? timer_opt = task.start_timer(timeout_us);

        if (catch err = timer_opt) {
            self.waiters.remove_first_match(&waiter);
            return err~;
        }

        timer = timer_opt;
    }

    task.suspend(&waiter);

    if (timer != null) {
        timer.cancel();
    }

    self.waiters.remove_first_match(&waiter);

    waiter.check()!;

    return self.get_result()!;
}

fn void*? Future.await(&self)
{
    return self.await_internal(0, false)!;
}

fn void*? Future.await_timeout(&self, ulong timeout_us)
{
    return self.await_internal(timeout_us, true)!;
}

// eof