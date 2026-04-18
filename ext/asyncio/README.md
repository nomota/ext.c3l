# ext::asyncio for C3

This is a C3 port of Python's asyncio library. It follows [Python's API](PythonAPI.md), as it is the most approachable among libraries of its kind.
It is based on C3's [fiber](../fiber/README.md) coroutine.
Asynchronous I/O by IOCP on Win32, kqueue/kevent on macOS(BSD family) and io_uring on Linux.

### Available module

| Module | Description |
|--------|-------------|
| `ext::asyncio` | Python asyncio-similar operations: Future, Task, EventLoop, Stream, Datagram, Transport, Protocol, DatagramProtocol |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

### Key concepts

* `Future` is a value container that will be filled at some point in the future. The primary operation on a future is `.await()`, which blocks until another coroutine calls `.set_value()` to fill it.
* `Task` is a handle for an independently running coroutine. A task can be `.await()`ed to wait for its completion. If not awaited, a task can finish silently and `autofree` itself. Within a task, `.set_result(void*)` can be called on a future.
* `EventLoop` is a scheduler. All activity is driven by the scheduler. It provides `.create_future()` and `.create_task()`. An event loop can be started with `.run()`, and `.gather()` can be used to join and free multiple tasks.
* `EventLoop` also handles other scheduling operations such as `.sleep()`, `.wait_for()`, and `.call_later()`.
* For finer concurrency control, `Lock`, `Queue`, `Semaphore`, `Event`, or `Channel` can be used.
* `TaskGroup` allows multiple tasks to be created via `.create_task()` and joined via `.wait()`.
* For networking, `Stream` handles TCP and `Datagram` handles UDP. Use `.open_connection()` to obtain a client `Stream`, and `.open_datagram()` to obtain a client `Datagram`.
* `Server` is a TCP server. Use `.start_server()` to create one, then call `.serve_forever()` to run it indefinitely.
* For UDP, use `.bind_datagram()` to obtain a server-side `Datagram`. A plain UDP `.socket()` can then call `.sock_sendto()` or `.sock_recvfrom()` to communicate with the server `Datagram`.
* Event-driven, callback-style communication is achieved by implementing interfaces such as `Protocol` (for TCP) or `DatagramProtocol` (for UDP). These interfaces require implementing reactive methods like `.connection_made()`, `.data_received()`, `.connection_lost()`, and `.error_received()`. Actual data transfer is performed through a `Transport`.


### Files

* [loop.c3](loop.c3): EventLoop, scheduling
* [future.c3](future.c3): Future, Task
* [primitives.c3](primitives.c3): Lock, Queue, Semaphore, Event, Channel
* [taskgroup.c3](taskgroup.c3): TaskGroup
* [io.posix.c3](io.posix.c3): async io for posix
* [io.win32.c3](io.win32.c3): async io for windows
* [net.posix.c3](net.posix.c3): net sockets for posix
* [net.win32.c3](net.win32.c3): net sockets fo windows
* [stream.c3](stream.c3): TCP Stream
* [datagram.c3](datagram.c3): UDP Datagram
* [protocol.c3](protocol.c3): Protocol, DatagramProtocol, Transport

### API functions

`EventLoop` functions

```c3 
import asyncio;
import ext::mem;

void asyncio::set_eventloop_config(usz taskq=1024, usz timerq=512, usz soonq=512); // embedded server: 64,16,32, busy server:4096,2048,2048

void mem::set_allocator(Allocator alloc); // set allocator to be used in across `asyncio`

alias Coroutine as fn void(); // a fiber coroutine function

void asyncio::run(Coroutine main_coro); // run a coroutine under an event loop

EventLoop* loop = asyncio::new_event_loop();

void loop.free(); // prevent leak

void asyncio::set_event_loop(EventLoop* loop); // set this loop as running loop

EventLoop* loop = asyncio::get_running_loop();

void loop.run_forever(); // Run the loop forever until stop() is called. Unlike run(), no initial task is registered; the caller sets up tasks beforehand.

bool b = loop.is_running(); // Return true if the loop is currently running (between run/run_forever and stop/close).

bool b = loop.is_closed(); // Return true if close() has been called on this loop.

void loop.stop(); // Stop the loop after the current iteration finishes. If the loop is running run_forever(), it will exit cleanly. If it is inside run(), the current task batch finishes first.

void loop.close(); // Release all resources held by the loop. Must be called after run() / run_forever() returns. Cancels any pending callback handles.
```

