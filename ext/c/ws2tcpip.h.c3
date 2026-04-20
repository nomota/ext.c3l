// ws2tcpip.h.c3

module c::ws2tcpip @if(env::WIN32);

import c::winsock2;

// Windows TCP/IP Specific API
// C3 mapping for ws2tcpip.h

// Common Windows types
alias Handle = void*;
alias DWord = uint;
alias Bool = int;
alias PVoid = void*;
alias ULong = uint;
alias UShort = ushort;
alias UChar = char;
alias Socket = uptr;

// IPv6 address structure
struct In6Addr {
    union {
        UChar[16] byte;
        UShort[8] word;
    }
}

// IPv4 address structure
struct InAddr {
    union {
        struct {
            UChar s_b1;
            UChar s_b2;
            UChar s_b3;
            UChar s_b4;
        } 
        struct {
            UShort s_w1;
            UShort s_w2;
        } 
        ULong s_addr;
    } 
}


// Address info structures
struct AddrInfo {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    ulong ai_addrlen;
    char* ai_canonname;
    winsock2::SockAddr* ai_addr;
    AddrInfo* ai_next;
}

struct AddrInfoEx {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    ulong ai_addrlen;
    char* ai_canonname;
    winsock2::SockAddr* ai_addr;
    void* ai_blob;
    ulong ai_bloblen;
    void* ai_provider;
    AddrInfoEx* ai_next;
}

struct AddrInfoW {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    ulong ai_addrlen;
    short* ai_canonname;
    winsock2::SockAddr* ai_addr;
    AddrInfoW* ai_next;
}

struct AddrInfoExW {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    ulong ai_addrlen;
    short* ai_canonname;
    winsock2::SockAddr* ai_addr;
    void* ai_blob;
    ulong ai_bloblen;
    void* ai_provider;
    AddrInfoExW* ai_next;
}

// IP multicast request structures
struct IpMreq {
    InAddr imr_multiaddr;
    InAddr imr_interface;
}

struct IpMreqSource {
    InAddr imr_multiaddr;
    InAddr imr_sourceaddr;
    InAddr imr_interface;
}

struct Ipv6Mreq {
    In6Addr ipv6mr_multiaddr;
    uint ipv6mr_interface;
}

struct GroupReq {
    ULong gr_interface;
    winsock2::SockAddrStorage gr_group;
}

struct GroupSourceReq {
    ULong gsr_interface;
    winsock2::SockAddrStorage gsr_group;
    winsock2::SockAddrStorage gsr_source;
}

// IP packet info structures
struct InPktinfo {
    InAddr ipi_addr;
    InAddr ipi_ifindex;
}

struct In6Pktinfo {
    In6Addr ipi6_addr;
    ULong ipi6_ifindex;
}

// TCP info structure
struct TcpInfoV0 {
    uint state;
    uint mss;
    ulong connection_time_ms;
    bool timestamps_enabled;
    ULong rtt_us;
    ULong min_rtt_us;
    ULong bytes_in_flight;
    ULong cwnd;
    ULong snd_wnd;
    ULong rcv_wnd;
    ULong rto_us;
    ULong snd_ssthresh;
    ULong rtt_var_us;
}

// Address info flags (AI_* constants)
const int AI_PASSIVE = 0x00000001;
const int AI_CANONNAME = 0x00000002;
const int AI_NUMERICHOST = 0x00000004;
const int AI_NUMERICSERV = 0x00000008;
const int AI_ALL = 0x00000100;
const int AI_ADDRCONFIG = 0x00000400;
const int AI_V4MAPPED = 0x00000800;
const int AI_NON_AUTHORITATIVE = 0x00004000;
const int AI_SECURE = 0x00008000;
const int AI_RETURN_PREFERRED_NAMES = 0x00010000;
const int AI_FQDN = 0x00020000;
const int AI_FILESERVER = 0x00040000;
const int AI_DISABLE_IDN_ENCODING = 0x00080000;
const uint AI_EXTENDED = 0x80000000;
const uint AI_RESOLUTION_HANDLE = 0x40000000;

// Name info flags (NI_* constants)
const int NI_NOFQDN = 0x01;
const int NI_NUMERICHOST = 0x02;
const int NI_NAMEREQD = 0x04;
const int NI_NUMERICSERV = 0x08;
const int NI_DGRAM = 0x10;
const int NI_MAXHOST = 1025;
const int NI_MAXSERV = 32;

// IPv6 option levels and names
const int IPPROTO_IPV6 = 41;

const int IPV6_HOPOPTS = 1;
const int IPV6_HDRINCL = 2;
const int IPV6_UNICAST_HOPS = 4;
const int IPV6_MULTICAST_IF = 9;
const int IPV6_MULTICAST_HOPS = 10;
const int IPV6_MULTICAST_LOOP = 11;
const int IPV6_ADD_MEMBERSHIP = 12;
const int IPV6_DROP_MEMBERSHIP = 13;
const int IPV6_JOIN_GROUP = 12;
const int IPV6_LEAVE_GROUP = 13;
const int IPV6_DONTFRAG = 14;
const int IPV6_PKTINFO = 19;
const int IPV6_HOPLIMIT = 21;
const int IPV6_CHECKSUM = 26;
const int IPV6_V6ONLY = 27;
const int IPV6_IFLIST = 28;
const int IPV6_ADD_IFLIST = 29;
const int IPV6_DEL_IFLIST = 30;
const int IPV6_UNICAST_IF = 31;
const int IPV6_RTHDR = 32;
const int IPV6_RECVRTHDR = 38;
const int IPV6_TCLASS = 39;
const int IPV6_RECVTCLASS = 40;
const int IPV6_ECN = 50;
const int IPV6_RECVECN = 50;
const int IPV6_PKTINFO_EX = 51;
const int IPV6_WFP_REDIRECT_RECORDS = 60;
const int IPV6_WFP_REDIRECT_CONTEXT = 70;
const int IPV6_MTU_DISCOVER = 71;
const int IPV6_MTU = 72;
const int IPV6_NRT_INTERFACE = 74;
const int IPV6_RECVERR = 75;
const int IPV6_USER_MTU = 76;

// IP option levels and names
const int IPPROTO_IP = 0;

const int IP_OPTIONS = 1;
const int IP_HDRINCL = 2;
const int IP_TOS = 3;
const int IP_TTL = 4;
const int IP_MULTICAST_IF = 9;
const int IP_MULTICAST_TTL = 10;
const int IP_MULTICAST_LOOP = 11;
const int IP_ADD_MEMBERSHIP = 12;
const int IP_DROP_MEMBERSHIP = 13;
const int IP_DONTFRAGMENT = 14;
const int IP_ADD_SOURCE_MEMBERSHIP = 15;
const int IP_DROP_SOURCE_MEMBERSHIP = 16;
const int IP_BLOCK_SOURCE = 17;
const int IP_UNBLOCK_SOURCE = 18;
const int IP_PKTINFO = 19;
const int IP_HOPLIMIT = 21;
const int IP_RECVTTL = 21;
const int IP_RECEIVE_BROADCAST = 22;
const int IP_RECVIF = 24;
const int IP_RECVDSTADDR = 25;
const int IP_IFLIST = 28;
const int IP_ADD_IFLIST = 29;
const int IP_DEL_IFLIST = 30;
const int IP_UNICAST_IF = 31;
const int IP_RTHDR = 32;
const int IP_RECVRTHDR = 38;
const int IP_TCLASS = 39;
const int IP_RECVTCLASS = 40;
const int IP_ORIGINAL_ARRIVAL_IF = 47;
const int IP_ECN = 50;
const int IP_RECVECN = 50;
const int IP_PKTINFO_EX = 51;
const int IP_WFP_REDIRECT_RECORDS = 60;
const int IP_WFP_REDIRECT_CONTEXT = 70;
const int IP_MTU_DISCOVER = 71;
const int IP_MTU = 73;
const int IP_NRT_INTERFACE = 74;
const int IP_RECVERR = 75;
const int IP_USER_MTU = 76;

// TCP options
const int TCP_NODELAY = 0x0001;
const int TCP_EXPEDITED_1122 = 0x0002;
const int TCP_KEEPALIVE = 3;
const int TCP_MAXSEG = 4;
const int TCP_MAXRT = 5;
const int TCP_STDURG = 6;
const int TCP_NOURG = 7;
const int TCP_ATMARK = 8;
const int TCP_NOSYNRETRIES = 9;
const int TCP_TIMESTAMPS = 10;
const int TCP_OFFLOAD_PREFERENCE = 11;
const int TCP_CONGESTION_ALGORITHM = 12;
const int TCP_DELAY_FIN_ACK = 13;
const int TCP_MAXRTMS = 14;
const int TCP_FASTOPEN = 15;
const int TCP_KEEPCNT = 16;
const int TCP_KEEPINTVL = 17;
const int TCP_FAIL_CONNECT_ON_ICMP_ERROR = 41;
const int TCP_ICMP_ERROR_INFO = 42;

// UDP options
const int UDP_NOCHECKSUM = 1;
const int UDP_SEND_MSG_SIZE = 2;
const int UDP_RECV_MAX_COALESCED_SIZE = 3;
const int UDP_CHECKSUM_COVERAGE = 20;

// Multicast source filter modes
const int MCAST_INCLUDE = 0;
const int MCAST_EXCLUDE = 1;

const int MCAST_JOIN_GROUP = 41;
const int MCAST_LEAVE_GROUP = 42;
const int MCAST_BLOCK_SOURCE = 43;
const int MCAST_UNBLOCK_SOURCE = 44;
const int MCAST_JOIN_SOURCE_GROUP = 45;
const int MCAST_LEAVE_SOURCE_GROUP = 46;

// Path MTU discovery options
const int IP_PMTUDISC_NOT_SET = 0;
const int IP_PMTUDISC_DO = 1;
const int IP_PMTUDISC_DONT = 2;
const int IP_PMTUDISC_PROBE = 3;
const int IP_PMTUDISC_MAX = 4;

// IPV6 MTU discovery
const int IPV6_PMTUDISC_NOT_SET = 0;
const int IPV6_PMTUDISC_DO = 1;
const int IPV6_PMTUDISC_DONT = 2;
const int IPV6_PMTUDISC_PROBE = 3;
const int IPV6_PMTUDISC_MAX = 4;

// Protection levels
const int PROTECTION_LEVEL_UNRESTRICTED = 10;
const int PROTECTION_LEVEL_EDGERESTRICTED = 20;
const int PROTECTION_LEVEL_RESTRICTED = 30;
const int PROTECTION_LEVEL_DEFAULT = 20;

// IPv6 address scope
const int ADDR_ANY = 0;

// Scope ID constants
const uint SCOPEID_UNSPECIFIED = 0;

// Address resolution functions
extern fn int getaddrinfo(
    char* node_name,
    char* service_name,
    AddrInfo* hints,
    AddrInfo** result
) @cname("getaddrinfo");

extern fn int getAddrInfoW(
    short* node_name,
    short* service_name,
    AddrInfoW* hints,
    AddrInfoW** result
) @cname("GetAddrInfoW");

extern fn int getAddrInfoExA(
    char* name,
    char* service_name,
    DWord namespace_id,
    void* namespace_provider_id,
    AddrInfoEx* hints,
    AddrInfoEx** result,
    void* timeout,
    void* overlapped,
    void* completion_routine,
    Handle* name_handle
) @cname("GetAddrInfoExA");

extern fn int getAddrInfoExW(
    short* name,
    short* service_name,
    DWord namespace_id,
    void* namespace_provider_id,
    AddrInfoExW* hints,
    AddrInfoExW** result,
    void* timeout,
    void* overlapped,
    void* completion_routine,
    Handle* name_handle
) @cname("GetAddrInfoExW");

extern fn int getAddrInfoExCancel(
    Handle* name_handle
) @cname("GetAddrInfoExCancel");

extern fn int getAddrInfoExOverflowSafeA(
    char* name,
    char* service_name,
    DWord namespace_id,
    void* namespace_provider_id,
    AddrInfoEx* hints,
    AddrInfoEx** result,
    void* timeout,
    void* overlapped,
    void* completion_routine,
    Handle* name_handle
) @cname("GetAddrInfoExOverflowSafeA");

extern fn int getAddrInfoExOverflowSafeW(
    short* name,
    short* service_name,
    DWord namespace_id,
    void* namespace_provider_id,
    AddrInfoExW* hints,
    AddrInfoExW** result,
    void* timeout,
    void* overlapped,
    void* completion_routine,
    Handle* name_handle
) @cname("GetAddrInfoExOverflowSafeW");

extern fn void freeaddrinfo(
    AddrInfo* ai
) @cname("freeaddrinfo");

extern fn void freeAddrInfoW(
    AddrInfoW* ai
) @cname("FreeAddrInfoW");

extern fn void freeAddrInfoEx(
    AddrInfoEx* ai
) @cname("FreeAddrInfoEx");

extern fn void freeAddrInfoExW(
    AddrInfoExW* ai
) @cname("FreeAddrInfoExW");

extern fn int getNameInfo(
    SockAddr* sa,
    int salen,
    char* host,
    DWord hostlen,
    char* serv,
    DWord servlen,
    int flags
) @cname("GetNameInfo");

extern fn int getNameInfoW(
    SockAddr* sa,
    int salen,
    short* host,
    DWord hostlen,
    short* serv,
    DWord servlen,
    int flags
) @cname("GetNameInfoW");

// IP address text conversion functions
extern fn int inet_pton(
    int family,
    char* src,
    PVoid dst
) @cname("inet_pton");

extern fn int inetPtonW(
    int family,
    short* src,
    PVoid dst
) @cname("InetPtonW");

extern fn char* inet_ntop(
    int family,
    PVoid src,
    char* dst,
    ulong size
) @cname("inet_ntop");

extern fn short* inetNtopW(
    int family,
    PVoid src,
    short* dst,
    ulong size
) @cname("InetNtopW");

