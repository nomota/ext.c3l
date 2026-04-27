// protocol.c3 

module ext::asyncio;

import ext::debug;
import ext::mem;

//import example;
/* python api functions 
transport,protocol = loop.create_connection(protocol, host, port)
dtrans,dproto = loop.create_datagram_endpoint(datagram_proto, host, port)
server = loop.create_server(protocol, host, port)
on_con_lost = loop.create_future()
asyncio.Protocol(msg, on_con_lost); // interface
asyncio.DatagramProtocol(msg, on_con_lost); // interface
proto.connection_made(transport)
transport.write(msg.encode())
proto.data_received(data)
dproto.datagram_received(data, addr)
dtrans.sendto(data,addr)
dproto.error_received(exc)
data.decode()
proto.connection_lost(exc)
on_con_lost.set_result(true)
on_con_lost.await()
transport.close()
*/

struct Context {
    Transport* transport;
    union {
        Protocol protocol;
        DatagramProtocol dprotocol;
    }
}

fn void _open_stream()
{
    EventLoop* loop = get_running_loop();
    Task* task = loop.current;
    
    Context* ctx = (Context*)task.arg;
    
    Transport* trans = ctx.transport;
    Protocol proto = ctx.protocol;

    localmem.free(task.arg);
    task.arg = null;

    Stream*? stream = open_connection(trans.host, trans.port);
    if (catch err = stream) {
        proto.connection_lost(err);
        return;
    }
    
    trans.stream = stream;

    proto.connection_made(trans);

    fault error = stream.error;
    
    while (! stream.at_eof()) {
        if (trans.closed) break;
        
        char[4096] buf;
        usz? n = stream.read_any(&buf);
        if (catch err = n) {
            error = err;
            break;
        }
        if (n == 0) break;
        proto.data_received(buf[0:n]);
    }
    
    
    if (!trans.closed) {
        trans.close(); // stream closed here
    }

    proto.connection_lost(error);
}

fn Transport* EventLoop.create_connection(&self, Protocol proto, String host, ushort port)
{
    Transport* t = transport_new();
    t.type = 't';
    t.proto = proto;
    t.host = host;
    t.port = port;
    
    Context* ctx = localmem.alloc(Context);
    ctx.transport = t;
    ctx.protocol = proto;

    self.create_task(&_open_stream, "_open_stream", 128_000, true, ctx);
    
    return t; // must be free'd at caller
}

tlocal Context ctx;
fn void _client_handler(Stream *stream)
{
    Transport* trans = ctx.transport;
    Protocol proto = ctx.protocol;

    trans.stream = stream;
    
    proto.connection_made(trans);

    fault error = stream.error;

    while (! stream.at_eof()) {
        if (trans.closed) break;
        
        char[4096] buf;
        usz? n = stream.read_any(&buf);
        if (catch err = n) {
            error = err;
            break;
        }
        if (n == 0) break;
        proto.data_received(buf[0:n]);
    }
    
    if (! trans.closed) {
        trans.close(); // stream close here
    }
    
    proto.connection_lost(error);
}

fn Server*? EventLoop.create_server(&self, Protocol proto, String host, ushort port)
{
    Transport* t = transport_new();
    t.type = 't';
    t.proto = proto;
    t.host = host;
    t.port = port;

    ctx.transport = t;
    ctx.protocol = proto;

    Server* server = start_server(&_client_handler, host, port)!;
    
    server.transport = t;
    // on server finish after serve_forever(), t is free'd through server.free()
    
    return server; // must be free'd at caller
}

fn void _drive_datagram()
{
    EventLoop* loop = get_running_loop();
    Task* task = loop.current;
    
    Context* ctx = (Context*)task.arg;
    
    Transport* trans = ctx.transport;
    DatagramProtocol dproto = ctx.dprotocol;

    localmem.free(task.arg);
    task.arg = null;

    Datagram*? datagram = bind_endpoint(trans.host, trans.port);
    if (catch err = datagram) {
        dproto.error_received(err);
        return;
    }
   
    trans.datagram = datagram;
    
    dproto.connection_made(trans);

    while (! trans.closed) {
        if (trans.closed) break;
        
        char[4096] buf;
        char[64] ip_str;
        usz ip_len;
        ushort port;

        usz n = datagram.recvfrom(&buf, &ip_str, &ip_len, &port);
        if (n == 0) break;

        dproto.datagram_received(buf[0:n], ip_str[0:ip_len], port);
        
        if (trans.closed) break;
    }

    fault error = trans.closed ? NONE: datagram.error;;
    
    if (error != NONE) {
        dproto.error_received(error);
    }

    if (! trans.closed) {
        trans.close(); // datagram closed here
    }
    
    if (&dproto.connection_lost) {
        dproto.connection_lost(error);
    }
}

