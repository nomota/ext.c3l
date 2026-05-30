// fiber.win32.c3

// Windows native Fiber coroutine.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(WINFIBER && env::WIN32);

import c::winbase;
import ext::mem;
import ext::debug;

alias WinFiber = void*;
alias Coroutine = fn void();

struct Fiber
{
    WinFiber wfiber;
    Coroutine entry;

    bool done;

    // Argument given to fiber.
    // Fiber does not own this memory.
    void* arg;
}

struct FiberContext @local
{
    Fiber primary;
    Fiber* running;
}

tlocal FiberContext* ctx @local = null;

LocalAllocator localmem = {};

//
// Init / deinit
//

fn void init(Allocator alloc = mem) @local
{
    if (localmem == (LocalAllocator){})
    {
        localmem = alloc;
    }

    if (ctx != null && ctx.running != null) return;

    if (ctx == null)
    {
        ctx = localmem.alloc(FiberContext)!!;
        @assert(ctx != null, "fiber context allocation failed");
    }

    *ctx = {
        .primary = {
            .wfiber = null,
            .entry = null,
            .done = false,
            .arg = null,
        },
        .running = null,
    };

    ctx.primary.wfiber = winbase::convertThreadToFiber(null);
    @assert(ctx.primary.wfiber != null, "fiber::init(): ConvertThreadToFiber failed");

    ctx.running = &ctx.primary;
}

fn void deinit()
{
    if (ctx == null) return;

    // Do not deinit while running inside a non-primary fiber.
    if (ctx.running != &ctx.primary) return;

    //
    // If your winbase binding exposes ConvertFiberToThread(), call it here.
    //
    // winbase::convertFiberToThread();
    //

    ctx.primary = {};
    ctx.running = null;

    localmem.free(ctx);
    ctx = null;
}

//
// Fiber entry trampoline
//

fn void fiber_entry(void* param) @callconv("stdcall") @private
{
    Fiber* fiber = (Fiber*)param;

    if (ctx == null || fiber == null) return;

    ctx.running = fiber;

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

fn Fiber*? create(Coroutine entry, uint stack_size = 128_000, void* arg = null)
{
    if (ctx == null || ctx.running == null) init();
    if (entry == null) return null;

    Fiber* fiber = localmem.alloc(Fiber)!;

    *fiber = {
        .wfiber = null,
        .entry = entry,
        .done = false,
        .arg = arg,
    };

    fiber.wfiber = winbase::createFiber(stack_size, &fiber_entry, (void*)fiber);
    @assert(fiber.wfiber != null, "fiber::create(): CreateFiber failed");

    return fiber;
}

fn void delete(Fiber* fiber)
{
    if (fiber == null) return;
    if (ctx != null && fiber == &ctx.primary) return;

    // Deleting the currently running fiber would free the active stack.
    if (ctx != null && fiber == ctx.running) return;

    if (fiber.wfiber != null)
    {
        winbase::deleteFiber(fiber.wfiber);
        fiber.wfiber = null;
    }

    fiber.entry = null;
    fiber.arg = null;
    fiber.done = true;

    localmem.free(fiber);
}

fn void switch_to(Fiber* fiber) @nosanitize("address")
{
    if (ctx == null || ctx.running == null) init();

    if (fiber == null || fiber.done) return;
    if (fiber == ctx.running) return;
    if (fiber.wfiber == null) return;

    Fiber* prev = ctx.running;
    ctx.running = fiber;

    winbase::switchToFiber(fiber.wfiber);

    // When SwitchToFiber returns, execution has resumed in prev.
    ctx.running = prev;
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

fn sz stack_used(Fiber* fiber)
{
    // Native Windows Fiber does not expose portable stack usage here.
    return 0;
}

fn void diag()
{
    Fiber* fiber = active();

    if (ctx == null || fiber == &ctx.primary)
    {
        warn("it's primary fiber");
        return;
    }

    warn("winfiber:%p done:%d arg:%p", fiber.wfiber, fiber.done, fiber.arg);
}