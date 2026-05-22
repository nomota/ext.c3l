// handler.c3

// Event-driven callback style protocol handlers
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import ext::mem;
import ext::debug;

faultdef TRANSPORT_CLOSED;
faultdef PROTOCOL_ERROR;
faultdef NO_WRITE_ON_UDP;
faultdef NO_SENDTO_ON_TCP;
faultdef NO_STREAM;
faultdef NO_DATAGRAM;
faultdef PROTOCOL_SERVER_CLOSED;

interface TCPHandler
{
    fn void? connection_made(Stream* stream);
    fn void? data_received(char[] data);
    fn void? connection_lost(fault exception);
}

interface UDPHandler
{
    fn void? connection_made(Datagram* transport);
    fn void? datagram_received(char[] data, String ip, ushort port);
    fn void? error_received(fault exception);
    fn void? connection_lost(fault exception) @optional;
}

struct TaskArg @local
{
    EventLoop* loop;
    TCPHandler tcp_handler;
    UDPHandler udp_handler;
    String host;
    ushort port;
    TCPServer* server;
    Stream* stream;
    Datagram* datagram;
}

fn void? client_task(void* v_arg) @local
{
    if (v_arg == null) return INVALID_STATE~;

    TaskArg* arg = (TaskArg*)v_arg;
    defer localmem.free(arg);
   
    TCPHandler handler = arg.tcp_handler;

    Stream*? stream = stream_connect(arg.host, arg.port);
    if (catch err = stream)
    {
        handler.connection_lost(err)!;
        return err~;
    }
    defer stream.free();

    if (catch err = handler.connection_made(stream))
    {
        handler.connection_lost(err)!;
        return err~;
    }

    fault error = NONE;
    while (!stream.closed)
    {
        char[4096] buf;
        usz? n = stream.read(buf[..]);
        if (catch err = n)
        {
            error = err;
            break;
        }

        if (n == 0) break;

        if (catch err = handler.data_received(buf[0:n]))
        {
            error = err;
            break;
        }
    }

    handler.connection_lost(error)!;
}

fn Task*? tcp_callback_client(TCPHandler handler, String host, ushort port)
{
    TaskArg* arg = localmem.alloc(TaskArg)!;
    defer (catch err) localmem.free(arg);
    *arg = {
        .tcp_handler = handler,
        .host = host,
        .port = port,
    };

    Task* task = aio::spawn_joinable(&client_task, arg)!;

    return task;
}

struct TCPServer @local
{
    Stream* stream; // listening/accepting
    String host;
    ushort port;

    bool closed;

    TCPHandler handler;
    Task* serving_task;
    TaskGroup service_tasks;
}

fn void? service_task(void* v_arg) @local
{
    if (v_arg == null) return INVALID_STATE~;

    TaskArg* arg = (TaskArg*)v_arg;
    defer localmem.free(arg);
    
    TCPServer* server = arg.server;
    Stream* stream = arg.stream;
    TCPHandler handler = arg.tcp_handler;
    if (server == null) return INVALID_STATE~;
    if (stream == null) return INVALID_STATE~;

    defer stream.free();
    
    if (catch err = handler.connection_made(stream))
    {
        handler.connection_lost(err)!;
        return err~;
    }

    fault error = NONE;
    while (!stream.closed && !server.closed)
    {
        char[4096] buf;
        usz? n = stream.read(buf[..]);
        if (catch err = n)
        {
            error = err;
            break;
        }

        if (n == 0) break;

        if (catch err = handler.data_received(buf[0:n]))
        {
            error = err;
            break;
        }
    }

    handler.connection_lost(error)!;
}

fn TCPServer*? tcp_server_new(TCPHandler handler, String host, ushort port) @local
{
    EventLoop* loop = current_loop()!;
    
    TCPServer* server = localmem.alloc(TCPServer)!;
    *server = {
        .stream = null,
        .host = host,
        .port = port,
        .closed = false,
        .handler = handler,
        .serving_task = null,
    };

    server.service_tasks.init(loop);

    return server;
}

