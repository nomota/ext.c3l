// dns.posix.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::net::dns @if(env::POSIX);

import c::stdio;
import c::stdlib;
import c::string;
import c::netdb;
import c::errno;
import c::arpa::inet;
import c::netinet::in;
import c::sys::socket;
import std::collections::list;

fn fault gai_to_fault(int err) @local
{
    switch (err)
    {
        case netdb::EAI_AGAIN:
            return errno::E_AGAIN;

        case netdb::EAI_BADFLAGS:
            return errno::E_INVALID_ARG;

        case netdb::EAI_FAIL:
            return errno::E_IO;

        case netdb::EAI_FAMILY:
            return errno::E_ADDR_FAMILY_NOT_SUPPORTED;

        case netdb::EAI_MEMORY:
            return errno::E_NO_MEMORY;

        case netdb::EAI_NONAME:
            return errno::E_NOT_FOUND;

        case netdb::EAI_SERVICE:
            return errno::E_NO_PROTO_OPTION;

        case netdb::EAI_SOCKTYPE:
            return errno::E_SOCKET_TYPE_NOT_SUPPORTED;

        case netdb::EAI_SYSTEM:
            return errno::get_fault();

        default:
            return errno::E_GENERAL_ERR;
    }
}

// Caller should properly free returned List and contained String values.
fn List{String}? get_addrinfo(Allocator allocx, String host)
{
    if (host.len == 0) return errno::E_INVALID_ARG~;
    if (host.len >= 256) return errno::E_NAME_TOO_LONG~;

    char[256] hostname;
    if (host.len > 0) string::memcpy(&hostname[0], host.ptr, host.len);
    hostname[host.len] = 0;

    netdb::AddrInfo hints = {};
    hints.ai_family = socket::AF_UNSPEC;
    hints.ai_socktype = socket::SOCK_STREAM;

    netdb::AddrInfo* result = null;
    int r = netdb::getaddrinfo(&hostname[0], null, &hints, &result);
    if (r != 0) return gai_to_fault(r)~;

    List{String} ips;
    ips.init(allocx);

    defer
    {
        netdb::freeaddrinfo(result);
    }

    for (netdb::AddrInfo* rp = result; rp != null; rp = rp.ai_next)
    {
        void* addr = null;

        if (rp.ai_family == socket::AF_INET)
        {
            in::SockAddrIn* ipv4 = (in::SockAddrIn*)rp.ai_addr;
            addr = &ipv4.sin_addr;
        }
        else if (rp.ai_family == socket::AF_INET6)
        {
            in::SockAddrIn6* ipv6 = (in::SockAddrIn6*)rp.ai_addr;
            addr = &ipv6.sin6_addr;
        }
        else
        {
            continue;
        }

        char[inet::INET6_ADDRSTRLEN] ipstr;
        char* p = inet::inet_ntop(rp.ai_family, addr, &ipstr[0], ipstr.len);
        if (p == null) continue;

        ips.push(((ZString)&ipstr[0]).str_view().copy(allocx));
    }

    return ips;
}

// eof