// static.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import std::io;
import ext::mem;
import ext::debug;
import ext::aio;
import ext::aio::path;


// Faults

faultdef STATIC_NOT_CONFIGURED;
faultdef STATIC_FORBIDDEN;
faultdef STATIC_NOT_FOUND;
faultdef STATIC_READ_ERROR;


// Static config

tlocal String static_root = "";
tlocal bool static_root_ready = false;

fn void static_set_root(String root)
{
    if (static_root_ready && static_root.len > 0)
    {
        str_free(static_root);
    }

    static_root = str_clone(root);
    static_root_ready = true;
}

fn void static_clear_root()
{
    if (static_root_ready && static_root.len > 0)
    {
        str_free(static_root);
    }

    static_root = "";
    static_root_ready = false;
}


// Helpers

fn bool static_contains_dotdot(String s)
{
    for (sz i = 0; i + 1 < s.len; i++)
    {
        if (s[i] == '.' && s[i + 1] == '.')
        {
            return true;
        }
    }

    return false;
}

fn bool static_has_backslash(String s)
{
    for (sz i = 0; i < s.len; i++)
    {
        if (s[i] == '\\') return true;
    }

    return false;
}

fn String? static_join_path(String root, String rel)
{
    bool root_slash = root.len > 0 && root[root.len - 1] == '/';
    bool rel_slash = rel.len > 0 && rel[0] == '/';

    sz extra = 0;
    sz skip = 0;

    if (!root_slash && !rel_slash)
    {
        extra = 1;
    }

    if (root_slash && rel_slash)
    {
        skip = 1;
    }

    sz n = root.len + rel.len + extra - skip;
    char* p = localmem.malloc(n + 1)!;

    sz pos = 0;

    p[pos:root.len] = root[0:root.len];
    pos += root.len;

    if (extra == 1) p[pos++] = '/';

    if (rel.len > skip)
    {
        p[pos:rel.len - skip] = rel[skip:rel.len - skip];
        pos += rel.len - skip;
    }

    p[pos] = 0;
    return (String)p[0:pos];
}

fn String static_content_type(String filename)
{
    if (filename.ends_with(".html")) return "text/html; charset=utf-8";
    if (filename.ends_with(".htm")) return "text/html; charset=utf-8";
    if (filename.ends_with(".css")) return "text/css; charset=utf-8";
    if (filename.ends_with(".js")) return "application/javascript; charset=utf-8";
    if (filename.ends_with(".mjs")) return "application/javascript; charset=utf-8";
    if (filename.ends_with(".json")) return "application/json; charset=utf-8";
    if (filename.ends_with(".txt")) return "text/plain; charset=utf-8";
    if (filename.ends_with(".svg")) return "image/svg+xml";
    if (filename.ends_with(".png")) return "image/png";
    if (filename.ends_with(".jpg")) return "image/jpeg";
    if (filename.ends_with(".jpeg")) return "image/jpeg";
    if (filename.ends_with(".gif")) return "image/gif";
    if (filename.ends_with(".webp")) return "image/webp";
    if (filename.ends_with(".ico")) return "image/x-icon";
    if (filename.ends_with(".wasm")) return "application/wasm";
    if (filename.ends_with(".pdf")) return "application/pdf";

    return "application/octet-stream";
}


// File read

fn char[]? static_read_file(String full_path)
{
    bool exists = path::exists(full_path);
    if (!exists) return STATIC_NOT_FOUND~;

    bool is_file = path::isfile(full_path);
    if (!is_file) return STATIC_NOT_FOUND~;

    sz size = path::getsize(full_path)!;
    if (size < 0) return STATIC_READ_ERROR~;

    if (size == 0) return {};

    aio::File* f = aio::file_open(full_path, "r")!;
    defer f.close();

    char* p = localmem.malloc(size)!;
    char[] buf = p[0:size];

    sz n = f.read(buf)!;

    if (n < size)
    {
        localmem.free(buf);
        return STATIC_READ_ERROR~;
    }

    return buf;
}


// Static handler

fn Response*? static_handler(Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (!static_root_ready)
    {
        c.status(500)!;
        return c.text("static root not configured")!;
    }

    String? rel_opt = c.splat();

    if (catch err = rel_opt)
    {
        c.status(404)!;
        return c.text("static file not found")!;
    }

    String rel = rel_opt;

    if (rel.len == 0)
    {
        rel = "index.html";
    }

    if (static_contains_dotdot(rel) || static_has_backslash(rel))
    {
        c.status(403)!;
        return c.text("forbidden")!;
    }

    String full_path = static_join_path(static_root, rel)!;
    defer localmem.free(full_path);

    char[]? data = static_read_file(full_path);

    if (catch err = data)
    {
        if (err == STATIC_NOT_FOUND)
        {
            c.status(404)!;
            return c.text("static file not found")!;
        }

        c.status(500)!;
        return c.text("static read error")!;
    }

    defer
    {
        if (data.ptr != null && data.len > 0)
        {
            localmem.free(data);
        }
    }

    c.content_type(static_content_type(full_path))!;
    return c.body_response(data)!;
}


// Application helper

fn void? Application.static_files(&self, String url_prefix, String root) @maydiscard
{
    static_set_root(root);

    String pattern;

    if (url_prefix == "/")
    {
        pattern = "/*";
    }
    else
    {
        pattern = join_paths(url_prefix, "/*")!;
    }

    defer
    {
        if (pattern.ptr != null && pattern != "/*")
        {
            localmem.free(pattern);
        }
    }

    self.get(pattern, &static_handler)!;
}

// eof