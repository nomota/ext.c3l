// http.c3

module ext::serializer::http;

import c::string;
import ext::debug; // warn(), @assert()

faultdef ERROR, INCOMPLETE;

const bool[256] LINE_END = {
    [(usz)'\r'] = true, // '\r'
    [(usz)'\n'] = true, // '\n'
};

struct KeyValue {
    String key;
    String value;
}

struct Url {
    String protocol;
    String user;
    String password;
    String host;
    String port;
    String path;
    String query;
    String fragment;
}

struct FormFile {
    String name;        // field name from Content-Disposition
    String filename;    // original filename from Content-Disposition
    String mime;        // Content-Type of this part
    String data;        // raw file bytes as a String slice
}

const MAX = 64;
struct Request {
    String method;
    String uri;
    String version;
    
    KeyValue[MAX] headers;
    uint n_headers;
    
    // decoded 
    usz content_length;
    bool chunked;
    
    Url url;
    String base_url;
    
    KeyValue[MAX] cookies;
    uint n_cookies;
    
    KeyValue[MAX] queries;
    usz n_queries;
    
    KeyValue[MAX] form;
    usz n_form;
    
    FormFile[MAX] files;
    uint n_files;
    
    String[MAX/4] ips;
    // Json json;
    
    char* body;
    // stream
}

struct SetCookie {
    String name;
    String value;
    String domain;
    String path;
    String expires;
    String max_age;
    String same_site;
    bool http_only;
    bool secure;
}

/*
    JSONResponse,
    HTMLResponse,
    PlainTextResponse,
    RedirectResponse,
    StreamingResponse,
    FileResponse,
*/
struct Response {
    String status;
    String message;

    KeyValue[MAX] headers;
    uint n_headers;
    
    // decoded 
    usz content_length;
    bool chunked;

    SetCookie[MAX] set_cookies;
    usz n_set_cookies;
    
    KeyValue[MAX] queries;
    KeyValue[MAX] form;
    String[MAX/4] ips;
    // Json json;
    
    char* body;
}

fn bool str_iequals(String s1, String s2) @inline
{
    if (s1.len != s2.len) return false;
    for (usz i = 0; i < s1.len; i++) {
        char a = *(s1.ptr+i);
        char b = *(s2.ptr+i);
        if (a >= 'A' && a <= 'Z') a |= 0x20;
        if (b >= 'A' && b <= 'Z') b |= 0x20;
        if (a != b) return false;
    }
    return true;
}

/*
macro char* find_in_8_chars(char* buf, bool* c)
{
    bool*[<8>] vector_c = c;
    bool*[<8>] matches = vector_c + (*(char[<8>]*)buf);
    uint mask = matches.mask_to_int();
    return mask != 0 ? buf + mask.ctz() : null;
}
*/

macro char* find_in_8_chars(char* buf, bool* c)
{
    // no boundary check, because we know that buf is longer than 8 bytes
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    if (c[*buf]) return buf; buf++;
    return null;
}


fn char*? find_chars(char* buf, char* end, bool* c) @inline
{
    while (end - buf >= 8) {
        char* out = find_in_8_chars(buf, c);
        if (out == null) {
            buf += 8;
            continue;
        }
        return out;
    }
    while (buf <= end) {
        if (c[*buf]) return buf; buf++;
    }
    
    return INCOMPLETE~;
}

macro char* find_in_8_char(char* buf, char c)
{
    char[<8>] vector_c = c;
    bool[<8>] matches = (*(char[<8>]*)buf).comp_eq(vector_c);
    uint mask = matches.mask_to_int();
    return mask != 0 ? buf + mask.ctz() : null;
}

/*
macro char* find_in_8_char(char* buf, char c)
{
    // no boundary check, because we know that buf is longer than 8 bytes
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    if (c == *buf) return buf; buf++;
    return null;
}
*/

fn char*? find_char(char* buf, char* end, char c) @inline
{
    while (end - buf >= 8) {
        char* out = find_in_8_char(buf, c);
        if (out == null) {
            buf += 8;
            continue;
        }
        return out;
    }
    while (buf <= end) {
        if (c == *buf) return buf; buf++;
    }
    
    return INCOMPLETE~;
}

// parse (GET) (uri) HTTP/(ver)
// ret = -1 for error, -2 for incomplete
fn char*? parse_http_req_line(char* buf, char* end, String* method, String* uri, String* ver)
{
    char*? out = find_char(buf, end, ' ');
    if (catch err = out) {

        return err~;
    }
    *method = (String)buf[0:out-buf];
    buf = out;

    // skip blanks
    while(*buf == ' ' && buf < end) buf++;
    if (buf == end) {

        return INCOMPLETE~;
    }
    out = find_char(buf, end, ' ')!;
    *uri = (String)buf[0:out-buf];
    buf = out;

    // skip blanks
    while(*buf == ' ' && buf < end) buf++;
    if (buf == end) {

        return INCOMPLETE~;
    }    
    if ((usz)(end - buf) < 9) {

        return INCOMPLETE~;
    }
    // EXPECT_CHAR_NO_CHECK x7
    if (*buf++ != 'H') { 
        return ERROR~;
    }
    if (*buf++ != 'T') {
        return ERROR~;
    }
    if (*buf++ != 'T') {
        return ERROR~;
    }
    if (*buf++ != 'P') {
        return ERROR~;
    }
    if (*buf++ != '/') {
        return ERROR~;
    }
    
    char* v = buf;
    if (*buf != '1' && *buf != '2' && *buf != '3') {
        return ERROR~;
    }
    buf++;
    if (*buf++ != '.') {
        return ERROR~;
    }
    if (*buf < '0' || '9' < *buf) {
        return ERROR~;
    }
    buf++;
    *ver = (String)v[0:buf-v];
    if (buf >= end) {
        return INCOMPLETE~;
    }

    while ((*buf == ' ' || *buf =='\r') && buf < end) {
        buf++;
        if (*buf == '\n') {
            buf++;
            return buf;
        }
    }

    return INCOMPLETE~;
}

// parse HTTP/1.0 (404) (Not found)
fn char*? parse_http_resp_line(char* buf, char* end, String* status, String* msg)
{
    if (end - buf < 9) { return INCOMPLETE~; }
    if (*buf != 'H' && buf[4] != '/' && buf[8] != ' ') { return ERROR~; }
    buf += 9;

    // skip blanks
    while(*buf == ' ' && buf < end) buf++;
    if (buf >= end) { return INCOMPLETE~; }

    char* st = buf;
    while ('0' <= *buf && *buf <= '9') buf++;
    if (buf >= end) { return INCOMPLETE~; }
    *status = (String)st[0:buf-st];

    // skip blanks
    while(*buf == ' ' && buf < end) buf++;
    if (buf >= end) { return INCOMPLETE~; }

    char* out = find_chars(buf, end, &LINE_END[0])!;
    *msg = (String)buf[0:out-buf];
    buf = out;
    if (*buf == '\r') buf++;
    if (buf == end) { return INCOMPLETE~; }
    if (*buf != '\n') { return ERROR~; }
    
    return buf;
}

fn char*? parse_key_value(char* buf, char* end, String* key, String* value)
{
    if (*buf == ' ' || *buf == '\t') {
        *key = "";
        buf++;
    } else {
        char* out = find_char(buf, end, ':')!;
        char[] k = buf[0:out-buf];
        buf = out+1;
        while (k[k.len-1] == ' ' || k[k.len-1] == '\t') k = k[0:k.len-1]; // trim tail
        *key = (String)k;
    }

    // skip blanks
    while(*buf == ' ' && buf < end) buf++;
    if (buf == end) { return INCOMPLETE~; }

    char* out = find_chars(buf, end, &LINE_END[0])!;
    char[] v = buf[0:out-buf];
    buf = out;
    while (v[v.len-1] == ' ' || v[v.len-1] == '\t') v = v[0:v.len-1]; // trim tail
    *value = (String)v;

    if (*buf == '\r') buf++;
    if (buf == end) { return INCOMPLETE~; }
    if (*buf != '\n') { return ERROR~; }
    buf++;
    return buf;
}


fn char*? parse_request(char* buf, char* end, Request* req)
{
    buf = parse_http_req_line(buf, end, &req.method, &req.uri, &req.version)!;
warn("-");
    uint n = 0;
    while (n < MAX && buf < end) {
        if (*buf == '\n') {
            req.body = ++buf;
            return buf;
        }
        if (*buf == '\r' && buf < end && *(buf+1) == '\n') {
            req.body = buf+2;
            return buf+2;
        }

        buf = parse_key_value(buf, end, &req.headers[n].key, &req.headers[n].value)!;
        n++;
        req.n_headers = n;

        if (buf >= end) { return INCOMPLETE~; }
    }

    return INCOMPLETE~;
}

fn char*? parse_response(char* buf, char* end, Response* resp)
{
    buf = parse_http_resp_line(buf, end, &resp.status, &resp.message)!;
    uint n = 0;
    while (n < MAX) {
        buf = parse_key_value(buf, end, &resp.headers[n].key, &resp.headers[n].value)!;
        n++;
        resp.n_headers = n;

        if (buf >= end) { return INCOMPLETE~; }
        if (*buf == '\n') {
            resp.body = ++buf;
            return buf;
        }
        if (*buf == '\r' && buf < end && *(buf+1) == '\n') {
            resp.decode_content_length();
            resp.body = buf+2;
            return buf+2; // body_start
        }
    }

    return INCOMPLETE~;
}

fn bool Request.decode_uri(&self)
{
    String uri = self.uri;
    if (uri.len == 0) return false;

    char* buf = uri.ptr;
    char* end = buf + uri.len;
    char* cur = buf;

    // 1. scheme:
    char* scheme_end = null;
    for (char* p = cur; p + 2 < end; p++) {
        if (*p == ':' && p[1] == '/' && p[2] == '/') {
            scheme_end = p;
            break;
        }
    }

    if (scheme_end != null) {
        self.url.protocol = (String)cur[0 : scheme_end - cur];
        cur = scheme_end + 3; // skip "://"

        // 2. authority end (next '/', '?', '#' or end)
        char* auth_end = cur;
        while (auth_end < end && *auth_end != '/' &&
               *auth_end != '?' && *auth_end != '#') {
            auth_end++;
        }

        // 3. '@' userinfo parsing
        char* at = null;
        for (char* p = cur; p < auth_end; p++) {
            if (*p == '@') { at = p; break; }
        }

        char* host_start = cur;
        if (at != null) {
            char* ui_start = cur;
            char* ui_colon = null;
            for (char* p = ui_start; p < at; p++) {
                if (*p == ':') { ui_colon = p; break; }
            }
            if (ui_colon != null) {
                self.url.user = (String)ui_start[0 : ui_colon - ui_start];
                char* pw = ui_colon + 1;
                self.url.password = (String)pw[0 : at - pw];
            } else {
                self.url.user = (String)ui_start[0 : at - ui_start];
            }
            host_start = at + 1;
        }

        // 4. host:port parsing
        char* h_colon = null;
        for (char* p = host_start; p < auth_end; p++) {
            if (*p == ':') { h_colon = p; break; }
        }
        if (h_colon != null) {
            self.url.host = (String)host_start[0 : h_colon - host_start];
            char* port_start = h_colon + 1;
            self.url.port = (String)port_start[0 : auth_end - port_start];
        } else {
            self.url.host = (String)host_start[0 : auth_end - host_start];
        }

        cur = auth_end;
    }

    // 5. path parsing (before '?' or '#')
    if (cur < end && (*cur == '/' || scheme_end == null)) {
        char* path_start = cur;
        while (cur < end && *cur != '?' && *cur != '#') cur++;
        self.url.path = (String)path_start[0 : cur - path_start];
    }

    // 6. query parsing (after '?' before '#')
    if (cur < end && *cur == '?') {
        cur++;
        char* q_start = cur;
        while (cur < end && *cur != '#') cur++;
        self.url.query = (String)q_start[0 : cur - q_start];
    }

    // 7. fragment parsing (after '#')
    if (cur < end && *cur == '#') {
        cur++;
        self.url.fragment = (String)cur[0 : end - cur];
    }

    return true;
}

faultdef NOT_FOUND;

fn String? Request.get(&self, String name)
{
    for (uint i = 0; i < self.n_headers; i++) {
        String key = self.headers[i].key;
        String val = self.headers[i].value;

        if (str_iequals(key, name)) {
            return val;
        }
    }
    return NOT_FOUND~;
}

fn bool Request.decode_content_length(&self)
{
    for (uint i = 0; i < self.n_headers; i++) {
        String key = self.headers[i].key;
        String val = self.headers[i].value;

        // Content-Length
        if (key.len == 14 && str_iequals(key, "Content-Length")) {
            usz n = 0;
            foreach (char c : val) {
                if (c < '0' || c > '9') return false; // non-digit → invalid
                n = n * 10 + (usz)(c - '0');
            }
            self.content_length = n;
            return true;
        }

        // Transfer-Encoding: chunked
        if (key.len == 17 && str_iequals(key, "Transfer-Encoding")) {
            // value may be "chunked" or "gzip, chunked" etc.
            char* buf = val.ptr;
            char* end = buf + val.len;
            while (buf < end) {
                // skip whitespace / commas
                while (buf < end && (*buf == ' ' || *buf == '\t' || *buf == ',')) buf++;
                if (buf + 7 <= end && str_iequals((String)buf[0:7], "chunked")) {
                    char after = (buf + 7 < end) ? buf[7] : ',';
                    if (after == ',' || after == ' ' || after == '\t' || buf + 7 == end) {
                        self.chunked = true;
                        return true;
                    }
                }
                // skip to next comma
                while (buf < end && *buf != ',') buf++;
            }
        }
    }
    return false;
}

fn bool Response.decode_content_length(&self)
{
    for (uint i = 0; i < self.n_headers; i++) {
        String key = self.headers[i].key;
        String val = self.headers[i].value;

        // Content-Length
        if (key.len == 14 && str_iequals(key, "Content-Length")) {
            usz n = 0;
            foreach (char c : val) {
                if (c < '0' || c > '9') return false; // non-digit → invalid
                n = n * 10 + (usz)(c - '0');
            }
            self.content_length = n;
            return true;
        }

        // Transfer-Encoding: chunked
        if (key.len == 17 && str_iequals(key, "Transfer-Encoding")) {
            // value may be "chunked" or "gzip, chunked" etc.
            char* buf = val.ptr;
            char* end = buf + val.len;
            while (buf < end) {
                // skip whitespace / commas
                while (buf < end && (*buf == ' ' || *buf == '\t' || *buf == ',')) buf++;
                if (buf + 7 <= end && str_iequals((String)buf[0:7], "chunked")) {
                    char after = (buf + 7 < end) ? buf[7] : ',';
                    if (after == ',' || after == ' ' || after == '\t' || buf + 7 == end) {
                        self.chunked = true;
                        return true;
                    }
                }
                // skip to next comma
                while (buf < end && *buf != ',') buf++;
            }
        }
    }
    return false;
}



fn bool Request.decode_cookies(&self)
{
    uint n = 0;
    bool in_cookie = false;

    for (uint i = 0; i < self.n_headers && n < MAX; i++) {
        String key = self.headers[i].key;
        String val = self.headers[i].value;

        // A header line with empty key is a continuation of the previous header.
        // Only process it if we are already inside a Cookie header.
        if (key.len == 0) {
            if (!in_cookie) continue;
            // fall through and parse val as more cookie pairs
        } else if (key.len == 6 && str_iequals(key, "Cookie")) {
            in_cookie = true;
            // fall through and parse val
        } else {
            // Any other named header ends the Cookie continuation block.
            in_cookie = false;
            continue;
        }

        // Parse cookie pairs from val.
        // Format is: name=value; name=value; ...
        char* buf = val.ptr;
        char* end = buf + val.len;

        while (buf < end && n < MAX) {
            // Skip leading whitespace before the cookie name.
            while (buf < end && (*buf == ' ' || *buf == '\t')) buf++;
            if (buf >= end) break;

            // Read name up to '=' or ';' or end.
            char* name_start = buf;
            while (buf < end && *buf != '=' && *buf != ';') buf++;
            char* name_end = buf;

            // Trim trailing whitespace from name.
            while (name_end > name_start &&
                   (name_end[-1] == ' ' || name_end[-1] == '\t')) name_end--;

            // Skip tokens with empty name entirely.
            if (name_end == name_start) {
                while (buf < end && *buf != ';') buf++;
                if (buf < end) buf++;
                continue;
            }

            self.cookies[n].key= (String)name_start[0 : name_end - name_start];

            // Read value only when an equals sign is present.
            if (buf < end && *buf == '=') {
                buf++; // skip '='

                // Quoted value: strip surrounding double quotes.
                if (buf < end && *buf == '"') {
                    buf++; // skip opening quote
                    char* v_start = buf;
                    while (buf < end && *buf != '"') buf++;
                    self.cookies[n].value = (String)v_start[0 : buf - v_start];
                    if (buf < end) buf++; // skip closing quote
                } else {
                    char* v_start = buf;
                    while (buf < end && *buf != ';') buf++;
                    char* v_end = buf;
                    // Trim trailing whitespace from value.
                    while (v_end > v_start &&
                           (v_end[-1] == ' ' || v_end[-1] == '\t')) v_end--;
                    self.cookies[n].value = (String)v_start[0 : v_end - v_start];
                }
            } else {
                // Name only token, no value.
                self.cookies[n].value = "";
            }

            n++;

            // Skip the semicolon separator between pairs.
            if (buf < end && *buf == ';') buf++;
        }
    }
    
    self.n_cookies = n;

    return n > 0;
}



fn bool Response.decode_setcookies(&self)
{
    uint n = 0;

    for (uint i = 0; i < self.n_headers && n < MAX; i++) {
        String key = self.headers[i].key;
        String val = self.headers[i].value;

        // Each Set-Cookie header is a single independent cookie.
        // A continuation line (empty key) extends the attribute list
        // of the most recently started Set-Cookie entry.
        bool is_continuation = (key.len == 0);
        bool is_set_cookie   = (key.len == 10 && str_iequals(key, "Set-Cookie"));

        if (!is_set_cookie && !is_continuation) continue;

        // A continuation line with no active entry is ignored.
        if (is_continuation && n == 0) continue;

        // A new Set-Cookie line always starts a fresh entry.
        SetCookie* sc;
        if (is_set_cookie) {
            sc = &self.set_cookies[n];
            *sc = {};  // zero out all fields

            // First token before the first semicolon is name=value.
            char* buf = val.ptr;
            char* end = buf + val.len;

            char* semi = buf;
            while (semi < end && *semi != ';') semi++;

            // Split name and value at the first '='.
            char* eq = buf;
            while (eq < semi && *eq != '=') eq++;

            char* name_end = eq;
            while (name_end > buf &&
                   (name_end[-1] == ' ' || name_end[-1] == '\t')) name_end--;
            sc.name = (String)buf[0 : name_end - buf];

            if (eq < semi) {
                char* v_start = eq + 1;  // skip '='
                char* v_end   = semi;
                while (v_end > v_start &&
                       (v_end[-1] == ' ' || v_end[-1] == '\t')) v_end--;
                sc.value = (String)v_start[0 : v_end - v_start];
            }

            // Skip past the name=value token.
            val = (semi < end) ? (String)(semi + 1)[0 : end - semi - 1] : "";
            n++;
        } else {
            // Continuation line appends attributes to the last entry.
            sc = &self.set_cookies[n - 1];
        }

        // Parse semicolon separated attributes from the remainder of the line.
        char* buf = val.ptr;
        char* end = buf + val.len;

        while (buf < end) {
            // Skip leading whitespace and semicolons.
            while (buf < end && (*buf == ' ' || *buf == '\t' || *buf == ';')) buf++;
            if (buf >= end) break;

            // Read attribute token up to the next semicolon.
            // Exception: Expires value may itself contain a comma but not a
            // semicolon, so plain semicolon splitting is safe here.
            char* tok_start = buf;
            while (buf < end && *buf != ';') buf++;
            char* tok_end = buf;

            // Trim trailing whitespace from attribute token.
            while (tok_end > tok_start &&
                   (tok_end[-1] == ' ' || tok_end[-1] == '\t')) tok_end--;

            char* eq = tok_start;
            while (eq < tok_end && *eq != '=') eq++;

            bool has_val = (eq < tok_end);

            // Attribute name span.
            char* attr_start = tok_start;
            char* attr_end   = has_val ? eq : tok_end;
            while (attr_end > attr_start &&
                   (attr_end[-1] == ' ' || attr_end[-1] == '\t')) attr_end--;
            usz attr_len = (usz)(attr_end - attr_start);

            // Attribute value span (when present).
            char* aval_start = has_val ? eq + 1 : null;
            char* aval_end   = tok_end;
            if (aval_start != null) {
                while (aval_start < aval_end &&
                       (*aval_start == ' ' || *aval_start == '\t')) aval_start++;
            }

            // Match against known attribute names (case insensitive).
            if (attr_len == 6 && str_iequals((String)attr_start[0:6], "Domain")) {
                if (aval_start != null) {
                    sc.domain = (String)aval_start[0 : aval_end - aval_start];
                }
            } else if (attr_len == 4 && str_iequals((String)attr_start[0:4], "Path")) {
                if (aval_start != null) {
                    sc.path = (String)aval_start[0 : aval_end - aval_start];
                }
            } else if (attr_len == 7 && str_iequals((String)attr_start[0:7], "Expires")) {
                if (aval_start != null) {
                    sc.expires = (String)aval_start[0 : aval_end - aval_start];
                }
            } else if (attr_len == 7 && str_iequals((String)attr_start[0:7], "Max-Age")) {
                if (aval_start != null) {
                    sc.max_age = (String)aval_start[0 : aval_end - aval_start];
                }
            } else if (attr_len == 8 && str_iequals((String)attr_start[0:8], "SameSite")) {
                if (aval_start != null) {
                    sc.same_site = (String)aval_start[0 : aval_end - aval_start];
                }
            } else if (attr_len == 8 && str_iequals((String)attr_start[0:8], "HttpOnly")) {
                sc.http_only = true;
            } else if (attr_len == 6 && str_iequals((String)attr_start[0:6], "Secure")) {
                sc.secure = true;
            }
        }
    }

    self.n_set_cookies = n;
    return n > 0;
}

fn usz decode_query(String query, KeyValue[] pairs)
{
    if (query.len == 0) return 0;

    char* buf = query.ptr;
    char* end = buf + query.len;
    usz   n   = 0;

    while (buf < end && n < pairs.len) {
        // Skip stray ampersands or semicolons between tokens.
        while (buf < end && (*buf == '&' || *buf == ';')) buf++;
        if (buf >= end) break;

        // Read key up to '=', '&', ';', or end.
        char* key_start = buf;
        while (buf < end && *buf != '=' && *buf != '&' && *buf != ';') buf++;
        char* key_end = buf;

        // Trim trailing whitespace from key.
        while (key_end > key_start &&
               (key_end[-1] == ' ' || key_end[-1] == '\t')) key_end--;

        // Skip tokens with empty key.
        if (key_end == key_start) continue;

        pairs[n].key = (String)key_start[0 : key_end - key_start];

        // Read value only when an equals sign is present.
        if (buf < end && *buf == '=') {
            buf++; // skip '='

            char* val_start = buf;
            while (buf < end && *buf != '&' && *buf != ';') buf++;
            char* val_end = buf;

            // Trim trailing whitespace from value.
            while (val_end > val_start &&
                   (val_end[-1] == ' ' || val_end[-1] == '\t')) val_end--;

            pairs[n].value = (String)val_start[0 : val_end - val_start];
        } else {
            // Key only token, no value.
            pairs[n].value = "";
        }

        n++;
    }

    return n;
}

fn bool Request.decode_query(&self)
{
    self.n_queries = decode_query(self.url.query, &self.queries);
    return true;
}

// Helper: find the next occurrence of delim starting at scan.
// Returns null if not found.
macro char* find_boundary(char* scan, char* end, char* delim, uint len)
{
    while (scan + len <= end) {
        if (string::strncmp(scan, delim, len) == 0) return scan;
        scan++;
    }
    return null;
}


fn bool Request.decode_form(&self)
{
    if (self.content_length == 0) {
        self.decode_content_length();
    }


    String body = (String)self.body[0:self.content_length];
    if (body.len == 0) return false;

    // Find Content-Type header.
    String content_type;
    bool found = false;
    for (uint i = 0; i < self.n_headers; i++) {
        if (self.headers[i].key.len == 12 &&
            str_iequals(self.headers[i].key, "Content-Type")) {
            content_type = self.headers[i].value;
            found = true;
            break;
        }
    }
    if (!found || content_type.len == 0) return false;

    // application/x-www-form-urlencoded
    if (content_type.len >= 33 &&
        str_iequals((String)content_type.ptr[0:33],
                    "application/x-www-form-urlencoded")) {
        usz n = decode_query(body, &self.form);
        self.n_form = (uint)n;
        return n > 0;
    }

    // multipart/form-data
    if (content_type.len < 19 ||
        !str_iequals((String)content_type.ptr[0:19], "multipart/form-data")) {
        return false;
    }

    // Locate "boundary=" in the Content-Type value.
    String boundary;
    {
        char* p   = content_type.ptr;
        char* end = p + content_type.len;
        while (p + 9 <= end) {
            if (str_iequals((String)p[0:9], "boundary=")) {
                p += 9;
                char* b_start = p;
                while (p < end && *p != ' ' && *p != '\t' && *p != ';') p++;
                boundary = (String)b_start[0 : p - b_start];
                break;
            }
            p++;
        }
    }
    if (boundary.len == 0) return false;

    // Build the delimiter string: "--" + boundary.
    // RFC 2046 limits boundary to 70 chars, so 72 is always enough.
    char[72] delim_buf;
    delim_buf[0] = '-';
    delim_buf[1] = '-';
    for (usz i = 0; i < boundary.len && i < 70; i++) {
        delim_buf[i + 2] = boundary[i];
    }
    String delim = (String)delim_buf[0 : boundary.len + 2];

    char* buf = body.ptr;
    char* end = buf + body.len;

    // Skip the opening delimiter line.
    buf = find_boundary(buf, end, delim.ptr, delim.len);
    if (buf == null) return false;
    buf += delim.len;
    if (buf < end && *buf == '\r') buf++;
    if (buf < end && *buf == '\n') buf++;

    while (buf < end) {
        // Parse part headers
        String part_name;
        String part_filename;
        String part_mime;

        while (buf < end) {
            // A blank line signals the end of part headers.
            if (*buf == '\r' && buf + 1 < end && buf[1] == '\n') {
                buf += 2;
                break;
            }
            if (*buf == '\n') {
                buf++;
                break;
            }

            // Read one part header line up to CRLF or LF.
            char* line_start = buf;
            while (buf < end && *buf != '\r' && *buf != '\n') buf++;
            char* line_end = buf;
            if (buf < end && *buf == '\r') buf++;
            if (buf < end && *buf == '\n') buf++;

            String line = (String)line_start[0 : line_end - line_start];
            if (line.len == 0) continue;

            // Content-Disposition: extract name= and filename=.
            if (line.len >= 19 &&
                str_iequals((String)line.ptr[0:19], "Content-Disposition")) {

                char* lp = line.ptr;
                char* le = lp + line.len;
                while (lp < le) {
                    // Match "filename=" before "name=" to avoid prefix clash.
                    if (lp + 9 <= le &&
                        str_iequals((String)lp[0:9], "filename=")) {

                        lp += 9;
                        bool q = (lp < le && *lp == '"');
                        if (q) lp++;
                        char* s = lp;
                        while (lp < le && *lp != '"' &&
                               *lp != ';' && *lp != ' ') lp++;
                        part_filename = (String)s[0 : lp - s];
                        if (q && lp < le) lp++;

                        continue;
                    }
                    // Match "name=" that is NOT preceded by 'e' (i.e. not filename=).
                    if (lp + 5 <= le &&
                        str_iequals((String)lp[0:5], "name=") &&
                        (lp == line.ptr || lp[-1] != 'e')) {
                        lp += 5;
                        bool q = (lp < le && *lp == '"');
                        if (q) lp++;
                        char* s = lp;
                        while (lp < le && *lp != '"' &&
                               *lp != ';' && *lp != ' ') lp++;
                        part_name = (String)s[0 : lp - s];
                        if (q && lp < le) lp++;

                        continue;
                    }
                    lp++;
                }
                continue;
            }

            // Content-Type: record the MIME type of this part.
            if (line.len >= 12 &&
                str_iequals((String)line.ptr[0:12], "Content-Type")) {
                char* lp = line.ptr;
                char* le = lp + line.len;
                while (lp < le && *lp != ':') lp++;
                if (lp < le) lp++;
                while (lp < le && (*lp == ' ' || *lp == '\t')) lp++;
                part_mime = (String)lp[0 : le - lp];
                continue;
            }
        }

        // A part with no name is malformed, skip.
        if (part_name.len == 0) {
            buf = find_boundary(buf, end, delim.ptr, delim.len);
            if (buf == null) break;
            buf += delim.len;
            if (buf + 1 < end && buf[0] == '-' && buf[1] == '-') break;
            if (buf < end && *buf == '\r') buf++;
            if (buf < end && *buf == '\n') buf++;
            continue;
        }

        // Locate end of part body (next delimiter)
        char* val_start = buf;
        char* delim_pos = find_boundary(buf, end, delim.ptr, delim.len);

        if (delim_pos == null) {
            warn("boundary missing");
            break;
        }

        // Strip the trailing CRLF that precedes the delimiter.
        char* val_end = delim_pos;
        while (val_end > val_start &&
               (val_end[-1] == '\r' || val_end[-1] == '\n')) val_end--;
// warn("part_filename:%s", part_filename);
        // Store the part
        if (part_filename.len > 0) {
            // File upload part: goes into files[].
            if (self.n_files < MAX) {
                self.files[self.n_files].name     = part_name;
                self.files[self.n_files].filename = part_filename;
                self.files[self.n_files].mime     = part_mime;
                self.files[self.n_files].data     =
                    (String)val_start[0 : val_end - val_start];
                self.n_files++;
            }
        } else {
            // Regular text field: goes into form[].
            if (self.n_form < MAX) {
                self.form[self.n_form].key = part_name;
                self.form[self.n_form].value =
                    (String)val_start[0 : val_end - val_start];
                self.n_form++;
            }
        }

        // Advance past the delimiter.
        buf = delim_pos + delim.len;

        // "--" after the delimiter means the final boundary, stop.
        if (buf + 1 < end && buf[0] == '-' && buf[1] == '-') break;

        // Skip the CRLF that follows an intermediate delimiter.
        if (buf < end && *buf == '\r') buf++;
        if (buf < end && *buf == '\n') buf++;
    }

    return (self.n_form + self.n_files) > 0;
}
