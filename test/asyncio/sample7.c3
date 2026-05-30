// sample7.c3
// Validates:
//   - Semaphore: concurrent active tasks never exceed the limit
//   - Event:     a single set() wakes all waiting tasks simultaneously
//   - Channel:   a send/recv pair delivers the correct value

module sample7;

import ext::asyncio;
import std::io;
import c::stdlib;
import ext::debug;
import ext::mem;

// -------------------------------------------------------
//  Semaphore validation
//  5 tasks compete for a semaphore with limit=2.
//  The peak simultaneous count inside the critical section
//  must never exceed 2.
// -------------------------------------------------------

Semaphore* g_sem;
int g_active   = 0;   // tasks currently inside the critical section
int g_max_seen = 0;   // peak simultaneous active count
bool g_sem_ok  = true;

fn void sem_worker()
{
    g_sem.acquire();

    g_active++;
    if (g_active > g_max_seen) g_max_seen = g_active;
    if (g_active > 2) g_sem_ok = false;   // detect limit violation

    asyncio::sleep_us(100);   // short delay to increase overlap between tasks

    g_active--;
    g_sem.release();
}

// -------------------------------------------------------
//  Event validation
//  3 waiter tasks call Event.wait() before the starter fires.
//  A single Event.set() must wake all 3 simultaneously.
// -------------------------------------------------------

Event*  g_event;
int     g_woke_count = 0;   // number of tasks that returned from Event.wait()

fn void event_waiter()
{
    g_event.wait();
    g_woke_count++;
}

fn void event_starter()
{
    asyncio::sleep_us(500);       // give all waiters time to enter wait() first
    g_event.set();
    io::printfn("[Event] set() called");
}

// -------------------------------------------------------
//  Channel validation
//  3 channel pairs each carry a distinct value (42, 1337, 99).
//  The receiver must get the exact value sent on each channel.
// -------------------------------------------------------

const int CHAN_COUNT = 3;
Channel*[CHAN_COUNT]  g_channels;
int[CHAN_COUNT] g_sent = { 42, 1337, 99 };
int[CHAN_COUNT] g_received = { 0, 0, 0 };

fn void chan_sender_0()
{
    int* v = mem::new(int);
    *v = g_sent[0];
    g_channels[0].send(v);
}

fn void chan_sender_1()
{
    int* v = mem::new(int);
    *v = g_sent[1];
    g_channels[1].send(v);
}

fn void chan_sender_2()
{
    int* v = mem::new(int);
    *v = g_sent[2];
    g_channels[2].send(v);
}

fn void chan_receiver()
{
    for (int i = 0; i < CHAN_COUNT; i++) {
        int*? p = (int*)g_channels[i].recv();
        if (catch err = p) {
            warn("%s", err);
            continue;
        }
        g_received[i] = *p;
    }
}


fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // --- Semaphore test ---
    io::printfn("\n=== Semaphore test (limit=2, workers=5) ===");
    g_sem = asyncio::semaphore_new(2);
    g_active = 0;
    g_max_seen = 0;
    g_sem_ok   = true;

    Task*[5] sem_tasks;
    for (int i = 0; i < 5; i++) {
        sem_tasks[i] = loop.create_task(&sem_worker, "sem_worker");
    }
    asyncio::gather(&sem_tasks);

    io::printfn("max simultaneous active: %d", g_max_seen);
    if (g_sem_ok && g_max_seen <= 2) {
        io::printfn("Semaphore test PASSED");
    } else {
        io::printfn("Semaphore test FAILED (limit exceeded)");
    }
    g_sem.free();

    // --- Event test ---
    io::printfn("\n=== Event test (3 waiters) ===");
    g_event = asyncio::event_new();
    g_woke_count = 0;

    Task* w1 = loop.create_task(&event_waiter,  "waiter1");
    Task* w2 = loop.create_task(&event_waiter,  "waiter2");
    Task* w3 = loop.create_task(&event_waiter,  "waiter3");
    Task* st = loop.create_task(&event_starter, "starter");

    Task*[4] ev_tasks = { w1, w2, w3, st };
    
    asyncio::gather(&ev_tasks);

    io::printfn("woke_count: %d", g_woke_count);
    if (g_woke_count == 3) {
        io::printfn("Event test PASSED: all 3 waiters woke up");
    } else {
        io::printfn("Event test FAILED: only %d woke up", g_woke_count);
    }
    g_event.free();

    // --- Channel test ---
    io::printfn("\n=== Channel test (%d pairs) ===", CHAN_COUNT);
    for (int i = 0; i < CHAN_COUNT; i++) {
        g_channels[i] = asyncio::channel_new();
    }

    Task* recv_task = loop.create_task(&chan_receiver,  "receiver");
    Task* s0        = loop.create_task(&chan_sender_0,  "sender0");
    Task* s1        = loop.create_task(&chan_sender_1,  "sender1");
    Task* s2        = loop.create_task(&chan_sender_2,  "sender2");

    Task*[4] ch_tasks = { recv_task, s0, s1, s2 };
    asyncio::gather(&ch_tasks);

    bool chan_ok = true;
    for (int i = 0; i < CHAN_COUNT; i++) {
        io::printfn("channel[%d]: sent=%d, received=%d", i, g_sent[i], g_received[i]);
        if (g_received[i] != g_sent[i]) chan_ok = false;
        g_channels[i].free();
    }
    if (chan_ok) {
        io::printfn("Channel test PASSED");
    } else {
        io::printfn("Channel test FAILED");
    }
}

fn int main()
{
  @assert_leak() {
    asyncio::run(&main_coro);
  };
    return 0;
}
