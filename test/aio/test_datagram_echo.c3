// test_datagram_echo.c3

import ext::aio;
import ext::debug;

bool server_started = false;
bool server_received = false;
bool server_echoed = false;
bool server_done = false;

bool client_sent = false;
bool client_received = false;
bool client_done = false;

const String TEST_MSG = "hello udp";

fn void? server_task(void* arg)
{
    Datagram* d = aio::datagram_bind("127.0.0.1", 9999)!;
    defer d.free();

    server_started = true;

    char[1024] buf;
    DatagramAddr from;

    sz n = d.recvfrom(buf[..], &from)!;

    warn(
        "server got '%s' from %s:%d",
        (String)buf[0:n],
        (String)from.ip[0:from.ip_len],
        from.port
    );

    @assert(n == TEST_MSG.len, "server received length mismatch");
    @assert((String)buf[0:n] == TEST_MSG, "server received content mismatch");
    @assert((String)from.ip[0:from.ip_len] == "127.0.0.1", "server received unexpected peer ip");
    @assert(from.port != 0, "server received invalid peer port");

    server_received = true;

    d.sendto(buf[0:n], (String)from.ip[0:from.ip_len], from.port)!;

    server_echoed = true;
    server_done = true;
}

fn void? client_task(void* arg)
{
    while (!server_started)
    {
        aio::yield();
    }

    aio::sleep(100)!;

    Datagram* d = aio::open_datagram()!;
    defer d.free();

    d.sendto(TEST_MSG, "127.0.0.1", 9999)!;

    client_sent = true;

    char[1024] buf;
    DatagramAddr from;

    sz n = d.recvfrom(buf[..], &from)!;

    warn("client got '%s'", (String)buf[0:n]);

    @assert(n == TEST_MSG.len, "client received length mismatch");
    @assert((String)buf[0:n] == TEST_MSG, "client received content mismatch");
    @assert((String)from.ip[0:from.ip_len] == "127.0.0.1", "client received unexpected peer ip");
    @assert(from.port == 9999, "client received unexpected peer port");

    client_received = true;
    client_done = true;
}

fn void? main_task(void* arg)
{
    Task* st = aio::spawn_joinable(&server_task)!;
    Task* ct = aio::spawn_joinable(&client_task)!;

    ct.join()!;
    st.join()!;

    @assert(server_started, "server did not start");
    @assert(client_sent, "client did not send datagram");

    @assert(server_received, "server did not receive datagram");
    @assert(server_echoed, "server did not echo datagram");
    @assert(server_done, "server task did not finish");

    @assert(client_received, "client did not receive echoed datagram");
    @assert(client_done, "client task did not finish");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task)!!;
}

// eof