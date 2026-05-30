# asyncio API Reference

## Event Loop

### Running

```python
asyncio.run(coro, *, debug=False)          # run coroutine as top-level entry point (3.7+)
asyncio.run_until_complete(coro | future)  # run until complete (low-level)

loop = asyncio.get_event_loop()            # get running loop (or create one)
loop = asyncio.get_running_loop()          # get running loop only (raises if none)
loop = asyncio.new_event_loop()
asyncio.set_event_loop(loop)

loop.run_until_complete(coro | future)
loop.run_forever()
loop.stop()
loop.close()
loop.is_running()   # bool
loop.is_closed()    # bool
```

### Scheduling

```python
loop.call_soon(callback, *args)                        # schedule on next iteration
loop.call_soon_threadsafe(callback, *args)             # thread-safe version
loop.call_later(delay, callback, *args)                # schedule after delay (seconds)
loop.call_at(when, callback, *args)                    # schedule at absolute time
loop.time()                                            # -> float, loop's monotonic clock

handle = loop.call_soon(cb)
handle.cancel()                                        # cancel pending callback
```

---

## Coroutines & Tasks

### Awaitables

```python
# Three types of awaitables:
# 1. coroutine   — async def fn() -> ...
# 2. Task        — wraps a coroutine, scheduled immediately
# 3. Future      — low-level promise object
```

### `asyncio.Task`

```python
task = asyncio.create_task(coro, *, name=None)         # schedule coroutine as Task
task = loop.create_task(coro, *, name=None)            # equivalent (low-level)

task.cancel(msg=None)          # request cancellation (raises CancelledError in coro)
task.cancelled()               # bool
task.done()                    # bool
task.result()                  # return value, or raises exception / CancelledError
task.exception()               # exception if raised, else None
task.add_done_callback(cb)     # cb(task) called when done
task.remove_done_callback(cb)
task.get_name()                # str
task.set_name(name)
task.get_coro()                # underlying coroutine object

asyncio.current_task()         # -> Task | None
asyncio.all_tasks(loop=None)   # -> set[Task]
```

### `asyncio.Future`

```python
fut = asyncio.Future(*, loop=None)

fut.set_result(value)
fut.set_exception(exc)
fut.result()                   # blocks until done; raises if exception/cancelled
fut.exception()                # -> BaseException | None
fut.cancel(msg=None)           # -> bool
fut.cancelled()                # bool
fut.done()                     # bool
fut.add_done_callback(cb)
fut.remove_done_callback(cb)
```

---

## Running Concurrently

### `asyncio.gather()`

```python
results = await asyncio.gather(
    coro1, coro2, coro3,       # coroutines or futures
    return_exceptions=False,   # True → exceptions returned as results instead of raised
)
# -> list of results in input order
# if return_exceptions=False and one raises, others are NOT cancelled automatically
```

### `asyncio.TaskGroup` (3.11+)

```python
async with asyncio.TaskGroup() as tg:
    task1 = tg.create_task(coro1())
    task2 = tg.create_task(coro2())
# all tasks complete before exiting; any exception cancels the group
```

### `asyncio.wait()`

```python
done, pending = await asyncio.wait(
    {coro1, coro2, task1},
    timeout=None,
    return_when=asyncio.ALL_COMPLETED,   # | FIRST_COMPLETED | FIRST_EXCEPTION
)
# returns sets of Tasks/Futures, does NOT cancel pending on timeout
```

### `asyncio.wait_for()`

```python
result = await asyncio.wait_for(coro, timeout=5.0)
# raises asyncio.TimeoutError on timeout, and cancels the inner task
```

### `asyncio.as_completed()`

```python
for coro in asyncio.as_completed([coro1, coro2, coro3], timeout=None):
    result = await coro              # yields in completion order
```

### `asyncio.shield()`

```python
result = await asyncio.shield(coro)
# protects inner task from cancellation;
# outer await is cancelled but inner task keeps running
```

---

## Sleeping & Timeouts

```python
await asyncio.sleep(delay, result=None)   # yield control; returns result after delay

# Timeout context manager (3.11+)
async with asyncio.timeout(5.0):
    await some_long_operation()
# raises asyncio.TimeoutError on expiry

async with asyncio.timeout_at(loop.time() + 5.0):
    ...

# Adjust deadline inside the block
async with asyncio.timeout(10.0) as cm:
    cm.reschedule(loop.time() + 20.0)
    cm.deadline()    # -> float | None
    cm.expired()     # -> bool
```

