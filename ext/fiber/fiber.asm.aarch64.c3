// fiber.asm.aarch64.c3

// Assembly context switching code for AArch64
//
// ABI:
//   - arg0: x0 = new context handle
//   - arg1: x1 = previous context handle
//
// Context layout:
//
//   offset  field
//   ------  -----
//   0       sp saved in x16
//   8       x30 / lr
//   16      x19
//   24      x20
//   32      x21
//   40      x22
//   48      x23
//   56      x24
//   64      x25
//   72      x26
//   80      x27
//   88      x28
//   96      x29 / fp
//   112     d8
//   120     d9
//   128     d10
//   136     d11
//   144     d12
//   152     d13
//   160     d14
//   168     d15
//
// Required context size:
//   at least 176 bytes
//
// AArch64 callee-saved registers:
//   x19-x28, x29/fp, x30/lr
//   d8-d15
//
// Notes:
//   - sp cannot be stored directly with normal stp/str addressing, so it is
//     copied through x16.
//   - x16 is an intra-procedure-call scratch register, so it does not need
//     to be preserved.
//   - Instruction words are encoded as little-endian bytes.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(env::AARCH64);

const char[*] ASM = {
    // ------------------------------------------------------------
    // save previous sp and lr
    //
    // x1 = prev handle
    // x16 = sp
    // [x1 + 0] = x16 / sp
    // [x1 + 8] = x30 / lr
    // ------------------------------------------------------------

    0xf0, 0x03, 0x00, 0x91,       // mov x16, sp
    0x30, 0x78, 0x00, 0xa9,       // stp x16, x30, [x1]

    // ------------------------------------------------------------
    // restore new sp and lr
    //
    // x0 = new handle
    // x16 = [x0 + 0]
    // x30 = [x0 + 8]
    // sp = x16
    // ------------------------------------------------------------

    0x10, 0x78, 0x40, 0xa9,       // ldp x16, x30, [x0]
    0x1f, 0x02, 0x00, 0x91,       // mov sp, x16

    // ------------------------------------------------------------
    // save / restore callee-saved general-purpose registers
    // ------------------------------------------------------------

    0x33, 0x50, 0x01, 0xa9,       // stp x19, x20, [x1, 16]
    0x13, 0x50, 0x41, 0xa9,       // ldp x19, x20, [x0, 16]

    0x35, 0x58, 0x02, 0xa9,       // stp x21, x22, [x1, 32]
    0x15, 0x58, 0x42, 0xa9,       // ldp x21, x22, [x0, 32]

    0x37, 0x60, 0x03, 0xa9,       // stp x23, x24, [x1, 48]
    0x17, 0x60, 0x43, 0xa9,       // ldp x23, x24, [x0, 48]

    0x39, 0x68, 0x04, 0xa9,       // stp x25, x26, [x1, 64]
    0x19, 0x68, 0x44, 0xa9,       // ldp x25, x26, [x0, 64]

    0x3b, 0x70, 0x05, 0xa9,       // stp x27, x28, [x1, 80]
    0x1b, 0x70, 0x45, 0xa9,       // ldp x27, x28, [x0, 80]

    0x3d, 0x30, 0x00, 0xf9,       // str x29, [x1, 96]
    0x1d, 0x30, 0x40, 0xf9,       // ldr x29, [x0, 96]

    // ------------------------------------------------------------
    // save / restore callee-saved floating-point registers
    // ------------------------------------------------------------

    0x28, 0x24, 0x07, 0x6d,       // stp d8, d9, [x1, 112]
    0x08, 0x24, 0x47, 0x6d,       // ldp d8, d9, [x0, 112]

    0x2a, 0x2c, 0x08, 0x6d,       // stp d10, d11, [x1, 128]
    0x0a, 0x2c, 0x48, 0x6d,       // ldp d10, d11, [x0, 128]

    0x2c, 0x34, 0x09, 0x6d,       // stp d12, d13, [x1, 144]
    0x0c, 0x34, 0x49, 0x6d,       // ldp d12, d13, [x0, 144]

    0x2e, 0x3c, 0x0a, 0x6d,       // stp d14, d15, [x1, 160]
    0x0e, 0x3c, 0x4a, 0x6d,       // ldp d14, d15, [x0, 160]

    // ------------------------------------------------------------
    // jump to restored lr / entrypoint
    // ------------------------------------------------------------

    0xc0, 0x03, 0x1f, 0xd6,       // br x30
};