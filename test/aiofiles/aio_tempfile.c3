// aio_tempfile.c3

module aio_tempfile;

import c::stdio;
import std::io;
import ext::debug;
import ext::mem;
import ext::asyncio;
import ext::aiofiles;
import ext::aiofiles::os::path;
import ext::aiofiles::tempfile;

// no boundary check, buf must be enough
fn String bcat(char[] buf, String... args)
{
    sz n = 0;
    foreach (arg: args) {
        buf[n:arg.len] = arg[0:arg.len];
        n += arg.len;
    }
    buf[n] = 0;
    return (String) buf[0:n];
}

// 1. Basic temporary file — write, read back, auto-delete on close
fn void? basic_tempfile()
{
    io::printn("=== 1. basic temp file ===");

    AioTempFile tmp = tempfile::temporaryFile()!;
    io::printfn("created : %s", tmp.fullpath);

    // Write some data
    tmp.file.writef("Hello from temp!\n")!;
    tmp.file.writef("Line %d\n", 2)!;
    tmp.file.flush();
    
    // Seek back to the beginning and read
    tmp.file.seek(0, 0);
    char[256] buf;
    sz n = tmp.file.read(&buf)!;
    io::printfn("content :\n%s", (String)buf[:n]);

    // close() removes the file automatically
    tmp.close();

    io::printn("temp file removed");
}

// 2. Temporary file as a scratch buffer — accumulate then consume
fn void? tempfile_as_buffer()
{
    io::printn("\n=== 2. temp file as scratch buffer ===");

    AioTempFile tmp = tempfile::temporaryFile()!;
    defer tmp.close();

    // Simulate writing chunks of data
    String[] chunks = { "alpha\n", "beta\n", "gamma\n", "delta\n" };
    foreach (chunk : chunks) {
        tmp.file.write((char[])chunk[:chunk.len])!;
    }
    tmp.file.flush();

    // Read back line by line
    tmp.file.seek(0, 0);
    char[128] line;
    int lineno = 1;
    while (!tmp.file.at_eof()) {
        sz n = tmp.file.read_until('\n', &line)!;
        if (n == 0) break;
        io::printfn("  [%d] %s", lineno++, (String)line[:n]);
    }
}

// 3. Temporary file for safe atomic write — write to temp, rename to final
fn void? atomic_write(String dest)
{
    io::printn("\n=== 3. atomic write via temp file ===");

    AioTempFile tmp = tempfile::temporaryFile()!;
    defer tmp.close();
    io::printfn("staging in: %s", tmp.fullpath);

    // Write all content to temp first
    tmp.file.writef("# config v2\n")!;
    tmp.file.writef("key = value\n")!;
    tmp.file.writef("timeout = 30\n")!;
    tmp.file.flush();
    tmp.close_handle(); // close file handle before rename (required on Windows)

    // Rename temp -> dest (atomic on POSIX)
    os::rename(tmp.fullpath, dest);

    io::printfn("committed: %s", dest);
}


// 4. Temporary directory — create files inside, auto-clean on close
fn void? basic_tempdir()
{
    io::printn("\n=== 4. basic temp dir ===");

    AioTempDir tdir = tempfile::temporaryDirectory();
    io::printfn("created : %s", tdir.fullpath);

    // Create a few files inside the temp dir
    String[] names = { "a.txt", "b.txt", "c.log" };
    foreach (name : names) {
        char[1024] pbuf;
        String fpath = bcat(&pbuf, tdir.fullpath, "/", name);

        AioFile f = aiofiles::open(fpath, "w")!;
        f.writef("// %s\n", name)!;
        f.close();
        io::printfn("  wrote: %s", fpath);
    }

    // close() recursively removes everything

    tdir.close();

    io::printn("temp dir removed");
}

// 5. Temporary directory as isolated sandbox — nested dirs + files
fn void? tempdir_sandbox()
{
    io::printn("\n=== 5. temp dir sandbox ===");

    AioTempDir tdir = tempfile::temporaryDirectory();
    defer tdir.close();

    // Build nested structure: <tdir>/sub/deep/
    char[1024] _sub; char[1024] _deep;
    String sub = bcat(&_sub, tdir.fullpath, "/sub");
    String deep = bcat(&_deep, tdir.fullpath, "/sub/deep");

    os::makedirs(sub);
    os::makedirs(deep);

    // Write a file at each level
    String[] paths = {
        string::tformat("%s/root.txt",     tdir.fullpath),
        string::tformat("%s/sub/mid.txt",  tdir.fullpath),
        string::tformat("%s/sub/deep/leaf.txt", tdir.fullpath),
    };
    foreach (p : paths) {
        AioFile f = aiofiles::open(p, "w")!;
        f.writef("data at %s\n", p)!;
        f.close();
        io::printfn("  created: %s", p);
    }

    io::printn("  (deferred close() will recursively clean up)");
}

// 6. Multiple temp files — independent lifetimes
fn void? multi_tempfiles()
{
    io::printn("\n=== 6. multiple temp files ===");

    AioTempFile t1 = tempfile::temporaryFile()!;
    AioTempFile t2 = tempfile::temporaryFile()!;
    AioTempFile t3 = tempfile::temporaryFile()!;

    t1.file.writef("file one\n")!;
    t2.file.writef("file two\n")!;
    t3.file.writef("file three\n")!;

    io::printfn("t1: %s", t1.name);
    io::printfn("t2: %s", t2.name);
    io::printfn("t3: %s", t3.name);

    // Close in reverse order — each removes its own file
    t3.close();
    t2.close();
    t1.close();
    io::printn("all temp files removed");
}

// 7. Temp file for capturing output (in-process "pipe")
fn void? capture_output()
{
    io::printn("\n=== 7. capture output to temp file ===");

    AioTempFile tmp = tempfile::temporaryFile()!;
    defer tmp.close();

    // "Redirect" formatted output into the temp file
    for (int i = 0; i < 5; i++) {
        tmp.file.writef("row %d: value=%d\n", i, i * i)!;
    }
    tmp.file.flush();

    // Read it all back
    tmp.file.seek(0, 0);
    char[512] buf;
    sz n = tmp.file.read(&buf)!;
    io::printn("--- captured output ---");
    io::print((String)buf[:n]);
    io::printn("-----------------------");
}

fn void main_coro()
{
    basic_tempfile()!!;
    tempfile_as_buffer()!!;
    atomic_write("config.ini")!!;
    @assert(path::exists("config.ini"), "error");
    basic_tempdir()!!;
    tempdir_sandbox()!!;
    multi_tempfiles()!!;
    capture_output()!!;

    // Cleanup the atomic-write artifact from demo 3
    os::remove("config.ini")!!;
}

fn void main()
{
    asyncio::run(&main_coro);
}
