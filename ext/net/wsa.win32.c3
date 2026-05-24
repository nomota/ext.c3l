// wsa.win32.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::net::wsa @if(env::WIN32);

import c::errno;
import c::winsock2;
import ext::debug;

bool initialized = false;

fn void startup() @init
{
    if (initialized) return;
    
    winsock2::WSAData wsa_data;
    int rc = winsock2::wsaStartup(0x0202, &wsa_data);
    if (rc != 0)
    {
        warn("ERROR: wsaStartup failed: %d\n", rc);
        return;
    }
    initialized = true;
}

fn void cleanup() @finalizer
{
    if (initialized)
    {
        winsock2::wsaCleanup();
        initialized = false;
    }
}

// eof