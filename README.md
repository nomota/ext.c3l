# ext.c3l - extended C3 library

An extended library for the C3 programming language, providing essential system-level functionality, networking capabilities, and cross-platform C header bindings, and more

## Overview

`ext.c3l` bridges the gap between C3 and system-level programming by providing:
- C header bindings (POSIX and Win32)
- Networking APIs (TCP, UDP, DNS)
- File system and I/O utilities
- Regular expression support
- Fiber coroutine 
- Async I/O framework
- SIMD Json parser

## Why ext library?

C3 standard library is minimalistic, lacks something. Ext library fills the gap.

## Installation

### Prerequisites

First, install the `c3l` library manager:

```bash
git clone https://github.com/konimarti/c3l
cd c3l
sudo make install
```

### Adding ext.c3l to your project

In your C3 project directory, fetch the library by:

```bash
# fetch from the source
c3l fetch https://github.com/nomota/ext.c3l

# to update to latest version
c3l update ext.c3l
```

This will download the library as a zip-packed file: `lib/ext.c3l`.

And in your `project.json`, "ext" gets added like this.
```json
    "dependancies": [ "ext" ],
```

Now it's ready to be used in your project.

You can compile your code like this.

```bash
# put `--lib ext` to compile command
c3c compile --lib ext yourcode.c3
```

## Available library modules

### C Header Bindings 

* [ext/c](ext/c)

Provides bridge modules to C header files for both POSIX and Windows platforms:

| C Header | C3 Module | Import Statement |
|----------|-----------|------------------|
| `stdio.h` | `stdio.h.c3` | `import c::stdio;` |
| `unistd.h` | `unistd.h.c3` | `import c::unistd;` |
| `netinet/in.h` | `netinet.in.h.c3` | `import c::netinet::in;` |
| `winsock2.h` | `winsock2.h.c3` | `import c::winsock2;` |
| ... | ... | ... |

- More about [C Header bindings](ext/c/README.md)


### Networking 

* [ext/net](ext/net)

High-level networking capabilities including TCP, UDP, and DNS:

| Module | Description |
|--------|-------------|
| `ext::io::tcp` | TCP operations: new(), new_listen(), listen(), connect(), accept(), send(), recv(), read(), write(), readline(), set_non_blocking(), close()|
| `ext::io::udp` | UDP operations: new(), new_bind(), bind(), send(), recv(), sendto(), recvfrom(), set_non_blocking(), close() |
| `ext::io::dns` | DNS operations: get_addrinfo() |


- More about [Networking APIs](ext/net/README.md)


### I/O Operations

* [ext/io](ext/io)

File system operations including stat, directory handling, and file utilities:

| Module | Description |
|--------|-------------|
| `ext::io::stat` | File stat operations: exists(), size(), is_(file/dir/link), is_(readable/writable/executable), read_link(), link(), symlink(), last_modified(), change_mode() |
| `ext::io::cfile` | File operations: open(), close(), read(), read_byte(), write(), write_byte(), printf(), seek(), tell(), eof(), load(), save(), copy(), rename(), remove(), exists(), size(), last_modified(), is_file(), is_dir(), change_mode() |
| `ext::io::dir` | Directory/folder operations: get_cur_dir(), change_dir(), make_dir(), remove_dir(), rename(), list_dir(), exists(), is_dir(), is_file(), change_mode(), scan_dir() |

- More about [I/O Operations](ext/io/README.md)

### Hash Operations

* [ext/hash](ext/hash)

| Module | Description |
|--------|-------------|
| `ext::hash::murmur` | MurmurHash3 functions: hash3_x86_32(), hash3_x86_128(), hash3_x64_128() |
| `ext::hash::city` | CityHash functions: hash64(), hash64_with_seed(), hash128(), hash128_with_seed(), hash128_crc(), hash128_ rc_with_seed() |

- More about [Hash Operations](ext/hash/README.md)


### Regular Expressions

Regex support for C3 based on C regex library.

