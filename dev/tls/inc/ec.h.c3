// ec.h.c3

// Elliptic Curves (EC) and ECDSA
//
// Naming conventions:
//   br_ec_public_key    → ECPublicKey
//   br_ec_private_key   → ECPrivateKey
//   br_ec_impl          → ECImpl
//   br_ecdsa_sign       → ECDSASignFn   (alias fn)
//   br_ecdsa_vrfy       → ECDSAVrfyFn   (alias fn)
//   br_ec_prime_i31     → ec_prime_i31  (extern)
//   br_ecdsa_i31_sign_asn1 → ecdsa_i31_sign_asn1 (extern fn)

module ext::net::tls;

// ============================================================================
// Named Curve Identifiers
//
// These values match the IANA TLS parameters registry:
//   https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml#tls-parameters-8
//
// Since all current identifiers are in the 0..31 range, curve support is
// encoded as a 32-bit bitmask: bit x corresponds to curve ID x.
// ============================================================================

<* Named curve: sect163k1. *>
const EC_SECT163K1        = 1;
<* Named curve: sect163r1. *>
const EC_SECT163R1        = 2;
<* Named curve: sect163r2. *>
const EC_SECT163R2        = 3;
<* Named curve: sect193r1. *>
const EC_SECT193R1        = 4;
<* Named curve: sect193r2. *>
const EC_SECT193R2        = 5;
<* Named curve: sect233k1. *>
const EC_SECT233K1        = 6;
<* Named curve: sect233r1. *>
const EC_SECT233R1        = 7;
<* Named curve: sect239k1. *>
const EC_SECT239K1        = 8;
<* Named curve: sect283k1. *>
const EC_SECT283K1        = 9;
<* Named curve: sect283r1. *>
const EC_SECT283R1        = 10;
<* Named curve: sect409k1. *>
const EC_SECT409K1        = 11;
<* Named curve: sect409r1. *>
const EC_SECT409R1        = 12;
<* Named curve: sect571k1. *>
const EC_SECT571K1        = 13;
<* Named curve: sect571r1. *>
const EC_SECT571R1        = 14;
<* Named curve: secp160k1. *>
const EC_SECP160K1        = 15;
<* Named curve: secp160r1. *>
const EC_SECP160R1        = 16;
<* Named curve: secp160r2. *>
const EC_SECP160R2        = 17;
<* Named curve: secp192k1. *>
const EC_SECP192K1        = 18;
<* Named curve: secp192r1. *>
const EC_SECP192R1        = 19;
<* Named curve: secp224k1. *>
const EC_SECP224K1        = 20;
<* Named curve: secp224r1. *>
const EC_SECP224R1        = 21;
<* Named curve: secp256k1. *>
const EC_SECP256K1        = 22;
<* Named curve: secp256r1 (NIST P-256). *>
const EC_SECP256R1        = 23;
<* Named curve: secp384r1 (NIST P-384). *>
const EC_SECP384R1        = 24;
<* Named curve: secp521r1 (NIST P-521). *>
const EC_SECP521R1        = 25;
<* Named curve: brainpoolP256r1. *>
const EC_BRAINPOOLP256R1  = 26;
<* Named curve: brainpoolP384r1. *>
const EC_BRAINPOOLP384R1  = 27;
<* Named curve: brainpoolP512r1. *>
const EC_BRAINPOOLP512R1  = 28;
<* Named curve: Curve25519. *>
const EC_CURVE25519       = 29;
<* Named curve: Curve448. *>
const EC_CURVE448         = 30;

// ============================================================================
// Key Structures
// ============================================================================

<*
  EC public key.

  All curve points are represented in uncompressed format.
*>
struct ECPublicKey {
    <* Curve identifier (one of the EC_* constants). *>
    int    curve;
    <* Public curve point (uncompressed format). *>
    char*  q;
    <* Length of the public curve point (in bytes). *>
    sz    qlen;
}

<*
  EC private key.

  The private key is an integer modulo the curve subgroup order, stored
  in unsigned big-endian encoding. Extra leading zeros are tolerated.
  It is recommended that the private key has the same byte length as the
  curve subgroup order.
*>
struct ECPrivateKey {
    <* Curve identifier (one of the EC_* constants). *>
    int    curve;
    <* Private key value (unsigned big-endian encoding). *>
    char*  x;
    <* Private key length (in bytes). *>
    sz    xlen;
}

// ============================================================================
// EC Implementation Vtable Function Pointer Aliases
// ============================================================================

