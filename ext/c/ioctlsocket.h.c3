// ioctlsocket.h.c3

module c::ioctlsocket @if(env::WIN32) @link("ws2_32");

import c::winsock2;

extern fn int ioctlsocket(winsock2::Socket s, long cmd, ulong* argp);

// Common commands.
//
// FIONBIO:
//   Enable/disable non-blocking mode.
//   argp = 1 -> non-blocking
//   argp = 0 -> blocking
//
// FIONREAD:
//   Get number of bytes available to read.
//   argp receives byte count.
//
// SIOCATMARK:
//   Check whether read pointer is at OOB mark.
//   argp receives non-zero if at mark.

const long FIONREAD   = 0x4004667F;
const long FIONBIO    = 0x8004667E;
const long SIOCATMARK = 0x40047307;

// eof