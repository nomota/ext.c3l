// json.c3

module ext::serializer::json;

import std::collections::list;
import std::collections::map;
import std::core::dstring;
import ext::mem;
import ext::debug;
import c::string;

LocalAllocator localmem = null;

alias JsonValue = any; // void* that remembers the type, of which it's pointing to
alias JsonArray = List{JsonValue};
alias JsonObject = HashMap{String, JsonValue};
alias JsonNull = void*;
alias JsonBool = bool;
alias JsonNumber = char[];

faultdef NONE,
    JSON_UNEXPECTED_EOF,
    JSON_INVALID_TOKEN,
    JSON_INVALID_NUMBER,
    JSON_INVALID_STRING,
    JSON_EXPECTED_COLON,
    JSON_EXPECTED_COMMA_OR_END,
    JSON_EXPECTED_VALUE,
    JSON_TRAILING_GARBAGE,
    JSON_TYPE_ERROR,
    JSON_KEY_NOT_FOUND,
    JSON_INDEX_OUT_OF_RANGE,
    JSON_NESTING_TOO_DEEP,
    JSON_INCOMPLETE;

struct JsonDecoder {
    char[] input;
    char* begin;
    char* end;
    usz pos;
    bool allow_trailing_commas;
    bool allow_comments;
}

fn JsonDecoder*? decoder_new(Allocator allocx, String text, bool allow_comma, bool allow_comment)
{
    localmem = allocx;
    JsonDecoder* d = localmem.alloc(JsonDecoder)!;
    *d = {
        .input = text,
        .begin = &text[0],
        .end = &text[0]+text.len,
        .pos = 0,
        .allow_trailing_commas = allow_comma,
        .allow_comments = allow_comment,
    };
    return d;
}

fn void JsonDecoder.free(&self)
{
    localmem.free(self);
}

fn bool JsonDecoder.has_more(&self) @inline
{
    return self.begin+self.pos < self.end;
}

fn char JsonDecoder.peek(&self) @inline
{
    return *(self.begin+self.pos);
}

fn void JsonDecoder.skip_space(&self)
{
    while (self.begin+self.pos < self.end) {
        char c = self.peek();
        switch (c) {
            case ' ':
            case '\t':
            case '\r':
            case '\n':
                self.pos++;
            case '/':
                if (!self.allow_comments) return;
                // need at least one more character to determine comment type
                if (self.begin+self.pos+1 >= self.end) return;
                char next = *(self.begin+self.pos+1);
                if (next == '/') {
                    // line comment: skip until '\n' or EOF
                    self.pos += 2;
                    while (self.begin+self.pos < self.end && self.peek() != '\n') {
                        self.pos++;
                    }
                } else if (next == '*') {
                    // block comment: skip until '*/' or EOF
                    // unterminated block comment is treated as EOF;
                    // the next parse_value() call will return JSON_UNEXPECTED_EOF.
                    self.pos += 2;
                    while (self.begin+self.pos+1 < self.end) {
                        if (self.peek() == '*' && *(self.begin+self.pos+1) == '/') {
                            self.pos += 2;
                            break;
                        }
                        self.pos++;
                    }
                } else {
                    // lone '/' is not a comment; let the parser handle it
                    return;
                }
            default:
                return;
        }
    }
}

fn JsonValue? decode(Allocator allocx, String text, bool allow_comma=true, bool allow_comment=true)
{
    JsonDecoder* d = decoder_new(allocx, text, allow_comma, allow_comment)!;
    defer d.free();

    JsonValue obj = d.parse()!; // any

    d.skip_space();
    if (d.begin+d.pos != d.end) return JSON_TRAILING_GARBAGE~;
    
    return obj;
}

const CHUNK = 16;

macro char* find_in_chunk1(char* buf, char c) @private
{
    char[<CHUNK>] vector_c = c;
    bool[<CHUNK>] matches = (*(char[<CHUNK>]*)buf).comp_eq(vector_c);
    uint mask = matches.mask_to_int();
    return mask != 0 ? buf + mask.ctz() : null;
}

