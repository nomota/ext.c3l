// mem.c3

module ext::mem;

import c::string;
import ext::debug;

Allocator allocx = null;

macro void set_allocator(Allocator alloc) @public
{
    if (allocx != null) { // not default allocator
        if (allocx != alloc) {
            warn("Allocator is already set. Perhaps memory allocation has been made prior to this.");
        }
        return;
    }
    allocx = alloc;
}

macro mem_alloc($Type) @builtin
{
    if (allocx == null) allocx = mem;
    
    void*? p = allocx.acquire($Type.sizeof, ZERO, 0);
    if (catch err = p) {
        @assert(false, "memory allocation error");
        unreachable("mem_alloc failed");
    } else {
        return p;
    }
}

macro mem_malloc(n) @builtin
{
    if (allocx == null) allocx = mem;
  
    void*? p = allocx.acquire(n, ZERO, 0);
    if (catch err = p) {
        @assert(false, "memory allocation error");
        unreachable("mem_malloc failed");
    } else {
        return p;
    }
}

macro mem_alloc_array($Type, n) @builtin
{
    if (allocx == null) allocx = mem;
  
    void*? p = allocx.acquire($Type.sizeof*n, ZERO, 0);
    if (catch err = p) {
        @assert(false, "memory allocation error");
        unreachable("mem_alloc_array failed");
    } else {
        return (($Type*)p)[0:n];
    }
}

macro mem_copy(char[] str) @builtin
{
    if (allocx == null) allocx = mem;
  
    char*? p = allocx.acquire(str.len, ZERO, 0);
    if (catch err = p) {
        @assert(false, "memory allocation error");
        unreachable("mem_copy failed");
    } else {
        string::memcpy(p, str.ptr, str.len);
        return p[0:str.len];
    }
}

macro String mem_copy_str(String str) @builtin
{
    return (String) mem_copy((char[])str);
}

macro mem_free(x) @builtin
{
    if (allocx == null) allocx = mem;
    
    if ((void*)x == null) { warn("mem_free(null)"); return; }
    allocx.release(x, false);
}

macro temp_alloc($Type) @builtin
{
    return ($Type*) temp_malloc($Type.sizeof);
}

macro temp_malloc(n) @builtin
{
    void*? p = tmem.acquire(n, ZERO, 0);
    if (catch p) return null;
    return p;
}

macro temp_alloc_array($Type, n) @builtin
{
    void* p = temp_malloc($Type.sizeof * n);
    return (($Type*)p)[0:n];
}

macro temp_free(x) @builtin
{
    // do nothing:
    // at the end of `@pool() {...};` macro scope,
    // `tmem` allocated memory gets free'd 
    // all at once automatically.
}

alias LocalAllocator = Allocator;

fn void* LocalAllocator.malloc(&self, usz size) @inline
{
    void*? a = self.acquire(size, ZERO, 0);
    if (catch a) return null;
    return a;
}

macro LocalAllocator.alloc(&self, $Type)
{
    return ($Type*) self.malloc($Type.sizeof);
}

macro LocalAllocator.alloc_array(&self, $Type, n)
{
    void* p = self.malloc($Type.sizeof*n);
    return (($Type*)p)[0:n];
}

fn void LocalAllocator.free(&self, void* a)
{
    self.release(a, false);
}
