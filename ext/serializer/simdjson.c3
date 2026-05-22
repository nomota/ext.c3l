// simdjson.c3

// JSON parser optimized by SIMD vector operations, inspired by `simdjson` C library.
// Two stages.
// Stage1. Scan and find indices of structural characters, {}[]:,", and begin of a value.
// Stage2. Walk through the indices to collect Tape entries. Each Tape entry has structural info or a value.

module ext::serializer::simdjson;

import std::collections::list;
import std::io;
import ext::mem;
import ext::debug;

// =======================================
// SIMD helpers  (Stage 1)
// =======================================

const int CHUNK = 16; // SIMD vector width
alias Chunk = char[<CHUNK>];
alias BChunk = bool[<CHUNK>];
alias MChunk = char[<CHUNK>]; // 0x00/0x01 per lane — supports bitwise OR across lanes

fn ushort structural_mask(Chunk* v) @inline
{
    MChunk m = (MChunk)((*v).comp_eq((Chunk)'{'))
             | (MChunk)((*v).comp_eq((Chunk)'}'))
             | (MChunk)((*v).comp_eq((Chunk)'['))
             | (MChunk)((*v).comp_eq((Chunk)']'))
             | (MChunk)((*v).comp_eq((Chunk)':'))
             | (MChunk)((*v).comp_eq((Chunk)','))
             | (MChunk)((*v).comp_eq((Chunk)'"'));
    return (ushort)((BChunk)m).mask_to_int();
}

fn ushort whitespace_mask(Chunk* v) @inline
{
    MChunk m = (MChunk)((*v).comp_eq((Chunk)' '))
             | (MChunk)((*v).comp_eq((Chunk)'\t'))
             | (MChunk)((*v).comp_eq((Chunk)'\r'))
             | (MChunk)((*v).comp_eq((Chunk)'\n'));
    return (ushort)((BChunk)m).mask_to_int();
}

fn ushort eq_mask(Chunk* v, char c) @inline
{
    return (ushort)((*v).comp_eq((Chunk)c)).mask_to_int();
}

// Prefix XOR: result[i] = XOR(input[0..i])
// Equivalent to carry-less multiply by 0xFFFF (pclmulqdq on x86).
fn ushort prefix_xor(ushort x) @inline
{
    x ^= x << 1;
    x ^= x << 2;
    x ^= x << 4;
    x ^= x << 8;
    return x;
}

fn ushort range_mask(uint from, uint to) @inline
{
    ushort hi = (to >= 15) ? (ushort)0xFFFF : (ushort)((1u << (to + 1u)) - 1u);
    ushort lo = (from == 0) ? (ushort)0     : (ushort)((1u << from) - 1u);
    return hi & ~lo;
}

// =======================================
// Scanner — carries cross-chunk state
// =======================================

struct Scanner {
    usz  in_string;     // 1 when the last chunk ended inside a string
    usz  prev_escaped;  // 1 when the last byte of the previous chunk was an odd backslash run
    bool in_comment;    // true when inside a // line comment
    bool prev_boundary; // true when the last byte of the previous chunk was a structural char or whitespace
}

// Returns a bitmask of positions belonging to the interior/closing of a string.
// These positions must be excluded from structural and pseudo-structural masks.
fn ushort Scanner.string_mask(&self, Chunk* v)
{
    ushort q = eq_mask(v, '"');
    ushort bs = eq_mask(v, '\\');

    ushort escaped = (ushort)((bs << 1) | (ushort)self.prev_escaped);
    ushort real_quotes = q & ~escaped;

    ushort pxor = prefix_xor(real_quotes);

    // If the previous chunk ended inside a string, flip open/close sense
    if (self.in_string != 0) pxor = ~pxor;

    // pxor        : opening"(included) ... closing"(excluded) = 1
    // pxor^quotes : opening"(excluded) ... closing"(included) = 1  <- what we want
    ushort s = pxor ^ real_quotes;

    // Carry: pxor MSB tells whether we exit this chunk still inside a string
    self.in_string = (usz)(pxor >> 15);
    self.prev_escaped = (usz)(bs   >> 15);

    return s;
}

// Returns a bitmask of positions belonging to a // line comment.
fn ushort Scanner.comment_mask(&self, Chunk* v, ushort str_mask)
{
    ushort nl = eq_mask(v, '\n');

    // Already inside a comment carried from a previous chunk
    if (self.in_comment)
    {
        if (nl != 0)
        {
            uint nl_bit = (uint)nl.ctz();
            self.in_comment = false;
            return range_mask(0, nl_bit);
        }
        return 0xFFFF;
    }

    // Look for "//" not inside a string
    ushort sl = eq_mask(v, '/') & ~str_mask;
    ushort dbl = sl & (ushort)(sl >> 1);
    if (dbl == 0) return 0;

    uint cs = (uint)dbl.ctz();

    ushort nl_after = nl & (ushort)(~((1u << cs) - 1u));
    if (nl_after != 0)
    {
        uint nl_bit = (uint)nl_after.ctz();
        return range_mask(cs, nl_bit);
    }

    self.in_comment = true;
    return range_mask(cs, 15);
}

// Returns a bitmask of pseudo-structural positions: the first non-whitespace,
// non-structural, non-string character that follows a structural char or
// whitespace run.  These mark the start of bare values (true/false/null/numbers).
fn ushort Scanner.pseudo_structural(&self, Chunk* v, ushort str_mask, ushort ws, ushort raw_s)
{
    ushort boundary = raw_s | ws;

    // Shift left by 1: "was the previous position a boundary?"
    // Bit 0 is supplied by the carry from the previous chunk.
    ushort prev_b = (ushort)((boundary << 1) | (self.prev_boundary ? 1u : 0u));

    ushort result = prev_b & ~ws & ~raw_s & ~str_mask;

    self.prev_boundary = (boundary >> 15) != 0;

    return result;
}

// =======================================
// Stage 1
// =======================================

// returned indices need to be free'd
fn usz[] scan(Allocator alloc, char[] input, bool allow_comma=true, bool allow_comment=true)
{
    usz n = input.len;
    usz nchunks = (n + CHUNK - 1) / CHUNK;

    List{usz} indices;
    
    // The very start of the input acts as a boundary so the first
    // bare value character is correctly detected as pseudo-structural.
    Scanner sc = { .prev_boundary = true };

    char[CHUNK] tail = {};

    for (usz ci = 0; ci < nchunks; ci++)
    {
        usz   base = ci * CHUNK;
        usz   avail = (n - base < CHUNK) ? n - base : CHUNK;
        char* buf = input.ptr + base;

        if (avail < CHUNK)
        {
            // Zero-pad the tail chunk to avoid spurious detections in padding
            // bytes (0x00 is non-whitespace, non-structural, so it would look
            // pseudo-structural without the length clamp below).
            for (int i = 0; i < CHUNK; i++) tail[i] = 0;
            mem::copy(&tail[0], buf, avail);
            buf = &tail[0];
        }

        Chunk* v = (Chunk*)buf;

        ushort str_mask = sc.string_mask(v);
        ushort ws = whitespace_mask(v);
        ushort raw_s = structural_mask(v) & ~str_mask;
        ushort pseudo = sc.pseudo_structural(v, str_mask, ws, raw_s);
        ushort s_mask = raw_s | pseudo;

        if (allow_comment) {
            s_mask &= ~sc.comment_mask(v, str_mask);
        }

        // Clamp to actual bytes in the last partial chunk
        if (avail < CHUNK) {
            s_mask &= (ushort)((1u << avail) - 1u);
        }

        ushort m = s_mask;
        while (m != 0)
        {
            uint bit = (uint)m.ctz();
            indices.push(base + bit);
            m &= m - 1;
        }
    }

    return indices.to_array(alloc);
}

// =======================================
// Stage 2 — tape
// =======================================

enum TapeType : char {
    ROOT,
    START_OBJECT, END_OBJECT,
    START_ARRAY,  END_ARRAY,
    STRING, NUMBER, TRUE, FALSE, NULL_VAL,
}

// Tape entry layout
//
//   STRING               offset = first byte after the opening "
//                        length = byte count up to (not including) the closing "
//   NUMBER               offset = first byte of the literal
//                        length = byte count of the literal (lazy, convert on access)
//   TRUE / FALSE / NULL_VAL
//                        offset = position in input, length = keyword length
//   START_OBJECT/ARRAY   offset = tape index of the matching END entry
//   END_OBJECT/ARRAY     offset = tape index of the matching START entry
struct TapeEntry {
    TapeType type;
    usz offset;
    usz length;
}

struct Parser {
    char[] input;
    usz[] indices; // structural index list from Stage 1
    usz idx; // cursor into indices[]
    TapeEntry[] tape;
    usz tape_pos;
    usz[] scope_stack;
    usz depth;
    bool allow_comma;
    bool allow_comment;
}

fn void Parser.emit(&self, TapeType t, usz offset, usz length) @inline
{
    self.tape[self.tape_pos++] = { t, offset, length };
}

