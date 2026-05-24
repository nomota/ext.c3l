// ext/aio/docs/STREAMS.md 

# ext::aio Streams

High-level TCP stream helpers built on top of `ext::aio::io` and `ext::aio::net`.

`Stream` wraps a socket file descriptor and provides simple asynchronous read/write operations, connection helpers, listener helpers, line-oriented reads, exact-length reads, and timeout wrappers.

## Overview

The stream API is intended for code that wants a small TCP abstraction instead of directly calling `net::tcp_*()` and `io::async_*()` functions.

A `Stream` owns its socket descriptor. Calling `close()` closes the descriptor, and calling `free()` closes it if needed and releases the stream object.


## Constructors

### `stream_new`

```c3
fn Stream*? aio::stream_new(Fd fd)
```

Creates a new `Stream` object from an existing file descriptor.

The stream takes ownership of `fd`.

Example:

```c3
Fd sock = net::tcp_socket()!;
Stream* stream = aio::stream_new(sock)!;
defer stream.free();
```

### `stream_listen`

```c3
fn Stream*? aio::stream_listen(String host, ushort port, int backlog = DEFAULT_BACKLOG)
```

Creates a listening TCP stream bound to `host:port`.

Internally this calls:

```c3
net::tcp_listen_host(host, port, backlog)
```

Example:

```c3
Stream* server = aio::stream_listen("127.0.0.1", 8080)!;
defer server.free();
```

### `stream_connect`

```c3
fn Stream*? aio::stream_connect(String host, ushort port)
```

Connects to a TCP server and returns a connected stream.

Internally this calls:

```c3
net::tcp_connect_host(host, port)
```

Example:

```c3
Stream* client = aio::stream_connect("127.0.0.1", 8080)!;
defer client.free();
```

### `stream_connect_timeout`

```c3
fn Stream*? aio::stream_connect_timeout(String host, ushort port, ulong timeout_ms)
```

Timeout wrapper around `stream_connect()`.

A timer is started before the connection attempt and cancelled when the call returns.

Example:

```c3
Stream* client = aio::stream_connect_timeout("example.com", 80, 3000)!;
defer client.free();
```

## Server-side API

### `Stream.accept`

```c3
fn Stream*? Stream.accept(&self)
```

Accepts one incoming TCP connection from a listening stream.

Internally this calls:

```c3
net::tcp_accept(self.fd)
```

Example:

```c3
Stream* server = aio::stream_listen("127.0.0.1", 8080)!;
defer server.free();

while (true)
{
    Stream* client = server.accept()!;
    // Usually hand this stream to a task/coroutine.
}
```

## Lifetime API

### `Stream.close`

```c3
fn void Stream.close(&self)
```

Closes the underlying socket if it is still open.

Calling `close()` more than once is safe.

Example:

```c3
stream.close();
```

### `Stream.free`

```c3
fn void Stream.free(&self)
```

Closes the stream if needed and releases the `Stream` allocation.

Example:

```c3
Stream* stream = aio::open_connection("127.0.0.1", 8080)!;
defer stream.free();
```

### `Stream.is_closed`

```c3
fn bool Stream.is_closed(&self) @inline
```

Returns `true` if the stream is logically closed or if its file descriptor is invalid.

Example:

```c3
if (stream.is_closed()) return CLOSED~;
```

## Connection information

### `Stream.peer_ip`

```c3
fn String? Stream.peer_ip(&self)
```

Returns the peer IP address.

Returns `CLOSED` if the underlying descriptor is invalid.

Example:

```c3
String ip = stream.peer_ip()!;
```

## Reading

### `Stream.read`

```c3
fn usz? Stream.read(&self, char[] buf)
```

Asynchronously reads data into `buf`.

Returns the number of bytes read.

A return value of `0` means EOF or peer close.

Example:

```c3
char[4096] buf;
usz n = stream.read(buf[..])!;

if (n == 0)
{
    return CLOSED~;
}

String data = (String)buf[0:n];
```

### `Stream.read_timeout`

```c3
fn usz? Stream.read_timeout(&self, char[] buf, ulong timeout_ms)
```

Timeout wrapper around `read()`.

Example:

```c3
char[4096] buf;
usz n = stream.read_timeout(buf[..], 5000)!;
```

### `Stream.read_exact`

```c3
fn void? Stream.read_exact(&self, char[] buf)
```

Reads until `buf` is completely filled.

Returns `CLOSED` if the peer closes the stream before enough bytes are read.

Example:

```c3
char[16] header;
stream.read_exact(header[..])!;
```

### `Stream.read_until`

```c3
fn usz? Stream.read_until(&self, char[] buf, char delim)
```

Reads one byte at a time until one of these happens:

- `delim` is read.
- `buf` becomes full.
- the peer closes the connection.

