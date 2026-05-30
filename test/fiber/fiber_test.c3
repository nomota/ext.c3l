
module fiber_test;

import ext::fiber;
import std::io;

Fiber*[3] coro;

macro void warn(String fmt, args...)
{
  io::printf("%s,%s: ", $$FILE, $$LINE); io::printfn(fmt, ...args);
}

int global_x;
int global_y;
fn void _init(Fiber* coro, int param_x, int param_y) 
{
  global_x = param_x;
  global_y = param_y;

  warn("switch to coro");
  fiber::switch_to(coro);
  warn("resume in _init");
}

fn void coroutine() 
{
  int param_x = global_x;
  int param_y = global_y;
  
  warn("coroutine(%d, %d)", param_x, param_y);
  
  warn("yield() from %d,%d", param_x, param_y);
  fiber::yield();
  warn("resume in coroutine");

  warn("coroutine(%d, %d)", param_x, param_y);
  
  warn("yield() from %d,%d", param_x, param_y);
  fiber::yield();
  warn("resume in coroutine");
  
  warn("done() from %d,%d", param_x, param_y);

  fiber::done(); // coroutine should always finish as this 
}

fn void main()
{
  warn("Fiber parameterized function example");

  coro[0] = fiber::active();
  coro[1] = fiber::create(&coroutine)!!;
  coro[2] = fiber::create(&coroutine)!!;

  _init(coro[1], 1, 2);
  _init(coro[2], 4, 8);

  warn("goto coro[2]");
  fiber::switch_to(coro[2]);
  warn("resume in root");
  
  warn("goto coro[1]");
  fiber::switch_to(coro[1]);
  warn("resume in root");
 
  // fiber::yield();
  warn("goto coro[1]");
  fiber::switch_to(coro[1]);
  warn("resume in root");
 
  warn("done");
}
