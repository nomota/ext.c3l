# ext::encoding::json - JSON decoder for C3

`ext::encoding::json` is a JSON decoder for the [ext.c3l](../..README.md) library ecosystem. It parses a JSON string into a tree of `JsonValue`s backed by a caller-supplied allocator, with optional support for trailing commas and comments.

* Note: This is highly efficient because they minimize the copy of data, remembering positional info on the given input buffer. So you need to be careful to keep the input buffer available while the parsed object is alive.

* Note: the decoded structure must be read-only, immutable, because it has pointers to input buffer.

# Available module

| Module | Description |
|--------|-------------|
| `ext::encoding::json` | JSON serializer: JsonObject, JsonArray, JsonValue, JsonNull, JsonBool, JsonNumber, String, bool, long, double, null, decode(), encode() |

### Files

* [json.c3](json.c3)

### Exqmples

* [../../test/encoding/json_sample.c3](../../test/encoding/json_sample.c3)

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.

## Type aliases

| Alias | Underlying type | Represents |
|-------|-----------------|------------|
| `JsonValue` | `any` | Any JSON value (tagged union via C3's `any`) |
| `JsonArray` | `List{JsonObject}` | JSON array |
| `JsonObject` | `HashMap{String, JsonObject}` | JSON object (key-value map) |
| `JsonNull` | `void*` | JSON `null` |
| `JsonBool` | `bool` | JSON `true` / `false` |
| `JsonNumber` | `char[]` | JSON number stored as raw text |

Numbers are kept as raw `char[]` slices and converted on demand via `as_int()` / `as_float()`, so no precision is lost during parsing.

---

## API

### Decoding

```c3
import ext::encoding::json;

// Parse a JSON string.
// allow_comma – tolerate trailing commas in arrays and objects (default: true)
// allow_comment – tolerate // and /* */ comments (default: true)
// Returns the root JsonObject or propagates a fault on error.
JsonValue? obj = json::decode(Allocator allocx, String text, bool allow_comma = true, bool allow_comment = true);
```

**Example**

```c3
@pool() {
    JsonValue? obj = json::decode(tmem, `{"name":"Alice","age":30}`); // `tmem` temporary allocator
    if (catch err = obj) {
        io::printfn("parse error: %s", err);
        return;
    }
    // defer obj.free(); // no need to free individually
}; // `tmem` allocated memory gets free'd here all at once
```

---

### JsonObject — type inspection

```c3
bool b = obj.is_null();    // true if the value is JSON null
bool b = obj.is_bool();    // true if the value is true or false
bool b = obj.is_int();     // true if the number has no decimal point or exponent
bool b = obj.is_float();   // true if the number has a decimal point or exponent
bool b = obj.is_string();  // true if the value is a JSON string
bool b = obj.is_array();   // true if the value is a JSON array
bool b = obj.is_object();     // true if the value is a JSON object
```

### JsonObject — value extraction

```c3
bool? b = obj.as_bool();    // JSON_TYPE_ERROR if not a bool
long? l = obj.as_int();     // JSON_TYPE_ERROR if not an integer number
double? d = obj.as_float();   // JSON_TYPE_ERROR if not a float number
String? s = obj.as_string();  // JSON_TYPE_ERROR if not a string
JsonArray? a = obj.as_array();   // JSON_TYPE_ERROR if not an array
JsonObject? m = obj.as_object();     // JSON_TYPE_ERROR if not an object
```

### JsonObject — memory management

```c3
void obj.free();  // recursively frees the object and all children
```

All allocations made during `decode()` share the `LocalAllocator` bound to the `Allocator` passed in. Call `obj.free()` once when the parsed tree is no longer needed.

---

### JsonMap — key-value access

```c3
bool b =  map.has(String key);              // true if the key exists
String? s = map.get_string(String key);       // JSON_KEY_NOT_FOUND or JSON_TYPE_ERROR on failure
long? n = map.get_int(String key);
double? d = map.get_float(String key);
bool? b = map.get_bool(String key);
JsonArray? a = map.get_array(String key);
JsonObject? m = map.get_object(String key);
```

**Example**

```c3
JsonObject? m = obj.as_object()!;
String name = m.get_string("name")!;  // "Alice"
long age = m.get_int("age")!;      // 30
```

---

### JsonArray — index-based access

```c3
JsonObject? obj = arr.at(sz index);           // raw element (any type)
String? s = arr.get_string(sz index);
long? n = arr.get_int(sz index);
double? d = arr.get_float(sz index);
bool? b = arr.get_bool(sz index);
JsonArray? a = arr.get_array(sz index);
JsonObject? m = arr.get_object(sz index);
```

**Example**

```c3
JsonArray tags = m.get_array("tags")!;
String first = tags.get_string(0)!;
```

### Encoding

```c3
String json_str = obj.encode();
json::free_str(json_str); // need to be free˚d by this function
---

## Internal details

`JsonDecoder` is an internal struct used during parsing and is not part of the public API. The decoder uses an 8-wide SIMD-style scan (`find_in_8_char`) built on C3's native vector type `char[<8>]` to accelerate string boundary search, falling back to a scalar scan for the remaining tail bytes.

---

## Notes

- Numbers are stored as raw `char[]` at parse time with no conversion overhead. Call `as_int()` or `as_float()` to convert when needed.
- Memory is owned shallowly by the `Allocator` passed to `decode()`. String and JsonNumber have the slices of the input text. Call `obj.free()` to release the full tree.

This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.
