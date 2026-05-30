// sample4.c3
// Tests: CallbackHandle.cancel(), create_future(), is_running(), is_closed(), close()
//
// Scenario:
//   - Register 4 call_later callbacks (t+0.5, t+1.0, t+1.5, t+2.0 sec)
//   - Cancel the t+1.0 sec one immediately after registering it
//   - Use create_future() + set_result() as a manual signal to stop the loop at t+1.7 sec

module sample4;

import std::io;
import ext::asyncio;

int g_fired;   // counts how many callbacks actually ran

fn String v2s(void* v)
{
    ZString z = (ZString)(char*)v;
    return z.str_view();
}

fn void on_cb(void* arg)
{
    g_fired++;
    io::printfn("[cb %s] fired  (total fired so far: %d)", v2s(arg), g_fired);
}

// ---------------------------------------------
//  Manual signal future
// ---------------------------------------------

asyncio::Future* g_signal;

fn void on_signal_ready(asyncio::Future* f, asyncio::CallbackCtx ctx)
{
    io::printfn("[signal ] Future done — stopping loop at 1.7 sec");
    f.loop.stop();
}

fn void send_signal(void* arg)
{
    // Called via call_later; sets the result on the shared Future
    if (!g_signal.done()) {
        g_signal.set_result(null);
    }
}

// ---------------------------------------------
//  Main coroutine
// ---------------------------------------------

fn void main_coro()
{
    io::printfn("=== sample4: CallbackHandle.cancel + create_future lifecycle ===");

    EventLoop* loop = asyncio::get_running_loop();
    // create_future() — bound to the current loop
    g_signal = loop.create_future();
    g_signal.add_done_callback(&on_signal_ready, null);

    ulong now = loop.time();

    CallbackHandle* h50  = loop.call_later(0.5,  &on_cb, "t+0.5s");
    CallbackHandle* h100 = loop.call_later(1.0, &on_cb, "t+1.0s");
    CallbackHandle* h150 = loop.call_later(1.5, &on_cb, "t+1.5s");
    CallbackHandle* h200 = loop.call_later(2.0, &on_cb, "t+2.0s");

    // Cancel t+100ms right away — should never fire
    h100.cancel();
    io::printfn("[main  ] cancelled h100");

    // Send a signal at t+1.7s to stop the loop before t+200ms fires
    loop.call_later(1.7, &send_signal, null);

    // Sleep long enough for all of the above to resolve
    io::printfn("[main  ] sleep 3.0 sec");
    asyncio::sleep(3.0);

    io::printfn("[main  ] (should not reach here — loop was stopped at t+1.7s)");

    // (void)h50; (void)h150; (void)h200;  // suppress unused warnings
}

fn void main()
{
  @assert_leak() {
    EventLoop* loop = asyncio::new_event_loop();
    asyncio::set_event_loop(loop);
    loop.create_task(&main_coro, "main");

    loop.run_forever();

    io::printfn("=== sample4 done ===");
    io::printfn("callbacks fired: %d  (expected 2: t+0.5s and t+1.5s)", g_fired);
    io::printfn("is_running=%s  is_closed=%s", loop.is_running() ? "true" : "false", loop.is_closed()  ? "true" : "false");

    // close() must cancel remaining handles (h200 was still pending)
    loop.close();
    io::printfn("after close: is_closed=%s", loop.is_closed() ? "true" : "false");
    g_signal.free();
    loop.free();
  };
}
