// murmur.c3 - C3 Translation of MurmurHash3

// MurmurHash3 was written by Austin Appleby, and is placed in the public
// domain. The author hereby disclaims copyright to this source code.
// C3 translation by Nomota Hiongun Kim

// Note - The x86 and x64 versions do _not_ produce the same results, as the
// algorithms are optimized for their respective platforms. You can still
// compile and run any of them on any platform, but your performance with the
// non-native version will be less than optimal.

/*
// How to use:
//

import ext::hash::murmur;

char[] key = "hello world";
uint seed = 123;

uint h32 = murmur::hash3_x86_32(key.ptr, key.len, seed);

uint128 h128 = murmur::hash3_x86_128(key.ptr, key.len, seed);

uint128 h128 = murmur::hash3_x64_128(key.ptr, key.len, seed);

*/


module ext::hash::murmur;

import libc;

//-----------------------------------------------------------------------------
// Platform-specific functions and macros

// C3 inline functions for bit rotation
fn uint rotl32(uint x, char r) @inline
{
    return (x << r) | (x >> (32 - r));
}

fn ulong rotl64(ulong x, char r) @inline
{
    return (x << r) | (x >> (64 - r));
}

//-----------------------------------------------------------------------------
// Block read - if your platform needs to do endian-swapping or can only
// handle aligned reads, do the conversion here

fn uint getblock32(char* p, uint i) @inline
{
    uint r;
    libc::memcpy(&r, p+i, uint::size);
    return r;
}

fn ulong getblock64(char* p, uint i) @inline
{
    ulong r = *(p+i*4);
    libc::memcpy(&r, p+i, ulong::size);
    return r;

}

//-----------------------------------------------------------------------------
// Finalization mix - force all bits of a hash block to avalanche

fn uint fmix32(uint h) @inline
{
    h ^= h >> 16;
    h *= 0x85ebca6b;
    h ^= h >> 13;
    h *= 0xC2b2ae35;
    h ^= h >> 16;
    
    return h;
}

fn ulong fmix64(ulong k) @inline
{
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccd;
    k ^= k >> 33;
    k *= 0xC4ceb9fe1a85ec53;
    k ^= k >> 33;
    
    return k;
}

//-----------------------------------------------------------------------------

fn uint hash3_x86_32(char* key, uint len, uint seed)
{
    char* data = key;
    uint nblocks = len / 4;
    
    uint h1 = seed;
    
    const uint C1 = 0xcc9e2d51;
    const uint C2 = 0x1b873593;
    
    //----------
    // body
    
    // uint* blocks = (uint*)(data + nblocks * 4);
    
    for (uint i = 0; i < nblocks; i++)
    {
        uint k1 = getblock32(data, i);
        
        k1 *= C1;
        k1 = rotl32(k1, 15);
        k1 *= C2;
        
        h1 ^= k1;
        h1 = rotl32(h1, 13);
        h1 = h1 * (uint)5 + 0xe6546b64;
    }
    
    //----------
    // tail
    
    char* tail = data + nblocks * 4;
    
    uint k1 = 0;
    
    switch (len & 3)
    {
        case 3:
            k1 ^= tail[2] << 16;
            nextcase;
        case 2:
            k1 ^= tail[1] << 8;
            nextcase;
        case 1:
            k1 ^= tail[0];
            k1 *= C1;
            k1 = rotl32(k1, 15);
            k1 *= C2;
            h1 ^= k1;
        default:
            break;
    }
    
    //----------
    // finalization
    
    h1 ^= len;
    h1 = fmix32(h1);
    
    return h1;
}

//-----------------------------------------------------------------------------

