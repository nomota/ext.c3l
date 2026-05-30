// arpa.inet.h.c3

module c::arpa::inet @if(env::LINUX);

import c::netinet::in;

// ========== Function Declarations ==========

// Byte order conversion functions
extern fn ushort htons(ushort hostshort);
extern fn uint htonl(uint hostlong);
extern fn ushort ntohs(ushort netshort);
extern fn uint ntohl(uint netlong);

// IPv4 address conversion functions (legacy)
extern fn uint inet_addr(char* cp);
extern fn char* inet_ntoa(InAddr in_addr);
extern fn int inet_aton(char* cp, InAddr* inp);

// IPv4/IPv6 address conversion functions (modern)
extern fn int inet_pton(int af, char* src, void* dst);
extern fn char* inet_ntop(int af, void* src, char* dst, uint size);

// Network/host address conversion (legacy)
extern fn uint inet_network(char* cp);
extern fn InAddr inet_makeaddr(uint net, uint host);
extern fn uint inet_lnaof(InAddr in_addr);
extern fn uint inet_netof(InAddr in_addr);

// Additional Linux functions
extern fn int inet_aton_r(char* cp, InAddr* inp);

// ========== Type Definitions ==========

// Address family constants (from netinet/in.h)
const int AF_INET = 2;
const int AF_INET6 = 10;

// ========== Constants ==========

// Maximum length of presentation form addresses
const int INET_ADDRSTRLEN = 16;   // xxx.xxx.xxx.xxx\0
const int INET6_ADDRSTRLEN = 46;  // xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxx.xxx.xxx.xxx\0




module c::arpa::inet @if(env::DARWIN);

import c::netinet::in;

// ========== Function Declarations ==========

// Byte order conversion functions
extern fn ushort htons(ushort hostshort);
extern fn uint htonl(uint hostlong);
extern fn ushort ntohs(ushort netshort);
extern fn uint ntohl(uint netlong);

// IPv4 address conversion functions (legacy)
extern fn uint inet_addr(char* cp);
extern fn char* inet_ntoa(InAddr in_addr);
extern fn int inet_aton(char* cp, InAddr* inp);

// IPv4/IPv6 address conversion functions (modern)
extern fn int inet_pton(int af, char* src, void* dst);
extern fn char* inet_ntop(int af, void* src, char* dst, uint size);

// Network/host address conversion (legacy)
extern fn uint inet_network(char* cp);
extern fn InAddr inet_makeaddr(uint net, uint host);
extern fn uint inet_lnaof(InAddr in_addr);
extern fn uint inet_netof(InAddr in_addr);

// Darwin-specific functions
extern fn char* inet_net_ntop(int af, void* src, int bits, char* dst, sz size);
extern fn int inet_net_pton(int af, char* src, void* dst, sz size);
extern fn uint inet_nsap_addr(char* ascii, char* binary, int maxlen);
extern fn char* inet_nsap_ntoa(int binlen, char* binary, char* ascii);

// ========== Type Definitions ==========

// Address family constants (from netinet/in.h)
const int AF_INET = 2;
const int AF_INET6 = 30;

// ========== Constants ==========

// Maximum length of presentation form addresses
const int INET_ADDRSTRLEN = 16;
const int INET6_ADDRSTRLEN = 46;




module c::arpa::inet @if(env::FREEBSD);

import c::netinet::in;

// ========== Function Declarations ==========

// Byte order conversion functions
extern fn ushort htons(ushort hostshort);
extern fn uint htonl(uint hostlong);
extern fn ushort ntohs(ushort netshort);
extern fn uint ntohl(uint netlong);

// IPv4 address conversion functions (legacy)
extern fn uint inet_addr(char* cp);
extern fn char* inet_ntoa(InAddr in_addr);
extern fn int inet_aton(char* cp, InAddr* inp);

// IPv4/IPv6 address conversion functions (modern)
extern fn int inet_pton(int af, char* src, void* dst);
extern fn char* inet_ntop(int af, void* src, char* dst, uint size);

// Network/host address conversion (legacy)
extern fn uint inet_network(char* cp);
extern fn InAddr inet_makeaddr(uint net, uint host);
extern fn uint inet_lnaof(InAddr in_addr);
extern fn uint inet_netof(InAddr in_addr);

// FreeBSD-specific functions
extern fn char* inet_net_ntop(int af, void* src, int bits, char* dst, sz size);
extern fn int inet_net_pton(int af, char* src, void* dst, sz size);
extern fn uint inet_nsap_addr(char* ascii, char* binary, int maxlen);
extern fn char* inet_nsap_ntoa(int binlen, char* binary, char* ascii);
extern fn char* inet_cidr_ntop(int af, void* src, int bits, char* dst, sz size);
extern fn int inet_cidr_pton(int af, char* src, void* dst, int* bits);

// ========== Type Definitions ==========

// Address family constants (from netinet/in.h)
const int AF_INET = 2;
const int AF_INET6 = 28;

// ========== Constants ==========

// Maximum length of presentation form addresses
const int INET_ADDRSTRLEN = 16;
const int INET6_ADDRSTRLEN = 46;




module c::arpa::inet @if(env::NETBSD);

import c::netinet::in;

// ========== Function Declarations ==========

// Byte order conversion functions
extern fn ushort htons(ushort hostshort);
extern fn uint htonl(uint hostlong);
extern fn ushort ntohs(ushort netshort);
extern fn uint ntohl(uint netlong);

// IPv4 address conversion functions (legacy)
extern fn uint inet_addr(char* cp);
extern fn char* inet_ntoa(InAddr in_addr);
extern fn int inet_aton(char* cp, InAddr* inp);

// IPv4/IPv6 address conversion functions (modern)
extern fn int inet_pton(int af, char* src, void* dst);
extern fn char* inet_ntop(int af, void* src, char* dst, uint size);

// Network/host address conversion (legacy)
extern fn uint inet_network(char* cp);
extern fn InAddr inet_makeaddr(uint net, uint host);
extern fn uint inet_lnaof(InAddr in_addr);
extern fn uint inet_netof(InAddr in_addr);

// NetBSD-specific functions
extern fn char* inet_net_ntop(int af, void* src, int bits, char* dst, sz size);
extern fn int inet_net_pton(int af, char* src, void* dst, sz size);
extern fn uint inet_nsap_addr(char* ascii, char* binary, int maxlen);
extern fn char* inet_nsap_ntoa(int binlen, char* binary, char* ascii);
extern fn char* inet_cidr_ntop(int af, void* src, int bits, char* dst, sz size);
extern fn int inet_cidr_pton(int af, char* src, void* dst, int* bits);

// NetBSD-specific: presentation format with scope
extern fn int inet_pton_scope(int af, char* src, void* dst, uint* scope);

// ========== Type Definitions ==========

// Address family constants (from netinet/in.h)
const int AF_INET = 2;
const int AF_INET6 = 24;

// ========== Constants ==========

// Maximum length of presentation form addresses
const int INET_ADDRSTRLEN = 16;
const int INET6_ADDRSTRLEN = 46;




module c::arpa::inet @if(env::OPENBSD);

import c::netinet::in;

// ========== Function Declarations ==========

// Byte order conversion functions
extern fn ushort htons(ushort hostshort);
extern fn uint htonl(uint hostlong);
extern fn ushort ntohs(ushort netshort);
extern fn uint ntohl(uint netlong);

// IPv4 address conversion functions (legacy)
extern fn uint inet_addr(char* cp);
extern fn char* inet_ntoa(InAddr in_addr);
extern fn int inet_aton(char* cp, InAddr* inp);

// IPv4/IPv6 address conversion functions (modern)
extern fn int inet_pton(int af, char* src, void* dst);
extern fn char* inet_ntop(int af, void* src, char* dst, uint size);

// Network/host address conversion (legacy)
extern fn uint inet_network(char* cp);
extern fn InAddr inet_makeaddr(uint net, uint host);
extern fn uint inet_lnaof(InAddr in_addr);
extern fn uint inet_netof(InAddr in_addr);

// OpenBSD-specific functions
extern fn char* inet_net_ntop(int af, void* src, int bits, char* dst, sz size);
extern fn int inet_net_pton(int af, char* src, void* dst, sz size);
extern fn uint inet_nsap_addr(char* ascii, char* binary, int maxlen);
extern fn char* inet_nsap_ntoa(int binlen, char* binary, char* ascii);

// ========== Type Definitions ==========

// Address family constants (from netinet/in.h)
const int AF_INET = 2;
const int AF_INET6 = 24;

// ========== Constants ==========

// Maximum length of presentation form addresses
const int INET_ADDRSTRLEN = 16;
const int INET6_ADDRSTRLEN = 46;


