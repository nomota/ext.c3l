// middleware.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import std::io;
import std::collections::list;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef INVALID_MIDDLEWARE_PATH;


// 
// Middleware types
// 

alias Next = fn Response*?(Context* c);
alias Middleware = fn Response*?(Context* c, Next next);


// 
// Middleware item / stack
// 

struct MiddlewareItem
{
    String path;
    Middleware middleware;
    bool has_path;
}

struct MiddlewareStack
{
    List{MiddlewareItem} items;
}

struct MiddlewareChain
{
    MiddlewareStack* stack;
    Handler handler;
    sz index;
}


// 
// Internal helpers
// 

fn bool middleware_path_valid(String path)
{
    if (path.len == 0) return false;
    if (path[0] != '/') return false;

    if (path.len > 1 && path[path.len - 1] == '/')
    {
        return false;
    }

    return true;
}

// Hono-style prefix match.
//
// use("/api", mw) applies to:
//   /api
//   /api/users
//
// but not:
//   /apix
fn bool path_matches_prefix(String prefix, String path)
{
    if (prefix == "/") return true;

    if (path.len < prefix.len) return false;

    if (path[0:prefix.len] != prefix[0:prefix.len])
    {
        return false;
    }

    if (path.len == prefix.len)
    {
        return true;
    }

    return path[prefix.len] == '/';
}


// 
// MiddlewareItem lifecycle
// 

fn void MiddlewareItem.free(&self)
{
    if (self.has_path) str_free(self.path);

    self.path = "";
    self.middleware = null;
    self.has_path = false;
}


// 
// MiddlewareStack lifecycle
// 

fn void MiddlewareStack.init(&self)
{
    self.items.init(localmem);
}

fn void MiddlewareStack.free(&self)
{
    for (sz i = 0; i < self.items.len(); i++)
    {
        self.items[i].free();
    }

    self.items.free();
}

fn void MiddlewareStack.clear(&self)
{
    for (sz i = 0; i < self.items.len(); i++)
    {
        self.items[i].free();
    }

    self.items.clear();
}

fn MiddlewareStack*? middleware_stack_new()
{
    MiddlewareStack* s = localmem.alloc(MiddlewareStack)!;
    s.init();
    return s;
}

fn void middleware_stack_free(MiddlewareStack* s)
{
    if (s == null) return;

    s.free();
    localmem.free(s);
}


// 
// Add middleware
// 

// Global middleware.
fn void? MiddlewareStack.use(&self, Middleware middleware) @maydiscard
{
    self.items.push((MiddlewareItem){
        .path = "",
        .middleware = middleware,
        .has_path = false,
    });
}

// Path-scoped middleware.
fn void? MiddlewareStack.use_path(&self, String path, Middleware middleware) @maydiscard
{
    if (!middleware_path_valid(path)) 
    {
        return INVALID_MIDDLEWARE_PATH~;
    }

    self.items.push((MiddlewareItem){
        .path = str_clone(path),
        .middleware = middleware,
        .has_path = true,
    });
}

fn sz MiddlewareStack.len(&self) @inline
{
    return self.items.len();
}

fn bool MiddlewareStack.empty(&self) @inline
{
    return self.items.len() == 0;
}


// 
// Matching
// 

fn bool MiddlewareItem.matches(&self, String path)
{
    if (!self.has_path) return true;
    return path_matches_prefix(self.path, path);
}


// 
// Chain execution
// 

fn void MiddlewareChain.init(&self, MiddlewareStack* stack, Handler handler)
{
    self.stack = stack;
    self.handler = handler;
    self.index = 0;
}

fn Response*? MiddlewareChain.run(&self, Context* c)
{
    self.index = 0;
    return self.next(c)!;
}

fn Response*? MiddlewareChain.next(&self, Context* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (self.stack == null) 
    {
        return context_call(c, self.handler)!;
    }

    while (self.index < self.stack.items.len()) 
    {
        sz i = self.index;
        self.index++;

        MiddlewareItem* item = &self.stack.items[i];

        if (!item.matches(c.path())) 
        {
            continue;
        }

        if (item.middleware == null) 
        {
            continue;
        }

        return item.middleware(c, &middleware_next)!;
    }

    return context_call(c, self.handler)!;
}


// 
// Current chain trampoline
// 

// C-style function pointer signatures cannot carry closure state.
// Therefore we keep the active chain in thread-local storage.
//
// This is acceptable for the current asyncio/fiber-style single logical
// request execution model, but nested middleware execution must restore
// the previous chain.
tlocal MiddlewareChain* current_middleware_chain = null;

fn Response*? middleware_next(Context* c)
{
    if (current_middleware_chain == null)
    {
        return CONTEXT_NOT_READY~;
    }

    return current_middleware_chain.next(c)!;
}

fn Response*? middleware_run(MiddlewareStack* stack, Context* c, Handler handler)
{
    if (c == null) return CONTEXT_NOT_READY~;

    MiddlewareChain chain;
    chain.init(stack, handler);

    MiddlewareChain* prev = current_middleware_chain;
    current_middleware_chain = &chain;

    defer
    {
        current_middleware_chain = prev;
    }

    return chain.run(c)!;
}


// 
// Convenience middlewares
// 

fn Response*? middleware_logger(Context* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    Response* res = next(c)!;

    String remote_ip = "";
    if (c.req != null)
    {
        remote_ip = c.req.remote_ip;
    }

    io::printf("LOG %s %s %s ", remote_ip, c.method(), c.path());

    if (res != null) 
    {
        io::printfn("-> %d", res.status);
    } 
    else 
    {
        io::printfn("(response=null)");
    }

    return res;
}

fn Response*? middleware_powered_by(Context* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    c.header("X-Powered-By", "ext::aiohttp")!;
    return next(c)!;
}


// 
// Debug
// 

fn void MiddlewareStack.dump(&self)
{
    for (sz i = 0; i < self.items.len(); i++) 
    {
        MiddlewareItem* item = &self.items[i];

        if (item.has_path) 
        {
            io::printfn("use %s", item.path);
        } 
        else 
        {
            io::printfn("use *");
        }
    }
}

// eof