// fiber.asm.c3

// Fast context switching by assembly code

// Nomota <hiongun@gmail.com>; MIT License

module ext::thread::fiber @if(env::X86_64 || env::AARCH64);

import c::unistd;
import c::sys::mman;
import std::io;
import c::string;
import c::stdlib;
import c::stdio;
import c::windows;
import c::memoryapi;
import c::winnt;
import ext::debug;
import ext::mem;

alias SwapFn = fn void(void*, void*) @callconv("stdcall");

struct Fiber {
    void* handle;
    char* block;
    usz stack_size;
    bool done;
}

tlocal long[64] _buffer;
tlocal Fiber* running = null;
tlocal Fiber primary;

SwapFn asm_swap = null;

char[4096] asmblock @align(4096);

const char[] CANARY = "CANARYCANARYCANARYCANARY"; // 24 bytes

tlocal LocalAllocator localmem = {};

fn void init(Allocator allocx = mem, bool debug = true) @private
{
    if (running != null) return;
    if (localmem == (LocalAllocator){}) {
        localmem = mem;
    }
    debug::set_debug(debug);

  $if env::WIN32:
    asmblock[0:ASMWIN64.len] = ASMWIN64[0:ASMWIN64.len];
 
    ulong addr = (ulong)(void*)&asmblock;

    // Windows page alignment
    ulong page_size = 8192;
    ulong base = addr & ~(page_size - 1);
    ulong size = (addr - base) + (ulong)asmblock.len;
    windows::DWord old_protect;

    windows::Bool ok = memoryapi::virtualProtect((void*)base, (usz)size, winnt::PAGE_EXECUTE_READ, &old_protect);

    if (ok != windows::TRUE) {
        stdio::printf("VirtualProtect failed\n");
        stdlib::exit(1);
    }
  $else // POSIX
    asmblock[0:ASM.len] = ASM[0:ASM.len];
    
    ulong addr = (ulong)(void*)&asmblock;
    ulong page_size = (ulong)unistd::sysconf(unistd::_SC_PAGESIZE);
    ulong base = addr - (addr % page_size);
    ulong size = (addr - base) + (ulong)asmblock.len;

    mman::mprotect((void*)base, (usz)size,
        mman::PROT_READ | mman::PROT_EXEC);
  $endif

    asm_swap = (SwapFn)(void*)&asmblock;

    primary = {
        .handle = (void*)&_buffer[0],
        .block = null,
        .stack_size = 0,
        .done = false,
    };
    
    running = &primary;
}

fn void deinit()
{
    if (running == null) return;
    primary = {};
    running = null;
}

// 
// crash — safety net if a coroutine entrypoint ever returns
// 

fn void crash() @noreturn @private
{
    unreachable("crash");
}

// 
// Public API
// 

/// Return the currently active coroutine handle.
fn Fiber* active()
{
    if (running == null) init();

    return running;
}

/*
### Stack Layout (x86-64)

memory (handle base)
┌──────────────────┐
│  handle[0]       │  ← initial rsp (points to p)
│  handle[1..N]    │  ← callee-saved registers saved here after first swap
│  ...             │
│  &crash          │  ← *p+1  (guard: called if entrypoint returns)
│  entrypoint addr │  ← *p    (popped → rax, then jmp rax)
└──────────────────┘  ← stack_top (16-byte aligned, 32 bytes below raw top)
*/

