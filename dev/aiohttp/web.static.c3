// web.static.c3

module ext::aiohttp::web;

import ext::aiohttp;

import ext::asyncio;
import ext::aiofiles;
import ext::aiofiles::os;
import ext::aiofiles::os::path;

// Static file handler — serves files from a directory on disk.
//
// Features:
//   - MIME type detection from file extension (built-in table)
//   - ETag generation (file size + mtime, hex-encoded)
//   - If-None-Match conditional request handling (304)
//   - Range request support (single range: "bytes=start-end")
//   - Directory index listing (optional, disabled by default)
//   - Path traversal prevention (rejects ".." components)
//   - aiofiles for async file I/O

const usz STATIC_PATH_MAX @private = 4096;
const usz STATIC_ETAG_MAX @private = 32;

// MIME table
struct MimeEntry @private { String ext; String mime; }
const MimeEntry[] MIME_TABLE @private = {
    { "html",  "text/html; charset=utf-8"        },
    { "htm",   "text/html; charset=utf-8"        },
    { "css",   "text/css; charset=utf-8"         },
    { "js",    "text/javascript; charset=utf-8"  },
    { "mjs",   "text/javascript; charset=utf-8"  },
    { "txt",   "text/plain; charset=utf-8"       },
    { "csv",   "text/csv; charset=utf-8"         },
    { "xml",   "application/xml"                 },
    { "json",  "application/json"                },
    { "wasm",  "application/wasm"                },
    { "pdf",   "application/pdf"                 },
    { "png",   "image/png"                       },
    { "jpg",   "image/jpeg"                      },
    { "jpeg",  "image/jpeg"                      },
    { "gif",   "image/gif"                       },
    { "svg",   "image/svg+xml"                   },
    { "webp",  "image/webp"                      },
    { "ico",   "image/x-icon"                    },
    { "avif",  "image/avif"                      },
    { "woff",  "font/woff"                       },
    { "woff2", "font/woff2"                      },
    { "ttf",   "font/ttf"                        },
    { "otf",   "font/otf"                        },
    { "mp3",   "audio/mpeg"                      },
    { "ogg",   "audio/ogg"                       },
    { "mp4",   "video/mp4"                       },
    { "webm",  "video/webm"                      },
    { "zip",   "application/zip"                 },
    { "gz",    "application/gzip"                },
    { "tar",   "application/x-tar"               },
};

fn String static_mime(String filename) @private
{
    usz dot = filename.len;
    for (usz i = filename.len; i > 0; i--) {
        if (filename[i - 1] == '.') { dot = i; break; }
    }
    if (dot >= filename.len) return "application/octet-stream";
    String ext_raw = (String) filename[dot: filename.len - dot];
    char[16] ext_buf;
    usz ext_len = ext_raw.len < 15 ? ext_raw.len : 15;
    for (usz i = 0; i < ext_len; i++) {
        char c = ext_raw[i];
        ext_buf[i] = (c >= 'A' && c <= 'Z') ? (char)(c | 0x20) : c;
    }
    String ext = (String)ext_buf[0:ext_len];
    foreach (e : MIME_TABLE) { if (e.ext == ext) return e.mime; }
    return "application/octet-stream";
}

fn String make_etag(char* out, usz file_size, long mtime) @private
{
    const char[16] HEX = "0123456789abcdef";
    usz j = 0;
    out[j++] = '"';
    char[16] tmp; usz tlen = 0;
    usz sv = file_size;
    if (sv == 0) { tmp[tlen++] = '0'; }
    else { while (sv > 0) { tmp[tlen++] = HEX[sv & 0xF]; sv >>= 4; } }
    for (usz i = tlen; i > 0; i--) out[j++] = tmp[i - 1];
    out[j++] = '-';
    tlen = 0;
    long mv = mtime;
    if (mv <= 0) { tmp[tlen++] = '0'; }
    else { while (mv > 0) { tmp[tlen++] = HEX[(usz)(mv & 0xF)]; mv >>= 4; } }
    for (usz i = tlen; i > 0; i--) out[j++] = tmp[i - 1];
    out[j++] = '"';
    return (String) out[0:j];
}

fn bool path_is_safe(String p) @private
{
    for (usz i = 0; i < p.len; i++) {
        if (p[i] == 0) return false;
        if (p[i] == '.' && i + 1 < p.len && p[i + 1] == '.') {
            bool left_ok  = (i == 0)         || p[i - 1] == '/';
            bool right_ok = (i + 2 >= p.len) || p[i + 2] == '/';
            if (left_ok && right_ok) return false;
        }
    }
    return true;
}

fn String path_join(char* buf, String root, String suffix) @private
{
    usz j = 0;
    if (root.len + suffix.len + 2 > STATIC_PATH_MAX) return "";
    for (usz i = 0; i < root.len; i++) buf[j++] = root[i];
    if (j > 0 && buf[j - 1] == '/') j--;
    buf[j++] = '/';
    usz si = 0;
    while (si < suffix.len && suffix[si] == '/') si++;
    for (; si < suffix.len; si++) buf[j++] = suffix[si];
    buf[j] = 0;
    return (String)buf[0: j];
}

struct ByteRange @private { usz start; usz end; bool valid; }

fn ByteRange parse_range(String hdr, usz file_size) @private
{
    ByteRange r = { 0, usz.max, false };
    if (file_size == 0 || hdr.len < 7) return r;
    if (hdr[0]!='b'||hdr[1]!='y'||hdr[2]!='t'||
        hdr[3]!='e'||hdr[4]!='s'||hdr[5]!='=') return r;
    usz pos = 6;
    bool has_start = false;
    usz start = 0;
    while (pos < hdr.len && hdr[pos] >= '0' && hdr[pos] <= '9') {
        start = start * 10 + (usz)(hdr[pos++] - '0');
        has_start = true;
    }
    if (pos >= hdr.len || hdr[pos] != '-') return r;
    pos++;
    bool has_end = false;
    usz end = 0;
    while (pos < hdr.len && hdr[pos] >= '0' && hdr[pos] <= '9') {
        end = end * 10 + (usz)(hdr[pos++] - '0');
        has_end = true;
    }
    if (!has_start && has_end) {
        if (end > file_size) end = file_size;
        r.start = (usz)(file_size - end);
        r.end = (usz)(file_size - 1);
        r.valid = true;
        return r;
    }
    if (!has_start) return r;
    if (!has_end) end = (usz)(file_size - 1);
    if (start > end || start >= file_size) return r;
    if (end >= file_size) end = (usz)(file_size - 1);
    r.start = start;
    r.end = end;
    r.valid = true;
    return r;
}

//  static config 

struct StaticConfig {
    String url_prefix;
    String fs_root;
    bool   show_index;
    bool   follow_links;
    usz    chunk_size;
}

//  directory listing 

fn Response*? static_serve_index(
    String    dir_path,
    String    url_path,
    Allocator alloc,
) @private
{
    localmem = alloc;
    
    DirIterator? iter = os::scandir(alloc, dir_path);
    if (catch err = iter) return http_not_found();

    char[8192] body;
    OBuf b = { &body[0], 8192, 0 };

    b.put("<!doctype html><html><head><meta charset=utf-8><title>Index of ");
    b.put(url_path);
    b.put("</title></head><body><h1>Index of ");
    b.put(url_path);
    b.put("</h1><ul>");
    if (url_path.len > 1) b.put("<li><a href=\"../\">../</a></li>");

    while (true) {
        DirEntry? entry = iter.next();
        if (catch err = entry) break;
        String name = entry.name;
        bool is_f = entry.is_file();
        entry.free();
        b.put("<li><a href=\"");
        b.put(name);
        if (!is_f) b.putc('/');
        b.put("\">");
        b.put(name);
        if (!is_f) b.putc('/');
        b.put("</a></li>");
    }
    iter.close();
    b.put("</ul></body></html>");

    return response_new(
        200,
        "OK",
        b.str().copy(alloc).ptr,
        b.cursor,
        "text/html; charset=utf-8",
    );
}

//  file serving 

fn Response*? static_serve_file(
    String        full_path,
    String        filename,
    Request*      req,
    StaticConfig* cfg,
    Allocator     alloc,
) @private
{
    localmem = alloc;
    
    Stat? st = os::stat(full_path);
    if (catch err = st) return http_not_found();

    usz  file_size = (usz)st.st_size;
    long mtime = st.st_mtime;

    char[STATIC_ETAG_MAX] etag_buf;
    String etag = make_etag(&etag_buf[0], file_size, mtime);

    // If-None-Match → 304
    String? inm = req.headers.get("if-none-match");
    if (try inm) {
        if (inm == etag) {
            Response* r = response_new(304);
            r.set_header("ETag", etag);
            return r;
        }
    }

    String mime = static_mime(filename);

    // Range parsing
    String? range_hdr = req.headers.get("range");
    ByteRange brange  = { 0, file_size > 0 ? (usz)(file_size - 1) : 0, false };
    bool is_range = false;
    if (try range_hdr) {
        ByteRange parsed = parse_range(range_hdr, file_size);
        if (parsed.valid && file_size > 0) { brange = parsed; is_range = true; }
    }

    usz send_start = brange.start;
    usz send_end   = (brange.end == usz.max) ? (file_size > 0 ? (usz)(file_size - 1) : 0) : brange.end;
    usz send_len   = file_size == 0 ? 0 : (send_end - send_start + 1);
    int status     = is_range ? 206 : 200;

    AioFile? afile = aiofiles::open(full_path, "rb");
    if (catch err = afile) return http_not_found();

    if (is_range && send_start > 0) afile.seek((long)send_start, 0);

    char* body_buf = localmem.malloc(send_len > 0 ? send_len : 1);
    usz bytes_read = 0;
    usz chunk = cfg.chunk_size > 0 ? cfg.chunk_size : 65536;
    while (bytes_read < send_len) {
        usz to_read = send_len - bytes_read;
        if (to_read > chunk) to_read = chunk;
        usz? n = afile.read_unbuffered(body_buf[bytes_read: to_read]);
        if (catch err = n) break;
        if (n == 0) break;
        bytes_read += n;
    }
    afile.close();

    Response* resp = response_new(
        status,
        "Ok",
        body_buf,
        bytes_read,
        mime,
    );
    resp.set_header("ETag", etag);
    resp.set_header("Accept-Ranges", "bytes");
    resp.set_header("Cache-Control", "public, max-age=3600");

    if (is_range) {
        char[64] cr_buf;
        OBuf b = { &cr_buf[0], 64, 0 };
        b.put("bytes ");
        b.putn((int)send_start);
        b.putc('-');
        b.putn((int)send_end);
        b.putc('/');
        b.putn((int)file_size);
        resp.set_header("Content-Range", b.str().copy(alloc));
    }

    return resp;
}

//  public handler 

fn Response*? static_handle(Request* req, StaticConfig* cfg) @private
{
    String req_path = req.path;
    String suffix   = req_path;

    if (cfg.url_prefix.len > 0 && req_path.len >= cfg.url_prefix.len) {
        bool ok = true;
        for (usz i = 0; i < cfg.url_prefix.len; i++) {
            if (req_path[i] != cfg.url_prefix[i]) { ok = false; break; }
        }
        if (ok) suffix = req_path[cfg.url_prefix.len: req_path.len  - cfg.url_prefix.len];
    }

    if (!path_is_safe(suffix)) return http_forbidden();
    if (suffix.len == 0) suffix = "/";

    char[STATIC_PATH_MAX] full_buf;
    String full_path = path_join(&full_buf[0], cfg.fs_root, suffix);
    if (full_path.len == 0) return http_not_found();

    if (path::isdir(full_path)) {
        if (!cfg.show_index) return http_forbidden();
        return static_serve_index(full_path, req_path, tmem);
    }
    if (!path::isfile(full_path)) return http_not_found();

    // extract filename for MIME
    String filename = full_path;
    for (usz i = full_path.len; i > 0; i--) {
        if (full_path[i - 1] == '/') {
            filename = full_path[i: full_path.len - i];
            break;
        }
    }
    return static_serve_file(full_path, filename, req, cfg, tmem);
}

//  slot table 

struct StaticSlot @private { StaticConfig config; bool in_use; }
const usz STATIC_SLOT_MAX @private = 8;
StaticSlot[STATIC_SLOT_MAX] static_slots @private;

// Create a RequestHandler bound to (url_prefix, fs_root).
// Both strings must outlive the returned handler.
macro RequestHandler? static_handler_make(
    String url_prefix,
    String fs_root,
    bool   show_index   = false,
    bool   follow_links = false,
    usz    chunk_size   = 65536,
)
{
    for (usz $i = 0; $i < STATIC_SLOT_MAX; $i++) {
        if (!static_slots[$i].in_use) {
            static_slots[$i].config = (StaticConfig){
                .url_prefix   = url_prefix,
                .fs_root      = fs_root,
                .show_index   = show_index,
                .follow_links = follow_links,
                .chunk_size   = chunk_size,
            };
            static_slots[$i].in_use = true;
            return fn Response*?(Request* req) {
                return static_handle(req, &static_slots[$i].config);
            };
        }
    }
    return null;
}

// Release a slot when its Application is freed.
fn void static_handler_free(String url_prefix)
{
    for (usz i = 0; i < STATIC_SLOT_MAX; i++) {
        if (static_slots[i].in_use &&
            static_slots[i].config.url_prefix == url_prefix) {
            static_slots[i].in_use = false;
            return;
        }
    }
}
