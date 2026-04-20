// sample10.c3

module example;

import std::io;
import ext::asyncio;
import c::string;
import ext::debug; // warn

asyncio::Server* g_server;

fn String bcat(char[] buf, String... args) @inline
{
    buf[0] = 0;
    foreach (arg: args) {
        string::strcat(buf.ptr, arg.ptr);
    }
    usz n = string::strlen(buf.ptr);
    return (String)buf[0..n-1];
}

fn int strncasecmp(char* a, char* b, usz n) @if(env::WIN32)
{
    return string::_strnicmp(a, b, n);
}

fn int strncasecmp(char* a, char* b, usz n) @if(env::POSIX)
{
    return string::strncasecmp(a, b, n);
}

fn void echo_handler(asyncio::Stream* stream)
{
    io::printfn("[server] client connected, send welcome");

    char[] welcome = "+OK server ready\n";
    stream.write(welcome)!!;

    // Read lines and echo them back until the client closes the connection.
    int count = 0;
    while (true)
    {
        io::printfn("[server] readline() %d", count++);

        char[256] cmd;
        usz n = stream.readline(&cmd)!!;
        if (n == 0) {
            // asyncio::warn("server readline failed");
            break; // EOF or closed
        }
        io::printfn("[server] received: %s", (String)cmd[0:n]);

        if (strncasecmp(&cmd[0], "QUIT", 4) == 0) {
            String resp = "+OK Server closing connection.\n";
            stream.write(resp)!!;
            break;
        }
        
        if (strncasecmp(&cmd[0], "STOP", 4) == 0) {
            String resp = "+OK Server stopping.\n";
            stream.write(resp)!!;
            
            g_server.stop();
            
            break;
        }

        char[256] respbuf;
        String resp = bcat(&respbuf, "+OK ", (String)cmd[0:n], "\n");
        stream.write(resp)!!;
    }

    io::printfn("[server] connection closed");

    // The handler owns the Stream — close it here.
    stream.close();
}


fn void server_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    Server*? server = asyncio::start_server(&echo_handler, "127.0.0.1", 9100);
    if (catch err = server)
    {
        io::printfn("[server] start_server failed: %s", err);
        return;
    }

    g_server = server;
    
    io::printfn("[server] listening on 127.0.0.1:9100");

    // Blocks here until server.stop() is called.
    server.serve_forever();

    server.free();
    io::printfn("[server] shut down");
}

fn void client_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Give the server coroutine time to reach serve_forever().
    asyncio::sleep_zero();
    asyncio::sleep_zero();

    // asyncio::warn("client open_connection()");
    Stream*? stream = asyncio::open_connection("127.0.0.1", 9100);
    if (catch err = stream)
    {
        io::printfn("[client] connect failed: %s", err);
        return;
    }

    io::printfn("[client] connected");
 
    // asyncio::warn("client%p readline welcome", stream);
   
    char[256] rbuf;
    usz n = stream.readline(&rbuf)!!;
    io::printfn("[client] welcome: %s", (String)rbuf[0:n]);

    // asyncio::warn("client%p write msg1", stream);
    char[] msg1 = "msg1: Hello, asyncio!\n";
    stream.write(msg1)!!;

    // asyncio::warn("client%p readline msg1", stream);
    n = stream.readline(&rbuf)!!; // read exactly as many bytes back
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);
    
    // asyncio::warn("client%p write msg2", stream);
    char[] msg2 = "msg2: World!\n";
    stream.write(msg2)!!;

    io::printfn("[client] readline..");

    n = stream.readline(&rbuf)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    char[] msg3 = "QUIT\n";
    stream.write(msg3)!!;

    io::printfn("[client] readline..");

    n = stream.readline(&rbuf)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    stream.close();
    io::printfn("[client] done");
}


fn void client_stop()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Give the server coroutine time to reach serve_forever().
    asyncio::sleep_zero();
    asyncio::sleep_zero();

    // asyncio::warn("client open_connection()");
    Stream*? stream = asyncio::open_connection("127.0.0.1", 9100);
    if (catch err = stream) {
        io::printfn("[client] connect failed: %s", err);
        return;
    }

    io::printfn("[client] connected");
 
    // asyncio::warn("client%p readline welcome", stream);
   
    char[256] rbuf;
    usz n = stream.readline(&rbuf)!!;
    io::printfn("[client] welcome: %s", (String)rbuf[0:n]);

    // asyncio::warn("client%p write msg1", stream);
    char[] msg1 = "msg1: Hello, asyncio!\n";
    stream.write(msg1)!!;

    // asyncio::warn("client%p readline msg1", stream);
    n = stream.readline(&rbuf)!!; // read exactly as many bytes back
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);
    
    // asyncio::warn("client%p write msg2", stream);
    char[] msg2 = "msg2: World!\n";
    stream.write(msg2)!!;

    io::printfn("[client] readline..");

    n = stream.readline(&rbuf)!!;
    io::printfn("[client] echo: %s", (String)rbuf[0:n]);

    char[] msg3 = "STOP\n";
    stream.write(msg3)!!;

    io::printfn("[client] readline..");

    usz? n2 = stream.readline(&rbuf);
    if (catch err = n2) {
        warn("err:%s but OK", err);
    } else {
        io::printfn("[client] echo: %s", (String)rbuf[0:n]);
    }

    stream.close();
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
    for (usz i = 0; i < ts.len; i++) {
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
  // @assert_leak() {
    asyncio::run(&main_coro);
 //  };
}
