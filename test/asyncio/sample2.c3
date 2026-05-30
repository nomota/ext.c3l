// sample2.c3
// Tests: Future, wait_for (timeout), cancel, add_done_callback, as_completed
//
// Scenario
// --------
//   producer  -- completes a shared Future after ~200 ms
//   consumer1 -- waits on the same Future with a generous timeout (500 ms)
//   consumer2 -- waits on the same Future with a tight timeout (100 ms)
//                -> should receive TIMEOUT and demonstrate cancel propagation
//   watcher   -- registers a done_callback on the Future and prints whenever it fires

module sample2;

import std::io;
import c::stdlib;
import ext::debug;
import ext::asyncio;

// ----------------------------------------
//  Shared state
// ----------------------------------------

asyncio::Future* g_ready;   // set by producer, awaited by consumers

// ----------------------------------------
//  Done callback (runs synchronously when Future fires)
// ----------------------------------------

fn void on_ready(asyncio::Future* f, asyncio::CallbackCtx ctx)
{
    io::printfn("[watcher] Future completed (state=%s)",
                f.cancelled() ? "CANCELLED" : "FINISHED");
}

// ---------------------------------------
//  Coroutines
// ---------------------------------------

fn void producer()
{
    io::printfn("[producer] sleeping 200 ms before resolving Future...");
    asyncio::sleep_ms(200);

    if (!g_ready.done()) {
        io::printfn("[producer] resolving Future");
        g_ready.set_result(null);
    } else {
        io::printfn("[producer] Future already done (was cancelled?)");
    }
}

fn void consumer1()
{
    io::printfn("[consumer1] waiting with 500 ms timeout...");
    if (catch err = g_ready.wait_for(500_000)) {  // 500 ms in us
        if (err == asyncio::NONE) {
            io::printfn("[consumer1] received result OK");
        } else {
            io::printfn("[consumer1] error: %s", err);
        }
    }
}

fn void consumer2()
{
    io::printfn("[consumer2] waiting with 100 ms timeout (should expire)...");
    if (catch err = g_ready.wait_for(100_000)) {   // 100 ms in us
        if (err == asyncio::TIMEOUT) {
            io::printfn("[consumer2] timed out as expected");
        } else {
            io::printfn("[consumer2] unexpected outcome: %s", err);
        }
    }
}

// ----------------------------------------
//  Main coroutine
// ----------------------------------------

fn void callback(asyncio::Task* t, sz idx) {
    io::printfn("[main] task[%d] '%s' completed", idx, t.get_name());
}

fn void main_coro()
{
    io::printfn("=== sample2: Future / timeout / cancel ===");

    EventLoop* loop = asyncio::get_running_loop();
    // Create a PENDING Future (state must be PENDING for set_result to work)
    g_ready = loop.create_future();
    g_ready.state  = asyncio::State.PENDING;

    // Register a done callback before any task runs
    g_ready.add_done_callback(&on_ready, null);

    // Launch the three participants
    asyncio::Task*[3] tasks = {
        loop.create_task(&producer,   "producer"),
        loop.create_task(&consumer1,  "consumer1"),
        loop.create_task(&consumer2,  "consumer2"),
    };

    // Print completion order
    asyncio::as_completed(&tasks, 3, &callback);

    g_ready.free();
    io::printfn("=== sample2 done ===");
    
    for (sz i = 0; i < 3; i++) {
        tasks[i].free();
    }
}

fn void main()
{
  @assert_leak() {
    asyncio::run(&main_coro);
  };
}
