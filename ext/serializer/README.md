# ext::serializer - various encoder/decoder in C3

This module is to fill missing gaps of C3 std lib by providing various encoders/decoders. 

* Note: These serializers are highly efficient because they minimize the copy of data, remembering positional info on the given input buffer. So you need to be careful to keep the input buffer available while the parsed object is alive.

* Note: the decoded structure must be read-only, immutable, because it has pointers to input buffer.

### JSON decoder/encoder

| Module | Description |
|--------|-------------|
| `ext::serializer::json` | JSON serializer: JsonObject, JsonArray, JsonValue, JsonNull, JsonBool, JsonNumber, String, bool, long, double, null, decode(), encode() |

* More about [JSON decoder/encoder](./README.json.md)

### HTTP header/parameter decoder

| Module | Description |
|--------|-------------|
| `ext::serializer::http` | HTTP/1.x parser: `Request`, `Response`, `Url`, `SetCookie`, `FormFile`, `KeyValue`, `parse_request()`, `parse_response()`, decode helpers |

* More about [HTTP parser](./README.http.md)

### SIMD JSON parser

| Module | Description |
|--------|-------------|
| `ext::serializer::simdjson` | SIMD JSON parser: `ParseResult`, `JsonValue`, `TapeEntry`, `TapeType`, `parse()`, `dump_tape()` |

* More about [SIMD JSON parser](./README.simdjson.md)

### Files

* [json.c3](json.c3)
* [http.c3](http.c3)
* [simdjson.c3](simdjson.c3)

### Exqmples

* [../../test/serializer/json_sample.c3](../../test/serializer/json_sample.c3)
* [../../test/serializer/http_sample.c3](../../test/serializer/http_sample.c3)
* [../../test/serializer/simdjson_sample.c3](../../test/serializer/simdjson_sample.c3)


This is a part of the extended C3 library.
Back to [ext.c3l](../../README.md) library.

