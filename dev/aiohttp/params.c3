// params.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import std::io;
import ext::mem;
import ext::debug;
import c::errno;

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
    if (!is_alpha(first) && first != '_')
    {
        return false;
    }

    for (sz i = 1; i < name.len; i++)
    {
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
    if (params == null) return;

    params.init();
}

fn void params_free(Params* params)
{
    if (params == null) return;

    params.free();
}

fn void params_clear(Params* params)
{
    if (params == null) return;
    
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

fn void? Params.put(&self, String name, String value) @maydiscard
{
    if (!param_name_valid(name))
    {
        return INVALID_PARAM_NAME~;
    }

    // Route params should be unique.
    // If the same name appears again, overwrite it.
    self.set(name, value)!;
}

fn void? Params.add_param(&self, String name, String value) @maydiscard
{
    if (!param_name_valid(name))
    {
        return INVALID_PARAM_NAME~;
    }

    self.add(name, value)!;
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

fn void? Params.copy_from(&self, Params* other) @maydiscard
{
    if (other == null) return errno::E_INVALID_ARG~;
    for (sz i = 0; i < other.len(); i++)
    {
        Param* p = &other.items[i];
        self.put(p.name, p.value)!;
    }
}

fn Params? params_clone(Params* src)
{
    if (src == null) return errno::E_INVALID_ARG~;
    
    Params dst;
    dst.init();

    if (catch err = dst.copy_from(src))
    {
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

const String STAR = "__splat__";

fn void? Params.set_splat(&self, String value) @maydiscard
{
    // "*" is an internal wildcard key, not a normal route param name.
    self.delete(STAR);
    self.add(STAR, value)!;
}

fn String? Params.splat(&self)
{
    return self.get(STAR);
}

fn void? Params.set_splat_decoded(&self, String raw_value) @maydiscard
{
    String? decoded = url_decode(raw_value);
    if (catch err = decoded) return err~;

    defer localmem.free(decoded);

    // Do not call put_decoded(STAR, ...).
    // "*" is intentionally not valid as a normal param name.
    self.delete(STAR);
    self.add(STAR, decoded)!;
}

// 
// Decoded param helpers
// 

// Decodes a route param value and stores the decoded value.
//
// Caller passes raw path segment.
// This function percent-decodes it with url_decode().
fn void? Params.put_decoded(&self, String name, String raw_value) @maydiscard
{
    if (!param_name_valid(name))
    {
        return INVALID_PARAM_NAME~;
    }

    String? decoded = url_decode(raw_value);
    if (catch err = decoded) return err~;

    defer localmem.free(decoded);

    self.set(name, decoded)!;
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
    for (sz i = 0; i < self.len(); i++)
    {
        io::printfn("%s = %s", self.items[i].name, self.items[i].value);
    }
}

// eof