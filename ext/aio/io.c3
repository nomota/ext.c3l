// io.c3

// ext::aio::io built on ext::mio
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::io;

import std::io;
import c::errno;
import c::string;
import ext::debug;
import ext::mem;
import ext::aio;
import ext::mio;

alias Fd = mio::Fd;

const sz MAX_EVENTS = 4096;
const sz MAX_FD_WATCH = 20_000;

macro bool fd_invalid(mio::Fd fd)
{
    return mio::fd_invalid(fd);
}

macro mio::Fd fd_null()
{
    return (mio::Fd)-1;
}

struct Watch @local
{
    mio::Fd fd;
    bool active;
    bool internal;
    bool poll_read_registered;
    bool poll_write_registered;
    Future* read_fut;
    Future* write_fut;
}

struct IoContext @local
{
    Watch[MAX_FD_WATCH] fd_table;
    sz fd_count;

    mio::Poll* poller;
    mio::Events events;
}

tlocal IoContext* ctx @local = null;

fn void init()
{
    if (ctx != null) return;

    aio::init();

    ctx = aio::localmem.alloc(IoContext)!!;

    *ctx = {
        .fd_count = 0,
        .poller = null,
        .events = {},
    };

    for (sz i = 0; i < MAX_FD_WATCH; i++)
    {
        ctx.fd_table[i] = {};
    }

    ctx.poller = mio::poll_new(MAX_EVENTS)!!;
    ctx.events = mio::events_new(MAX_EVENTS)!!;
}

fn void deinit()
{
    if (ctx == null) return;

    ctx.events.free();

    if (ctx.poller != null)
    {
        ctx.poller.free();
        ctx.poller = null;
    }

    aio::localmem.free(ctx);
    ctx = null;
}

fn bool set_nonblocking(mio::Fd fd)
{
    if (catch err = mio::set_nonblock_fd(fd))
    {
        return false;
    }

    return true;
}

fn Watch* find_or_create(mio::Fd fd) @local
{
    @assert(fd >= 0 && (sz)fd < MAX_FD_WATCH);

    Watch* w = &ctx.fd_table[(sz)fd];

    if (!w.active)
    {
        *w = {
            .fd = fd,
            .active = true,
            .internal = false,
            .poll_read_registered = false,
            .poll_write_registered = false,
            .read_fut = null,
            .write_fut = null,
        };

        ctx.fd_count++;
    }

    return w;
}

fn Watch* find(mio::Fd fd)
{
    if (fd < 0 || (sz)fd >= MAX_FD_WATCH) return null;

    Watch* w = &ctx.fd_table[(sz)fd];

    return w.active ? w : null;
}

fn bool poll_update(Watch* w, bool want_read, bool want_write)
{
    if (ctx == null) return false;
    if (ctx.poller == null) return false;
    if (w == null) return false;

    bool old_registered = w.poll_read_registered || w.poll_write_registered;
    bool new_registered = want_read || want_write;

    if (!old_registered && !new_registered)
    {
        w.poll_read_registered = false;
        w.poll_write_registered = false;
        return true;
    }

    if (old_registered && !new_registered)
    {
        if (catch err = ctx.poller.deregister(w.fd))
        {
            return false;
        }

        w.poll_read_registered = false;
        w.poll_write_registered = false;
        return true;
    }

    mio::Interest interest = {
        .read = want_read,
        .write = want_write,
    };

    if (!old_registered)
    {
        if (catch err = ctx.poller.register(w.fd, interest))
        {
            return false;
        }
    }
    else
    {
        if (catch err = ctx.poller.reregister(w.fd, interest))
        {
            return false;
        }
    }

    w.poll_read_registered = want_read;
    w.poll_write_registered = want_write;

    return true;
}

fn void register_read(mio::Fd fd, Future* future)
{
    Watch* w = find_or_create(fd);

    if (w.read_fut != null)
    {
        w.read_fut.cancel();
    }

    w.read_fut = future;

    if (!poll_update(w, true, w.write_fut != null))
    {
        w.read_fut = null;
        future.cancel(aio::POLL_ERROR);
    }
}

fn void register_write(mio::Fd fd, Future* future)
{
    Watch* w = find_or_create(fd);

    if (w.write_fut != null)
    {
        w.write_fut.cancel();
    }

    w.write_fut = future;

    if (!poll_update(w, w.read_fut != null, true))
    {
        w.write_fut = null;
        future.cancel(aio::POLL_ERROR);
    }
}

