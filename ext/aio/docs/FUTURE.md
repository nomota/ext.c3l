# Future

`Future` is an awaitable result container in `ext::aio`.

A future represents a value that may become available later. A task can wait for a future with `await()`, and another task or callback can complete it by setting a result, an error, or cancellation.

Back to [`ext::aio`](../README.md).

## Basic idea

A future starts incomplete.

It can finish in one of three ways:

| Completion | Method |
|-----------|--------|
| Success | `future.set_result(result)` |
| Error | `future.set_error(err)` |
| Cancellation | `future.cancel(err)` |

A waiting task uses:

```c3
void* value = future.await()!;
```

If the future is already done, `await()` returns immediately.

## Creating a future

Create a future inside a running event loop:

```c3
Future* future = aio::future_new()!;
```

`future_new()` requires an active event loop. It should be called from async code, or from code that already has an active `ext::aio` loop.

Example:

```c3
fn void? other_task(void* arg) // callee task
{
    Future* fut = (Future*)arg;
    
    // do something
    
    fut.set_result(something_in_void_ptr); // awake awaiting future
}

fn void? main_task(void* arg) // caller task
{
    Future* future = aio::future_new()!;
    defer future.free();

    aio::spawn(&other_task, future)!;

    void* value = future.await()!; // wait until the value gets filled
    // value == something_in_void_ptr

    future.free();
}
```

## Freeing a future

Free a future with:

```c3
// in a caller task where the future was creates
future.free(); 
```

If the future is still incomplete, `free()` cancels it first. This wakes any tasks waiting on it.

The caller that creates a future is usually responsible for freeing it.

## Waiting for a result

Use `await()` to wait for a future:

```c3
// in a caller task
void* result = future.await()!;
```

If the future is not done, the current task is suspended. The event loop can continue running other tasks.

When the future completes, the waiting task resumes.

Example:

```c3
fn void? waiter(void* arg)
{
    // caller task

    void* value = future.await()!;

    // use the value
}
```

## Setting a result

Complete a future successfully with:

```c3
// in a callee task
future.set_result(result)!; // void*
```

Example:

```c3
fn void? producer(void* arg) // callee task
{
    Future* future = (Future*)arg;

    future.set_result((void*)123)!;
}
```

After a result is set:

* `future.done()` returns `true`
* `future.cancelled()` returns `false`
* `await()` returns the stored result
* all waiters are woken

A future can be completed only once. Calling `set_result()` on a completed future returns `FUTURE_DONE` error.

## Setting an error

Complete a future with an error of C3's `fault` type:

```c3
// in callee task
future.set_error(aio::FAILED)!;
```

A future error is delivered to awaiters:

```c3
// in caller task
if (catch err = future.await())
{
    // err is the fault passed to set_error()
}
```

Like `set_result()`, `set_error()` can be called only once.

## Cancelling a future

Cancel a future with:

```c3
// in callee task
future.cancel();
```

or with a specific cancellation fault:

```c3
// in callee task
future.cancel(aio::TIMEOUT);
```

After cancellation:

* `future.done()` returns `true`
* `future.cancelled()` returns `true`
* `await()` returns the cancellation fault
* all waiters are cancelled

If no fault is supplied, cancellation uses `CANCELLED`.

## Checking state

Use `done()` to check whether a future has completed:

```c3
if (future.done())
{
    // result, error, or cancellation is available
}
```

Use `cancelled()` to check whether it was cancelled:

```c3
if (future.cancelled())
{
    // future completed by cancellation
}
```

Most code should simply call `await()` and handle faults normally.

## Getting the result without waiting

`get_result()` returns the result if the future is already done.

```c3
void* value = future.get_result()!;
```

If the future is not done, it returns `INVALID_STATE` error.

If the future completed with an error or cancellation, `get_result()` returns that fault.

Use `await()` in normal async code. Use `get_result()` only when you already know the future is done.

## Multiple waiters

A future can have multiple waiting tasks.

When the future completes, all waiters are woken.

```c3
// caller task
Future* future = aio::future_new()!;

aio::spawn(&waiter_a, future)!; // if it has future.await() in it
aio::spawn(&waiter_b, future)!; // if it has future.await() in it 

// this awakes both waiter_a and waiter_b
future.set_result(data)!;
```

Both waiting tasks resume and observe the same result.

## Result type

`Future` stores the result as `void*`.

```c3
void* result;
```

This keeps the primitive simple and generic, but it means the caller must define ownership and casting rules.

Example using an integer-like value:

```c3
// in callee task
future.set_result((void*)123)!;

// in caller task
void* value = future.await()!;
int n = (int)(isz)value;
```

Example using a pointer:

```c3
// in callee task
MyResult* result = alloc_result()!;
future.set_result(result)!;

// in caller task
MyResult* received = (MyResult*)future.await()!;
received.free();
```

The future does not automatically free the result pointer. The producer and consumer must agree on ownership.

## Common producer/consumer pattern

```c3
fn void? consumer(void* arg)
{
    Future* future = (Future*)arg;

    void* value = future.await()!;

    int n = (int)(iptr)value;

    return;
}

fn void? producer(void* arg)
{
    Future* future = (Future*)arg;

    aio::sleep(100)!;

    future.set_result((void*)42)!;

    return;
}

fn void? main_task(void* arg)
{
    Future* future = aio::future_new()!;
    defer future.free();

    Task* c = aio::spawn_joinable(&consumer, future)!;
    Task* p = aio::spawn_joinable(&producer, future)!;

    p.join();
    c.join();
}
```

## Error propagation example

```c3
fn void? consumer(void* arg)
{
    Future* future = (Future*)arg;

    if (catch err = future.await())
    {
        // err is aio::FAILED
        return err;
    }

    return;
}

fn void? producer(void* arg)
{
    Future* future = (Future*)arg;

    future.set_error(aio::FAILED)!;

    return;
}
```

## Timeout-style cancellation

A timeout utility can cancel a future with `TIMEOUT`:

```c3
future.cancel(aio::TIMEOUT);
```

Awaiters receive `TIMEOUT`:

```c3
if (catch err = future.await())
{
    if (err == aio::TIMEOUT)
    {
        // timed out
    }
}
```

## Practical rules

* Create futures only while an event loop is active.
* Complete a future only once.
* Use `await()` in normal async code.
* Use `get_result()` only after confirming `done()`.
* Always free futures you create.
* Define ownership of `void*` result values clearly.
* Use `set_error()` for operation failure.
* Use `cancel()` for cancellation or timeout.

## Related documents

| Document | Description |
|----------|-------------|
| [`EVENT_LOOP.md`](EVENT_LOOP.md) | Event loop lifecycle and scheduling model |
| [`TASKS.md`](TASKS.md) | Task spawning, joining, cancellation |
| [`WAITER.md`](WAITER.md) | Waiters, sleep, and timers |
| [`SYNCHRONIZATION.md`](SYNCHRONIZATION.md) | Event, Lock, Semaphore, Queue, Channel |
| [`EXECUTOR.md`](EXECUTOR.md) | Thread executor for blocking work |
