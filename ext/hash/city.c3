// city.c3 
// 
// CityHash implementation in C3
// Translated from cityhash-c
// Copyright (c) 2011-2012, Alexander Nusov
// Original copyright (c) 2011 Google, Inc.
//
module ext::hash::city;

import std::io;
import libc;

// Type definitions
typedef Uint128 = uint128;

// Constants - some primes between 2^63 and 2^64 for various uses
const ulong K0 = 0xc3a5c85c97cb3127;
const ulong K1 = 0xb492b66fbe98f273;
const ulong K2 = 0x9ae16a3b2f90404f;
const ulong K3 = 0xc949d7c7509e6557;

// Helper macros
macro uint128_low64(x) => (ulong)(x & 0xFFFFFFFFFFFFFFFF);
macro uint128_high64(x) => (ulong)(x >> 64);

// Unaligned load functions
fn ulong unaligned_load64(char* p) @inline
{
  ulong result;
  libc::memcpy(&result, p, ulong::size);
  return result;
}

fn uint unaligned_load32(char* p) @inline
{
  uint result;
  libc::memcpy(&result, p, uint::size);
  return result;
}

// Byte order handling
// $if env::LITTLE_ENDIAN:
  macro uint32_in_expected_order(x) @if (! env::BIG_ENDIAN) => x;
  macro uint64_in_expected_order(x) @if (! env::BIG_ENDIAN) => x;
// $else
  fn uint bswap_32(uint x) @if (env::BIG_ENDIAN) @inline
  {
    return ((x & 0x000000FF) << 24) |
         ((x & 0x0000FF00) << 8) |
         ((x & 0x00FF0000) >> 8) |
         ((x & 0xFF000000) >> 24);
  }
  
  fn ulong bswap_64(ulong x) @if (env::BIG_ENDIAN) @inline
  {
    return ((x & 0x00000000000000FF) << 56) |
         ((x & 0x000000000000FF00) << 40) |
         ((x & 0x0000000000FF0000) << 24) |
         ((x & 0x00000000FF000000) << 8) |
         ((x & 0x000000FF00000000) >> 8) |
         ((x & 0x0000FF0000000000) >> 24) |
         ((x & 0x00FF000000000000) >> 40) |
         ((x & 0xFF00000000000000) >> 56);
  }
  
  macro uint32_in_expected_order(x) @if (env::BIG_ENDIAN) => bswap_32(x);
  macro uint64_in_expected_order(x) @if (env::BIG_ENDIAN) => bswap_64(x);
// $endif

fn ulong fetch64(char* p) @inline
{
  return uint64_in_expected_order(unaligned_load64(p));
}

fn uint fetch32(char* p) @inline
{
  return uint32_in_expected_order(unaligned_load32(p));
}

// Hash 128 input bits down to 64 bits of output
fn ulong hash128to64(uint128 x) @inline
{
  const ulong K_MUL = 0x9ddfea08eb382d69;
  ulong a = (uint128_low64(x) ^ uint128_high64(x)) * K_MUL;
  a ^= (a >> 47);
  ulong b = (uint128_high64(x) ^ a) * K_MUL;
  b ^= (b >> 47);
  b *= K_MUL;
  return b;
}

// Bitwise right rotate
fn ulong rotate(ulong val, int shift) @inline
{
  return shift == 0 ? val : ((val >> shift) | (val << (64 - shift)));
}

// Equivalent to rotate(), but requires the second arg to be non-zero
fn ulong rotate_by_at_least_1(ulong val, int shift) @inline
{
  return (val >> shift) | (val << (64 - shift));
}

fn ulong shift_mix(ulong val) @inline
{
  return val ^ (val >> 47);
}

fn ulong hash_len16(ulong u, ulong v) @inline
{
  uint128 result = ((uint128)v << 64) | (uint128)u;
  return hash128to64(result);
}

fn ulong hash_len0to16(char* s, uint len)
{
  if (len > 8) {
    ulong a = fetch64(s);
    ulong b = fetch64(s + len - 8);
    return hash_len16(a, rotate_by_at_least_1(b + len, (int)len)) ^ b;
  }
  if (len >= 4) {
    ulong a = fetch32(s);
    return hash_len16(len + (a << 3), fetch32(s + len - 4));
  }
  if (len > 0) {
    char a = s[0];
    char b = s[len >> 1];
    char c = s[len - 1];
    uint y = (uint)a + ((uint)b << 8);
    uint z = (uint)len + ((uint)c << 2);
    return shift_mix(y * K2 ^ z * K3) * K2;
  }
  return K2;
}

fn ulong hash_len17to32(char* s, uint len)
{
  ulong a = fetch64(s) * K1;
  ulong b = fetch64(s + 8);
  ulong c = fetch64(s + len - 8) * K2;
  ulong d = fetch64(s + len - 16) * K0;
  return hash_len16(rotate(a - b, 43) + rotate(c, 30) + d,
            a + rotate(b ^ K3, 20) - c + len);
}

