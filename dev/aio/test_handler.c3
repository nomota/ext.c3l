// test_handler.c3

import ext::aio;
import ext::debug;
import ext::mem;

const String HOST = "127.0.0.1";
const ushort TCP_PORT = 39081;
const ushort UDP_PORT = 39082;

const String TCP_MSG = "hello tcp callback";
const String UDP_MSG = "hello udp callback";

bool g_tcp_server_made = false;
bool g_tcp_server_received = false;
bool g_tcp_server_lost = false;

bool g_tcp_client_made = false;
bool g_tcp_client_received = false;
bool g_tcp_client_lost = false;

bool g_udp_server_made = false;
bool g_udp_server_received = false;
bool g_udp_server_lost = false;

char[256] g_tcp_client_buf;
usz g_tcp_client_len = 0;

char[256] g_udp_client_buf;
usz g_udp_client_len = 0;

struct EchoTCPServerHandler (TCPHandler)
{
    Stream* stream;
}

fn void? EchoTCPServerHandler.connection_made(&self, Stream* stream) @dynamic
{
    warn("[tcp-server] connection_made");

    self.stream = stream;
    g_tcp_server_made = true;
}

fn void? EchoTCPServerHandler.data_received(&self, char[] data) @dynamic
{
    warn("[tcp-server] data_received: %s", (String)data);

    g_tcp_server_received = true;

    usz n = self.stream.write(data)!;
    @assert(n == data.len);

    self.stream.close();
}

fn void? EchoTCPServerHandler.connection_lost(&self, fault exception) @dynamic
{
    warn("[tcp-server] connection_lost: %s", exception);

    g_tcp_server_lost = true;
}

struct EchoTCPClientHandler (TCPHandler)
{
    Stream* stream;
    bool sent;
}

fn void? EchoTCPClientHandler.connection_made(&self, Stream* stream) @dynamic
{
    warn("[tcp-client] connection_made");

    self.stream = stream;
    self.sent = true;
    g_tcp_client_made = true;

    usz n = stream.write(TCP_MSG[..])!;
    @assert(n == TCP_MSG.len);
}

fn void? EchoTCPClientHandler.data_received(&self, char[] data) @dynamic
{
    warn("[tcp-client] data_received: %s", (String)data);

    g_tcp_client_received = true;

    g_tcp_client_buf[0:data.len] = data[..];
    g_tcp_client_len = data.len;

    self.stream.close();
}

fn void? EchoTCPClientHandler.connection_lost(&self, fault exception) @dynamic
{
    warn("[tcp-client] connection_lost: %s", exception);

    g_tcp_client_lost = true;
}

struct EchoUDPServerHandler (UDPHandler)
{
    Datagram* transport;
}

fn void? EchoUDPServerHandler.connection_made(&self, Datagram* transport) @dynamic
{
    warn("[udp-server] connection_made");

    self.transport = transport;
    g_udp_server_made = true;
}

fn void? EchoUDPServerHandler.datagram_received(&self, char[] data, String ip, ushort port) @dynamic
{
    warn("[udp-server] datagram_received: %s from %s:%d", (String)data, ip, port);

    g_udp_server_received = true;

    usz n = self.transport.sendto(data, ip, port)!;
    @assert(n == data.len);

    self.transport.close();
}

fn void? EchoUDPServerHandler.error_received(&self, fault exception) @dynamic
{
    warn("[udp-server] error_received: %s", exception);
}

fn void? EchoUDPServerHandler.connection_lost(&self, fault exception) @dynamic
{
    warn("[udp-server] connection_lost: %s", exception);

    g_udp_server_lost = true;
}

fn void? test_tcp_callback()
{
    warn("=== tcp_callback_server / tcp_callback_client ===");

    EchoTCPServerHandler server_handler = {};
    EchoTCPClientHandler client_handler = {};

    Task* server_task = aio::tcp_callback_server(&server_handler, HOST, TCP_PORT)!;

    aio::sleep(50)!;

    Task* client_task = aio::tcp_callback_client(&client_handler, HOST, TCP_PORT)!;

    if (catch err = client_task.join())
    {
        if (err != aio::CLOSED && err != aio::CANCELLED) return err~;
    }

    aio::sleep(100)!;
    
    warn("cancel server_task");
    server_task.cancel();

    if (catch err = server_task.join())
    {
        if (err != aio::CLOSED && err != aio::CANCELLED) return err~;
    }

    @assert(g_tcp_server_made);
    @assert(g_tcp_server_received);

    @assert(g_tcp_client_made);
    @assert(g_tcp_client_received);

    String received = (String)g_tcp_client_buf[0:g_tcp_client_len];
    @assert(received == TCP_MSG);

    warn("[tcp] OK");
}

fn void? test_udp_callback()
{
    warn("=== udp_callback_server ===");

    EchoUDPServerHandler server_handler = {};

    Task* server_task = aio::udp_callback_server(&server_handler, HOST, UDP_PORT)!;

    aio::sleep(50)!;

    Datagram* client = aio::datagram_bind(HOST, 0)!;
    defer client.free();

    usz sent = client.sendto(UDP_MSG[..], HOST, UDP_PORT)!;
    @assert(sent == UDP_MSG.len);

    DatagramAddr addr;
    usz n = client.recvfrom(g_udp_client_buf[..], &addr)!;
    g_udp_client_len = n;

    String received = (String)g_udp_client_buf[0:g_udp_client_len];
    @assert(received == UDP_MSG);

    aio::sleep(100)!;

    server_task.cancel();

    if (catch err = server_task.join())
    {
        if (err != aio::CLOSED && err != aio::CANCELLED) return err~;
    }

    @assert(g_udp_server_made);
    @assert(g_udp_server_received);

    warn("[udp] OK");
}

fn void? main_task(void* arg)
{
    warn("=== ext::aio handler tests ===");

    test_tcp_callback()!;
    test_udp_callback()!;

    warn("=== ext::aio handler tests done ===");
    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof