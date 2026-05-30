# ext::mem - mem allocation macros in ext lib

`ext::mem` is for giving memory allocation functions/macros.

# Available module

| Module | Description |
|--------|-------------|
| `ext::mem` | Allocation macros: set_allocator(), mem_alloc(), mem_malloc(), mem_alloc_array(), mem_copy(), mem_copy_str(), mem_free(), temp_alloc(), temp_malloc(), temp_alloc_array(), temp_free(), LocalAllocator |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

# API functions

```c3 
import ext::mem;

void mem::set_allocator(Allocator alloc); // this is done only once in a lifetime of a program
// if missing, first allocation sets `mem` as the default allocator

// @builtin, so you don't have to specify `mem::` prefix
void* p = mem_malloc(size) @builtin;
Type* p = mem_alloc(Type) @builtin;
Type[] p = mem_alloc_array(Type, number) @builtin;
char[] p = mem_copy(char[] buf) @builtin;
String p = mem_copy_str(String str) @builtin;
void mem_free(void* p) @builtin;

// temp allocator within @pool() {..}; scope
void* p = temp_malloc(size) @builtin;
Type* p = temp_alloc(Type) @builtin;
Type[] p = temp_alloc_array(Type, number) @builtin;

void temp_free(void* p); // do nothing.
// at the end of `@pool() {...};` macro scope,`tmem` allocated memory gets free'd all at once automatically.
```

# LocalAllocator

`LocalAllocator` wraps an existing `Allocator` and provides a struct-scoped allocation interface. Useful for passing a specific allocator instance around without relying on the global `allocx`.

```c3
import ext::mem;

// Create a LocalAllocator backed by an existing allocator.
// Returns null on allocation failure.
tlocal LocalAllocator* mem = mem::localallocator_new(Allocator allocx);

// Allocate raw bytes. Returns null on failure.
void*? p = mem.malloc(sz size);

// Allocate a single value of Type. Returns null on failure.
Type*? p = mem.alloc(Type);

// Allocate an array of n elements of Type. Returns null on failure.
Type[]? arr = mem.alloc_array(Type, n);

// Free a previously allocated pointer.
void mem.free(void* p);
```

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.
