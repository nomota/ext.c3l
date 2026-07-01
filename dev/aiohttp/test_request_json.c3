// test_request_json.c3

// Request and Context JSON body parsing tests using ext::serializer::simdjson.
//
// Nomota <hiongun@gmail.com>; MIT License

module test::request_json;

import std::io;
import ext::debug;
import ext::aio::http;
import ext::serializer::simdjson;


fn void test_request_json_object()
{
    char[] raw =
        "POST /users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 39\r\n"
        "\r\n"
        "{\"name\":\"Alice\",\"age\":30,\"active\":true}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    @assert(req.has_body());
    @assert(req.body_text() == "{\"name\":\"Alice\",\"age\":30,\"active\":true}");

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    @assert(root.is_object());
    @assert(root.len() == 3);

    simdjson::JsonValue name = root.get("name")!!;
    simdjson::JsonValue age = root.get("age")!!;
    simdjson::JsonValue active = root.get("active")!!;

    @assert(name.is_string());
    @assert(name.as_str() == "Alice");

    @assert(age.is_number());
    @assert(age.raw_num() == "30");
    @assert(age.as_long()!! == 30);

    @assert(active.is_true());
    @assert(active.as_bool());
}

fn void test_context_json_object()
{
    char[] raw =
        "POST /users HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 37\r\n"
        "\r\n"
        "{\"id\":123,\"name\":\"Bob\",\"admin\":false}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    Context* c = http::context_new(req)!!;
    defer http::context_free(c);

    @assert(c.has_body());
    @assert(c.body_text() == "{\"id\":123,\"name\":\"Bob\",\"admin\":false}");

    simdjson::ParseResult result = c.req_json()!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    @assert(root.is_object());

    simdjson::JsonValue id = root.get("id")!!;
    simdjson::JsonValue name = root.get("name")!!;
    simdjson::JsonValue admin = root.get("admin")!!;

    @assert(id.as_long()!! == 123);
    @assert(name.as_str() == "Bob");
    @assert(admin.is_false());
    @assert(!admin.as_bool());
}

fn void test_json_array()
{
    char[] raw =
        "POST /values HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 24\r\n"
        "\r\n"
        "[10,20,30,true,null,\"x\"]";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    @assert(root.is_array());
    @assert(root.len() == 6);

    @assert(root.at(0)!!.as_long()!! == 10);
    @assert(root.at(1)!!.as_long()!! == 20);
    @assert(root.at(2)!!.as_long()!! == 30);
    @assert(root.at(3)!!.is_true());
    @assert(root.at(4)!!.is_null());
    @assert(root.at(5)!!.as_str() == "x");
}

fn void test_nested_json()
{
    char[] raw =
        "POST /nested HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 60\r\n"
        "\r\n"
        "{\"user\":{\"name\":\"Kim\"},\"scores\":[100,95],\"meta\":{\"ok\":true}}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();
    simdjson::JsonValue user = root.get("user")!!;
    simdjson::JsonValue scores = root.get("scores")!!;
    simdjson::JsonValue meta = root.get("meta")!!;

    @assert(user.is_object());
    @assert(user.get("name")!!.as_str() == "Kim");

    @assert(scores.is_array());
    @assert(scores.len() == 2);
    @assert(scores.at(0)!!.as_long()!! == 100);
    @assert(scores.at(1)!!.as_long()!! == 95);

    @assert(meta.is_object());
    @assert(meta.get("ok")!!.is_true());
}

fn void test_json_number_formats()
{
    char[] raw =
        "POST /numbers HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 29\r\n"
        "\r\n"
        "[-1,0,123,-3.14,6.02e23,1E-4]";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    @assert(root.len() == 6);

    @assert(root.at(0)!!.as_long()!! == -1);
    @assert(root.at(1)!!.as_long()!! == 0);
    @assert(root.at(2)!!.as_long()!! == 123);

    @assert(root.at(3)!!.raw_num() == "-3.14");
    @assert(root.at(4)!!.raw_num() == "6.02e23");
    @assert(root.at(5)!!.raw_num() == "1E-4");

    double d = root.at(3)!!.as_double()!!;
    @assert(d < -3.13 && d > -3.15);
}

fn void test_json_zero_copy()
{
    char[] raw =
        "POST /zero-copy HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 17\r\n"
        "\r\n"
        "{\"value\":\"hello\"}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue value = result.root().get("value")!!;
    String text = value.as_str();

    @assert(text == "hello");

    bool inside_body = text.ptr >= req.body.ptr && text.ptr < req.body.ptr + req.body.len;
    @assert(inside_body);
}

fn void test_json_trailing_comma_default()
{
    char[] raw =
        "POST /comma HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 14\r\n"
        "\r\n"
        "{\"a\":1,\"b\":2,}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    @assert(root.is_object());
    @assert(root.len() == 2);
    @assert(root.get("a")!!.as_long()!! == 1);
    @assert(root.get("b")!!.as_long()!! == 2);
}

fn void test_json_trailing_comma_strict()
{
    char[] raw =
        "POST /comma HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 14\r\n"
        "\r\n"
        "{\"a\":1,\"b\":2,}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    if (catch err = req.parse_json(tmem, false, false)) {
        @assert(err == simdjson::PARSE_FAILED);
        return;
    }

    @assert(false);
}

fn void test_json_comment_default()
{
    char[] raw =
        "POST /comment HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 24\r\n"
        "\r\n"
        "{\n// comment\n\"value\":7\n}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    @assert(result.root().get("value")!!.as_long()!! == 7);
}

fn void test_json_comment_strict()
{
    char[] raw =
        "POST /comment HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 24\r\n"
        "\r\n"
        "{\n// comment\n\"value\":7\n}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    if (catch err = req.parse_json(tmem, true, false)) {
        @assert(err == simdjson::PARSE_FAILED);
        return;
    }

    @assert(false);
}

fn void test_invalid_json()
{
    char[] raw =
        "POST /invalid HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 11\r\n"
        "\r\n"
        "{\"a\":1,\"b\"}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    if (catch err = req.parse_json(tmem)) {
        @assert(err == simdjson::PARSE_FAILED);
        return;
    }

    @assert(false);
}

fn void test_empty_json_body()
{
    char[] raw =
        "POST /empty HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 0\r\n"
        "\r\n";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    @assert(!req.has_body());
    @assert(req.body_text() == "");

    if (catch err = req.parse_json(tmem)) {
        @assert(err == simdjson::EMPTY_INPUT);
        return;
    }

    @assert(false);
}

fn void test_json_missing_key()
{
    char[] raw =
        "POST /missing HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 7\r\n"
        "\r\n"
        "{\"a\":1}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    if (catch err = root.get("missing")) {
        @assert(err == simdjson::KEY_NOT_FOUND);
        return;
    }

    @assert(false);
}

fn void test_json_array_out_of_range()
{
    char[] raw =
        "POST /range HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 7\r\n"
        "\r\n"
        "[1,2,3]";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue root = result.root();

    if (catch err = root.at(3)) {
        @assert(err == simdjson::INDEX_OUT_OF_RANGE);
        return;
    }

    @assert(false);
}

fn void test_json_type_mismatch()
{
    char[] raw =
        "POST /type HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 14\r\n"
        "\r\n"
        "{\"name\":\"Kim\"}";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    simdjson::JsonValue name = result.root().get("name")!!;

    if (catch err = name.as_long()) {
        @assert(err == simdjson::TYPE_MISMATCH);
        return;
    }

    @assert(false);
}

fn void test_json_chunked_body()
{
    char[] raw =
        "POST /chunked HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Type: application/json\r\n"
        "Transfer-Encoding: chunked\r\n"
        "\r\n"
        "8\r\n"
        "{\"name\":\r\n"
        "7\r\n"
        "\"Alice\"\r\n"
        "1\r\n"
        "}\r\n"
        "0\r\n"
        "\r\n";

    Request* req = http::request_parse(raw)!!;
    defer http::request_free(req);

    @assert(req.body_text() == "{\"name\":\"Alice\"}");

    simdjson::ParseResult result = req.parse_json(tmem)!!;
    defer result.free();

    @assert(result.root().get("name")!!.as_str() == "Alice");
}

fn void test_context_not_ready()
{
    Context c;
    c.req = null;
    c.res = null;

    if (catch err = c.req_json()) {
        @assert(err == http::CONTEXT_NOT_READY);
        return;
    }

    @assert(false);
}

fn void main()
{
    test_request_json_object();
    test_context_json_object();
    test_json_array();
    test_nested_json();
    test_json_number_formats();
    test_json_zero_copy();

    test_json_trailing_comma_default();
    test_json_trailing_comma_strict();
    test_json_comment_default();
    test_json_comment_strict();

    test_invalid_json();
    test_empty_json_body();
    test_json_missing_key();
    test_json_array_out_of_range();
    test_json_type_mismatch();

    test_json_chunked_body();
    test_context_not_ready();

    io::printfn("test_request_json: OK");
}