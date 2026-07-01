// test_header.c3

// Header and KeyVals tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::header;

import std::io;
import ext::aio::http;
import ext::debug;

fn bool contains(String haystack, String needle)
{
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    for (sz i = 0; i + needle.len <= haystack.len; i++)
    {
        if (haystack[i:needle.len] == needle) return true;
    }

    return false;
}

fn void test_ascii_eq_ignore_case()
{
    @assert(http::ascii_eq_ignore_case('A', 'a'), "A/a mismatch");
    @assert(http::ascii_eq_ignore_case('z', 'Z'), "z/Z mismatch");
    @assert(http::ascii_eq_ignore_case('M', 'm'), "M/m mismatch");
    @assert(!http::ascii_eq_ignore_case('A', 'b'), "A/b should not match");
}

fn void test_str_iequals()
{
    @assert(http::str_iequals("Content-Type", "content-type"), "case-insensitive compare failed");
    @assert(http::str_iequals("HOST", "host"), "HOST compare failed");
    @assert(!http::str_iequals("Host", "Host2"), "different strings should not match");
    @assert(!http::str_iequals("Host", "Hos"), "different lengths should not match");
}

fn void test_valid_header_name()
{
    @assert(http::is_valid_name("Host"), "Host should be valid");
    @assert(http::is_valid_name("Content-Type"), "Content-Type should be valid");
    @assert(http::is_valid_name("X_Custom"), "X_Custom should be valid");

    @assert(!http::is_valid_name(""), "empty name should be invalid");
    @assert(!http::is_valid_name("Bad Header"), "space should be invalid");
    @assert(!http::is_valid_name("Bad:Header"), "colon should be invalid");
    @assert(!http::is_valid_name("Bad/Header"), "slash should be invalid");
    @assert(!http::is_valid_name("Bad=Header"), "equals should be invalid");
}

fn void test_init_empty()
{
    http::Headers h;
    h.init();
    defer h.free();

    @assert(h.len() == 0, "new headers len mismatch");
    @assert(h.size() == 0, "new headers size mismatch");
    @assert(h.empty(), "new headers should be empty");
    @assert(!h.has("Host"), "new headers should not have Host");
}

fn void test_add_get_has()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("User-Agent", "test")!!;

    @assert(h.len() == 2, "headers len mismatch");
    @assert(!h.empty(), "headers should not be empty");
    @assert(h.has("host"), "case-insensitive has failed");
    @assert(h.has("USER-AGENT"), "case-insensitive has failed");

    String host = h.get("HOST")!!;
    String ua = h.get("user-agent")!!;

    @assert(host == "localhost", "Host value mismatch");
    @assert(ua == "test", "User-Agent value mismatch");
}

fn void test_get_not_found()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;

    if (catch err = h.get("Missing"))
    {
        @assert(err == http::NOT_FOUND, "missing header fault mismatch");
        return;
    }

    @assert(false, "missing header should fail");
}

fn void test_find()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("Content-Type", "text/plain")!!;

    sz idx = h.find("content-type")!!;
    @assert(idx == 1, "find index mismatch");

    if (catch err = h.find("Missing"))
    {
        @assert(err == http::NOT_FOUND, "find missing fault mismatch");
        return;
    }

    @assert(false, "find missing should fail");
}

fn void test_add_duplicate_headers()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Set-Cookie", "a=1")!!;
    h.add("Set-Cookie", "b=2")!!;

    @assert(h.len() == 2, "duplicate headers should be preserved");

    String first = h.get("set-cookie")!!;
    @assert(first == "a=1", "get should return first duplicate");
}

fn void test_set_overwrites_all_existing()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Set-Cookie", "a=1")!!;
    h.add("Set-Cookie", "b=2")!!;
    h.set("Set-Cookie", "c=3")!!;

    @assert(h.len() == 1, "set should remove existing duplicates");
    @assert(h.get("set-cookie")!! == "c=3", "set value mismatch");
}

fn void test_delete()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("Set-Cookie", "a=1")!!;
    h.add("Set-Cookie", "b=2")!!;

    bool removed = h.delete("set-cookie");

    @assert(removed, "delete should remove matching headers");
    @assert(h.len() == 1, "delete len mismatch");
    @assert(!h.has("Set-Cookie"), "deleted header still exists");
    @assert(h.has("Host"), "unrelated header removed");

    bool removed_again = h.delete("set-cookie");
    @assert(!removed_again, "delete missing should return false");
}

fn void test_clear()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("Content-Type", "text/plain")!!;

    h.clear();

    @assert(h.len() == 0, "clear len mismatch");
    @assert(h.empty(), "clear should make headers empty");

    h.add("X-Test", "ok")!!;
    @assert(h.len() == 1, "headers should be reusable after clear");
}

fn void test_invalid_add()
{
    http::Headers h;
    h.init();
    defer h.free();

    if (catch err = h.add("Bad Header", "x"))
    {
        @assert(err == http::INVALID_HEADER_NAME, "invalid add fault mismatch");
        return;
    }

    @assert(false, "invalid header add should fail");
}

fn void test_invalid_set()
{
    http::Headers h;
    h.init();
    defer h.free();

    if (catch err = h.set("Bad:Header", "x"))
    {
        @assert(err == http::INVALID_HEADER_NAME, "invalid set fault mismatch");
        return;
    }

    @assert(false, "invalid header set should fail");
}

fn void test_serialized_len()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("X-Test", "ok")!!;

    sz expected = "Host: localhost\r\n".len + "X-Test: ok\r\n".len;

    @assert(h.serialized_len() == expected, "serialized_len mismatch");
}

fn void test_write_to()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("X-Test", "ok")!!;

    char[128] out;
    sz n = h.write_to(out[..]);

    @assert(n == h.serialized_len(), "write_to length mismatch");

    String wire = (String)out[0:n];

    @assert(contains(wire, "Host: localhost\r\n"), "Host missing from write_to");
    @assert(contains(wire, "X-Test: ok\r\n"), "X-Test missing from write_to");
}

fn void test_write_to_small_buffer()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;

    char[4] out;
    sz n = h.write_to(out[..]);

    @assert(n == 0, "small write_to should return 0");
}

fn void test_serialize_empty()
{
    http::Headers h;
    h.init();
    defer h.free();

    String wire = h.serialize()!!;
    defer http::localmem.free(wire);

    @assert(wire.len == 0, "empty serialize should return empty string");
}

fn void test_serialize()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.add("Host", "localhost")!!;
    h.add("Set-Cookie", "a=1")!!;
    h.add("Set-Cookie", "b=2")!!;

    String wire = h.serialize()!!;
    defer http::localmem.free(wire);

    @assert(contains(wire, "Host: localhost\r\n"), "serialized Host missing");
    @assert(contains(wire, "Set-Cookie: a=1\r\n"), "serialized first cookie missing");
    @assert(contains(wire, "Set-Cookie: b=2\r\n"), "serialized second cookie missing");
}

fn void test_convenience_headers()
{
    http::Headers h;
    h.init();
    defer h.free();

    h.content_type("text/plain")!!;
    h.content_length(123)!!;
    h.server("ext::aio::http")!!;
    h.connection("close")!!;
    h.set_cookie("sid=abc")!!;

    @assert(h.get("Content-Type")!! == "text/plain", "content_type mismatch");
    @assert(h.get("Content-Length")!! == "123", "content_length mismatch");
    @assert(h.get("Server")!! == "ext::aio::http", "server mismatch");
    @assert(h.get("Connection")!! == "close", "connection mismatch");
    @assert(h.get("Set-Cookie")!! == "sid=abc", "set_cookie mismatch");
}

fn void test_header_aliases()
{
    http::Param p = {
        .name = "id".copy(http::localmem),
        .value = "42".copy(http::localmem),
    };
    defer p.free();

    @assert(p.name == "id", "Param alias name mismatch");
    @assert(p.value == "42", "Param alias value mismatch");
}

fn void main()
{
    test_ascii_eq_ignore_case();
    test_str_iequals();
    test_valid_header_name();

    test_init_empty();
    test_add_get_has();
    test_get_not_found();
    test_find();

    test_add_duplicate_headers();
    test_set_overwrites_all_existing();
    test_delete();
    test_clear();

    test_invalid_add();
    test_invalid_set();

    test_serialized_len();
    test_write_to();
    test_write_to_small_buffer();
    test_serialize_empty();
    test_serialize();

    test_convenience_headers();
    test_header_aliases();

    io::printfn("test_header: OK");
}

// eof