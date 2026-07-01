// multipart.c3

// multipart/form-data parser for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::collections::list;
import ext::mem;
import c::errno;


// 
// Faults
// 

faultdef UNSUPPORTED_MULTIPART_TYPE;
faultdef INVALID_MULTIPART_BODY;
faultdef MULTIPART_BODY_INCOMPLETE;
faultdef BOUNDARY_NOT_FOUND;
faultdef MULTIPART_TOO_LARGE;
faultdef INVALID_RFC5987_VALUE;
faultdef UNSUPPORTED_RFC5987_CHARSET;

// 
// Multipart types
// 

struct MultipartPart
{
    String name;
    String filename;
    String content_type;

    Headers headers;

    char[] body;
    bool owns_body;
}

struct MultipartForm
{
    List{MultipartPart} parts;
}


// 
// Helpers
// 

fn bool is_boundary_char(char c) @local
{
    if (c >= '0' && c <= '9') return true;
    if (c >= 'a' && c <= 'z') return true;
    if (c >= 'A' && c <= 'Z') return true;

    switch (c)
    {
        case '\'':
        case '(':
        case ')':
        case '+':
        case '_':
        case ',':
        case '-':
        case '.':
        case '/':
        case ':':
        case '=':
        case '?':
            return true;
        default:
            return false;
    }
}

fn bool boundary_valid(String boundary) @local
{
    if (boundary.len == 0) return false;
    if (boundary.len > 70) return false;

    for (sz i = 0; i < boundary.len; i++)
    {
        if (!is_boundary_char(boundary[i])) return false;
    }

    return true;
}

fn String? content_type_param(String content_type, String name)
{
    sz pos = 0;

    while (pos < content_type.len)
    {
        sz semi = -1;

        for (sz i = pos; i < content_type.len; i++)
        {
            if (content_type[i] == ';')
            {
                semi = i;
                break;
            }
        }

        String part;

        if (semi < 0)
        {
            part = content_type[pos:content_type.len - pos].trim();
            pos = content_type.len;
        }
        else
        {
            part = content_type[pos:semi - pos].trim();
            pos = semi + 1;
        }

        sz eq = find_char(part, '=', 0);

        if (eq <= 0) continue;

        String key = part[0:eq].trim();
        String value = trim_quotes(part[eq + 1:part.len - eq - 1]);

        if (str_iequals(key, name))
        {
            return value.copy(localmem);
        }
    }

    return NOT_FOUND~;
}

fn String? boundary_from_content_type(String content_type)
{
    String? boundary = content_type_param(content_type, "boundary");
    if (catch err = boundary) return err~;

    if (!boundary_valid(boundary))
    {
        localmem.free(boundary);
        return BOUNDARY_NOT_FOUND~;
    }

    return boundary;
}

fn bool Request.is_multipart(&self)
{
    String? ct = self.header("Content-Type");
    if (catch err = ct) return false;

    String base = content_type_base(ct);

    return str_iequals(base, "multipart/form-data");
}

fn bool Context.is_multipart(&self)
{
    if (self.req == null) return false;
    return self.req.is_multipart();
}

fn String? header_param(String value, String name)
{
    return content_type_param(value, name);
}


fn String? latin1_to_utf8_copy(String value) @local
{
    char* p = localmem.malloc(value.len * 2 + 1)!;

    sz pos = 0;

    for (sz i = 0; i < value.len; i++)
    {
        int b = (int)value[i];

        if (b < 0x80)
        {
            p[pos++] = (char)b;
        }
        else
        {
            p[pos++] = (char)(0xC0 | (b >> 6));
            p[pos++] = (char)(0x80 | (b & 0x3F));
        }
    }

    p[pos] = 0;
    return (String)p[0:pos];
}

fn String? decode_rfc5987_value(String raw_value)
{
    String value = trim_quotes(raw_value);

    sz first_quote = -1;

    for (sz i = 0; i < value.len; i++)
    {
        if (value[i] == '\'')
        {
            first_quote = i;
            break;
        }
    }

    if (first_quote <= 0)
    {
        return INVALID_RFC5987_VALUE~;
    } 

    sz second_quote = -1;

    for (sz i = first_quote + 1; i < value.len; i++)
    {
        if (value[i] == '\'')
        {
            second_quote = i;
            break;
        }
    }

    if (second_quote < 0)
    {
        return INVALID_RFC5987_VALUE~;
    }

    String charset = value[0:first_quote];
    String encoded = value[second_quote + 1:value.len - second_quote - 1];

    String decoded = percent_decode(encoded)!;

    if (str_iequals(charset, "UTF-8") || str_iequals(charset, "UTF8"))
    {
        return decoded;
    }

    if (str_iequals(charset, "ISO-8859-1") || str_iequals(charset, "LATIN1"))
    {
        defer localmem.free(decoded);

        return latin1_to_utf8_copy(decoded)!;
    }

    localmem.free(decoded);
    return UNSUPPORTED_RFC5987_CHARSET~;
}

// 
// MultipartPart lifecycle
// 