Scheduling callback functions

```c3 
import asyncio;

void? asyncio::sleep_zero() @maydiscard; // yield to scheduler

ulong asyncio::clock_now(); // micro seconds

void? asyncio::sleep_us(ulong micro_seconds) @maydiscard;

void? asyncio::sleep_ms(ulong mili_seconds) @maydiscard;

void? asyncio::sleep(double seconds) @maydiscard;

ulong loop.time(); // Return the loop-internal monotonic clock value in microseconds. Use this instead of raw clock_now() when scheduling relative to the loop.

alias CompletedCallback = fn void(Task*, usz);

void? asyncio::as_completed(Task** tasks, usz count, CompletedCallback cb) @maydiscard; // Invoke cb in completion order. Returns CANCELLED_ERR if the calling task is cancelled while waiting.
 
alias SoonCallback = fn void(void*);

// CallbackHandle: Returned by call_soon() / call_lat()er / call_at(). The caller can cancel() it before it fires.

void cb_handle.cancel(); // Cancel this callback before it fires. Safe to call even if already fired or cancelled.

void cb_handle.free(); // prevent memory leak 

CallbackHandle* cb_handle = loop.call_soon(SoonCallback cb, void* arg = null); // register a callback function to be called soon.

CallbackHandle* cb_handle = loop.call_later_us(ulong delay_us, SoonCallback cb, void* arg = null); // Schedule cb(arg) to be called after delay_us microseconds.

fn CallbackHandle* cb_handle = loop.call_later_ms(ulong delay_ms, SoonCallback cb, void* arg = null); // Call cb(arg) after delay_ms mili_seconds

CallbackHandle* cb_handle = loop.call_later(double delay_sec, SoonCallback cb, void* arg = null);

CallbackHandle* cb_handle = loop.call_at_us(ulong when_us, SoonCallback cb, void* arg = null); // Schedule cb(arg) to be called at an absolute loop timestamp (microseconds). Use loop.time() to get the current timestamp.

CallbackHandle* cb_handle = loop.call_at(double when_sec, SoonCallback cb, void* arg = null); // at absolute time. use loop.time() to set when_sec 

CallbackHandle* cb_handle = loop.call_soon_threadsafe(SoonCallback cb, void* arg = null); // Thread-safe variant of call_soon. Safe to call from any OS thread; the callback will be executed on the event-loop thread.

```

Future functions

```c3 
import asyncio;

Future* future = loop.create_future(); // Allocate a new Future already bound to a loop. Equivalent to Python's loop.create_future().

void future.free(; // prevent memory leak

void future.defer_free(); // wait until the future gets done, and free it

bool b = future.done(); // whether it's done

bool b = future.cancelled(); // whether it's cancelled

bool b = future.cancelling(); // whether it's cancelling

void? future.set_result(void* data) @maydiscard; // data must be an allocated memory, to be free'd later, or null for simply signalling done

void*? future.get_result(); // result must be free'd by caller

void future.set_exception(fault err);

fault f = future.get_error(); 

void future.cancel(String msg = "");

void future.add_done_callback(Callback cb, CallbackCtx ctx = null); // on completion, cb(future, ctx) gets called

usz num_removed = future.remove_done_callback(Callback cb);

EventLoop* loop = future.get_loop();

void*? future.await() @maydiscard; // Suspend the current Task until this Future completes or get .set_result()'ed. Returns CANCELLED_ERR if the task was cancelled while waiting.

void? f = future.wait_for(ulong timeout_us) @maydiscard; // wait with microseconds timeout, returns TIMEOUT, CANCELLED_ERR, or other fault

Future* proxy_fut = asyncio::shield(Future* fut); // Protect fut from external cancellation; returns a new proxy Future

usz? asyncio::wait_any(Future** futs, usz count) @maydiscard; // Return the index of the first Future to complete. Returns CANCELLED_ERR if the calling task is cancelled while waiting.
```

Task functions

