// header.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import std::collections::list;
import ext::mem;
import ext::debug;

faultdef INVALID_HEADER_VALUE;

LocalAllocator localmem = null;

fn void init() @init
{
    if (localmem == null) localmem = tmem;
}

// Name comparison is case-insensitive,
// but the original casing is preserved when serialized.
struct KeyVal @private
{
    String name;
    String value;
}

// Headers intentionally stores headers as an array.
//
// Do not replace this with HashMap{String, String}.
// Multiple headers with the same name must be allowed:
//   Set-Cookie: a=1
//   Set-Cookie: b=2
struct KeyVals @private
{
    List{KeyVal} items;
}

alias Param = KeyVal;
alias Header = KeyVal;
alias Auth = KeyVal;

alias Params = KeyVals;
alias Headers = KeyVals;
alias Query = KeyVals;
alias Cookies = KeyVals;


fn void KeyVal.free(&self)
{
    if (self.name.ptr != null && self.name.len > 0) str_free(self.name);
    if (self.value.ptr != null && self.value.len > 0) str_free(self.value);

    self.name = "";
    self.value = "";
}


// Public API

fn void KeyVals.init(&self)
{
    self.items.init(localmem);
}

fn void KeyVals.clear(&self)
{
    foreach (item: self.items) {
        item.free();
    }

    self.items.clear();
}

fn void KeyVals.free(&self)
{
    foreach (item: self.items) {
        item.free();
    }

    self.items.free();
}

fn sz KeyVals.size(&self) @inline
{
    return self.items.len();
}

fn sz KeyVals.len(&self) @inline
{
    return self.items.len();
}

fn bool KeyVals.empty(&self) @inline
{
    return self.items.len() == 0;
}

fn bool KeyVals.has(&self, String name)
{
    foreach (item: self.items) {
        if (str_iequals(item.name, name)) {
            return true;
        }
    }

    return false;
}

// Returns the name at index.
//
// The returned string is owned by KeyVals.
fn String? KeyVals.name_at(&self, sz index)
{
    if (index < 0 || index >= self.len()) return NOT_FOUND~;

    return self.items[index].name;
}

// Returns the value at index.
//
// The returned string is owned by KeyVals.
fn String? KeyVals.value_at(&self, sz index)
{
    if (index < 0 || index >= self.len()) return NOT_FOUND~;

    return self.items[index].value;
}

faultdef NOT_FOUND;

// Returns the first matching header value.
//
// This mirrors common framework behavior.
// For repeated headers such as Set-Cookie, use values().
fn String? KeyVals.get(&self, String name)
{
    for (sz i = 0; i < self.len(); i++) {
        if (str_iequals(self.items[i].name, name)) {
            return self.items[i].value;
        }
    }

    return NOT_FOUND~;
}

// Returns the index of the first matching header.
fn sz? KeyVals.find(&self, String name)
{
    for (sz i = 0; i < self.len(); i++) {
        if (str_iequals(self.items[i].name, name)) {
            return i;
        }
    }

    return NOT_FOUND~;
}

// Adds a new header without removing existing headers.
//
// Use this for:
//   Set-Cookie
//   Warning
//   WWW-Authenticate

faultdef INVALID_HEADER_NAME;

fn void? KeyVals.add(&self, String name, String value) @maydiscard
{
    if (!is_valid_name(name)) return INVALID_HEADER_NAME~;
    if (!is_valid_value(value)) return INVALID_HEADER_VALUE~;

    self.items.push({
        .name = str_clone(name),
        .value = str_clone(value),
    });
}

// Sets a header.
//
// Existing headers with the same name are removed,
// then one new header is appended.
fn void? KeyVals.set(&self, String name, String value) @maydiscard
{
    if (!is_valid_name(name)) return INVALID_HEADER_NAME~;
    if (!is_valid_value(value)) return INVALID_HEADER_VALUE~;

    self.delete(name);
    self.add(name, value)!;
}

// Deletes all headers with the given name.
fn bool KeyVals.delete(&self, String name)
{
    bool removed = false;
    sz i = 0;
    
    while (i < self.len()) {
        if (str_iequals(self.items[i].name, name)) {
            self.items[i].free();
            self.items.remove_at(i);
            removed = true;
            continue;
        }

        i++;
    }

    return removed;
}

fn void KeyVals.remove(&self, String name)
{
    (void)self.delete(name);
}


// Appends serialized headers into a caller-owned buffer.
//
// Returns number of bytes written.
// If buffer is too small, returns 0.
fn sz KeyVals.write_to(&self, char[] out)
{
    sz pos = 0;

    for (sz i = 0; i < self.len(); i++) {
        Header* h = &self.items[i];

        sz need = h.name.len + 2 + h.value.len + 2;
        if (pos + need > out.len) return 0;

        out[pos:h.name.len] = h.name[0:h.name.len];
        pos += h.name.len;

        out[pos++] = ':';
        out[pos++] = ' ';

        out[pos:h.value.len] = h.value[0:h.value.len];
        pos += h.value.len;

        out[pos++] = '\r';
        out[pos++] = '\n';
    }

    return pos;
}

// Calculates serialized byte length, excluding final empty CRLF.
fn sz KeyVals.serialized_len(&self)
{
    sz n = 0;

    for (sz i = 0; i < self.len(); i++) {
        Header* h = &self.items[i];
        n += h.name.len + 2 + h.value.len + 2;
    }

    return n;
}

faultdef HEADER_SERIALIZE_ERROR;

// Allocates and returns serialized header block.
//
// Format:
//   Name: value\r\n
//   Name2: value2\r\n
//
// Does not append the final blank line.
// Response writer should append another "\r\n".
fn String? Headers.serialize(&self)
{
    sz n = self.serialized_len();

    char* p = localmem.malloc(n + 1)!;
    char[] out = p[0:n];

    sz written = self.write_to(out);
    if (written != n) {
        localmem.free(p);
        return HEADER_SERIALIZE_ERROR~;
    }
    p[written] = 0;

    return (String)out;
}


// Convenience helpers

fn void? Headers.content_type(&self, String value) @maydiscard
{
    self.set("Content-Type", value)!;
}

fn void? Headers.content_length(&self, sz value) @maydiscard
{
    if (value < 0) return INVALID_HEADER_VALUE~;

    String s = string::format(localmem, "%d", value);
    defer localmem.free(s);
    
    self.set("Content-Length", s)!;
}

fn void? Headers.server(&self, String value) @maydiscard
{
    self.set("Server", value)!;
}

fn void? Headers.connection(&self, String value) @maydiscard
{
    self.set("Connection", value)!;
}

fn void? Headers.set_cookie(&self, String value) @maydiscard
{
    self.add("Set-Cookie", value)!;
}


// Debug

fn void Headers.dump(&self)
{
    for (sz i = 0; i < self.len(); i++) {
        io::printfn("%s: %s", self.items[i].name, self.items[i].value);
    }
}

// eof