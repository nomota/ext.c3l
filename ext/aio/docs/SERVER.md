// ext/aio/docs/SERVER.md 

# ext::aio Server

TCP server support for `ext::aio`.

This module provides a small async TCP server API built on top of `Stream`, `Task`, and `TaskGroup`.


## Handler type

```c3
alias ClientHandler @local = fn void?(Stream*);
```

A server handler receives one accepted client `Stream*`.

The handler runs in its own task. When the handler returns or fails, the stream is removed from the server client list and freed automatically.

```c3
fn void? handle_client(Stream* stream)
{
    char[1024] buf;

    usz n = stream.read(buf[..])!;
    stream.write(buf[0:n])!;
}
```

## Start a server

### `start_server`

```c3
fn Server*? aio::start_server(ClientHandler handler, String host, ushort port, int backlog = net::DEFAULT_BACKLOG)
```

Creates a TCP listening socket and returns a `Server`.

The server is not accepting clients yet. Call `serve_forever()` to start accepting connections.

```c3
Server* server = aio::start_server(&handle_client, "127.0.0.1", 9000)!;
defer server.free();

server.serve_forever()!;
```

## Serving

### `Server.serve_forever`

```c3
fn void? Server.serve_forever(&self) @maydiscard
```

Accepts clients in a loop until the server is closed.

Each accepted socket is wrapped in a `Stream` and passed to the configured client handler in a task managed by the server.

```c3
server.serve_forever()!;
```

If the server is already closed, `SERVER_CLOSED` is returned.

`serve_forever()` normally runs until `close()` is called or the serving task is cancelled.

## Closing

### `Server.close`

```c3
fn void Server.close(&self)
```

Closes the listening socket, cancels the serving task if one exists, and closes all active client streams.

```c3
server.close();
```

Calling `close()` more than once is safe.

### `Server.wait_closed`

```c3
fn void? Server.wait_closed(&self)
```

Waits until all client tasks finish.

Call this after `close()` and before `free()`.

```c3
server.close();
server.wait_closed()!;
server.free();
```

`wait_closed()` suppresses common shutdown faults such as `CANCELLED`, `CLOSED`, `IO_ERROR`, and `POLL_ERROR`.

Other faults are returned to the caller.

### `Server.free`

```c3
fn void Server.free(&self)
```

Releases the server object.

If the server is not closed, `free()` closes it first.

The caller must call `wait_closed()` before `free()` after closing the server. `free()` asserts that the client list is empty.

```c3
server.close();
server.wait_closed()!;
server.free();
```

## Client management

### `Server.close_clients`

```c3
fn void Server.close_clients(&self)
```

Closes all currently active client streams.

```c3
server.close_clients();
```

### `Server.abort_clients`

```c3
fn void Server.abort_clients(&self)
```

Closes all active client streams and cancels all client tasks.

```c3
server.abort_clients();
```

Use this when you want to force client handlers to stop.

## State

### `Server.is_closed`

```c3
fn bool Server.is_closed(&self) @inline
```

Returns `true` when the server is closed or its file descriptor is invalid.

```c3
if (server.is_closed())
{
    return aio::SERVER_CLOSED~;
}
```

## Example: echo server

```c3
import ext::aio;
import ext::debug;

fn void? echo_handler(Stream* stream)
{
    char[1024] buf;

    while (true)
    {
        usz n = stream.read(buf[..])!;
        if (n == 0) break;

        stream.write(buf[0:n])!;
    }
}

fn void? main_task(void* arg)
{
    Server* server = aio::start_server(&echo_handler, "127.0.0.1", 9000)!;
    defer
    {
        server.close();
        server.wait_closed();
        server.free();
    }

    warn("serving on 127.0.0.1:9000");

    server.serve_forever()!;
}
```

## Example: serve in a task

```c3
import ext::aio;
import ext::debug;

Server* g_server = null;

fn void? handle_client(Stream* stream)
{
    char[1024] buf;

    usz n = stream.read(buf[..])!;
    stream.write(buf[0:n])!;
}

fn void? serve_task(void* arg)
{
    Server* server = (Server*)arg;
    server.serve_forever()!;
}

fn void? stop_task(void* arg)
{
    aio::sleep(10_000)!;

    Server* server = (Server*)arg;
    server.close();
}

fn void? main_task(void* arg)
{
    g_server = aio::start_server(&handle_client, "127.0.0.1", 9000)!;

    Task* serving = aio::create_task(&serve_task, g_server)!;
    Task* stopper = aio::create_task(&stop_task, g_server)!;

    stopper.await()!;
    serving.await();

    g_server.wait_closed()!;
    g_server.free();
}
```

## Shutdown pattern

Use this pattern when shutting down a server explicitly:

```c3
server.close();
server.wait_closed()!;
server.free();
```

Use `abort_clients()` when active clients must be cancelled instead of waiting for them to finish naturally:

```c3
server.abort_clients();
server.close();
server.wait_closed()!;
server.free();
```

## Notes

- `start_server()` creates the listening socket but does not start accepting clients.
- `serve_forever()` records the current task as the serving task while it is running.
- Every accepted client runs in the server's `TaskGroup`.
- Client streams are automatically freed after the handler exits.
- After `close()`, call `wait_closed()` before `free()`.
- `close_clients()` closes active streams but does not directly cancel client tasks.
- `abort_clients()` closes active streams and cancels all client tasks.

// eof