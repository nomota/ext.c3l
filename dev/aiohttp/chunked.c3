// chunked.c3

// HTTP chunked transfer decoding for ext::aiohttp

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiohttp;

import ext::mem;
import c::errno;


// 
// Faults
// 

faultdef INVALID_CHUNKED_BODY;
faultdef CHUNKED_BODY_INCOMPLETE;
faultdef CHUNK_SIZE_TOO_LARGE;


// 
// Helpers
// 

fn bool chunk_is_hex(char c) @inline @local
{
    if (c >= '0' && c <= '9') return true;
    if (c >= 'a' && c <= 'f') return true;
    if (c >= 'A' && c <= 'F') return true;
    return false;
}

fn sz chunk_hex_value(char c) @local
{
    if (c >= '0' && c <= '9') return (sz)(c - '0');
    if (c >= 'a' && c <= 'f') return (sz)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return (sz)(c - 'A' + 10);
    return 0;
}

fn sz chunk_find_crlf(char[] data, sz start) @local
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

fn sz chunk_find_lf(char[] data, sz start) @local
{
    if (start < 0) return -1;

    for (sz i = start; i < data.len; i++)
    {
        if (data[i] == '\n') return i;
    }

    return -1;
}

fn sz? chunk_parse_size_line(char[] line)
{
    if (line.len == 0) return INVALID_CHUNKED_BODY~;

    sz n = 0;
    bool saw_digit = false;

    for (sz i = 0; i < line.len; i++)
    {
        char c = line[i];

        // Ignore chunk extensions:
        //   4;ext=value
        if (c == ';') break;

        if (c == ' ' || c == '\t')
        {
            continue;
        }

        if (!chunk_is_hex(c))
        {
            return INVALID_CHUNKED_BODY~;
        }

        saw_digit = true;

        if (n > (MAX_BODY_BYTES / 16))
        {
            return CHUNK_SIZE_TOO_LARGE~;
        }

        n = n * 16 + chunk_hex_value(c);

        if (n > MAX_BODY_BYTES)
        {
            return CHUNK_SIZE_TOO_LARGE~;
        }
    }

    if (!saw_digit) return INVALID_CHUNKED_BODY~;

    return n;
}

fn sz? chunked_expected_len(char[] input)
{
    sz pos = 0;

    while (true)
    {
        sz line_end = chunk_find_crlf(input, pos);
        sz line_gap = 2;

        if (line_end < 0)
        {
            line_end = chunk_find_lf(input, pos);
            line_gap = 1;
        }

        if (line_end < 0)
        {
            return CHUNKED_BODY_INCOMPLETE~;
        }

        char[] size_line = input[pos:line_end - pos];

        if (size_line.len > 0 && size_line[size_line.len - 1] == '\r')
        {
            size_line = size_line[0:size_line.len - 1];
        }

        sz chunk_size = chunk_parse_size_line(size_line)!;

        pos = line_end + line_gap;

        if (chunk_size == 0)
        {
            while (true)
            {
                sz trailer_end = chunk_find_crlf(input, pos);
                sz trailer_gap = 2;

                if (trailer_end < 0)
                {
                    trailer_end = chunk_find_lf(input, pos);
                    trailer_gap = 1;
                }

                if (trailer_end < 0)
                {
                    return CHUNKED_BODY_INCOMPLETE~;
                }

                if (trailer_end == pos)
                {
                    return pos + trailer_gap;
                }

                pos = trailer_end + trailer_gap;
            }
        }

        if (chunk_size > MAX_BODY_BYTES)
        {
            return CHUNK_SIZE_TOO_LARGE~;
        }

        if (pos + chunk_size > input.len)
        {
            return CHUNKED_BODY_INCOMPLETE~;
        }

        pos += chunk_size;

        if (pos + 1 >= input.len)
        {
            return CHUNKED_BODY_INCOMPLETE~;
        }

        if (input[pos] == '\r' && input[pos + 1] == '\n')
        {
            pos += 2;
            continue;
        }

        if (input[pos] == '\n')
        {
            pos += 1;
            continue;
        }

        return INVALID_CHUNKED_BODY~;
    }
}

// 
// Public API
// 

struct ChunkedDecodeResult
{
    char[] body;
    sz consumed;
}

// Decodes a complete chunked body.
//
// Caller owns result.body and must free it with localmem.free().
// consumed is the number of bytes consumed from input, including the final
// zero-size chunk and trailer terminator.
fn ChunkedDecodeResult? chunked_decode(char[] input)
{
    DString out;
    out.init(localmem, 4096);
    defer catch out.free();

    sz pos = 0;

    while (true)
    {
        sz line_end = chunk_find_crlf(input, pos);
        sz line_gap = 2;

        if (line_end < 0)
        {
            line_end = chunk_find_lf(input, pos);
            line_gap = 1;
        }

        if (line_end < 0)
        {
            return CHUNKED_BODY_INCOMPLETE~;
        }

        char[] size_line = input[pos:line_end - pos];

        // Strip trailing '\r' when LF-only path saw "\r\n" malformed slice.
        if (size_line.len > 0 && size_line[size_line.len - 1] == '\r')
        {
            size_line = size_line[0:size_line.len - 1];
        }

        sz chunk_size = chunk_parse_size_line(size_line)!;

        pos = line_end + line_gap;

        if (chunk_size == 0)
        {
            // Consume trailers until blank line.
            while (true)
            {
                sz trailer_end = chunk_find_crlf(input, pos);
                sz trailer_gap = 2;

                if (trailer_end < 0)
                {
                    trailer_end = chunk_find_lf(input, pos);
                    trailer_gap = 1;
                }

                if (trailer_end < 0)
                {
                    return CHUNKED_BODY_INCOMPLETE~;
                }

                if (trailer_end == pos)
                {
                    pos += trailer_gap;
                
                    char[] body = {};
                
                    if (out.len() > 0)
                    {
                        body = out.copy_str(localmem);
                    }
                
                    return (ChunkedDecodeResult){
                        .body = body,
                        .consumed = pos,
                    };
                }
                
                pos = trailer_end + trailer_gap;
            }
        }

        if (chunk_size > MAX_BODY_BYTES)
        {
            return CHUNK_SIZE_TOO_LARGE~;
        }

        if (out.len() + chunk_size > MAX_BODY_BYTES)
        {
            return REQUEST_TOO_LARGE~;
        }

        if (pos + chunk_size > input.len)
        {
            return CHUNKED_BODY_INCOMPLETE~;
        }

        out.append(input[pos:chunk_size]);
        pos += chunk_size;

        if (pos + 1 >= input.len)
        {
            return CHUNKED_BODY_INCOMPLETE~;
        }

        if (input[pos] == '\r' && input[pos + 1] == '\n')
        {
            pos += 2;
            continue;
        }

        if (input[pos] == '\n')
        {
            pos += 1;
            continue;
        }

        return INVALID_CHUNKED_BODY~;
    }
}

fn bool transfer_encoding_has_chunked(String value) @local
{
    sz start = 0;

    while (start <= value.len)
    {
        sz comma = -1;

        for (sz i = start; i < value.len; i++)
        {
            if (value[i] == ',')
            {
                comma = i;
                break;
            }
        }

        String part;

        if (comma < 0)
        {
            part = trim_spaces(value[start:value.len - start]);
            return str_iequals(part, "chunked");
        }

        part = trim_spaces(value[start:comma - start]);

        if (str_iequals(part, "chunked")) return true;

        start = comma + 1;
    }

    return false;
}

fn bool Request.is_chunked(&self)
{
    String? te = self.header("Transfer-Encoding");
    if (catch err = te) return false;

    return transfer_encoding_has_chunked(te);
}

// eof