/// Create a coroutine in caller-supplied memory (zero-copy).
alias Coroutine = fn void();
fn Fiber* create(uint stack_size, Coroutine coroutine)
{
    if (running == null) init();

    Fiber* fiber = localmem.alloc(Fiber);
    fiber.done = false;
    fiber.stack_size = stack_size;

    char* block;

    if (debug::debug) {
        block = localmem.malloc(stack_size + CANARY.len*2);
        string::memset(&block[0], 'Z', stack_size+CANARY.len*2);
        string::memcpy(&block[0], CANARY.ptr, CANARY.len);
        string::memcpy(&block[stack_size+CANARY.len], CANARY.ptr, CANARY.len);
    } else {
        block = localmem.malloc(stack_size);
    }

    fiber.block = block; // == canary+stack+canary
    @assert(fiber.block != null, "error");
    
    void *handle = block+CANARY.len;
    fiber.handle = handle; // stack

    // Build the initial stack layout:
    //
    //   handle[0]  = rsp  → points to p below
    //
    //   stack grows downward:
    //   ┌──────────────┐ ← stack_top (16-byte aligned, 32 bytes reserved)
    //   │  &crash      │ ← called if entrypoint returns
    //   │  entrypoint  │ ← popped into rax by the swap stub, then jmp rax
    //   └──────────────┘ ← p  (stored as initial rsp in handle[0])

    ulong stack_top = (ulong)handle + stack_size;
    stack_top -= 32; // shadow space / ABI reserve
    stack_top &= ~((ulong)15); // 16-byte alignment

    long* p = (long*)stack_top;
    p--;
    *p = (long)(void*)&crash; // return address guard
    p--;
    *p = (long)(void*)coroutine; // initial instruction pointer

    *((long*)handle) = (long)p; // store rsp in handle[0]

    return fiber;
}

fn void check_canary(Fiber* fiber) @inline @private
{
    if (!debug::debug) return;
    if (fiber == &primary) return; // primary has no block
    @assert(fiber.block != null, "error");
    
    usz stack_size = fiber.stack_size;

    if (string::strncmp(fiber.block, CANARY.ptr, CANARY.len) != 0) {
        warn("Prefix canary breached, fiber stack size is too small. current stack_size:%d", stack_size);
        stdlib::exit(0);
    }

    if (string::strncmp(fiber.block + stack_size+CANARY.len, CANARY.ptr, CANARY.len) != 0) {
        warn("Postfix canary breached, fiber stack size is too small. current stack_size:%d", stack_size);
        stdlib::exit(0);
    }
    
    usz used = stack_used(fiber);
    float usage = (float)used/(float)stack_size;
    if (usage > (float)0.9) {
        warn("STACK WARN stack_size:%d, used:%d, usage:%.1f%%, fiber stack size need to be enlarged", stack_size, used, usage*100);
    }
}

fn void diag()
{
    Fiber* fiber = active();
    if (fiber == &primary) {
        warn("it's primary fiber");
        return; // primary has no block
    }
    
    @assert(fiber.block != null);

    usz stack_size = fiber.stack_size;

    warn("stack low:%p, high:%p", fiber.handle, fiber.handle+stack_size);
    
    usz used = stack_used(fiber);
    float usage = (float)used/(float)stack_size;
    warn("stack_size:%d, used:%d, usage:%.1f%%", stack_size, used, usage*100);
    
    check_canary(fiber);
}

fn usz stack_used(Fiber* fiber)
{
    if (!debug::debug) return 0;
    if (fiber == &primary) return 0; // primary has no block
    @assert(fiber.block != null, "error");
    
    usz stack_size = fiber.stack_size;
    usz untouched = 0;
    for (isz i = 0; i < stack_size; i++) {
        usz idx = CANARY.len+i;
        if (fiber.block[idx] == 'Z') {
            untouched += 1;
        }
    }
    return stack_size - untouched;
}

fn void delete(Fiber* fiber)
{
    if (fiber == null || fiber == &primary) return;
    check_canary(fiber);
    // warn("@@@  free block=%p,stack_size:%dKB,stack_filled:%dKB", fiber.block, fiber.stack_size/1024, stack_filled(fiber)/1024);
    localmem.free(fiber.block);
    localmem.free(fiber);
}

fn void switch_to(Fiber* fiber) @nosanitize("address")
{
    if (fiber == null || fiber.done) return;
    if (running != &primary) check_canary(running);
    if (fiber != &primary) check_canary(fiber);

    Fiber* prev = running;
    running = fiber;

    // warn("%p, %p, %p, %p", prev, fiber, prev.handle, fiber.handle);

    asm_swap(fiber.handle, prev.handle);
}

fn void yield() @nosanitize("address")
{
    if (running == &primary) return;
    check_canary(running);
    
    switch_to(&primary);
}

fn void done() @nosanitize("address")
{
    running.done = true;
    check_canary(running);
    yield();
}
