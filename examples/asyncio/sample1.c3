// sample1.c3

// Tests: create_task, sleep_ms, gather
// Spawns three counter coroutines that sleep between ticks and run concurrently.

module sample1;

import std::io;
import ext::debug; // warn, @assert
import ext::mem;
import ext::asyncio;
import ext::fiber;

// -----------------------------------------
//  Shared counter state
// -----------------------------------------

int[3] g_counts;   // each task writes to its own slot

// -----------------------------------------
//  Worker coroutines
// -----------------------------------------

fn void counter_a()
{
    for (int i = 0; i < 5; i++) {
        g_counts[0]++;
        io::printfn("[A] tick %d", i + 1);
        asyncio::sleep_ms(150);
    }
    io::printfn("[A] done  (total=%d)", g_counts[0]);
}

fn void counter_b()
{
    for (int i = 0; i < 3; i++) {
        g_counts[1]++;
        io::printfn("[B] tick %d", i + 1);
        asyncio::sleep_ms(170);
    }
    io::printfn("[B] done  (total=%d)", g_counts[1]);
}

fn void counter_c()
{
    for (int i = 0; i < 4; i++) {
        g_counts[2]++;
        io::printfn("[C] tick %d", i + 1);
        asyncio::sleep_ms(130);
    }
    io::printfn("[C] done  (total=%d)", g_counts[2]);
}

// -----------------------------------------
//  Main coroutine
// -----------------------------------------

fn void main_coro()
{
    io::printfn("=== sample1: concurrent counters ===");

    EventLoop* loop = asyncio::get_running_loop();
    asyncio::Task*[3] tasks = {
        loop.create_task(&counter_a, "counter_a"),
        loop.create_task(&counter_b, "counter_b"),
        loop.create_task(&counter_c, "counter_c"),
    };

    // Wait for all three to finish
    asyncio::gather(&tasks);

    io::printfn("=== all tasks done ===");
    io::printfn("final counts: A=%d  B=%d  C=%d", g_counts[0], g_counts[1], g_counts[2]);
}

fn void main()
{
  @assert_leak() {
    asyncio::run(&main_coro);
  };
}
