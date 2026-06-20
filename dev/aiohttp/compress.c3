// compress.c3

// Response compression middleware for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::io;
import std::compression::gzip;
import std::compression::deflate;
import ext::mem;


// Compression configuration

const sz DEFAULT_COMPRESS_MIN_SIZE = 1024;

tlocal sz compress_min_size = DEFAULT_COMPRESS_MIN_SIZE;
tlocal bool compress_gzip_enabled = true;
tlocal bool compress_deflate_enabled = true;


// Encoding

enum CompressEncoding
{
    COMPRESS_IDENTITY,
    COMPRESS_GZIP,
    COMPRESS_DEFLATE,
    COMPRESS_NOT_ACCEPTABLE,
}


// Configuration API

fn void compress_set_min_size(sz min_size)
{
    if (min_size < 0) {
        compress_min_size = DEFAULT_COMPRESS_MIN_SIZE;
        return;
    }

    compress_min_size = min_size;
}

fn sz compress_get_min_size()
{
    return compress_min_size;
}

fn void compress_enable_gzip(bool enabled)
{
    compress_gzip_enabled = enabled;
}

fn void compress_enable_deflate(bool enabled)
{
    compress_deflate_enabled = enabled;
}

fn void compress_reset()
{
    compress_min_size = DEFAULT_COMPRESS_MIN_SIZE;
    compress_gzip_enabled = true;
    compress_deflate_enabled = true;
}


// Header helpers

fn int compress_parse_q1000(String value) @local
{
    value = value.trim();

    if (value.len == 0) return 0;

    if (value[0] == '1') {
        if (value.len == 1) return 1000;
        if (value[1] != '.') return 0;
        if (value.len > 5) return 0;

        for (sz i = 2; i < value.len; i++) {
            if (value[i] != '0') return 0;
        }

        return 1000;
    }

    if (value[0] != '0') return 0;
    if (value.len == 1) return 0;
    if (value[1] != '.') return 0;
    if (value.len > 5) return 0;

    int q = 0;
    sz digits = 0;

    for (sz i = 2; i < value.len; i++) {
        char c = value[i];

        if (c < '0' || c > '9') return 0;

        q = q * 10 + (int)(c - '0');
        digits++;
    }

    while (digits < 3) {
        q *= 10;
        digits++;
    }

    return q;
}

fn String compress_item_name(String item) @local
{
    sz semicolon = item.index_of(";") ?? -1;

    if (semicolon < 0) return item.trim();

    return item[0:semicolon].trim();
}

fn int compress_item_q(String item) @local
{
    sz semicolon = item.index_of(";") ?? -1;

    if (semicolon < 0) return 1000;

    String params = item[semicolon + 1..];

    while (params.len > 0) {
        sz next = params.index_of(";") ?? -1;
        String param;

        if (next < 0) {
            param = params.trim();
            params = "";
        } else {
            param = params[0:next].trim();
            params = params[next + 1..];
        }

        if (param.len == 0) continue;

        sz equals = param.index_of("=") ?? -1;
        if (equals <= 0) continue;

        String name = param[0:equals].trim();
        String value = param[equals + 1..].trim();

        if (str_iequals(name, "q")) return compress_parse_q1000(value);
    }

    return 1000;
}

fn int compress_find_encoding_q(String accept_encoding, String encoding, bool* found) @local
{
    *found = false;

    String remaining = accept_encoding;

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

        String name = compress_item_name(item);

        if (str_iequals(name, encoding)) {
            *found = true;
            return compress_item_q(item);
        }
    }

    return 0;
}

fn int compress_effective_encoding_q(String accept_encoding, String encoding, int wildcard_q) @local
{
    bool found = false;
    int q = compress_find_encoding_q(accept_encoding, encoding, &found);

    if (found) return q;

    return wildcard_q;
}

fn CompressEncoding compress_select_encoding(String accept_encoding)
{
    bool wildcard_found = false;
    int wildcard_q = compress_find_encoding_q(accept_encoding, "*", &wildcard_found);

    if (!wildcard_found) wildcard_q = 0;

    int gzip_q = compress_effective_encoding_q(accept_encoding, "gzip", wildcard_q);
    int deflate_q = compress_effective_encoding_q(accept_encoding, "deflate", wildcard_q);

    bool identity_found = false;
    int identity_q = compress_find_encoding_q(accept_encoding, "identity", &identity_found);

    if (!identity_found) identity_q = 1000;
    if (!compress_gzip_enabled) gzip_q = 0;
    if (!compress_deflate_enabled) deflate_q = 0;

    if (identity_found && identity_q > 0 && identity_q >= gzip_q && identity_q >= deflate_q) {
        return COMPRESS_IDENTITY;
    }

    if (gzip_q > 0 && gzip_q >= deflate_q) return COMPRESS_GZIP;
    if (deflate_q > 0) return COMPRESS_DEFLATE;
    if (identity_q > 0) return COMPRESS_IDENTITY;

    return COMPRESS_NOT_ACCEPTABLE;
}


// Content-Type helpers

fn bool compress_media_type_matches(String content_type, String prefix) @local
{
    content_type = content_type.trim();

    if (content_type.len < prefix.len) return false;

    return str_iequals(content_type[0:prefix.len], prefix);
}

fn bool compress_content_type_allowed(String content_type) @local
{
    if (content_type.len == 0) return false;

    if (compress_media_type_matches(content_type, "text/")) return true;
    if (compress_media_type_matches(content_type, "application/json")) return true;
    if (compress_media_type_matches(content_type, "application/javascript")) return true;
    if (compress_media_type_matches(content_type, "application/x-javascript")) return true;
    if (compress_media_type_matches(content_type, "application/xml")) return true;
    if (compress_media_type_matches(content_type, "application/xhtml+xml")) return true;
    if (compress_media_type_matches(content_type, "application/wasm")) return true;
    if (compress_media_type_matches(content_type, "image/svg+xml")) return true;
    if (content_type.contains("+json")) return true;
    if (content_type.contains("+xml")) return true;

    return false;
}

fn bool compress_response_content_type_allowed(Response* res) @local
{
    if (res == null) return false;

    String? content_type = res.headers.get("Content-Type");

    if (catch err = content_type) return false;

    return compress_content_type_allowed(content_type);
}


// Vary helper

fn bool compress_vary_contains(String value, String name) @local
{
    String remaining = value;

    while (remaining.len > 0) {
        sz comma = remaining.index_of(",") ?? -1;
        String item;

        if (comma < 0) {
            item = remaining.trim();
            remaining = "";
        } else {
            item = remaining[0:comma].trim();
            remaining = remaining[comma + 1..];
        }

        if (str_iequals(item, name)) return true;
    }

    return false;
}

fn void? compress_add_vary(Response* res, String name) @local
{
    if (res == null) return;

    String? old = res.headers.get("Vary");

    if (catch err = old) {
        res.headers.set("Vary", name)!;
        return;
    }

    if (compress_vary_contains(old, name)) return;

    String value = string::format(localmem, "%s, %s", old, name);
    defer localmem.free(value);

    res.headers.set("Vary", value)!;
}


// Response helpers

fn bool compress_body_kind_supported(Response* res) @local
{
    if (res == null) return false;
    if (res.body_kind == BODY_EMPTY) return false;
    if (res.body_kind == BODY_STREAM) return false;
    if (res.body_kind == BODY_FILE) return false;

    return true;
}

fn bool compress_response_allowed(Response* res) @local
{
    if (res == null) return false;
    if (!status_allows_body(res.status)) return false;
    if (!compress_body_kind_supported(res)) return false;
    if (res.body.len < compress_min_size) return false;
    if (res.headers.has("Content-Encoding")) return false;
    if (!compress_response_content_type_allowed(res)) return false;

    return true;
}

faultdef UNDEFINED_ENCODING;

fn char[]? compress_body(char[] input, CompressEncoding encoding) @local
{
    switch (encoding) {
        case COMPRESS_GZIP:
            return gzip::compress(localmem, input)!;

        case COMPRESS_DEFLATE:
            return deflate::compress(localmem, input)!;

        default:
            return UNDEFINED_ENCODING~;
    }
}

fn String compress_encoding_name(CompressEncoding encoding) @local
{
    switch (encoding) {
        case COMPRESS_GZIP:
            return "gzip";

        case COMPRESS_DEFLATE:
            return "deflate";

        default:
            return "";
    }
}

fn void? compress_replace_body(Response* res, char[] compressed) @maydiscard
{
    if (res.owns_body && res.body.len > 0) {
        localmem.free(res.body);
    }

    res.body = compressed;
    res.owns_body = true;

    res.headers.remove("Transfer-Encoding");
    res.headers.content_length(compressed.len)!;
}


// Middleware

fn Response*? middleware_compress(Ctx* c, Next next)
{
    if (c == null) return CONTEXT_NOT_READY~;

    Response* res = next(c)!;

    compress_add_vary(res, "Accept-Encoding")!;

    if (str_iequals(c.method(), "HEAD")) return res;
    if (!compress_response_allowed(res)) return res;

    String? accept_encoding = c.req_header("Accept-Encoding");

    if (catch err = accept_encoding) return res;

    CompressEncoding encoding = compress_select_encoding(accept_encoding);

    if (encoding == COMPRESS_IDENTITY) return res;
    if (encoding == COMPRESS_NOT_ACCEPTABLE) return res;

    char[] compressed = compress_body(res.body, encoding)!;

    if (compressed.len >= res.body.len) {
        if (compressed.len > 0) localmem.free(compressed);
        return res;
    }

    compress_replace_body(res, compressed)!;
    res.headers.set("Content-Encoding", compress_encoding_name(encoding))!;

    return res;
}


// Debug

fn void compress_dump()
{
    io::printfn("compression:");
    io::printfn("  min_size = %d", compress_min_size);
    io::printfn("  gzip     = %s", compress_gzip_enabled ? "true" : "false");
    io::printfn("  deflate  = %s", compress_deflate_enabled ? "true" : "false");
}

// eof