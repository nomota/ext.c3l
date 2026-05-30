# Event Loop

`ext::aio` runs asynchronous code on a cooperative event loop.

The event loop schedules tasks, resumes them when they are ready, handles sleeps and timers, and waits for I/O events. Most programs should use `aio::run()` instead of manually creating an event loop.

Back to [`ext::aio`](../README.md).

## Basic usage

```c3
import ext::aio;
import ext::debug;

fn void? main_task(void* arg) // async task
{
    warn("hello");

    aio::sleep(1000)!;

    warn("done");
}

fn void main()
{ 
    void* arg;
    aio::run(&main_task, arg); // run event loop, arg is optional
}
```

`aio::run()` creates an event loop, runs the main task within the loop, cleans up the loop, and shuts down the aio runtime.

Main task function must be of following type. It is a async fiber coroutine.

```c3
alias TaskFn = fn void?(void*);
```

## Cooperative scheduling

`ext::aio` does not forcibly interrupt running tasks.

A task runs until it:

* awaits a future
* sleeps
* waits for I/O
* waits on a synchronization primitive
* calls `aio::yield()`
* returns
* fails
* is cancelled

A long CPU-bound task should occasionally yield:

```c3
fn void? worker(void* arg)
{
    while (has_more_work())
    {
        do_some_work();

        aio::yield()!;
    }
}
```

## Spawning tasks

You can create more tasks in a task under a loop. 
Use `spawn()` for detached background work:

```c3
Task* task = aio::spawn(&background_worker, arg, detached: true)!; // detached is optional and true by default
```

Use `spawn_joinable()` when you need to wait for a task:

```c3
Task* task = aio::spawn_joinable(&worker, arg)!;

task.join(); // wait until the task ends
```

Detached tasks are cleaned up by the loop after they finish. Joinable tasks should be joined by the caller.

## Sleeping

Use `aio::sleep()` instead of blocking sleep functions:

```c3
aio::sleep(1000)!; // micro seconds
```

This suspends only the current task. Other tasks and I/O events can continue running.

## Yielding

Use `aio::yield()` to voluntarily let other ready tasks run:

```c3
aio::yield()!;
```

This is mainly useful in long CPU loops. Most async operations already yield naturally when they need to wait.

## Stopping the loop

Stop the current loop with:

```c3
aio::stop()!;
```

Stopping the loop cancels unfinished tasks and exits the loop.

Example:

```c3
fn void? shutdown_task(void* arg)
{
    aio::stop()!;
}
```

## Current loop and task

Inside async code, you can access the active loop and task:

```c3
EventLoop* loop = aio::current_loop()!;
Task* task = aio::current_task()!;
```

These functions are valid only while running inside an active `ext::aio` loop. Outside the loop, `current_loop()` returns `NO_LOOP`.

Most user code does not need these functions.

## Manual loop control

Most programs should use `aio::run()`.

Manual loop control is useful only when embedding `ext::aio` into another runtime or when a program needs explicit loop lifetime control.

```c3
EventLoop* loop = aio::loop_new()!;

Task* task = loop.spawn_joinable(&main_task)!;

loop.run_until_complete(task)!;

loop.free();
```

`run_forever()` runs until `aio::stop()` or `loop.stop()` is called.

```c3
EventLoop* loop = aio::loop_new()!;

loop.spawn(&server_task)!;
loop.run_forever()!;

loop.free();
```

## I/O behavior

Async I/O suspends only the current task.

```c3
char[1024] buf;
sz n = stream.read(buf[..])!;
```

While this task waits for data, other tasks may run.

Socket and pipe operations are handled by the platform I/O backend. Regular file operations are executor-backed.

## Blocking calls

Do not call long blocking functions directly inside async tasks.

Bad:

```c3
fn void? task(void* arg)
{
    blocking_read();
}
```

Better:

```c3
fn void? task(void* arg)
{
    async_or_executor_operation()!;
}
```

A blocking call inside a task blocks the entire event-loop thread.

## Common patterns

### Run tasks concurrently

```c3
fn void? main_task(void* arg)
{
    Task* a = aio::spawn_joinable(&worker_a)!;
    Task* b = aio::spawn_joinable(&worker_b)!;

    a.join();
    b.join();
}
```

### Background task

```c3
fn void? main_task(void* arg)
{
    aio::spawn(&background_worker)!;

    do_main_work()!;
}
```

### TCP server loop

```c3
fn void? main_task(void* arg)
{
    Stream* server = aio::stream_listen("127.0.0.1", 8080)!;
    defer server.free();

    while (!server.closed)
    {
        Stream* client = server.accept()!;

        aio::spawn(&handle_client, client)!;
    }
}
```

## Practical rules

* Use `aio::run()` for normal program entry.
* Use `spawn_joinable()` when completion matters.
* Use `spawn()` for detached background tasks.
* Do not block inside tasks.
* Use `aio::sleep()` instead of blocking sleep.
* Use `aio::yield()` in long CPU loops.
* Use async I/O functions instead of manual blocking I/O.
* Call `aio::stop()` to shut down a running loop from async code.

## Related documents

| Document | Description |
|----------|-------------|
| [`TASKS.md`](TASKS.md) | Task lifecycle, joining, cancellation |
| [`FUTURE.md`](FUTURE.md) | Futures and await behavior |
| [`WAITER.md`](WAITER.md) | Waiters, sleep, and timers |
| [`SYNCHRONIZATION.md`](SYNCHRONIZATION.md) | Event, Lock, Semaphore, Queue, Channel |
| [`STREAMS.md`](STREAMS.md) | TCP stream API |
| [`DATAGRAMS.md`](DATAGRAMS.md) | UDP datagram API |
| [`EXECUTOR.md`](EXECUTOR.md) | Thread executor for blocking work |
| [`PLATFORM.md`](PLATFORM.md) | POSIX and Windows backend notes |
