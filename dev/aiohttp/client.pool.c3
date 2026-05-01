// client.pool.c3

module ext::aiohttp;

import ext::asyncio;
import ext::mem;
import ext::debug;
import ext::thread::fiber;

// HTTP/1.1 connection pool — used internally by TcpConnector.
//
// Design:
//   - One ConnPool per (host, port) pair, stored in a flat PoolTable.
//   - Each ConnPool holds a free-list of idle Stream* with per-entry
//     keepalive timestamps, and an asyncio Semaphore that enforces
//     limit_per_host.
//   - A global Semaphore on PoolTable enforces the total connection limit.
//   - acquire() either returns an idle Stream* from the free-list or opens
//     a new TCP connection via asyncio::open_connection().
//   - release() returns the Stream* to the free-list (or closes it when
//     force_close is set or the pool is shutting down).
//   - reap() scans idle connections older than keepalive_timeout_us and
//     closes them; should be called periodically by the event loop.
//
// Thread-safety:
//   All operations run inside asyncio fibers on the event-loop thread.
//   No OS-level locking is used; asyncio Semaphore / Queue handle
//   fiber scheduling.

//  constants 

const usz POOL_MAX_IDLE_PER_HOST @private = 32;  // hard cap on free-list length
const usz POOL_HOST_KEY_MAX      @private = 256; // max "host:port" key length

//  idle connection entry 

struct IdleConn @private {
    Stream* stream;
    ulong   idle_since_us; // asyncio::clock_now() at the time of release
}

//  per-host connection pool 

struct ConnPool @private {
    // host key: "host:port\0" (null-terminated for easy debug printing)
    char[POOL_HOST_KEY_MAX] key;
    usz  key_len;

    // free-list of idle connections (ring buffer)
    IdleConn[POOL_MAX_IDLE_PER_HOST] idle;
    usz idle_head; // next pop position
    usz idle_tail; // next push position
    usz idle_count;

    // per-host semaphore (limit_per_host). null = unlimited.
    Semaphore* sem;

    // total connections currently open (idle + active)
    int total;

    bool closed;
}

fn usz ConnPool.idle_cap(&self) @inline
{
    return POOL_MAX_IDLE_PER_HOST;
}

// Push an idle connection onto the free-list.
// Returns false if the list is full.
fn bool ConnPool.push_idle(&self, Stream* s, ulong now_us)
{
    if (self.idle_count >= self.idle_cap()) return false;
    self.idle[self.idle_tail & (POOL_MAX_IDLE_PER_HOST - 1)] = (IdleConn){
        .stream       = s,
        .idle_since_us = now_us,
    };
    self.idle_tail++;
    self.idle_count++;
    return true;
}

// Pop the most-recently-used idle connection (LIFO — better for keepalive).
// Returns null if the list is empty.
fn Stream* ConnPool.pop_idle(&self)
{
    if (self.idle_count == 0) return null;
    self.idle_tail--;
    IdleConn* e = &self.idle[self.idle_tail & (POOL_MAX_IDLE_PER_HOST - 1)];
    self.idle_count--;
    return e.stream;
}

// Close and remove idle connections older than max_age_us.
// Returns the number of connections closed.
fn usz ConnPool.reap_idle(&self, ulong now_us, ulong max_age_us)
{
    usz closed_count = 0;
    // scan from head (oldest) forward
    while (self.idle_count > 0) {
        IdleConn* e = &self.idle[self.idle_head & (POOL_MAX_IDLE_PER_HOST - 1)];
        if (now_us - e.idle_since_us < max_age_us) break; // rest are newer
        e.stream.close();
        self.idle_head++;
        self.idle_count--;
        self.total--;
        closed_count++;
    }
    return closed_count;
}

// Close all idle connections (drain on shutdown).
fn void ConnPool.drain_idle(&self)
{
    while (self.idle_count > 0) {
        IdleConn* e = &self.idle[self.idle_head & (POOL_MAX_IDLE_PER_HOST - 1)];
        e.stream.close();
        self.idle_head++;
        self.idle_count--;
        self.total--;
    }
}

//  pool table 

const usz POOL_TABLE_CAP @private = 64; // max distinct (host, port) pairs

struct PoolTable @private {
    ConnPool[POOL_TABLE_CAP] pools;
    usz pool_count;

    Semaphore* global_sem; // total connection limit. null = unlimited.

    // config (copied from TcpConnector)
    int   limit;
    int   limit_per_host;
    double keepalive_timeout;
    bool  force_close;

    bool closed;
}

// Write "host:port" into buf[POOL_HOST_KEY_MAX]. Returns length (no null needed).
fn usz pool_make_key(char* buf, String host, ushort port) @private
{
    usz j = 0;
    usz hlen = host.len < (POOL_HOST_KEY_MAX - 7) ? host.len : (POOL_HOST_KEY_MAX - 7);
    for (usz i = 0; i < hlen; i++) buf[j++] = host[i];
    buf[j++] = ':';
    // format port digits
    char[5] digits;
    usz dlen = 0;
    uint p = (uint)port;
    if (p == 0) { digits[dlen++] = '0'; }
    else { while (p > 0) { digits[dlen++] = (char)('0' + p % 10); p /= 10; } }
    // reverse
    for (usz i = 0; i < dlen; i++) buf[j++] = digits[dlen - 1 - i];
    buf[j] = 0;
    return j;
}

fn bool key_eq(char* a, usz alen, char* b, usz blen) @private @inline
{
    if (alen != blen) return false;
    for (usz i = 0; i < alen; i++) if (a[i] != b[i]) return false;
    return true;
}

// Find or create a ConnPool for (host, port).
fn ConnPool*? PoolTable.get_or_create(&self, String host, ushort port, Allocator alloc)
{
    localmem = alloc;
    
    char[POOL_HOST_KEY_MAX] key;
    usz klen = pool_make_key(&key[0], host, port);

    // linear search (POOL_TABLE_CAP is small)
    for (usz i = 0; i < self.pool_count; i++) {
        ConnPool* cp = &self.pools[i];
        if (key_eq(&cp.key[0], cp.key_len, &key[0], klen)) return cp;
    }

    if (self.pool_count >= POOL_TABLE_CAP) return CONNECTION_FAILED ~;

    ConnPool* cp = &self.pools[self.pool_count++];
    for (usz i = 0; i < klen; i++) cp.key[i] = key[i];
    cp.key[klen] = 0;
    cp.key_len   = klen;
    cp.idle_head = 0;
    cp.idle_tail = 0;
    cp.idle_count = 0;
    cp.total     = 0;
    cp.closed    = false;

    if (self.limit_per_host > 0) {
        cp.sem = asyncio::semaphore_new(self.limit_per_host);
    } else {
        cp.sem = null;
    }

    return cp;
}

//  public pool API 

// Initialise a PoolTable from TcpConnector config.
// Call once after allocating the TcpConnector.
fn void? pool_init(
    PoolTable*  pt,
    int         limit,
    int         limit_per_host,
    double       keepalive_timeout,
    bool        force_close,
    Allocator   alloc,
)
{
    localmem = alloc;
    
    pt.pool_count           = 0;
    pt.limit                = limit;
    pt.limit_per_host       = limit_per_host;
    pt.keepalive_timeout = keepalive_timeout;
    pt.force_close          = force_close;
    pt.closed               = false;

    if (limit > 0) {
        pt.global_sem = asyncio::semaphore_new(limit);
    } else {
        pt.global_sem = null;
    }
}

// Acquire a Stream* for (host, port).
// Blocks the calling fiber if the connection limit is reached.
// Returns a reused idle connection when available, otherwise opens a new TCP connection.
// On return the caller owns the Stream* until pool_release() is called.
fn Stream*? pool_acquire(
    PoolTable*  pt,
    String      host,
    ushort      port,
    double      connect_timeout,
    Allocator   alloc,
)
{
warn("-");
    localmem = alloc;
warn("-");
    if (pt.closed) return CONNECTION_FAILED ~;
warn("-");
    // global limit
    if (pt.global_sem != null) {
        pt.global_sem.acquire();
    }

    ConnPool* cp = pt.get_or_create(host, port, alloc)!;
warn("-");
    // per-host limit
    if (cp.sem != null) cp.sem.acquire();

    // try idle free-list first
    Stream* s = cp.pop_idle();
    if (s != null) {
        // verify connection is still alive with a zero-byte peek
        // (a closed server will make stream.at_eof() == true)
        if (!s.at_eof()) {
            return s;
        }
        // stale — close and open a fresh one
        s.close();
        cp.total--;
    }

    // open a new TCP connection
    Stream*? ns = asyncio::open_connection(host, port);
warn("-");
    if (catch err = ns) {
warn("-");
        // release semaphores on failure
        if (cp.sem != null) cp.sem.release();
        if (pt.global_sem != null) pt.global_sem.release();
        return CONNECTION_FAILED ~;
    }

    cp.total++;
    return ns;
}

// Return a Stream* to the pool after a request completes.
// If force_close is set, or the pool is shutting down, or the free-list
// is full, the connection is closed immediately.
fn void pool_release(
    PoolTable* pt,
    Stream*    s,
    String     host,
    ushort     port,
)
{
warn("-");
    bool did_return = false;

    if (!pt.closed && !pt.force_close) {
        // best-effort: find the pool (it must already exist)
        char[POOL_HOST_KEY_MAX] key;
        usz klen = pool_make_key(&key[0], host, port);

        for (usz i = 0; i < pt.pool_count; i++) {
            ConnPool* cp = &pt.pools[i];
            if (key_eq(&cp.key[0], cp.key_len, &key[0], klen)) {
                ulong now = asyncio::clock_now();
                if (cp.push_idle(s, now)) {
                    did_return = true;
                    // release per-host sem — still holding global (connection open)
                    if (cp.sem != null) cp.sem.release();
                }
                break;
            }
        }
    }

    if (!did_return) {
        // close and release both semaphores
        // find pool to decrement total
        char[POOL_HOST_KEY_MAX] key;
        usz klen = pool_make_key(&key[0], host, port);
        for (usz i = 0; i < pt.pool_count; i++) {
            ConnPool* cp = &pt.pools[i];
            if (key_eq(&cp.key[0], cp.key_len, &key[0], klen)) {
                cp.total--;
                if (cp.sem != null) cp.sem.release();
                break;
            }
        }
        s.close();
    }
    
    if (pt.global_sem != null) pt.global_sem.release();
}

// Close all idle connections older than keepalive_timeout_us.
// Call periodically (e.g. every 5 seconds) from the event loop.
fn void pool_reap(PoolTable* pt)
{
warn("-");
    ulong now = asyncio::clock_now();
    for (usz i = 0; i < pt.pool_count; i++) {
        ConnPool* cp = &pt.pools[i];
        usz reaped = cp.reap_idle(now, (ulong)(pt.keepalive_timeout*1_000_000));
        // release global semaphore slots for each closed idle connection
        for (usz r = 0; r < reaped; r++) {
            if (pt.global_sem != null) pt.global_sem.release();
        }
    }
}

// Drain all idle connections and mark the table as closed.
// New acquire() calls will fail after this.
fn void pool_close(PoolTable* pt)
{
warn("-");
    pt.closed = true;
    for (usz i = 0; i < pt.pool_count; i++) {
        ConnPool* cp = &pt.pools[i];
        usz idle_before = cp.idle_count;
        cp.drain_idle();
        // release global semaphore slots
        for (usz r = 0; r < idle_before; r++) {
            if (pt.global_sem != null) pt.global_sem.release();
        }
        if (cp.sem != null) {
            cp.sem.free();
            cp.sem = null;
        }
        cp.closed = true;
    }
    if (pt.global_sem != null) {
        pt.global_sem.free();
        pt.global_sem = null;
    }
warn("-");
}

// Return the total number of open connections across all hosts.
fn int pool_total_conns(PoolTable* pt)
{
    int total = 0;
    for (usz i = 0; i < pt.pool_count; i++) {
        total += pt.pools[i].total;
    }
    return total;
}

// Return the number of idle connections for a specific host:port.
fn usz pool_idle_count(PoolTable* pt, String host, ushort port)
{
    char[POOL_HOST_KEY_MAX] key;
    usz klen = pool_make_key(key[0..], host, port);
    for (usz i = 0; i < pt.pool_count; i++) {
        ConnPool* cp = &pt.pools[i];
        if (key_eq(&cp.key[0], cp.key_len, &key[0], klen)) return cp.idle_count;
    }
    return 0;
}
