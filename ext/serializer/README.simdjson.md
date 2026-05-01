# ext::serializer::simdjson — SIMD-accelerated JSON parser for C3

`ext::serializer::simdjson` is a high-performance JSON parser for the [ext.c3l](../../README.md) library ecosystem, inspired by the [`simdjson`](https://simdjson.org/) C++ library. It processes JSON in two distinct stages: a SIMD-vectorized scan pass followed by a lightweight tape-building pass, delivering fast parse times with zero allocation per value.

* Note: Like `ext::serializer::json`, this parser is zero-copy. `JsonValue` holds slices into the original input buffer. Keep the input buffer alive for the entire lifetime of the `ParseResult`.

* Note: The decoded tape is read-only. Do not modify the input buffer after calling `parse()`.

# Available module

| Module | Description |
|--------|-------------|
| `ext::serializer::simdjson` | SIMD JSON parser: `ParseResult`, `JsonValue`, `TapeEntry`, `TapeType`, `parse()`, `dump_tape()` |

### Files

* [simdjson.c3](simdjson.c3)

### Examples 

* [../../examples/serializer/simdjson_sample.c3](../../examples/serializer/simdjson_sample.c3)

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.

---

## Architecture overview

Parsing runs in two sequential stages.

**Stage 1 — SIMD structural scan (`scan()`)**

The input is processed in 16-byte chunks using C3's native `char[<16>]` vector type. Each chunk is tested against the set of structural characters (`{`, `}`, `[`, `]`, `:`, `,`, `"`) and whitespace characters simultaneously via `comp_eq` lane comparisons. The resulting per-lane bitmasks are combined with bitwise OR and collapsed to a 16-bit integer with `mask_to_int()`, yielding a compact `ushort` bitmask of structural positions for each chunk.

A stateful `Scanner` carries three pieces of cross-chunk context:

| Field | Purpose |
|-------|---------|
| `in_string` | Whether the previous chunk ended inside a string literal |
| `prev_escaped` | Whether the last byte of the previous chunk was an odd-length backslash run |
| `prev_boundary` | Whether the last byte was a structural character or whitespace |

Using these, Stage 1 also identifies **pseudo-structural positions**: the first non-whitespace, non-structural character following a boundary. These mark the start of bare values (`true`, `false`, `null`, numbers) that carry no opening delimiter. Optional `//` line comment suppression is handled entirely in Stage 1 via `Scanner.comment_mask()`.

The output of Stage 1 is a flat `usz[]` array of source-buffer offsets — one entry per structural or pseudo-structural character.

**Stage 2 — tape construction (`Parser`)**

The `Parser` walks the index list from Stage 1 and emits a flat array of `TapeEntry` records called the **tape**. Objects and arrays produce a cross-linked pair of `START_*` / `END_*` entries: the `START` entry stores the tape index of its matching `END`, and vice versa. This cross-link allows O(1) subtree skipping during value access.

---

## Internal types

### `TapeType`

```c3
enum TapeType : char {
    ROOT,
    START_OBJECT, END_OBJECT,
    START_ARRAY,  END_ARRAY,
    STRING, NUMBER, TRUE, FALSE, NULL_VAL,
}
```

### `TapeEntry`

```c3
struct TapeEntry {
    TapeType type;
    usz offset;  // byte offset into the source buffer (scalars), or paired tape index (containers)
    usz length;  // byte length of the value in the source buffer
}
```

For `STRING` and `NUMBER`, `offset` and `length` delimit the raw source slice (not yet decoded). For `START_OBJECT` / `START_ARRAY`, `offset` holds the tape index of the matching `END` entry, enabling O(1) subtree skipping.

### `ParseResult`

```c3
struct ParseResult {
    TapeEntry[] tape;
    char[] src;
    bool ok;
    Allocator alloc;
}
```

Owns the `tape` allocation. Call `result.free()` when done.

### `JsonValue`

```c3
struct JsonValue {
    char[] src;    // slice of the original input (not owned)
    TapeEntry[] tape;
    usz pos;       // index of this value's tape entry
}
```

A lightweight, zero-copy cursor into the tape. Copying a `JsonValue` is cheap; no heap allocation is involved.

---

## API

### Parsing

```c3
import ext::serializer::simdjson;

// Parse a JSON byte slice.
// allow_comma   — tolerate trailing commas in arrays and objects (default: true)
// allow_comment — tolerate // line comments (default: true)
// Returns a ParseResult or propagates a fault on error.
ParseResult? result = simdjson::parse(Allocator alloc, char[] input, bool allow_comma = true, bool allow_comment = true);
```

**Faults**

| Fault | Condition |
|-------|-----------|
| `EMPTY_INPUT` | `input.len == 0` |
| `NO_TOKENS` | Stage 1 found no structural characters |
| `PARSE_FAILED` | Stage 2 encountered a malformed structure |
| `ALLOC_FAILED` | Tape or scope-stack allocation failed |

**Example**

```c3
import ext::serializer::simdjson;

@pool() {
    char[] src = `{"name":"Alice","scores":[10,20,30]}`;
    ParseResult? result = simdjson::parse(tmem, src);
    if (catch err = result) {
        io::printfn("json parse error: %s", err);
        return err~;
    }
    // defer result.free();

    JsonValue root = result.root();
    // access values via root...
}; // result gets free'd here
```

---

### Memory management

```c3
void result.free();  // frees the tape allocation; does not touch the input buffer
```

The `ParseResult` owns only the `tape` array. Strings and numbers are zero-copy slices of the original input; no individual value free is required.

---

### `JsonValue` — type inspection

```c3
JsonValue v = result.root();

TapeType t = v.type();       // raw tape type of this entry
bool b = v.is_string();      // true if STRING
bool b = v.is_number();      // true if NUMBER
bool b = v.is_object();      // true if START_OBJECT
bool b = v.is_array();       // true if START_ARRAY
bool b = v.is_null();        // true if NULL_VAL
bool b = v.is_true();        // true if TRUE
bool b = v.is_false();       // true if FALSE
```

### `JsonValue` — value extraction

```c3
JsonValue v = result.root();

bool     b = v.as_bool();      // true when type == TRUE, false otherwise (no fault)
String   s = v.as_str();       // zero-copy slice; raw JSON escapes are preserved
String   s = v.raw_num();      // raw source slice of a NUMBER (e.g. "-3.14e+2")
long?    l = v.as_long();      // TYPE_MISMATCH if not NUMBER; propagates to_long() faults
double?  d = v.as_double();    // TYPE_MISMATCH if not NUMBER; propagates to_double() faults
```

Numbers are stored as raw `char[]` source slices and converted on demand. No precision is lost at parse time.

**Faults for value extraction**

| Fault | Condition |
|-------|-----------|
| `TYPE_MISMATCH` | The value's tape type does not match the requested accessor |
| `INVALID_NUMBER` | `to_long()` or `to_double()` failed on the raw number text |

---

### `JsonValue` — object access

```c3
JsonValue v = result.root();

usz n   = v.len(); // number of key-value pairs (0 if not an object)
JsonValue? child = v.get(String key); // linear key scan; TYPE_MISMATCH or KEY_NOT_FOUND on failure
```

**Fault**

| Fault | Condition |
|-------|-----------|
| `KEY_NOT_FOUND` | Key is absent from the object |
| `TYPE_MISMATCH` | Value is not an object |

**Example**

```c3
JsonValue? name_val = root.get("name");
String name = name_val.as_str(); // "Alice"
```

---

### `JsonValue` — array access

```c3
usz n = v.len(); // number of elements (0 if not an array)
JsonValue? elem = v.at(usz i);  // index-based access; TYPE_MISMATCH or INDEX_OUT_OF_RANGE on failure
```

**Fault**

| Fault | Condition |
|-------|-----------|
| `INDEX_OUT_OF_RANGE` | Index is >= the array length |
| `TYPE_MISMATCH` | Value is not an array |

**Example**

```c3
JsonValue? scores = root.get("scores");
JsonValue? first  = scores.at(0);
long n = first.as_long()!;  // 10
```

---

### Tape debugger

```c3
void simdjson::dump_tape(ParseResult* r);
```

Prints all tape entries to stdout with their index, type, and payload. Useful for inspecting parser output during development.

**Sample output**

```
=== tape dump ===
[00] START_OBJECT  -> end@8
[01] STRING        "name"
[02] STRING        "Alice"
[03] STRING        "scores"
[04] START_ARRAY   -> end@7
[05] NUMBER        10
[06] NUMBER        20
[07] END_ARRAY     <- start@4
[08] END_OBJECT    <- start@0
=== 9 entries ===
```

---

## Comparison with `ext::serializer::json`

| Feature | `ext::serializer::json` | `ext::serializer::simdjson` |
|---------|------------------------|-----------------------------|
| Parse strategy | Single-pass recursive descent | Two-stage: SIMD scan + tape walk |
| Value representation | `any`-tagged tree (`JsonValue = any`) | Flat tape with `JsonValue` cursor |
| Memory layout | Tree nodes allocated per value | Single contiguous `TapeEntry[]` array |
| Container skip | O(depth) tree traversal | O(1) via cross-linked tape indices |
| SIMD width | 8-byte `char[<8>]` scan in string search | 16-byte `char[<16>]` full structural scan |
| String decoding | Zero-copy slice (no escape processing) | Zero-copy slice (no escape processing) |
| Comment support | `//` and `/* */` | `//` only |
| Trailing comma | Supported | Supported |
| Free per value | `obj.free()` recursive free | `result.free()` single deallocation |

---

## Notes

- `JsonValue` holds raw pointers into the input buffer. The input must remain valid for the entire lifetime of the `ParseResult`.
- Strings returned by `as_str()` retain JSON escape sequences (`\\n`, `\\uXXXX`, etc.). Unescape at the application level if needed.
- Object key lookup (`get()`) performs a linear scan over tape entries. For repeated access to the same object, cache the `JsonValue` rather than calling `get()` multiple times.
- The `scan()` function and `Parser` type are internal and are not part of the public API.

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.
