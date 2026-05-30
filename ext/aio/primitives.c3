// primitives.c3

// Synchronization primitives on ext::aio

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import std::collections::linkedlist;
import ext::mem;

faultdef LOCK_ERROR;
faultdef QUEUE_EMPTY, QUEUE_FULL, QUEUE_CLOSED;
faultdef CHANNEL_CLOSED, CHANNEL_USED;

// 
// Waiter list helpers
// 

fn void wake_one(LinkedList{Waiter*}* waiters) @local
{
    if (waiters == null) return;
    if (waiters.is_empty()) return;

    Waiter* waiter = waiters.pop_first()!!;

    if (waiter != null) waiter.wake();
}

fn void wake_all(LinkedList{Waiter*}* waiters) @local
{
    if (waiters == null) return;

    while (!waiters.is_empty())
    {
        Waiter* waiter = waiters.pop_first()!!;

        if (waiter != null) waiter.wake();
    }
}

fn void cancel_all_waiters(LinkedList{Waiter*}* waiters, fault err = CANCELLED) @local
{
    if (waiters == null) return;

    while (!waiters.is_empty())
    {
        Waiter* waiter = waiters.pop_first()!!;

        if (waiter != null)
        {
            waiter.cancel(err);
        }
    }
}

// 
// Lock
// 

struct Lock
{
    bool locked;
    LinkedList{Waiter*} waiters;
}

fn Lock*? lock_new()
{
    Lock* lock = localmem.alloc(Lock)!;
    *lock = {
        .locked = false,
    };

    lock.waiters.init(localmem);

    return lock;
}

fn void Lock.init(&self)
{
    *self = {
        .locked = false,
    };

    self.waiters.init(localmem);
}

fn void Lock.deinit(&self)
{
    cancel_all_waiters(&self.waiters, CANCELLED);
    self.waiters.free();
    self.locked = false;
}

fn void Lock.free(&self)
{
    self.deinit();
    localmem.free(self);
}

fn bool Lock.is_locked(&self) @inline
{
    return self.locked;
}

fn void? Lock.acquire(&self) @maydiscard
{
    Task* task = current_task()!;

    while (self.locked)
    {
        Waiter waiter;
        waiter.init(task);

        self.waiters.push(&waiter);

        task.suspend(&waiter);

        self.waiters.remove_first_match(&waiter);

        waiter.check()!;
    }

    self.locked = true;
}

fn void? Lock.release(&self) @maydiscard
{
    if (!self.locked) return LOCK_ERROR~;

    self.locked = false;

    wake_one(&self.waiters);
}

// 
// Semaphore
// 

struct Semaphore
{
    int value;
    LinkedList{Waiter*} waiters;
}

fn Semaphore*? semaphore_new(int initial_value = 1)
{
    if (initial_value < 0) return INVALID_STATE~;

    Semaphore* sem = localmem.alloc(Semaphore)!;
    *sem = {
        .value = initial_value,
    };

    sem.waiters.init(localmem);

    return sem;
}

fn void Semaphore.init(&self, int initial_value = 1)
{
    if (initial_value < 0) initial_value = 0;

    *self = {
        .value = initial_value,
    };

    self.waiters.init(localmem);
}

fn void Semaphore.deinit(&self)
{
    cancel_all_waiters(&self.waiters, CANCELLED);
    self.waiters.free();
    self.value = 0;
}

fn void Semaphore.free(&self)
{
    self.deinit();
    localmem.free(self);
}

fn int Semaphore.count(&self) @inline
{
    return self.value;
}

fn void? Semaphore.acquire(&self) @maydiscard
{
    Task* task = current_task()!;

    while (self.value <= 0)
    {
        Waiter waiter;
        waiter.init(task);

        self.waiters.push(&waiter);

        task.suspend(&waiter);

        self.waiters.remove_first_match(&waiter);

        waiter.check()!;
    }

    self.value -= 1;
}

fn void Semaphore.release(&self)
{
    self.value += 1;

    wake_one(&self.waiters);
}

// 
// Event
//
// Future-based, like asyncio.Event.
// set() completes the current future.
// clear() replaces it with a fresh pending future.
// 

struct Event
{
    Future* future;
}

fn Event*? event_new(bool initial = false)
{
    Event* event = localmem.alloc(Event)!;
    defer (catch err) { localmem.free(event); }

    event.future = future_new()!;

    if (initial)
    {
        event.future.set_result(null)!!;
    }

    return event;
}

fn void? Event.init(&self, bool initial = false)
{
    *self = {
        .future = future_new()!,
    };

    if (initial)
    {
        self.future.set_result(null)!;
    }
}

fn void Event.deinit(&self)
{
    if (self.future != null)
    {
        self.future.cancel(CANCELLED);
        self.future.free();
        self.future = null;
    }
}

fn void Event.free(&self)
{
    self.deinit();
    localmem.free(self);
}

fn bool Event.is_set(&self) @inline
{
    return self.future != null && self.future.done();
}

fn void? Event.set(&self) @maydiscard
{
    if (!self.future.done())
    {
        self.future.set_result(null)!;
    }
}

fn void? Event.clear(&self) @maydiscard
{
    if (!self.future.done()) return;

    self.future.free();

    self.future = future_new()!;
}

fn void? Event.wait(&self) @maydiscard
{
    self.future.await()!;
}

// 
// Queue
//
// Waiter-based.
// Future is not ideal for repeated put/get operations because each
// operation needs its own cancellation-safe wait token.
// 

const sz QUEUE_CAP_DEFAULT = 64;

struct Queue
{
    void*[] buf;
    sz capacity;
    sz head;
    sz tail;
    sz count;

    bool closed;

    LinkedList{Waiter*} get_waiters;
    LinkedList{Waiter*} put_waiters;
}

fn Queue*? queue_new(sz capacity = QUEUE_CAP_DEFAULT)
{
    if (capacity == 0) capacity = QUEUE_CAP_DEFAULT;

    Queue* q = localmem.alloc(Queue)!;
    *q = {
        .capacity = capacity,
        .head = 0,
        .tail = 0,
        .count = 0,
        .closed = false,
    };

    q.buf = localmem.alloc_array(void*, capacity)!;
    q.get_waiters.init(localmem);
    q.put_waiters.init(localmem);

    return q;
}

fn void? Queue.init(&self, sz capacity = QUEUE_CAP_DEFAULT) @maydiscard
{
    if (capacity == 0) capacity = QUEUE_CAP_DEFAULT;

    *self = {
        .capacity = capacity,
        .head = 0,
        .tail = 0,
        .count = 0,
        .closed = false,
    };

    self.buf = localmem.alloc_array(void*, capacity)!;
    self.get_waiters.init(localmem);
    self.put_waiters.init(localmem);
}

fn void Queue.deinit(&self)
{
    self.close();

    if (self.buf.len > 0)
    {
        localmem.free(self.buf);
        self.buf = {};
    }

    self.get_waiters.free();
    self.put_waiters.free();

    self.capacity = 0;
    self.head = 0;
    self.tail = 0;
    self.count = 0;
    self.closed = true;
}

fn void Queue.free(&self)
{
    self.deinit();
    localmem.free(self);
}

fn sz Queue.size(&self) @inline
{
    return self.count;
}

fn bool Queue.empty(&self) @inline
{
    return self.count == 0;
}

fn bool Queue.full(&self) @inline
{
    return self.count == self.capacity;
}

fn sz Queue.maxsize(&self) @inline
{
    return self.capacity;
}

fn bool Queue.is_closed(&self) @inline
{
    return self.closed;
}

fn void Queue.close(&self)
{
    if (self.closed) return;

    self.closed = true;

    cancel_all_waiters(&self.get_waiters, QUEUE_CLOSED);
    cancel_all_waiters(&self.put_waiters, QUEUE_CLOSED);
}

fn void? Queue.put(&self, void* item) @maydiscard
{
    if (self.closed) return QUEUE_CLOSED~;

    Task* task = current_task()!;

    while (self.full())
    {
        if (self.closed) return QUEUE_CLOSED~;

        Waiter waiter;
        waiter.init(task);

        self.put_waiters.push(&waiter);

        task.suspend(&waiter);

        self.put_waiters.remove_first_match(&waiter);

        waiter.check()!;
    }

    self.buf[self.tail] = item;
    self.tail = (self.tail + 1) % self.capacity;
    self.count += 1;

    wake_one(&self.get_waiters);
}

fn void*? Queue.get(&self)
{
    Task* task = current_task()!;

    while (self.empty())
    {
        if (self.closed) return QUEUE_CLOSED~;

        Waiter waiter;
        waiter.init(task);

        self.get_waiters.push(&waiter);

        task.suspend(&waiter);

        self.get_waiters.remove_first_match(&waiter);

        waiter.check()!;
    }

    void* item = self.buf[self.head];

    self.buf[self.head] = null;
    self.head = (self.head + 1) % self.capacity;
    self.count -= 1;

    wake_one(&self.put_waiters);

    return item;
}

fn void? Queue.put_nowait(&self, void* item) @maydiscard
{
    if (self.closed) return QUEUE_CLOSED~;
    if (self.full()) return QUEUE_FULL~;

    self.buf[self.tail] = item;
    self.tail = (self.tail + 1) % self.capacity;
    self.count += 1;

    wake_one(&self.get_waiters);
}

fn void*? Queue.get_nowait(&self)
{
    if (self.empty())
    {
        if (self.closed) return QUEUE_CLOSED~;
        return QUEUE_EMPTY~;
    }

    void* item = self.buf[self.head];

    self.buf[self.head] = null;
    self.head = (self.head + 1) % self.capacity;
    self.count -= 1;

    wake_one(&self.put_waiters);

    return item;
}

// 
// Channel
//
// Future-based one-shot channel.
// After one successful send(), recv() returns that value.
// It cannot be reused.
// 

struct Channel
{
    Future* future;
}

fn Channel*? channel_new()
{
    Channel* ch = localmem.alloc(Channel)!;
    defer (catch err) { localmem.free(ch); }
    
    ch.future = future_new()!;

    return ch;
}

fn void? Channel.init(&self)
{
    *self = {
        .future = future_new()!,
    };

    if (self.future == null) return INVALID_STATE~;
}

fn void Channel.deinit(&self)
{
    if (self.future != null)
    {
        self.future.cancel(CHANNEL_CLOSED);
        self.future.free();
        self.future = null;
    }
}

fn void Channel.free(&self)
{
    self.deinit();
    localmem.free(self);
}

fn bool Channel.ready(&self) @inline
{
    return self.future != null &&
        self.future.done() &&
        !self.future.cancelled();
}

fn bool Channel.is_closed(&self) @inline
{
    return self.future == null || self.future.cancelled();
}

fn void Channel.close(&self)
{
    if (self.future == null) return;

    self.future.cancel(CHANNEL_CLOSED);
}

fn void? Channel.send(&self, void* value) @maydiscard
{
    if (self.future == null) return CHANNEL_CLOSED~;
    if (self.future.done()) return CHANNEL_USED~;

    self.future.set_result(value)!;
}

fn void*? Channel.recv(&self)
{
    if (self.future == null) return CHANNEL_CLOSED~;

    return self.future.await();
}

fn void*? Channel.recv_nowait(&self)
{
    if (self.future == null) return CHANNEL_CLOSED~;

    if (!self.future.done()) return QUEUE_EMPTY~;

    return self.future.get_result();
}

// eof