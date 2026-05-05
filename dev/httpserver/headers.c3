// header.c3

module ext::httpserver;

import std::io;
import std::collections::list;
import ext::mem;
import ext::debug;

tlocal LocalAllocator localmem = {};

fn void init() @init
{
    if (localmem == (LocalAllocator){}) {
        localmem = tmem;
    }
}

// Name comparison is case-insensitive,
// but the original casing is preserved when serialized.
struct KeyVal @private {
    String name;
    String value;
}

// Headers intentionally stores headers as an array.
//
// Do not replace this with HashMap{String, String}.
// Multiple headers with the same name must be allowed:
//   Set-Cookie: a=1
//   Set-Cookie: b=2
struct KeyVals @private {
    List{KeyVal} items;
}

alias Param = KeyVal;
alias Header = KeyVal;

alias Params = KeyVals;
alias Headers = KeyVals;
alias Query = KeyVals;
alias Cookies = KeyVals;

// 
// Internal helpers
// 

fn bool ascii_eq_ignore_case(char a, char b) @inline
{
    if (a >= 'A' && a <= 'Z') a = a + 32;
    if (b >= 'A' && b <= 'Z') b = b + 32;
    return a == b;
}

fn bool str_iequals(String a, String b)
{
    if (a.len != b.len) return false;

    for (usz i = 0; i < a.len; i++) {
        if (!ascii_eq_ignore_case(a[i], b[i])) return false;
    }

    return true;
}

fn bool is_valid_name(String name)
{
    if (name.len == 0) return false;

    for (usz i = 0; i < name.len; i++) {
        char c = name[i];

        // RFC token-ish validation.
        // Disallow CTL, space, colon.
        if (c <= 32 || c == 127 || c == ':') return false;

        switch (c) {
            case '(':
            case ')':
            case '<':
            case '>':
            case '@':
            case ',':
            case ';':
            case '\\':
            case '"':
            case '/':
            case '[':
            case ']':
            case '?':
            case '=':
            case '{':
            case '}':
                return false;
            default:
        }
    }

    return true;
}

fn String str_clone(String s) @inline
{
    return s.copy(localmem);
}

fn void str_free(String s) @inline
{
    localmem.free(s);
}

fn void KeyVal.free(&self)
{
    if (self.name.ptr != null && self.name.len > 0) str_free(self.name);
    if (self.value.ptr != null && self.value.len > 0) str_free(self.value);

    self.name = "";
    self.value = "";
}


// 
// Public API
// 

fn void KeyVals.init(&self)
{
    self.items.init(localmem);
}

fn void KeyVals.free(&self)
{
    for (usz i = 0; i < self.len(); i++) {
        self.items[i].free();
    }

    self.items.free();
}

fn void KeyVals.clear(&self)
{
    for (usz i = 0; i < self.len(); i++) {
        self.items[i].free();
    }
    self.items.free();
}

fn usz KeyVals.size(&self) @inline
{
    return self.items.len();
}

fn usz KeyVals.len(&self) @inline
{
    return self.items.len();
}

fn bool KeyVals.empty(&self) @inline
{
    return self.items.len() == 0;
}

fn bool KeyVals.has(&self, String name)
{
    for (usz i = 0; i < self.len(); i++) {
        if (str_iequals(self.items[i].name, name)) {
            return true;
        }
    }

    return false;
}

faultdef NOT_FOUND;

// Returns the first matching header value.
//
// This mirrors common framework behavior.
// For repeated headers such as Set-Cookie, use values().
fn String? KeyVals.get(&self, String name)
{
    for (usz i = 0; i < self.len(); i++) {
        if (str_iequals(self.items[i].name, name)) {
            return self.items[i].value;
        }
    }

    return NOT_FOUND~;
}

// Returns the index of the first matching header.
fn usz? KeyVals.find(&self, String name)
{
    for (usz i = 0; i < self.len(); i++) {
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
fn void KeyVals.add(&self, String name, String value)
{
    if (!is_valid_name(name)) return;

    self.items.push({
        .name = str_clone(name),
        .value = str_clone(value),
    });
}

// Sets a header.
//
// Existing headers with the same name are removed,
// then one new header is appended.
fn void KeyVals.set(&self, String name, String value)
{
    if (!is_valid_name(name)) return;

    self.delete(name);
    self.add(name, value);
}

// Deletes all headers with the given name.
fn bool KeyVals.delete(&self, String name)
{
    bool removed = false;
    usz i = 0;
    
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

// Appends serialized headers into a caller-owned buffer.
//
// Returns number of bytes written.
// If buffer is too small, returns 0.
fn usz KeyVals.write_to(&self, char[] out)
{
    usz pos = 0;

    for (usz i = 0; i < self.len(); i++) {
        Header* h = &self.items[i];

        usz need = h.name.len + 2 + h.value.len + 2;
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
fn usz KeyVals.serialized_len(&self)
{
    usz n = 0;

    for (usz i = 0; i < self.len(); i++) {
        Header* h = &self.items[i];
        n += h.name.len + 2 + h.value.len + 2;
    }

    return n;
}

// Allocates and returns serialized header block.
//
// Format:
//   Name: value\r\n
//   Name2: value2\r\n
//
// Does not append the final blank line.
// Response writer should append another "\r\n".
fn String Headers.serialize(&self)
{
    usz n = self.serialized_len();

    if (n == 0) return "";

    char* p = localmem.malloc(n + 1);
    char[] out = p[0:n];

    usz written = self.write_to(out);
    p[written] = 0;

    return (String)out;
}

// 
// Convenience helpers
// 

fn void Headers.content_type(&self, String value)
{
    self.set("Content-Type", value);
}

fn void Headers.content_length(&self, usz value)
{
    String s = string::tformat("%d", value);
    self.set("Content-Length", s);
}

fn void Headers.server(&self, String value)
{
    self.set("Server", value);
}

fn void Headers.connection(&self, String value)
{
    self.set("Connection", value);
}

fn void Headers.set_cookie(&self, String value)
{
    self.add("Set-Cookie", value);
}

// 
// Debug
// 

fn void Headers.dump(&self)
{
    for (usz i = 0; i < self.len(); i++) {
        io::printfn("%s: %s", self.items[i].name, self.items[i].value);
    }
}