fn Transport* EventLoop.create_datagram_endpoint(&self, DatagramProtocol proto, String host, ushort port)
{
    Transport* t = transport_new();
    t.type = 'u';
    t.dproto = proto;
    t.host = host;
    t.port = port;

    Context* ctx = localmem.alloc(Context);
    ctx.transport = t;
    ctx.dprotocol = proto;
    
    self.create_task(&_drive_datagram, "_drive_datagram", 80_000, true, ctx);
    
    return t; // must be free'd at caller
}

interface DatagramProtocol {
    fn void connection_made(Transport* transport);
    fn void datagram_received(char[] buf, char[] ip, ushort port);
    fn void error_received(fault exception);
    fn void connection_lost(fault exception) @optional;
    // fn void pause_writing() @optional;
    // fn void resume_writing() @optional;
}

interface Protocol {
    fn void connection_made(Transport* transport);
    fn void data_received(char[] data);
    fn void connection_lost(fault exception);
    // fn void pause_writing() @optional;
    // fn void resume_writing() @optional;
}

struct Transport {
    char type; // 'u'dp datagram, 't'cp
    Protocol proto;
    DatagramProtocol dproto;
    String host;
    ushort port;
    Stream* stream;
    Datagram* datagram;
    bool closed;
}

fn Transport* transport_new() @private
{
    Transport* t = localmem.alloc(Transport);
    *t = {};
    return t;
}

fn void Transport.free(&self)
{
    if (!self.closed) self.close();
    localmem.free(self);
}

faultdef NO_WRITE_ON_UDP;

fn usz? Transport.write(&self, char[] data)
{
    if (self.type == 't') {
        return self.stream.write(data)!;
    }
    return NO_WRITE_ON_UDP~;
}

fn void Transport.sendto(&self, char[] data, char[] ip, short port)
{
    if (self.type == 'u') {
        self.datagram.sendto(data, ip, port);
    }
}

fn void Transport.close(&self)
{
    if (self.closed) return;
    self.closed = true;
    if (self.type == 't') {
        self.stream.close();
    }
    if (self.type == 'u') {
        self.datagram.close();
    }
}


/* User code sample 1 - loop.create_connection()

struct MyProto (Protocol) {
    char[] msg;
    Transport* transport;
    Future* on_con_lost;
}

fn MyProto* myproto_new(char[] msg, Future* on_con_lost)
{
    MyProto* p = localmem.alloc(MyProto);
    self.msg = msg;
    self.on_con_lost = on_con_lost;
    return p;
}

fn void MyProto.free(&self)
{
    self.transport.free();
    self.on_con_lost.free();
    localmem.free(&self);
}

fn void MyProto.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;
    // do something
}

fn void MyProto.data_received(&self, char[] data)
{
    // do something
}

fn void MyProto.connection_lost(&self, Error error)
{
    // do something
    self.on_con_lost.set_result(null);
}

fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();

    Future* on_con_lost = loop.create_future();
    MyProto* proto = myproto_new("hello", on_con_lost);
    
    Transport* tr = loop.create_connection(proto, "127.0.0.1", 8888);
    on_con_lost.await();
    
    proto.free();
}

fn void main()
{
    asyncio::run(&main_coro);
}
*/

/* User code sample 2 - loop.create_server()

struct MyProto (Protocol) {
    Transport* transport;
}

fn MyProto* myproto_new()
{
    MyProto* p = localmem.alloc(MyProto);
    return p;
}

fn void MyProto.free(&self)
{
    localmem.free(&self);
}

fn void MyProto.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;
    // do something
}

fn void MyProto.data_received(&self, char[] data)
{
    // do something
}

fn void MyProto.connection_lost(&self, Error error)
{
    // do something

}

fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();
    
    MyProto* proto = myproto_new();
    
    Server* server = loop.create_server(proto, "127.0.0.1", 8888);

    server.serve_forever();

    server.free();
    proto.free();
}

fn void main()
{
    asyncio::run(&main_coro);
}
*/

/* User code sample 3 - loop.create_datagram_endpoint()

struct MyProto (DatagramProtocol) {
    Transport* transport;
    char[] msg;
    Future* on_con_lost;
}

fn MyProto* myproto_new(char[] msg, Future* on_con_lost)
{
    MyProto* p = localmem.alloc(MyProto);
    p.msg = msg;
    p.on_con_lost = on_con_lost;
    return p;
}

fn void MyProto.free(&self)
{
    self.transport.free();
    localmem.free(&self);
}

fn void MyProto.connection_made(&self, Transport* transport) @dynamic
{
    self.transport = transport;
    // do something
}

fn void MyProto.datagram_received(&self, char[] data, char[] ip, short port) @dynamic
{
    // do something
}

fn void MyProto.error_received(&self, fault error) @dynamic
{
    // do something
    self.on_con_lost.set_result(null);
}

fn void main_coro()
{
    EventLoop* loop = asyncio::get_running_loop();
    
    Future* on_con_lost = loop.create_future();
    MyProto* proto = myproto_new("Hello", on_con_lost);
    
    Transport* trans = loop.create_datagram_endpoint(proto, "127.0.0.1", 8888);
    on_con_lost.await();

    proto.free();
}

fn void main()
{
    asyncio::run(&main_coro);
}
*/

