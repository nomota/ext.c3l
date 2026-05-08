import ext::aio;
import ext::debug;

fn void worker1()
{
    warn("worker1: A");
    aio::yield();
    aio::sleep(500)!!;

    warn("worker1: B");
}

fn void worker2()
{
    warn("worker2: A");
    aio::yield();
    aio::sleep(100)!!;

    warn("worker2: B");
}

fn void main_task()
{
    EventLoop* loop = aio::current_loop();

    Task* t1 = loop.spawn(&worker1);
    Task* t2 = loop.spawn(&worker2);

    t1.join()!!;
    t2.join()!!;

    warn("main done");
}

fn void main()
{
    aio::run(&main_task);
}
