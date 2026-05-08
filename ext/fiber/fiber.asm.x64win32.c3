// fiber.asm.x64win32.c3

// Assembly context switching code for x86-64 Windows ABI
//
// Converted from libco-style context switching.
//
// ABI:
//   - arg0: rcx = new context handle
//   - arg1: rdx = previous context handle
//
// Context layout:
//
//   offset  field
//   ------  -----
//   0       rsp
//   8       rbp
//   16      rsi
//   24      rdi
//   32      rbx
//   40      r12
//   48      r13
//   56      r14
//   64      r15
//   80      xmm6
//   96      xmm7
//   112     xmm8
//   128     xmm9
//   144     xmm10
//   160     xmm11
//   176     xmm12
//   192     xmm13
//   208     xmm14
//   224     xmm15
//
// Required context size:
//   at least 240 bytes
//
// Win64 callee-saved registers:
//   rbp, rsi, rdi, rbx, r12, r13, r14, r15
//   xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15
//
// This version uses movups instead of movaps for XMM save/restore,
// so the context buffer does not need 16-byte alignment.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(env::WIN32);

const char[*] ASM = {
    // ------------------------------------------------------------
    // save previous context
    //
    // rdx = prev handle
    // [rdx + 0] = current rsp
    // ------------------------------------------------------------

    0x48, 0x89, 0x22,             // mov [rdx], rsp

    // ------------------------------------------------------------
    // restore new stack pointer
    //
    // rcx = new handle
    // rsp = [rcx + 0]
    // ------------------------------------------------------------

    0x48, 0x8b, 0x21,             // mov rsp, [rcx]

    // ------------------------------------------------------------
    // pop resume address / initial entrypoint
    //
    // For an already-running fiber, this pops the return address
    // originally pushed by the call to asm_switch().
    //
    // For a newly-created fiber, create() must build the initial stack
    // so that the first popped value is the coroutine entrypoint.
    // ------------------------------------------------------------

    0x58,                         // pop rax

    // ------------------------------------------------------------
    // save Win64 callee-saved general-purpose registers
    // ------------------------------------------------------------

    0x48, 0x89, 0x6a, 0x08,       // mov [rdx +  8], rbp
    0x48, 0x89, 0x72, 0x10,       // mov [rdx + 16], rsi
    0x48, 0x89, 0x7a, 0x18,       // mov [rdx + 24], rdi
    0x48, 0x89, 0x5a, 0x20,       // mov [rdx + 32], rbx
    0x4c, 0x89, 0x62, 0x28,       // mov [rdx + 40], r12
    0x4c, 0x89, 0x6a, 0x30,       // mov [rdx + 48], r13
    0x4c, 0x89, 0x72, 0x38,       // mov [rdx + 56], r14
    0x4c, 0x89, 0x7a, 0x40,       // mov [rdx + 64], r15

    // ------------------------------------------------------------
    // save Win64 callee-saved XMM registers
    //
    // movups is used instead of movaps to avoid alignment faults.
    // ------------------------------------------------------------

    0x0f, 0x11, 0x72, 0x50,       // movups [rdx +  80], xmm6
    0x0f, 0x11, 0x7a, 0x60,       // movups [rdx +  96], xmm7
    0x44, 0x0f, 0x11, 0x42, 0x70, // movups [rdx + 112], xmm8

    0x48, 0x83, 0xc2, 0x70,       // add rdx, 112

    0x44, 0x0f, 0x11, 0x4a, 0x10, // movups [rdx +  16], xmm9
    0x44, 0x0f, 0x11, 0x52, 0x20, // movups [rdx +  32], xmm10
    0x44, 0x0f, 0x11, 0x5a, 0x30, // movups [rdx +  48], xmm11
    0x44, 0x0f, 0x11, 0x62, 0x40, // movups [rdx +  64], xmm12
    0x44, 0x0f, 0x11, 0x6a, 0x50, // movups [rdx +  80], xmm13
    0x44, 0x0f, 0x11, 0x72, 0x60, // movups [rdx +  96], xmm14
    0x44, 0x0f, 0x11, 0x7a, 0x70, // movups [rdx + 112], xmm15

    // ------------------------------------------------------------
    // restore Win64 callee-saved general-purpose registers
    //
    // rcx still points to the new context.
    // ------------------------------------------------------------

    0x48, 0x8b, 0x69, 0x08,       // mov rbp, [rcx +  8]
    0x48, 0x8b, 0x71, 0x10,       // mov rsi, [rcx + 16]
    0x48, 0x8b, 0x79, 0x18,       // mov rdi, [rcx + 24]
    0x48, 0x8b, 0x59, 0x20,       // mov rbx, [rcx + 32]
    0x4c, 0x8b, 0x61, 0x28,       // mov r12, [rcx + 40]
    0x4c, 0x8b, 0x69, 0x30,       // mov r13, [rcx + 48]
    0x4c, 0x8b, 0x71, 0x38,       // mov r14, [rcx + 56]
    0x4c, 0x8b, 0x79, 0x40,       // mov r15, [rcx + 64]

    // ------------------------------------------------------------
    // restore Win64 callee-saved XMM registers
    // ------------------------------------------------------------

    0x0f, 0x10, 0x71, 0x50,       // movups xmm6,  [rcx +  80]
    0x0f, 0x10, 0x79, 0x60,       // movups xmm7,  [rcx +  96]
    0x44, 0x0f, 0x10, 0x41, 0x70, // movups xmm8,  [rcx + 112]

    0x48, 0x83, 0xc1, 0x70,       // add rcx, 112

    0x44, 0x0f, 0x10, 0x49, 0x10, // movups xmm9,  [rcx +  16]
    0x44, 0x0f, 0x10, 0x51, 0x20, // movups xmm10, [rcx +  32]
    0x44, 0x0f, 0x10, 0x59, 0x30, // movups xmm11, [rcx +  48]
    0x44, 0x0f, 0x10, 0x61, 0x40, // movups xmm12, [rcx +  64]
    0x44, 0x0f, 0x10, 0x69, 0x50, // movups xmm13, [rcx +  80]
    0x44, 0x0f, 0x10, 0x71, 0x60, // movups xmm14, [rcx +  96]
    0x44, 0x0f, 0x10, 0x79, 0x70, // movups xmm15, [rcx + 112]

    // ------------------------------------------------------------
    // jump to resume address / entrypoint
    // ------------------------------------------------------------

    0xff, 0xe0,                   // jmp rax
};