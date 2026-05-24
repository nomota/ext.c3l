// test_tcp_echo.c3

import ext::aio;
import ext::debug;

fn void assert_echo(String expected, char[] got)
{
    @assert(got.len == expected.len, "echo length mismatch");
    @assert((String)got == expected, "echo payload mismatch");
}

fn void? handle_client(Stream* s)
{
    String ip = s.peer_ip()!;
    defer aio::localmem.free(ip);

    warn("server: client connected ip=%s", ip);

    defer s.free();

    char[1024] buf;

    while (true)
    {
        usz n = s.read(buf[..])!;

        if (n == 0)
        {
            break;
        }

        warn("server: received '%s'", (String)buf[0:n]);

        s.write_all(buf[0:n])!;
    }

    warn("server: client closed");
}

fn void? server_task(void* arg)
{
    Server* server = (Server*)arg;
    if (server == null) return aio::INVALID_STATE~;

    server.serve_forever();
}

fn void? client_task(void* arg)
{
    Server* server = (Server*)arg;
    if (server == null) return aio::INVALID_STATE~;

    aio::sleep(100)!;

    warn("client: connecting");

    Stream* s = aio::stream_connect("127.0.0.1", 8080)!;
    defer s.free();
    defer server.close();

    warn("client: connected");

    String msg = "hello aio";
    s.write_all(msg)!;

    char[1024] buf;
    usz n = s.read(buf[..])!;

    warn("client: got '%s'", (String)buf[0:n]);

    assert_echo(msg, buf[0:n]);

    s.close();

    warn("client: closed");
}

fn void? main_task(void* arg)
{
    Server* server = aio::start_server(&handle_client, "127.0.0.1", 8080)!;
    defer server.free();

    warn("server: listening on 127.0.0.1:8080");

    Task* st = aio::spawn_joinable(&server_task, server)!;
    Task* ct = aio::spawn_joinable(&client_task, server)!;

    ct.join();
    st.join();

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof