// test_timeout_all.c3

import ext::aio;
import ext::debug;
import ext::mem;

Server* g_read_server = null;
Server* g_write_server = null;

bool read_server_started = false;
bool read_client_connected = false;
bool read_timeout_seen = false;
bool read_server_stopped = false;

bool write_server_started = false;
bool write_client_connected = false;
bool write_timeout_seen = false;
bool write_server_stopped = false;

bool open_timeout_checked = false;


fn void? handle_read_timeout_client(Stream* s)
{
    warn("[read-timeout] client connected ip=%s", s.peer_ip()!!);

    char[128] buf;

    if (catch err = s.read_timeout(buf[..], 200))
    {
        warn("[read-timeout] err=%s", err);

        @assert(err == aio::TIMEOUT, "read_timeout() must return aio::TIMEOUT");

        read_timeout_seen = true;
    }
    else
    {
        @assert(false, "read_timeout() unexpectedly succeeded");
    }

    warn("[read-timeout] ok");
}

fn void? handle_write_timeout_client(Stream* s)
{
    warn("[write-timeout] client connected ip=%s", s.peer_ip()!!);

    // Do not read from the client.
    // This should eventually make the client's send buffer fill.
    aio::sleep(2000)!;

    warn("[write-timeout] server closing idle client");
}

fn void? read_timeout_server_task(void* arg)
{
    g_read_server = aio::start_server(&handle_read_timeout_client, "127.0.0.1", 8080)!;

    read_server_started = true;

    warn("[server] listening for read-timeout test");

    g_read_server.serve_forever();

    g_read_server.wait_closed()!;

    g_read_server.free();
    g_read_server = null;

    read_server_stopped = true;
}

fn void? read_timeout_client_task(void* arg)
{
    while (g_read_server == null)
    {
        aio::yield();
    }

    Stream* s = aio::stream_connect("127.0.0.1", 8080)!;
    defer s.free();

    read_client_connected = true;

    warn("[read-timeout-client] connected, staying idle");

    aio::sleep(500)!;

    @assert(read_timeout_seen, "server did not observe read timeout");

    if (g_read_server != null)
    {
        g_read_server.close();
    }

    warn("[read-timeout-client] done");
}

fn void? write_timeout_server_task(void* arg)
{
    g_write_server = aio::start_server(&handle_write_timeout_client, "127.0.0.1", 8081)!;

    write_server_started = true;

    warn("[server] listening for write-timeout test");

    g_write_server.serve_forever();

    g_write_server.wait_closed()!;

    g_write_server.free();
    g_write_server = null;

    write_server_stopped = true;
}

fn void? write_timeout_client_task(void* arg)
{
    while (g_write_server == null)
    {
        aio::yield();
    }

    Stream* s = aio::stream_connect("127.0.0.1", 8081)!;
    defer s.free();

    write_client_connected = true;

    warn("[write-timeout-client] connected");

    const sz BIG_SIZE = 64 * 1024 * 1024;

    char* big = mem::malloc(BIG_SIZE);
    if (big == null) return aio::OUT_OF_MEMORY~;
    defer mem::free(big);

    for (sz i = 0; i < BIG_SIZE; i++)
    {
        big[i] = 'A';
    }

    if (catch err = s.write_all_timeout((char[])big[0:BIG_SIZE], 200))
    {
        warn("[write-timeout-client] err=%s", err);

        @assert(err == aio::TIMEOUT, "write_all_timeout() must return aio::TIMEOUT");

        write_timeout_seen = true;
    }
    else
    {
        @assert(false, "write_all_timeout() unexpectedly succeeded");
    }

    if (g_write_server != null)
    {
        g_write_server.close();
    }

    warn("[write-timeout-client] done");
}

fn void? stream_connect_timeout_task(void* arg)
{
    warn("[open-timeout] connecting to blackhole address");

    if (catch err = aio::stream_connect_timeout("10.255.255.1", 65000, 300))
    {
        warn("[open-timeout] err=%s", err);

        @assert(
            err == aio::TIMEOUT || err == aio::CONNECT_ERROR,
            "stream_connect_timeout() must return aio::TIMEOUT or aio::CONNECT_ERROR"
        );

        open_timeout_checked = true;
    }
    else
    {
        @assert(false, "stream_connect_timeout() unexpectedly succeeded");
    }

    warn("[open-timeout] done");
}

fn void? main_task(void* arg)
{
    Task* t1 = aio::spawn_joinable(&read_timeout_server_task)!;
    Task* t2 = aio::spawn_joinable(&read_timeout_client_task)!;

    t2.join();
    t1.join();

    @assert(read_server_started, "read-timeout server did not start");
    @assert(read_client_connected, "read-timeout client did not connect");
    @assert(read_timeout_seen, "read timeout was not observed");
    @assert(read_server_stopped, "read-timeout server did not stop");
    @assert(g_read_server == null, "read-timeout server was not cleared");

    Task* t3 = aio::spawn_joinable(&write_timeout_server_task)!;
    Task* t4 = aio::spawn_joinable(&write_timeout_client_task)!;

    t4.join();
    t3.join();

    @assert(write_server_started, "write-timeout server did not start");
    @assert(write_client_connected, "write-timeout client did not connect");
    @assert(write_timeout_seen, "write timeout was not observed");
    @assert(write_server_stopped, "write-timeout server did not stop");
    @assert(g_write_server == null, "write-timeout server was not cleared");

    Task* t5 = aio::spawn_joinable(&stream_connect_timeout_task)!;
    t5.join();

    @assert(open_timeout_checked, "stream_connect_timeout test did not complete");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof