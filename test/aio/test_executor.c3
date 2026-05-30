// test_executor.c3

import ext::aio;
import ext::debug;
import std::thread;
import c::unistd;

int g_tick_count = 0;

fn void* blocking_add(void* arg)
{
    int base = (int)(sz)arg;

    thread::sleep_ms(300);

    return (void*)(sz)(base + 100);
}

fn void* blocking_sum(void* arg)
{
    int n = (int)(sz)arg;
    int sum = 0;

    for (int i = 1; i <= n; i++)
    {
        sum += i;
        thread::sleep_ms(10);
    }

    return (void*)(sz)sum;
}

fn void? ticker_task(void* arg)
{
    for (int i = 0; i < 10; i++)
    {
        aio::sleep(50)!;

        g_tick_count += 1;

        warn("[ticker] tick %d", g_tick_count);
    }
}

fn void? executor_add_task(void* arg)
{
    warn("[executor-add] start");

    void* result = aio::run_in_executor(&blocking_add, (void*)23)!;

    int value = (int)(sz)result;

    warn("[executor-add] result=%d", value);

    if (value != 123) return aio::FAILED~;
}

fn void? executor_sum_task(void* arg)
{
    warn("[executor-sum] start");

    void* result = aio::run_in_executor(&blocking_sum, (void*)10)!;

    int value = (int)(sz)result;

    warn("[executor-sum] result=%d", value);

    if (value != 55) return aio::FAILED~;
}

fn void? main_task(void* arg)
{
    g_tick_count = 0;

    Task* ticker = aio::spawn_joinable(&ticker_task)!;
    Task* add = aio::spawn_joinable(&executor_add_task)!;
    Task* sum = aio::spawn_joinable(&executor_sum_task)!;

    ticker.join()!;
    add.join()!;
    sum.join()!;

    warn("[main] tick_count=%d", g_tick_count);

    if (g_tick_count == 0) return aio::FAILED~;

    warn("executor test passed");
    warn("OK");
}

fn void main()
{
    aio::run(&main_task);
}