// Return a 16-byte hash for 48 bytes. Quick and dirty.
fn uint128 weak_hash_len32_with_seeds6(ulong w, ulong x, ulong y, ulong z, ulong a, ulong b)
{
  a += w;
  b = rotate(b + a + z, 21);
  ulong c = a;
  a += x;
  a += y;
  b += rotate(a, 44);
  
  ulong first = a + z;
  ulong second = b + c;
  return ((uint128)second << 64) | (uint128)first;
}

// Return a 16-byte hash for s[0] ... s[31], a, and b. Quick and dirty.
fn uint128 weak_hash_len32_with_seeds(char* s, ulong a, ulong b)
{
  return weak_hash_len32_with_seeds6(fetch64(s),
                     fetch64(s + 8),
                     fetch64(s + 16),
                     fetch64(s + 24),
                     a, b);
}

// Return an 8-byte hash for 33 to 64 bytes
fn ulong hash_len33to64(char* s, uint len)
{
  ulong z = fetch64(s + 24);
  ulong a = fetch64(s) + (len + fetch64(s + len - 16)) * K0;
  ulong b = rotate(a + z, 52);
  ulong c = rotate(a, 37);
  a += fetch64(s + 8);
  c += rotate(a, 7);
  a += fetch64(s + 16);
  ulong vf = a + z;
  ulong vs = b + rotate(a, 31) + c;
  a = fetch64(s + 16) + fetch64(s + len - 32);
  z = fetch64(s + len - 8);
  b = rotate(a + z, 52);
  c = rotate(a, 37);
  a += fetch64(s + len - 24);
  c += rotate(a, 7);
  a += fetch64(s + len - 16);
  ulong wf = a + z;
  ulong ws = b + rotate(a, 31) + c;
  ulong r = shift_mix((vf + ws) * K2 + (wf + vs) * K0);
  return shift_mix(r * K0 + vs) * K2;
}

// Main CityHash64 function
fn ulong hash64(char* s, uint len)
{
  if (len <= 32) {
    if (len <= 16) {
      return hash_len0to16(s, len);
    } else {
      return hash_len17to32(s, len);
    }
  } else if (len <= 64) {
    return hash_len33to64(s, len);
  }
  
  // For strings over 64 bytes we hash the end first, and then as we
  // loop we keep 56 bytes of state: v, w, x, y, and z.
  ulong x = fetch64(s + len - 40);
  ulong y = fetch64(s + len - 16) + fetch64(s + len - 56);
  ulong z = hash_len16(fetch64(s + len - 48) + len, fetch64(s + len - 24));
  uint128 v = weak_hash_len32_with_seeds(s + len - 64, len, z);
  uint128 w = weak_hash_len32_with_seeds(s + len - 32, y + K1, x);
  x = x * K1 + fetch64(s);
  
  // Decrease len to the nearest multiple of 64, and operate on 64-byte chunks
  len = (len - 1) & (uint)~63;
  do {
    x = rotate(x + y + uint128_low64(v) + fetch64(s + 8), 37) * K1;
    y = rotate(y + uint128_high64(v) + fetch64(s + 48), 42) * K1;
    x ^= uint128_high64(w);
    y += uint128_low64(v) + fetch64(s + 40);
    z = rotate(z + uint128_low64(w), 33) * K1;
    v = weak_hash_len32_with_seeds(s, uint128_high64(v) * K1, x + uint128_low64(w));
    w = weak_hash_len32_with_seeds(s + 32, z + uint128_high64(w), y + fetch64(s + 16));
    
    // Swap z and x
    ulong temp = z;
    z = x;
    x = temp;
    
    s += 64;
    len -= 64;
  } while (len != 0);
  
  return hash_len16(hash_len16(uint128_low64(v), uint128_low64(w)) + shift_mix(y) * K1 + z,
            hash_len16(uint128_high64(v), uint128_high64(w)) + x);
}

fn ulong hash64_with_seed(char* s, uint len, ulong seed)
{
  return hash64_with_seeds(s, len, K2, seed);
}

fn ulong hash64_with_seeds(char* s, uint len, ulong seed0, ulong seed1)
{
  return hash_len16(hash64(s, len) - seed0, seed1);
}

// A subroutine for CityHash128(). Returns a decent 128-bit hash for strings
// of any length representable in signed long. Based on City and Murmur.
fn uint128 city_murmur(char* s, uint len, uint128 seed)
{
  ulong a = uint128_low64(seed);
  ulong b = uint128_high64(seed);
  ulong c = 0;
  ulong d = 0;
  long l = (long)len - 16;
  
  if (l <= 0) {  // len <= 16
    a = shift_mix(a * K1) * K1;
    c = b * K1 + hash_len0to16(s, len);
    d = shift_mix(a + (len >= 8 ? fetch64(s) : c));
  } else {  // len > 16
    c = hash_len16(fetch64(s + len - 8) + K1, a);
    d = hash_len16(b + len, c + fetch64(s + len - 16));
    a += d;
    do {
      a ^= shift_mix(fetch64(s) * K1) * K1;
      a *= K1;
      b ^= a;
      c ^= shift_mix(fetch64(s + 8) * K1) * K1;
      c *= K1;
      d ^= c;
      s += 16;
      l -= 16;
    } while (l > 0);
  }
  
  a = hash_len16(a, c);
  b = hash_len16(d, b);
  
  ulong first = a ^ b;
  ulong second = hash_len16(b, a);
  return ((uint128)second << 64) | (uint128)first;
}

fn uint128 hash128_with_seed(char* s, uint len, uint128 seed)
{
  if (len < 128) {
    return city_murmur(s, len, seed);
  }
  
  // We expect len >= 128 to be the common case. Keep 56 bytes of state:
  // v, w, x, y, and z.
  uint128 v, w;
  ulong x = uint128_low64(seed);
  ulong y = uint128_high64(seed);
  ulong z = len * K1;
  
  ulong vf = rotate(y ^ K1, 49) * K1 + fetch64(s);
  ulong vs = rotate(vf, 42) * K1 + fetch64(s + 8);
  v = ((uint128)vs << 64) | (uint128)vf;
  
  ulong wf = rotate(y + z, 35) * K1 + x;
  ulong ws = rotate(x + fetch64(s + 88), 53) * K1;
  w = ((uint128)ws << 64) | (uint128)wf;
  
  // This is the same inner loop as CityHash64(), manually unrolled
  do {
    x = rotate(x + y + uint128_low64(v) + fetch64(s + 8), 37) * K1;
    y = rotate(y + uint128_high64(v) + fetch64(s + 48), 42) * K1;
    x ^= uint128_high64(w);
    y += uint128_low64(v) + fetch64(s + 40);
    z = rotate(z + uint128_low64(w), 33) * K1;
    v = weak_hash_len32_with_seeds(s, uint128_high64(v) * K1, x + uint128_low64(w));
    w = weak_hash_len32_with_seeds(s + 32, z + uint128_high64(w), y + fetch64(s + 16));
    
    ulong temp = z;
    z = x;
    x = temp;
    s += 64;
    
    x = rotate(x + y + uint128_low64(v) + fetch64(s + 8), 37) * K1;
    y = rotate(y + uint128_high64(v) + fetch64(s + 48), 42) * K1;
    x ^= uint128_high64(w);
    y += uint128_low64(v) + fetch64(s + 40);
    z = rotate(z + uint128_low64(w), 33) * K1;
    v = weak_hash_len32_with_seeds(s, uint128_high64(v) * K1, x + uint128_low64(w));
    w = weak_hash_len32_with_seeds(s + 32, z + uint128_high64(w), y + fetch64(s + 16));
    
    temp = z;
    z = x;
    x = temp;
    s += 64;
    len -= 128;
  } while (len >= 128);
  
  x += rotate(uint128_low64(v) + z, 49) * K0;
  z += rotate(uint128_low64(w), 37) * K0;
  
  // If 0 < len < 128, hash up to 4 chunks of 32 bytes each from the end of s
  sz tail_done = 0;
  while (tail_done < len) {
    tail_done += 32;
    y = rotate(x + y, 42) * K0 + uint128_high64(v);
    
    ulong wf_new = uint128_low64(w) + fetch64(s + len - tail_done + 16);
    w = ((uint128)uint128_high64(w) << 64) | (uint128)wf_new;
    
    x = x * K0 + uint128_low64(w);
    z += uint128_high64(w) + fetch64(s + len - tail_done);
    
    ulong ws_new = uint128_high64(w) + uint128_low64(v);
    w = ((uint128)ws_new << 64) | (uint128)uint128_low64(w);
    
    v = weak_hash_len32_with_seeds(s + len - tail_done, uint128_low64(v) + z, uint128_high64(v));
  }
  
  // At this point our 56 bytes of state should contain more than
  // enough information for a strong 128-bit hash. We use two
  // different 56-byte-to-8-byte hashes to get a 16-byte final result.
  x = hash_len16(x, uint128_low64(v));
  y = hash_len16(y + z, uint128_low64(w));
  
  ulong first = hash_len16(x + uint128_high64(v), uint128_high64(w)) + y;
  ulong second = hash_len16(x + uint128_high64(w), y + uint128_high64(v));
  return ((uint128)second << 64) | (uint128)first;
}

fn uint128 hash128(char* s, uint len)
{
  if (len >= 16) {
    ulong first = fetch64(s) ^ K3;
    ulong second = fetch64(s + 8);
    uint128 r = ((uint128)second << 64) | (uint128)first;
    return hash128_with_seed(s + 16, len - 16, r);
  } else if (len >= 8) {
    ulong first = fetch64(s) ^ (len * K0);
    ulong second = fetch64(s + len - 8) ^ K1;
    uint128 r = ((uint128)second << 64) | (uint128)first;
    return hash128_with_seed(null, 0, r);
  } else {
    uint128 r = ((uint128)K1 << 64) | (uint128)K0;
    return hash128_with_seed(s, len, r);
  }
}

