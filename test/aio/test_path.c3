// test_path.c3

import ext::aio;
import ext::aio::io;
import ext::aio::path;
import ext::debug;
import std::collections::list;


fn void? write_file(String name, String data)
{
    Fd fd = io::file_open(name, "w")!;
    defer io::file_close(fd);

    sz n = io::file_write(fd, data[..])!;
    @assert(n == data.len);
    io::file_flush(fd)!;
}

fn String? read_file(String name, char[] buf)
{
    Fd fd = io::file_open(name, "r")!;
    defer io::file_close(fd);

    sz n = io::file_read(fd, buf)!;
    return (String)buf[0:n];
}

fn void? test_exists_and_types()
{
    warn("[path] exists/isfile/isdir/islink");

    path::makedirs("tmp_aio_path_test", 0o777, true)!;
    write_file("tmp_aio_path_test/file.txt", "hello path")!;

    @assert(path::exists("tmp_aio_path_test"));
    @assert(path::isdir("tmp_aio_path_test"));
    @assert(!path::isfile("tmp_aio_path_test"));

    @assert(path::exists("tmp_aio_path_test/file.txt"));
    @assert(path::isfile("tmp_aio_path_test/file.txt"));
    @assert(!path::isdir("tmp_aio_path_test/file.txt"));

    @assert(!path::exists("tmp_aio_path_test/no_such_file.txt"));
}

fn void? test_stat_and_getsize()
{
    warn("[path] stat/getsize");

    write_file("tmp_aio_path_test/stat.txt", "abcdef")!;

    path::Stat st = path::stat("tmp_aio_path_test/stat.txt")!;
    @assert(st.st_size == 6);
    @assert(st.st_mtime > 0);

    sz size = path::getsize("tmp_aio_path_test/stat.txt")!;
    @assert(size == 6);
}

fn void? test_rename_replace_remove()
{
    warn("[path] rename/replace/remove");

    write_file("tmp_aio_path_test/rename_src.txt", "rename-data")!;

    path::rename(
        "tmp_aio_path_test/rename_src.txt",
        "tmp_aio_path_test/rename_dst.txt"
    )!;

    @assert(!path::exists("tmp_aio_path_test/rename_src.txt"));
    @assert(path::exists("tmp_aio_path_test/rename_dst.txt"));

    write_file("tmp_aio_path_test/replace_src.txt", "new-data")!;
    write_file("tmp_aio_path_test/replace_dst.txt", "old-data")!;

    path::replace(
        "tmp_aio_path_test/replace_src.txt",
        "tmp_aio_path_test/replace_dst.txt"
    )!;

    @assert(!path::exists("tmp_aio_path_test/replace_src.txt"));
    @assert(path::exists("tmp_aio_path_test/replace_dst.txt"));

    char[128] buf;
    String s = read_file("tmp_aio_path_test/replace_dst.txt", buf[..])!;
    @assert(s == "new-data");

    path::remove("tmp_aio_path_test/rename_dst.txt")!;
    @assert(!path::exists("tmp_aio_path_test/rename_dst.txt"));
}

fn void? test_mkdir_makedirs_removedirs()
{
    warn("[path] mkdir/makedirs/removedirs");

    path::mkdir("tmp_aio_path_test/one", 0o777)!;
    @assert(path::isdir("tmp_aio_path_test/one"));

    path::makedirs("tmp_aio_path_test/a/b/c", 0o777, true)!;
    @assert(path::isdir("tmp_aio_path_test/a"));
    @assert(path::isdir("tmp_aio_path_test/a/b"));
    @assert(path::isdir("tmp_aio_path_test/a/b/c"));

    path::removedirs("tmp_aio_path_test/a/b/c")!;

    @assert(!path::exists("tmp_aio_path_test/a/b/c"));
    @assert(!path::exists("tmp_aio_path_test/a/b"));
    @assert(!path::exists("tmp_aio_path_test/a"));
}

fn void? test_listdir()
{
    warn("[path] listdir");

    path::makedirs("tmp_aio_path_test/list", 0o777, true)!;
    write_file("tmp_aio_path_test/list/a.txt", "a")!;
    write_file("tmp_aio_path_test/list/b.txt", "b")!;

    List{String} files = path::listdir(mem, "tmp_aio_path_test/list")!;
    defer files.free();

    @assert(files.len() >= 2);

    bool found_a = false;
    bool found_b = false;

    foreach (String f : files)
    {
        if (f == "a.txt") found_a = true;
        if (f == "b.txt") found_b = true;
    }

    @assert(found_a);
    @assert(found_b);
}

fn void? test_scandir()
{
    warn("[path] scandir");

    path::makedirs("tmp_aio_path_test/scan", 0o777, true)!;
    write_file("tmp_aio_path_test/scan/file1.txt", "file1")!;

    path::DirIterator it = path::scandir(mem, "tmp_aio_path_test/scan")!;
    defer it.close();

    bool found = false;

    while (true)
    {
        path::DirEntry? ent = it.next();
        if (catch err = ent) break;

        defer ent.free();

        if (ent.name == "file1.txt")
        {
            found = true;
            @assert(ent.is_file());
        }
    }

    @assert(found);
}

fn void? test_link_symlink_readlink()
{
    warn("[path] link/symlink/readlink");

    write_file("tmp_aio_path_test/link_src.txt", "link-data")!;

    path::link(
        "tmp_aio_path_test/link_src.txt",
        "tmp_aio_path_test/hard_link.txt"
    )!;

    @assert(path::exists("tmp_aio_path_test/hard_link.txt"));
    @assert(path::isfile("tmp_aio_path_test/hard_link.txt"));


    if (catch err = path::symlink(
        "link_src.txt",
        "tmp_aio_path_test/sym_link.txt"))
    {
        warn("[SKIP] symlink failed: %s", err);
        return;
    }

    @assert(path::islink("tmp_aio_path_test/sym_link.txt"));
    @assert(path::exists("tmp_aio_path_test/sym_link.txt"));

    char[512] buf;
    sz n = path::readlink("tmp_aio_path_test/sym_link.txt", buf[..])!;
    @assert(n > 0);
}

fn void? cleanup()
{
    if (path::exists("tmp_aio_path_test/list/a.txt")) path::remove("tmp_aio_path_test/list/a.txt")!;
    if (path::exists("tmp_aio_path_test/list/b.txt")) path::remove("tmp_aio_path_test/list/b.txt")!;
    if (path::exists("tmp_aio_path_test/scan/file1.txt")) path::remove("tmp_aio_path_test/scan/file1.txt")!;

    if (path::exists("tmp_aio_path_test/file.txt")) path::remove("tmp_aio_path_test/file.txt")!;
    if (path::exists("tmp_aio_path_test/stat.txt")) path::remove("tmp_aio_path_test/stat.txt")!;
    if (path::exists("tmp_aio_path_test/replace_dst.txt")) path::remove("tmp_aio_path_test/replace_dst.txt")!;
    if (path::exists("tmp_aio_path_test/link_src.txt")) path::remove("tmp_aio_path_test/link_src.txt")!;
    if (path::exists("tmp_aio_path_test/hard_link.txt")) path::remove("tmp_aio_path_test/hard_link.txt")!;
    path::remove("tmp_aio_path_test/sym_link.txt");

    path::removedirs("tmp_aio_path_test/list");
    path::removedirs("tmp_aio_path_test/scan");
    path::removedirs("tmp_aio_path_test/one");
    path::removedirs("tmp_aio_path_test");
}

fn void? main_task(void* arg)
{
    warn("=== ext::aio::path tests ===");

    if (path::exists("tmp_aio_path_test"))
    {
        cleanup()!!;
    }

    path::makedirs("tmp_aio_path_test", 0o777, true)!!;

    test_exists_and_types()!!;
    test_stat_and_getsize()!!;
    test_rename_replace_remove()!!;
    test_mkdir_makedirs_removedirs()!!;
    test_listdir()!!;
    test_scandir()!!;
    test_link_symlink_readlink()!!;

    cleanup()!!;

    warn("=== ext::aio::path tests done ===");
    
    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof