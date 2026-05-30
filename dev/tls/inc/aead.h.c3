// aead.h.c3

module ext::net::tls;

import string; // libc

// ============================================================================
// AEADClass (vtable)
//
// AEAD (Authenticated Encryption with Additional Data) combines a block
// cipher in CTR mode with a MAC to provide both confidentiality and
// checked integrity. The general usage sequence is:
//
//   reset() → aad_inject() [×N] → flip() → run() [×N] → get_tag() / check_tag()
//
// Notes:
//   - Encryption is in-place; no padding is added.
//   - Additional authenticated data (AAD) must be processed before plaintext.
//   - All sizes are in bytes; no sub-byte lengths are supported.
//   - The OOP API (vtable) is NOT provided for CCM due to its requirement
//     that plaintext length be known in advance.
// ============================================================================

<*
  Reset an AEAD context for a new computation run.
  Conserves implementations and keys. Cancels any ongoing computation.
  The nonce MUST NOT be reused for the same key and distinct messages.

  param cc    AEAD context structure.
  param iv    nonce to use.
  param len   nonce length (in bytes).
*>
alias AEADResetFn        = fn void(AEADClass** cc, void* iv, sz len);

<*
  Inject additional authenticated data.
  Must be called before flip(). May be called multiple times.

  param cc     AEAD context structure.
  param data   pointer to additional authenticated data.
  param len    length of additional authenticated data (in bytes).
*>
alias AEADAadInjectFn    = fn void(AEADClass** cc, void* data, sz len);

<*
  Finish injection of additional authenticated data.
  MUST be called before run(), even if no AAD was injected.
  No AAD may be injected after this call.

  param cc   AEAD context structure.
*>
alias AEADFlipFn         = fn void(AEADClass** cc);

<*
  Encrypt or decrypt data in place.
  Must be called after flip(). May be called multiple times.
  If encrypt is non-zero, data is treated as plaintext and encrypted.
  Otherwise, data is treated as ciphertext and decrypted.

  param cc        AEAD context structure.
  param encrypt   non-zero for encryption, zero for decryption.
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
*>
alias AEADRunFn          = fn void(AEADClass** cc, int encrypt, void* data, sz len);

<*
  Compute the authentication tag into the provided buffer.
  Terminates the AEAD run; reset() must be called to start a new one.
  Tag length depends on the algorithm (e.g. 16 bytes for GCM/EAX).

  param cc    AEAD context structure.
  param tag   destination buffer for the tag.
*>
alias AEADGetTagFn       = fn void(AEADClass** cc, void* tag);

<*
  Compute and verify the authentication tag.
  Returns 1 on match, 0 on mismatch (data or tag was altered in transit).
  Terminates the AEAD run; reset() must be called to start a new one.

  param cc    AEAD context structure.
  param tag   tag value to compare with.
  returns 1 on success (exact match), 0 otherwise.
*>
alias AEADCheckTagFn     = fn uint(AEADClass** cc, void* tag);

<*
  Compute the authentication tag with explicit (possibly truncated) length.
  Shorter tags increase forgery probability; use with care.
  Terminates the AEAD run; reset() must be called to start a new one.

  param cc    AEAD context structure.
  param tag   destination buffer for the tag.
  param len   tag length (in bytes).
*>
alias AEADGetTagTruncFn  = fn void(AEADClass** cc, void* tag, sz len);

<*
  Compute and verify the authentication tag with explicit (possibly truncated) length.
  Returns 1 on match, 0 on mismatch.
  Terminates the AEAD run; reset() must be called to start a new one.

  param cc    AEAD context structure.
  param tag   tag value to compare with.
  param len   tag length (in bytes).
  returns 1 on success (exact match), 0 otherwise.
*>
alias AEADCheckTagTruncFn = fn uint(AEADClass** cc, void* tag, sz len);

<*
  Class type for an AEAD algorithm.

  Each AEAD context structure begins with a vtable pointer (first field).
  Note: no OOP initialisation method is provided, as different algorithms
  have incompatible init() signatures.
*>
struct AEADClass {
    <*
      Size (in bytes) of authentication tags produced by this algorithm.
    *>
    sz tag_size;

    <* Reset for a new computation run with a new nonce. *>
    AEADResetFn reset;

    <* Inject additional authenticated data (before flip). *>
    AEADAadInjectFn aad_inject;

    <*
      Transition from AAD to message data processing.
      Must be called even if no AAD was injected.
    *>
    AEADFlipFn flip;

    <* Encrypt or decrypt data in place (after flip). *>
    AEADRunFn run;

    <*
      Compute authentication tag (full length).
      Terminates the AEAD run.
    *>
    AEADGetTagFn get_tag;

    <*
      Compute and verify authentication tag (full length).
      Terminates the AEAD run. Returns 1 on match, 0 on mismatch.
    *>
    AEADCheckTagFn check_tag;

    <*
      Compute authentication tag with explicit (truncated) length.
      Terminates the AEAD run.
    *>
    AEADGetTagTruncFn get_tag_trunc;

    <*
      Compute and verify authentication tag with explicit (truncated) length.
      Terminates the AEAD run. Returns 1 on match, 0 on mismatch.
    *>
    AEADCheckTagTruncFn check_tag_trunc;
}

// ============================================================================
// GCM (Galois/Counter Mode)
//
// Combines a block cipher in CTR mode with GHASH for authenticated encryption.
//
//   - Any block cipher with 16-byte blocks may be used.
//   - Recommended nonce length is 12 bytes (96 bits); other lengths are
//     internally hashed, which slightly increases nonce-reuse probability.
//   - AAD may be up to 2^64-1 bits.
//   - Plaintext may be up to 2^39-256 bits (~65 GiB).
//   - Authentication tag is always 16 bytes (may be truncated).
//
// The block cipher context must already be initialised with the secret key
// before being passed to gcm_init(). Call gcm_reset() after gcm_init() to
// set the nonce and start a computation.
// ============================================================================

<*
  GCM context structure.

  The first field (vtable) may be accessed directly. All other fields are
  opaque and shall not be accessed directly.
*>
struct GCMContext {
    <* Pointer to vtable for this context. *>
    AEADClass* vtable;

    BlockCTRClass** bctx;
    GHashFn gh;
    char[16] h;
    char[12] j0_1;
    char[16] buf;
    char[16] y;
    uint j0_2;
    uint jc;
    ulong count_aad;
    ulong count_ctr;
}

<*
  Initialize a GCM context.

  The block cipher context (bctx) must already be initialised with the
  secret key and must use 16-byte blocks in CTR mode. The GHASH
  implementation (gh) is also required. These are linked into the GCM
  context (not copied). Call gcm_reset() afterwards to set the nonce.

  param ctx    GCM context structure.
  param bctx   block cipher context (already initialised with secret key).
  param gh     GHASH implementation.
*>
extern fn void gcm_init(GCMContext* ctx, BlockCTRClass** bctx, GHashFn gh);

<*
  Reset a GCM context for a new computation run.

  Conserves implementations and keys. Cancels any ongoing computation.
  The nonce MUST NOT be reused for the same key.
  Normal nonce length is 12 bytes; other lengths are supported but
  slightly increase the probability of nonce collision.

  param ctx   GCM context structure.
  param iv    GCM nonce to use.
  param len   GCM nonce length (in bytes).
*>
extern fn void gcm_reset(GCMContext* ctx, void* iv, sz len);

<*
  Inject additional authenticated data into GCM.

  Must be called before gcm_flip(). May be called multiple times.
  Total AAD may be up to 2^64-1 bits.

  param ctx    GCM context structure.
  param data   pointer to additional authenticated data.
  param len    length of additional authenticated data (in bytes).
*>
extern fn void gcm_aad_inject(GCMContext* ctx, void* data, sz len);

<*
  Finish injection of additional authenticated data into GCM.

  MUST be called before gcm_run(), even if no AAD was injected.
  No AAD may be injected after this call.

  param ctx   GCM context structure.
*>
extern fn void gcm_flip(GCMContext* ctx);

<*
  Encrypt or decrypt data with GCM (in place).

  Must be called after gcm_flip(). May be called multiple times.
  If encrypt is non-zero, treats data as plaintext and encrypts it.
  Otherwise, treats data as ciphertext and decrypts it.
  Maximum total data length is 2^39-256 bits (~65 GiB).

  param ctx       GCM context structure.
  param encrypt   non-zero for encryption, zero for decryption.
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
*>
extern fn void gcm_run(GCMContext* ctx, int encrypt, void* data, sz len);

<*
  Compute GCM authentication tag (16 bytes).

  Terminates the GCM run; gcm_reset() must be called to start a new one.
  Normally sent alongside the encrypted data. When decrypting, recompute
  and compare; use gcm_check_tag() as a convenient alternative.

  param ctx   GCM context structure.
  param tag   destination buffer for the tag (16 bytes).
*>
extern fn void gcm_get_tag(GCMContext* ctx, void* tag);

<*
  Compute and verify GCM authentication tag.

  Returns 1 on exact match, 0 on mismatch (data or tag was altered).
  Terminates the GCM run; gcm_reset() must be called to start a new one.

  param ctx   GCM context structure.
  param tag   tag value to compare with (16 bytes).
  returns 1 on success, 0 otherwise.
*>
extern fn uint gcm_check_tag(GCMContext* ctx, void* tag);

<*
  Compute GCM authentication tag with explicit (possibly truncated) length.

  len must be at most 16. NIST SP 800-38D recommends 12–16 bytes; tags
  shorter than 12 bytes increase forgery probability and should be used
  only with great care. Terminates the GCM run.

  param ctx   GCM context structure.
  param tag   destination buffer for the tag.
  param len   tag length (16 bytes or less).
*>
extern fn void gcm_get_tag_trunc(GCMContext* ctx, void* tag, sz len);

<*
  Compute and verify GCM authentication tag with explicit (possibly truncated) length.

  Returns 1 on exact match, 0 on mismatch.
  len must be at most 16. Terminates the GCM run.

  param ctx   GCM context structure.
  param tag   tag value to compare with.
  param len   tag length (in bytes).
  returns 1 on success, 0 otherwise.
*>
extern fn uint gcm_check_tag_trunc(GCMContext* ctx, void* tag, sz len);

<*
  Class instance (vtable) for GCM.
*>
extern AEADClass gcm_vtable;

// ============================================================================
// EAX
//
// Combines a block cipher in CTR mode with CBC-MAC (using the same key)
// for authenticated encryption.
//
//   - Any block cipher with 16-byte blocks may be used.
//   - Nonce may have any length; random nonces of at least 16 bytes
//     are recommended to keep reuse probability negligible.
//   - AAD length is unlimited.
//   - Plaintext length is unlimited.
//   - Authentication tag is always 16 bytes (may be truncated).
//
// EAX supports a "capture" mechanism to reduce per-message overhead when
// the same key is reused: key-dependent state can be captured before or
// after AAD processing and reused across messages with the same AAD.
// ============================================================================

<*
  EAX context structure.

  The first field (vtable) may be accessed directly. All other fields are
  opaque and shall not be accessed directly.
*>
struct EAXContext {
    <* Pointer to vtable for this context. *>
    AEADClass* vtable;

    BlockCTRCBCClass** bctx;
    char[16] L2;
    char[16] L4;
    char[16] nonce;
    char[16] head;
    char[16] ctr;
    char[16] cbcmac;
    char[16] buf;
    sz ptr;
}

<*
  EAX captured state.

  Holds key-dependent intermediate values that do not depend on the nonce.
  Can be populated before or after AAD processing and reused across
  messages with the same key (and optionally the same AAD), reducing
  per-message overhead.
*>
struct EAXState {
    char[3][16] st;
}

<*
  Initialize an EAX context.

  The block cipher context (bctx) must already be initialised with the
  secret key and must use 16-byte blocks in CTR+CBC-MAC mode. The bctx
  pointer is linked into the EAX context (not copied). Call eax_reset()
  afterwards to provide the nonce.

  param ctx    EAX context structure.
  param bctx   block cipher context (already initialised with secret key).
*>
extern fn void eax_init(EAXContext* ctx, BlockCTRCBCClass** bctx);

<*
  Capture pre-AAD state.

  Precomputes key-dependent data and stores it in st. The EAX context is
  not modified. The captured state can be used with eax_reset_pre_aad()
  or updated with eax_get_aad_mac() and then used with eax_reset_post_aad().

  param ctx   EAX context structure.
  param st    recipient for captured state.
*>
extern fn void eax_capture(EAXContext* ctx, EAXState* st);

<*
  Reset an EAX context for a new computation run.

  Conserves implementations and keys. Cancels any ongoing computation.
  Random nonces of at least 16 bytes are recommended to keep reuse
  probability negligible.

  param ctx     EAX context structure.
  param nonce   EAX nonce to use.
  param len     EAX nonce length (in bytes).
*>
extern fn void eax_reset(EAXContext* ctx, void* nonce, sz len);

<*
  Reset an EAX context using a pre-AAD captured state.

  Reuses a state captured before AAD processing for lower per-message
  overhead. The state must have been populated by eax_capture() and NOT
  yet updated with eax_get_aad_mac().

  After this call, AAD MUST be injected (at least one byte via
  eax_aad_inject()) before calling eax_flip(). At least one message byte
  must also be provided via eax_run(). Empty messages are not supported
  in this mode.

  param ctx     EAX context structure.
  param st      pre-AAD captured state.
  param nonce   EAX nonce to use.
  param len     EAX nonce length (in bytes).
