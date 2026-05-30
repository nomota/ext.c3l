// citycrc.c3
//
// CityHashCrc implementation in C3 (requires SSE4.2)
// Translated from city-c
// Copyright (c) 2011-2012, Alexander Nusov
// Original copyright (c) 2011 Google, Inc.
//
// This file declares the subset of the CityHash functions that require
// _mm_mm_crc32_u64(). See the CityHash README for details.
//
// Functions in the CityHash family are not suitable for cryptography.

module ext::hash::city;

import std::io;
import libc;

fn ulong _mm_crc32_u64(ulong crc, ulong val) 
  @if($defined(env::SSE4_2)) @inline
{
  ulong result;
  asm {
    movq $rax, crc;        // move crc value to rax register
    crc32 $rax, val;       // run CRC32 command: rax = crc32(rax, val)
    movq result, $rax;     // store to result 
  }
  return result;
}

fn ulong _mm_crc32_u64(ulong crc, ulong data)
  @if(! $defined(env::SSE4_2)) @inline
{
  for (int i = 0; i < 64; i++) {
    if ((crc ^ data) & 0x80000000) {
      crc = (crc << 1) ^ 0x1EDC6F41; 
    } else {
      crc <<= 1;
    }
    data <<= 1;
  }
  return crc;
}


// Requires len >= 240
fn void hash256_crc_long(char* s, uint len, uint seed, ulong* result)
{
  ulong a = city::fetch64(s + 56) + city::K0;
  ulong b = city::fetch64(s + 96) + city::K0;
  ulong c = result[0] = city::hash_len16(b, len);
  ulong d = result[1] = city::fetch64(s + 120) * city::K0 + len;
  ulong e = city::fetch64(s + 184) + seed;
  ulong f = seed;
  ulong g = 0;
  ulong h = 0;
  ulong i = 0;
  ulong j = 0;
  ulong t = c + d;
  
  // 240 bytes of input per iter
  sz iters = len / 240;
  len -= (uint)iters * 240;
  
  while (iters > 0) {
    // Macro-like inline block repeated 6 times
    for (int chunk_idx = 0; chunk_idx < 6; chunk_idx++) {
      ulong multiplier = (chunk_idx % 2 == 0) ? 1 : city::K0;
      int z = (chunk_idx % 2 == 0) ? 1 : 0;
      
      ulong old_a = a;
      a = city::rotate(b, 41 ^ z) * multiplier + city::fetch64(s);
      b = city::rotate(c, 27 ^ z) * multiplier + city::fetch64(s + 8);
      c = city::rotate(d, 41 ^ z) * multiplier + city::fetch64(s + 16);
      d = city::rotate(e, 33 ^ z) * multiplier + city::fetch64(s + 24);
      e = city::rotate(t, 25 ^ z) * multiplier + city::fetch64(s + 32);
      t = old_a;
      
      f = _mm_crc32_u64(f, a);
      g = _mm_crc32_u64(g, b);
      h = _mm_crc32_u64(h, c);
      i = _mm_crc32_u64(i, d);
      j = _mm_crc32_u64(j, e);
      s += 40;
    }
    iters--;
  }
  
  while (len >= 40) {
    ulong old_a = a;
    a = city::rotate(b, 41) * city::K0 + city::fetch64(s);
    b = city::rotate(c, 27) * city::K0 + city::fetch64(s + 8);
    c = city::rotate(d, 41) * city::K0 + city::fetch64(s + 16);
    d = city::rotate(e, 33) * city::K0 + city::fetch64(s + 24);
    e = city::rotate(t, 25) * city::K0 + city::fetch64(s + 32);
    t = old_a;
    
    f = _mm_crc32_u64(f, a);
    g = _mm_crc32_u64(g, b);
    h = _mm_crc32_u64(h, c);
    i = _mm_crc32_u64(i, d);
    j = _mm_crc32_u64(j, e);
    s += 40;
    len -= 40;
  }
  
  if (len > 0) {
    s = s + len - 40;
    ulong old_a = a;
    a = city::rotate(b, 41) * city::K0 + city::fetch64(s);
    b = city::rotate(c, 27) * city::K0 + city::fetch64(s + 8);
    c = city::rotate(d, 41) * city::K0 + city::fetch64(s + 16);
    d = city::rotate(e, 33) * city::K0 + city::fetch64(s + 24);
    e = city::rotate(t, 25) * city::K0 + city::fetch64(s + 32);
    t = old_a;
    
    f = _mm_crc32_u64(f, a);
    g = _mm_crc32_u64(g, b);
    h = _mm_crc32_u64(h, c);
    i = _mm_crc32_u64(i, d);
    j = _mm_crc32_u64(j, e);
  }
  
  j += i << 32;
  a = city::hash_len16(a, j);
  h += g << 32;
  b += h;
  c = city::hash_len16(c, f) + i;
  d = city::hash_len16(d, e + result[0]);
  j += e;
  i += city::hash_len16(h, t);
  e = city::hash_len16(a, d) + j;
  f = city::hash_len16(b, c) + a;
  g = city::hash_len16(j, i) + c;
  result[0] = e + f + g + h;
  a = city::shift_mix((a + g) * city::K0) * city::K0 + b;
  result[1] += a + result[0];
  a = city::shift_mix(a * city::K0) * city::K0 + c;
  result[2] = a + result[1];
  a = city::shift_mix((a + e) * city::K0) * city::K0;
  result[3] = a + result[2];
}

// Requires len < 240
fn void hash256_crc_short(char* s, uint len, ulong* result)
{
  char[240] buf;
  libc::memcpy(&buf, s, len);
  libc::memset(&buf[len], 0, (sz)(240 - len));
  hash256_crc_long(&buf, 240, ~(uint)len, result);
}

fn void hash256_crc(char* s, uint len, ulong* result)
{
  if (len >= 240) {
    hash256_crc_long(s, len, 0, result);
  } else {
    hash256_crc_short(s, len, result);
  }
}

fn uint128 hash128_crc_with_seed(char* s, uint len, uint128 seed)
{
  if (len <= 900) {
    return city::hash128_with_seed(s, len, seed);
  } else {
    ulong[4] result;
    hash256_crc(s, len, &result);
    ulong u = city::uint128_high64(seed) + result[0];
    ulong v = city::uint128_low64(seed) + result[1];
    ulong first = city::hash_len16(u, v + result[2]);
    ulong second = city::hash_len16(city::rotate(v, 32), u * city::K0 + result[3]);
    return ((uint128)second << 64) | (uint128)first;
  }
}

fn uint128 hash128_crc(char* s, uint len)
{
  if (len <= 900) {
    return city::hash128(s, len);
  } else {
    ulong[4] result;
    hash256_crc(s, len, &result);
    return ((uint128)result[3] << 64) | (uint128)result[2];
  }
}