/*
macro char* find_in_8_char(char* buf, char c) @private 
{
    // no boundary check, because we know that buf is longer than 8 bytes
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    return null;
}
*/

fn char*? find_char(char* buf, char* end, char c) @inline @private
{
    while (end - buf >= CHUNK) {
        char* out = find_in_chunk1(buf, c);
        if (out == null) {
            buf += CHUNK;
            continue;
        }
        return out;
    }
    while (buf <= end) {
        if (c == *buf) return buf; buf++;
    }
    
    return JSON_INCOMPLETE~;
}

fn JsonValue? JsonDecoder.parse(&self)
{
    return self.parse_value()!;
}

fn void JsonValue.free(&self)
{
    switch (self.type) {
        case JsonObject:
            JsonObject* m = (JsonObject*) *self;
            m.@each(; key, value) {
                key.free(localmem);
                value.free();
            };
            localmem.free(m);
        case JsonArray:
            JsonArray* l = (JsonArray*) *self;
            foreach (e: l) {
                e.free();
            }
            localmem.free(l);
        case String:
            String* s = (String*) *self;
            (*s).free(localmem);
            localmem.free(s);
        case JsonNumber:
            JsonNumber* n = (JsonNumber*) *self;
            localmem.free(n);
        default:
            // do nothing for true/false/null
            (void)self;
    }
}

fn JsonValue? JsonDecoder.parse_string(&self)
{
    usz p0 = self.pos;
    @assert(*(self.begin+p0) == '"', "string error");
    char* p = self.begin+p0+1;

    char* q = p;
    do {
        q = find_char(p, self.end, '"')!;

        // skip \" while accept \\" as string end
        usz n_bs = 0; // num backspaces
        char* r = q-1;
        while (r >= p && *r == '\\') { n_bs++; r--; }
        if (n_bs % 2 == 0) break;
        p = q+1;
    } while (p < self.end);
    
    String* s = localmem.alloc(String)!;

    *s = unescape_str((String) p[0:q-p]);

    q++;
    self.pos = (q - self.begin);

    any a = any_make(s, String.typeid);
    
    return a;
}

const JsonBool TRUE = true;
const JsonBool FALSE = false;
const JsonNull NULL = null;

macro warn_linepos(char* begin, usz pos)
{
    int line = 1;
    int col = 1;
    for (usz i = 0; i < pos; i++) {
        if (*(begin+i) == '\n')  {
            line++;
            col = 1;
            continue;
        }
        col++;
    }
    warn("json line:%d, column:%d", line, col);
}

fn JsonValue? JsonDecoder.parse_true(&self)
{
    if (string::strncmp(self.begin+self.pos, "true", 4) != 0) {
        warn_linepos(self.begin, self.pos);
        return JSON_INVALID_TOKEN~;
    }
    self.pos += 4;
    return any_make(&TRUE, bool.typeid);
}

fn JsonValue? JsonDecoder.parse_false(&self)
{
    if (string::strncmp(self.begin+self.pos, "false", 5) != 0) {
        warn_linepos(self.begin, self.pos);
        return JSON_INVALID_TOKEN~;
    }
    self.pos += 5;
    return any_make(&FALSE, bool.typeid);
}

fn JsonValue? JsonDecoder.parse_null(&self)
{
    if (string::strncmp(self.begin+self.pos, "null", 4) != 0) {
        warn_linepos(self.begin, self.pos);
        return JSON_INVALID_TOKEN~;
    }
    self.pos += 4;
    return any_make(&NULL, JsonNull.typeid);
}

const bool[256] NUM = {
    [(usz)'0'] = true, [(usz)'1'] = true,
    [(usz)'2'] = true, [(usz)'3'] = true,
    [(usz)'4'] = true, [(usz)'5'] = true,
    [(usz)'6'] = true, [(usz)'7'] = true,
    [(usz)'8'] = true, [(usz)'9'] = true,
    [(usz)'e'] = true, [(usz)'E'] = true,
    [(usz)'+'] = true, [(usz)'-'] = true,
    [(usz)'.'] = true,
};

fn bool isnum(char c) @inline @private
{
    return NUM[(usz)c];
}

fn JsonValue? JsonDecoder.parse_number(&self)
{
    char* p = self.begin+self.pos;
    char* q = p;
    bool e_found = false;
    bool dot_found = false;
    while (q < self.end && isnum(*q)) {
        if (*q == '-' || *q == '+') {
            if (q != p && *(q-1) != 'e' && *(q-1) != 'E') {
                return JSON_INVALID_NUMBER~;
            }
        }
        if (*q == 'e' || *q == 'E') {
            if (e_found) return JSON_INVALID_NUMBER~;
            e_found = true;
        }
        if (*q == '.') {
            if (dot_found || e_found) return JSON_INVALID_NUMBER~;
            dot_found = true;
        }
        q++;
    }
    JsonNumber* num = localmem.alloc(JsonNumber)!;
    *num = p[0:q-p];
    self.pos = q-self.begin;
    any a = any_make(num, JsonNumber.typeid);
    return a;
}

fn JsonValue? JsonDecoder.parse_array(&self)
{
    List{any}* l = localmem.alloc(List{any})!;
    *l = {};
    l.init(localmem);
    defer (catch err) { l.free(); localmem.free(l); }
    
    self.pos++; // skip '['
    while (self.begin+self.pos < self.end) {
        self.skip_space();
        char c = self.peek();
        if (c == ']') { // empty array
            self.pos++;
            break;
        }
        if (c == ',') { // empty array with comma
            self.pos++;
            self.skip_space();
            char c2 = self.peek();
            if (self.allow_trailing_commas && c2 == ']') {
                self.pos++;
                break;
            }
        }
        
        any a = self.parse_value()!;
        l.push(a);

        self.skip_space();
        c = self.peek();
        if (c == ']') {
            self.pos++;
            break;
        }
        if (c == ',') {
            self.pos++;
            self.skip_space();
            char c2 = self.peek();
            if (self.allow_trailing_commas && c2 == ']') {
                self.pos++;
                break;
            }
            continue;
        }
        warn_linepos(self.begin, self.pos);
        return JSON_INVALID_TOKEN~;
    }
    any a = any_make(l, List{any}.typeid);
    return a;
}

fn JsonValue? JsonDecoder.parse_object(&self)
{

    HashMap{String,any}* m = localmem.alloc(HashMap{String,any})!;
    *m = {};
    m.init(localmem);

    defer (catch err) { m.free(); localmem.free(m); }

    self.pos++; // skip '{'
    while (self.begin+self.pos < self.end) {
        self.skip_space();
        char c = self.peek();
        if (c == '}') { // empty map
            self.pos++;
            break;
        }
        if (c == ',') { // empty map with comma
            self.pos++;
            self.skip_space();
            char c2 = self.peek();
            if (self.allow_trailing_commas && c2 == '}') {
                self.pos++;
                break;
            }
        }
        
        if (c != '"') {
            return JSON_INVALID_TOKEN~;
        }
        String* s = (String*) self.parse_string()!;

        self.skip_space();
        char colon = self.peek();

        if (colon != ':') {
            warn_linepos(self.begin, self.pos);
            return JSON_INVALID_TOKEN~;
        }
        self.pos++;
        self.skip_space();

// warn("%d [%s]", self.pos, (String)(self.begin+self.pos)[0:5]);
        any a = self.parse_value()!;
        (*m)[*s] = a;
        localmem.free(s);

       
        self.skip_space();
        c = self.peek();

        if (c == '}') {
            self.pos++;
            break;
        }
        if (c == ',') {
            self.pos++;
            self.skip_space();
            char c2 = self.peek();
            if (self.allow_trailing_commas && c2 == '}') {
                self.pos++;
                break;
            }
            continue;
        }
        warn_linepos(self.begin, self.pos);
        return JSON_INVALID_TOKEN~;
    }

    any a = any_make(m, HashMap{String,any}.typeid);
    return a;
}

