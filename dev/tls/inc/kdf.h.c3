// kdf.h.c3

// Key Derivation Functions: HKDF (RFC 5869) and SHAKE (FIPS 202)
//
// Naming conventions:
//   br_hkdf_context      → HKDFContext
//   br_shake_context     → SHAKEContext
//   br_hkdf_init         → hkdf_init      (extern fn)
//   br_hkdf_inject       → hkdf_inject    (extern fn)
//   br_hkdf_flip         → hkdf_flip      (extern fn)
//   br_hkdf_produce      → hkdf_produce   (extern fn)
//   br_shake_init        → shake_init     (extern fn)
//   br_shake_inject      → shake_inject   (extern fn)
//   br_shake_flip        → shake_flip     (extern fn)
//   br_shake_produce     → shake_produce  (extern fn)
//   BR_HKDF_NO_SALT      → HKDF_NO_SALT  (reference to hkdf_no_salt)

module ext::net::tls;

// ============================================================================
// HKDF (RFC 5869)
//
// Two-phase KDF built on top of HMAC with a configurable hash function:
//
//   1. HKDF-Extract: hkdf_init() + hkdf_inject() [×N]
//      Ingests input key material (IKM) along with an optional salt,
//      producing a fixed-length pseudorandom key (PRK).
//
//   2. HKDF-Expand:  hkdf_flip() + hkdf_produce() [×N]
//      Expands the PRK into arbitrarily long output keying material,
//      bound to an application-specific "info" string.
//
// Constraints on the hash function: output ≤ 64 bytes, internal state
// ≤ 64 bytes, block length a power of two in [16, 256].
//
// Maximum total output: 255 × (hash output length in bytes).
//
// Salt semantics:
//   - salt_len == 0           → salt is present but empty (zero-length).
//   - salt == HKDF_NO_SALT    → salt is absent (equivalent to a zero-filled
//                               string of length equal to the hash output).
// ============================================================================

<*
  The special "absent salt" sentinel value for hkdf_init().

  Pass &hkdf_no_salt as the salt parameter to indicate that no salt is
  provided (distinct from a zero-length salt). salt_len is ignored when
  this sentinel is used.
*>
extern char hkdf_no_salt;

<*
  HKDF context.

  Holds all state for both the HKDF-Extract and HKDF-Expand phases.
  Initialise with hkdf_init(); no dynamic allocation is performed and
  no explicit release is needed.

  All fields are opaque; use the provided API functions exclusively.
*>
struct HKDFContext {
    // Union of the active HMAC context (Extract phase) and the
    // stored PRK key context (Expand phase). Only one is live at a time.
    union {
        HMACContext    hmac_ctx;
        HMACKeyContext prk_ctx;
    } u;
    char[64] buf;        // output block buffer (one hash-output worth)
    sz      ptr;        // current read position within buf
    sz      dig_len;    // underlying hash output length (in bytes)
    uint     chunk_num;  // HKDF-Expand block counter (1-based)
}

<*
  Initialise an HKDF context (begin HKDF-Extract).

  Selects the underlying hash function and provides the salt. Arbitrary
  salt lengths are supported. To supply an absent salt (equivalent to a
  zero-filled string of length equal to the hash output), pass
  &hkdf_no_salt as salt; salt_len is ignored in that case.

  param hc              HKDF context to initialise.
  param digest_vtable   hash function implementation vtable.
  param salt            HKDF-Extract salt (or &hkdf_no_salt for absent salt).
  param salt_len        salt length in bytes (ignored when salt == &hkdf_no_salt).
*>
extern fn void hkdf_init(HKDFContext* hc, HashClass* digest_vtable,
    void* salt, sz salt_len);

<*
  Inject input key material into HKDF (HKDF-Extract phase).

  May be called multiple times after hkdf_init() and before hkdf_flip()
  to supply IKM in chunks.

  param hc        HKDF context.
  param ikm       input key material bytes.
  param ikm_len   input key material length (in bytes).
