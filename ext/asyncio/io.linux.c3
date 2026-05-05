// io.linux.c3

// Linux async I/O backend using io_uring (kernel ≥ 5.1, off=-1 requires ≥ 5.6)

module ext::asyncio @if(env::LINUX);

import std::io;
import c::stdlib;
import c::unistd;
import c::fcntl;
import c::string;
import c::netinet::in;
import c::sys::socket;
import c::sys::mman;
import c::sys::syscall;
import c::errno;
import c::sys::stat;
import ext::debug;
import ext::mem;


fn int _uring_setup(uint entries, IoUringParams* p) @inline @private 
{
    return (int)syscall::syscall(syscall::SYS_IO_URING_SETUP, (long)entries, (long)p);
}

fn int _uring_enter(int fd, uint to_submit, uint min_complete, uint flags) @inline @private 
{
    return (int)syscall::syscall(syscall::SYS_IO_URING_ENTER,
        (long)fd, (long)to_submit, (long)min_complete,
        (long)flags, (long)null, (long)0);
}

//  io_uring constants 

alias UInt8 = char;
alias UInt16 = ushort;

const UInt8 IORING_OP_READ          = 22;
const UInt8 IORING_OP_WRITE         = 23;
const UInt8 IORING_OP_RECV          = 27;
const UInt8 IORING_OP_SEND          = 26;
const UInt8 IORING_OP_RECVMSG       = 10;
const UInt8 IORING_OP_SENDMSG       = 9;
const UInt8 IORING_OP_TIMEOUT       = 11;
const UInt8 IORING_OP_POLL_ADD      = 6;
const UInt8 IORING_OP_POLL_REMOVE   = 7;

const uint IORING_ENTER_GETEVENTS   = 1;

const ulong IORING_OFF_SQ_RING      = 0;
const ulong IORING_OFF_CQ_RING      = 0x8000000;
const ulong IORING_OFF_SQES         = 0x10000000;

const ulong URING_TIMEOUT_UD        = ~0UL; // sentinel: discard CQE
const ulong URING_POLL_TAG          = 1UL << 63; // distinguishes poll-add CQEs

const uint  POLLIN                  = 0x0001;
const uint  POLLOUT                 = 0x0004;

// MAP_POPULATE may not be in all C3 mman bindings; define as fallback
const int MAP_POPULATE_HINT         = 0x08000;

//  io_uring structures 

struct IoSqringOffsets {
    uint head, tail, ring_mask, ring_entries, flags, dropped, array, resv1;
    ulong resv2;
}
struct IoCqringOffsets {
    uint head, tail, ring_mask, ring_entries, overflow, cqes, flags, resv1;
    ulong resv2;
}
struct IoUringParams {
    uint sq_entries, cq_entries, flags, sq_thread_cpu, sq_thread_idle;
    uint features, wq_fd;
    uint[3] resv;
    IoSqringOffsets sq_off;
    IoCqringOffsets cq_off;
}

// 64-byte SQE
struct IoUringSqe {
    UInt8  opcode, flags;
    UInt16 ioprio;
    int    fd;
    ulong  off;       // file offset; -1 = current pos (kernel ≥ 5.6)
    ulong  addr;      // buffer ptr or &msghdr
    uint   len;       // buffer length or iov count
    uint   op_flags;  // per-opcode flags (poll events, msg flags, …)
    ulong  user_data;
    UInt16 buf_index, personality;
    int    splice_fd_in;
    ulong  pad1, pad2;
}

// 16-byte CQE
struct IoUringCqe {
    ulong user_data;
    int   res;
    uint  flags;
}

struct KernelTimespec { long tv_sec, tv_nsec; }

// Minimal iovec / msghdr kept for potential future use (e.g. sendmsg fallback).
// Currently async_recvfrom and async_sendto use POLL_ADD + syscall instead.
struct UringIov    { void* iov_base; usz iov_len; }
struct UringMsgHdr {
    void*      msg_name;
    uint       msg_namelen;
    UringIov*  msg_iov;
    usz        msg_iovlen;
    void*      msg_control;
    usz        msg_controllen;
    int        msg_flags;
}

//  op pool (used by async_read / async_write only)
//  Buffers are caller-provided; ops carry no inline storage.

const usz URING_ENTRIES  = 512;     // SQ / CQ size (power of 2)
const usz URING_OP_POOL  = 64;      // max simultaneous async ops

struct UringOp {
    bool    active;
    int     result;    // filled by io_poll from CQE.res  (default -1)
    Future* future;
}

tlocal UringOp[URING_OP_POOL] _op_pool;
tlocal usz _active_op_count;

fn usz _op_alloc() @private 
{
    for (usz i = 0; i < URING_OP_POOL; i++) {
        if (!_op_pool[i].active) {
            string::memset(&_op_pool[i], 0, UringOp.sizeof);
            _op_pool[i].active = true;
            _op_pool[i].result = -1;
            _active_op_count++;
            return i;
        }
    }
    @assert(false, "asyncio/uring: op pool exhausted");
    return usz.max;
}

fn void _op_free(usz i) @private
{
    _op_pool[i].active = false;
    _op_pool[i].future = null;
    _active_op_count--;
}

//  fd watch table (for POLL_ADD – register_read / register_write) 

const usz MAX_FD_WATCH = 4096;
const usz MAX_EVENTS   = 512;

struct FdWatch {
    int     fd;
    bool    active;
    Future* read_fut;
    Future* write_fut;
}

tlocal FdWatch[MAX_FD_WATCH] _fd_table;
tlocal usz _fd_count;

//  ring state 

tlocal int   _ring_fd    = -1;
tlocal void* _sq_ring    = null;  tlocal usz _sq_ring_sz = 0;
tlocal void* _cq_ring    = null;  tlocal usz _cq_ring_sz = 0;
tlocal void* _sqes_map   = null;  tlocal usz _sqes_sz    = 0;

tlocal uint*       _sq_head;
tlocal uint*       _sq_tail_k;    // kernel's sq tail pointer (we write)
tlocal uint*       _sq_mask;
tlocal uint*       _sq_entries_p;
tlocal uint*       _sq_array;
tlocal IoUringSqe* _sqes;
tlocal uint        _sq_tail_l;    // our local sq tail counter
tlocal uint        _pending;      // SQEs queued but not yet sent to kernel

tlocal uint*       _cq_head_k;    // kernel's cq head pointer (we write)
tlocal uint*       _cq_tail;
tlocal uint*       _cq_mask;
tlocal IoUringCqe* _cqes;

tlocal KernelTimespec _ts;

fn UInt8* _rp(void* base, uint off) @inline @private
{
    return (UInt8*)base + off;
}

//  init / destroy 

tlocal bool initialized = false;

