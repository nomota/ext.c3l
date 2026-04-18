// fiber.sjlj.c3

module ext::thread::fiber @if(false); // not included @if(env::POSIX);

import std::io;
import c::signal;
import c::setjmp;
import c::string;
import c::stdlib;
import ext::mem;
import ext::debug;

// Coroutine implementation based on POSIX sigsetjmp/siglongjmp
//  Original: Based on ideas from a paper by Ralf Engelschall


// ========================================
// Canary / stack debug
// ========================================

const int SIG_FIBER = signal::SIGRTMIN+7;
const char[] CANARY = "CANARYCANARYCANARYCANARY"; // 24 bytes

alias Coroutine = fn void();

struct Fiber {
    SigJmpBuf context;
    Coroutine entry;
    char* block;      // raw allocation base (canary prefix at block[0])
    usz   stack_size; // usable stack size (excluding canary)
    bool  done;
}

tlocal Fiber primary;
tlocal Fiber* running = null;
tlocal Volatile{Fiber*} creating;

fn void init(Allocator allocx = mem, bool dbg = true) @private
{
    if (running != null) return;
    mem::set_allocator(allocx);
    debug::set_debug(dbg);
    running = &primary;
    creating.set(null);
}

fn void deinit()
{
    if (running == null) return;
    primary = {};
    running = null;
}

// ========================================
// Canary helpers
// ========================================

fn void check_canary(Fiber* fiber) @inline @private
{
    if (!debug) return;
    if (fiber.block == null) return; // primary has no block

    usz stack_size = fiber.stack_size;

    if (string::strncmp(fiber.block, CANARY.ptr, CANARY.len) != 0) {
        warn("Prefix canary breached");
        stdlib::exit(0);
    }

    if (string::strncmp(fiber.block + CANARY.len + stack_size, CANARY.ptr, CANARY.len) != 0) {
        warn("Postfix canary breached");
        stdlib::exit(0);
    }
}


// ========================================
// Signal helpers
// ========================================

fn void block_sig_fiber(SigSet* oldmask) @private
{
    SigSet set = {};
    signal::sigemptyset(&set);
    signal::sigaddset(&set, SIG_FIBER);
    signal::sigprocmask(signal::SIG_BLOCK, &set, oldmask);
}

fn void restore_sigmask(SigSet* oldmask) @private
{
    signal::sigprocmask(signal::SIG_SETMASK, oldmask, null);
}

// ========================================
// Springboard / init_common
// ========================================

fn void springboard(CInt ignored) @private
{
    Fiber* f = creating.get();
    if (f == null) return;

    if (setjmp::sigsetjmp(&f.context, 1) != 0) {
        running = f;
        check_canary(f);
        f.entry();
        f.done = true;
        check_canary(f);
        yield();
    }
}

fn bool init_common(Fiber* fiber, Coroutine entry, Stack* stack) @private
{
    SigAction handler = {};
    SigAction old_handler = {};
    Stack old_stack = {};
    SigSet saved_mask = {};

    stack.ss_flags = 0;

    if (stack.ss_sp == null) return false;

    block_sig_fiber(&saved_mask);

    if (signal::sigaltstack(stack, &old_stack) != 0) {
        restore_sigmask(&saved_mask);
        return false;
    }

    handler.sa_handler = &springboard;
    handler.sa_flags = signal::SA_ONSTACK;
    signal::sigemptyset(&handler.sa_mask);

    creating.set(fiber);

    if (signal::sigaction(SIG_FIBER, &handler, &old_handler) != 0) {
        signal::sigaltstack(&old_stack, null);
        creating.set(null);
        return false;
    }

    restore_sigmask(&saved_mask);

    bool ok = signal::raise(SIG_FIBER) == 0;
    if (ok) {
        fiber.entry = entry;
    }

    block_sig_fiber(null);

    creating.set(null);
    signal::sigaction(SIG_FIBER, &old_handler, null);
    signal::sigaltstack(&old_stack, null);

    restore_sigmask(&saved_mask);

    return ok;
}

// ========================================
// Public API
// ========================================

fn usz stack_used(Fiber* fiber)
{
    if (!debug) return 0;
    if (fiber.block == null) return 0; // primary has no block

    usz stack_size = fiber.stack_size;
    usz untouched = 0;
    for (isz i = 0; i < stack_size; i++) {
        usz idx = i + CANARY.len;
        if (fiber.block[idx] != 'Z') {
            untouched = i;
            break;
        }
    }
    return stack_size - untouched;
}

fn Fiber* active()
{
    if (running == null) init();
    return running;
}

fn Fiber* create(uint stack_size, Coroutine entry)
{
    if (running == null) init();

    if (stack_size < signal::SIGSTKSZ) stack_size = signal::SIGSTKSZ;
    if (stack_size < 65_536)           stack_size = 65_536;

    Fiber* fiber = mem_alloc(Fiber);
    *fiber = {};
    fiber.done = false;
    fiber.stack_size = stack_size;

    char* block;
    void* ss_sp;

    if (debug) {
        block = mem_malloc(stack_size + CANARY.len * 2);
        string::memcpy(&block[0], CANARY.ptr, CANARY.len);
        string::memset(&block[CANARY.len], 'Z', stack_size);
        string::memcpy(&block[CANARY.len + stack_size], CANARY.ptr, CANARY.len);
        ss_sp = block + CANARY.len;
    } else {
        block = mem_malloc(stack_size);
        ss_sp = block;
    }

    fiber.block = block;

    Stack stack = {};
    stack.ss_size = stack_size;
    stack.ss_sp   = ss_sp;

    if (!init_common(fiber, entry, &stack)) {
        mem_free(block);
        mem_free(fiber);
        return null;
    }

    return fiber;
}

fn void delete(Fiber* fiber)
{
    if (fiber == null || fiber == &primary) return;
    check_canary(fiber);
    // warn("@@@  free block=%p,stack_size:%dKB,stack_filled:%dKB", fiber.block, fiber.stack_size/1024, stack_used(fiber)/1024);
    mem_free(fiber.block);
    mem_free(fiber);
}

fn void switch_to(Fiber* fiber) @nosanitize("address")
{
    if (fiber == null || fiber.done) return;
    if (running != &primary) check_canary(running);
    if (fiber   != &primary) check_canary(fiber);
    if (setjmp::sigsetjmp(&running.context, 1) == 0) {
        running = fiber;
        setjmp::siglongjmp(&running.context, 1);
    }
}

fn void yield() @nosanitize("address")
{
    if (running == &primary) return;
    check_canary(running);
    if (setjmp::sigsetjmp(&running.context, 1) == 0) {
        running = &primary;
        setjmp::siglongjmp(&running.context, 1);
    }
}

fn void done() @nosanitize("address")
{
    if (running == &primary) return;
    running.done = true;
    check_canary(running);
    yield();
}
