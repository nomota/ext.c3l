// client.dns.c3

module ext::aiohttp;

import ext::asyncio;
import ext::debug;

// TTL-based DNS resolution cache — used internally by TcpConnector.
//
// Design:
//   - Flat array of DnsCacheEntry, capped at DNS_CACHE_CAP entries.
//   - Each entry stores the resolved IP string + port, with an expiry
//     timestamp (asyncio::clock_now() + ttl_us).
//   - Lookup is case-insensitive linear scan (host names are short; cap is small).
//   - On miss, asyncio::open_connection() is used as the resolver — the OS
//     getaddrinfo() call happens inside asyncio's thread pool so it does not
//     block the event loop fiber.
//   - Expired entries are evicted lazily on lookup, and by dns_cache_reap()
//     which can be called periodically.
//   - When the table is full and no expired entry can be evicted, the oldest
//     entry (smallest expiry) is replaced (LRU-by-expiry policy).
//
// Thread-safety:
//   All calls run on the event-loop fiber thread. No locking required.
//
// Limitations:
//   - Only the first resolved address per hostname is cached (single-A policy).
//   - AAAA / round-robin across multiple addresses is not implemented here;
//     pool_acquire() handles retries at the Stream level.
//   - TTL is wall-clock via asyncio::clock_now(), not DNS-protocol TTL.

//  constants 

const usz DNS_CACHE_CAP      @private = 256;  // max cached host entries
const usz DNS_HOST_MAX       @private = 253;  // RFC 1035 max hostname length
const usz DNS_IP_MAX         @private = 46;   // max IPv6 string "xxxx:...:xxxx"

//  cache entry 

struct DnsCacheEntry @private {
    char[DNS_HOST_MAX + 1] host;   // null-terminated, lowercased
    usz  host_len;
    char[DNS_IP_MAX + 1]   ip;     // resolved address string, null-terminated
    usz  ip_len;
    ushort port;                   // port used during resolution (for connect test)
    ulong  expires_us;             // asyncio::clock_now() value at expiry
    bool   valid;                  // false = slot is empty
}

//  cache table 

struct DnsCache {
    DnsCacheEntry[DNS_CACHE_CAP] entries;
    usz  count;   // number of valid entries
    bool enabled;             // false = always miss (bypass cache)
    double ttl;             // default TTL in seconds
}

//  private helpers 

// Lowercase ASCII char (branchless).
fn char dns_lower(char c) @private @inline
{
    return (c >= 'A' && c <= 'Z') ? (char)(c | 0x20) : c;
}

// Case-insensitive comparison of two host strings.
fn bool dns_host_eq(char* a, usz alen, char* b, usz blen) @private
{
    if (alen != blen) return false;
    for (usz i = 0; i < alen; i++) {
        if (dns_lower(a[i]) != dns_lower(b[i])) return false;
    }
    return true;
}

// Copy host into entry.host[], lowercasing as we go.
fn void dns_store_host(DnsCacheEntry* e, String host) @private
{
    usz len = host.len < DNS_HOST_MAX ? host.len : DNS_HOST_MAX;
    for (usz i = 0; i < len; i++) e.host[i] = dns_lower(host[i]);
    e.host[len] = 0;
    e.host_len  = len;
}

// Copy ip string into entry.ip[].
fn void dns_store_ip(DnsCacheEntry* e, String ip) @private
{
    usz len = ip.len < DNS_IP_MAX ? ip.len : DNS_IP_MAX;
    for (usz i = 0; i < len; i++) e.ip[i] = ip[i];
    e.ip[len] = 0;
    e.ip_len  = len;
}

// Find the index of the entry with the smallest expires_us (oldest).
// Returns DNS_CACHE_CAP if the table is empty.
fn usz dns_oldest_idx(DnsCache* c) @private
{
    usz   best_idx = DNS_CACHE_CAP;
    ulong best_exp = (ulong)0xFFFFFFFFFFFFFFFF;
    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        if (!c.entries[i].valid) continue;
        if (c.entries[i].expires_us < best_exp) {
            best_exp = c.entries[i].expires_us;
            best_idx = i;
        }
    }
    return best_idx;
}

// Find an empty or expired slot. Returns DNS_CACHE_CAP if none available.
fn usz dns_free_slot(DnsCache* c, ulong now_us) @private
{
    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        DnsCacheEntry* e = &c.entries[i];
        if (!e.valid) return i;
        if (e.expires_us <= now_us) {
            // expired — reclaim
            e.valid = false;
            c.count--;
            return i;
        }
    }
    return DNS_CACHE_CAP; // full and all live
}

//  public API 

// Initialise a DnsCache.
fn void dns_cache_init(DnsCache* c, bool enabled, double ttl)
{
warn("-");
    c.count = 0;
    c.enabled = enabled;
    c.ttl = ttl;
    for (usz i = 0; i < DNS_CACHE_CAP; i++) c.entries[i].valid = false;
}

// Look up host in the cache.
// On hit, copies the IP string into out_ip[DNS_IP_MAX+1] and returns true.
// On miss or expiry, returns false (caller must resolve and then dns_cache_put).
fn bool dns_cache_get(DnsCache* c, String host, char* out_ip, usz* out_ip_len)
{
    if (!c.enabled) return false;

    ulong now = asyncio::clock_now();

    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        DnsCacheEntry* e = &c.entries[i];
        if (!e.valid) continue;

        // lazy expiry
        if (e.expires_us <= now) {
            e.valid = false;
            c.count--;
            continue;
        }

        if (dns_host_eq(&e.host[0], e.host_len, host.ptr, host.len)) {
            // hit — copy IP out
            for (usz j = 0; j < e.ip_len; j++) out_ip[j] = e.ip[j];
            out_ip[e.ip_len] = 0;
            *out_ip_len = e.ip_len;
            return true;
        }
    }

    return false;
}

// Store a resolved (host → ip) mapping in the cache.
// If the table is full and all entries are live, evicts the oldest entry.
fn void dns_cache_put(DnsCache* c, String host, String ip, ulong ttl_us = 0)
{
    if (!c.enabled) return;

    ulong now = asyncio::clock_now();
    ulong actual_ttl = ttl_us > 0 ? ttl_us : (ulong)(c.ttl*1_000_000);
    ulong expires = now + actual_ttl;

    // update existing entry if host already cached
    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        DnsCacheEntry* e = &c.entries[i];
        if (!e.valid) continue;
        if (dns_host_eq(&e.host[0], e.host_len, host.ptr, host.len)) {
            dns_store_ip(e, ip);
            e.expires_us = expires;
            return;
        }
    }

    // find a free or expired slot
    usz slot = dns_free_slot(c, now);
    if (slot >= DNS_CACHE_CAP) {
        // table full — evict oldest
        slot = dns_oldest_idx(c);
        if (slot >= DNS_CACHE_CAP) return; // should not happen
        c.count--;
    }

    DnsCacheEntry* e = &c.entries[slot];
    dns_store_host(e, host);
    dns_store_ip(e, ip);
    e.expires_us = expires;
    e.valid      = true;
    c.count++;
}

// Invalidate a single host entry (e.g. after a connection failure).
fn void dns_cache_invalidate(DnsCache* c, String host)
{
    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        DnsCacheEntry* e = &c.entries[i];
        if (!e.valid) continue;
        if (dns_host_eq(&e.host[0], e.host_len, host.ptr, host.len)) {
            e.valid = false;
            c.count--;
            return;
        }
    }
}

// Evict all expired entries. Returns the number evicted.
// Call periodically from the event loop (e.g. every 30 seconds).
fn usz dns_cache_reap(DnsCache* c)
{
    ulong now = asyncio::clock_now();
    usz   evicted = 0;
    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        DnsCacheEntry* e = &c.entries[i];
        if (!e.valid) continue;
        if (e.expires_us <= now) {
            e.valid = false;
            c.count--;
            evicted++;
        }
    }
    return evicted;
}

// Flush all entries regardless of TTL (e.g. on network change).
fn void dns_cache_flush(DnsCache* c)
{
    for (usz i = 0; i < DNS_CACHE_CAP; i++) {
        if (c.entries[i].valid) {
            c.entries[i].valid = false;
            c.count--;
        }
    }
}

// Return the number of live (non-expired) entries.
fn usz dns_cache_size(DnsCache* c)
{
    return c.count;
}

//  resolve helper 

// Resolve host → IP string, consulting the cache first.
//
// On cache miss, opens a temporary TCP connection via asyncio::open_connection()
// (which calls getaddrinfo() on a thread-pool thread) solely to obtain the
// resolved address, then immediately closes the connection and caches the result.
//
// In practice, the caller (pool_acquire) already calls open_connection() to
// get the Stream* it will use — so this helper is provided for pre-warming the
// cache or for callers that need the IP string independently.
//
// out_ip must point to a buffer of at least DNS_IP_MAX+1 bytes.
// Returns true on success, false on resolution failure.
fn bool? dns_resolve(
    DnsCache* c,
    String    host,
    ushort    port,
    char*     out_ip,
    usz*      out_ip_len,
    Allocator alloc,
)
{
    // cache hit
    if (dns_cache_get(c, host, out_ip, out_ip_len)) return true;

    // cache miss — open a connection to resolve (asyncio handles getaddrinfo)
    Stream*? s = asyncio::open_connection(host, port);
    if (catch err = s) return false;

    String ip = s.get_ip();
    
    dns_cache_put(c, host, ip); // host → ip (pass-through, avoids re-lookup)

    s.close();

    // report that resolution succeeded (caller re-opens via pool_acquire)
    *out_ip_len = ip.len < DNS_IP_MAX ? ip.len : DNS_IP_MAX;
    for (usz i = 0; i < *out_ip_len; i++) out_ip[i] = ip[i];
    out_ip[*out_ip_len] = 0;

    return true;
}
