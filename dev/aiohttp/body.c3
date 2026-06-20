// body.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;


// 
// Content-Type helpers
// 

fn String content_type_base(String value)
{
    String v = trim_spaces(value);

    for (sz i = 0; i < v.len; i++)
    {
        if (v[i] == ';')
        {
            return trim_spaces(v[0:i]);
        }
    }

    return v;
}

fn bool Request.content_type_is(&self, String expected)
{
    String? ct = self.header("Content-Type");
    if (catch err = ct) return false;

    return str_iequals(content_type_base(ct), expected);
}

fn bool Context.content_type_is(&self, String expected)
{
    if (self.req == null) return false;
    return self.req.content_type_is(expected);
}


// 
// Request body type checks
// 

fn bool Request.is_json(&self)
{
    String? ct = self.header("Content-Type");
    if (catch err = ct) return false;

    String base = content_type_base(ct);

    if (str_iequals(base, "application/json")) return true;

    // Accept vendor JSON types:
    //   application/problem+json
    //   application/vnd.api+json
    if (base.len > "+json".len)
    {
        String suffix = base[base.len - "+json".len:"+json".len];
        if (str_iequals(suffix, "+json")) return true;
    }

    return false;
}

fn bool Request.is_text(&self)
{
    String? ct = self.header("Content-Type");
    if (catch err = ct) return false;

    String base = content_type_base(ct);

    if (str_iequals(base, "text/plain")) return true;

    if (base.len >= "text/".len) 
    {
        if (str_iequals(base[0:"text/".len], "text/")) return true;
    }

    return false;
}

fn bool Request.is_html(&self)
{
    return self.content_type_is("text/html");
}

fn bool Request.is_octet_stream(&self)
{
    return self.content_type_is("application/octet-stream");
}


// 
// Context body type checks
// 

fn bool Context.req_is_json(&self)
{
    if (self.req == null) return false;
    return self.req.is_json();
}

fn bool Context.req_is_text(&self)
{
    if (self.req == null) return false;
    return self.req.is_text();
}

fn bool Context.req_is_html(&self)
{
    if (self.req == null) return false;
    return self.req.is_html();
}

fn bool Context.req_is_octet_stream(&self)
{
    if (self.req == null) return false;
    return self.req.is_octet_stream();
}


// 
// Request body readers
// 

fn char[] Request.bytes(&self)
{
    return self.body;
}

fn String Request.text(&self)
{
    return (String)self.body;
}

// JSON is not parsed yet.
// This returns raw JSON text body.
fn String Request.json_text(&self)
{
    return (String)self.body;
}


// 
// Request copy helpers
// 

faultdef EMPTY_BODY;

// Returns allocated copy.
// Caller must free with localmem.free().
fn char[]? Request.bytes_copy(&self)
{
    if (self.body.len == 0) return EMPTY_BODY~;
    
    char* p = localmem.malloc(self.body.len)!;
    p[0:self.body.len] = self.body[0:self.body.len];

    return p[0:self.body.len];
}

// Returns allocated copy.
// Caller must free with localmem.free().
fn String? Request.text_copy(&self)
{
    if (self.body.len == 0) return EMPTY_BODY~;
    
    char* p = localmem.malloc(self.body.len + 1)!;
    p[0:self.body.len] = self.body[0:self.body.len];
    p[self.body.len] = 0;

    return (String)p[0:self.body.len];
}


// 
// Context body readers
// 

fn char[] Context.req_bytes(&self)
{
    if (self.req == null) return {};
    return self.req.bytes();
}

fn String Context.req_text(&self)
{
    if (self.req == null) return "";
    return self.req.text();
}

fn String Context.req_json_text(&self)
{
    if (self.req == null) return "";
    return self.req.json_text();
}


// 
// Context body copy helpers
// 

fn char[]? Context.req_bytes_copy(&self)
{
    if (self.req == null) return EMPTY_BODY~;
    return self.req.bytes_copy()!;
}

fn String? Context.req_text_copy(&self)
{
    if (self.req == null) return EMPTY_BODY~;
    return self.req.text_copy()!;
}


// 
// Guard helpers
// 

fn bool Context.require_json(&self)
{
    return self.req_is_json();
}

fn bool Context.require_text(&self)
{
    return self.req_is_text();
}


// 
// Debug
// 

fn void request_body_dump(Request* req)
{
    if (req == null) return;
    
    io::printfn("body length: %d", req.body.len);

    if (req.body.len > 0)
    {
        io::printfn("%s", (String)req.body);
    }
}

// eof