// sample5.c3
// Tests: call_soon_threadsafe
//
// Scenario:
//   - The event loop runs on the main OS thread.
//   - A worker OS thread performs a "blocking" computation (simulated with
//     thread::sleep), then pushes results back to the loop via
//     call_soon_threadsafe.
//   - The loop-side callback stores the result and calls loop.stop().
//
// This models the common pattern of offloading blocking work to a thread
// and receiving the result asynchronously in the event loop.

module sample5;

import std::io;
import std::time;
import std::thread;
import ext::asyncio;
import ext::debug;
import c::stdio;

// ---------------------------------------------
//  Shared result (written by worker, read by loop)
// ---------------------------------------------

int g_result;
bool g_result_ready;

// ---------------------------------------------
//  Loop-side callback: invoked on the loop thread via call_soon_threadsafe
// ---------------------------------------------

fn void on_worker_done(void* arg)
{
    g_result_ready = true;
    io::printfn("[loop   ] received result from worker: %d", g_result);
    io::printfn("[loop   ] stopping the loop");
    asyncio::get_running_loop().stop();
}

// ---------------------------------------------
//  Worker OS thread entry
// ---------------------------------------------

struct WorkerArg {
    int operand_a;
    int operand_b;
    EventLoop* loop;
}

fn int worker_thread(void* raw_arg)
{
    stdio::printf("thread called\n");
    stdio::printf("[worker ] called\n");
    
    WorkerArg* arg = (WorkerArg*)raw_arg;
    assert(arg != null, "error");
    assert(arg.operand_a == 20, "error");
    assert(arg.operand_b == 21, "error");
    stdio::printf("arg.operand_a: %d\n", arg.operand_a);
    
    stdio::printf("[worker ] started, computing %d + %d ...\n", arg.operand_a, arg.operand_b);

    // Simulate blocking work: sleep 1.5s on the OS thread
    stdio::printf("[worker ] sleep 1.5s\n");
    thread::sleep((Duration)1_500_000);

    g_result = arg.operand_a + arg.operand_b;
    stdio::printf("[worker ] done, pushing result to event loop\n");

    // Push the completion callback to the loop thread — this is the only
    // safe way to touch loop state from another OS thread.
    //EventLoop* loop = asyncio::get_running_loop();
    arg.loop.call_soon_threadsafe(&on_worker_done, null);

    return 0;
}

// ---------------------------------------------
//  Main coroutine — starts the worker thread and yields
// ---------------------------------------------
WorkerArg* g_arg;

fn void main_coro()
{
    io::printfn("=== sample5: call_soon_threadsafe from worker thread ===");

    g_arg = mem::new(WorkerArg);
    *g_arg = { .operand_a = 20, .operand_b = 21, .loop = asyncio::get_running_loop() };
    
    Thread thr;
    thr.create(&worker_thread, g_arg)!!; // run in a separate thread
    thr.detach()!!;
    
    io::printfn("[main   ] worker thread launched, yielding to loop");

    // Yield control; the loop will keep running until the worker calls stop()
    // via call_soon_threadsafe.  We sleep longer than the worker takes.
    io::printfn("[main   ] sleep 5.0s");
    asyncio::sleep(5.0);


    io::printfn("[main   ] (should not reach here — loop was stopped by worker)");
}

fn void main()
{
  @assert_leak() {
    EventLoop* loop = asyncio::new_event_loop();
    asyncio::set_event_loop(loop);

    Task* t = loop.create_task(&main_coro, "main", 64_000);

    loop.run_forever();

    io::printfn("=== sample5 done ===");
    io::printfn("result=%d  ready=%s",
                g_result,
                g_result_ready ? "true" : "false");
    t.free();
    mem::free(g_arg);

    loop.close();
    loop.free();
  };
}
