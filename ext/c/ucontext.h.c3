// ucontext.h.c3

// ucontext.h — user-space context saving and switching
//
// Depends on signal.h.c3 for signal::Stack and signal::SigSet.

module c::ucontext @if(!env::WIN32);

// Context manipulation functions
extern fn int getcontext(UContext* ucp);
extern fn int setcontext(UContext* ucp);
alias Coroutine = fn void();
extern fn void makecontext(UContext* ucp, Coroutine func, int argc, ...);
extern fn int swapcontext(UContext* oucp, UContext* ucp);



module c::ucontext @if(env::LINUX);

// greg_t: general-purpose register value
alias Greg = long;

module c::ucontext @if(env::LINUX && env::X86_64);

import c::signal;

    // Number of general-purpose registers in mcontext
    const int NGREG = 23;

    // gregset_t register indices (x86-64)
    const int REG_R8      = 0;  // %r8
    const int REG_R9      = 1;  // %r9
    const int REG_R10     = 2;  // %r10
    const int REG_R11     = 3;  // %r11
    const int REG_R12     = 4;  // %r12
    const int REG_R13     = 5;  // %r13
    const int REG_R14     = 6;  // %r14
    const int REG_R15     = 7;  // %r15
    const int REG_RDI     = 8;  // %rdi
    const int REG_RSI     = 9;  // %rsi
    const int REG_RBP     = 10; // %rbp
    const int REG_RBX     = 11; // %rbx
    const int REG_RDX     = 12; // %rdx
    const int REG_RAX     = 13; // %rax
    const int REG_RCX     = 14; // %rcx
    const int REG_RSP     = 15; // %rsp
    const int REG_RIP     = 16; // %rip (instruction pointer)
    const int REG_EFL     = 17; // %eflags
    const int REG_CSGSFS  = 18; // %cs/%gs/%fs segment registers
    const int REG_ERR     = 19; // Fault error code
    const int REG_TRAPNO  = 20; // Trap number
    const int REG_OLDMASK = 21; // Old signal mask (obsolete)
    const int REG_CR2     = 22; // %cr2 (page fault address)

    // x87 FPU register (80-bit extended precision, padded to 128 bits)
    struct FpXReg {
        ushort[4] significand;
        ushort    exponent;
        ushort[3] _padding;
    }

    // SSE/AVX XMM register (128-bit)
    struct XmmReg {
        uint[4] element;
    }

    // Floating-point and SSE state (_fpstate / _libc_fpstate)
    struct FpState @cname("_fpstate") {
        ushort   cwd;         // FPU control word
        ushort   swd;         // FPU status word
        ushort   ftw;         // FPU tag word (abridged)
        ushort   fop;         // Last FPU opcode
        ulong    rip;         // FPU instruction pointer
        ulong    rdp;         // FPU data pointer
        uint     mxcsr;       // SSE control/status register
        uint     mxcr_mask;   // Valid bits in mxcsr
        FpXReg[8]  _st;       // x87 ST(0)–ST(7)
        XmmReg[16] _xmm;      // XMM0–XMM15
        uint[24] _padding;
    }

    // Machine context (mcontext_t) — x86-64 Linux
    struct MContext @cname("mcontext_t") {
        Greg[23]  gregs;        // General-purpose registers (use REG_* indices)
        FpState*  fpregs;       // Pointer to FP/SSE state (null if not saved)
        ulong[8]  __reserved1;
    }

    // Full user context (ucontext_t) — x86-64 Linux
    struct UContext @cname("ucontext_t") {
        ulong       uc_flags;    // Context flags (kernel internal)
        UContext*   uc_link;     // Context to resume when this one returns
        signal::Stack   uc_stack;    // Stack used by this context
        MContext    uc_mcontext; // Machine-specific saved registers
        signal::SigSet  uc_sigmask;  // Signals blocked in this context
        FpState     __fpregs_mem; // Storage for FP state (fpregs points here)
        ulong[4]    __ssp;       // Shadow stack pointer (CET)
    }

module c::ucontext @if(env::LINUX && env::AARCH64);

import c::signal;

    // Number of general-purpose registers
    const int NGREG = 34; // 31 GP regs + sp + pc + pstate

    // aarch64 FP/SIMD register (128-bit)
    struct Vv128 {
        ulong[2] val;
    }

    // aarch64 FP state
    struct FpSimdContext @cname("fpsimd_context") {
        uint   head;       // FPSIMD_MAGIC
        uint   size;
        uint   fpsr;       // FP status register
        uint   fpcr;       // FP control register
        Vv128[32] vregs;    // V0–V31 SIMD registers
    }

    // Machine context (mcontext_t) — aarch64 Linux
    // Matches struct sigcontext in the kernel ABI.
    struct MContext @cname("mcontext_t") {
        ulong       fault_address; // Faulting address (if applicable)
        ulong[31]   regs;          // X0–X30 general-purpose registers
        ulong       sp;            // Stack pointer
        ulong       pc;            // Program counter
        ulong       pstate;        // CPSR / SPSR
        char[4096]  __reserved;    // Space for additional records (16-byte aligned)
    }

    // Full user context (ucontext_t) — aarch64 Linux
    struct UContext @cname("ucontext_t") {
        ulong           uc_flags;
        UContext*       uc_link;
        signal::Stack       uc_stack;
        signal::SigSet      uc_sigmask;
        MContext        uc_mcontext;
    }

module c::ucontext @if(env::LINUX && env::X86);

import c::signal;

    // Number of general-purpose registers (i386)
    const int NGREG = 19;

    // gregset_t register indices (i386)
    const int REG_GS     = 0;
    const int REG_FS     = 1;
    const int REG_ES     = 2;
    const int REG_DS     = 3;
    const int REG_EDI    = 4;
    const int REG_ESI    = 5;
    const int REG_EBP    = 6;
    const int REG_ESP    = 7;
    const int REG_EBX    = 8;
    const int REG_EDX    = 9;
    const int REG_ECX    = 10;
    const int REG_EAX    = 11;
    const int REG_TRAPNO = 12;
    const int REG_ERR    = 13;
    const int REG_EIP    = 14;
    const int REG_CS     = 15;
    const int REG_EFL    = 16;
    const int REG_UESP   = 17;
    const int REG_SS     = 18;

    // x87 FPU register (i386)
    struct FpReg {
        ushort[4] significand;
        ushort    exponent;
    }

    // Floating-point state (i386 _fpstate)
    struct FpState @cname("_fpstate") {
        ulong    cw;          // FPU control word
        ulong    sw;          // FPU status word
        ulong    tag;         // FPU tag word
        ulong    ipoff;       // FPU instruction pointer offset
        ulong    cssel;       // FPU code segment selector
        ulong    dataoff;     // FPU data pointer offset
        ulong    datasel;     // FPU data segment selector
        FpReg[8] _st;         // x87 ST(0)–ST(7)
        ushort   status;
        ushort   magic;       // 0xffff = no FP/EMU, 0x0000 = FP/EMU present
    }

    // Machine context (mcontext_t) — i386 Linux
    struct MContext @cname("mcontext_t") {
        Greg[19]  gregs;
        FpState*  fpregs;
        ulong     oldmask;
        ulong     cr2;
    }

    // Full user context (ucontext_t) — i386 Linux
    struct UContext @cname("ucontext_t") {
        ulong       uc_flags;
        UContext*   uc_link;
        signal::Stack   uc_stack;
        MContext    uc_mcontext;
        signal::SigSet  uc_sigmask;
        FpState     __fpregs_mem;
    }

module c::ucontext @if(env::LINUX && env::ARCH_TYPE == RISCV64);

import c::signal;

    // Number of general-purpose registers (RISC-V)
    const int NGREG = 32;

    // RISC-V FP state
    struct FpState @cname("__riscv_mc_f_ext_state") {
        uint[32] f;      // FP registers (single precision)
        uint     fcsr;   // FP control/status register
    }

    struct FpStateD @cname("__riscv_mc_d_ext_state") {
        ulong[32] f;     // FP registers (double precision)
        uint      fcsr;
    }

    // Machine context — RISC-V 64
    struct MContext @cname("mcontext_t") {
        ulong[32] gregs;  // x0–x31 (x0 always zero)
        FpStateD  fpregs;
    }

    // Full user context — RISC-V 64
    struct UContext @cname("ucontext_t") {
        ulong           uc_flags;
        UContext*       uc_link;
        signal::Stack       uc_stack;
        signal::SigSet      uc_sigmask;
        char[1024 / 8]  __unused; // alignment padding
        MContext        uc_mcontext;
    }




module c::ucontext @if(env::DARWIN && env::AARCH64);

    // arm64 exception state
    struct ArmExceptionState64 @cname("__darwin_arm_exception_state64") {
        ulong   far;  // Fault address register
        uint    esr;  // Exception syndrome register
        uint    exception;
    }

    // arm64 general-purpose thread state
    struct ArmThreadState64 @cname("__darwin_arm_thread_state64") {
        ulong[29] x;    // X0–X28
        ulong     fp;   // Frame pointer (X29)
        ulong     lr;   // Link register (X30)
        ulong     sp;   // Stack pointer
        ulong     pc;   // Program counter
        uint      cpsr; // Current program status register
        uint      __pad;
    }

    // arm64 NEON/FP state
    struct ArmNeonState64 @cname("__darwin_arm_neon_state64") {
        char[512] v;    // Q0–Q31 (128-bit each, 32 * 16 = 512)
        uint      fpsr;
        uint      fpcr;
    }

    // Machine context — arm64 Darwin
    struct MContext @cname("__darwin_mcontext64") {
        ArmExceptionState64 es;
        ArmThreadState64    ss;
        ArmNeonState64      ns;
    }

module c::ucontext @if(env::DARWIN && env::X86_64);

    // x86-64 exception state
    struct X86ExceptionState64 @cname("__darwin_x86_exception_state64") {
        uint trapno;
        uint cpu;
        ulong faultvaddr;
    }

    // x86-64 general-purpose thread state
    struct X86ThreadState64 @cname("__darwin_x86_thread_state64") {
        ulong rax, rbx, rcx, rdx;
        ulong rdi, rsi, rbp, rsp;
        ulong r8,  r9,  r10, r11;
        ulong r12, r13, r14, r15;
        ulong rip;
        ulong rflags;
        ulong cs, fs, gs;
    }

    // x86-64 float/SSE state
    struct X86FloatState64 @cname("__darwin_x86_float_state64") {
        int[2]   __invalid_env;  // Legacy FPU env (unused)
        char[512] __fpu_fcw;     // Full FXSAVE area (512 bytes)
    }

    // Machine context — x86-64 Darwin
    struct MContext @cname("__darwin_mcontext64") {
        X86ExceptionState64 es;
        X86ThreadState64    ss;
        X86FloatState64     fs;
    }

module c::ucontext @if(env::DARWIN);

import c::signal;

// Full user context — Darwin
// uc_mcontext is a POINTER to MContext (not inline), sized by uc_mcsize.
struct UContext @cname("ucontext") {
    int             uc_onstack;   // Nonzero if executing on signal stack
    signal::SigSet      uc_sigmask;  // Signals blocked in this context
    signal::Stack       uc_stack;    // Stack used by this context
    UContext*       uc_link;      // Context to resume when this one returns
    sz             uc_mcsize;    // Size of machine context (bytes)
    MContext*       uc_mcontext;  // Pointer to machine context
}



module c::ucontext @if(env::FREEBSD && env::X86_64);

    // Machine context — x86-64 FreeBSD
    struct MContext @cname("mcontext") {
        long  mc_onstack;  // Nonzero if executing on signal stack
        long  mc_rdi;
        long  mc_rsi;
        long  mc_rdx;
        long  mc_rcx;
        long  mc_r8;
        long  mc_r9;
        long  mc_rax;
        long  mc_rbx;
        long  mc_rbp;
        long  mc_r10;
        long  mc_r11;
        long  mc_r12;
        long  mc_r13;
        long  mc_r14;
        long  mc_r15;
        uint  mc_trapno;
        ushort mc_fs;
        ushort mc_gs;
        long  mc_addr;    // Fault address
        uint  mc_flags;
        ushort mc_es;
        ushort mc_ds;
        long  mc_err;
        long  mc_rip;
        long  mc_cs;
        long  mc_rflags;
        long  mc_rsp;
        long  mc_ss;
        long  mc_len;      // sizeof(MContext)
        long  mc_fpformat; // FP state format
        long  mc_ownedfp;  // FP ownership flag
        long[64] mc_fpstate; // FP/SSE state (512 bytes)
        long  mc_fsbase;   // %fs base address
        long  mc_gsbase;   // %gs base address
        long  mc_xfpustate;    // Extended FPU state pointer
        long  mc_xfpustate_len;
        long[4] mc_spare;
    }

module c::ucontext @if(env::FREEBSD && env::AARCH64);

    // Machine context — aarch64 FreeBSD
    struct MContext @cname("mcontext") {
        ulong[30]       mc_gpregs_x; // X0–X29
        ulong       mc_lr;           // X30 (link register)
        ulong       mc_sp;
        ulong       mc_elr;          // Exception link register (PC)
        ulong       mc_spsr;         // Saved program status register
        uint        mc_flags;
        uint        mc_pad;
        ulong[8]    mc_spare;
        char[288]   mc_fpregs;       // FP/SIMD state (struct fpregs)
    }

module c::ucontext @if(env::FREEBSD);

import c::signal;

// Full user context — FreeBSD
struct UContext @cname("ucontext") {
    signal::SigSet  uc_sigmask;
    MContext    uc_mcontext;
    UContext*   uc_link;
    signal::Stack   uc_stack;
    int         uc_flags;
    int[4]      __spare__;
}

