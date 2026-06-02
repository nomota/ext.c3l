// ext/wepoll/README.md 

# c::wepoll

Windows-only epoll-compatible polling API for C3.

This module is a C3 port of [wepoll](https://github.com/piscisaureus/wepoll), an epoll-like event polling implementation for Windows sockets. It provides a small subset of the Linux `epoll` API on top of Windows AFD polling and IOCP.

The module is intended for poller-style networking code, especially code that wants to share a POSIX-like polling interface across Linux, BSD, macOS, and Windows backends.

## Module

```c3
module c::wepoll @if(env::WIN32) @link("ws2_32", "kernel32");
```

Import it with:

```c3
import c::wepoll;
```

You normally also need Winsock bindings:

```c3
import c::winsock2;
import c::ws2tcpip;
```

## Available

| Module | Feature |
|--------|--------|
| `c::wepoll` | `epoll_create()`, `epoll_create1()`, `epoll_close()`, `epoll_ctl()`, `epoll_wait()` |
| commands | `EPOLL_CTL_ADD`, `EPOLL_CTL_MOD`, `EPOLL_CTL_DEL` |
| polls | `EPOLLIN`, `EPOLLOUT` |
| events | `EPOLLERR`, `EPOLLHUP`, `EPOLLRDHUP`, `EPOLLONESHOT` |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

## Public types

```c3
alias Handle = void*;
alias Socket = usz;
alias EPollFd = Handle;
```

```c3
union EpollData
{
    void* ptr;
    int fd;
    uint u32;
    ulong u64;
    Socket sock;
    Handle hnd;
}

struct EPollEvent
{
    uint events;
    EpollData data;
}
```

`EPollEvent.data` is user-owned data. The poller stores and returns it unchanged when an event is reported.

## Constants

Control operations:

```c3
const int EPOLL_CTL_ADD = 1;
const int EPOLL_CTL_MOD = 2;
const int EPOLL_CTL_DEL = 3;
```

Events:

```c3
const uint EPOLLIN      = 1u << 0;
const uint EPOLLPRI     = 1u << 1;
const uint EPOLLOUT     = 1u << 2;
const uint EPOLLERR     = 1u << 3;
const uint EPOLLHUP     = 1u << 4;
const uint EPOLLRDNORM  = 1u << 6;
const uint EPOLLRDBAND  = 1u << 7;
const uint EPOLLWRNORM  = 1u << 8;
const uint EPOLLWRBAND  = 1u << 9;
const uint EPOLLMSG     = 1u << 10;
const uint EPOLLRDHUP   = 1u << 13;
const uint EPOLLONESHOT = 1u << 31;
```

## API

### epoll_create

```c3
fn EPollFd wepoll::epoll_create(int size);
```

Creates a new epoll handle.

`size` must be greater than zero. It is accepted for Linux API compatibility and is otherwise ignored.

Returns `null` on failure.

### epoll_create1

```c3
fn EPollFd wepoll::epoll_create1(int flags);
```

Creates a new epoll handle.

`flags` must currently be `0`.

Returns `null` on failure.

### epoll_close

```c3
fn int wepoll::epoll_close(EPollFd ephnd);
```

Closes an epoll handle and releases all internal socket state associated with it.

Returns `0` on success and `-1` on failure.

### epoll_ctl

```c3
fn int wepoll::epoll_ctl(EPollFd ephnd, int op, Socket sock, EPollEvent* event);
```

Adds, modifies, or removes a socket registration.

For `EPOLL_CTL_ADD` and `EPOLL_CTL_MOD`, `event` must not be `null`.

For `EPOLL_CTL_DEL`, `event` may be `null`.

Returns `0` on success and `-1` on failure.

### epoll_wait

```c3
fn int wepoll::epoll_wait(EPollFd ephnd, EPollEvent* events, int maxevents, int timeout);
```

Waits for readiness events.

`timeout` uses milliseconds:

| Value | Meaning |
|------:|---------|
| `0` | Poll without blocking |
| `> 0` | Wait up to this many milliseconds |
| `< 0` | Wait indefinitely |

Returns the number of events, `0` on timeout, or `-1` on failure.

## Basic UDP example

```c3
import c::winsock2;
import c::ws2tcpip;
import c::wepoll;
import ext::debug;

fn void main()
{
    winsock2::WSAData data;
    int rc = winsock2::wsaStartup(0x0202, &data);
    @assert(rc == 0, "WSAStartup failed");

    winsock2::Socket server = winsock2::socket(
        winsock2::AF_INET,
        winsock2::SOCK_DGRAM,
        winsock2::IPPROTO_UDP
    );

    @assert(server != winsock2::INVALID_SOCKET, "server socket failed");
    defer winsock2::closesocket(server);

    uint nonblock = 1;
    rc = winsock2::ioctlsocket(server, winsock2::FIONBIO, &nonblock);
    @assert(rc == 0, "server nonblock failed");

    winsock2::SockAddrIn addr = {};
    addr.sin_family = (ushort)winsock2::AF_INET;
    addr.sin_port = winsock2::htons(19094);

    rc = winsock2::inet_pton(
        winsock2::AF_INET,
        "127.0.0.1",
        &addr.sin_addr
    );

    @assert(rc == 1, "inet_pton failed");

    rc = winsock2::bind(
        server,
        (winsock2::SockAddr*)&addr,
        (int)@sizeof(addr)
    );

    @assert(rc == 0, "bind failed");

    wepoll::EPollFd epfd = wepoll::epoll_create1(0);
    @assert(epfd != null, "epoll_create1 failed");
    defer wepoll::epoll_close(epfd);

    wepoll::EPollEvent event = {};
    event.events = wepoll::EPOLLIN;
    event.data.sock = (wepoll::Socket)server;

    rc = wepoll::epoll_ctl(
        epfd,
        wepoll::EPOLL_CTL_ADD,
        (wepoll::Socket)server,
        &event
    );

    @assert(rc == 0, "epoll_ctl ADD failed");

    wepoll::EPollEvent[8] events;

    int n = wepoll::epoll_wait(
        epfd,
        &events[0],
        events.len,
        1000
    );

    @assert(n >= 0, "epoll_wait failed");
}
```

## Implementation notes

This port follows the original wepoll architecture:

1. An epoll handle owns a Windows IOCP handle.
2. Socket readiness is requested through AFD polling.
3. AFD poll completions are received through IOCP.
4. Socket state is stored in internal trees and queues.
5. Handle lifetime is protected by a small reference lock.

The implementation loads selected `ntdll.dll` routines dynamically:

```text
NtCancelIoFileEx
NtCreateFile
NtCreateKeyedEvent
NtDeviceIoControlFile
NtReleaseKeyedEvent
NtWaitForKeyedEvent
RtlNtStatusToDosError
```

The AFD device path used by the implementation is:

```text
\\Device\\Afd\\Wepoll
```


### Socket-only behavior

This module is designed for Winsock sockets. It is not a general Windows handle poller.

### AFD internals

The implementation depends on undocumented AFD behavior, following the original wepoll design. This is expected for wepoll-style Windows epoll emulation.

### Edge-triggering

`EPOLLET` is not currently defined or implemented in this port.

## Test programs

[../../test/wepoll](../../test/wepoll)

## License

This C3 port is based on wepoll:

```text
https://github.com/piscisaureus/wepoll
```

Original copyright:

```text
Copyright 2012-2020, Bert Belder <bertbelder@gmail.com>
```

Keep the original BSD-style license text with the ported source file.


This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

// eof