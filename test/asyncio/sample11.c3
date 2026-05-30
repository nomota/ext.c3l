// sample11.c3
//
// UDP echo server + client example using ext::asyncio.
// Server datagram endpoint is created first, then client endpoint sends one packet,
// receives one echoed packet, and shuts everything down.

module example;

import std::io;
import ext::asyncio;
import c::string;

// ========================================
//  Shared globals
// ========================================

asyncio::Transport* g_server_trans;


// ========================================
//  Server-side Datagram Protocol
// ========================================

struct UdpEchoServerP (DatagramProtocol) {
    Transport* transport;
    String ready_msg;
}

fn UdpEchoServerP* udpechoserverp_new(String ready_msg)
{
    UdpEchoServerP* p = mem::new(UdpEchoServerP);
    *p = {
        .ready_msg = ready_msg,
    };
    return p;
}

fn void UdpEchoServerP.free(&self)
{
    mem::free(self);
}

fn void UdpEchoServerP.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;
    g_server_trans = transport;
    io::printfn("[udp-server] bound on %s:%d", self.transport.host, self.transport.port);
    io::printfn("[udp-server] %s", self.ready_msg);
}

fn void UdpEchoServerP.datagram_received(&self, char[] data, char[] ip, ushort port) @dynamic
{
    io::printfn("[udp-server] received from %s:%d -> %s", (String)ip, port, (String)data);

    // echo back to sender
    self.transport.sendto(data, ip, (short)port);
    io::printfn("[udp-server] echoed back");
}

fn void UdpEchoServerP.error_received(&self, fault exception) @dynamic
{
    io::printfn("[udp-server] closed/error: %s", exception);
}


// ========================================
//  Client-side Datagram Protocol
// ========================================

struct UdpEchoClientP (DatagramProtocol) {
    Transport* transport;
    Future* on_done;
    String msg;
    String server_ip;
    ushort server_port;
}

fn UdpEchoClientP* udpechoclientp_new(
    String msg,
    String server_ip,
    ushort server_port,
    Future* on_done
)
{
    UdpEchoClientP* p = mem::new(UdpEchoClientP);
    *p = {
        .msg = msg,
        .server_ip = server_ip,
        .server_port = server_port,
        .on_done = on_done,
    };
    return p;
}

fn void UdpEchoClientP.free(&self)
{
    mem::free(self);
}

fn void UdpEchoClientP.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;

    io::printfn(
        "[udp-client] ready, sending to %s:%d -> %s",
        self.server_ip,
        self.server_port,
        self.msg
    );

    self.transport.sendto(self.msg, self.server_ip, (short)self.server_port);
}

fn void UdpEchoClientP.datagram_received(&self, char[] data, char[] ip, ushort port) @dynamic
{
    io::printfn("[udp-client] received from %s:%d -> %s", (String)ip, port, (String)data);

    // one round-trip done
    self.transport.close();
}

fn void UdpEchoClientP.error_received(&self, fault exception) @dynamic
{
    io::printfn("[udp-client] closed/error: %s", exception);
    if (!self.on_done.done()) self.on_done.set_result(null);
}

fn void UdpEchoClientP.connection_lost(&self, fault exception) @dynamic
{
   if (!self.on_done.done()) self.on_done.set_result(null);
}

// ========================================
//  Coroutines
// ========================================

fn void server_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    UdpEchoServerP* proto = udpechoserverp_new("UDP echo server ready");

    Transport* trans = loop.create_datagram_endpoint(proto, "127.0.0.1", 9001);

    while (!trans.closed) {
        asyncio::sleep(0.05);
    }

    trans.free();
    proto.free();

    io::printfn("[udp-server-coro] shut down");
}

fn void client_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    asyncio::sleep(0.1);

    Future* on_done = loop.create_future();
    UdpEchoClientP* proto = udpechoclientp_new(
        "Hello, UDP asyncio!",
        "127.0.0.1",
        9001,
        on_done
    );

    Transport* trans = loop.create_datagram_endpoint(proto, "127.0.0.1", 0);

    on_done.await();

    io::printfn("[udp-client-coro] done");

    if (!trans.closed) trans.close();
    trans.free();
    proto.free();
    on_done.free();

    if (g_server_trans != null && !g_server_trans.closed) {
        g_server_trans.close();
    }
}

fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    Task* s = loop.create_task(&server_coro, "udp-server");
    asyncio::sleep(0.1);

    Task* c = loop.create_task(&client_coro, "udp-client");

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
