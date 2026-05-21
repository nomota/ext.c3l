// test_read_timeout.c3

import ext::aio;
import ext::debug;

Server* g_server = null;

bool server_listened = false;
bool client_connected = false;
bool timeout_seen = false;
bool server_closed_client = false;
bool server_stopped = false;

fn void? handle_client(Stream* s)
{
    warn("server: client connected");

    defer s.free();

    char[128] buf;

    if (catch err = s.read_timeout(buf[..], 200))
    {
        warn("server: read timeout err=%s", err);

        @assert(err == aio::TIMEOUT, "read_timeout() must fail with aio::TIMEOUT");

        timeout_seen = true;
    }
    else
    {
        @assert(false, "read_timeout() unexpectedly succeeded");
    }

    warn("server: closing client");

    server_closed_client = true;
}

fn void? server_task(void* arg)
{
    g_server = aio::start_server(&handle_client, "127.0.0.1", 8080)!;

    server_listened = true;
    warn("server: listening");

    if (catch err = g_server.serve_forever())
    {
        if (err != aio::CANCELLED && err != aio::CLOSED && err != aio::IO_ERROR)
        {
            return err~;
        }
    }

    g_server.wait_closed()!;

    g_server.free();
    g_server = null;

    server_stopped = true;
}

fn void? client_task(void* arg)
{
    while (g_server == null)
    {
        aio::yield();
    }

    Stream* s = aio::open_connection("127.0.0.1", 8080)!;
    defer s.free();

    client_connected = true;

    warn("client: connected, idle");

    aio::sleep(500)!;

    @assert(timeout_seen, "server did not observe read timeout while client was idle");

    if (g_server != null)
    {
        g_server.close();
    }
}

fn void? main_task(void* arg)
{
    Task* st = aio::spawn_joinable(&server_task)!;
    Task* ct = aio::spawn_joinable(&client_task)!;

    ct.join()!;
    st.join()!;

    @assert(server_listened, "server did not start listening");
    @assert(client_connected, "client did not connect");
    @assert(timeout_seen, "read timeout did not occur");
    @assert(server_closed_client, "server did not close client after timeout");
    @assert(server_stopped, "server did not stop");
    @assert(g_server == null, "global server was not cleared");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof