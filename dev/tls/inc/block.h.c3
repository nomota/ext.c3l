// block.h.c3

// Block Ciphers and Symmetric Ciphers (AES, DES/3DES, ChaCha20, Poly1305)
//
// Naming conventions:
//   br_block_cbcenc_class  → BlockCBCEncClass
//   br_block_cbcdec_class  → BlockCBCDecClass
//   br_block_ctr_class     → BlockCTRClass
//   br_block_ctrcbc_class  → BlockCTRCBCClass
//   br_aes_big_cbcenc_keys → AesBigCBCEncKeys
//   br_aes_big_cbcenc_init → aes_big_cbcenc_init  (extern fn)
//   br_chacha20_run        → ChaCha20RunFn         (alias fn)
//   br_poly1305_run        → Poly1305RunFn          (alias fn)

module ext::net::tls;

// ============================================================================
// OOP Vtable Function Pointer Aliases — CBC Encryption
// ============================================================================

<*
  Key expansion (init) function for CBC encryption.

  param ctx       context structure to initialise.
  param key       secret key.
  param key_len   key length (in bytes).
*>
alias BlockCBCEncInitFn = fn void(BlockCBCEncClass** ctx, void* key, sz key_len);

<*
  CBC encryption run function.

  Encrypts len bytes in place. len MUST be a multiple of the block size.
  The IV pointed to by iv is updated with the last encrypted block.

  param ctx    context structure (already initialised).
  param iv     IV for CBC encryption (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, multiple of block size).
*>
alias BlockCBCEncRunFn  = fn void(BlockCBCEncClass** ctx, void* iv, void* data, sz len);

// ============================================================================
// OOP Vtable Function Pointer Aliases — CBC Decryption
// ============================================================================

<*
  Key expansion (init) function for CBC decryption.

  param ctx       context structure to initialise.
  param key       secret key.
  param key_len   key length (in bytes).
*>
alias BlockCBCDecInitFn = fn void(BlockCBCDecClass** ctx, void* key, sz key_len);

<*
  CBC decryption run function.

  Decrypts len bytes in place. len MUST be a multiple of the block size.
  The IV pointed to by iv is updated with the last encrypted block.

  param ctx    context structure (already initialised).
  param iv     IV for CBC decryption (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, multiple of block size).
*>
alias BlockCBCDecRunFn  = fn void(BlockCBCDecClass** ctx, void* iv, void* data, sz len);

// ============================================================================
// OOP Vtable Function Pointer Aliases — CTR
// ============================================================================

<*
  Key expansion (init) function for CTR encryption/decryption.

  param ctx       context structure to initialise.
  param key       secret key.
  param key_len   key length (in bytes).
*>
alias BlockCTRInitFn    = fn void(BlockCTRClass** ctx, void* key, sz key_len);

<*
  CTR encryption/decryption run function.

  The iv parameter is (block_size - 4) bytes (e.g. 12 bytes for AES).
  The counter cc is the 32-bit block counter; the new counter value is returned.
  Data length is not required to be a multiple of the block size.

  param ctx    context structure (already initialised).
  param iv     IV for CTR (block_size - 4 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
alias BlockCTRRunFn     = fn uint(BlockCTRClass** ctx, void* iv, uint cc, void* data, sz len);

// ============================================================================
// OOP Vtable Function Pointer Aliases — CTR + CBC-MAC (ctrcbc)
// ============================================================================

<*
  Key expansion (init) function for combined CTR + CBC-MAC.

  param ctx       context structure to initialise.
  param key       secret key.
  param key_len   key length (in bytes).
*>
alias BlockCTRCBCInitFn    = fn void(BlockCTRCBCClass** ctx, void* key, sz key_len);

<*
  CTR encryption + CBC-MAC function.

  Applies CTR encryption in place, then computes CBC-MAC over the
  encrypted output. Both ctr and cbcmac are block-sized buffers and
  are updated on return. len MUST be a multiple of the block size.

  param ctx      context structure (already initialised).
  param ctr      counter for CTR (block_size bytes, updated).
  param cbcmac   IV and output buffer for CBC-MAC (block_size bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, multiple of block size).
*>
alias BlockCTRCBCEncryptFn = fn void(BlockCTRCBCClass** ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC function.

  Computes CBC-MAC over the encrypted input first, then applies CTR
  decryption in place. Both ctr and cbcmac are block-sized buffers and
  are updated on return. len MUST be a multiple of the block size.

  param ctx      context structure (already initialised).
  param ctr      counter for CTR (block_size bytes, updated).
  param cbcmac   IV and output buffer for CBC-MAC (block_size bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, multiple of block size).
*>
alias BlockCTRCBCDecryptFn = fn void(BlockCTRCBCClass** ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR-only encryption/decryption function (no CBC-MAC).

  len MUST be a multiple of the block size.

  param ctx    context structure (already initialised).
  param ctr    counter for CTR (block_size bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, multiple of block size).
*>
alias BlockCTRCBCCtrFn     = fn void(BlockCTRCBCClass** ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC-only function (data is not modified).

  len MUST be a multiple of the block size.

  param ctx      context structure (already initialised).
  param cbcmac   IV and output buffer for CBC-MAC (block_size bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, multiple of block size).
*>
alias BlockCTRCBCMacFn     = fn void(BlockCTRCBCClass** ctx, void* cbcmac, void* data, sz len);

// ============================================================================
// OOP Vtable Structures (Class Types)
// ============================================================================

<*
  Class type for CBC encryption implementations.

  Each CBC encryption context begins with a vtable pointer.
  The vtable provides context_size, block_size, log_block_size, init, and run.
*>
struct BlockCBCEncClass {
    <* Size (in bytes) of the subkey context structure. *>
    sz      context_size;
    <* Block size in bytes (always a power of two). *>
    uint     block_size;
    <* Base-2 logarithm of block_size (e.g. 4 for 16-byte blocks). *>
    uint     log_block_size;
    <* Key expansion function; also sets the vtable field in the context. *>
    BlockCBCEncInitFn init;
    <* CBC encryption function; encrypts in place, updates IV. *>
    BlockCBCEncRunFn  run;
}

<*
  Class type for CBC decryption implementations.

  Each CBC decryption context begins with a vtable pointer.
*>
struct BlockCBCDecClass {
    <* Size (in bytes) of the subkey context structure. *>
    sz      context_size;
    <* Block size in bytes. *>
    uint     block_size;
    <* Base-2 logarithm of block_size. *>
    uint     log_block_size;
    <* Key expansion function. *>
    BlockCBCDecInitFn init;
    <* CBC decryption function; decrypts in place, updates IV. *>
    BlockCBCDecRunFn  run;
}

<*
  Class type for CTR encryption/decryption implementations.

  Each CTR context begins with a vtable pointer.
*>
struct BlockCTRClass {
    <* Size (in bytes) of the subkey context structure. *>
    sz        context_size;
    <* Block size in bytes. *>
    uint       block_size;
    <* Base-2 logarithm of block_size. *>
    uint       log_block_size;
    <* Key expansion function. *>
    BlockCTRInitFn init;
    <*
      CTR encryption/decryption function.
      Returns the new 32-bit block counter value.
    *>
    BlockCTRRunFn  run;
}

<*
  Class type for combined CTR + CBC-MAC implementations.

  Each CTR+CBC-MAC context begins with a vtable pointer.
  Used by EAX and CCM authenticated encryption modes.
*>
struct BlockCTRCBCClass {
    <* Size (in bytes) of the subkey context structure. *>
    sz              context_size;
    <* Block size in bytes. *>
    uint             block_size;
    <* Base-2 logarithm of block_size. *>
    uint             log_block_size;
    <* Key expansion function. *>
    BlockCTRCBCInitFn    init;
    <* CTR encryption + CBC-MAC over ciphertext. *>
    BlockCTRCBCEncryptFn encrypt;
    <* CBC-MAC over ciphertext + CTR decryption. *>
    BlockCTRCBCDecryptFn decrypt;
    <* CTR encryption/decryption only (no MAC). *>
    BlockCTRCBCCtrFn     ctr;
    <* CBC-MAC only (data unchanged). *>
    BlockCTRCBCMacFn     mac;
}

// ============================================================================
// AES — "aes_big": classical table-based implementation (not constant-time)
//
// Fast but uses 1 kB encryption table, 1 kB decryption table, and a 256-byte
// key schedule table. Data-dependent accesses make it vulnerable to
// cache-timing attacks. Key lengths: 16, 24, or 32 bytes.
// ============================================================================

<* AES block size (16 bytes). *>
const AES_BIG_BLOCK_SIZE = 16;

<*
  Subkey context for AES CBC encryption (aes_big implementation).

  First field is the vtable pointer, set by aes_big_cbcenc_init().
  All other fields are opaque.
*>
struct AesBigCBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CBC decryption (aes_big implementation).

  First field is the vtable pointer, set by aes_big_cbcdec_init().
*>
struct AesBigCBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CTR encryption/decryption (aes_big implementation).

  First field is the vtable pointer, set by aes_big_ctr_init().
*>
struct AesBigCTRKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRClass* vtable;
    uint[60]       skey;
    uint           num_rounds;
}

<*
  Subkey context for AES CTR + CBC-MAC (aes_big implementation).

  First field is the vtable pointer, set by aes_big_ctrcbc_init().
*>
struct AesBigCTRCBCKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRCBCClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<* Vtable instance for AES CBC encryption (aes_big). *>
extern BlockCBCEncClass aes_big_cbcenc_vtable;
<* Vtable instance for AES CBC decryption (aes_big). *>
extern BlockCBCDecClass aes_big_cbcdec_vtable;
<* Vtable instance for AES CTR encryption/decryption (aes_big). *>
extern BlockCTRClass    aes_big_ctr_vtable;
<* Vtable instance for AES CTR + CBC-MAC (aes_big). *>
extern BlockCTRCBCClass aes_big_ctrcbc_vtable;

<*
  Key schedule for AES CBC encryption (aes_big).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_big_cbcenc_init(AesBigCBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CBC decryption (aes_big).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_big_cbcdec_init(AesBigCBCDecKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR encryption/decryption (aes_big).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_big_ctr_init(AesBigCTRKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR + CBC-MAC (aes_big).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_big_ctrcbc_init(AesBigCTRCBCKeys* ctx, void* key, sz len);

<*
  CBC encryption with AES (aes_big).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_big_cbcenc_run(AesBigCBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with AES (aes_big).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_big_cbcdec_run(AesBigCBCDecKeys* ctx, void* iv, void* data, sz len);

<*
  CTR encryption/decryption with AES (aes_big).

  param ctx    context (already initialised).
  param iv     IV (12 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint aes_big_ctr_run(AesBigCTRKeys* ctx, void* iv, uint cc, void* data, sz len);

<*
  CTR encryption + CBC-MAC with AES (aes_big).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_big_ctrcbc_encrypt(AesBigCTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC with AES (aes_big).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_big_ctrcbc_decrypt(AesBigCTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR encryption/decryption only with AES (aes_big).

  param ctx    context (already initialised).
  param ctr    counter for CTR (16 bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_big_ctrcbc_ctr(AesBigCTRCBCKeys* ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC with AES (aes_big).

  param ctx      context (already initialised).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_big_ctrcbc_mac(AesBigCTRCBCKeys* ctx, void* cbcmac, void* data, sz len);

// ============================================================================
// AES — "aes_small": size-optimised implementation (not constant-time)
//
// Slower than aes_big; smaller code footprint using a 256-byte table.
// Still subject to cache-timing attacks. Key lengths: 16, 24, or 32 bytes.
// ============================================================================

<* AES block size (16 bytes). *>
const AES_SMALL_BLOCK_SIZE = 16;

<*
  Subkey context for AES CBC encryption (aes_small implementation).
*>
struct AesSmallCBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CBC decryption (aes_small implementation).
*>
struct AesSmallCBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CTR encryption/decryption (aes_small implementation).
*>
struct AesSmallCTRKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRClass* vtable;
    uint[60]       skey;
    uint           num_rounds;
}

<*
  Subkey context for AES CTR + CBC-MAC (aes_small implementation).
*>
struct AesSmallCTRCBCKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRCBCClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<* Vtable instance for AES CBC encryption (aes_small). *>
extern BlockCBCEncClass aes_small_cbcenc_vtable;
<* Vtable instance for AES CBC decryption (aes_small). *>
extern BlockCBCDecClass aes_small_cbcdec_vtable;
<* Vtable instance for AES CTR encryption/decryption (aes_small). *>
extern BlockCTRClass    aes_small_ctr_vtable;
<* Vtable instance for AES CTR + CBC-MAC (aes_small). *>
extern BlockCTRCBCClass aes_small_ctrcbc_vtable;

<*
  Key schedule for AES CBC encryption (aes_small).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_small_cbcenc_init(AesSmallCBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CBC decryption (aes_small).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_small_cbcdec_init(AesSmallCBCDecKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR encryption/decryption (aes_small).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_small_ctr_init(AesSmallCTRKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR + CBC-MAC (aes_small).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_small_ctrcbc_init(AesSmallCTRCBCKeys* ctx, void* key, sz len);

<*
  CBC encryption with AES (aes_small).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_small_cbcenc_run(AesSmallCBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with AES (aes_small).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_small_cbcdec_run(AesSmallCBCDecKeys* ctx, void* iv, void* data, sz len);

<*
  CTR encryption/decryption with AES (aes_small).

  param ctx    context (already initialised).
  param iv     IV (12 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint aes_small_ctr_run(AesSmallCTRKeys* ctx, void* iv, uint cc, void* data, sz len);

<*
  CTR encryption + CBC-MAC with AES (aes_small).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_small_ctrcbc_encrypt(AesSmallCTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC with AES (aes_small).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_small_ctrcbc_decrypt(AesSmallCTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR encryption/decryption only with AES (aes_small).

  param ctx    context (already initialised).
  param ctr    counter for CTR (16 bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_small_ctrcbc_ctr(AesSmallCTRCBCKeys* ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC with AES (aes_small).

  param ctx      context (already initialised).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_small_ctrcbc_mac(AesSmallCTRCBCKeys* ctx, void* cbcmac, void* data, sz len);

// ============================================================================
// AES — "aes_ct": 32-bit constant-time implementation
//
// Constant-time; immune to cache-timing attacks. Code size similar to
// aes_big; performance similar to aes_small. Recommended default for AES
// unless hardware acceleration or a non-CT context is available.
// Key lengths: 16, 24, or 32 bytes.
// ============================================================================

<* AES block size (16 bytes). *>
const AES_CT_BLOCK_SIZE = 16;

<*
  Subkey context for AES CBC encryption (aes_ct implementation).
*>
struct AesCTCBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CBC decryption (aes_ct implementation).
*>
struct AesCTCBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CTR encryption/decryption (aes_ct implementation).
*>
struct AesCTCTRKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRClass* vtable;
    uint[60]       skey;
    uint           num_rounds;
}

<*
  Subkey context for AES CTR + CBC-MAC (aes_ct implementation).
*>
struct AesCTCTRCBCKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRCBCClass* vtable;
    uint[60]          skey;
    uint              num_rounds;
}

<* Vtable instance for AES CBC encryption (aes_ct). *>
extern BlockCBCEncClass aes_ct_cbcenc_vtable;
<* Vtable instance for AES CBC decryption (aes_ct). *>
extern BlockCBCDecClass aes_ct_cbcdec_vtable;
<* Vtable instance for AES CTR encryption/decryption (aes_ct). *>
extern BlockCTRClass    aes_ct_ctr_vtable;
<* Vtable instance for AES CTR + CBC-MAC (aes_ct). *>
extern BlockCTRCBCClass aes_ct_ctrcbc_vtable;

<*
  Key schedule for AES CBC encryption (aes_ct).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct_cbcenc_init(AesCTCBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CBC decryption (aes_ct).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct_cbcdec_init(AesCTCBCDecKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR encryption/decryption (aes_ct).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct_ctr_init(AesCTCTRKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR + CBC-MAC (aes_ct).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct_ctrcbc_init(AesCTCTRCBCKeys* ctx, void* key, sz len);

<*
  CBC encryption with AES (aes_ct).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct_cbcenc_run(AesCTCBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with AES (aes_ct).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct_cbcdec_run(AesCTCBCDecKeys* ctx, void* iv, void* data, sz len);

<*
  CTR encryption/decryption with AES (aes_ct).

  param ctx    context (already initialised).
  param iv     IV (12 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint aes_ct_ctr_run(AesCTCTRKeys* ctx, void* iv, uint cc, void* data, sz len);

<*
  CTR encryption + CBC-MAC with AES (aes_ct).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct_ctrcbc_encrypt(AesCTCTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC with AES (aes_ct).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct_ctrcbc_decrypt(AesCTCTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR encryption/decryption only with AES (aes_ct).

  param ctx    context (already initialised).
  param ctr    counter for CTR (16 bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct_ctrcbc_ctr(AesCTCTRCBCKeys* ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC with AES (aes_ct).

  param ctx      context (already initialised).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct_ctrcbc_mac(AesCTCTRCBCKeys* ctx, void* cbcmac, void* data, sz len);

// ============================================================================
// AES — "aes_ct64": 64-bit constant-time implementation
//
// Constant-time; uses 64-bit registers. On 64-bit platforms, approximately
// twice as fast as aes_ct for CTR and CBC decryption (parallel modes).
// CBC encryption cannot benefit from wider registers (sequential). Larger
// code footprint than aes_ct on 32-bit. Key lengths: 16, 24, or 32 bytes.
// ============================================================================

<* AES block size (16 bytes). *>
const AES_CT64_BLOCK_SIZE = 16;

<*
  Subkey context for AES CBC encryption (aes_ct64 implementation).
*>
struct AesCT64CBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    ulong[30]         skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CBC decryption (aes_ct64 implementation).
*>
struct AesCT64CBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    ulong[30]         skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CTR encryption/decryption (aes_ct64 implementation).
*>
struct AesCT64CTRKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRClass* vtable;
    ulong[30]      skey;
    uint           num_rounds;
}

<*
  Subkey context for AES CTR + CBC-MAC (aes_ct64 implementation).
*>
struct AesCT64CTRCBCKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRCBCClass* vtable;
    ulong[30]         skey;
    uint              num_rounds;
}

<* Vtable instance for AES CBC encryption (aes_ct64). *>
extern BlockCBCEncClass aes_ct64_cbcenc_vtable;
<* Vtable instance for AES CBC decryption (aes_ct64). *>
extern BlockCBCDecClass aes_ct64_cbcdec_vtable;
<* Vtable instance for AES CTR encryption/decryption (aes_ct64). *>
extern BlockCTRClass    aes_ct64_ctr_vtable;
<* Vtable instance for AES CTR + CBC-MAC (aes_ct64). *>
extern BlockCTRCBCClass aes_ct64_ctrcbc_vtable;

<*
  Key schedule for AES CBC encryption (aes_ct64).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct64_cbcenc_init(AesCT64CBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CBC decryption (aes_ct64).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct64_cbcdec_init(AesCT64CBCDecKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR encryption/decryption (aes_ct64).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct64_ctr_init(AesCT64CTRKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR + CBC-MAC (aes_ct64).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_ct64_ctrcbc_init(AesCT64CTRCBCKeys* ctx, void* key, sz len);

<*
  CBC encryption with AES (aes_ct64).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct64_cbcenc_run(AesCT64CBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with AES (aes_ct64).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct64_cbcdec_run(AesCT64CBCDecKeys* ctx, void* iv, void* data, sz len);

<*
  CTR encryption/decryption with AES (aes_ct64).

  param ctx    context (already initialised).
  param iv     IV (12 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint aes_ct64_ctr_run(AesCT64CTRKeys* ctx, void* iv, uint cc, void* data, sz len);

<*
  CTR encryption + CBC-MAC with AES (aes_ct64).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct64_ctrcbc_encrypt(AesCT64CTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC with AES (aes_ct64).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct64_ctrcbc_decrypt(AesCT64CTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR encryption/decryption only with AES (aes_ct64).

  param ctx    context (already initialised).
  param ctr    counter for CTR (16 bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct64_ctrcbc_ctr(AesCT64CTRCBCKeys* ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC with AES (aes_ct64).

  param ctx      context (already initialised).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_ct64_ctrcbc_mac(AesCT64CTRCBCKeys* ctx, void* cbcmac, void* data, sz len);

// ============================================================================
// AES — "aes_x86ni": x86 AES-NI hardware implementation
//
// Uses AES-NI opcodes (available on most modern x86/x86-64 CPUs).
// Constant-time and very fast. Available only when compiled for x86.
// Use aes_x86ni_*_get_vtable() to safely detect runtime availability.
// Key lengths: 16, 24, or 32 bytes. skey stores 15 round keys × 16 bytes.
// ============================================================================

<* AES block size (16 bytes). *>
const AES_X86NI_BLOCK_SIZE = 16;

<*
  Subkey context for AES CBC encryption (aes_x86ni implementation).
*>
struct AesX86NICBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    char[240]         skey;       // 16 * 15 bytes of round key material
    uint              num_rounds;
}

<*
  Subkey context for AES CBC decryption (aes_x86ni implementation).
*>
struct AesX86NICBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    char[240]         skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CTR encryption/decryption (aes_x86ni implementation).
*>
struct AesX86NICTRKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRClass* vtable;
    char[240]      skey;
    uint           num_rounds;
}

<*
  Subkey context for AES CTR + CBC-MAC (aes_x86ni implementation).
*>
struct AesX86NICTRCBCKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRCBCClass* vtable;
    char[240]         skey;
    uint              num_rounds;
}

<*
  Vtable instance for AES CBC encryption (aes_x86ni).
  Obtain safely via aes_x86ni_cbcenc_get_vtable() to check availability.
*>
extern BlockCBCEncClass aes_x86ni_cbcenc_vtable;

<*
  Vtable instance for AES CBC decryption (aes_x86ni).
  Obtain safely via aes_x86ni_cbcdec_get_vtable() to check availability.
*>
extern BlockCBCDecClass aes_x86ni_cbcdec_vtable;

<*
  Vtable instance for AES CTR encryption/decryption (aes_x86ni).
  Obtain safely via aes_x86ni_ctr_get_vtable() to check availability.
*>
extern BlockCTRClass    aes_x86ni_ctr_vtable;

<*
  Vtable instance for AES CTR + CBC-MAC (aes_x86ni).
  Obtain safely via aes_x86ni_ctrcbc_get_vtable() to check availability.
*>
extern BlockCTRCBCClass aes_x86ni_ctrcbc_vtable;

<*
  Key schedule for AES CBC encryption (aes_x86ni).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_x86ni_cbcenc_init(AesX86NICBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CBC decryption (aes_x86ni).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_x86ni_cbcdec_init(AesX86NICBCDecKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR encryption/decryption (aes_x86ni).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_x86ni_ctr_init(AesX86NICTRKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR + CBC-MAC (aes_x86ni).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_x86ni_ctrcbc_init(AesX86NICTRCBCKeys* ctx, void* key, sz len);

<*
  CBC encryption with AES (aes_x86ni).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_x86ni_cbcenc_run(AesX86NICBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with AES (aes_x86ni).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_x86ni_cbcdec_run(AesX86NICBCDecKeys* ctx, void* iv, void* data, sz len);

<*
  CTR encryption/decryption with AES (aes_x86ni).

  param ctx    context (already initialised).
  param iv     IV (12 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint aes_x86ni_ctr_run(AesX86NICTRKeys* ctx, void* iv, uint cc, void* data, sz len);

<*
  CTR encryption + CBC-MAC with AES (aes_x86ni).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_x86ni_ctrcbc_encrypt(AesX86NICTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC with AES (aes_x86ni).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_x86ni_ctrcbc_decrypt(AesX86NICTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR encryption/decryption only with AES (aes_x86ni).

  param ctx    context (already initialised).
  param ctr    counter for CTR (16 bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_x86ni_ctrcbc_ctr(AesX86NICTRCBCKeys* ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC with AES (aes_x86ni).

  param ctx      context (already initialised).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_x86ni_ctrcbc_mac(AesX86NICTRCBCKeys* ctx, void* cbcmac, void* data, sz len);

<*
  Get the aes_x86ni CBC encryption vtable if available at runtime.

  Returns a pointer to aes_x86ni_cbcenc_vtable if the implementation was
  compiled in and the current CPU supports AES-NI; otherwise returns null.

  return the aes_x86ni CBC encryption vtable, or null.
*>
extern fn BlockCBCEncClass* aes_x86ni_cbcenc_get_vtable();

<*
  Get the aes_x86ni CBC decryption vtable if available at runtime.

  return the aes_x86ni CBC decryption vtable, or null.
*>
extern fn BlockCBCDecClass* aes_x86ni_cbcdec_get_vtable();

<*
  Get the aes_x86ni CTR vtable if available at runtime.

  return the aes_x86ni CTR vtable, or null.
*>
extern fn BlockCTRClass* aes_x86ni_ctr_get_vtable();

<*
  Get the aes_x86ni CTR + CBC-MAC vtable if available at runtime.

  return the aes_x86ni CTR + CBC-MAC vtable, or null.
*>
extern fn BlockCTRCBCClass* aes_x86ni_ctrcbc_get_vtable();

// ============================================================================
// AES — "aes_pwr8": POWER8 AES hardware implementation
//
// Uses AES opcodes present in POWER8 and later (PowerPC/POWER, 32/64-bit,
// both endiannesses). Constant-time and fast. Use aes_pwr8_*_get_vtable()
// to safely detect runtime availability. Key lengths: 16, 24, or 32 bytes.
// ============================================================================

<* AES block size (16 bytes). *>
const AES_PWR8_BLOCK_SIZE = 16;

<*
  Subkey context for AES CBC encryption (aes_pwr8 implementation).
*>
struct AesPWR8CBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    char[240]         skey;       // 16 * 15 bytes
    uint              num_rounds;
}

<*
  Subkey context for AES CBC decryption (aes_pwr8 implementation).
*>
struct AesPWR8CBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    char[240]         skey;
    uint              num_rounds;
}

<*
  Subkey context for AES CTR encryption/decryption (aes_pwr8 implementation).
*>
struct AesPWR8CTRKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRClass* vtable;
    char[240]      skey;
    uint           num_rounds;
}

<*
  Subkey context for AES CTR + CBC-MAC (aes_pwr8 implementation).
*>
struct AesPWR8CTRCBCKeys {
    <* Pointer to vtable for this context. *>
    BlockCTRCBCClass* vtable;
    char[240]         skey;
    uint              num_rounds;
}

<*
  Vtable instance for AES CBC encryption (aes_pwr8).
  Obtain safely via aes_pwr8_cbcenc_get_vtable() to check availability.
*>
extern BlockCBCEncClass aes_pwr8_cbcenc_vtable;

<*
  Vtable instance for AES CBC decryption (aes_pwr8).
  Obtain safely via aes_pwr8_cbcdec_get_vtable() to check availability.
*>
extern BlockCBCDecClass aes_pwr8_cbcdec_vtable;

<*
  Vtable instance for AES CTR encryption/decryption (aes_pwr8).
  Obtain safely via aes_pwr8_ctr_get_vtable() to check availability.
*>
extern BlockCTRClass    aes_pwr8_ctr_vtable;

<*
  Vtable instance for AES CTR + CBC-MAC (aes_pwr8).
  Obtain safely via aes_pwr8_ctrcbc_get_vtable() to check availability.
*>
extern BlockCTRCBCClass aes_pwr8_ctrcbc_vtable;

<*
  Key schedule for AES CBC encryption (aes_pwr8).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_pwr8_cbcenc_init(AesPWR8CBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CBC decryption (aes_pwr8).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_pwr8_cbcdec_init(AesPWR8CBCDecKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR encryption/decryption (aes_pwr8).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_pwr8_ctr_init(AesPWR8CTRKeys* ctx, void* key, sz len);

<*
  Key schedule for AES CTR + CBC-MAC (aes_pwr8).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (16, 24, or 32 bytes).
*>
extern fn void aes_pwr8_ctrcbc_init(AesPWR8CTRCBCKeys* ctx, void* key, sz len);

<*
  CBC encryption with AES (aes_pwr8).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_pwr8_cbcenc_run(AesPWR8CBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with AES (aes_pwr8).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_pwr8_cbcdec_run(AesPWR8CBCDecKeys* ctx, void* iv, void* data, sz len);

<*
  CTR encryption/decryption with AES (aes_pwr8).

  param ctx    context (already initialised).
  param iv     IV (12 bytes, constant).
  param cc     initial block counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint aes_pwr8_ctr_run(AesPWR8CTRKeys* ctx, void* iv, uint cc, void* data, sz len);

<*
  CTR encryption + CBC-MAC with AES (aes_pwr8).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to encrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_pwr8_ctrcbc_encrypt(AesPWR8CTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR decryption + CBC-MAC with AES (aes_pwr8).

  param ctx      context (already initialised).
  param ctr      counter for CTR (16 bytes, updated).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to decrypt (in place).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_pwr8_ctrcbc_decrypt(AesPWR8CTRCBCKeys* ctx, void* ctr, void* cbcmac, void* data, sz len);

<*
  CTR encryption/decryption only with AES (aes_pwr8).

  param ctx    context (already initialised).
  param ctr    counter for CTR (16 bytes, updated).
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_pwr8_ctrcbc_ctr(AesPWR8CTRCBCKeys* ctx, void* ctr, void* data, sz len);

<*
  CBC-MAC with AES (aes_pwr8).

  param ctx      context (already initialised).
  param cbcmac   IV for CBC-MAC (16 bytes, updated).
  param data     data to MAC (unmodified).
  param len      data length (in bytes, MUST be a multiple of 16).
*>
extern fn void aes_pwr8_ctrcbc_mac(AesPWR8CTRCBCKeys* ctx, void* cbcmac, void* data, sz len);

<*
  Get the aes_pwr8 CBC encryption vtable if available at runtime.

  return the aes_pwr8 CBC encryption vtable, or null.
*>
extern fn BlockCBCEncClass* aes_pwr8_cbcenc_get_vtable();

<*
  Get the aes_pwr8 CBC decryption vtable if available at runtime.

  return the aes_pwr8 CBC decryption vtable, or null.
*>
extern fn BlockCBCDecClass* aes_pwr8_cbcdec_get_vtable();

<*
  Get the aes_pwr8 CTR vtable if available at runtime.

  return the aes_pwr8 CTR vtable, or null.
*>
extern fn BlockCTRClass* aes_pwr8_ctr_get_vtable();

<*
  Get the aes_pwr8 CTR + CBC-MAC vtable if available at runtime.

  return the aes_pwr8 CTR + CBC-MAC vtable, or null.
*>
extern fn BlockCTRCBCClass* aes_pwr8_ctrcbc_get_vtable();

// ============================================================================
// AES Aggregate Union Types
//
// These unions are large enough to hold the subkey context for any AES
// implementation. Use them to allocate a context without knowing which
// implementation will be selected at runtime.
// ============================================================================

<*
  Aggregate context for AES CBC encryption — covers all implementations.

  The vtable field can be read directly to dispatch operations once
  the context has been initialised by one of the aes_*_cbcenc_init() functions.
*>
union AesGenCBCEncKeys {
    BlockCBCEncClass*   vtable;
    AesBigCBCEncKeys    c_big;
    AesSmallCBCEncKeys  c_small;
    AesCTCBCEncKeys     c_ct;
    AesCT64CBCEncKeys   c_ct64;
    AesX86NICBCEncKeys  c_x86ni;
    AesPWR8CBCEncKeys   c_pwr8;
}

<*
  Aggregate context for AES CBC decryption — covers all implementations.
*>
union AesGenCBCDecKeys {
    BlockCBCDecClass*   vtable;
    AesBigCBCDecKeys    c_big;
    AesSmallCBCDecKeys  c_small;
    AesCTCBCDecKeys     c_ct;
    AesCT64CBCDecKeys   c_ct64;
    AesX86NICBCDecKeys  c_x86ni;
    AesPWR8CBCDecKeys   c_pwr8;
}

<*
  Aggregate context for AES CTR encryption/decryption — covers all implementations.
*>
union AesGenCTRKeys {
    BlockCTRClass*      vtable;
    AesBigCTRKeys       c_big;
    AesSmallCTRKeys     c_small;
    AesCTCTRKeys        c_ct;
    AesCT64CTRKeys      c_ct64;
    AesX86NICTRKeys     c_x86ni;
    AesPWR8CTRKeys      c_pwr8;
}

<*
  Aggregate context for AES CTR + CBC-MAC — covers all implementations.
*>
union AesGenCTRCBCKeys {
    BlockCTRCBCClass*   vtable;
    AesBigCTRCBCKeys    c_big;
    AesSmallCTRCBCKeys  c_small;
    AesCTCTRCBCKeys     c_ct;
    AesCT64CTRCBCKeys   c_ct64;
    AesX86NICTRCBCKeys  c_x86ni;
    AesPWR8CTRCBCKeys   c_pwr8;
}

// ============================================================================
// DES / 3DES — "des_tab": table-based implementation (not constant-time)
//
// Classical, table-based DES/3DES. Fast but subject to cache-timing attacks.
// Key lengths: 8 bytes (DES), 16 bytes (2-key 3DES), 24 bytes (3-key 3DES).
// Note: some bits in each byte are ignored (effective security: 56/112/168 bits).
// Only CBC mode is provided (no CTR for 8-byte block ciphers).
// ============================================================================

<* DES/3DES block size (8 bytes). *>
const DES_TAB_BLOCK_SIZE = 8;

<*
  Subkey context for DES CBC encryption (des_tab implementation).
*>
struct DesTabCBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    uint[96]          skey;
    uint              num_rounds;
}

<*
  Subkey context for DES CBC decryption (des_tab implementation).
*>
struct DesTabCBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    uint[96]          skey;
    uint              num_rounds;
}

<* Vtable instance for DES CBC encryption (des_tab). *>
extern BlockCBCEncClass des_tab_cbcenc_vtable;
<* Vtable instance for DES CBC decryption (des_tab). *>
extern BlockCBCDecClass des_tab_cbcdec_vtable;

<*
  Key schedule for DES CBC encryption (des_tab).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (8, 16, or 24 bytes).
*>
extern fn void des_tab_cbcenc_init(DesTabCBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for DES CBC decryption (des_tab).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (8, 16, or 24 bytes).
*>
extern fn void des_tab_cbcdec_init(DesTabCBCDecKeys* ctx, void* key, sz len);

<*
  CBC encryption with DES (des_tab).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 8).
*>
extern fn void des_tab_cbcenc_run(DesTabCBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with DES (des_tab).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 8).
*>
extern fn void des_tab_cbcdec_run(DesTabCBCDecKeys* ctx, void* iv, void* data, sz len);

// ============================================================================
// DES / 3DES — "des_ct": constant-time implementation
//
// Constant-time DES/3DES; immune to cache-timing attacks.
// Approximately 4× slower than des_tab. Same key lengths.
// ============================================================================

<* DES/3DES block size (8 bytes). *>
const DES_CT_BLOCK_SIZE = 8;

<*
  Subkey context for DES CBC encryption (des_ct implementation).
*>
struct DesCTCBCEncKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCEncClass* vtable;
    uint[96]          skey;
    uint              num_rounds;
}

<*
  Subkey context for DES CBC decryption (des_ct implementation).
*>
struct DesCTCBCDecKeys {
    <* Pointer to vtable for this context. *>
    BlockCBCDecClass* vtable;
    uint[96]          skey;
    uint              num_rounds;
}

<* Vtable instance for DES CBC encryption (des_ct). *>
extern BlockCBCEncClass des_ct_cbcenc_vtable;
<* Vtable instance for DES CBC decryption (des_ct). *>
extern BlockCBCDecClass des_ct_cbcdec_vtable;

<*
  Key schedule for DES CBC encryption (des_ct).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (8, 16, or 24 bytes).
*>
extern fn void des_ct_cbcenc_init(DesCTCBCEncKeys* ctx, void* key, sz len);

<*
  Key schedule for DES CBC decryption (des_ct).

  param ctx   context to initialise.
  param key   secret key.
  param len   secret key length (8, 16, or 24 bytes).
*>
extern fn void des_ct_cbcdec_init(DesCTCBCDecKeys* ctx, void* key, sz len);

<*
  CBC encryption with DES (des_ct).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to encrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 8).
*>
extern fn void des_ct_cbcenc_run(DesCTCBCEncKeys* ctx, void* iv, void* data, sz len);

<*
  CBC decryption with DES (des_ct).

  param ctx    context (already initialised).
  param iv     IV (updated).
  param data   data to decrypt (in place).
  param len    data length (in bytes, MUST be a multiple of 8).
*>
extern fn void des_ct_cbcdec_run(DesCTCBCDecKeys* ctx, void* iv, void* data, sz len);

// ============================================================================
// DES Aggregate Union Types
// ============================================================================

<*
  Aggregate context for DES CBC encryption — covers des_tab and des_ct.
*>
union DesGenCBCEncKeys {
    BlockCBCEncClass* vtable;
    DesTabCBCEncKeys  tab;
    DesCTCBCEncKeys   ct;
}

<*
  Aggregate context for DES CBC decryption — covers des_tab and des_ct.
*>
union DesGenCBCDecKeys {
    BlockCBCDecClass* vtable;
    DesTabCBCDecKeys  c_tab;
    DesCTCBCDecKeys   c_ct;
}

// ============================================================================
// ChaCha20
//
// Stream cipher described in RFC 7539. Key is 256 bits (32 bytes), IV is
// 96 bits (12 bytes), block counter is 32 bits. Data is encrypted/decrypted
// in place. If len is not a multiple of 64, excess keystream bytes from
// the last block are dropped (chunked processing requires non-final chunks
// to be multiples of 64 bytes).
// ============================================================================

<*
  Function type for a ChaCha20 implementation (RFC 7539).

  param key    secret key (32 bytes).
  param iv     nonce (12 bytes).
  param cc     initial counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
alias ChaCha20RunFn = fn uint(void* key, void* iv, uint cc, void* data, sz len);

<*
  ChaCha20 implementation: straightforward C code, constant-time.

  param key    secret key (32 bytes).
  param iv     nonce (12 bytes).
  param cc     initial counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint chacha20_ct_run(void* key, void* iv, uint cc, void* data, sz len);

<*
  ChaCha20 implementation: SSE2 code, constant-time (x86 only).

  Available only on x86 platforms with SSE2 support. Use
  chacha20_sse2_get() to safely detect availability at runtime.

  param key    secret key (32 bytes).
  param iv     nonce (12 bytes).
  param cc     initial counter value.
  param data   data to encrypt or decrypt (in place).
  param len    data length (in bytes).
  return new block counter value.
*>
extern fn uint chacha20_sse2_run(void* key, void* iv, uint cc, void* data, sz len);

<*
  Get the SSE2 ChaCha20 implementation if available at runtime.

  Returns a function pointer to chacha20_sse2_run if the implementation
  was compiled in and the current CPU supports SSE2; otherwise returns null.

  return the sse2 ChaCha20 implementation, or null.
*>
extern fn ChaCha20RunFn chacha20_sse2_get();

// ============================================================================
// Poly1305 (ChaCha20+Poly1305 AEAD, RFC 7539)
//
// Poly1305 is a MAC combined with ChaCha20 for authenticated encryption.
// The tag is computed over the concatenation of AAD and ciphertext, with
// padding and length fields as described in RFC 7539 section 2.8.
// The ChaCha20 implementation is provided as a function pointer (ichacha),
// allowing the best available implementation to be supplied at runtime.
// After decryption the caller must verify the tag.
// ============================================================================

<*
  Function type for a ChaCha20+Poly1305 AEAD implementation.

  param key       secret key (32 bytes).
  param iv        nonce (12 bytes).
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
  param aad       additional authenticated data.
  param aad_len   AAD length (in bytes).
  param tag       output buffer for the authentication tag (16 bytes).
  param ichacha   ChaCha20 implementation to use.
  param encrypt   non-zero for encryption, zero for decryption.
*>
alias Poly1305RunFn = fn void(
    void* key, void* iv,
    void* data, sz len,
    void* aad, sz aad_len,
    void* tag, ChaCha20RunFn ichacha, int encrypt);

<*
  ChaCha20+Poly1305 AEAD implementation using mixed 32-bit multiplications.

  param key       secret key (32 bytes).
  param iv        nonce (12 bytes).
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
  param aad       additional authenticated data.
  param aad_len   AAD length (in bytes).
  param tag       output buffer for the authentication tag (16 bytes).
  param ichacha   ChaCha20 implementation to use.
  param encrypt   non-zero for encryption, zero for decryption.
*>
extern fn void poly1305_ctmul_run(
    void* key, void* iv,
    void* data, sz len,
    void* aad, sz aad_len,
    void* tag, ChaCha20RunFn ichacha, int encrypt);

<*
  ChaCha20+Poly1305 AEAD implementation using pure 32-bit multiplications.

  Slower than ctmul on most architectures; faster on some (e.g. ARM Cortex M0+).

  param key       secret key (32 bytes).
  param iv        nonce (12 bytes).
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
  param aad       additional authenticated data.
  param aad_len   AAD length (in bytes).
  param tag       output buffer for the authentication tag (16 bytes).
  param ichacha   ChaCha20 implementation to use.
  param encrypt   non-zero for encryption, zero for decryption.
*>
extern fn void poly1305_ctmul32_run(
    void* key, void* iv,
    void* data, sz len,
    void* aad, sz aad_len,
    void* tag, ChaCha20RunFn ichacha, int encrypt);

<*
  ChaCha20+Poly1305 AEAD implementation using the generic "i15" big-integer code.

  Useful for minimising code footprint when i15 is already included (e.g. for
  ECC or RSA). Substantially slower than ctmul and ctmul32.

  param key       secret key (32 bytes).
  param iv        nonce (12 bytes).
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
  param aad       additional authenticated data.
  param aad_len   AAD length (in bytes).
  param tag       output buffer for the authentication tag (16 bytes).
  param ichacha   ChaCha20 implementation to use.
  param encrypt   non-zero for encryption, zero for decryption.
*>
extern fn void poly1305_i15_run(
    void* key, void* iv,
    void* data, sz len,
    void* aad, sz aad_len,
    void* tag, ChaCha20RunFn ichacha, int encrypt);

<*
  ChaCha20+Poly1305 AEAD implementation using 64-bit multiplications (ctmulq).

  Uses 64×64→128-bit multiplications. Available only on 64-bit platforms that
  provide this primitive. Use poly1305_ctmulq_get() to safely detect
  availability at runtime.

  param key       secret key (32 bytes).
  param iv        nonce (12 bytes).
  param data      data to encrypt or decrypt (in place).
  param len       data length (in bytes).
  param aad       additional authenticated data.
  param aad_len   AAD length (in bytes).
  param tag       output buffer for the authentication tag (16 bytes).
  param ichacha   ChaCha20 implementation to use.
  param encrypt   non-zero for encryption, zero for decryption.
*>
extern fn void poly1305_ctmulq_run(
    void* key, void* iv,
    void* data, sz len,
    void* aad, sz aad_len,
    void* tag, ChaCha20RunFn ichacha, int encrypt);

<*
  Get the ctmulq ChaCha20+Poly1305 implementation if available at runtime.

  Returns a function pointer to poly1305_ctmulq_run if supported on the
  current platform; otherwise returns null.

  return the ctmulq Poly1305 implementation, or null.
*>
extern fn Poly1305RunFn poly1305_ctmulq_get();