fn void unregister(mio::Fd fd)
{
    Watch* w = find(fd);
    if (w == null) return;

    if (w.read_fut)
    {
        w.read_fut.cancel();
        w.read_fut = null;
    }

    if (w.write_fut)
    {
        w.write_fut.cancel();
        w.write_fut = null;
    }

    poll_update(w, false, false);

    w.active = false;
    w.internal = false;
    w.poll_read_registered = false;
    w.poll_write_registered = false;

    ctx.fd_count--;
}

fn void? wait_readable(mio::Fd fd) @maydiscard
{
    Future* fut = aio::future_new()!;
    defer fut.free();

    register_read(fd, fut);

    void*? res = fut.await();

    if (catch err = res)
    {
        Watch* w = find(fd);

        if (w != null && w.read_fut == fut)
        {
            w.read_fut = null;
            poll_update(w, false, w.write_fut != null);
        }

        if (fut.error == aio::IO_ERROR)
        {
            return aio::IO_ERROR~;
        }

        return err~;
    }
}

fn void? wait_writable(mio::Fd fd) @maydiscard
{
    Future* fut = aio::future_new()!;
    defer fut.free();

    register_write(fd, fut);

    void*? res = fut.await();

    if (catch err = res)
    {
        Watch* w = find(fd);

        if (w != null && w.write_fut == fut)
        {
            w.write_fut = null;
            poll_update(w, w.read_fut != null, false);
        }

        if (fut.error == aio::IO_ERROR)
        {
            return aio::IO_ERROR~;
        }

        return err~;
    }
}

fn void poll_wake()
{
    if (ctx == null) return;
    if (ctx.poller == null) return;
    if (ctx.poller.waker == null) return;

    (void)ctx.poller.waker.wake();
}

fn void poll_wakeup_handler()
{
    (void)aio::current_loop().threadsafe.process();
}

fn bool pending() @inline
{
    if (ctx == null) return false;

    for (sz i = 0; i < MAX_FD_WATCH; i++)
    {
        Watch* w = &ctx.fd_table[i];

        if (!w.active) continue;
        if (w.internal) continue;

        if (w.read_fut != null) return true;
        if (w.write_fut != null) return true;
    }

    return false;
}

fn void complete_error(Watch* w, fault err = aio::POLL_ERROR)
{
    if (w.read_fut)
    {
        Future* f = w.read_fut;
        w.read_fut = null;
        f.cancel(err);
    }

    if (w.write_fut)
    {
        Future* f = w.write_fut;
        w.write_fut = null;
        f.cancel(err);
    }

    poll_update(w, false, false);
}

fn void complete_read(Watch* w)
{
    if (w.read_fut == null) return;

    Future* f = w.read_fut;
    w.read_fut = null;

    poll_update(w, false, w.write_fut != null);

    f.set_result(null);
}

fn void complete_write(Watch* w)
{
    if (w.write_fut == null) return;

    Future* f = w.write_fut;
    w.write_fut = null;

    poll_update(w, w.read_fut != null, false);

    f.set_result(null);
}

fn void poll(ulong timeout_us)
{
    if (ctx == null) return;
    if (ctx.poller == null) return;

    ulong ms = timeout_us / 1000;
    long timeout_ms = ms > 2_147_483_647 ? -1 : (long)ms;

    if (catch err = ctx.poller.poll(&ctx.events, timeout_ms))
    {
        return;
    }

    poll_wakeup_handler();

    for (sz i = 0; i < ctx.events.len; i++)
    {
        mio::Event* event = ctx.events.get(i);
        if (event == null) continue;

        Watch* w = find(event.fd);
        if (w == null) continue;

        if (event.error)
        {
            complete_error(w, aio::POLL_ERROR);
            continue;
        }

        if ((event.read || event.hup) && w.read_fut)
        {
            complete_read(w);
            continue;
        }

        if (event.write && w.write_fut)
        {
            complete_write(w);
            continue;
        }

        if (event.hup && w.write_fut)
        {
            Future* f = w.write_fut;
            w.write_fut = null;

            poll_update(w, w.read_fut != null, false);

            f.cancel(aio::POLL_ERROR);
            continue;
        }
    }
}

fn bool would_block_fault(fault err) @inline
{
    return
        err == errno::E_AGAIN ||
        err == errno::E_WOULD_BLOCK ||
        err == errno::E_IN_PROGRESS ||
        err == errno::E_ALREADY;
}

fn sz? async_read(mio::Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    while (true)
    {
        sz? n = mio::tcp_read_fd(fd, buf);

        if (catch err = n)
        {
            if (!would_block_fault(err))
            {
                return err~;
            }

            wait_readable(fd)!;
            continue;
        }

        return n;
    }
}

fn sz? async_write(mio::Fd fd, char[] buf)
{
    if (buf.len == 0) return 0;

    sz total = 0;

    while (total < buf.len)
    {
        sz? n = mio::tcp_write_fd(fd, buf[total .. buf.len - 1]);

        if (catch err = n)
        {
            if (!would_block_fault(err))
            {
                if (total > 0) return total;
                return err~;
            }

            wait_writable(fd)!;
            continue;
        }

        if (n == 0) break;

        total += n;
    }

    return total;
}

fn sz? async_recvfrom(mio::Fd fd, char[] buf, char* ip_str, sz* ip_len, ushort* port)
{
    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (ip_len == null) return errno::E_INVALID_ARG~;
    if (port == null) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;

    char[128] ip_buf;

    while (true)
    {
        sz? n = mio::udp_recvfrom_fd(fd, buf, ip_buf[..], port);

        if (catch err = n)
        {
            if (!would_block_fault(err))
            {
                return err~;
            }

            wait_readable(fd)!;
            continue;
        }

        sz len = (sz)string::strlen(&ip_buf[0]);

        string::memcpy(ip_str, &ip_buf[0], len);
        ip_str[len] = 0;
        *ip_len = len;

        return n;
    }
}

fn sz? async_sendto(mio::Fd fd, char[] buf, char* ip_str, ushort port)
{
    if (ip_str == null) return errno::E_INVALID_ARG~;
    if (buf.len == 0) return 0;

    String ip = (String)ip_str[0:string::strlen(ip_str)];

    while (true)
    {
        sz? n = mio::udp_sendto_fd(fd, buf, ip, port);

        if (catch err = n)
        {
            if (!would_block_fault(err))
            {
                return err~;
            }

            wait_writable(fd)!;
            continue;
        }

        return n;
    }
}

fn mio::Fd[2]? pipe_open()
{
    mio::Poll* poll = mio::poll_new(16)!;
    defer poll.free();

    mio::Events events = mio::events_new(16)!;
    defer events.free();

    mio::TcpListener listener = mio::tcp_listen("127.0.0.1", 0)!;
    defer listener.close();

    char[64] ip_buf;
    ushort port = 0;

    listener.local_addr(ip_buf[..], &port)!;

    mio::TcpStream client = mio::tcp_connect("127.0.0.1", port)!;
    defer (catch err) client.close();

    poll.register(listener.fd, mio::want_read())!;
    poll.register(client.fd, mio::want_write())!;

    mio::TcpStream server = {};
    bool accepted = false;
    bool connected = false;

    defer (catch err)
    {
        if (accepted) server.close();
    }

    while (!accepted || !connected)
    {
        poll.poll(&events, 1000)!;

        if (events.is_empty())
        {
            return aio::IO_ERROR~;
        }

        for (sz i = 0; i < events.len; i++)
        {
            mio::Event* event = events.get(i);
            if (event == null) continue;

            if (!accepted && event.fd == listener.fd && event.read)
            {
                ushort peer_port = 0;

                server = listener.accept(ip_buf[..], &peer_port)!;
                accepted = true;
                continue;
            }

            if (!connected && event.fd == client.fd && (event.write || event.error || event.hup))
            {
                int err = client.take_error();

                if (err != 0)
                {
                    return aio::IO_ERROR~;
                }

                connected = true;
                continue;
            }
        }
    }

    (void)poll.deregister(listener.fd);
    (void)poll.deregister(client.fd);

    return { server.fd, client.fd };
}

fn void fd_close(mio::Fd fd)
{
    if (fd_invalid(fd)) return;

    unregister(fd);

    mio::socket_close_fd(fd);
}

// eof