fn void io_init() @private
{
    if (initialized) return;
    initialized = true;

    IoUringParams p = {};
    _ring_fd = _uring_setup(URING_ENTRIES, &p);
    @assert(_ring_fd >= 0, "asyncio: io_uring_setup failed (kernel ≥ 5.1 required)");

    //  mmap SQ ring 
    _sq_ring_sz = (usz)p.sq_off.array + (usz)p.sq_entries * 4;
    _sq_ring = mman::mmap(null, _sq_ring_sz,
        mman::PROT_READ | mman::PROT_WRITE,
        mman::MAP_SHARED | MAP_POPULATE_HINT,
        _ring_fd, (long)IORING_OFF_SQ_RING);
    @assert((iptr)_sq_ring != mman::MAP_FAILED, "asyncio: mmap SQ ring failed");

    //  mmap SQE array 
    _sqes_sz = (usz)p.sq_entries * IoUringSqe.sizeof;
    _sqes_map = mman::mmap(null, _sqes_sz,
        mman::PROT_READ | mman::PROT_WRITE,
        mman::MAP_SHARED | MAP_POPULATE_HINT,
        _ring_fd, (long)IORING_OFF_SQES);
    @assert((iptr)_sqes_map != mman::MAP_FAILED, "asyncio: mmap SQEs failed");

    //  mmap CQ ring 
    _cq_ring_sz = (usz)p.cq_off.cqes + (usz)p.cq_entries * IoUringCqe.sizeof;
    _cq_ring = mman::mmap(null, _cq_ring_sz,
        mman::PROT_READ | mman::PROT_WRITE,
        mman::MAP_SHARED | MAP_POPULATE_HINT,
        _ring_fd, (long)IORING_OFF_CQ_RING);
    @assert((iptr)_cq_ring != mman::MAP_FAILED, "asyncio: mmap CQ ring failed");

    //  SQ pointers 
    _sq_head      = (uint*)_rp(_sq_ring, p.sq_off.head);
    _sq_tail_k    = (uint*)_rp(_sq_ring, p.sq_off.tail);
    _sq_mask      = (uint*)_rp(_sq_ring, p.sq_off.ring_mask);
    _sq_entries_p = (uint*)_rp(_sq_ring, p.sq_off.ring_entries);
    _sq_array     = (uint*)_rp(_sq_ring, p.sq_off.array);
    _sqes         = (IoUringSqe*)_sqes_map;

    // Pre-populate sq_array: position i → SQE slot i (fixed mapping)
    for (uint i = 0; i < p.sq_entries; i++) _sq_array[i] = i;

    //  CQ pointers 
    _cq_head_k = (uint*)_rp(_cq_ring, p.cq_off.head);
    _cq_tail   = (uint*)_rp(_cq_ring, p.cq_off.tail);
    _cq_mask   = (uint*)_rp(_cq_ring, p.cq_off.ring_mask);
    _cqes      = (IoUringCqe*)_rp(_cq_ring, p.cq_off.cqes);

    _sq_tail_l = 0;
    _pending   = 0;
}

fn void io_destroy() @private
{
    if (!initialized) return;
    mman::munmap(_sq_ring,  _sq_ring_sz);
    mman::munmap(_sqes_map, _sqes_sz);
    mman::munmap(_cq_ring,  _cq_ring_sz);
    unistd::close(_ring_fd);
    _ring_fd     = -1;
    initialized  = false;
}

//  SQE helpers 

// Returns a zeroed SQE slot; flushes ring first if full.
fn IoUringSqe* _get_sqe() @inline @private 
{
    uint avail = *_sq_entries_p - (_sq_tail_l - *_sq_head);
    if (avail == 0) {
        // Ring full – flush now so we can keep going
        *_sq_tail_k = _sq_tail_l;
        _uring_enter(_ring_fd, _pending, 0, 0);
        _pending = 0;
    }
    uint idx = _sq_tail_l & *_sq_mask;
    _sq_tail_l++;
    _pending++;
    IoUringSqe* sqe = &_sqes[idx];
    string::memset(sqe, 0, IoUringSqe.sizeof);
    return sqe;
}

// Publish queued SQEs to the kernel without waiting for completions.
fn void _flush_submit() @inline @private
{
    if (_pending == 0) return;
    *_sq_tail_k = _sq_tail_l;
    _uring_enter(_ring_fd, _pending, 0, 0);
    _pending = 0;
}

fn bool _is_socket(int fd) @private
{
    int t; socket::SockLen l = $sizeof(t);
    return socket::getsockopt(fd, socket::SOL_SOCKET, socket::SO_TYPE, &t, &l) == 0;
}

//  CQE processing 

fn void _process_cqes() @private
{
    uint head = *_cq_head_k;
    uint tail = *_cq_tail;
    uint mask = *_cq_mask;

    while (head != tail) {
        IoUringCqe* cqe = &_cqes[head & mask];
        ulong ud  = cqe.user_data;
        int   res = cqe.res;
        head++;

        //  timeout sentinel 
        if (ud == URING_TIMEOUT_UD) {
            continue;
        }

        //  poll-add completion (register_read / register_write) 
        if (ud & URING_POLL_TAG) {
            ulong tag = ud & ~URING_POLL_TAG;
            int   fd  = (int)(tag >> 1);
            bool  wr  = (tag & 1) != 0;
            if ((usz)fd < MAX_FD_WATCH && _fd_table[fd].active) {
                FdWatch* w = &_fd_table[fd];
                if (wr) {
                    if (w.write_fut != null) {
                        Future* f = w.write_fut; w.write_fut = null;
                        if (res < 0) { f.set_exception(IO_ERROR); f.cancel("poll error"); }
                        else          { f.set_result(null); }
                    }
                } else {
                    if (w.read_fut != null) {
                        Future* f = w.read_fut; w.read_fut = null;
                        if (res < 0) { f.set_exception(IO_ERROR); f.cancel("poll error"); }
                        else          { f.set_result(null); }
                    }
                }
                if (w.read_fut == null && w.write_fut == null) {
                    w.active = false; _fd_count--;
                }
            }
            continue;
        }

        //  I/O op completion 
        if (ud < URING_OP_POOL) {
            UringOp* op = &_op_pool[ud];
            if (!op.active) continue; // stale / already freed
            op.result = res;
            Future* fut = op.future;
            if (fut != null) {
                if (res < 0) { fut.set_exception(IO_ERROR); fut.cancel("io error"); }
                else          { fut.set_result(null); }
            }
        }
    }
    *_cq_head_k = head; // advance CQ head (consume CQEs)
}

//  io_pending / io_poll 

fn bool io_pending() @inline @private
{
    return _active_op_count > 0 || _fd_count > 0;
}

fn void io_poll(ulong timeout_us) @private
{
    if (!io_pending()) return;

    // Always submit a TIMEOUT SQE.
    // When timeout_us=0 → ts={0,0} → kernel fires the CQE immediately.
    // This guarantees min_complete=1 never blocks forever, even when
    // the event loop calls io_poll(0) (timer already expired, no wait needed).
    _ts.tv_sec  = (long)(timeout_us / 1_000_000);
    _ts.tv_nsec = (long)((timeout_us % 1_000_000) * 1000);
    IoUringSqe* tsqe = _get_sqe();
    tsqe.opcode    = IORING_OP_TIMEOUT;
    tsqe.fd        = -1;
    tsqe.addr      = (ulong)(iptr)&_ts;
    tsqe.len       = 0;  // pure time-based; not linked to completion count
    tsqe.user_data = URING_TIMEOUT_UD;

    // Publish SQ tail, then block until ≥ 1 completion (TIMEOUT guarantees return).
    *_sq_tail_k = _sq_tail_l;
    uint to_submit = _pending;
    _pending = 0;

    _uring_enter(_ring_fd, to_submit, 1, IORING_ENTER_GETEVENTS);
    _process_cqes();
}

//  poll-add helpers for register_read / register_write 

fn FdWatch* _find_or_create(int fd) @private
{
    @assert(fd >= 0 && (usz)fd < MAX_FD_WATCH, "asyncio: fd out of range");
    FdWatch* w = &_fd_table[fd];
    if (!w.active) { *w = {}; w.fd = fd; w.active = true; _fd_count++; }
    return w;
}

fn FdWatch* _find(int fd) @private
{
    if (fd < 0 || (usz)fd >= MAX_FD_WATCH) return null;
    FdWatch* w = &_fd_table[fd];
    return w.active ? w : null;
}

fn void _poll_add(int fd, bool want_write) @private
{
    IoUringSqe* sqe = _get_sqe();
    sqe.opcode    = IORING_OP_POLL_ADD;
    sqe.fd        = fd;
    sqe.op_flags  = want_write ? POLLOUT : POLLIN;
    sqe.user_data = URING_POLL_TAG | ((ulong)fd << 1) | (want_write ? 1UL : 0UL);
}

fn void register_read(int fd, Future* future) @private
{
    FdWatch* w = _find_or_create(fd);
    if (w.read_fut != null) w.read_fut.cancel("register_read: replaced");
    w.read_fut = future;
    _poll_add(fd, false);
    _flush_submit();
}

fn void register_write(int fd, Future* future) @private
{
    FdWatch* w = _find_or_create(fd);
    if (w.write_fut != null) w.write_fut.cancel("register_write: replaced");
    w.write_fut = future;
    _poll_add(fd, true);
    _flush_submit();
}

fn void unregister(int fd) @private
{
    FdWatch* w = _find(fd);
    if (w == null) return;
    if (w.read_fut)  { w.read_fut.cancel("fd unregistered");  w.read_fut  = null; }
    if (w.write_fut) { w.write_fut.cancel("fd unregistered"); w.write_fut = null; }

    // Try to cancel any in-flight POLL_ADD SQEs for this fd.
    IoUringSqe* sqe = _get_sqe();
    sqe.opcode    = IORING_OP_POLL_REMOVE;
    sqe.user_data = 0;
    sqe.addr      = URING_POLL_TAG | ((ulong)fd << 1);        // read poll ud

    sqe = _get_sqe();
    sqe.opcode    = IORING_OP_POLL_REMOVE;
    sqe.user_data = 0;
    sqe.addr      = URING_POLL_TAG | ((ulong)fd << 1) | 1UL;  // write poll ud
    _flush_submit();

    w.active = false;
    _fd_count--;
}

//  set_nonblocking (kept for compatibility; io_uring doesn't require it) 

fn bool set_nonblocking(int fd)
{
    int flags = fcntl::fcntl(fd, fcntl::F_GETFL, 0);
    if (flags < 0) return false;
    return fcntl::fcntl(fd, fcntl::F_SETFL, flags | fcntl::O_NONBLOCK) == 0;
}

fn bool _would_block() @inline @private
{
    int e = errno::errno();
    return e == errno::EAGAIN || e == errno::EWOULDBLOCK;
}

//  async_read 
// Submits IORING_OP_RECV (socket) or IORING_OP_READ (file) targeting the
// caller-provided buffer directly (zero-copy).  No EAGAIN retry loop needed:
// io_uring delivers the completion when data is ready.
//
// The caller's buf must remain valid until this call returns.  Since the
// fiber awaits the future here, the buffer (typically on the caller's
// fiber stack or heap) is naturally pinned for the duration of the op.

fn usz? async_read(int fd, void* buf, usz len)
{
    EventLoop* loop = asyncio::get_running_loop();

    usz slot = _op_alloc();
    if (slot == usz.max) return IO_ERROR~;
    UringOp* op = &_op_pool[slot];

    Future* fut = loop.create_future();
    op.future = fut;

    IoUringSqe* sqe = _get_sqe();
    if (_is_socket(fd)) {
        sqe.opcode   = IORING_OP_RECV;
        sqe.op_flags = 0;
    } else {
        sqe.opcode = IORING_OP_READ;
        sqe.off    = (ulong)-1; // use current file position (kernel ≥ 5.6)
    }
    sqe.fd        = fd;
    sqe.addr      = (ulong)(iptr)buf;
    sqe.len       = (uint)len;
    sqe.user_data = (ulong)slot;
    _flush_submit();

    void*? raw = fut.await();
    fault   ferr = fut.error;
    int     res  = op.result;
    fut.free();
    _op_free(slot);

    if (catch err = raw) {
        if (ferr == IO_ERROR) return IO_ERROR~;
        return err~;
    }
    if (res < 0) return IO_ERROR~;
    return (usz)res;
}

//  async_write 
// Submits IORING_OP_SEND (socket) or IORING_OP_WRITE (file) directly
// from the caller-provided buffer (zero-copy).  Loops only on partial
// writes (the kernel may return fewer bytes than requested), advancing
// the offset into the caller buffer each iteration.

fn usz? async_write(int fd, void* buf, usz len)
{
    EventLoop* loop = asyncio::get_running_loop();
    bool is_sock = _is_socket(fd);
    usz total = 0;

    while (total < len) {
        usz slot = _op_alloc();
        if (slot == usz.max) return total > 0 ? total : IO_ERROR~;
        UringOp* op = &_op_pool[slot];

        Future* fut = loop.create_future();
        op.future = fut;

        IoUringSqe* sqe = _get_sqe();
        if (is_sock) {
            sqe.opcode   = IORING_OP_SEND;
            sqe.op_flags = 0;
        } else {
            sqe.opcode = IORING_OP_WRITE;
            sqe.off    = (ulong)-1;
        }
        sqe.fd        = fd;
        sqe.addr      = (ulong)(iptr)((char*)buf + total);
        sqe.len       = (uint)(len - total);
        sqe.user_data = (ulong)slot;
        _flush_submit();

        void*? raw = fut.await();
        fault   ferr = fut.error;
        int     res  = op.result;
        fut.free();
        _op_free(slot);

        if (catch err = raw) {
            if (total > 0) return total;
            if (ferr == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        if (res <= 0) return total > 0 ? total : IO_ERROR~;
        total += (usz)res;
    }
    return total;
}

//  async_recvfrom
// Uses POLL_ADD (register_read) + blocking recvfrom(), same model as the
// epoll backend.  This is intentional: IORING_OP_RECVMSG keeps an SQE
// permanently inside the kernel and cannot be cancelled by unregister(fd)
// alone.  With POLL_ADD the FdWatch future is cancelled the moment the
// transport calls unregister / close_file, so the datagram receive loop
// always exits cleanly without leaving orphaned ops in the ring.

fn usz? async_recvfrom(int fd, void* buf, usz len, char* ip_str, usz* ip_len, ushort* port)
{
    EventLoop* loop = asyncio::get_running_loop();

    while (true) {
        socket::SockAddrStorage ss;
        socket::SockLen sslen = $sizeof(ss);

        isz n = socket::recvfrom(fd, buf, len, 0, (socket::SockAddr*)&ss, &sslen);
        if (n >= 0) {
            if (ip_str != null || port != null) {
                if (ss.ss_family == (ushort)socket::AF_INET6) {
                    in::SockAddrIn6* a6 = (in::SockAddrIn6*)&ss;
                    in::inet_ntop(socket::AF_INET6, &a6.sin6_addr, ip_str, 46);
                    if (ip_len) *ip_len = (usz)string::strlen(ip_str);
                    if (port)   *port   = in::ntohs(a6.sin6_port);
                } else {
                    in::SockAddrIn* a4 = (in::SockAddrIn*)&ss;
                    in::inet_ntop(socket::AF_INET, &a4.sin_addr, ip_str, 16);
                    if (ip_len) *ip_len = (usz)string::strlen(ip_str);
                    if (port)   *port   = in::ntohs(a4.sin_port);
                }
            }
            return (usz)n;
        }

        if (!_would_block()) return errno::get_fault()~;

        // Wait for POLLIN via POLL_ADD.  unregister(fd) / close_file(fd)
        // will cancel this future, which unblocks the loop immediately.
        Future* fut = loop.create_future();
        register_read(fd, fut);

        void*? res = fut.await();
        fault ferror = fut.error;

        if (catch err = res) {
            FdWatch* w = _find(fd);
            if (w != null) w.read_fut = null;
            fut.free();
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        fut.free();
    }
}

//  async_sendto
// Uses POLL_ADD (register_write) + blocking sendto() for the same reason
// as async_recvfrom: ensures the fd can be cancelled cleanly via unregister.
// UDP sends almost never block (kernel buffers the packet immediately), so
// the fast path just calls sendto() directly without entering the poller.

fn usz? async_sendto(int fd, void* buf, usz len, char* ip_str, ushort port)
{
    EventLoop* loop = asyncio::get_running_loop();

    // Resolve destination address
    in::SockAddrIn  a4 = {};
    in::SockAddrIn6 a6 = {};
    socket::SockAddr* dest_addr;
    socket::SockLen dest_len;

    if (string::strchr(ip_str, ':') != null) {
        if (in::inet_pton(socket::AF_INET6, ip_str, &a6.sin6_addr) != 1)  return errno::get_fault()~;
        a6.sin6_family = (ushort)socket::AF_INET6;
        a6.sin6_port   = in::htons(port);
        dest_addr = (socket::SockAddr*)&a6;
        dest_len  = $sizeof(a6);
    } else {
        if (in::inet_pton(socket::AF_INET, ip_str, &a4.sin_addr) != 1) return errno::get_fault()~;
        a4.sin_family = (ushort)socket::AF_INET;
        a4.sin_port   = in::htons(port);
        dest_addr = (socket::SockAddr*)&a4;
        dest_len  = $sizeof(a4);
    }

    while (true) {
        isz n = socket::sendto(fd, (char*)buf, len, 0, dest_addr, dest_len);
        if (n > 0) return (usz)n;
        if (n == 0) break;

        if (!_would_block()) return errno::get_fault()~;

        Future* fut = loop.create_future();
        register_write(fd, fut);

        void*? res = fut.await();
        fault ferror = fut.error;

        if (catch err = res) {
            FdWatch* w = _find(fd);
            if (w != null) w.write_fut = null;
            fut.free();
            if (ferror == IO_ERROR) return IO_ERROR~;
            return err~;
        }
        fut.free();
    }
    return 0;
}

//  file helpers (same semantics as io.posix.c3) 

fn int? open_file(String path, String mode)
{
    char[256] buf;
    char* path_cstr = str2cptr(path, &buf);

    int flags = 0;
    switch (mode) {
      case "r":  flags = fcntl::O_RDONLY;
      case "r+": flags = fcntl::O_CREAT | fcntl::O_RDWR;
      case "w":  flags = fcntl::O_RDWR  | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "w+": flags = fcntl::O_RDWR  | fcntl::O_CREAT | fcntl::O_TRUNC;
      case "a":  flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_WRONLY;
      case "a+": flags = fcntl::O_CREAT | fcntl::O_APPEND | fcntl::O_RDWR;
      default:   return errno::E_INVALID_ARG~;
    }
    stat::umask(0);
    int fd = fcntl::open(path_cstr, flags, 0o644);
    if (fd < 0) return errno::get_fault()~;
    // set_nonblocking not strictly required with io_uring but kept for consistency
    set_nonblocking(fd);
    return fd;
}

fn void close_file(int fd)
{
    unregister(fd);
    unistd::close(fd);
}

// off_t = long

fn long io_seek(int fd, long pos, int whence)
{
    return unistd::lseek(fd, pos, whence);
}
fn long io_tell(int fd)
{
    return unistd::lseek(fd, 0, unistd::SEEK_CUR);
}
fn int io_truncate(int fd, long pos)
{
    return unistd::ftruncate(fd, pos);
}
fn void io_flush(int fd)
{
    unistd::fsync(fd);
}
fn long io_size(int fd)
{
    stat::Stat_t st;
    stat::fstat(fd, &st);
    return (long)st.st_size;
}

fn int io_stdin()  { 
    set_nonblocking(0);
    return 0;
}
fn int io_stdout() { 
    set_nonblocking(1); 
    return 1;
}
fn int io_stderr() { 
    set_nonblocking(2);
    return 2;
}