---

## Synchronization Primitives

### `asyncio.Lock`

```python
lock = asyncio.Lock()

async with lock:
    ...

await lock.acquire()
lock.release()
lock.locked()    # bool
```

### `asyncio.Event`

```python
event = asyncio.Event()

await event.wait()      # block until set
event.set()             # wake all waiters
event.clear()           # reset
event.is_set()          # bool
```

### `asyncio.Condition`

```python
cond = asyncio.Condition(lock=None)

async with cond:
    await cond.wait()              # release lock, block, re-acquire on notify
    await cond.wait_for(predicate) # wait until predicate() returns True
    cond.notify(n=1)               # wake n waiters
    cond.notify_all()
```

### `asyncio.Semaphore` / `asyncio.BoundedSemaphore`

```python
sem = asyncio.Semaphore(value=1)
sem = asyncio.BoundedSemaphore(value=1)  # raises if released more than acquired

async with sem:
    ...

await sem.acquire()
sem.release()
sem.locked()    # bool (True when value == 0)
```

### `asyncio.Queue`

```python
q = asyncio.Queue(maxsize=0)       # 0 = unlimited
q = asyncio.LifoQueue(maxsize=0)
q = asyncio.PriorityQueue(maxsize=0)

await q.put(item)                  # block if full
q.put_nowait(item)                 # raises QueueFull if full
item = await q.get()               # block if empty
item = q.get_nowait()              # raises QueueEmpty if empty
q.task_done()                      # signal worker finished an item
await q.join()                     # block until all items processed

q.empty()     # bool
q.full()      # bool
q.qsize()     # int
```

---

## Streams (High-level)

### Open Connection

```python
reader, writer = await asyncio.open_connection(
    host, port,
    ssl=None,
    limit=2**16,    # read buffer limit (bytes)
)
```

### Start Server

```python
server = await asyncio.start_server(
    client_connected_cb,   # async def cb(reader, writer)
    host=None,
    port=None,
    ssl=None,
    backlog=100,
    limit=2**16,
)

async with server:
    await server.serve_forever()

server.close()
await server.wait_closed()
server.sockets                 # list of bound sockets
```

### `StreamReader`

```python
data  = await reader.read(n=-1)        # up to n bytes (-1 = until EOF)
data  = await reader.readexactly(n)    # exactly n bytes, raises IncompleteReadError
line  = await reader.readline()        # up to \n (inclusive)
data  = await reader.readuntil(sep=b"\n")

reader.at_eof()    # bool
reader.exception() # -> Exception | None
```

### `StreamWriter`

```python
writer.write(data: bytes)
writer.writelines(data: list[bytes])
await writer.drain()                   # flush write buffer, wait for backpressure
writer.write_eof()

await writer.wait_closed()
writer.close()
writer.is_closing()                    # bool

writer.get_extra_info("peername")      # (host, port)
writer.get_extra_info("sockname")
writer.get_extra_info("socket")
writer.get_extra_info("ssl_object")    # ssl.SSLObject if TLS
writer.transport                       # underlying Transport
```

---

## Subprocess

```python
proc = await asyncio.create_subprocess_exec(
    "cmd", "arg1", "arg2",
    stdin=asyncio.subprocess.PIPE,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
)

proc = await asyncio.create_subprocess_shell(
    "cmd | grep foo",
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.STDOUT,  # merge stderr into stdout
)

stdout, stderr = await proc.communicate(input=b"data")  # send stdin, read all output
await proc.wait()          # wait for exit
proc.kill()                # SIGKILL
proc.terminate()           # SIGTERM
proc.send_signal(signal.SIGUSR1)
proc.pid                   # int
proc.returncode            # int | None (None if not yet exited)
proc.stdin                 # StreamWriter | None
proc.stdout                # StreamReader | None
proc.stderr                # StreamReader | None
```

---

## Thread / Executor Integration

