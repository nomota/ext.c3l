// helpers.c3

// common helper functions shared by entire module

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

fn bool is_digit(char c) @inline
{
    return c >= '0' && c <= '9';
}

fn bool is_space(char c) @inline
{
    return c == ' ' || c == '\t';
}

fn bool is_hex(char c)
{
    if (c >= '0' && c <= '9') return true;
    if (c >= 'a' && c <= 'f') return true;
    if (c >= 'A' && c <= 'F') return true;
    return false;
}

fn char hex_value(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}


fn bool is_token_char(char c)
{
    if (c <= 32 || c == 127) return false;

    switch (c)
    {
        case '(':
        case ')':
        case '<':
        case '>':
        case '@':
        case ',':
        case ';':
        case ':':
        case '\\':
        case '"':
        case '/':
        case '[':
        case ']':
        case '?':
        case '=':
        case '{':
        case '}':
            return false;
        default:
            return true;
    }
}

fn sz find_char(String s, char needle, sz start = 0)
{
    for (sz i = start; i < s.len; i++)
    {
        if (s[i] == needle) return (sz)i;
    }

    return -1;
}

fn char[]? bytes_clone(char[] data) 
{
    if (data.len == 0) return {};

    char* p = localmem.malloc(data.len)!;
    p[0:data.len] = data[0:data.len];

    return p[0:data.len];
}

fn void bytes_free(char[] body)
{
    if (body.ptr != null && body.len > 0) {
        localmem.free(body);
    }
}


fn sz[2]? find_line_end(char[] data, sz start)
{
    sz i = start;

    while (i < data.len)
    {
        if (i + 1 < data.len && data[i] == '\r' && data[i + 1] == '\n')
        {
            return { i, 2 };
        }

        if (data[i] == '\n')
        {
            return { i, 1 };
        }

        i++;
    }

    return NOT_FOUND~;
}

fn sz find_bytes(char[] data, char[] needle, sz start) 
{
    if (needle.len == 0) return start;
    if (data.len < needle.len) return -1;

    for (sz i = start; i + needle.len <= data.len; i++)
    {
        if (data[i:needle.len] == needle[0:needle.len]) return i;
    }

    return -1;
}

fn sz[2]? find_header_end(char[] data, sz start = 0, sz end = -1)
{
    if (end == -1) end = data.len;
    if (end < start+2) return NOT_FOUND~;

    for (sz i = start; i < end; i++)
    {
        if (i+3 < data.len && 
            data[i] == '\r'
            && data[i + 1] == '\n'
            && data[i + 2] == '\r'
            && data[i + 3] == '\n')
        {
            return {i,4};
        }
        if (i+1 < data.len && 
            data[i] == '\n'
            && data[i + 1] == '\n')
        {
            return {i,2};
        }
    }

    return NOT_FOUND~;
}

fn sz find_crlf(char[] data, sz start) 
{
    if (start < 0) return -1;

    for (sz i = start; i + 1 < data.len; i++)
    {
        if (data[i] == '\r' && data[i + 1] == '\n')
        {
            return i;
        }
    }

    return -1;
}


fn sz find_lf(char[] data, sz start)
{
    if (start < 0) return -1;

    for (sz i = start; i < data.len; i++)
    {
        if (data[i] == '\n') return i;
    }

    return -1;
}

fn String trim_quotes(String s)
{
    s = s.trim();

    if (s.len >= 2 && s[0] == '"' && s[s.len - 1] == '"')
    {
        return s[1:s.len - 2];
    }

    return s;
}

fn String? percent_decode(String value)
{
    char* p = localmem.malloc(value.len + 1)!;
    defer catch localmem.free(p);
    
    sz pos = 0;
    sz i = 0;

    while (i < value.len)
    {
        if (value[i] != '%')
        {
            p[pos++] = value[i];
            i++;
            continue;
        }
        
        if (i + 2 >= value.len) return INVALID_RFC5987_VALUE~;
        if (!is_hex(value[i+1]) || !is_hex(value[i+2])) return INVALID_RFC5987_VALUE~;
        
        int hi = hex_value(value[i + 1]);
        int lo = hex_value(value[i + 2]);

        if (hi < 0 || lo < 0) return INVALID_RFC5987_VALUE~;
        if (hi == 0 && lo == 0) return INVALID_RFC5987_VALUE~;

        p[pos++] = (char)(hi * 16 + lo);
        i += 3;
    }

    p[pos] = 0;
    return (String)p[0:pos];
}

fn sz? parse_sz(String s) 
{
    if (s.len == 0) return BAD_REQUEST~;

    sz value = 0;

    for (sz i = 0; i < s.len; i++)
    {
        char c = s[i];
        if (!is_digit(c)) return BAD_REQUEST~;

        sz digit = (sz)(c - '0');

        // Simple overflow guard.
        if (value > ((sz::max - digit) / 10))
        {
            return REQUEST_TOO_LARGE~;
        }

        value = value * 10 + digit;
    }

    return value;
}


fn sz write_string(char[] out, sz pos, String s)
{
    out[pos:s.len] = s[0:s.len];
    return pos + s.len;
}

fn sz write_char(char[] out, sz pos, char c)
{
    out[pos] = c;
    return pos + 1;
}

fn sz write_crlf(char[] out, sz pos)
{
    out[pos++] = '\r';
    out[pos++] = '\n';
    return pos;
}

fn sz write_int(char[] out, sz pos, int n)
{
    String s = string::bformat(out[pos..], "%d", n);
    return pos+s.len;
}

fn bool ascii_eq_ignore_case(char a, char b) @inline
{
    if (a >= 'A' && a <= 'Z') a = a + 32;
    if (b >= 'A' && b <= 'Z') b = b + 32;
    return a == b;
}

fn bool str_iequals(String a, String b)
{
    if (a.len != b.len) return false;

    for (sz i = 0; i < a.len; i++)
    {
        if (!ascii_eq_ignore_case(a[i], b[i])) return false;
    }

    return true;
}

fn bool is_valid_name(String name)
{
    if (name.len == 0) return false;

    for (sz i = 0; i < name.len; i++)
    {
        char c = name[i];

        // RFC token-ish validation.
        // Disallow CTL, space, colon.
        if (c <= 32 || c == 127 || c == ':') return false;

        switch (c)
        {
            case '(':
            case ')':
            case '<':
            case '>':
            case '@':
            case ',':
            case ';':
            case '\\':
            case '"':
            case '/':
            case '[':
            case ']':
            case '?':
            case '=':
            case '{':
            case '}':
                return false;
            default:
        }
    }

    return true;
}

fn bool is_valid_value(String value)
{
    for (sz i = 0; i < value.len; i++)
    {
        char c = value[i];

        if (c == '\r' || c == '\n') return false;
        if (c == 127) return false;
        if (c < 32 && c != '\t') return false;
    }

    return true;
}

fn String str_clone(String s) @inline
{
    return s.copy(localmem);
}

fn void str_free(String s) @inline
{
    localmem.free(s);
}

fn bool header_has_token(String value, String token)
{
    sz start = 0;

    while (start <= value.len) {
        sz end = start;

        while (end < value.len && value[end] != ',') {
            end++;
        }

        String item = value[start:end - start].trim();

        if (str_iequals(item, token)) return true;
        if (end >= value.len) break;

        start = end + 1;
    }

    return false;
}


// eof