// test_taskgroup.c3

import ext::aio;
import ext::debug;

int worker1_started = 0;
int worker1_done = 0;

int worker2_started = 0;
int worker2_cancelled = 0;
int worker2_exited = 0;

fn void? worker1(void* arg)
{
    int id = (int)(sz)arg;

    worker1_started += 1;

    warn("worker %d start", id);

    aio::sleep((ulong)(100 * id))!;

    worker1_done += 1;

    warn("worker %d done", id);
}

fn void? main_task1(void* arg)
{
    TaskGroup group;
    group.init();

    group.spawn(&worker1, (void*)1)!;
    group.spawn(&worker1, (void*)2)!;
    group.spawn(&worker1, (void*)3)!;

    group.join_all()!;

    group.free();

    @assert(worker1_started == 3, "not all workers started");
    @assert(worker1_done == 3, "not all workers completed");

    warn("main_task1 OK");
}

fn void? worker2(void* arg)
{
    int id = (int)(sz)arg;

    worker2_started += 1;

    warn("worker2 %d start", id);

    if (catch err = aio::sleep(5000))
    {
        warn("worker2 %d cancelled err=%s", id, err);

        if (err != aio::CANCELLED) return err~;

        worker2_cancelled += 1;
    }

    worker2_exited += 1;

    warn("worker2 %d exit", id);
}

fn void? main_task2(void* arg)
{
    warn("main_task2 entered");

    TaskGroup group;
    group.init();

    group.spawn(&worker2, (void*)1)!;
    group.spawn(&worker2, (void*)2)!;

    aio::sleep(200)!;

    warn("cancel group");

    group.cancel_and_join()!;

    group.free();

    @assert(worker2_started == 2, "not all worker2 tasks started");
    @assert(worker2_cancelled == 2, "not all worker2 tasks were cancelled");
    @assert(worker2_exited == 2, "not all worker2 tasks exited");

    warn("main_task2 OK");
}

fn void main()
{
    aio::run(&main_task1)!!;
    warn("main_task1 finished");
    
    aio::run(&main_task2)!!;
    warn("main_task2 finished");
    
    warn("OK");
}

// eof