```python
# Run blocking function in thread pool
result = await loop.run_in_executor(
    executor=None,         # None → default ThreadPoolExecutor
    func,
    *args,
)

# Set default executor
loop.set_default_executor(ThreadPoolExecutor(max_workers=10))

# Schedule coroutine from another thread
fut = asyncio.run_coroutine_threadsafe(coro, loop)   # -> concurrent.futures.Future
fut.result(timeout=5)
fut.cancel()

# Check if currently in async context
asyncio.get_event_loop().is_running()
```

---

## Low-level Transport / Protocol

### Protocol Interface

```python
class MyProtocol(asyncio.Protocol):
    def connection_made(self, transport): ...
    def data_received(self, data: bytes): ...
    def eof_received(self): ...
    def connection_lost(self, exc): ...
    def pause_writing(self): ...
    def resume_writing(self): ...

class MyDatagramProtocol(asyncio.DatagramProtocol):
    def datagram_received(self, data: bytes, addr): ...
    def error_received(self, exc): ...
    def connection_made(self, transport): ...
    def connection_lost(self, exc): ...
```

### Creating Connections (loop-level)

```python
transport, protocol = await loop.create_connection(
    protocol_factory,
    host=None, port=None,
    ssl=None,
    sock=None,             # existing socket
    local_addr=None,
)

transport, protocol = await loop.create_datagram_endpoint(
    protocol_factory,
    local_addr=None,
    remote_addr=None,
    allow_broadcast=False,
)

server = await loop.create_server(
    protocol_factory,
    host=None, port=None,
    ssl=None,
    backlog=100,
    reuse_address=True,
    reuse_port=False,
)
```

### `Transport`

```python
transport.write(data: bytes)
transport.writelines(list_of_data)
transport.write_eof()
transport.close()
transport.abort()                          # discard buffer, close immediately
transport.is_closing()                     # bool
transport.get_extra_info("peername")
transport.get_extra_info("sockname")
transport.get_extra_info("socket")
transport.get_extra_info("ssl_object")
transport.set_write_buffer_limits(high, low)
transport.get_write_buffer_size()          # -> int
transport.pause_reading()
transport.resume_reading()
transport.is_reading()                     # bool
```

---

## Unix Domain Sockets & Pipes (POSIX only)

```python
reader, writer = await asyncio.open_unix_connection(path=None, *, sock=None, ssl=None)
server = await asyncio.start_unix_server(cb, path=None, *, sock=None, ssl=None)

read_transport, protocol  = await loop.connect_read_pipe(proto_factory, pipe)
write_transport, protocol = await loop.connect_write_pipe(proto_factory, pipe)
```

---

## Signals (POSIX only)

```python
loop.add_signal_handler(signal.SIGTERM, callback, *args)
loop.remove_signal_handler(signal.SIGTERM)
```

---

## Debugging & Introspection

```python
loop.set_debug(True)           # enable debug mode (logs slow callbacks, etc.)
loop.get_debug()               # -> bool

asyncio.current_task()         # -> Task | None (running task)
asyncio.all_tasks(loop=None)   # -> set[Task] (all pending tasks)

task.get_stack()               # list of frames
task.print_stack()             # print traceback

# Enable globally via environment
# PYTHONASYNCIODEBUG=1
```

---

## Common Patterns

```python
# Run multiple coroutines concurrently, collect results
results = await asyncio.gather(fetch(url1), fetch(url2), fetch(url3))

# Cancel all tasks on shutdown
async def shutdown():
    tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)

# Producer / consumer with Queue
async def producer(q):
    for item in data:
        await q.put(item)
    await q.put(None)           # sentinel

async def consumer(q):
    while (item := await q.get()) is not None:
        process(item)
        q.task_done()

# Timeout with cleanup
try:
    result = await asyncio.wait_for(coro(), timeout=10.0)
except asyncio.TimeoutError:
    ...

# Run blocking I/O without blocking event loop
data = await loop.run_in_executor(None, requests.get, url)

# Periodic task
async def periodic(interval):
    while True:
        await do_work()
        await asyncio.sleep(interval)

# Wait for first success, cancel others
tasks = [asyncio.create_task(c) for c in coros]
done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
for t in pending:
    t.cancel()
result = done.pop().result()

# Thread-safe event set from worker thread
loop = asyncio.get_event_loop()
event = asyncio.Event()
loop.call_soon_threadsafe(event.set)
```