// Hostname resolution
extern fn int setAddrInfoExA(
    char* name,
    char* service_name,
    winsock2::SockAddr* addresses,
    DWord address_count,
    void* blob,
    DWord blob_length,
    DWord flags,
    DWord namespace_id,
    void* namespace_provider_id,
    void* timeout,
    void* overlapped,
    void* completion_routine,
    Handle* name_handle
) @cname("SetAddrInfoExA");

extern fn int setAddrInfoExW(
    short* name,
    short* service_name,
    winsock2::SockAddr* addresses,
    DWord address_count,
    void* blob,
    DWord blob_length,
    DWord flags,
    DWord namespace_id,
    void* namespace_provider_id,
    void* timeout,
    void* overlapped,
    void* completion_routine,
    Handle* name_handle
) @cname("SetAddrInfoExW");

// IPv6 address testing macros (implemented as inline functions in C3)
extern fn bool in6_is_addr_unspecified(In6Addr* addr);
extern fn bool in6_is_addr_loopback(In6Addr* addr);
extern fn bool in6_is_addr_linklocal(In6Addr* addr);
extern fn bool in6_is_addr_sitelocal(In6Addr* addr);
extern fn bool in6_is_addr_v4mapped(In6Addr* addr);
extern fn bool in6_is_addr_v4compat(In6Addr* addr);
extern fn bool in6_is_addr_multicast(In6Addr* addr);
extern fn bool in6_is_addr_mc_nodelocal(In6Addr* addr);
extern fn bool in6_is_addr_mc_linklocal(In6Addr* addr);
extern fn bool in6_is_addr_mc_sitelocal(In6Addr* addr);
extern fn bool in6_is_addr_mc_orglocal(In6Addr* addr);
extern fn bool in6_is_addr_mc_global(In6Addr* addr);

// Well-known IPv6 addresses (as constants)
// In6Addr IN6ADDR_ANY_INIT
// In6Addr IN6ADDR_LOOPBACK_INIT

// IPv6 multicast scopes
const int IPV6_ADDR_MC_SCOPE_NODELOCAL = 0x01;
const int IPV6_ADDR_MC_SCOPE_LINKLOCAL = 0x02;
const int IPV6_ADDR_MC_SCOPE_SITELOCAL = 0x05;
const int IPV6_ADDR_MC_SCOPE_ORGLOCAL = 0x08;
const int IPV6_ADDR_MC_SCOPE_GLOBAL = 0x0E;

// TCP states (for TcpInfoV0)
const uint TCPSTATE_CLOSED = 0;
const uint TCPSTATE_LISTEN = 1;
const uint TCPSTATE_SYN_SENT = 2;
const uint TCPSTATE_SYN_RCVD = 3;
const uint TCPSTATE_ESTABLISHED = 4;
const uint TCPSTATE_FIN_WAIT_1 = 5;
const uint TCPSTATE_FIN_WAIT_2 = 6;
const uint TCPSTATE_CLOSE_WAIT = 7;
const uint TCPSTATE_CLOSING = 8;
const uint TCPSTATE_LAST_ACK = 9;
const uint TCPSTATE_TIME_WAIT = 10;
const uint TCPSTATE_MAX = 11;

// GetAddrInfoEx flags
const uint NS_ALL = 0;
const uint NS_DNS = 12;
const uint NS_NETBT = 13;
const uint NS_WINS = 14;
const uint NS_NLA = 15;
const uint NS_BTH = 16;
const uint NS_EMAIL = 37;
const uint NS_PNRPNAME = 38;
const uint NS_PNRPCLOUD = 39;

// Additional error codes
const int EAI_AGAIN = 11002;
const int EAI_BADFLAGS = 10022;
const int EAI_FAIL = 11003;
const int EAI_FAMILY = 10047;
const int EAI_MEMORY = 8;
const int EAI_NOSECURENAME = 11032;
const int EAI_NONAME = 11001;
const int EAI_SERVICE = 10109;
const int EAI_SOCKTYPE = 10044;
const int EAI_IPSECPOLICY = 11033;

// Windows-specific EAI errors
const int EAI_NODATA = 11001;

// sockaddr_in6 old structure definitions
const int SIN6_LEN = 28;

// IPv6 flow info masks
const uint IPV6_FLOWINFO_MASK = 0x0FFFFFFF;
const uint IPV6_FLOWLABEL_MASK = 0x000FFFFF;

// Special IPv4 addresses
const uint INADDR_ANY = 0x00000000;
const uint INADDR_LOOPBACK = 0x7F000001;
const uint INADDR_BROADCAST = 0xFFFFFFFF;
const uint INADDR_NONE = 0xFFFFFFFF;

// Maximum lengths
const int INET_ADDRSTRLEN = 22;
const int INET6_ADDRSTRLEN = 46;
