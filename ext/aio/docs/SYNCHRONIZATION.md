// ext/aio/docs/SYNCHRONIZATION.md 

# ext::aio Synchronization Primitives

`primitives.c3` provides cooperative synchronization primitives built on top of `ext::aio` tasks, waiters, and futures.

The module includes:

| Primitive | Purpose |
|---|---|
| `Lock` | Mutual exclusion for cooperative tasks |
| `Semaphore` | Limit concurrent access to a shared resource |
| `Event` | Broadcast-style state flag backed by a `Future` |
| `Queue` | Bounded multi-producer / multi-consumer FIFO queue |
| `Channel` | One-shot value delivery channel backed by a `Future` |

The primitives are designed for tasks running inside an `EventLoop`. Blocking operations suspend the current task instead of blocking the OS thread.


## Lock

`Lock` is a cooperative mutual exclusion primitive.

```c3
fn Lock*? aio::lock_new();

fn void Lock.init(&self);
fn void Lock.deinit(&self);
fn void Lock.free(&self);

fn bool Lock.is_locked(&self) @inline;

fn void? Lock.acquire(&self) @maydiscard;
fn void? Lock.release(&self) @maydiscard;
```

### Behavior

`Lock.acquire()` suspends the current task while the lock is already held.

`Lock.release()` releases the lock and wakes one waiting task.

If `release()` is called while the lock is not held, it returns `LOCK_ERROR`.

### Heap allocation

```c3
Lock* lock = aio::lock_new()!;
defer lock.free();

lock.acquire()!;

/* critical section */

lock.release()!;
```

### Stack allocation

```c3
Lock lock;
lock.init();
defer lock.deinit();

lock.acquire()!;

/* critical section */

lock.release()!;
```


## Semaphore

`Semaphore` limits the number of tasks that may enter a protected section concurrently.


```c3
fn Semaphore*? aio::semaphore_new(int initial_value = 1);

fn void Semaphore.init(&self, int initial_value = 1);
fn void Semaphore.deinit(&self);
fn void Semaphore.free(&self);

fn int Semaphore.count(&self) @inline;

fn void? Semaphore.acquire(&self) @maydiscard;
fn void Semaphore.release(&self);
```

### Behavior

`Semaphore.acquire()` suspends the current task while the internal counter is `0` or lower.

When acquisition succeeds, the counter is decremented.

`Semaphore.release()` increments the counter and wakes one waiting task.

### Example

```c3
Semaphore sem;
sem.init(3);
defer sem.deinit();

sem.acquire()!;

/* at most 3 tasks may be here at the same time */

sem.release();
```

### Initial value

For heap allocation, a negative initial value is invalid:

```c3
Semaphore*? sem = semaphore_new(-1); // returns INVALID_STATE
```

For stack initialization, negative values are clamped to `0`:

```c3
Semaphore sem;
sem.init(-1); // becomes 0
```

## Event

`Event` is a reusable state flag similar to Python's `asyncio.Event`.


```c3
fn Event*? aio::event_new(bool initial = false);

fn void? Event.init(&self, bool initial = false);
fn void Event.deinit(&self);
fn void Event.free(&self);

fn bool Event.is_set(&self) @inline;

fn void? Event.set(&self) @maydiscard;
fn void? Event.clear(&self) @maydiscard;
fn void? Event.wait(&self) @maydiscard;
```

### Behavior

`Event.wait()` waits until the event is set.

`Event.set()` completes the current future and wakes all tasks waiting on it.

`Event.clear()` replaces the completed future with a new pending future.

This means:

- Once set, all current and future waiters pass immediately.
- After `clear()`, future waiters block again.
- `clear()` does nothing if the event is already pending.

### Example

```c3
Event event;
event.init();
defer event.deinit();

/* waiter task */
event.wait()!;

/* signaler task */
event.set()!;
```

### Initial state

```c3
Event event;
event.init(true); // already set
```

A task calling `event.wait()` on this event will continue immediately.

## Queue

`Queue` is a bounded FIFO queue for passing `void*` values between tasks.

It is waiter-based instead of future-based because each `put()` or `get()` operation needs an independent cancellation-safe wait token.

```c3
fn Queue*? aio::queue_new(sz capacity = QUEUE_CAP_DEFAULT);

fn void? Queue.init(&self, sz capacity = QUEUE_CAP_DEFAULT) @maydiscard;
fn void Queue.deinit(&self);
fn void Queue.free(&self);

fn sz Queue.size(&self) @inline;
fn bool Queue.empty(&self) @inline;
fn bool Queue.full(&self) @inline;
fn sz Queue.maxsize(&self) @inline;
fn bool Queue.is_closed(&self) @inline;

fn void Queue.close(&self);

fn void? Queue.put(&self, void* item) @maydiscard;
fn void*? Queue.get(&self);

fn void? Queue.put_nowait(&self, void* item) @maydiscard;
fn void*? Queue.get_nowait(&self);
```

### Capacity

If `capacity` is `0`, the queue uses `QUEUE_CAP_DEFAULT`.

```c3
Queue* q = aio::queue_new()!;     // capacity = 64
Queue* q2 = aio::queue_new(128)!; // capacity = 128
```

### Blocking operations

`Queue.put()` suspends while the queue is full.

`Queue.get()` suspends while the queue is empty.

Both operations resume when the opposite side makes progress:

- `put()` wakes one getter.
- `get()` wakes one putter.

### Non-blocking operations

`Queue.put_nowait()` returns immediately.

It fails with:

