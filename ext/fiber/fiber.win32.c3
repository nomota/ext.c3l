// fiber.win32.c3

// Window native Fiber coroutine

// Nomota <hiongun@gmail.com>; MIT License

module ext::thread::fiber @if(env::WIN32 && !(env::X86_64 || env::AARCH64));

import c::winbase;
import ext::mem;
import ext::debug;

alias FiberProc = fn void(void* param);
alias WinFiber = void*;

struct Fiber {
    WinFiber wfiber;
    bool done;
}

tlocal Fiber* running = null;
tlocal Fiber primary;

alias Coroutine = fn void();

fn void thunk(void* coentry) @callconv("stdcall") @private
{
    ((Coroutine)coentry)();
    @assert(running != null && running.done, "fiber::thunk(): coroutine returned without calling fiber::done()");
}

fn void init(Allocator allocx=mem, bool debug=true) @private
{
    if (running != null) return;
    primary.wfiber = winbase::convertThreadToFiber(null);
    @assert(primary.wfiber != null, "fiber::init(): ConvertThreadToFiber failed");
    running = &primary;
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

fn Fiber* create(uint stack_size, Coroutine coroutine)
{
    if (running == null) init();
    Fiber* fiber = mem_alloc(Fiber);
    fiber.wfiber = winbase::createFiber(stack_size, &thunk, (void*)coroutine);
    @assert(fiber.wfiber != null, "fiber::create(): CreateFiber failed");
    fiber.done = false;
    return fiber;
}

fn void delete(Fiber* fiber) 
{
    if (fiber == null || fiber == &primary) return;
    winbase::deleteFiber(fiber.wfiber);
    mem_free(fiber);
}

fn void switch_to(Fiber* fiber) @nosanitize("address")
{
    if (fiber == null || fiber.done) return;
    running = fiber;
    winbase::switchToFiber(fiber.wfiber);
}

fn void yield() @nosanitize("address")
{
    if (running == &primary) return;
    switch_to(&primary);
}

fn void done() @nosanitize("address")
{
    running.done = true;
    yield();
}

