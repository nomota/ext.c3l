// fiber.config.c3

// Choose exactly one fiber backend at compile time.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber;

// Assembly backends.
const bool ASM_X86_64_SYSV = env::POSIX && env::X86_64;   // POSIX, x86-64 System V ABI
const bool ASM_X86_64_WIN64 = env::WIN32 && env::X86_64;  // Windows, x86-64 Win64 ABI
const bool ASM_AARCH64 = env::POSIX && env::AARCH64;      // POSIX, AArch64 ABI

// Portable POSIX backend.
const bool SJLJ = false;                                  // POSIX, sigsetjmp/siglongjmp

// POSIX/Linux backend.
const bool UCONTEXT = false;                              // POSIX, ucontext

// Windows native backend.
const bool WINFIBER = false;                              // Windows, Fiber API