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

tlocal ThreadPool{4} pool;
tlocal bool pool_initialized = false;

struct ExecutorWork {
    ExecutorFn func;
    void* arg;
    void* result;
    Future* future;
    EventLoop* loop;
}

fn void _executor_wakeup(void* work)
{
    ExecutorWork* w = (ExecutorWork*)work;

    if (! w.future.done()) {
        w.future.set_result(null); // notify finish
    }
}

fn int _executor_thread(void* work)
{
    ExecutorWork* w = (ExecutorWork*)work;

  @pool_init(mem, 16_000) { // Temp allocator needs init at each thread
    w.result = w.func(w.arg); // blocking operation runs on OS thread
  };
  
    w.loop.call_soon_threadsafe(&_executor_wakeup, w); // safe cross-thread wakeup

    return 0;
}

// Public API

// Run blocking func(arg) in a new OS thread.
// The calling fiber suspends until the thread completes.

fn void*? EventLoop.run_in_executor(&self, ExecutorFn func, void* arg = null)
{
    if (! pool_initialized) {
        pool.init()!;
        pool_initialized = true;
    }

    Future* fut = self.create_future();
    fut.defer_free();
    
    ExecutorWork* w = mem_alloc(ExecutorWork); defer mem_free(w);

    *w = {
        .func = func, 
        .arg = arg, 
        .result = null,
        .future = fut, // to know when thread finish
        .loop = self,
    };

    self.executor_count++;
 
    pool.push(&_executor_thread, w)!;
    
    void* r = fut.await()!; // resumes in _executor_wakeup

    self.executor_count--;

    void* result = w.result;

    return result;
}

// Module-level shorthand — uses the currently running loop.
fn void*? run_in_executor(ExecutorFn func, void* arg = null)
{
    return get_running_loop().run_in_executor(func, arg)!;
}

