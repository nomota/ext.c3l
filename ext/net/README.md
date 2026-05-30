# ext::net

High-level networking library for the [C3 programming language](https://c3-lang.org/).

`ext::net` provides small, practical abstractions over raw socket APIs, including TCP, UDP, and DNS lookup support. It is intended to be simple enough for direct use, while still exposing socket-level behavior such as non-blocking mode and explicit error handling.

This is part of the extended C3 library.

Back to [ext.c3l](../../README.md).

## Available Modules

| Module | Description |
|--------|-------------|
| `ext::net::tcp` | TCP operations: `new()`, `new_listen()`, `new_connect()`, `listen()`, `connect()`, `accept()`, `send()`, `recv()`, `read()`, `write()`, `readline()`, `set_non_blocking()`, `close()` |
| `ext::net::udp` | UDP operations: `new()`, `new_bind()`, `bind()`, `send()`, `recv()`, `sendto()`, `recvfrom()`, `set_non_blocking()`, `close()` |
| `ext::net::dns` | DNS operations: `get_addrinfo()` |
| `ext::net::wsa` | Windows-only WinSock startup helper |

## Platform Support

| Platform | TCP | UDP | DNS |
|----------|-----|-----|-----|
| POSIX / Linux / BSD / macOS | yes | yes | yes |
| Windows | yes | yes | yes |

The POSIX implementation uses the system socket API.

The Windows implementation uses WinSock. Socket errors should be interpreted through WinSock error codes, not only through `GetLastError()`.

## Error Handling

`ext::net` uses C3 optional return values. Functions that can fail return optional types such as `TcpSocket?`, `UdpSocket?`, `sz?`, or `void?`.

Typical error handling:

```c3
TcpSocket? server = tcp::new_listen(8080);
if (catch err = server)
{
    io::printfn("listen failed: %s", err);
    return;
}
```

Most socket errors are mapped to common `c::errno` faults such as:

```text
E_ACCESS_DENIED, E_ADDR_IN_USE, E_ADDR_NOT_AVAIL, E_AGAIN, E_WOULD_BLOCK,
E_CONN_REFUSED, E_CONN_RESET, E_NOT_CONNECTED, E_TIMED_OUT, E_GENERAL_ERR
```

## TCP Module

Source files:

* [tcp.posix.c3](tcp.posix.c3)
* [tcp.win32.c3](tcp.win32.c3)

Import:

```c3
import ext::net::tcp;
```

Available API:

```c3
TcpSocket? sock = tcp::new(int version = AF_INET);

int? r = sock.listen(
    ushort port,
    String opt_ip = "*",
    int backlog = 10
);

TcpSocket? server = tcp::new_listen(
    ushort port,
    String opt_ip = "*",
    int backlog = 10
);

void? sock.connect(String ip, ushort port);

TcpSocket? sock = tcp::new_connect(String ip, ushort port);

TcpSocket? client = server.accept(
    char[] ip = &__null__,
    ushort* port = null
);

sz? n = sock.send(char[] buf);
sz? n = sock.recv(char[] buf);

// these are blocking mode only
sz? n = sock.write(char[] buf);
sz? n = sock.read(char[] buf);
sz? n = sock.readline(char[] line);

void? sock.set_non_blocking() @maydiscard;
void? sock.close() @maydiscard;
```

Notes:

* `tcp::new()` creates a socket.
* `tcp::new_listen()` creates, binds, and listens.
* `tcp::new_connect()` creates and connects.
* `listen()` sets `reuse_addr`.
* `opt_ip = "*"` binds to the default wildcard address.
* For IPv6, the wildcard address is usually `"::"`.
* `send()` and `write()` are aliases in style, depending on how the socket is used.
* `recv()` and `read()` are aliases in style, depending on how the socket is used.
* `readline()` is useful for text protocols.

## UDP Module

Source files:

* [udp.posix.c3](udp.posix.c3)
* [udp.win32.c3](udp.win32.c3)

Import:

```c3
import ext::net::udp;
```

Available API:

```c3
UdpSocket? sock = udp::new(int version = AF_INET);

void? sock.bind(
    ushort port,
    String opt_ip = "*"
);

UdpSocket? sock = udp::new_bind(
    ushort port,
    String ip = "*"
);

sz? n = sock.recvfrom(
    char[] msgbuf,
    char[] ip,
    ushort* port
);

sz? n = sock.sendto(
    char[] msgbuf,
    String ip,
    ushort port
);

sz? n = sock.send(char[] buf);
sz? n = sock.recv(char[] buf);

void? sock.set_non_blocking() @maydiscard;
void? sock.close() @maydiscard;
```

Notes:

* `udp::new()` creates a UDP socket.
* `udp::new_bind()` creates and binds.
* `bind()` sets `reuse_addr`.
* `recvfrom()` returns the sender address through `ip` and `port`.
* `sendto()` sends a datagram to a target address.
* `send()` and `recv()` are useful after connecting a UDP socket or when using a platform mode that supports default peer behavior.

## DNS Module

Source files:

* [dns.posix.c3](dns.posix.c3)
* [dns.win32.c3](dns.win32.c3)

Import:

```c3
import ext::net::dns;
import std::collections::list;
```

Available API:

```c3
// caller should free ips properly
List{String}? ips = dns::get_addrinfo(Allocator allocx, String host);
```

Example:

```c3
List{String} ips = dns::get_addrinfo(mem, "example.com")!!;

foreach (ip: ips)
{
    io::printfn("%s", ip);
    ip.free(mem);
}

ips.free();
```

The caller owns the returned list and every `String` inside it. Free both the contained strings and the list itself.

DNS lookup uses `getaddrinfo()` internally. On Windows, `wsa::startup()` is called before using WinSock DNS APIs.

## TCP Server Example

```c3
import std::io;
import stdio;

import ext::net::tcp;

fn void main()
{
    TcpSocket? server = tcp::new_listen(8080);
    if (catch err = server)
    {
        io::printfn("Failed to listen: %s", err);
        return;
    }

    io::printfn("Server listening on port 8080...");

    while (true)
    {
        char[64] client_ip;
        ushort client_port;

        TcpSocket? client = server.accept(client_ip[..], &client_port);
        if (catch err = client)
        {
            io::printfn("accept failed: %s", err);
            continue;
        }
        defer client.close()!!;

        stdio::printf("Client connected from %s:%d\n", &client_ip[0], client_port);

        char[1024] buffer;
        sz? bytes = client.recv(buffer[..]);
        if (catch err = bytes)
        {
            io::printfn("recv failed: %s", err);
            continue;
        }

        io::printfn("Received: %s", (String)buffer[0:bytes]);

        client.send("Hello from server!\n")!!;
    }
}
```

## TCP Client Example

```c3
import std::io;

import ext::net::tcp;

fn void main()
{
    TcpSocket? sock = tcp::new_connect("127.0.0.1", 8080);
    if (catch err = sock)
    {
        io::printfn("connect failed: %s", err);
        return;
    }
    defer sock.close()!!;

    io::printfn("Connected to server");

    sock.send("Hello, server!\n")!!;

    char[1024] buffer;
    sz bytes = sock.recv(buffer[..])!!;

    io::printfn("Server response: %s", (String)buffer[0:bytes]);
}
```

## UDP Server Example

```c3
import std::io;

import ext::net::udp;

fn void main()
{
    UdpSocket? sock = udp::new_bind(9000);
    if (catch err = sock)
    {
        io::printfn("bind failed: %s", err);
        return;
    }
    defer sock.close()!!;

    io::printfn("UDP server listening on port 9000...");

    char[1024] buffer;
    char[64] client_ip;
    ushort client_port;

    while (true)
    {
        sz len = sock.recvfrom(buffer[..], client_ip[..], &client_port)!!;

        io::printfn(
            "Received from %s:%d: %s",
            (ZString)&client_ip[0],
            client_port,
            (String)buffer[0:len]
        );

        sock.sendto("Acknowledged\n", (ZString)&client_ip[0], client_port)!!;
    }
}
```

## UDP Client Example

```c3
import std::io;

import ext::net::udp;

fn void main()
{
    UdpSocket sock = udp::new()!!;
    defer sock.close()!!;

    sock.sendto("Hello, UDP server!\n", "127.0.0.1", 9000)!!;

    char[1024] buffer;
    char[64] server_ip;
    ushort server_port;

    sz len = sock.recvfrom(buffer[..], server_ip[..], &server_port)!!;

    io::printfn(
        "Response from %s:%d: %s",
        (ZString)&server_ip[0],
        server_port,
        (String)buffer[0:len]
    );
}
```

## DNS Example

```c3
import std::io;
import std::collections::list;

import ext::net::dns;

fn void main()
{
    List{String}? ips = dns::get_addrinfo(mem, "example.com");
    if (catch err = ips)
    {
        io::printfn("DNS lookup failed: %s", err);
        return;
    }

    foreach (ip: ips)
    {
        io::printfn("%s", ip);
        ip.free(mem);
    }

    ips.free();
}
```

## Non-Blocking I/O

Sockets can be switched to non-blocking mode:

```c3
import ext::net::tcp;

fn void main()
{
    TcpSocket sock = tcp::new_connect("127.0.0.1", 8080)!!;
    defer sock.close()!!;

    sock.set_non_blocking()!!;

    char[1024] buffer;
    sz? n = sock.recv(buffer[..]);

    if (catch err = n)
    {
        if (err == errno::E_WOULD_BLOCK)
        {
            // Try again later, or wait through an event loop.
            return;
        }

        return;
    }
}
```

Non-blocking sockets are useful when integrating `ext::net` with an event loop such as `ext::aio`.

On Windows, socket operations should use WinSock error handling. A socket operation that would block normally maps to `E_WOULD_BLOCK`.

## Reading Lines

`readline()` is useful for simple text protocols.

```c3
import std::io;

import ext::net::tcp;
import c::errno;

fn void? handle_client(TcpSocket sock)
{
    char[1024] line;

    while (true)
    {
        sz? len = sock.readline(line[..]);
        if (catch err = len)
        {
            if (err == errno::EOF) break;

            io::printfn("readline failed: %s", err);
            return err;
        }

        io::printfn("Received line: %s", (String)line[0:len]);

        sock.send("OK\n")!;
    }
}
```

## Testing

Example programs are available in the `test/` directory:

* [tcpserver.c3](../../test/tcpserver.c3) - TCP echo server
* [tcpclient.c3](../../test/tcpclient.c3) - TCP client
* [udpserver.c3](../../test/udpserver.c3) - UDP echo server
* [udpclient.c3](../../test/udpclient.c3) - UDP client

Example run:

```bash
# Terminal 1
make tcpserver

# Terminal 2
make tcpclient
```

UDP examples:

```bash
# Terminal 1
make udpserver

# Terminal 2
make udpclient
```

## Design Notes

`ext::net` is intentionally synchronous at the API level. It exposes non-blocking mode so that higher-level modules can build event-loop based I/O on top of it.

A typical layering is:

```text
ext::aio
    -> ext::net::tcp / ext::net::udp
        -> POSIX sockets or WinSock
```

For Windows, IOCP is not required to use `ext::net`. A higher-level event loop may also use non-blocking sockets with `select()` or `WSAPoll()`. File I/O is a separate concern and is usually handled by a thread pool or an overlapped I/O backend.

Back to [ext.c3l](../../README.md).
