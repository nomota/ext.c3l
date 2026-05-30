// sample6.c3
// Validates:
//   - Lock:  only one task may enter the critical section at a time
//   - Queue: producer/consumer ordering is correct and the queue blocks when full

module sample6;

import ext::asyncio;
import std::io;
import c::stdlib;
import ext::debug;
import ext::mem;

// Shared counter — without a Lock, concurrent access would corrupt the value
int g_counter = 0;
Lock* g_lock;

// Shared queue (small capacity=3 to trigger full-blocking)
Queue* g_queue;

// Ordered log of events (up to 32 entries)
String[32] g_log;
int g_log_count = 0;

fn void log(String msg)
{
    g_log[g_log_count++] = msg;
    io::printfn("[LOG] %s", msg);
}

// -------------------------------------------------------
//  Lock validation
//  3 tasks each increment the counter 10 times.
//  With correct locking the final value must be exactly 30.
// -------------------------------------------------------

fn void worker_lock()
{
    for (int i = 0; i < 10; i++) {
        g_lock.acquire();
        // Critical section: read → yield (give other tasks a chance to preempt) → write
        int tmp = g_counter;
        asyncio::sleep_zero(); // intentionally give preemption
        g_counter = tmp + 1;
        g_lock.release();
    }
}

// -------------------------------------------------------
//  Queue validation — 2 producers / 1 consumer
//  queue capacity=3, each producer sends 6 items → 12 total.
//  When the consumer has drained all items they must cover 0–11
//  with no duplicates or gaps.
// -------------------------------------------------------

int g_produced = 0;
int g_consumed = 0;
int[12] g_consume_order;

fn void producer()
{
    for (int i = 0; i < 6; i++) {
        // Cast int to void* without heap allocation (value-as-pointer trick)
        int val = g_produced++;
        g_queue.put((void*)(iptr)val);
    }
    log("producer done");
}

fn void consumer()
{
    for (int i = 0; i < 12; i++) {
        void* item = g_queue.get();
        g_consume_order[g_consumed] = (int)(iptr)item;
        g_consumed++;
    }
    log("consumer done");
}

fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // --- Lock test ---
    log("=== Lock test start ===");
    g_lock = asyncio::lock_new();
    g_counter = 0;

    Task* t1 = loop.create_task(&worker_lock, "worker1");
    Task* t2 = loop.create_task(&worker_lock, "worker2");
    Task* t3 = loop.create_task(&worker_lock, "worker3");

    Task*[3] lock_tasks = { t1, t2, t3 };
    asyncio::gather(&lock_tasks);

    if (g_counter == 30) {
        log("Lock test PASSED: counter == 30");
    } else {
        io::printfn("Lock test FAILED: counter == %d (expected 30)", g_counter);
    }
    g_lock.free();

    // --- Queue test ---
    log("=== Queue test start ===");
    g_queue = asyncio::queue_new(3);   // capacity=3 → producer blocks after 3 items
    g_produced = 0;
    g_consumed = 0;

    Task* p1 = loop.create_task(&producer, "producer1");
    Task* p2 = loop.create_task(&producer, "producer2");
    Task* c1 = loop.create_task(&consumer, "consumer1");

    Task*[3] q_tasks = { p1, p2, c1 };
    asyncio::gather(&q_tasks);

    // Verify that all 12 items are in range 0–11 with no duplicates
    bool[12] seen;
    bool ok = true;
    for (int i = 0; i < 12; i++) {
        int v = g_consume_order[i];
        // warn("v:%d", v);
        if (v < 0 || v >= 12 || seen[v]) { ok = false; break; }
        seen[v] = true;
    }
    if (ok) {
        log("Queue test PASSED: all 12 items received, no duplicates");
    } else {
        log("Queue test FAILED: unexpected item order or duplicate");
    }
    g_queue.free();
}

fn int main()
{
  @assert_leak() {
    asyncio::run(&main_coro);
  };
    return 0;
}
