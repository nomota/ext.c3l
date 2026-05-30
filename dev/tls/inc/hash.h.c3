// hash.h.c3

module ext::net::tls;

// ============================================================================
// Hash Function Symbolic Identifiers
//
// These match the TLS standard identifiers (RFC 5246 §7.4.1.4.1):
//   MD5=1, SHA-1=2, SHA-224=3, SHA-256=4, SHA-384=5, SHA-512=6
// MD5+SHA-1 is non-standard and is assigned 0.
// ============================================================================

<*
  Symbolic identifier for MD5.
*>
const MD5_ID     = 1;

<*
  Symbolic identifier for SHA-1.
*>
const SHA1_ID    = 2;

<*
  Symbolic identifier for SHA-224.
*>
const SHA224_ID  = 3;

<*
  Symbolic identifier for SHA-256.
*>
const SHA256_ID  = 4;

<*
  Symbolic identifier for SHA-384.
*>
const SHA384_ID  = 5;

<*
  Symbolic identifier for SHA-512.
*>
const SHA512_ID  = 6;

<*
  Symbolic identifier for MD5+SHA-1 (not a TLS-standard function; value 0).
*>
const MD5SHA1_ID = 0;

// ============================================================================
// Hash Output Sizes (in bytes)
// ============================================================================

<* MD5 output size in bytes. *>
const MD5_SIZE     = 16;

<* SHA-1 output size in bytes. *>
const SHA1_SIZE    = 20;

<* SHA-224 output size in bytes. *>
const SHA224_SIZE  = 28;

<* SHA-256 output size in bytes. *>
const SHA256_SIZE  = 32;

<* SHA-384 output size in bytes. *>
const SHA384_SIZE  = 48;

<* SHA-512 output size in bytes. *>
const SHA512_SIZE  = 64;

<* MD5+SHA-1 output size in bytes (36 = 16 + 20). *>
const MD5SHA1_SIZE = 36;

// ============================================================================
// HashClass Descriptor Field Offsets and Masks
//
// Use these to unpack fields from HashClass.desc:
//   (desc >> HASHDESC_xxx_OFF) & HASHDESC_xxx_MASK
//
// Fields:
//   ID     - symbolic identifier (MD5=1 .. SHA-512=6)
//   OUT    - hash output size in bytes
//   STATE  - internal running state size in bytes
//   LBLEN  - log2 of the internal block size (6 for 64-byte blocks,
//             7 for 128-byte blocks used by SHA-384/512)
// ============================================================================

const HASHDESC_ID_OFF       = 0;
const HASHDESC_ID_MASK      = 0xFF;

const HASHDESC_OUT_OFF      = 8;
const HASHDESC_OUT_MASK     = 0x7F;

const HASHDESC_STATE_OFF    = 15;
const HASHDESC_STATE_MASK   = 0xFF;

const HASHDESC_LBLEN_OFF    = 23;
const HASHDESC_LBLEN_MASK   = 0x0F;

<* Descriptor flag: Merkle-Damgård padding is used. *>
const HASHDESC_MD_PADDING     = (uint)1 << 28;

<* Descriptor flag: padding length field is 128-bit (SHA-384/512). *>
const HASHDESC_MD_PADDING_128 = (uint)1 << 29;

<* Descriptor flag: padding length field is big-endian. *>
const HASHDESC_MD_PADDING_BE  = (uint)1 << 30;

// ============================================================================
// HashClass (vtable)
// ============================================================================

// Forward-declare function pointer aliases for HashClass methods.

<*
  Initialise (or reset) a hash context for a new computation.
  Sets the vtable pointer as the first field of the context.
*>
alias HashInitFn     = fn void(HashClass** ctx);

<*
  Inject data bytes into a running hash computation.
  If len is 0, data is ignored and nothing happens.
*>
alias HashUpdateFn   = fn void(HashClass** ctx, void* data, sz len);

<*
  Produce hash output into dst. The context is NOT modified,
  so further bytes may be injected to continue the computation.
*>
alias HashOutFn      = fn void(HashClass** ctx, void* dst);

<*
  Save the current running state into dst.
  Returns the total number of bytes injected so far.
  The context is not modified.
*>
alias HashStateFn    = fn ulong(HashClass** ctx, void* dst);

<*
  Restore the running state from stb, with count being the total
  injected byte length. Does NOT set the vtable pointer.
*>
alias HashSetStateFn = fn void(HashClass** ctx, void* stb, ulong count);

<*
  Class type for hash function implementations.

  Constant instances (vtables) are defined for each implemented hash
  function. The vtable provides an OOP interface: init(), update(),
  out(), state(), and set_state() methods, plus informative fields
  context_size and desc.

  Assumptions for users of the OOP API:
    - Hash output size is at most 64 bytes.
    - Hash internal state size is at most 64 bytes.
    - Internal block size is a power of two between 16 and 256.
*>
struct HashClass {
    <*
      Size (in bytes) of the context structure for this hash function.
      Used by generic implementations for dynamic context allocation.
    *>
    sz context_size;

    <*
      Descriptor word encoding information about the hash function.
      Unpack using HASHDESC_xxx_OFF / HASHDESC_xxx_MASK constants.
      Fields: ID, OUT (output size), STATE (state size), LBLEN (log2 block size).
    *>
    uint desc;

    <* Initialise (or reset) a context for a new computation. *>
    HashInitFn init;

    <*
      Inject data bytes. len=0 is a no-op.
    *>
    HashUpdateFn update;

    <*
      Produce hash output. Context is not modified.
    *>
    HashOutFn out;

    <*
      Save running state. Returns total injected byte count.
    *>
    HashStateFn state;

    <*
      Restore running state. Does not set the vtable pointer.
    *>
    HashSetStateFn set_state;
}

// ============================================================================
// MD5
// ============================================================================

<* Constant vtable for MD5. *>
extern HashClass md5_vtable;

<*
  MD5 context.

  The first field (vtable) is set by md5_init(). Other fields are opaque.
*>
struct MD5Context {
    <* Pointer to vtable for this context. *>
    HashClass* vtable;

    char[64] buf;
    ulong count;
    uint[4] val;
}

<*
  Initialise or reset a context for a new MD5 computation.
  Also sets the vtable pointer.

  param ctx   pointer to the context structure.
*>
extern fn void md5_init(MD5Context* ctx);

<*
  Inject data bytes into a running MD5 computation.
  If len is 0, data is ignored and this function does nothing.

  param ctx    pointer to the context structure.
  param data   pointer to the injected data.
  param len    injected data length (in bytes).
*>
extern fn void md5_update(MD5Context* ctx, void* data, sz len);

<*
  Compute MD5 output.
  The context is not modified; further bytes may be injected afterwards.

  param ctx   pointer to the context structure.
  param out   destination buffer for the hash output.
*>
extern fn void md5_out(MD5Context* ctx, void* out);

<*
  Save MD5 running state into out.
  Returns the total number of bytes injected since last init/reset.
  The context is not modified.

  param ctx   pointer to the context structure.
  param out   destination buffer for the running state.
  returns the injected total byte length.
*>
extern fn ulong md5_state(MD5Context* ctx, void* out);

<*
  Restore MD5 running state.

  param ctx     pointer to the context structure.
  param stb     source buffer for the running state.
  param count   the injected total byte length.
*>
extern fn void md5_set_state(MD5Context* ctx, void* stb, ulong count);

// ============================================================================
// SHA-1
// ============================================================================

<* Constant vtable for SHA-1. *>
extern HashClass sha1_vtable;

<*
  SHA-1 context.

  The first field (vtable) is set by sha1_init(). Other fields are opaque.
*>
struct SHA1Context {
    <* Pointer to vtable for this context. *>
    HashClass* vtable;

    char[64] buf;
    ulong count;
    uint[5] val;
}

<*
  Initialise or reset a context for a new SHA-1 computation.
  Also sets the vtable pointer.
*>
extern fn void sha1_init(SHA1Context* ctx);

<*
  Inject data bytes into a running SHA-1 computation.
  If len is 0, data is ignored and this function does nothing.
*>
extern fn void sha1_update(SHA1Context* ctx, void* data, sz len);

<*
  Compute SHA-1 output. The context is not modified.
*>
extern fn void sha1_out(SHA1Context* ctx, void* out);

<*
  Save SHA-1 running state into out.
  Returns the total number of bytes injected since last init/reset.
*>
extern fn ulong sha1_state(SHA1Context* ctx, void* out);

<*
  Restore SHA-1 running state.
*>
extern fn void sha1_set_state(SHA1Context* ctx, void* stb, ulong count);

// ============================================================================
// SHA-224
// ============================================================================

<* Constant vtable for SHA-224. *>
extern HashClass sha224_vtable;

<*
  SHA-224 context.

  The first field (vtable) is set by sha224_init(). Other fields are opaque.
  Note: SHA-256 shares this same context layout.
*>
struct SHA224Context {
    <* Pointer to vtable for this context. *>
    HashClass* vtable;

    char[64] buf;
    ulong count;
    uint[8] val;
}

<*
  Initialise or reset a context for a new SHA-224 computation.
  Also sets the vtable pointer.
*>
extern fn void sha224_init(SHA224Context* ctx);

<*
  Inject data bytes into a running SHA-224 computation.
  If len is 0, data is ignored and this function does nothing.
*>
extern fn void sha224_update(SHA224Context* ctx, void* data, sz len);

<*
  Compute SHA-224 output. The context is not modified.
*>
extern fn void sha224_out(SHA224Context* ctx, void* out);

<*
  Save SHA-224 running state into out.
  Returns the total number of bytes injected since last init/reset.
*>
extern fn ulong sha224_state(SHA224Context* ctx, void* out);

<*
  Restore SHA-224 running state.
*>
extern fn void sha224_set_state(SHA224Context* ctx, void* stb, ulong count);

// ============================================================================
// SHA-256
//
// SHA-256 shares the same context layout as SHA-224. The update(),
// state(), and set_state() functions are identical to the SHA-224 versions.
// ============================================================================

<* Constant vtable for SHA-256. *>
extern HashClass sha256_vtable;

<*
  SHA-256 context.

  SHA-256 and SHA-224 use an identical context layout; this is an alias.
*>
alias SHA256Context = SHA224Context;

<*
  Initialise or reset a context for a new SHA-256 computation.
  Also sets the vtable pointer.
*>
extern fn void sha256_init(SHA256Context* ctx);

<*
  Compute SHA-256 output. The context is not modified.
*>
extern fn void sha256_out(SHA256Context* ctx, void* out);

// SHA-256 update / state / set_state are identical to SHA-224:
// use sha224_update(), sha224_state(), sha224_set_state() directly.

// ============================================================================
// SHA-384
// ============================================================================

<* Constant vtable for SHA-384. *>
extern HashClass sha384_vtable;

<*
  SHA-384 context.

  The first field (vtable) is set by sha384_init(). Other fields are opaque.
  Note: SHA-512 shares this same context layout.
*>
struct SHA384Context {
    <* Pointer to vtable for this context. *>
    HashClass* vtable;

    char[128] buf;
    ulong count;
    ulong[8] val;
}

<*
  Initialise or reset a context for a new SHA-384 computation.
  Also sets the vtable pointer.
*>
extern fn void sha384_init(SHA384Context* ctx);

<*
  Inject data bytes into a running SHA-384 computation.
  If len is 0, data is ignored and this function does nothing.
*>
extern fn void sha384_update(SHA384Context* ctx, void* data, sz len);

<*
  Compute SHA-384 output. The context is not modified.
*>
extern fn void sha384_out(SHA384Context* ctx, void* out);

<*
  Save SHA-384 running state into out.
  Returns the total number of bytes injected since last init/reset.
*>
extern fn ulong sha384_state(SHA384Context* ctx, void* out);

<*
  Restore SHA-384 running state.
*>
extern fn void sha384_set_state(SHA384Context* ctx, void* stb, ulong count);

// ============================================================================
// SHA-512
//
// SHA-512 shares the same context layout as SHA-384. The update(),
// state(), and set_state() functions are identical to the SHA-384 versions.
// ============================================================================

<* Constant vtable for SHA-512. *>
extern HashClass sha512_vtable;

<*
  SHA-512 context.

  SHA-512 and SHA-384 use an identical context layout; this is an alias.
*>
alias SHA512Context = SHA384Context;

<*
  Initialise or reset a context for a new SHA-512 computation.
  Also sets the vtable pointer.
*>
extern fn void sha512_init(SHA512Context* ctx);

<*
  Compute SHA-512 output. The context is not modified.
*>
extern fn void sha512_out(SHA512Context* ctx, void* out);

// SHA-512 update / state / set_state are identical to SHA-384:
// use sha384_update(), sha384_state(), sha384_set_state() directly.

// ============================================================================
// MD5+SHA-1
//
// Computes MD5 and SHA-1 simultaneously over the same input, producing
// a 36-byte output (MD5 || SHA-1). Shares an internal data buffer for
// efficiency. Useful for SSL 3.0, TLS 1.0, and TLS 1.1.
// ============================================================================

<* Constant vtable for MD5+SHA-1. *>
extern HashClass md5sha1_vtable;

<*
  MD5+SHA-1 context.

  The first field (vtable) is set by md5sha1_init(). Other fields are opaque.
*>
struct MD5SHA1Context {
    <* Pointer to vtable for this context. *>
    HashClass* vtable;

    char[64] buf;
    ulong count;
    uint[4] val_md5;
    uint[5] val_sha1;
}

<*
  Initialise or reset a context for a new MD5+SHA-1 computation.
  Also sets the vtable pointer.
*>
extern fn void md5sha1_init(MD5SHA1Context* ctx);

<*
  Inject data bytes into a running MD5+SHA-1 computation.
  If len is 0, data is ignored and this function does nothing.
*>
extern fn void md5sha1_update(MD5SHA1Context* ctx, void* data, sz len);

<*
  Compute MD5+SHA-1 output (36 bytes: MD5 then SHA-1).
  The context is not modified.
*>
extern fn void md5sha1_out(MD5SHA1Context* ctx, void* out);

<*
  Save MD5+SHA-1 running state into out.
  Returns the total number of bytes injected since last init/reset.
*>
extern fn ulong md5sha1_state(MD5SHA1Context* ctx, void* out);

<*
  Restore MD5+SHA-1 running state.
*>
extern fn void md5sha1_set_state(MD5SHA1Context* ctx, void* stb, ulong count);

// ============================================================================
// HashCompatContext — union large enough to hold any standard hash context
// ============================================================================

<*
  Aggregate context for configurable hash function support.

  Large enough to serve as context for all standard hash functions
  (MD5, SHA-1, SHA-224, SHA-256, SHA-384, SHA-512, MD5+SHA-1).
*>
union HashCompatContext {
    HashClass* vtable;
    MD5Context md5;
    SHA1Context sha1;
    SHA224Context sha224;
    SHA256Context sha256;
    SHA384Context sha384;
    SHA512Context sha512;
    MD5SHA1Context md5sha1;
}

// ============================================================================
// Multi-Hasher
//
// Computes up to six standard hash functions (MD5, SHA-1, SHA-224, SHA-256,
// SHA-384, SHA-512) in parallel over a single shared input buffer.
// Which functions are active depends on which vtables are configured.
// Does NOT use the HashClass vtable OOP structure.
// ============================================================================

<*
  Multi-hasher context structure.

  Runs up to six standard hash functions in parallel over the same input.
  Configure implementations with multihash_setimpl() after calling
  multihash_zero(), then start hashing with multihash_init().
  Fields are opaque; do not access directly.
*>
struct MultiHashContext {
    char[128] buf;
    ulong count;
    uint[25] val_32;
    ulong[16] val_64;
    HashClass*[6] impl;
}

<*
  Clear a multi-hasher context.

  Must be called once before setting any implementation pointers.

  param ctx   the multi-hasher context.
*>
extern fn void multihash_zero(MultiHashContext* ctx);

<*
  Set a hash function implementation in a multi-hasher.

  Must be called after multihash_zero() and before multihash_init().
  id must be one of the standard identifiers (MD5_ID=1 .. SHA512_ID=6).
  Pass null for impl to remove that function from the multi-hasher.

  param ctx    the multi-hasher context.
  param id     hash function symbolic identifier (1 to 6).
  param impl   hash function vtable, or null.
*>
fn void multihash_setimpl(MultiHashContext* ctx, int id, HashClass* impl) @inline
{
    ctx.impl[id - 1] = impl;
}

