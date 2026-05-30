// sample3.c3
// Tests: call_soon, call_later_ms, call_at_us, run_forever, stop
//
// Timeline (approximate):
//   t+0sec   call_soon  → fires on the very next tick
//   t+0.5sec  call_later → fires after 0.5 sec
//   t+1.0sec call_at    → fires at an absolute timestamp 1.0 sec ahead
//   t+1.5sec coroutine calls stop() to exit run_forever

module sample3;

import std::io;
import ext::asyncio;

// ---------------------------------------------
//  Callbacks (plain functions, not coroutines)
// ---------------------------------------------

fn String v2s(void* v)
{
    ZString z = (ZString)(char*)v;
    return z.str_view();
}

fn void on_soon(void* arg)
{
    io::printfn("[call_soon ] fired  (arg=%s)", v2s(arg));
}

fn void on_later(void* arg)
{
    io::printfn("[call_later] fired after 0.5 sec  (arg=%s)", v2s(arg));
}

fn void on_at(void* arg)
{
    io::printfn("[call_at   ] fired at t+1 sec  (arg=%s)", v2s(arg));
}

fn void on_stop_signal(void* arg)
{
    EventLoop* loop = asyncio::get_running_loop();
    
    io::printfn("[stopper   ] stopping the loop after 1.5 sec");
    loop.stop();
}

// ---------------------------------------------
//  Main coroutine
// ---------------------------------------------

fn void main_coro()
{
    io::printfn("=== sample3: call_soon / call_later / call_at ===");

    EventLoop* loop = asyncio::get_running_loop();
    ulong now = loop.time();

    // Fires on the next loop tick — no delay
    loop.call_soon(&on_soon, "hello");

    // Fires 0.5 sec from now
    loop.call_later(0.5, &on_later, "world");

    // Fires at an absolute timestamp 1 sec from now
    loop.call_at((double)(now + 1_000_000)/1_000_000, &on_at, "absolute");

    // Stop the loop 1.50 sec from now
    loop.call_later((double)1_500_000/1_000_000, &on_stop_signal, null);

    io::printfn("[main      ] callbacks registered, yielding to loop");

    // Suspend this task so the loop can run other work while waiting
    io::printfn("[main      ] sleep 2 sec");
    asyncio::sleep(2.0);

    // We only reach here if stop() was NOT called before sleep finished,
    // which should not happen in this sample.
    io::printfn("[main      ] (should not reach here)");
}

fn void main()
{
  @assert_leak() {
    // Initialise the loop manually because we will call run_forever()
    EventLoop* loop = asyncio::new_event_loop();
    asyncio::set_event_loop(loop);
    
    // Enqueue the main task by hand (run_forever does not do it for us)
    loop.create_task(&main_coro, "main");

    loop.run_forever();

    io::printfn("=== sample3 done (is_running=%s, is_closed=%s) ===",
                loop.is_running() ? "true" : "false",
                loop.is_closed()  ? "true" : "false");

    loop.close();
    io::printfn("=== loop closed (is_closed=%s) ===",
                loop.is_closed() ? "true" : "false");
    loop.free();
  };
}