<*
  Get the conventional generator point for a curve.

  MUST NOT be called for unsupported curves.

  param curve   curve identifier.
  param len     receives the encoded generator length (in bytes).
  return pointer to the encoded generator.
*>
alias ECGeneratorFn = fn char*(int curve, sz* len);

<*
  Get the subgroup order for a curve (unsigned big-endian).

  MUST NOT be called for unsupported curves.

  param curve   curve identifier.
  param len     receives the encoded order length (in bytes).
  return pointer to the encoded order.
*>
alias ECOrderFn     = fn char*(int curve, sz* len);

<*
  Get the byte offset and length of the X coordinate in an encoded point.

  param curve   curve identifier.
  param len     receives the X coordinate length (in bytes).
  return byte offset of the X coordinate in the encoded point.
*>
alias ECXOffFn      = fn sz(int curve, sz* len);

<*
  Multiply a curve point by an integer (in place).

  G must be a valid, non-infinity point on the curve subgroup; returns 0
  if validation fails. The multiplier x must be non-zero and less than
  the subgroup order (result is indeterminate but no error is guaranteed
  if this property is violated). Processing is constant-time.

  param G       encoded point to multiply (updated in place).
  param glen    length of the encoded point (in bytes).
  param x       multiplier (unsigned big-endian).
  param xlen    multiplier length (in bytes).
  param curve   curve identifier.
  return 1 on success, 0 on error.
*>
alias ECMulFn       = fn uint(char* G, sz glen, char* x, sz xlen, int curve);

<*
  Multiply the curve generator by an integer.

  The multiplier must be non-zero and less than the subgroup order.
  Result is written into R. May be faster than ECMulFn for the generator.

  param R       output buffer for the result point.
  param x       multiplier (unsigned big-endian).
  param xlen    multiplier length (in bytes).
  param curve   curve identifier.
  return encoded result point length (in bytes).
*>
alias ECMulGenFn    = fn sz(char* R, char* x, sz xlen, int curve);

<*
  Multiply two curve points by two integers and return their sum: x*A + y*B.

  Result is written back into A. Both A and B must be valid non-infinity
  subgroup points (returns 0 otherwise). If B is null, the conventional
  generator is used. Both multipliers must be non-zero and less than the
  subgroup order; if either is zero an error is returned, but an out-of-range
  value may yield an indeterminate result. Returns 0 if the result is the
  point at infinity. Processing is constant-time.

  param A       first point and output buffer (updated in place).
  param B       second point (null to use the generator).
  param len     common encoded length of the points (in bytes).
  param x       multiplier for A (unsigned big-endian).
  param xlen    multiplier length for A (in bytes).
  param y       multiplier for B (unsigned big-endian).
  param ylen    multiplier length for B (in bytes).
  param curve   curve identifier.
  return 1 on success, 0 on error.
*>
alias ECMulAddFn    = fn uint(char* A, char* B, sz len,
    char* x, sz xlen, char* y, sz ylen, int curve);

// ============================================================================
// EC Implementation Structure
// ============================================================================

<*
  EC implementation (vtable).

  An ECImpl instance describes a complete EC implementation, including the
  set of supported curves and all point-operation callbacks. Curve support
  is encoded as a bitmask: bit x is set if curve ID x is supported.

  Example: an implementation supporting P-256 (ID 23) and P-384 (ID 24)
  will have supported_curves = 0x01800000.
*>
struct ECImpl {
    <*
      Bitmask of supported curve identifiers.
      Bit x is set if the curve with ID x is supported.
    *>
    uint         supported_curves;

    <* Return the conventional generator point for the specified curve. *>
    ECGeneratorFn generator;

    <* Return the subgroup order for the specified curve (big-endian). *>
    ECOrderFn     order;

    <* Return the byte offset and length of the X coordinate in a point. *>
    ECXOffFn      xoff;

    <* Multiply a curve point by an integer (in place). *>
    ECMulFn       mul;

    <* Multiply the curve generator by an integer. *>
    ECMulGenFn    mulgen;

    <* Compute x*A + y*B and write the result into A. *>
    ECMulAddFn    muladd;
}

// ============================================================================
// EC Implementations — NIST Curves (secp256r1, secp384r1, secp521r1)
// ============================================================================

<*
  EC implementation "i31": generic 31-bit word modular arithmetic.
  Supports NIST P-256, P-384, and P-521.
*>
extern ECImpl ec_prime_i31;

<*
  EC implementation "i15": generic 15-bit word modular arithmetic.
  Supports NIST P-256, P-384, and P-521.
*>
extern ECImpl ec_prime_i15;

<*
  EC implementation "m15" for P-256: specialised code, 32-bit multiplications.
  Uses Karatsuba decomposition and fast modular reduction for secp256r1 only.
*>
extern ECImpl ec_p256_m15;

<*
  EC implementation "m31" for P-256: specialised code, 31-bit multiplications.
  Uses MUL31 operations for secp256r1 only.
*>
extern ECImpl ec_p256_m31;

<*
  EC implementation "m62" for P-256: specialised 64×64→128-bit multiplication.
  Available only on platforms with 64-bit multiply support.
  Use ec_p256_m62_get() to safely detect runtime availability.
*>
extern ECImpl ec_p256_m62;

<*
  Get the "m62" P-256 implementation if available at runtime.

  return the implementation pointer, or null.
*>
extern fn ECImpl* ec_p256_m62_get();

<*
  EC implementation "m64" for P-256: specialised 64×64→128-bit multiplication.
  Available only on platforms with 64-bit multiply support.
  Use ec_p256_m64_get() to safely detect runtime availability.
*>
extern ECImpl ec_p256_m64;

<*
  Get the "m64" P-256 implementation if available at runtime.

  return the implementation pointer, or null.
*>
extern fn ECImpl* ec_p256_m64_get();

// ============================================================================
// EC Implementations — Curve25519
//
// Curve25519 specifics shared by all implementations:
//   - muladd() always returns 0 (not implemented).
//   - order() returns 2^255-1; the multiplication algorithm clears the
//     top bit and the low three bits of the scalar automatically.
// ============================================================================

<*
  EC implementation "i15" for Curve25519: generic 15-bit word arithmetic.
*>
extern ECImpl ec_c25519_i15;

<*
  EC implementation "i31" for Curve25519: generic 31-bit word arithmetic.
*>
extern ECImpl ec_c25519_i31;

<*
  EC implementation "m15" for Curve25519: specialised, ≤15-bit multiplications.
*>
extern ECImpl ec_c25519_m15;

<*
  EC implementation "m31" for Curve25519: specialised, ≤31-bit multiplications.
*>
extern ECImpl ec_c25519_m31;

<*
  EC implementation "m62" for Curve25519: specialised 62-bit multiplications
  (124-bit result). Available only on platforms with 64-bit multiply support.
  Use ec_c25519_m62_get() to safely detect runtime availability.
*>
extern ECImpl ec_c25519_m62;

<*
  Get the "m62" Curve25519 implementation if available at runtime.

  return the implementation pointer, or null.
*>
extern fn ECImpl* ec_c25519_m62_get();

<*
  EC implementation "m64" for Curve25519: specialised 64×64→128-bit
  multiplication. Available only on platforms with 64-bit multiply support.
  Use ec_c25519_m64_get() to safely detect runtime availability.
*>
extern ECImpl ec_c25519_m64;

<*
  Get the "m64" Curve25519 implementation if available at runtime.

  return the implementation pointer, or null.
*>
extern fn ECImpl* ec_c25519_m64_get();

// ============================================================================
// Aggregate EC Implementations
// ============================================================================

<*
  Aggregate EC implementation "m15".

  Dispatches to: ec_c25519_m15 for Curve25519, ec_p256_m15 for P-256,
  and ec_prime_i15 for P-384 and P-521.
*>
extern ECImpl ec_all_m15;

<*
  Aggregate EC implementation "m31".

  Dispatches to: ec_c25519_m31 for Curve25519, ec_p256_m31 for P-256,
  and ec_prime_i31 for P-384 and P-521.
*>
extern ECImpl ec_all_m31;

<*
  Get the default EC implementation for the current system.

  Returns a pointer to the preferred implementation on the current platform.

  return the default EC implementation.
*>
extern fn ECImpl* ec_get_default();

// ============================================================================
// ECDSA — Signature Format Conversion
// ============================================================================

<*
  Convert an ECDSA signature from "raw" to "asn1" format (in place).

  The new length is returned. Conversion may enlarge the signature by at
  most 9 bytes. Returns 0 on error (e.g. odd raw length, oversized integer).

  param sig       signature buffer to convert (in place).
  param sig_len   current signature length (in bytes).
  return new signature length, or 0 on error.
*>
extern fn sz ecdsa_raw_to_asn1(void* sig, sz sig_len);

<*
  Convert an ECDSA signature from "asn1" to "raw" format (in place).

  The new length is returned. The raw length will be less than twice the
  asn1 length. Returns 0 on error (e.g. invalid ASN.1, oversized integer).

  param sig       signature buffer to convert (in place).
  param sig_len   current signature length (in bytes).
  return new signature length, or 0 on error.
*>
extern fn sz ecdsa_asn1_to_raw(void* sig, sz sig_len);

// ============================================================================
// ECDSA — Function Pointer Types
//
// Signature format reference (maximum sizes by curve):
//   NIST P-256: raw = 64 bytes, asn1 = 72 bytes
//   NIST P-384: raw = 96 bytes, asn1 = 104 bytes
//   NIST P-521: raw = 132 bytes, asn1 = 139 bytes
// ============================================================================

<*
  Function type for an ECDSA signer.

  Writes the signature to sig and returns its length. Returns 0 on error
  or if the curve is not supported by the EC implementation. The hash
  value is assumed to have the length defined by the hash class hf.

  param impl         EC implementation to use.
  param hf           hash function class used to produce hash_value.
  param hash_value   hashed data to sign.
  param sk           EC private key.
  param sig          destination buffer for the signature.
  return signature length (in bytes), or 0 on error.
*>
alias ECDSASignFn = fn sz(ECImpl* impl,
    HashClass* hf, void* hash_value,
    ECPrivateKey* sk, void* sig);

<*
  Function type for an ECDSA signature verifier.

  Returns 1 on a valid signature, 0 on failure or if the curve is not
  supported by the EC implementation.

  param impl       EC implementation to use.
  param hash       hashed data that was signed.
  param hash_len   hash value length (in bytes).
  param pk         EC public key.
  param sig        signature to verify.
  param sig_len    signature length (in bytes).
  return 1 on success, 0 on error.
*>
alias ECDSAVrfyFn = fn uint(ECImpl* impl,
    void* hash, sz hash_len,
    ECPublicKey* pk, void* sig, sz sig_len);

// ============================================================================
// ECDSA — Concrete Implementations
// ============================================================================

<*
  ECDSA signer, "i31" implementation, "asn1" output format.

  param impl         EC implementation to use.
  param hf           hash function class.
  param hash_value   hashed data to sign.
  param sk           EC private key.
  param sig          destination buffer.
  return signature length (in bytes), or 0 on error.
*>
extern fn sz ecdsa_i31_sign_asn1(ECImpl* impl,
    HashClass* hf, void* hash_value,
    ECPrivateKey* sk, void* sig);

<*
  ECDSA signer, "i31" implementation, "raw" output format.

  param impl         EC implementation to use.
  param hf           hash function class.
  param hash_value   hashed data to sign.
  param sk           EC private key.
  param sig          destination buffer.
  return signature length (in bytes), or 0 on error.
*>
extern fn sz ecdsa_i31_sign_raw(ECImpl* impl,
    HashClass* hf, void* hash_value,
    ECPrivateKey* sk, void* sig);

<*
  ECDSA verifier, "i31" implementation, "asn1" input format.

  param impl       EC implementation to use.
  param hash       hashed data that was signed.
  param hash_len   hash length (in bytes).
  param pk         EC public key.
  param sig        signature to verify.
  param sig_len    signature length (in bytes).
  return 1 on success, 0 on error.
*>
extern fn uint ecdsa_i31_vrfy_asn1(ECImpl* impl,
    void* hash, sz hash_len,
    ECPublicKey* pk, void* sig, sz sig_len);

<*
  ECDSA verifier, "i31" implementation, "raw" input format.

  param impl       EC implementation to use.
  param hash       hashed data that was signed.
  param hash_len   hash length (in bytes).
  param pk         EC public key.
  param sig        signature to verify.
  param sig_len    signature length (in bytes).
  return 1 on success, 0 on error.
*>
extern fn uint ecdsa_i31_vrfy_raw(ECImpl* impl,
    void* hash, sz hash_len,
    ECPublicKey* pk, void* sig, sz sig_len);

<*
  ECDSA signer, "i15" implementation, "asn1" output format.

  param impl         EC implementation to use.
  param hf           hash function class.
  param hash_value   hashed data to sign.
  param sk           EC private key.
  param sig          destination buffer.
  return signature length (in bytes), or 0 on error.
*>
extern fn sz ecdsa_i15_sign_asn1(ECImpl* impl,
    HashClass* hf, void* hash_value,
    ECPrivateKey* sk, void* sig);

<*
  ECDSA signer, "i15" implementation, "raw" output format.

  param impl         EC implementation to use.
  param hf           hash function class.
  param hash_value   hashed data to sign.
  param sk           EC private key.
  param sig          destination buffer.
  return signature length (in bytes), or 0 on error.
*>
extern fn sz ecdsa_i15_sign_raw(ECImpl* impl,
    HashClass* hf, void* hash_value,
    ECPrivateKey* sk, void* sig);

<*
  ECDSA verifier, "i15" implementation, "asn1" input format.

  param impl       EC implementation to use.
  param hash       hashed data that was signed.
  param hash_len   hash length (in bytes).
  param pk         EC public key.
  param sig        signature to verify.
  param sig_len    signature length (in bytes).
  return 1 on success, 0 on error.
*>
extern fn uint ecdsa_i15_vrfy_asn1(ECImpl* impl,
    void* hash, sz hash_len,
    ECPublicKey* pk, void* sig, sz sig_len);

<*
  ECDSA verifier, "i15" implementation, "raw" input format.

  param impl       EC implementation to use.
  param hash       hashed data that was signed.
  param hash_len   hash length (in bytes).
  param pk         EC public key.
  param sig        signature to verify.
  param sig_len    signature length (in bytes).
  return 1 on success, 0 on error.
*>
extern fn uint ecdsa_i15_vrfy_raw(ECImpl* impl,
    void* hash, sz hash_len,
    ECPublicKey* pk, void* sig, sz sig_len);

// ============================================================================
// ECDSA — Default Implementation Getters
// ============================================================================

<*
  Get the default ECDSA signer (asn1 output format) for the current system.

  return the default ECDSASignFn implementation.
*>
extern fn ECDSASignFn ecdsa_sign_asn1_get_default();

<*
  Get the default ECDSA signer (raw output format) for the current system.

  return the default ECDSASignFn implementation.
*>
extern fn ECDSASignFn ecdsa_sign_raw_get_default();

<*
  Get the default ECDSA verifier (asn1 input format) for the current system.

  return the default ECDSAVrfyFn implementation.
*>
extern fn ECDSAVrfyFn ecdsa_vrfy_asn1_get_default();

<*
  Get the default ECDSA verifier (raw input format) for the current system.

  return the default ECDSAVrfyFn implementation.
*>
extern fn ECDSAVrfyFn ecdsa_vrfy_raw_get_default();

// ============================================================================
// Key Generation
// ============================================================================

<*
  Maximum buffer size required for an EC private key element.
  Use this to size kbuf when calling ec_keygen().
*>
const EC_KBUF_PRIV_MAX_SIZE = 72;

<*
  Maximum buffer size required for an EC public key element.
  Use this to size kbuf when calling ec_compute_pub().
*>
const EC_KBUF_PUB_MAX_SIZE  = 145;

<*
  Generate a new EC private key.

  On success, sk.x is set to point into kbuf and the used byte count is
  returned. If kbuf is null, the key is not generated but the required
  buffer size is still computed and returned (sk may also be null in this
  case). If sk is null but kbuf is not null, the key is generated into
  kbuf without populating sk. Returns 0 if the curve is unsupported.

  param rng_ctx   PRNG context (already initialised).
  param impl      EC implementation to use.
  param sk        private key structure to fill (or null).
  param kbuf      key data buffer (or null); must be at least EC_KBUF_PRIV_MAX_SIZE.
  param curve     curve identifier.
  return bytes used in kbuf, or 0 on error.
*>
extern fn sz ec_keygen(PRNGClass** rng_ctx,
    ECImpl* impl, ECPrivateKey* sk,
    void* kbuf, int curve);

<*
  Compute the EC public key corresponding to an EC private key.

  The public key point is written into kbuf and pk.q is set to point there.
  The number of bytes written is returned. If kbuf is null, the point is not
  computed but its size is still returned (pk may be null in this case). If
  pk is null but kbuf is not null, the point is written into kbuf without
  populating pk. Returns 0 if the curve is unsupported.

  The private key must be valid; an out-of-range value leads to
  unpredictable results.

  param impl   EC implementation to use.
  param pk     public key structure to fill (or null).
  param kbuf   public key point buffer (or null); must be at least EC_KBUF_PUB_MAX_SIZE.
  param sk     source private key.
  return public key point length (in bytes), or 0 on error.
*>
extern fn sz ec_compute_pub(ECImpl* impl, ECPublicKey* pk,
    void* kbuf, ECPrivateKey* sk);
