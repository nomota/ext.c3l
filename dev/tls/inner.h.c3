// inner.h.c3

// Internal implementation header — not part of the public API.
// All structures, functions, and constants here are used by 
// internals.

// Sections:
//   1.  Size constants (RSA, EC)
//   2.  Platform detection notes
//   3.  Encode / decode inline functions (16/32/64-bit, LE/BE)
//   4.  Range encode / decode (extern fn)
//   5.  Constant-time primitives (inline)
//   6.  Hash support (IVs, round functions, digest helpers)
//   7.  i32 big-integer functions
//   8.  i31 big-integer functions
//   9.  i15 big-integer functions
//  10.  i62 / modpow opt type
//  11.  Digest utilities
//  12.  DES support
//  13.  AES support (big, small, ct, ct64, x86ni, pwr8)
//  14.  RSA padding / unpadding
//  15.  EC curve definitions
//  16.  ASN.1 support
//  17.  SSL/TLS internal constants and engine functions
//
// NOTE: The PowerPC assembly macros section and the compiler-intrinsics
// activation section from the original inner.h are omitted; they are
// C preprocessor / inline-assembly constructs with no direct C3 equivalent.

module ext::net::tls;

import string; // libc

// ============================================================================
// 1. Size Constants
// ============================================================================

<*
  Maximum RSA modulus size in bits.
  Stack buffer allocations depend on this value. Must be a multiple of 64.
  Must not exceed 47666. Sizes beyond 3072 bits are rarely useful, but
  RSA-4096 root keys exist in widespread PKI deployments.
*>
const MAX_RSA_SIZE   = 4096;

<*
  Minimum RSA modulus size in bits.
  Used only to reject obviously invalid key-generation parameters.
  Applications should normally use at least 2048 bits.
*>
const MIN_RSA_SIZE   = 512;

<*
  Maximum RSA factor (prime) size in bits, for private-key operations.
  Approximately half the maximum modulus size. Must be a multiple of 32.
*>
const MAX_RSA_FACTOR = (MAX_RSA_SIZE + 64) >> 1;   // 2080

<*
  Maximum elliptic-curve modulus / order size in bits.
  Stack buffer sizes depend on this value. Must be a multiple of 8.
*>
const MAX_EC_SIZE    = 528;

// ============================================================================
// 2. Platform Detection Notes
//
// The original inner.h detects the following at compile time using C macros:
//
//   BR_64          — 64-bit integer types are efficient on this platform.
//   BR_LOMUL       — Use low-multiplication strategy (e.g. Cortex-M).
//   BR_i386 / BR_amd64 — x86 architecture variants.
//   BR_GCC / BR_CLANG / BR_MSC — Compiler brand / version thresholds.
//   BR_AES_X86NI   — AES-NI instructions available.
//   BR_SSE2        — SSE2 instructions available.
//   BR_RDRAND      — RDRAND instruction available.
//   BR_USE_URANDOM / BR_USE_GETENTROPY / BR_USE_WIN32_RAND — RNG source.
//   BR_POWER8 / BR_POWER8_LE / BR_POWER8_BE — POWER8 crypto / endianness.
//   BR_INT128 / BR_UMUL128 — 128-bit integer or multiply support.
//   BR_LE_UNALIGNED / BR_BE_UNALIGNED — Unaligned memory access support.
//   BR_USE_UNIX_TIME / BR_USE_WIN32_TIME — OS time source.
//
// In C3 these are handled via the @if(env::...) conditional compilation
// mechanism or via dedicated platform modules. The inline functions below
// implement the portable (non-unaligned) fallback paths; platform-optimised
// paths can be substituted by wrapping them in @if blocks as needed.
// ============================================================================

// ============================================================================
// 3. Encode / Decode Inline Functions
//
// Portable implementations of 16-bit, 32-bit, and 64-bit integer encoding
// and decoding in little-endian and big-endian byte order.
// These operate on raw byte buffers via pointer arithmetic.
// ============================================================================

<* Write a 16-bit value in little-endian byte order into dst. *>
fn void enc16le(void* dst, uint x) @inline
{
    char* buf = (char*)dst;
    buf[0] = (char)x;
    buf[1] = (char)(x >> 8);
}

<* Write a 16-bit value in big-endian byte order into dst. *>
fn void enc16be(void* dst, uint x) @inline
{
    char* buf = (char*)dst;
    buf[0] = (char)(x >> 8);
    buf[1] = (char)x;
}

<* Read a 16-bit value in little-endian byte order from src. *>
fn uint dec16le(void* src) @inline
{
    char* buf = (char*)src;
    return (uint)(char)buf[0] | ((uint)(char)buf[1] << 8);
}

<* Read a 16-bit value in big-endian byte order from src. *>
fn uint dec16be(void* src) @inline
{
    char* buf = (char*)src;
    return ((uint)(char)buf[0] << 8) | (uint)(char)buf[1];
}

<* Write a 32-bit value in little-endian byte order into dst. *>
fn void enc32le(void* dst, uint x) @inline
{
    char* buf = (char*)dst;
    buf[0] = (char)x;
    buf[1] = (char)(x >> 8);
    buf[2] = (char)(x >> 16);
    buf[3] = (char)(x >> 24);
}

<* Write a 32-bit value in big-endian byte order into dst. *>
fn void enc32be(void* dst, uint x) @inline
{
    char* buf = (char*)dst;
    buf[0] = (char)(x >> 24);
    buf[1] = (char)(x >> 16);
    buf[2] = (char)(x >> 8);
    buf[3] = (char)x;
}

<* Read a 32-bit value in little-endian byte order from src. *>
fn uint dec32le(void* src) @inline
{
    char* buf = (char*)src;
    return (uint)(char)buf[0]
        | ((uint)(char)buf[1] << 8)
        | ((uint)(char)buf[2] << 16)
        | ((uint)(char)buf[3] << 24);
}

<* Read a 32-bit value in big-endian byte order from src. *>
fn uint dec32be(void* src) @inline
{
    char* buf = (char*)src;
    return ((uint)(char)buf[0] << 24)
        | ((uint)(char)buf[1] << 16)
        | ((uint)(char)buf[2] << 8)
        | (uint)(char)buf[3];
}

<* Write a 64-bit value in little-endian byte order into dst. *>
fn void enc64le(void* dst, ulong x) @inline
{
    char* buf = (char*)dst;
    enc32le(buf,     (uint)x);
    enc32le(buf + 4, (uint)(x >> 32));
}

<* Write a 64-bit value in big-endian byte order into dst. *>
fn void enc64be(void* dst, ulong x) @inline
{
    char* buf = (char*)dst;
    enc32be(buf,     (uint)(x >> 32));
    enc32be(buf + 4, (uint)x);
}