*>
extern fn void eax_reset_pre_aad(EAXContext* ctx, EAXState* st,
    void* nonce, sz len);

<*
  Reset an EAX context using a post-AAD captured state.

  Reuses a state captured after AAD processing for lower per-message
  overhead. The state must have been populated by eax_capture() and then
  updated with eax_get_aad_mac().

  After this call, eax_flip() MUST NOT be called. Message data MUST be
  injected (at least one byte via eax_run()). Empty messages are not
  supported in this mode.

  param ctx     EAX context structure.
  param st      post-AAD captured state.
  param nonce   EAX nonce to use.
  param len     EAX nonce length (in bytes).
*>
extern fn void eax_reset_post_aad(EAXContext* ctx, EAXState* st,
    void* nonce, sz len);

<*
  Inject additional authenticated data into EAX.

  Must be called before eax_flip(). May be called multiple times.
  Total AAD length is unlimited.

  param ctx    EAX context structure.
  param data   pointer to additional authenticated data.
  param len    length of additional authenticated data (in bytes).
*>
extern fn void eax_aad_inject(EAXContext* ctx, void* data, sz len);

<*
  Finish injection of additional authenticated data into EAX.

  MUST be called before eax_run(), even if no AAD was injected.
  No AAD may be injected after this call.

  param ctx   EAX context structure.
*>
extern fn void eax_flip(EAXContext* ctx);

<*
  Obtain a copy of the MAC over additional authenticated data.

  May only be called after eax_flip(). Copies the AAD-specific MAC into
  the provided state structure. The MAC depends on the secret key and AAD,
  but not the nonce. The updated state is intended for use with a
  subsequent eax_reset_post_aad() call.

  param ctx   EAX context structure.
  param st    captured state to update.
*>
fn void eax_get_aad_mac(EAXContext* ctx, EAXState* st) @inline
{
    // Copy the AAD MAC (ctx.head) into st.st[1].
    string::memcpy(&st.st[1][0], &st.head[0], 16);
    
    //char* src = &ctx.head[0];
    //char* dst = &st.st[1][0];
    //for (sz i = 0; i < 16; i++) {
    //    dst[i] = src[i];
    //}
}

<*
  Encrypt or decrypt data with EAX (in place).

  Must be called after eax_flip(). May be called multiple times.
  If encrypt is non-zero, treats data as plaintext and encrypts it.
  Otherwise, treats data as ciphertext and decrypts it.

  param ctx       EAX context structure.
  param encrypt   non-zero for encryption, zero for decryption.
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
*>
extern fn void eax_run(EAXContext* ctx, int encrypt, void* data, sz len);

<*
  Compute EAX authentication tag (16 bytes).

  Terminates the EAX run; eax_reset() must be called to start a new one.

  param ctx   EAX context structure.
  param tag   destination buffer for the tag (16 bytes).
*>
extern fn void eax_get_tag(EAXContext* ctx, void* tag);

<*
  Compute and verify EAX authentication tag.

  Returns 1 on exact match, 0 on mismatch.
  Terminates the EAX run; eax_reset() must be called to start a new one.

  param ctx   EAX context structure.
  param tag   tag value to compare with (16 bytes).
  returns 1 on success, 0 otherwise.
*>
extern fn uint eax_check_tag(EAXContext* ctx, void* tag);

<*
  Compute EAX authentication tag with explicit (possibly truncated) length.

  len must be at most 16. Tags shorter than 12 bytes increase forgery
  probability and should be used with great care. Terminates the EAX run.

  param ctx   EAX context structure.
  param tag   destination buffer for the tag.
  param len   tag length (16 bytes or less).
*>
extern fn void eax_get_tag_trunc(EAXContext* ctx, void* tag, sz len);

<*
  Compute and verify EAX authentication tag with explicit (possibly truncated) length.

  Returns 1 on exact match, 0 on mismatch.
  len must be at most 16. Terminates the EAX run.

  param ctx   EAX context structure.
  param tag   tag value to compare with.
  param len   tag length (in bytes).
  returns 1 on success, 0 otherwise.
*>
extern fn uint eax_check_tag_trunc(EAXContext* ctx, void* tag, sz len);

<*
  Class instance (vtable) for EAX.
*>
extern AEADClass eax_vtable;

// ============================================================================
// CCM (Counter with CBC-MAC)
//
// Combines a block cipher in CTR mode with CBC-MAC (using the same key)
// for authenticated encryption.
//
//   - Any block cipher with 16-byte blocks may be used.
//   - Plaintext length AND tag length MUST be known before processing begins.
//   - Nonce length must be 7–13 bytes; plaintext length must fit in
//     (15 - nonce_len) bytes.
//   - AAD length is practically unlimited (up to 2^64 bytes).
//   - Authentication tag length must be 4–16 bytes and even.
//
// Note: CCM does NOT provide the OOP vtable interface (AEADClass) due to
// its requirement that plaintext/AAD lengths be declared upfront.
// ============================================================================

<*
  CCM context structure.

  All fields are opaque and shall not be accessed directly.
*>
struct CCMContext {
    BlockCTRCBCClass** bctx;
    char[16] ctr;
    char[16] cbcmac;
    char[16] tagmask;
    char[16] buf;
    sz ptr;
    sz tag_len;
}

<*
  Initialize a CCM context.

  The block cipher context (bctx) must already be initialised with the
  secret key and must use 16-byte blocks in CTR+CBC-MAC mode. The bctx
  pointer is linked into the CCM context (not copied). Call ccm_reset()
  afterwards to set the nonce and declare lengths.

  param ctx    CCM context structure.
  param bctx   block cipher context (already initialised with secret key).
*>
extern fn void ccm_init(CCMContext* ctx, BlockCTRCBCClass** bctx);

<*
  Reset a CCM context for a new computation run.

  Conserves implementations and keys. Cancels any ongoing computation.

  aad_len is the EXACT total byte length of additional authenticated data
  to be injected (may be 0). data_len is the EXACT byte length of plaintext
  or ciphertext to be processed. Both must be exact; CCM does not tolerate
  partial or mismatched lengths.

  nonce_len must be 7–13 (inclusive). data_len must be representable in
  (15 - nonce_len) bytes; if nonce_len is 13, data_len cannot exceed 65535.

  tag_len must be 4–16 and even. Shorter tags increase forgery probability;
  tags below 12 bytes should be used only with care.

  Random nonces are generally discouraged for CCM due to the small maximum
  nonce size.

  Returns 1 on success, 0 on error (tag or nonce length out of range, or
  data_len cannot be encoded with the specified nonce_len).

  param ctx         CCM context structure.
  param nonce       CCM nonce to use.
  param nonce_len   CCM nonce length (in bytes, 7 to 13).
  param aad_len     additional authenticated data length (in bytes, exact).
  param data_len    plaintext/ciphertext length (in bytes, exact).
  param tag_len     tag length (in bytes, 4 to 16, even).
  returns 1 on success, 0 on error.
*>
extern fn int ccm_reset(CCMContext* ctx, void* nonce, sz nonce_len,
    ulong aad_len, ulong data_len, sz tag_len);

<*
  Inject additional authenticated data into CCM.

  Must be called before ccm_flip(). May be called multiple times, but the
  total amount MUST exactly match the aad_len provided to ccm_reset().

  param ctx    CCM context structure.
  param data   pointer to additional authenticated data.
  param len    length of additional authenticated data (in bytes).
*>
extern fn void ccm_aad_inject(CCMContext* ctx, void* data, sz len);

<*
  Finish injection of additional authenticated data into CCM.

  MUST be called before ccm_run(), even if no AAD was injected.
  No AAD may be injected after this call.

  param ctx   CCM context structure.
*>
extern fn void ccm_flip(CCMContext* ctx);

<*
  Encrypt or decrypt data with CCM (in place).

  Must be called after ccm_flip(). May be called multiple times, but the
  total length MUST exactly match the data_len provided to ccm_reset().
  If encrypt is non-zero, treats data as plaintext and encrypts it.
  Otherwise, treats data as ciphertext and decrypts it.

  param ctx       CCM context structure.
  param encrypt   non-zero for encryption, zero for decryption.
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
*>
extern fn void ccm_run(CCMContext* ctx, int encrypt, void* data, sz len);

<*
  Compute CCM authentication tag.

  Terminates the CCM run; all data must have been injected via ccm_run().
  After this call no more data can be processed; ccm_reset() is required
  for a new message. Returns the tag length (as set in ccm_reset()).
  The tag value is written into tag (up to 16 bytes).

  param ctx   CCM context structure.
  param tag   destination buffer for the tag (up to 16 bytes).
  returns the tag length (in bytes).
*>
extern fn sz ccm_get_tag(CCMContext* ctx, void* tag);

<*
  Compute and verify CCM authentication tag.

  Returns 1 on exact match, 0 on mismatch (data or tag was altered).
  Terminates the CCM run; ccm_reset() must be called to start a new one.

  param ctx   CCM context structure.
  param tag   tag value to compare with (up to 16 bytes).
  returns 1 on success, 0 otherwise.
*>
extern fn uint ccm_check_tag(CCMContext* ctx, void* tag);
