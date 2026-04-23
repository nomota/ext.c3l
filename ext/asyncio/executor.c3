// executor.c3

// call loop.run_in_executor() to treat a blocking (non-async-friendly) function in a thread, in parallel with other async functions

// Nomota <hiongun@gmail.com>; MIT License

module ext::asyncio;

import std::thread;
import std::atomic::types;
import ext::debug;
import ext::mem;
import ext::thread::fiber;
import c::pthread;
import c::errno;

alias ExecutorFn = fn void*(void*);

struct ExecutorWork {
    ExecutorFn func;
    void* arg;
    void* result;
    Atomic{bool} alive;
}

fn int _executor_thread(void* work)
{
  @pool_init(mem, 4_000) { // Temp allocator needs init at each thread

    ExecutorWork* w = (ExecutorWork*)work;

    w.result = w.func(w.arg); // blocking operation runs on OS thread

    w.alive.store(false);
    
    return 0;
  };
}

// Public API

// Run blocking func(arg) in a new OS thread.
// The calling fiber suspends until the thread completes.

fn void*? EventLoop.run_in_executor(&self, ExecutorFn func, void* arg = null)
{
    ExecutorWork* w = mem_alloc(ExecutorWork);

    *w = {
        .func = func, 
        .arg = arg, 
        .result = null,
    };
    w.alive.store(true);
    
  $if $defined(env::WIN32):
    // keep doing io_poll(), while thread is running
    _active_op_count++;
  $endif

    self.executor_count++;
 
    thread::Thread t;
    t.create(&_executor_thread, w)!;

    // non-blocking wait
    while (w.alive.load()) {
        asyncio::sleep_zero();
    }
    
    t.join()!;
    
    self.executor_count--;

  $if $defined(env::WIN32):
    _active_op_count--;
  $endif

    void* result = w.result;
    mem_free(w);
    return result;
}

// Module-level shorthand — uses the currently running loop.
fn void*? run_in_executor(ExecutorFn func, void* arg = null)
{
    return get_running_loop().run_in_executor(func, arg)!;
}

