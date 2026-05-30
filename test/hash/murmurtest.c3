import std::io;

import ext::hash::murmur;

fn void main() 
{
  {
    char[] key = "hello world";
    uint seed = 123;

    uint h32 = murmur::hash3_x86_32(key.ptr, key.len, seed);

    io::printfn("MurmurHash: 0x%x", h32);
  }
  {
    char[] key = "hello world!";
    uint seed = 123;

    uint h32 = murmur::hash3_x86_32(key.ptr, key.len, seed);

    io::printfn("MurmurHash: 0x%x", h32);
  }
}