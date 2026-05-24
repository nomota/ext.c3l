// ext/aio/docs/EXECUTOR.md 

# ext::aio Executor

Run blocking functions on a thread pool and await their result.

This module provides a small executor API for running blocking or CPU-bound functions outside the event loop thread, then returning the result back to the async task through a `Future`.


## Function types

### `ExecutorFn`

```c3
alias ExecutorFn = fn void*(void*);
```

Function type used by the executor.

An executor function receives one `void*` argument and returns one `void*` result.

```c3
fn void* blocking_work(void* arg)
{
    return arg;
}
```

### `ThreadSafeFn`

```c3
alias ThreadSafeFn = fn void?(void*);
```

Function type used by the event loop thread-safe callback queue.

This is mainly used internally by the executor to notify the event loop after worker-thread completion.

## Run blocking work

### `EventLoop.run_in_executor`

```c3
fn void*? EventLoop.run_in_executor(&self, ExecutorFn func, void* arg = null)
```

Runs `func(arg)` on the global executor thread pool and waits asynchronously for the result.

The blocking function runs on a worker thread. When it finishes, the worker thread schedules a callback back into the event loop thread and completes the waiting `Future`.

```c3
void* result = loop.run_in_executor(&blocking_work, arg)!;
```

If the waiting task is cancelled or the future fails, the function returns the fault.

### `run_in_executor`

```c3
fn void*? aio::run_in_executor(ExecutorFn func, void* arg = null)
```

Convenience wrapper around the current event loop.

```c3
void* result = aio::run_in_executor(&blocking_work, arg)!;
```

This is equivalent to:

```c3
EventLoop* loop = aio::current_loop()!;
void* result = loop.run_in_executor(&blocking_work, arg)!;
```

## Example: run a blocking function

```c3
import ext::aio;
import ext::debug;

fn void* blocking_func(void* arg)
{
    int value = (int)(isz)arg;

    // Simulate blocking work here.
    value *= 2;

    return (void*)(isz)value;
}

fn void? main_task(void* arg)
{
    void* result = aio::run_in_executor(&blocking_func, (void*)21)!;

    int value = (int)(isz)result;
    warn("result: %d", value);
}
```

## Example: pass a struct argument

```c3
import ext::aio;
import ext::mem;
import ext::debug;

struct WorkArg
{
    int a;
    int b;
}

struct WorkResult
{
    int value;
}

fn void* add_blocking(void* arg)
{
    WorkArg* a = (WorkArg*)arg;

    WorkResult* result = mem::new(WorkResult)!!;
    result.value = a.a + a.b;

    return result;
}

fn void? main_task(void* arg)
{
    WorkArg arg = {
        .a = 10,
        .b = 32,
    };

    WorkResult* result = (WorkResult*)aio::run_in_executor(&add_blocking, &arg)!;
    defer mem::free(result);

    warn("result: %d", result.value);
}
```

## Example: use an explicit event loop

```c3
import ext::aio;
import ext::debug;

fn void* blocking_job(void* arg)
{
    return (void*)123;
}

fn void? main_task(void* arg)
{
    EventLoop* loop = aio::current_loop()!;

    void* result = loop.run_in_executor(&blocking_job)!;

    warn("result: %d", (int)(isz)result);
}
```


## Cancellation behavior

If the awaiting async task is cancelled while the executor thread is still running, the executor work is not freed immediately because the worker thread may still use it.

Instead, the future pointer in the work object is cleared:

```c3
work.future = null;
```

When the worker thread later completes, `executor_complete()` sees that the future is missing or already done and frees the work safely.

## Memory ownership

`run_in_executor()` owns the internal `ExecutorWork`.

The caller owns any memory passed through `arg`, unless the blocking function takes ownership explicitly.

The caller also owns the returned pointer, unless the returned pointer refers to static memory or caller-owned memory.

```c3
void* result = aio::run_in_executor(&func, arg)!;
// free result here if func allocated it
```

## Notes

- The executor uses a global `ThreadPool{4}`.
- The executor pool is initialized automatically.
- `ExecutorFn` runs on a worker thread, not on the event loop thread.
- The executor result is delivered back to the event loop through a `Future`.
- Do not access event-loop-only objects directly from the executor worker function.
- Use the thread-safe callback path to notify the event loop from another thread.
- `run_in_executor()` is appropriate for blocking file, DNS, system, or CPU-heavy work that should not block the event loop.

// eof