fn JsonValue? JsonDecoder.parse_value(&self)
{
    self.skip_space();

    if (!self.has_more()) return JSON_UNEXPECTED_EOF~;

    char c = self.peek();
    switch (c)
    {
        case '{':
            return self.parse_object()!;

        case '[':
            return self.parse_array()!;

        case '"':
            return self.parse_string()!;

        case 't':
            return self.parse_true()!;

        case 'f':
            return self.parse_false()!;

        case 'n':
            return self.parse_null()!;

        case '-':
        case '+':
        case '0'..'9':
            return self.parse_number()!;

        default:
            warn_linepos(self.begin, self.pos);
            return JSON_EXPECTED_VALUE~;
    }
}

fn bool JsonValue.is_null(&self)
{
    return (self.type == JsonNull.typeid);
}

fn bool JsonValue.is_bool(&self)
{
    if (self.type == JsonBool.typeid) {
        return true;
    }
    return false;
}

fn bool JsonValue.is_int(&self)
{
    if (self.type == JsonNumber.typeid) {
        char[]* n = (char[]*) *self;
        bool is_int = true;
        for (usz i = 0; i < n.len; i++) {
            if ((*n)[i] == '.' || (*n)[i] == 'e' || (*n)[i] == 'E')
            {
                is_int = false;
                break;
            }
        }
        return is_int;
    }
    return false;
}

fn bool JsonValue.is_float(&self)
{
    if (self.type == JsonNumber.typeid) {
        return ! self.is_int();
    }
    return false;
}

fn bool JsonValue.is_string(&self)
{
    if (self.type == String.typeid) {
        return true;
    }
    return false;
}

fn bool JsonValue.is_array(&self)
{
    if (self.type == List{JsonValue}.typeid) {
        return true;
    }
    return false;
}

fn bool JsonValue.is_object(&self)
{
    if (self.type == HashMap{String, JsonValue}.typeid) {
        return true;
    }
    return false;
}

fn bool? JsonValue.as_bool(&self)
{
    if (! self.is_bool()) return JSON_TYPE_ERROR~;
    JsonBool* b = (JsonBool*) *self;
    return (b == &TRUE);
}

fn long? JsonValue.as_int(&self)
{
    if (! self.is_int()) return JSON_TYPE_ERROR~;
    JsonNumber* n = (String*) *self; // char[]
    return ((String)(*n)).to_long()!;
}

fn double? JsonValue.as_float(&self)
{
    if (! self.is_float()) return JSON_TYPE_ERROR~;
    JsonNumber* n = (JsonNumber*) *self; // char[]

    return ((String)(*n)).to_double()!;
}

fn String? JsonValue.as_string(&self)
{
    if (! self.is_string()) return JSON_TYPE_ERROR~;
    String* n = (String*) *self;
    return *n;
}

fn JsonArray? JsonValue.as_array(&self)
{
    if (! self.is_array()) return JSON_TYPE_ERROR~;
    JsonArray* n = (JsonArray*) *self;
    return *n;
}

fn JsonObject? JsonValue.as_object(&self)
{
    if (! self.is_object()) return JSON_TYPE_ERROR~;
    JsonObject* n = (JsonObject*) *self;
    return *n;
}

fn bool JsonObject.has(&self, String key)
{
    return self.has_key(key);
}

/*
fn JsonValue? JsonObject.get(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return (*self)[key];
}
*/

fn String? JsonObject.get_string(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return ((*self)[key]).as_string()!;
}

fn long? JsonObject.get_int(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return ((*self)[key]).as_int()!;
}

fn double? JsonObject.get_float(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return ((*self)[key]).as_float()!;
}