<* Read a 64-bit value in little-endian byte order from src. *>
fn ulong dec64le(void* src) @inline
{
    char* buf = (char*)src;
    return (ulong)dec32le(buf)
        | ((ulong)dec32le(buf + 4) << 32);
}

<* Read a 64-bit value in big-endian byte order from src. *>
fn ulong dec64be(void* src) @inline
{
    char* buf = (char*)src;
    return ((ulong)dec32be(buf) << 32)
        | (ulong)dec32be(buf + 4);
}

<*
  Byte-swap a 32-bit integer.
  Reverses the byte order: 0xAABBCCDD → 0xDDCCBBAA.
*>
fn uint swap32(uint x) @inline
{
    x = ((x & 0x00FF00FF) << 8) | ((x >> 8) & 0x00FF00FF);
    return (x << 16) | (x >> 16);
}

// ============================================================================
// 4. Range Encode / Decode (extern fn)
//
// Process arrays of successive 16-bit, 32-bit, or 64-bit values.
// ============================================================================

extern fn void range_dec16le(ushort* v, sz num, void* src);
extern fn void range_dec16be(ushort* v, sz num, void* src);
extern fn void range_enc16le(void* dst, ushort* v, sz num);
extern fn void range_enc16be(void* dst, ushort* v, sz num);

extern fn void range_dec32le(uint* v, sz num, void* src);
extern fn void range_dec32be(uint* v, sz num, void* src);
extern fn void range_enc32le(void* dst, uint* v, sz num);
extern fn void range_enc32be(void* dst, uint* v, sz num);

extern fn void range_dec64le(ulong* v, sz num, void* src);
extern fn void range_dec64be(ulong* v, sz num, void* src);
extern fn void range_enc64le(void* dst, ulong* v, sz num);
extern fn void range_enc64be(void* dst, ulong* v, sz num);

// ============================================================================
// 5. Constant-Time Primitives
//
// All operate on 32-bit unsigned values. Boolean "ctl" arguments MUST be
// exactly 0 or 1 — no other value is valid.
//
// These functions are designed to execute in constant time regardless of
// input values, preventing timing side-channel attacks.
//
// Signed-operand variants (EQ0, GT0, GE0, LT0, LE0, CMP) accept int
// arguments; callers must be careful with signed overflow semantics.
// ============================================================================

<* Negate a boolean: returns 1 if ctl == 0, returns 0 if ctl == 1. *>
fn uint ct_not(uint ctl) @inline => ctl ^ 1;

<*
  Constant-time multiplexer.
  Returns x if ctl == 1, y if ctl == 0. No branching on ctl.
*>
fn uint ct_mux(uint ctl, uint x, uint y) @inline => y ^ (-(ctl) & (x ^ y));

<*
  Constant-time equality test.
  Returns 1 if x == y, 0 otherwise.
*>
fn uint ct_eq(uint x, uint y) @inline
{
    uint q = x ^ y;
    return ct_not((q | -(q)) >> 31);
}

<*
  Constant-time inequality test.
  Returns 1 if x != y, 0 otherwise.
*>
fn uint ct_neq(uint x, uint y) @inline
{
    uint q = x ^ y;
    return (q | -(q)) >> 31;
}

<*
  Constant-time unsigned greater-than.
  Returns 1 if x > y, 0 otherwise.
*>
fn uint ct_gt(uint x, uint y) @inline
{
    uint z = y - x;
    return (z ^ ((x ^ y) & (x ^ z))) >> 31;
}

<* Constant-time: returns 1 if x >= y (unsigned), 0 otherwise. *>
macro uint ct_ge(uint x, uint y) => ct_not(ct_gt(y, x));

<* Constant-time: returns 1 if x < y (unsigned), 0 otherwise. *>
macro uint ct_lt(uint x, uint y) => ct_gt(y, x);

<* Constant-time: returns 1 if x <= y (unsigned), 0 otherwise. *>
macro uint ct_le(uint x, uint y) => ct_not(ct_gt(x, y));

<*
  Constant-time signed comparison.
  Returns -1 if x < y, 0 if x == y, +1 if x > y (treating inputs as
  unsigned values interpreted as 32-bit unsigned integers).
*>
fn int ct_cmp(uint x, uint y) @inline
{
    return (int)ct_gt(x, y) | -(int)ct_gt(y, x);
}

<*
  Returns 1 if x == 0 (signed), 0 otherwise.
  Operand is signed (int); use care with signed overflow.
*>
fn uint ct_eq0(int x) @inline
{
    uint q = (uint)x;
    return ~(q | -(q)) >> 31;
}

<*
  Returns 1 if x > 0 (signed), 0 otherwise.
  High bit of -x is 0 when x == 0, 1 when x > 0.
*>
fn uint ct_gt0(int x) @inline
{
    uint q = (uint)x;
    return (~q & -(q)) >> 31;
}

<* Returns 1 if x >= 0 (signed), 0 otherwise. *>
fn uint ct_ge0(int x) @inline => ~(uint)x >> 31;

<* Returns 1 if x < 0 (signed), 0 otherwise. *>
fn uint ct_lt0(int x) @inline => (uint)x >> 31;

<*
  Returns 1 if x <= 0 (signed), 0 otherwise.
  Handles the special case x == INT_MIN via the OR with x itself.
*>
fn uint ct_le0(int x) @inline
{
    uint q = (uint)x;
    return (q | ~-(q)) >> 31;
}

<*
  Conditional copy.
  Copies src into dst (len bytes) if and only if ctl == 1.
  dst and src may overlap completely but not partially.
*>
extern fn void ccopy(uint ctl, void* dst, void* src, sz len);

<*
  Compute the bit length of a 32-bit integer.
  Returns a value in [0, 32]. Constant-time with respect to x.
*>
fn uint bit_length(uint x) @inline
{
    uint k = ct_neq(x, 0);
    uint c;
    c = ct_gt(x, 0xFFFF); x = ct_mux(c, x >> 16, x); k += c << 4;
    c = ct_gt(x, 0x00FF); x = ct_mux(c, x >>  8, x); k += c << 3;
    c = ct_gt(x, 0x000F); x = ct_mux(c, x >>  4, x); k += c << 2;
    c = ct_gt(x, 0x0003); x = ct_mux(c, x >>  2, x); k += c << 1;
    k += ct_gt(x, 0x0001);
    return k;
}

<* Constant-time minimum of two unsigned 32-bit values. *>
fn uint ct_min(uint x, uint y) @inline => ct_mux(ct_gt(x, y), y, x);

<* Constant-time maximum of two unsigned 32-bit values. *>
fn uint ct_max(uint x, uint y) @inline => ct_mux(ct_gt(x, y), x, y);

<*
  Multiply two 32-bit integers producing a 64-bit result.
  macro MUL(x, y) — assumes the basic multiply is constant-time.
