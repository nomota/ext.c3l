# Waiter, Sleep, and Timer

These provide the low-level waiting primitives used by `ext::aio`.

These APIs are mostly intended for library code that needs to suspend the current task and resume it later when an event becomes ready, cancelled, or timed out.

## Overview

| Component | Purpose |
|----------|---------|
| `Waiter` | Represents a suspended task waiting for an external event. |
| `Sleep` | Internal timer node used by `sleep()`. |
| `sleep(us)` | Suspends the current task for a given number of microseconds. |
| `Timer` | Cancels a target task after a timeout. |

## Waiter

A `Waiter` is the basic mechanism for suspending and waking a task.

## Public API

### `Waiter.init`

```c3
fn void Waiter.init(&self, Task* task)
```

Initializes a waiter for the specified task.

The waiter starts in the `WAITING` state, with no error, and is marked as active.

Example:

```c3
Waiter waiter;
waiter.init(current_task()!);
```

### `Waiter.done`

```c3
fn bool Waiter.done(&self) @inline
```

Returns `true` if the waiter is no longer waiting.

This is equivalent to:

```c3
self.state == READY || self.state == CANCELLED
```

### `Waiter.waiting`

```c3
fn bool Waiter.waiting(&self) @inline
```

Returns `true` if the waiter is still in the `WAITING` state.

### `Waiter.cancelled`

```c3
fn bool Waiter.cancelled(&self) @inline
```

Returns `true` if the waiter was cancelled.

### `Waiter.wake`

```c3
fn void Waiter.wake(&self)
```

Wakes the waiter normally.

If the waiter is active and still waiting, this function:

1. Sets the state to `READY`.
2. Clears the error.
3. Marks the waiter as inactive.
4. Schedules the waiting task with `loop.call_soon()`.

Calling `wake()` on an inactive, already completed, or invalid waiter is ignored.

### `Waiter.cancel`

```c3
fn void Waiter.cancel(&self, fault err = NONE)
```

Cancels the waiter.

If the waiter is active and still waiting, this function:

1. Sets the state to `CANCELLED`.
2. Stores the provided fault.
3. Uses `CANCELLED` if no explicit fault was provided.
4. Marks the waiter as inactive.
5. Schedules the waiting task with `loop.call_soon()`.

Example:

```c3
waiter.cancel(CANCELLED);
```

### `Waiter.check`

```c3
fn void? Waiter.check(&self) @maydiscard
```

Checks the waiter result after the task resumes.

If the waiter was cancelled, this returns the stored fault. If no stored fault exists, it returns `CANCELLED`.

If `error` is set, it returns that fault.

Otherwise it returns successfully.

Typical use:

```c3
task.suspend(&waiter);
waiter.check();
```

## Typical Waiter Pattern

A waiter is usually allocated on the waiting task's stack, registered with some event source, and then passed to `Task.suspend()`.

```c3
fn void? wait_for_event(EventSource* source)
{
    Task* task = aio::current_task()!;

    Waiter waiter;
    waiter.init(task);

    source.add_waiter(&waiter);

    task.suspend(&waiter);

    source.remove_waiter(&waiter);

    waiter.check();
}
```

The important rule is:

> The event source must not keep using the waiter after the waiting function returns.

Because a typical waiter is stack-allocated, it becomes invalid after the function returns. The event source must remove it before returning from the wait function.

## Sleep

Sleep implements task sleeping using a sorted linked list of `Sleep` nodes owned by the event loop.

`Sleep` is marked `@local`, and the public user-facing API is `sleep()`.

## Time Base

```c3
fn ulong aio::clock_now() @inline
```

Returns the current monotonic time in microseconds.

## `sleep`

```c3
fn void? aio::sleep(ulong us) @maydiscard
```

Suspends the current task for `us` microseconds.

Example:

```c3
aio::sleep(100_000)!; // 100 ms
```

## Timer for cancelling a task

Timerimplements task timeout handling on top of `sleep()`.

### `Task.start_timer`

```c3
fn Timer*? Task.start_timer(&self, ulong timeout_us)
```

Starts a timer for the specified task.

When the timer expires, it cancels the target task by calling:

```c3
target.cancel_timeout();
```

Returns a `Timer*` that must be cancelled or otherwise released by the caller.

Example:

```c3
Timer* timer = task.start_timer(100_000)!;
defer timer.cancel();
```

### `start_timer`

```c3
fn Timer*? aio::start_timer(ulong timeout_us)
```

Starts a timer for the current task.

Example:

```c3
Timer* timer = aio::start_timer(100_000)!;
defer timer.cancel();
```

### `Timer.cancel`

```c3
fn void Timer.cancel(&self)
```

Cancels and frees the timer.

This function:

1. Marks the timer inactive.
2. Clears the target task.
3. Cancels the internal timer task.
4. Frees the timer object.

Example:

```c3
Timer* timer = aio::start_timer(100_000)!;
defer timer.cancel();

do_something_that_may_timeout()!;
```

## Typical Timeout Pattern

```c3
fn void? operation_with_timeout()
{
    Timer* timer = aio::start_timer(1_000_000)!; // 1 second, if using microseconds
    defer timer.cancel();

    perform_operation()!;
}
```

If `perform_operation()` finishes before the timeout, the deferred `timer.cancel()` disables the timer.

If the timeout expires first, the timer task calls `target.cancel_timeout()`.

## Lifetime Rules

### Stack-allocated waiters

Most waiters are stack-allocated:

```c3
Waiter waiter;
waiter.init(task);
```

This is safe only if the waiter is removed from every external queue before the function returns.

### Stack-allocated sleeps

`sleep()` uses a stack-allocated `Sleep` object.

Therefore, `loop.remove_sleep(&sleep)` must run after the task resumes, even if the sleep was cancelled before its deadline.

### Heap-allocated timers

`Timer` objects are heap-allocated with `localmem.alloc()`.

A returned timer must be cancelled to avoid leaving the internal timer task alive longer than intended.

Use:

```c3
defer timer.cancel();
```

whenever the timer should be scoped to the current operation.

## Recommended Usage

Use `sleep()` when a task simply needs to yield for a duration:

```c3
aio::sleep(50_000)!; // 50 ms
```

Use `Waiter` when implementing a new async primitive:

```c3
Waiter waiter;
waiter.init(current_task()!);

register_waiter(&waiter);

current_task()!.suspend(&waiter);

unregister_waiter(&waiter);

waiter.check()!;
```

Use `Timer` when an operation should cancel the current task after a timeout:

```c3
Timer* timer = aio::start_timer(1_000_000)!;
defer timer.cancel();

operation()!;
```


## Summary

`Waiter` is the core suspend/resume primitive.

`sleep()` builds on `Waiter` by registering a local sleep node with the event loop.

`Timer` builds on `sleep()` by spawning an internal task that cancels a target task after a timeout.

Together, these files provide the foundation for timeout, cancellation, and delayed scheduling behavior in `ext::aio`.
