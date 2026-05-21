// test_primitives.c3

import ext::aio;
import ext::debug;

Future* g_future = null;
Event* g_event = null;
Lock* g_lock = null;
Semaphore* g_sem = null;
Queue* g_queue = null;
Channel* g_channel = null;

int g_lock_counter = 0;
int g_sem_inside = 0;
int g_sem_max_inside = 0;

// 
// Future
// 

fn void? future_waiter(void* arg)
{
    warn("[future] waiter start");

    void* value = g_future.await()!;

    warn("[future] waiter got %d", (int)(isz)value);

    @assert((int)(isz)value == 123, "future waiter got wrong value");
}

fn void? future_setter(void* arg)
{
    aio::sleep(100)!;

    warn("[future] setter set_result");

    g_future.set_result((void*)123)!;
}

fn void? future_cancel_waiter(void* arg)
{
    warn("[future-cancel] waiter start");

    if (catch err = g_future.await())
    {
        warn("[future-cancel] waiter got err=%s", err);

        @assert(err == aio::CANCELLED, "future cancel waiter got unexpected error");
        return;
    }

    @assert(false, "future cancel waiter returned without cancellation");
}

fn void? future_canceller(void* arg)
{
    aio::sleep(100)!;

    warn("[future-cancel] cancel");

    g_future.cancel();
}

// 
// Event
// 

fn void? event_waiter(void* arg)
{
    int id = (int)(isz)arg;

    warn("[event] waiter %d waiting", id);

    g_event.wait()!;

    warn("[event] waiter %d woke", id);
}

fn void? event_setter(void* arg)
{
    aio::sleep(100)!;

    warn("[event] set");

    g_event.set()!;
}

fn void? event_clear_waiter(void* arg)
{
    warn("[event-clear] waiter waiting");

    g_event.wait()!;

    warn("[event-clear] waiter woke");
}

// 
// Lock
// 

fn void? lock_worker(void* arg)
{
    int id = (int)(isz)arg;

    warn("[lock] worker %d waiting", id);

    g_lock.acquire()!;

    warn("[lock] worker %d acquired", id);

    int old = g_lock_counter;

    aio::sleep(50)!;

    g_lock_counter = old + 1;

    warn("[lock] worker %d releasing counter=%d", id, g_lock_counter);

    g_lock.release()!;
}

fn void? lock_release_error_task(void* arg)
{
    Lock* lock = aio::lock_new()!;
    defer lock.free();

    if (catch err = lock.release())
    {
        warn("[lock-error] release unlocked err=%s", err);

        @assert(err == aio::LOCK_ERROR, "lock.release() returned unexpected error");
        return;
    }

    @assert(false, "lock.release() on unlocked lock did not fail");
}

// 
// Semaphore
// 

fn void? sem_worker(void* arg)
{
    int id = (int)(isz)arg;

    warn("[sem] worker %d waiting", id);

    g_sem.acquire()!;

    g_sem_inside += 1;

    if (g_sem_inside > g_sem_max_inside) g_sem_max_inside = g_sem_inside;

    warn("[sem] worker %d entered inside=%d", id, g_sem_inside);

    aio::sleep(100)!;

    g_sem_inside -= 1;

    warn("[sem] worker %d leaving inside=%d", id, g_sem_inside);

    g_sem.release();
}

// 
// Queue
// 

fn void? queue_producer(void* arg)
{
    for (int i = 1; i <= 5; i++)
    {
        aio::sleep(30)!;

        warn("[queue] put %d", i);

        g_queue.put((void*)(isz)i)!;
    }

    warn("[queue] producer done");
}

fn void? queue_consumer(void* arg)
{
    int sum = 0;

    for (int i = 1; i <= 5; i++)
    {
        void* item = g_queue.get()!;

        int value = (int)(isz)item;

        warn("[queue] got %d", value);

        sum += value;
    }

    warn("[queue] consumer sum=%d", sum);

    @assert(sum == 15, "queue consumer sum mismatch");
}

fn void? queue_close_waiter(void* arg)
{
    warn("[queue-close] waiting get");

    if (catch err = g_queue.get())
    {
        warn("[queue-close] got err=%s", err);

        @assert(err == aio::QUEUE_CLOSED, "queue close waiter got unexpected error");
        return;
    }

    @assert(false, "queue close waiter returned item after queue close");
}

fn void? queue_closer(void* arg)
{
    aio::sleep(100)!;

    warn("[queue-close] close queue");

    g_queue.close();
}

