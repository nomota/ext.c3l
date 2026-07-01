// form.c3

// application/x-www-form-urlencoded parsing for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import ext::mem;
import ext::debug;

// Faults

faultdef UNSUPPORTED_FORM_TYPE;
faultdef INVALID_FORM_ENCODING;

// Content-Type helpers

fn bool content_type_matches(String value, String media_type)
{
    value = value.trim();

    if (value.len < media_type.len) return false;
    if (!str_iequals(value[0:media_type.len], media_type)) return false;

    if (value.len == media_type.len) return true;

    sz pos = media_type.len;

    while (pos < value.len && is_space(value[pos]))
    {
        pos++;
    }

    return pos < value.len && value[pos] == ';';
}

fn bool Request.is_form_urlencoded(&self)
{
    String? ct = self.header("Content-Type");
    if (catch err = ct) return false;

    return content_type_matches(
        ct,
        "application/x-www-form-urlencoded"
    );
}

fn bool Context.is_form_urlencoded(&self)
{
    if (self.req == null) return false;
    return self.req.is_form_urlencoded();
}

// Form decode helpers


fn String? decode_component(String s) @local
{
    DString out;
    out.init(localmem, s.len);
    defer catch out.free();

    char[1] one;

    for (sz i = 0; i < s.len; i++)
    {
        char c = s[i];

        if (c == '+')
        {
            one[0] = ' ';
            out.append(one[..]);
            continue;
        }

        if (c != '%')
        {
            one[0] = c;
            out.append(one[..]);
            continue;
        }

        if (i + 2 >= s.len)
        {
            return INVALID_FORM_ENCODING~;
        }

        char hi = s[i + 1];
        char lo = s[i + 2];

        if (!is_hex(hi) || !is_hex(lo))
        {
            return INVALID_FORM_ENCODING~;
        }

        one[0] = (hex_value(hi) << 4) | hex_value(lo);
        out.append(one[..]);

        i += 2;
    }

    return out.copy_str(localmem);
}

fn void? parse_pair(Query* form, String pair) @local
{
    if (form == null) return INVALID_FORM_ENCODING~;

    sz eq = -1;

    for (sz i = 0; i < pair.len; i++)
    {
        if (pair[i] == '=')
        {
            eq = i;
            break;
        }
    }

    String raw_name;
    String raw_value;

    if (eq < 0)
    {
        raw_name = pair;
        raw_value = "";
    }
    else
    {
        raw_name = pair[0:eq];
        raw_value = pair[eq + 1..];
    }

    String name = decode_component(raw_name)!;
    defer localmem.free(name);

    String value = decode_component(raw_value)!;
    defer localmem.free(value);

    form.add(name, value)!;
}

fn void? parse_urlencoded(Query* form, String body)
{
    if (form == null) return INVALID_FORM_ENCODING~;
    if (body.len == 0) return;

    sz start = 0;

    while (start <= body.len)
    {
        sz amp = -1;

        for (sz i = start; i < body.len; i++)
        {
            if (body[i] == '&')
            {
                amp = i;
                break;
            }
        }

        String pair;

        if (amp < 0)
        {
            pair = body[start:body.len - start];

            if (pair.len > 0)
            {
                parse_pair(form, pair)!;
            }

            return;
        }

        pair = body[start:amp - start];

        if (pair.len > 0)
        {
            parse_pair(form, pair)!;
        }

        start = amp + 1;
    }
}

// Request form parser

// Parses application/x-www-form-urlencoded request body.
//
// Caller owns returned Query and must call form.free().
fn Query? Request.form_params(&self)
{
    if (!self.is_form_urlencoded())
    {
        return UNSUPPORTED_FORM_TYPE~;
    }

    Query form;
    form.init();

    if (self.body.len == 0) return form;

    String body = (String)self.body;

    if (catch err = parse_urlencoded(&form, body))
    {
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
    if (catch err = value) return err~;

    return value.copy(localmem);
}

// Context form cache

fn void? Context.ensure_form_cache(&self)
{
    if (self.form_cache_ready) return;

    if (self.req == null) return CONTEXT_NOT_READY~;

    if (!self.req.is_form_urlencoded())
    {
        return UNSUPPORTED_FORM_TYPE~;
    }

    self.form_cache.clear();

    if (self.req.body.len == 0)
    {
        self.form_cache_ready = true;
        return;
    }

    String body = (String)self.req.body;

    if (catch err = parse_urlencoded(&self.form_cache, body))
    {
        self.form_cache.clear();
        return err~;
    }

    self.form_cache_ready = true;
}

fn Query* Context.forms(&self)
{
    if (catch self.ensure_form_cache())
    {
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
    if (catch self.ensure_form_cache())
    {
        return false;
    }

    return self.form_cache.has(name);
}

// Debug

fn void form_dump(Query* form)
{
    if (form == null) return;
    form.dump();
}

// eof