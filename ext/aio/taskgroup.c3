// taskgroup.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio;

import std::collections::linkedlist;
import ext::mem;

struct TaskGroup
{
    EventLoop* loop;
    LinkedList{Task*} tasks;
    bool closed;
}

fn void TaskGroup.init(&self, EventLoop* loop = null)
{
    if (loop == null)
    {
        loop = current_loop()!!;
    }
    *self = {
        .loop = loop,
        .closed = false,
    };

    self.tasks.init(localmem);
}

fn void TaskGroup.free(&self)
{
    self.tasks.free();

    self.loop = null;
    self.closed = true;
}

fn Task*? TaskGroup.spawn(&self, TaskFn entry, void* arg = null)
{
    if (self.closed) return INVALID_STATE~;
    if (self.loop == null) return INVALID_STATE~;

    Task* task = self.loop.spawn_joinable(entry, arg)!;

    self.tasks.push(task);

    return task;
}

fn void TaskGroup.cancel_all(&self)
{
    foreach (task: self.tasks.array_view())
    {
        if (task == null) continue;

        if (task.state == TASK_DONE) continue;
        if (task.state == TASK_CANCELLED) continue;
        if (task.state == TASK_FAILED) continue;

        task.cancel();
    }
}

fn void? TaskGroup.join_all(&self)
{
    fault first_err = NONE;

    while (!self.tasks.is_empty())
    {
        Task* task = self.tasks.pop_first()!!;

        if (task == null) continue;

        if (catch err = task.join())
        {
            if (first_err == NONE) first_err = err;
        }
    }

    if (first_err != NONE) return first_err~;
}

fn void? TaskGroup.cancel_and_join(&self)
{
    self.cancel_all();

    if (catch err = self.join_all())
    {
        if (err == CANCELLED) return;
        return err~;
    }
}

// eof