// uc_flags values
const int UCF_SWAPPED = 0x00000001; // Context has been swapped



module c::ucontext @if(env::NETBSD && env::X86_64);

    // Machine context — x86-64 NetBSD
    struct MContext @cname("mcontext") {
        ulong  __gregs_rdi;
        ulong  __gregs_rsi;
        ulong  __gregs_rdx;
        ulong  __gregs_rcx;
        ulong  __gregs_r8;
        ulong  __gregs_r9;
        ulong  __gregs_r10;
        ulong  __gregs_r11;
        ulong  __gregs_r12;
        ulong  __gregs_r13;
        ulong  __gregs_r14;
        ulong  __gregs_r15;
        ulong  __gregs_rbp;
        ulong  __gregs_rbx;
        ulong  __gregs_rax;
        ulong  __gregs_gs;
        ulong  __gregs_fs;
        ulong  __gregs_es;
        ulong  __gregs_ds;
        ulong  __gregs_trapno;
        ulong  __gregs_err;
        ulong  __gregs_rip;
        ulong  __gregs_cs;
        ulong  __gregs_rflags;
        ulong  __gregs_rsp;
        ulong  __gregs_ss;
        ulong  mc_tlsbase;  // %fs base (TLS)
        char[512] __fpregs; // FXSAVE area
    }

module c::ucontext @if(env::NETBSD && env::AARCH64);

    // Machine context — aarch64 NetBSD
    struct MContext @cname("mcontext") {
        ulong[32] __gregs;  // X0–X30, SP (index 31)
        ulong     __gregs_pc;
        ulong     __gregs_spsr;
        char[512] __fpregs; // FP/SIMD state
        ulong     __flags;
    }

module c::ucontext @if(env::NETBSD);

import c::signal;

// Full user context — NetBSD
struct UContext @cname("ucontext") {
    uint        uc_flags;    // UC_* flags below
    UContext*   uc_link;
    signal::SigSet  uc_sigmask;
    signal::Stack   uc_stack;
    MContext    uc_mcontext;
    long[4]     __uc_pad;
}

// uc_flags values
const uint UC_SIGMASK  = 0x01; // uc_sigmask is valid
const uint UC_STACK    = 0x02; // uc_stack is valid
const uint UC_CPU      = 0x04; // uc_mcontext GP regs are valid
const uint UC_FPU      = 0x08; // uc_mcontext FP regs are valid
const uint UC_ALL      = (UC_SIGMASK | UC_STACK | UC_CPU | UC_FPU);



module c::ucontext @if(env::OPENBSD && env::X86_64);

    // Machine context — x86-64 OpenBSD
    struct SigContext @cname("sigcontext") {
        ulong sc_rdi;
        ulong sc_rsi;
        ulong sc_rdx;
        ulong sc_rcx;
        ulong sc_r8;
        ulong sc_r9;
        ulong sc_r10;
        ulong sc_r11;
        ulong sc_r12;
        ulong sc_r13;
        ulong sc_r14;
        ulong sc_r15;
        ulong sc_rbp;
        ulong sc_rbx;
        ulong sc_rax;
        ulong sc_gs;
        ulong sc_fs;
        ulong sc_es;
        ulong sc_ds;
        ulong sc_trapno;
        ulong sc_err;
        ulong sc_rip;
        ulong sc_cs;
        ulong sc_rflags;
        ulong sc_rsp;
        ulong sc_ss;
        char* sc_fpstate;  // Pointer to FP save area
        int   __sc_unused;
        int   sc_mask;
    }

    alias MContext = SigContext;

module c::ucontext @if(env::OPENBSD && env::AARCH64);

    // Machine context — aarch64 OpenBSD
    struct SigContext @cname("sigcontext") {
        ulong       sc_cookie;
        ulong       sc_mask;
        ulong       sc_spsr;
        ulong       sc_lr;
        ulong       sc_elr;
        ulong       sc_sp;
        ulong[30]   sc_x;    // X0–X29
        char[272]   sc_fpregs; // FP/SIMD state
    }

    alias MContext = SigContext;

module c::ucontext @if(env::OPENBSD);

import c::signal;

// Full user context — OpenBSD
// Note: OpenBSD uses sc_mask inside SigContext instead of a separate uc_sigmask.
struct UContext @cname("ucontext") {
    int         uc_flags;    // Reserved (must be 0)
    UContext*   uc_link;
    signal::SigSet  uc_sigmask;
    signal::Stack   uc_stack;
    MContext    uc_mcontext;
}
