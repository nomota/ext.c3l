// ext/aio/docs/TASKS.md 

# Tasks

`Task` is the basic unit of asynchronous execution in `ext::aio`.

A task is a coroutine running on the event loop. It starts from a `TaskFn`, can suspend while waiting, and later resumes when the event loop marks it ready again.

Back to [`ext::aio`](../README.md).

## Task function

A task entry function has this type:

```c3
alias TaskFn = fn void?(void*);
```

Example:

```c3
fn void? worker(void* arg)
{
    aio::sleep(1000)!;
}
```

A task may return normally or fail with a fault.

```c3
fn void? worker(void* arg)
{
    if (something_failed())
    {
        return aio::FAILED~;
    }
}
```

## Spawning tasks

Use `aio::spawn()` for detached background tasks.

```c3
aio::spawn(&worker, arg)!;
```

Use `aio::spawn_joinable()` when another task must wait for completion.

```c3
Task* task = aio::spawn_joinable(&worker, arg)!;

task.join();
```

## Detached tasks

Detached tasks are fire-and-forget.

```c3
aio::spawn(&background_worker, null)!;
```

A detached task is automatically cleaned up by the event loop after it finishes, fails, or is cancelled.

You cannot join a detached task. Calling `join()` on a detached task returns `JOIN_DETACHED` error.

Use detached tasks for:

* per-client server handlers
* background cleanup
* periodic maintenance jobs
* work whose result is not needed by the caller

Example:

```c3
fn void? handle_client(void* arg)
{
    Stream* stream = (Stream*)arg;
    defer stream.free();

    // handle connection
}

fn void? server_task(void* arg)
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

## Joinable tasks

Joinable tasks are used when the caller needs to wait for task completion.

```c3
Task* task = aio::spawn_joinable(&worker, null)!;

task.join();
```

A joinable task is not automatically treated as fire-and-forget. The caller should join it or otherwise manage its lifetime.

Use joinable tasks for:

* child work whose completion matters
* concurrent subtasks
* tests
* startup/shutdown sequencing

Example:

```c3
fn void? main_task(void* arg)
{
    Task* a = aio::spawn_joinable(&worker_a)!;
    Task* b = aio::spawn_joinable(&worker_b)!;

    a.join();
    b.join();
}
```

## Joining a task

`join()` waits until the target task finishes, fails, or is cancelled.

```c3
task.join();
```

The current task is suspended while waiting. The event loop remains active and can continue running other tasks.

After `join()` finishes, the joined task is reaped by the loop.

## Task states

A task moves through a small set of states.

| State | Meaning |
|-------|---------|
| `TASK_NEW` | Task object has been created. |
| `TASK_READY` | Task is ready to run. |
| `TASK_RUNNING` | Task is currently executing. |
| `TASK_WAITING` | Task is suspended and waiting for something. |
| `TASK_DONE` | Task completed successfully. |
| `TASK_CANCELLED` | Task was cancelled or timed out. |
| `TASK_FAILED` | Task returned an error fault other than cancellation or timeout. |

Most user code does not need to inspect task states directly. Prefer `join()` and normal fault handling.

## Waiting and suspension

A task becomes waiting when it waits on something asynchronous, such as:

* sleep
* future
* waiter
* lock
* event
* semaphore
* queue
* channel
* stream read/write
* datagram recv/send
* executor-backed operation

Example:

```c3
fn void? worker(void* arg)
{
    aio::sleep(1000)!;

    char[1024] buf;
    usz n = stream.read(buf[..])!;
}
```

While this task is waiting, other tasks can run.

## Yielding

Use `aio::yield()` to let other ready tasks run.

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

Use this in CPU-heavy loops. Ordinary async operations already yield when they block.

## Cancellation

A task can be cancelled by the loop or by user code.

```c3
task.cancel();
```

Cancellation requests are delivered through the task's current wait point when possible.

A task should use `defer` for cleanup:

```c3
fn void? worker(void* arg)
{
    Resource* r = open_resource()!;
    defer r.free();

    while (true)
    {
        do_work()!;
        aio::sleep(100)!;
    }
}
```

When the task is cancelled, cleanup code should still run as control unwinds through faults.

## Checking task result

`Task.check()` reports a stored task error if one exists.

```c3
task.check()!;
```

It returns a fault if the task failed or was cancelled.

Common task-level faults:

| Fault | Meaning |
|-------|---------|
| `CANCELLED` | Task was cancelled. |
| `TIMEOUT` | Task timed out. |
| `FAILED` | Generic task failure. |
| `INVALID_STATE` | Invalid state transition or operation. |

## Failure behavior

If a task entry function returns a fault:

```c3
fn void? worker(void* arg)
{
    return aio::FAILED~;
}
```

then the task becomes failed, except for cancellation-style faults:

| Returned fault | Final state |
|----------------|-------------|
| `CANCELLED` | `TASK_CANCELLED` |
| `TIMEOUT` | `TASK_CANCELLED` |
| any other fault | `TASK_FAILED` |

A failed task wakes a joiner, if one is waiting.

## Task groups

`TaskGroup` manages a set of joinable tasks together.

It is useful when a component spawns multiple child tasks and later needs to cancel or join all of them during shutdown.

A task group always spawns joinable tasks.

## Initializing a task group

### `TaskGroup.init`

```c3
fn void TaskGroup.init(&self, EventLoop* loop = null)
```

Initializes a task group.

If `loop` is `null`, the current event loop is used.

```c3
TaskGroup group;
group.init();
defer group.free();
```

With an explicit loop:

```c3
EventLoop* loop = aio::current_loop()!;

