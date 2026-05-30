// sample10.c3

module example;

import std::io;
import ext::asyncio;
import c::string;

asyncio::Server* g_server;

fn String bcat(char[] buf, String... args) @inline
{
    buf[0] = 0;
    foreach (arg: args) {
        string::strcat(buf.ptr, arg.ptr);
    }
    sz n = string::strlen(buf.ptr);
    return (String)buf[0..n-1];
}

fn int strncasecmp(char* a, char* b, sz n) @if(env::WIN32)
{
    return string::_strnicmp(a, b, n);
}

fn int strncasecmp(char* a, char* b, sz n) @if(env::POSIX)
{
    return string::strncasecmp(a, b, n);
}

fn void server_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    Datagram*? server = asyncio::bind_endpoint("127.0.0.1", 9100);
    if (catch err = server)
    {
        io::printfn("[server] bind_endpoint failed: %s", err);
        return;
    }

    while (!server.closed) {
        char[1024] buf;
        char[128] ip;
        sz iplen;
        ushort port;
        char[1024] respbuf;
        
        sz n = server.recvfrom(&buf, &ip, &iplen, &port)!!;
        if (n == 0) {
            io::printfn("[server] recvfrom failed: %s", server.error);
            break;
        }
        io::printfn("[server] recvd:%s, from:%s:%d", (String)buf[0:n], (String)ip[0:iplen], port);

        if (strncasecmp(&buf[0], "STOP", 4) == 0) {
            String resp = bcat(&respbuf, "+OK shutdown");
            io::printfn("[server] send:%s, to:%s:%d", resp, (String)ip[0:iplen], port);
    
            n = server.sendto(resp, ip[0:iplen], port)!!;
            
            break;
        }
        
        String resp = bcat(&respbuf, "+OK ", (String)buf[0:n]);
        io::printfn("[server] send:%s, to:%s:%d", resp, (String)ip[0:iplen], port);

        n = server.sendto(resp, ip[0:iplen], port)!!;
        if (n == 0) {
            io::printfn("[server] sendto failed: %s", server.error);
            break;
        }
    }
    
    server.close();
    io::printfn("[server] shut down");
}

fn void client_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Give the server coroutine time to reach serve_forever().
    asyncio::sleep_zero();
    asyncio::sleep_zero();

    int sock = asyncio::socket("IPV4", "UDP");

    char[] msg1 = "msg1: Hello, asyncio!";
    io::printfn("[client] sock_sendto: %s", (String)msg1);
    loop.sock_sendto(sock, msg1, "127.0.0.1", 9100)!!;

    char[1024] rbuf;
    char[64] ip;
    sz iplen;
    ushort port;
    
    sz n = loop.sock_recvfrom(sock, &rbuf, &ip, &iplen, &port)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);
    
    char[] msg2 = "msg2: World!";
    io::printfn("[client] sock_sendto: %s", (String)msg2);
    loop.sock_sendto(sock, msg2, "127.0.0.1", 9100)!!;

    n = loop.sock_recvfrom(sock, &rbuf, &ip, &iplen, &port)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    char[] msg3 = "QUIT";
    io::printfn("[client] sock_sendto: %s", (String)msg3);
    loop.sock_sendto(sock, msg3, "127.0.0.1", 9100)!!;

    n = loop.sock_recvfrom(sock, &rbuf, &ip, &iplen, &port)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    asyncio::socket_close(sock);
    io::printfn("[client] done");
}


fn void client_stop()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Give the server coroutine time to reach serve_forever().
    asyncio::sleep_zero();
    asyncio::sleep_zero();

    int sock = asyncio::socket("IPV4", "UDP");

    char[] msg1 = "msg1: Hello, asyncio!";
    io::printfn("[client] sock_sendto: %s", (String)msg1);
    loop.sock_sendto(sock, msg1, "127.0.0.1", 9100)!!;

    char[1024] rbuf;
    char[64] ip;
    sz iplen;
    ushort port;
    
    sz n = loop.sock_recvfrom(sock, &rbuf, &ip, &iplen, &port)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);
    
    char[] msg2 = "msg2: World!";
    io::printfn("[client] sock_sendto: %s", (String)msg2);
    loop.sock_sendto(sock, msg2, "127.0.0.1", 9100)!!;

    n = loop.sock_recvfrom(sock, &rbuf, &ip, &iplen, &port)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    char[] msg3 = "STOP";
    io::printfn("[client] sock_sendto: %s", (String)msg3);
    loop.sock_sendto(sock, msg3, "127.0.0.1", 9100)!!;

    n = loop.sock_recvfrom(sock, &rbuf, &ip, &iplen, &port)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    asyncio::socket_close(sock);
    io::printfn("[client] done");
}


// ========================================
//  Main coroutine — entry point for the event loop
// ========================================

fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Spawn the server first.
    // asyncio::warn("create_task server");
    Task* server_t = loop.create_task(&server_coro, "server", 64_000, false);
    
    // Yield once so the server reaches serve_forever before we proceed.
    asyncio::sleep(0.1);

    // Spawn the client and wait for it to finish.
    Task*[20] ts;
    for (sz i = 0; i < ts.len; i++) {
        // asyncio::warn("create_task client");
        ts[i] = loop.create_task(&client_coro, "client", 80_000, false); // autofree==false, free'd at gather()
    }

    asyncio::gather(&ts);

    // asyncio::warn("create_task stop");
    Task* stop_t = loop.create_task(&client_stop, "client", 80_000, false);
    
    stop_t.await();
    server_t.await();

    stop_t.free();
    server_t.free();
}

// ========================================
//  Entry point
// ========================================

fn void main()
{
  @assert_leak() {
    asyncio::run(&main_coro);
  };
}
