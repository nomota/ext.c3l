# ext::hash - Extended Hash functions

Hash functions that are not found in C3 std library

## Available Modules

| Module | Description |
|--------|-------------|
| `ext::hash::murmur` | MurmurHash3 functions: hash3_x86_32(), hash3_x86_128(), hash3_x64_128() |
| `ext::hash::city` | CityHash functions: hash64(), hash64_with_seed(), hash128(), hash128_with_seed(), hash128_crc(), hash128_ rc_with_seed() |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

### MurmurHash3 module

* [murmur.c3](murmur.c3)

Available functions:

```c3 
import ext::hash::murmur;

uint h32 = murmur::hash3_x86_32(char* key, uint len, uint seed);

uint128 h128 = murmur::hash3_x86_128(char* key, uint len, uint seed);

uint128 h128 = murmur::hash3_x64_128(char* key, uint len, uint seed);
```

### CityHash module

This is a C3 language port of Google's CityHash, a family of fast hash functions for strings. The original implementation was in C++ and this is based on the C port by Alexander Nusov.

CityHash provides hash functions for byte arrays (strings). On x86-64 hardware, `city::hash128_crc()` is faster than other high-quality hash functions due to higher instruction-level parallelism.

* [city.c3](city.c3)
* [citycrc.c3](citycrc.c3)

Available functions:

```c3
import ext::hash::city;

// CityHash64

ulong h = city::hash64(char* buf, uint len);
ulong h = city::hash64_with_seed(char* buf, uint len, ulong seed);

// CityHash128

uint128 h = city::hash128(char* s, uint len);
uint128 h = city::hash128_with_seed(char* s, uint len, uint128 seed);

// CityHashCrc (requires SSE4.2)

uint128 h = city::hash128_crc(char* s, uint len);
uint128 h = city::hash128_crc_with_seed(char* s, uint len, uint128 seed);
void h = city::hash256_crc(char* s, uint len, ulong* result);
```

### Example codes 

* [../../test/hash](../../test/hash)

Back to [ext.c3l](../../README.md) library.