TaskGroup group;
group.init(loop);
defer group.free();
```

## Freeing a task group

### `TaskGroup.free`

```c3
fn void TaskGroup.free(&self)
```

Frees the internal task list and marks the group as closed.

```c3
group.free();
```

A task group should normally be joined or cancelled before it is freed.

## Spawning tasks in a group

### `TaskGroup.spawn`

```c3
fn Task*? TaskGroup.spawn(&self, TaskFn entry, void* arg = null)
```

Spawns a joinable task on the group's event loop and records it in the group.

```c3
Task* task = group.spawn(&worker, arg)!;
```

If the group is closed or has no event loop, `INVALID_STATE` is returned.

Use `TaskGroup.spawn()` when the task should be managed as part of the group's lifetime.

## Cancelling all tasks in a group

### `TaskGroup.cancel_all`

```c3
fn void TaskGroup.cancel_all(&self)
```

Cancels every task in the group that is not already done, cancelled, or failed.

```c3
group.cancel_all();
```

This only requests cancellation. Use `join_all()` afterward to wait until all tasks have actually finished.

```c3
group.cancel_all();
group.join_all();
```

## Joining all tasks in a group

### `TaskGroup.join_all`

```c3
fn void? TaskGroup.join_all(&self)
```

Joins every task currently recorded in the group.

Tasks are removed from the group as they are joined.

```c3
group.join_all();
```

If one or more tasks fail, `join_all()` remembers the first fault and returns it after all tasks have been joined.

This means `join_all()` still drains the group even when a child task fails.

## Cancel and join

### `TaskGroup.cancel_and_join`

```c3
fn void? TaskGroup.cancel_and_join(&self)
```

Cancels all tasks and then joins them.

```c3
group.cancel_and_join();
```

If joining returns `CANCELLED`, it is treated as normal shutdown and suppressed. Other faults are returned.

## Task group example

```c3
fn void? worker(void* arg)
{
    int id = (int)(isz)arg;

    while (true)
    {
        do_work(id)!;
        aio::sleep(100)!;
    }
}

