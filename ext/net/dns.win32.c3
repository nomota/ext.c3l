// dns.win32.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::net::dns @if(env::WIN32);

import c::stdio;
import c::stdlib;
import c::string;
import c::errno;
import c::winsock2;
import c::ws2tcpip;
import std::collections::list;
import ext::net::wsa;

fn fault gai_to_fault(int err) @local
{
    switch (err)
    {
        case winsock2::WSATRY_AGAIN:
            return errno::E_AGAIN;

        case winsock2::WSAEINVAL:
            return errno::E_INVALID_ARG;

        case winsock2::WSANO_RECOVERY:
            return errno::E_IO;

        case winsock2::WSAEAFNOSUPPORT:
            return errno::E_ADDR_FAMILY_NOT_SUPPORTED;

        case winsock2::WSA_NOT_ENOUGH_MEMORY:
            return errno::E_NO_MEMORY;

        case winsock2::WSAHOST_NOT_FOUND:
        case winsock2::WSANO_DATA:
            return errno::E_NOT_FOUND;

        case winsock2::WSATYPE_NOT_FOUND:
            return errno::E_NO_PROTO_OPTION;

        case winsock2::WSAESOCKTNOSUPPORT:
            return errno::E_SOCKET_TYPE_NOT_SUPPORTED;

        case winsock2::WSAEINTR:
            return errno::E_INTERRUPTED;

        default:
            return errno::errno_to_fault((long)err);
    }
}

// Caller should properly free returned List and contained String values.
fn List{String}? get_addrinfo(Allocator allocx, String host)
{
    if (host.len == 0) return errno::E_INVALID_ARG~;
    if (host.len >= 256) return errno::E_NAME_TOO_LONG~;

    wsa::startup()!;

    char[256] hostname;
    if (host.len > 0) string::memcpy(&hostname[0], host.ptr, host.len);
    hostname[host.len] = 0;

    ws2tcpip::AddrInfo hints = {};
    hints.ai_family = winsock2::AF_UNSPEC;
    hints.ai_socktype = winsock2::SOCK_STREAM;

    ws2tcpip::AddrInfo* result = null;
    int r = ws2tcpip::getaddrinfo(&hostname[0], null, &hints, &result);
    if (r != 0) return gai_to_fault(r)~;

    defer
    {
        ws2tcpip::freeaddrinfo(result);
    }

    List{String} ips;
    ips.init(allocx);

    for (ws2tcpip::AddrInfo* rp = result; rp != null; rp = rp.ai_next)
    {
        void* addr = null;

        if (rp.ai_family == winsock2::AF_INET)
        {
            winsock2::SockAddrIn* ipv4 = (winsock2::SockAddrIn*)rp.ai_addr;
            addr = &ipv4.sin_addr;
        }
        else if (rp.ai_family == winsock2::AF_INET6)
        {
            winsock2::SockAddrIn6* ipv6 = (winsock2::SockAddrIn6*)rp.ai_addr;
            addr = &ipv6.sin6_addr;
        }
        else
        {
            continue;
        }

        char[ws2tcpip::INET6_ADDRSTRLEN] ipstr;
        char* p = ws2tcpip::inet_ntop(rp.ai_family, addr, &ipstr[0], ipstr.len);
        if (p == null) continue;

        ips.push(((ZString)&ipstr[0]).str_view().copy(allocx));
    }

    return ips;
}

// eof