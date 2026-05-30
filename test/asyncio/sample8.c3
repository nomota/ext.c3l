// sample8.c3

// Demonstrates TaskGroup:
//   - All tasks succeed → wait() returns NONE
//   - One task fails   → wait() cancels the rest and returns the error

module sample_tg;

import ext::asyncio;
import std::io;
import c::stdlib;
import ext::debug;

// ---------------------------------------
//  Shared state
// ----------------------------------------

int[5] g_results;   // each worker writes its result here

// ----------------------------------------
//  Success scenario — 5 workers that each do some work
// ----------------------------------------

// Worker context passed via a global (C3 coroutines take no args)
int g_worker_id = 0;

tlocal int tl_id;   // each fiber captures its own id at start

fn void make_worker(int id)
{
    // We can't pass args to coroutines, so we use a tlocal capture pattern:
    // caller sets g_worker_id, then immediately creates the task.
    // The task reads it before any yield.
}

// Five concrete workers to avoid the no-arg coroutine limitation
fn void worker_0() { asyncio::sleep_us(50 * 1);  g_results[0] = 100; }
fn void worker_1() { asyncio::sleep_us(50 * 2);  g_results[1] = 200; }
fn void worker_2() { asyncio::sleep_us(50 * 3);  g_results[2] = 300; }
fn void worker_3() { asyncio::sleep_us(50 * 4);  g_results[3] = 400; }
fn void worker_4() { asyncio::sleep_us(50 * 5);  g_results[4] = 500; }

// ----------------------------------------
//  Failure scenario — one task sets an error, the rest
//  should be cancelled before they finish
// ----------------------------------------

int[3]  g_ran;     // 1 if the task body completed, 0 if cancelled
bool g_fail_triggered = false;

fn void faulty_task()
{
    // Simulate work, then signal failure by setting error on own future
    asyncio::sleep_us(200);
    EventLoop* loop = asyncio::get_running_loop();
    Task* me = loop.current;
    me.set_exception(asyncio::INVALID_STATE_ERR);   // inject an error
    g_fail_triggered = true;
}

fn void slow_task_0()
{
    if (catch asyncio::sleep_us(10_000)) return;
    g_ran[0] = 1;
}

fn void slow_task_1()
{
    if (catch asyncio::sleep_us(10_000)) return;
    g_ran[1] = 1;
}

// ----------------------------------------
//  Main coroutine
// ----------------------------------------

fn void main_coro()
{
    //warn("-");
    EventLoop* loop = asyncio::get_running_loop();

    // ====================================
    //  Test 1: all tasks succeed
    // ====================================
    io::printfn("=== TaskGroup success test ===");

    TaskGroup* tg1 = asyncio::taskgroup_new();

    tg1.create_task(&worker_0, "w0");
    tg1.create_task(&worker_1, "w1");
    tg1.create_task(&worker_2, "w2");
    tg1.create_task(&worker_3, "w3");
    tg1.create_task(&worker_4, "w4");

    fault err1 = asyncio::NONE;
    if (catch esc1 = tg1.wait()) err1 = esc1;

    if (err1 == asyncio::NONE) {
        io::printfn("wait() returned NONE — OK");
    } else {
        io::printfn("wait() returned unexpected error: %s", err1);
    }

    bool results_ok = true;
    for (int i = 0; i < 5; i++) {
        io::printfn("  g_results[%d] = %d", i, g_results[i]);
        if (g_results[i] != (i + 1) * 100) results_ok = false;
    }
    io::printfn("Success test: %s", results_ok ? "PASSED" : "FAILED");
    tg1.free();

    // ====================================
    //  Test 2: one task fails → others are cancelled
    // ====================================
    io::printfn("\n=== TaskGroup failure propagation test ===");

    g_ran[0] = 0;
    g_ran[1] = 0;
    g_fail_triggered = false;

    TaskGroup* tg2 = asyncio::taskgroup_new();

    tg2.create_task(&faulty_task, "faulty");
    tg2.create_task(&slow_task_0, "slow0");
    tg2.create_task(&slow_task_1, "slow1");

    fault err2 = asyncio::NONE;
    if (catch esc2 = tg2.wait()) err2 = esc2;

    io::printfn("faulty task triggered: %s", g_fail_triggered ? "yes" : "no");
    io::printfn("wait() returned error: %s (expected %s)", err2, asyncio::INVALID_STATE_ERR);
    io::printfn("slow_task_0 completed: %s (expected: no)", g_ran[0] ? "yes" : "no");
    io::printfn("slow_task_1 completed: %s (expected: no)", g_ran[1] ? "yes" : "no");

    bool fail_ok = (err2 == asyncio::INVALID_STATE_ERR)
                && g_fail_triggered
                && (g_ran[0] == 0)
                && (g_ran[1] == 0);

    io::printfn("Failure propagation test: %s", fail_ok ? "PASSED" : "FAILED");
    tg2.free();
}

fn int main()
{
  @assert_leak() {
    asyncio::run(&main_coro);
  };
    return 0;
}
