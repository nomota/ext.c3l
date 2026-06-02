// wepoll.c3

// C3 port of wepoll.c
//
// Original project:
//   https://github.com/piscisaureus/wepoll
//
// Copyright 2012-2020, Bert Belder <bertbelder@gmail.com>
// BSD-style license. Keep the original license text with this file.

module c::wepoll @if(env::WIN32) @link("ws2_32", "kernel32");

import c::errno;
import c::string;
import c::stdlib;
import c::winsock2;
import c::winbase;
import c::synchapi;
import c::winnt;
import ext::debug;

// Public epoll-like API types

alias Handle = void*;
alias Socket = usz;
alias EPollFd = Handle;

alias DWord = uint;
alias Bool = int;
alias NtStatus = int;
alias AccessMask = uint;
alias ULongPtr = uptr;
alias ULong = uint;
alias UShort = ushort;
alias WChar = ushort;
alias PWStr = WChar*;

const NtStatus STATUS_SUCCESS = 0x00000000;
const NtStatus STATUS_PENDING = 0x00000103;
const NtStatus STATUS_CANCELLED = (NtStatus)0xC0000120;
const NtStatus STATUS_NOT_FOUND = (NtStatus)0xC0000225;

const int EPOLL_CTL_ADD = 1;
const int EPOLL_CTL_MOD = 2;
const int EPOLL_CTL_DEL = 3;

const uint EPOLLIN = 1u << 0;
const uint EPOLLPRI = 1u << 1;
const uint EPOLLOUT = 1u << 2;
const uint EPOLLERR = 1u << 3;
const uint EPOLLHUP = 1u << 4;
const uint EPOLLRDNORM = 1u << 6;
const uint EPOLLRDBAND = 1u << 7;
const uint EPOLLWRNORM = 1u << 8;
const uint EPOLLWRBAND = 1u << 9;
const uint EPOLLMSG = 1u << 10;
const uint EPOLLRDHUP = 1u << 13;
const uint EPOLLONESHOT = 1u << 31;

const uint FILE_OPEN = 0x00000001;

const uint KEYEDEVENT_WAIT = 0x00000001;
const uint KEYEDEVENT_WAKE = 0x00000002;
const uint KEYEDEVENT_ALL_ACCESS = winnt::STANDARD_RIGHTS_REQUIRED | KEYEDEVENT_WAIT | KEYEDEVENT_WAKE;

const uint IOCTL_AFD_POLL = 0x00012024;

const uint AFD_POLL_RECEIVE = 0x0001;
const uint AFD_POLL_RECEIVE_EXPEDITED = 0x0002;
const uint AFD_POLL_SEND = 0x0004;
const uint AFD_POLL_DISCONNECT = 0x0008;
const uint AFD_POLL_ABORT = 0x0010;
const uint AFD_POLL_LOCAL_CLOSE = 0x0020;
const uint AFD_POLL_ACCEPT = 0x0080;
const uint AFD_POLL_CONNECT_FAIL = 0x0100;

const uint ERROR_IO_PENDING = 997;
const uint ERROR_INVALID_PARAMETER = 87;
const uint ERROR_INVALID_HANDLE = 6;
const uint ERROR_ALREADY_EXISTS = 183;
const uint ERROR_NOT_ENOUGH_MEMORY = 8;
const uint ERROR_NOT_FOUND = 1168;
const uint WAIT_TIMEOUT = 258;

const DWord SIO_BSP_HANDLE_POLL = 0x4800001D;
const DWord SIO_BASE_HANDLE = 0x48000022;

union EpollData
{
    void* ptr;
    int fd;
    uint u32;
    ulong u64;
    Socket sock;
    Handle hnd;
}

struct EPollEvent
{
    uint events;
    EpollData data;
}

// NT private structures

struct IoStatusBlock
{
    NtStatus status;
    ULongPtr information;
}

alias PioStatusBlock = IoStatusBlock*;

alias PioApcRoutine = fn void(void* apcContext, PioStatusBlock ioStatusBlock, uint reserved) @callconv("stdcall");

struct UnicodeString
{
    UShort length;
    UShort maximumLength;
    PWStr buffer;
}

struct ObjectAttributes
{
    ULong length;
    Handle rootDirectory;
    UnicodeString* objectName;
    ULong attributes;
    void* securityDescriptor;
    void* securityQualityOfService;
}

struct AfdPollHandleInfo
{
    Handle handle;
    ULong events;
    NtStatus status;
}

struct AfdPollInfo
{
    winnt::LargeInteger timeout;
    ULong numberOfHandles;
    ULong exclusive;
    AfdPollHandleInfo[1] handles;
}

fn bool nt_success(NtStatus status) @inline
{
    return status >= 0;
}

// ntdll dynamic function pointers

alias NtCancelIoFileExFn = fn NtStatus(
    Handle fileHandle,
    IoStatusBlock* ioRequestToCancel,
    IoStatusBlock* ioStatusBlock
) @callconv("stdcall");

alias NtCreateFileFn = fn NtStatus(
    Handle* fileHandle,
    AccessMask desiredAccess,
    ObjectAttributes* objectAttributes,
    IoStatusBlock* ioStatusBlock,
    winnt::LargeInteger* allocationSize,
    ULong fileAttributes,
    ULong shareAccess,
    ULong createDisposition,
    ULong createOptions,
    void* eaBuffer,
    ULong eaLength
) @callconv("stdcall");

alias NtCreateKeyedEventFn = fn NtStatus(
    Handle* keyedEventHandle,
    AccessMask desiredAccess,
    ObjectAttributes* objectAttributes,
    ULong flags
) @callconv("stdcall");

alias NtDeviceIoControlFileFn = fn NtStatus(
    Handle fileHandle,
    Handle event,
    PioApcRoutine apcRoutine,
    void* apcContext,
    IoStatusBlock* ioStatusBlock,
    ULong ioControlCode,
    void* inputBuffer,
    ULong inputBufferLength,
    void* outputBuffer,
    ULong outputBufferLength
) @callconv("stdcall");

alias NtReleaseKeyedEventFn = fn NtStatus(
    Handle keyedEventHandle,
    void* keyValue,
    Bool alertable,
    winnt::LargeInteger* timeout
) @callconv("stdcall");

alias NtWaitForKeyedEventFn = fn NtStatus(
    Handle keyedEventHandle,
    void* keyValue,
    Bool alertable,
    winnt::LargeInteger* timeout
) @callconv("stdcall");

alias RtlNtStatusToDosErrorFn = fn ULong(NtStatus status) @callconv("stdcall");

NtCancelIoFileExFn ntCancelIoFileEx = null;
NtCreateFileFn ntCreateFile = null;
NtCreateKeyedEventFn ntCreateKeyedEvent = null;
NtDeviceIoControlFileFn ntDeviceIoControlFile = null;
NtReleaseKeyedEventFn ntReleaseKeyedEvent = null;
NtWaitForKeyedEventFn ntWaitForKeyedEvent = null;
RtlNtStatusToDosErrorFn rtlNtStatusToDosError = null;


fn void err_set_win_error(DWord error)
{
    winbase::setLastError(error);
    // errno::set_errno((int)errno::win_error_to_errno(error));
}

fn void err_map_win_error()
{
    //DWord error = winbase::getLastError();
    //errno::set_errno((int)errno::win_error_to_errno(error));
}

fn int err_check_handle(Handle handle)
{
    DWord flags = 0;

    if (handle == winbase::INVALID_HANDLE_VALUE)
    {
        err_set_win_error(ERROR_INVALID_HANDLE);
        return -1;
    }

    if (!winbase::getHandleInformation(handle, &flags))
    {
        err_map_win_error();
        return -1;
    }

    return 0;
}

// Init / ntdll loading

fn int nt_global_init()
{
    winbase::HModule ntdll = winbase::getModuleHandleA("ntdll.dll");
    if (ntdll == null) return -1;

    void* fnptr;

    fnptr = winbase::getProcAddress(ntdll, "NtCancelIoFileEx");
    if (fnptr == null) return -1;
    ntCancelIoFileEx = (NtCancelIoFileExFn)fnptr;

    fnptr = winbase::getProcAddress(ntdll, "NtCreateFile");
    if (fnptr == null) return -1;
    ntCreateFile = (NtCreateFileFn)fnptr;

    fnptr = winbase::getProcAddress(ntdll, "NtCreateKeyedEvent");
    if (fnptr == null) return -1;
    ntCreateKeyedEvent = (NtCreateKeyedEventFn)fnptr;

    fnptr = winbase::getProcAddress(ntdll, "NtDeviceIoControlFile");
    if (fnptr == null) return -1;
    ntDeviceIoControlFile = (NtDeviceIoControlFileFn)fnptr;

    fnptr = winbase::getProcAddress(ntdll, "NtReleaseKeyedEvent");
    if (fnptr == null) return -1;
    ntReleaseKeyedEvent = (NtReleaseKeyedEventFn)fnptr;

    fnptr = winbase::getProcAddress(ntdll, "NtWaitForKeyedEvent");
    if (fnptr == null) return -1;
    ntWaitForKeyedEvent = (NtWaitForKeyedEventFn)fnptr;

    fnptr = winbase::getProcAddress(ntdll, "RtlNtStatusToDosError");
    if (fnptr == null) return -1;
    rtlNtStatusToDosError = (RtlNtStatusToDosErrorFn)fnptr;

    return 0;
}

bool init_done = false;
synchapi::InitOnce init_once = synchapi::INIT_ONCE_STATIC_INIT;

//fn int ws_global_init();
//fn int reflock_global_init();
//fn int epoll_global_init();

fn Bool init_once_callback(synchapi::InitOnce* once, void* parameter, void** context) @callconv("stdcall")
{
    if (ws_global_init() < 0) return 0;
    if (nt_global_init() < 0) return 0;
    if (reflock_global_init() < 0) return 0;
    if (epoll_global_init() < 0) return 0;

    init_done = true;

    return 1;
}

fn int init()
{
    if (!init_done && !synchapi::initOnceExecuteOnce(&init_once, &init_once_callback, null, null))
    {
        return -1;
    }

    return 0;
}

// AFD

WChar[] afd_device_name_buf = {
    '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\',
    'A', 'f', 'd', '\\',
    'W', 'e', 'p', 'o', 'l', 'l',
    0,
};

UnicodeString afd_device_name = {};
ObjectAttributes afd_device_attributes = {};

fn void init_afd() @init
{
    afd_device_name = {
        .length = 36,
        .maximumLength = 38,
        .buffer = afd_device_name_buf.ptr,
    };
    
    afd_device_attributes = {
        .length = (ULong)(ObjectAttributes::size),
        .rootDirectory = null,
        .objectName = &afd_device_name,
        .attributes = 0,
        .securityDescriptor = null,
        .securityQualityOfService = null,
    };
}

fn int afd_create_device_handle(Handle iocp_handle, Handle* afd_device_handle_out)
{
    if (afd_device_handle_out == null) return -1;

    Handle afd_device_handle = null;
    IoStatusBlock iosb = {};
    NtStatus status;

    status = ntCreateFile(
        &afd_device_handle,
        winnt::SYNCHRONIZE,
        &afd_device_attributes,
        &iosb,
        null,
        0,
        winbase::FILE_SHARE_READ | winbase::FILE_SHARE_WRITE,
        FILE_OPEN,
        0,
        null,
        0
    );

    if (status != STATUS_SUCCESS)
    {
        err_set_win_error(rtlNtStatusToDosError(status));
        return -1;
    }

    if (winbase::createIoCompletionPort(afd_device_handle, iocp_handle, 0, 0) == null)
    {
        winbase::closeHandle(afd_device_handle);
        err_map_win_error();
        return -1;
    }

    if (!winbase::setFileCompletionNotificationModes(
        afd_device_handle,
        winbase::FILE_SKIP_SET_EVENT_ON_HANDLE))
    {
        winbase::closeHandle(afd_device_handle);
        err_map_win_error();
        return -1;
    }

    *afd_device_handle_out = afd_device_handle;
    return 0;
}

fn int afd_poll(Handle afd_device_handle, AfdPollInfo* poll_info, IoStatusBlock* io_status_block)
{
    @assert(io_status_block != null, "afd_poll(): io_status_block must not be null");

    io_status_block.status = STATUS_PENDING;

    NtStatus status = ntDeviceIoControlFile(
        afd_device_handle,
        null,
        null,
        io_status_block,
        io_status_block,
        IOCTL_AFD_POLL,
        poll_info,
        (ULong)@sizeof(*poll_info),
        poll_info,
        (ULong)@sizeof(*poll_info)
    );

    if (status == STATUS_SUCCESS)
    {
        return 0;
    }

    if (status == STATUS_PENDING)
    {
        err_set_win_error(ERROR_IO_PENDING);
        return -1;
    }

    err_set_win_error(rtlNtStatusToDosError(status));
    return -1;
}

fn int afd_cancel_poll(Handle afd_device_handle, IoStatusBlock* io_status_block)
{
    if (io_status_block == null) return 0;

    if (io_status_block.status != STATUS_PENDING)
    {
        return 0;
    }

    IoStatusBlock cancel_iosb = {};

    NtStatus cancel_status = ntCancelIoFileEx(
        afd_device_handle,
        io_status_block,
        &cancel_iosb
    );

    if (cancel_status == STATUS_SUCCESS || cancel_status == STATUS_NOT_FOUND)
    {
        return 0;
    }

    err_set_win_error(rtlNtStatusToDosError(cancel_status));
    return -1;
}

// Queue

struct QueueNode
{
    QueueNode* prev;
    QueueNode* next;
}

struct Queue
{
    QueueNode head;
}

fn void queue_node_init(QueueNode* node)
{
    node.prev = node;
    node.next = node;
}

fn void queue_init(Queue* queue)
{
    queue_node_init(&queue.head);
}

fn bool queue_is_enqueued(QueueNode* node)
{
    return node.prev != node;
}

fn bool queue_is_empty(Queue* queue)
{
    return !queue_is_enqueued(&queue.head);
}

fn QueueNode* queue_first(Queue* queue)
{
    if (queue_is_empty(queue)) return null;
    return queue.head.next;
}

fn QueueNode* queue_last(Queue* queue)
{
    if (queue_is_empty(queue)) return null;
    return queue.head.prev;
}

fn void queue_detach_node(QueueNode* node)
{
    node.prev.next = node.next;
    node.next.prev = node.prev;
}

fn void queue_prepend(Queue* queue, QueueNode* node)
{
    node.next = queue.head.next;
    node.prev = &queue.head;

    node.next.prev = node;
    queue.head.next = node;
}

fn void queue_append(Queue* queue, QueueNode* node)
{
    node.next = &queue.head;
    node.prev = queue.head.prev;

    node.prev.next = node;
    queue.head.prev = node;
}

fn void queue_move_to_start(Queue* queue, QueueNode* node)
{
    queue_detach_node(node);
    queue_prepend(queue, node);
}

fn void queue_move_to_end(Queue* queue, QueueNode* node)
{
    queue_detach_node(node);
    queue_append(queue, node);
}

fn void queue_remove(QueueNode* node)
{
    queue_detach_node(node);
    queue_node_init(node);
}

// Reflock

struct Reflock
{
    int state;
}

const int REFLOCK_REF = 0x00000001;
const int REFLOCK_REF_MASK = 0x0fffffff;
const int REFLOCK_DESTROY = 0x10000000;
const int REFLOCK_DESTROY_MASK = (int)0xf0000000;
const int REFLOCK_POISON = 0x300dead0;

Handle reflock_keyed_event = null;

fn int reflock_global_init()
{
    NtStatus status = ntCreateKeyedEvent(
        &reflock_keyed_event,
        KEYEDEVENT_ALL_ACCESS,
        null,
        0
    );

    if (status != STATUS_SUCCESS)
    {
        err_set_win_error(rtlNtStatusToDosError(status));
        return -1;
    }

    return 0;
}

fn void reflock_init(Reflock* reflock)
{
    reflock.state = 0;
}

fn void reflock_signal_event(void* address)
{
    NtStatus status = ntReleaseKeyedEvent(
        reflock_keyed_event,
        address,
        0,
        null
    );

    @assert(status == STATUS_SUCCESS, "NtReleaseKeyedEvent failed");
}

fn void reflock_await_event(void* address)
{
    NtStatus status = ntWaitForKeyedEvent(
        reflock_keyed_event,
        address,
        0,
        null
    );

    @assert(status == STATUS_SUCCESS, "NtWaitForKeyedEvent failed");
}

fn void reflock_ref(Reflock* reflock)
{
// warn("%d", reflock.state);
    int state = winbase::interlockedAdd(&reflock.state, REFLOCK_REF);
// warn("%s %d", state, reflock.state);
    @assert((state & REFLOCK_DESTROY_MASK) == 0, "reflock_ref(): invalid state");
}

fn void reflock_unref(Reflock* reflock)
{
// warn("%d", reflock.state);
    int state = winbase::interlockedAdd(&reflock.state, -REFLOCK_REF);
// warn("%d %d", state, reflock.state);
    @assert((state & REFLOCK_DESTROY_MASK & ~REFLOCK_DESTROY) == 0, "reflock_unref(): invalid state");

    if (state == REFLOCK_DESTROY)
    {
        reflock_signal_event(reflock);
    }
}

fn void reflock_unref_and_destroy(Reflock* reflock)
{
// warn("%d", reflock.state);
    int state = winbase::interlockedAdd(
        &reflock.state,
        REFLOCK_DESTROY - REFLOCK_REF
    );
// warn("%d %d", state, reflock.state);
    int ref_count = reflock.state & REFLOCK_REF_MASK;

    @assert((reflock.state & REFLOCK_DESTROY_MASK) == REFLOCK_DESTROY, "reflock_unref_and_destroy(): invalid state");

    if (ref_count != 0)
    {
        reflock_await_event(reflock);
    }

    state = winbase::interlockedExchange(&reflock.state, REFLOCK_POISON);

    @assert(state == REFLOCK_DESTROY, "reflock_unref_and_destroy(): poisoned invalid state");
}

// Tree

struct Tree
{
    TreeNode* root;
}

struct TreeNode
{
    TreeNode* left;
    TreeNode* right;
    TreeNode* parent;
    uptr key;
    bool red;
}

fn void tree_init(Tree* tree)
{
    tree.root = null;
}

fn void tree_node_init(TreeNode* node)
{
    node.left = null;
    node.right = null;
    node.parent = null;
    node.key = 0;
    node.red = false;
}

fn TreeNode* tree_root(Tree* tree)
{
    return tree.root;
}

fn TreeNode* tree_find(Tree* tree, uptr key)
{
    TreeNode* node = tree.root;

    while (node != null)
    {
        if (key < node.key)
        {
            node = node.left;
        }
        else if (key > node.key)
        {
            node = node.right;
        }
        else
        {
            return node;
        }
    }

    return null;
}

fn void tree_rotate_left(Tree* tree, TreeNode* node)
{
    TreeNode* p = node;
    TreeNode* q = node.right;
    TreeNode* parent = p.parent;

    if (parent != null)
    {
        if (parent.left == p)
        {
            parent.left = q;
        }
        else
        {
            parent.right = q;
        }
    }
    else
    {
        tree.root = q;
    }

    q.parent = parent;
    p.parent = q;
    p.right = q.left;

    if (p.right != null)
    {
        p.right.parent = p;
    }

    q.left = p;
}

fn void tree_rotate_right(Tree* tree, TreeNode* node)
{
    TreeNode* p = node;
    TreeNode* q = node.left;
    TreeNode* parent = p.parent;

    if (parent != null)
    {
        if (parent.left == p)
        {
            parent.left = q;
        }
        else
        {
            parent.right = q;
        }
    }
    else
    {
        tree.root = q;
    }

    q.parent = parent;
    p.parent = q;
    p.left = q.right;

    if (p.left != null)
    {
        p.left.parent = p;
    }

    q.right = p;
}

fn int tree_add(Tree* tree, TreeNode* node, uptr key)
{
    TreeNode* parent = tree.root;

    if (parent != null)
    {
        while (true)
        {
            if (key < parent.key)
            {
                if (parent.left != null)
                {
                    parent = parent.left;
                }
                else
                {
                    parent.left = node;
                    break;
                }
            }
            else if (key > parent.key)
            {
                if (parent.right != null)
                {
                    parent = parent.right;
                }
                else
                {
                    parent.right = node;
                    break;
                }
            }
            else
            {
                return -1;
            }
        }
    }
    else
    {
        tree.root = node;
    }

    node.key = key;
    node.left = null;
    node.right = null;
    node.parent = parent;
    node.red = true;

    while (parent != null && parent.red)
    {
        TreeNode* grandparent = parent.parent;

        if (parent == grandparent.left)
        {
            TreeNode* uncle = grandparent.right;

            if (uncle != null && uncle.red)
            {
                parent.red = false;
                uncle.red = false;
                grandparent.red = true;

                node = grandparent;
                parent = node.parent;
            }
            else
            {
                if (node == parent.right)
                {
                    tree_rotate_left(tree, parent);
                    node = parent;
                    parent = node.parent;
                }

                parent.red = false;
                grandparent.red = true;
                tree_rotate_right(tree, grandparent);
            }
        }
        else
        {
            TreeNode* uncle = grandparent.left;

            if (uncle != null && uncle.red)
            {
                parent.red = false;
                uncle.red = false;
                grandparent.red = true;

                node = grandparent;
                parent = node.parent;
            }
            else
            {
                if (node == parent.left)
                {
                    tree_rotate_right(tree, parent);
                    node = parent;
                    parent = node.parent;
                }

                parent.red = false;
                grandparent.red = true;
                tree_rotate_left(tree, grandparent);
            }
        }
    }

    tree.root.red = false;

    return 0;
}

fn void tree_del(Tree* tree, TreeNode* node)
{
    TreeNode* parent = node.parent;
    TreeNode* left = node.left;
    TreeNode* right = node.right;
    TreeNode* next;
    bool red;

    if (left == null)
    {
        next = right;
    }
    else if (right == null)
    {
        next = left;
    }
    else
    {
        next = right;

        while (next.left != null)
        {
            next = next.left;
        }
    }

    if (parent != null)
    {
        if (parent.left == node)
        {
            parent.left = next;
        }
        else
        {
            parent.right = next;
        }
    }
    else
    {
        tree.root = next;
    }

    if (left != null && right != null)
    {
        red = next.red;
        next.red = node.red;
        next.left = left;
        left.parent = next;

        if (next != right)
        {
            parent = next.parent;
            next.parent = node.parent;
            node = next.right;
            parent.left = node;
            next.right = right;
            right.parent = next;
        }
        else
        {
            next.parent = parent;
            parent = next;
            node = next.right;
        }
    }
    else
    {
        red = node.red;
        node = next;
    }

    if (node != null)
    {
        node.parent = parent;
    }

    if (red) return;

    if (node != null && node.red)
    {
        node.red = false;
        return;
    }

    while (true)
    {
        if (node == tree.root) break;

        if (node == parent.left)
        {
            TreeNode* sibling = parent.right;

            if (sibling.red)
            {
                sibling.red = false;
                parent.red = true;
                tree_rotate_left(tree, parent);
                sibling = parent.right;
            }

            if ((sibling.left != null && sibling.left.red) ||
                (sibling.right != null && sibling.right.red))
            {
                if (sibling.right == null || !sibling.right.red)
                {
                    sibling.left.red = false;
                    sibling.red = true;
                    tree_rotate_right(tree, sibling);
                    sibling = parent.right;
                }

                sibling.red = parent.red;
                parent.red = false;
                sibling.right.red = false;
                tree_rotate_left(tree, parent);
                node = tree.root;
                break;
            }

            sibling.red = true;
        }
        else
        {
            TreeNode* sibling = parent.left;

            if (sibling.red)
            {
                sibling.red = false;
                parent.red = true;
                tree_rotate_right(tree, parent);
                sibling = parent.left;
            }

            if ((sibling.left != null && sibling.left.red) ||
                (sibling.right != null && sibling.right.red))
            {
                if (sibling.left == null || !sibling.left.red)
                {
                    sibling.right.red = false;
                    sibling.red = true;
                    tree_rotate_left(tree, sibling);
                    sibling = parent.left;
                }

                sibling.red = parent.red;
                parent.red = false;
                sibling.left.red = false;
                tree_rotate_right(tree, parent);
                node = tree.root;
                break;
            }

            sibling.red = true;
        }

        node = parent;
        parent = parent.parent;

        if (node.red) break;
    }

    if (node != null)
    {
        node.red = false;
    }
}

// Thread-safe tree

struct TsTree
{
    Tree tree;
    winbase::SRWLock lock;
}

struct TsTreeNode
{
    TreeNode tree_node;
    Reflock reflock;
}

fn void ts_tree_init(TsTree* ts_tree)
{
    tree_init(&ts_tree.tree);
    winbase::initializeSRWLock(&ts_tree.lock);
}

fn void ts_tree_node_init(TsTreeNode* node)
{
    tree_node_init(&node.tree_node);
    reflock_init(&node.reflock);
}

fn int ts_tree_add(TsTree* ts_tree, TsTreeNode* node, uptr key)
{
    int r;

    winbase::acquireSRWLockExclusive(&ts_tree.lock);
    r = tree_add(&ts_tree.tree, &node.tree_node, key);
    winbase::releaseSRWLockExclusive(&ts_tree.lock);

    return r;
}

fn TsTreeNode* ts_tree_find_node(TsTree* ts_tree, uptr key)
{
    TreeNode* tree_node = tree_find(&ts_tree.tree, key);
    if (tree_node == null) return null;

    return (TsTreeNode*)((char*)tree_node - $reflect(TsTreeNode.tree_node).offset);
}

fn TsTreeNode* ts_tree_del_and_ref(TsTree* ts_tree, uptr key)
{
    TsTreeNode* node;

    winbase::acquireSRWLockExclusive(&ts_tree.lock);

    node = ts_tree_find_node(ts_tree, key);
    if (node != null)
    {
        tree_del(&ts_tree.tree, &node.tree_node);
        reflock_ref(&node.reflock);
    }

    winbase::releaseSRWLockExclusive(&ts_tree.lock);

    return node;
}

fn TsTreeNode* ts_tree_find_and_ref(TsTree* ts_tree, uptr key)
{
    TsTreeNode* node;

    winbase::acquireSRWLockShared(&ts_tree.lock);

    node = ts_tree_find_node(ts_tree, key);
    if (node != null)
    {
        reflock_ref(&node.reflock);
    }

    winbase::releaseSRWLockShared(&ts_tree.lock);

    return node;
}

fn void ts_tree_node_unref(TsTreeNode* node)
{
    reflock_unref(&node.reflock);
}

fn void ts_tree_node_unref_and_destroy(TsTreeNode* node)
{
    reflock_unref_and_destroy(&node.reflock);
}

// Port / poll group

const sz POLL_GROUP_MAX_GROUP_SIZE = 32;
const sz PORT_MAX_ON_STACK_COMPLETIONS = 256;

struct PollGroup
{
    PortState* port_state;
    QueueNode queue_node;
    Handle afd_device_handle;
    sz group_size;
}

struct PortState
{
    Handle iocp_handle;
    Tree sock_tree;
    Queue sock_update_queue;
    Queue sock_deleted_queue;
    Queue poll_group_queue;
    TsTreeNode handle_tree_node;
    winbase::CriticalSection lock;
    sz active_poll_count;
}

TsTree epoll_handle_tree;

fn int epoll_global_init()
{
    ts_tree_init(&epoll_handle_tree);
    return 0;
}

fn PollGroup* poll_group_from_queue_node(QueueNode* queue_node)
{
    return (PollGroup*)((char*)queue_node - $reflect(PollGroup.queue_node).offset);
}

fn Handle poll_group_get_afd_device_handle(PollGroup* poll_group)
{
    return poll_group.afd_device_handle;
}

fn Handle port_get_iocp_handle(PortState* port_state)
{
    @assert(port_state.iocp_handle != null, "port_get_iocp_handle(): null iocp handle");
    return port_state.iocp_handle;
}

fn Queue* port_get_poll_group_queue(PortState* port_state)
{
    return &port_state.poll_group_queue;
}

fn PollGroup* poll_group_new(PortState* port_state)
{
    Handle iocp_handle = port_get_iocp_handle(port_state);
    Queue* poll_group_queue = port_get_poll_group_queue(port_state);

    PollGroup* poll_group = (PollGroup*)stdlib::malloc(PollGroup::size);
    if (poll_group == null)
    {
        err_set_win_error(ERROR_NOT_ENOUGH_MEMORY);
        return null;
    }

    string::memset(poll_group, 0, PollGroup::size);

    queue_node_init(&poll_group.queue_node);
    poll_group.port_state = port_state;

    if (afd_create_device_handle(iocp_handle, &poll_group.afd_device_handle) < 0)
    {
        stdlib::free(poll_group);
        return null;
    }

    queue_append(poll_group_queue, &poll_group.queue_node);

    return poll_group;
}

fn void poll_group_delete(PollGroup* poll_group)
{
    @assert(poll_group.group_size == 0, "poll_group_delete(): group still in use");

    winbase::closeHandle(poll_group.afd_device_handle);
    queue_remove(&poll_group.queue_node);
    stdlib::free(poll_group);
}

fn PollGroup* poll_group_acquire(PortState* port_state)
{
    Queue* poll_group_queue = port_get_poll_group_queue(port_state);
    PollGroup* poll_group = null;

    if (!queue_is_empty(poll_group_queue))
    {
        poll_group = poll_group_from_queue_node(queue_last(poll_group_queue));
    }

    if (poll_group == null || poll_group.group_size >= POLL_GROUP_MAX_GROUP_SIZE)
    {
        poll_group = poll_group_new(port_state);
    }

    if (poll_group == null) return null;

    poll_group.group_size++;

    if (poll_group.group_size == POLL_GROUP_MAX_GROUP_SIZE)
    {
        queue_move_to_start(poll_group_queue, &poll_group.queue_node);
    }

    return poll_group;
}

fn void poll_group_release(PollGroup* poll_group)
{
    PortState* port_state = poll_group.port_state;
    Queue* poll_group_queue = port_get_poll_group_queue(port_state);

    poll_group.group_size--;

    @assert(poll_group.group_size < POLL_GROUP_MAX_GROUP_SIZE, "poll_group_release(): invalid group size");

    queue_move_to_end(poll_group_queue, &poll_group.queue_node);
}

fn PortState* port_state_from_handle_tree_node(TsTreeNode* tree_node)
{
    return (PortState*)((char*)tree_node - $reflect(PortState.handle_tree_node).offset);
}

fn TsTreeNode* port_state_to_handle_tree_node(PortState* port_state)
{
    return &port_state.handle_tree_node;
}

fn PortState* port_alloc()
{
    PortState* port_state = (PortState*)stdlib::malloc(PortState::size);
    if (port_state == null)
    {
        err_set_win_error(ERROR_NOT_ENOUGH_MEMORY);
        return null;
    }

    return port_state;
}

fn void port_free(PortState* port_state)
{
    @assert(port_state != null, "port_free(): null port_state");
    stdlib::free(port_state);
}

fn Handle port_create_iocp()
{
    Handle iocp_handle = winbase::createIoCompletionPort(
        winbase::INVALID_HANDLE_VALUE,
        null,
        0,
        0
    );

    if (iocp_handle == null)
    {
        err_map_win_error();
        return null;
    }

    return iocp_handle;
}

fn PortState* port_new(Handle* iocp_handle_out)
{
    if (iocp_handle_out == null)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        return null;
    }

    PortState* port_state = port_alloc();
    if (port_state == null) return null;

    Handle iocp_handle = port_create_iocp();
    if (iocp_handle == null)
    {
        port_free(port_state);
        return null;
    }

    string::memset(port_state, 0, PortState::size);

    port_state.iocp_handle = iocp_handle;
    tree_init(&port_state.sock_tree);
    queue_init(&port_state.sock_update_queue);
    queue_init(&port_state.sock_deleted_queue);
    queue_init(&port_state.poll_group_queue);
    ts_tree_node_init(&port_state.handle_tree_node);
    winbase::initializeCriticalSection(&port_state.lock);

    *iocp_handle_out = iocp_handle;

    return port_state;
}

fn int port_close_iocp(PortState* port_state)
{
    Handle iocp_handle = port_state.iocp_handle;
    port_state.iocp_handle = null;

    if (!winbase::closeHandle(iocp_handle))
    {
        err_map_win_error();
        return -1;
    }

    return 0;
}

fn int port_close(PortState* port_state)
{
    int result;

    winbase::enterCriticalSection(&port_state.lock);
    result = port_close_iocp(port_state);
    winbase::leaveCriticalSection(&port_state.lock);

    return result;
}

// Sock state

const uint SOCK_KNOWN_EPOLL_EVENTS =
    EPOLLIN |
    EPOLLPRI |
    EPOLLOUT |
    EPOLLERR |
    EPOLLHUP |
    EPOLLRDNORM |
    EPOLLRDBAND |
    EPOLLWRNORM |
    EPOLLWRBAND |
    EPOLLMSG |
    EPOLLRDHUP;

enum SockPollStatus : int
{
    SOCK_POLL_IDLE,
    SOCK_POLL_PENDING,
    SOCK_POLL_CANCELLED,
}

struct SockState
{
    IoStatusBlock io_status_block;
    AfdPollInfo poll_info;

    QueueNode queue_node;
    TreeNode tree_node;

    PollGroup* poll_group;

    Socket base_socket;
    EpollData user_data;

    uint user_events;
    uint pending_events;

    SockPollStatus poll_status;
    bool delete_pending;
}

fn SockState* sock_state_from_queue_node(QueueNode* queue_node)
{
    return (SockState*)((char*)queue_node - $reflect(SockState.queue_node).offset);
}

fn QueueNode* sock_state_to_queue_node(SockState* sock_state)
{
    return &sock_state.queue_node;
}

fn SockState* sock_state_from_tree_node(TreeNode* tree_node)
{
    return (SockState*)((char*)tree_node - $reflect(SockState.tree_node).offset);
}

fn TreeNode* sock_state_to_tree_node(SockState* sock_state)
{
    return &sock_state.tree_node;
}

fn void port_unregister_socket(PortState* port_state, SockState* sock_state)
{
    tree_del(&port_state.sock_tree, sock_state_to_tree_node(sock_state));
}

fn void port_cancel_socket_update(PortState* port_state, SockState* sock_state)
{
    if (!queue_is_enqueued(sock_state_to_queue_node(sock_state))) return;

    queue_remove(sock_state_to_queue_node(sock_state));
}

fn void port_remove_deleted_socket(PortState* port_state, SockState* sock_state)
{
    if (!queue_is_enqueued(sock_state_to_queue_node(sock_state))) return;

    queue_remove(sock_state_to_queue_node(sock_state));
}

fn void port_add_deleted_socket(PortState* port_state, SockState* sock_state)
{
    if (queue_is_enqueued(sock_state_to_queue_node(sock_state))) return;

    queue_append(&port_state.sock_deleted_queue, sock_state_to_queue_node(sock_state));
}

fn int sock_cancel_poll(SockState* sock_state)
{
    @assert(sock_state.poll_status == SOCK_POLL_PENDING, "sock_cancel_poll(): poll not pending");

    if (afd_cancel_poll(
        poll_group_get_afd_device_handle(sock_state.poll_group),
        &sock_state.io_status_block) < 0)
    {
        return -1;
    }

    sock_state.poll_status = SOCK_POLL_CANCELLED;
    sock_state.pending_events = 0;

    return 0;
}

fn void sock_free(SockState* sock_state)
{
    @assert(sock_state != null, "sock_free(): null sock_state");
    stdlib::free(sock_state);
}

fn int sock_delete_impl(PortState* port_state, SockState* sock_state, bool force)
{
    if (!sock_state.delete_pending)
    {
        if (sock_state.poll_status == SOCK_POLL_PENDING)
        {
            sock_cancel_poll(sock_state);
        }

        port_cancel_socket_update(port_state, sock_state);
        port_unregister_socket(port_state, sock_state);

        sock_state.delete_pending = true;
    }

    if (force || sock_state.poll_status == SOCK_POLL_IDLE)
    {
        port_remove_deleted_socket(port_state, sock_state);
        poll_group_release(sock_state.poll_group);
        sock_free(sock_state);
    }
    else
    {
        port_add_deleted_socket(port_state, sock_state);
    }

    return 0;
}

fn void sock_delete(PortState* port_state, SockState* sock_state)
{
    sock_delete_impl(port_state, sock_state, false);
}

fn void sock_force_delete(PortState* port_state, SockState* sock_state)
{
    sock_delete_impl(port_state, sock_state, true);
}

fn int port_delete(PortState* port_state)
{
    TreeNode* tree_node;
    QueueNode* queue_node;

    @assert(port_state.iocp_handle == null, "port_delete(): IOCP handle still open");

    while ((tree_node = tree_root(&port_state.sock_tree)) != null)
    {
        SockState* sock_state = sock_state_from_tree_node(tree_node);
        sock_force_delete(port_state, sock_state);
    }

    while ((queue_node = queue_first(&port_state.sock_deleted_queue)) != null)
    {
        SockState* sock_state = sock_state_from_queue_node(queue_node);
        sock_force_delete(port_state, sock_state);
    }

    while ((queue_node = queue_first(&port_state.poll_group_queue)) != null)
    {
        PollGroup* poll_group = poll_group_from_queue_node(queue_node);
        poll_group_delete(poll_group);
    }

    @assert(queue_is_empty(&port_state.sock_update_queue), "port_delete(): update queue not empty");

    winbase::deleteCriticalSection(&port_state.lock);

    port_free(port_state);

    return 0;
}

fn SockState* port_find_socket(PortState* port_state, Socket socket)
{
    TreeNode* tree_node = tree_find(&port_state.sock_tree, (uptr)socket);

    if (tree_node == null)
    {
        err_set_win_error(ERROR_NOT_FOUND);
        return null;
    }

    return sock_state_from_tree_node(tree_node);
}

fn int port_register_socket(PortState* port_state, SockState* sock_state, Socket socket)
{
    if (tree_add(&port_state.sock_tree, sock_state_to_tree_node(sock_state), (uptr)socket) < 0)
    {
        err_set_win_error(ERROR_ALREADY_EXISTS);
        return -1;
    }

    return 0;
}

fn void port_request_socket_update(PortState* port_state, SockState* sock_state)
{
    if (queue_is_enqueued(sock_state_to_queue_node(sock_state))) return;

    queue_append(&port_state.sock_update_queue, sock_state_to_queue_node(sock_state));
}

// Winsock base socket

fn int ws_global_init()
{
    winsock2::WSAData wsa_data;

    int r = winsock2::wsaStartup(0x0202, &wsa_data);
    if (r != 0)
    {
        err_set_win_error((DWord)r);
        return -1;
    }

    return 0;
}

fn Socket ws_ioctl_get_bsp_socket(Socket socket, DWord ioctl)
{
    Socket bsp_socket = winsock2::INVALID_SOCKET;
    DWord bytes = 0;

    if (winsock2::wsaIoctl(
        (winsock2::Socket)socket,
        ioctl,
        null,
        0,
        &bsp_socket,
        (DWord)@sizeof(bsp_socket),
        &bytes,
        null,
        null) != winsock2::SOCKET_ERROR)
    {
        return bsp_socket;
    }

    return winsock2::INVALID_SOCKET;
}

fn Socket ws_get_base_socket(Socket socket)
{
    Socket base_socket;
    DWord error;

    while (true)
    {
        base_socket = ws_ioctl_get_bsp_socket(socket, SIO_BASE_HANDLE);
        if (base_socket != winsock2::INVALID_SOCKET)
        {
            return base_socket;
        }

        error = winbase::getLastError();

        if (error == winsock2::WSAENOTSOCK)
        {
            err_set_win_error(error);
            return winsock2::INVALID_SOCKET;
        }

        base_socket = ws_ioctl_get_bsp_socket(socket, SIO_BSP_HANDLE_POLL);

        if (base_socket != winsock2::INVALID_SOCKET && base_socket != socket)
        {
            socket = base_socket;
        }
        else
        {
            err_set_win_error(error);
            return winsock2::INVALID_SOCKET;
        }
    }
}

fn SockState* sock_alloc()
{
    SockState* sock_state = (SockState*)stdlib::malloc(SockState::size);
    if (sock_state == null)
    {
        err_set_win_error(ERROR_NOT_ENOUGH_MEMORY);
        return null;
    }

    return sock_state;
}

fn SockState* sock_new(PortState* port_state, Socket socket)
{
    if (socket == 0 || socket == winsock2::INVALID_SOCKET)
    {
        err_set_win_error(ERROR_INVALID_HANDLE);
        return null;
    }

    Socket base_socket = ws_get_base_socket(socket);
    if (base_socket == winsock2::INVALID_SOCKET)
    {
        return null;
    }

    PollGroup* poll_group = poll_group_acquire(port_state);
    if (poll_group == null)
    {
        return null;
    }

    SockState* sock_state = sock_alloc();
    if (sock_state == null)
    {
        poll_group_release(poll_group);
        return null;
    }

    string::memset(sock_state, 0, SockState::size);

    sock_state.base_socket = base_socket;
    sock_state.poll_group = poll_group;
    sock_state.poll_status = SOCK_POLL_IDLE;

    tree_node_init(&sock_state.tree_node);
    queue_node_init(&sock_state.queue_node);

    if (port_register_socket(port_state, sock_state, socket) < 0)
    {
        sock_free(sock_state);
        poll_group_release(poll_group);
        return null;
    }

    return sock_state;
}

fn int sock_set_event(PortState* port_state, SockState* sock_state, EPollEvent* event)
{
    uint events = event.events | EPOLLERR | EPOLLHUP;

    sock_state.user_events = events;
    sock_state.user_data = event.data;

    if ((events & SOCK_KNOWN_EPOLL_EVENTS & ~sock_state.pending_events) != 0)
    {
        port_request_socket_update(port_state, sock_state);
    }

    return 0;
}

fn DWord sock_epoll_events_to_afd_events(uint epoll_events)
{
    DWord afd_events = AFD_POLL_LOCAL_CLOSE;

    if ((epoll_events & (EPOLLIN | EPOLLRDNORM)) != 0)
    {
        afd_events |= AFD_POLL_RECEIVE | AFD_POLL_ACCEPT;
    }

    if ((epoll_events & (EPOLLPRI | EPOLLRDBAND)) != 0)
    {
        afd_events |= AFD_POLL_RECEIVE_EXPEDITED;
    }

    if ((epoll_events & (EPOLLOUT | EPOLLWRNORM | EPOLLWRBAND)) != 0)
    {
        afd_events |= AFD_POLL_SEND;
    }

    if ((epoll_events & (EPOLLIN | EPOLLRDNORM | EPOLLRDHUP)) != 0)
    {
        afd_events |= AFD_POLL_DISCONNECT;
    }

    if ((epoll_events & EPOLLHUP) != 0)
    {
        afd_events |= AFD_POLL_ABORT;
    }

    if ((epoll_events & EPOLLERR) != 0)
    {
        afd_events |= AFD_POLL_CONNECT_FAIL;
    }

    return afd_events;
}

fn uint sock_afd_events_to_epoll_events(DWord afd_events)
{
    uint epoll_events = 0;

    if ((afd_events & (AFD_POLL_RECEIVE | AFD_POLL_ACCEPT)) != 0)
    {
        epoll_events |= EPOLLIN | EPOLLRDNORM;
    }

    if ((afd_events & AFD_POLL_RECEIVE_EXPEDITED) != 0)
    {
        epoll_events |= EPOLLPRI | EPOLLRDBAND;
    }

    if ((afd_events & AFD_POLL_SEND) != 0)
    {
        epoll_events |= EPOLLOUT | EPOLLWRNORM | EPOLLWRBAND;
    }

    if ((afd_events & AFD_POLL_DISCONNECT) != 0)
    {
        epoll_events |= EPOLLIN | EPOLLRDNORM | EPOLLRDHUP;
    }

    if ((afd_events & AFD_POLL_ABORT) != 0)
    {
        epoll_events |= EPOLLHUP;
    }

    if ((afd_events & AFD_POLL_CONNECT_FAIL) != 0)
    {
        epoll_events |=
            EPOLLIN |
            EPOLLOUT |
            EPOLLERR |
            EPOLLRDNORM |
            EPOLLWRNORM |
            EPOLLRDHUP;
    }

    return epoll_events;
}

fn int sock_update(PortState* port_state, SockState* sock_state)
{
    @assert(!sock_state.delete_pending, "sock_update(): socket is delete pending");

    if (sock_state.poll_status == SOCK_POLL_PENDING &&
        (sock_state.user_events & SOCK_KNOWN_EPOLL_EVENTS & ~sock_state.pending_events) == 0)
    {
    }
    else if (sock_state.poll_status == SOCK_POLL_PENDING)
    {
        if (sock_cancel_poll(sock_state) < 0)
        {
            return -1;
        }
    }
    else if (sock_state.poll_status == SOCK_POLL_CANCELLED)
    {
    }
    else if (sock_state.poll_status == SOCK_POLL_IDLE)
    {
        sock_state.poll_info.exclusive = 0;
        sock_state.poll_info.numberOfHandles = 1;
        sock_state.poll_info.timeout.quadPart = 0x7fffffffffffffff;
        sock_state.poll_info.handles[0].handle = (Handle)sock_state.base_socket;
        sock_state.poll_info.handles[0].status = 0;
        sock_state.poll_info.handles[0].events =
            sock_epoll_events_to_afd_events(sock_state.user_events);

        if (afd_poll(
            poll_group_get_afd_device_handle(sock_state.poll_group),
            &sock_state.poll_info,
            &sock_state.io_status_block) < 0)
        {
            switch (winbase::getLastError())
            {
                case ERROR_IO_PENDING:
                    break;

                case ERROR_INVALID_HANDLE:
                    return sock_delete_impl(port_state, sock_state, false);

                default:
                    err_map_win_error();
                    return -1;
            }
        }

        sock_state.poll_status = SOCK_POLL_PENDING;
        sock_state.pending_events = sock_state.user_events;
    }
    else
    {
        @assert(false, "sock_update(): unreachable poll status");
    }

    port_cancel_socket_update(port_state, sock_state);

    return 0;
}

fn int sock_feed_event(PortState* port_state, IoStatusBlock* io_status_block, EPollEvent* event)
{
    SockState* sock_state = (SockState*)((char*)io_status_block - $reflect(SockState.io_status_block).offset);

    AfdPollInfo* poll_info = &sock_state.poll_info;
    uint epoll_events = 0;

    sock_state.poll_status = SOCK_POLL_IDLE;
    sock_state.pending_events = 0;

    if (sock_state.delete_pending)
    {
        return sock_delete_impl(port_state, sock_state, false);
    }

    if (io_status_block.status == STATUS_CANCELLED)
    {
    }
    else if (!nt_success(io_status_block.status))
    {
        epoll_events = EPOLLERR;
    }
    else if (poll_info.numberOfHandles < 1)
    {
    }
    else if ((poll_info.handles[0].events & AFD_POLL_LOCAL_CLOSE) != 0)
    {
        return sock_delete_impl(port_state, sock_state, false);
    }
    else
    {
        epoll_events = sock_afd_events_to_epoll_events(poll_info.handles[0].events);
    }

    port_request_socket_update(port_state, sock_state);

    epoll_events &= sock_state.user_events;

    if (epoll_events == 0)
    {
        return 0;
    }

    if ((sock_state.user_events & EPOLLONESHOT) != 0)
    {
        sock_state.user_events = 0;
    }

    event.data = sock_state.user_data;
    event.events = epoll_events;

    return 1;
}

// Port polling

fn int port_update_events(PortState* port_state)
{
    Queue* sock_update_queue = &port_state.sock_update_queue;

    while (!queue_is_empty(sock_update_queue))
    {
        QueueNode* queue_node = queue_first(sock_update_queue);
        SockState* sock_state = sock_state_from_queue_node(queue_node);

        if (sock_update(port_state, sock_state) < 0)
        {
            return -1;
        }
    }

    return 0;
}

fn void port_update_events_if_polling(PortState* port_state)
{
    if (port_state.active_poll_count > 0)
    {
        port_update_events(port_state);
    }
}

fn int port_feed_events(
    PortState* port_state,
    EPollEvent* epoll_events,
    winbase::OverlappedEntry* iocp_events,
    DWord iocp_event_count
)
{
    int epoll_event_count = 0;

    for (DWord i = 0; i < iocp_event_count; i++)
    {
        IoStatusBlock* io_status_block = (IoStatusBlock*)iocp_events[i].lpOverlapped;
        EPollEvent* event = &epoll_events[epoll_event_count];

        epoll_event_count += sock_feed_event(port_state, io_status_block, event);
    }

    return epoll_event_count;
}

fn int port_poll(
    PortState* port_state,
    EPollEvent* epoll_events,
    winbase::OverlappedEntry* iocp_events,
    DWord maxevents,
    DWord timeout
)
{
    DWord completion_count = 0;

    if (port_update_events(port_state) < 0)
    {
        return -1;
    }

    port_state.active_poll_count++;

    winbase::leaveCriticalSection(&port_state.lock);

    Bool ok = winbase::getQueuedCompletionStatusEx(
        port_state.iocp_handle,
        iocp_events,
        maxevents,
        &completion_count,
        timeout,
        (Bool)false
    );
    DWord error = 0;
    if (!ok) error = winbase::getLastError();
    
    winbase::enterCriticalSection(&port_state.lock);

    port_state.active_poll_count--;

    if (!ok)
    {
        winbase::setLastError(error);
        if (error == WAIT_TIMEOUT) return 0;
        return -1;
    }
    return port_feed_events(port_state, epoll_events, iocp_events, completion_count);
}

fn int port_wait(PortState* port_state, EPollEvent* events, int maxevents, int timeout)
{
    winbase::OverlappedEntry[PORT_MAX_ON_STACK_COMPLETIONS] stack_iocp_events;
    winbase::OverlappedEntry* iocp_events = null;

    ulong due = 0;
    DWord gqcs_timeout;
    int result = 0;

    if (maxevents <= 0)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        return -1;
    }

    if ((sz)maxevents <= PORT_MAX_ON_STACK_COMPLETIONS)
    {
        iocp_events = &stack_iocp_events[0];
    }
    else
    {
        iocp_events = (winbase::OverlappedEntry*)stdlib::malloc((sz)maxevents * winbase::OverlappedEntry::size);

        if (iocp_events == null)
        {
            iocp_events = &stack_iocp_events[0];
            maxevents = (int)PORT_MAX_ON_STACK_COMPLETIONS;
        }
    }

    if (timeout > 0)
    {
        due = winbase::getTickCount64() + (ulong)timeout;
        gqcs_timeout = (DWord)timeout;
    }
    else if (timeout == 0)
    {
        gqcs_timeout = 0;
    }
    else
    {
        gqcs_timeout = winbase::INFINITE;
    }

    winbase::enterCriticalSection(&port_state.lock);

    while (true)
    {
        result = port_poll(
            port_state,
            events,
            iocp_events,
            (DWord)maxevents,
            gqcs_timeout
        );

        if (result < 0 || result > 0)
        {
            break;
        }

        if (timeout < 0)
        {
            continue;
        }

        ulong now = winbase::getTickCount64();

        if (now >= due)
        {
            winbase::setLastError(WAIT_TIMEOUT);
            break;
        }

        gqcs_timeout = (DWord)(due - now);
    }

    port_update_events_if_polling(port_state);

    winbase::leaveCriticalSection(&port_state.lock);

    if (iocp_events != &stack_iocp_events[0])
    {
        stdlib::free(iocp_events);
    }

    if (result >= 0)
    {
        return result;
    }

    if (winbase::getLastError() == WAIT_TIMEOUT)
    {
        return 0;
    }

    return -1;
}

fn int port_ctl_add(PortState* port_state, Socket sock, EPollEvent* event)
{
    SockState* sock_state = sock_new(port_state, sock);
    if (sock_state == null) return -1;

    if (sock_set_event(port_state, sock_state, event) < 0)
    {
        sock_delete(port_state, sock_state);
        return -1;
    }

    port_update_events_if_polling(port_state);

    return 0;
}

fn int port_ctl_mod(PortState* port_state, Socket sock, EPollEvent* event)
{
    SockState* sock_state = port_find_socket(port_state, sock);
    if (sock_state == null) return -1;

    if (sock_set_event(port_state, sock_state, event) < 0)
    {
        return -1;
    }

    port_update_events_if_polling(port_state);

    return 0;
}

fn int port_ctl_del(PortState* port_state, Socket sock)
{
    SockState* sock_state = port_find_socket(port_state, sock);
    if (sock_state == null) return -1;

    sock_delete(port_state, sock_state);

    return 0;
}

fn int port_ctl_op(PortState* port_state, int op, Socket sock, EPollEvent* event)
{
    switch (op)
    {
        case EPOLL_CTL_ADD:
            return port_ctl_add(port_state, sock, event);

        case EPOLL_CTL_MOD:
            return port_ctl_mod(port_state, sock, event);

        case EPOLL_CTL_DEL:
            return port_ctl_del(port_state, sock);

        default:
            err_set_win_error(ERROR_INVALID_PARAMETER);
            return -1;
    }
}

fn int port_ctl(PortState* port_state, int op, Socket sock, EPollEvent* event)
{
    int result;

    winbase::enterCriticalSection(&port_state.lock);
    result = port_ctl_op(port_state, op, sock, event);
    winbase::leaveCriticalSection(&port_state.lock);

    return result;
}

// Public epoll API

fn Handle epoll_create_internal()
{
    if (init() < 0) return null;

    Handle ephnd = null;
    PortState* port_state = port_new(&ephnd);
    if (port_state == null) return null;

    TsTreeNode* tree_node = port_state_to_handle_tree_node(port_state);

    if (ts_tree_add(&epoll_handle_tree, tree_node, (uptr)ephnd) < 0)
    {
        port_delete(port_state);
        err_set_win_error(ERROR_ALREADY_EXISTS);
        return null;
    }

    return ephnd;
}

fn EPollFd epoll_create(int size)
{
    if (size <= 0)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        return null;
    }

    return epoll_create_internal();
}

fn EPollFd epoll_create1(int flags)
{
    if (flags != 0)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        return null;
    }

    return epoll_create_internal();
}

fn int epoll_close(EPollFd ephnd)
{
    if (init() < 0) return -1;

    TsTreeNode* tree_node = ts_tree_del_and_ref(&epoll_handle_tree, (uptr)ephnd);
    if (tree_node == null)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        err_check_handle(ephnd);
        return -1;
    }

    PortState* port_state = port_state_from_handle_tree_node(tree_node);

    port_close(port_state);

    ts_tree_node_unref_and_destroy(tree_node);

    return port_delete(port_state);
}

fn int epoll_ctl(EPollFd ephnd, int op, Socket sock, EPollEvent* event)
{
    if (init() < 0) return -1;

    TsTreeNode* tree_node = ts_tree_find_and_ref(&epoll_handle_tree, (uptr)ephnd);
    if (tree_node == null)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        err_check_handle(ephnd);
        err_check_handle((Handle)sock);
        return -1;
    }

    PortState* port_state = port_state_from_handle_tree_node(tree_node);

    int r = port_ctl(port_state, op, sock, event);

    ts_tree_node_unref(tree_node);

    if (r < 0)
    {
        err_check_handle(ephnd);
        err_check_handle((Handle)sock);
        return -1;
    }

    return 0;
}

fn int epoll_wait(EPollFd ephnd, EPollEvent* events, int maxevents, int timeout)
{
    if (maxevents <= 0)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        return -1;
    }

    if (init() < 0) return -1;

    TsTreeNode* tree_node = ts_tree_find_and_ref(&epoll_handle_tree, (uptr)ephnd);
    if (tree_node == null)
    {
        err_set_win_error(ERROR_INVALID_PARAMETER);
        err_check_handle(ephnd);
        return -1;
    }

    PortState* port_state = port_state_from_handle_tree_node(tree_node);

    int num_events = port_wait(port_state, events, maxevents, timeout);

    ts_tree_node_unref(tree_node);

    if (num_events < 0)
    {
        err_check_handle(ephnd);
        return -1;
    }

    return num_events;
}

// eof