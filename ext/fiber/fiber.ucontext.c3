// fiber.ucontext.c3

// Coroutine implementation based on POSIX ucontext.
// Virtual-memory stack version.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(UCONTEXT && env::POSIX);

import c::ucontext;
import ext::mem;
import ext::debug;

alias Coroutine = fn void();

struct Fiber
{
    UContext context;
    Coroutine entry;

    // mmap() base address. This is what must be passed to munmap().
    char* block;

    // Total mmap() region size:
    //
    //     guard_page_size + usable_stack_size
    //
    sz block_size;

    // First usable stack byte. The guard page is immediately below this.
    char* stack_low;

    // One-past-end of usable stack.
    char* stack_high;

    // Usable stack size, page-aligned.
    sz stack_size;

    bool done;

    // Argument given to fiber.
    // Fiber does not own this memory.
    void* arg;
}

struct FiberContext @private
{
    Fiber primary;
    Fiber* running;
}

tlocal FiberContext* ctx @private = null;

LocalAllocator localmem @private = {};

//
// Init / deinit
//

fn void? init(Allocator alloc = mem) @private @maydiscard
{
    if (localmem == (LocalAllocator){})
    {
        localmem = alloc;
    }

    if (ctx != null && ctx.running != null) return;

    if (ctx == null)
    {
        ctx = localmem.alloc(FiberContext)!;
    }

    *ctx = {
        .primary = {
            .context = {},
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

    // Capture primary context once. swapcontext() will update it later.
    ucontext::getcontext(&ctx.primary.context);

    ctx.running = &ctx.primary;
}

fn void deinit()
{
    if (ctx == null) return;

    ctx.primary = {};
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

//
// Public API
//

fn Fiber* active()
{
    if (ctx == null || ctx.running == null) init();
    return ctx.running;
}

fn sz stack_used(Fiber* fiber)
{
    if (ctx == null) return 0;
    if (fiber == null || fiber == &ctx.primary) return 0;
    if (fiber.stack_low == null || fiber.stack_high == null) return 0;

    // ucontext_t is platform-specific, so saved SP is not read portably.
    // We can only approximate usage for the currently running fiber.
    if (fiber != ctx.running) return 0;

    long marker = 0;
    ulong sp = (ulong)(void*)&marker;

    ulong low = (ulong)(void*)fiber.stack_low;
    ulong high = (ulong)(void*)fiber.stack_high;

    if (sp < low || sp >= high) return 0;

    return (sz)(high - sp);
}

fn void diag()
{
    Fiber* fiber = active();

    if (fiber == &ctx.primary)
    {
        warn("it's primary fiber");
        return;
    }

    @assert(fiber != null);
    @assert(fiber.block != null);
    @assert(fiber.stack_low != null);
    @assert(fiber.stack_high != null);

    warn("mmap block:%p, block_size:%d", fiber.block, fiber.block_size);
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
        .entry = entry,
        .block = block,
        .block_size = block_size,
        .stack_low = stack_low,
        .stack_high = stack_high,
        .stack_size = usable_size,
        .done = false,
        .arg = arg,
    };

    ucontext::getcontext(&fiber.context);

    fiber.context.uc_stack.ss_sp = stack_low;
    fiber.context.uc_stack.ss_size = usable_size;
    fiber.context.uc_stack.ss_flags = 0;

    // Do not let returning from fiber_entry() fall through into an unknown
    // context. fiber_entry() calls yield() and then unreachable().
    fiber.context.uc_link = null;

    ucontext::makecontext(&fiber.context, &fiber_entry, 0);

    return fiber;
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

    if (ucontext::swapcontext(&prev.context, &fiber.context) != 0)
    {
        ctx.running = prev;
    }
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