// executor.c3

// call loop.run_in_executor() to treat a blocking (non-async-friendly) function in a thread, in parallel with other async functions

// Nomota <hiongun@gmail.com>; MIT License

module ext::asyncio;

import std::thread;
import std::atomic::types;
import ext::debug;
import ext::mem;
import ext::fiber;
import c::pthread;
import c::errno;
import c::stdio;
import c::stdlib;

ThreadPool{4} pool;
bool pool_initialized = false;

fn void pool_init() @init
{
    if (! pool_initialized) {
        pool.init()!!;
        pool_initialized = true;
    }
}

alias ExecutorFn = fn void*(void*);

struct ExecutorWork {
    ExecutorFn func;
    void* arg;
    void* result;
    Future* future;
    EventLoop* loop;
}

macro void warn_stack(String tag) @private
{
    PthreadAttr attr;
    pthread::pthread_getattr_np(pthread::pthread_self(), &attr);

    void* stack_addr;
    usz stack_size;
    pthread::pthread_attr_getstack(&attr, &stack_addr, &stack_size);

    char marker;

    stdio::printf(
        "%s,%d: %s: stack low=%p high=%p size=%zu marker=%p\n(low.%d.marker.%d.high)\n",
        $$FILE, $$LINE, tag,
        stack_addr,
        (char*)stack_addr + stack_size,
        stack_size,
        &marker, (int)(&marker-stack_addr), (int)(((char*)stack_addr + stack_size) - &marker)
    );

    pthread::pthread_attr_destroy(&attr);
}

fn int _executor_thread(void* work)
{
    ExecutorWork* w = (ExecutorWork*)work;
    
  @pool_init(mem, 16_000) { // Temp allocator needs init at each thread
    w.result = w.func(w.arg); // blocking operation runs on OS thread
  };
  
    w.future.set_result(null); // notify finish

    return 0;
}

// Public API

// Run blocking func(arg) in a new OS thread.
// The calling fiber suspends until the thread completes.

fn void*? EventLoop.run_in_executor(&self, ExecutorFn func, void* arg = null)
{

    Future* fut = self.create_future();
    fut.defer_free();
    
    ExecutorWork w = {
        .func = func, 
        .arg = arg, 
        .result = null,
        .future = fut, // to know when thread finish
        .loop = self,
    };

    self.executor_count++;
    
    pool.push(&_executor_thread, &w)!;
    void* r = fut.await()!; // resumes in _executor_wakeup

    self.executor_count--;

    return w.result;
}

// Module-level shorthand — uses the currently running loop.
fn void*? run_in_executor(ExecutorFn func, void* arg = null)
{
    return get_running_loop().run_in_executor(func, arg)!;
}