| Module | Description |
|--------|-------------|
| `ext::regex` | RegEx operations: new_compile(), match(), group(), free(), replace(), split(), reg_match(), reg_replace(), reg_split();|
| `slre` | SLRE operations: compile(), match(), reg_match(), reg_replace() |


* [ext/regex](ext/regex)
- More about [Regular Expressions](ext/regex/README.md)

### Fiber coroutine

It provides a lightweight cooperative multitasking system, allowing you to create and switch between multiple execution contexts (fibers) within a single thread.

Based on:
* X86_64, AARCH64: Assembly code, fast switching
* Windows: Native Fiber interface
* Other Posix: based on sigsetjmp() /siglongjmp()

| Module | Description |
|--------|-------------|
| `ext::fiber` | Fiber operations: create(), delete(), active(), switch_to(), yield() |

* [ext/fiber](ext/fiber)
- More about [Fiber Coroutine](ext/fiber/README.md)

### Async I/O 

Coroutine-based asynchronous I/O framework for C3.

`ext::aio` provides an event loop, cooperative tasks, futures, synchronization primitives, TCP streams, UDP datagrams, callback-style protocol handlers, and executor-backed file/path operations.

It is built on top of the [fiber](../fiber/README.md) coroutine module.

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

* [ext/io](ext/aio)
- More about [Async I/O for C3](ext/aio/README.md)


## Debugging macros

`ext::debug` is for giving debugging macros within a library.

| Module | Description |
|--------|-------------|
| `ext::debug` | Debugging macros: warn(), @assert(), @debug_leak(), set_debug() |

* [ext/debug](ext/debug)
- More about [Debugging macros](ext/debug/README.md)

### Memory allocation macros

`ext::mem` is for giving memory allocation macros within a library.

| Module | Description |
|--------|-------------|
| `ext::mem` | Allocation macros: set_allocator(), mem_alloc(), mem_malloc(), mem_alloc_array(), mem_copy(), mem_copy_str(), mem_free(), temp_alloc(), temp_malloc(), temp_alloc_array(), temp_free(), LocalAllocator |

* [ext/mem](ext/mem)
- More about [Allocation macros](ext/mem/README.md)

### Serializer - various encoder/decoder

`ext::serializer` module is to fill missing gaps of C3 std lib by providing various encoders/decoders.

| Module | Description |
|--------|-------------|
| `ext::serializer::json` | JSON serializer: JsonObject, JsonArray, JsonValue, JsonNull, JsonBool, JsonNumber, String, bool, long, double, null, decode(), encode() |
| `ext::serializer::http` | HTTP/1.x parser: `Request`, `Response`, `Url`, `SetCookie`, `FormFile`, `KeyValue`, `parse_request()`, `parse_response()`, decode helpers |
| `ext::serializer::simdjson` | SIMD JSON parser: `ParseResult`, `JsonValue`, `TapeEntry`, `TapeType`, `parse()`, `dump_tape()` |

* More about [Serializers, Encode/decoders](ext/serializer/README.md)


## Usage by test

* [test/hash](test/hash)
* [test/regex](test/regex)
* [test/io](test/io)
* [test/net](test/net)
* [test/fiber](test/fiber)
* [test/asyncio](test/asyncio)
* [test/aiofiles](test/aiofiles)
* [test/serializer](example/serializer)


## Platform Support

- **POSIX** systems (Linux, macOS, BSD variants)
- **Windows** (Win32 API support)

Cross-platform compatibility is a primary goal, with platform-specific implementations abstracted behind unified APIs where possible.

## Contributing

Contributions are welcome! When submitting pull requests:

1. Ensure cross-platform compatibility
2. Update relevant README files in sub-libraries
3. Follow existing code style and conventions
4. Test on both POSIX and Windows platforms when applicable

## Repository

GitHub: [https://github.com/nomota/ext.c3l](https://github.com/nomota/ext.c3l)

## License

MIT License

---

For detailed documentation on specific modules, please refer to the README files in each subdirectory under `ext/`.
