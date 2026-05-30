// fiber.asm.c3

// Fast context switching by assembly code.
// Virtual-memory stack version.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(ASM_X86_64_SYSV || ASM_AARCH64);

import c::unistd;
import c::sys::mman;
import c::stdlib;
import ext::debug;
import ext::mem;

//
// Constants / types
//

const int CONTEXT_LONGS @private = 64;

alias Coroutine = fn void();

alias SwitchFn = fn void(void*, void*);

struct Fiber
{
    // Context save area.
    //
    // The assembly switch code expects handle to point to this buffer.
    //
    // x86-64 SysV layout:
    //   context[0] = rsp
    //   context[1] = rbp
    //   context[2] = rbx
    //   context[3] = r12
    //   context[4] = r13
    //   context[5] = r14
    //   context[6] = r15
    //
    // AArch64 layout:
    //   context[0] = sp
    //   context[1] = x30 / lr
    //   context[2...] = callee-saved registers
    //
    long[CONTEXT_LONGS] context @align(16);
    void* handle;

    Coroutine entry;

    // Stack allocation base.
    //
    // In per-stack mmap mode, this is the mmap() base.
    // In arena mode, this is the stack slice base inside the arena.
    char* block;

    // Allocation size associated with block.
    //
    // In per-stack mmap mode, this is the mmap() region size.
    // In arena mode, this is the stack slice size.
    sz block_size;

    // First usable stack byte.
    char* stack_low;

    // One-past-end of usable stack.
    char* stack_high;

    // Usable stack size.
    sz stack_size;

    bool done;

    // Argument given to fiber.
    // Fiber does not own this memory.
    void* arg;
}

struct FiberContext @private
{
    long[CONTEXT_LONGS] primary_context @align(16);
    Fiber primary;
    Fiber* running;
}

tlocal FiberContext* ctx @private = null;

LocalAllocator localmem @private = {};

SwitchFn asm_switch @private = null;
bool asm_inited @private = false;

// Executable assembly trampoline storage.
char[4096] asmblock @align(4096);

//
// Low-level helpers
//

fn sz page_size() @private
{
    long p = unistd::sysconf(unistd::_SC_PAGESIZE);
    if (p <= 0) return 4096;
    return (sz)p;
}

faultdef MAKE_EXECUTABLE_FAIL;

fn void? make_asm_executable(char[] block, char[] asm_bytes) @private
{
    if (asm_bytes.len > block.len)
    {
        return MAKE_EXECUTABLE_FAIL~;
    }

    block[0:asm_bytes.len] = asm_bytes[0:asm_bytes.len];

    ulong addr = (ulong)(void*)&block[0];
    ulong ps = (ulong)page_size();

    ulong base = addr - (addr % ps);
    ulong size = (addr - base) + (ulong)block.len;

    int rc = mman::mprotect(
        (void*)base,
        (sz)size,
        mman::PROT_READ | mman::PROT_EXEC
    );

    if (rc != 0)
    {
        warn("mprotect failed for asmblock");
        return MAKE_EXECUTABLE_FAIL~;
    }

    asm_switch = (SwitchFn)(void*)&block[0];
}

fn void? ensure_asm_executable() @private
{
    if (asm_inited) return;

    make_asm_executable(asmblock[..], ASM[..])!;

    asm_inited = true;
}

//
// Init / deinit
//

fn void? init(Allocator alloc = mem) @maydiscard @private
{
    if (localmem == (LocalAllocator){})
    {
        localmem = alloc;
    }

    ensure_asm_executable()!;

    if (ctx != null && ctx.running != null) return;

    if (ctx == null)
    {
        ctx = localmem.alloc(FiberContext)!;
    }

    *ctx = {
        .primary_context = {},
        .primary = {
            .context = {},
            .handle = null,
            .entry = null,
            .block = null,
            .block_size = 0,
            .stack_low = null,
            .stack_high = null,
            .stack_size = 0,
            .done = false,
            .arg = null,
        },
        .running = null,
    };

    ctx.primary.handle = (void*)&ctx.primary_context[0];
    ctx.running = &ctx.primary;
}

fn void deinit()
{
    if (ctx == null) return;

    ctx.primary = {};
    ctx.primary_context = {};
    ctx.running = null;

    localmem.free(ctx);
    ctx = null;
}

//
// Fiber entry trampoline
//

fn void fiber_entry() @private
{
    if (ctx == null || ctx.running == null) return;

    Fiber* fiber = ctx.running;

    if (fiber == &ctx.primary) return;

    if (fiber.entry != null)
    {
        fiber.entry();
    }

    fiber.done = true;

    yield();

    unreachable("dead fiber resumed");
}

fn void crash() @noreturn @private
{
    unreachable("fiber coroutine entrypoint returned");
}

//
// Initial context setup
//

fn void setup_initial_context(Fiber* fiber) @private @if(ASM_X86_64_SYSV)
{
    long* h = (long*)fiber.handle;

    for (int i = 0; i < CONTEXT_LONGS; i++)
    {
        h[i] = 0;
    }

    // Build initial stack.
    ulong stack_top = (ulong)(void*)fiber.stack_high;

    // Keep 32 bytes reserved. On SysV this is not Win64 shadow space,
    // but it keeps the old layout convention and does not hurt.
    stack_top -= 32;

    // 16-byte alignment.
    stack_top &= ~((ulong)15);

    long* p = (long*)stack_top;

    // If fiber_entry ever returns, crash immediately.
    p--;
    *p = (long)(void*)&crash;

    // First pop by asm_switch jumps here.
    p--;
    *p = (long)(void*)&fiber_entry;

    // context[0] = saved rsp.
    h[0] = (long)(void*)p;
}

