// process.h.c3

module c::process;

// ========== Linux ==========

module c::process @if(env::LINUX);

// Linux does not have process.h
// Process-related functions are in unistd.h and sys/wait.h
//
// For process operations on Linux, use:
// - unistd module for fork(), exec*(), getpid(), etc.
// - sys::wait module for wait(), waitpid(), etc.
// - stdlib module for exit(), abort(), system(), etc.

// Common functions available through other headers:
// - fork() - unistd.h
// - exec*() family - unistd.h
// - wait(), waitpid() - sys/wait.h
// - getpid(), getppid() - unistd.h
// - exit(), _exit() - stdlib.h, unistd.h
// - system() - stdlib.h

// ========== Darwin (macOS) ==========

module c::process @if(env::DARWIN);

// macOS does not have process.h
// Use unistd.h and sys/wait.h instead

// ========== FreeBSD ==========

module c::process @if(env::FREEBSD);

// FreeBSD does not have process.h
// Use unistd.h and sys/wait.h instead

// ========== NetBSD ==========

module c::process @if(env::NETBSD);

// NetBSD does not have process.h
// Use unistd.h and sys/wait.h instead

// ========== OpenBSD ==========

module c::process @if(env::OPENBSD);

// OpenBSD does not have process.h
// Use unistd.h and sys/wait.h instead

// ========== Windows ==========

module c::process @if(env::WIN32);

// Process creation - spawn family
extern fn iptr _spawnl(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnle(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnlp(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnlpe(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnv(int mode, char* cmdname, char** argv);
extern fn iptr _spawnve(int mode, char* cmdname, char** argv, char** envp);
extern fn iptr _spawnvp(int mode, char* cmdname, char** argv);
extern fn iptr _spawnvpe(int mode, char* cmdname, char** argv, char** envp);

// Wide character spawn functions
extern fn iptr _wspawnl(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnle(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnlp(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnlpe(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnv(int mode, ushort* cmdname, ushort** argv);
extern fn iptr _wspawnve(int mode, ushort* cmdname, ushort** argv, ushort** envp);
extern fn iptr _wspawnvp(int mode, ushort* cmdname, ushort** argv);
extern fn iptr _wspawnvpe(int mode, ushort* cmdname, ushort** argv, ushort** envp);

// Process execution - exec family
extern fn iptr _execl(char* cmdname, char* arg0, ...);
extern fn iptr _execle(char* cmdname, char* arg0, ...);
extern fn iptr _execlp(char* cmdname, char* arg0, ...);
extern fn iptr _execlpe(char* cmdname, char* arg0, ...);
extern fn iptr _execv(char* cmdname, char** argv);
extern fn iptr _execve(char* cmdname, char** argv, char** envp);
extern fn iptr _execvp(char* cmdname, char** argv);
extern fn iptr _execvpe(char* cmdname, char** argv, char** envp);

// Wide character exec functions
extern fn iptr _wexecl(ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wexecle(ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wexeclp(ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wexeclpe(ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wexecv(ushort* cmdname, ushort** argv);
extern fn iptr _wexecve(ushort* cmdname, ushort** argv, ushort** envp);
extern fn iptr _wexecvp(ushort* cmdname, ushort** argv);
extern fn iptr _wexecvpe(ushort* cmdname, ushort** argv, ushort** envp);

// Process control
extern fn void exit(int status);
extern fn void _exit(int status);
extern fn void abort();
extern fn int atexit(void* func);
extern fn int _onexit(void* func);

// Process information
extern fn int _getpid();
extern fn iptr _cwait(int* termstat, iptr procHandle, int action);

// System command
extern fn int system(char* command);
extern fn int _wsystem(ushort* command);

// Environment
extern fn char* getenv(char* varname);
extern fn ushort* _wgetenv(ushort* varname);
extern fn int _putenv(char* envstring);
extern fn int _wputenv(ushort* envstring);
extern fn int _putenv_s(char* varname, char* value);
extern fn int _wputenv_s(ushort* varname, ushort* value);
extern fn void _searchenv(char* filename, char* varname, char* pathname);
extern fn void _wsearchenv(ushort* filename, ushort* varname, ushort* pathname);
extern fn int _searchenv_s(char* filename, char* varname, char* pathname, sz sizeInBytes);
extern fn int _wsearchenv_s(ushort* filename, ushort* varname, ushort* pathname, sz sizeInWords);

// Spawn/Exec modes
const int _P_WAIT = 0;          // Suspend parent until child completes
const int _P_NOWAIT = 1;        // Continue parent, child runs concurrently
const int _P_OVERLAY = 2;       // Overlay parent (same as exec)
const int _P_NOWAITO = 3;       // Continue parent, no wait
const int _P_DETACH = 4;        // Background, no access to console/keyboard

// Compatibility aliases (without underscore)
const int P_WAIT = _P_WAIT;
const int P_NOWAIT = _P_NOWAIT;
const int P_OVERLAY = _P_OVERLAY;
const int P_NOWAITO = _P_NOWAITO;
const int P_DETACH = _P_DETACH;

// cwait action flags
const int _WAIT_CHILD = 0;
const int _WAIT_GRANDCHILD = 1;

const int WAIT_CHILD = _WAIT_CHILD;
const int WAIT_GRANDCHILD = _WAIT_GRANDCHILD;

// Exit status codes
const int EXIT_SUCCESS = 0;
const int EXIT_FAILURE = 1;

// Deprecated POSIX compatibility functions
extern fn iptr spawnl(int mode, char* cmdname, char* arg0, ...) @cname("_spawnl");
extern fn iptr spawnle(int mode, char* cmdname, char* arg0, ...) @cname("_spawnle");
extern fn iptr spawnlp(int mode, char* cmdname, char* arg0, ...) @cname("_spawnlp");
extern fn iptr spawnlpe(int mode, char* cmdname, char* arg0, ...) @cname("_spawnlpe");
extern fn iptr spawnv(int mode, char* cmdname, char** argv) @cname("_spawnv");
extern fn iptr spawnve(int mode, char* cmdname, char** argv, char** envp) @cname("_spawnve");
extern fn iptr spawnvp(int mode, char* cmdname, char** argv) @cname("_spawnvp");
extern fn iptr spawnvpe(int mode, char* cmdname, char** argv, char** envp) @cname("_spawnvpe");

extern fn iptr execl(char* cmdname, char* arg0, ...) @cname("_execl");
extern fn iptr execle(char* cmdname, char* arg0, ...) @cname("_execle");
extern fn iptr execlp(char* cmdname, char* arg0, ...) @cname("_execlp");
extern fn iptr execlpe(char* cmdname, char* arg0, ...) @cname("_execlpe");
extern fn iptr execv(char* cmdname, char** argv) @cname("_execv");
extern fn iptr execve(char* cmdname, char** argv, char** envp) @cname("_execve");
extern fn iptr execvp(char* cmdname, char** argv) @cname("_execvp");
extern fn iptr execvpe(char* cmdname, char** argv, char** envp) @cname("_execvpe");

extern fn int getpid() @cname("_getpid");
extern fn iptr cwait(int* termstat, iptr procHandle, int action) @cname("_cwait");