fn void MultipartPart.init(&self)
{
    self.name = "";
    self.filename = "";
    self.content_type = "";

    self.headers.init();

    self.body = {};
    self.owns_body = false;
}

fn void MultipartPart.free(&self)
{
    str_free(self.name);
    str_free(self.filename);
    str_free(self.content_type);

    self.headers.free();

    if (self.owns_body)
    {
        bytes_free(self.body);
    }

    self.name = "";
    self.filename = "";
    self.content_type = "";
    self.body = {};
    self.owns_body = false;
}

fn bool MultipartPart.is_file(&self) @inline
{
    return self.filename.len > 0;
}

fn String MultipartPart.text(&self)
{
    return (String)self.body;
}

fn void? MultipartPart.set_body_copy(&self, char[] body)
{
    if (body.len > MAX_BODY_BYTES)
    {
        return MULTIPART_TOO_LARGE~;
    }

    if (self.owns_body)
    {
        bytes_free(self.body);
    }

    if (body.len == 0)
    {
        self.body = {};
        self.owns_body = false;
        return;
    }

    self.body = bytes_clone(body)!;
    self.owns_body = true;
}


// 
// MultipartForm lifecycle
// 

fn void MultipartForm.init(&self)
{
    self.parts.init(localmem);
}

fn void MultipartForm.free(&self)
{
    for (sz i = 0; i < self.parts.len(); i++)
    {
        self.parts[i].free();
    }

    self.parts.free();
}

fn sz MultipartForm.len(&self) @inline
{
    return self.parts.len();
}

fn MultipartPart* MultipartForm.get_part(&self, sz index)
{
    if (index < 0 || index >= self.parts.len()) return null;
    return &self.parts[index];
}

fn MultipartPart* MultipartForm.get(&self, String name)
{
    for (sz i = 0; i < self.parts.len(); i++)
    {
        MultipartPart* part = &self.parts[i];

        if (part.name == name) return part;
    }

    return null;
}

fn String? MultipartForm.value(&self, String name)
{
    MultipartPart* part = self.get(name);

    if (part == null) return NOT_FOUND~;
    if (part.is_file()) return NOT_FOUND~;

    return part.text();
}

fn MultipartPart* MultipartForm.file(&self, String name)
{
    MultipartPart* part = self.get(name);

    if (part == null) return null;
    if (!part.is_file()) return null;

    return part;
}


// 
// Part parser
// 

fn void? parse_part_headers(MultipartPart* part, char[] header_block) @local
{
    sz pos = 0;

    while (pos < header_block.len)
    {
        sz line_end = find_crlf(header_block, pos);
        if (line_end < 0) return INVALID_MULTIPART_BODY~;

        if (line_end == pos) break;

        String line = (String)header_block[pos:line_end - pos];

        sz colon = find_char(line, ':', 0);
        if (colon <= 0) return INVALID_HEADER~;

        String name = line[0:colon];
        String value = line[colon + 1:line.len - colon - 1].trim();

        if (!is_valid_name(name)) return INVALID_HEADER~;

        part.headers.add(name, value)!;

        pos = line_end + 2;
    }

    String? cd = part.headers.get("Content-Disposition");
    if (catch err = cd) return INVALID_MULTIPART_BODY~;

    String? field_name = header_param(cd, "name");
    if (catch err = field_name) return INVALID_MULTIPART_BODY~;
    defer localmem.free(field_name);

    str_free(part.name);
    part.name = str_clone(field_name);

    String? filename_ext = header_param(cd, "filename*");
    
    if (try filename_ext)
    {
        defer localmem.free(filename_ext);
    
        String decoded_filename = decode_rfc5987_value(filename_ext)!;
        defer localmem.free(decoded_filename);
    
        str_free(part.filename);
        part.filename = str_clone(decoded_filename);
    }
    else
    {
        String? filename = header_param(cd, "filename");
    
        if (try filename)
        {
            defer localmem.free(filename);
    
            str_free(part.filename);
            part.filename = str_clone(filename);
        }
    }
    
    String? ct = part.headers.get("Content-Type");
    if (try ct)
    {
        str_free(part.content_type);
        part.content_type = str_clone(ct);
    }
}

fn void? add_part(MultipartForm* form, char[] header_block, char[] body) @local
{
    MultipartPart part;
    part.init();

    if (catch err = parse_part_headers(&part, header_block))
    {
        part.free();
        return err~;
    }

    if (catch err = part.set_body_copy(body))
    {
        part.free();
        return err~;
    }

    form.parts.push(part);
}


// 
// Multipart parser
// 

fn MultipartForm? multipart_parse(char[] body, String boundary)
{
    if (!boundary_valid(boundary))
    {
        return BOUNDARY_NOT_FOUND~;
    }

    MultipartForm form;
    form.init();

    DString marker;
    marker.init(localmem, boundary.len + 4);
    defer marker.free();

    marker.append((char[])"--");
    marker.append((char[])boundary);

    DString next_marker;
    next_marker.init(localmem, boundary.len + 6);
    defer next_marker.free();

    next_marker.append((char[])"\r\n--");
    next_marker.append((char[])boundary);

    char[] first_marker = (char[])marker.str_view();
    char[] repeated_marker = (char[])next_marker.str_view();

    sz pos = find_bytes(body, first_marker, 0);
    if (pos < 0)
    {
        form.free();
        return BOUNDARY_NOT_FOUND~;
    }

    pos += first_marker.len;

    if (pos + 1 < body.len && body[pos] == '-' && body[pos + 1] == '-')
    {
        return form;
    }

    if (pos + 1 >= body.len || body[pos] != '\r' || body[pos + 1] != '\n')
    {
        form.free();
        return INVALID_MULTIPART_BODY~;
    }

    pos += 2;

    while (true)
    {
        sz[2]? header_end = find_header_end(body, pos, body.len)!;
        if (catch err = header_end)
        {
            form.free();
            return MULTIPART_BODY_INCOMPLETE~;
        }

        char[] header_block = body[pos:header_end[0] - pos + 2];

        sz body_start = header_end[0] + 4;

        sz next = find_bytes(body, repeated_marker, body_start);
        if (next < 0)
        {
            form.free();
            return MULTIPART_BODY_INCOMPLETE~;
        }

        char[] part_body = body[body_start:next - body_start];

        add_part(&form, header_block, part_body)!;

        pos = next + repeated_marker.len;

        if (pos + 1 < body.len && body[pos] == '-' && body[pos + 1] == '-')
        {
            return form;
        }

        if (pos + 1 >= body.len || body[pos] != '\r' || body[pos + 1] != '\n')
        {
            form.free();
            return INVALID_MULTIPART_BODY~;
        }

        pos += 2;
    }
}


// 
// Request helpers
// 

fn MultipartForm? Request.multipart(&self)
{
    if (!self.is_multipart())
    {
        return UNSUPPORTED_MULTIPART_TYPE~;
    }

    String ct = self.header("Content-Type")!;
    String boundary = boundary_from_content_type(ct)!;
    defer localmem.free(boundary);

    return multipart_parse(self.body, boundary)!;
}

fn MultipartPart*? Request.multipart_file(&self, String name)
{
    MultipartForm form = self.multipart()!;
    defer form.free();

    MultipartPart* part = form.file(name);

    if (part == null) return NOT_FOUND~;

    MultipartPart* copy = localmem.alloc(MultipartPart)!;
    copy.init();

    copy.name = str_clone(part.name);
    copy.filename = str_clone(part.filename);
    copy.content_type = str_clone(part.content_type);
    copy.headers.copy_from(&part.headers)!;
    copy.set_body_copy(part.body)!;

    return copy;
}

fn String? Request.multipart_value_copy(&self, String name)
{
    MultipartForm form = self.multipart()!;
    defer form.free();

    String value = form.value(name)!;

    return value.copy(localmem);
}

fn void? Context.ensure_multipart_cache(&self)
{
    if (self.multipart_cache_ready) return;

    if (self.req == null) return CONTEXT_NOT_READY~;

    if (!self.req.is_multipart())
    {
        return UNSUPPORTED_MULTIPART_TYPE~;
    }

    self.multipart_cache.free();
    self.multipart_cache.init();

    String ct = self.req.header("Content-Type")!;
    String boundary = boundary_from_content_type(ct)!;
    defer localmem.free(boundary);

    MultipartForm form = multipart_parse(self.req.body, boundary)!;

    self.multipart_cache = form;
    self.multipart_cache_ready = true;
}

// 
// Context helpers
// 

fn MultipartForm? Context.multipart(&self)
{
    if (self.req == null) return CONTEXT_NOT_READY~;

    return self.req.multipart()!;
}

fn String? Context.multipart_value_copy(&self, String name)
{
    if (self.req == null) return CONTEXT_NOT_READY~;

    return self.req.multipart_value_copy(name)!;
}

fn MultipartPart*? Context.multipart_file(&self, String name)
{
    if (self.req == null) return CONTEXT_NOT_READY~;

    return self.req.multipart_file(name)!;
}

fn MultipartForm* Context.multiparts(&self)
{
    if (catch self.ensure_multipart_cache())
    {
        return null;
    }

    return &self.multipart_cache;
}

fn MultipartPart* Context.multipart_part(&self, String name)
{
    if (catch self.ensure_multipart_cache())
    {
        return null;
    }

    return self.multipart_cache.get(name);
}

fn MultipartPart* Context.multipart_file_ref(&self, String name)
{
    if (catch self.ensure_multipart_cache())
    {
        return null;
    }

    return self.multipart_cache.file(name);
}

fn String? Context.multipart_value(&self, String name)
{
    self.ensure_multipart_cache()!;

    return self.multipart_cache.value(name);
}

fn bool Context.has_multipart(&self, String name)
{
    if (catch self.ensure_multipart_cache())
    {
        return false;
    }

    return self.multipart_cache.get(name) != null;
}

fn bool Context.has_multipart_file(&self, String name)
{
    if (catch self.ensure_multipart_cache())
    {
        return false;
    }

    return self.multipart_cache.file(name) != null;
}

fn void multipart_part_free(MultipartPart* part)
{
    if (part == null) return;

    part.free();
    localmem.free(part);
}

// eof