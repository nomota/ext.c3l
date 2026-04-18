// fiber.ucontext.c3

module ext::thread::fiber @if(env::POSIX && (!env::X86_64 && !env::AARCH64));

import std::io;
import c::ucontext;
import c::string;
import c::stdlib;
import ext::debug;
import ext::mem;

struct Fiber {
    UContext context;
    char* block;
    usz stack_size;
    bool done;
}

tlocal Fiber* running = null;
tlocal Fiber primary;

alias Coroutine = fn void();

fn void init(Allocator allocx = mem, bool debug = true) @private
{
    if (running != null) return;
    running = &primary;
    mem::set_allocator(allocx);
    debug::set_debug(debug);
}

fn void deinit()
{
    if (running == null) return;
    primary = {};
    running = null;
}

fn Fiber* active() 
{
    if (running == null) init();
    return running;
}

const char[] CANARY = "CANARYCANARYCANARYCANARY"; // 24 bytes
fn Fiber* create(uint stack_size, Coroutine coroutine)
{
    if (running == null) init();
 
    Fiber* fiber = mem_alloc(Fiber);
   
    ucontext::getcontext(&fiber.context);
    UContext* ctx = &fiber.context;
    ctx.uc_stack.ss_size = stack_size;
    ctx.uc_link = null;

    char* block;
    if (debug) {
        block = mem_malloc(stack_size+CANARY.len*2);
        // warn("#### malloc block=%p", block);
        string::memcpy(&block[0], CANARY.ptr, CANARY.len);
        string::memset(&block[CANARY.len], 'Z', stack_size);
        string::memcpy(&block[CANARY.len+stack_size], CANARY.ptr, CANARY.len);
        ctx.uc_stack.ss_sp = block+CANARY.len;
    } else {
        block = mem_malloc(stack_size);
        ctx.uc_stack.ss_sp = block;
    }
    
    ucontext::makecontext(&fiber.context, coroutine, 0);
    fiber.block = block;
    fiber.done = false;
    fiber.stack_size = stack_size;
    
    // warn("### block=%p,stack_size:%dKB,stack_filled:%dKB", fiber.block, fiber.stack_size/1024, stack_filled(fiber)/1024);

    return fiber;
}

fn void delete(Fiber* fiber) 
{
    if (fiber == null || fiber == &primary) return;
    check_canary();
    // warn("@@@  free block=%p,stack_size:%dKB,stack_filled:%dKB", fiber.block, fiber.stack_size/1024, stack_filled(fiber)/1024);
    mem_free(fiber.block);
    mem_free(fiber);
}

fn void check_canary(fiber) @inline @private
{
    if (! debug) return;
    usz stack_size = fiber.stack_size;

    if (string::strncmp(fiber.block, CANARY.ptr, CANARY.len) != 0) {
        warn("Prefix canary breached");
        stdlib::exit(0);
    }
    
    if (string::strncmp(fiber.block+CANARY.len+stack_size, CANARY.ptr, CANARY.len) != 0) {
        warn("Postfix canary breached");
        stdlib::exit(0);
    }
}

fn usz stack_used(Fiber* fiber)
{
    if (! debug) return 0;
    
    usz stack_size = fiber.context.uc_stack.ss_size;
    // warn("%d %c%c%c", stack_size, fiber.block[CANARY.len+stack_size-3],fiber.block[CANARY.len+stack_size-2],fiber.block[CANARY.len+stack_size-1]);
    usz untouched;
    for (isz i = 0; i < stack_size; i++) {
        usz idx = i+CANARY.len;
        if (fiber.block[idx] != 'Z') {
            untouched = i;
            break;
        }
    }
    return stack_size-untouched;
}
    
fn void switch_to(Fiber* fiber) @nosanitize("address")
{
    if (fiber == null || fiber.done) return;
    if (running != &primary) check_canary(running);
    if (fiber != &primary) check_canary(fiber);
    if (ucontext::getcontext(&running.context) == 0) {
        Fiber* prev = running;
        running = fiber;
        ucontext::swapcontext(&prev.context, &fiber.context);
    }
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

