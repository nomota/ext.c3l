// netdb.h.c3

module c::netdb @if(!env::WIN32);

import c::netinet::in;
import c::sys::socket;

// ========== Function Declarations (Common) ==========

// Host database functions
extern fn HostEnt* gethostbyname(char* name);
extern fn HostEnt* gethostbyaddr(void* addr, uint len, int type);
extern fn int gethostbyname_r(char* name, HostEnt* ret, char* buf, sz buflen, HostEnt** result, int* h_errnop);
extern fn int gethostbyaddr_r(void* addr, uint len, int type, HostEnt* ret, char* buf, sz buflen, HostEnt** result, int* h_errnop);

// Service database functions
extern fn ServEnt* getservbyname(char* name, char* proto);
extern fn ServEnt* getservbyport(int port, char* proto);
extern fn int getservbyname_r(char* name, char* proto, ServEnt* ret, char* buf, sz buflen, ServEnt** result);
extern fn int getservbyport_r(int port, char* proto, ServEnt* ret, char* buf, sz buflen, ServEnt** result);

// Protocol database functions
extern fn ProtoEnt* getprotobyname(char* name);
extern fn ProtoEnt* getprotobynumber(int proto);
extern fn int getprotobyname_r(char* name, ProtoEnt* ret, char* buf, sz buflen, ProtoEnt** result);
extern fn int getprotobynumber_r(int proto, ProtoEnt* ret, char* buf, sz buflen, ProtoEnt** result);

// Modern address resolution (getaddrinfo/getnameinfo)
extern fn int getaddrinfo(char* node, char* service, AddrInfo* hints, AddrInfo** res);
extern fn void freeaddrinfo(AddrInfo* res);
extern fn char* gai_strerror(int errcode);
extern fn int getnameinfo(SockAddr* sa, uint salen, char* host, uint hostlen, char* serv, uint servlen, int flags);

// Host database iteration
extern fn HostEnt* gethostent();
extern fn void sethostent(int stayopen);
extern fn void endhostent();

// Service database iteration
extern fn ServEnt* getservent();
extern fn void setservent(int stayopen);
extern fn void endservent();

// Protocol database iteration
extern fn ProtoEnt* getprotoent();
extern fn void setprotoent(int stayopen);
extern fn void endprotoent();

// Network database functions
extern fn NetEnt* getnetbyname(char* name);
extern fn NetEnt* getnetbyaddr(uint net, int type);
extern fn NetEnt* getnetent();
extern fn void setnetent(int stayopen);
extern fn void endnetent();

// Error handling
extern fn void herror(char* s);
extern fn char* hstrerror(int err);

// ========== Common Type Definitions ==========

// Host entry structure
struct HostEnt {
    char* h_name;
    char** h_aliases;
    int h_addrtype;
    int h_length;
    char** h_addr_list;
}

// Service entry structure
struct ServEnt {
    char* s_name;
    char** s_aliases;
    int s_port;
    char* s_proto;
}

// Protocol entry structure
struct ProtoEnt {
    char* p_name;
    char** p_aliases;
    int p_proto;
}

// Network entry structure
struct NetEnt {
    char* n_name;
    char** n_aliases;
    int n_addrtype;
    uint n_net;
}

// Address info structure (for getaddrinfo)
struct AddrInfo {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    uint ai_addrlen;
    socket::SockAddr* ai_addr;
    char* ai_canonname;
    AddrInfo* ai_next;
}


// ========== Linux-specific Definitions ==========

module c::netdb @if(env::LINUX);

// Host errors
const int HOST_NOT_FOUND = 1;
const int TRY_AGAIN = 2;
const int NO_RECOVERY = 3;
const int NO_DATA = 4;
const int NO_ADDRESS = NO_DATA;

// Address info flags
const int AI_PASSIVE = 0x0001;
const int AI_CANONNAME = 0x0002;
const int AI_NUMERICHOST = 0x0004;
const int AI_V4MAPPED = 0x0008;
const int AI_ALL = 0x0010;
const int AI_ADDRCONFIG = 0x0020;
const int AI_IDN = 0x0040;
const int AI_CANONIDN = 0x0080;
const int AI_NUMERICSERV = 0x0400;

// Name info flags
const int NI_NUMERICHOST = 1;
const int NI_NUMERICSERV = 2;
const int NI_NOFQDN = 4;
const int NI_NAMEREQD = 8;
const int NI_DGRAM = 16;
const int NI_IDN = 32;

// Error codes for getaddrinfo
const int EAI_BADFLAGS = -1;
const int EAI_NONAME = -2;
const int EAI_AGAIN = -3;
const int EAI_FAIL = -4;
const int EAI_FAMILY = -6;
const int EAI_SOCKTYPE = -7;
const int EAI_SERVICE = -8;
const int EAI_MEMORY = -10;
const int EAI_SYSTEM = -11;
const int EAI_OVERFLOW = -12;
const int EAI_NODATA = -5;
const int EAI_ADDRFAMILY = -9;
const int EAI_INPROGRESS = -100;
const int EAI_CANCELED = -101;
const int EAI_NOTCANCELED = -102;
const int EAI_ALLDONE = -103;
const int EAI_INTR = -104;
const int EAI_IDN_ENCODE = -105;

// Socket types (from sys/socket.h)
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;

// Address families (from sys/socket.h)
const int AF_UNSPEC = 0;
const int AF_INET = 2;
const int AF_INET6 = 10;

// IP protocols (from netinet/in.h)
const int IPPROTO_TCP = 6;
const int IPPROTO_UDP = 17;

// Maximum sizes
const int NI_MAXHOST = 1025;
const int NI_MAXSERV = 32;

// ========== Darwin-specific Definitions ==========

module c::netdb @if(env::DARWIN);

// Host errors
const int HOST_NOT_FOUND = 1;
const int TRY_AGAIN = 2;
const int NO_RECOVERY = 3;
const int NO_DATA = 4;
const int NO_ADDRESS = NO_DATA;

// Address info flags
const int AI_PASSIVE = 0x00000001;
const int AI_CANONNAME = 0x00000002;
const int AI_NUMERICHOST = 0x00000004;
const int AI_NUMERICSERV = 0x00001000;
const int AI_V4MAPPED = 0x00000800;
const int AI_ALL = 0x00000100;
const int AI_ADDRCONFIG = 0x00000400;
const int AI_V4MAPPED_CFG = 0x00000200;
const int AI_DEFAULT = (AI_V4MAPPED_CFG | AI_ADDRCONFIG);
const int AI_UNUSABLE = 0x10000000;

// Name info flags
const int NI_NUMERICHOST = 0x00000002;
const int NI_NUMERICSERV = 0x00000008;
const int NI_NOFQDN = 0x00000001;
const int NI_NAMEREQD = 0x00000004;
const int NI_DGRAM = 0x00000010;
const int NI_WITHSCOPEID = 0x00000020;
const int NI_NUMERICSCOPE = 0x00000040;

// Error codes for getaddrinfo
const int EAI_ADDRFAMILY = 1;
const int EAI_AGAIN = 2;
const int EAI_BADFLAGS = 3;
const int EAI_FAIL = 4;
const int EAI_FAMILY = 5;
const int EAI_MEMORY = 6;
const int EAI_NODATA = 7;
const int EAI_NONAME = 8;
const int EAI_SERVICE = 9;
const int EAI_SOCKTYPE = 10;
const int EAI_SYSTEM = 11;
const int EAI_BADHINTS = 12;
const int EAI_PROTOCOL = 13;
const int EAI_OVERFLOW = 14;

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;

// Address families
const int AF_UNSPEC = 0;
const int AF_INET = 2;
const int AF_INET6 = 30;

// IP protocols
const int IPPROTO_TCP = 6;
const int IPPROTO_UDP = 17;

// Maximum sizes
const int NI_MAXHOST = 1025;
const int NI_MAXSERV = 32;

// ========== FreeBSD-specific Definitions ==========

module c::netdb @if(env::FREEBSD);

// Host errors
const int HOST_NOT_FOUND = 1;
const int TRY_AGAIN = 2;
const int NO_RECOVERY = 3;
const int NO_DATA = 4;
const int NO_ADDRESS = NO_DATA;

// Address info flags
const int AI_PASSIVE = 0x00000001;
const int AI_CANONNAME = 0x00000002;
const int AI_NUMERICHOST = 0x00000004;
const int AI_NUMERICSERV = 0x00000008;
const int AI_V4MAPPED = 0x00000800;
const int AI_ALL = 0x00000100;
const int AI_ADDRCONFIG = 0x00000400;

// Name info flags
const int NI_NUMERICHOST = 0x00000001;
const int NI_NUMERICSERV = 0x00000002;
const int NI_NOFQDN = 0x00000004;
const int NI_NAMEREQD = 0x00000008;
const int NI_DGRAM = 0x00000010;

// Error codes for getaddrinfo
const int EAI_ADDRFAMILY = 1;
const int EAI_AGAIN = 2;
const int EAI_BADFLAGS = 3;
const int EAI_FAIL = 4;
const int EAI_FAMILY = 5;
const int EAI_MEMORY = 6;
const int EAI_NODATA = 7;
const int EAI_NONAME = 8;
const int EAI_SERVICE = 9;
const int EAI_SOCKTYPE = 10;
const int EAI_SYSTEM = 11;
const int EAI_BADHINTS = 12;
const int EAI_PROTOCOL = 13;
const int EAI_OVERFLOW = 14;

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;

