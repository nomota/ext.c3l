// server.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import std::collections::linkedlist;

import ext::mem;
import ext::debug;
import ext::aio::io;
import ext::aio::net;

faultdef SERVER_CLOSED;

alias ClientHandler @local = fn void?(Stream*);

struct Server
{
    Fd fd;
    bool closed;
    ClientHandler handler;
    Task* serving_task;
    LinkedList{Stream*} clients;
    TaskGroup client_tasks;
}

struct TaskArg @local
{
    Server* server;
    ClientHandler handler;
    Stream* stream;
}

fn void? client_task(void* arg) @local
{
    TaskArg* a = (TaskArg*)arg;
    @assert(a != null);
    
    ClientHandler handler = a.handler;
    Stream* stream = a.stream;
    Server* server = a.server;
    
    localmem.free(a);

    @assert(stream != null);
    @assert(server != null);
    @assert(handler != null);

    server.add_client(stream);

    defer
    {
        server.remove_client(stream);
        stream.free();
    }

    handler(stream)!;
}

fn Server*? start_server(ClientHandler handler, String host, ushort port, int backlog = net::DEFAULT_BACKLOG)
{
    if (handler == null) return INVALID_STATE~;

    Fd fd = net::tcp_listen_host(host, port, backlog)!;

    EventLoop* loop = current_loop()!;
    
    Server* server = localmem.alloc(Server)!;
    *server = {
        .fd = fd,
        .closed = false,
        .handler = handler,
        .serving_task = null,
    };

    server.clients.init(localmem);
    server.client_tasks.init(loop);
    
    return server;
}

fn void Server.abort_clients(&self)
{
    self.close_clients();
    self.client_tasks.cancel_all();
}

fn void Server.close_clients(&self)
{
    foreach (stream: self.clients.array_view())
    {
        if (stream == null) continue;

        stream.close();
    }
}

fn void Server.close(&self)
{
    if (self.closed) return;

    self.closed = true;

    if (self.serving_task != null)
    {
        self.serving_task.cancel();
    }

    if (!io::fd_invalid(self.fd))
    {
        net::socket_close(self.fd);
        self.fd = io::fd_null();
    }

    self.close_clients();
}

fn void Server.stop(&self)
{
    self.close();
}

// The caller must call wait_closed() before free() after close().
fn void? Server.wait_closed(&self) @maydiscard
{
    if (catch err = self.client_tasks.join_all())
    {
        if (err == CANCELLED) return;
        if (err == CLOSED) return;
        if (err == IO_ERROR) return;
        if (err == POLL_ERROR) return;

        return err~;
    }
}

fn void Server.free(&self)
{
    if (!self.closed) self.close();

    @assert(self.clients.len() == 0, "Server.free(): wait_closed() was not called before free");

    self.clients.free();
    self.client_tasks.free();

    localmem.free(self);
}

fn bool Server.is_closed(&self) @inline
{
    return self.closed || io::fd_invalid(self.fd);
}

fn void Server.add_client(&self, Stream* stream)
{
    if (stream == null) return;

    self.clients.push(stream);
}

fn void Server.remove_client(&self, Stream* stream)
{
    if (stream == null) return;

    self.clients.remove_first_match(stream);
}

fn void? Server.serve_forever(&self) @maydiscard
{
    if (self.is_closed()) return SERVER_CLOSED~;

    self.serving_task = current_task()!;
    defer self.serving_task = null;

    while (!self.closed)
    {
        Fd client_fd = net::tcp_accept(self.fd)!;

        Stream* stream = stream_new(client_fd)!;
        defer catch stream.free();
        
        TaskArg* arg = localmem.alloc(TaskArg)!;
        defer catch localmem.free(arg);
        *arg = {
            .server = self,
            .handler = self.handler,
            .stream = stream,
        };
        
        self.client_tasks.spawn(&client_task, arg)!;
    }
}

// eof