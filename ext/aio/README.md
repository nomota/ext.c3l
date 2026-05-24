// ext/aio/README.md

# ext::aio - Async I/O for C3

Coroutine-based asynchronous I/O framework for C3.

`ext::aio` provides an event loop, cooperative tasks, futures, synchronization primitives, TCP streams, UDP datagrams, callback-style protocol handlers, and executor-backed file/path operations.

The design is inspired by Python's `asyncio`, but adapted to C3's explicit fault handling, lightweight task model, and platform-specific I/O backends.

It is built on top of the [fiber](../fiber/README.md) coroutine module.

## Features

| Area | Description |
|------|-------------|
| Event loop | Single-threaded cooperative event loop with task scheduling and I/O polling |
| Tasks | Spawned coroutine tasks with cancellation and join support |
| Futures | Awaitable result container used by tasks, I/O operations, and synchronization primitives |
| Waiter, Sleep, Timer | Waiting primitives and cancelling timer |
| Synchronization | Event, Lock, Semaphore, Queue, Channel-style primitives |
| TCP streams | Async connect, listen, accept, read, write, close |
| UDP datagrams | Async bind, recvfrom, sendto |
| Server | Socket server generation |
| Callback handlers | Event-driven TCP/UDP protocol handler interfaces |
| Executor | Invoking threaded executor for blocking operations |
| File I/O | Executor-backed regular file operations |
| Path operations | Async stat, rename, remove, mkdir, listdir, link, symlink, readlink |
| Cross-platform backend | POSIX epoll/kqueue/select-style backend and Win32 IOCP backend |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.


## Available modules

| Module | Description |
|--------|-------------|
| `ext::aio` | Core event loop, task, future, synchronization, waiter, sleep, timer, stream, datagram, server, and callback handler APIs, thread executor |
| `ext::aio::io` | Platform-specific low-level I/O backend |
| `ext::aio::net` | Platform-specific async net operations |
| `ext::aio::path` | Executor-backed asynchronous filesystem path operations |

## Quick async task example

```c3
import ext::aio;
import ext::debug;

fn void? worker(void* arg)
{
    warn("worker start");

    aio::sleep(1000)!;

    warn("worker done");
}

fn void? main_task(void* arg)
{
    Task* task = aio::spawn_joinable(&worker, null)!;

    task.join()!;

    warn("main task done");
}

fn void main()
{
    aio::run(&main_task);
}
```

## TCP client example

```c3
import ext::aio;
import ext::debug;

fn void? main_task(void* arg)
{
    Stream* stream = aio::stream_connect("127.0.0.1", 8080)!;
    defer stream.free();

    stream.write("hello\n"[..])!;

    char[1024] buf;
    usz n = stream.read(buf[..])!;

    warn("received: %.*s", n, buf.ptr);

    stream.close();
}

fn void main()
{
    aio::run(&main_task);
}
```

## TCP server example

```c3
import ext::aio;

fn void? handle_client(void* arg)
{
    Stream* stream = (Stream*)arg;
    defer stream.free();

    char[4096] buf;

    while (!stream.closed)
    {
        usz n = stream.read(buf[..])!;
        if (n == 0) break;

        stream.write(buf[0:n])!;
    }
}

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

fn void main()
{
    aio::run(&main_task);
}
```

## UDP example

```c3
import ext::aio;
import ext::debug;

fn void? main_task(void* arg)
{
    Datagram* dgram = aio::datagram_bind("127.0.0.1", 9000)!;
    defer dgram.free();

    char[2048] buf;
    DatagramAddr addr;

    while (!dgram.closed)
    {
        usz n = dgram.recvfrom(buf[..], &addr)!;

        String ip = (String)addr.ip[0:addr.ip_len];

        warn("received from %s:%d: %.*s", ip, addr.port, n, buf.ptr);

        dgram.sendto(buf[0:n], ip, addr.port)!;
    }
}

fn void main()
{
    aio::run(&main_task);
}
```

## Callback-style TCP handler

