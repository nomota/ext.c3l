// debug.c3

module ext::debug;

import std::io;
import c::stdlib;

macro void warn(String fmt, args...) @builtin
{
    io::printf("%s,%d: ", $$FILE, $$LINE);
    io::printfn(fmt, ...args);
}

macro @assert(#expr, String msg = "assert failed") @builtin
{
  if (debug) {
    if (!(#expr)) {
        warn("%s", msg);
        stdlib::exit(1); // die without stack trace
    }
  }
}

// Compile-time gated leak reporter: wraps body in @assert_leak only in debug builds.
macro @debug_leak(; @body) @builtin
{
    if (debug) {
        @assert_leak() { @body(); };
    } else {
        @body();
    }
}

bool debug = true; // default

macro void set_debug(bool dbg) @public
{
    debug = dbg;
}

