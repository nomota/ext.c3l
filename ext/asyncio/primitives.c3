//  primitives.c3 

module ext::asyncio;

import std::io;
import c::stdlib;
import ext::debug;
import ext::mem;
import ext::thread::fiber;

const usz LOCK_WAITER_MAX = 64;

struct Lock {
    bool locked;
    Task*[LOCK_WAITER_MAX] waiters;
    usz waiter_count;
}

fn Lock* lock_new() @inline 
{
    Lock* lock = localmem.alloc(Lock);
    return lock;
}

fn void Lock.free(&self)
{
    localmem.free(self);
}

fn bool Lock.is_locked(&self) @inline
{
    return self.locked;
}

fn void Lock.acquire(&self) 
{
    EventLoop* loop = get_running_loop();
    while (self.locked) {
        Task* me = loop.current;
        @assert(me != null, "asyncio: Lock.acquire() called outside a task");
        
        @assert(self.waiter_count < LOCK_WAITER_MAX, "asyncio: Lock waiter overflow");
        self.waiters[self.waiter_count++] = me;
        me.state = State.SUSPENDED;
        fiber::yield();
    }
    self.locked = true;
}

fn void Lock.release(&self) 
{
    @assert(self.locked, "asyncio: Lock.release() called on unlocked lock");
    EventLoop* loop = get_running_loop();
    self.locked = false;
    if (self.waiter_count > 0) {
        Task* next = self.waiters[0];

        for (usz i = 1; i < self.waiter_count; i++) {
            self.waiters[i-1] = self.waiters[i];
        }
        self.waiter_count--;
        next.state = State.PENDING;
        loop._enqueue(next);
    }
}

const usz SEM_WAITER_MAX = 64;

struct Semaphore {
    int value; // number of available slots
    Task*[SEM_WAITER_MAX] waiters;
    usz waiter_count;
}

fn Semaphore* semaphore_new(int initial_value) 
{
    Semaphore* sem = localmem.alloc(Semaphore);
    sem.value = initial_value;
    return sem;
}

fn void Semaphore.free(&self)
{
    localmem.free(self);
}

fn int Semaphore.count(&self) @inline 
{
    return self.value;
}

fn void Semaphore.acquire(&self) 
{
    EventLoop* loop = get_running_loop();
    while (self.value <= 0) {
        Task* me = loop.current;
        @assert(me != null, "asyncio: Semaphore.acquire() called outside a task");
        @assert(self.waiter_count < SEM_WAITER_MAX, "asyncio: Semaphore waiter overflow");
        self.waiters[self.waiter_count++] = me;
        me.state = State.SUSPENDED;
        fiber::yield();
    }
    self.value--;
}

fn void Semaphore.release(&self) 
{
    EventLoop* loop = get_running_loop();
    self.value++;
    if (self.waiter_count > 0) {
        Task* next = self.waiters[0];
        for (usz i = 1; i < self.waiter_count; i++) self.waiters[i-1] = self.waiters[i];
        self.waiter_count--;
        next.state = State.PENDING;
        loop._enqueue(next);
    }
}

struct Event {
    Future* future;
}

fn Event* event_new() 
{
    EventLoop* loop = get_running_loop();
    Event* event = localmem.alloc(Event);
    event.future = loop.create_future();
    return event;
}

fn void Event.free(&self) 
{
    self.future.free();
    localmem.free(self);
}

fn bool Event.is_set(&self) @inline 
{ 
    return self.future.done(); 
}

// set event waiting, wake all
fn void Event.set(&self) 
{
    self.future.set_result(null);
}

fn void Event.clear(&self) 
{
    EventLoop* loop = self.future.loop;
    self.future.free();
    self.future = loop.create_future();
}

// wait until event set
fn void? Event.wait(&self) @maydiscard
{
    self.future.await()!;
}

const usz QUEUE_CAP_DEFAULT = 64;