fn void? queue_nowait_test_task(void* arg)
{
    Queue* q = aio::queue_new(1)!;
    defer q.free();

    if (catch err = q.get_nowait())
    {
        warn("[queue-nowait] empty err=%s", err);

        @assert(err == aio::QUEUE_EMPTY, "queue get_nowait empty error mismatch");
    }
    else
    {
        @assert(false, "queue get_nowait on empty queue did not fail");
    }

    q.put_nowait((void*)10)!;

    if (catch err = q.put_nowait((void*)20))
    {
        warn("[queue-nowait] full err=%s", err);

        @assert(err == aio::QUEUE_FULL, "queue put_nowait full error mismatch");
    }
    else
    {
        @assert(false, "queue put_nowait on full queue did not fail");
    }

    void* item = q.get_nowait()!;

    @assert((int)(isz)item == 10, "queue get_nowait returned wrong item");

    q.close();

    if (catch err = q.get_nowait())
    {
        warn("[queue-nowait] closed err=%s", err);

        @assert(err == aio::QUEUE_CLOSED, "queue get_nowait closed error mismatch");
    }
    else
    {
        @assert(false, "queue get_nowait on closed queue did not fail");
    }
}

// 
// Channel
// 

fn void? channel_receiver(void* arg)
{
    warn("[channel] receiver waiting");

    void* value = g_channel.recv()!;

    warn("[channel] receiver got %d", (int)(isz)value);

    @assert((int)(isz)value == 777, "channel receiver got wrong value");
}

fn void? channel_sender(void* arg)
{
    aio::sleep(100)!;

    warn("[channel] sender send");

    g_channel.send((void*)777)!;
}

fn void? channel_close_receiver(void* arg)
{
    warn("[channel-close] receiver waiting");

    if (catch err = g_channel.recv())
    {
        warn("[channel-close] receiver got err=%s", err);

        @assert(err == aio::CHANNEL_CLOSED, "channel close receiver got unexpected error");
        return;
    }

    @assert(false, "channel close receiver got value after close");
}

fn void? channel_closer(void* arg)
{
    aio::sleep(100)!;

    warn("[channel-close] close");

    g_channel.close();
}

fn void? channel_used_test_task(void* arg)
{
    Channel* ch = aio::channel_new()!;
    defer ch.free();

    ch.send((void*)1)!;

    if (catch err = ch.send((void*)2))
    {
        warn("[channel-used] err=%s", err);

        @assert(err == aio::CHANNEL_USED, "channel second send returned unexpected error");
    }
    else
    {
        @assert(false, "channel second send did not fail with CHANNEL_USED");
    }

    void* value = ch.recv_nowait()!;

    @assert((int)(isz)value == 1, "channel recv_nowait returned wrong value");
}

// 
// Test runners
// 

fn void? run_future_test(void* arg)
{
    warn("=== future test ===");

    g_future = aio::future_new()!;

    Task* waiter = aio::spawn_joinable(&future_waiter)!;
    Task* setter = aio::spawn_joinable(&future_setter)!;

    waiter.join()!;
    setter.join()!;

    @assert(g_future.done(), "future was not done");
    @assert(!g_future.cancelled(), "future was unexpectedly cancelled");

    g_future.free();
    g_future = null;

    warn("=== future test ok ===");
}

fn void? run_future_cancel_test(void* arg)
{
    warn("=== future cancel test ===");

    g_future = aio::future_new()!;

    Task* waiter = aio::spawn_joinable(&future_cancel_waiter)!;
    Task* canceller = aio::spawn_joinable(&future_canceller)!;

    waiter.join()!;
    canceller.join()!;

    @assert(g_future.done(), "cancelled future was not done");
    @assert(g_future.cancelled(), "future was not cancelled");

    g_future.free();
    g_future = null;

    warn("=== future cancel test ok ===");
}

fn void? run_event_test(void* arg)
{
    warn("=== event test ===");

    g_event = aio::event_new(false)!;

    Task* w1 = aio::spawn_joinable(&event_waiter, (void*)1)!;
    Task* w2 = aio::spawn_joinable(&event_waiter, (void*)2)!;
    Task* setter = aio::spawn_joinable(&event_setter)!;

    w1.join()!;
    w2.join()!;
    setter.join()!;

    @assert(g_event.is_set(), "event was not set");

    g_event.clear()!;

    @assert(!g_event.is_set(), "event clear failed");

    Task* w3 = aio::spawn_joinable(&event_clear_waiter)!;

    aio::sleep(100)!;

    @assert(!g_event.is_set(), "event was unexpectedly set before set()");

    g_event.set()!;

    w3.join()!;

    g_event.free();
    g_event = null;

    warn("=== event test ok ===");
}

