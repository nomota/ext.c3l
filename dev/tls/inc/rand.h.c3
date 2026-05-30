// rand.h.c3

// Pseudo-Random Generators (PRNG): HMAC_DRBG and AESCTR_DRBG
//
// Naming conventions:
//   br_prng_class              → PRNGClass
//   br_prng_seeder             → PRNGSeederFn     (alias fn)
//   br_hmac_drbg_context       → HMACDRBGContext
//   br_aesctr_drbg_context     → AESCTRDRBGContext
//   br_hmac_drbg_init          → hmac_drbg_init   (extern fn)
//   br_prng_seeder_system      → prng_seeder_system (extern fn)

module ext::net::tls;

// ============================================================================
// PRNG Vtable Function Pointer Aliases
// ============================================================================

<*
  PRNG initialisation function.

  Sets the vtable pointer in the context (first field) and initialises
  internal state using the provided seed. Extra params are implementation-
  defined (e.g. a HashClass* for HMAC_DRBG, a BlockCTRClass* for AESCTR_DRBG).

  param ctx        PRNG context to initialise (pointer to first field).
  param params     implementation-defined extra parameters (may be null).
  param seed       initial seed bytes.
  param seed_len   initial seed length (in bytes).
*>
alias PRNGInitFn     = fn void(PRNGClass** ctx, void* params, void* seed, sz seed_len);

<*
  Produce pseudo-random bytes.

  Writes len bytes into out and updates the context accordingly.
  Formally, HMAC_DRBG requests over 65536 bytes are out of NIST spec
  (but will not fail in this implementation).

  param ctx   PRNG context.
  param out   output buffer.
  param len   number of pseudo-random bytes to produce.
*>
alias PRNGGenerateFn = fn void(PRNGClass** ctx, void* out, sz len);

<*
  Inject additional entropy into the PRNG.

  Adds seed bytes to the PRNG's internal entropy pool without replacing
  existing entropy; injecting known/attacker-controlled bytes does not
  degrade the quality of future output.

  param ctx        PRNG context.
  param seed       additional seed bytes.
  param seed_len   additional seed length (in bytes).
*>
alias PRNGUpdateFn   = fn void(PRNGClass** ctx, void* seed, sz seed_len);

// ============================================================================
// PRNG Vtable Structure
// ============================================================================

<*
  Class type for PRNG implementations (vtable).

  A constant PRNGClass instance is defined for each implemented PRNG and
  is pointed to by the first field of each corresponding context structure.
  The OOP API dispatches through these function pointers.
*>
struct PRNGClass {
    <* Size (in bytes) of the context structure for this PRNG. *>
    sz          context_size;

    <*
      Initialise the PRNG context with an initial seed.
      Also sets the vtable pointer in the context.
    *>
    PRNGInitFn     init;

    <* Produce pseudo-random bytes into the output buffer. *>
    PRNGGenerateFn generate;

    <* Inject additional entropy into the PRNG state. *>
    PRNGUpdateFn   update;
}

// ============================================================================
// PRNG Seeder
// ============================================================================

<*
  Function type for an entropy seeder.

  A seeder obtains random values from an OS or hardware source and injects
  them into a PRNG context as an initial seed. It guarantees at least 128
  bits of entropy. Transient errors are retried internally; a returned
  failure may be treated as permanent by the caller.

  param ctx   PRNG context to seed (pointer to first field).
  return 1 on success, 0 on error.
*>
alias PRNGSeederFn = fn int(PRNGClass** ctx);

<*
  Get a system or hardware entropy seeder, if available.

  Returns a seeder backed by OS or hardware RNG facilities. If no such
  facility is known, null is returned. If name is not null, *name is set
  to a symbolic string identifying the seeder; if no seeder is available
  and name is not null, *name is set to "none".

  param name   receives the seeder name string, or null.
  return a system seeder function pointer, or null.
*>
extern fn PRNGSeederFn prng_seeder_system(char** name);

// ============================================================================
// HMAC_DRBG
//
// Defined in NIST SP 800-90A Rev. 1. Uses HMAC over a configurable hash
// function. In this implementation:
//   - The reseed counter is not maintained (NIST limit: 2^48 requests).
//   - Requests over 65536 bytes (NIST limit: 2^19 bits) are permitted but
//     formally out of spec. No known security penalty applies.
//   - Usage within SSL/TLS stays well within both NIST thresholds.
//
// Initialise with hmac_drbg_init(), passing a HashClass* as the
// digest_class parameter to select the underlying hash function
// (SHA-1 or SHA-2 per NIST; other hash functions work but are non-standard).
// ============================================================================

<*
  Context for HMAC_DRBG.

  The first field (vtable) is set by hmac_drbg_init() and may be read
  directly. All other fields are opaque.
*>
struct HMACDRBGContext {
    <* Pointer to the PRNG vtable for this context. *>
    PRNGClass*  vtable;
    char[64]    k;
    char[64]    v;
    HashClass*  digest_class;
}

<*
  Statically allocated vtable for HMAC_DRBG.
*>
extern PRNGClass hmac_drbg_vtable;

<*
  Initialise an HMAC_DRBG context.

  Sets the vtable pointer and initialises internal state. The seed value
  corresponds to the concatenation of the NIST "seed", "nonce", and
  "personalization string" in that order. The digest_class parameter
  selects the underlying hash function (SHA-1 or a SHA-2 variant per
  NIST; other hash functions work but are non-standard).

  param ctx            HMAC_DRBG context to initialise.
  param digest_class   vtable for the underlying hash function.
  param seed           initial seed bytes.
  param seed_len       initial seed length (in bytes).
*>
extern fn void hmac_drbg_init(HMACDRBGContext* ctx,
    HashClass* digest_class, void* seed, sz seed_len);

<*
  Generate pseudo-random bytes with HMAC_DRBG.

  Writes len bytes into out and updates the context. Requesting more than
  65536 bytes in one call is formally outside NIST limits but will not fail.

  param ctx   HMAC_DRBG context.
  param out   output buffer.
  param len   number of pseudo-random bytes to produce.
*>
extern fn void hmac_drbg_generate(HMACDRBGContext* ctx, void* out, sz len);

<*
  Inject additional entropy into HMAC_DRBG.

  Adds seed bytes to the internal pool without replacing existing entropy.
  Injecting known or attacker-controlled bytes does not degrade output quality.

  param ctx        HMAC_DRBG context.
  param seed       additional seed bytes.
  param seed_len   additional seed length (in bytes).
*>
extern fn void hmac_drbg_update(HMACDRBGContext* ctx, void* seed, sz seed_len);

<*
  Get the hash function vtable used by an HMAC_DRBG context.

  MUST NOT be called on an uninitialised context.

  param ctx   HMAC_DRBG context (already initialised).
  return the hash function vtable.
*>
fn HashClass* hmac_drbg_get_hash(HMACDRBGContext* ctx) @inline
{
    return ctx.digest_class;
}

// ============================================================================
// AESCTR_DRBG
//
// A custom PRNG based on AES-128 in CTR mode. Intended for situations
// requiring maximum throughput with a hardware-accelerated AES/CTR
// implementation. Benchmarks show a 15–20% improvement in RSA key
// generation over HMAC_DRBG on a recent x86 CPU.
//
// Internally: CTR mode starting at counter zero (128-bit big-endian).
// The counter is not allowed to reach 32768; at most every 32768 × 16
// bytes the update() function is invoked. update() derives the new
// AES-128 key using Hirose's construction over AES-256.
//
// NOTE: This DRBG does not follow any existing standard and has not
// been formally analysed. It should not be used in production until
// that analysis has been completed.
//
// The aesctr parameter to aesctr_drbg_init() must be a BlockCTRClass*
// pointing to an AES/CTR vtable (e.g. from aes_ct_ctr_vtable).
// ============================================================================

<*
  Context for AESCTR_DRBG.

  The first field (vtable) is set by aesctr_drbg_init() and may be read
  directly. All other fields are opaque.
*>
struct AESCTRDRBGContext {
    <* Pointer to the PRNG vtable for this context. *>
    PRNGClass*      vtable;
    AesGenCTRKeys   sk;
    uint            cc;
}

<*
  Statically allocated vtable for AESCTR_DRBG.
*>
extern PRNGClass aesctr_drbg_vtable;

<*
  Initialise an AESCTR_DRBG context.

  Sets the vtable pointer and initialises internal state. The internal
  AES key is first set to the all-zero key; then aesctr_drbg_update() is
  called with the provided seed (even if seed_len is zero). The aesctr
  parameter selects the AES/CTR implementation to use.

  param ctx        AESCTR_DRBG context to initialise.
  param aesctr     vtable for the AES/CTR implementation.
  param seed       initial seed bytes (may be null if seed_len is zero).
  param seed_len   initial seed length (in bytes).
*>
extern fn void aesctr_drbg_init(AESCTRDRBGContext* ctx,
    BlockCTRClass* aesctr, void* seed, sz seed_len);

<*
  Generate pseudo-random bytes with AESCTR_DRBG.

  Writes len bytes into out and updates the context accordingly.

  param ctx   AESCTR_DRBG context.
  param out   output buffer.
  param len   number of pseudo-random bytes to produce.
*>
extern fn void aesctr_drbg_generate(AESCTRDRBGContext* ctx, void* out, sz len);

<*
  Inject additional entropy into AESCTR_DRBG.

  Adds seed bytes to the internal pool without replacing existing entropy.
  Injecting known or attacker-controlled bytes does not degrade output quality.

  param ctx        AESCTR_DRBG context.
  param seed       additional seed bytes.
  param seed_len   additional seed length (in bytes).
*>
extern fn void aesctr_drbg_update(AESCTRDRBGContext* ctx, void* seed, sz seed_len);