*>
extern fn void hkdf_inject(HKDFContext* hc, void* ikm, sz ikm_len);

<*
  Switch from HKDF-Extract to HKDF-Expand.

  Finalises the Extract phase (PRK computation) and prepares the context
  for output production. Must be called exactly once, after all IKM has
  been injected and before any hkdf_produce() calls.

  param hc   HKDF context.
*>
extern fn void hkdf_flip(HKDFContext* hc);

<*
  Produce output bytes from HKDF (HKDF-Expand phase).

  May be called multiple times after hkdf_flip() to obtain output in
  chunks. The same info string must be supplied on every call for a given
  context. Returns the number of bytes actually written, which may be less
  than out_len if the 255 × hash-output-length limit is reached.

  param hc         HKDF context.
  param info       application-specific context/label string.
  param info_len   info string length (in bytes).
  param out        destination buffer.
  param out_len    number of output bytes requested.
  return number of bytes actually produced.
*>
extern fn sz hkdf_produce(HKDFContext* hc,
    void* info, sz info_len, void* out, sz out_len);

// ============================================================================
// SHAKE (FIPS 202)
//
// Extendable-output functions (XOF) based on the Keccak sponge construction.
// Two standard variants:
//
//   SHAKE128: security_level = 128  (capacity = 256 bits, faster)
//   SHAKE256: security_level = 256  (capacity = 512 bits, ~20-25% slower)
//
// Unlike HKDF, SHAKE has no salt or info string concept. Usage sequence:
//
//   shake_init() → shake_inject() [×N] → shake_flip() → shake_produce() [×N]
//
// Allowed security levels: any multiple of 32 in [32, 768].
// Output length is unlimited.
// ============================================================================

<*
  SHAKE context.

  Holds the full Keccak sponge state for a SHAKE computation.
  Initialise with shake_init(); no dynamic allocation is performed and
  no explicit release is needed.

  All fields are opaque; use the provided API functions exclusively.
*>
struct SHAKEContext {
    char[200]  dbuf;   // sponge input/output buffer (rate bytes active)
    sz        dptr;   // current position within dbuf
    sz        rate;   // sponge rate in bytes (= 200 - capacity/8)
    ulong[25]  a;      // Keccak-f[1600] state (5×5 matrix of 64-bit lanes)
}

<*
  Initialise a SHAKE context.

  Sets the sponge capacity to twice the given security_level, consistent
  with the FIPS 202 definition: SHAKE128 uses security_level = 128 and
  SHAKE256 uses security_level = 256. Allowed values are multiples of 32
  in the range [32, 768]; values above 256 bits offer diminishing returns.

  param sc               SHAKE context to initialise.
  param security_level   security level in bits (e.g. 128 or 256).
*>
extern fn void shake_init(SHAKEContext* sc, int security_level);

<*
  Inject input bytes into SHAKE (absorption phase).

  May be called multiple times after shake_init() and before shake_flip()
  to supply input in chunks.

  param sc    SHAKE context.
  param data  input bytes to absorb.
  param len   number of input bytes.
*>
extern fn void shake_inject(SHAKEContext* sc, void* data, sz len);

<*
  Switch from absorption to squeezing (output production).

  Finalises the input injection phase and prepares the context for output
  production. Must be called exactly once, after all input has been
  injected and before any shake_produce() calls.

  param sc   SHAKE context.
*>
extern fn void shake_flip(SHAKEContext* sc);

<*
  Produce output bytes from SHAKE (squeezing phase).

  May be called multiple times after shake_flip() to obtain output in
  chunks. There is no practical upper limit on the total number of bytes
  that may be produced.

  param sc    SHAKE context.
  param out   destination buffer.
  param len   number of output bytes to produce.
*>
extern fn void shake_produce(SHAKEContext* sc, void* out, sz len);