Returns the number of bytes copied into `buf`.

The delimiter is included in the buffer when found.

Example:

```c3
char[1024] line;
usz n = stream.read_until(line[..], '\n')!;

String text = (String)line[0:n];
```

### `Stream.read_line`

```c3
fn usz? Stream.read_line(&self, char[] buf)
```

Reads until newline.

Equivalent to:

```c3
stream.read_until(buf, '\n')
```

Example:

```c3
char[1024] line;
usz n = stream.read_line(line[..])!;
```

## Writing

### `Stream.write`

```c3
fn usz? Stream.write(&self, char[] buf) @maydiscard
```

Asynchronously writes data from `buf`.

Returns the number of bytes written.

This function may write fewer bytes than requested. Use `write_all()` when the whole buffer must be sent.

Example:

```c3
char[] data = "hello\n";
usz n = stream.write(data)!;
```

### `Stream.write_all`

```c3
fn void? Stream.write_all(&self, char[] data) @maydiscard
```

Writes the full contents of `data`.

Internally it loops until all bytes are written.

Returns `CLOSED` if a write returns `0`.

Example:

```c3
stream.write_all("hello\n")!;
```

### `Stream.write_all_timeout`

```c3
fn void? Stream.write_all_timeout(&self, char[] data, ulong timeout_ms)
```

Timeout wrapper around `write_all()`.

Example:

```c3
stream.write_all_timeout("hello\n", 5000)!;
```

## Client example

```c3
module examples::stream_client;

import ext::aio;

fn void? main_task(void* arg)
{
    Stream* stream = aio::stream_connect("example.com", 80)!;
    defer stream.free();

    stream.write_all(
        "GET / HTTP/1.1\r\n"
        "Host: example.com\r\n"
        "Connection: close\r\n"
        "\r\n"
    )!;

    char[4096] buf;

    while (true)
    {
        usz n = stream.read(buf[..])!;

        if (n == 0) break;

        String chunk = (String)buf[0:n];
        io::printf("%s", chunk);
    }
}
```

## Line-based echo server example

```c3
module examples::stream_echo_server;

import ext::aio;
import ext::debug;

fn void? handle_client(Stream* client)
{
    defer client.free();

    String ip = client.peer_ip()!!;
    warn("client connected: %s", ip);

    char[1024] line;

    while (true)
    {
        usz n = client.read_line(line[..])!;

        if (n == 0) break;

        client.write_all(line[0:n])!;
    }

    warn("client disconnected");
}

fn void? main_task(void* arg)
{
    Stream* server = aio::stream_listen("127.0.0.1", 8080)!;
    defer server.free();

    while (true)
    {
        Stream* client = server.accept()!;

        // Replace this with your task spawning API if desired.
        handle_client(client)!;
    }
}
```

## Notes

### Ownership

`Stream` owns its file descriptor.

Do not close the same descriptor manually after passing it to `stream_new()` unless you also prevent the stream from closing it again.

### Partial writes

`write()` may complete after writing only part of the buffer.

Use `write_all()` for protocol messages, HTTP requests, text lines, and other cases where the full buffer must be transmitted.

### EOF handling

`read()` returning `0` should be treated as EOF.

The higher-level helpers `read_exact()` and `write_all()` convert unexpected zero-length progress into `CLOSED`.

### Timeout behavior

The timeout helpers create a timer, run the underlying operation, and cancel the timer afterward.

```c3
Timer* timer = start_timer(timeout_ms)!;
defer timer.cancel();
```

The actual cancellation behavior depends on the event loop and timer implementation.

## API summary

| Function | Description |
|---|---|
| `stream_new(fd)` | Wrap an existing socket descriptor. |
| `stream_listen(host, port, backlog)` | Create a listening TCP stream. |
| `stream_connect(host, port)` | Connect to a TCP server. |
| `stream_connect_timeout(host, port, timeout_ms)` | Timed connection helper. |
| `Stream.accept()` | Accept a client from a listening stream. |
| `Stream.close()` | Close the stream. |
| `Stream.free()` | Close and free the stream. |
| `Stream.is_closed()` | Check closed state. |
| `Stream.peer_ip()` | Get peer IP address. |
| `Stream.read(buf)` | Read bytes asynchronously. |
| `Stream.read_timeout(buf, timeout_ms)` | Timed read helper. |
| `Stream.read_exact(buf)` | Fill the whole buffer. |
| `Stream.read_until(buf, delim)` | Read until delimiter, EOF, or buffer full. |
| `Stream.read_line(buf)` | Read until newline. |
| `Stream.write(buf)` | Write bytes asynchronously. |
| `Stream.write_all(data)` | Write the full buffer. |
| `Stream.write_all_timeout(data, timeout_ms)` | Timed full-buffer write helper. |

// eof