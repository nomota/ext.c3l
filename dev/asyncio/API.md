# asyncio API

### EventLoop

```
asyncio.run(coro)
asyncio.get_event_loop()
asyncio.set_event_loop(loop)
asyncio.new_event_loop()
asyncio.get_running_loop()
loop.call_soon(cb, arg)
loop.call_later(delay, cb, arg)
loop.call_at(when, callback, *args)


```

### Coroutines & Tasks

```
asyncio.create_task(coro)
asyncio.gather(*coros)
asyncio.as_completed(aws)
asyncio.wait(tasks)
asyncio.wait_for(coro, timeout)
asyncio.shield(coro)
asyncio.ensure_future(coro)
asyncio.current_task()
asyncio.all_tasks(loop=None)
asyncio.TaskGroup()
taskgroup.create_task(coro, arg)
```

### Sleeping & Scheduling

```
asyncio.sleep(delay)
asyncio.timeout(delay)
asyncio.timeout_at(when)
```

### Threads & Executors

```
asyncio.to_thread(func, *args)
loop.run_in_executor(executor, func, arg)
```

### Synchronization Primitives

```
asyncio.Lock()
asyncio.Event()
asyncio.Condition()
asyncio.Semaphore(n)
asyncio.BoundedSemaphore(n)
```

### Queues

```
asyncio.Queue(maxsize)
asyncio.LifoQueue(maxsize)
asyncio.PriorityQueue(maxsize)
```

### Networking

```
reader,writer = asyncio.open_connection(host, port)
reader.read(n)
reader.readline()
writer.get_extra_info('peername'|'sockname'
) -> (ip,port)
writer.get_extra_info('socket'|'ssl_object'
)
writer.write(data)
writer.drain()
writer.close()
writer.wait_closed()
server = asyncio.start_server(cb, host, port)
server.serve_forever()
server.sockets[0].getsockname() -> (ip,port)
asyncio.open_unix_connection(path)
asyncio.start_unix_server(cb, path)
transport,protocol = loop.create_connection(protocol, host, port)
dtrans,dproto = loop.create_datagram_endpoint(datagram_proto, host, port)
server = loop.create_server(protocol, host, port)
on_con_lost = loop.create_future()
asyncio.Protocol(msg, on_con_lost); // interface
asyncio.DatagramProtocol(msg, on_con_lost); // interface
proto.connection_made(transport)
transport.write(msg.encode())
proto.data_received(data)
dproto.datagram_received(data, addr)
dtrans.sendto(data,addr)
dproto.error_received(exc)
data.decode()
proto.connection_lost(exc)
on_con_lost.set_result(true)
on_con_lost.await()
transport.close()
```

### Future & Callbacks

```
asyncio.Future()
fut.set_result(val)
fut.set_exception(e)
fut.done()
fut.cancelled()
fut.result()
fut.exception()
fut.add_done_callback(fn)
asyncio.isfuture(obj)
asyncio.iscoroutine(obj)
asyncio.iscoroutinefunction(fn)
```

### Subprocess

```
asyncio.create_subprocess_exec(...)
asyncio.create_subprocess_shell(...)
```
