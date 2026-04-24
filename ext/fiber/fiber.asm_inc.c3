// fiber.asm_inc.c3

// Assembly context switching code
// converted from libco

// Nomota <hiongun@gmail.com>; MIT License

module ext::thread::fiber @if(env::X86_64);

// 
// x86-64 swap function (machine code)
//
// Two ABI variants are compiled in conditionally:
//   - Win64:    args in rcx (new), rdx (prev)
//               callee-saved: rbp, rsi, rdi, rbx, r12-r15, xmm6-xmm15
//   - System V: args in rdi (new), rsi (prev)
//               callee-saved: rbp, rbx, r12-r15  (no SSE regs required)
//
// Common logic:
//   mov [prev], rsp        ; save current stack pointer
//   mov rsp,    [new]      ; restore next stack pointer
//   pop rax                ; pop entrypoint address into rax
//   mov [prev+N], reg      ; save callee-saved registers
//   mov reg,    [new+N]    ; restore callee-saved registers
//   jmp rax                ; jump to entrypoint (or resume point)
// 


// ----------------------------------------
// Win64 ABI
// rcx = new handle, rdx = prev handle
// Win64 callee-saved: rbp, rsi, rdi, rbx, r12-r15, xmm6-xmm15
// ----------------------------------------
const char[*] ASMWIN64 = {
    // --- save prev context (rdx) ---
    0x48, 0x89, 0x22, // mov [rdx], rsp
    0x48, 0x8b, 0x21, // mov rsp, [rcx]
    0x58, // pop rax  ; entrypoint → rax
    0x48, 0x89, 0x6a, 0x08, // mov [rdx+ 8], rbp
    0x48, 0x89, 0x72, 0x10, // mov [rdx+16], rsi
    0x48, 0x89, 0x7a, 0x18, // mov [rdx+24], rdi
    0x48, 0x89, 0x5a, 0x20, // mov [rdx+32], rbx
    0x4c, 0x89, 0x62, 0x28, // mov [rdx+40], r12
    0x4c, 0x89, 0x6a, 0x30, // mov [rdx+48], r13
    0x4c, 0x89, 0x72, 0x38, // mov [rdx+56], r14
    0x4c, 0x89, 0x7a, 0x40, // mov [rdx+64], r15

    // Win64 requires saving xmm6-xmm15 (callee-saved SSE registers)
    0x0f, 0x29, 0x72, 0x50, // movaps [rdx+ 80], xmm6
    0x0f, 0x29, 0x7a, 0x60, // movaps [rdx+ 96], xmm7
    0x44, 0x0f, 0x29, 0x42, 0x70, // movaps [rdx+112], xmm8
    0x48, 0x83, 0xc2, 0x70, // add rdx, 112     ; advance base for xmm9-15
    0x44, 0x0f, 0x29, 0x4a, 0x10, // movaps [rdx+ 16], xmm9
    0x44, 0x0f, 0x29, 0x52, 0x20, // movaps [rdx+ 32], xmm10
    0x44, 0x0f, 0x29, 0x5a, 0x30, // movaps [rdx+ 48], xmm11
    0x44, 0x0f, 0x29, 0x62, 0x40, // movaps [rdx+ 64], xmm12
    0x44, 0x0f, 0x29, 0x6a, 0x50, // movaps [rdx+ 80], xmm13
    0x44, 0x0f, 0x29, 0x72, 0x60, // movaps [rdx+ 96], xmm14
    0x44, 0x0f, 0x29, 0x7a, 0x70, // movaps [rdx+112], xmm15
        
    // --- restore new context (rcx) ---
    0x48, 0x8b, 0x69, 0x08, // mov rbp, [rcx+ 8]
    0x48, 0x8b, 0x71, 0x10, // mov rsi, [rcx+16]
    0x48, 0x8b, 0x79, 0x18, // mov rdi, [rcx+24]
    0x48, 0x8b, 0x59, 0x20, // mov rbx, [rcx+32]
    0x4c, 0x8b, 0x61, 0x28, // mov r12, [rcx+40]
    0x4c, 0x8b, 0x69, 0x30, // mov r13, [rcx+48]
    0x4c, 0x8b, 0x71, 0x38, // mov r14, [rcx+56]
    0x4c, 0x8b, 0x79, 0x40, // mov r15, [rcx+64]
        
    0x0f, 0x28, 0x71, 0x50, // movaps xmm6,  [rcx+ 80]
    0x0f, 0x28, 0x79, 0x60, // movaps xmm7,  [rcx+ 96]
    0x44, 0x0f, 0x28, 0x41, 0x70, // movaps xmm8,  [rcx+112]
    0x48, 0x83, 0xc1, 0x70, // add rcx, 112
    0x44, 0x0f, 0x28, 0x49, 0x10, // movaps xmm9,  [rcx+ 16]
    0x44, 0x0f, 0x28, 0x51, 0x20, // movaps xmm10, [rcx+ 32]
    0x44, 0x0f, 0x28, 0x59, 0x30, // movaps xmm11, [rcx+ 48]
    0x44, 0x0f, 0x28, 0x61, 0x40, // movaps xmm12, [rcx+ 64]
    0x44, 0x0f, 0x28, 0x69, 0x50, // movaps xmm13, [rcx+ 80]
    0x44, 0x0f, 0x28, 0x71, 0x60, // movaps xmm14, [rcx+ 96]
    0x44, 0x0f, 0x28, 0x79, 0x70, // movaps xmm15, [rcx+112]
        
    0xff, 0xe0, // jmp rax
};


