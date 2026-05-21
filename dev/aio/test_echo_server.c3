// echo_echo_server.c3

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
    Server* server = (Server*)arg;
    if (server == null) return aio::INVALID_STATE~;

    if (catch err = server.serve_forever())
    {
        if (err == aio::CANCELLED) return;
        if (err == aio::CLOSED) return;
        if (err == aio::IO_ERROR) return;

        return err~;
    }

    warn("server task end");
}

fn void? client_task(void* arg)
{
    Server* server = (Server*)arg;
    if (server == null) return aio::INVALID_STATE~;

    defer server.close();

    Stream* s = aio::open_connection("127.0.0.1", 8080)!;
    defer s.free();

    char[1024] buf;

    String msg1 = "hello-1";
    s.write_all(msg1)!;

    usz n = s.read(buf[..])!;
    assert_echo(msg1, buf[0:n]);
    warn("client recv: %s", (String)buf[0:n]);

    String msg2 = "hello-2";
    s.write_all(msg2)!;

    n = s.read(buf[..])!;
    assert_echo(msg2, buf[0:n]);
    warn("client recv: %s", (String)buf[0:n]);

    s.close();

    warn("client force server to close");
}

fn void? main_task(void* arg)
{
    Server* server = aio::start_server(&handle_client, "0.0.0.0", 8080)!;
    defer server.free();

    warn("server listening on 0.0.0.0:8080");

    Task* st = aio::spawn_joinable(&server_task, server)!;

    aio::sleep(100)!;

    Task* ct = aio::spawn_joinable(&client_task, server)!;

    ct.join()!;
    st.join()!;

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof