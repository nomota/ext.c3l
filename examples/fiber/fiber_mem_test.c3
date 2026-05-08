// fiber_mem_test.c3

module test_fiber_mem @if(env::POSIX);

import std::io;
import c::stdio;
import c::stdlib;
import c::string;
import ext::fiber;

const int FIBER_COUNT = 100_000;
const int REPORT_EVERY = 5_000;
const uint STACK_SIZE = 128_000;

struct MemInfo
{
    long vm_size_kb;
    long vm_rss_kb;
}

fn void noop()
{
    // Do nothing.
    //
    // For SJLJ backend, returning from entry is okay because springboard()
    // marks the fiber done and yields back.
}

fn bool parse_status_line(char* line, char* key, long* out_value) @private
{
    usz key_len = string::strlen(key);

    if (string::strncmp(line, key, key_len) != 0) return false;

    char* p = line + key_len;

    while (*p == ' ' || *p == '\t' || *p == ':')
    {
        p++;
    }

    *out_value = stdlib::atol(p);
    return true;
}

fn MemInfo read_mem_info()
{
    MemInfo info = {
        .vm_size_kb = 0,
        .vm_rss_kb = 0,
    };

    CFile fp = stdio::fopen("/proc/self/status", "r");
    if (fp == null) return info;

    char[512] line;

    while (stdio::fgets(&line[0], line.len, fp) != null)
    {
        long value = 0;

        if (parse_status_line(&line[0], "VmSize", &value))
        {
            info.vm_size_kb = value;
            continue;
        }

        if (parse_status_line(&line[0], "VmRSS", &value))
        {
            info.vm_rss_kb = value;
            continue;
        }
    }

    stdio::fclose(fp);
    return info;
}

fn void print_mem(String label, int count)
{
    MemInfo m = read_mem_info();

    io::printf(
        "%s count=%d VmSize=%d KB VmRSS=%d KB\n",
        label,
        count,
        m.vm_size_kb,
        m.vm_rss_kb
    );
}

fn void main()
{
    io::printf("fiber memory test\n");
    io::printf("fiber_count=%d stack_size=%d\n", FIBER_COUNT, STACK_SIZE);

    print_mem("start ", 0);

    Fiber*[] fibers = mem::alloc_array(Fiber*, FIBER_COUNT);

    //
    // 1. Create many fibers.
    //
    // This should mostly increase VmSize because each fiber reserves
    // virtual stack memory with mmap().
    //
    int fiber_count = 0;
    for (int i = 0; i < FIBER_COUNT; i++)
    {
        fibers[i] = fiber::create(&noop, STACK_SIZE, null);

        if (fibers[i] == null)
        {
            io::printf("fiber create failed at %d\n", i);
            break;
        }

        fiber_count = i + 1;

        if ((i + 1) % REPORT_EVERY == 0)
        {
            print_mem("create", i + 1);
        }
    }

    print_mem("after create", fiber_count);

    //
    // 2. Run each fiber once.
    //
    // For the virtual-memory stack backend, RSS may increase here because
    // the fiber stack is actually touched when the coroutine starts.
    //

    for (int i = 0; i < fiber_count; i++)
    {
        if (fibers[i] == null) continue;

        fiber::switch_to(fibers[i]);

        if ((i + 1) % REPORT_EVERY == 0)
        {
            print_mem("run   ", i + 1);
        }
    }

    print_mem("after run", fiber_count);

    //
    // 3. Delete fibers.
    //
    // VmSize should go back down as mmap() regions are munmap()'d.
    //

    for (int i = 0; i < fiber_count; i++)
    {
        if (fibers[i] == null) continue;

        fiber::delete(fibers[i]);
        fibers[i] = null;

        if ((i + 1) % REPORT_EVERY == 0)
        {
            print_mem("delete", i + 1);
        }
    }

    print_mem("after delete", 0);

    mem::free(fibers);

    fiber::deinit();

    print_mem("end   ", 0);
}

module test_fiber_mem @if(env::WIN32);

import std::io;

fn void main()
{
    io::printfn("this test does not apply to windows");
}

