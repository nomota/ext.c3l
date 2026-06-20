// test_params.c3

// Params tests for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module test::params;

import std::io;
import ext::aio::http;
import ext::debug;
import c::errno;

fn void test_param_name_valid()
{
    @assert(aio::http::param_name_valid("id"), "id should be valid");
    @assert(aio::http::param_name_valid("user_id"), "user_id should be valid");
    @assert(aio::http::param_name_valid("file-name"), "file-name should be valid");
    @assert(aio::http::param_name_valid("_id"), "_id should be valid");

    @assert(!aio::http::param_name_valid(""), "empty name should be invalid");
    @assert(!aio::http::param_name_valid("1id"), "digit first should be invalid");
    @assert(!aio::http::param_name_valid("user.id"), "dot should be invalid");
    @assert(!aio::http::param_name_valid("user/id"), "slash should be invalid");
    @assert(!aio::http::param_name_valid("user:id"), "colon should be invalid");
}

fn void test_params_put_get()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.put("id", "42")!!;

    String id = params.get_param("id")!!;
    @assert(id == "42", "param value mismatch");

    @assert(params.has_param("id"), "param should exist");
    @assert(!params.has_param("missing"), "missing param should not exist");
}

fn void test_params_put_overwrites()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.put("id", "1")!!;
    params.put("id", "2")!!;

    @assert(params.len() == 1, "put should overwrite existing param");

    String id = params.get_param("id")!!;
    @assert(id == "2", "overwritten param mismatch");
}

fn void test_params_add_param_allows_duplicate()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.add_param("tag", "a")!!;
    params.add_param("tag", "b")!!;

    @assert(params.len() == 2, "add_param should preserve duplicates");

    String first = params.get_param("tag")!!;
    @assert(first == "a", "first duplicate param mismatch");
}

fn void test_params_delete()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.put("id", "42")!!;

    bool removed = params.delete_param("id");

    @assert(removed, "delete should remove existing param");
    @assert(!params.has_param("id"), "deleted param should not exist");

    bool removed_again = params.delete_param("id");
    @assert(!removed_again, "delete missing param should return false");
}

fn void test_params_invalid_put()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    if (catch err = params.put("1id", "42"))
    {
        @assert(err == aio::http::INVALID_PARAM_NAME, "invalid put fault mismatch");
        return;
    }

    @assert(false, "invalid param put should fail");
}

fn void test_params_invalid_add_param()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    if (catch err = params.add_param("user.id", "42"))
    {
        @assert(err == aio::http::INVALID_PARAM_NAME, "invalid add_param fault mismatch");
        return;
    }

    @assert(false, "invalid add_param should fail");
}

fn void test_params_copy_from()
{
    aio::http::Params src;
    src.init();
    defer src.free();

    src.put("user_id", "kim")!!;
    src.put("post_id", "42")!!;

    aio::http::Params dst;
    dst.init();
    defer dst.free();

    dst.copy_from(&src)!!;

    @assert(dst.len() == 2, "copy_from len mismatch");
    @assert(dst.get_param("user_id")!! == "kim", "copy_from user_id mismatch");
    @assert(dst.get_param("post_id")!! == "42", "copy_from post_id mismatch");
}

fn void test_params_copy_from_null()
{
    aio::http::Params dst;
    dst.init();
    defer dst.free();

    if (catch err = dst.copy_from(null))
    {
        @assert(err == errno::E_INVALID_ARG, "copy_from null fault mismatch");
        return;
    }

    @assert(false, "copy_from null should fail");
}

fn void test_params_clone()
{
    aio::http::Params src;
    src.init();
    defer src.free();

    src.put("id", "42")!!;
    src.put("name", "kim")!!;

    aio::http::Params cloned = aio::http::params_clone(&src)!!;
    defer cloned.free();

    @assert(cloned.len() == 2, "params_clone len mismatch");
    @assert(cloned.get_param("id")!! == "42", "params_clone id mismatch");
    @assert(cloned.get_param("name")!! == "kim", "params_clone name mismatch");
}

fn void test_params_clone_null()
{
    if (catch err = aio::http::params_clone(null))
    {
        @assert(err == errno::E_INVALID_ARG, "params_clone null fault mismatch");
        return;
    }

    @assert(false, "params_clone null should fail");
}

fn void test_splat()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.set_splat("css/app.css")!!;

    String splat = params.splat()!!;
    @assert(splat == "css/app.css", "splat mismatch");
    @assert(params.splat()!! == "css/app.css", "raw splat key mismatch");
}

fn void test_splat_overwrites()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.set_splat("a")!!;
    params.set_splat("b")!!;

    @assert(params.len() == 1, "splat should overwrite previous value");
    @assert(params.splat()!! == "b", "splat overwrite mismatch");
}

fn void test_put_decoded()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.put_decoded("name", "kim%20lee")!!;

    String name = params.get_param("name")!!;
    @assert(name == "kim lee", "decoded param mismatch");
}

fn void test_put_decoded_invalid_encoding()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    if (catch err = params.put_decoded("name", "kim%ZZ"))
    {
        @assert(err == aio::http::INVALID_URL_ENCODING, "put_decoded invalid encoding fault mismatch");
        return;
    }

    @assert(false, "put_decoded invalid encoding should fail");
}

fn void test_put_decoded_invalid_name()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    if (catch err = params.put_decoded("1name", "kim"))
    {
        @assert(err == aio::http::INVALID_PARAM_NAME, "put_decoded invalid name fault mismatch");
        return;
    }

    @assert(false, "put_decoded invalid name should fail");
}

fn void test_set_splat_decoded()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    params.set_splat_decoded("docs/my%20file.pdf")!!;

    String splat = params.splat()!!;
    @assert(splat == "docs/my file.pdf", "decoded splat mismatch");
}

fn void test_set_splat_decoded_invalid_encoding()
{
    aio::http::Params params;
    params.init();
    defer params.free();

    if (catch err = params.set_splat_decoded("docs/%ZZ"))
    {
        @assert(err == aio::http::INVALID_URL_ENCODING, "set_splat_decoded invalid encoding fault mismatch");
        return;
    }

    @assert(false, "set_splat_decoded invalid encoding should fail");
}

fn void test_params_lifecycle_helpers()
{
    aio::http::Params params = aio::http::params_new()!!;
    defer aio::http::params_free(&params);

    params.put("id", "42")!!;

    @assert(params.len() == 1, "params_new len mismatch");

    aio::http::params_clear(&params);

    @assert(params.len() == 0, "params_clear mismatch");

    aio::http::params_init(null);
    aio::http::params_clear(null);
    aio::http::params_free(null);
}

fn void main()
{
    test_param_name_valid();

    test_params_put_get();
    test_params_put_overwrites();
    test_params_add_param_allows_duplicate();
    test_params_delete();

    test_params_invalid_put();
    test_params_invalid_add_param();

    test_params_copy_from();
    test_params_copy_from_null();
    test_params_clone();
    test_params_clone_null();

    test_splat();
    test_splat_overwrites();

    test_put_decoded();
    test_put_decoded_invalid_encoding();
    test_put_decoded_invalid_name();

    test_set_splat_decoded();
    test_set_splat_decoded_invalid_encoding();

    test_params_lifecycle_helpers();

    io::printfn("test_params: OK");
}

// eof