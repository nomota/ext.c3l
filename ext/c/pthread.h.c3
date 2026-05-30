// pthread.h.c3 

// C3 extern mappings for pthread.h functions and types.

module c::pthread @if(!env::WIN32);

// Thread Creation and Management

// Create a new thread.
alias ThreadFn = fn void*(void*);

extern fn CInt pthread_create(Pthread* thread, PthreadAttr* attr, ThreadFn start_routine, void* arg);

// Wait for thread termination
extern fn CInt pthread_join(Pthread thread, void** retval);

// Detach a thread (automatically release resources on termination)
extern fn CInt pthread_detach(Pthread thread);

// Terminate calling thread
extern fn void pthread_exit(void* retval);

// Return thread ID of calling thread
extern fn Pthread pthread_self();

// Compare two thread IDs
extern fn CInt pthread_equal(Pthread t1, Pthread t2);

// Send cancellation request to a thread
extern fn CInt pthread_cancel(Pthread thread);

// Set thread cancellation state
extern fn CInt pthread_setcancelstate(CInt state, CInt* oldstate);

// Set thread cancellation type
extern fn CInt pthread_setcanceltype(CInt type, CInt* oldtype);

// Create cancellation point
extern fn void pthread_testcancel();

// Thread Attribute Management

// Initialize thread attributes
extern fn CInt pthread_attr_init(PthreadAttr* attr);

// Destroy thread attributes
extern fn CInt pthread_attr_destroy(PthreadAttr* attr);

// Set/get detach state
extern fn CInt pthread_attr_setdetachstate(PthreadAttr* attr, CInt detachstate);
extern fn CInt pthread_attr_getdetachstate(PthreadAttr* attr, CInt* detachstate);

// Set/get stack size
extern fn CInt pthread_attr_setstacksize(PthreadAttr* attr, CSize stacksize);
extern fn CInt pthread_attr_getstacksize(PthreadAttr* attr, CSize* stacksize);

// Set/get stack address and size
extern fn CInt pthread_attr_setstack(PthreadAttr* attr, void* stackaddr, CSize stacksize);
extern fn CInt pthread_attr_getstack(PthreadAttr* attr, void** stackaddr, CSize* stacksize);

// Set/get scheduling policy
extern fn CInt pthread_attr_setschedpolicy(PthreadAttr* attr, CInt policy);
extern fn CInt pthread_attr_getschedpolicy(PthreadAttr* attr, CInt* policy);

// Mutex Functions

// Initialize mutex
extern fn CInt pthread_mutex_init(PthreadMutex* mutex, PthreadMutexAttr* attr);

// Destroy mutex
extern fn CInt pthread_mutex_destroy(PthreadMutex* mutex);

// Lock mutex
extern fn CInt pthread_mutex_lock(PthreadMutex* mutex);

// Try to lock mutex (non-blocking)
extern fn CInt pthread_mutex_trylock(PthreadMutex* mutex);

// Lock mutex with timeout
extern fn CInt pthread_mutex_timedlock(PthreadMutex* mutex, TimeSpec* abstime);

// Unlock mutex
extern fn CInt pthread_mutex_unlock(PthreadMutex* mutex);

// Mutex Attribute Management

// Initialize/destroy mutex attributes
extern fn CInt pthread_mutexattr_init(PthreadMutexAttr* attr);
extern fn CInt pthread_mutexattr_destroy(PthreadMutexAttr* attr);

// Set/get mutex type
extern fn CInt pthread_mutexattr_settype(PthreadMutexAttr* attr, CInt type);
extern fn CInt pthread_mutexattr_gettype(PthreadMutexAttr* attr, CInt* type);

// Set/get process-shared attribute
extern fn CInt pthread_mutexattr_setpshared(PthreadMutexAttr* attr, CInt pshared);
extern fn CInt pthread_mutexattr_getpshared(PthreadMutexAttr* attr, CInt* pshared);

// Set/get protocol attribute
extern fn CInt pthread_mutexattr_setprotocol(PthreadMutexAttr* attr, CInt protocol);
extern fn CInt pthread_mutexattr_getprotocol(PthreadMutexAttr* attr, CInt* protocol);

// Condition Variable Functions

// Initialize/destroy condition variable
extern fn CInt pthread_cond_init(PthreadCond* cond, PthreadCondAttr* attr);
extern fn CInt pthread_cond_destroy(PthreadCond* cond);

// Wait on condition variable
extern fn CInt pthread_cond_wait(PthreadCond* cond, PthreadMutex* mutex);

// Wait on condition variable with timeout
extern fn CInt pthread_cond_timedwait(PthreadCond* cond, PthreadMutex* mutex, TimeSpec* abstime);