<*
  Get a hash function implementation from a multi-hasher.

  Returns the currently configured vtable for the given hash function id,
  or null if none was configured.

  param ctx    the multi-hasher context.
  param id     hash function symbolic identifier (1 to 6).
  returns the hash function vtable, or null.
*>
fn HashClass* multihash_getimpl(MultiHashContext* ctx, int id) @inline
{
    return ctx.impl[id - 1];
}

<*
  Reset a multi-hasher context for a new hashing computation.

  Prepares the context for all currently configured implementations.

  param ctx   the multi-hasher context.
*>
extern fn void multihash_init(MultiHashContext* ctx);

<*
  Inject data bytes into a running multi-hashing computation.
  If len is 0, data is ignored and this function does nothing.

  param ctx    pointer to the context structure.
  param data   pointer to the injected data.
  param len    injected data length (in bytes).
*>
extern fn void multihash_update(MultiHashContext* ctx, void* data, sz len);

<*
  Compute a hash output from a multi-hasher.

  The hash for all bytes injected since the last init/reset is written
  into dst for the given hash function id. Returns the output length in
  bytes, or 0 if that hash function was not configured. The context is
  not modified.

  param ctx   pointer to the context structure.
  param id    hash function symbolic identifier.
  param dst   destination buffer for the hash output.
  returns the hash output length (in bytes), or 0.
*>
extern fn sz multihash_out(MultiHashContext* ctx, int id, void* dst);

// ============================================================================
// GHASH
//
// GHASH is a universal hash function used within GCM encryption mode.
// It is NOT a general-purpose cryptographic hash function.
//
// The y array (16 bytes) is used as both input and output; it starts
// all-zero in a fresh GCM computation. h is a 16-byte key derived from
// the block cipher key. Data is implicitly zero-padded to a multiple of
// 16 bytes, which matches GCM's rules for associated data and ciphertext.
// ============================================================================

<*
  Type for a GHASH implementation.

  param y      16-byte input/output array (updated in place).
  param h      16-byte GHASH key.
  param data   input data (may be null if len is 0).
  param len    input data length (in bytes).
*>
alias GHashFn = fn void(void* y, void* h, void* data, sz len);

<*
  GHASH implementation using mixed 32-bit multiplications (32×32→64).
  Constant-time if multiplications are constant-time.
*>
extern fn void ghash_ctmul(void* y, void* h, void* data, sz len);

<*
  GHASH implementation using strict 32-bit multiplications (32×32→32).
  Slower than ghash_ctmul() on most platforms, but faster on architectures
  where the 32-bit multiply does not produce the upper 32 bits.
  Constant-time if multiplications are constant-time.
*>
extern fn void ghash_ctmul32(void* y, void* h, void* data, sz len);

<*
  GHASH implementation using 64-bit multiplications (64×64→64).
  Substantially faster than the 32-bit variants on most 64-bit platforms.
  Constant-time if multiplications are constant-time.
*>
extern fn void ghash_ctmul64(void* y, void* h, void* data, sz len);

<*
  GHASH implementation using the pclmulqdq opcode (x86 AES-NI).

  Only available on x86 platforms where the compiler supports the
  relevant intrinsics AND the CPU supports pclmulqdq. Calling this on
  an unsupported CPU will raise an illegal instruction exception.
  Use ghash_pclmul_get() to safely obtain this pointer.
*>
extern fn void ghash_pclmul(void* y, void* h, void* data, sz len);

<*
  Obtain the pclmul GHASH implementation if available.

  Returns a pointer to ghash_pclmul() if both the compiler support and
  CPU support are present; otherwise returns null.

  returns the pclmul GHASH implementation, or null.
*>
extern fn GHashFn ghash_pclmul_get();

<*
  GHASH implementation using POWER8 opcodes.

  Only available on POWER8 (and later) platforms. Use ghash_pwr8_get()
  to safely obtain this pointer.
*>
extern fn void ghash_pwr8(void* y, void* h, void* data, sz len);

<*
  Obtain the pwr8 GHASH implementation if available.

  Returns a pointer to ghash_pwr8() if both compiler and CPU support are
  present; otherwise returns null.

  returns the pwr8 GHASH implementation, or null.
*>
extern fn GHashFn ghash_pwr8_get();