fn bool? JsonObject.get_bool(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return ((*self)[key]).as_bool()!;
}

fn JsonArray? JsonObject.get_array(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return ((*self)[key]).as_array()!;
}

fn JsonObject? JsonObject.get_object(&self, String key)
{
    if (!self.has_key(key)) return JSON_KEY_NOT_FOUND~;
    return ((*self)[key]).as_object()!;
}

/*
fn usz JsonArray.len(&self)
{
    return self.len();
}
*/

fn JsonValue? JsonArray.at(&self, usz index)
{
    return (*self)[index];
}

fn String? JsonArray.get_string(&self, usz index)
{
    return (*self)[index].as_string()!;
}

fn long? JsonArray.get_int(&self, usz index)
{
    return (*self)[index].as_int();
}

fn double? JsonArray.get_float(&self, usz index)
{
    return (*self)[index].as_float();
}

fn bool? JsonArray.get_bool(&self, usz index)
{
    return (*self)[index].as_bool();
}

fn JsonArray? JsonArray.get_array(&self, usz index)
{
    return (*self)[index].as_array();
}

fn JsonObject? JsonArray.get_object(&self, usz index)
{
    return (*self)[index].as_object();
}

// ---------------------------------------
// Unescaping
// ---------------------------------------

fn int hex_val(char c) @inline @private
{
    if ('0' <= c && c <= '9') return c - '0';
    if ('a' <= c && c <= 'f') return c - 'a' + 10;
    if ('A' <= c && c <= 'F') return c - 'A' + 10;
    return -1; // invalid hex digit
}

