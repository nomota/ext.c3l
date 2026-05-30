// task_group.c3
 
module ext::asyncio;

import ext::debug;
import ext::mem;

const sz TG_MAX_TASKS = 128;

struct TaskGroup {
    Task*[TG_MAX_TASKS] tasks;
    sz count;
    bool failed;
    fault first_error;
    EventLoop* loop;
}

fn TaskGroup* taskgroup_new() 
{
    TaskGroup* tg = localmem.alloc(TaskGroup);
    *tg = {
        .count = 0,
        .failed = false,
        .first_error = NONE,
        .loop = get_running_loop(),
    };
    return tg;
}

fn void TaskGroup.free(&self) 
{
    for (sz i = 0; i < self.count; i++) {
        self.tasks[i].free();
    }
    localmem.free(self);
}

fn Task* TaskGroup.create_task(&self, Coroutine coro, String name = "tg_task", uint stack_size = 64_000, void* arg=null) 
{
    @assert(self.count < TG_MAX_TASKS, "TaskGroup: task limit exceeded");
    Task* t = self.loop.create_task(coro, name, stack_size, false, arg);
    self.tasks[self.count++] = t;
    return t;
}

fn void? TaskGroup.wait(&self) @maydiscard
{
    bool any_running = true;

    while (any_running) {
        any_running = false;
        bool found_error = false;

        for (sz i = 0; i < self.count; i++) {
            Task* t = self.tasks[i];
            if (t.done()) {
                if (t.error != NONE && !self.failed) {
                    self.failed = true;
                    self.first_error = t.error;
                    found_error = true;
                }
            } else {
                any_running = true;
            }
        }

        if (found_error) {
            for (sz i = 0; i < self.count; i++) {
                if (!self.tasks[i].done()) {
                    self.tasks[i].cancel();
                }
            }
            for (sz i = 0; i < self.count; i++) {
                if (!self.tasks[i].done()) {
                    self.tasks[i].await();
                }
            }
            return self.first_error~;
        }

        if (any_running) sleep_zero();
    }
}
