// signal.h.c3

module c::signal @if(!env::WIN32);

// Common signal handling type
alias SigHandler = fn void(int);

// Special handler values (compared against signal() return value)
const uptr SIG_DFL = 0;        // Default signal action
const uptr SIG_IGN = 1;        // Ignore signal
const uptr SIG_ERR = uptr::max; // Error return from signal()

// Basic signal functions
extern fn SigHandler signal(int signum, SigHandler handler);
extern fn int raise(int sig);
extern fn int kill(int pid, int sig);

// Signal set manipulation
extern fn int sigemptyset(SigSet* set);
extern fn int sigfillset(SigSet* set);
extern fn int sigaddset(SigSet* set, int signum);
extern fn int sigdelset(SigSet* set, int signum);
extern fn int sigismember(SigSet* set, int signum);

// Signal mask and actions
extern fn int sigprocmask(int how, SigSet* set, SigSet* oldset);
extern fn int sigaction(int signum, SigAction* act, SigAction* oldact);
extern fn int sigpending(SigSet* set);
extern fn int sigsuspend(SigSet* mask);

// Signal waiting
extern fn int sigwait(SigSet* set, int* sig);
extern fn int sigwaitinfo(SigSet* set, SigInfo* info);
extern fn int sigtimedwait(SigSet* set, SigInfo* info, TimeSpec* timeout);

// Alternate signal stack
extern fn int sigaltstack(Stack* ss, Stack* old_ss);

// Signal interruption
extern fn int siginterrupt(int sig, int flag);

// Thread signal functions
extern fn int pthread_sigmask(int how, SigSet* set, SigSet* oldset);
extern fn int pthread_kill(void* thread, int sig);

// Signal queue (realtime)
extern fn int sigqueue(int pid, int sig, SigVal value);

// Alarm and pause
extern fn uint alarm(uint seconds);
extern fn int pause();

// Signal description
extern fn char* strsignal(int sig);
extern fn void psignal(int sig, char* s);
extern fn void psiginfo(SigInfo* pinfo, char* s);

alias Time = long; // time_t

union SigVal {
    int   sival_int;    // Integer value
    void *sival_ptr;    // Pointer value
}

struct TimeSpec {
    Time tv_sec;   // Seconds
    long   tv_nsec;  // Nanoseconds (0-999,999,999)
}




module c::signal @if(env::LINUX);

// sigprocmask / pthread_sigmask how argument
const int SIG_BLOCK   = 0; // Block signals in set
const int SIG_UNBLOCK = 1; // Unblock signals in set
const int SIG_SETMASK = 2; // Set signal mask to set

// Linux signal numbers
const int SIGHUP = 1;     // Hangup
const int SIGINT = 2;     // Interrupt
const int SIGQUIT = 3;    // Quit
const int SIGILL = 4;     // Illegal instruction
const int SIGTRAP = 5;    // Trace trap
const int SIGABRT = 6;    // Abort
const int SIGIOT = 6;     // IOT trap (same as SIGABRT)
const int SIGBUS = 7;     // BUS error
const int SIGFPE = 8;     // Floating-point exception
const int SIGKILL = 9;    // Kill (cannot be caught or ignored)
const int SIGUSR1 = 10;   // User-defined signal 1
const int SIGSEGV = 11;   // Segmentation violation
const int SIGUSR2 = 12;   // User-defined signal 2
const int SIGPIPE = 13;   // Broken pipe
const int SIGALRM = 14;   // Alarm clock
const int SIGTERM = 15;   // Termination
const int SIGSTKFLT = 16; // Stack fault
const int SIGCHLD = 17;   // Child status changed
const int SIGCONT = 18;   // Continue
const int SIGSTOP = 19;   // Stop (cannot be caught or ignored)
const int SIGTSTP = 20;   // Keyboard stop
const int SIGTTIN = 21;   // Background read from tty
const int SIGTTOU = 22;   // Background write to tty
const int SIGURG = 23;    // Urgent condition on socket
const int SIGXCPU = 24;   // CPU limit exceeded
const int SIGXFSZ = 25;   // File size limit exceeded
const int SIGVTALRM = 26; // Virtual alarm clock
const int SIGPROF = 27;   // Profiling alarm clock
const int SIGWINCH = 28;  // Window size change
const int SIGIO = 29;     // I/O now possible
const int SIGPOLL = 29;   // Pollable event (same as SIGIO)
const int SIGPWR = 30;    // Power failure restart
const int SIGSYS = 31;    // Bad system call
const int SIGUNUSED = 31; // Same as SIGSYS

