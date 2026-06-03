// ext/mio/README.md

# ext::mio

Minimal readiness-based I/O poller for C3.

`ext::mio` provides a small cross-platform readiness API inspired by Rust's `mio`.
It is intended to be a low-level building block for event loops, async runtimes, TCP/UDP servers, and wakeable poll loops.

The module does not own tasks, futures, coroutines, or buffers. It only reports readiness.

## Features

- Cross-platform `Poll` abstraction
- Readiness events for read, write, error, and hang-up
- TCP listener and stream helpers
- UDP socket helpers
- Thread-safe registration path using an internal waker
- Internal waker for waking a blocked poll loop
- Non-blocking sockets by default
- Local and peer address helpers
- POSIX backend support through epoll/kqueue/select-style implementations
- Windows backend support through wepoll-style socket polling

## Available

| Module | Feature |
|--------|--------|
| `ext::mio` | `Poll*`, `Event`, want_read(), want_write(), want_readwrite(), register(), reregister(), deregister(), poll(), wake() |
| sockets | TcpListener, TcpStream, UdpSocket |
| primitive non-blocking operation | tcp_socket_fd(), socket_bind_fd(), tcp_listen_fd(), tcp_connect_fd(), tcp_accept_fd(), tcp_read_fd(), tcp_write_fd(), udp_socket_fd(), udp_recvfrom_fd(), udp_sendto_fd(), socket_close_fd(), socket_family_fd(), peer_addr_fd() |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

## Design

`ext::mio` is intentionally small.

It separates readiness notification from actual I/O. A readiness event means that an operation may now succeed, not that it is guaranteed to complete fully. Reads and writes must still handle short I/O and would-block errors.

Typical usage:

1. Create a `Poll`.
2. Create an `Events` buffer.
3. Create or accept non-blocking sockets.
4. Register file descriptors or sockets with an interest.
5. Call `poll.poll()`.
6. Inspect returned events.
7. Perform non-blocking I/O.
8. Reregister or deregister as needed.

## Module

```c3
import ext::mio;
```

### Interest

```c3
mio::Interest read = mio::want_read();
mio::Interest write = mio::want_write();
mio::Interest both = mio::want_readwrite();
```

Interests can be combined:

```c3
mio::Interest interest = mio::want_read().add(mio::want_write());
```

### Event

Each returned event contains:

```c3
event.fd
event.read
event.write
event.error
event.hup
```

`read` means the fd may be readable.
`write` means the fd may be writable.
`error` means the fd has an error condition.
`hup` means the peer or fd may have closed.

Always check `error` and `hup` when handling socket events.

## Creating a poller

```c3
mio::Poll* poll = mio::poll_new(1024)!!;
defer poll.free();

mio::Events events = mio::events_new(1024)!!;
defer events.free();
```

`poll_new()` creates an internal waker and registers it with the platform poller.

## Registering fds

```c3
mio::Fd fd; // file descripter, socket handle
poll.register(fd, mio::want_read())!!;
poll.reregister(fd, mio::want_write())!!;
poll.deregister(fd)!!;
```

`register()`, `reregister()`, and `deregister()` are protected by a mutex and wake the poll loop after modifying the registry.

This allows another thread to modify registrations while a poll loop is blocked.

## Polling

```c3
poll.poll(&events, 1000)!!;

for (sz i = 0; i < events.len; i++)
{
    mio::Event* event = events.get(i);
    if (event == null) continue;

    if (event.read)
    {
        // read or accept
    }

    if (event.write)
    {
        // write or finish non-blocking connect
    }

    if (event.error || event.hup)
    {
        // inspect error or close
    }
}
```

Timeout is in milliseconds.

Common timeout values:

| Value | Meaning |
|-------|---------|
| `-1` | Wait indefinitely |
| `0` | Return immediately |
| `> 0` | Wait up to N milliseconds |

## TCP listener

```c3
mio::TcpListener listener = mio::tcp_listen("127.0.0.1", 8080)!!;
defer listener.close();

poll.register(listener.fd, mio::want_read())!!;
```

Accept when the listener becomes readable:

```c3
char[64] ip_buf;
ushort port = 0;

mio::TcpStream stream = listener.accept(ip_buf[..], &port)!!;
defer stream.close();

poll.register(stream.fd, mio::want_read())!!;
```

## TCP connect

`mio::tcp_connect()` starts a non-blocking connect.

```c3
mio::TcpStream client = mio::tcp_connect("127.0.0.1", 8080)!!;
defer client.close();

poll.register(client.fd, mio::want_write())!!;
```

When the socket becomes writable, check `SO_ERROR`:

```c3
int err = client.take_error();
@assert(err == 0, "connect failed");

poll.reregister(client.fd, mio::want_read())!!;
```

## TCP read and write

```c3
char[1024] buf;

sz n = stream.read(buf[..])!!;
if (n == 0)
{
    // EOF
}

sz written = stream.write(buf[0:n])!!;
```

Reads and writes are non-blocking.
The caller must handle would-block errors and partial writes.

## UDP

Bind a UDP socket:

```c3
mio::UdpSocket server = mio::udp_bind("127.0.0.1", 8081)!!;
defer server.close();

poll.register(server.fd, mio::want_read())!!;
```

Create an unbound UDP socket:

```c3
mio::UdpSocket client = mio::udp_socket()!!;
defer client.close();
```

Send:

```c3
char[] msg = "hello udp";

sz sent = client.send_to(msg, "127.0.0.1", 8081)!!;
```

Receive:

```c3
char[1024] buf;
char[64] ip_buf;
ushort port = 0;

sz n = server.recv_from(buf[..], ip_buf[..], &port)!!;
```

## Low-level fd helpers

`ext::mio` also exposes low-level fd-based helpers.

These functions are useful when building higher-level wrappers such as `TcpStream`, `TcpListener`, `UdpSocket`, or an async runtime on top of `ext::mio`.

The object methods are safer for ordinary users. The fd helpers are mostly intended for runtime, socket abstraction, and platform integration code.

### Generic fd helpers

| Function | Description |
|----------|-------------|
| `fd_invalid(fd)` | Returns true if an fd/socket handle is invalid for the current platform. On POSIX this means `fd < 0`; on Windows this means `0` or `-1`. |
| `set_nonblock_fd(fd)` | Sets the fd/socket to non-blocking mode. |
| `set_reuseaddr_fd(fd)` | Enables `SO_REUSEADDR` on the socket. |
| `socket_close_fd(fd)` | Closes a socket fd if it is valid. |
| `socket_family_fd(fd)` | Returns the address family of a bound socket, such as `AF_INET` or `AF_INET6`. |
| `socket_family_from_ip(ip)` | Returns the socket family inferred from an IP string. IPv6 is selected when the string contains `:`. |
| `socket_bind_fd(fd, ip, port)` | Binds an existing socket fd to an explicit IP address and port. |
| `socket_bind_any_fd(fd, family)` | Binds an existing socket fd to port `0` on the wildcard address for the given family. |
| `socket_local_addr(fd, ip_buf, port)` | Writes the local socket address into `ip_buf` and `port`. This is currently an internal helper. |
| `socket_peer_addr(fd, ip_buf, port)` | Writes the peer socket address into `ip_buf` and `port`. This is currently an internal helper. |
| `peer_addr_fd(fd, ip_buf, port)` | Writes the peer socket address for a connected socket. |

### TCP fd helpers

| Function | Description |
|----------|-------------|
| `tcp_socket_fd(family)` | Creates a non-blocking TCP socket fd for the given address family. |
| `tcp_listen_fd(fd, backlog)` | Calls `listen()` on an already bound TCP socket fd. |
| `tcp_connect_fd(fd, ip, port)` | Starts a non-blocking TCP connect on an existing socket fd. A pending connect is treated as success. |
| `tcp_connect(ip, port)` | Creates a non-blocking TCP socket and starts connecting. Returns a `TcpStream`. |
| `tcp_accept_fd(listener_fd, peer)` | Accepts one TCP connection from a listener fd, sets the accepted socket non-blocking, and optionally writes the peer address into `peer`. |
| `tcp_read_fd(fd, buf)` | Reads from a TCP socket fd using non-blocking `read()`/`recv()`. |
| `tcp_write_fd(fd, buf)` | Writes to a TCP socket fd using non-blocking `write()`/`send()`. |
| `take_error_fd(fd)` | Reads `SO_ERROR` for a socket fd. Use this after non-blocking connect readiness. |

### UDP fd helpers

| Function | Description |
|----------|-------------|
| `udp_socket_fd(family)` | Creates a non-blocking UDP socket fd for the given address family. |
| `udp_recvfrom_fd(fd, buf, ip_buf, port)` | Receives one datagram and writes sender IP/port into `ip_buf` and `port`. |
| `udp_sendto_fd(fd, buf, ip, port)` | Sends one datagram to the given IP and port. |

### Address conversion helpers

| Function | Description |
|----------|-------------|
| `make_sockaddr(ip, port, addr, len)` | Converts an IP string and port to a platform socket address structure. |
| `sockaddr_to_addr(addr, ip_buf, port)` | Converts a platform socket address structure back to an IP string and port. |

### Recommended usage

Use object methods for normal application code:

```c3
mio::TcpStream stream = mio::tcp_connect("127.0.0.1", 8080)!!;
sz n = stream.write("hello")!!;
```

Use fd helpers when composing your own abstraction:

```c3
mio::Fd fd = mio::tcp_socket_fd(mio::socket_family_from_ip("127.0.0.1"))!!;
defer mio::socket_close_fd(fd);

mio::tcp_connect_fd(fd, "127.0.0.1", 8080)!!;

poll.register(fd, mio::want_write())!!;
```

After write readiness, complete the non-blocking connect with `take_error_fd()`:

```c3
int err = mio::take_error_fd(fd);
@assert(err == 0, "connect failed");

poll.reregister(fd, mio::want_read())!!;
```


## Waker

In multi-thread situation, you want to wake a poller in other thread, a `Waker` can wake a blocked poll loop.

```c3
mio::Waker* waker = mio::waker_new()!!;
defer waker.free();

poll.register(waker.fd(), mio::want_read())!!;
waker.wake()!!;
```

When readable, drain it:

```c3
waker.drain()!!;
```

`Poll` already owns an internal waker. Most users do not need to create a waker manually unless they are building custom coordination around a poll loop.

## Example: TCP echo server

```c3
import std::io;
import ext::mio;
import ext::debug;

const ushort PORT = 8080;

fn void main()
{
    mio::Poll* poll = mio::poll_new(1024)!!;
    defer poll.free();

    mio::Events events = mio::events_new(1024)!!;
    defer events.free();

    mio::TcpListener listener = mio::tcp_listen("127.0.0.1", PORT)!!;
    defer listener.close();

    poll.register(listener.fd, mio::want_read())!!;

    mio::TcpStream client = {};
    bool has_client = false;

    while (true)
    {
        poll.poll(&events, 1000)!!;

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            if (event.fd == listener.fd && event.read)
            {
                char[64] ip_buf;
                ushort port = 0;

                client = listener.accept(ip_buf[..], &port)!!;
                has_client = true;

                poll.register(client.fd, mio::want_read())!!;
                continue;
            }

            if (has_client && event.fd == client.fd && event.read)
            {
                char[1024] buf;

                sz n = client.read(buf[..])!!;
                if (n == 0)
                {
                    poll.deregister(client.fd)!!;
                    client.close();
                    has_client = false;
                    continue;
                }

                sz written = client.write(buf[0:n])!!;
                @assert(written == n, "partial write");

                poll.deregister(client.fd)!!;
                client.close();

                warn("OK");
                return;
            }

            if (event.error || event.hup)
            {
                warn("socket error or hup");
                return;
            }
        }
    }
}
```

## Example: TCP client

```c3
import std::io;
import ext::mio;
import ext::debug;

const ushort PORT = 8080;
const char[] MSG = "hello mio";

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::TcpStream stream = mio::tcp_connect("127.0.0.1", PORT)!!;
    defer stream.close();

    poll.register(stream.fd, mio::want_write())!!;

    bool connected = false;
    bool sent = false;

    while (true)
    {
        poll.poll(&events, 1000)!!;

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;
            if (event.fd != stream.fd) continue;

            if (!connected && (event.write || event.error || event.hup))
            {
                int err = stream.take_error();
                @assert(err == 0, "connect failed");

                connected = true;

                sz n = stream.write(MSG)!!;
                @assert(n == (sz)MSG.len, "partial write");

                sent = true;
                poll.reregister(stream.fd, mio::want_read())!!;
                continue;
            }

            if (sent && event.read)
            {
                char[256] buf;

                sz n = stream.read(buf[..])!!;
                String text = (String)buf[0:n];

                warn("%s", text);

                poll.deregister(stream.fd)!!;
                return;
            }
        }
    }
}
```

## Example: UDP echo

```c3
import std::io;
import c::string;
import ext::mio;
import ext::debug;

const ushort PORT = 8081;

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::UdpSocket server = mio::udp_bind("127.0.0.1", PORT)!!;
    defer server.close();

    poll.register(server.fd, mio::want_read())!!;

    mio::UdpSocket client = mio::udp_socket()!!;
    defer client.close();

    char[] msg = "hello udp";

    sz sent = client.send_to(msg, "127.0.0.1", PORT)!!;
    @assert(sent == (sz)msg.len, "send_to failed");

    poll.poll(&events, 1000)!!;
    @assert(!events.is_empty(), "poll timeout");

    for (sz i = 0; i < events.len; i++)
    {
        mio::Event* event = events.get(i);
        if (event == null) continue;

        if (event.fd == server.fd && event.read)
        {
            char[128] buf;
            char[64] ip_buf;
            ushort port = 0;

            sz n = server.recv_from(buf[..], ip_buf[..], &port)!!;

            String ip = (String)ip_buf[0:string::strlen(&ip_buf[0])];
            sz echoed = server.send_to(buf[0:n], ip, port)!!;

            @assert(echoed == n, "udp echo failed");

            warn("OK");
            return;
        }
    }
}
```

## Address helpers

```c3
char[64] ip_buf;
ushort port = 0;

listener.local_addr(ip_buf[..], &port)!!;
stream.local_addr(ip_buf[..], &port)!!;
stream.peer_addr(ip_buf[..], &port)!!;
udp.local_addr(ip_buf[..], &port)!!;
```

## Error handling

Most fallible functions return C3 option/fault results.

Common module faults:

```c3
MIO_INVALID
MIO_CLOSED
MIO_FULL
MIO_UNSUPPORTED
NET_ADDR_ERROR
NET_SOCKET_ERROR
NET_BIND_ERROR
NET_LISTEN_ERROR
NET_ACCEPT_ERROR
NET_CONNECT_ERROR
```

Platform errors are generally mapped through `c::errno`.

Readiness does not remove the need to check operation results. A socket may report readable or writable and still return an error when the operation is attempted.

## Threading

`Poll.register()`, `Poll.reregister()`, and `Poll.deregister()` are mutex-protected and wake the poll loop after registry changes.

This supports a common pattern:

- one thread blocks in `poll.poll()`
- another thread registers, modifies, or deregisters fds
- the internal waker wakes the polling thread

The returned `Events` buffer should be owned by the polling thread.

## Notes

- `ext::mio` does not provide task scheduling.
- `ext::mio` does not provide futures.
- `ext::mio` does not retry reads or writes automatically.
- `ext::mio` does not guarantee full writes.
- `ext::mio` does not abstract protocols beyond basic TCP and UDP helpers.
- `ext::mio` is suitable as the poller layer under `ext::aio`.

## Recommended test coverage

Useful tests include:

[../../test/mio](../../test/mio)

- TCP connect/read/write
- TCP listener accept
- threaded TCP echo
- UDP send/receive
- waker wake/drain
- register/reregister/deregister
- invalid API calls
- address helpers
- closed socket behavior
- timeout behavior
- batch readiness
- cross-thread registration wakeups

## License

MIT License.


This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

// eof