fn void Parser.patch_offset(&self, usz tape_idx, usz new_offset) @inline
{
    self.tape[tape_idx].offset = new_offset;
}

// Cross-link the opening and closing tape entries.
// NOTE: does NOT advance idx — the caller must consume the closing delimiter.
fn void Parser.close_scope(&self, TapeType close_type)
{
    usz open_tape = self.scope_stack[--self.depth];
    usz close_tape = self.tape_pos;
    self.patch_offset(open_tape, close_tape); // START.offset -> END tape index
    self.emit(close_type, open_tape, 0);       // END.offset -> START tape index
}

fn bool Parser.at_end(&self) @inline => self.idx >= self.indices.len;

fn char Parser.peek(&self) @inline
{
    return self.at_end() ? '\0' : self.input[self.indices[self.idx]];
}

// ---- end-of-value scanners ----

fn usz find_string_end(char[] input, usz start) @private
{
    usz i = start;
    while (i < input.len)
    {
        if (input[i] == '\\') { i += 2; continue; }
        if (input[i] == '"')  return i;
        i++;
    }
    return input.len;
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

fn usz find_number_end(char[] input, usz start) @private
{
    usz i = start;
    while (i < input.len)
    {
        if (! isnum(input[i])) {
            break;
        }
        i++;
    }
    return i;
}

// ---- scalar value parsers — each advances self.idx by 1 ----
//
// Invariant shared by ALL parse_X functions:
//   On successful return, self.idx points to the first structural index
//   that has NOT yet been consumed.

// Emits a STRING entry for the string whose opening " is at indices[idx].
fn bool Parser.parse_string_val(&self)
{
    usz pos = self.indices[self.idx];
    usz start = pos + 1;
    usz end = find_string_end(self.input, start);
    self.emit(TapeType.STRING, start, end - start);
    self.idx++; // consume the opening " structural index
    return true;
}

// Emits a NUMBER entry for the literal starting at indices[idx].
fn bool Parser.parse_number_val(&self)
{
    usz pos = self.indices[self.idx];
    usz end = find_number_end(self.input, pos);
    self.emit(TapeType.NUMBER, pos, end - pos);
    self.idx++;
    return true;
}

// Emits a keyword entry (true/false/null) after validating the literal bytes.
fn bool Parser.parse_literal_val(&self, char[] expected, TapeType t)
{
    usz pos = self.indices[self.idx];
    usz len = expected.len;
    if (pos + len > self.input.len) return false;
    for (usz i = 0; i < len; i++) {
        if (self.input[pos + i] != expected[i]) return false;
    }
    self.emit(t, pos, len);
    self.idx++;
    return true;
}

fn bool Parser.parse_value(&self)
{
    if (self.at_end()) return false;

    usz  pos = self.indices[self.idx];
    char c = self.input[pos];

    switch (c)
    {
        case '{': return self.parse_object();
        case '[': return self.parse_array();
        case '"': return self.parse_string_val();
        case 't': return self.parse_literal_val("true",  TapeType.TRUE);
        case 'f': return self.parse_literal_val("false", TapeType.FALSE);
        case 'n': return self.parse_literal_val("null",  TapeType.NULL_VAL);
        default:
            if (c == '-' || (c >= '0' && c <= '9')) {
                return self.parse_number_val();
            }
            return false;
    }
}

fn bool Parser.parse_object(&self)
{
    usz open_tape = self.tape_pos;
    self.emit(TapeType.START_OBJECT, 0, 0);
    self.scope_stack[self.depth++] = open_tape;
    self.idx++; // consume '{'

    // Empty object
    if (self.peek() == '}')
    {
        self.idx++; // consume '}'
        self.close_scope(TapeType.END_OBJECT);
        return true;
    }

    while (true)
    {
        // Key must be a string
        if (self.at_end() || self.peek() != '"') return false;
        usz kpos = self.indices[self.idx];
        usz kstart = kpos + 1;
        usz kend = find_string_end(self.input, kstart);
        self.emit(TapeType.STRING, kstart, kend - kstart);
        self.idx++; // consume key '"'

        // Colon
        if (self.at_end() || self.peek() != ':') return false;
        self.idx++; // consume ':'

        // Value — parse_value() fully consumes the value and advances idx
        if (!self.parse_value()) return false;

        char next = self.peek();
        if (next == '}')
        {
            self.idx++; // consume '}'
            self.close_scope(TapeType.END_OBJECT);
            return true;
        }
        if (next != ',') return false;
        self.idx++; // consume ','

        // Trailing comma: } may follow the comma immediately
        if (self.allow_comma && self.peek() == '}')
        {
            self.idx++; // consume '}'
            self.close_scope(TapeType.END_OBJECT);
            return true;
        }
    }
}

fn bool Parser.parse_array(&self)
{
    usz open_tape = self.tape_pos;
    self.emit(TapeType.START_ARRAY, 0, 0);
    self.scope_stack[self.depth++] = open_tape;
    self.idx++; // consume '['

    // Empty array
    if (self.peek() == ']')
    {
        self.idx++; // consume ']'
        self.close_scope(TapeType.END_ARRAY);
        return true;
    }

    while (true)
    {
        // Value — parse_value() fully consumes the value and advances idx
        if (!self.parse_value()) return false;

        char next = self.peek();
        if (next == ']')
        {
            self.idx++; // consume ']'
            self.close_scope(TapeType.END_ARRAY);
            return true;
        }
        if (next != ',') return false;
        self.idx++; // consume ','

        // Trailing comma: ] may follow the comma immediately
        if (self.allow_comma && self.peek() == ']')
        {
            self.idx++; // consume ']'
            self.close_scope(TapeType.END_ARRAY);
            return true;
        }
    }
}

// =======================================
// Public parse entry point
// =======================================

faultdef
    EMPTY_INPUT,
    NO_TOKENS,
    PARSE_FAILED,
    ALLOC_FAILED;

struct ParseResult {
    TapeEntry[] tape;
    char[] src;
    bool ok;
    Allocator alloc;
}

fn void ParseResult.free(&self)
{
    self.alloc.free(self.tape);
}

// result must be free'd at caller
fn ParseResult? parse(Allocator alloc, char[] input, bool allow_comma=true, bool allow_comment=true)
{
    if (input.len == 0) return EMPTY_INPUT~;

    usz[] s1 = scan(alloc, input, allow_comma, allow_comment);
    defer alloc.free(s1);
    
    if (s1.len == 0) return NO_TOKENS~;

    usz max_tape = s1.len + 4;
    usz max_depth = s1.len / 2 + 2;

    TapeEntry* tape_ptr = (TapeEntry*)alloc.malloc(TapeEntry.sizeof * max_tape)!;
    usz* scope_ptr = (usz*)alloc.malloc(usz.sizeof * max_depth)!;
    defer alloc.free(scope_ptr);
    
    Parser p = {
        .input = input,
        .indices = s1,
        .tape = tape_ptr[:max_tape],
        .scope_stack = scope_ptr[:max_depth],
        .allow_comma = allow_comma,
        .allow_comment = allow_comment,
    };

    if (!p.parse_value()) return PARSE_FAILED~;

    return { tape_ptr[:p.tape_pos], input, true, alloc };
}

// =======================================
// JsonValue — lazy, zero-copy view into the tape
// =======================================

faultdef
    TYPE_MISMATCH,
    KEY_NOT_FOUND,
    INDEX_OUT_OF_RANGE,
    INVALID_NUMBER;

struct JsonValue
{
    char[] src; // slice of the original input (not owned)
    TapeEntry[] tape;
    usz pos; // index of this value's tape entry
}

fn JsonValue ParseResult.root(&self) => { self.src, self.tape, 0 };

fn TapeType JsonValue.type(&self)  @inline => self.tape[self.pos].type;
fn bool JsonValue.is_string(&self) @inline => self.tape[self.pos].type == TapeType.STRING;
fn bool JsonValue.is_number(&self) @inline => self.tape[self.pos].type == TapeType.NUMBER;
fn bool JsonValue.is_object(&self) @inline => self.tape[self.pos].type == TapeType.START_OBJECT;
fn bool JsonValue.is_array(&self)  @inline => self.tape[self.pos].type == TapeType.START_ARRAY;
fn bool JsonValue.is_null(&self)   @inline => self.tape[self.pos].type == TapeType.NULL_VAL;
fn bool JsonValue.is_true(&self)   @inline => self.tape[self.pos].type == TapeType.TRUE;
fn bool JsonValue.is_false(&self)  @inline => self.tape[self.pos].type == TapeType.FALSE;
fn bool JsonValue.as_bool(&self)   @inline => self.tape[self.pos].type == TapeType.TRUE;

// Zero-copy string slice. The slice still contains raw JSON escape sequences.
fn String JsonValue.as_str(&self) @inline
{
    TapeEntry* e = &self.tape[self.pos];
    // Use [offset : length] (start + count) instead of [offset .. offset+length]
    // because C3's .. range is inclusive on both ends, which would read one extra byte.
    return (String)self.src[e.offset : e.length];
}

// Raw number slice as it appears in the source (e.g. "-3.14e+2").
// Numeric conversion is deferred to as_long() / as_double().
fn String JsonValue.raw_num(&self) @inline
{
    TapeEntry* e = &self.tape[self.pos];
    return (String)self.src[e.offset : e.length];
}

fn long? JsonValue.as_long(&self)
{
    if (!self.is_number()) return TYPE_MISMATCH~;
    return self.raw_num().to_long()!;
}

fn double? JsonValue.as_double(&self)
{
    if (!self.is_number()) return TYPE_MISMATCH~;
    return self.raw_num().to_double()!;
}

// Return the tape index of the first entry that follows this value.
// For objects and arrays this jumps past the entire subtree in O(1).
fn usz next_tape_pos(TapeEntry[] tape, usz pos)
{
    switch (tape[pos].type)
    {
        case START_OBJECT:
        case START_ARRAY:
            return tape[pos].offset + 1; // offset = END tape index
        default:
            return pos + 1;
    }
}

fn bool str_equal(String a, String b) @inline
{
    return (a == b);
/*
    if (a.len != b.len) return false;
    for (usz i = 0; i < a.len; i++) {
        if (a[i] != b[i]) return false;
    }
    return true;
*/
}

// Look up a key in a JSON object (linear scan).
fn JsonValue? JsonValue.get(&self, String key)
{
    if (!self.is_object()) return TYPE_MISMATCH~;
    usz t = self.pos + 1;
    usz end = self.tape[self.pos].offset; // END_OBJECT tape index
    while (t < end)
    {
        TapeEntry* ke = &self.tape[t];
        String k = (String)self.src[ke.offset : ke.length];
        if (str_equal(k, key)) return { self.src, self.tape, t + 1 };
        t = next_tape_pos(self.tape, t + 1); // skip past the value
    }
    return KEY_NOT_FOUND~;
}

// Return the element at index i in a JSON array.
fn JsonValue? JsonValue.at(&self, usz i)
{
    if (!self.is_array()) return TYPE_MISMATCH~;
    usz t = self.pos + 1;
    usz end = self.tape[self.pos].offset;
    usz n = 0;
    while (t < end)
    {
        if (n == i) return { self.src, self.tape, t };
        t = next_tape_pos(self.tape, t);
        n++;
    }
    return INDEX_OUT_OF_RANGE~;
}

// Number of elements (array) or key-value pairs (object).
fn usz JsonValue.len(&self)
{
    if (!self.is_object() && !self.is_array()) return 0;
    bool is_obj = self.is_object();
    usz  t = self.pos + 1;
    usz  end = self.tape[self.pos].offset;
    usz  count = 0;
    while (t < end)
    {
        if (is_obj) t++; // skip the key STRING entry
        t = next_tape_pos(self.tape, t);
        count++;
    }
    return count;
}

// =======================================
// Tape dump — linear debug printer
// =======================================

// Print all tape entries linearly with index, type, and payload.
// For STRING/NUMBER the raw source slice is shown.
// For START/END pairs the cross-link tape index is shown.
fn void dump_tape(ParseResult* r)
{
    io::printn("=== tape dump ===");
    for (usz i = 0; i < r.tape.len; i++)
    {
        TapeEntry* e = &r.tape[i];
        switch (e.type)
        {
            case START_OBJECT:
                io::printfn("[%02d] START_OBJECT  -> end@%d", i, e.offset);
            case END_OBJECT:
                io::printfn("[%02d] END_OBJECT    <- start@%d", i, e.offset);
            case START_ARRAY:
                io::printfn("[%02d] START_ARRAY   -> end@%d", i, e.offset);
            case END_ARRAY:
                io::printfn("[%02d] END_ARRAY     <- start@%d", i, e.offset);
            case STRING:
                // Use [offset : length] — C3's .. range is inclusive on both
                // ends, which would read one extra byte with [offset .. offset+length].
                io::printfn(`[%02d] STRING        "%s"`,
                    i, (String)r.src[e.offset : e.length]);
            case NUMBER:
                io::printfn("[%02d] NUMBER        %s",
                    i, (String)r.src[e.offset : e.length]);
            case TRUE:
                io::printfn("[%02d] TRUE", i);
            case FALSE:
                io::printfn("[%02d] FALSE", i);
            case NULL_VAL:
                io::printfn("[%02d] NULL", i);
            case ROOT:
                io::printfn("[%02d] ROOT", i);
        }
    }
    io::printfn("=== %d entries ===", r.tape.len);
}

