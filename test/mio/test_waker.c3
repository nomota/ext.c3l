// test_waker.c3

// Basic waker test for ext::mio

// Nomota <hiongun@gmail.com>; MIT License

import std::thread;
import c::unistd;
import ext::mio;
import ext::debug;

bool g_thread_ok = false;

fn int wake_thread(void* arg)
{
    mio::Waker* waker = (mio::Waker*)arg;

    thread::sleep_ms(10);

    waker.wake()!!;

    g_thread_ok = true;

    return 0;
}

fn void main()
{
    mio::Poll* poll = mio::poll_new(64)!!;
    defer poll.free();

    mio::Events events = mio::events_new(64)!!;
    defer events.free();

    mio::Waker* waker = mio::waker_new()!!;
    defer waker.free();

    poll.register(waker.fd(), mio::want_read())!!;

    Thread thread;
    thread.create(&wake_thread, waker)!!;

    while (true)
    {
        poll.poll(&events, 1000)!!;
        if (events.len > 0) break;
    }
    
    bool got_wake = false;

    for (sz i = 0; i < events.len; i++)
    {
        mio::Event* event = events.get(i);
        if (event == null) continue;

        if (event.fd == waker.fd() && event.read)
        {
            got_wake = true;
            break;
        }
    }

    @assert(got_wake, "waker fd was not readable");

    waker.drain()!!;

    poll.deregister(waker.fd())!!;

    thread.join()!!;

    @assert(g_thread_ok, "wake thread did not complete");

    warn("OK");
}

// eof