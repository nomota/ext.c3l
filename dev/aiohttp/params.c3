// params.c3

module ext::httpserver;

import std::io;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef INVALID_PARAM_NAME;


// 
// Param name helpers
// 

fn bool is_alpha(char c) @inline
{
    if (c >= 'a' && c <= 'z') return true;
    if (c >= 'A' && c <= 'Z') return true;
    return false;
}

fn bool is_alnum(char c) @inline
{
    if (is_alpha(c)) return true;
    if (c >= '0' && c <= '9') return true;
    return false;
}

// Route param names are intentionally simpler than HTTP header names.
//
// Allowed:
//   :id
//   :user_id
//   :file-name
//
// Not allowed:
//   :
//   :/x
//   :user.id
fn bool param_name_valid(String name)
{
    if (name.len == 0) return false;

    char first = name[0];
    if (!is_alpha(first) && first != '_') {
        return false;
    }

    for (sz i = 1; i < name.len; i++) {
        char c = name[i];

        if (is_alnum(c)) continue;
        if (c == '_') continue;
        if (c == '-') continue;

        return false;
    }

    return true;
}


// 
// Params lifecycle
// 

fn void params_init(Params* params)
{
    params.init();
}

fn void params_free(Params* params)
{
    params.free();
}

fn void params_clear(Params* params)
{
    params.clear();
}

fn Params? params_new()
{
    Params params;
    params.init();
    return params;
}


// 
// Params API
// 

fn void? Params.put(&self, String name, String value)
{
    if (!param_name_valid(name)) {
        return INVALID_PARAM_NAME~;
    }

    // Route params should be unique.
    // If the same name appears again, overwrite it.
    self.set(name, value);
}

fn void? Params.add_param(&self, String name, String value)
{
    if (!param_name_valid(name)) {
        return INVALID_PARAM_NAME~;
    }

    self.add(name, value);
}

fn String? Params.get_param(&self, String name)
{
    return self.get(name);
}

fn bool Params.has_param(&self, String name)
{
    return self.has(name);
}

fn bool Params.delete_param(&self, String name)
{
    return self.delete(name);
}


// 
// Copy helpers
// 

fn void? Params.copy_from(&self, Params* other)
{
    for (sz i = 0; i < other.len(); i++) {
        Param* p = &other.items[i];
        self.put(p.name, p.value)!;
    }
}

fn Params? params_clone(Params* src)
{
    Params dst;
    dst.init();

    if (catch err = dst.copy_from(src)) {
        dst.free();
        return err~;
    }

    return dst;
}


// 
// Splat helper
// 

// Stores wildcard capture.
//
// Example route:
//   /static/*
//
// Path:
//   /static/css/app.css
//
// Param:
//   "*" => "css/app.css"

const String STAR = "__wildcard_splat_key";

fn void? Params.set_splat(&self, String value)
{
    self.set(STAR, value);
}

fn String? Params.splat(&self)
{
    return self.get(STAR);
}


// 
// Decoded param helpers
// 

// Decodes a route param value and stores the decoded value.
//
// Caller passes raw path segment.
// This function percent-decodes it with url_decode().
fn void? Params.put_decoded(&self, String name, String raw_value)
{
    if (!param_name_valid(name)) {
        return INVALID_PARAM_NAME~;
    }

    String? decoded = url_decode(raw_value);
    if (catch err = decoded) {
        return err~;
    }
    defer localmem.free(decoded);

    self.set(name, decoded);
}

fn void? Params.set_splat_decoded(&self, String raw_value)
{
    String? decoded = url_decode(raw_value);
    if (catch err = decoded) {
        return err~;
    }
    defer localmem.free(decoded);

    self.set(STAR, decoded);
}


// 
// Request params placeholder
// 

// Request itself does not own route params.
// Router/Context will own Params.
//
// This is intentionally not implemented here:
//   fn String? Request.param(...)
//
// It should be implemented on Context later:
//
//   fn String? Context.param(&self, String name)
//   {
//       return self.params.get(name);
//   }


// 
// Debug
// 

fn void Params.dump_params(&self)
{
    for (sz i = 0; i < self.len(); i++) {
        io::printfn("%s = %s", self.items[i].name, self.items[i].value);
    }
}