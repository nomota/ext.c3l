// aiohttp.client.c3

module ext::aiohttp;

import ext::asyncio;
import ext::serializer::http;
import ext::serializer::simdjson;
import std::encoding::base64;
import std::hash::sha1;
import ext::mem;
import ext::debug;
import ext::thread::fiber;
import std::collections::pair;
import std::collections::list;

//  constants 

const int    MAX_REDIRECTS      @private = 10;
const usz    RESP_READ_BUFSIZE  @private = 32_000;
const usz    WS_KEY_B64_LEN     @private = 24;
const usz    WS_HANDSHAKE_BUFSZ @private = 512;

//  TcpConnector 

struct TcpConnector {
    int limit; // max concurrent conn, 100
    int limit_per_host; // 0:unlimited
    TlsConfig* tls;
    
    usz read_bufsize;
    
    bool use_dns_cache;
    double ttl_dns_cache; // seconds, 10
    
    double keepalive_timeout; // seconds
    bool force_close; // Keep-Alive
    
    bool closed;
    PoolTable pool;
    
    DnsCache dns;
}

fn TcpConnector* connector_new(
    int limit = 100,
    int limit_per_host = 0,
    TlsConfig* tls = null,
    usz read_bufsize = 65536,
    bool use_dns_cache = true,
    double ttl_dns_cache = 10.0,
    double keepalive_timeout = 15.0,
    bool force_close = false)
{
    if (localmem == (LocalAllocator){}) {
        localmem = tmem;
    }

    TcpConnector* c = localmem.alloc(TcpConnector);
    c.limit = limit;
    c.limit_per_host = limit_per_host;
    c.tls = tls;
    c.read_bufsize = read_bufsize > 0 ? read_bufsize : RESP_READ_BUFSIZE;
    c.use_dns_cache = use_dns_cache;
    c.ttl_dns_cache = ttl_dns_cache;
    c.keepalive_timeout = keepalive_timeout;
    c.force_close = force_close;
    c.closed = false;
    
    ulong keepalive_us = (ulong)(keepalive_timeout * 1000000.0);
    (void) pool_init(&c.pool, limit, limit_per_host, keepalive_us, force_close, localmem);

    dns_cache_init(&c.dns, use_dns_cache, ttl_dns_cache);

    return c;
}

fn void TcpConnector.close(&self)
{
    if (self.closed) return;
    self.closed = true;
    pool_close(&self.pool);
    localmem.free(self);
}

fn int TcpConnector.total_conns(&self)
{
    return pool_total_conns(&self.pool);
}

//  ClientSession 

struct ClientSession {
    TcpConnector* connector;
    ClientTimeout timeout;
    Headers*      default_headers;
    BasicAuth*    auth;
    CookieJar*    cookie_jar;
    bool          raise_for_status;
    bool          closed;
    bool owns_connector;
    bool owns_jar;
}

fn ClientSession* session_new(
    TcpConnector* connector = null,
    ClientTimeout timeout = TIMEOUT_DEFAULT,
    Headers* default_headers = null,
    BasicAuth* auth = null,
    CookieJar* cookie_jar = null,
    bool raise_for_status = false)
{
    if (localmem == (LocalAllocator){}) {
        localmem = tmem;
    }
    
    ClientSession* s = localmem.alloc(ClientSession);
    if (connector == null) {
        s.connector = connector_new();
        s.owns_connector = true;
    } else {
        s.connector = connector;
        s.owns_connector = false;
    }
    s.timeout = timeout;
    s.default_headers = default_headers;
    s.auth = auth;
    s.raise_for_status = raise_for_status;
    s.closed = false;
    if (cookie_jar == null) {
        s.cookie_jar = cookiejar_new();
        s.owns_jar = true;
    } else {
        s.cookie_jar = cookie_jar;
        s.owns_jar = false;
    }
    return s;
}

fn void ClientSession.close(&self)
{
    if (self.closed) return;
    self.closed = true;
    if (self.owns_connector) self.connector.close();
    if (self.owns_jar)       self.cookie_jar.free();
    // default_headers/auth are borrowed; caller owns them.
    localmem.free(self);
}

//  ClientResponse 

struct History {
    int status;
    String url;
}

struct ClientResponse {
    int status;
    bool ok; // whether status < 400
    String reason;
    Url url; // last url
    HttpMethod method; // requested method
    Headers* headers;
    CookieJar* cookies;
    bool released;
    History[] history; // if redirected
    StreamReader* content;
    
    // private
    Stream* stream;
    String conn_host; // host or proxyhost
    ushort conn_port; // port or proxyport
    
    TcpConnector* connector;
    char[] body;
    bool body_complete;
    
    ChunkDecoder chunk_dec;
    bool is_chunked;
    String chunked_file; // temporary file that saves chunked uploaded data
    
    usz content_length;
}

//  response parsing helpers 

fn char*? resp_read_headers(
    Stream* stream, http::Response* out_resp,
    char* scratch, usz scratch_size, usz* out_filled,
) @private
{
    usz filled = 0;
    while (filled < scratch_size) {
        usz n = stream.read(scratch[filled: scratch_size - filled])!;
        if (n == 0) return RESPONSE_ERROR~;
        filled += n;
        for (usz i = 0; i + 3 < filled; i++) {
            if (scratch[i]=='\r' && scratch[i+1]=='\n' &&
                scratch[i+2]=='\r' && scratch[i+3]=='\n') {
                char*? bp = http::parse_response(scratch, scratch + filled, out_resp);
                if (catch err = bp) return RESPONSE_ERROR~;
                *out_filled = filled;
                return bp; // body_ptr
            }
        }
    }
    return RESPONSE_ERROR~;
}

fn ClientResponse*? build_response(
    http::Response* p, Url* req_url, HttpMethod method,
    Stream* stream, TcpConnector* connector,
    CookieJar* jar, char* body_start, usz body_len,
    Allocator alloc,
) @private
{
    localmem = alloc;
    
    ClientResponse* r = localmem.alloc(ClientResponse);
    // parse status code
    r.status = 0;
    foreach (c : p.status) {
        if (c < '0' || c > '9') break;
        r.status = r.status * 10 + (int)(c - '0');
    }
    r.reason = p.message;
    r.url = *req_url;
    r.method = method;
    r.ok = r.status < 400;
    r.released = false;
    r.history = {};
    r.chunked_file = "";
    r.stream = stream;
    r.connector = connector;
    if (body_len > 0) {
        r.body = localmem.alloc_array(char, body_len);
        mem::copy(r.body.ptr, body_start, body_len);
    } else {
        r.body = {};
    }

    r.body_complete = false;

    r.headers = headers_new();
    for (uint i = 0; i < p.n_headers; i++) {
        r.headers.add(p.headers[i].key, p.headers[i].value);
    }

    // update cookie jar from Set-Cookie
    p.decode_setcookies();
    
    List{Cookie} raw_cookies;
    for (usz i = 0; i < p.n_set_cookies; i++) {
        http::SetCookie* sc = &p.set_cookies[i];
        raw_cookies.push((Cookie){
            .name = sc.name,
            .value = sc.value,
            .domain = sc.domain,
            .path = sc.path,
            .expires = 0,
            .secure = sc.secure,
            .http_only = sc.http_only, 
            .same_site = sc.same_site,
        });
    }
    if (raw_cookies.len() > 0) {
        jar.update(raw_cookies.to_array(tmem), req_url);
    }
    r.cookies = jar;

    r.is_chunked = p.chunked;
    r.content_length = p.content_length;

    if (r.is_chunked) {
        r.chunk_dec.init();
    }
    
    r.content = localmem.alloc(StreamReader);
    *r.content = {
        .s = stream,
        .r = r,
        .buf_count = r.body.len,
        .total_bytes = 0,
    };
    r.content.buf[0:r.body.len] = r.body[0:r.body.len];
    r.content.buf_count = r.body.len;
    
    r.history = {};
    
    return r;
}

struct StreamReader {
    Stream* s;
    ClientResponse* r;

    // Initial bytes already read together with the response headers.
    // For chunked responses these are encoded bytes; for fixed-length
    // responses these are raw body bytes. ClientResponse.read() consumes
    // and normalizes them.
    char[RESP_READ_BUFSIZE] buf;
    usz   buf_count;

    usz total_bytes;
}

fn void StreamReader.free(&self)
{
    localmem.free(self);
}

// caller must free the result
fn char[]? StreamReader.read(&self, usz n)
{
    if (self.buf_count > n) {
        char[] out = localmem.copy(self.buf[0:n]);
        self.total_bytes += n;
        self.buf[0:self.buf_count-n] = self.buf[n:self.buf_count-n];
        self.buf_count -= n;
        return out;
    }
    
    usz want = n - self.buf_count;

    usz? n_read = self.s.read(self.buf[self.buf_count:want]);
    if (catch err = n_read) return err~;

    char[] out = localmem.copy(self.buf[0:self.buf_count+n_read]);
    self.total_bytes += self.buf_count+n_read;
    self.buf_count = 0;

    return out;
}

// caller must free the result
fn char[]? StreamReader.readany(&self)
{
    if (self.buf_count > 0) {
        char[] out = localmem.copy(self.buf[0:self.buf_count]);
        self.total_bytes += self.buf_count;
        self.buf_count = 0;
        return out;
    }

    usz want = RESP_READ_BUFSIZE;

    usz? n_read = self.s.read(self.buf[0:want]);
    if (catch err = n_read) return err~;

    char[] out = localmem.copy(self.buf[0:n_read]);
    self.total_bytes += n_read;
    self.buf_count = 0;

    return out;
}

faultdef INCOMPLETE_READ_ERROR;

// caller must free the result
fn char[]? StreamReader.readexactly(&self, usz n)
{
    if (self.buf_count > n) {
        char[] out = localmem.copy(self.buf[0:n]);
        self.total_bytes += n;
        self.buf[0:self.buf_count-n] = self.buf[n:self.buf_count-n];
        self.buf_count -= n;
        return out;
    }
    
    usz want = n - self.buf_count;

    usz? n_read = self.s.read(self.buf[self.buf_count:want]);
    if (catch err = n_read) return err~;

    if (n_read+self.buf_count < n) {
        return INCOMPLETE_READ_ERROR~;
    }
    
    char[] out = localmem.copy(self.buf[0:self.buf_count+n_read]);
    self.total_bytes += self.buf_count+n_read;
    self.buf_count = 0;

    return out;
}

// caller must free the result
fn char[]? StreamReader.readline(&self)
{
    usz? n = ((String)self.buf[0:self.buf_count]).index_of_char('\n');
    if (try n) {
        char[] out = localmem.copy(self.buf[0:n]);
        self.total_bytes += n;
        self.buf[0:self.buf_count-n] = self.buf[n:self.buf_count-n];
        self.buf_count -= n;
        return out;
    }
    
    usz want = RESP_READ_BUFSIZE - self.buf_count;

    usz? n_read = self.s.readline(self.buf[self.buf_count:want]);
    if (catch err = n_read) return err~;

    char[] out = localmem.copy(self.buf[0:self.buf_count+n_read]);
    self.total_bytes += self.buf_count+n_read;
    self.buf_count = 0;

    return out;
}

// caller must free the result
fn char[]? StreamReader.iter_chunked(&self, usz n)
{
    return self.read(n)!;
}

// caller must free the result
fn char[]? StreamReader.iter_any(&self)
{
    return self.readany()!;
}

faultdef NOT_CHUNKED, NO_MORE_CHUNK;

// caller must free the result char[]
fn Pair{char[],bool}? StreamReader.iter_chunks(&self)
{
    if (!self.r.is_chunked) {
        return NOT_CHUNKED~;
    }

    if (self.r.body.len > 0) {
        self.r.chunk_dec.feed(self.r.body.ptr, self.r.body.len)!;
        localmem.free(self.r.body);
        self.r.body = {};
    }

    ChunkFrame frame;
    if (self.r.chunk_dec.next(&frame)) {
        return {
            localmem.copy(frame.data[0:frame.data_len]),
            frame.is_final,
        };
    }
    
    while (!self.r.chunk_dec.done()) {
        usz n = self.s.read(&self.buf)!;
        if (n == 0) return NO_MORE_CHUNK~;
    
        self.r.chunk_dec.feed(&self.buf[0], n)!;
    
        if (self.r.chunk_dec.next(&frame)) {
            return {
                localmem.copy(frame.data[0:frame.data_len]),
                frame.is_final,
            };
        }
    }
    
    return NO_MORE_CHUNK~;
}

fn bool StreamReader.at_eof(&self)
{
    return self.s.at_eof();
}

fn void StreamReader.unread(&self, char[] data)
{
    // move existing content to make room for data
    for (usz i = self.buf_count; i > 0; i--) {
        self.buf[i+data.len-1] = self.buf[i-1];
    }

    self.buf[0:data.len] = data[0:data.len];
}


//  ClientResponse methods 

fn void resp_append(char** buf, usz* len, usz* cap, char* data, usz data_len) @private
{
    if (data_len == 0) return;
    if (*buf == null) {
        *cap = data_len > RESP_READ_BUFSIZE ? data_len : RESP_READ_BUFSIZE;
        *buf = localmem.malloc(*cap);
        *len = 0;
    }
    if (*len + data_len > *cap) {
        usz nc = *cap;
        while (*len + data_len > nc) nc *= 2;
        char* nb = localmem.malloc(nc);
        if (*len > 0) mem::copy(nb, *buf, *len);
        localmem.free(*buf);
        *buf = nb;
        *cap = nc;
    }
    mem::copy(*buf + *len, data, data_len);
    *len += data_len;
}

fn bool resp_has_no_body(HttpMethod method, int status) @private @inline
{
    return method == HttpMethod.HEAD || status == 204 || status == 304 ||
           (status >= 100 && status < 200);
}

// caller must NOT free return data
fn char[]? ClientResponse.read(&self)
{
    if (self.body_complete) {
        return self.body;
    }

    if (resp_has_no_body(self.method, self.status)) {
        if (self.body.len > 0) {
            localmem.free(self.body);
            self.body = {};
        }

        self.body_complete = true;
        return self.body;
    }

    if (self.stream == null) return RESPONSE_ERROR~;

    if (self.is_chunked) {
        char* out = null;
        usz len = 0;
        usz cap = 0;

        // body.ptr currently contains the raw bytes already read after the
        // response header.  They must be decoded before reading more.
        if (self.body.len > 0) {
            self.chunk_dec.feed(self.body.ptr, self.body.len)!;
            localmem.free(self.body);
            self.body = {};

            ChunkFrame frame;
            while (self.chunk_dec.next(&frame)) {
                if (frame.is_final) break;
                resp_append(&out, &len, &cap, frame.data, frame.data_len);
            }
        }

        while (!self.chunk_dec.done()) {
            char[RESP_READ_BUFSIZE] raw;
            usz n = self.stream.read(&raw)!;
            if (n == 0) break;
            self.chunk_dec.feed(&raw[0], n)!;

            ChunkFrame frame;
            while (self.chunk_dec.next(&frame)) {
                if (frame.is_final) break;
                resp_append(&out, &len, &cap, frame.data, frame.data_len);
            }
        }

        localmem.free(self.body);
        self.body = out[0:len];
        self.body_complete = true;
    } else {
        usz total = self.content_length;
        usz cap = total > 0 ? total : RESP_READ_BUFSIZE;
        if (cap == 0) cap = RESP_READ_BUFSIZE;

        char* out = localmem.malloc(cap);
        usz len = 0;

        if (self.body.len > 0) {
            if (self.body.len > cap) {
                localmem.free(out);
                cap = self.body.len;
                out = localmem.malloc(cap);
            }
            mem::copy(out, self.body.ptr, self.body.len);
            len = self.body.len;
            localmem.free(self.body);
            self.body = {};
        }

        while (total == 0 || len < total) {
            usz want = RESP_READ_BUFSIZE;
            if (total > 0 && total - len < want) want = total - len;
            if (len + want > cap) {
                usz nc = cap;
                while (len + want > nc) nc *= 2;
                char* nb = localmem.malloc(nc);
                if (len > 0) mem::copy(nb, out, len);
                localmem.free(out);
                out = nb;
                cap = nc;
            }
            usz n = self.stream.read(out[len:want])!;
            if (n == 0) break;
            len += n;
        }
        
        self.body = out[0:len];
        self.body_complete = true;
    }

    return self.body;
}

// caller must not free
fn String? ClientResponse.text(&self, String encoding = "utf-8")
{
    char[]? raw = self.read();
    if (catch err = raw) return err~;

    return (String) raw;
}

// caller must not free
fn String? ClientResponse.json_text(&self) 
{
    // need check Content-Type
    
    return self.text();
}

fn JsonValue? ClientResponse.json(&self)
{
    String? txt0 = self.json_text();
    if (catch err = txt0) return err~;
    String txt = txt0;

    ParseResult? result = simdjson::parse(localmem, txt);
    if (catch err = result) {
        return err~;
    }
    defer result.free();

    JsonValue root = result.root();
    return root;
}

fn void? ClientResponse.raise_for_status(&self)
{
    if (self.status >= 400) return RESPONSE_ERROR~;
}

fn void pool_discard_response_stream(PoolTable* pt, Stream* s, String host, ushort port) @private
{
    char[POOL_HOST_KEY_MAX] key;
    usz klen = pool_make_key(&key[0], host, port);

    for (usz i = 0; i < pt.pool_count; i++) {
        ConnPool* cp = &pt.pools[i];
        if (key_eq(&cp.key[0], cp.key_len, &key[0], klen)) {
            if (cp.total > 0) cp.total--;
            if (cp.sem != null) cp.sem.release();
            break;
        }
    }

    if (pt.global_sem != null) pt.global_sem.release();
    s.close();
}

fn void ClientResponse.release(&self)
{
    if (self.released) return;
    self.released = true;

    if (self.stream != null) {
        // A connection can only be safely returned to the keep-alive pool
        // after the body has been consumed.  Otherwise the next response
        // parser would see leftover bytes from this response.
        if (self.body_complete || resp_has_no_body(self.method, self.status)) {
            pool_release(&self.connector.pool, self.stream, self.url.host, self.url.effective_port());
        } else {
            pool_discard_response_stream(&self.connector.pool, self.stream, self.conn_host, self.conn_port);
        }
        self.stream = null;
    }

    if (self.body.ptr != null) {
        localmem.free(self.body);
        self.body = {};
    }

    if (self.headers != null) {
        self.headers.free();
        self.headers = null;
    }
    
    if (self.content != null) {
        self.content.free();
        self.content = null;
    }

    localmem.free(self);
}

//  core request dispatcher 

fn bool is_redirect_status(int s) @private @inline
{
    return s == 301 || s == 302 || s == 303 || s == 307 || s == 308;
}

fn ClientResponse*? session_do_request(
    ClientSession* s, HttpMethod method, String url_str,
    Headers* params, Headers* req_headers,
    char* data, usz data_len, String json_str, FormData* form,
    TlsConfig* tls, Headers* cookies, BasicAuth* auth, ClientTimeout* timeout, String proxy_url,
) @private
{
    if (s.closed) return CONNECTION_FAILED~;
    
    Url url = url_parse(url_str)!;
    String conn_host = url.host;
    ushort conn_port = url.effective_port();
    
    if (proxy_url != "") {
        Url p_url = url_parse(proxy_url)!;
        conn_host = p_url.host;
        conn_port = p_url.effective_port();
    }
    
    int redirects = 0;
    
    bool new_timeout = false;
    bool new_req_headers = false;
    defer {
        if (new_req_headers) {
            req_headers.free();
        }
        if (new_timeout) {
            localmem.free(timeout);
        }
    }
    
    if (timeout == null) {
        timeout = localmem.alloc(ClientTimeout);
        *timeout = TIMEOUT_DEFAULT;
        new_timeout = true;
    }

    while (true) {
warn("-%s:%d", conn_host, conn_port);
warn("%p %p %p %p", s, s.connector, &s.connector.pool, &localmem);
        Stream*? stream = pool_acquire(&s.connector.pool, conn_host, conn_port, timeout.connect, localmem);
warn("-");
        if (catch err = stream) return CONNECTION_FAILED~;
        
        // inject cookies
        if (cookies != null) {
            if (req_headers == null) {
                req_headers = headers_new();
                new_req_headers = true;
            }
            
            char[4096] ck;
            OBuf o = { &ck[0], 4096, 0 };
            
            for (usz i = 0; i < cookies.len(); i++) {
                Header h = cookies.get_at(i);
                o.put(h.name);
                o.putc('=');
                o.put(h.value);
                o.put("; ");
            }
            
            req_headers.add("Cookie", o.str());
        }
        
        if (catch req_write(stream, method, &url, params, s.default_headers, req_headers, auth, data, data_len, json_str, form, localmem)) {
            pool_discard_response_stream(&s.connector.pool, stream, conn_host, conn_port);
            return CONNECTION_FAILED~;
        }
        
        char[RESP_READ_BUFSIZE * 2] hdr_scratch;
        http::Response parsed;
        usz filled = 0;
        char*? body_ptr = resp_read_headers(stream, &parsed, &hdr_scratch[0], hdr_scratch.len, &filled);
        if (catch err = body_ptr) {
            pool_discard_response_stream(&s.connector.pool, stream, conn_host, conn_port);
            return RESPONSE_ERROR~;
        }
        
        usz body_len = filled - (usz)(body_ptr-&hdr_scratch[0]);
        
        ClientResponse*? resp = build_response(&parsed, &url, method, stream, s.connector, s.cookie_jar, body_ptr, body_len, localmem);
        if (catch err = resp) {
            pool_discard_response_stream(&s.connector.pool, stream, conn_host, conn_port);
            return RESPONSE_ERROR~;
        }
        
        resp.conn_host = conn_host;
        resp.conn_port = conn_port;
        
        // redirects
        if (is_redirect_status(resp.status) && redirects < MAX_REDIRECTS) {
            redirects++;
            int redirect_status = resp.status;
            String? loc = resp.headers.get("location");
            resp.release();
            if (catch err = loc) return RESPONSE_ERROR~;
            if (redirect_status == 303) {
                method = HttpMethod.GET;
                data = null; data_len = 0; json_str = ""; form = null;
            }
            Url? new_url = url_parse(loc);
            if (catch err = new_url) {
                // relative redirect
                char[4096] abs_buf;
                OBuf b = { &abs_buf[0], 4096, 0 };
                
                b.put(url.scheme); b.put("://"); b.put(url.host);
                if (url.port != 0 && url.port != scheme_default_port(url.scheme)) {
                    b.putc(':');
                    b.putn((int)url.port);
                }
                b.put(loc);
                url = url_parse(b.str())!;
            } else {
                url = new_url;
            }
            history_append(&resp.history, resp.status, url.to_string(localmem));
            continue;
        }
        if (redirects >= MAX_REDIRECTS) { resp.release(); return TOO_MANY_REDIRECTS~; }
        if (s.raise_for_status && resp.status >= 400) { resp.release(); return RESPONSE_ERROR~; }

        return resp;
    }
}

fn void history_append(History[]* history, int status, String url)
{
    usz n = (*history).len;
    History[] new_h = localmem.alloc_array(History, n+1);
    new_h[0:n] = (*history)[0:n];
    new_h[n] = { status, url };
    localmem.free(*history);
    *history = new_h;
}

//  ClientSession HTTP method shortcuts 

fn ClientResponse*? ClientSession.request(&self, HttpMethod method, String url,
    Headers* params = null, Headers* headers = null,
    char[] data = {}, String json = "",
    FormData* form = null, TlsConfig* tls = null, 
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, method, url, params, headers, data.ptr, data.len, json, form, tls, cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.get(&self, String url,
    Headers* params = null, Headers* headers = null, TlsConfig* tls = null,
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.GET, url, params, headers, null, 0, "", null, tls, cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.post(&self, String url,
    char[] data = {}, String json = "",
    FormData* form = null, Headers* headers = null, TlsConfig* tls = null,
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.POST, url, null, headers, data.ptr, data.len, json, form, tls, cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.put(&self, String url,
    char[] data = {},
    Headers* headers = null, TlsConfig* tls = null,
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.PUT, url, null, headers, data.ptr, data.len, "", null, tls, cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.patch(&self, String url,
    char[] data = {}, 
    Headers* headers = null, TlsConfig* tls = null,
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.PATCH, url, null, headers, data.ptr, data.len, "", null, tls, cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.delete(&self, String url,
    Headers* headers = null, TlsConfig* tls = null, 
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.DELETE, url, null, headers, null, 0, "", null, tls,  cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.head(&self, String url,
    Headers* headers = null, TlsConfig* tls = null,
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.HEAD, url, null, headers, null, 0, "", null, tls, cookies, auth, timeout, proxy);
}

fn ClientResponse*? ClientSession.options(&self, String url,
    Headers* headers = null, TlsConfig* tls = null,
    Headers* cookies = null, BasicAuth* auth = null, ClientTimeout* timeout = null, String proxy = "") @maydiscard
{
    return session_do_request(self, HttpMethod.OPTIONS, url, null, headers, null, 0, "", null, tls, cookies, auth, timeout, proxy);
}

