// example.c3
// 
// Example usage of hash in C3

module example;

import ext::hash::city;
import std::io;

fn void main()
{
    // Test strings
    String test1 = "Hello, World!";
    String test2 = "The quick brown fox jumps over the lazy dog";
    String test3 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit";
    
    io::printfn("=== hash64 Examples ===\n");
    
    // hash64
    ulong hash1 = city::hash64(test1.ptr, test1.len);
    io::printfn("hash64('%s') = 0x%016x", test1, hash1);
    
    ulong hash2 = city::hash64(test2.ptr, test2.len);
    io::printfn("hash64('%s') = 0x%016x", test2, hash2);
    
    ulong hash3 = city::hash64(test3.ptr, test3.len);
    io::printfn("hash64('%s') = 0x%016x\n", test3, hash3);
    
    // hash64_with_seed
    io::printfn("=== hash64_with_seed Examples ===\n");
    ulong seed = 0x1234567890ABCDEF;
    ulong hash_seeded = city::hash64_with_seed(test1.ptr, test1.len, seed);
    io::printfn("hash64_with_seed('%s', 0x%016x) = 0x%016x\n", test1, seed, hash_seeded);
    
    // hash128
    io::printfn("=== hash128 Examples ===\n");
    uint128 hash128_1 = city::hash128(test1.ptr, test1.len);
    ulong low1 = city::uint128_low64(hash128_1);
    ulong high1 = city::uint128_high64(hash128_1);
    io::printfn("hash128('%s') = 0x%016x%016x", test1, high1, low1);
    
    uint128 hash128_2 = city::hash128(test2.ptr, test2.len);
    ulong low2 = city::uint128_low64(hash128_2);
    ulong high2 = city::uint128_high64(hash128_2);
    io::printfn("hash128('%s') = 0x%016x%016x\n", test2, high2, low2);
    
    // hash128WithSeed
    io::printfn("=== hash128_with_seed Examples ===\n");
    uint128 seed128 = ((uint128)0xFEDCBA0987654321 << 64) | (uint128)0x1234567890ABCDEF;
    uint128 hash128_seeded = city::hash128_with_seed(test1.ptr, test1.len, seed128);
    ulong low_s = city::uint128_low64(hash128_seeded);
    ulong high_s = city::uint128_high64(hash128_seeded);
    io::printfn("hash128_with_seed('%s', ...) = 0x%016x%016x\n", test1, high_s, low_s);
    
    // hashCrc (if SSE4.2 is available)
    io::printfn("=== hash_crc Examples (requires SSE4.2) ===\n");
    uint128 hash_crc = city::hash128_crc(test2.ptr, test2.len);
    ulong low_crc = city::uint128_low64(hash_crc);
    ulong high_crc = city::uint128_high64(hash_crc);
    io::printfn("hash128_crc('%s') = 0x%016x%016x", test2, high_crc, low_crc);
    
    // hashCrc256
    ulong[4] result256;
    city::hash256_crc(test3.ptr, test3.len, &result256);
    io::printfn("hash256_crc('%s') =", test3);
    io::printfn("  [0] = 0x%016x", result256[0]);
    io::printfn("  [1] = 0x%016x", result256[1]);
    io::printfn("  [2] = 0x%016x", result256[2]);
    io::printfn("  [3] = 0x%016x\n", result256[3]);
    
    // Demonstrate collision resistance
    io::printfn("=== Collision Resistance ===\n");
    String similar1 = "hash";
    String similar2 = "Hash";
    ulong hash_s1 = city::hash64(similar1.ptr, similar1.len);
    ulong hash_s2 = city::hash64(similar2.ptr, similar2.len);
    io::printfn("hash64('%s') = 0x%016x", similar1, hash_s1);
    io::printfn("hash64('%s') = 0x%016x", similar2, hash_s2);
    io::printfn("Different hashes for similar strings: %s\n", hash_s1 != hash_s2 ? "Yes" : "No");
    
    // Performance note
    io::printfn("=== Performance Notes ===");
    io::printfn("hash64 is optimized for x86-64 with high instruction-level parallelism");
    io::printfn("hash128 is faster than hash64 for strings > 2000 bytes");
    io::printfn("hashCrc variants require SSE4.2 and are fastest for very long strings");
    io::printfn("\nWarning: hash is NOT suitable for cryptographic purposes!");
}