// ----------------------------------------
// System V AMD64 ABI (Linux, macOS, BSD)
// rdi = new handle, rsi = prev handle
// SysV callee-saved: rbp, rbx, r12-r15
// xmm registers are all caller-saved in SysV — no need to save
// ----------------------------------------
const char[*] ASM = {
    // --- save prev context (rsi) ---
    0x48, 0x89, 0x26, // mov [rsi], rsp
    0x48, 0x8b, 0x27, // mov rsp, [rdi]
    0x58, // pop rax ; entrypoint → rax
    0x48, 0x89, 0x6e, 0x08, // mov [rsi+ 8], rbp
    0x48, 0x89, 0x5e, 0x10, // mov [rsi+16], rbx
    0x4c, 0x89, 0x66, 0x18, // mov [rsi+24], r12
    0x4c, 0x89, 0x6e, 0x20, // mov [rsi+32], r13
    0x4c, 0x89, 0x76, 0x28, // mov [rsi+40], r14
    0x4c, 0x89, 0x7e, 0x30, // mov [rsi+48], r15
    // --- restore new context (rdi) ---
    0x48, 0x8b, 0x6f, 0x08, // mov rbp, [rdi+ 8]
    0x48, 0x8b, 0x5f, 0x10, // mov rbx, [rdi+16]
    0x4c, 0x8b, 0x67, 0x18, // mov r12, [rdi+24]
    0x4c, 0x8b, 0x6f, 0x20, // mov r13, [rdi+32]
    0x4c, 0x8b, 0x77, 0x28, // mov r14, [rdi+40]
    0x4c, 0x8b, 0x7f, 0x30, // mov r15, [rdi+48]
    0xff, 0xe0, // jmp rax
};

module ext::thread::fiber @if(env::AARCH64);

const char[*] ASM = {
  0x910003f0,  /* mov x16,sp           */
  0xa9007830,  /* stp x16,x30,[x1]     */
  0xa9407810,  /* ldp x16,x30,[x0]     */
  0x9100021f,  /* mov sp,x16           */
  0xa9015033,  /* stp x19,x20,[x1, 16] */
  0xa9415013,  /* ldp x19,x20,[x0, 16] */
  0xa9025835,  /* stp x21,x22,[x1, 32] */
  0xa9425815,  /* ldp x21,x22,[x0, 32] */
  0xa9036037,  /* stp x23,x24,[x1, 48] */
  0xa9436017,  /* ldp x23,x24,[x0, 48] */
  0xa9046839,  /* stp x25,x26,[x1, 64] */
  0xa9446819,  /* ldp x25,x26,[x0, 64] */
  0xa905703b,  /* stp x27,x28,[x1, 80] */
  0xa945701b,  /* ldp x27,x28,[x0, 80] */
  0xf900303d,  /* str x29,    [x1, 96] */
  0xf940301d,  /* ldr x29,    [x0, 96] */
  0x6d072428,  /* stp d8, d9, [x1,112] */
  0x6d472408,  /* ldp d8, d9, [x0,112] */
  0x6d082c2a,  /* stp d10,d11,[x1,128] */
  0x6d482c0a,  /* ldp d10,d11,[x0,128] */
  0x6d09342c,  /* stp d12,d13,[x1,144] */
  0x6d49340c,  /* ldp d12,d13,[x0,144] */
  0x6d0a3c2e,  /* stp d14,d15,[x1,160] */
  0x6d4a3c0e,  /* ldp d14,d15,[x0,160] */
  0xd61f03c0,  /* br x30               */
};


module ext::thread::fiber @if(env::X86);

// asm_switch(oldp, newp);
// fastcall: oldp to edx, newp to ecx, push return addr, call asm
// stdcall: push newp, push oldp, push return addr, call asm

const char[*] ASM = {
    0x58, // pop eax
    // pop ecx
    // pop edx
    // push ebp
    // mov ebp, esp
    0x89, 0x22, // mov [edx], esp
    0x8b, 0x21, // mov esp, [ecx]
    0x89, 0x6a, 0x04, // mov [edx+4], ebp
    0x89, 0x72, 0x08, // mov [edx+8], esi
    0x89, 0x7a, 0x0c, // mov [edx+12], edi
    0x89, 0x5a, 0x10, // mov [edx+16], ebx
    0x8b, 0x69, 0x04, // mov ebp, [ecx+4]
    0x8b, 0x71, 0x08, // mov esi, [ecx+8]
    0x8b, 0x79, 0x0c, // mov edi, [ecx+12]
    0x8b, 0x59, 0x10, // mov ebx, [ecx+16]
    // mov esp, ebp
    // pop ebp
    0xff, 0xe0, // jmp eax
};

