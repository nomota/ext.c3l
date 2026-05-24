// ext/aio/docs/HANDLERS.md 

# ext::aio Handlers

Event-driven callback style protocol handlers for `ext::aio`.

This module provides callback-based TCP and UDP helpers on top of `Stream`, `Datagram`, and `Task`.

It is useful when you want a protocol-handler style API instead of manually reading from streams or datagrams in application code.


## TCP handler

```c3
interface TCPHandler
{
    fn void? connection_made(Stream* stream);
    fn void? data_received(char[] data);
    fn void? connection_lost(fault exception);
}
```

A `TCPHandler` receives connection lifecycle and data callbacks.

### `connection_made`

```c3
fn void? connection_made(Stream* stream)
```

Called when a TCP connection is established.

For clients, this is called after `stream_connect()` succeeds.

For servers, this is called after a client has been accepted.

The `Stream*` can be stored by the handler if it needs to write responses later.

### `data_received`

```c3
fn void? data_received(char[] data)
```

Called whenever bytes are read from the TCP stream.

The `data` slice is valid for the duration of the callback. Copy it if it must be kept after the callback returns.

### `connection_lost`

```c3
fn void? connection_lost(fault exception)
```

Called when the connection is closed or when an error stops the read loop.

If the connection ends normally, `exception` is `NONE`.

If a read or callback fails, `exception` contains the fault that ended the connection.

## UDP handler

```c3
interface UDPHandler
{
    fn void? connection_made(Datagram* transport);
    fn void? datagram_received(char[] data, String ip, ushort port);
    fn void? error_received(fault exception);
    fn void? connection_lost(fault exception) @optional;
}
```

A `UDPHandler` receives datagram lifecycle, receive, and error callbacks.

### `connection_made`

```c3
fn void? connection_made(Datagram* transport)
```

Called after the UDP datagram socket is created and bound.

The `Datagram*` can be stored by the handler if it needs to send replies with `sendto()`.

### `datagram_received`

```c3
fn void? datagram_received(char[] data, String ip, ushort port)
```

Called for every received UDP datagram.

The sender address is passed as `ip` and `port`.

The `data` slice is valid for the duration of the callback. Copy it if it must be kept after the callback returns.

### `error_received`

```c3
fn void? error_received(fault exception)
```

Called when the UDP receive loop or a UDP callback fails.

### `connection_lost`

```c3
fn void? connection_lost(fault exception) @optional
```

Optional callback called when the UDP task exits.

If the task ends normally, `exception` is `NONE`.

## TCP client

### `tcp_callback_client`

```c3
fn Task*? aio::tcp_callback_client(TCPHandler handler, String host, ushort port)
```

Starts a joinable TCP client task.

The task connects to `host:port`, calls `connection_made()`, then repeatedly reads from the stream and calls `data_received()`.

When the stream closes or an error occurs, `connection_lost()` is called.

```c3
// You have to define your own handler, by inheriting TCPHandler interface
struct MyTcpHandler (TCPHandler) // implements interface
{
    Stream* stream;
    // some more members
}

// Define your own callback functions
fn void? MyTcpHandler.connection_made(&self, Stream* stream)
{
    // do something
}

fn void? MyTcpHandler.data_received(&self, char[] data)
{
    // do something
}

fn void? MyTcpHandler.connection_lost(&self, fault exception)
{
    // do something
}

MyTcpHandler handler; 

Task* task = aio::tcp_callback_client(&handler, "127.0.0.1", 9000)!;
task.join();
```

## TCP server

### `tcp_callback_server`

```c3
fn Task*? aio::tcp_callback_server(TCPHandler handler, String host, ushort port, int backlog = net::DEFAULT_BACKLOG)
```

Starts a joinable TCP callback server task.

The server listens on `host:port`.

Each accepted client runs in a service task and receives callbacks through the provided `TCPHandler`.

```c3
// You have to define your own handler, by inheriting TCPHandler interface
struct MyTcpHandler (TCPHandler) // implements interface
{
    Stream* stream;
    // some more members
}

// Define your own callback functions
fn void? MyTcpHandler.connection_made(&self, Stream* stream)
{
    // do something
}

fn void? MyTcpHandler.data_received(&self, char[] data)
{
    // do something
}

fn void? MyTcpHandler.connection_lost(&self, fault exception)
{
    // do something
}

MyTcpHandler handler; 

Task* server_task = aio::tcp_callback_server(&handler, "127.0.0.1", 9000)!;
server_task.join();
```

The returned task represents the server task. Cancelling or completing this task stops the server task.

## UDP server

### `udp_callback_server`

```c3
fn Task*? aio::udp_callback_server(UDPHandler handler, String host, ushort port)
```

Starts a joinable UDP callback server task.

The server binds a datagram socket to `host:port`, calls `connection_made()`, then repeatedly receives datagrams and calls `datagram_received()`.