```c3 
import asyncio;

// Task inherits Future, and all Future methods are applicable to Task

Task* task = asyncio::EventLoop.create_task(&self, Coroutine coro, String name = "", usz stack_size = 128_000, bool autofree = false, void* arg = null);

void asyncio::task_return(void* value); // Set the return value of a task (call at the end of a coroutine). Must be an allocated memory, to be free'd later

void task.free(); // prevent memory leak

void task.defer_free(); // wait and free

String name = task.get_name();

void task.set_name(String name);

void task.cancel(String msg = "");

void task.uncancel();

void*? task.await() @maydiscard; // Suspend current Task until this Task completes, or get .set_result()'ed

void? asyncio::gather(Task*[] tasks) @maydiscard; // Wait for all Tasks to complete. Returns CANCELLED_ERR if the calling task is cancelled while waiting.
```

Primitives for controlling parallel tasks

```c3 
import asyncio;

Lock* lock = asyncio::lock_new();
void lock.free(); // prevent memory leak.
bool b = lock.is_locked();
void lock.acquire();
void lock.release();

Semaphore* sem = asyncio::semaphore_new(int initial_value); // max number of parallel tasks
void sem.free(); // prevent leak
int n = sem.count();
void sem.acquire();
void sem.release();

Event* event = asyncio::event_new();
void event.free(); // prevent leak 
bool b = event.is_set();
void event.set(); // set event waiting, wake all
void event.clear();
void? event.wait() @maydiscard; // wait until event set

Queue* queue = asyncio::queue_new(usz capacity = QUEUE_CAP_DEFAULT);
void queue.free(); // prevent leak 
usz n = queue.size();
bool b = queue.empty();
bool b = queue.full();
usz n = queue.maxsize(); // capacity
void queue.put(void* item); // enqueue
void* item = queue.get(); // dequeue
void*? item = queue.get_nowait(); // dequeue without blocking, returns QUEUE_EMPTY if empty
void? queue.put_nowait(void* item) @maydiscard; // enqueue without blocking, returns QUEUE_FULL if full

Channel* chan = asyncio::channel_new(); // single item queue.
void chan.free(); // prevent memory leak 
void chan.send(void* value); // send and wake up the receiver, value must be heap allocated
void*? value = chan.recv(); // wait and receive, value needs to be free'd
bool b = chan.ready();
```

Task group 

```c3
import asyncio;

TaskGroup* group = asyncio::taskgroup_new();

void group.free(); // prevent leak

Task* task = group.create_task(Coroutine coro, String name = "tg_task", uint stack_size = 64_000, void* arg=null);

void? group.wait() @maydiscard;
```

I/O functions

```c3 
import asyncio;

bool asyncio::set_nonblocking(int fd); // sets a socket/file descripter nonblocking

usz? n = asyncio::async_read(int fd, void* buf, usz len);

usz? n = asyncio::async_write(int fd, void* buf, usz len);

usz? n = asyncio::async_recvfrom(int fd, void* buf, usz len, char* ip_str, usz* ip_len, ushort* port); // UDP

usz? n = asyncio::async_sendto(int fd, void* buf, usz len, char* ip_str, ushort port); // UDP

int? fd = asyncio::open_file(String path, String mode);

void asyncio::close_file(int fd);

long pos = asyncio::io_seek(int fd, long pos, int whence);

long pos = asyncio::io_tell(int fd);

int r = asyncio::io_truncate(int fd, long pos); // return 0 on success, -1 on failure

void asyncio::io_flush(int fd);

long size = asyncio::io_size(int fd);

int in = asyncio::stdin();
int out = asyncio::stdout();
int err = asyncio::stdout();
```

Net functions

```c3 
import asyncio;

int sock = asyncio::socket(String ipversion, String proto); // ipversion="IPV4"|"IPV6", proto="TCP"|"UDP"

void asyncio::socket_close(int sock);

Stream*? stream = asyncio::open_connection(String host_str, ushort port); // TCP client

Datagram*? dgram = asyncio::open_datagram(String host_str, ushort port); // UDP client

Datagram*? server_dgram = bind_endpoint(String host_str, ushort port); // UDP server

alias ClientHandler = fn void(Stream*);

Server*? server = asyncio::start_server(ClientHandler handler, String host_str, ushort port); // TCP server 

void server.free(); // prevent leak

void? server.serve_forever() @maydiscard;

void server.stop();
```

Streams

