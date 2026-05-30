// spawn.h.c3

module c::spawn;

// ========== Linux ==========

module c::spawn @if(env::LINUX);

// Opaque types
alias SpawnFileActions = void;
alias SpawnAttr = void;

// Function Declarations - spawn functions
extern fn int posix_spawn(int* pid, char* path, SpawnFileActions* file_actions, 
                         SpawnAttr* attrp, char** argv, char** envp);
extern fn int posix_spawnp(int* pid, char* file, SpawnFileActions* file_actions,
                          SpawnAttr* attrp, char** argv, char** envp);

// File actions functions
extern fn int posix_spawn_file_actions_init(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_destroy(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_addopen(SpawnFileActions* file_actions,
                                               int fd, char* path, int oflag, uint mode);
extern fn int posix_spawn_file_actions_addclose(SpawnFileActions* file_actions, int fd);
extern fn int posix_spawn_file_actions_adddup2(SpawnFileActions* file_actions,
                                               int fd, int newfd);
extern fn int posix_spawn_file_actions_addchdir_np(SpawnFileActions* file_actions, char* path);
extern fn int posix_spawn_file_actions_addfchdir_np(SpawnFileActions* file_actions, int fd);

// Spawn attributes functions
extern fn int posix_spawnattr_init(SpawnAttr* attr);
extern fn int posix_spawnattr_destroy(SpawnAttr* attr);
extern fn int posix_spawnattr_getflags(SpawnAttr* attr, short* flags);
extern fn int posix_spawnattr_setflags(SpawnAttr* attr, short flags);
extern fn int posix_spawnattr_getpgroup(SpawnAttr* attr, int* pgroup);
extern fn int posix_spawnattr_setpgroup(SpawnAttr* attr, int pgroup);
extern fn int posix_spawnattr_getschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_setschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_getschedpolicy(SpawnAttr* attr, int* schedpolicy);
extern fn int posix_spawnattr_setschedpolicy(SpawnAttr* attr, int schedpolicy);
extern fn int posix_spawnattr_getsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_setsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_getsigmask(SpawnAttr* attr, void* sigmask);
extern fn int posix_spawnattr_setsigmask(SpawnAttr* attr, void* sigmask);

// Flags for posix_spawnattr_setflags()
const short POSIX_SPAWN_RESETIDS = 0x01;           // Reset effective uid/gid
const short POSIX_SPAWN_SETPGROUP = 0x02;          // Set process group
const short POSIX_SPAWN_SETSIGDEF = 0x04;          // Set default signal actions
const short POSIX_SPAWN_SETSIGMASK = 0x08;         // Set signal mask
const short POSIX_SPAWN_SETSCHEDPARAM = 0x10;      // Set scheduling parameters
const short POSIX_SPAWN_SETSCHEDULER = 0x20;       // Set scheduler policy
const short POSIX_SPAWN_USEVFORK = 0x40;           // Use vfork() (Linux extension)
const short POSIX_SPAWN_SETSID = 0x80;             // Create new session (Linux extension)

// ========== Darwin (macOS) ==========

module c::spawn @if(env::DARWIN);

// Opaque types
alias SpawnFileActions = void;
alias SpawnAttr = void;

// Function Declarations
extern fn int posix_spawn(int* pid, char* path, SpawnFileActions* file_actions,
                         SpawnAttr* attrp, char** argv, char** envp);
extern fn int posix_spawnp(int* pid, char* file, SpawnFileActions* file_actions,
                          SpawnAttr* attrp, char** argv, char** envp);

// File actions functions
extern fn int posix_spawn_file_actions_init(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_destroy(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_addopen(SpawnFileActions* file_actions,
                                               int fd, char* path, int oflag, uint mode);
extern fn int posix_spawn_file_actions_addclose(SpawnFileActions* file_actions, int fd);
extern fn int posix_spawn_file_actions_adddup2(SpawnFileActions* file_actions,
                                               int fd, int newfd);
extern fn int posix_spawn_file_actions_addinherit_np(SpawnFileActions* file_actions, int fd);
extern fn int posix_spawn_file_actions_addchdir_np(SpawnFileActions* file_actions, char* path);
extern fn int posix_spawn_file_actions_addfchdir_np(SpawnFileActions* file_actions, int fd);

// Spawn attributes functions
extern fn int posix_spawnattr_init(SpawnAttr* attr);
extern fn int posix_spawnattr_destroy(SpawnAttr* attr);
extern fn int posix_spawnattr_getflags(SpawnAttr* attr, short* flags);
extern fn int posix_spawnattr_setflags(SpawnAttr* attr, short flags);
extern fn int posix_spawnattr_getpgroup(SpawnAttr* attr, int* pgroup);
extern fn int posix_spawnattr_setpgroup(SpawnAttr* attr, int pgroup);
extern fn int posix_spawnattr_getschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_setschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_getschedpolicy(SpawnAttr* attr, int* schedpolicy);
extern fn int posix_spawnattr_setschedpolicy(SpawnAttr* attr, int schedpolicy);
extern fn int posix_spawnattr_getsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_setsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_getsigmask(SpawnAttr* attr, void* sigmask);
extern fn int posix_spawnattr_setsigmask(SpawnAttr* attr, void* sigmask);

// macOS-specific attribute functions
extern fn int posix_spawnattr_setbinpref_np(SpawnAttr* attr, sz count, int* pref, sz* ocount);
extern fn int posix_spawnattr_getbinpref_np(SpawnAttr* attr, sz count, int* pref, sz* ocount);

// Flags
const short POSIX_SPAWN_RESETIDS = 0x0001;
const short POSIX_SPAWN_SETPGROUP = 0x0002;
const short POSIX_SPAWN_SETSIGDEF = 0x0004;
const short POSIX_SPAWN_SETSIGMASK = 0x0008;
const short POSIX_SPAWN_SETEXEC = 0x0040;            // macOS: exec instead of spawn
const short POSIX_SPAWN_START_SUSPENDED = 0x0080;    // macOS: start suspended
const short POSIX_SPAWN_CLOEXEC_DEFAULT = 0x4000;    // macOS: close-on-exec default

// CPU types for setbinpref_np
const int CPU_TYPE_X86_64 = 0x01000007;
const int CPU_TYPE_ARM64 = 0x0100000C;
const int CPU_TYPE_ANY = -1;

// ========== FreeBSD ==========

module c::spawn @if(env::FREEBSD);

// Opaque types
alias SpawnFileActions = void;
alias SpawnAttr = void;

// Function Declarations
extern fn int posix_spawn(int* pid, char* path, SpawnFileActions* file_actions,
                         SpawnAttr* attrp, char** argv, char** envp);
extern fn int posix_spawnp(int* pid, char* file, SpawnFileActions* file_actions,
                          SpawnAttr* attrp, char** argv, char** envp);

// File actions functions
extern fn int posix_spawn_file_actions_init(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_destroy(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_addopen(SpawnFileActions* file_actions,
                                               int fd, char* path, int oflag, uint mode);
extern fn int posix_spawn_file_actions_addclose(SpawnFileActions* file_actions, int fd);
extern fn int posix_spawn_file_actions_adddup2(SpawnFileActions* file_actions,
                                               int fd, int newfd);

// Spawn attributes functions
extern fn int posix_spawnattr_init(SpawnAttr* attr);
extern fn int posix_spawnattr_destroy(SpawnAttr* attr);
extern fn int posix_spawnattr_getflags(SpawnAttr* attr, short* flags);
extern fn int posix_spawnattr_setflags(SpawnAttr* attr, short flags);
extern fn int posix_spawnattr_getpgroup(SpawnAttr* attr, int* pgroup);
extern fn int posix_spawnattr_setpgroup(SpawnAttr* attr, int pgroup);
extern fn int posix_spawnattr_getschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_setschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_getschedpolicy(SpawnAttr* attr, int* schedpolicy);
extern fn int posix_spawnattr_setschedpolicy(SpawnAttr* attr, int schedpolicy);
extern fn int posix_spawnattr_getsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_setsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_getsigmask(SpawnAttr* attr, void* sigmask);
extern fn int posix_spawnattr_setsigmask(SpawnAttr* attr, void* sigmask);

// Flags
const short POSIX_SPAWN_RESETIDS = 0x01;
const short POSIX_SPAWN_SETPGROUP = 0x02;
const short POSIX_SPAWN_SETSIGDEF = 0x04;
const short POSIX_SPAWN_SETSIGMASK = 0x08;
const short POSIX_SPAWN_SETSCHEDPARAM = 0x10;
const short POSIX_SPAWN_SETSCHEDULER = 0x20;
const short POSIX_SPAWN_USEVFORK = 0x40;

// ========== NetBSD ==========

module c::spawn @if(env::NETBSD);

// Opaque types
alias SpawnFileActions = void;
alias SpawnAttr = void;

// Function Declarations
extern fn int posix_spawn(int* pid, char* path, SpawnFileActions* file_actions,
                         SpawnAttr* attrp, char** argv, char** envp);
extern fn int posix_spawnp(int* pid, char* file, SpawnFileActions* file_actions,
                          SpawnAttr* attrp, char** argv, char** envp);

// File actions functions
extern fn int posix_spawn_file_actions_init(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_destroy(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_addopen(SpawnFileActions* file_actions,
                                               int fd, char* path, int oflag, uint mode);
extern fn int posix_spawn_file_actions_addclose(SpawnFileActions* file_actions, int fd);
extern fn int posix_spawn_file_actions_adddup2(SpawnFileActions* file_actions,
                                               int fd, int newfd);

// Spawn attributes functions
extern fn int posix_spawnattr_init(SpawnAttr* attr);
extern fn int posix_spawnattr_destroy(SpawnAttr* attr);
extern fn int posix_spawnattr_getflags(SpawnAttr* attr, short* flags);
extern fn int posix_spawnattr_setflags(SpawnAttr* attr, short flags);
extern fn int posix_spawnattr_getpgroup(SpawnAttr* attr, int* pgroup);
extern fn int posix_spawnattr_setpgroup(SpawnAttr* attr, int pgroup);
extern fn int posix_spawnattr_getschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_setschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_getschedpolicy(SpawnAttr* attr, int* schedpolicy);
extern fn int posix_spawnattr_setschedpolicy(SpawnAttr* attr, int schedpolicy);
extern fn int posix_spawnattr_getsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_setsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_getsigmask(SpawnAttr* attr, void* sigmask);
extern fn int posix_spawnattr_setsigmask(SpawnAttr* attr, void* sigmask);

// Flags
const short POSIX_SPAWN_RESETIDS = 0x01;
const short POSIX_SPAWN_SETPGROUP = 0x02;
const short POSIX_SPAWN_SETSIGDEF = 0x04;
const short POSIX_SPAWN_SETSIGMASK = 0x08;
const short POSIX_SPAWN_SETSCHEDPARAM = 0x10;
const short POSIX_SPAWN_SETSCHEDULER = 0x20;

// ========== OpenBSD ==========

module c::spawn @if(env::OPENBSD);

// Opaque types
alias SpawnFileActions = void;
alias SpawnAttr = void;

// Function Declarations
extern fn int posix_spawn(int* pid, char* path, SpawnFileActions* file_actions,
                         SpawnAttr* attrp, char** argv, char** envp);
extern fn int posix_spawnp(int* pid, char* file, SpawnFileActions* file_actions,
                          SpawnAttr* attrp, char** argv, char** envp);

// File actions functions
extern fn int posix_spawn_file_actions_init(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_destroy(SpawnFileActions* file_actions);
extern fn int posix_spawn_file_actions_addopen(SpawnFileActions* file_actions,
                                               int fd, char* path, int oflag, uint mode);
extern fn int posix_spawn_file_actions_addclose(SpawnFileActions* file_actions, int fd);
extern fn int posix_spawn_file_actions_adddup2(SpawnFileActions* file_actions,
                                               int fd, int newfd);

// Spawn attributes functions
extern fn int posix_spawnattr_init(SpawnAttr* attr);
extern fn int posix_spawnattr_destroy(SpawnAttr* attr);
extern fn int posix_spawnattr_getflags(SpawnAttr* attr, short* flags);
extern fn int posix_spawnattr_setflags(SpawnAttr* attr, short flags);
extern fn int posix_spawnattr_getpgroup(SpawnAttr* attr, int* pgroup);
extern fn int posix_spawnattr_setpgroup(SpawnAttr* attr, int pgroup);
extern fn int posix_spawnattr_getschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_setschedparam(SpawnAttr* attr, void* schedparam);
extern fn int posix_spawnattr_getschedpolicy(SpawnAttr* attr, int* schedpolicy);
extern fn int posix_spawnattr_setschedpolicy(SpawnAttr* attr, int schedpolicy);
extern fn int posix_spawnattr_getsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_setsigdefault(SpawnAttr* attr, void* sigdefault);
extern fn int posix_spawnattr_getsigmask(SpawnAttr* attr, void* sigmask);
extern fn int posix_spawnattr_setsigmask(SpawnAttr* attr, void* sigmask);

// Flags
const short POSIX_SPAWN_RESETIDS = 0x01;
const short POSIX_SPAWN_SETPGROUP = 0x02;
const short POSIX_SPAWN_SETSIGDEF = 0x04;
const short POSIX_SPAWN_SETSIGMASK = 0x08;
const short POSIX_SPAWN_SETSCHEDPARAM = 0x10;
const short POSIX_SPAWN_SETSCHEDULER = 0x20;

// ========== Windows ==========

module c::spawn @if(env::WIN32);

// Windows does not have POSIX spawn
// Instead, use:
// 1. CreateProcess() from windows.h
// 2. _spawn* functions from process.h
// 3. system() for simple cases

// Windows _spawn* family (from process.h)
extern fn iptr _spawnl(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnle(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnlp(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnlpe(int mode, char* cmdname, char* arg0, ...);
extern fn iptr _spawnv(int mode, char* cmdname, char** argv);
extern fn iptr _spawnve(int mode, char* cmdname, char** argv, char** envp);
extern fn iptr _spawnvp(int mode, char* cmdname, char** argv);
extern fn iptr _spawnvpe(int mode, char* cmdname, char** argv, char** envp);

// Wide character versions
extern fn iptr _wspawnl(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnle(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnlp(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnlpe(int mode, ushort* cmdname, ushort* arg0, ...);
extern fn iptr _wspawnv(int mode, ushort* cmdname, ushort** argv);
extern fn iptr _wspawnve(int mode, ushort* cmdname, ushort** argv, ushort** envp);
extern fn iptr _wspawnvp(int mode, ushort* cmdname, ushort** argv);
extern fn iptr _wspawnvpe(int mode, ushort* cmdname, ushort** argv, ushort** envp);

// Spawn modes
const int _P_WAIT = 0;       // Suspend parent until child completes
const int _P_NOWAIT = 1;     // Continue parent, child runs concurrently
const int _P_OVERLAY = 2;    // Overlay parent (like exec)
const int _P_NOWAITO = 3;    // Continue parent, no wait
const int _P_DETACH = 4;     // Background, no access to console

// Aliases for compatibility
const int P_WAIT = _P_WAIT;
const int P_NOWAIT = _P_NOWAIT;
const int P_OVERLAY = _P_OVERLAY;
const int P_NOWAITO = _P_NOWAITO;
const int P_DETACH = _P_DETACH;

// Note: For full control on Windows, use CreateProcess() from windows.h
// CreateProcess() allows:
// - Fine-grained process creation flags
// - Security attributes
// - Environment customization
// - Startup info (window state, stdio redirection, etc.)