// Wake up one waiting thread
extern fn CInt pthread_cond_signal(PthreadCond* cond);

// Wake up all waiting threads
extern fn CInt pthread_cond_broadcast(PthreadCond* cond);

// Condition Variable Attribute Management

// Initialize/destroy condition variable attributes
extern fn CInt pthread_condattr_init(PthreadCondAttr* attr);
extern fn CInt pthread_condattr_destroy(PthreadCondAttr* attr);

// Set/get process-shared attribute
extern fn CInt pthread_condattr_setpshared(PthreadCondAttr* attr, CInt pshared);
extern fn CInt pthread_condattr_getpshared(PthreadCondAttr* attr, CInt* pshared);

// Set/get clock attribute
extern fn CInt pthread_condattr_setclock(PthreadCondAttr* attr, CInt clock_id);
extern fn CInt pthread_condattr_getclock(PthreadCondAttr* attr, CInt* clock_id);

// Read-Write Lock Functions

// Initialize/destroy read-write lock
extern fn CInt pthread_rwlock_init(PthreadRWLock* rwlock, PthreadRWLockAttr* attr);
extern fn CInt pthread_rwlock_destroy(PthreadRWLock* rwlock);

// Acquire read lock
extern fn CInt pthread_rwlock_rdlock(PthreadRWLock* rwlock);

// Try to acquire read lock (non-blocking)
extern fn CInt pthread_rwlock_tryrdlock(PthreadRWLock* rwlock);

// Acquire read lock with timeout
extern fn CInt pthread_rwlock_timedrdlock(PthreadRWLock* rwlock, TimeSpec* abstime);

// Acquire write lock
extern fn CInt pthread_rwlock_wrlock(PthreadRWLock* rwlock);

// Try to acquire write lock (non-blocking)
extern fn CInt pthread_rwlock_trywrlock(PthreadRWLock* rwlock);

// Acquire write lock with timeout
extern fn CInt pthread_rwlock_timedwrlock(PthreadRWLock* rwlock, TimeSpec* abstime);

// Unlock read-write lock
extern fn CInt pthread_rwlock_unlock(PthreadRWLock* rwlock);

// Read-Write Lock Attribute Management

// Initialize/destroy read-write lock attributes
extern fn CInt pthread_rwlockattr_init(PthreadRWLockAttr* attr);
extern fn CInt pthread_rwlockattr_destroy(PthreadRWLockAttr* attr);

// Set/get process-shared attribute
extern fn CInt pthread_rwlockattr_setpshared(PthreadRWLockAttr* attr, CInt pshared);
extern fn CInt pthread_rwlockattr_getpshared(PthreadRWLockAttr* attr, CInt* pshared);

// Spinlock Functions

// Initialize/destroy spinlock
extern fn CInt pthread_spin_init(PthreadSpinLock* lock, CInt pshared);
extern fn CInt pthread_spin_destroy(PthreadSpinLock* lock);

// Acquire spinlock
extern fn CInt pthread_spin_lock(PthreadSpinLock* lock);

// Try to acquire spinlock (non-blocking)
extern fn CInt pthread_spin_trylock(PthreadSpinLock* lock);

// Release spinlock
extern fn CInt pthread_spin_unlock(PthreadSpinLock* lock);

// Barrier Functions

// Initialize/destroy barrier
extern fn CInt pthread_barrier_init(PthreadBarrier* barrier, PthreadBarrierAttr* attr, CUInt count);
extern fn CInt pthread_barrier_destroy(PthreadBarrier* barrier);

// Wait at barrier
extern fn CInt pthread_barrier_wait(PthreadBarrier* barrier);

// Barrier Attribute Management

// Initialize/destroy barrier attributes
extern fn CInt pthread_barrierattr_init(PthreadBarrierAttr* attr);
extern fn CInt pthread_barrierattr_destroy(PthreadBarrierAttr* attr);

// Set/get process-shared attribute
extern fn CInt pthread_barrierattr_setpshared(PthreadBarrierAttr* attr, CInt pshared);
extern fn CInt pthread_barrierattr_getpshared(PthreadBarrierAttr* attr, CInt* pshared);

// Thread-Specific Data

// Create thread-specific data key
alias Keyfn = fn void(void*);
extern fn CInt pthread_key_create(PthreadKey* key, Keyfn destructor);

// Delete thread-specific data key
extern fn CInt pthread_key_delete(PthreadKey key);

// Set thread-specific data
extern fn CInt pthread_setspecific(PthreadKey key, void* value);

// Get thread-specific data
extern fn void* pthread_getspecific(PthreadKey key);

// Once Initialization

// Execute initialization routine once
alias Oncefn = fn void();
extern fn CInt pthread_once(PthreadOnce* once_control, Oncefn init_routine);


// Cleanup Handlers

// Push cleanup handler
alias CleanupFn = fn void(void*);
extern fn void pthread_cleanup_push(CleanupFn routine, void* arg);

// Pop and execute cleanup handler
extern fn void pthread_cleanup_pop(CInt execute);

// Non-Portable Extensions (Linux/glibc)

// Get thread attributes of an existing thread
// Note: Caller must destroy the returned attr with pthread_attr_destroy()
extern fn CInt pthread_getattr_np(Pthread thread, PthreadAttr* attr) @if(env::LINUX);


// Type Definitions

alias CSize = sz;

// Opaque types
alias Pthread = CULong;           // Thread ID
alias PthreadKey = CUInt;        // Thread-specific data key

// TimeSpec structure
struct TimeSpec {
    CLong tv_sec;    // Seconds
    CLong tv_nsec;   // Nanoseconds
}

// Scheduling parameters
struct SchedParam {
    CInt sched_priority;  // Scheduling priority
}

// Structure Definitions

// Thread attributes
struct PthreadAttr {
    char[56] __size;      // Internal implementation (platform-dependent)
}

// Mutex
struct PthreadMutex {
    char[40] __size;      // Internal implementation (platform-dependent)
}

// Mutex attributes
struct PthreadMutexAttr {
    char[4] __size;       // Internal implementation
}

// Condition variable
struct PthreadCond {
    char[48] __size;      // Internal implementation (platform-dependent)
}

// Condition variable attributes
struct PthreadCondAttr {
    char[4] __size;       // Internal implementation
}

// Read-write lock
struct PthreadRWLock {
    char[56] __size;      // Internal implementation (platform-dependent)
}

// Read-write lock attributes
struct PthreadRWLockAttr {
    char[8] __size;       // Internal implementation
}

// Spinlock
struct PthreadSpinLock {
    CInt __lock;          // Lock state
}

// Barrier
struct PthreadBarrier {
    char[32] __size;      // Internal implementation (platform-dependent)
}

// Barrier attributes
struct PthreadBarrierAttr {
    char[4] __size;       // Internal implementation
}

// Once control
struct PthreadOnce {
    CInt __once;          // Initialization state
}

// Initialization Macros

// Static initializers
const PthreadMutex PTHREAD_MUTEX_INITIALIZER = {};
const PthreadCond PTHREAD_COND_INITIALIZER = {};
const PthreadRWLock PTHREAD_RWLOCK_INITIALIZER = {};
const PthreadOnce PTHREAD_ONCE_INIT = { .__once = 0 };

// Constant Definitions

// Detach state
const CInt PTHREAD_CREATE_JOINABLE = 0;  // Joinable (default)
const CInt PTHREAD_CREATE_DETACHED = 1;  // Detached

// Cancellation state
const CInt PTHREAD_CANCEL_ENABLE = 0;    // Cancellation enabled (default)
const CInt PTHREAD_CANCEL_DISABLE = 1;   // Cancellation disabled

// Cancellation type
const CInt PTHREAD_CANCEL_DEFERRED = 0;     // Deferred cancellation (default)
const CInt PTHREAD_CANCEL_ASYNCHRONOUS = 1; // Asynchronous cancellation

// Mutex types
const CInt PTHREAD_MUTEX_NORMAL = 0;        // Normal mutex
const CInt PTHREAD_MUTEX_RECURSIVE = 1;     // Recursive mutex
const CInt PTHREAD_MUTEX_ERRORCHECK = 2;    // Error-checking mutex
const CInt PTHREAD_MUTEX_DEFAULT = 0;       // Default mutex

// Process sharing
const CInt PTHREAD_PROCESS_PRIVATE = 0;  // Private to process (default)
const CInt PTHREAD_PROCESS_SHARED = 1;   // Shared between processes

// Mutex protocol
const CInt PTHREAD_PRIO_NONE = 0;     // No priority
const CInt PTHREAD_PRIO_INHERIT = 1;  // Priority inheritance
const CInt PTHREAD_PRIO_PROTECT = 2;  // Priority protection

// Barrier return value
const CInt PTHREAD_BARRIER_SERIAL_THREAD = -1;  // Last thread to pass barrier

// Scheduling policies
const CInt SCHED_OTHER = 0;   // Standard round-robin time-sharing
const CInt SCHED_FIFO = 1;    // First-in, first-out
const CInt SCHED_RR = 2;      // Round-robin