```c3
import ext::aio;
import ext::debug;

struct EchoHandler (TCPHandler)
{
    Stream* stream;
}

fn void? EchoHandler.connection_made(&self, Stream* stream) @dynamic
{
    self.stream = stream;
    warn("connection made");
}

fn void? EchoHandler.data_received(&self, char[] data) @dynamic
{
    self.stream.write(data)!;
}

fn void? EchoHandler.connection_lost(&self, fault exception) @dynamic
{
    warn("connection lost: %s", exception);
}

fn void? main_task(void* arg)
{
    EchoHandler handler = {};

    Task* server = aio::tcp_callback_server(&handler, "127.0.0.1", 8080)!;

    server.join()!;
}

fn void main()
{
    aio::run(&main_task);
}
```

## File I/O

Regular file operations are executor-backed.

This is intentional. On POSIX, regular files are not reliably pollable with epoll/kqueue in the same way sockets and pipes are. On Windows, native overlapped file I/O is possible, but `ext::aio` keeps regular file operations executor-based for API consistency and simpler cancellation/lifetime rules.

```c3
import ext::aio;
import ext::aio::io;

fn void? main_task(void* arg)
{
    Fd fd = io::file_open("hello.txt", "w+")!;
    defer io::file_close(fd);

    io::file_write(fd, "hello file\n"[..])!;
    io::file_seek(fd, 0, 0)!;

    char[128] buf;
    usz n = io::file_read(fd, buf[..])!;
}

fn void main()
{
    aio::run(&main_task);
}
```

## Low-level I/O split

`ext::aio::io` separates pollable I/O from regular file I/O.

| API family | Intended target |
|------------|-----------------|
| `async_read`, `async_write` | sockets, pipes, pollable handles |
| `async_recvfrom`, `async_sendto` | UDP sockets |
| `file_open`, `file_read`, `file_write`, `file_seek`, `file_tell`, `file_truncate`, `file_flush`, `file_size`, `file_close` | regular files |

## Platform support

| Platform | Backend |
|----------|---------|
| Linux | epoll |
| macOS / BSD | kqueue |
| Other POSIX fallback | select-style backend |
| Windows | IOCP for socket/pipe operations, executor-backed regular file operations |

## Documentation

Detailed documentation is split into topic-specific files:

| Document | Description |
|----------|-------------|
| [`docs/EVENT_LOOP.md`](docs/EVENT_LOOP.md) | Event loop lifecycle, scheduling, polling, wakeups |
| [`docs/TASKS.md`](docs/TASKS.md) | Task spawning, joining, cancellation |
| [`docs/FUTURE.md`](docs/FUTURE.md) | Future lifecycle and await semantics |
| [`docs/WAITER.md`](docs/WAITER.md) | Waiters, Sleep, Timer |
| [`docs/SYNCHRONIZATION.md`](docs/SYNCHRONIZATION.md) | Event, Lock, Semaphore, Queue, Channel |
| [`docs/STREAMS.md`](docs/STREAMS.md) | TCP stream API |
| [`docs/DATAGRAMS.md`](docs/DATAGRAMS.md) | UDP datagram API |
| [`docs/SERVER.md`](docs/SERVER.md) | Server API |
| [`docs/HANDLERS.md`](docs/HANDLERS.md) | TCPHandler and UDPHandler callback interfaces |
| [`docs/EXECUTOR.md`](docs/EXECUTOR.md) | Invoking threaded executor for blocking operations |
| [`docs/FILE_IO.md`](docs/FILE_IO.md) | Executor-backed file operations |
| [`docs/PATH.md`](docs/PATH.md) | Filesystem path utilities |

## Error handling

`ext::aio` follows C3 fault-based error handling.

Common faults include:

| Fault | Meaning |
|-------|---------|
| `CANCELLED` | Task or future was cancelled |
| `CLOSED` | Operation was attempted on a closed object |
| `IO_ERROR` | Platform I/O operation failed |
| `POLL_ERROR` | Polling backend reported an error |
| `TIMEOUT` | Operation timed out |
| `TRANSPORT_CLOSED` | Handler transport was closed |
| `PROTOCOL_ERROR` | Protocol handler error |

## Design notes

`ext::aio` uses cooperative scheduling. A task runs until it awaits, sleeps, yields, blocks on a future, or performs an async I/O operation.

Blocking filesystem operations are delegated to thread executor. Socket and pipe operations are handled by platform-specific nonblocking or overlapped I/O backends.

This keeps the event loop responsive while preserving a simple synchronous-looking programming style.

## License

MIT License.



This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

// eof