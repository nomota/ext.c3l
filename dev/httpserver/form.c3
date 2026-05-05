// form.c3

module ext::httpserver;

import std::io;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef UNSUPPORTED_FORM_TYPE;
faultdef INVALID_FORM_BODY;


// 
// Content-Type helpers
// 

fn bool content_type_starts_with(String value, String prefix)
{
    if (value.len < prefix.len) return false;

    return str_iequals(value[0:prefix.len], prefix);
}

fn bool Request.is_form_urlencoded(&self)
{
    String? ct = self.header("Content-Type");

    if (catch err = ct) {
        return false;
    }

    // Accept:
    //   application/x-www-form-urlencoded
    //   application/x-www-form-urlencoded; charset=utf-8
    return content_type_starts_with(
        trim_spaces(ct),
        "application/x-www-form-urlencoded"
    );
}

fn bool Context.is_form_urlencoded(&self)
{
    if (self.req == null) return false;
    return self.req.is_form_urlencoded();
}


// 
// Request form parser
// 

// Parses application/x-www-form-urlencoded request body.
//
// Caller owns returned Query and must call form.free().
fn Query? Request.form_params(&self)
{
    if (!self.is_form_urlencoded()) {
        return UNSUPPORTED_FORM_TYPE~;
    }

    Query form;
    form.init();

    if (self.body.len == 0) {
        return form;
    }

    String body = (String)self.body;

    if (catch err = query_parse(&form, body)) {
        form.free();
        return err~;
    }

    return form;
}

// Convenience accessor.
//
// Returns an allocated copy.
// Caller must free the returned String with localmem.free().
fn String? Request.form_copy(&self, String name)
{
    Query form = self.form_params()!;
    defer form.free();

    String? value = form.get(name);
    if (catch err = value) {
        return err~;
    }

    return value.copy(localmem);
}


// 
// Context form cache
// 

// To enable Context-level form caching, add these fields to Context:
//
//   Query form_cache;
//   bool form_cache_ready;
//
// Then initialize/free them in context.c3.

fn void? Context.ensure_form_cache(&self)
{
    if (self.form_cache_ready) return;

    if (self.req == null) {
        return CONTEXT_NOT_READY~;
    }

    if (!self.req.is_form_urlencoded()) {
        return UNSUPPORTED_FORM_TYPE~;
    }

    if (self.req.body.len == 0) {
        self.form_cache_ready = true;
        return;
    }

    String body = (String)self.req.body;
    query_parse(&self.form_cache, body)!;

    self.form_cache_ready = true;
}


fn Query* Context.forms(&self)
{
    if (catch self.ensure_form_cache()) {
        return null;
    }

    return &self.form_cache;
}

fn String? Context.form(&self, String name)
{
    self.ensure_form_cache()!;
    return self.form_cache.get(name);
}

fn bool Context.has_form(&self, String name)
{
    if (catch self.ensure_form_cache()) {
        return false;
    }

    return self.form_cache.has(name);
}


// 
// Debug
// 

fn void form_dump(Query* form)
{
    form.dump();
}