// Real-time signals
const int SIGRTMIN = 32;
const int SIGRTMAX = 64;

// Number of signals
const int NSIG = 65;
const int _NSIG = 65;

// Signal action flags (Linux-specific values)
const int SA_NOCLDSTOP = 0x00000001;
const int SA_NOCLDWAIT = 0x00000002;
const int SA_SIGINFO = 0x00000004;
const int SA_ONSTACK = 0x08000000;
const int SA_RESTART = 0x10000000;
const int SA_NODEFER = 0x40000000;
const uint SA_RESETHAND = 0x80000000;
const int SA_INTERRUPT = 0x20000000;
const int SA_RESTORER = 0x04000000;

// siginfo_t codes
const int SI_USER = 0;      // Sent by kill, sigsend, raise
const int SI_KERNEL = 0x80; // Sent by the kernel
const int SI_QUEUE = -1;    // Sent by sigqueue
const int SI_TIMER = -2;    // Sent by timer expiration
const int SI_MESGQ = -3;    // Sent by real-time mesq state change
const int SI_ASYNCIO = -4;  // Sent by AIO completion
const int SI_SIGIO = -5;    // Sent by queued SIGIO
const int SI_TKILL = -6;    // Sent by tkill system call

// SIGILL codes
const int ILL_ILLOPC = 1;  // Illegal opcode
const int ILL_ILLOPN = 2;  // Illegal operand
const int ILL_ILLADR = 3;  // Illegal addressing mode
const int ILL_ILLTRP = 4;  // Illegal trap
const int ILL_PRVOPC = 5;  // Privileged opcode
const int ILL_PRVREG = 6;  // Privileged register
const int ILL_COPROC = 7;  // Coprocessor error
const int ILL_BADSTK = 8;  // Internal stack error

// SIGFPE codes
const int FPE_INTDIV = 1;  // Integer divide by zero
const int FPE_INTOVF = 2;  // Integer overflow
const int FPE_FLTDIV = 3;  // Floating point divide by zero
const int FPE_FLTOVF = 4;  // Floating point overflow
const int FPE_FLTUND = 5;  // Floating point underflow
const int FPE_FLTRES = 6;  // Floating point inexact result
const int FPE_FLTINV = 7;  // Floating point invalid operation
const int FPE_FLTSUB = 8;  // Subscript out of range

// SIGSEGV codes
const int SEGV_MAPERR = 1; // Address not mapped to object
const int SEGV_ACCERR = 2; // Invalid permissions for mapped object

// SIGBUS codes
const int BUS_ADRALN = 1;  // Invalid address alignment
const int BUS_ADRERR = 2;  // Non-existent physical address
const int BUS_OBJERR = 3;  // Object specific hardware error

// SIGTRAP codes
const int TRAP_BRKPT = 1;  // Process breakpoint
const int TRAP_TRACE = 2;  // Process trace trap

// SIGCHLD codes
const int CLD_EXITED = 1;    // Child has exited
const int CLD_KILLED = 2;    // Child was killed
const int CLD_DUMPED = 3;    // Child terminated abnormally
const int CLD_TRAPPED = 4;   // Traced child has trapped
const int CLD_STOPPED = 5;   // Child has stopped
const int CLD_CONTINUED = 6; // Stopped child has continued

// SIGPOLL codes
const int POLL_IN = 1;  // Data input available
const int POLL_OUT = 2; // Output buffers available
const int POLL_MSG = 3; // Input message available
const int POLL_ERR = 4; // I/O error
const int POLL_PRI = 5; // High priority input available
const int POLL_HUP = 6; // Device disconnected

// Signal set type
struct SigSet {
    char[128] __val;  // 128 bytes for signal mask
}

alias SigFn = fn void(int, SigInfo*, void*);
alias Restfn = fn void();
// Signal action structure
struct SigAction {
    union {
        SigHandler sa_handler;
        SigFn sa_sigaction;
    }
    SigSet sa_mask;
    int sa_flags;
    Restfn sa_restorer;
}

// Signal info structure
struct SigInfo {
    int si_signo;
    int si_errno;
    int si_code;
    union {
        int[28] _pad;
        struct {
            int si_pid;
            uint si_uid;
        }
        struct {
            int si_tid;
            int si_overrun;
            SigVal si_sigval;
        }
        struct {
            int si_pid2;
            uint si_uid2;
            int si_status;
            long si_utime;
            long si_stime;
        }
        struct {
            void* si_addr;
            short si_addr_lsb;
        }
        struct {
            long si_band;
            int si_fd;
        }
    }
}

// Stack structure
struct Stack {
    void* ss_sp;
    int ss_flags;
    sz ss_size;
}

// Stack flags
const int SS_ONSTACK = 1;
const int SS_DISABLE = 2;
const int MINSIGSTKSZ = 2048;
const int SIGSTKSZ = 8192;

alias Eventfn = fn void(SigVal);
// Signal event structure (for timers)
struct SigEvent {
    SigVal sigev_value;
    int sigev_signo;
    int sigev_notify;
    union {
        int[12] _pad;
        struct {
            Eventfn sigev_notify_function;
            void* sigev_notify_attributes;
        }
        int _tid;
    }
}

const int SIGEV_SIGNAL = 0;
const int SIGEV_NONE = 1;
const int SIGEV_THREAD = 2;
const int SIGEV_THREAD_ID = 4;



module c::signal @if(env::DARWIN);

// sigprocmask / pthread_sigmask how argument
const int SIG_BLOCK   = 1; // Block signals in set
const int SIG_UNBLOCK = 2; // Unblock signals in set
const int SIG_SETMASK = 3; // Set signal mask to set

// macOS/Darwin signal numbers
const int SIGHUP = 1;
const int SIGINT = 2;
const int SIGQUIT = 3;
const int SIGILL = 4;
const int SIGTRAP = 5;
const int SIGABRT = 6;
const int SIGIOT = 6;
const int SIGEMT = 7;
const int SIGFPE = 8;
const int SIGKILL = 9;
const int SIGBUS = 10;
const int SIGSEGV = 11;
const int SIGSYS = 12;
const int SIGPIPE = 13;
const int SIGALRM = 14;
const int SIGTERM = 15;
const int SIGURG = 16;
const int SIGSTOP = 17;
const int SIGTSTP = 18;
const int SIGCONT = 19;
const int SIGCHLD = 20;
const int SIGTTIN = 21;
const int SIGTTOU = 22;
const int SIGIO = 23;
const int SIGXCPU = 24;
const int SIGXFSZ = 25;
const int SIGVTALRM = 26;
const int SIGPROF = 27;
const int SIGWINCH = 28;
const int SIGINFO = 29;
const int SIGUSR1 = 30;
const int SIGUSR2 = 31;

const int NSIG = 32;

// Signal action flags (Darwin-specific values)
const int SA_ONSTACK = 0x0001;
const int SA_RESTART = 0x0002;
const int SA_RESETHAND = 0x0004;
const int SA_NOCLDSTOP = 0x0008;
const int SA_NODEFER = 0x0010;
const int SA_NOCLDWAIT = 0x0020;
const int SA_SIGINFO = 0x0040;
const int SA_USERTRAMP = 0x0100;
const int SA_64REGSET = 0x0200;

// siginfo_t codes
const int SI_USER = 0x10001;
const int SI_QUEUE = 0x10002;
const int SI_TIMER = 0x10003;
const int SI_ASYNCIO = 0x10004;
const int SI_MESGQ = 0x10005;

// SIGILL codes
const int ILL_ILLOPC = 1;
const int ILL_ILLTRP = 2;
const int ILL_PRVOPC = 3;
const int ILL_ILLOPN = 4;
const int ILL_ILLADR = 5;
const int ILL_PRVREG = 6;
const int ILL_COPROC = 7;
const int ILL_BADSTK = 8;

// SIGFPE codes
const int FPE_INTDIV = 7;
const int FPE_INTOVF = 8;
const int FPE_FLTDIV = 1;
const int FPE_FLTOVF = 2;
const int FPE_FLTUND = 3;
const int FPE_FLTRES = 4;
const int FPE_FLTINV = 5;
const int FPE_FLTSUB = 6;

// SIGSEGV codes
const int SEGV_MAPERR = 1;
const int SEGV_ACCERR = 2;

// SIGBUS codes
const int BUS_ADRALN = 1;
const int BUS_ADRERR = 2;
const int BUS_OBJERR = 3;

// SIGTRAP codes
const int TRAP_BRKPT = 1;
const int TRAP_TRACE = 2;

// SIGCHLD codes
const int CLD_EXITED = 1;
const int CLD_KILLED = 2;
const int CLD_DUMPED = 3;
const int CLD_TRAPPED = 4;
const int CLD_STOPPED = 5;
const int CLD_CONTINUED = 6;

// Signal set type (Darwin uses 32-bit mask)
struct SigSet {
    uint __bits;
}

alias SigFn = fn void(int, SigInfo*, void*);
// Signal action structure
struct SigAction {
    union {
        SigHandler sa_handler;
        SigFn sa_sigaction;
    }
    SigSet sa_mask;
    int sa_flags;
}

// Signal info structure (Darwin)
struct SigInfo {
    int si_signo;
    int si_errno;
    int si_code;
    int si_pid;
    uint si_uid;
    int si_status;
    void* si_addr;
    SigVal si_value;
    long si_band;
    ulong[7] __pad;
}

// Stack structure
struct Stack {
    void* ss_sp;
    sz ss_size;
    int ss_flags;
}

// Stack flags
const int SS_ONSTACK = 0x0001;
const int SS_DISABLE = 0x0004;
const int MINSIGSTKSZ = 32768;
const int SIGSTKSZ = 131072;

alias Evfn = fn void(SigVal);
// Signal event structure
struct SigEvent {
    int sigev_notify;
    int sigev_signo;
    SigVal sigev_value;
    Evfn sigev_notify_function;
    void* sigev_notify_attributes;
}

const int SIGEV_NONE = 0;
const int SIGEV_SIGNAL = 1;
const int SIGEV_THREAD = 3;



module c::signal @if(env::FREEBSD);

// sigprocmask / pthread_sigmask how argument
const int SIG_BLOCK   = 1; // Block signals in set
const int SIG_UNBLOCK = 2; // Unblock signals in set
const int SIG_SETMASK = 3; // Set signal mask to set

// FreeBSD signal numbers
const int SIGHUP = 1;
const int SIGINT = 2;
const int SIGQUIT = 3;
const int SIGILL = 4;
const int SIGTRAP = 5;
const int SIGABRT = 6;
const int SIGIOT = 6;
const int SIGEMT = 7;
const int SIGFPE = 8;
const int SIGKILL = 9;
const int SIGBUS = 10;
const int SIGSEGV = 11;
const int SIGSYS = 12;
const int SIGPIPE = 13;
const int SIGALRM = 14;
const int SIGTERM = 15;
const int SIGURG = 16;
const int SIGSTOP = 17;
const int SIGTSTP = 18;
const int SIGCONT = 19;
const int SIGCHLD = 20;
const int SIGTTIN = 21;
const int SIGTTOU = 22;
const int SIGIO = 23;
const int SIGXCPU = 24;
const int SIGXFSZ = 25;
const int SIGVTALRM = 26;
const int SIGPROF = 27;
const int SIGWINCH = 28;
const int SIGINFO = 29;
const int SIGUSR1 = 30;
const int SIGUSR2 = 31;
const int SIGTHR = 32;
const int SIGLWP = 32;

// Real-time signals
const int SIGRTMIN = 65;
const int SIGRTMAX = 126;

const int NSIG = 128;

// Signal action flags
const int SA_ONSTACK = 0x0001;
const int SA_RESTART = 0x0002;
const int SA_RESETHAND = 0x0004;
const int SA_NODEFER = 0x0010;
const int SA_NOCLDWAIT = 0x0020;
const int SA_SIGINFO = 0x0040;
const int SA_NOCLDSTOP = 0x0008;

// siginfo_t codes
const int SI_USER = 0x10001;
const int SI_QUEUE = 0x10002;
const int SI_TIMER = 0x10003;
const int SI_ASYNCIO = 0x10004;
const int SI_MESGQ = 0x10005;
const int SI_KERNEL = 0x10006;
const int SI_LWP = 0x10007;

// SIGILL codes
const int ILL_ILLOPC = 1;
const int ILL_ILLOPN = 2;
const int ILL_ILLADR = 3;
const int ILL_ILLTRP = 4;
const int ILL_PRVOPC = 5;
const int ILL_PRVREG = 6;
const int ILL_COPROC = 7;
const int ILL_BADSTK = 8;

// SIGFPE codes
const int FPE_INTOVF = 1;
const int FPE_INTDIV = 2;
const int FPE_FLTDIV = 3;
const int FPE_FLTOVF = 4;
const int FPE_FLTUND = 5;
const int FPE_FLTRES = 6;
const int FPE_FLTINV = 7;
const int FPE_FLTSUB = 8;

// SIGSEGV codes
const int SEGV_MAPERR = 1;
const int SEGV_ACCERR = 2;

// SIGBUS codes
const int BUS_ADRALN = 1;
const int BUS_ADRERR = 2;
const int BUS_OBJERR = 3;

// SIGTRAP codes
const int TRAP_BRKPT = 1;
const int TRAP_TRACE = 2;

// SIGCHLD codes
const int CLD_EXITED = 1;
const int CLD_KILLED = 2;
const int CLD_DUMPED = 3;
const int CLD_TRAPPED = 4;
const int CLD_STOPPED = 5;
const int CLD_CONTINUED = 6;

// Signal set type
struct SigSet {
    uint[4] __bits;
}

alias SigFn = fn void(int, SigInfo*, void*);
// Signal action structure
struct SigAction {
    union {
        SigHandler sa_handler;
        SigFn sa_sigaction;
    }
    int sa_flags;
    SigSet sa_mask;
}

// Signal info structure
struct SigInfo {
    int si_signo;
    int si_errno;
    int si_code;
    int si_pid;
    uint si_uid;
    int si_status;
    void* si_addr;
    SigVal si_value;
    union {
        struct {
            int _trapno;
        }
        struct {
            int _timerid;
            int _overrun;
        }
        struct {
            int _mqd;
        }
        struct {
            long _band;
        }
        struct {
            int _syscall;
        }
        int[7] __spare__;
    }
}

// Stack structure
struct Stack {
    void* ss_sp;
    sz ss_size;
    int ss_flags;
}

// Stack flags
const int SS_ONSTACK = 0x0001;
const int SS_DISABLE = 0x0004;
const int MINSIGSTKSZ = 2048;
const int SIGSTKSZ = (MINSIGSTKSZ + 32768);

alias Evfn = fn void(SigVal);
// Signal event structure
struct SigEvent {
    int sigev_notify;
    int sigev_signo;
    SigVal sigev_value;
    union {
        int _threadid;
        struct {
            Evfn _function;
            void* _attribute;
        }
        long[8] __spare__;
    }
}

const int SIGEV_NONE = 0;
const int SIGEV_SIGNAL = 1;
const int SIGEV_THREAD = 2;
const int SIGEV_KEVENT = 3;
const int SIGEV_THREAD_ID = 4;



module c::signal @if(env::NETBSD);

// sigprocmask / pthread_sigmask how argument
const int SIG_BLOCK   = 1; // Block signals in set
const int SIG_UNBLOCK = 2; // Unblock signals in set
const int SIG_SETMASK = 3; // Set signal mask to set

// NetBSD signal numbers
const int SIGHUP = 1;
const int SIGINT = 2;
const int SIGQUIT = 3;
const int SIGILL = 4;
const int SIGTRAP = 5;
const int SIGABRT = 6;
const int SIGIOT = 6;
const int SIGEMT = 7;
const int SIGFPE = 8;
const int SIGKILL = 9;
const int SIGBUS = 10;
const int SIGSEGV = 11;
const int SIGSYS = 12;
const int SIGPIPE = 13;
const int SIGALRM = 14;
const int SIGTERM = 15;
const int SIGURG = 16;
const int SIGSTOP = 17;
const int SIGTSTP = 18;
const int SIGCONT = 19;
const int SIGCHLD = 20;
const int SIGTTIN = 21;
const int SIGTTOU = 22;
const int SIGIO = 23;
const int SIGXCPU = 24;
const int SIGXFSZ = 25;
const int SIGVTALRM = 26;
const int SIGPROF = 27;
const int SIGWINCH = 28;
const int SIGINFO = 29;
const int SIGUSR1 = 30;
const int SIGUSR2 = 31;
const int SIGPWR = 32;