fn void? main_task(void* arg)
{
    TaskGroup group;
    group.init();
    defer group.free();

    group.spawn(&worker, (void*)1)!;
    group.spawn(&worker, (void*)2)!;
    group.spawn(&worker, (void*)3)!;

    aio::sleep(1000)!;

    group.cancel_and_join();
}
```

## Task group shutdown pattern

Use this pattern when a component owns multiple child tasks:

```c3
self.tasks.cancel_all();
self.tasks.join_all();
self.tasks.free();
```

Or use the combined helper:

```c3
self.tasks.cancel_and_join();
self.tasks.free();
```

This pattern is useful in servers, protocol handlers, connection pools, and background services.

## Task group failure behavior

`join_all()` joins all tasks even if one of them fails.

The first observed fault is returned after all tasks have been removed from the group.

```c3
if (catch err = group.join_all())
{
    warn("task group failed: %s", err);
    return err~;
}
```

`cancel_and_join()` suppresses `CANCELLED`, because cancellation is the expected result during shutdown.

```c3
if (catch err = group.cancel_and_join())
{
    warn("shutdown failed: %s", err);
    return err~;
}
```

## Resource ownership

Be explicit about ownership when passing pointers to tasks.

Detached task example:

```c3
Stream* client = server.accept()!;

aio::spawn(&handle_client, client)!;
```

The spawned task should own and free the client stream:

```c3
fn void? handle_client(void* arg)
{
    Stream* stream = (Stream*)arg;
    defer stream.free();

    // use stream
}
```

For joinable tasks, the caller usually owns the `Task*` until `join()` completes.

For task groups, the group owns the list of task handles until `join_all()` or `cancel_and_join()` drains the group.

## Common patterns

### Run child tasks concurrently

```c3
fn void? main_task(void* arg)
{
    Task* a = aio::spawn_joinable(&load_config)!;
    Task* b = aio::spawn_joinable(&connect_service)!;

    a.join();
    b.join();
}
```

### Run child tasks with a task group

```c3
fn void? main_task(void* arg)
{
    TaskGroup group;
    group.init();
    defer group.free();

    group.spawn(&load_config)!;
    group.spawn(&connect_service)!;

    group.join_all();
}
```

### Start a periodic background task

```c3
fn void? heartbeat(void* arg)
{
    while (true)
    {
        send_heartbeat()!;

        aio::sleep(1000)!;
    }
}

fn void? main_task(void* arg)
{
    aio::spawn(&heartbeat)!;

    run_application()!;
}
```

### Cancel a task

```c3
fn void? main_task(void* arg)
{
    Task* task = aio::spawn_joinable(&worker)!;

    aio::sleep(500)!;

    task.cancel();

    task.join();
}
```

### Cancel a task group

```c3
fn void? main_task(void* arg)
{
    TaskGroup group;
    group.init();
    defer group.free();

    group.spawn(&worker_a)!;
    group.spawn(&worker_b)!;

    aio::sleep(500)!;

    group.cancel_and_join();
}
```

## Practical rules

* Use `spawn()` for detached background work.
* Use `spawn_joinable()` when you need completion ordering.
* Use `TaskGroup` when one owner must manage many child tasks.
* Do not join detached tasks.
* Do not let a task join itself.
* Join or cancel-and-join task group tasks before freeing the group.
* Use `defer` for resource cleanup inside tasks.
* Use `aio::yield()` in long CPU loops.
* Do not perform long blocking work directly in a task.
* Pass ownership clearly when giving pointers to detached tasks.
* Prefer normal optional/fault handling over manually inspecting task state.

## Related documents

| Document | Description |
|----------|-------------|
| [`EVENT_LOOP.md`](EVENT_LOOP.md) | Event loop lifecycle and scheduling model |
| [`FUTURE.md`](FUTURE.md) | Future lifecycle and await semantics |
| [`WAITER.md`](WAITER.md) | Waiters, sleep, and timers |
| [`SYNCHRONIZATION.md`](SYNCHRONIZATION.md) | Event, Lock, Semaphore, Queue, Channel |
| [`EXECUTOR.md`](EXECUTOR.md) | Thread executor for blocking work |

// eof
