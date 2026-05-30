// executor.c3

// Run blocking functions on a thread pool and await their result.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import std::thread;
import ext::mem;
import ext::debug;
import ext::aio::io;

faultdef EXECUTOR_ERROR;

ThreadPool{4} executor_pool;
bool executor_pool_initialized = false;

fn void executor_pool_init() @init
{
    if (executor_pool_initialized) return;

    executor_pool.init()!!;
    executor_pool_initialized = true;
}

alias ExecutorFn = fn void*(void*);

struct ExecutorWork
{
    EventLoop* loop;

    ExecutorFn func;
    void* arg;
    void* result;
    
    Future* future;
}

fn void ExecutorWork.free(&self) @inline
{
    localmem.free(self);
}

fn void? executor_complete(void* arg) @private
{
    ExecutorWork* work = (ExecutorWork*)arg;
    @assert(work != null);
    
    Future* future = work.future;
    
    if (future == null || future.done())
    {
        work.free();
        return;
    }
    
    (void)future.set_result(work.result);
}

fn int executor_thread(void* arg) @private
{
  @pool_init(mem, 16_000) { // needs to cover whole thread
    ExecutorWork* work = (ExecutorWork*)arg;
    @assert(work != null);

    work.result = work.func(work.arg);

    // notify back to loop's thread
    work.loop.threadsafe.call_soon(&executor_complete, work);
  };
    return 0;
}

fn void*? EventLoop.run_in_executor(&self, ExecutorFn func, void* arg = null)
{
    @assert(func != null);

    executor_pool_init();

    Future* future = future_new()!; defer future.free();
    ExecutorWork* work = localmem.alloc(ExecutorWork)!;
    *work = {
        .loop = self,
        .func = func,
        .arg = arg,
        .future = future,
        .result = null,
    };

    // fork a thread
    executor_pool.push(&executor_thread, work);

    void*? result = future.await(); // wait until thread notify back to loop
    if (catch err = result)
    {
        // Don't free work, because still in use in thread.
        // Disable future, so that it may not be used in thread.
        work.future = null;
        return err~;
    }

    work.free();
    return result;
}

fn void*? run_in_executor(ExecutorFn func, void* arg = null)
{
    EventLoop* loop = current_loop()!;

    return loop.run_in_executor(func, arg);
}

alias ThreadSafeFn = fn void?(void*);

struct ThreadSafeCall @private
{
    ThreadSafeFn func;
    void* arg;
    ThreadSafeCall* next;
}

struct ThreadSafe @private
{
    EventLoop* loop;
    ThreadSafeCall* head;
    ThreadSafeCall* tail;
    thread::Mutex lock;
}

fn void? ThreadSafe.init(&self, EventLoop* loop)
{
    self.loop = loop;
    self.head = null;
    self.tail = null;

    self.lock.init()!;
}

fn void ThreadSafe.deinit(&self)
{
    ThreadSafeCall* call = self.head;

    while (call != null)
    {
        ThreadSafeCall* next = call.next;
        localmem.free(call);
        call = next;
    }

    self.lock.destroy();
    
    self.loop = null;
    self.head = null;
    self.tail = null;
}

fn void? ThreadSafe.call_soon(&self, ThreadSafeFn func, void* arg = null) @maydiscard
{
    if (func == null) return;

    ThreadSafeCall* call = localmem.alloc(ThreadSafeCall)!;
    *call = {
        .func = func,
        .arg = arg,
        .next = null,
    };

    self.lock.lock();

    if (self.tail == null)
    {
        self.head = call;
        self.tail = call;
    }
    else
    {
        self.tail.next = call;
        self.tail = call;
    }

    self.lock.unlock();
    
    io::poll_wake(); // notify to wake poll
}

fn void ThreadSafe.process(&self)
{
    while (true)
    {
        self.lock.lock();

        ThreadSafeCall* call = self.head;

        if (call != null)
        {
            self.head = call.next;

            if (self.head == null)
            {
                self.tail = null;
            }

            call.next = null;
        }

        self.lock.unlock();

        if (call == null) break;

        ThreadSafeFn func = call.func;
        void* arg = call.arg;

        localmem.free(call);

        if (func != null)
        {
            if (catch err = func(arg))
            {
                warn("threadsafe callback failed: %s", err);
            }
        }
    }
}

// eof