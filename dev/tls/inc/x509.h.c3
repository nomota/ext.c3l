// x509.h.c3

module ext::net::tls;

// ============================================================================
// X.509 Error Codes (32..63 range)
// ============================================================================

<*
  X.509 status: validation was successful; this is not actually an error.
*>
const ERR_X509_OK                  = 32;

<*
  X.509 status: invalid value in an ASN.1 structure.
*>
const ERR_X509_INVALID_VALUE       = 33;

<*
  X.509 status: truncated certificate.
*>
const ERR_X509_TRUNCATED           = 34;

<*
  X.509 status: empty certificate chain (no certificate at all).
*>
const ERR_X509_EMPTY_CHAIN         = 35;

<*
  X.509 status: inner element extends beyond outer element size.
*>
const ERR_X509_INNER_TRUNC         = 36;

<*
  X.509 status: unsupported tag class (application or private).
*>
const ERR_X509_BAD_TAG_CLASS       = 37;

<*
  X.509 status: unsupported tag value.
*>
const ERR_X509_BAD_TAG_VALUE       = 38;

<*
  X.509 status: indefinite length.
*>
const ERR_X509_INDEFINITE_LENGTH   = 39;

<*
  X.509 status: extraneous element.
*>
const ERR_X509_EXTRA_ELEMENT       = 40;

<*
  X.509 status: unexpected element.
*>
const ERR_X509_UNEXPECTED          = 41;

<*
  X.509 status: expected constructed element, but is primitive.
*>
const ERR_X509_NOT_CONSTRUCTED     = 42;

<*
  X.509 status: expected primitive element, but is constructed.
*>
const ERR_X509_NOT_PRIMITIVE       = 43;

<*
  X.509 status: BIT STRING length is not multiple of 8.
*>
const ERR_X509_PARTIAL_BYTE        = 44;

<*
  X.509 status: BOOLEAN value has invalid length.
*>
const ERR_X509_BAD_BOOLEAN         = 45;

<*
  X.509 status: value is off-limits.
*>
const ERR_X509_OVERFLOW            = 46;

<*
  X.509 status: invalid distinguished name.
*>
const ERR_X509_BAD_DN              = 47;

<*
  X.509 status: invalid date/time representation.
*>
const ERR_X509_BAD_TIME            = 48;

<*
  X.509 status: certificate contains unsupported features that cannot be ignored.
*>
const ERR_X509_UNSUPPORTED         = 49;

<*
  X.509 status: key or signature size exceeds internal limits.
*>
const ERR_X509_LIMIT_EXCEEDED      = 50;

<*
  X.509 status: key type does not match that which was expected.
*>
const ERR_X509_WRONG_KEY_TYPE      = 51;

<*
  X.509 status: signature is invalid.
*>
const ERR_X509_BAD_SIGNATURE       = 52;

<*
  X.509 status: validation time is unknown.
*>
const ERR_X509_TIME_UNKNOWN        = 53;

<*
  X.509 status: certificate is expired or not yet valid.
*>
const ERR_X509_EXPIRED             = 54;

<*
  X.509 status: issuer/subject DN mismatch in the chain.
*>
const ERR_X509_DN_MISMATCH         = 55;

<*
  X.509 status: expected server name was not found in the chain.
*>
const ERR_X509_BAD_SERVER_NAME     = 56;

<*
  X.509 status: unknown critical extension in certificate.
*>
const ERR_X509_CRITICAL_EXTENSION  = 57;

<*
  X.509 status: not a CA, or path length constraint violation.
*>
const ERR_X509_NOT_CA              = 58;

<*
  X.509 status: Key Usage extension prohibits intended usage.
*>
const ERR_X509_FORBIDDEN_KEY_USAGE = 59;

<*
  X.509 status: public key found in certificate is too small.
*>
const ERR_X509_WEAK_PUBLIC_KEY     = 60;

<*
  X.509 status: chain could not be linked to a trust anchor.
*>
const ERR_X509_NOT_TRUSTED         = 62;

// ============================================================================
// Key Type Constants
//
// Key type is a combination of a basic key type (low 4 bits) and optional
// usage flags. For a public key only the basic type is set. For an expected
// key type, the flags indicate the intended purpose(s).
// ============================================================================

<*
  Key type: algorithm is RSA.
*>
const KEYTYPE_RSA   = 1;

<*
  Key type: algorithm is EC.
*>
const KEYTYPE_EC    = 2;

<*
  Key type: usage is "key exchange".

  Combined (via bitwise OR) with KEYTYPE_RSA or KEYTYPE_EC to indicate
  the key should be fit for key exchanges (e.g. TLS_RSA_* and TLS_ECDH_*).
*>
const KEYTYPE_KEYX  = 0x10;

<*
  Key type: usage is "signature".

  Combined (via bitwise OR) with KEYTYPE_RSA or KEYTYPE_EC to indicate
  the key should be fit for signatures (e.g. TLS_ECDHE_* suites).
*>
const KEYTYPE_SIGN  = 0x20;

<*
  Trust anchor flag: CA.

  A "CA" anchor is deemed fit to verify signatures on certificates.
  A "non-CA" anchor is accepted only for direct trust (the server's
  certificate name and key must match the anchor exactly).
*>
const X509_TA_CA    = 0x0001;

// ============================================================================
// Internal Buffer Sizes
// ============================================================================

<*
  Buffer size for a public key element (supports RSA-4096 + short exponent).
*>
const X509_BUFSIZE_KEY = 520;

<*
  Buffer size for a signature element (supports RSA-4096 signature).
*>
const X509_BUFSIZE_SIG = 512;

// ============================================================================
// PEM Banners
// ============================================================================

<*
  PEM banner for RSA private key (raw).
*>
const ENCODE_PEM_RSA_RAW = "RSA PRIVATE KEY";

<*
  PEM banner for EC private key (raw).
*>
const ENCODE_PEM_EC_RAW  = "EC PRIVATE KEY";

<*
  PEM banner for an RSA or EC private key in PKCS#8 format.
*>
const ENCODE_PEM_PKCS8   = "PRIVATE KEY";

// ============================================================================
// Public Key Structure
// ============================================================================

<*
  Aggregate structure for public keys.
*>
struct X509PKey {
    <*
      Key type: KEYTYPE_RSA or KEYTYPE_EC.
    *>
    char key_type;

    <*
      Actual public key.
    *>
    union key {
        <* RSA public key. *>
        RSAPublicKey rsa;
        <* EC public key. *>
        ECPublicKey ec;
    }
}

// ============================================================================
// Distinguished Name and Trust Anchor
// ============================================================================

<*
  Distinguished Name (X.500) structure. The DN is DER-encoded.
*>
struct X500Name {
    <* Encoded DN data. *>
    char* data;
    <* Encoded DN length (in bytes). *>
    sz len;
}

<*
  Trust anchor structure.
*>
struct X509TrustAnchor {
    <* Encoded DN (X.500 name). *>
    X500Name dn;
    <* Anchor flags (e.g. X509_TA_CA). *>
    uint flags;
    <* Anchor public key. *>
    X509PKey pkey;
}

// ============================================================================
// X.509 Engine Class (vtable)
// ============================================================================

// Forward-declare function pointer aliases for X509Class methods.
// All methods receive a pointer-to-pointer to the vtable as their first arg.

<*
  Start a new certificate chain. Sets the vtable (first field) of the
  context structure. server_name (if not null) is matched against the
  end-entity certificate's SAN/CN.
*>
alias X509StartChainFn = fn void(X509Class** ctx, char* server_name);

<*
  Start a new certificate. length is the total certificate length in bytes.
*>
alias X509StartCertFn  = fn void(X509Class** ctx, uint length);

<*
  Receive some bytes for the current certificate.
  len is never zero; chunks sum to the total length from start_cert.
*>
alias X509AppendFn     = fn void(X509Class** ctx, char* buf, sz len);

<*
  Finish the current certificate.
*>
alias X509EndCertFn    = fn void(X509Class** ctx);

<*
  Finish the chain. Returns 0 on success, or a non-zero error code.
*>
alias X509EndChainFn   = fn uint(X509Class** ctx);

<*
  Get the resulting end-entity public key.
  May return null on validation failure. If usages is not null and
  validation succeeded, *usages is set to a combination of
  KEYTYPE_SIGN and/or KEYTYPE_KEYX.
*>
alias X509GetPKeyFn    = fn X509PKey*(X509Class** ctx, uint* usages);

<*
  Class type for an X.509 engine.

  A certificate chain validation uses a caller-allocated context containing
  the running state. Methods are called in order:
    - start_chain() at the start of validation.
    - For each certificate: start_cert(), zero or more append(), end_cert().
    - end_chain() when the last certificate has been processed.
    - get_pkey() after successful chain processing.

  A context may be reused; start_chain() shall ensure (re)initialisation.
*>
struct X509Class {
    <* X.509 context size, in bytes. *>
    sz context_size;

    <* Start a new chain. *>
    X509StartChainFn start_chain;

    <* Start a new certificate. *>
    X509StartCertFn start_cert;

    <* Receive some bytes for the current certificate. *>
    X509AppendFn append;

    <* Finish the current certificate. *>
    X509EndCertFn end_cert;

    <*
      Finish the chain. Returns 0 on success, or a non-zero error code.
    *>
    X509EndChainFn end_chain;

    <*
      Get the resulting end-entity public key.
    *>
    X509GetPKeyFn get_pkey;
}

// ============================================================================
// "Known Key" Engine
// ============================================================================

<*
  The "known key" X.509 engine structure.

  Returns an externally configured public key and ignores certificate
  contents entirely. The first field (vtable) may be accessed directly;
  all other fields are opaque.
*>
struct X509KnownKeyContext {
    <* Reference to the context vtable. *>
    X509Class* vtable;

    X509PKey pkey;
    uint usages;
}

<*
  Class instance for the "known key" X.509 engine.
*>
extern X509Class x509_knownkey_vtable;

<*
  Initialize a "known key" X.509 engine with a known RSA public key.

  The provided pointers are linked in (not copied) and must remain
  valid while the public key may be in use.

  param ctx      context to initialise.
  param pk       known RSA public key.
  param usages   allowed key usages (KEYTYPE_KEYX and/or KEYTYPE_SIGN).
*>
extern fn void x509_knownkey_init_rsa(X509KnownKeyContext* ctx, RSAPublicKey* pk, uint usages);

<*
  Initialize a "known key" X.509 engine with a known EC public key.

  The provided pointers are linked in (not copied) and must remain
  valid while the public key may be in use.

  param ctx      context to initialise.
  param pk       known EC public key.
  param usages   allowed key usages (KEYTYPE_KEYX and/or KEYTYPE_SIGN).
*>
extern fn void x509_knownkey_init_ec(X509KnownKeyContext* ctx, ECPublicKey* pk, uint usages);

// ============================================================================
// Name Element
// ============================================================================

<*
  Type for receiving a name element.

  An array of these structures can be provided to the X.509 decoding engines.
  If the specified elements are found in the subject DN or SAN extension, the
  name contents are copied as zero-terminated strings into the buffer.

  TeletexString and BMPString are converted to UTF8String. If the string does
  not fit in the buffer, the copy is aborted and an error is reported.
*>
struct NameElement {
    <*
      Element OID.

      For X.500 name elements: encoded OID where the first byte is the
      DER-encoded OID value length, followed by the OID value itself
      (e.g. id-at-commonName OID 2.5.4.3 is encoded as: 03 55 04 03).

      For SAN name elements: first byte is 0, second byte is the
      GeneralName tag (1=rfc822Name, 2=dNSName, 6=uniformResourceIdentifier,
      0=otherName). If both bytes are 0, an encoded OID follows for
      otherName matching.
    *>
    char* oid;

    <* Destination buffer (must be at least 1 byte). *>
    char* buf;

    <* Length (in bytes) of the destination buffer. *>
    sz len;

    <*
      Decoding status: 0 = not found, 1 = found and decoded, -1 = error.
    *>
    int status;
}

// ============================================================================
// "Minimal" X.509 Engine
// ============================================================================

<*
  The "minimal" X.509 engine structure.

  Performs rudimentary but serviceable X.509 path validation. The first
  field (vtable) may be accessed directly; all other fields are opaque.
*>
struct X509MinimalContext {
    X509Class* vtable;

    // Structure for returning the EE public key.
    X509PKey pkey;

    // CPU for the T0 virtual machine.
    struct cpu {
        uint* dp;
        uint* rp;
        char* ip;
    }
    uint[32] dp_stack;
    uint[32] rp_stack;
    int err;

    // Server name to match with the SAN / CN of the EE certificate.
    char* server_name;

    // Validated key usages.
    char key_usages;

    // Explicitly set date and time.
    uint days;
    uint seconds;

    // Current certificate length (bytes). Set to 0 when fully processed.
    uint cert_length;

    // Number of certificates processed so far in the current chain.
    // Incremented at end of each certificate; 0 for the EE.
    uint num_certs;

    // Certificate data chunk.
    char* hbuf;
    sz hlen;

    // General-purpose pad for various operations.
    char[256] pad;

    // Buffer for EE public key data.
    char[X509_BUFSIZE_KEY] ee_pkey_data;

    // Buffer for currently decoded public key.
    char[X509_BUFSIZE_KEY] pkey_data;

    // Signature type: signer key type, hash function OID offset (in T0
    // data block), and hash function output length.
    char cert_signer_key_type;
    ushort cert_sig_hash_oid;
    char cert_sig_hash_len;

    // Current/last certificate signature.
    char[X509_BUFSIZE_SIG] cert_sig;
    ushort cert_sig_len;

    // Minimum RSA key length (difference in bytes from 128).
    short min_rsa_size;

    // Configured trust anchors.
    X509TrustAnchor* trust_anchors;
    sz trust_anchors_num;

    // Multi-hasher for the TBS.
    char do_mhash;
    MultiHashContext mhash;
    char[64] tbs_hash;

    // Simple hasher for the subject/issuer DN.
    char do_dn_hash;
    HashClass* dn_hash_impl;
    HashCompatContext dn_hash;
    char[64] current_dn_hash;
    char[64] next_dn_hash;
    char[64] saved_dn_hash;

    // Name elements to gather.
    NameElement* name_elts;
    sz num_name_elts;

    // Public key cryptography implementations (signature verification).
    RSAPKCS1Vrfy irsa;
    ECDSAVrfy iecdsa;
    ECImpl* iec;
}

<*
  Class instance for the "minimal" X.509 engine.
*>
extern X509Class x509_minimal_vtable;

<*
  Initialise a "minimal" X.509 engine.

  dn_hash_impl is used internally to match X.500 names. Any standard
  hash function works, but a collision-resistant function is advised.

  After initialization, signature verification implementations (hash
  functions and signature algorithms) MUST be added.

  param ctx                 context to initialise.
  param dn_hash_impl        hash function for DN comparisons.
  param trust_anchors       trust anchors.
  param trust_anchors_num   number of trust anchors.
*>
extern fn void x509_minimal_init(X509MinimalContext* ctx,
    HashClass* dn_hash_impl,
    X509TrustAnchor* trust_anchors, sz trust_anchors_num);

<*
  Set a supported hash function in an X.509 "minimal" engine.

  Hash functions are used with signature verification. The id MUST be
  one of the standard hash function identifiers (1=MD5, 2=SHA-1,
  3=SHA-224, 4=SHA-256, 5=SHA-384, 6=SHA-512). Passing null for impl
  removes support for that hash function.

  param ctx    validation context.
  param id     hash function identifier (1 to 6).
  param impl   hash function implementation (or null).
*>
fn void x509_minimal_set_hash(X509MinimalContext* ctx, int id, HashClass* impl) @inline
{
    multihash_setimpl(&ctx.mhash, id, impl);
}

<*
  Set a RSA signature verification implementation in the X.509 "minimal" engine.

  If irsa is null, RSA support is disabled.

  param ctx    validation context.
  param irsa   RSA signature verification implementation (or null).
*>
fn void x509_minimal_set_rsa(X509MinimalContext* ctx, RSAPKCS1Vrfy irsa) @inline
{
    ctx.irsa = irsa;
}

<*
  Set a ECDSA signature verification implementation in the X.509 "minimal" engine.

  If iecdsa is null, ECDSA support is disabled and iec may be null.
  Otherwise iecdsa MUST verify ECDSA signatures with "asn1" format,
  using iec as the underlying elliptic curve support.

  param ctx      validation context.
  param iec      elliptic curve implementation (or null).
  param iecdsa   ECDSA implementation (or null).
*>
fn void x509_minimal_set_ecdsa(X509MinimalContext* ctx, ECImpl* iec, ECDSAVrfy iecdsa) @inline
{
    ctx.iecdsa = iecdsa;
    ctx.iec = iec;
}

<*
  Initialise a "minimal" X.509 engine with default algorithms.

  Equivalent to x509_minimal_init() but also sets implementations for
  RSA, ECDSA, and the standard hash functions.

  param ctx                 context to initialise.
  param trust_anchors       trust anchors.
  param trust_anchors_num   number of trust anchors.
*>
extern fn void x509_minimal_init_full(X509MinimalContext* ctx,
    X509TrustAnchor* trust_anchors, sz trust_anchors_num);

<*
  Set the validation time for the X.509 "minimal" engine.

  Days are counted in the proleptic Gregorian calendar since January 1st,
  0 AD. Seconds are counted since midnight (0 to 86400). Time is UTC.

  If not explicitly set and BearSSL was compiled with system clock support,
  the current time is used automatically. Otherwise, the validation fails
  (except for direct trust of the EE key).

  param ctx       validation context.
  param days      days since January 1st, 0 AD (Gregorian calendar).
  param seconds   seconds since midnight (0 to 86400).
*>
fn void x509_minimal_set_time(X509MinimalContext* ctx, uint days, uint seconds) @inline
{
    ctx.days = days;
    ctx.seconds = seconds;
}

<*
  Set the minimal acceptable RSA key length (X.509 "minimal" engine).

  The key length is in bytes. Default minimum is 128 bytes (1017 bits).
  RSA keys shorter than this are rejected. Applies to end-entity and
  intermediate CA certificates, but not to "CA" trust anchors.

  param ctx           validation context.
  param byte_length   minimum RSA key length, in bytes (not bits).
*>
fn void x509_minimal_set_minrsa(X509MinimalContext* ctx, int byte_length) @inline
{
    ctx.min_rsa_size = (short)(byte_length - 128);
}

<*
  Set the name elements to gather from the EE certificate.

  The provided array is linked into the context (not copied). If the same
  element type is requested multiple times, structures are filled in the
  order matching values are encountered in the certificate.

  param ctx        validation context.
  param elts       array of name element structures to fill.
  param num_elts   number of name element structures to fill.
*>
fn void x509_minimal_set_name_elements(X509MinimalContext* ctx,
    NameElement* elts, sz num_elts) @inline
{
    ctx.name_elts = elts;
    ctx.num_name_elts = num_elts;
}

// ============================================================================
// X.509 Decoder Context
// ============================================================================

<*
  Callback for receiving subject DN data chunk by chunk.
*>
alias AppendDNFn = fn void(void* ctx, void* buf, sz len);

<*
  X.509 decoder context.

  Not for X.509 validation, but for extracting names and public keys from
  encoded certificates. Intended use is for self-signed certificates as
  trust anchors. Contents are opaque and shall not be accessed directly.
*>
struct X509DecoderContext {
    // Structure for returning the public key.
    X509PKey pkey;

    // CPU for the T0 virtual machine.
    struct cpu {
        uint* dp;
        uint* rp;
        char* ip;
    }
    uint[32] dp_stack;
    uint[32] rp_stack;
    int err;

    // General-purpose pad for various operations.
    char[256] pad;

    // Flag set when decoding succeeds.
    char decoded;

    // Validity dates.
    uint notbefore_days;
    uint notbefore_seconds;
    uint notafter_days;
    uint notafter_seconds;

    // The "CA" flag: set if a Basic Constraints extension asserts CA status.
    char isCA;

    // DN processing: subject DN is extracted and pushed to the callback.
    char copy_dn;
    void* append_dn_ctx;
    AppendDNFn append_dn;

    // Certificate data chunk.
    char* hbuf;
    sz hlen;

    // Buffer for decoded public key.
    char[X509_BUFSIZE_KEY] pkey_data;

    // Type of key and hash function used in the certificate signature.
    char signer_key_type;
    char signer_hash_id;
}

<*
  Initialise an X.509 decoder context for processing a new certificate.

  The append_dn() callback receives the certificate's subject DN chunk by
  chunk. If append_dn is null, the subject DN is ignored.

  param ctx             X.509 decoder context to initialise.
  param append_dn       DN receiver callback (or null).
  param append_dn_ctx   opaque context for the DN receiver callback.
*>
extern fn void x509_decoder_init(X509DecoderContext* ctx,
    AppendDNFn append_dn, void* append_dn_ctx);

<*
  Push some certificate bytes into a decoder context.

  param ctx    X.509 decoder context.
  param data   certificate data chunk.
  param len    certificate data chunk length (in bytes).
*>
extern fn void x509_decoder_push(X509DecoderContext* ctx, void* data, sz len);

<*
  Obtain the decoded public key.

  Returns a pointer internal to the decoder context; releasing or reusing
  the context invalidates it. Returns null if decoding is unfinished or
  failed.

  param ctx   X.509 decoder context.
  returns the public key, or null on unfinished/error.
