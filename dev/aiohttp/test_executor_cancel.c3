// test_executor_cancel.c3

// Executor cancel/race tests for ext::aio

// Nomota <hiongun@gmail.com>; MIT License

module test::executor_cancel;

import std::io;
import std::thread;
import ext::aio;
import ext::debug;

const sz JOB_COUNT = 32;

struct Job
{
    sz id;
    long sleep_us;
    bool started;
    bool finished;
}

Job[JOB_COUNT] jobs;
bool[JOB_COUNT] task_done;
bool ping_done = false;

fn void* slow_job(void* arg)
{
    Job* job = (Job*)arg;

    job.started = true;

    // Blocking sleep in worker thread.
    // Use platform sleep helper if your std/c binding differs.
    thread::sleep_ms(job.sleep_us/1000);

    job.finished = true;

    return arg;
}

fn void* fast_job(void* arg)
{
    Job* job = (Job*)arg;

    job.started = true;
    job.finished = true;

    return arg;
}

fn void? await_fast_job_task(void* arg)
{
    sz index = (sz)arg;

    Job* result = (Job*)aio::run_in_executor(&fast_job, &jobs[index])!!;

    @assert(result == &jobs[index], "fast executor result pointer mismatch");
    @assert(jobs[index].started, "fast executor job did not start");
    @assert(jobs[index].finished, "fast executor job did not finish");

    task_done[index] = true;
}

fn void? await_slow_job_task(void* arg)
{
    sz index = (sz)arg;

    Job* result = (Job*)aio::run_in_executor(&slow_job, &jobs[index])!!;

    @assert(result == &jobs[index], "slow executor result pointer mismatch");
    @assert(jobs[index].started, "slow executor job did not start");
    @assert(jobs[index].finished, "slow executor job did not finish");

    task_done[index] = true;
}

fn void? cancellable_executor_task(void* arg)
{
    sz index = (sz)arg;

    // This task is expected to be cancelled while worker still runs.
    void*? result = aio::run_in_executor(&slow_job, &jobs[index]);

    if (catch err = result)
    {
        @assert(
            err == aio::CANCELLED ||
            err == aio::TIMEOUT,
            "cancelled executor task fault mismatch"
        );

        task_done[index] = true;
        return;
    }

    // If cancellation races and the job completes first, this is also acceptable.
    task_done[index] = true;
}

fn void? ping_task(void* arg)
{
    for (sz i = 0; i < 20; i++)
    {
        aio::sleep(10_000)!;
    }

    ping_done = true;
}

fn void init_jobs()
{
    for (sz i = 0; i < JOB_COUNT; i++)
    {
        jobs[i] = {
            .id = i,
            .sleep_us = 50_000,
            .started = false,
            .finished = false,
        };

        task_done[i] = false;
    }

    ping_done = false;
}

fn void wait_until_all_done(sz count)
{
    for (sz spin = 0; spin < 500; spin++)
    {
        bool done = true;

        for (sz i = 0; i < count; i++)
        {
            if (!task_done[i])
            {
                done = false;
                break;
            }
        }

        if (done) return;

        aio::sleep(10_000)!!;
    }
}

fn void test_many_fast_executor_jobs()
{
    init_jobs();

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        aio::spawn(&await_fast_job_task, (void*)i)!!;
    }

    wait_until_all_done(JOB_COUNT);

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        @assert(task_done[i], "fast executor task did not finish");
        @assert(jobs[i].started, "fast executor job not started");
        @assert(jobs[i].finished, "fast executor job not finished");
    }
}

fn void test_many_slow_executor_jobs()
{
    init_jobs();

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        aio::spawn(&await_slow_job_task, (void*)i)!!;
    }

    wait_until_all_done(JOB_COUNT);

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        @assert(task_done[i], "slow executor task did not finish");
        @assert(jobs[i].started, "slow executor job not started");
        @assert(jobs[i].finished, "slow executor job not finished");
    }
}

fn void test_executor_does_not_block_loop()
{
    init_jobs();

    aio::spawn(&ping_task, null)!!;

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        aio::spawn(&await_slow_job_task, (void*)i)!!;
    }

    for (sz spin = 0; spin < 500; spin++)
    {
        if (ping_done) break;
        aio::sleep(10_000)!!;
    }

    @assert(ping_done, "event loop was blocked by executor jobs");

    wait_until_all_done(JOB_COUNT);
}

fn void wait_cancelled_workers_finished()
{
    for (sz spin = 0; spin < 300; spin++)
    {
        bool finished = true;

        for (sz i = 0; i < JOB_COUNT; i++)
        {
            if (!jobs[i].finished)
            {
                finished = false;
                break;
            }
        }

        if (finished) return;

        aio::sleep(10_000)!!;
    }
}

fn void test_cancel_executor_awaiters()
{
    init_jobs();

    Task*[JOB_COUNT] tasks;

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        jobs[i].sleep_us = 200_000;
        tasks[i] = aio::spawn_joinable(&cancellable_executor_task, (void*)i)!!;
    }

    aio::sleep(20_000)!!;

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        tasks[i].cancel();
    }

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        if (catch err = tasks[i].join())
        {
            @assert(
                err == aio::CANCELLED ||
                err == aio::TIMEOUT,
                "executor cancelled join fault mismatch"
            );
        }
    }

    // Give worker completions time to call back into the loop.
    // This checks that executor_complete() safely handles future == null.
    wait_cancelled_workers_finished();

    for (sz i = 0; i < JOB_COUNT; i++)
    {
        @assert(jobs[i].started, "cancelled executor worker did not start");
        @assert(jobs[i].finished, "cancelled executor worker did not finish");
    }
}

fn void? main_task(void* arg)
{
    test_many_fast_executor_jobs();
    test_many_slow_executor_jobs();
    test_executor_does_not_block_loop();
    test_cancel_executor_awaiters();

    aio::current_loop().stop()!;

    io::printfn("test_executor_cancel: OK");
}

fn void main()
{
    aio::run(&main_task);
}

// eof