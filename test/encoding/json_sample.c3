// json_sample.c3


// 
// ext::encoding::json — sample examples
// 

import ext::encoding::json;
import std::io;
import std::collections::list;
import ext::debug;

// 
// Example 1 — basic decode + map access
// 
fn void example_basic()
{
    io::printfn("\n1. basic decode, map access\n");
    @pool() {
        String src = `{
            "name": "Alice",
            "age": 30,
            "verified": true,
            "score": 98.6,
            "nickname": null
        }`;

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[basic] parse error: %s", err);
            return;
        }

        JsonObject m = obj.as_object()!!;

        String name     = m.get_string("name")!!;       // "Alice"

        long   age      = m.get_int("age")!!;            // 30

        bool   verified = m.get_bool("verified")!!;      // true

        double score    = m.get_float("score")!!;        // 98.6

        io::printfn("[basic] name=%s  age=%d  verified=%s  score=%.1f",
            name, age, verified ? "true" : "false", score);

        // Checking null
        JsonValue nick = m.get("nickname")!!;
        if (nick.is_null()) {
            io::printfn("[basic] nickname is null");
        }
    };
}

// 
// Example 2 — array access
// 
fn void example_array()
{
    io::printfn("\n2. array access\n");
    @pool() {
        String src = `{
            "tags": ["c3", "json", "parser"],
            "scores": [10, 20, 30]
        }`;

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[array] parse error: %s", err);
            return;
        }

        JsonObject   m    = obj.as_object()!!;

        JsonArray tags = m.get_array("tags")!!;

        // Index-based access
        String first  = tags.get_string(0)!!;   // "c3"
        String second = tags.get_string(1)!!;   // "json"
        String third  = tags.get_string(2)!!;   // "parser"
        io::printfn("[array] tags: %s, %s, %s", first, second, third);

        // Iterate with len / at()
        JsonArray scores = m.get_array("scores")!!;
        long total = 0;
        for (sz i = 0; i < scores.len(); i++) {
            total += scores.get_int(i)!!;
        }
        io::printfn("[array] scores total: %d", total);  // 60
    };
}

// 
// Example 3 — nested objects
// 
fn void example_nested()
{
    io::printfn("\n3. nested object\n");
    @pool() {
        String src = `{
            "user": {
                "id": 42,
                "profile": {
                    "city": "Seoul",
                    "active": true
                }
            }
        }`;

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[nested] parse error: %s", err);
            return;
        }

        JsonObject root    = obj.as_object()!!;
        JsonObject user    = root.get_object("user")!!;
        JsonObject profile = user.get_object("profile")!!;

        long   id     = user.get_int("id")!!;         // 42
        String city   = profile.get_string("city")!!; // "Seoul"
        bool   active = profile.get_bool("active")!!; // true

        io::printfn("[nested] id=%d  city=%s  active=%s",
            id, city, active ? "true" : "false");
    };
}

// 
// Example 4 — array of objects
// 
fn void example_array_of_objects()
{
    io::printfn("\n4. arrah of objects\n");
    @pool() {
        String src = `{
            "items": [
                {"id": 1, "name": "apple",  "price": 1.5},
                {"id": 2, "name": "banana", "price": 0.75},
                {"id": 3, "name": "cherry", "price": 3.0}
            ]
        }`;

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[arr_obj] parse error: %s", err);
            return;
        }

        JsonObject   root  = obj.as_object()!!;
        JsonArray items = root.get_array("items")!!;

        for (sz i = 0; i < items.len(); i++) {
            JsonObject item  = items.get_object(i)!!;
            long   id     = item.get_int("id")!!;
            String name   = item.get_string("name")!!;
            double price  = item.get_float("price")!!;
            io::printfn("[arr_obj] #%d  %-8s  $%.2f", id, name, price);
        }
    };
}

// 
// Example 5 — type inspection with is_* guards
// 
fn void print_value(JsonValue v)
{
    if (v.is_null())   { io::print("null");                     return; }
    if (v.is_bool())   { io::print(v.as_bool()!! ? "true" : "false"); return; }
    if (v.is_int())    { io::printf("%d", v.as_int()!!);        return; }
    if (v.is_float())  { io::printf("%f", v.as_float()!!);      return; }
    if (v.is_string()) { io::printf("%s", v.as_string()!!);     return; }
    if (v.is_array())  { io::print("[array]");                   return; }
    if (v.is_object())    { io::print("{object}");                  return; }
}

fn void example_type_inspection()
{
    io::printfn("\n5. type inspection\n");
    @pool() {
        String src = `{
            "a": null,
            "b": true,
            "c": 42,
            "d": 3.14,
            "e": "hello",
            "f": [1, 2],
            "g": {"x": 0}
        }`;

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[types] parse error: %s", err);
            return;
        }

        JsonObject m = obj.as_object()!!;
        String[] keys = {"a", "b", "c", "d", "e", "f", "g"};
        foreach (String key : keys) {
            io::printf("[types] %s = ", key);
            print_value(m.get(key)!!);
            io::printfn("");
        }
    };
}

// 
// Example 6 — trailing commas and comments (lenient mode)
// 
fn void example_lenient()
{
    io::printfn("\n6. trailing comma, comment\n");
    @pool() {
        String src = `{
            // This is a comment
            "x": 1,
            "y": 2,  /* inline comment */
            "z": [3, 4,],  // trailing comma in array
        }`;

        // allow_comma=true, allow_comment=true (both are defaults)
        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[lenient] parse error: %s", err);
            return;
        }

        JsonObject m = obj.as_object()!!;
        io::printfn("[lenient] x=%d  y=%d", m.get_int("x")!!, m.get_int("y")!!);

        JsonArray z = m.get_array("z")!!;
        io::printfn("[lenient] z[0]=%d  z[1]=%d", z.get_int(0)!!, z.get_int(1)!!);
    };
}

// 
// Example 7 — strict mode (no trailing commas, no comments)
// 
fn void example_strict()
{
    io::printfn("\n7. strict mode\n");
    @pool() {
        String valid_src   = `{"key": "value"}`;
        String invalid_src = `{"key": "value",}`;  // trailing comma — not allowed

        JsonValue? obj1 = json::decode(tmem, valid_src,   false, false);
        JsonValue? obj2 = json::decode(tmem, invalid_src, false, false);
        
        bool ok1 = true;
        if (catch err = obj1) ok1 = false;

        bool fail2 = false;
        if (catch err = obj2) fail2 = true;

        io::printfn("[strict] valid parse:   %s", (ok1)  ? "OK" : "FAIL");
        io::printfn("[strict] invalid parse: %s", (fail2)  ? "FAIL (expected) OK." : "FAIL.");
    };
}

// 
// Example 8 — encode back to JSON string
// 
fn void example_encode()
{
    io::printfn("\n8. encode to json str\n");
    @pool() {
        String src = `{"name": "Bob", "scores": [5, 10, 15]}`;

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[encode] parse error: %s", err);
            return;
        }

        String out = obj.encode();
        io::printfn("[encode] %s", out);
        json::free_str(out);  // encode() uses its own allocator — must free separately
    };
}

// 
// Example 9 — optional key handling with has()
// 
fn void example_optional_keys()
{
    io::printfn("\n9. optional key handling\n");
    @pool() {
        String src = `{"username": "charlie"}`;  // "email" key absent

        JsonValue? obj = json::decode(tmem, src);
        if (catch err = obj) {
            io::printfn("[optional] parse error: %s", err);
            return;
        }

        JsonObject m = obj.as_object()!!;

        String username = m.get_string("username")!!;
        io::printfn("[optional] username: %s", username);

        if (m.has("email")) {
            io::printfn("[optional] email: %s", m.get_string("email")!!);
        } else {
            io::printfn("[optional] email: (not provided) OK.");
        }
    };
}

// 
// Example 10 — error handling without !-propagation
// 
fn void example_error_handling()
{
    io::printfn("\n10. error handling\n");
    @pool() {
        String bad_json = `{"broken": }`;

        JsonValue? obj = json::decode(tmem, bad_json);
        if (catch err = obj) {
            io::printfn("[errors] caught parse fault: %s", err);
            return;
        }

        JsonObject m = obj.as_object()!!;

        // Accessing a key that doesn't exist
        long? n = m.get_int("missing");
        if (catch err = n) {
            io::printfn("[errors] caught key fault: %s", err);
        }

        // Type mismatch
        JsonValue? name_obj = m.get("name");
        if (catch err = name_obj) {
            io::printfn("[errors] caught get fault: %s", err);
            return;
        }
        long? wrong_type = name_obj.as_int();
        if (catch err = wrong_type) {
            io::printfn("[errors] caught type fault: %s", err);
        }
    };
}

// 
// main
// 
fn void main()
{
    example_basic();
    example_array();
    example_nested();
    example_array_of_objects();
    example_type_inspection();
    example_lenient();
    example_strict();
    example_encode();
    example_optional_keys();
    example_error_handling();
}
