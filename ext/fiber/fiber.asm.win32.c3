// fiber.asm.win32.c3

// Fast context switching by assembly code.
// Windows x86-64 / Win64 ABI.
// Virtual-memory stack version.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(ASM_X86_64_WIN64 && env::WIN32);

import c::windows;
import c::memoryapi;
import c::winnt;
import c::stdlib;
import ext::debug;
import ext::mem;

//
// Constants / types
//

const int CONTEXT_LONGS @private = 64;

alias Coroutine = fn void();

// Windows x64 ABI:
//   arg0 -> rcx
//   arg1 -> rdx
//
// C3에서 "stdcall"이 Windows x64 ABI로 매핑된다는 전제.
// 만약 C3가 "win64" callconv를 지원하면 아래를 win64로 바꿔도 됨.
alias SwitchFn = fn void(void*, void*) @callconv("stdcall");

struct Fiber
{
    // Context save area.
    //
    // The Win64 asm switch code expects handle to point to this buffer.
    //
    // Layout:
    //
    //   offset  field
    //   ------  -----
    //   0       rsp
    //   8       rbp
    //   16      rsi
    //   24      rdi
    //   32      rbx
    //   40      r12
    //   48      r13
    //   56      r14
    //   64      r15
    //   80      xmm6
    //   96      xmm7
    //   112     xmm8
    //   128     xmm9
    //   144     xmm10
    //   160     xmm11
    //   176     xmm12
    //   192     xmm13
    //   208     xmm14
    //   224     xmm15
    //
    long[CONTEXT_LONGS] context @align(16);
    void* handle;

    Coroutine entry;

    // Stack allocation base.
    //
    // In Windows VM mode, this is the VirtualAlloc reserved region base.
    char* block;

    // Total VirtualAlloc reserved region size.
    //
    //     guard_page_size + usable_stack_size
    //
    usz block_size;

    // First usable stack byte.
    char* stack_low;

    // One-past-end of usable stack.
    char* stack_high;

    // Usable stack size.
    usz stack_size;

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
char[4096] asmblock @align(4096) @private;

//
// Low-level helpers
//

fn void make_asm_executable(char[] block, char[] asm_bytes) @private
{
    if (asm_bytes.len > block.len)
    {
        stdlib::exit(1);
    }

    block[0:asm_bytes.len] = asm_bytes[0:asm_bytes.len];

    windows::DWord old_protect = 0;

    windows::Bool ok = memoryapi::virtualProtect(
        (void*)&block[0],
        block.len,
        winnt::PAGE_EXECUTE_READ,
        &old_protect
    );

    if (ok != windows::TRUE)
    {
        warn("VirtualProtect failed for asmblock");
        stdlib::exit(1);
    }

    // If your bindings expose FlushInstructionCache, keep this.
    // It is harmless and correct for generated code.
    memoryapi::flushInstructionCache(
        windows::getCurrentProcess(),
        (void*)&block[0],
        asm_bytes.len
    );

    asm_switch = (SwitchFn)(void*)&block[0];
}

fn void ensure_asm_executable() @private
{
    if (asm_inited) return;

    make_asm_executable(asmblock[..], ASM[..]);

    asm_inited = true;
}

//
// Init / deinit
//

fn void init(Allocator alloc = mem) @private
{
    if (localmem == (LocalAllocator){})
    {
        localmem = alloc;
    }

    ensure_asm_executable();

    if (ctx != null && ctx.running != null) return;

    if (ctx == null)
    {
        ctx = localmem.alloc(FiberContext);
        @assert(ctx != null, "fiber context allocation failed");
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

fn void setup_initial_context(Fiber* fiber) @private
{
    long* h = (long*)fiber.handle;

    for (int i = 0; i < CONTEXT_LONGS; i++)
    {
        h[i] = 0;
    }

    //
    // Build initial stack.
    //
    // Win64 stack rules:
    //
    //   - stack must be 16-byte aligned before call
    //   - at function entry, rsp % 16 == 8
    //   - caller reserves 32 bytes shadow space
    //
    // This backend enters by:
    //
    //   mov rsp, [new]
    //   pop rax
    //   jmp rax
    //
    // Therefore, after pop, rsp should look like a normal Win64 function
    // entry stack.
    //
    ulong stack_top = (ulong)(void*)fiber.stack_high;

    // Reserve shadow space.
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

//
// Public API
//

fn Fiber* active()
{
    if (ctx == null || ctx.running == null) init();
    return ctx.running;
}

fn Fiber* create(Coroutine entry, uint stack_size = 128_000, void* arg = null)
{
    if (ctx == null || ctx.running == null) init();
    if (entry == null) return null;

    usz block_size = 0;
    char* stack_low = null;
    char* stack_high = null;
    usz usable_size = 0;

    char* block = vm::stack_alloc(
        (usz)stack_size,
        &block_size,
        &stack_low,
        &stack_high,
        &usable_size
    );

    if (block == null) return null;

    Fiber* fiber = localmem.alloc(Fiber);
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

fn usz stack_used(Fiber* fiber)
{
    if (!debug::debug) return 0;
    if (ctx == null) return 0;
    if (fiber == null || fiber == &ctx.primary) return 0;
    if (fiber.handle == null) return 0;
    if (fiber.stack_low == null || fiber.stack_high == null) return 0;

    ulong sp;

    if (fiber == ctx.running)
    {
        // Approximate current rsp with a local variable.
        long marker = 0;
        sp = (ulong)(void*)&marker;
    }
    else
    {
        // Saved rsp is stored in context[0] by asm_switch.
        sp = (ulong)(void*)(*((long*)fiber.handle));
    }

    ulong low = (ulong)(void*)fiber.stack_low;
    ulong high = (ulong)(void*)fiber.stack_high;

    if (sp < low || sp >= high) return 0;

    return (usz)(high - sp);
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

    usz used = stack_used(fiber);
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

    // Deleting the currently running fiber would free the active stack.
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