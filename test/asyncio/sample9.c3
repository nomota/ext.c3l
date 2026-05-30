// sample9.c3

// TCP echo server + client example using ext::asyncio.
// The server coroutine is spawned first; the client coroutine is
// created only after the server is listening.

module example;

import std::io;
import ext::asyncio;
import c::string;

// ========================================
//  Server-side Protocol
// ========================================

struct EchoServerP (Protocol) {
    Transport* transport;
    String msg;
}

fn EchoServerP* echoserverp_new(String msg)
{
    EchoServerP* p = mem::new(EchoServerP);
    *p = {
        .msg = msg,
    };
    return p;
}

fn void EchoServerP.free(&self)
{
    mem::free(self);
}

fn void EchoServerP.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;
    io::printfn("[server] client connected");
    self.transport.write(self.msg)!!;
}

fn void EchoServerP.data_received(&self, char[] data) @dynamic
{
    io::printfn("[server] received: %s", (String)data);
    self.transport.write(data)!!; // echo back
}

fn void EchoServerP.connection_lost(&self, fault exception) @dynamic
{
    io::printfn("[server] connection closed");
}


// =======================================
//  Client-side Protocol
// =======================================

struct EchoClientP (Protocol) {
    Transport* transport;
    Future* on_con_lost;
    String msg;
}

fn EchoClientP* echoclientp_new(String msg, Future* on_con_lost)
{
    EchoClientP* p = mem::new(EchoClientP);

    *p = {
        .on_con_lost = on_con_lost,
        .msg = msg, 
    };
  
    return p;
}

fn void EchoClientP.free(&self)
{
    mem::free(self);
}

fn void EchoClientP.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;
    io::printfn("[client] connected, sending: %s", (String)self.msg);
    self.transport.write(self.msg)!!;
}

fn void EchoClientP.data_received(&self, char[] data) @dynamic
{
    io::printfn("[client] echo received: %s", (String)data);
    self.transport.close(); // done after one round-trip
}

fn void EchoClientP.connection_lost(&self, fault exception) @dynamic
{
    io::printfn("[client] connection closed");
    self.on_con_lost.set_result(null);
}


// ========================================
//  Coroutines
// ========================================

// Shared handle so the client coroutine can stop the server.
asyncio::Server* g_server;
EchoServerP* g_proto;
// Server coroutine: starts listening and serves until g_server.stop() is called.
fn void server_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    EchoServerP* proto = echoserverp_new("+OK Echo server ready");

    Server*? server = loop.create_server(proto, "127.0.0.1", 9000
    );
    if (catch err = server) {
        io::printfn("[server] failed to start: %s", err);
        return;
    }

    g_server = server;
    g_proto = proto;
    
    io::printfn("[server-coro] listening on port 9000");

    // Blocks the coroutine here until server.stop() is called externally.
    io::printfn("[server-coro] serve_forever");
    server.serve_forever();

    // Cleanup after the loop exits serve_forever.

    server.free();
    proto.free();
    io::printfn("[server-coro] shut down");
}

// Client coroutine: connects, sends one message, waits for the echo, then
// stops the server and signals the main coroutine to exit.
fn void client_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Yield a few ticks so the server coroutine reaches serve_forever first.
    asyncio::sleep_zero();
    asyncio::sleep_zero();

    Future* on_con_lost = loop.create_future();
    EchoClientP* proto = echoclientp_new("Hello, asyncio!", on_con_lost);

    Transport* tr = loop.create_connection(proto, "127.0.0.1", 9000);

    // Wait until connection_lost fires (i.e. the round-trip is complete).
    on_con_lost.await();

    proto.free();

    io::printfn("[client-coro] done");

    tr.close();
    tr.free();
    on_con_lost.free();
    
    g_server.stop();
}

// Main coroutine: spawns server first, then client.
fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    // Spawn server coroutine.
    Task* s = loop.create_task(&server_coro, "server");

    // Yield once so the server task gets a chance to run before we spawn
    // the client, guaranteeing the listen socket is ready.
    asyncio::sleep(0.1);

    // Spawn client coroutine.
    Task* c = loop.create_task(&client_coro, "client");
    c.await();
    s.await();
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
