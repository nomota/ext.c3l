// test_file.c3

import ext::aio;
import ext::aio::path;
import ext::debug;

const String TEST_PATH = "aio_file_test.txt";
const String TEST_DATA = "hello aio file\n";

fn void? main_task(void* arg)
{
    aio::File* f = aio::file_open(TEST_PATH, "w+")!;
    defer f.free();

    f.write_all(TEST_DATA)!;
    f.flush()!;

    long size = f.size()!;
    @assert(size == (long)TEST_DATA.len, "file size mismatch after write");

    long pos = f.tell()!;
    @assert(pos == (long)TEST_DATA.len, "file position mismatch after write");

    long seek_pos = f.seek(0, 0)!;
    @assert(seek_pos == 0, "seek(0, SEEK_SET) failed");

    char[128] buf = {};
    usz n = f.read(buf[..])!;

    @assert(n == TEST_DATA.len, "read length mismatch");

    String got = (String)buf[0:n];
    @assert(got == TEST_DATA, "read content mismatch");

    warn("read: '%s'", got);

    size = f.size()!;
    @assert(size == (long)TEST_DATA.len, "file size mismatch after read");

    warn("size: %d", size);
    
    path::remove(TEST_PATH);
    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}