// ext/c/README.md 

# c - C Standard Header Bindings for C3

`c` provides C header bindings for the [C3 programming language](https://c3-lang.org/). It exposes standard C library, POSIX, BSD, macOS, and Windows system APIs as C3 modules so that low-level system code can be written directly in C3.

This package is designed as a foundation for higher-level C3 libraries, including networking, file I/O, asynchronous I/O, process handling, and other system-level utilities.

## Overview

The `c` package maps C headers to C3 modules. It allows C3 programs to call native C and operating-system APIs with minimal wrapping while still following C3 naming and module conventions.

It is especially useful when:

- translating existing C code to C3
- writing low-level or system-level libraries
- accessing POSIX or Windows APIs directly
- building cross-platform abstractions on top of native APIs

## Features

- **Cross-platform bindings** for POSIX, BSD, macOS, and Windows APIs
- **Standard C library coverage**, including I/O, strings, memory, math, time, and process support
- **Networking support**, including sockets, TCP, UDP, DNS, and Winsock bindings
- **File-system and directory APIs** for both POSIX and Windows
- **Threading and synchronization APIs**, including POSIX threads and Windows synchronization primitives
- **Direct C interop** through C3 `extern` declarations and `@cname`
- **Translation-friendly naming**, making C-to-C3 porting straightforward
- **Foundation for higher-level libraries** such as `ext::aio`, `ext::net`, and file-system utilities

## Usage

Import the modules you need:

```c3
import c::stdio;
import c::unistd;
import c::sys::socket;
import c::errno;
```

Call C functions through their C3 module namespace:

```c3
import c::stdio;

fn void main()
{
    stdio::printf("Hello from ext::c!\n");
}
```

## POSIX Example

```c3
import c::sys::socket;
import c::netinet::in;
import c::unistd;
import c::errno;

fn int? create_server_socket(ushort port)
{
    int sockfd = socket::socket(socket::AF_INET, socket::SOCK_STREAM, 0);
    if (sockfd < 0) return errno::get_fault()~; // POSIX/Windows `errno` to C3 `fault`

    /*
     * bind(), listen(), and other socket setup code would follow here.
     */

    return sockfd;
}
```

## Windows Example

```c3
import c::winsock2;
import c::ws2tcpip;

fn void? init_networking()
{
    WSAData wsa_data;

    int rc = winsock2::wsaStartup(0x0202, &wsa_data);
    if (rc != 0) return winsock2::wsa_fault()~; // wsaGetLaseError() to C3 `fault`
}
```

## Naming Differences from C

C3 has stricter naming rules than C, so these bindings cannot always preserve C names exactly as C3 identifiers.

The original C symbol name is preserved with `@cname` when needed.

General rules used by this package:

- Types and structs use **PascalCase**
- Variables and functions use **lowercase or camelCase**
- Constants and faults use **UPPERCASE**
- C function names that do not follow C3 naming rules are mapped with `@cname`

Example:

```c
/* C: winsock2.h */

struct WSADATA
{
};

int WSAStartup(unsigned short version_required, struct WSADATA* wsa_data);
```

```c3
// C3: winsock2.h.c3

struct WSAData @cname("WSADATA")
{
}

extern fn int wsaStartup(ushort version_required, WSAData* wsa_data)
    @cname("WSAStartup");
```

## Module Naming Convention

C header files are mapped to C3 modules using the following pattern:

| C header | C3 file | C3 import |
|----------|---------|-----------|
| `stdio.h` | `stdio.h.c3` | `import c::stdio;` |
| `unistd.h` | `unistd.h.c3` | `import c::unistd;` |
| `sys/socket.h` | `sys.socket.h.c3` | `import c::sys::socket;` |
| `netinet/in.h` | `netinet.in.h.c3` | `import c::netinet::in;` |
| `winsock2.h` | `winsock2.h.c3` | `import c::winsock2;` |

## Available Modules

### POSIX and Unix Headers

| Module | Description |
|--------|-------------|
| `c::arpa::inet` | Internet address manipulation |
| `c::complex` | Complex number mathematics |
| `c::dirent` | Directory operations |
| `c::errno` | `errno()` access and errno-to-fault conversion |
| `c::fcntl` | File control operations |
| `c::math` | Mathematical functions |
| `c::netdb` | Network database operations |
| `c::netinet::in` | Internet protocol family definitions |
| `c::netinet::tcp` | TCP protocol definitions |
| `c::netinet::udp` | UDP protocol definitions |
| `c::poll` | I/O multiplexing |
| `c::pthread` | POSIX threads |
| `c::regex` | Regular expressions |
| `c::signal` | Signal handling |
| `c::spawn` | Process spawning |
| `c::stddef` | Standard type definitions |
| `c::stdio` | Standard input and output |
| `c::stdlib` | Standard library functions |
| `c::string` | String and memory operations |
| `c::sys::ioctl` | Device and terminal control operations |
| `c::sys::mman` | Memory mapping and memory protection |
| `c::sys::socket` | Socket interface |
| `c::sys::stat` | File status and permissions |
| `c::sys::time` | Time-related structures and functions |
| `c::sys::wait` | Process waiting |
| `c::termios` | Terminal I/O control |
| `c::time` | Time and date functions |
| `c::unistd` | POSIX operating system API |

More mappings are available in the [`c`](./) directory.

Example usage files:

- [`../net/tcp.posix.c3`](../net/tcp.posix.c3)
- [`../io/dir.posix.c3`](../io/dir.posix.c3)

### Windows Headers

| Module | Description |
|--------|-------------|
| `c::errhandlingapi` | Error handling functions |
| `c::fileapi` | File management functions |
| `c::handleapi` | Handle management |
| `c::io` | Low-level I/O operations |
| `c::ioapiset` | Overlapped I/O and I/O completion port APIs |
| `c::memoryapi` | Memory management functions |
| `c::process` | Process control |
| `c::processthreadapi` | Process and thread functions |
| `c::synchapi` | Synchronization functions |
| `c::sysinfoapi` | System information functions |
| `c::windows` | Core Windows API declarations |
| `c::winioctl` | Windows device I/O control codes and structures |
| `c::winsock2` | Windows Sockets 2 |
| `c::ws2tcpip` | Windows TCP/IP helper functions |
| `c::errno` | Windows error and Winsock error to C3 fault conversion |

More mappings are available in the [`c`](./) directory.

Example usage files:

- [`../net/tcp.win32.c3`](../net/tcp.win32.c3)
- [`../io/dir.win32.c3`](../io/dir.win32.c3)

## Use Cases

### C Code Translation

The bindings keep the shape of C APIs close to the original headers, making it easier to port C code to C3 while preserving the original control flow and system calls.

### System Programming

Use native operating-system APIs directly from C3 for file descriptors, handles, memory mapping, sockets, processes, terminals, and other low-level resources.

### Network Programming

Build TCP, UDP, DNS, and socket-based libraries using POSIX sockets or Winsock through a common C3 binding style.

### File-System Programming

Access file metadata, permissions, directories, symbolic links, device information, and platform-specific file operations.

### Cross-Platform Libraries

Build higher-level portable libraries by placing POSIX and Windows implementations behind a common C3 API.

## Related Libraries

This package is part of the extended C3 library collection.

Back to [`ext.c3l`](../../README.md).

## Browsing Headers

Browse the available header mappings in the [`c`](./) directory.

// eof