fn void append_utf8(DString* buf, uint cp) @inline @private
{
    if (cp < 0x80) {
        buf.append_char((char)cp);
    } else if (cp < 0x800) {
        buf.append_char((char)(0xC0 | (cp >> 6)));
        buf.append_char((char)(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        buf.append_char((char)(0xE0 | (cp >> 12)));
        buf.append_char((char)(0x80 | ((cp >> 6) & 0x3F)));
        buf.append_char((char)(0x80 | (cp & 0x3F)));
    } else {
        buf.append_char((char)(0xF0 | (cp >> 18)));
        buf.append_char((char)(0x80 | ((cp >> 12) & 0x3F)));
        buf.append_char((char)(0x80 | ((cp >> 6) & 0x3F)));
        buf.append_char((char)(0x80 | (cp & 0x3F)));
    }
}

fn void free_str(String str) @public
{
    str.free(localmem);
}

// Decode JSON escape sequences in `str` and return the unescaped result.
// The returned String is allocated from localmem; free with free_str() when done.
// Invalid or incomplete escapes are copied through literally.
fn String unescape_str(String str) @private
{
    DString buf;
    buf.init(localmem);

    usz i = 0;
    while (i < str.len) {
        char c = str[i];
        if (c != '\\') {
            buf.append_char(c);
            i++;
            continue;
        }

        // lone backslash at end of input — copy literally
        if (i + 1 >= str.len) {
            buf.append_char('\\');
            i++;
            continue;
        }

        char esc = str[i + 1];
        switch (esc) {
            case '"':  buf.append_char('"');  i += 2;
            case '\\': buf.append_char('\\'); i += 2;
            case '/':  buf.append_char('/');  i += 2;
            case 'n':  buf.append_char('\n'); i += 2;
            case 'r':  buf.append_char('\r'); i += 2;
            case 't':  buf.append_char('\t'); i += 2;
            case 'b':  buf.append_char('\b'); i += 2;
            case 'f':  buf.append_char('\f'); i += 2;
            case 'u':
                // need exactly 4 hex digits: \uXXXX → i+2 .. i+5
                if (i + 6 > str.len) {
                    buf.append_char('\\'); i++; continue;
                }
                int h0 = hex_val(str[i + 2]);
                int h1 = hex_val(str[i + 3]);
                int h2 = hex_val(str[i + 4]);
                int h3 = hex_val(str[i + 5]);
                if (h0 < 0 || h1 < 0 || h2 < 0 || h3 < 0) {
                    // not valid hex — copy the backslash and move on
                    buf.append_char('\\'); i++; continue;
                }
                uint cp = (uint)(h0 << 12 | h1 << 8 | h2 << 4 | h3);
                i += 6;

                // high surrogate? look ahead for a matching low surrogate \uDCxx
                if (cp >= 0xD800 && cp <= 0xDBFF && i + 6 <= str.len
                        && str[i] == '\\' && str[i + 1] == 'u') {
                    int l0 = hex_val(str[i + 2]);
                    int l1 = hex_val(str[i + 3]);
                    int l2 = hex_val(str[i + 4]);
                    int l3 = hex_val(str[i + 5]);
                    if (l0 >= 0 && l1 >= 0 && l2 >= 0 && l3 >= 0) {
                        uint low = (uint)(l0 << 12 | l1 << 8 | l2 << 4 | l3);
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            // valid surrogate pair → combine into a single codepoint
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                            i += 6;
                        }
                    }
                }
                append_utf8(&buf, cp);

            default:
                // unknown escape sequence — copy both characters literally
                buf.append_char('\\');
                buf.append_char(esc);
                i += 2;
        }
    }

    return buf.str_view();
}

// ---------------------------------------
// Encoding
// ---------------------------------------

const char[16] HEX_DIGITS @private = "0123456789abcdef";

// Append the JSON encoding of `self` into `buf`.
fn void JsonValue.encode_into(&self, DString* buf)
{
    switch (self.type) {
        case JsonNull:
            buf.append("null");

        case JsonBool:
            JsonBool* b = (JsonBool*) *self;
            buf.append(*b ? "true" : "false");

        case JsonNumber:
            // stored as raw char[] — emit verbatim
            JsonNumber* n = (JsonNumber*) *self;
            buf.append((String)(*n));

        case String:
            String* s = (String*) *self;
            buf.append_char('"');
            foreach (c : *s) {
                switch (c) {
                    case '"':  buf.append("\\\"");
                    case '\\': buf.append("\\\\");
                    case '\n': buf.append("\\n");
                    case '\r': buf.append("\\r");
                    case '\t': buf.append("\\t");
                    case '\b': buf.append("\\b");
                    case '\f': buf.append("\\f");
                    default:
                        if (c < 0x20) {
                            // control character → \u00XX
                            char[6] esc = {
                                '\\', 'u', '0', '0',
                                HEX_DIGITS[(c >> 4) & 0xf],
                                HEX_DIGITS[c & 0xf],
                            };
                            buf.append((String)esc[0:6]);
                        } else {
                            buf.append_char(c);
                        }
                }
            }
            buf.append_char('"');

        case JsonArray:
            JsonArray* l = (JsonArray*) *self;
            buf.append_char('[');
            foreach (i, e : *l) {
                if (i > 0) buf.append_char(',');
                e.encode_into(buf);
            }
            buf.append_char(']');

        case JsonObject:
            JsonObject* m = (JsonObject*) *self;
            buf.append_char('{');
            bool first = true;
            m.@each(; String key, JsonValue value) {
                if (!first) buf.append_char(',');
                first = false;
                buf.append_char('"');
                buf.append(key);
                buf.append_char('"');
                buf.append_char(':');
                value.encode_into(buf);
            };
            buf.append_char('}');

        default:
            // unknown type — emit null as a safe fallback
            buf.append("null");
    }
}

// Serialize a JsonValue back to a JSON string.
// The returned String is allocated from the module's allocator (localmem).
// Free it with free_str() when no longer needed.
fn String JsonValue.encode(&self)
{
    DString buf;
    buf.init(localmem);
    self.encode_into(&buf);
    // str_view() is a non-owning view into buf's internal heap buffer.
    // We leave the buffer alive; the caller frees via free_str().
    return buf.str_view();
}
