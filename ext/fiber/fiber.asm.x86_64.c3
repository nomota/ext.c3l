// fiber.asm.x86_64.c3

// Assembly context switching code for x86-64 System V ABI
//
// Converted from libco-style context switching.
//
// ABI:
//   - arg0: rdi = new context handle
//   - arg1: rsi = previous context handle
//
// Context layout:
//
//   offset  field
//   --  -
//   0       rsp
//   8       rbp
//   16      rbx
//   24      r12
//   32      r13
//   40      r14
//   48      r15
//
// SysV AMD64 callee-saved registers:
//   rbp, rbx, r12, r13, r14, r15
//
// SSE/XMM registers are caller-saved in SysV, so they are not saved here.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber @if(env::POSIX && env::X86_64);

const char[*] ASM = {
    // 
    // save previous context
    //
    // rsi = prev handle
    // [rsi + 0] = current rsp
    // 

    0x48, 0x89, 0x26,             // mov [rsi], rsp

    // 
    // restore new stack pointer
    //
    // rdi = new handle
    // rsp = [rdi + 0]
    // 

    0x48, 0x8b, 0x27,             // mov rsp, [rdi]

    // 
    // pop resume address / initial entrypoint
    //
    // For an already-running fiber, this pops the return address
    // originally pushed by the call to asm_switch().
    //
    // For a newly-created fiber, create() must build the initial stack
    // so that the first popped value is the coroutine entrypoint.
    // 

    0x58,                         // pop rax

    // 
    // save SysV callee-saved registers into previous context
    // 

    0x48, 0x89, 0x6e, 0x08,       // mov [rsi +  8], rbp
    0x48, 0x89, 0x5e, 0x10,       // mov [rsi + 16], rbx
    0x4c, 0x89, 0x66, 0x18,       // mov [rsi + 24], r12
    0x4c, 0x89, 0x6e, 0x20,       // mov [rsi + 32], r13
    0x4c, 0x89, 0x76, 0x28,       // mov [rsi + 40], r14
    0x4c, 0x89, 0x7e, 0x30,       // mov [rsi + 48], r15

    // 
    // restore SysV callee-saved registers from new context
    // 

    0x48, 0x8b, 0x6f, 0x08,       // mov rbp, [rdi +  8]
    0x48, 0x8b, 0x5f, 0x10,       // mov rbx, [rdi + 16]
    0x4c, 0x8b, 0x67, 0x18,       // mov r12, [rdi + 24]
    0x4c, 0x8b, 0x6f, 0x20,       // mov r13, [rdi + 32]
    0x4c, 0x8b, 0x77, 0x28,       // mov r14, [rdi + 40]
    0x4c, 0x8b, 0x7f, 0x30,       // mov r15, [rdi + 48]

    // 
    // jump to resume address / entrypoint
    // 

    0xff, 0xe0,                   // jmp rax
};