// Address families
const int AF_UNSPEC = 0;
const int AF_INET = 2;
const int AF_INET6 = 28;

// IP protocols
const int IPPROTO_TCP = 6;
const int IPPROTO_UDP = 17;

// Maximum sizes
const int NI_MAXHOST = 1025;
const int NI_MAXSERV = 32;

// ========== NetBSD-specific Definitions ==========

module c::netdb @if(env::NETBSD);

// Host errors
const int HOST_NOT_FOUND = 1;
const int TRY_AGAIN = 2;
const int NO_RECOVERY = 3;
const int NO_DATA = 4;
const int NO_ADDRESS = NO_DATA;

// Address info flags
const int AI_PASSIVE = 0x00000001;
const int AI_CANONNAME = 0x00000002;
const int AI_NUMERICHOST = 0x00000004;
const int AI_NUMERICSERV = 0x00000008;
const int AI_V4MAPPED = 0x00000800;
const int AI_ALL = 0x00000100;
const int AI_ADDRCONFIG = 0x00000400;

// Name info flags
const int NI_NUMERICHOST = 0x00000001;
const int NI_NUMERICSERV = 0x00000002;
const int NI_NOFQDN = 0x00000004;
const int NI_NAMEREQD = 0x00000008;
const int NI_DGRAM = 0x00000010;
const int NI_WITHSCOPEID = 0x00000020;
const int NI_NUMERICSCOPE = 0x00000040;

// Error codes for getaddrinfo
const int EAI_ADDRFAMILY = 1;
const int EAI_AGAIN = 2;
const int EAI_BADFLAGS = 3;
const int EAI_FAIL = 4;
const int EAI_FAMILY = 5;
const int EAI_MEMORY = 6;
const int EAI_NODATA = 7;
const int EAI_NONAME = 8;
const int EAI_SERVICE = 9;
const int EAI_SOCKTYPE = 10;
const int EAI_SYSTEM = 11;
const int EAI_BADHINTS = 12;
const int EAI_PROTOCOL = 13;
const int EAI_OVERFLOW = 14;
const int EAI_MAX = 15;

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;

// Address families
const int AF_UNSPEC = 0;
const int AF_INET = 2;
const int AF_INET6 = 24;

// IP protocols
const int IPPROTO_TCP = 6;
const int IPPROTO_UDP = 17;

// Maximum sizes
const int NI_MAXHOST = 1025;
const int NI_MAXSERV = 32;

// ========== OpenBSD-specific Definitions ==========

module c::netdb @if(env::OPENBSD);

// Host errors
const int HOST_NOT_FOUND = 1;
const int TRY_AGAIN = 2;
const int NO_RECOVERY = 3;
const int NO_DATA = 4;
const int NO_ADDRESS = NO_DATA;

// Address info flags
const int AI_PASSIVE = 0x00000001;
const int AI_CANONNAME = 0x00000002;
const int AI_NUMERICHOST = 0x00000004;
const int AI_NUMERICSERV = 0x00000008;
const int AI_V4MAPPED = 0x00000800;
const int AI_ALL = 0x00000100;
const int AI_ADDRCONFIG = 0x00000400;
const int AI_FQDN = 0x00000020;

// Name info flags
const int NI_NUMERICHOST = 0x00000001;
const int NI_NUMERICSERV = 0x00000002;
const int NI_NOFQDN = 0x00000004;
const int NI_NAMEREQD = 0x00000008;
const int NI_DGRAM = 0x00000010;

// Error codes for getaddrinfo
const int EAI_ADDRFAMILY = 1;
const int EAI_AGAIN = 2;
const int EAI_BADFLAGS = 3;
const int EAI_FAIL = 4;
const int EAI_FAMILY = 5;
const int EAI_MEMORY = 6;
const int EAI_NODATA = 7;
const int EAI_NONAME = 8;
const int EAI_SERVICE = 9;
const int EAI_SOCKTYPE = 10;
const int EAI_SYSTEM = 11;
const int EAI_BADHINTS = 12;
const int EAI_PROTOCOL = 13;
const int EAI_OVERFLOW = 14;

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;

// Address families
const int AF_UNSPEC = 0;
const int AF_INET = 2;
const int AF_INET6 = 24;

// IP protocols
const int IPPROTO_TCP = 6;
const int IPPROTO_UDP = 17;

// Maximum sizes
const int NI_MAXHOST = 1025;
const int NI_MAXSERV = 32;