fn void setup_initial_context(Fiber* fiber) @private @if(ASM_AARCH64)
{
    long* h = (long*)fiber.handle;

    for (int i = 0; i < CONTEXT_LONGS; i++)
    {
        h[i] = 0;
    }

    ulong stack_top = (ulong)(void*)fiber.stack_high;

    // AArch64 requires 16-byte SP alignment.
    stack_top &= ~((ulong)15);

    // AArch64 asm restores:
    //
    //   x16 = context[0]
    //   x30 = context[1]
    //   sp  = x16
    //   br x30
    //
    h[0] = (long)(void*)stack_top;
    h[1] = (long)(void*)&fiber_entry;
}

//
// Public API
//

fn Fiber* active()
{
    if (ctx == null || ctx.running == null) init();
    return ctx.running;
}

faultdef NULL_ENTRY;

fn Fiber*? create(Coroutine entry, uint stack_size = 256_000, void* arg = null)
{
    if (ctx == null || ctx.running == null) init();
    if (entry == null) return NULL_ENTRY~;

    sz block_size = 0;
    char* stack_low = null;
    char* stack_high = null;
    sz usable_size = 0;

    char* block = vm::stack_alloc(
        (sz)stack_size,
        &block_size,
        &stack_low,
        &stack_high,
        &usable_size
    )!;

    Fiber* fiber = localmem.alloc(Fiber)!;
    *fiber = {
        .context = {},
        .handle = null,
        .entry = entry,
        .block = block,
        .block_size = block_size,
        .stack_low = stack_low,
        .stack_high = stack_high,
        .stack_size = usable_size,
        .done = false,
        .arg = arg,
    };

    fiber.handle = (void*)&fiber.context[0];

    @assert(fiber.block != null);
    @assert(fiber.handle != null);
    @assert(fiber.stack_low != null);
    @assert(fiber.stack_high != null);
    @assert(fiber.stack_size > 0);

    setup_initial_context(fiber);

    return fiber;
}

fn sz stack_used(Fiber* fiber)
{
    if (!debug::debug) return 0;
    if (ctx == null) return 0;
    if (fiber == null || fiber == &ctx.primary) return 0;
    if (fiber.handle == null) return 0;
    if (fiber.stack_low == null || fiber.stack_high == null) return 0;

    ulong sp;

    if (fiber == ctx.running)
    {
        // Approximate current rsp/sp with a local variable.
        long marker = 0;
        sp = (ulong)(void*)&marker;
    }
    else
    {
        // Saved rsp/sp is stored in context[0] by asm_switch.
        sp = (ulong)(void*)(*((long*)fiber.handle));
    }

    ulong low = (ulong)(void*)fiber.stack_low;
    ulong high = (ulong)(void*)fiber.stack_high;

    if (sp < low || sp >= high) return 0;

    return (sz)(high - sp);
}

fn void diag()
{
    Fiber* fiber = active();

    if (ctx == null || fiber == &ctx.primary)
    {
        warn("it's primary fiber");
        return;
    }

    @assert(fiber != null);
    @assert(fiber.block != null);
    @assert(fiber.stack_low != null);
    @assert(fiber.stack_high != null);

    warn("stack block:%p, block_size:%d", fiber.block, fiber.block_size);
    warn("stack low:%p, high:%p", fiber.stack_low, fiber.stack_high);

    sz used = stack_used(fiber);
    float usage = (float)used / (float)fiber.stack_size;

    warn(
        "stack_size:%d, used:%d, usage:%.1f%%",
        fiber.stack_size,
        used,
        usage * 100
    );
}

fn void delete(Fiber* fiber)
{
    if (fiber == null) return;
    if (ctx != null && fiber == &ctx.primary) return;

    // Deleting the currently running fiber would unmap the active stack.
    if (ctx != null && fiber == ctx.running) return;

    fiber.done = true;
    fiber.entry = null;
    fiber.arg = null;

    vm::stack_free(fiber.block, fiber.block_size);

    fiber.handle = null;
    fiber.block = null;
    fiber.block_size = 0;
    fiber.stack_low = null;
    fiber.stack_high = null;
    fiber.stack_size = 0;

    localmem.free(fiber);
}

fn void switch_to(Fiber* fiber) @nosanitize("address")
{
    if (ctx == null || ctx.running == null) init();

    if (fiber == null || fiber.done) return;
    if (fiber == ctx.running) return;

    Fiber* prev = ctx.running;
    ctx.running = fiber;

    asm_switch(fiber.handle, prev.handle);
}

fn void yield() @nosanitize("address")
{
    if (ctx == null || ctx.running == null) return;
    if (ctx.running == &ctx.primary) return;

    switch_to(&ctx.primary);
}

fn void done() @nosanitize("address")
{
    if (ctx == null || ctx.running == null) return;
    if (ctx.running == &ctx.primary) return;

    Fiber* fiber = ctx.running;

    fiber.done = true;

    yield();

    unreachable("dead fiber resumed");
}