fn void? TCPServer.close(&self) @maydiscard
{
    if (self.closed) return;

    self.closed = true;

    Task* task = current_task()!;
    if (self.serving_task != null && self.serving_task != task)
    {
        self.serving_task.cancel();
    }

    if (self.stream != null) self.stream.close();

    self.service_tasks.cancel_all();
}

fn void? TCPServer.wait_closed(&self)
{
    if (catch err = self.service_tasks.join_all())
    {
        if (err == CANCELLED) return;
        if (err == CLOSED) return;
        if (err == IO_ERROR) return;

        return err~;
    }
}

fn void TCPServer.free(&self)
{
    if (!self.closed) self.close();

    self.service_tasks.free();
    if (self.stream != null) self.stream.free();
    localmem.free(self);
}

fn bool TCPServer.is_closed(&self) @inline
{
    return self.closed || self.stream == null || self.stream.closed;
}

fn void? server_task(void* v_arg) @local
{
    if (v_arg == null) return INVALID_STATE~;

    TaskArg* arg = (TaskArg*)v_arg;
    defer localmem.free(arg);
    
    TCPServer*? server = tcp_server_new(arg.tcp_handler, arg.host, arg.port);
    if (catch err = server)
    {
        arg.stream.free();
        return err~;
    }
    defer {
        server.serving_task = null;
        server.close();
        (void)server.wait_closed();
        server.free();
    }

    server.stream = arg.stream;
    server.serving_task = current_task()!;

    while (!server.closed)
    {
        Stream* stream = server.stream.accept()!;
        defer (catch err) stream.free();
        
        TaskArg* arg_ = localmem.alloc(TaskArg)!;
        defer (catch err) localmem.free(arg_);
        
        *arg_ = {
            .server = server,
            .stream = stream,
            .tcp_handler = arg.tcp_handler,
        };

        server.service_tasks.spawn(&service_task, arg_)!;
    }
}

fn Task*? tcp_callback_server(TCPHandler handler, String host, ushort port, int backlog = net::DEFAULT_BACKLOG)
{
    TaskArg* arg = localmem.alloc(TaskArg)!;
    defer (catch err) localmem.free(arg);
    
    Stream* stream = stream_listen(host, port, backlog)!;
    defer (catch err) stream.free();
    
    *arg = {
        .stream = stream,
        .host = host,
        .port = port,
        .tcp_handler = handler,
    };

    Task* task = aio::spawn_joinable(&server_task, arg)!;

    return task;
}

faultdef DATAGRAM_INVALID_ARG;

fn void? datagram_task(void* v_arg) @local
{
    if (v_arg == null) return DATAGRAM_INVALID_ARG~;

    TaskArg* arg = (TaskArg*)v_arg;
    defer localmem.free(arg);
    
    UDPHandler handler = arg.udp_handler;
    Datagram* datagram = arg.datagram;
    if (datagram == null) return DATAGRAM_INVALID_ARG~;
    defer datagram.free();
    
    if (catch err = handler.connection_made(datagram))
    {
        handler.error_received(err)!;
        return err~;
    }

    fault error = NONE;
    while (!datagram.closed)
    {
        char[4096] buf;
        DatagramAddr addr;
        usz? n = datagram.recvfrom(buf[..], &addr);
        if (catch err = n)
        {
            error = err;
            break;
        }

        if (n == 0) continue;

        String ip = (String)addr.ip[0:addr.ip_len];

        if (catch err = handler.datagram_received(buf[0:n], ip, addr.port))
        {
            error = err;
            break;
        }
    }

    if (error != NONE)
    {
        handler.error_received(error)!;
    }

    if (&handler.connection_lost)
    {
        handler.connection_lost(error)!;
    }
}

fn Task*? udp_callback_server(UDPHandler handler, String host, ushort port)
{
    Datagram* datagram = datagram_bind(host, port)!;
    defer (catch err) datagram.free();
    
    TaskArg* arg = localmem.alloc(TaskArg)!;
    defer (catch err) localmem.free(arg);
    
    *arg = {
        .datagram = datagram,
        .udp_handler = handler,
    };

    Task* task = aio::spawn_joinable(&datagram_task, arg)!;

    return task;
}

// eof