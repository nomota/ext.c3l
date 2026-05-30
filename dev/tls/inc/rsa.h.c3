// rsa.h.c3

// Depends on:
//   hash  (HashClass)
//   rand  (PRNGClass)

module ext::net::tsl;

// ============================================================
// Key structures
// ============================================================

<*
  RSA public key.

  References the modulus and the public exponent. Both integers use
  unsigned big-endian representation; extra leading zero bytes are
  allowed.
*>
struct RSAPublicKey {
    <* Modulus. *>
    char* n;
    <* Modulus length (in bytes). *>
    sz nlen;
    <* Public exponent. *>
    char* e;
    <* Public exponent length (in bytes). *>
    sz elen;
}

<*
  RSA private key.

  References the private factors, reduced private exponents, and CRT
  coefficient. It also contains the bit length of the modulus. The big
  integers use unsigned big-endian representation; extra leading zero
  bytes are allowed. However, the modulus bit length (n_bitlen) MUST be
  exact.
*>
struct RSAPrivateKey {
    <* Modulus bit length (in bits, exact value). *>
    uint n_bitlen;
    <* First prime factor. *>
    char* p;
    <* First prime factor length (in bytes). *>
    sz plen;
    <* Second prime factor. *>
    char* q;
    <* Second prime factor length (in bytes). *>
    sz qlen;
    <* First reduced private exponent (d mod p-1). *>
    char* dp;
    <* First reduced private exponent length (in bytes). *>
    sz dplen;
    <* Second reduced private exponent (d mod q-1). *>
    char* dq;
    <* Second reduced private exponent length (in bytes). *>
    sz dqlen;
    <* CRT coefficient (inverse of q mod p). *>
    char* iq;
    <* CRT coefficient length (in bytes). *>
    sz iqlen;
}

// ============================================================
// Function pointer aliases
// ============================================================

<*
  RSA public key engine (modular exponentiation with public exponent).

  The value x[] is modified in place. xlen must match the actual modulus
  length (without extra leading zeros). Returns 1 on success, 0 on error.

  param x     operand to exponentiate (modified in place).
  param xlen  length of the operand (in bytes).
  param pk    RSA public key.
  returns 1 on success, 0 on error.
*>
alias RSAPublic = fn uint(char* x, sz xlen, RSAPublicKey* pk);

<*
  RSA signature verification engine (PKCS#1 v1.5).

  Verifies that the signature (x, xlen) matches the modulus length,
  strips PKCS#1 v1.5 padding, and writes the recovered hash into
  hash_out. The caller must still compare hash_out with the actual
  hash of the signed data.

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hash_oid  encoded hash algorithm OID (or null for raw hash).
  param hash_len  expected hash value length (in bytes).
  param pk        RSA public key.
  param hash_out  output buffer for the recovered hash value.
  returns 1 on success, 0 on error.
*>
alias RSAPKCS1Vrfy = fn uint(char* x, sz xlen, char* hash_oid, sz hash_len,
    RSAPublicKey* pk, char* hash_out);

<*
  RSA signature verification engine (PSS).

  Unlike PKCS#1 v1.5, the hash value must be provided because it cannot
  be extracted from the signature.

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hf_data   hash function applied on the message.
  param hf_mgf1   hash function to use with MGF1.
  param hash      hash value of the signed message.
  param salt_len  PSS salt length (in bytes).
  param pk        RSA public key.
  returns 1 on success, 0 on error.
*>
alias RSAPSSVrfy = fn uint(char* x, sz xlen,
    HashClass* hf_data, HashClass* hf_mgf1,
    void* hash, sz salt_len, RSAPublicKey* pk);

<*
  RSA encryption engine (OAEP).

  The source message (src, src_len) may overlap with the destination
  buffer (dst, dst_max_len). Returns the encrypted message length on
  success, 0 on error.

  param rnd          source of random bytes.
  param dig          hash function to use with MGF1.
  param label        label value (may be null if label_len is zero).
  param label_len    label length (in bytes).
  param pk           RSA public key.
  param dst          destination buffer.
  param dst_max_len  destination buffer length (in bytes).
  param src          message to encrypt.
  param src_len      source message length (in bytes).
  returns encrypted message length (in bytes), or 0 on error.
*>
alias RSAOAEPEncrypt = fn sz(PRNGClass** rnd, HashClass* dig,
    void* label, sz label_len, RSAPublicKey* pk,
    void* dst, sz dst_max_len,
    void* src, sz src_len);

<*
  RSA private key engine (modular exponentiation with private key).

  The buffer length is inferred from sk->n_bitlen: it is
  (sk->n_bitlen + 7) / 8 bytes.

  param x   operand to exponentiate (modified in place).
  param sk  RSA private key.
  returns 1 on success, 0 on error.
*>
alias RSAPrivate = fn uint(char* x, RSAPrivateKey* sk);

<*
  RSA signature generation engine (PKCS#1 v1.5).

  The signature length is exactly (sk->n_bitlen + 7) / 8 bytes.

  param hash_oid  encoded hash algorithm OID (or null for raw hash).
  param hash      hash value.
  param hash_len  hash value length (in bytes).
  param sk        RSA private key.
  param x         output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
alias RSAPKCS1Sign = fn uint(char* hash_oid,
    char* hash, sz hash_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA signature generation engine (PSS).

  The signature length is exactly (sk->n_bitlen + 7) / 8 bytes.

  param rng        PRNG for salt generation (null if salt_len is zero).
  param hf_data    hash function used to hash the signed data.
  param hf_mgf1    hash function to use with MGF1.
  param hash_value hashed message.
  param salt_len   salt length (in bytes).
  param sk         RSA private key.
  param x          output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
alias RSAPSSSign = fn uint(PRNGClass** rng,
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash_value, sz salt_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA decryption engine (OAEP).

  The buffer initially contains the encrypted message; on success it is
  overwritten with the plaintext and *len is updated. Implementations
  must use constant-time padding validation.

  param dig        hash function to use with MGF1.
  param label      label value (may be null if label_len is zero).
  param label_len  label length (in bytes).
  param sk         RSA private key.
  param data       input/output buffer.
  param len        pointer to encrypted length; updated to plaintext length.
  returns 1 on success, 0 on error.
*>
alias RSAOAEPDecrypt = fn uint(HashClass* dig, void* label, sz label_len,
    RSAPrivateKey* sk, void* data, sz* len);

<*
  RSA key pair generator type.

  Generates a new RSA key pair whose modulus has `size` bits. If pk is
  null, kbuf_pub may also be null and only the private key is written.
  If pubexp is zero, the public exponent defaults to 3.

  param rng_ctx    source PRNG context (already initialized).
  param sk         RSA private key structure (destination).
  param kbuf_priv  buffer for private key elements.
  param pk         RSA public key structure (destination), or null.
  param kbuf_pub   buffer for public key elements, or null.
  param size       target RSA modulus size (in bits).
  param pubexp     public exponent to use, or zero.
  returns 1 on success, 0 on error.
*>
alias RSAKeygen = fn uint(PRNGClass** rng_ctx,
    RSAPrivateKey* sk, void* kbuf_priv,
    RSAPublicKey* pk, void* kbuf_pub,
    uint size, uint pubexp);

<*
  Type for a function that computes the public modulus from a private key.

  Writes the encoded modulus (unsigned big-endian) to n and returns its
  byte length. If n is null, the length is returned without writing.
  Returns 0 on error.

  param n   destination buffer (or null).
  param sk  RSA private key.
  returns modulus length (in bytes), or 0 on error.
*>
alias RSAComputeModulus = fn sz(void* n, RSAPrivateKey* sk);

<*
  Type for a function that recomputes the public exponent from a private key.

  Returns 0 if p or q is not congruent to 3 mod 4, if the exponent does
  not fit in 32 bits, if an internal limit is exceeded, or if the key is
  otherwise invalid.

  param sk  RSA private key.
  returns the public exponent, or 0 on error.
*>
alias RSAComputePubexp = fn uint(RSAPrivateKey* sk);

<*
  Type for a function that recomputes the full private exponent.

  Writes the encoded private exponent (unsigned big-endian) to d and
  returns its byte length. If d is null, only the length is returned.
  Returns 0 on error.

  param d       destination buffer (or null).
  param sk      RSA private key.
  param pubexp  the public exponent.
  returns private exponent length (in bytes), or 0 on error.
*>
alias RSAComputePrivexp = fn sz(void* d, RSAPrivateKey* sk, uint pubexp);

// ============================================================
// Hash OID constants (for PKCS#1 v1.5 signatures)
//
// Each constant is a byte string whose first byte is the OID value
// length, followed by that many OID bytes.
// ============================================================

<* Encoded OID for SHA-1 (in RSA PKCS#1 signatures). *>
const char* HASH_OID_SHA1   = "\x05\x2b\x0e\x03\x02\x1a";

<* Encoded OID for SHA-224 (in RSA PKCS#1 signatures). *>
const char* HASH_OID_SHA224 = "\x09\x60\x86\x48\x01\x65\x03\x04\x02\x04";

<* Encoded OID for SHA-256 (in RSA PKCS#1 signatures). *>
const char* HASH_OID_SHA256 = "\x09\x60\x86\x48\x01\x65\x03\x04\x02\x01";

<* Encoded OID for SHA-384 (in RSA PKCS#1 signatures). *>
const char* HASH_OID_SHA384 = "\x09\x60\x86\x48\x01\x65\x03\x04\x02\x02";

<* Encoded OID for SHA-512 (in RSA PKCS#1 signatures). *>
const char* HASH_OID_SHA512 = "\x09\x60\x86\x48\x01\x65\x03\x04\x02\x03";

// ============================================================
// Buffer size helpers
// ============================================================

<*
  Get buffer size needed to hold RSA private key elements.

  param size  target key size (modulus size, in bits).
  returns required buffer length (in bytes).
*>
fn sz rsa_kbuf_priv_size(sz size) @inline => 5 * ((size + 15) >> 4);

<*
  Get buffer size needed to hold RSA public key elements.

  param size  target key size (modulus size, in bits).
  returns required buffer length (in bytes).
*>
fn sz rsa_kbuf_pub_size(sz size) @inline => 4 + ((size + 7) >> 3);

// ============================================================
// Engine: i32
// Integers represented as 32-bit arrays; 32x32->64 multiply.
// ============================================================

<*
  RSA public key engine "i32".

  param x     operand to exponentiate.
  param xlen  length of the operand (in bytes).
  param pk    RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i32_public(char* x, sz xlen, RSAPublicKey* pk);

<*
  RSA signature verification "i32" (PKCS#1 v1.5).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hash_oid  encoded hash algorithm OID (or null).
  param hash_len  expected hash value length (in bytes).
  param pk        RSA public key.
  param hash_out  output buffer for the hash value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i32_pkcs1_vrfy(char* x, sz xlen,
    char* hash_oid, sz hash_len,
    RSAPublicKey* pk, char* hash_out);

<*
  RSA signature verification "i32" (PSS).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hf_data   hash function applied on the message.
  param hf_mgf1   hash function to use with MGF1.
  param hash      hash value of the signed message.
  param salt_len  PSS salt length (in bytes).
  param pk        RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i32_pss_vrfy(char* x, sz xlen,
    HashClass* hf_data, HashClass* hf_mgf1,
    void* hash, sz salt_len, RSAPublicKey* pk);

<*
  RSA private key engine "i32".

  param x   operand to exponentiate.
  param sk  RSA private key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i32_private(char* x, RSAPrivateKey* sk);

<*
  RSA signature generation "i32" (PKCS#1 v1.5).

  param hash_oid  encoded hash algorithm OID (or null).
  param hash      hash value.
  param hash_len  hash value length (in bytes).
  param sk        RSA private key.
  param x         output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i32_pkcs1_sign(char* hash_oid,
    char* hash, sz hash_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA signature generation "i32" (PSS).

  param rng        PRNG for salt generation (null if salt_len is zero).
  param hf_data    hash function used to hash the signed data.
  param hf_mgf1    hash function to use with MGF1.
  param hash_value hashed message.
  param salt_len   salt length (in bytes).
  param sk         RSA private key.
  param x          output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i32_pss_sign(PRNGClass** rng,
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash_value, sz salt_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA encryption (OAEP) with the "i32" engine.
  see RSAOAEPEncrypt
*>
extern fn sz rsa_i32_oaep_encrypt(PRNGClass** rnd, HashClass* dig,
    void* label, sz label_len, RSAPublicKey* pk,
    void* dst, sz dst_max_len,
    void* src, sz src_len);

<*
  RSA decryption (OAEP) with the "i32" engine.
  see RSAOAEPDecrypt
*>
extern fn uint rsa_i32_oaep_decrypt(HashClass* dig, void* label, sz label_len,
    RSAPrivateKey* sk, void* data, sz* len);

// ============================================================
// Engine: i31
// 32-bit words, 31 bits of data each; slightly faster than i32.
// ============================================================

<*
  RSA public key engine "i31".

  param x     operand to exponentiate.
  param xlen  length of the operand (in bytes).
  param pk    RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i31_public(char* x, sz xlen, RSAPublicKey* pk);

<*
  RSA signature verification "i31" (PKCS#1 v1.5).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hash_oid  encoded hash algorithm OID (or null).
  param hash_len  expected hash value length (in bytes).
  param pk        RSA public key.
  param hash_out  output buffer for the hash value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i31_pkcs1_vrfy(char* x, sz xlen,
    char* hash_oid, sz hash_len,
    RSAPublicKey* pk, char* hash_out);

<*
  RSA signature verification "i31" (PSS).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hf_data   hash function applied on the message.
  param hf_mgf1   hash function to use with MGF1.
  param hash      hash value of the signed message.
  param salt_len  PSS salt length (in bytes).
  param pk        RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i31_pss_vrfy(char* x, sz xlen,
    HashClass* hf_data, HashClass* hf_mgf1,
    void* hash, sz salt_len, RSAPublicKey* pk);

<*
  RSA private key engine "i31".

  param x   operand to exponentiate.
  param sk  RSA private key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i31_private(char* x, RSAPrivateKey* sk);

<*
  RSA signature generation "i31" (PKCS#1 v1.5).

  param hash_oid  encoded hash algorithm OID (or null).
  param hash      hash value.
  param hash_len  hash value length (in bytes).
  param sk        RSA private key.
  param x         output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i31_pkcs1_sign(char* hash_oid,
    char* hash, sz hash_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA signature generation "i31" (PSS).

  param rng        PRNG for salt generation (null if salt_len is zero).
  param hf_data    hash function used to hash the signed data.
  param hf_mgf1    hash function to use with MGF1.
  param hash_value hashed message.
  param salt_len   salt length (in bytes).
  param sk         RSA private key.
  param x          output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i31_pss_sign(PRNGClass** rng,
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash_value, sz salt_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA encryption (OAEP) with the "i31" engine.
  see RSAOAEPEncrypt
*>
extern fn sz rsa_i31_oaep_encrypt(PRNGClass** rnd, HashClass* dig,
    void* label, sz label_len, RSAPublicKey* pk,
    void* dst, sz dst_max_len,
    void* src, sz src_len);

<*
  RSA decryption (OAEP) with the "i31" engine.
  see RSAOAEPDecrypt
*>
extern fn uint rsa_i31_oaep_decrypt(HashClass* dig, void* label, sz label_len,
    RSAPrivateKey* sk, void* data, sz* len);

<*
  RSA key pair generation with the "i31" engine.
  see RSAKeygen
*>
extern fn uint rsa_i31_keygen(PRNGClass** rng_ctx,
    RSAPrivateKey* sk, void* kbuf_priv,
    RSAPublicKey* pk, void* kbuf_pub,
    uint size, uint pubexp);

<*
  Recompute RSA modulus ("i31" engine).
  see RSAComputeModulus
*>
extern fn sz rsa_i31_compute_modulus(void* n, RSAPrivateKey* sk);

<*
  Recompute RSA public exponent ("i31" engine).
  see RSAComputePubexp
*>
extern fn uint rsa_i31_compute_pubexp(RSAPrivateKey* sk);

<*
  Recompute RSA private exponent ("i31" engine).
  see RSAComputePrivexp
*>
extern fn sz rsa_i31_compute_privexp(void* d, RSAPrivateKey* sk, uint pubexp);

// ============================================================
// Engine: i62
// Like i31 but uses 64x64->128 multiply; not available everywhere.
// Use the rsa_i62_*_get() functions to check availability at runtime.
// ============================================================

<*
  RSA public key engine "i62" (requires 64x64->128 multiply opcode).

  param x     operand to exponentiate.
  param xlen  length of the operand (in bytes).
  param pk    RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i62_public(char* x, sz xlen, RSAPublicKey* pk);

<*
  RSA signature verification "i62" (PKCS#1 v1.5).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hash_oid  encoded hash algorithm OID (or null).
  param hash_len  expected hash value length (in bytes).
  param pk        RSA public key.
  param hash_out  output buffer for the hash value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i62_pkcs1_vrfy(char* x, sz xlen,
    char* hash_oid, sz hash_len,
    RSAPublicKey* pk, char* hash_out);

<*
  RSA signature verification "i62" (PSS).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hf_data   hash function applied on the message.
  param hf_mgf1   hash function to use with MGF1.
  param hash      hash value of the signed message.
  param salt_len  PSS salt length (in bytes).
  param pk        RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i62_pss_vrfy(char* x, sz xlen,
    HashClass* hf_data, HashClass* hf_mgf1,
    void* hash, sz salt_len, RSAPublicKey* pk);

<*
  RSA private key engine "i62".

  param x   operand to exponentiate.
  param sk  RSA private key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i62_private(char* x, RSAPrivateKey* sk);

<*
  RSA signature generation "i62" (PKCS#1 v1.5).

  param hash_oid  encoded hash algorithm OID (or null).
  param hash      hash value.
  param hash_len  hash value length (in bytes).
  param sk        RSA private key.
  param x         output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i62_pkcs1_sign(char* hash_oid,
    char* hash, sz hash_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA signature generation "i62" (PSS).

  param rng        PRNG for salt generation (null if salt_len is zero).
  param hf_data    hash function used to hash the signed data.
  param hf_mgf1    hash function to use with MGF1.
  param hash_value hashed message.
  param salt_len   salt length (in bytes).
  param sk         RSA private key.
  param x          output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i62_pss_sign(PRNGClass** rng,
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash_value, sz salt_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA encryption (OAEP) with the "i62" engine.
  see RSAOAEPEncrypt
*>
extern fn sz rsa_i62_oaep_encrypt(PRNGClass** rnd, HashClass* dig,
    void* label, sz label_len, RSAPublicKey* pk,
    void* dst, sz dst_max_len,
    void* src, sz src_len);

<*
  RSA decryption (OAEP) with the "i62" engine.
  see RSAOAEPDecrypt
*>
extern fn uint rsa_i62_oaep_decrypt(HashClass* dig, void* label, sz label_len,
    RSAPrivateKey* sk, void* data, sz* len);

<*
  RSA key pair generation with the "i62" engine.
  see RSAKeygen
*>
extern fn uint rsa_i62_keygen(PRNGClass** rng_ctx,
    RSAPrivateKey* sk, void* kbuf_priv,
    RSAPublicKey* pk, void* kbuf_pub,
    uint size, uint pubexp);

// i62 availability getters — return null/0 when the opcode is unavailable.

<* Get the "i62" public key implementation, or 0 if unavailable. *>
extern fn RSAPublic rsa_i62_public_get();

<* Get the "i62" PKCS#1 v1.5 signature verification implementation, or 0. *>
extern fn RSAPKCS1Vrfy rsa_i62_pkcs1_vrfy_get();

<* Get the "i62" PSS signature verification implementation, or 0. *>
extern fn RSAPSSVrfy rsa_i62_pss_vrfy_get();

<* Get the "i62" private key implementation, or 0 if unavailable. *>
extern fn RSAPrivate rsa_i62_private_get();

<* Get the "i62" PKCS#1 v1.5 signature generation implementation, or 0. *>
extern fn RSAPKCS1Sign rsa_i62_pkcs1_sign_get();

<* Get the "i62" PSS signature generation implementation, or 0. *>
extern fn RSAPSSSign rsa_i62_pss_sign_get();

<* Get the "i62" OAEP encryption implementation, or 0 if unavailable. *>
extern fn RSAOAEPEncrypt rsa_i62_oaep_encrypt_get();

<* Get the "i62" OAEP decryption implementation, or 0 if unavailable. *>
extern fn RSAOAEPDecrypt rsa_i62_oaep_decrypt_get();

<* Get the "i62" key pair generation implementation, or 0 if unavailable. *>
extern fn RSAKeygen rsa_i62_keygen_get();

// ============================================================
// Engine: i15
// 16-bit integers, 15 bits of data each; only 32-bit multiply
// needed — well-suited for ARM Cortex M0/M0+.
// ============================================================

<*
  RSA public key engine "i15".

  param x     operand to exponentiate.
  param xlen  length of the operand (in bytes).
  param pk    RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i15_public(char* x, sz xlen, RSAPublicKey* pk);

<*
  RSA signature verification "i15" (PKCS#1 v1.5).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hash_oid  encoded hash algorithm OID (or null).
  param hash_len  expected hash value length (in bytes).
  param pk        RSA public key.
  param hash_out  output buffer for the hash value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i15_pkcs1_vrfy(char* x, sz xlen,
    char* hash_oid, sz hash_len,
    RSAPublicKey* pk, char* hash_out);

<*
  RSA signature verification "i15" (PSS).

  param x         signature buffer.
  param xlen      signature length (in bytes).
  param hf_data   hash function applied on the message.
  param hf_mgf1   hash function to use with MGF1.
  param hash      hash value of the signed message.
  param salt_len  PSS salt length (in bytes).
  param pk        RSA public key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i15_pss_vrfy(char* x, sz xlen,
    HashClass* hf_data, HashClass* hf_mgf1,
    void* hash, sz salt_len, RSAPublicKey* pk);

<*
  RSA private key engine "i15".

  param x   operand to exponentiate.
  param sk  RSA private key.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i15_private(char* x, RSAPrivateKey* sk);

<*
  RSA signature generation "i15" (PKCS#1 v1.5).

  param hash_oid  encoded hash algorithm OID (or null).
  param hash      hash value.
  param hash_len  hash value length (in bytes).
  param sk        RSA private key.
  param x         output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i15_pkcs1_sign(char* hash_oid,
    char* hash, sz hash_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA signature generation "i15" (PSS).

  param rng        PRNG for salt generation (null if salt_len is zero).
  param hf_data    hash function used to hash the signed data.
  param hf_mgf1    hash function to use with MGF1.
  param hash_value hashed message.
  param salt_len   salt length (in bytes).
  param sk         RSA private key.
  param x          output buffer for the signature value.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_i15_pss_sign(PRNGClass** rng,
    HashClass* hf_data, HashClass* hf_mgf1,
    char* hash_value, sz salt_len,
    RSAPrivateKey* sk, char* x);

<*
  RSA encryption (OAEP) with the "i15" engine.
  see RSAOAEPEncrypt
*>
extern fn sz rsa_i15_oaep_encrypt(PRNGClass** rnd, HashClass* dig,
    void* label, sz label_len, RSAPublicKey* pk,
    void* dst, sz dst_max_len,
    void* src, sz src_len);

<*
  RSA decryption (OAEP) with the "i15" engine.
  see RSAOAEPDecrypt
*>
extern fn uint rsa_i15_oaep_decrypt(HashClass* dig, void* label, sz label_len,
    RSAPrivateKey* sk, void* data, sz* len);

<*
  RSA key pair generation with the "i15" engine.
  see RSAKeygen
*>
extern fn uint rsa_i15_keygen(PRNGClass** rng_ctx,
    RSAPrivateKey* sk, void* kbuf_priv,
    RSAPublicKey* pk, void* kbuf_pub,
    uint size, uint pubexp);

<*
  Recompute RSA modulus ("i15" engine).
  see RSAComputeModulus
*>
extern fn sz rsa_i15_compute_modulus(void* n, RSAPrivateKey* sk);

<*
  Recompute RSA public exponent ("i15" engine).
  see RSAComputePubexp
*>
extern fn uint rsa_i15_compute_pubexp(RSAPrivateKey* sk);

<*
  Recompute RSA private exponent ("i15" engine).
  see RSAComputePrivexp
*>
extern fn sz rsa_i15_compute_privexp(void* d, RSAPrivateKey* sk, uint pubexp);

// ============================================================
// Default implementation getters
// ============================================================

<*
  Get the preferred RSA public key implementation for this platform.
  returns the default implementation.
*>
extern fn RSAPublic rsa_public_get_default();

<*
  Get the preferred RSA private key implementation for this platform.
  returns the default implementation.
*>
extern fn RSAPrivate rsa_private_get_default();

<*
  Get the preferred RSA PKCS#1 v1.5 signature verification implementation.
  returns the default implementation.
*>
extern fn RSAPKCS1Vrfy rsa_pkcs1_vrfy_get_default();

<*
  Get the preferred RSA PSS signature verification implementation.
  returns the default implementation.
*>
extern fn RSAPSSVrfy rsa_pss_vrfy_get_default();

<*
  Get the preferred RSA PKCS#1 v1.5 signature generation implementation.
  returns the default implementation.
*>
extern fn RSAPKCS1Sign rsa_pkcs1_sign_get_default();

<*
  Get the preferred RSA PSS signature generation implementation.
  returns the default implementation.
*>
extern fn RSAPSSSign rsa_pss_sign_get_default();

<*
  Get the preferred RSA OAEP encryption implementation.
  returns the default implementation.
*>
extern fn RSAOAEPEncrypt rsa_oaep_encrypt_get_default();

<*
  Get the preferred RSA OAEP decryption implementation.
  returns the default implementation.
*>
extern fn RSAOAEPDecrypt rsa_oaep_decrypt_get_default();

<*
  Get the preferred RSA key pair generation implementation.
  returns the default implementation.
*>
extern fn RSAKeygen rsa_keygen_get_default();

<*
  Get the preferred RSA compute-modulus implementation.
  returns the default implementation.
*>
extern fn RSAComputeModulus rsa_compute_modulus_get_default();

<*
  Get the preferred RSA compute-public-exponent implementation.
  returns the default implementation.
*>
extern fn RSAComputePubexp rsa_compute_pubexp_get_default();

<*
  Get the preferred RSA compute-private-exponent implementation.
  returns the default implementation.
*>
extern fn RSAComputePrivexp rsa_compute_privexp_get_default();

// ============================================================
// SSL/TLS helper
// ============================================================

<*
  RSA decryption helper for SSL/TLS (PKCS#1 v1.5 key exchange).

  Performs constant-time RSA decryption followed by constant-time
  PKCS#1 v1.5 padding verification. On success, the 48-byte pre-master
  secret is written at the start of the `data` buffer.

  This function verifies that len is at least 59 bytes and matches the
  RSA modulus length before proceeding.

  param core  RSA private key engine.
  param sk    RSA private key.
  param data  input/output buffer (cipher text in, pre-master secret out).
  param len   length (in bytes) of the data to decrypt.
  returns 1 on success, 0 on error.
*>
extern fn uint rsa_ssl_decrypt(RSAPrivate core, RSAPrivateKey* sk,
    char* data, sz len);