struct Queue {
    void*[] buf; // heap alloc ring buffer
    usz capacity;
    usz head;
    usz tail;
    usz count;

    // empty q, get() waiting tasks
    Task*[LOCK_WAITER_MAX] get_waiters;
    usz get_waiter_count;

    // full q, put() waiting tasks
    Task*[LOCK_WAITER_MAX] put_waiters;
    usz put_waiter_count;
}

fn Queue* queue_new(usz capacity = QUEUE_CAP_DEFAULT) 
{
    Queue* q = localmem.alloc(Queue);
    *q = {};
    q.capacity = capacity;
    q.buf = localmem.alloc_array(void*, capacity);
    return q;
}

fn void Queue.free(&self) 
{
    localmem.free(self.buf);
    localmem.free(self);
}

fn usz Queue.size(&self) @inline
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

fn usz Queue.maxsize(&self) @inline
{
    return self.capacity;
}

fn void Queue.put(&self, void* item) 
{
    EventLoop* loop = get_running_loop();
    while (self.full()) {
        Task* me = loop.current;
        @assert(me != null, "asyncio: Queue.put() called outside a task");
        @assert(self.put_waiter_count < LOCK_WAITER_MAX, "asyncio: Queue put_waiter overflow");
        usz idx = self.put_waiter_count;
        self.put_waiters[idx] = me;
        self.put_waiter_count++;
        me.state = State.SUSPENDED;
        fiber::yield();
        
        if (!self.full()) break;
    }
// warn("%d %d", self.capacity, self.tail);
    self.buf[self.tail] = item;
    self.tail = (self.tail + 1) % self.capacity;
    self.count++;
    
    // wake get() waiters
    if (self.get_waiter_count > 0) {
        Task* next = self.get_waiters[0];
        for (usz i = 1; i < self.get_waiter_count; i++) self.get_waiters[i-1] = self.get_waiters[i];
        self.get_waiter_count--;
        next.state = State.PENDING;
        loop._enqueue(next);
    }
}

fn void* Queue.get(&self) 
{
    EventLoop* loop = get_running_loop();
    while (self.empty()) {
        Task* me = loop.current;
        @assert(me != null, "asyncio: Queue.get() called outside a task");
        @assert(self.get_waiter_count < LOCK_WAITER_MAX, "asyncio: Queue get_waiter overflow");
        self.get_waiters[self.get_waiter_count++] = me;
        me.state = State.SUSPENDED;
        fiber::yield();
    }

    void* item = self.buf[self.head];
    self.head  = (self.head + 1) % self.capacity;
    self.count--;

    // wake put() waiters
    if (self.put_waiter_count > 0) {
        Task* next  = self.put_waiters[0];

        for (usz i = 1; i < self.put_waiter_count; i++) {
            self.put_waiters[i-1] = self.put_waiters[i];
        }
        self.put_waiter_count--;
    
        next.state = State.PENDING;
        loop._enqueue(next);
    }

    return item;
}

// dequeue without blocking
fn void*? Queue.get_nowait(&self) 
{
    if (self.empty()) {
        return QUEUE_EMPTY~;
    }
    return self.get();
}

// enqueue without blocking
fn void? Queue.put_nowait(&self, void* item) @maydiscard
{
    if (self.full()) return QUEUE_FULL~;
    self.put(item);
}

//  Channel — Future based one direction, single item
struct Channel {
    Future* future;
}

fn Channel* channel_new() 
{
    EventLoop* loop = get_running_loop();
    Channel* chan = localmem.alloc(Channel);
    chan.future = loop.create_future();
    return chan;
}

fn void Channel.free(&self) 
{
    self.future.free();
    localmem.free(self);
}

// send and wake up the receiver
fn void Channel.send(&self, void* value) 
{
    self.future.set_result(value);
}

// wait and receive
fn void*? Channel.recv(&self)
{
    return self.future.await()!;
}

fn bool Channel.ready(&self) @inline 
{
    return self.future.done();
}
