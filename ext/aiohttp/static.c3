// static.c3

// Static file serving for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::mem;
import ext::aio;
import ext::aio::path;
import ext::io::stat;
import c::time;
import c::locale;

// Faults

faultdef STATIC_NOT_CONFIGURED;
faultdef STATIC_FORBIDDEN;
faultdef STATIC_NOT_FOUND;
faultdef STATIC_READ_ERROR;

const sz MAX_FILE_BYTES = 4_000_000_000;


// Static config

tlocal String static_root = "";
tlocal bool static_root_ready = false;

fn void set_root(String root)
{
    if (static_root_ready && static_root.len > 0) {
        str_free(static_root);
    }

    static_root = str_clone(root);
    static_root_ready = true;
}

fn void clear_root()
{
    if (static_root_ready && static_root.len > 0) {
        str_free(static_root);
    }

    static_root = "";
    static_root_ready = false;
}



fn bool path_starts_with_parent(String path) @local
{
    if (path == "..") return true;
    if (path.starts_with("../")) return true;
    if (path == "/..") return true;
    if (path.starts_with("/../")) return true;
    return false;
}

fn String? normalize_path(String path)
{
    if (path.len == 0) return {};
    if (path.contains("\\")) return STATIC_FORBIDDEN~;

    char[] out = localmem.alloc_array(char, path.len)!;
    defer localmem.free(out);

    sz[] segment_offsets = localmem.alloc_array(sz, path.len + 1)!;
    defer localmem.free(segment_offsets);

    bool absolute = path[0] == '/';
    sz out_len = 0;
    sz segment_count = 0;
    sz pos = 0;

    if (absolute) out[out_len++] = '/';

    while (pos < path.len) {
        while (pos < path.len && path[pos] == '/') {
            pos++;
        }

        if (pos >= path.len) break;

        sz start = pos;

        while (pos < path.len && path[pos] != '/') {
            pos++;
        }

        sz len = pos - start;

        if (len == 1 && path[start] == '.') continue;

        if (len == 2 && path[start] == '.' && path[start + 1] == '.') {
            if (segment_count > 0) {
                sz previous = segment_offsets[segment_count - 1];
                bool previous_is_parent = out_len - previous == 2 && out[previous] == '.' && out[previous + 1] == '.';

                if (!previous_is_parent) {
                    segment_count--;
                    out_len = previous;

                    if (out_len > 1 && out[out_len - 1] == '/') out_len--;

                    continue;
                }
            }

            if (out_len > 0 && out[out_len - 1] != '/') out[out_len++] = '/';

            segment_offsets[segment_count++] = out_len;
            out[out_len++] = '.';
            out[out_len++] = '.';

            continue;
        }

        if (out_len > 0 && out[out_len - 1] != '/') out[out_len++] = '/';

        segment_offsets[segment_count++] = out_len;

        for (sz i = 0; i < len; i++) {
            out[out_len++] = path[start + i];
        }
    }

    if (out_len == 0) return {};
    if (out_len > 1 && out[out_len - 1] == '/') out_len--;

    String normalized = (String)out[0:out_len];

    if (path_starts_with_parent(normalized)) return STATIC_FORBIDDEN~;

    return normalized.copy(localmem);
}

fn String normalize_rel(String rel)
{
    if (rel.len == 0) return "index.html";

    while (rel.starts_with("/")) {
        if (rel.len == 1) return "index.html";
        rel = rel[1..];
    }

    if (rel.len == 0) return "index.html";

    return rel;
}

fn bool is_safe_rel(String rel)
{
    if (rel.len == 0) return true;
    if (rel.contains("\\")) return false;

    sz start = 0;

    while (start <= rel.len) {
        sz slash = rel[start..].index_of("/") ?? -1;
        String part;

        if (slash < 0) {
            part = rel[start..];
        } else {
            part = rel[start:slash];
        }

        if (part == "..") return false;
        if (slash < 0) break;

        start += slash + 1;
    }

    return true;
}

fn String? join_path(String root, String rel)
{
    if (root.len == 0) return STATIC_NOT_CONFIGURED~;

    if (root.ends_with("/") && rel.starts_with("/")) return string::format(localmem, "%s%s", root, rel[1..]);
    if (!root.ends_with("/") && !rel.starts_with("/")) return string::format(localmem, "%s/%s", root, rel);

    return string::format(localmem, "%s%s", root, rel);
}


// Content type

fn String content_type_from_path(String file_path)
{
    if (file_path.ends_with(".html") || file_path.ends_with(".htm")) return "text/html; charset=utf-8";
    if (file_path.ends_with(".css")) return "text/css; charset=utf-8";
    if (file_path.ends_with(".js") || file_path.ends_with(".mjs")) return "application/javascript; charset=utf-8";
    if (file_path.ends_with(".json")) return "application/json; charset=utf-8";
    if (file_path.ends_with(".txt")) return "text/plain; charset=utf-8";
    if (file_path.ends_with(".xml")) return "application/xml; charset=utf-8";
    if (file_path.ends_with(".csv")) return "text/csv; charset=utf-8";
    if (file_path.ends_with(".svg")) return "image/svg+xml";
    if (file_path.ends_with(".png")) return "image/png";
    if (file_path.ends_with(".jpg") || file_path.ends_with(".jpeg")) return "image/jpeg";
    if (file_path.ends_with(".gif")) return "image/gif";
    if (file_path.ends_with(".webp")) return "image/webp";
    if (file_path.ends_with(".ico")) return "image/x-icon";
    if (file_path.ends_with(".wasm")) return "application/wasm";
    if (file_path.ends_with(".pdf")) return "application/pdf";
    if (file_path.ends_with(".zip")) return "application/zip";
    if (file_path.ends_with(".gz")) return "application/gzip";
    if (file_path.ends_with(".mp4")) return "video/mp4";
    if (file_path.ends_with(".webm")) return "video/webm";
    if (file_path.ends_with(".mp3")) return "audio/mpeg";
    if (file_path.ends_with(".wav")) return "audio/wav";

    return "application/octet-stream";
}

faultdef GMTIME_ERROR;

fn String? http_date(long unix_time)
{
    if (unix_time < 0) return STATIC_READ_ERROR~;

    locale::setlocale(locale::LC_TIME, "C");

    // time::TimeT unix_time = time::time(null);
    time::Tm* utc = time::gmtime(&unix_time);
    if (utc == null) return GMTIME_ERROR~;

    char[64] buffer;
    sz n = time::strftime(&buffer[0], buffer.len, "%a, %d %b %Y %H:%M:%S GMT", utc);

    return ((String)buffer[0:n]).copy(localmem);
}


// Cache helpers

fn String? make_etag(stat::StatInfo* info)
{
    if (info == null) return STATIC_READ_ERROR~;

    return string::format(localmem, "\"%x-%x\"", (long)info.size, info.mtime);
}

fn String normalize_etag_token(String token) @local
{
    token = token.trim();

    if (token.len >= 2 && (token[0] == 'W' || token[0] == 'w') && token[1] == '/') {
        token = token[2..].trim();
    }

    return token;
}

fn bool etag_matches(String candidate, String etag) @local
{
    candidate = normalize_etag_token(candidate);
    etag = normalize_etag_token(etag);

    return candidate == "*" || candidate == etag;
}

fn bool header_matches_etag(String value, String etag) @local
{
    String remaining = value;

    while (remaining.len > 0) {
        sz comma = remaining.index_of(",") ?? -1;
        String item;

        if (comma < 0) {
            item = remaining;
            remaining = "";
        } else {
            item = remaining[0:comma];
            remaining = remaining[comma + 1..];
        }

        if (etag_matches(item, etag)) return true;
    }

    return false;
}

fn bool is_not_modified(Ctx* c, String etag, String last_modified)
{
    if (c == null) return false;

    String? if_none_match = c.req_header("If-None-Match");

    if (try if_none_match) {
        return header_matches_etag(if_none_match, etag);
    }

    String? if_modified_since = c.req_header("If-Modified-Since");

    if (try if_modified_since) {
        return if_modified_since.trim() == last_modified;
    }

    return false;
}

fn bool if_range_etag_matches(String value, String etag) @local
{
    value = value.trim();

    if (value.len == 0) return false;

    if (value.len >= 2 && (value[0] == 'W' || value[0] == 'w') && value[1] == '/') {
        return false;
    }

    return value == etag;
}

fn bool if_range_matches(Ctx* c, String etag, String last_modified)
{
    if (c == null) return false;

    String? if_range = c.req_header("If-Range");

    if (catch err = if_range) return true;

    String value = if_range.trim();

    if (value.len == 0) return false;
    if (value.starts_with("\"") || value.starts_with("W/") || value.starts_with("w/")) return if_range_etag_matches(value, etag);

    return value == last_modified;
}


// Response helpers

fn void? apply_cache_headers(Response* res, String etag, String last_modified) @maydiscard
{
    if (res == null) return STATIC_READ_ERROR~;

    res.header("ETag", etag)!;
    res.header("Last-Modified", last_modified)!;
    res.header("Accept-Ranges", "bytes")!;
}

fn void? apply_file_headers(Response* res, String full_path, stat::StatInfo* info) @maydiscard
{
    if (res == null || info == null) return STATIC_READ_ERROR~;

    res.content_type(content_type_from_path(full_path))!;
    res.header("Accept-Ranges", "bytes")!;

    if (info.mtime < 0) return;

    String last_modified = http_date(info.mtime)!;
    defer localmem.free(last_modified);

    String etag = make_etag(info)!;
    defer localmem.free(etag);

    res.header("Last-Modified", last_modified)!;
    res.header("ETag", etag)!;
}

fn Response*? not_modified_response(String etag, String last_modified) @local
{
    Response* res = response_empty(304)!;

    apply_cache_headers(res, etag, last_modified)!;

    res.headers.remove("Content-Type");
    res.headers.remove("Transfer-Encoding");
    res.headers.content_length(0)!;

    return res;
}

fn Response*? range_not_satisfiable_response(sz file_size) @local
{
    Response* res = response_empty(416)!;

    String content_range = byte_range_unsatisfied_content_range(file_size)!;
    defer localmem.free(content_range);

    res.header("Content-Range", content_range)!;
    res.header("Accept-Ranges", "bytes")!;
    res.headers.remove("Content-Type");
    res.headers.remove("Transfer-Encoding");
    res.headers.content_length(0)!;

    return res;
}

fn Response*? static_range_response(Ctx* c, String full_path, stat::StatInfo* info, ByteRange range, String etag, String last_modified) @local
{
    if (c == null || info == null) return STATIC_READ_ERROR~;

    Response* res = c.file_range(full_path, range.start, range.length)!;
    res.set_status(206)!;

    String content_range = byte_range_content_range(range, info.size)!;
    defer localmem.free(content_range);

    res.content_type(content_type_from_path(full_path))!;
    res.header("Content-Range", content_range)!;
    apply_cache_headers(res, etag, last_modified)!;
    res.headers.content_length(range.length)!;

    return res;
}


// Static handler

fn Response*? static_handler(Ctx* c)
{
    if (c == null) return CONTEXT_NOT_READY~;

    if (!static_root_ready || static_root.len == 0) {
        c.status(500)!;
        return c.text("static root not configured")!;
    }

    String? rel = c.splat();

    if (catch err = rel) {
        c.status(404)!;
        return c.text("static file not found")!;
    }

    String? decoded = percent_decode(rel);

    if (catch err = decoded) {
        c.status(403)!;
        return c.text("forbidden")!;
    }

    defer localmem.free(decoded);

    String? normalized = normalize_path(decoded);

    if (catch err = normalized) {
        c.status(403)!;
        return c.text("forbidden")!;
    }

    defer {
        if (normalized.len > 0) localmem.free(normalized);
    }

    rel = normalize_rel(normalized);

    if (!is_safe_rel(rel)) {
        c.status(403)!;
        return c.text("forbidden")!;
    }

    String full_path = join_path(static_root, rel)!;
    defer localmem.free(full_path);

    stat::StatInfo? info = path::statinfo(full_path);

    if (catch err = info) {
        c.status(404)!;
        return c.text("static file not found")!;
    }

    if (info.is_link) {
        c.status(403)!;
        return c.text("forbidden")!;
    }

    if (info.is_dir || !info.is_file) {
        c.status(404)!;
        return c.text("static file not found")!;
    }

    if (info.size < 0) {
        c.status(500)!;
        return c.text("static read error")!;
    }

    if (info.size > MAX_FILE_BYTES) {
        c.status(413)!;
        return c.text("413 Payload Too Large")!;
    }

    String etag = "";
    String last_modified = "";
    bool cache_headers_ready = false;

    if (info.mtime >= 0) {
        last_modified = http_date(info.mtime)!;
        defer localmem.free(last_modified);

        etag = make_etag(&info)!;
        defer localmem.free(etag);

        cache_headers_ready = true;

        if (is_not_modified(c, etag, last_modified)) {
            return not_modified_response(etag, last_modified)!;
        }
    }

    String? range_header = c.req_header("Range");

    if (try range_header) {
        bool use_range = true;

        if (cache_headers_ready) {
            use_range = if_range_matches(c, etag, last_modified);
        }

        if (use_range) {
            ByteRange? range = parse_byte_range(range_header, info.size);

            if (catch err = range) {
                return range_not_satisfiable_response(info.size)!;
            }

            if (cache_headers_ready) {
                return static_range_response(c, full_path, &info, range, etag, last_modified)!;
            }

            Response* range_res = c.file_range(full_path, range.start, range.length)!;
            range_res.set_status(206)!;

            String content_range = byte_range_content_range(range, info.size)!;
            defer localmem.free(content_range);

            range_res.content_type(content_type_from_path(full_path))!;
            range_res.header("Content-Range", content_range)!;
            range_res.header("Accept-Ranges", "bytes")!;
            range_res.headers.content_length(range.length)!;

            return range_res;
        }
    }

    Response* res = c.file(full_path, info.size)!;
    apply_file_headers(res, full_path, &info)!;

    return res;
}


// Application helper

fn void? Application.static_files(&self, String url_prefix, String root) @maydiscard
{
    set_root(root);

    String pattern;

    if (url_prefix == "/") {
        pattern = "/*";
    } else if (url_prefix.ends_with("/")) {
        pattern = string::format(localmem, "%s*", url_prefix);
    } else {
        pattern = string::format(localmem, "%s/*", url_prefix);
    }

    defer {
        if (pattern != "/*") localmem.free(pattern);
    }

    self.get(pattern, &static_handler)!;
    self.head(pattern, &static_handler)!;
}

// eof