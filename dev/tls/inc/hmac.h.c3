// hmac.h.c3
//
// C3 bindings for BearSSL bearssl_hmac.h
// HMAC (Hash-based Message Authentication Code)
//
// Naming conventions:
//   br_hmac_key_context  → HMACKeyContext
//   br_hmac_context      → HMACContext
//   br_hmac_key_init     → hmac_key_init      (extern fn)
//   br_hmac_init         → hmac_init          (extern fn)
//   br_hmac_update       → hmac_update        (extern fn)
//   br_hmac_out          → hmac_out           (extern fn)
//   br_hmac_outCT        → hmac_out_ct        (extern fn)
//
// Constraints on the underlying hash function:
//   - output size     ≤ 64 bytes
//   - internal state  ≤ 64 bytes
//   - block length    is a power of 2 in [16, 256]

module ext::net::tls;

// ============================================================================
// HMAC Key Context
//
// Holds the pre-processed HMAC key (inner and outer padded key blocks).
// Initialised once with hmac_key_init(); can be reused for multiple
// independent HMAC computations. Never modified during HMAC processing.
// No dynamic allocation; no release function needed.
// ============================================================================

<*
  HMAC key context.

  Contains the pre-processed secret key (inner and outer padded blocks)
  derived from the raw key and the selected hash function. This context
  is not modified during HMAC computation and can be shared across
  multiple concurrent hmac_init() calls.

  All fields are opaque; use the provided API functions exclusively.
*>
struct HMACKeyContext {
    HashClass* dig_vtable;   // underlying hash function vtable
    char[64]   ksi;          // inner padded key block  (key XOR ipad)
    char[64]   kso;          // outer padded key block  (key XOR opad)
}

<*
  Initialise an HMAC key context.

  Processes the raw secret key with the selected hash function and stores
  the resulting padded key blocks. Arbitrary key lengths are supported.

  param kc              HMAC key context to initialise.
  param digest_vtable   hash function implementation vtable.
  param key             HMAC secret key bytes.
  param key_len         HMAC secret key length (in bytes).
*>
extern fn void hmac_key_init(HMACKeyContext* kc,
    HashClass* digest_vtable, void* key, sz key_len);

<*
  Get the hash function vtable from an HMAC key context.

  MUST NOT be called on an uninitialised key context.

  param kc   HMAC key context (already initialised).
  return the underlying hash function vtable.
*>
fn HashClass* hmac_key_get_digest(HMACKeyContext* kc) @inline
{
    return kc.dig_vtable;
}

// ============================================================================
// HMAC Computation Context
//
// Holds the running state for a single HMAC computation. Initialised from
// an HMACKeyContext (which is not modified). Input bytes are injected with
// hmac_update(); the MAC is obtained with hmac_out() or hmac_out_ct().
// The context is not modified by hmac_out() / hmac_out_ct(), so partial
// MACs can be computed efficiently by calling those functions mid-stream.
// No dynamic allocation; no release function needed.
// ============================================================================

<*
  HMAC computation context.

  Maintains the in-progress hash state and a copy of the outer padded key
  block. Initialised from an HMACKeyContext via hmac_init(). The key
  context is not referenced after initialisation and may be reused or
  released independently.

  All fields are opaque; use the provided API functions exclusively.
*>
struct HMACContext {
    HashCompatContext dig;      // running inner hash state
    char[64]         kso;      // copy of outer padded key block
    sz              out_len;  // actual output length (bytes)
}

<*
  Initialise an HMAC computation context.

  Copies the relevant state from kc into ctx; kc is not modified and may
  be reused, modified, or released without affecting this computation.

  out_len controls the number of bytes produced by hmac_out():
    - 0         → use the natural output length of the hash function.
    - non-zero  → min(out_len, natural output length) bytes are produced.

  param ctx       HMAC computation context to initialise.
  param kc        HMAC key context (already initialised with the key).
  param out_len   desired output length in bytes (0 = natural length).
*>
extern fn void hmac_init(HMACContext* ctx, HMACKeyContext* kc, sz out_len);

<*
  Get the HMAC output size for an initialised computation context.

  Returns the number of bytes that hmac_out() will produce. Equal to
  min(out_len passed to hmac_init(), natural hash output length); if
  out_len was 0, returns the natural hash output length.

  MUST NOT be called on an uninitialised context.

  param ctx   HMAC computation context (already initialised).
  return HMAC output size in bytes.
*>
fn sz hmac_size(HMACContext* ctx) @inline
{
    return ctx.out_len;
}

<*
  Get the hash function vtable from an HMAC computation context.

  param ctx   HMAC computation context (already initialised).
  return the underlying hash function vtable.
*>
fn HashClass* hmac_get_digest(HMACContext* ctx) @inline
{
    return ctx.dig.vtable;
}

<*
  Inject input bytes into an HMAC computation.

  Feeds len bytes from data into the running HMAC state. May be called
  any number of times. If len is zero, data is ignored and the function
  does nothing.

  param ctx    HMAC computation context.
  param data   input bytes to process.
  param len    number of input bytes (may be zero).
*>
extern fn void hmac_update(HMACContext* ctx, void* data, sz len);

<*
  Compute the HMAC output (non-destructive).

  Writes the current HMAC value to out and returns the number of bytes
  written. The context is NOT modified, so further input may be injected
  and hmac_out() called again to obtain intermediate ("partial") MACs.

  The out buffer must be at least hmac_size(ctx) bytes large.

  param ctx   HMAC computation context (already initialised).
  param out   destination buffer for the HMAC output.
  return number of bytes written to out.
*>
extern fn sz hmac_out(HMACContext* ctx, void* out);

<*
  Constant-time HMAC computation.

  Processes additional input of exactly len bytes (where min_len ≤ len ≤
  max_len), then computes and writes the HMAC output to out. The execution
  time and memory access pattern do not depend on the byte values of data
  or the value of len; max_len bytes are always read from data regardless
  of len, preventing length-based side channels.

  The context is NOT modified by this call.

  Constraints:
    - min_len ≤ len ≤ max_len (must hold; not validated internally).
    - max_len - min_len < 2^30 (approximately one gigabyte).
    - The underlying hash function must use Merkle-Damgård padding
      (MD5, SHA-1, SHA-224, SHA-256, SHA-384, or SHA-512).

  param ctx       HMAC computation context (already initialised).
  param data      extra input bytes (max_len bytes are always read).
  param len       actual extra input length in bytes (min_len ≤ len ≤ max_len).
  param min_len   minimum possible extra input length (in bytes).
  param max_len   maximum possible extra input length (in bytes).
  param out       destination buffer for the HMAC output.
  return number of bytes written to out.
*>
extern fn sz hmac_out_ct(HMACContext* ctx,
    void* data, sz len, sz min_len, sz max_len,
    void* out);
