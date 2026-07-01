// simdjson_sample.c3

module simdjson_sample;

import std::io;
import ext::encoding::simdjson;


// =======================================
// Tests
// =======================================

fn void test_stage1() => @pool()
{
    io::printfn("\n1. stage 1 only\n");
    char[] input = `{ "key": [1, "b\"c", null] }`;
    sz[] indices = simdjson::scan(tmem, input, {});
    defer tmem.free(indices);
    io::printfn("stage1 indices (%d):", indices.len);
    foreach (idx: indices) {
        io::printfn("  %d  '%c'", idx, input[idx]);
    }
    // Expected 11: { " : [ 1 , " , n ] }
}

fn void test_strict() => @pool()
{
    io::printfn("\n2. test strict\n");
    String src = `{ "name": "Alice", "age": 30, "scores": [10, 20, 30], "active": true }`;
    ParseResult? r = simdjson::parse(tmem, (char[])src, false, false);
    if (catch err = r) { io::printfn("strict parse error: %s", err); return; }
    defer r.free();
    simdjson::dump_tape(&r);
    
    JsonValue root = r.root();
    io::printfn("is_object: %s",  root.is_object());
    io::printfn("name = %s", (root.get("name")!!).as_str());
    io::printfn("age_raw = %s", (root.get("age")!!).raw_num());
    io::printfn("age = %d", (root.get("age")!!).as_long()!!);
    io::printfn("active = %s", (root.get("active")!!).as_bool());

    JsonValue scores = root.get("scores")!!;
    io::printfn("scores.len = %d", scores.len());
    for (sz i = 0; i < scores.len(); i++) {
        io::printfn("  scores[%d] = %s", i, (scores.at(i)!!).raw_num());
    }
}

fn void test_relaxed() => @pool()
{
    io::printfn("\n3. test relaxed with comments and trailing commas\n");

    String src = `{
        // user record
        "name": "Bob",
        "tags": ["admin", "user",],
        "meta": { "version": 2, }
    }`;
    ParseResult? r = simdjson::parse(tmem, (char[])src, true, true);
    if (catch err = r) { io::printfn("relaxed parse error: %s", err); return; }
    defer r.free();
    simdjson::dump_tape(&r);
    
    JsonValue root = r.root();
    io::printfn("relaxed name = %s", (root.get("name")!!).as_str());
    io::printfn("relaxed tags.len = %d", (root.get("tags")!!).len());
    io::printfn("relaxed version = %s", ((root.get("meta")!!).get("version")!!).raw_num());
}

fn void main()
{
    test_stage1();
    test_strict();
    test_relaxed();
}