// Real-time signals
const int SIGRTMIN = 33;
const int SIGRTMAX = 63;

const int NSIG = 64;

// Signal action flags
const int SA_ONSTACK = 0x0001;
const int SA_RESTART = 0x0002;
const int SA_RESETHAND = 0x0004;
const int SA_NOCLDSTOP = 0x0008;
const int SA_NODEFER = 0x0010;
const int SA_NOCLDWAIT = 0x0020;
const int SA_SIGINFO = 0x0040;

// siginfo_t codes
const int SI_USER = 0;
const int SI_QUEUE = -1;
const int SI_TIMER = -2;
const int SI_ASYNCIO = -3;
const int SI_MESGQ = -4;

// SIGILL codes
const int ILL_ILLOPC = 1;
const int ILL_ILLOPN = 2;
const int ILL_ILLADR = 3;
const int ILL_ILLTRP = 4;
const int ILL_PRVOPC = 5;
const int ILL_PRVREG = 6;
const int ILL_COPROC = 7;
const int ILL_BADSTK = 8;

// SIGFPE codes
const int FPE_INTDIV = 1;
const int FPE_INTOVF = 2;
const int FPE_FLTDIV = 3;
const int FPE_FLTOVF = 4;
const int FPE_FLTUND = 5;
const int FPE_FLTRES = 6;
const int FPE_FLTINV = 7;
const int FPE_FLTSUB = 8;

// SIGSEGV codes
const int SEGV_MAPERR = 1;
const int SEGV_ACCERR = 2;

// SIGBUS codes
const int BUS_ADRALN = 1;
const int BUS_ADRERR = 2;
const int BUS_OBJERR = 3;

// SIGTRAP codes
const int TRAP_BRKPT = 1;
const int TRAP_TRACE = 2;

// SIGCHLD codes
const int CLD_EXITED = 1;
const int CLD_KILLED = 2;
const int CLD_DUMPED = 3;
const int CLD_TRAPPED = 4;
const int CLD_STOPPED = 5;
const int CLD_CONTINUED = 6;

// Signal set type
struct SigSet {
    uint[4] __bits;
}

alias SigFn = fn void(int, SigInfo*, void*);
// Signal action structure
struct SigAction {
    union {
        SigHandler sa_handler;
        SigFn sa_sigaction;
    }
    SigSet sa_mask;
    int sa_flags;
}

// Signal info structure
struct SigInfo {
    int si_signo;
    int si_code;
    int si_errno;
    union {
        int[24] _pad;
        struct {
            int _pid;
            uint _uid;
            SigVal _value;
        }
        struct {
            int _pid2;
            uint _uid2;
            int _status;
            long _utime;
            long _stime;
        }
        struct {
            void* _addr;
            int _trap;
        }
        struct {
            long _band;
            int _fd;
        }
    }
}

// Stack structure
struct Stack {
    void* ss_sp;
    sz ss_size;
    int ss_flags;
}

// Stack flags
const int SS_ONSTACK = 0x0001;
const int SS_DISABLE = 0x0004;
const int MINSIGSTKSZ = 8192;
const int SIGSTKSZ = (MINSIGSTKSZ + 32768);

alias Eventfn = fn void(SigVal);
// Signal event structure
struct SigEvent {
    int sigev_notify;
    int sigev_signo;
    SigVal sigev_value;
    Eventfn sigev_notify_function;
    void* sigev_notify_attributes;
}

const int SIGEV_NONE = 0;
const int SIGEV_SIGNAL = 1;
const int SIGEV_THREAD = 2;



module c::signal @if(env::OPENBSD);

// sigprocmask / pthread_sigmask how argument
const int SIG_BLOCK   = 1; // Block signals in set
const int SIG_UNBLOCK = 2; // Unblock signals in set
const int SIG_SETMASK = 3; // Set signal mask to set

// OpenBSD signal numbers
const int SIGHUP = 1;
const int SIGINT = 2;
const int SIGQUIT = 3;
const int SIGILL = 4;
const int SIGTRAP = 5;
const int SIGABRT = 6;
const int SIGIOT = 6;
const int SIGEMT = 7;
const int SIGFPE = 8;
const int SIGKILL = 9;
const int SIGBUS = 10;
const int SIGSEGV = 11;
const int SIGSYS = 12;
const int SIGPIPE = 13;
const int SIGALRM = 14;
const int SIGTERM = 15;
const int SIGURG = 16;
const int SIGSTOP = 17;
const int SIGTSTP = 18;
const int SIGCONT = 19;
const int SIGCHLD = 20;
const int SIGTTIN = 21;
const int SIGTTOU = 22;
const int SIGIO = 23;
const int SIGXCPU = 24;
const int SIGXFSZ = 25;
const int SIGVTALRM = 26;
const int SIGPROF = 27;
const int SIGWINCH = 28;
const int SIGINFO = 29;
const int SIGUSR1 = 30;
const int SIGUSR2 = 31;
const int SIGTHR = 32;

const int NSIG = 33;

// Signal action flags
const int SA_ONSTACK = 0x0001;
const int SA_RESTART = 0x0002;
const int SA_RESETHAND = 0x0004;
const int SA_NOCLDSTOP = 0x0008;
const int SA_NODEFER = 0x0010;
const int SA_NOCLDWAIT = 0x0020;
const int SA_SIGINFO = 0x0040;

// siginfo_t codes
const int SI_USER = 0;
const int SI_LWP = -1;
const int SI_QUEUE = -2;
const int SI_TIMER = -3;

// SIGILL codes
const int ILL_ILLOPC = 1;
const int ILL_ILLOPN = 2;
const int ILL_ILLADR = 3;
const int ILL_ILLTRP = 4;
const int ILL_PRVOPC = 5;
const int ILL_PRVREG = 6;
const int ILL_COPROC = 7;
const int ILL_BADSTK = 8;

// SIGFPE codes
const int FPE_INTDIV = 1;
const int FPE_INTOVF = 2;
const int FPE_FLTDIV = 3;
const int FPE_FLTOVF = 4;
const int FPE_FLTUND = 5;
const int FPE_FLTRES = 6;
const int FPE_FLTINV = 7;
const int FPE_FLTSUB = 8;

// SIGSEGV codes
const int SEGV_MAPERR = 1;
const int SEGV_ACCERR = 2;

// SIGBUS codes
const int BUS_ADRALN = 1;
const int BUS_ADRERR = 2;
const int BUS_OBJERR = 3;

// SIGTRAP codes
const int TRAP_BRKPT = 1;
const int TRAP_TRACE = 2;

// SIGCHLD codes
const int CLD_EXITED = 1;
const int CLD_KILLED = 2;
const int CLD_DUMPED = 3;
const int CLD_TRAPPED = 4;
const int CLD_STOPPED = 5;
const int CLD_CONTINUED = 6;

// Signal set type
struct SigSet {
    uint __bits;
}

alias SigFn = fn void(int, SigInfo*, void*);
// Signal action structure
struct SigAction {
    union {
        SigHandler sa_handler;
        SigFn sa_sigaction;
    }
    SigSet sa_mask;
    int sa_flags;
}

// Signal info structure
struct SigInfo {
    int si_signo;
    int si_code;
    int si_errno;
    union {
        int[29] _pad;
        struct {
            int _pid;
            union {
                struct {
                    uint _uid;
                    SigVal _value;
                }
                struct {
                    long _utime;
                    int _status;
                    long _stime;
                }
            }
        }
        struct {
            void* _addr;
            int _trapno;
        }
        struct {
            long _band;
            int _fd;
        }
    }
}

// Stack structure
struct Stack {
    void* ss_sp;
    sz ss_size;
    int ss_flags;
}

// Stack flags
const int SS_ONSTACK = 0x0001;
const int SS_DISABLE = 0x0004;
const int MINSIGSTKSZ = 12288;
const int SIGSTKSZ = (MINSIGSTKSZ + 32768);

