// synchapi.h.c3

module c::synchapi @if(env::WIN32) @link("kernel32");

// Windows Synchronization API
// C3 mapping for synchapi.h

alias Handle = void*;
alias DWord = uint;
alias Bool = int;
alias PVoid = void*;
alias Long = int;
alias ULong = uint;
alias LongPtr = iptr;
alias ULongPtr = uptr;

// Wait result constants

const uint WAIT_OBJECT_0 = 0x00000000;
const uint WAIT_ABANDONED = 0x00000080;
const uint WAIT_TIMEOUT = 0x00000102;
const uint WAIT_FAILED = 0xFFFFFFFF;
const uint WAIT_IO_COMPLETION = 0x000000C0;

// Infinite timeout

const uint INFINITE = 0xFFFFFFFF;

// Mutex access rights

const uint MUTEX_ALL_ACCESS = 0x001F0001;
const uint MUTEX_MODIFY_STATE = 0x0001;

// Semaphore access rights

const uint SEMAPHORE_ALL_ACCESS = 0x001F0003;
const uint SEMAPHORE_MODIFY_STATE = 0x0002;

// Event access rights

const uint EVENT_ALL_ACCESS = 0x001F0003;
const uint EVENT_MODIFY_STATE = 0x0002;

// Timer access rights

const uint TIMER_ALL_ACCESS = 0x001F0003;
const uint TIMER_MODIFY_STATE = 0x0002;
const uint TIMER_QUERY_STATE = 0x0001;

// Synchronization barrier flags

const uint SYNCHRONIZATION_BARRIER_FLAGS_SPIN_ONLY = 0x01;
const uint SYNCHRONIZATION_BARRIER_FLAGS_BLOCK_ONLY = 0x02;
const uint SYNCHRONIZATION_BARRIER_FLAGS_NO_DELETE = 0x04;

// Critical section spin count

const uint CRITICAL_SECTION_NO_DEBUG_INFO = 0x01000000;

// Event flags

const uint CREATE_EVENT_INITIAL_SET = 0x00000002;
const uint CREATE_EVENT_MANUAL_RESET = 0x00000001;

// Mutex flags

const uint CREATE_MUTEX_INITIAL_OWNER = 0x00000001;

// Condition variable flags

const uint CONDITION_VARIABLE_LOCKMODE_SHARED = 0x00000001;

// InitOnce flags

const uint INIT_ONCE_CHECK_ONLY = 0x00000001;
const uint INIT_ONCE_ASYNC = 0x00000002;
const uint INIT_ONCE_INIT_FAILED = 0x00000004;
const uint INIT_ONCE_CTX_RESERVED_BITS = 2;

// Maximum wait objects

const uint MAXIMUM_WAIT_OBJECTS = 64;

// Structures

struct CriticalSection
{
    PVoid debugInfo;
    Long lockCount;
    Long recursionCount;
    Handle owningThread;
    Handle lockSemaphore;
    ULongPtr spinCount;
}

struct CriticalSectionAndSpinCount
{
    CriticalSection criticalSection;
    DWord spinCount;
}

struct SRWLock
{
    PVoid ptr;
}

struct ConditionVariable
{
    PVoid ptr;
}

struct SynchronizationBarrier
{
    DWord reserved1;
    DWord reserved2;
    ULongPtr[2] reserved3;
    DWord reserved4;
    DWord reserved5;
}

struct SecurityAttributes
{
    DWord length;
    PVoid securityDescriptor;
    Bool inheritHandle;
}

struct Reason
{
    DWord flags;

    union reason
    {
        struct detailed
        {
            Handle resourceFileNameModule;
            short* resourceReasonId;
        }

        char* simpleReasonString;
    }
}

struct InitOnce
{
    PVoid ptr;
}

const InitOnce INIT_ONCE_STATIC_INIT = { (PVoid)0 };

alias InitOnceCallback = fn Bool(InitOnce*, PVoid, PVoid*);

// Critical section functions

extern fn void initializeCriticalSection(CriticalSection* criticalSection) @cname("InitializeCriticalSection");

extern fn Bool initializeCriticalSectionAndSpinCount(
    CriticalSection* criticalSection,
    DWord spinCount
) @cname("InitializeCriticalSectionAndSpinCount");

extern fn Bool initializeCriticalSectionEx(
    CriticalSection* criticalSection,
    DWord spinCount,
    DWord flags
) @cname("InitializeCriticalSectionEx");

extern fn DWord setCriticalSectionSpinCount(
    CriticalSection* criticalSection,
    DWord spinCount
) @cname("SetCriticalSectionSpinCount");

extern fn void enterCriticalSection(CriticalSection* criticalSection) @cname("EnterCriticalSection");

extern fn Bool tryEnterCriticalSection(CriticalSection* criticalSection) @cname("TryEnterCriticalSection");

extern fn void leaveCriticalSection(CriticalSection* criticalSection) @cname("LeaveCriticalSection");

extern fn void deleteCriticalSection(CriticalSection* criticalSection) @cname("DeleteCriticalSection");

// SRW lock functions

extern fn void initializeSRWLock(SRWLock* srwLock) @cname("InitializeSRWLock");

extern fn void acquireSRWLockExclusive(SRWLock* srwLock) @cname("AcquireSRWLockExclusive");

extern fn Bool tryAcquireSRWLockExclusive(SRWLock* srwLock) @cname("TryAcquireSRWLockExclusive");

extern fn void releaseSRWLockExclusive(SRWLock* srwLock) @cname("ReleaseSRWLockExclusive");

extern fn void acquireSRWLockShared(SRWLock* srwLock) @cname("AcquireSRWLockShared");

extern fn Bool tryAcquireSRWLockShared(SRWLock* srwLock) @cname("TryAcquireSRWLockShared");

extern fn void releaseSRWLockShared(SRWLock* srwLock) @cname("ReleaseSRWLockShared");

// Condition variable functions

extern fn void initializeConditionVariable(ConditionVariable* conditionVariable) @cname("InitializeConditionVariable");

extern fn void wakeConditionVariable(ConditionVariable* conditionVariable) @cname("WakeConditionVariable");

extern fn void wakeAllConditionVariable(ConditionVariable* conditionVariable) @cname("WakeAllConditionVariable");

extern fn Bool sleepConditionVariableCS(
    ConditionVariable* conditionVariable,
    CriticalSection* criticalSection,
    DWord milliseconds
) @cname("SleepConditionVariableCS");

extern fn Bool sleepConditionVariableSRW(
    ConditionVariable* conditionVariable,
    SRWLock* srwLock,
    DWord milliseconds,
    ULong flags
) @cname("SleepConditionVariableSRW");

// Mutex functions

extern fn Handle createMutexA(
    SecurityAttributes* mutexAttributes,
    Bool initialOwner,
    char* name
) @cname("CreateMutexA");

extern fn Handle createMutexW(
    SecurityAttributes* mutexAttributes,
    Bool initialOwner,
    short* name
) @cname("CreateMutexW");

extern fn Handle createMutexExA(
    SecurityAttributes* mutexAttributes,
    char* name,
    DWord flags,
    DWord desiredAccess
) @cname("CreateMutexExA");

extern fn Handle createMutexExW(
    SecurityAttributes* mutexAttributes,
    short* name,
    DWord flags,
    DWord desiredAccess
) @cname("CreateMutexExW");

extern fn Handle openMutexA(
    DWord desiredAccess,
    Bool inheritHandle,
    char* name
) @cname("OpenMutexA");

extern fn Handle openMutexW(
    DWord desiredAccess,
    Bool inheritHandle,
    short* name
) @cname("OpenMutexW");

extern fn Bool releaseMutex(Handle mutex) @cname("ReleaseMutex");

// Semaphore functions

extern fn Handle createSemaphoreA(
    SecurityAttributes* semaphoreAttributes,
    Long initialCount,
    Long maximumCount,
    char* name
) @cname("CreateSemaphoreA");

extern fn Handle createSemaphoreW(
    SecurityAttributes* semaphoreAttributes,
    Long initialCount,
    Long maximumCount,
    short* name
) @cname("CreateSemaphoreW");

extern fn Handle createSemaphoreExA(
    SecurityAttributes* semaphoreAttributes,
    Long initialCount,
    Long maximumCount,
    char* name,
    DWord flags,
    DWord desiredAccess
) @cname("CreateSemaphoreExA");

extern fn Handle createSemaphoreExW(
    SecurityAttributes* semaphoreAttributes,
    Long initialCount,
    Long maximumCount,
    short* name,
    DWord flags,
    DWord desiredAccess
) @cname("CreateSemaphoreExW");

extern fn Handle openSemaphoreA(
    DWord desiredAccess,
    Bool inheritHandle,
    char* name
) @cname("OpenSemaphoreA");

extern fn Handle openSemaphoreW(
    DWord desiredAccess,
    Bool inheritHandle,
    short* name
) @cname("OpenSemaphoreW");

extern fn Bool releaseSemaphore(
    Handle semaphore,
    Long releaseCount,
    Long* previousCount
) @cname("ReleaseSemaphore");

// Event functions

extern fn Handle createEventA(
    SecurityAttributes* eventAttributes,
    Bool manualReset,
    Bool initialState,
    char* name
) @cname("CreateEventA");

extern fn Handle createEventW(
    SecurityAttributes* eventAttributes,
    Bool manualReset,
    Bool initialState,
    short* name
) @cname("CreateEventW");

extern fn Handle createEventExA(
    SecurityAttributes* eventAttributes,
    char* name,
    DWord flags,
    DWord desiredAccess
) @cname("CreateEventExA");

extern fn Handle createEventExW(
    SecurityAttributes* eventAttributes,
    short* name,
    DWord flags,
    DWord desiredAccess
) @cname("CreateEventExW");

extern fn Handle openEventA(
    DWord desiredAccess,
    Bool inheritHandle,
    char* name
) @cname("OpenEventA");

extern fn Handle openEventW(
    DWord desiredAccess,
    Bool inheritHandle,
    short* name
) @cname("OpenEventW");

extern fn Bool setEvent(Handle event) @cname("SetEvent");

extern fn Bool resetEvent(Handle event) @cname("ResetEvent");

extern fn Bool pulseEvent(Handle event) @cname("PulseEvent");

// Waitable timer functions

extern fn Handle createWaitableTimerA(
    SecurityAttributes* timerAttributes,
    Bool manualReset,
    char* timerName
) @cname("CreateWaitableTimerA");

extern fn Handle createWaitableTimerW(
    SecurityAttributes* timerAttributes,
    Bool manualReset,
    short* timerName
) @cname("CreateWaitableTimerW");

extern fn Handle createWaitableTimerExA(
    SecurityAttributes* timerAttributes,
    char* timerName,
    DWord flags,
    DWord desiredAccess
) @cname("CreateWaitableTimerExA");

extern fn Handle createWaitableTimerExW(
    SecurityAttributes* timerAttributes,
    short* timerName,
    DWord flags,
    DWord desiredAccess
) @cname("CreateWaitableTimerExW");

extern fn Handle openWaitableTimerA(
    DWord desiredAccess,
    Bool inheritHandle,
    char* timerName
) @cname("OpenWaitableTimerA");

extern fn Handle openWaitableTimerW(
    DWord desiredAccess,
    Bool inheritHandle,
    short* timerName
) @cname("OpenWaitableTimerW");

extern fn Bool setWaitableTimer(
    Handle timer,
    long* dueTime,
    Long period,
    void* completionRoutine,
    PVoid argToCompletionRoutine,
    Bool resume
) @cname("SetWaitableTimer");

extern fn Bool setWaitableTimerEx(
    Handle timer,
    long* dueTime,
    Long period,
    void* completionRoutine,
    PVoid argToCompletionRoutine,
    Reason* wakeContext,
    ULong tolerableDelay
) @cname("SetWaitableTimerEx");

extern fn Bool cancelWaitableTimer(Handle timer) @cname("CancelWaitableTimer");

// Wait functions

extern fn DWord waitForSingleObject(Handle handle, DWord milliseconds) @cname("WaitForSingleObject");

extern fn DWord waitForSingleObjectEx(
    Handle handle,
    DWord milliseconds,
    Bool alertable
) @cname("WaitForSingleObjectEx");

extern fn DWord waitForMultipleObjects(
    DWord count,
    Handle* handles,
    Bool waitAll,
    DWord milliseconds
) @cname("WaitForMultipleObjects");

extern fn DWord waitForMultipleObjectsEx(
    DWord count,
    Handle* handles,
    Bool waitAll,
    DWord milliseconds,
    Bool alertable
) @cname("WaitForMultipleObjectsEx");

extern fn DWord signalObjectAndWait(
    Handle objectToSignal,
    Handle objectToWaitOn,
    DWord milliseconds,
    Bool alertable
) @cname("SignalObjectAndWait");

extern fn Bool waitOnAddress(
    void* address,
    PVoid compareAddress,
    ulong addressSize,
    DWord milliseconds
) @cname("WaitOnAddress");

extern fn void wakeByAddressAll(PVoid address) @cname("WakeByAddressAll");

extern fn void wakeByAddressSingle(PVoid address) @cname("WakeByAddressSingle");

// Synchronization barrier functions

extern fn Bool initializeSynchronizationBarrier(
    SynchronizationBarrier* barrier,
    Long totalThreads,
    Long spinCount
) @cname("InitializeSynchronizationBarrier");

extern fn Bool enterSynchronizationBarrier(
    SynchronizationBarrier* barrier,
    DWord flags
) @cname("EnterSynchronizationBarrier");

extern fn Bool deleteSynchronizationBarrier(SynchronizationBarrier* barrier) @cname("DeleteSynchronizationBarrier");

// Sleep functions

extern fn void sleep(DWord milliseconds) @cname("Sleep");

extern fn DWord sleepEx(DWord milliseconds, Bool alertable) @cname("SleepEx");

// Interlocked functions

extern fn Long interlockedIncrement(Long* addend) @cname("InterlockedIncrement");

extern fn Long interlockedDecrement(Long* addend) @cname("InterlockedDecrement");

extern fn Long interlockedExchange(Long* target, Long value) @cname("InterlockedExchange");

extern fn Long interlockedExchangeAdd(Long* addend, Long value) @cname("InterlockedExchangeAdd");

extern fn Long interlockedCompareExchange(
    Long* destination,
    Long exchange,
    Long comparand
) @cname("InterlockedCompareExchange");

extern fn PVoid interlockedCompareExchangePointer(
    PVoid* destination,
    PVoid exchange,
    PVoid comparand
) @cname("InterlockedCompareExchangePointer");

extern fn PVoid interlockedExchangePointer(
    PVoid* target,
    PVoid value
) @cname("InterlockedExchangePointer");

// Once initialization

extern fn void initOnceInitialize(InitOnce* initOnce) @cname("InitOnceInitialize");

extern fn Bool initOnceExecuteOnce(
    InitOnce* initOnce,
    InitOnceCallback initFn,
    PVoid parameter,
    PVoid* context
) @cname("InitOnceExecuteOnce");

extern fn Bool initOnceBeginInitialize(
    InitOnce* initOnce,
    DWord flags,
    Bool* pending,
    PVoid* context
) @cname("InitOnceBeginInitialize");

extern fn Bool initOnceComplete(
    InitOnce* initOnce,
    DWord flags,
    PVoid context
) @cname("InitOnceComplete");

// eof