```c3
// You have to define your own handler, by inheriting UDPHandler interface
struct MyUdpHandler (UDPHandler) // implements interface
{
    Datagram* datagram;
    // some more members
}

// Define your own callback functions
fn void? MyUdpHandler.connection_made(&self, Datagram* datagram)
{
    // do something
}

fn void? MyUdpHandler.datagram_received(&self, char[] data, String ip, ushort port)
{
    // do something
}

fn void? MyUdpHandler.error_received(&self, fault exception)
{
    // do something
}

fn void? MyUdpHandler.connection_lost(&self, fault exception)
{
    // do something
}

MyUdpHandler handler; 

Task* task = aio::udp_callback_server(&handler, "127.0.0.1", 9000)!;
task.join();
```

## Example: TCP echo handler

```c3
import ext::aio;
import ext::debug;

struct EchoHandler (TCPHandler)
{
    Stream* stream;
}

fn void? EchoHandler.connection_made(&self, Stream* stream)
{
    self.stream = stream;
    warn("[tcp] connection made");
}

fn void? EchoHandler.data_received(&self, char[] data)
{
    warn("[tcp] received: %s", (String)data);

    if (self.stream == null) return aio::NO_STREAM~;

    self.stream.write(data)!;
}

fn void? EchoHandler.connection_lost(&self, fault exception)
{
    if (exception != NONE)
    {
        warn("[tcp] connection lost: %s", exception);
    }
    else
    {
        warn("[tcp] connection closed");
    }
}

fn void? main()
{
    EchoHandler handler = {};

    Task* task = aio::tcp_callback_server(&handler, "127.0.0.1", 9000)!;
    task.join();
}
```

## Example: TCP client handler

```c3
import ext::aio;
import ext::debug;

struct ClientHandler (TCPHandler)
{
    Stream* stream;
}

fn void? ClientHandler.connection_made(&self, Stream* stream)
{
    self.stream = stream;

    char[] msg = "hello tcp";
    stream.write(msg)!;
}

fn void? ClientHandler.data_received(&self, char[] data)
{
    warn("[client] received: %s", (String)data);

    if (self.stream != null)
    {
        self.stream.close();
    }
}

fn void? ClientHandler.connection_lost(&self, fault exception)
{
    if (exception != NONE)
    {
        warn("[client] connection lost: %s", exception);
    }
}

fn void? main()
{
    ClientHandler handler = {};

    Task* task = aio::tcp_callback_client(&handler, "127.0.0.1", 9000)!;
    task.join();
}
```

## Example: UDP echo handler

```c3
import ext::aio;
import ext::debug;

struct UdpEchoHandler (UDPHandler)
{
    Datagram* transport;
}

fn void? UdpEchoHandler.connection_made(&self, Datagram* transport)
{
    self.transport = transport;
    warn("[udp] listening");
}

fn void? UdpEchoHandler.datagram_received(&self, char[] data, String ip, ushort port)
{
    warn("[udp] received from %s:%d: %s", ip, port, (String)data);

    if (self.transport == null) return aio::NO_DATAGRAM~;

    self.transport.sendto(data, ip, port)!;
}

fn void? UdpEchoHandler.error_received(&self, fault exception)
{
    warn("[udp] error: %s", exception);
}

fn void? UdpEchoHandler.connection_lost(&self, fault exception)
{
    if (exception != NONE)
    {
        warn("[udp] connection lost: %s", exception);
    }
    else
    {
        warn("[udp] closed");
    }
}

fn void? main()
{
    UdpEchoHandler handler = {};

    Task* task = aio::udp_callback_server(&handler, "127.0.0.1", 9000)!;
    task.join();
}
```

## Callback flow

### TCP client flow

```text
tcp_callback_client()
    connect
    connection_made(stream)
    read loop
        data_received(data)
    connection_lost(error)
```

### TCP server flow

```text
tcp_callback_server()
    listen
    accept loop
        accept client
        spawn service task
            connection_made(stream)
            read loop
                data_received(data)
            connection_lost(error)
```

### UDP server flow

```text
udp_callback_server()
    bind datagram
    connection_made(datagram)
    receive loop
        datagram_received(data, ip, port)
    error_received(error)
    connection_lost(error)
```

## Error handling

For TCP, errors from connect, read, or callbacks are passed to `connection_lost()`.

```c3
fn void? MyHandler.connection_lost(&self, fault exception)
{
    if (exception != NONE)
    {
        warn("tcp error: %s", exception);
    }
}
```

For UDP, errors are passed to `error_received()` and then to optional `connection_lost()` if that callback exists.

```c3
fn void? MyUdpHandler.error_received(&self, fault exception)
{
    warn("udp error: %s", exception);
}
```

## Notes

- The callback helpers return joinable `Task*` values.
- TCP callbacks use `Stream`.
- UDP callbacks use `Datagram`.
- TCP `data_received()` receives byte slices from the stream read loop.
- UDP `datagram_received()` receives one datagram at a time.
- Store the transport in `connection_made()` if the handler needs to write or send replies.
- TCP `connection_lost()` is always required.
- UDP `connection_lost()` is optional.
- Callback data slices should be copied if they need to outlive the callback.

// eof