fn void? run_lock_test(void* arg)
{
    warn("=== lock test ===");

    g_lock = aio::lock_new()!;

    g_lock_counter = 0;

    Task* t1 = aio::spawn_joinable(&lock_worker, (void*)1)!;
    Task* t2 = aio::spawn_joinable(&lock_worker, (void*)2)!;
    Task* t3 = aio::spawn_joinable(&lock_worker, (void*)3)!;
    Task* t4 = aio::spawn_joinable(&lock_release_error_task)!;

    t1.join()!;
    t2.join()!;
    t3.join()!;
    t4.join()!;

    @assert(g_lock_counter == 3, "lock counter mismatch");
    @assert(!g_lock.is_locked(), "lock still locked after workers");

    g_lock.free();
    g_lock = null;

    warn("=== lock test ok ===");
}

fn void? run_semaphore_test(void* arg)
{
    warn("=== semaphore test ===");

    g_sem = aio::semaphore_new(2)!;

    g_sem_inside = 0;
    g_sem_max_inside = 0;

    Task* t1 = aio::spawn_joinable(&sem_worker, (void*)1)!;
    Task* t2 = aio::spawn_joinable(&sem_worker, (void*)2)!;
    Task* t3 = aio::spawn_joinable(&sem_worker, (void*)3)!;
    Task* t4 = aio::spawn_joinable(&sem_worker, (void*)4)!;

    t1.join()!;
    t2.join()!;
    t3.join()!;
    t4.join()!;

    warn("[sem] max_inside=%d", g_sem_max_inside);

    @assert(g_sem_max_inside <= 2, "semaphore allowed too many workers inside");
    @assert(g_sem.count() == 2, "semaphore count was not restored");

    g_sem.free();
    g_sem = null;

    warn("=== semaphore test ok ===");
}

fn void? run_queue_test(void* arg)
{
    warn("=== queue test ===");

    g_queue = aio::queue_new(2)!;

    Task* producer = aio::spawn_joinable(&queue_producer)!;
    Task* consumer = aio::spawn_joinable(&queue_consumer)!;

    producer.join()!;
    consumer.join()!;

    @assert(g_queue.empty(), "queue was not empty after producer/consumer");

    g_queue.free();
    g_queue = null;

    warn("=== queue test ok ===");
}

fn void? run_queue_close_test(void* arg)
{
    warn("=== queue close test ===");

    g_queue = aio::queue_new(2)!;
    
    Task* waiter = aio::spawn_joinable(&queue_close_waiter)!;
    Task* closer = aio::spawn_joinable(&queue_closer)!;

    waiter.join()!;
    closer.join()!;

    g_queue.free();
    g_queue = null;

    warn("=== queue close test ok ===");
}

fn void? run_queue_nowait_test(void* arg)
{
    warn("=== queue nowait test ===");

    queue_nowait_test_task(null)!;

    warn("=== queue nowait test ok ===");
}

fn void? run_channel_test(void* arg)
{
    warn("=== channel test ===");

    g_channel = aio::channel_new()!;

    Task* receiver = aio::spawn_joinable(&channel_receiver)!;
    Task* sender = aio::spawn_joinable(&channel_sender)!;

    receiver.join()!;
    sender.join()!;

    @assert(g_channel.ready(), "channel was not ready after transfer");

    g_channel.free();
    g_channel = null;

    warn("=== channel test ok ===");
}

fn void? run_channel_close_test(void* arg)
{
    warn("=== channel close test ===");

    g_channel = aio::channel_new()!;
    
    Task* receiver = aio::spawn_joinable(&channel_close_receiver)!;
    Task* closer = aio::spawn_joinable(&channel_closer)!;

    receiver.join()!;
    closer.join()!;

    @assert(!g_channel.ready(), "closed channel unexpectedly ready");
    @assert(g_channel.is_closed(), "channel was not closed");

    g_channel.free();
    g_channel = null;

    warn("=== channel close test ok ===");
}

fn void? run_channel_used_test(void* arg)
{
    warn("=== channel used test ===");

    channel_used_test_task(null)!;

    warn("=== channel used test ok ===");
}

fn void? main_task(void* arg)
{
    run_future_test(null)!;
    run_future_cancel_test(null)!;
    run_event_test(null)!;
    run_lock_test(null)!;
    run_semaphore_test(null)!;
    run_queue_test(null)!;
    run_queue_close_test(null)!;
    run_queue_nowait_test(null)!;
    run_channel_test(null)!;
    run_channel_close_test(null)!;
    run_channel_used_test(null)!;

    warn("=== all primitive tests passed ===");
}

fn void main()
{
    aio::run(&main_task)!!;

    warn("OK");
}

// eof