*>
macro ulong ct_mul(uint x, uint y) => (ulong)x * (ulong)y;

<*
  Multiply two 31-bit integers producing a 62-bit result.
  macro MUL31(x, y) — standard version.
  The low 31 bits can be obtained via ct_mul31_lo().
*>
macro ulong ct_mul31(uint x, uint y) => (ulong)x * (ulong)y;

<* Return the low 31 bits of the product of two 31-bit integers. *>
macro uint ct_mul31_lo(uint x, uint y) => ((uint)x * (uint)y) & 0x7FFFFFFF;

<*
  Multiply two words whose combined bit-lengths do not exceed 31 bits.
  macro MUL15(x, y) — standard version.
*>
macro uint ct_mul15(uint x, uint y) => (uint)x * (uint)y;

<*
  Arithmetic right shift: propagates the sign bit into vacated positions.
  C3 right-shift of signed integers is arithmetic on all supported targets.
*>
macro int ct_arsh(int x, uint n) => x >> n;

<*
  Constant-time division.
  Divides the 64-bit value hi:lo by d (where hi < d). Stores the
  remainder in *r and returns the (possibly truncated) quotient.
  If hi == d, the quotient does not fit in 32 bits and the returned
  value is truncated. hi > d yields indeterminate results.
*>
extern fn uint divrem(uint hi, uint lo, uint d, uint* r);

<* Return the remainder of hi:lo divided by d (quotient discarded). *>
fn uint i_rem(uint hi, uint lo, uint d) @inline
{
    uint r;
    divrem(hi, lo, d, &r);
    return r;
}

<* Return the quotient of hi:lo divided by d (remainder discarded). *>
fn uint i_div(uint hi, uint lo, uint d) @inline
{
    uint r;
    return divrem(hi, lo, d, &r);
}

// ============================================================================
// 6. Hash Support
// ============================================================================

<* Initialisation vector for MD5. *>
extern uint[*] md5_iv;

<* Initialisation vector for SHA-1. *>
extern uint[*] sha1_iv;

<* Initialisation vector for SHA-224. *>
extern uint[*] sha224_iv;

<* Initialisation vector for SHA-256. *>
extern uint[*] sha256_iv;

<* MD5 compression round (one 64-byte block). *>
extern fn void md5_round(char* buf, uint* val);

<* SHA-1 compression round (one 64-byte block). *>
extern fn void sha1_round(char* buf, uint* val);

<*
  SHA-224 / SHA-256 compression round (both use the same function).
  Processes one 64-byte block.
*>
extern fn void sha2small_round(char* buf, uint* val);

<*
  Core TLS P_hash function.
  Computes P_hash(secret, label || seed) and XORs the result into dst.
  Used by the TLS PRF implementations in prf.h.c3.
*>
extern fn void tls_phash(void* dst, sz len,
    HashClass* dig,
    void* secret, sz secret_len, char* label,
    sz seed_num, TLSPRFSeedChunk* seed);

<*
  Copy all configured hash implementations from one multihash context
  to another. Copies only the impl[] array of vtable pointers.
*>
fn void multihash_copyimpl(MultihashContext* dst, MultihashContext* src) @inline
{
    sz n = MultihashContext.impl::size;
    char* d = (char*)&dst.impl;
    char* s = (char*)&src.impl;
    for (sz i = 0; i < n; i++) d[i] = s[i];
}

<*
  Get the output size (in bytes) of a hash function from its vtable.
  Uses the HASHDESC_OUT fields encoded in HashClass.desc.
*>
fn sz digest_size(HashClass* digest_class) @inline
{
    return (sz)(digest_class.desc >> HASHDESC_OUT_OFF) & HASHDESC_OUT_MASK;
}

<*
  Get the output size (in bytes) of a hash function identified by ID.
  Returns 0 for unknown IDs.
*>
extern fn sz digest_size_by_id(int digest_id);

<*
  Get the DER-encoded OID (without tag and length) for a hash function.
  The first byte of the returned buffer is the number of subsequent bytes.
  Returns null and sets *len to 0 for unsupported or zero digest IDs.
*>
extern fn char* digest_oid(int digest_id, sz* len);

// ============================================================================
// 7. i32 — Big Integer Functions (32-bit word representation)
//
// Representation: x[0] = announced bit length; x[1], x[2], ... = value
// words in little-endian order (x[1] = least significant 32 bits).
// Unused bits in the last word are zero; subsequent words are uninitialised.
// All timing depends only on announced bit lengths, not on word values.
// ============================================================================

<*
  Compute the actual bit length of an i32 integer.
  x points to the first (least significant) value word; xlen is the
  number of 32-bit words to examine.
  CT: value or length of x does not leak.
*>
extern fn uint i32_bit_length(uint* x, sz xlen);

<*
  Decode an i32 integer from big-endian unsigned representation.
  The true bit length is computed and stored in x[0], but all words
  covering the full len source bytes are written.
  CT: value or length of x does not leak.
*>
extern fn void i32_decode(uint* x, void* src, sz len);

<*
  Decode an i32 integer from big-endian unsigned representation and
  verify it is less than the modulus m[].
  Returns 1 if the value fits within m[], 0 otherwise (x[] is zeroed,
  but its announced bit length matches m[]).
  CT: value, length, and fit-check result do not leak.
*>
extern fn uint i32_decode_mod(uint* x, void* src, sz len, uint* m);

<*
  Reduce a[] modulo m[], writing the result into x[].
  x[] announced bit length is set to match m[].
  x[] MUST be distinct from both a[] and m[].
  CT: only announced bit lengths leak.
*>
extern fn void i32_reduce(uint* x, uint* a, uint* m);

<*
  Decode and reduce: decode src into x[] modulo m[].
  Announced bit length of x[] matches m[].
  x[] MUST be distinct from m[].
*>
extern fn void i32_decode_reduce(uint* x, void* src, sz len, uint* m);

<*
  Encode an i32 integer into big-endian unsigned representation.
  If len is shorter than the integer, it is truncated.
  If len is longer, extra leading bytes are zero-filled.
*>
extern fn void i32_encode(void* dst, sz len, uint* x);

<*
  Multiply x[] by 2^32, add z, and reduce modulo m[].
  x[] and m[] must have the same announced bit length, which matches
  the true bit length of m[].
  x[] and m[] MUST be distinct. CT: only the common bit length leaks.
*>
extern fn void i32_muladd_small(uint* x, uint z, uint* m);

<*
  Extract a 32-bit window from i32 integer a[] starting at bit offset off.
  The requested window MUST lie entirely within the announced bit length.
*>
fn uint i32_word(uint* a, uint off) @inline
{
    sz  u = (sz)(off >> 5) + 1;
    uint j = off & 31;
    if (j == 0) {
        return a[u];
    } else {
        return (a[u] >> j) | (a[u + 1] << (32 - j));
    }
}

<* Returns 1 if i32 integer x[] is zero, 0 otherwise. *>
extern fn uint i32_szero(uint* x);

<*
  Add b[] to a[]; return carry (0 or 1).
  If ctl == 0, a[] is not modified but carry is still computed.
  a[] and b[] must have the same announced bit length.
  May alias completely, but not partially.
*>
extern fn uint i32_add(uint* a, uint* b, uint ctl);

<*
  Subtract b[] from a[]; return borrow (0 or 1).
  If ctl == 0, a[] is not modified but borrow is still computed.
  a[] and b[] must have the same announced bit length.
  May alias completely, but not partially.
*>
extern fn uint i32_sub(uint* a, uint* b, uint ctl);

<*
  Compute d[] += a[] * b[].
  d[] announced bit length must initially match a[].
  d[] must be large enough for the full result (may need one extra word).
  Resulting announced bit length of d[] = sum of bit lengths of a[] and b[].
  a[] and b[] may alias. d[] must be disjoint from both.
*>
extern fn void i32_mulacc(uint* d, uint* a, uint* b);

<*
  Zeroize an i32 integer: set x[0] = bit_len and zero all value words.
*>
fn void i32_zero(uint* x, uint bit_len) @inline
{
    *x++ = bit_len;
    sz words = (sz)((bit_len + 31) >> 5);
    string::memset(x, 0, words*4);
    //for (sz i = 0; i < words; i++) x[i] = 0;
}

<*
  Compute -(1/x) mod 2^32. Returns 0 if x is even.
  Used to derive the Montgomery parameter m0i.
*>
extern fn uint i32_ninv32(uint x);

<* Convert x[] to Montgomery representation modulo m[]. x[] < m[]. *>
extern fn void i32_to_monty(uint* x, uint* m);

<*
  Convert x[] back from Montgomery representation modulo m[].
  m0i = -(1/m[1]) mod 2^32 (m[] must be odd).
*>
extern fn void i32_from_monty(uint* x, uint* m, uint m0i);

<*
  Montgomery multiplication: d[] = x[] * y[] / R mod m[].
  d[] must be distinct from x[], y[], and m[].
  x[] and y[] must be < m[]; they may alias.
  m0i = -(1/m[1]) mod 2^32.
*>
extern fn void i32_montymul(uint* d, uint* x, uint* y, uint* m, uint m0i);

<*
  Modular exponentiation: x[] = x[]^e mod m[].
  x[] is an integer modulo m[] (same announced bit length, lower value).
  m[] must be odd. e is big-endian, elen bytes.
  m0i = -(1/m[1]) mod 2^32.
  t1[] and t2[] are temporary arrays, each sized to hold an integer as
  large as m[].
*>
extern fn void i32_modpow(uint* x, char* e, sz elen,
    uint* m, uint m0i, uint* t1, uint* t2);

// ============================================================================
// 8. i31 — Big Integer Functions (31-bit word representation)
//
// Representation: x[0] encodes both array length and announced bit length k
// as ((k / 31) << 5) + (k % 31). x[1], x[2], ... hold 31 value bits each
// (upper bit of each word is always 0), little-endian.
// All timing depends only on announced bit lengths, not on word values.
// ============================================================================

<* Returns 1 if i31 integer x[] is zero, 0 otherwise. *>
extern fn uint i31_szero(uint* x);

<*
  Add b[] to a[]; return carry (0 or 1).
  If ctl == 0, a[] is not modified but carry is still computed.
  Same announced bit length required. May alias completely, not partially.
*>
extern fn uint i31_add(uint* a, uint* b, uint ctl);

<*
  Subtract b[] from a[]; return borrow (0 or 1).
  If ctl == 0, a[] is not modified but borrow is still computed.
  Same announced bit length required. May alias completely, not partially.
*>
extern fn uint i31_sub(uint* a, uint* b, uint ctl);

<*
  Compute the ENCODED actual bit length of an i31 integer.
  x points to the first value word; xlen is the number of words.
  Upper bit of each value word MUST be 0.
  Returns ((k / 31) << 5) + (k % 31) where k is the true bit length.
  CT: value or length of x does not leak.
*>
extern fn uint i31_bit_length(uint* x, sz xlen);

<*
  Decode an i31 integer from big-endian unsigned representation.
  True bit length is computed and stored (encoded) in x[0].
  CT: value or length of x does not leak.
*>
extern fn void i31_decode(uint* x, void* src, sz len);

<*
  Decode an i31 integer and verify it is less than m[].
  Returns 1 if the value fits, 0 otherwise (x[] zeroed with m[]'s bit length).
  CT: value, length, and fit-check result do not leak.
*>
extern fn uint i31_decode_mod(uint* x, void* src, sz len, uint* m);

<*
  Zeroize an i31 integer. bit_len is the ENCODED bit length value.
*>
fn void i31_zero(uint* x, uint bit_len) @inline
{
    *x++ = bit_len;
    sz words = (sz)((bit_len + 31) >> 5);
    string::memset(x, 0, words*4);
    //for (sz i = 0; i < words; i++) x[i] = 0;
}

<*
  Right-shift an i31 integer by count bits. count must be < 31.
*>
extern fn void i31_rshift(uint* x, int count);

<*
  Reduce a[] modulo m[], writing result into x[].
  x[] announced bit length matches m[]. x[] MUST be distinct from a[] and m[].
  CT: only announced bit lengths leak.
*>
extern fn void i31_reduce(uint* x, uint* a, uint* m);

<*
  Decode and reduce: decode src into x[] modulo m[].
  x[] MUST be distinct from m[].
*>
extern fn void i31_decode_reduce(uint* x, void* src, sz len, uint* m);

<*
  Multiply x[] by 2^31, add z (which MUST fit in 31 bits), reduce mod m[].
  x[] and m[] must have the same announced bit length matching m[]'s true length.
  x[] and m[] MUST be distinct. CT: only the common bit length leaks.
*>
extern fn void i31_muladd_small(uint* x, uint z, uint* m);

<*
  Encode an i31 integer into big-endian unsigned representation.
  Truncated if len is too short; zero-padded if too long.
*>
extern fn void i31_encode(void* dst, sz len, uint* x);

<*
  Compute -(1/x) mod 2^31. Returns 0 if x is even.
  Used to derive the Montgomery parameter m0i for i31.
*>
extern fn uint i31_ninv31(uint x);

<*
  Montgomery multiplication for i31: d[] = x[] * y[] / R mod m[].
  d[] must be distinct from x[], y[], and m[].
  x[] and y[] must be < m[]; they may alias.
  m0i = -(1/m[1]) mod 2^31.
*>
extern fn void i31_montymul(uint* d, uint* x, uint* y, uint* m, uint m0i);

<* Convert x[] to Montgomery representation (i31). x[] < m[]. *>
extern fn void i31_to_monty(uint* x, uint* m);

<*
  Convert x[] back from Montgomery representation (i31).
  m0i = -(1/m[1]) mod 2^32 (note: 2^32, not 2^31).
*>
extern fn void i31_from_monty(uint* x, uint* m, uint m0i);

<*
  Modular exponentiation (i31): x[] = x[]^e mod m[].
  m[] must be odd. e is big-endian unsigned, elen bytes.
  m0i = -(1/m[1]) mod 2^31.
  t1[] and t2[] are per-operation temporaries sized to hold an m[]-sized integer.
*>
extern fn void i31_modpow(uint* x, char* e, sz elen,
    uint* m, uint m0i, uint* t1, uint* t2);

<*
  Window-optimised modular exponentiation (i31).
  Same as i31_modpow but uses a tmp[] workspace (twlen words) to enable
  window-based acceleration when extra space is available.
  Minimum required: two i31 integers the size of m[] (including the header word).
  Returns 1 on success, 0 if tmp[] is too short.
*>
extern fn uint i31_modpow_opt(uint* x, char* e, sz elen,
    uint* m, uint m0i, uint* tmp, sz twlen);

<*
  Compute d[] += a[] * b[] (i31).
  d[] initial announced bit length must match a[].
  d[] must be large enough (may need one extra word).
  a[] and b[] may alias. d[] must be disjoint from both.
*>
extern fn void i31_mulacc(uint* d, uint* a, uint* b);

<*
  Compute x[] / y[] mod m[] (i31), result in x[].
  x[], y[], and m[] all have the same announced bit length as m[].
  m[] must be odd. m0i = -1/m mod 2^31.
  t[] must point to at least three i31 integers the size of m[].
  m[] may not overlap x[] or y[]. x[] and y[] may overlap each other.
  t[] must be disjoint from all other arrays.
  Returns 1 if y[] is invertible modulo m[], 0 otherwise.
*>
extern fn uint i31_moddiv(uint* x, uint* y, uint* m, uint m0i, uint* t);

// ============================================================================
// 9. i15 — Big Integer Functions (15-bit word representation)
//
// Similar to i31 but uses 16-bit words with 15 value bits each.
// Documentation is sparse in the original; signatures are preserved here.
// ============================================================================

<* Zeroize an i15 integer. bit_len is the encoded bit length. *>
fn void i15_zero(ushort* x, ushort bit_len) @inline
{
    *x++ = bit_len;
    sz words = (sz)((bit_len + 15) >> 4);
    string::memset(x, 0, words*4);
    //for (sz i = 0; i < words; i++) x[i] = 0;
}

extern fn uint   i15_szero(ushort* x);
extern fn ushort i15_ninv15(ushort x);
extern fn uint   i15_add(ushort* a, ushort* b, uint ctl);
extern fn uint   i15_sub(ushort* a, ushort* b, uint ctl);
extern fn void   i15_muladd_small(ushort* x, ushort z, ushort* m);
extern fn void   i15_montymul(ushort* d, ushort* x, ushort* y, ushort* m, ushort m0i);
extern fn void   i15_to_monty(ushort* x, ushort* m);
extern fn void   i15_modpow(ushort* x, char* e, sz elen,
                             ushort* m, ushort m0i, ushort* t1, ushort* t2);
extern fn uint   i15_modpow_opt(ushort* x, char* e, sz elen,
                                 ushort* m, ushort m0i, ushort* tmp, sz twlen);
extern fn void   i15_encode(void* dst, sz len, ushort* x);
extern fn uint   i15_decode_mod(ushort* x, void* src, sz len, ushort* m);
extern fn void   i15_rshift(ushort* x, int count);
extern fn uint   i15_bit_length(ushort* x, sz xlen);
extern fn void   i15_decode(ushort* x, void* src, sz len);
extern fn void   i15_from_monty(ushort* x, ushort* m, ushort m0i);
extern fn void   i15_decode_reduce(ushort* x, void* src, sz len, ushort* m);
extern fn void   i15_reduce(ushort* x, ushort* a, ushort* m);
extern fn void   i15_mulacc(ushort* d, ushort* a, ushort* b);
extern fn uint   i15_moddiv(ushort* x, ushort* y, ushort* m, ushort m0i, ushort* t);

// ============================================================================
// 10. i62 and modpow_opt Function Type
// ============================================================================

<*
  Function pointer type matching the i31_modpow_opt() signature.
  Some implementations may require stricter alignment on the tmp[] array.
*>
alias I31ModpowOptFn = fn uint(uint* x, char* e, sz elen,
    uint* m, uint m0i, uint* tmp, sz twlen);

<*
  Window-optimised modular exponentiation using 64×64→128-bit multiplications.
  Same interface as i31_modpow_opt(), but tmp[] must be 64-bit aligned and
  contains ulong values (not uint).
  Returns 1 on success, 0 if tmp[] is too short.
*>
extern fn uint i62_modpow_opt(uint* x31, char* e, sz elen,
    uint* m31, uint m0i31, ulong* tmp, sz twlen);

<*
  Wrapper for i62_modpow_opt() with the same type signature as
  i31_modpow_opt(). The tmp[] argument MUST be 64-bit aligned even
  though it is declared as uint*.
*>
extern fn uint i62_modpow_opt_as_i31(uint* x, char* e, sz elen,
    uint* m, uint m0i, uint* tmp, sz twlen);

// ============================================================================
// 12. DES Support
// ============================================================================

<* Apply the DES Initial Permutation (IP) to the 64-bit block xl:xr. *>
extern fn void des_do_ip(uint* xl, uint* xr);

<* Apply the DES Final Permutation (FP = IP^-1) to the 64-bit block xl:xr. *>
extern fn void des_do_invip(uint* xl, uint* xr);

<*
  Key schedule for one DES key (8 bytes).
  Computes 16 subkeys, each as two 28-bit values stored in two 32-bit words.
  PC-2 bit extraction is NOT applied at this stage.
*>
extern fn void des_keysched_unit(uint* skey, void* key);

<* Reverse 16 DES subkeys in place (converts encryption schedule to decryption). *>
extern fn void des_rev_skey(uint* skey);

<*
  DES/3DES key schedule for the 'des_tab' implementation (encryption direction).
  Returns the number of rounds (8 for DES, 24 for 3DES).
*>
extern fn uint des_tab_keysched(uint* skey, void* key, sz key_len);

<*
  DES/3DES key schedule for the 'des_ct' (constant-time bitsliced) implementation.
  Returns the number of rounds.
*>
extern fn uint des_ct_keysched(uint* skey, void* key, sz key_len);

<*
  Expand DES/3DES subkeys from the compressed bitsliced form (des_ct).
*>
extern fn void des_ct_skey_expand(uint* sk_exp, uint num_rounds, uint* skey);

<*
  DES/3DES block encrypt or decrypt using the 'des_tab' implementation.
  Operates on a single 8-byte block in place.
*>
extern fn void des_tab_process_block(uint num_rounds, uint* skey, void* block);

<*
  DES/3DES block encrypt or decrypt using the 'des_ct' bitsliced implementation.
  Operates on a single 8-byte block in place.
*>
extern fn void des_ct_process_block(uint num_rounds, uint* skey, void* block);

// ============================================================================
// 13. AES Support
// ============================================================================

<* The AES S-box lookup table (256 bytes). *>
extern char[*] aes_s;

<*
  AES key schedule (table-based, not constant-time).
  Fills skey[] with (num_rounds + 1) 128-bit subkeys.
  Returns the number of rounds (10, 12, or 14 for 128/192/256-bit keys).
  Returns 0 if the key size is not 16, 24, or 32 bytes.
*>
extern fn uint aes_keysched(uint* skey, void* key, sz key_len);

<*
  AES key schedule for decryption ('aes_big' implementation).
  Returns the number of rounds, or 0 for invalid key size.
*>
extern fn uint aes_big_keysched_inv(uint* skey, void* key, sz key_len);

<*
  AES single-block encryption in place ('aes_big' — fast, not constant-time).
*>
extern fn void aes_big_encrypt(uint num_rounds, uint* skey, void* data);

<*
  AES single-block decryption in place ('aes_big' — fast, not constant-time).
*>
extern fn void aes_big_decrypt(uint num_rounds, uint* skey, void* data);

<*
  AES single-block encryption in place ('aes_small' — small code, slow,
  not constant-time).
*>
extern fn void aes_small_encrypt(uint num_rounds, uint* skey, void* data);

<*
  AES single-block decryption in place ('aes_small' — small code, slow,
  not constant-time).
*>
extern fn void aes_small_decrypt(uint num_rounds, uint* skey, void* data);

// --- Constant-time bitsliced AES ('aes_ct', 32-bit words) -----------------
// Two independent AES states are interleaved on even/odd bit ranks.
// Input: 32 bytes (two 16-byte blocks) → eight 32-bit words q[0..7].

<*
  Bytewise orthogonalisation of eight 32-bit words (bitslice conversion).
  This operation is its own inverse (an involution).
*>
extern fn void aes_ct_ortho(uint* q);

<*
  Bitsliced constant-time AES S-box.
  Processes 32 S-box instances in parallel across eight 32-bit words.
*>
extern fn void aes_ct_bitslice_sbox(uint* q);

<* Bitsliced constant-time AES inverse S-box. *>
extern fn void aes_ct_bitslice_invsbox(uint* q);

<*
  AES encryption on bitsliced data (two blocks in parallel).
*>
extern fn void aes_ct_bitslice_encrypt(uint num_rounds, uint* skey, uint* q);

<*
  AES decryption on bitsliced data (two blocks in parallel).
*>
extern fn void aes_ct_bitslice_decrypt(uint num_rounds, uint* skey, uint* q);

<*
  Constant-time AES key schedule.
  Returns the number of rounds, or 0 for invalid key size.
*>
extern fn uint aes_ct_keysched(uint* comp_skey, void* key, sz key_len);

<*
  Expand compressed subkeys from aes_ct_keysched() into the form needed
  by aes_ct_bitslice_encrypt() / aes_ct_bitslice_decrypt().
*>
extern fn void aes_ct_skey_expand(uint* skey, uint num_rounds, uint* comp_skey);

// --- Constant-time bitsliced AES ('aes_ct64', 64-bit words) ---------------
// Four independent AES states are interleaved on bit ranks 0,4,8,...
// through 3,7,11,... Input: 64 bytes (four 16-byte blocks) → eight 64-bit words.

<*
  Bytewise orthogonalisation of eight 64-bit words (bitslice conversion).
  This operation is its own inverse.
*>
extern fn void aes_ct64_ortho(ulong* q);

<*
  Interleave bytes of one AES input block for 'aes_ct64'.
  Four little-endian 32-bit words w[0..3] → interleaved outputs q0, q1.
*>
extern fn void aes_ct64_interleave_in(ulong* q0, ulong* q1, uint* w);

<* Reverse the interleaving produced by aes_ct64_interleave_in(). *>
extern fn void aes_ct64_interleave_out(uint* w, ulong q0, ulong q1);

<*
  Bitsliced constant-time AES S-box (64-bit).
  Processes 64 S-box instances in parallel.
*>
extern fn void aes_ct64_bitslice_sbox(ulong* q);

<* Bitsliced constant-time AES inverse S-box (64-bit). *>
extern fn void aes_ct64_bitslice_invsbox(ulong* q);

<*
  AES encryption on 64-bit bitsliced data (four blocks in parallel).
*>
extern fn void aes_ct64_bitslice_encrypt(uint num_rounds, ulong* skey, ulong* q);

<*
  AES decryption on 64-bit bitsliced data (four blocks in parallel).
*>
extern fn void aes_ct64_bitslice_decrypt(uint num_rounds, ulong* skey, ulong* q);

<*
  Constant-time AES key schedule (64-bit version).
  Returns the number of rounds, or 0 for invalid key size.
*>
extern fn uint aes_ct64_keysched(ulong* comp_skey, void* key, sz key_len);

<*
  Expand compressed subkeys from aes_ct64_keysched() into the form needed
  by aes_ct64_bitslice_encrypt() / aes_ct64_bitslice_decrypt().
*>
extern fn void aes_ct64_skey_expand(ulong* skey, uint num_rounds, ulong* comp_skey);

// --- AES-NI (x86) ----------------------------------------------------------

<*
  Test whether x86 AES-NI opcodes are available on the current CPU.
  Returns 1 if available, 0 otherwise.
*>
extern fn int aes_x86ni_supported();

<*
  AES key schedule using x86 AES-NI instructions (encryption direction).
  Key size MUST be 16, 24, or 32 bytes; returns 0 otherwise.
  Returns the number of rounds.
*>
extern fn uint aes_x86ni_keysched_enc(char* skni, void* key, sz len);

<*
  AES key schedule using x86 AES-NI instructions (decryption direction).
  Key size MUST be 16, 24, or 32 bytes; returns 0 otherwise.
  Returns the number of rounds.
*>
extern fn uint aes_x86ni_keysched_dec(char* skni, void* key, sz len);

// --- AES POWER8 ------------------------------------------------------------

<*
  Test whether POWER8 AES opcodes are available on the current CPU.
  Returns 1 if available, 0 otherwise.
*>
extern fn int aes_pwr8_supported();

<*
  AES key schedule using POWER8 instructions (encryption direction).
  Key size MUST be 16, 24, or 32 bytes; returns 0 otherwise.
  Returns the number of rounds.
*>
extern fn uint aes_pwr8_keysched(char* skni, void* key, sz len);

// ============================================================================
// 14. RSA Padding / Unpadding
// ============================================================================

<*
  Apply PKCS#1 v1.5 signature padding to a hash value.
  hash_oid is the DER-encoded hash function OID, or null.
  n_bitlen is the RSA modulus size in bits. Output goes into x[].
  Returns 1 on success, 0 on error.
*>
extern fn uint rsa_pkcs1_sig_pad(char* hash_oid,
    char* hash, sz hash_len, uint n_bitlen, char* x);

<*
  Verify and strip PKCS#1 v1.5 signature padding.
  sig[] is the result after modular exponentiation (the padded hash).
  hash_oid is the DER-encoded hash function OID, or null.
  On success the hash is extracted into hash_out[].
  Returns 1 on success, 0 on error.
*>
extern fn uint rsa_pkcs1_sig_unpad(char* sig, sz sig_len,
    char* hash_oid, sz hash_len, char* hash_out);

<*
  Apply PSS signature padding.
  hf_data and hf_mgf1 are hash function vtables for data and MGF1.
  hash is the pre-computed message hash; salt_len is the PSS salt length.
  n_bitlen is the RSA modulus size in bits. Output goes into x[].
  Returns 1 on success, 0 on error.
*>
extern fn uint rsa_pss_sig_pad(PRNGClass** rng,
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash, sz salt_len, uint n_bitlen, char* x);

<*
  Verify PSS padding. The input x[] is the result after modular
  exponentiation; it is modified in place. The RSA key pk is used
  to infer the signature length.
  Returns 1 on success, 0 on failure.
*>
extern fn uint rsa_pss_sig_unpad(
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash, sz salt_len, RSAPublicKey* pk, char* x);

<*
  Apply OAEP encryption padding.
  Returns the length of the padded output on success, 0 on error.
*>
extern fn sz rsa_oaep_pad(PRNGClass** rnd, HashClass* dig,
    void* label, sz label_len, RSAPublicKey* pk,
    void* dst, sz dst_max_len, void* src, sz src_len);

<*
  Verify and strip OAEP decryption padding.
  On success: returns 1, adjusts *len to the message length, and moves
  the message to the start of data[]. On failure: returns 0, *len is
  unchanged. In either case, the entire buffer contents are modified.
*>
extern fn uint rsa_oaep_unpad(HashClass* dig,
    void* label, sz label_len, void* data, sz* len);

<*
  Compute MGF1 and XOR its output into data[].
  Uses hash function dig with the given seed.
*>
extern fn void mgf1_xor(void* data, sz len,
    HashClass* dig, void* seed, sz seed_len);

<*
  Inner RSA key generation function shared by the 'i31' and 'i62'
  implementations. mp31 is the modular exponentiation implementation to use.
*>
extern fn uint rsa_i31_keygen_inner(PRNGClass** rng,
    RSAPrivateKey* sk, void* kbuf_priv,
    RSAPublicKey* pk, void* kbuf_pub,
    uint size, uint pubexp, I31ModpowOptFn mp31);

// ============================================================================
// 15. Elliptic Curve Definitions
// ============================================================================

<*
  Generic EC curve parameters: unsigned big-endian curve order and
  the encoded conventional base point (generator).
*>
struct ECCurveDef {
    int    curve;
    char*  order;
    sz    order_len;
    char*  generator;
    sz    generator_len;
}

<* NIST P-256 (secp256r1) curve parameters. *>
extern ECCurveDef secp256r1;

<* NIST P-384 (secp384r1) curve parameters. *>
extern ECCurveDef secp384r1;

<* NIST P-521 (secp521r1) curve parameters. *>
extern ECCurveDef secp521r1;

<*
  Curve25519 parameters.
  The advertised "order" is 2^255-1 (not the true group order), intended
  as a hint for ECDH key generation only. ECDSA is not used with this curve.
*>
extern ECCurveDef curve25519;

<*
  Decode bytes as an i31 integer with truncation (bits2int from RFC 6979).
  ebitlen is the target ENCODED bit length. The result has exactly that
  announced bit length and decodes the most significant ebitlen bits from src.
*>
extern fn void ecdsa_i31_bits2int(uint* x, void* src, sz len, uint ebitlen);

<*
  Decode bytes as an i15 integer with truncation (bits2int from RFC 6979).
  ebitlen is the target ENCODED bit length.
*>
extern fn void ecdsa_i15_bits2int(ushort* x, void* src, sz len, uint ebitlen);

// ============================================================================
// 16. ASN.1 Support
// ============================================================================

<*
  Prepared representation of a non-negative ASN.1 INTEGER value.
  data points to the minimal-length big-endian unsigned encoding
  (no leading zero unless the value is zero itself).
  asn1len equals len or len+1 (the latter when a leading 0x00 byte is
  needed to keep the DER encoding positive).
*>
struct ASN1Uint {
    char* data;
    sz   len;
    sz   asn1len;
}

<*
  Prepare an ASN1Uint from a raw big-endian unsigned integer.
  Strips leading zero bytes and computes the correct asn1len.
*>
extern fn ASN1Uint asn1_uint_prepare(void* xdata, sz xlen);

<*
  Encode an ASN.1 length field into dest.
  Returns the number of bytes written. If dest is null, no encoding is
  performed but the correct byte count is still returned.
*>
extern fn sz asn1_encode_length(void* dest, sz len);

<*
  Compute the number of bytes needed to encode an ASN.1 length value.
  Equivalent to calling asn1_encode_length(null, len).
*>
macro sz len_of_len(sz len) => asn1_encode_length(null, len);

<*
  Encode a prepared ASN.1 INTEGER into dest.
  Returns the number of bytes written. If dest is null, only the byte
  count is computed and returned.
*>
extern fn sz asn1_encode_uint(void* dest, ASN1Uint pp);

<*
  Get the DER-encoded OID that identifies an elliptic curve.
  The returned buffer starts with a one-byte length followed by that many
  OID value bytes (no tag byte). Returns null for unrecognised curves.
*>
extern fn char* get_curve_oid(int curve);

<*
  Inner function for EC private key DER encoding.
  Equivalent to the public encode_ec_raw_der() API, with an extra flag:
  if include_curve_oid is 0, the curve OID is omitted (used for PKCS#8).
*>
extern fn sz encode_ec_raw_der_inner(void* dest,
    ECPrivateKey* sk, ECPublicKey* pk, int include_curve_oid);

// ============================================================================
// 17. SSL/TLS Internal Constants and Engine Functions
// ============================================================================

// Record type codes
const SSL_CHANGE_CIPHER_SPEC   = 20;
const SSL_ALERT                = 21;
const SSL_HANDSHAKE            = 22;
const SSL_APPLICATION_DATA     = 23;

// Handshake message type codes
const SSL_HELLO_REQUEST        =  0;
const SSL_CLIENT_HELLO         =  1;
const SSL_SERVER_HELLO         =  2;
const SSL_CERTIFICATE          = 11;
const SSL_SERVER_KEY_EXCHANGE  = 12;
const SSL_CERTIFICATE_REQUEST  = 13;
const SSL_SERVER_HELLO_DONE    = 14;
const SSL_CERTIFICATE_VERIFY   = 15;
const SSL_CLIENT_KEY_EXCHANGE  = 16;
const SSL_FINISHED             = 20;

// Alert level codes
const LEVEL_WARNING = 1;
const LEVEL_FATAL   = 2;

// Low-level I/O state codes
const IO_FAILED = 0;
const IO_IN     = 1;
const IO_OUT    = 2;
const IO_INOUT  = 3;

<*
  Mark the SSL engine as failed, recording err as the error code.
  If the engine was already failed, the code is not overwritten.
  If err is 0, the engine is marked as cleanly closed (no error).
*>
extern fn void ssl_engine_fail(SSLEngineContext* cc, int err);

<*
  Test whether the SSL engine is closed (either cleanly or as a failure).
  Returns non-zero if iomode == IO_FAILED.
*>
fn int ssl_engine_closed(SSLEngineContext* cc) @inline
{
    return cc.iomode == IO_FAILED;
}

<*
  Adjust the maximum outgoing record fragment length.
  Takes effect immediately if the output buffer can accommodate the change.
*>
extern fn void ssl_engine_new_max_frag_len(SSLEngineContext* rc, uint max_frag_len);

<*
  Test whether the current incoming record has been fully received.
  Returns 0 only when a complete record header has arrived but some
  encrypted payload bytes have not yet been read.
*>
extern fn int ssl_engine_recvrec_finished(SSLEngineContext* rc);

<*
  Flush the current outgoing record if it contains any payload.
  Intended to be called only from the handshake processor.
*>
extern fn void ssl_engine_flush_record(SSLEngineContext* cc);

<*
  Test whether there is accumulated outgoing payload waiting to be sent.
*>
fn int ssl_engine_has_pld_to_send(SSLEngineContext* rc) @inline
{
    return rc.oxa != rc.oxb && rc.oxa != rc.oxc;
}

<*
  Initialise the PRNG in the SSL engine context.
  Attempts to use the OS-provided RNG. Returns 1 on success, 0 on failure;
  on failure the context error code is set.
*>
extern fn int ssl_engine_init_rand(SSLEngineContext* cc);

<*
  Reset the handshake-related portion of the engine state.
  hsinit and hsrun are the T0 handshake initialisation and run functions.
*>
extern fn void ssl_engine_hs_reset(SSLEngineContext* cc,
    fn void(void*) hsinit, fn void(void*) hsrun);

<*
  Get the TLS PRF implementation to use for the given prf_id.
  Returns a TLSPRFImplFn appropriate for the negotiated TLS version.
*>
extern fn TLSPRFImplFn ssl_engine_get_prf(SSLEngineContext* cc, int prf_id);

<*
  Derive the master secret from a pre-master secret.
  prf_id selects the hash for the TLS 1.2 PRF (ignored for TLS 1.0/1.1).
*>
extern fn void ssl_engine_compute_master(SSLEngineContext* cc,
    int prf_id, void* pms, sz len);

// --- Record encryption mode switch functions --------------------------------

<*
  Switch to CBC decryption for incoming records.
  is_client: non-zero for client, zero for server.
  prf_id: PRF hash ID (ignored below TLS 1.2).
  mac_id: HMAC hash ID.
  bc_impl: CBC decryption vtable. cipher_key_len: key length in bytes.
*>
extern fn void ssl_engine_switch_cbc_in(SSLEngineContext* cc,
    int is_client, int prf_id, int mac_id,
    BlockCBCDecClass* bc_impl, sz cipher_key_len);

<*
  Switch to CBC encryption for outgoing records.
  (Parameters identical to ssl_engine_switch_cbc_in.)
*>
extern fn void ssl_engine_switch_cbc_out(SSLEngineContext* cc,
    int is_client, int prf_id, int mac_id,
    BlockCBCEncClass* bc_impl, sz cipher_key_len);

<*
  Switch to GCM decryption for incoming records.
  bc_impl: CTR-mode block cipher vtable. cipher_key_len: key length.
*>
extern fn void ssl_engine_switch_gcm_in(SSLEngineContext* cc,
    int is_client, int prf_id,
    BlockCTRClass* bc_impl, sz cipher_key_len);

<*
  Switch to GCM encryption for outgoing records.
*>
extern fn void ssl_engine_switch_gcm_out(SSLEngineContext* cc,
    int is_client, int prf_id,
    BlockCTRClass* bc_impl, sz cipher_key_len);

<*
  Switch to ChaCha20+Poly1305 decryption for incoming records.
*>
extern fn void ssl_engine_switch_chapol_in(SSLEngineContext* cc,
    int is_client, int prf_id);

<*
  Switch to ChaCha20+Poly1305 encryption for outgoing records.
*>
extern fn void ssl_engine_switch_chapol_out(SSLEngineContext* cc,
    int is_client, int prf_id);

<*
  Switch to CCM decryption for incoming records.
  bc_impl: CTR+CBC block cipher vtable.
  cipher_key_len: cipher key length. tag_len: CCM tag length.
*>
extern fn void ssl_engine_switch_ccm_in(SSLEngineContext* cc,
    int is_client, int prf_id,
    BlockCTRCBCClass* bc_impl, sz cipher_key_len, sz tag_len);

<*
  Switch to CCM encryption for outgoing records.
*>
extern fn void ssl_engine_switch_ccm_out(SSLEngineContext* cc,
    int is_client, int prf_id,
    BlockCTRCBCClass* bc_impl, sz cipher_key_len, sz tag_len);

// --- T0 virtual machine handshake entry points ------------------------------

<* Initialise the T0 client handshake state machine. *>
extern fn void ssl_hs_client_init_main(void* ctx);

<* Run the T0 client handshake state machine. *>
extern fn void ssl_hs_client_run(void* ctx);

<* Initialise the T0 server handshake state machine. *>
extern fn void ssl_hs_server_init_main(void* ctx);

<* Run the T0 server handshake state machine. *>
extern fn void ssl_hs_server_run(void* ctx);

<*
  Choose a hash function for signatures based on a bitmask of supported IDs.
  Selection order: SHA-256, SHA-384, SHA-512, SHA-224, SHA-1.
  Returns 0 if none of those are indicated as supported.
*>
extern fn int ssl_choose_hash(uint bf);
