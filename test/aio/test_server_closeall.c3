// test_server_closeall.c3

import ext::aio;
import ext::debug;

Server* g_server = null;

bool server_started = false;
bool server_closed = false;
bool server_freed = false;

bool client_connected = false;
bool client_read_closed = false;

bool handler_started = false;
bool handler_ended = false;
bool stopper_done = false;

fn bool close_error(fault err)
{
    return err == aio::CLOSED ||
           err == aio::CANCELLED ||
           err == aio::IO_ERROR;
}

fn void? handle_client(Stream* s)
{
    handler_started = true;

    defer {
        handler_ended = true;
        warn("handler: ended");
    }

    warn("handler: client connected ip=%s", s.peer_ip()!!);

    char[128] buf;

    sz? n = s.read(buf[..]);
    if (catch err = n)
    {
        warn("handler: read ended err=%s", err);

        if (err == aio::CANCELLED ||
            err == aio::CLOSED ||
            err == aio::IO_ERROR ||
            err == aio::POLL_ERROR)
        {
            return;
        }

        return err~;
    }

    if (n == 0)
    {
        warn("handler: read returned EOF");
        return;
    }

    warn("handler: unexpected data n=%d", n);
}

fn void? server_task(void* arg)
{
    g_server = aio::start_server(&handle_client, "127.0.0.1", 8080)!;
    server_started = true;

    warn("server: listening");

    g_server.serve_forever();

    server_closed = true;

    warn("server: serve_forever stopped");

    g_server.wait_closed()!;

    g_server.free();
    g_server = null;
    server_freed = true;

    warn("server: freed");
}

fn void? client_task(void* arg)
{
    while (g_server == null)
    {
        aio::yield();
    }

    Stream* s = aio::stream_connect("127.0.0.1", 8080)!;
    defer s.free();

    client_connected = true;

    warn("client: connected, waiting for server close");

    char[128] buf;

    if (catch err = s.read(buf[..]))
    {
        warn("client: read ended err=%s", err);

        @assert(close_error(err), "client read ended with unexpected error");

        client_read_closed = true;
        return;
    }

    client_read_closed = true;

    warn("client: read returned EOF");
}

fn void? stopper_task(void* arg)
{
    while (g_server == null)
    {
        aio::sleep(1)!;
    }
    aio::sleep(300)!;

    warn("stopper: closing server");

    @assert(g_server != null, "server must exist before close");

    g_server.close();

    stopper_done = true;

    warn("stopper: done");
}

fn void? main_task(void* arg)
{
    Task* st = aio::spawn_joinable(&server_task)!;
    Task* ct = aio::spawn_joinable(&client_task)!;
    Task* xt = aio::spawn_joinable(&stopper_task)!;

    xt.join()!;
    ct.join()!;
    st.join()!;

    @assert(server_started, "server did not start");
    @assert(client_connected, "client did not connect");
    @assert(handler_started, "handler was not started");

    @assert(stopper_done, "stopper did not run");
    @assert(client_read_closed, "client did not observe server close");
    @assert(handler_ended, "handler did not end after server close");

    @assert(server_closed, "server serve_forever did not stop");
    @assert(server_freed, "server was not freed");
    @assert(g_server == null, "g_server was not cleared");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof