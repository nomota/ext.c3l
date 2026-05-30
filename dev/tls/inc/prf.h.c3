// prf.h.c3

// TLS Pseudorandom Functions (PRF)
//
// Naming conventions:
//   br_tls_prf_seed_chunk  → TLSPRFSeedChunk
//   br_tls_prf_impl        → TLSPRFImplFn     (alias fn)
//   br_tls10_prf           → tls10_prf        (extern fn)
//   br_tls12_sha256_prf    → tls12_sha256_prf (extern fn)
//   br_tls12_sha384_prf    → tls12_sha384_prf (extern fn)
//
// Overview:
//   The TLS PRF expands a shared secret into symmetric key material during
//   the SSL/TLS handshake. All three implementations share the same
//   parameter shape:
//
//     dst        — output buffer (arbitrary length)
//     secret     — input secret / key material
//     label      — NUL-terminated ASCII label string
//     seed       — array of seed chunks (concatenated internally)
//
//   TLS 1.0/1.1 uses MD5 + SHA-1 internally (tls10_prf).
//   TLS 1.2     uses a single explicit hash function:
//                 SHA-256 (tls12_sha256_prf) — used by most cipher suites
//                 SHA-384 (tls12_sha384_prf) — used by some cipher suites

module ext::net::tls;

// ============================================================================
// Seed Chunk
// ============================================================================

<*
  A single chunk of PRF seed data.

  The seed is provided as an array of chunks that are concatenated
  internally before use. Each chunk may have any length, including zero;
  if len is zero, data may be null.
*>
struct TLSPRFSeedChunk {
    <* Pointer to the chunk data (may be null when len is zero). *>
    void* data;
    <* Chunk length (in bytes). *>
    sz   len;
}

// ============================================================================
// PRF Function Pointer Type
// ============================================================================

<*
  Function pointer type for a TLS PRF implementation.

  Shared signature for tls10_prf, tls12_sha256_prf, and tls12_sha384_prf,
  allowing them to be stored and called interchangeably at runtime.

  param dst          destination buffer for the PRF output.
  param len          number of output bytes to produce.
  param secret       secret value (key material) for this computation.
  param secret_len   secret length (in bytes).
  param label        PRF label (NUL-terminated ASCII string).
  param seed_num     number of seed chunks in the seed array.
  param seed         array of seed chunks (concatenated internally).
*>
alias TLSPRFImplFn = fn void(
    void*              dst,
    sz                len,
    void*              secret,
    sz                secret_len,
    char*              label,
    sz                seed_num,
    TLSPRFSeedChunk*   seed);

// ============================================================================
// PRF Implementations
// ============================================================================

<*
  PRF for TLS 1.0 and TLS 1.1 (MD5 + SHA-1).

  Implements the PRF specified by RFC 2246 (TLS 1.0) and RFC 4346
  (TLS 1.1), which internally uses both MD5 and SHA-1 via the P_hash
  construction over HMAC.

  param dst          destination buffer for the PRF output.
  param len          number of output bytes to produce.
  param secret       secret value (key material) for this computation.
  param secret_len   secret length (in bytes).
  param label        PRF label (NUL-terminated ASCII string).
  param seed_num     number of seed chunks in the seed array.
  param seed         array of seed chunks (concatenated internally).
*>
extern fn void tls10_prf(
    void*              dst,
    sz                len,
    void*              secret,
    sz                secret_len,
    char*              label,
    sz                seed_num,
    TLSPRFSeedChunk*   seed);

<*
  PRF for TLS 1.2 with SHA-256.

  Implements the PRF specified by RFC 5246 (TLS 1.2) using SHA-256 as
  the underlying hash function. Used by the majority of TLS 1.2 cipher
  suites.

  param dst          destination buffer for the PRF output.
  param len          number of output bytes to produce.
  param secret       secret value (key material) for this computation.
  param secret_len   secret length (in bytes).
  param label        PRF label (NUL-terminated ASCII string).
  param seed_num     number of seed chunks in the seed array.
  param seed         array of seed chunks (concatenated internally).
*>
extern fn void tls12_sha256_prf(
    void*              dst,
    sz                len,
    void*              secret,
    sz                secret_len,
    char*              label,
    sz                seed_num,
    TLSPRFSeedChunk*   seed);

<*
  PRF for TLS 1.2 with SHA-384.

  Implements the PRF specified by RFC 5246 (TLS 1.2) using SHA-384 as
  the underlying hash function. Used by cipher suites that explicitly
  require SHA-384 (e.g. TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384).

  param dst          destination buffer for the PRF output.
  param len          number of output bytes to produce.
  param secret       secret value (key material) for this computation.
  param secret_len   secret length (in bytes).
  param label        PRF label (NUL-terminated ASCII string).
  param seed_num     number of seed chunks in the seed array.
  param seed         array of seed chunks (concatenated internally).
*>
extern fn void tls12_sha384_prf(
    void*              dst,
    sz                len,
    void*              secret,
    sz                secret_len,
    char*              label,
    sz                seed_num,
    TLSPRFSeedChunk*   seed);
