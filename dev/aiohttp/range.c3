// range.c3

// HTTP byte range parsing for ext::aio::http
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::mem;


// Faults

faultdef INVALID_RANGE;
faultdef RANGE_NOT_SATISFIABLE;
faultdef MULTIPLE_RANGES_NOT_SUPPORTED;


// Byte range

struct ByteRange
{
    sz start;
    sz length;
}


// Parsing helpers

fn sz? range_parse_number(String value) @local
{
    value = value.trim();

    if (value.len == 0) return INVALID_RANGE~;

    for (sz i = 0; i < value.len; i++) {
        if (value[i] < '0' || value[i] > '9') return INVALID_RANGE~;
    }

    sz? number = value.to_long();

    if (catch err = number) return INVALID_RANGE~;
    if (number < 0) return INVALID_RANGE~;

    return number;
}

fn ByteRange? range_from_start_end(String start_text, String end_text, sz file_size) @local
{
    sz start = range_parse_number(start_text)!;
    sz end = range_parse_number(end_text)!;

    if (file_size <= 0) return RANGE_NOT_SATISFIABLE~;
    if (start >= file_size) return RANGE_NOT_SATISFIABLE~;
    if (end < start) return RANGE_NOT_SATISFIABLE~;

    if (end >= file_size) end = file_size - 1;

    return {
        .start = start,
        .length = end - start + 1,
    };
}

fn ByteRange? range_from_start(String start_text, sz file_size) @local
{
    sz start = range_parse_number(start_text)!;

    if (file_size <= 0) return RANGE_NOT_SATISFIABLE~;
    if (start >= file_size) return RANGE_NOT_SATISFIABLE~;

    return {
        .start = start,
        .length = file_size - start,
    };
}

fn ByteRange? range_from_suffix(String suffix_text, sz file_size) @local
{
    sz suffix_length = range_parse_number(suffix_text)!;

    if (file_size <= 0) return RANGE_NOT_SATISFIABLE~;
    if (suffix_length <= 0) return RANGE_NOT_SATISFIABLE~;

    if (suffix_length > file_size) suffix_length = file_size;

    return {
        .start = file_size - suffix_length,
        .length = suffix_length,
    };
}


// Range parser

fn ByteRange? parse_byte_range(String value, sz file_size)
{
    value = value.trim();

    if (value.len == 0) return INVALID_RANGE~;
    if (file_size < 0) return RANGE_NOT_SATISFIABLE~;

    sz equals = value.index_of("=") ?? -1;

    if (equals <= 0) return INVALID_RANGE~;

    String unit = value[0:equals].trim();
    String range_value = value[equals + 1..].trim();

    if (!str_iequals(unit, "bytes")) return INVALID_RANGE~;
    if (range_value.len == 0) return INVALID_RANGE~;
    if (range_value.contains(",")) return MULTIPLE_RANGES_NOT_SUPPORTED~;

    sz hyphen = range_value.index_of("-") ?? -1;

    if (hyphen < 0) return INVALID_RANGE~;

    String start_text = range_value[0:hyphen].trim();
    String end_text = range_value[hyphen + 1..].trim();

    if (end_text.contains("-")) return INVALID_RANGE~;
    if (start_text.len == 0 && end_text.len == 0) return INVALID_RANGE~;

    if (start_text.len == 0) return range_from_suffix(end_text, file_size)!;
    if (end_text.len == 0) return range_from_start(start_text, file_size)!;

    return range_from_start_end(start_text, end_text, file_size)!;
}


// Header formatting

fn String? byte_range_content_range(ByteRange range, sz file_size)
{
    if (range.start < 0 || range.length <= 0 || file_size < 0) return INVALID_RANGE~;

    sz end = range.start + range.length - 1;

    if (range.start >= file_size || end >= file_size) return RANGE_NOT_SATISFIABLE~;

    return string::format(localmem, "bytes %d-%d/%d", range.start, end, file_size);
}

fn String? byte_range_unsatisfied_content_range(sz file_size)
{
    if (file_size < 0) return INVALID_RANGE~;

    return string::format(localmem, "bytes */%d", file_size);
}

// eof