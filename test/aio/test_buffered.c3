// test_buffered.c3

import ext::aio;
import ext::debug;

Server* g_server = null;

bool server_started = false;
bool server_got_line = false;
bool server_echoed = false;
bool server_closed = false;

bool client_connected = false;
bool client_got_line = false;
bool client_done = false;

const String TEST_LINE = "hello buffered\n";

fn void? handle_client(Stream* s)
{
    BufferedStream* bs = aio::buffered_new(s, 1024, false)!;
    defer bs.free();

    char[128] line;

    sz n = bs.read_line(line[..])!;

    warn("server got line: '%s'", (String)line[0:n]);

    @assert(n == TEST_LINE.len, "server read_line length mismatch");
    @assert((String)line[0:n] == TEST_LINE, "server read_line content mismatch");

    server_got_line = true;

    bs.write_all(line[0:n])!;

    server_echoed = true;
}

fn void? server_task(void* arg)
{
    g_server = aio::start_server(&handle_client, "127.0.0.1", 8080)!;
    server_started = true;

    warn("server listening");

    g_server.serve_forever();

    server_closed = true;

    g_server.wait_closed()!;

    g_server.free();
    g_server = null;
}

fn void? client_task(void* arg)
{
    while (g_server == null)
    {
        aio::yield();
    }

    aio::sleep(100)!;

    Stream* s = aio::stream_connect("127.0.0.1", 8080)!;
    BufferedStream* bs = aio::buffered_new(s, 1024, true)!;
    defer bs.free();

    client_connected = true;

    bs.write_all(TEST_LINE)!;

    char[128] line;
    sz n = bs.read_line(line[..])!;

    warn("client got line: '%s'", (String)line[0:n]);

    @assert(n == TEST_LINE.len, "client read_line length mismatch");
    @assert((String)line[0:n] == TEST_LINE, "client read_line content mismatch");

    client_got_line = true;

    if (g_server != null)
    {
        g_server.close();
    }

    client_done = true;
}

fn void? main_task(void* arg)
{
    Task* st = aio::spawn_joinable(&server_task)!;
    Task* ct = aio::spawn_joinable(&client_task)!;

    ct.join()!;
    st.join()!;

    @assert(server_started, "server did not start");
    @assert(client_connected, "client did not connect");

    @assert(server_got_line, "server did not receive line");
    @assert(server_echoed, "server did not echo line");
    @assert(client_got_line, "client did not receive echoed line");

    @assert(client_done, "client task did not finish");
    @assert(server_closed, "server did not close");
    @assert(g_server == null, "g_server was not cleared");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof