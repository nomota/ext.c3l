// pem.h.c3

// PEM encoder and streaming decoder
//
// Naming conventions:
//   br_pem_decoder_context → PEMDecoderContext
//   br_pem_decoder_init    → pem_decoder_init    (extern fn)
//   br_pem_decoder_push    → pem_decoder_push    (extern fn)
//   br_pem_decoder_event   → pem_decoder_event   (extern fn)
//   br_pem_encode          → pem_encode          (extern fn)
//   BR_PEM_BEGIN_OBJ       → PEM_BEGIN_OBJ       (const)
//   BR_PEM_END_OBJ         → PEM_END_OBJ         (const)
//   BR_PEM_ERROR           → PEM_ERROR           (const)
//   BR_PEM_LINE64          → PEM_LINE64          (const)
//   BR_PEM_CRLF            → PEM_CRLF            (const)

module ext::net::tls;

// ============================================================================
// PEM Decoder Events
// ============================================================================

<*
  Event: start of a PEM object.

  Raised when the opening banner ("-----BEGIN ...-----") of a new object
  is detected. The object name (normalised to ASCII uppercase, trailing
  dashes stripped) can be retrieved with pem_decoder_name().
*>
const PEM_BEGIN_OBJ = 1;

<*
  Event: end of a PEM object.

  Raised when the closing banner ("-----END ...-----") of the current
  object is reached with no decoding error.
*>
const PEM_END_OBJ   = 2;

<*
  Event: decoding error within an object.

  Raised when Base64 decoding fails inside an object. This implicitly
  closes the current object and returns the decoder to the idle state.
  The offending source line is consumed before the event is raised.
*>
const PEM_ERROR     = 3;

// ============================================================================
// PEM Encoder Flags
// ============================================================================

<*
  Encoder flag: break lines at 64 characters instead of the default 76.
*>
const PEM_LINE64 = 0x0001;

<*
  Encoder flag: use CR+LF line endings instead of a bare LF.
*>
const PEM_CRLF   = 0x0002;

// ============================================================================
// PEM Decoder — Internal CPU State (T0 Virtual Machine)
// ============================================================================

<*
  Internal T0 virtual machine CPU state used by the PEM decoder.
  This structure is opaque; do not access its fields directly.
*>
struct PEMDecoderCPU {
    uint*  dp;
    uint*  rp;
    char*  ip;
}

// ============================================================================
// PEM Decoder Data Callback
// ============================================================================

<*
  Callback function type for receiving decoded PEM object data.

  Called repeatedly with successive chunks of decoded binary data as the
  decoder processes a PEM object. Set via pem_decoder_setdest(). If set
  to null, decoded data is silently discarded.

  param dest_ctx   opaque context pointer supplied to pem_decoder_setdest().
  param src        pointer to the current chunk of decoded data.
  param len        chunk length (in bytes).
*>
alias PEMDestFn = fn void(void* dest_ctx, void* src, sz len);

// ============================================================================
// PEM Decoder Context
// ============================================================================

<*
  PEM decoder context.

  Implements a streaming, state-machine-based PEM decoder. The caller
  pushes source bytes with pem_decoder_push() and polls for events with
  pem_decoder_event(). No dynamic allocation is performed; the context
  may be discarded without any explicit cleanup.

  All fields are opaque; use the provided API functions to interact with
  the decoder.
*>
struct PEMDecoderContext {
    // T0 virtual machine CPU state
    PEMDecoderCPU cpu;
    uint[32]      dp_stack;
    uint[32]      rp_stack;
    int           err;

    // Input buffer pointers (current source window)
    char*         hbuf;
    sz           hlen;

    // Decoded data callback and its opaque context
    PEMDestFn     dest;
    void*         dest_ctx;

    // Current event code (one of PEM_BEGIN_OBJ, PEM_END_OBJ, PEM_ERROR, or 0)
    char          event;
    // Object name, normalised to ASCII uppercase (NUL-terminated, max 127 chars)
    char[128]     name;
    // Internal Base64 decode buffer
    char[255]     buf;
    sz           ptr;
}

// ============================================================================
// PEM Decoder API
// ============================================================================

<*
  Initialise a PEM decoder context.

  Must be called before any other decoder function on the context.

  param ctx   decoder context to initialise.
*>
extern fn void pem_decoder_init(PEMDecoderContext* ctx);

<*
  Push source bytes into the PEM decoder.

  Returns the number of bytes actually consumed, which may be less than
  len if an event is raised mid-stream. While an event is pending (i.e.
  before pem_decoder_event() has been called to clear it), this function
  returns 0 and no bytes are consumed.

  param ctx    decoder context.
  param data   source bytes to push.
  param len    number of source bytes.
  return number of bytes consumed (0 to len).
*>
extern fn sz pem_decoder_push(PEMDecoderContext* ctx, void* data, sz len);

<*
  Set the callback for receiving decoded object data.

  Once an object-start event is raised, this callback is invoked repeatedly
  with successive decoded binary chunks. Setting dest to null discards all
  decoded data. Should typically be called immediately after observing a
  PEM_BEGIN_OBJ event.

  param ctx        decoder context.
  param dest       callback to receive decoded data chunks (or null).
  param dest_ctx   opaque pointer passed through to each dest call.
*>
fn void pem_decoder_setdest(PEMDecoderContext* ctx, PEMDestFn dest, void* dest_ctx) @inline
{
    ctx.dest     = dest;
    ctx.dest_ctx = dest_ctx;
}

<*
  Read and clear the current decoder event.

  Returns the pending event value (PEM_BEGIN_OBJ, PEM_END_OBJ, or
  PEM_ERROR) and clears it so that the decoder can accept further input.
  Returns 0 if no event is pending.

  param ctx   decoder context.
  return the current event, or 0 if none.
*>
extern fn int pem_decoder_event(PEMDecoderContext* ctx);

<*
  Get the name of the most recently detected PEM object.

  Valid only immediately after a PEM_BEGIN_OBJ event is raised. The name
  is normalised to ASCII uppercase and does not include trailing dashes.
  The returned pointer refers to storage inside ctx and remains valid
  until the next call that modifies the context.

  param ctx   decoder context.
  return NUL-terminated object name string.
*>
fn char* pem_decoder_name(PEMDecoderContext* ctx) @inline
{
    return &ctx.name[0];
}

// ============================================================================
// PEM Encoder
// ============================================================================

<*
  Encode binary data as a PEM object.

  Encodes the binary data at src (len bytes) into PEM format, writing the
  result into dest (NUL-terminated). The banner string is embedded in the
  opening and closing lines (e.g. "CERTIFICATE" produces
  "-----BEGIN CERTIFICATE-----" / "-----END CERTIFICATE-----").

  Returns the number of characters written, NOT counting the terminating
  NUL. Allocate at least one extra byte beyond the returned value.

  If dest is null, no output is written but the required length is still
  computed and returned. If len is zero, src may also be null. If dest is
  null, src may be null regardless of len.

  The dest and src buffers may overlap (src is consumed before the
  corresponding output position is reached); note that PEM output is
  always larger than the source binary.

  Flags:
    PEM_LINE64  — break lines at 64 characters (default: 76).
    PEM_CRLF    — use CR+LF line endings (default: LF only).

  param dest     destination buffer, or null to compute length only.
  param src      source binary data (may be null in some cases; see above).
  param len      source data length (in bytes).
  param banner   PEM banner label string (e.g. "CERTIFICATE").
  param flags    encoder flags (PEM_LINE64, PEM_CRLF, or 0).
  return PEM output length in characters, excluding the terminating NUL.
*>
extern fn sz pem_encode(void* dest, void* src, sz len, char* banner, uint flags);
