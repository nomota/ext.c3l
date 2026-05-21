// fiber.sjlj.c3

// Coroutine implementation based on POSIX sigsetjmp/siglongjmp.
// Virtual-memory stack version.
//
// Original:
//   Based on ideas from a paper by Ralf Engelschall.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(SJLJ && env::POSIX);

import c::signal;
import c::setjmp;
import ext::mem;
import ext::debug;

//
// Constants / types
//

const int SIG_FIBER = signal::SIGRTMIN + 7;
const usz MIN_STACK_SIZE = 65_536;

alias Coroutine = fn void();

struct Fiber
{
    SigJmpBuf context;
    Coroutine entry;

    // mmap() base address. This is what must be passed to munmap().
    char* block;

    // Total mmap() region size:
    //
    //     guard_page_size + usable_stack_size
    //
    usz block_size;

    // First usable stack byte. The guard page is immediately below this.
    char* stack_low;

    // One-past-end of usable stack.
    char* stack_high;

    // Usable stack size, page-aligned.
    usz stack_size;

    bool done;

    // Argument given to fiber
    // Fiber does not own this memory.
    void* arg; // within coroutine, `fiber::active().arg` to get access of it
}

struct FiberContext @private
{
    Fiber primary;
    Fiber* running;
    Fiber* creating;
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
        .creating = null,
    };

    ctx.running = &ctx.primary;
}

// All non-primary fibers must be deleted before deinit().
fn void deinit()
{
    if (ctx == null) return;

    ctx.primary = {};
    ctx.running = null;
    ctx.creating = null;

    localmem.free(ctx);
    ctx = null;
}

//
// Signal helpers
//

fn void block_sig_fiber(SigSet* oldmask = null) @private
{
    SigSet set = {};
    signal::sigemptyset(&set);
    signal::sigaddset(&set, SIG_FIBER);
    signal::sigprocmask(signal::SIG_BLOCK, &set, oldmask);
}

fn void restore_sigmask(SigSet* oldmask) @private
{
    if (oldmask == null) return;
    signal::sigprocmask(signal::SIG_SETMASK, oldmask, null);
}

//
// Springboard / init_common
//

fn void springboard(CInt ignored) @private
{
    if (ctx == null) return;

    Fiber* fiber = ctx.creating;
    if (fiber == null) return;

    if (setjmp::sigsetjmp(&fiber.context, 1) != 0)
    {
        ctx.running = fiber;

        @assert(fiber.entry != null);
        
        fiber.entry();

        fiber.done = true;

        yield();

        unreachable("dead fiber resumed");
    }
}

fn bool init_common(Fiber* fiber, Coroutine entry, Stack* stack) @private
{
    SigAction handler = {};
    SigAction old_handler = {};
    Stack old_stack = {};
    SigSet saved_mask = {};

    if (ctx == null) init();

    if (fiber == null || entry == null || stack == null) return false;
    if (stack.ss_sp == null || stack.ss_size == 0) return false;

    stack.ss_flags = 0;

    block_sig_fiber(&saved_mask);

    if (signal::sigaltstack(stack, &old_stack) != 0)
    {
        restore_sigmask(&saved_mask);
        return false;
    }

    handler.sa_handler = &springboard;
    handler.sa_flags = signal::SA_ONSTACK;
    signal::sigemptyset(&handler.sa_mask);

    ctx.creating = fiber;

    if (signal::sigaction(SIG_FIBER, &handler, &old_handler) != 0)
    {
        ctx.creating = null;
        if (signal::sigaltstack(&old_stack, null) != 0)
        {
            return false;
        }
        restore_sigmask(&saved_mask);
        return false;
    }

    // Allow SIG_FIBER so raise() can run springboard on the alternate stack.
    restore_sigmask(&saved_mask);

    bool ok = signal::raise(SIG_FIBER) == 0;

    if (ok)
    {
        fiber.entry = entry;
    }

    // Block SIG_FIBER while restoring handler and alternate stack.
    block_sig_fiber(null);

    ctx.creating = null;
    signal::sigaction(SIG_FIBER, &old_handler, null);
    signal::sigaltstack(&old_stack, null);

    restore_sigmask(&saved_mask);

    return ok;
}

//
// Public API
//

fn Fiber* active()
{
    if (ctx == null || ctx.running == null) init();
    return ctx.running;
}

fn usz stack_used(Fiber* fiber)
{
    if (ctx == null) return 0;
    if (fiber == null || fiber == &ctx.primary) return 0;
    if (fiber.stack_low == null || fiber.stack_high == null) return 0;

    // sigjmp_buf is opaque, so saved SP cannot be read portably.
    // We can only approximate usage for the currently running fiber.
    if (fiber != ctx.running) return 0;

    long marker = 0;
    ulong sp = (ulong)(void*)&marker;

    ulong low = (ulong)(void*)fiber.stack_low;
    ulong high = (ulong)(void*)fiber.stack_high;

    if (sp < low || sp >= high) return 0;

    return (usz)(high - sp);
}

faultdef INIT_FAIL, NULL_ENTRY;

fn Fiber*? create(Coroutine entry, uint stack_size = 256_000, void* arg = null)
{
    if (ctx == null || ctx.running == null) init();
    if (entry == null) return NULL_ENTRY~;

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
    )!;

    Fiber* fiber = localmem.alloc(Fiber)!;
    *fiber = {
        .context = {},
        .entry = null,
        .block = block,
        .block_size = block_size,
        .stack_low = stack_low,
        .stack_high = stack_high,
        .stack_size = usable_size,
        .done = false,
        .arg = arg,
    };

    Stack stack = {};
    stack.ss_size = usable_size;
    stack.ss_sp = stack_low;

    if (!init_common(fiber, entry, &stack))
    {
        vm::stack_free(fiber.block, fiber.block_size);
        localmem.free(fiber);
        return INIT_FAIL~;
    }

    return fiber;
}

fn void delete(Fiber* fiber)
{
    if (fiber == null) return;
    if (ctx != null && fiber == &ctx.primary) return;

    // Deleting the currently running fiber would unmap the active stack.
    if (ctx != null && fiber == ctx.running)
    {
        warn("cannot delete running fiber");
        return;
    }
    
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

    if (setjmp::sigsetjmp(&prev.context, 1) == 0)
    {
        ctx.running = fiber;
        setjmp::siglongjmp(&fiber.context, 1);
    }
}

fn void yield() @nosanitize("address")
{
    if (ctx == null || ctx.running == null) return;
    if (ctx.running == &ctx.primary) return;

    Fiber* fiber = ctx.running;

    if (setjmp::sigsetjmp(&fiber.context, 1) == 0)
    {
        ctx.running = &ctx.primary;
        setjmp::siglongjmp(&ctx.primary.context, 1);
    }
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