*>
fn X509PKey* x509_decoder_get_pkey(X509DecoderContext* ctx) @inline
{
    if (ctx.decoded && ctx.err == 0) {
        return &ctx.pkey;
    } else {
        return null;
    }
}

<*
  Get decoder error status.

  Returns ERR_X509_TRUNCATED if decoding is unfinished, 0 on success,
  or a non-zero error code on failure.

  param ctx   X.509 decoder context.
  returns 0 on successful decoding, or a non-zero error code.
*>
fn int x509_decoder_last_error(X509DecoderContext* ctx) @inline
{
    if (ctx.err != 0) {
        return ctx.err;
    }
    if (!ctx.decoded) {
        return ERR_X509_TRUNCATED;
    }
    return 0;
}

<*
  Get the "isCA" flag from an X.509 decoder context.

  Set if the decoded certificate claims CA status via a Basic Constraints
  extension. Should not be read before decoding completed successfully.

  param ctx   X.509 decoder context.
  returns the "isCA" flag.
*>
fn int x509_decoder_isCA(X509DecoderContext* ctx) @inline
{
    return ctx.isCA;
}

<*
  Get the issuing CA key type (algorithm used to sign the decoded certificate).

  Returns KEYTYPE_RSA or KEYTYPE_EC. Returns 0 if the signature type was
  not recognised.

  param ctx   X.509 decoder context.
  returns the issuing CA key type.
*>
fn int x509_decoder_get_signer_key_type(X509DecoderContext* ctx) @inline
{
    return ctx.signer_key_type;
}

<*
  Get the identifier for the hash function used to sign the decoded certificate.

  Returns 0 if the hash function was not recognised.

  param ctx   X.509 decoder context.
  returns the signature hash function identifier.
*>
fn int x509_decoder_get_signer_hash_id(X509DecoderContext* ctx) @inline
{
    return ctx.signer_hash_id;
}

// ============================================================================
// X.509 Certificate (DER-encoded)
// ============================================================================

<*
  Type for an X.509 certificate (DER-encoded).
*>
struct X509Certificate {
    <* The DER-encoded certificate data. *>
    char* data;
    <* The DER-encoded certificate length (in bytes). *>
    sz data_len;
}

// ============================================================================
// Private Key Decoder Context
// ============================================================================

<*
  Private key decoder context.

  Recognises RSA and EC private keys in raw DER format or wrapped in an
  unencrypted PKCS#8 archive (DER-encoded). Contents are opaque and shall
  not be accessed directly.
*>
struct SKeyDecoderContext {
    // Structure for returning the private key.
    union key {
        RSAPrivateKey rsa;
        ECPrivateKey ec;
    }

    // CPU for the T0 virtual machine.
    struct cpu {
        uint* dp;
        uint* rp;
        char* ip;
    }
    uint[32] dp_stack;
    uint[32] rp_stack;
    int err;

    // Private key data chunk.
    char* hbuf;
    sz hlen;

    // General-purpose pad for various operations.
    char[256] pad;

    // Decoded key type; 0 until decoding is complete.
    char key_type;

    // Buffer for private key elements (accommodates RSA-4096: ~5 × 2048-bit integers).
    char[3 * X509_BUFSIZE_SIG] key_data;
}

<*
  Initialise a private key decoder context.

  param ctx   key decoder context to initialise.
*>
extern fn void skey_decoder_init(SKeyDecoderContext* ctx);

<*
  Push some data bytes into a private key decoder context.

  param ctx    key decoder context.
  param data   private key data chunk.
  param len    private key data chunk length (in bytes).
*>
extern fn void skey_decoder_push(SKeyDecoderContext* ctx, void* data, sz len);

<*
  Get the decoding status for a private key.

  Returns ERR_X509_TRUNCATED if decoding is unfinished, 0 on success,
  or a non-zero error code on failure.

  param ctx   key decoder context.
  returns 0 on successful decoding, or a non-zero error code.
*>
fn int skey_decoder_last_error(SKeyDecoderContext* ctx) @inline
{
    if (ctx.err != 0) {
        return ctx.err;
    }
    if (ctx.key_type == 0) {
        return ERR_X509_TRUNCATED;
    }
    return 0;
}

<*
  Get the decoded private key type.

  Returns KEYTYPE_RSA or KEYTYPE_EC. Returns 0 if decoding is not
  finished or failed.

  param ctx   key decoder context.
  returns decoded private key type, or 0.
*>
fn int skey_decoder_key_type(SKeyDecoderContext* ctx) @inline
{
    if (ctx.err == 0) {
        return ctx.key_type;
    } else {
        return 0;
    }
}

<*
  Get the decoded RSA private key.

  Returns null if decoding failed, is unfinished, or the key is not RSA.
  The returned pointer references structures within the context that become
  invalid if the context is reused or released.

  param ctx   key decoder context.
  returns decoded RSA private key, or null.
*>
fn RSAPrivateKey* skey_decoder_get_rsa(SKeyDecoderContext* ctx) @inline
{
    if (ctx.err == 0 && ctx.key_type == KEYTYPE_RSA) {
        return &ctx.key.rsa;
    } else {
        return null;
    }
}

<*
  Get the decoded EC private key.

  Returns null if decoding failed, is unfinished, or the key is not EC.
  The returned pointer references structures within the context that become
  invalid if the context is reused or released.

  param ctx   key decoder context.
  returns decoded EC private key, or null.
*>
fn ECPrivateKey* skey_decoder_get_ec(SKeyDecoderContext* ctx) @inline
{
    if (ctx.err == 0 && ctx.key_type == KEYTYPE_EC) {
        return &ctx.key.ec;
    } else {
        return null;
    }
}

// ============================================================================
// Key Encoding Functions
// ============================================================================

<*
  Encode an RSA private key (raw DER format).

  Encodes the key in PKCS#1 (RFC 8017 Appendix C, RSAPrivateKey) with DER.

  If dest is not null, the encoded key is written there and the encoded
  length (in bytes) is returned. If dest is null, nothing is written but
  the encoded length is still computed and returned.

  param dest   destination buffer (or null).
  param sk     RSA private key.
  param pk     RSA public key.
  param d      RSA private exponent.
  param dlen   RSA private exponent length (in bytes).
  returns the encoded key length (in bytes).
*>
extern fn sz encode_rsa_raw_der(void* dest,
    RSAPrivateKey* sk, RSAPublicKey* pk, void* d, sz dlen);

<*
  Encode an RSA private key (PKCS#8 DER format).

  Wraps the raw DER encoding (as per encode_rsa_raw_der) in a PKCS#8
  OneAsymmetricKey structure (RFC 5958) with DER.

  If dest is not null, the encoded key is written there and the encoded
  length (in bytes) is returned. If dest is null, nothing is written but
  the encoded length is still computed and returned.

  param dest   destination buffer (or null).
  param sk     RSA private key.
  param pk     RSA public key.
  param d      RSA private exponent.
  param dlen   RSA private exponent length (in bytes).
  returns the encoded key length (in bytes).
*>
extern fn sz encode_rsa_pkcs8_der(void* dest,
    RSAPrivateKey* sk, RSAPublicKey* pk, void* d, sz dlen);

<*
  Encode an EC private key (raw DER format).

  Encodes the key per RFC 5915 (ECPrivateKey) with DER. If pk is null,
  the publicKey field is omitted (it is nominally optional).

  If dest is not null, the encoded key is written there and the encoded
  length (in bytes) is returned. If dest is null, nothing is written but
  the encoded length is still computed and returned.

  Returns 0 if the key cannot be encoded (e.g. no known OID for the curve).

  param dest   destination buffer (or null).
  param sk     EC private key.
  param pk     EC public key (or null).
  returns the encoded key length (in bytes), or 0.
*>
extern fn sz encode_ec_raw_der(void* dest, ECPrivateKey* sk, ECPublicKey* pk);

<*
  Encode an EC private key (PKCS#8 DER format).

  Encodes the key in PKCS#8 OneAsymmetricKey (RFC 5958) format. The curve
  OID is included in the privateKeyAlgorithm field. The privateKey field
  contains the DER encoding of ECPrivateKey (RFC 5915) without its
  parameters field. If pk is not null, the encoded public key is included
  in the publicKey field of the ECPrivateKey value (but not in the PKCS#8
  wrapper's publicKey field).

  If dest is not null, the encoded key is written there and the encoded
  length (in bytes) is returned. If dest is null, nothing is written but
  the encoded length is still computed and returned.

  Returns 0 if the key cannot be encoded (e.g. no known OID for the curve).

  param dest   destination buffer (or null).
  param sk     EC private key.
  param pk     EC public key (or null).
  returns the encoded key length (in bytes), or 0.
*>
extern fn sz encode_ec_pkcs8_der(void* dest, ECPrivateKey* sk, ECPublicKey* pk);
