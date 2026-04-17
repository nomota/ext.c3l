// debug.c3

module ext::debug;

import std::io;
import c::stdlib;

macro void warn(String fmt, args...) @builtin
{
    io::printf("%s,%d: ", $$FILE, $$LINE);
    io::printfn(fmt, ...args);
}

macro @assert(expr, String msg) @builtin
{
    if (! debug) return;
    
    if (!(expr)) { warn("%s", msg); stdlib::exit(1); }
}

bool debug = true;

macro void set_debug(bool dbg) @public
{
    debug = dbg;
}

