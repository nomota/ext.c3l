// cfile_example.C3

// cfile examples

// Nomota <hiongun@gmail.com>; MIT License

module cfile_example;

import ext::io::cfile;
import ext::io::stat;
import std::io;
import ext::debug;

// 
// 1. Writing to a File
// 
fn void example_write()
{
    cfile::File? fp = cfile::open("hello.txt", "w");
    if (catch err = fp) {
        io::printfn("Failed to open file: %s", err);
        return;
    }
    defer fp.close();

    char[] data = "Hello, C3 World!\n";
    fp.write(data)!!;

    fp.write_byte('!')!!;

    fp.printf("value: %d, name: %s\n", 42, "C3")!!;

    fp.flush();
    io::printfn("hello.txt written successfully");
}

// 
// 2. Reading Line by Line
// 
fn void example_readline()
{
    cfile::File? fp = cfile::open("hello.txt", "r");
    if (catch err = fp) {
        io::printfn("Failed to open file: %s", err);
        return;
    }
    defer fp.close();

    char[1024] line_buf;

    while (!fp.eof()) {
        sz? n = fp.readline(&line_buf);
        if (catch err = n) { break; }
        if (n == 0)  { break; }
        io::printf("%s", (String)line_buf[:n]);
    }
}

// 
// 3. Buffer Read + seek / tell
// 
fn void example_read_buffer()
{
    cfile::File? fp = cfile::open("hello.txt", "r");
    if (catch err = fp) { return; }
    defer fp.close();

    char[4096] buf;

    long? pos = fp.tell();
    if (try pos) {
        io::printfn("Current position: %d bytes", pos);
    }

    sz? n = fp.read(&buf);
    if (catch err = n) {
        io::printfn("Read failed: %s", err);
        return;
    }
    io::printfn("Bytes read: %d", n);
    io::printf("Content: %s", (String)buf[:n]);

    fp.seek(0, 0)!!;
}

// 
// 4. Reading One Byte at a Time
// 
fn void example_read_byte()
{
    cfile::File? fp = cfile::open("hello.txt", "r");
    if (catch err = fp) { return; }
    defer fp.close();

    sz count = 0;
    while (!fp.eof()) {
        char? c = fp.read_byte();
        if (catch err = c) { break; }
        io::printf("%c", c);
        count++;
    }
    io::printfn("\nTotal bytes read: %d", count);
}

// 
// 5. Load / Save an Entire File
// 
fn void example_load_save()
{
    char[]? buf = cfile::load(tmem, "hello.txt");
    if (catch err = buf) {
        io::printfn("Load failed: %s", err);
        return;
    }
    // defer free(buf);

    io::printfn("File size : %d bytes", buf.len);
    io::printfn("Content   :\n%s", (String)buf);

    cfile::save("output.txt", buf)!!;
    io::printfn("output.txt saved");
}

// 
// 6. File Existence, Size, and Modification Time
// 
fn void example_stat()
{
    String path = "hello.txt";

    if (!cfile::exists(path)) {
        io::printfn("File does not exist: %s", path);
        return;
    }

    sz? siz = cfile::size(path);
    if (try siz) {
        io::printfn("Size           : %d bytes", siz);
    }

    long? mtime = cfile::last_modified(path);
    if (try mtime) {
        io::printfn("Modified (unix): %d", mtime);
    }
}

// 
// 7. File Type and Permission Flags
// 
fn void example_file_type()
{
    String path = "hello.txt";

    io::printfn("Is directory ? %s", cfile::is_dir(path)        ? "yes" : "no");
    io::printfn("Is file      ? %s", cfile::is_file(path)       ? "yes" : "no");
    io::printfn("Is symlink   ? %s", cfile::is_link(path)       ? "yes" : "no");
    io::printfn("Readable     ? %s", cfile::is_readable(path)   ? "yes" : "no");
    io::printfn("Writable     ? %s", cfile::is_writeable(path)  ? "yes" : "no");
    io::printfn("Executable   ? %s", cfile::is_executable(path) ? "yes" : "no");
}

// 
// 8. Copy, Rename, and Remove
// 
fn void example_ops()
{
    cfile::copy("hello.txt", "hello_backup.txt")!!;
    io::printfn("Copied   → hello_backup.txt");

    cfile::rename("hello_backup.txt", "hello_renamed.txt")!!;
    io::printfn("Renamed  → hello_renamed.txt");

    cfile::remove("hello_renamed.txt")!!;
    io::printfn("Removed    hello_renamed.txt");
}

// 
// 9. Read Symbolic Link Target (POSIX only)
// 
fn void example_read_link() @if(env::LINUX)
{
    char[512] link_buf;

    sz? len = cfile::read_link("/proc/self/exe", &link_buf);
    if (catch err = len) {
        io::printfn("read_link failed: %s", err);
        return;
    }
    io::printfn("Executable path: %s", (String)link_buf[:len]);
}

fn void example_read_link() @if(env::WIN32)
{
    cfile::remove("mylink");
    stat::symlink("cfile_example.exe", "mylink");

    char[512] link_buf;

    sz? len = cfile::read_link("mylink", &link_buf);
    if (catch err = len) {
        io::printfn("read_link failed: %s", err);
        return;
    }
    io::printfn("Executable path: %s", (String)link_buf[:len]);
    cfile::remove("mylink");
}

// 
// 10. Change File Permissions (POSIX only)
// 
fn void example_chmod()
{
    // 0o644 = owner rw, group/others r
    cfile::change_mode("hello.txt", 0o644)!!;
    io::printfn("Permissions changed to 0644");
}

// 
// main
// 
fn void main()
{
    io::printfn("=== ext::io::cfile examples ===\n");

    io::printfn("[1] Write");
    example_write();

    io::printfn("\n[2] Read line by line");
    example_readline();

    io::printfn("\n[3] Buffer read + seek/tell");
    example_read_buffer();

    io::printfn("\n[4] Read byte by byte");
    example_read_byte();

    io::printfn("\n[5] Load / Save");
    example_load_save();

    io::printfn("\n[6] Stat");
    example_stat();

    io::printfn("\n[7] File type & permissions");
    example_file_type();

    io::printfn("\n[8] Copy / Rename / Remove");
    example_ops();

    io::printfn("\n[9] Read symlink (POSIX)");
    example_read_link();

    io::printfn("\n[10] Change mode (POSIX)");
    example_chmod();

    cfile::remove("hello.txt");
    cfile::remove("output.txt");
    io::printfn("\nDone.");
}

