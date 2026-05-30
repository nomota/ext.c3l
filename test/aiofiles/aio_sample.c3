// aio_sample.c3

module aio_sample;

import std::collections::list;
import std::io;
import c::stdlib;
import ext::debug;
import ext::mem;
import ext::asyncio;
import ext::aiofiles;
import ext::aiofiles::os;
import ext::aiofiles::os::path;

// 1. Basic file read/write
fn void? basic_readwrite()
{
    io::printn("=== 1. basic read/write ===");

    // Write to file
    AioFile? wf = aiofiles::open("hello.txt", "w");
    if (catch err = wf) {
        io::printfn("open error: %s", err);
        return;
    }
    defer wf.close();

    wf.writef("Hello, %s!\n", "C3")!;
    wf.writef("Line %d\n", 2)!;
    wf.writef("Line %d\n", 3)!;
    wf.flush();

    // Check file size
    sz size = aiofiles::file_size("hello.txt")!;
    io::printfn("Written %d bytes", size);

    // Read file
    AioFile rf = aiofiles::open("hello.txt", "r")!;
    defer rf.close();

    char[256] buf;
    sz n = rf.read(&buf)!;
    io::printfn("Read: %s", (String)buf[:n]);
}

// 2. readline — read line by line
fn void? read_lines()
{
    io::printn("\n=== 2. read lines ===");

    AioFile f = aiofiles::open("hello.txt", "r")!;
    defer f.close();

    char[256] buf;
    int lineno = 1;
    while (!f.at_eof()) {
        sz n = f.read_until('\n', &buf)!;
        if (n == 0) break;

        io::printfn("[%d] %s", lineno++, (String)buf[:n]);
    }
}

// 3. seek / tell / truncate
fn void? seek_demo()
{
    io::printn("\n=== 3. seek / tell / truncate ===");

    AioFile f = aiofiles::open("hello.txt", "r+")!;
    defer f.close();

    // Current position
    long pos = f.tell();
    io::printfn("Initial pos: %d", pos);

    // Move forward 5 bytes
    f.seek(5, 0);
    io::printfn("After seek(5): %d", f.tell());

    // Read the rest
    char[128] buf;
    sz n = f.read_unbuffered(&buf)!;
    io::printfn("From pos 5: %s", (String)buf[:n]);

    // Truncate file to 10 bytes
    f.truncate(10);
    sz new_size = aiofiles::file_size("hello.txt")!;
    io::printfn("After truncate: %d bytes", new_size);
}


// 4. os::stat / rename / remove
fn void? os_stat_demo()
{
    io::printn("\n=== 4. os stat / rename / remove ===");

    // Create a file
    AioFile f = aiofiles::open("temp.txt", "w")!;
    f.writef("temporary data\n")!;
    f.close();

    // Query metadata via stat
    Stat st = os::stat("temp.txt")!;
    io::printfn("size  : %d", st.st_size);
    io::printfn("mtime : %d", st.st_mtime);

    // Rename
    os::rename("temp.txt", "renamed.txt")!;
    io::printfn("renamed: %s", path::exists("renamed.txt") ? "yes" : "no");

    // Replace (overwrite)
    AioFile f2 = aiofiles::open("target.txt", "w")!;
    f2.writef("old\n")!;
    f2.close();
    os::replace("renamed.txt", "target.txt")!; // renamed -> target (overwrites)

    // Remove
    os::remove("target.txt")!;
    io::printfn("removed: %s", !path::exists("target.txt") ? "yes" : "no");
}

// 5. mkdir / makedirs / listdir / removedirs
fn void? dir_demo()
{
    io::printn("\n=== 5. mkdir / listdir / removedirs ===");

    // Create nested directories
    os::makedirs("sandbox/a/b/c")!;
    io::printfn("isdir sandbox/a/b/c: %s", path::isdir("sandbox/a/b/c") ? "yes" : "no");

    // Create some files
    String[] names = {
       "foo.txt", "bar.txt", "baz.c3"
    };
    foreach (name : names) {
        AioFile f = aiofiles::open(string::tformat("sandbox/%s", name), "w")!;
        f.writef("// %s\n", name)!;
        f.close();
    }

    // List directory contents
    List{String} files = os::listdir(mem, "sandbox")!;
    defer {
        files.free();
    }
    io::printn("sandbox contents:");
    foreach (s : files) io::printfn("  %s", s);

    // Remove recursively (only empty subdirectories)
    os::removedirs("sandbox/a/b/c")!;

    @assert(path::exists("sandbox"), "err");

    foreach (name : names) {
        os::remove(string::tformat("sandbox/%s", name))!;
    }

    os::removedirs("sandbox")!;
    @assert(!path::exists("sandbox"), "err");
}

// 6. scandir — directory iterator
fn void? scandir_demo()
{
    io::printn("\n=== 6. scandir ===");

    os::makedirs("scan_test")!;
    String[] names = {"alpha.txt", "beta.txt", "gamma.c3"};

    foreach (name : names) {
        AioFile f = aiofiles::open(string::tformat("scan_test/%s", name), "w")!;
        f.writef("data\n")!;
        f.close();
    }

    DirIterator iter = os::scandir(mem, "scan_test")!;
    defer iter.close();

    io::printn("scan_test entries:");
    while (true) {
        DirEntry? entry = iter.next();
        if (catch entry) break;
        defer entry.free();

        if (entry.is_file()) {
            sz  sz = entry.size()          ?? 0;
            long mtime = entry.last_modified() ?? 0;
            io::printfn("  [F] %-20s  size=%d  mtime=%d", entry.name, sz, mtime);
        } else if (entry.is_link()) {
            io::printfn("  [L] %s", entry.name);
        } else {
            io::printfn("  [D] %s", entry.name);
        }
    }

    @assert(path::exists("scan_test"), "err");

    foreach (name : names) {
        os::remove(string::tformat("scan_test/%s", name))!;
    }

    os::removedirs("scan_test")!;

    @assert(!path::exists("scan_test"), "err");
}

// 7. symlink / link / readlink
fn void? link_demo()
{
    io::printn("\n=== 7. symlink / link / readlink ===");

    AioFile f = aiofiles::open("original.txt", "w")!;
    f.writef("original content\n")!;
    f.close();
    
    if (path::exists("link_to_original.txt")) {
        os::remove("link_to_original.txt")!;
    }
    os::symlink("original.txt", "link_to_original.txt")!;
    io::printfn("islink: %s", path::islink("link_to_original.txt") ? "yes" : "no");

    char[256] buf;
    sz n = os::readlink("link_to_original.txt", &buf)!;
    io::printfn("readlink -> %s", (String)buf[:n]);

    if (path::exists("hardlink.txt")) {
        os::remove("hardlink.txt")!;
    }
    os::link("original.txt", "hardlink.txt")!;
    io::printfn("hardlink size: %d", path::getsize("hardlink.txt")!);

    @assert(path::exists("original.txt"), "err");
    os::remove("original.txt")!;

    os::remove("hardlink.txt")!;

    os::remove("link_to_original.txt")!;

    //@assert(path::exists("link_to_original.txt"), "err");
    @assert(! path::exists("link_to_original.txt"), "err");
}

// 8. Chunked file copy utility
fn void? copy_file(String src, String dst)
{
    io::printn("\n=== 8. file copy ===");

    AioFile in  = aiofiles::open(src, "r")!;
    AioFile out = aiofiles::open(dst, "w")!;
    defer in.close();
    defer out.close();

    char[4096] buf;
    sz total = 0;
    while (!in.at_eof()) {
        sz n = in.read_unbuffered(&buf)!;
        if (n == 0) break;
        out.write(buf[:n])!;
        total += n;
    }
    out.flush();
    io::printfn("copied %d bytes: %s -> %s", total, src, dst);
}

// 9. Log writer
struct Logger {
    AioFile file;
}

fn Logger? logger_open(String path)
{
    return { .file = aiofiles::open(path, "a+")! };
}

fn void Logger.close(&self)
{
    self.file.close();
}

fn void? Logger.log(&self, String level, String msg)
{
    self.file.writef("[%s] %s\n", level, msg)!;
    self.file.flush();
}

fn void? logger_demo()
{
    io::printn("\n=== 9. logger ===\n");
    
    Logger log = logger_open("app.log")!;
    defer log.close();

    log.log("INFO",  "application started")!;
    log.log("DEBUG", "loading config...")!;
    log.log("WARN",  "config not found, using defaults")!;
    log.log("ERROR", "connection timeout")!;

    io::printn("Log 4 lines:");

    // Print full log
    AioFile f = aiofiles::open("app.log", "r")!;
    defer f.close();
    char[1024] buf;
    sz n = f.read(&buf)!;
    io::print((String)buf[:n]);
    
    io::printn("done.");
}

// 10. stdin / stdout  handling
fn void? echo_stdin()
{
    io::printn("\n=== 10. stdin/out  ===");
    
    AioFile in  = aiofiles::stdin();
    AioFile out = aiofiles::stdout();
    AioFile err = aiofiles::stderr();

    err.writef("[echo] type something (EOF to quit)\n")!;

    char[1024] buf;
    while (!in.at_eof()) {
        sz? n = in.read_until('\n', &buf);
        if (catch e = n) {
            warn("%s", e);
            return e~;
        }
// warn("n = %d", n);        
        
        if (n == 0) break;
        out.writef(">> %s", (String)buf[:n])!;
        out.flush();
    }
}

fn void main_coro()
{
    basic_readwrite()!!;

    read_lines()!!;

    seek_demo()!!;

    os_stat_demo()!!;

    dir_demo()!!;

    scandir_demo()!!;

    link_demo()!!;

    copy_file("hello.txt", "hello_copy.txt")!!;
        
    logger_demo()!!;

    // echo_stdin()!!; // interactive
    
    // Cleanup
    os::remove("hello.txt")!!;
    os::remove("hello_copy.txt")!!;
    os::remove("app.log")!!;
}
    
// main: run via asyncio event loop
fn void main()
{
    asyncio::run(&main_coro);
}