```c3 
import asyncio;

bool b = stream.at_eof() @inline;

usz? n = stream.read(char[] buf); 

usz? n = stream.read_any(char[] buf);

usz? n = stream.read_until(char delim, char[] buf);

usz? n = stream.readline(char[] buf);

usz? n = stream.write(char[] buf);

usz? n = stream.writef(String fmt, args...); 
Stream*? stream = asyncio::open_file_stream(String path, String mode);

void stream.close();

Stream* in = asyncio::stdin_stream();
Stream* out = asyncio::stdout_stream();
Stream* err = asyncio::stderr_stream();
```

Datagram 

```c3 
import asyncio;

usz n = dgram.sendto(char[] data, char[] ip, short port);

usz n = dgram.recvfrom(char[] data, char[] ip, usz* ip_len, ushort* port);

usz n = loop.sock_sendto(&self, int sock_fd, char[] data, char[] ip, short port);

usz n = loop.sock_recvfrom(&self, int sock_fd, char[] data, char[] ip, usz* ip_len, ushort* port);

void dgram.close();
```


Transport & Protocol

```c3 
import asyncio;

// User should implement following protocol interfaces to get proper transport or server

interface Protocol {
    fn void connection_made(Transport* transport);
    fn void data_received(char[] data);
    fn void connection_lost(fault exception);
}

interface DatagramProtocol {
    fn void connection_made(Transport* transport);
    fn void datagram_received(char[] buf, char[] ip, ushort port);
    fn void error_received(fault exception);
    fn void connection_lost(fault exception) @optional;
}

Transport* trans = loop.create_connection(Protocol proto, String host, ushort port); // tcp client

Server*? server = loop.create_server(Protocol proto, String host, ushort port); // tcp server

Transport* trans = loop.create_datagram_endpoint(DatagramProtocol proto, String host, ushort port);

void trans.free(); // prevent leak

usz? n = trans.write(char[] data); // tcp

void trans.sendto(char[] data, char[] ip, short port); // udp

void trans.close();
```

### Examples

* [../../examples/asyncio/sample1.c3](../../examples/asyncio/sample1.c3)
  * asyncio::run(), asyncio::gather(), asyncio::get_running_loop(),  loop.create_task(), asyncio::sleep_ms()
* [../../examples/asyncio/sample2.c3](../../examples/asyncio/sample2.c3)
  * loop.create_future(), future.add_done_callback(), future.wait_for()
* [../../examples/asyncio/sample3.c3](../../examples/asyncio/sample3.c3)
  * loop.time(), loop.time(), loop.call_soon(), loop.call_later(), loop.call_at(), asyncio::sleep(), loop.run_forever(), loop.is_closed(), loop.close()
* [../../examples/asyncio/sample4.c3](../../examples/asyncio/sample4.c3)
  * future.set_result(), CallbackHandle.cancel()
* [../../examples/asyncio/sample5.c3](../../examples/asyncio/sample5.c3)
  * loop.call_soon_threadsafe()
* [../../examples/asyncio/sample6.c3](../../examples/asyncio/sample6.c3)
  * asyncio::sleep_zero(), lock.aquire(), lock.release(), queue.put(), queue.get() 
* [../../examples/asyncio/sample7.c3](../../examples/asyncio/sample7.c3)
  * semaphore.acquire(), semaphore.release(), event.wait(), event.set(), channel.send(), channel.recv()
* [../../examples/asyncio/sample8.c3](../../examples/asyncio/sample8.c3)
  * task.set_exception(), TaskGroup.wait()
* [../../examples/asyncio/sample9.c3](../../examples/asyncio/sample9.c3)
  * EchoServer(Protocol), EchoClient(Protocol)
* [../../examples/asyncio/sample10.c3](../../examples/asyncio/sample10.c3)
  * asyncio::start_server(), server.serve_forever(), asyncio::open_connection(), stream.readline(), stream.write()
* [../../examples/asyncio/sample11.c3](../../examples/asyncio/sample11.c3)
  * UdpEchoServer(DatagramProtocol), UdpEchoClient(DatagramProtocol)
* [../../examples/asyncio/sample12.c3](../../examples/asyncio/sample12.c3)
  * asyncio::bind_endpoint(), datagram.recvfrom(), datagram.sendto(), loop.sock_sendto(), loop.sock_recvfrom()


This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

