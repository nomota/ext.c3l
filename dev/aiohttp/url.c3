// url.c3

module ext::httpserver;

import std::io;
import ext::mem;
import ext::debug;


// 
// Faults
// 

faultdef INVALID_URL_ENCODING;


// 
// Internal helpers
// 

fn bool is_hex(char c) @inline
{
    if (c >= '0' && c <= '9') return true;
    if (c >= 'a' && c <= 'f') return true;
    if (c >= 'A' && c <= 'F') return true;
    return false;
}

fn char hex_value(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

fn sz find_char_from(String s, char needle, sz start)
{
    for (sz i = start; i < s.len; i++) {
        if (s[i] == needle) return (sz)i;
    }

    return -1;
}

// 
// Percent decoding
// 

// Decodes URL percent-encoded string.
//
// If plus_as_space is true:
//   '+' becomes ' '
//
// For query string decoding, use plus_as_space = true.
// For path decoding, use plus_as_space = false.
fn String? url_decode_ex(String s, bool plus_as_space)
{
    if (s.len == 0) return "";

    char* out = localmem.malloc(s.len + 1);
    defer (catch err) {
        localmem.free(out);
    }
    sz pos = 0;

    for (sz i = 0; i < s.len; i++) {
        char c = s[i];

        if (c == '%' ) {
            if (i + 2 >= s.len) {
                return INVALID_URL_ENCODING~;
            }

            char hi = s[i + 1];
            char lo = s[i + 2];

            if (!is_hex(hi) || !is_hex(lo)) {
                return INVALID_URL_ENCODING~;
            }

            out[pos++] = (hex_value(hi) << 4) | hex_value(lo);
            i += 2;
            continue;
        }

        if (plus_as_space && c == '+') {
            out[pos++] = ' ';
            continue;
        }

        out[pos++] = c;
    }

    out[pos] = 0;
    return (String)out[0:pos];
}

// General URL decode.
// Does not convert '+' to space.
fn String? url_decode(String s)
{
    return url_decode_ex(s, false);
}

// Query component decode.
// Converts '+' to space.
fn String? query_decode(String s)
{
    return url_decode_ex(s, true);
}


// 
// Query parser
// 

// Parses one key=value pair.
//
// Supported:
//   a=1
//   a=
//   flag
//
// For "flag", value becomes "".
fn void? query_parse_pair(Query* out, String pair)
{
    if (pair.len == 0) return;

    sz eq = find_char_from(pair, '=', 0);

    String raw_name;
    String raw_value;

    if (eq < 0) {
        raw_name = pair;
        raw_value = "";
    } else {
        sz p = (sz)eq;
        raw_name = pair[0:p];
        raw_value = pair[p + 1:pair.len - p - 1];
    }

    if (raw_name.len == 0) {
        return;
    }

    String? name_dec = query_decode(raw_name);
    if (catch err = name_dec) {
        return err~;
    }

    String? value_dec = query_decode(raw_value);
    if (catch err = value_dec) {
        localmem.free(name_dec);
        return err~;
    }

    out.add(name_dec, value_dec);

    localmem.free(name_dec);
    localmem.free(value_dec);
}

// Parses query string into Query.
//
// Example:
//   a=1&b=hello+world&flag
//
// Result:
//   a    => 1
//   b    => hello world
//   flag => ""
fn void? query_parse(Query* out, String query_string)
{
    if (query_string.len == 0) return;

    sz start = 0;

    while (start <= query_string.len) {
        sz amp = find_char_from(query_string, '&', start);

        String pair;

        if (amp < 0) {
            pair = query_string[start:query_string.len - start];
            query_parse_pair(out, pair)!;
            break;
        }

        sz end = (sz)amp;
        pair = query_string[start:end - start];
        query_parse_pair(out, pair)!;

        start = end + 1;
    }
}


// 
// Request query helpers
// 

// Allocates and parses request query parameters.
// Caller must call query.free().
fn Query? Request.query_params(&self)
{
    Query q;
    q.init();

    if (catch err = query_parse(&q, self.query_string)) {
        q.free();
        return err~;
    }

    return q;
}

// Convenience accessor.
//
// This parses query_string on every call.
// For repeated query access, prefer:
//
//   Query q = req.query_params()!;
//   defer q.free();
//   String? v = q.get("name");
fn String? Request.query_copy(&self, String name)
{
    Query q = self.query_params()!;
    defer q.free();

    return q.get(name).copy(localmem);
}


// 
// Path helpers
// 

fn String? Request.decoded_path(&self)
{
    return url_decode(self.path);
}


// 
// Debug
// 

fn void query_dump(Query* q)
{
    q.dump();
}