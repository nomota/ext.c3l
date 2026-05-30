// ssl.h.c3 

module ext::net::tls;

// The `TLS_*` constants correspond to the standard cipher suites and
// their values in the IANA registry.
//
// The `ALERT_*` constants are for standard TLS alert messages. When
// a fatal alert message is sent or received, then the SSL engine context
// status is set to the sum of that alert value (an integer in the 0..255
// range) and a fixed offset (`ERR_SEND_FATAL_ALERT` for a sent alert,
// `ERR_RECV_FATAL_ALERT` for a received alert).

<*
  Optimal input buffer size.
*>
const SSL_BUFSIZE_INPUT = 16384 + 325;

<*
  Optimal output buffer size.
*>
const SSL_BUFSIZE_OUTPUT = 16384 + 85;

<*
  Optimal buffer size for monodirectional engine
  (shared input/output buffer).
*>
const SSL_BUFSIZE_MONO = SSL_BUFSIZE_INPUT;

<*
  Optimal buffer size for bidirectional engine
  (single buffer split into two separate input/output buffers).
*>
const SSL_BUFSIZE_BIDI = SSL_BUFSIZE_INPUT + SSL_BUFSIZE_OUTPUT;

//
// Constants for known SSL/TLS protocol versions (SSL 3.0, TLS 1.0, TLS 1.1
// and TLS 1.2). Note that though there is a constant for SSL 3.0, that
// protocol version is not actually supported.
//

<*
  Protocol version: SSL 3.0 (unsupported).
*>
const SSL30 = 0x0300;

<*
  Protocol version: TLS 1.0.
*>
const TLS10 = 0x0301;

<*
  Protocol version: TLS 1.1.
*>
const TLS11 = 0x0302;

<*
  Protocol version: TLS 1.2.
*>
const TLS12 = 0x0303;

//
// Error constants. They are used to report the reason why a context has
// been marked as failed.
//
// Implementation note: SSL-level error codes should be in the 1..31
// range. The 32..63 range is for certificate decoding and validation
// errors. Received fatal alerts imply an error code in the 256..511 range.
//

<*
  SSL status: no error so far (0).
*>
const ERR_OK = 0;

<*
  SSL status: caller-provided parameter is incorrect.
*>
const ERR_BAD_PARAM = 1;

<*
  SSL status: operation requested by the caller cannot be applied
  with the current context state (e.g. reading data while outgoing data
  is waiting to be sent).
*>
const ERR_BAD_STATE = 2;

<*
  SSL status: incoming protocol or record version is unsupported.
*>
const ERR_UNSUPPORTED_VERSION = 3;

<*
  SSL status: incoming record version does not match the expected
  version.
*>
const ERR_BAD_VERSION = 4;

<*
  SSL status: incoming record length is invalid.
*>
const ERR_BAD_LENGTH = 5;

<*
  SSL status: incoming record is too large to be processed, or
  buffer is too small for the handshake message to send.
*>
const ERR_TOO_LARGE = 6;

<*
  SSL status: decryption found an invalid padding, or the record
  MAC is not correct.
*>
const ERR_BAD_MAC = 7;

<*
  SSL status: no initial entropy was provided, and none can be
  obtained from the OS.
*>
const ERR_NO_RANDOM = 8;

<*
  SSL status: incoming record type is unknown.
*>
const ERR_UNKNOWN_TYPE = 9;

<*
  SSL status: incoming record or message has wrong type with
  regards to the current engine state.
*>
const ERR_UNEXPECTED = 10;

<*
  SSL status: ChangeCipherSpec message from the peer has invalid
  contents.
*>
const ERR_BAD_CCS = 12;

<*
  SSL status: alert message from the peer has invalid contents
  (odd length).
*>
const ERR_BAD_ALERT = 13;

<*
  SSL status: incoming handshake message decoding failed.
*>
const ERR_BAD_HANDSHAKE = 14;

<*
  SSL status: ServerHello contains a session ID which is larger
  than 32 bytes.
*>
const ERR_OVERSIZED_ID = 15;

<*
  SSL status: server wants to use a cipher suite that we did
  not claim to support. This is also reported if we tried to advertise
  a cipher suite that we do not support.
*>
const ERR_BAD_CIPHER_SUITE = 16;

<*
  SSL status: server wants to use a compression that we did not
  claim to support.
*>
const ERR_BAD_COMPRESSION = 17;

<*
  SSL status: server's max fragment length does not match
  client's.
*>
const ERR_BAD_FRAGLEN = 18;

<*
  SSL status: secure renegotiation failed.
*>
const ERR_BAD_SECRENEG = 19;

<*
  SSL status: server sent an extension type that we did not
  announce, or used the same extension type several times in a single
  ServerHello.
*>
const ERR_EXTRA_EXTENSION = 20;

<*
  SSL status: invalid Server Name Indication contents (when
  used by the server, this extension shall be empty).
*>
const ERR_BAD_SNI = 21;

<*
  SSL status: invalid ServerHelloDone from the server (length
  is not 0).
*>
const ERR_BAD_HELLO_DONE = 22;

<*
  SSL status: internal limit exceeded (e.g. server's public key
  is too large).
*>
const ERR_LIMIT_EXCEEDED = 23;

<*
  SSL status: Finished message from peer does not match the
  expected value.
*>
const ERR_BAD_FINISHED = 24;

<*
  SSL status: session resumption attempt with distinct version
  or cipher suite.
*>
const ERR_RESUME_MISMATCH = 25;

<*
  SSL status: unsupported or invalid algorithm (ECDHE curve,
  signature algorithm, hash function).
*>
const ERR_INVALID_ALGORITHM = 26;

<*
  SSL status: invalid signature (on ServerKeyExchange from
  server, or in CertificateVerify from client).
*>
const ERR_BAD_SIGNATURE = 27;

<*
  SSL status: peer's public key does not have the proper type
  or is not allowed for requested operation.
*>
const ERR_WRONG_KEY_USAGE = 28;

<*
  SSL status: client did not send a certificate upon request,
  or the client certificate could not be validated.
*>
const ERR_NO_CLIENT_AUTH = 29;

<*
  SSL status: I/O error or premature close on underlying
  transport stream. This error code is set only by the simplified
  I/O API ("sslio_*").
*>
const ERR_IO = 31;

<*
  SSL status: base value for a received fatal alert.

  When a fatal alert is received from the peer, the alert value
  is added to this constant.
*>
const ERR_RECV_FATAL_ALERT = 256;

<*
  SSL status: base value for a sent fatal alert.

  When a fatal alert is sent to the peer, the alert value is added
  to this constant.
*>
const ERR_SEND_FATAL_ALERT = 512;

<*
  Test validity of the incoming record length.

  This function returns 1 if the announced length for an
  incoming record is valid, 0 otherwise.

  param ctx          decryption engine context.
  param record_len   incoming record length.
  returns 1 if valid length, 0 otherwise.
*>
alias CheckLengthFn = fn int(SSLRecInClass** ctx, sz record_len);

<*
  Decrypt the incoming record.

  This function may assume that the record length is valid
  (it has been previously tested with `check_length()`).
  Decryption is done in place; `*len` is updated with the
  cleartext length, and the address of the first plaintext
  byte is returned. If the record is correct but empty, then
  `*len` is set to 0 and a non-null pointer is returned.

  On decryption/MAC error, null is returned.

  param ctx           decryption engine context.
  param record_type   record type (23 for application data, etc).
  param version       record version.
  param payload       address of encrypted payload.
  param len           pointer to payload length (updated).
  returns pointer to plaintext, or null on error.
*>
alias DecryptFn = fn char* (SSLRecInClass** ctx, int record_type, uint version, void* payload, sz* len);

<*
  Decryption engine for SSL.

  When processing incoming records, the SSL engine will use a decryption
  engine that uses a specific context structure, and has a set of
  methods (a vtable) that follows this template.

  The decryption engine is responsible for applying decryption, verifying
  MAC, and keeping track of the record sequence number.
*>
struct SSLRecInClass {
    <*
      Context size (in bytes).
    *>
    sz context_size;

    CheckLengthFn check_length;
    DecryptFn decrypt;
}

<*
  Compute maximum plaintext sizes and offsets.

  When this function is called, the `*start` and `*end`
  values contain offsets designating the free area in the
  outgoing buffer for plaintext data; that free area is
  preceded by a 5-byte space which will receive the record
  header.

  The `max_plaintext()` function is responsible for adjusting
  both `*start` and `*end` to make room for any record-specific
  header, MAC, padding, and possible split.

  param ctx     encryption engine context.
  param start   pointer to start of plaintext offset (updated).
  param end     pointer to end of plaintext offset (updated).
*>
alias MaxPlaintextFn = fn void(SSLRecOutClass** ctx, sz* start, sz* end);

<*
  Perform record encryption.

  This function encrypts the record. The plaintext address and
  length are provided. Returned value is the start of the
  encrypted record (or sequence of records, if a split was
  performed), including the 5-byte header, and `*len` is
  adjusted to the total size of the record(s), also including
  the header(s).

  param ctx           encryption engine context.
  param record_type   record type (23 for application data, etc).
  param version       record version.
  param plaintext     address of plaintext.
  param len           pointer to plaintext length (updated).
  returns pointer to start of built record.
*>
alias EncryptFn = fn char* (SSLRecOutClass** ctx, int record_type, uint version, void* plaintext, sz* len);

<*
  Encryption engine for SSL.

  When building outgoing records, the SSL engine will use an encryption
  engine that uses a specific context structure, and has a set of
  methods (a vtable) that follows this template.

  The encryption engine is responsible for applying encryption and MAC,
  and keeping track of the record sequence number.
*>
struct SSLRecOutClass {
    <*
      Context size (in bytes).
    *>
    sz context_size;

    MaxPlaintextFn max_plaintext;
    EncryptFn encrypt;
}

<*
  Context for a no-encryption engine.

  The no-encryption engine processes outgoing records during the initial
  handshake, before encryption is applied.
*>
struct SSLRecOutClearContext {
    <*
      No-encryption engine vtable.
    *>
    SSLRecOutClass* vtable;
}

<*
  Static, constant vtable for the no-encryption engine.
*>
extern SSLRecOutClass sslrec_out_clear_vtable;

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CBC decryption).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
  param dig_impl      hash function for HMAC.
  param mac_key       HMAC key.
  param mac_key_len   HMAC key length (in bytes).
  param mac_out_len   HMAC output length (in bytes).
  param iv            initial IV (or null).
*>
alias SSLRecInCBCInitFn = fn void(SSLRecInCBCClass** ctx, BlockCBCDecClass* bc_impl, void* bc_key, sz bc_key_len, HashClass* dig_impl, void* mac_key, sz mac_key_len, sz mac_out_len, void* iv);

<*
  Record decryption engine class, for CBC mode.

  This class type extends the decryption engine class with an
  initialisation method that receives the parameters needed
  for CBC processing: block cipher implementation, block cipher key,
  HMAC parameters (hash function, key, MAC length), and IV. If the
  IV is null, then a per-record IV will be used (TLS 1.1+).
*>
struct SSLRecInCBCClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecInClass inner;

    SSLRecInCBCInitFn init;
}

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CBC encryption).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
  param dig_impl      hash function for HMAC.
  param mac_key       HMAC key.
  param mac_key_len   HMAC key length (in bytes).
  param mac_out_len   HMAC output length (in bytes).
  param iv            initial IV (or null).
*>
alias SSLRecOutCBCInitFn = fn void(SSLRecOutCBCClass** ctx, BlockCBCEncClass* bc_impl, void* bc_key, sz bc_key_len, HashClass* dig_impl, void* mac_key, sz mac_key_len, sz mac_out_len, void* iv);

<*
  Record encryption engine class, for CBC mode.

  This class type extends the encryption engine class with an
  initialisation method that receives the parameters needed
  for CBC processing: block cipher implementation, block cipher key,
  HMAC parameters (hash function, key, MAC length), and IV. If the
  IV is null, then a per-record IV will be used (TLS 1.1+).
*>
struct SSLRecOutCBCClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecOutClass inner;

    SSLRecOutCBCInitFn init;
}

<*
  Context structure for decrypting incoming records with
  CBC + HMAC.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecInCBCContext {
    <*
      Pointer to vtable.
    *>
    SSLRecInCBCClass* vtable;

    ulong seq;

    union bc {
        BlockCBCDecClass* vtable;
        AESGenCBCDecKeys aes;
        DESGenCBCDecKeys des;
    }

    HmacKeyContext mac;
    sz mac_len;
    char[16] iv;
    int explicit_iv;
}

<*
  Static, constant vtable for record decryption with CBC.
*>
extern SSLRecInCBCClass sslrec_in_cbc_vtable;

<*
  Context structure for encrypting outgoing records with
  CBC + HMAC.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecOutCBCContext {
    <*
      Pointer to vtable.
    *>
    SSLRecOutCBCClass* vtable;

    ulong seq;

    union bc {
        BlockCBCEncClass* vtable;
        AESGenCBCEncKeys aes;
        DESGenCBCEncKeys des;
    }

    HmacKeyContext mac;
    sz mac_len;
    char[16] iv;
    int explicit_iv;
}

<*
  Static, constant vtable for record encryption with CBC.
*>
extern SSLRecOutCBCClass sslrec_out_cbc_vtable;

/*
<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CTR encryption/decryption).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
*>
*/
//alias SSLRecInCTRInitFn = fn void(SSLRecInCTRClass** ctx, BlockCTRClass* bc_impl, void* bc_key, sz bc_key_len);

/*
<*
  Record decryption engine class, for stream mode based on CTR.

  This class type extends the decryption engine class with an
  initialisation method that receives the parameters needed
  for CTR processing.
*>
struct SSLRecInCTRClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecInClass inner;

    SSLRecInCTRInitFn init;
}
*/

/*
<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CTR encryption/decryption).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
*>
*/
// alias SSLRecOutCTRInitFn = fn void(SSLRecOutCTRClass** ctx, BlockCTRClass* bc_impl, void* bc_key, sz bc_key_len);

/*
<*
  Record encryption engine class, for stream mode based on CTR.

  This class type extends the encryption engine class with an
  initialisation method that receives the parameters needed
  for CTR processing.
*>
struct SSLRecOutCTRClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecOutClass inner;

    SSLRecOutCTRInitFn init;
}
*/

/*
<*
  Context structure for decrypting incoming records with
  stream cipher mode based on CTR.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecInCTRContext {
    <*
      Pointer to vtable.
    *>
    SSLRecInCTRClass* vtable;

    ulong seq;

    union bc {
        BlockCTRClass* vtable;
        AESGenCTRKeys aes;
    }
}
*/

/*
<*
  Context structure for encrypting outgoing records with
  stream cipher mode based on CTR.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecOutCTRContext {
    <*
      Pointer to vtable.
    *>
    SSLRecOutCTRClass* vtable;

    ulong seq;

    union bc {
        BlockCTRClass* vtable;
        AESGenCTRKeys aes;
    }
}
*/


<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CTR encryption/decryption).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
  param ghash         GHASH implementation.
*>
alias SSLRecInGCMInitFn = fn void(SSLRecInGCMClass** ctx, BlockCTRClass* bc_impl, void* bc_key, sz bc_key_len, GHashFn ghash, void* iv);

<*
  Record decryption engine class, for GCM mode.

  This class type extends the decryption engine class with an
  initialisation method that receives the parameters needed
  for GCM processing.
*>
struct SSLRecInGCMClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecInClass inner;

    SSLRecInGCMInitFn init;
}

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CTR encryption/decryption).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
  param ghash         GHASH implementation.
*>
alias SSLRecOutGCMInitFn = fn void(SSLRecOutGCMClass** ctx, BlockCTRClass* bc_impl, void* bc_key, sz bc_key_len, GHashFn ghash, void* iv);

<*
  Record encryption engine class, for GCM mode.

  This class type extends the encryption engine class with an
  initialisation method that receives the parameters needed
  for GCM processing.
*>
struct SSLRecOutGCMClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecOutClass inner;

    SSLRecOutGCMInitFn init;
}

<*
  Context structure for decrypting incoming records with GCM.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecGCMContext {
    <*
      Pointer to vtable.
    *>
    union vtable {
        void* gen;
        SSLRecInGCMClass* in;
        SSLRecOutGCMClass* out;
    }

    ulong seq;

    union bc {
        BlockCTRClass* vtable;
        AESGenCTRKeys aes;
    }

    GHashFn gh;
    char[4] iv;
    char[16] h;
}

<*
  Static, constant vtable for record decryption with GCM.
*>
extern SSLRecInGCMClass sslrec_in_gcm_vtable;


<*
  Static, constant vtable for record encryption with GCM.
*>
extern SSLRecOutGCMClass sslrec_out_gcm_vtable;

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CTR+CBC-MAC).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
  param tag_len       authentication tag length (in bytes).
*>
alias SSLRecInCCMInitFn = fn void(SSLRecInCCMClass** ctx, BlockCTRCBCClass* bc_impl, void* bc_key, sz bc_key_len, void* iv, sz tag_len);

<*
  Record decryption engine class, for CCM mode.

  This class type extends the decryption engine class with an
  initialisation method that receives the parameters needed
  for CCM processing.
*>
struct SSLRecInCCMClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecInClass inner;

    SSLRecInCCMInitFn init;
}

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx           context to initialise.
  param bc_impl       block cipher implementation (CTR+CBC-MAC).
  param bc_key        block cipher key.
  param bc_key_len    block cipher key length (in bytes).
  param tag_len       authentication tag length (in bytes).
*>
alias SSLRecOutCCMInitFn = fn void(SSLRecOutCCMClass** ctx, BlockCTRCBCClass* bc_impl, void* bc_key, sz bc_key_len, void* iv, sz tag_len);

<*
  Record encryption engine class, for CCM mode.

  This class type extends the encryption engine class with an
  initialisation method that receives the parameters needed
  for CCM processing.
*>
struct SSLRecOutCCMClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecOutClass inner;

    SSLRecOutCCMInitFn init;
}

<*
  Context structure for decrypting incoming records with CCM.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecCCMContext {
    <*
      Pointer to vtable.
    *>
    union vtable {
        void* gen;
        SSLRecInCCMClass* in;
        SSLRecOutCCMClass* out;
    }

    ulong seq;

    union bc {
        BlockCTRCBCClass* vtable;
        AESGenCTRCBCKeys aes;
    }
    char[4] iv;
    sz tag_len;
}

<*
  Static, constant vtable for record decryption with CCM.
*>
extern SSLRecInCCMClass sslrec_in_ccm_vtable;


<*
  Static, constant vtable for record encryption with CCM.
*>
extern SSLRecOutCCMClass sslrec_out_ccm_vtable;

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx          context to initialise.
  param ichacha      ChaCha20 implementation.
  param ipoly        Poly1305 implementation.
  param key          key.
*>
alias SSLRecInChaPolInitFn = fn void(SSLRecInChaPolClass** ctx, ChaCha20Run ichacha, Poly1305Run ipoly, void* key, void* iv);

<*
  Record decryption engine class, for ChaCha20+Poly1305.

  This class type extends the decryption engine class with an
  initialisation method that receives the parameters needed
  for ChaCha20+Poly1305 processing.
*>
struct SSLRecInChaPolClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecInClass inner;

    SSLRecInChaPolInitFn init;
}

<*
  Engine initialisation method.

  This method sets the vtable field in the context.

  param ctx          context to initialise.
  param ichacha      ChaCha20 implementation.
  param ipoly        Poly1305 implementation.
  param key          key.
*>
alias SSLRecOutChaPolInitFn = fn void(SSLRecOutChaPolClass** ctx, ChaCha20Run ichacha, Poly1305Run ipoly, void* key, void* iv);

<*
  Record encryption engine class, for ChaCha20+Poly1305.

  This class type extends the encryption engine class with an
  initialisation method that receives the parameters needed
  for ChaCha20+Poly1305 processing.
*>
struct SSLRecOutChaPolClass {
    <*
      Superclass, as first vtable field.
    *>
    SSLRecOutClass inner;

    SSLRecOutChaPolInitFn init;
}

<*
  Context structure for decrypting incoming records with
  ChaCha20+Poly1305.

  The first field points to the vtable. The other fields are opaque
  and shall not be accessed directly.
*>
struct SSLRecChaPolContext {
    <*
      Pointer to vtable.
    *>
    union vtable {
        void* gen;
        SSLRecInChaPolClass* in;
        SSLRecOutChaPolClass* out;
    }

    ulong seq;
    char[32] key;
    char[12] iv;

    ChaCha20Run ichacha;
    Poly1305Run ipoly;
}

<*
  Static, constant vtable for record decryption with
  ChaCha20+Poly1305.
*>
extern SSLRecInChaPolClass sslrec_in_chapol_vtable;


<*
  Static, constant vtable for record encryption with
  ChaCha20+Poly1305.
*>
extern SSLRecOutChaPolClass sslrec_out_chapol_vtable;

//
// ============================================================================
//

/*
<*
  A supported cipher suite.
*>
struct CipherSuite {
    uint suite;
    ushort min_version;
    ushort max_version;
    char cipher_type;
    char mac_id;
    char prf_id;
}

<*
  No encryption / no MAC.
*>
//const CIPHER_SUITE_CLEAR = 0;

<*
  RSA key exchange.
*>
//const KEYX_RSA = 1;

<*
  ECDHE_RSA key exchange.
*>
//const KEYX_ECDHE_RSA = 2;

<*
  ECDHE_ECDSA key exchange.
*>
//const KEYX_ECDHE_ECDSA = 3;

<*
  Static ECDH with RSA certificate.
*>
//const KEYX_ECDH_RSA = 4;

<*
  Static ECDH with ECDSA certificate.
*>
//const KEYX_ECDH_ECDSA = 5;

<*
  AES/CBC with HMAC.
*>
//const CIPHER_AES_CBC = 1;

<*
  AES/GCM.
*>
//const CIPHER_AES_GCM = 2;

<*
  AES/CCM.
*>
//const CIPHER_AES_CCM = 3;

<*
  AES/CCM with 8-byte tag.
*>
//const CIPHER_AES_CCM_8 = 4;

<*
  3DES/CBC with HMAC.
*>
//const CIPHER_3DES_CBC = 5;

<*
  ChaCha20+Poly1305.
*>
//const CIPHER_CHACHA20_POLY1305 = 6;
*/

<*
  Type for session parameters, to be saved for session resumption.
*>
struct SSLSessionParameters {
    <*
      Session ID buffer.
    *>
    char[32] session_id;

    <*
      Session ID length (in bytes, at most 32).
    *>
    char session_id_len;

    <*
      Protocol version.
    *>
    ushort version;

    <*
      Cipher suite.
    *>
    ushort cipher_suite;

    <*
      Master secret.
    *>
    char[48] master_secret;
}

//
// Maximum number of cipher suites supported by a client or server.
//
const MAX_CIPHER_SUITES = 48;

<*
  Handshake runner callback.
*>
alias HSRunFn = fn void(void* ctx);

<*
  Context structure for SSL engine.

  This strucuture is common to the client and server; both the client
  context (`SSLClientContext`) and the server context
  (`SSLServerContext`) include a `SSLEngineContext` as their
  first field.

  The engine context manages records, including alerts, closures, and
  transitions to new encryption/MAC algorithms. Processing of handshake
  records is delegated to externally provided code. This structure
  should not be used directly.

  Structure contents are opaque and shall not be accessed directly.
*>
struct SSLEngineContext {
    //
    // The error code. When non-zero, then the state is "failed" and
    // no I/O may occur until reset.
    //
    int err;

    //
    // Configured I/O buffers. They are either disjoint, or identical.
    //
    char* ibuf;
    char* obuf;
    sz ibuf_len;
    sz obuf_len;

    //
    // Maximum fragment length applies to outgoing records; incoming
    // records can be processed as long as they fit in the input
    // buffer. It is guaranteed that incoming records at least as big
    // as max_frag_len can be processed.
    //
    ushort max_frag_len;
    char log_max_frag_len;
    char peer_log_max_frag_len;

    //
    // Buffering management registers.
    //
    sz ixa;
    sz ixb;
    sz ixc;
    sz oxa;
    sz oxb;
    sz oxc;
    char iomode;
    char incrypt;

    //
    // Shutdown flag: when set to non-zero, incoming record bytes
    // will not be accepted anymore. This is used after a close_notify
    // has been received: afterwards, the engine no longer claims that
    // it could receive bytes from the transport medium.
    //
    char shutdown_recv;

    //
    // 'record_type_in' is set to the incoming record type when the
    // record header has been received.
    // 'record_type_out' is used to make the next outgoing record
    // header when it is ready to go.
    //
    char record_type_in;
    char record_type_out;

    //
    // When a record is received, its version is extracted:
    // -- if 'version_in' is 0, then it is set to the received version;
    // -- otherwise, if the received version is not identical to
    //    the 'version_in' contents, then a failure is reported.
    //
    // This implements the SSL requirement that all records shall
    // use the negotiated protocol version, once decided (in the
    // ServerHello). It is up to the handshake handler to adjust this
    // field when necessary.
    //
    ushort version_in;

    //
    // 'version_out' is used when the next outgoing record is ready
    // to go.
    //
    ushort version_out;

    //
    // Record handler contexts.
    //
    union in {
        SSLRecInClass* vtable;
        SSLRecInCBCContext cbc;
        SSLRecGCMContext gcm;
        SSLRecChaPolContext chapol;
        SSLRecCCMContext ccm;
    }

    union out {
        SSLRecOutClass* vtable;
        SSLRecOutClearContext clear;
        SSLRecOutCBCContext cbc;
        SSLRecGCMContext gcm;
        SSLRecChaPolContext chapol;
        SSLRecCCMContext ccm;
    }

    //
    // The "application data" flag. Value:
    //   0   handshake is in process, no application data acceptable
    //   1   application data can be sent and received
    //   2   closing, no application data can be sent, but some
    //       can still be received (and discarded)
    //
    char application_data;

    //
    // Context RNG.
    //
    //   rng_init_done is initially 0. It is set to 1 when the
    //   basic structure of the RNG is set, and 2 when some
    //   entropy has been pushed in. The value 2 marks the RNG
    //   as "properly seeded".
    //
    //   rng_os_rand_done is initially 0. It is set to 1 when
    //   some seeding from the OS or hardware has been attempted.
    //
    HmacDRBGContext rng;
    int rng_init_done;
    int rng_os_rand_done;

    //
    // Supported minimum and maximum versions, and cipher suites.
    //
    ushort version_min;
    ushort version_max;
    ushort[MAX_CIPHER_SUITES] suites_buf;
    char suites_num;

    //
    // For clients, the server name to send as a SNI extension. For
    // servers, the name received in the SNI extension (if any).
    //
    char[256] server_name;

    //
    // "Security parameters". These are filled by the handshake
    // handler, and used when switching encryption state.
    //
    char[32] client_random;
    char[32] server_random;
    SSLSessionParameters session;

    //
    // ECDHE elements: curve and point from the peer. The server also
    // uses that buffer for the point to send to the client.
    //
    char ecdhe_curve;
    char[133] ecdhe_point;
    char ecdhe_point_len;

    //
    // Secure renegotiation (RFC 5746): 'reneg' can be:
    //   0   first handshake (server support is not known)
    //   1   peer does not support secure renegotiation
    //   2   peer supports secure renegotiation
    //
    // The saved_finished buffer contains the client and the
    // server "Finished" values from the last handshake, in
    // that order (12 bytes each).
    //
    char reneg;
    char[24] saved_finished;

    //
    // Behavioural flags.
    //
    uint flags;

    //
    // Context variables for the handshake processor. The 'pad' must
    // be large enough to accommodate an RSA-encrypted pre-master
    // secret, or an RSA signature; since we want to support up to
    // RSA-4096, this means at least 512 bytes. (Other pad usages
    // require its length to be at least 256.)
    //
    struct cpu {
        uint* dp;
        uint* rp;
        char* ip;
    }

    uint[32] dp_stack;
    uint[32] rp_stack;
    char[512] pad;
    char* hbuf_in;
    char* hbuf_out;
    char* saved_hbuf_out;
    sz hlen_in;
    sz hlen_out;

    HSRunFn hsrun;

    //
    // The 'action' value communicates OOB information between the
    // engine and the handshake processor.
    //
    // From the engine:
    //   0  invocation triggered by I/O
    //   1  invocation triggered by explicit close
    //   2  invocation triggered by explicit renegotiation
    //
    char action;

    //
    // State for alert messages. Value is either 0, or the value of
    // the alert level byte (level is either 1 for warning, or 2 for
    // fatal; we convert all other values to 'fatal').
    //
    char alert;

    //
    // Closure flags. This flag is set when a close_notify has been
    // received from the peer.
    //
    char close_received;

    //
    // Multi-hasher for the handshake messages. The handshake handler
    // is responsible for resetting it when appropriate.
    //
    MultiHashContext mhash;

    //
    // Pointer to the X.509 engine. The engine is supposed to be
    // already initialized. It is used to validate the peer's
    // certificate.
    //
    X509Class** x509ctx;

    //
    // Certificate chain to send. This is used by both client and
    // server, when they send their respective Certificate messages.
    // If chain_len is 0, then chain may be null.
    //
    X509Certificate* chain;
    sz chain_len;
    char* cert_cur;
    sz cert_len;

    //
    // List of supported protocol names (ALPN extension). If unset,
    // (number of names is 0), then:
    //  - the client sends no ALPN extension;
    //  - the server ignores any incoming ALPN extension.
    //
    // Otherwise:
    //  - the client sends an ALPN extension with all the names;
    //  - the server selects the first protocol in its list that
    //    the client also supports, or fails (fatal alert 120)
    //    if the client sends an ALPN extension and there is no
    //    match.
    //
    // The 'selected_protocol' field contains 1+n if the matching
    // name has index n in the list (the value is 0 if no match was
    // performed, e.g. the peer did not send an ALPN extension).
    //
    char** protocol_names;
    ushort protocol_names_num;
    ushort selected_protocol;

    //
    // Pointers to implementations; left to null for unsupported
    // functions. For the raw hash functions, implementations are
    // referenced from the multihasher (mhash field).
    //
    TLSPrfImpl prf10;
    TLSPrfImpl prf_sha256;
    TLSPrfImpl prf_sha384;
    BlockCBCEncClass* iaes_cbcenc;
    BlockCBCDecClass* iaes_cbcdec;
    BlockCTRClass* iaes_ctr;
    BlockCTRCBCClass* iaes_ctrcbc;
    BlockCBCEncClass* ides_cbcenc;
    BlockCBCDecClass* ides_cbcdec;
    GHashFn ighash;
    ChaCha20Run ichacha;
    Poly1305Run ipoly;
    SSLRecInCBCClass* icbc_in;
    SSLRecOutCBCClass* icbc_out;
    SSLRecInGCMClass* igcm_in;
    SSLRecOutGCMClass* igcm_out;
    SSLRecInChaPolClass* ichapol_in;
    SSLRecOutChaPolClass* ichapol_out;
    SSLRecInCCMClass* iccm_in;
    SSLRecOutCCMClass* iccm_out;
    ECImpl* iec;
    RSAPKCS1Vrfy irsavrfy;
    ECDSAVrfy iecdsa;
}

<*
  Get currently defined engine behavioural flags.

  param cc   SSL engine context.
  returns the flags.
*>
fn uint ssl_engine_get_flags(SSLEngineContext* cc) @inline
{
    return cc.flags;
}

<*
  Set all engine behavioural flags.

  param cc      SSL engine context.
  param flags   new value for all flags.
*>
fn void ssl_engine_set_all_flags(SSLEngineContext* cc, uint flags) @inline
{
    cc.flags = flags;
}

<*
  Set some engine behavioural flags.

  The flags set in the `flags` parameter are set in the context; other
  flags are untouched.

  param cc      SSL engine context.
  param flags   additional set flags.
*>
fn void ssl_engine_add_flags(SSLEngineContext* cc, uint flags) @inline
{
    cc.flags |= flags;
}

<*
  Clear some engine behavioural flags.

  The flags set in the `flags` parameter are cleared from the context; other
  flags are untouched.

  param cc      SSL engine context.
  param flags   flags to remove.
*>
fn void ssl_engine_remove_flags(SSLEngineContext* cc, uint flags) @inline
{
    cc.flags &= ~flags;
}

<*
  Behavioural flag: enforce server preferences.

  If this flag is set, then the server will enforce its own cipher suite
  preference order; otherwise, it follows the client preferences.
*>
const OPT_ENFORCE_SERVER_PREFERENCES = (uint)1 << 0;

<*
  Behavioural flag: disable renegotiation.

  If this flag is set, then renegotiations are rejected unconditionally:
  they won't be honoured if asked for programmatically, and requests from
  the peer are rejected.
*>
const OPT_NO_RENEGOTIATION = (uint)1 << 1;

<*
  Behavioural flag: tolerate lack of client authentication.

  If this flag is set in a server and the server requests a client
  certificate, but the authentication fails (the client does not send
  a certificate, or the client's certificate chain cannot be validated),
  then the connection keeps on. Without this flag, a failed client
  authentication terminates the connection.

  Notes:

    - If the client's certificate can be validated and its public key is
      supported, then a wrong signature value terminates the connection
      regardless of that flag.

    - If using full-static ECDH, then a failure to validate the client's
      certificate prevents the handshake from succeeding.
*>
const OPT_TOLERATE_NO_CLIENT_AUTH = (uint)1 << 2;

<*
  Behavioural flag: fail on application protocol mismatch.

  The ALPN extension allows the client to send a list of application
  protocol names, and the server to select one.

  Normal behaviour in case of mismatch is to report no matching name
  (`ssl_engine_get_selected_protocol()` returns `null`) and carry on.
  If the flag is set, then a mismatch implies a protocol failure.
*>
const OPT_FAIL_ON_ALPN_MISMATCH = (uint)1 << 3;

<*
  Set the minimum and maximum supported protocol versions.

  The two provided versions MUST be supported by the implementation
  (i.e. TLS 1.0, 1.1 and 1.2), and `version_max` MUST NOT be lower
  than `version_min`.

  param cc            SSL engine context.
  param version_min   minimum supported TLS version.
  param version_max   maximum supported TLS version.
*>
fn void ssl_engine_set_versions(SSLEngineContext* cc, uint version_min, uint version_max) @inline
{
    cc.version_min = (ushort)version_min;
    cc.version_max = (ushort)version_max;
}

<*
  Set the list of cipher suites advertised by this context.

  The provided array is copied into the context.

  param cc           SSL engine context.
  param suites       cipher suites.
  param suites_num   number of cipher suites.
*>
extern fn void ssl_engine_set_suites(SSLEngineContext* cc, ushort* suites, sz suites_num);

<*
  Set the X.509 engine.

  The caller shall ensure that the X.509 engine is properly initialised.

  param cc        SSL engine context.
  param x509ctx   X.509 certificate validation context.
*>
fn void ssl_engine_set_x509(SSLEngineContext* cc, X509Class** x509ctx) @inline
{
    cc.x509ctx = x509ctx;
}

<*
  Set the supported protocol names.

  param ctx     SSL engine context.
  param names   list of protocol names (zero-terminated).
  param num     number of protocol names (MUST be 1 or more).
*>
fn void ssl_engine_set_protocol_names(SSLEngineContext* ctx, char** names, sz num) @inline
{
    ctx.protocol_names = names;
    ctx.protocol_names_num = (ushort)num;
}

<*
  Get the selected protocol.

  If this context was initialised with a non-empty list of protocol
  names, and both client and server sent ALPN extensions during the
  handshake, and a common name was found, then that name is returned.
  Otherwise, `null` is returned.

  returns the selected protocol, or `null`.
*>
fn char* ssl_engine_get_selected_protocol(SSLEngineContext* ctx) @inline
{
    uint k = ctx.selected_protocol;
    return (k == 0 || k == 0xFFFF) ? null : ctx.protocol_names[k - 1];
}

<*
  Set a hash function implementation (by ID).

  param ctx    SSL engine context.
  param id     hash function identifier.
  param impl   hash function implementation.
*>
fn void ssl_engine_set_hash(SSLEngineContext* ctx, int id, HashClass* impl) @inline
{
    multihash_setimpl(&ctx.mhash, id, impl);
}

<*
  Get a hash function implementation (by ID).

  param ctx   SSL engine context.
  param id    hash function identifier.
  returns the hash function implementation.
*>
fn HashClass* ssl_engine_get_hash(SSLEngineContext* ctx, int id) @inline
{
    return multihash_getimpl(&ctx.mhash, id);
}

<*
  Set the PRF implementation (for TLS 1.0 and 1.1).

  param cc     SSL engine context.
  param impl   PRF implementation.
*>
fn void ssl_engine_set_prf10(SSLEngineContext* cc, TLSPrfImpl impl) @inline
{
    cc.prf10 = impl;
}

<*
  Set the PRF implementation with SHA-256 (for TLS 1.2).

  param cc     SSL engine context.
  param impl   PRF implementation.
*>
fn void ssl_engine_set_prf_sha256(SSLEngineContext* cc, TLSPrfImpl impl) @inline
{
    cc.prf_sha256 = impl;
}

<*
  Set the PRF implementation with SHA-384 (for TLS 1.2).

  param cc     SSL engine context.
  param impl   PRF implementation.
*>
fn void ssl_engine_set_prf_sha384(SSLEngineContext* cc, TLSPrfImpl impl) @inline
{
    cc.prf_sha384 = impl;
}

<*
  Set the AES/CBC implementations.

  param cc         SSL engine context.
  param ibc_enc    AES/CBC encryption implementation.
  param ibc_dec    AES/CBC decryption implementation.
*>
fn void ssl_engine_set_aes_cbc(SSLEngineContext* cc, BlockCBCEncClass* ibc_enc, BlockCBCDecClass* ibc_dec) @inline
{
    cc.iaes_cbcenc = ibc_enc;
    cc.iaes_cbcdec = ibc_dec;
}

<*
  Set the AES/CTR implementation.

  param cc       SSL engine context.
  param ictr     AES/CTR implementation.
*>
fn void ssl_engine_set_aes_ctr(SSLEngineContext* cc, BlockCTRClass* ictr) @inline
{
    cc.iaes_ctr = ictr;
}

<*
  Set the AES/CTR+CBC-MAC implementation.

  param cc         SSL engine context.
  param ictrcbc    AES/CTR+CBC-MAC implementation.
*>
fn void ssl_engine_set_aes_ctrcbc(SSLEngineContext* cc, BlockCTRCBCClass* ictrcbc) @inline
{
    cc.iaes_ctrcbc = ictrcbc;
}

<*
  Set the DES/CBC implementations.

  param cc         SSL engine context.
  param ibc_enc    DES/CBC encryption implementation.
  param ibc_dec    DES/CBC decryption implementation.
*>
fn void ssl_engine_set_des_cbc(SSLEngineContext* cc, BlockCBCEncClass* ibc_enc, BlockCBCDecClass* ibc_dec) @inline
{
    cc.ides_cbcenc = ibc_enc;
    cc.ides_cbcdec = ibc_dec;
}

<*
  Set the GHASH implementation.

  param cc      SSL engine context.
  param impl    GHASH implementation.
*>
fn void ssl_engine_set_ghash(SSLEngineContext* cc, GHashFn impl) @inline
{
    cc.ighash = impl;
}

<*
  Set the ChaCha20 implementation.

  param cc      SSL engine context.
  param impl    ChaCha20 implementation.
*>
fn void ssl_engine_set_chacha20(SSLEngineContext* cc, ChaCha20Run impl) @inline
{
    cc.ichacha = impl;
}

<*
  Set the Poly1305 implementation.

  param cc      SSL engine context.
  param impl    Poly1305 implementation.
*>
fn void ssl_engine_set_poly1305(SSLEngineContext* cc, Poly1305Run impl) @inline
{
    cc.ipoly = impl;
}

<*
  Set the CBC record layer implementations.

  param cc       SSL engine context.
  param in_impl  incoming CBC record implementation.
  param out_impl outgoing CBC record implementation.
*>
fn void ssl_engine_set_cbc(SSLEngineContext* cc, SSLRecInCBCClass* in_impl, SSLRecOutCBCClass* out_impl) @inline
{
    cc.icbc_in = in_impl;
    cc.icbc_out = out_impl;
}

<*
  Set the GCM record layer implementations.

  param cc       SSL engine context.
  param in_impl  incoming GCM record implementation.
  param out_impl outgoing GCM record implementation.
*>
fn void ssl_engine_set_gcm(SSLEngineContext* cc, SSLRecInGCMClass* in_impl, SSLRecOutGCMClass* out_impl) @inline
{
    cc.igcm_in = in_impl;
    cc.igcm_out = out_impl;
}

<*
  Set the ChaCha20+Poly1305 record layer implementations.

  param cc       SSL engine context.
  param in_impl  incoming ChaCha20+Poly1305 record implementation.
  param out_impl outgoing ChaCha20+Poly1305 record implementation.
*>
fn void ssl_engine_set_chapol(SSLEngineContext* cc, SSLRecInChaPolClass* in_impl, SSLRecOutChaPolClass* out_impl) @inline
{
    cc.ichapol_in = in_impl;
    cc.ichapol_out = out_impl;
}

<*
  Set the CCM record layer implementations.

  param cc       SSL engine context.
  param in_impl  incoming CCM record implementation.
  param out_impl outgoing CCM record implementation.
*>
fn void ssl_engine_set_ccm(SSLEngineContext* cc, SSLRecInCCMClass* in_impl, SSLRecOutCCMClass* out_impl) @inline
{
    cc.iccm_in = in_impl;
    cc.iccm_out = out_impl;
}

<*
  Set the elliptic curve implementation.

  param cc      SSL engine context.
  param impl    elliptic curve implementation.
*>
fn void ssl_engine_set_ec(SSLEngineContext* cc, ECImpl* impl) @inline
{
    cc.iec = impl;
}

<*
  Set the RSA signature verification implementation.

  param cc      SSL engine context.
  param impl    RSA signature verification implementation.
*>
fn void ssl_engine_set_rsavrfy(SSLEngineContext* cc, RSAPKCS1Vrfy impl) @inline
{
    cc.irsavrfy = impl;
}

<*
  Set the ECDSA signature verification implementation.

  param cc      SSL engine context.
  param impl    ECDSA signature verification implementation.
*>
fn void ssl_engine_set_ecdsa(SSLEngineContext* cc, ECDSAVrfy impl) @inline
{
    cc.iecdsa = impl;
}

/*
<*
  Set all "default" cryptographic implementations.

  This function configures all implementation slots in the engine with
  the library-provided default routines.

  param cc   SSL engine context.
*>
//extern fn void ssl_engine_set_default_cryptos(SSLEngineContext* cc);
*/

<*
  Set the buffer for a mono/bidirectional engine.

  The provided buffer is used as a single I/O area, shared by input and
  output processing.

  param cc      SSL engine context.
  param buf     buffer.
  param buf_len buffer length (in bytes).
*>
extern fn void ssl_engine_set_buffer(SSLEngineContext* cc, void* buf, sz buf_len, int bidi);

<*
  Set the buffer for a bidirectional engine.

  The provided buffer is split into two areas, one for input and one for
  output.

  param cc      SSL engine context.
  param buf     buffer.
  param buf_len buffer length (in bytes).
*>
extern fn void ssl_engine_set_buffers_bidi(SSLEngineContext* cc, void* ibuf, sz ibuf_len, void* obuf, sz obuf_len);

/*
<*
  Set the buffer for a monodirectional engine.

  The provided buffer is used as a single I/O area.

  param cc      SSL engine context.
  param buf     buffer.
  param buf_len buffer length (in bytes).
*>
//fn void ssl_engine_set_buffer_mono(SSLEngineContext* cc, void* buf, sz buf_len) @inline
//{
//    ssl_engine_set_buffer(cc, buf, buf_len, 0);
//}
*/

<*
  Get the current engine state.

  The returned value is a combination of status flags.
*>
extern fn uint ssl_engine_current_state(SSLEngineContext* cc);

<*
  Engine state: the engine is closed.
*>
const SSL_CLOSED = 0x0001;

<*
  Engine state: some bytes can be sent to the transport.
*>
const SSL_SENDREC = 0x0002;

<*
  Engine state: some application data can be read.
*>
const SSL_RECVAPP = 0x0010;

<*
  Engine state: some application data can be written.
*>
const SSL_SENDAPP = 0x0008;

<*
  Engine state: some bytes can be read from the transport.
*>
const SSL_RECVREC = 0x0004;

/*
<*
  Engine state: closing in progress.
*>
//const SSL_CLOSING = 0x0020;

<*
  Engine state: engine failed.
*>
//const SSL_FAILED = 0x0040;

<*
  Engine state: engine is in application data mode.
*>
//const SSL_APPDATA = 0x0080;
*/

<*
  Get the engine error status.

  param cc   SSL engine context.
  returns error code.
*>
fn int ssl_engine_last_error(SSLEngineContext* cc) @inline
{
    return cc.err;
}

<*
  Get the transport-layer receive buffer.

  The returned pointer designates the data area from which bytes should
  be read and passed to the transport layer. The available length is
  written into `*len`.

  param cc    SSL engine context.
  param len   receives the available length.
  returns buffer pointer.
*>
extern fn char* ssl_engine_sendrec_buf(SSLEngineContext* cc, sz* len);

<*
  Acknowledge bytes sent to the transport layer.

  param cc    SSL engine context.
  param len   number of bytes sent.
*>
extern fn void ssl_engine_sendrec_ack(SSLEngineContext* cc, sz len);

<*
  Get the transport-layer input buffer.

  The returned pointer designates the buffer into which bytes received
  from the transport shall be written. The available length is written
  into `*len`.

  param cc    SSL engine context.
  param len   receives the available length.
  returns buffer pointer.
*>
extern fn char* ssl_engine_recvrec_buf(SSLEngineContext* cc, sz* len);

<*
  Acknowledge bytes received from the transport layer.

  param cc    SSL engine context.
  param len   number of bytes received.
*>
extern fn void ssl_engine_recvrec_ack(SSLEngineContext* cc, sz len);

<*
  Get the application-data receive buffer.

  The returned pointer designates plaintext bytes ready to be consumed
  by the caller. The available length is written into `*len`.

  param cc    SSL engine context.
  param len   receives the available length.
  returns buffer pointer.
*>
extern fn char* ssl_engine_recvapp_buf(SSLEngineContext* cc, sz* len);

<*
  Acknowledge consumed application-data bytes.

  param cc    SSL engine context.
  param len   number of consumed bytes.
*>
extern fn void ssl_engine_recvapp_ack(SSLEngineContext* cc, sz len);

<*
  Get the application-data output buffer.

  The returned pointer designates plaintext bytes to be filled by the
  caller. The available length is written into `*len`.

  param cc    SSL engine context.
  param len   receives the available length.
  returns buffer pointer.
*>
extern fn char* ssl_engine_sendapp_buf(SSLEngineContext* cc, sz* len);

<*
  Acknowledge produced application-data bytes.

  param cc    SSL engine context.
  param len   number of produced bytes.
*>
extern fn void ssl_engine_sendapp_ack(SSLEngineContext* cc, sz len);

<*
  Flush buffered application data.

  This asks the engine to package buffered plaintext into records.

  param cc   SSL engine context.
*>
extern fn void ssl_engine_flush(SSLEngineContext* cc, int force);

<*
  Close the SSL stream.

  This function starts closure by emitting a `close_notify` alert if
  appropriate.

  param cc   SSL engine context.
*>
extern fn void ssl_engine_close(SSLEngineContext* cc);

<*
  Renegotiate the SSL connection.

  param cc   SSL engine context.
*>
extern fn int ssl_engine_renegotiate(SSLEngineContext* cc);

<*
  Get the negotiated protocol version.

  Returned value is 0 until the version is known.

  param cc   SSL engine context.
  returns protocol version.
*>
fn uint ssl_engine_get_version(SSLEngineContext* cc) @inline
{
    return cc.session.version;
}

<*
  Get the negotiated cipher suite.

  Returned value is 0 until the cipher suite is known.

  param cc   SSL engine context.
  returns cipher suite.
*>
fn uint ssl_engine_get_cipher_suite(SSLEngineContext* cc) @inline
{
    return cc.session.cipher_suite;
}

<*
  Copy session parameters.

  param cc   SSL engine context.
  param dst  destination structure.
*>
fn void ssl_engine_get_session_parameters(SSLEngineContext* cc, SSLSessionParameters* dst) @inline
{
    *dst = cc.session;
}

<*
  Set session parameters.

  This is used for session resumption.

  param cc   SSL engine context.
  param src  source structure.
*>
fn void ssl_engine_set_session_parameters(SSLEngineContext* cc, SSLSessionParameters* src) @inline
{
    cc.session = *src;
}

<*
  Get the server name.

  For a client context, this is the SNI name to send. For a server
  context, this is the name received from the peer, if any.

  param cc   SSL engine context.
  returns server name, or `null`.
*>
fn char* ssl_engine_get_server_name(SSLEngineContext* cc) @inline
{
    return cc.server_name;
}

<*
  Read callback.
*>
alias SSLIOReadFn = fn int(void* ctx, char* data, sz len);

<*
  Write callback.
*>
alias SSLIOWriteFn = fn int(void* ctx, char* data, sz len);



<*
  Simplified I/O context.

  This helper binds an SSL engine to a pair of callbacks for transport I/O.
*>
struct SSLIOContext {
    <*
      SSL engine context.
    *>
    SSLEngineContext* engine;


    SSLIOReadFn low_read;
    void* read_context;

    SSLIOWriteFn low_write;
    void* write_context;
}

<*
  Initialise a simplified I/O context.

  param cc         I/O context.
  param engine     SSL engine context.
  param low_read   transport read callback.
  param read_ctx   read callback context.
  param low_write  transport write callback.
  param write_ctx  write callback context.
*>
extern fn void sslio_init(SSLIOContext* cc, SSLEngineContext* engine, SSLIOReadFn low_read, void* read_ctx, SSLIOWriteFn low_write, void* write_ctx);

<*
  Read application data.

  param cc    I/O context.
  param dst   destination buffer.
  param len   maximum number of bytes.
  returns number of bytes read, or -1 on error.
*>
extern fn int sslio_read(SSLIOContext* cc, void* dst, sz len);

<*
  Write application data.

  param cc    I/O context.
  param src   source buffer.
  param len   number of bytes to write.
  returns number of bytes written, or -1 on error.
*>
extern fn int sslio_write(SSLIOContext* cc, void* src, sz len);

<*
  Flush pending outgoing data.

  param cc    I/O context.
  returns 0 on success, -1 on error.
*>
extern fn int sslio_flush(SSLIOContext* cc);

<*
  Close the SSL stream and underlying transport cleanly.

  param cc    I/O context.
  returns 0 on success, -1 on error.
*>
extern fn int sslio_close(SSLIOContext* cc);

<*
  Get the last SSL error from a simplified I/O context.

  param cc   I/O context.
  returns error code.
*>
fn int sslio_last_error(SSLIOContext* cc) @inline
{
    return ssl_engine_last_error(cc.engine);
}

struct SSLClientCertificate {
    int auth_type;
    int hash_id;
    X509Certificate* chain;
    sz chain_len;
}

<*
  Begin reception of a list of trust anchor names.

  This is called while parsing the incoming CertificateRequest.

  param pctx   certificate handler context.
*>
alias StartNameListFn = fn void(SSLClientCertificateClass** pctx);

<*
  Begin reception of a new trust anchor name.

  The total encoded name length is provided; it is less than
  65535 bytes.

  param pctx   certificate handler context.
  param len    encoded name length (in bytes).
*>
alias StartNameFn = fn void(SSLClientCertificateClass** pctx, sz len);

<*
  Receive some more bytes for the current trust anchor name.

  The provided reference (`data`) points to a transient buffer;
  it may be reused as soon as this function returns. The chunk
  length (`len`) is never zero.

  param pctx   certificate handler context.
  param data   anchor name chunk.
  param len    anchor name chunk length (in bytes).
*>
alias AppendNameFn = fn void(SSLClientCertificateClass** pctx, char* data, sz len);

<*
  End current trust anchor name.

  This function is called when all the encoded anchor name data
  has been provided.

  param pctx   certificate handler context.
*>
alias EndNameFn = fn void(SSLClientCertificateClass** pctx);

<*
  End list of trust anchor names.

  This function is called when all the anchor names in the
  CertificateRequest message have been obtained.

  param pctx   certificate handler context.
*>
alias EndNameListFn = fn void(SSLClientCertificateClass** pctx);

<*
  Select client certificate and algorithms.

  This callback function shall fill the provided `choices`
  structure with the selected algorithms and certificate chain.
  The `hash_id`, `chain` and `chain_len` fields must be set. If
  the client cannot or does not wish to send a certificate,
  then it shall set `chain` to `null` and `chain_len` to 0.

  The `auth_types` parameter describes the authentication types,
  signature algorithms and hash functions that are supported by
  both the client context and the server, and compatible with
  the current protocol version.

  param pctx         certificate handler context.
  param cc           SSL client context.
  param auth_types   supported authentication types and algorithms.
  param choices      destination structure for the policy choices.
*>
alias ChooseFn1 = fn void(SSLClientCertificateClass** pctx, SSLClientContext* cc, uint auth_types, SSLClientCertificate* choices);

<*
  Perform key exchange (client part).

  This callback is invoked in case of a full static ECDH key
  exchange.

  Returned value is 1 on success, 0 on error.

  param pctx   certificate handler context.
  param data   server public key point.
  param len    public key point length / X coordinate length.
  returns 1 on success, 0 on error.
*>
alias DoKeyxFn1 = fn uint(SSLClientCertificateClass** pctx, char* data, sz* len);

<*
  Perform a signature (client authentication).

  This callback is invoked when a client certificate was sent,
  and static ECDH is not used.

  Returned value is the signature length (in bytes), or 0 on error.

  param pctx      certificate handler context.
  param hash_id   hash function identifier.
  param hv_len    hash value length (in bytes).
  param data      input/output buffer (hash value, then signature).
  param len       total buffer length (in bytes).
  returns signature length (in bytes) on success, or 0 on error.
*>
alias DoSignFn1 = fn sz(SSLClientCertificateClass** pctx, int hash_id, sz hv_len, char* data, sz len);




<*
  Client certificate authentication handler.

  The SSL client engine will call these methods when the server requests
  a client certificate. It will first obtain the list of trust anchor
  names, then call `choose()` to select certificate parameters, and
  finally call either `do_sign()` or `do_keyx()` depending on the chosen
  algorithm.
*>
struct SSLClientCertificateClass {
    <*
      Context size (in bytes).
    *>
    sz context_size;

    StartNameListFn start_name_list;
    StartNameFn start_name;
    AppendNameFn append_name;
    EndNameFn end_name;
    EndNameListFn end_name_list;
    ChooseFn1 choose;
    DoKeyxFn1 do_keyx;
    DoSignFn1 do_sign;
}

//
// Symbolic constants for cipher suites.
//

// From RFC 5246
const TLS_NULL_WITH_NULL_NULL = 0x0000;
const TLS_RSA_WITH_NULL_MD5 = 0x0001;
const TLS_RSA_WITH_NULL_SHA = 0x0002;
const TLS_RSA_WITH_NULL_SHA256 = 0x003B;
const TLS_RSA_WITH_RC4_128_MD5 = 0x0004;
const TLS_RSA_WITH_RC4_128_SHA = 0x0005;
const TLS_RSA_WITH_3DES_EDE_CBC_SHA = 0x000A;
const TLS_RSA_WITH_AES_128_CBC_SHA = 0x002F;
const TLS_RSA_WITH_AES_256_CBC_SHA = 0x0035;
const TLS_RSA_WITH_AES_128_CBC_SHA256 = 0x003C;
const TLS_RSA_WITH_AES_256_CBC_SHA256 = 0x003D;
const TLS_DH_DSS_WITH_3DES_EDE_CBC_SHA = 0x000D;
const TLS_DH_RSA_WITH_3DES_EDE_CBC_SHA = 0x0010;
const TLS_DHE_DSS_WITH_3DES_EDE_CBC_SHA = 0x0013;
const TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA = 0x0016;
const TLS_DH_DSS_WITH_AES_128_CBC_SHA = 0x0030;
const TLS_DH_RSA_WITH_AES_128_CBC_SHA = 0x0031;
const TLS_DHE_DSS_WITH_AES_128_CBC_SHA = 0x0032;
const TLS_DHE_RSA_WITH_AES_128_CBC_SHA = 0x0033;
const TLS_DH_DSS_WITH_AES_256_CBC_SHA = 0x0036;
const TLS_DH_RSA_WITH_AES_256_CBC_SHA = 0x0037;
const TLS_DHE_DSS_WITH_AES_256_CBC_SHA = 0x0038;
const TLS_DHE_RSA_WITH_AES_256_CBC_SHA = 0x0039;
const TLS_DH_DSS_WITH_AES_128_CBC_SHA256 = 0x003E;
const TLS_DH_RSA_WITH_AES_128_CBC_SHA256 = 0x003F;
const TLS_DHE_DSS_WITH_AES_128_CBC_SHA256 = 0x0040;
const TLS_DHE_RSA_WITH_AES_128_CBC_SHA256 = 0x0067;
const TLS_DH_DSS_WITH_AES_256_CBC_SHA256 = 0x0068;
const TLS_DH_RSA_WITH_AES_256_CBC_SHA256 = 0x0069;
const TLS_DHE_DSS_WITH_AES_256_CBC_SHA256 = 0x006A;
const TLS_DHE_RSA_WITH_AES_256_CBC_SHA256 = 0x006B;
const TLS_DH_ANON_WITH_RC4_128_MD5 = 0x0018;
const TLS_DH_ANON_WITH_3DES_EDE_CBC_SHA = 0x001B;
const TLS_DH_ANON_WITH_AES_128_CBC_SHA = 0x0034;
const TLS_DH_ANON_WITH_AES_256_CBC_SHA = 0x003A;
const TLS_DH_ANON_WITH_AES_128_CBC_SHA256 = 0x006C;
const TLS_DH_ANON_WITH_AES_256_CBC_SHA256 = 0x006D;

// From RFC 4492
const TLS_ECDH_ECDSA_WITH_NULL_SHA = 0xC001;
const TLS_ECDH_ECDSA_WITH_RC4_128_SHA = 0xC002;
const TLS_ECDH_ECDSA_WITH_3DES_EDE_CBC_SHA = 0xC003;
const TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA = 0xC004;
const TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA = 0xC005;
const TLS_ECDHE_ECDSA_WITH_NULL_SHA = 0xC006;
const TLS_ECDHE_ECDSA_WITH_RC4_128_SHA = 0xC007;
const TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA = 0xC008;
const TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA = 0xC009;
const TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA = 0xC00A;
const TLS_ECDH_RSA_WITH_NULL_SHA = 0xC00B;
const TLS_ECDH_RSA_WITH_RC4_128_SHA = 0xC00C;
const TLS_ECDH_RSA_WITH_3DES_EDE_CBC_SHA = 0xC00D;
const TLS_ECDH_RSA_WITH_AES_128_CBC_SHA = 0xC00E;
const TLS_ECDH_RSA_WITH_AES_256_CBC_SHA = 0xC00F;
const TLS_ECDHE_RSA_WITH_NULL_SHA = 0xC010;
const TLS_ECDHE_RSA_WITH_RC4_128_SHA = 0xC011;
const TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA = 0xC012;
const TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA = 0xC013;
const TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA = 0xC014;
const TLS_ECDH_ANON_WITH_NULL_SHA = 0xC015;
const TLS_ECDH_ANON_WITH_RC4_128_SHA = 0xC016;
const TLS_ECDH_ANON_WITH_3DES_EDE_CBC_SHA = 0xC017;
const TLS_ECDH_ANON_WITH_AES_128_CBC_SHA = 0xC018;
const TLS_ECDH_ANON_WITH_AES_256_CBC_SHA = 0xC019;

// From RFC 5288
const TLS_RSA_WITH_AES_128_GCM_SHA256 = 0x009C;
const TLS_RSA_WITH_AES_256_GCM_SHA384 = 0x009D;
const TLS_DHE_RSA_WITH_AES_128_GCM_SHA256 = 0x009E;
const TLS_DHE_RSA_WITH_AES_256_GCM_SHA384 = 0x009F;
const TLS_DH_RSA_WITH_AES_128_GCM_SHA256 = 0x00A0;
const TLS_DH_RSA_WITH_AES_256_GCM_SHA384 = 0x00A1;
const TLS_DHE_DSS_WITH_AES_128_GCM_SHA256 = 0x00A2;
const TLS_DHE_DSS_WITH_AES_256_GCM_SHA384 = 0x00A3;
const TLS_DH_DSS_WITH_AES_128_GCM_SHA256 = 0x00A4;
const TLS_DH_DSS_WITH_AES_256_GCM_SHA384 = 0x00A5;
const TLS_DH_ANON_WITH_AES_128_GCM_SHA256 = 0x00A6;
const TLS_DH_ANON_WITH_AES_256_GCM_SHA384 = 0x00A7;

// From RFC 5289
const TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 = 0xC023;
const TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 = 0xC024;
const TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256 = 0xC025;
const TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384 = 0xC026;
const TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256 = 0xC027;
const TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384 = 0xC028;
const TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256 = 0xC029;
const TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384 = 0xC02A;
const TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 = 0xC02B;
const TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 = 0xC02C;
const TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256 = 0xC02D;
const TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384 = 0xC02E;
const TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 = 0xC02F;
const TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 = 0xC030;
const TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256 = 0xC031;
const TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384 = 0xC032;

// From RFC 6655 and 7251
const TLS_RSA_WITH_AES_128_CCM = 0xC09C;
const TLS_RSA_WITH_AES_256_CCM = 0xC09D;
const TLS_RSA_WITH_AES_128_CCM_8 = 0xC0A0;
const TLS_RSA_WITH_AES_256_CCM_8 = 0xC0A1;
const TLS_ECDHE_ECDSA_WITH_AES_128_CCM = 0xC0AC;
const TLS_ECDHE_ECDSA_WITH_AES_256_CCM = 0xC0AD;
const TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8 = 0xC0AE;
const TLS_ECDHE_ECDSA_WITH_AES_256_CCM_8 = 0xC0AF;

// From RFC 7905
const TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 = 0xCCA8;
const TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 = 0xCCA9;
const TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256 = 0xCCAA;
const TLS_PSK_WITH_CHACHA20_POLY1305_SHA256 = 0xCCAB;
const TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256 = 0xCCAC;
const TLS_DHE_PSK_WITH_CHACHA20_POLY1305_SHA256 = 0xCCAD;
const TLS_RSA_PSK_WITH_CHACHA20_POLY1305_SHA256 = 0xCCAE;

// From RFC 7507
const TLS_FALLBACK_SCSV = 0x5600;

//
// Symbolic constants for alerts.
//
const ALERT_CLOSE_NOTIFY = 0;
const ALERT_UNEXPECTED_MESSAGE = 10;
const ALERT_BAD_RECORD_MAC = 20;
const ALERT_RECORD_OVERFLOW = 22;
const ALERT_DECOMPRESSION_FAILURE = 30;
const ALERT_HANDSHAKE_FAILURE = 40;
const ALERT_BAD_CERTIFICATE = 42;
const ALERT_UNSUPPORTED_CERTIFICATE = 43;
const ALERT_CERTIFICATE_REVOKED = 44;
const ALERT_CERTIFICATE_EXPIRED = 45;
const ALERT_CERTIFICATE_UNKNOWN = 46;
const ALERT_ILLEGAL_PARAMETER = 47;
const ALERT_UNKNOWN_CA = 48;
const ALERT_ACCESS_DENIED = 49;
const ALERT_DECODE_ERROR = 50;
const ALERT_DECRYPT_ERROR = 51;
const ALERT_PROTOCOL_VERSION = 70;
const ALERT_INSUFFICIENT_SECURITY = 71;
const ALERT_INTERNAL_ERROR = 80;
const ALERT_USER_CANCELED = 90;
const ALERT_NO_RENEGOTIATION = 100;
const ALERT_UNSUPPORTED_EXTENSION = 110;
const ALERT_NO_APPLICATION_PROTOCOL = 120;

<*
  Type for a "translated cipher suite", as an array of two
  16-bit integers.

  The first element is the cipher suite identifier (as used on the wire).
  The second element is the concatenation of four 4-bit elements which
  characterise the cipher suite contents.
*>
alias SuiteTranslated = ushort[2];

const SSLKEYX_RSA = 0;
const SSLKEYX_ECDHE_RSA = 1;
const SSLKEYX_ECDHE_ECDSA = 2;
const SSLKEYX_ECDH_RSA = 3;
const SSLKEYX_ECDH_ECDSA = 4;

const SSLENC_3DES_CBC = 0;
const SSLENC_AES128_CBC = 1;
const SSLENC_AES256_CBC = 2;
const SSLENC_AES128_GCM = 3;
const SSLENC_AES256_GCM = 4;
const SSLENC_CHACHA20 = 5;

const SSLMAC_AEAD = 0;
const SSLMAC_SHA1 = SHA1_ID;
const SSLMAC_SHA256 = SHA256_ID;
const SSLMAC_SHA384 = SHA384_ID;

const SSLPRF_SHA256 = SHA256_ID;
const SSLPRF_SHA384 = SHA384_ID;


<*
  Type for the server policy choices, taken after analysis of
  the client message (ClientHello).
*>
struct SSLServerChoices {
    <*
      Cipher suite to use with that client.
    *>
    ushort cipher_suite;

    <*
      Hash function or algorithm for signing the ServerKeyExchange.

      This parameter is ignored for `TLS_RSA_*` and `TLS_ECDH_*`
      cipher suites; it is used only for `TLS_ECDHE_*` suites, in
      which the server signs the ephemeral EC Diffie-Hellman
      parameters sent to the client.
    *>
    uint algo_id;

    <*
      Certificate chain to send to the client.

      This is an array of `X509Certificate` objects, each
      normally containing a DER-encoded certificate. The server
      code does not try to decode these elements.
    *>
    X509Certificate* chain;

    <*
      Certificate chain length (number of certificates).
    *>
    sz chain_len;
}


<*
  Select algorithms and certificates for this connection.

  param pctx      policy context.
  param cc        SSL server context.
  param choices   destination structure for the policy choices.
  returns 1 on success, 0 on error.
*>
alias ChooseFn2 = fn int(SSLServerPolicyClass** pctx, SSLServerContext* cc, SSLServerChoices* choices);

<*
  Perform key exchange (server part).

  param pctx   policy context.
  param data   key exchange data from the client.
  param len    key exchange data length (in bytes).
  returns 1 on success, 0 on error.
*>
alias DoKeyxFn2 = fn uint(SSLServerPolicyClass** pctx, char* data, sz* len);

<*
  Perform a signature (for a ServerKeyExchange message).

  param pctx      policy context.
  param algo_id   hash function / algorithm identifier.
  param data      input/output buffer (message/hash, then signature).
  param hv_len    hash value or message length (in bytes).
  param len       total buffer length (in bytes).
  returns signature length (in bytes), or 0 on error.
*>
alias DoSignFn2 = fn sz(SSLServerPolicyClass** pctx, uint algo_id, char* data, sz hv_len, sz len);



<*
  Class type for a policy handler (server side).

  A policy handler selects the policy parameters for a connection
  (cipher suite and other algorithms, and certificate chain to send to
  the client); it also performs the server-side computations involving
  its permanent private key.

  The SSL server engine will invoke first `choose()`, once the
  ClientHello message has been received, then either `do_keyx()`
  or `do_sign()`, depending on the cipher suite.
*>
struct SSLServerPolicyClass {
    <*
      Context size (in bytes).
    *>
    sz context_size;


    ChooseFn2 choose;
    DoKeyxFn2 do_keyx;
    DoSignFn2 do_sign;
}

<*
  A single-chain RSA policy handler.

  This policy context uses a single certificate chain, and a RSA
  private key. The context can be restricted to only signatures or
  only key exchange.

  Apart from the first field (vtable pointer), its contents are
  opaque and shall not be accessed directly.
*>
struct SSLServerPolicyRSAContext {
    <*
      Pointer to vtable.
    *>
    SSLServerPolicyClass* vtable;

    X509Certificate* chain;
    sz chain_len;
    RSAPrivateKey* sk;
    uint allowed_usages;
    RSAPrivate irsacore;
    RSAPKCS1Sign irsasign;
}

<*
  A single-chain EC policy handler.

  This policy context uses a single certificate chain, and an EC
  private key. The context can be restricted to only signatures or
  only key exchange.

  Due to how TLS is defined, this context must be made aware whether
  the server certificate was itself signed with RSA or ECDSA. The code
  does not try to decode the certificate to obtain that information.

  Apart from the first field (vtable pointer), its contents are
  opaque and shall not be accessed directly.
*>
struct SSLServerPolicyECContext {
    <*
      Pointer to vtable.
    *>
    SSLServerPolicyClass* vtable;

    X509Certificate* chain;
    sz chain_len;
    ECPrivateKey* sk;
    uint allowed_usages;
    uint cert_issuer_key_type;
    MultiHashContext* mhash;
    ECImpl* iec;
    ECDSASign iecdsa;
}

<*
  Record a session.

  param ctx          session cache context.
  param server_ctx   SSL server context.
  param params       session parameters to save.
*>
alias SaveFn = fn void(SSLSessionCacheClass** ctx, SSLServerContext* server_ctx, SSLSessionParameters* params);

<*
  Lookup a session in the cache.

  param ctx          session cache context.
  param server_ctx   SSL server context.
  param params       destination for session parameters.
  returns 1 if found, 0 otherwise.
*>
alias LoadFn = fn int(SSLSessionCacheClass** ctx, SSLServerContext* server_ctx, SSLSessionParameters* params);



<*
  Class type for a session parameter cache.

  Session parameters are saved in the cache with `save()`, and
  retrieved with `load()`. The cache implementation can apply any
  storage and eviction strategy that it sees fit. The SSL server
  context that performs the request is provided, so that its
  functionalities may be used by the implementation.
*>
struct SSLSessionCacheClass {
    <*
      Context size (in bytes).
    *>
    sz context_size;


    SaveFn save;
    LoadFn load;
}

<*
  Context for a basic cache system.

  The system stores session parameters in a buffer provided at
  initialisation time. Each entry uses exactly 100 bytes, and
  buffer sizes up to 4294967295 bytes are supported.

  Entries are evicted with a LRU (Least Recently Used) policy. A
  search tree is maintained to keep lookups fast even with large
  caches.

  Apart from the first field (vtable pointer), the structure
  contents are opaque and shall not be accessed directly.
*>
struct SSLSessionCacheLRU {
    <*
      Pointer to vtable.
    *>
    SSLSessionCacheClass* vtable;

    char* store;
    sz store_len;
    sz store_ptr;
    char[32] index_key;
    HashClass* hash;
    int init_done;
    uint head;
    uint tail;
    uint root;
}

<*
  Initialise a LRU session cache with the provided storage space.

  The provided storage space must remain valid as long as the cache
  is used. Arbitrary lengths are supported, up to 4294967295 bytes;
  each entry uses up exactly 100 bytes.

  param cc          session cache context.
  param store       storage space for cached entries.
  param store_len   storage space length (in bytes).
*>
extern fn void ssl_session_cache_lru_init(SSLSessionCacheLRU* cc, char* store, sz store_len);

<*
  Forget an entry in an LRU session cache.

  The session cache context must have been initialised. The entry
  with the provided session ID (of exactly 32 bytes) is looked for
  in the cache; if located, it is disabled.

  param cc   session cache context.
  param id   session ID to forget.
*>
extern fn void ssl_session_cache_lru_forget(SSLSessionCacheLRU* cc, char* id);

<*
  Context structure for a SSL server.

  The first field (called `eng`) is the SSL engine; all functions that
  work on a `SSLEngineContext` structure shall take as parameter
  a pointer to that field. The other structure fields are opaque and
  must not be accessed directly.
*>
struct SSLServerContext {
    <*
      The encapsulated engine context.
    *>
    SSLEngineContext eng;

    ushort client_max_version;

    <*
      Session cache.
    *>
    SSLSessionCacheClass** cache_vtable;

    <*
      Translated cipher suites supported by the client.
    *>
    SuiteTranslated[MAX_CIPHER_SUITES] client_suites;
    char client_suites_num;

    <*
      Hash functions supported by the client.
    *>
    uint hashes;

    <*
      Curves supported by the client.
    *>
    uint curves;

    <*
      Context for chain handler.
    *>
    SSLServerPolicyClass** policy_vtable;
    ushort sign_hash_id;

    union chain_handler {
        SSLServerPolicyClass* vtable;
        SSLServerPolicyRSAContext single_rsa;
        SSLServerPolicyECContext single_ec;
    }

    char[70] ecdhe_key;
    sz ecdhe_key_len;

    <*
      Trust anchor names for client authentication.
    *>
    X500Name* ta_names;
    X509TrustAnchor* tas;
    sz num_tas;
    
    sz cur_dn_index;
    char* cur_dn;
    sz cur_dn_len;
    
    char[64] hash_cv;
    sz hash_cv_len;
    int hash_cv_id;
}

<*
  Get the maximum version supported by the client.

  param cc   server context.
  returns maximum version supported by the client.
*>
fn uint ssl_server_get_client_max_version(SSLServerContext* cc) @inline
{
    return cc.client_max_version;
}

<*
  Get the cipher suites supported by the client.

  Returned value is a pointer to the internally stored translated
  suite array. The number of elements is written into `*num`.

  param cc    server context.
  param num   destination for number of suites.
  returns translated cipher suite array.
*>
fn SuiteTranslated* ssl_server_get_client_suites(SSLServerContext* cc, sz* num) @inline
{
    *num = cc.client_suites_num;
    return &cc.client_suites[0];
}

<*
  Get the hash functions and signature algorithms supported by the client.

  param cc   server context.
  returns supported hashes / algorithms bit mask.
*>
fn uint ssl_server_get_client_hashes(SSLServerContext* cc) @inline
{
    return cc.hashes;
}

<*
  Get the elliptic curves supported by the client.

  param cc   server context.
  returns supported curves bit mask.
*>
fn uint ssl_server_get_client_curves(SSLServerContext* cc) @inline
{
    return cc.curves;
}

<*
  Set an externally provided server policy handler.

  param cc     server context.
  param pctx   policy handler context (pointer to vtable).
*>
fn void ssl_server_set_policy(SSLServerContext* cc, SSLServerPolicyClass** pctx) @inline
{
    cc.policy_vtable = pctx;
}

<*
  Set a single RSA server certificate and key.

  This function uses a policy context included in the server context.
  It configures use of a single server certificate chain with a RSA
  private key. The `allowed_usages` policy restriction is internal to
  the context configuration.

  param cc          server context.
  param chain       server certificate chain to send.
  param chain_len   chain length (number of certificates).
  param sk          server private key (RSA).
  param irsacore    RSA core implementation.
  param irsasign    RSA signature implementation.
*>
extern fn void ssl_server_set_single_rsa(SSLServerContext* cc, X509Certificate* chain, sz chain_len, RSAPrivateKey* sk, RSAPrivate irsacore, RSAPKCS1Sign irsasign);

<*
  Set a single EC server certificate and key.

  This function uses a policy context included in the server context.
  It configures use of a single server certificate chain with an EC
  private key. The `allowed_usages` is a combination of usages, namely
  `KEYTYPE_KEYX` and/or `KEYTYPE_SIGN`; this enables or disables
  the corresponding cipher suites.

  In order to support `TLS_ECDH_*` cipher suites (non-ephemeral ECDH),
  the algorithm type of the key used by the issuing CA to sign the
  server's certificate must be provided.

  param cc                     server context.
  param chain                  server certificate chain to send.
  param chain_len              chain length (number of certificates).
  param sk                     server private key (EC).
  param allowed_usages         allowed private key usages.
  param cert_issuer_key_type   issuing CA's key type.
  param iec                    EC core implementation.
  param iecdsa                 ECDSA signature implementation ("asn1" format).
*>
extern fn void ssl_server_set_single_ec(SSLServerContext* cc, X509Certificate* chain, sz chain_len, ECPrivateKey* sk, uint allowed_usages, uint cert_issuer_key_type, ECImpl* iec, ECDSASign iecdsa);

<*
  Activate client certificate authentication.

  The trust anchor encoded X.500 names (DN) to send to the client are
  provided. A client certificate will be requested and validated through
  the X.509 validator configured in the SSL engine. If `num` is 0, then
  client certificate authentication is disabled.

  param cc         server context.
  param ta_names   encoded trust anchor names.
  param num        number of encoded trust anchor names.
*>
fn void ssl_server_set_trust_anchor_names(SSLServerContext* cc, X500Name* ta_names, sz num) @inline
{
    cc.ta_names = ta_names;
    cc.tas = null;
    cc.num_tas = num;
}

<*
  Activate client certificate authentication.

  This is a variant for `ssl_server_set_trust_anchor_names()`: the
  trust anchor names are provided not as an array of stand-alone names
  (`X500Name` structures), but as an array of trust anchors
  (`X509TrustAnchor` structures). The server engine itself will
  only use the `dn` field of each trust anchor.

  param cc    server context.
  param tas   trust anchors (only names are used).
  param num   number of trust anchors.
*>
fn void ssl_server_set_trust_anchor_names_alt(SSLServerContext* cc, X509TrustAnchor* tas, sz num) @inline
{
    cc.ta_names = null;
    cc.tas = tas;
    cc.num_tas = num;
}

<*
  Configure the cache for session parameters.

  The cache context is provided as a pointer to its first field (vtable
  pointer).

  param cc       server context.
  param vtable   session cache context.
*>
fn void ssl_server_set_cache(SSLServerContext* cc, SSLSessionCacheClass** vtable) @inline
{
    cc.cache_vtable = vtable;
}

<*
  Prepare or reset a server context for handling an incoming client.

  param cc   server context.
  returns 1 on success, 0 on error.
*>
extern fn int ssl_server_reset(SSLServerContext* cc);

<*
  A single-chain RSA client certificate handler.

  This handler uses a single certificate chain, with a RSA
  signature. The list of trust anchor DN is ignored.
*>
struct SSLClientCertificateRSAContext {
    <*
      Pointer to vtable.
    *>
    SSLClientCertificateClass* vtable;

    X509Certificate* chain;
    sz chain_len;
    RSAPrivateKey* sk;
    RSAPKCS1Sign irsasign;
}

<*
  A single-chain EC client certificate handler.

  This handler uses a single certificate chain with an EC private key.
  The list of trust anchor DN is ignored.

  This handler may support both static ECDH, and ECDSA signatures
  (either usage may be selectively disabled).
*>
struct SSLClientCertificateECContext {
    <*
      Pointer to vtable.
    *>
    SSLClientCertificateClass* vtable;

    X509Certificate* chain;
    sz chain_len;
    ECPrivateKey* sk;
    uint allowed_usages;
    uint issuer_key_type;
    MultiHashContext* mhash;
    ECImpl* iec;
    ECDSASign iecdsa;
}

<*
  Context structure for a SSL client.

  The first field (called `eng`) is the SSL engine; all functions that
  work on a `SSLEngineContext` structure shall take as parameter
  a pointer to that field. The other structure fields are opaque and
  must not be accessed directly.
*>
struct SSLClientContext {
    <*
      The encapsulated engine context.
    *>
    SSLEngineContext eng;

    ushort min_clienthello_len;
    uint hashes;
    int server_curve;
    SSLClientCertificateClass** client_auth_vtable;
    char auth_type;
    char hash_id;

    union client_auth {
        SSLClientCertificateClass* vtable;
        SSLClientCertificateRSAContext single_rsa;
        SSLClientCertificateECContext single_ec;
    }

    RSAPublic irsapub;
}

<*
  Get the hash functions and signature algorithms supported by
  the server.

  param cc   client context.
  returns the server-supported hash functions and signature algorithms.
*>
fn uint ssl_client_get_server_hashes(SSLClientContext* cc) @inline
{
    return cc.hashes;
}

<*
  Get the server key curve.

  This function returns the ID for the curve used by the server's public
  key. This is set when the server's certificate chain is processed;
  this value is 0 if the server's key is not an EC key.

  param cc   client context.
  returns the server public key curve ID, or 0.
*>
fn int ssl_client_get_server_curve(SSLClientContext* cc) @inline
{
    return cc.server_curve;
}

<*
  SSL client profile: full.

  This function initialises the provided SSL client context with
  all supported algorithms and cipher suites. It also initialises
  a companion X.509 validation engine with all supported algorithms,
  and the provided trust anchors; the X.509 engine will be used by
  the client context to validate the server's certificate.

  param cc                  client context to initialise.
  param xc                  X.509 validation context to initialise.
  param trust_anchors       trust anchors to use.
  param trust_anchors_num   number of trust anchors.
*>
extern fn void ssl_client_init_full(SSLClientContext* cc, X509MinimalContext* xc, X509TrustAnchor* trust_anchors, sz trust_anchors_num);

<*
  Clear the complete contents of a SSL client context.

  Everything is cleared, including the reference to the configured buffer,
  implementations, cipher suites and state. This is a preparatory step
  to assembling a custom profile.

  param cc   client context to clear.
*>
extern fn void ssl_client_zero(SSLClientContext* cc);

<*
  Set an externally provided client certificate handler context.

  The handler's methods are invoked when the server requests a client
  certificate.

  param cc     client context.
  param pctx   certificate handler context (pointer to vtable).
*>
fn void ssl_client_set_client_certificate(SSLClientContext* cc, SSLClientCertificateClass** pctx) @inline
{
    cc.client_auth_vtable = pctx;
}

<*
  Set the RSA public-key operations implementation.

  This will be used to encrypt the pre-master secret with the server's
  RSA public key (RSA-encryption cipher suites only).

  param cc        client context.
  param irsapub   RSA public-key implementation.
*>
fn void ssl_client_set_rsapub(SSLClientContext* cc, RSAPublic irsapub) @inline
{
    cc.irsapub = irsapub;
}

<*
  Set the "default" RSA implementation for public-key operations.

  This sets the RSA implementation in the client context to the fastest
  one available on the current platform.

  param cc   client context.
*>
extern fn void ssl_client_set_default_rsapub(SSLClientContext* cc);

<*
  Set the minimum ClientHello length (RFC 7685 padding).

  param cc    client context.
  param len   minimum ClientHello length (in bytes).
*>
fn void ssl_client_set_min_clienthello_len(SSLClientContext* cc, ushort len) @inline
{
    cc.min_clienthello_len = len;
}

<*
  Prepare or reset a client context for a new connection.

  The `server_name` value is used for SNI if non-null. The
  `resume_session` flag indicates whether the current session parameters
  should be offered for resumption.

  param cc               client context.
  param server_name      target server name, or `null`.
  param resume_session   non-zero to try session resumption.
  returns 1 on success, 0 on error.
*>
extern fn int ssl_client_reset(SSLClientContext* cc, char* server_name, int resume_session);

<*
  Forget any saved session in the context.

  This means that the next handshake that uses this context will
  necessarily be a full handshake.

  param cc   client context.
*>
fn void ssl_client_forget_session(SSLClientContext* cc) @inline
{
    cc.eng.session.session_id_len = 0;
}

<*
  Set client certificate chain and key (single RSA case).

  param cc          client context.
  param chain       client certificate chain (EE first).
  param chain_len   chain length.
  param sk          client RSA private key.
  param irsasign    RSA signature implementation.
*>
extern fn void ssl_client_set_single_rsa(SSLClientContext* cc, X509Certificate* chain, sz chain_len, RSAPrivateKey* sk, RSAPKCS1Sign irsasign);

<*
  Set client certificate chain and key (single EC case).

  param cc                     client context.
  param chain                  client certificate chain (EE first).
  param chain_len              chain length.
  param sk                     client EC private key.
  param allowed_usages         allowed key usages.
  param cert_issuer_key_type   issuing CA key type.
  param iec                    EC core implementation.
  param iecdsa                 ECDSA signature implementation.
*>
extern fn void ssl_client_set_single_ec(SSLClientContext* cc, X509Certificate* chain, sz chain_len, ECPrivateKey* sk, uint allowed_usages, uint cert_issuer_key_type, ECImpl* iec, ECDSASign iecdsa);

<*
  Get the embedded engine context from a client context.

  param cc   client context.
  returns pointer to engine context.
*>
fn SSLEngineContext* ssl_client_engine(SSLClientContext* cc) @inline
{
    return &cc.eng;
}

const AUTH_ECDH  = 0;
const AUTH_RSA   = 1;
const AUTH_ECDSA = 3;

extern fn void ssl_engine_set_default_aes_cbc(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_aes_gcm(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_des_cbc(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_chapol(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_aes_ccm(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_ec(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_rsavrfy(SSLEngineContext* cc);
extern fn void ssl_engine_set_default_ecdsa(SSLEngineContext* cc);

extern fn void ssl_engine_inject_entropy(SSLEngineContext* cc, void* data, sz len);
extern fn int  ssl_key_export(SSLEngineContext* cc, void* dst, sz len, char* label, void* context, sz context_len);

extern fn void ssl_server_init_full_rsa(SSLServerContext* cc, X509Certificate* chain, sz chain_len, RSAPrivateKey* sk);
extern fn void ssl_server_init_full_ec(SSLServerContext* cc, X509Certificate* chain, sz chain_len, uint cert_issuer_key_type, ECPrivateKey* sk);
extern fn void ssl_server_init_minr2g(SSLServerContext* cc, X509Certificate* chain, sz chain_len, RSAPrivateKey* sk);
extern fn void ssl_server_init_mine2g(SSLServerContext* cc, X509Certificate* chain, sz chain_len, RSAPrivateKey* sk);
extern fn void ssl_server_init_minf2g(SSLServerContext* cc, X509Certificate* chain, sz chain_len, ECPrivateKey* sk);
extern fn void ssl_server_init_minu2g(SSLServerContext* cc, X509Certificate* chain, sz chain_len, ECPrivateKey* sk);
extern fn void ssl_server_init_minv2g(SSLServerContext* cc, X509Certificate* chain, sz chain_len, ECPrivateKey* sk);
extern fn void ssl_server_init_mine2c(SSLServerContext* cc, X509Certificate* chain, sz chain_len, RSAPrivateKey* sk);
extern fn void ssl_server_init_minf2c(SSLServerContext* cc, X509Certificate* chain, sz chain_len, ECPrivateKey* sk);

extern fn void ssl_server_zero(SSLServerContext* cc);
extern fn int  sslio_read_all(SSLIOContext* cc, void* dst, sz len);
extern fn int  sslio_write_all(SSLIOContext* cc, void* src, sz len);

fn ECImpl*       ssl_engine_get_ec(SSLEngineContext* cc) @inline { return cc.iec; }
fn RSAPKCS1Vrfy  ssl_engine_get_rsavrfy(SSLEngineContext* cc) @inline { return cc.irsavrfy; }
fn ECDSAVrfy     ssl_engine_get_ecdsa(SSLEngineContext* cc) @inline { return cc.iecdsa; }
fn int           ssl_engine_get_ecdhe_curve(SSLEngineContext* cc) @inline { return cc.ecdhe_curve; }

