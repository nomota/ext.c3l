# Fiber - Lightweight coroutines for C3

`ext::fiber` provides lightweight, cooperative, non-preemptive coroutines for C3.

It is inspired by [libco](https://github.com/higan-emu/libco) and provides a small execution-context abstraction that lets you create, switch, yield, and delete fibers within a single thread.

This module is part of the extended C3 library.

Back to [ext.c3l](../../README.md).

---

## Overview

A fiber is a manually scheduled execution context with its own stack.

Unlike OS threads, fibers are not scheduled by the kernel. They run cooperatively: execution switches only when you explicitly call `fiber::switch_to()` or `fiber::yield()`.

Typical use cases include:

- cooperative schedulers
- async runtimes
- lightweight task systems
- protocol parsers
- generators/state machines that benefit from stackful execution

---

## Backends

The implementation is selected at compile time.

### Current backends

| Platform | Backend |
|---------|---------|
| POSIX x86-64 | Assembly context switching, System V ABI |
| Windows x86-64 | Assembly context switching, Win64 ABI |
| POSIX AArch64 | Assembly context switching |
| Windows | Native Windows Fiber API |
| POSIX fallback | `ucontext` |
| POSIX experimental | `sigsetjmp()` / `siglongjmp()` |

The assembly backends are the preferred fast-switching backends where supported.

---

## Available module

| Module | Description |
|--------|-------------|
| `ext::fiber` | Fiber operations: `create()`, `delete()`, `active()`, `switch_to()`, `yield()`, `done()`, `stack_used()`, `deinit()` |

---

## Files

| File | Description |
|------|-------------|
| `fiber.config.c3` | Compile-time backend selection |
| `fiber.vm.posix.c3` | POSIX virtual-memory stack allocator |
| `fiber.vm.win32.c3` | Windows virtual-memory stack allocator |
| `fiber.asm.c3` | POSIX assembly backend for x86-64 System V and AArch64 |
| `fiber.asm.win32.c3` | Windows x86-64 assembly backend |
| `fiber.asm.x86_64.c3` | x86-64 System V machine-code switch routine |
| `fiber.asm.x86_64.win32.c3` | x86-64 Win64 machine-code switch routine |
| `fiber.asm.aarch64.c3` | AArch64 machine-code switch routine |
| `fiber.win32.c3` | Native Windows Fiber API backend |
| `fiber.ucontext.c3` | POSIX `ucontext` backend |
| `fiber.sjlj.c3` | POSIX `sigsetjmp()` / `siglongjmp()` backend |
| `../../test/fiber/fiber_test.c3` | Basic fiber example |
| `../../test/fiber/fiber_mem_test.c3` | Fiber memory usage test |

---

## How it works

1. `fiber::active()` returns the currently running fiber.
2. `fiber::create()` creates a new fiber with its own stack.
3. The coroutine function has a plain `fn void()` signature.
4. `fiber::switch_to(fib)` transfers execution to the target fiber.
5. `fiber::yield()` switches back to the primary fiber.
6. At the end of a coroutine, call `fiber::done()`.
7. Release a completed fiber with `fiber::delete()`.

Fibers are stackful. If a fiber yields from deep inside a call chain, execution later resumes from exactly that point.

---

## API

```c3
import ext::fiber;

alias Coroutine = fn void();

Fiber*? fiber::create(Coroutine entry, uint stack_size = 128_000, void* arg = null);
Fiber* fiber::active();

void fiber::switch_to(Fiber* fib);
void fiber::yield();
void fiber::done();

void fiber::delete(Fiber* fib);
void fiber::deinit();

sz fiber::stack_used(Fiber* fib);
void fiber::diag();
```

### `fiber::create()`

```c3
Fiber*? fib = fiber::create(&my_coroutine, 128_000, arg);
```

Creates a new fiber.

Arguments:

| Argument | Description |
|----------|-------------|
| `entry` | Coroutine entry function. Must be `fn void()` |
| `stack_size` | Requested stack size in bytes |
| `arg` | Optional user pointer attached to the fiber |

Inside a coroutine, the argument can be accessed through the active fiber:

```c3
void* arg = fiber::active().arg;
```

The minimum stack size is 64 KB. Smaller values are rounded up internally.

### `fiber::active()`

```c3
Fiber* current = fiber::active();
```

Returns the currently running fiber.

### `fiber::switch_to()`

```c3
fiber::switch_to(fib);
```

Switches execution to another fiber.

Control returns when the target fiber yields, switches back, or finishes.

### `fiber::yield()`

```c3
fiber::yield();
```

Switches execution back to the primary fiber.

This is the usual coroutine suspend point.

### `fiber::done()`

```c3
fiber::done();
```

Marks the current fiber as finished and yields back to the primary fiber.

A coroutine should call this before returning.

### `fiber::delete()`

```c3
fiber::delete(fib);
```

Releases a fiber.

Do not delete the currently running fiber.

### `fiber::stack_used()`

```c3
sz used = fiber::stack_used(fib);
```

Returns an approximate stack usage value where supported.

Availability and accuracy depend on the backend.

### `fiber::deinit()`

```c3
fiber::deinit();
```

Cleans up fiber module state.

All non-primary fibers should be deleted before calling this.

---

## Important notes

- Fibers are cooperative only.
- Fibers are not OS threads.
- Fibers must not be shared across threads.
- A fiber only stops running when it calls `fiber::yield()`, `fiber::switch_to()`, or `fiber::done()`.
- A coroutine should call `fiber::done()` before returning.
- Do not delete the currently running fiber.
- Always delete fibers you no longer need.
- Stack size is fixed at creation time.
- Large local arrays or deep call chains require larger stacks.
- `fiber::active().arg` can be used to retrieve the user argument inside a coroutine.

---

## Stack allocation

Assembly and POSIX backends use virtual-memory backed stacks.

The default stack allocator uses guard-page mode.

### Guard-page mode

```text
[ guard page ][ usable stack ]
```

The guard page is `PROT_NONE` or no-access.

This catches stack overflow immediately, but each stack may consume additional virtual memory map entries.

On Linux, large numbers of guarded stacks may be limited by `vm.max_map_count`.

---

## Usage example

```c3
module example;

import std::io;
import ext::fiber;

int counter = 0;

fn void my_coroutine()
{
    for (int i = 0; i < 3; i++)
    {
        counter++;
        io::printfn("coroutine step %d", i);
        fiber::yield();
    }

    io::printfn("coroutine done");

    fiber::done();
}

fn void main()
{
    Fiber* co = fiber::create(&my_coroutine);

    for (int step = 0; step < 4; step++)
    {
        io::printfn("scheduler step %d", step);
        fiber::switch_to(co);
    }

    fiber::delete(co);
    fiber::deinit();

    io::printfn("all done, counter = %d", counter);
}
```

Expected output:

```text
scheduler step 0
coroutine step 0
scheduler step 1
coroutine step 1
scheduler step 2
coroutine step 2
scheduler step 3
coroutine done
all done, counter = 3
```

---

## Example with argument

```c3
module example_arg;

import std::io;
import ext::fiber;

struct TaskArg
{
    int id;
    int count;
}

fn void worker()
{
    TaskArg* arg = (TaskArg*)fiber::active().arg;

    for (int i = 0; i < arg.count; i++)
    {
        io::printfn("fiber %d step %d", arg.id, i);
        fiber::yield();
    }

    fiber::done();
}

fn void main()
{
    TaskArg myarg = {
        .id = 1,
        .count = 3,
    };

    Fiber* fib = fiber::create(&worker, arg: &myarg);

    while (!fib.done)
    {
        fiber::switch_to(fib);
    }

    fiber::delete(fib);
    fiber::deinit();
}
```

---

## Backend selection

Backend selection is configured in `fiber.config.c3`.

Example:

```c3
// fiber.config.c3
module ext::fiber;

const bool ASM_X86_64_SYSV = env::POSIX && env::X86_64;
const bool ASM_X86_64_WIN64 = env::WIN32 && env::X86_64;
const bool ASM_AARCH64 = env::POSIX && env::AARCH64;

const bool SJLJ = false;
const bool UCONTEXT = false;
const bool WINFIBER = false;
```

Only one backend should be active for a given target.

---

Back to [ext.c3l](../../README.md).