- `QUEUE_CLOSED` if the queue is closed
- `QUEUE_FULL` if the queue is full

`Queue.get_nowait()` returns immediately.

It fails with:

- `QUEUE_CLOSED` if the queue is closed and empty
- `QUEUE_EMPTY` if the queue is open and empty

### Close behavior

`Queue.close()` marks the queue as closed and cancels all waiting getters and putters with `QUEUE_CLOSED`.

After closing:

- `put()` fails with `QUEUE_CLOSED`
- `put_nowait()` fails with `QUEUE_CLOSED`
- `get()` continues to drain already queued items
- `get()` fails with `QUEUE_CLOSED` once the queue is empty
- `get_nowait()` returns queued items until empty, then fails with `QUEUE_CLOSED`

### Producer example

```c3
fn void? producer(void* arg)
{
    Queue* q = (Queue*)arg;

    for (int i = 0; i < 10; i++)
    {
        q.put((void*)(isz)i)!;
    }

    q.close();
}
```

### Consumer example

```c3
fn void? consumer(void* arg)
{
    Queue* q = (Queue*)arg;

    while (true)
    {
        if (catch err = q.get())
        {
            if (err == QUEUE_CLOSED) break;
            return err~;
        }

        void* item = q.get()!!;

        /* process item */
    }
}
```

A more typical pattern is to avoid calling `get()` twice by assigning the result directly according to the surrounding C3 optional/fault style used in the project.

```c3
fn void? consumer(void* arg)
{
    Queue* q = (Queue*)arg;

    while (true)
    {
        void* item = q.get()!;
        /* process item */
    }
}
```

Use an explicit `catch` branch when `QUEUE_CLOSED` should be treated as normal termination.

### Queue ownership

The queue stores raw `void*` values.

It does not own or free the pointed-to objects. The producer and consumer must define the ownership rule.

## Channel

`Channel` is a future-based one-shot channel.

It delivers exactly one value.

```c3
fn Channel*? aio::channel_new();

fn void? Channel.init(&self);
fn void Channel.deinit(&self);
fn void Channel.free(&self);

fn bool Channel.ready(&self) @inline;
fn bool Channel.is_closed(&self) @inline;

fn void Channel.close(&self);

fn void? Channel.send(&self, void* value) @maydiscard;
fn void*? Channel.recv(&self);
fn void*? Channel.recv_nowait(&self);
```

### Behavior

`Channel.send()` completes the channel with one value.

`Channel.recv()` waits until the value is available or the channel is closed.

`Channel.recv_nowait()` returns immediately.

A channel cannot be reused after a successful `send()`.

### Faults

`send()` fails with:

- `CHANNEL_CLOSED` if the channel has no future
- `CHANNEL_USED` if the channel was already completed

`recv()` fails with:

- `CHANNEL_CLOSED` if the channel has no future
- the future's cancellation fault if the channel was closed

`recv_nowait()` fails with:

- `CHANNEL_CLOSED` if the channel has no future
- `QUEUE_EMPTY` if no value is ready yet

`recv_nowait()` uses `QUEUE_EMPTY` for the "not ready yet" case even though this is a channel operation.

### Example

```c3
Channel ch;
ch.init();
defer ch.deinit();

/* sender task */
ch.send((void*)123)!;

/* receiver task */
void* value = ch.recv()!;
```

### One-shot rule

```c3
ch.send((void*)1)!;
ch.send((void*)2)!; // CHANNEL_USED
```

Use `Queue` instead of `Channel` when multiple values must be sent over time.

## Choosing a primitive

| Need | Use |
|---|---|
| Protect one critical section | `Lock` |
| Allow up to N concurrent tasks | `Semaphore` |
| Wake many tasks when a condition becomes true | `Event` |
| Pass multiple values between producers and consumers | `Queue` |
| Deliver one value exactly once | `Channel` |

## Lifecycle summary

Heap-allocated objects:

```c3
Lock* lock = aio::lock_new()!;
defer lock.free();

Semaphore* sem = aio::semaphore_new(1)!;
defer sem.free();

Event* event = aio::event_new()!;
defer event.free();

Queue* q = aio::queue_new(64)!;
defer q.free();

Channel* ch = aio::channel_new()!;
defer ch.free();
```

Stack-allocated objects:

```c3
Lock lock;
lock.init();
defer lock.deinit();

Semaphore sem;
sem.init(1);
defer sem.deinit();

Event event;
event.init();
defer event.deinit();

Queue q;
q.init(64)!;
defer q.deinit();

Channel ch;
ch.init()!;
defer ch.deinit();
```

## Cancellation and deinitialization

The primitives cancel suspended waiters during deinitialization or close operations.

| Primitive | Deinitialization behavior |
|---|---|
| `Lock` | Cancels all waiters with `CANCELLED` |
| `Semaphore` | Cancels all waiters with `CANCELLED` |
| `Event` | Cancels and frees the backing future |
| `Queue` | Closes the queue and cancels get/put waiters with `QUEUE_CLOSED` |
| `Channel` | Cancels and frees the backing future with `CHANNEL_CLOSED` |

Do not free a primitive while another task may still use it unless that lifetime is externally synchronized.

## Notes

These primitives are cooperative. They coordinate `ext::aio` tasks, not OS threads.

They assume that the current code runs inside an active `EventLoop` task context. Blocking operations call `current_task()` and suspend that task through a `Waiter` or `Future`.

For repeated producer/consumer communication, prefer `Queue`.

For one-shot result delivery, prefer `Channel`.

For reusable notification, prefer `Event`.

// eof