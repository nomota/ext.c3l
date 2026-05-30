// test1.c3

// simple task spawning test

import ext::aio;
import ext::debug;

int step = 0;

fn void expect_step(int expected, String label)
{
    @assert(step == expected, "unexpected execution order");
    warn(label);
    step += 1;
}

fn void? worker1(void* arg)
{
    expect_step(0, "worker1: A");

    aio::yield();
    aio::sleep(500)!;

    expect_step(3, "worker1: B");
}

fn void? worker2(void* arg)
{
    expect_step(1, "worker2: A");

    aio::yield();
    aio::sleep(100)!;

    expect_step(2, "worker2: B");
}

fn void? main_task(void* arg)
{
    Task* t1 = aio::spawn_joinable(&worker1)!;
    Task* t2 = aio::spawn_joinable(&worker2)!;

    t1.join()!;
    t2.join()!;

    expect_step(4, "main done");

    @assert(step == 5, "test1: final step mismatch");

    warn("OK");
}

fn void main()
{
    aio::run(&main_task);

    @assert(step == 5, "test1: main_task did not complete");
}