fn uint128 hash3_x86_128(char* key, uint len, uint seed)
{
    char* data = key;
    uint nblocks = len / 16;
    
    uint h1 = seed;
    uint h2 = seed;
    uint h3 = seed;
    uint h4 = seed;
    
    const uint C1 = 0x239b961b;
    const uint C2 = 0xab0e9789;
    const uint C3 = 0x38b34ae5;
    const uint C4 = 0xa1e38b93;
    
    //----------
    // body
    
    // uint* blocks = (uint*)(data + nblocks * 16);
    
    for (uint i = 0; i < nblocks; i++)
    {
        uint k1 = getblock32(data, i * 4 + 0);
        uint k2 = getblock32(data, i * 4 + 1);
        uint k3 = getblock32(data, i * 4 + 2);
        uint k4 = getblock32(data, i * 4 + 3);
        
        k1 *= C1; k1 = rotl32(k1, 15); k1 *= C2; h1 ^= k1;
        h1 = rotl32(h1, 19); h1 += h2; h1 = h1 * (uint)5 + 0x561ccd1b;
        
        k2 *= C2; k2 = rotl32(k2, 16); k2 *= C3; h2 ^= k2;
        h2 = rotl32(h2, 17); h2 += h3; h2 = h2 * (uint)5 + 0x0bcaa747;
        
        k3 *= C3; k3 = rotl32(k3, 17); k3 *= C4; h3 ^= k3;
        h3 = rotl32(h3, 15); h3 += h4; h3 = h3 * (uint)5 + 0x96cd1C35;
        
        k4 *= C4; k4 = rotl32(k4, 18); k4 *= C1; h4 ^= k4;
        h4 = rotl32(h4, 13); h4 += h1; h4 = h4 * (uint)5 + 0x32aC3b17;
    }
    
    //----------
    // tail
    
    char* tail = data + nblocks * 16;
    
    uint k1 = 0;
    uint k2 = 0;
    uint k3 = 0;
    uint k4 = 0;
    
    switch (len & 15)
    {
        case 15:
            k4 ^= tail[14] << 16;
            nextcase;
        case 14:
            k4 ^= tail[13] << 8;
            nextcase;
        case 13:
            k4 ^= tail[12] << 0;
            k4 *= C4; k4 = rotl32(k4, 18); k4 *= C1; h4 ^= k4;
            nextcase;
        case 12:
            k3 ^= tail[11] << 24;
            nextcase;
        case 11:
            k3 ^= tail[10] << 16;
            nextcase;
        case 10:
            k3 ^= tail[9] << 8;
            nextcase;
        case 9:
            k3 ^= tail[8] << 0;
            k3 *= C3; k3 = rotl32(k3, 17); k3 *= C4; h3 ^= k3;
            nextcase;
        case 8:
            k2 ^= tail[7] << 24;
            nextcase;
        case 7:
            k2 ^= tail[6] << 16;
            nextcase;
        case 6:
            k2 ^= tail[5] << 8;
            nextcase;
        case 5:
            k2 ^= tail[4] << 0;
            k2 *= C2; k2 = rotl32(k2, 16); k2 *= C3; h2 ^= k2;
            nextcase;
        case 4:
            k1 ^= tail[3] << 24;
            nextcase;
        case 3:
            k1 ^= tail[2] << 16;
            nextcase;
        case 2:
            k1 ^= tail[1] << 8;
            nextcase;
        case 1:
            k1 ^= tail[0] << 0;
            k1 *= C1; k1 = rotl32(k1, 15); k1 *= C2; h1 ^= k1;
        default:
            break;
    }
    
    //----------
    // finalization
    
    h1 ^= len; h2 ^= len; h3 ^= len; h4 ^= len;
    
    h1 += h2; h1 += h3; h1 += h4;
    h2 += h1; h3 += h1; h4 += h1;
    
    h1 = fmix32(h1);
    h2 = fmix32(h2);
    h3 = fmix32(h3);
    h4 = fmix32(h4);
    
    h1 += h2; h1 += h3; h1 += h4;
    h2 += h1; h3 += h1; h4 += h1;
    
    uint128 out = h1;
    out = (out << 32) + h2;
    out = (out << 32) + h3;
    out = (out << 32) + h4;
    
    return out;
}

//-----------------------------------------------------------------------------

fn uint128 hash3_x64_128(char* key, uint len, uint seed)
{
    char* data = key;
    uint nblocks = len / 16;
    
    ulong h1 = seed;
    ulong h2 = seed;
    
    const ulong C1 = 0x87C37b91114253d5;
    const ulong C2 = 0x4cf5ad432745937f;
    
    //----------
    // body
    
    // ulong* blocks = (ulong*)data;
    
    for (uint i = 0; i < nblocks; i++)
    {
        ulong k1 = getblock64(data, i * 2 + 0);
        ulong k2 = getblock64(data, i * 2 + 1);
        
        k1 *= C1; k1 = rotl64(k1, 31); k1 *= C2; h1 ^= k1;
        h1 = rotl64(h1, 27); h1 += h2; h1 = h1 * (uint)5 + 0x52dce729;
        
        k2 *= C2; k2 = rotl64(k2, 33); k2 *= C1; h2 ^= k2;
        h2 = rotl64(h2, 31); h2 += h1; h2 = h2 * (uint)5 + 0x38495ab5;
    }
    
    //----------
    // tail
    
    char* tail = data + nblocks * 16;
    
    ulong k1 = 0;
    ulong k2 = 0;
    
    switch (len & 15)
    {
        case 15:
            k2 ^= ((ulong)tail[14]) << 48;
            nextcase;
        case 14:
            k2 ^= ((ulong)tail[13]) << 40;
            nextcase;
        case 13:
            k2 ^= ((ulong)tail[12]) << 32;
            nextcase;
        case 12:
            k2 ^= ((ulong)tail[11]) << 24;
            nextcase;
        case 11:
            k2 ^= ((ulong)tail[10]) << 16;
            nextcase;
        case 10:
            k2 ^= ((ulong)tail[9]) << 8;
            nextcase;
        case 9:
            k2 ^= ((ulong)tail[8]) << 0;
            k2 *= C2; k2 = rotl64(k2, 33); k2 *= C1; h2 ^= k2;
            nextcase;
        case 8:
            k1 ^= ((ulong)tail[7]) << 56;
            nextcase;
        case 7:
            k1 ^= ((ulong)tail[6]) << 48;
            nextcase;
        case 6:
            k1 ^= ((ulong)tail[5]) << 40;
            nextcase;
        case 5:
            k1 ^= ((ulong)tail[4]) << 32;
            nextcase;
        case 4:
            k1 ^= ((ulong)tail[3]) << 24;
            nextcase;
        case 3:
            k1 ^= ((ulong)tail[2]) << 16;
            nextcase;
        case 2:
            k1 ^= ((ulong)tail[1]) << 8;
            nextcase;
        case 1:
            k1 ^= ((ulong)tail[0]) << 0;
            k1 *= C1; k1 = rotl64(k1, 31); k1 *= C2; h1 ^= k1;
        default:
            break;
    }
    
    //----------
    // finalization
    
    h1 ^= len; h2 ^= len;
    
    h1 += h2;
    h2 += h1;
    
    h1 = fmix64(h1);
    h2 = fmix64(h2);
    
    h1 += h2;
    h2 += h1;
    
    uint128 out = h1;
    out = (out << 64) + h2;
    
    return out;
}
