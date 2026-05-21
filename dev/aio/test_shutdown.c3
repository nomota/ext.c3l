// test_shutdown.c3

import ext::aio;
import ext::debug;

Server* g_server = null;
bool server_listened = false;
bool close_requested = false;
bool server_stopped = false;

fn void? handle_client(Stream* s)
{
    String ip = s.peer_ip()!;
    defer aio::localmem.free(ip);

    warn("client connected ip=%s", ip);

    defer s.free();

    char[1024] buf;

    while (true)
    {
        usz n = s.read(buf[..])!;

        if (n == 0) break;

        s.write_all(buf[0:n])!;
    }

    warn("client closed");
}

fn void? server_task(void* arg)
{
    g_server = aio::start_server(&handle_client, "127.0.0.1", 8080)!;

    server_listened = true;
    warn("server listening");

    if (catch err = g_server.serve_forever())
    {
        if (err != aio::CANCELLED && err != aio::CLOSED && err != aio::IO_ERROR)
        {
            return err~;
        }
    }

    warn("server stopping clients");

    g_server.wait_closed()!;

    warn("server stopped");

    g_server.free();
    g_server = null;
    server_stopped = true;
}

fn void? stopper_task(void* arg)
{
    while (g_server == null)
    {
        aio::yield();
    }

    aio::sleep(500)!;

    warn("closing server");

    @assert(g_server != null, "server must exist before close");

    close_requested = true;
    g_server.close();
}

fn void? main_task(void* arg)
{
    Task* st = aio::spawn_joinable(&server_task)!;
    Task* ct = aio::spawn_joinable(&stopper_task)!;

    ct.join()!;
    st.join()!;

    @assert(server_listened, "server did not start listening");
    @assert(close_requested, "server close was not requested");
    @assert(server_stopped, "server did not stop");
    @assert(g_server == null, "global server was not cleared");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof