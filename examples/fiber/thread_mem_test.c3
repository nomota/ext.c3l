// thread_mem_test.c3

module test_thread_mem @if(env::POSIX);

import std::io;
import c::stdio;
import c::stdlib;
import c::string;
import c::pthread;
import c::unistd;

const int THREAD_COUNT = 100_000;
const int REPORT_EVERY = 1_000;
const uint STACK_SIZE = 128_000;

struct MemInfo
{
    long vm_size_kb;
    long vm_rss_kb;
}

fn void* thread_entry(void* arg)
{
    // Keep the thread alive until main joins it.
    //
    // If the thread exits immediately, the measurement will mostly show
    // create/delete churn instead of simultaneous thread memory usage.
    while (true)
    {
        unistd::sleep(1);
    }

    // return null;
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
    io::printf("thread memory test\n");
    io::printf("thread_count=%d stack_size=%d\n", THREAD_COUNT, STACK_SIZE);

    print_mem("start ", 0);

    Pthread* threads = mem::alloc_array(Pthread, THREAD_COUNT);

    PthreadAttr attr = {};
    int rc = pthread::pthread_attr_init(&attr);

    if (rc != 0)
    {
        io::printf("pthread_attr_init failed rc=%d\n", rc);
        return;
    }

    rc = pthread::pthread_attr_setstacksize(&attr, STACK_SIZE);

    if (rc != 0)
    {
        io::printf("pthread_attr_setstacksize failed rc=%d stack_size=%d\n", rc, STACK_SIZE);
        pthread::pthread_attr_destroy(&attr);
        return;
    }
    
    pthread::pthread_setcancelstate(pthread::PTHREAD_CANCEL_ENABLE, null);
    pthread::pthread_setcanceltype(pthread::PTHREAD_CANCEL_DEFERRED, null);
    
    //
    // 1. Create many threads.
    //
    // Unlike fibers, pthreads are kernel-visible execution contexts.
    // This will usually fail much earlier than the fiber test because of
    // kernel thread limits, scheduler resources, and per-thread metadata.
    //

    int thread_count = 0;

    for (int i = 0; i < THREAD_COUNT; i++)
    {
        rc = pthread::pthread_create(
            &threads[i],
            &attr,
            &thread_entry,
            null
        );

        if (rc != 0)
        {
            io::printf("pthread_create failed at %d rc=%d\n", i, rc);
            break;
        }

        thread_count = i + 1;

        if ((i + 1) % REPORT_EVERY == 0)
        {
            print_mem("create", i + 1);
        }
    }

    print_mem("after create", thread_count);

    //
    // 2. Threads stay alive, so there is no separate run phase.
    //
    // Sleep a little so /proc/self/status has a stable point to observe.
    //

    unistd::sleep(2);
    print_mem("after sleep ", thread_count);

    //
    // 3. Cancel and join threads.
    //
    // The entry function loops forever, so we use pthread_cancel().
    //

    for (int i = 0; i < thread_count; i++)
    {
        pthread::pthread_cancel(threads[i]);

        if ((i + 1) % REPORT_EVERY == 0)
        {
            print_mem("cancel", i + 1);
        }
    }

    for (int i = 0; i < thread_count; i++)
    {
        pthread::pthread_join(threads[i], null);

        if ((i + 1) % REPORT_EVERY == 0)
        {
            print_mem("join  ", i + 1);
        }
    }

    print_mem("after join", 0);

    pthread::pthread_attr_destroy(&attr);
    mem::free(threads);

    print_mem("end   ", 0);
}

module test_thread_mem @if(env::WIN32);

import std::io;

fn void main()
{
    io::printfn("this test does not apply to windows");
}

