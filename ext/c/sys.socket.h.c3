// sys.socket.h.c3

module c::sys::socket @if(!env::WIN32);

// Main socket functions
extern fn int socket(int domain, int type, int protocol);
extern fn int bind(int sockfd, SockAddr* addr, SockLen addrlen);
extern fn int listen(int sockfd, int backlog);
extern fn int accept(int sockfd, SockAddr* addr, SockLen* addrlen);
extern fn int connect(int sockfd, SockAddr* addr, SockLen addrlen);

// Data transfer
extern fn sz send(int sockfd, void* buf, sz len, int flags);
extern fn sz recv(int sockfd, void* buf, sz len, int flags);
extern fn sz sendto(int sockfd, void* buf, sz len, int flags, SockAddr* dest_addr, SockLen addrlen);
extern fn sz recvfrom(int sockfd, void* buf, sz len, int flags, SockAddr* src_addr, SockLen* addrlen);
extern fn sz sendmsg(int sockfd, MsgHdr* msg, int flags);
extern fn sz recvmsg(int sockfd, MsgHdr* msg, int flags);

// Socket options
extern fn int setsockopt(int sockfd, int level, int optname, void* optval, SockLen optlen);
extern fn int getsockopt(int sockfd, int level, int optname, void* optval, SockLen* optlen);

// Socket control
extern fn int shutdown(int sockfd, int how);
extern fn int socketpair(int domain, int type, int protocol, int[2] sv);

// Name/address functions
extern fn int getsockname(int sockfd, SockAddr* addr, SockLen* addrlen);
extern fn int getpeername(int sockfd, SockAddr* addr, SockLen* addrlen);

// Control message macros (helper functions)
macro sz cmsg_align(sz len) => (((len) + sz::size - 1) & ~(sz::size - 1));
macro sz cmsg_space(sz len) => (cmsg_align(CMsgHdr::size) + cmsg_align(len));
macro sz cmsg_len(sz len) => (cmsg_align(CMsgHdr::size) + (len));
macro CMsgHdr* cmsg_firsthdr(MsgHdr* msg) => ((msg).msg_controllen >= CMsgHdr::size ? (CMsgHdr*)(msg).msg_control : (CMsgHdr*)0);
macro char* cmsg_data(CMsgHdr* cmsg) => ((char*)(cmsg) + cmsg_align(CMsgHdr::size));

alias SockLen = uint;

module c::sys::socket @if(env::LINUX);

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;
const int SOCK_RDM = 4;
const int SOCK_SEQPACKET = 5;
const int SOCK_DCCP = 6;
const int SOCK_PACKET = 10;

// Socket type flags (Linux)
const int SOCK_CLOEXEC = 0x80000;
const int SOCK_NONBLOCK = 0x800;

// Address families
const int AF_UNSPEC = 0;
const int AF_UNIX = 1;
const int AF_LOCAL = 1;
const int AF_INET = 2;
const int AF_AX25 = 3;
const int AF_IPX = 4;
const int AF_APPLETALK = 5;
const int AF_NETROM = 6;
const int AF_BRIDGE = 7;
const int AF_ATMPVC = 8;
const int AF_X25 = 9;
const int AF_INET6 = 10;
const int AF_ROSE = 11;
const int AF_DECNET = 12;
const int AF_NETBEUI = 13;
const int AF_SECURITY = 14;
const int AF_KEY = 15;
const int AF_NETLINK = 16;
const int AF_ROUTE = AF_NETLINK;
const int AF_PACKET = 17;
const int AF_ASH = 18;
const int AF_ECONET = 19;
const int AF_ATMSVC = 20;
const int AF_RDS = 21;
const int AF_SNA = 22;
const int AF_IRDA = 23;
const int AF_PPPOX = 24;
const int AF_WANPIPE = 25;
const int AF_LLC = 26;
const int AF_CAN = 29;
const int AF_TIPC = 30;
const int AF_BLUETOOTH = 31;
const int AF_IUCV = 32;
const int AF_RXRPC = 33;
const int AF_ISDN = 34;
const int AF_PHONET = 35;
const int AF_IEEE802154 = 36;
const int AF_CAIF = 37;
const int AF_ALG = 38;
const int AF_NFC = 39;
const int AF_VSOCK = 40;
const int AF_KCM = 41;
const int AF_QIPCRTR = 42;
const int AF_SMC = 43;
const int AF_XDP = 44;
const int AF_MAX = 45;

// Protocol families
const int PF_UNSPEC = AF_UNSPEC;
const int PF_UNIX = AF_UNIX;
const int PF_LOCAL = AF_LOCAL;
const int PF_INET = AF_INET;
const int PF_INET6 = AF_INET6;
const int PF_NETLINK = AF_NETLINK;
const int PF_PACKET = AF_PACKET;
const int PF_BLUETOOTH = AF_BLUETOOTH;

// Socket level
const int SOL_SOCKET = 1;

// Socket options
const int SO_DEBUG = 1;
const int SO_REUSEADDR = 2;
const int SO_TYPE = 3;
const int SO_ERROR = 4;
const int SO_DONTROUTE = 5;
const int SO_BROADCAST = 6;
const int SO_SNDBUF = 7;
const int SO_RCVBUF = 8;
const int SO_SNDBUFFORCE = 32;
const int SO_RCVBUFFORCE = 33;
const int SO_KEEPALIVE = 9;
const int SO_OOBINLINE = 10;
const int SO_NO_CHECK = 11;
const int SO_PRIORITY = 12;
const int SO_LINGER = 13;
const int SO_BSDCOMPAT = 14;
const int SO_REUSEPORT = 15;
const int SO_PASSCRED = 16;
const int SO_PEERCRED = 17;
const int SO_RCVLOWAT = 18;
const int SO_SNDLOWAT = 19;
const int SO_RCVTIMEO = 20;
const int SO_SNDTIMEO = 21;
const int SO_ACCEPTCONN = 30;
const int SO_PEERSEC = 31;
const int SO_PASSSEC = 34;
const int SO_TIMESTAMPNS = 35;
const int SO_MARK = 36;
const int SO_TIMESTAMPING = 37;
const int SO_PROTOCOL = 38;
const int SO_DOMAIN = 39;
const int SO_RXQ_OVFL = 40;
const int SO_WIFI_STATUS = 41;
const int SO_PEEK_OFF = 42;
const int SO_NOFCS = 43;
const int SO_LOCK_FILTER = 44;
const int SO_SELECT_ERR_QUEUE = 45;
const int SO_BUSY_POLL = 46;
const int SO_MAX_PACING_RATE = 47;
const int SO_BPF_EXTENSIONS = 48;
const int SO_INCOMING_CPU = 49;
const int SO_ATTACH_BPF = 50;
const int SO_ATTACH_REUSEPORT_CBPF = 51;
const int SO_ATTACH_REUSEPORT_EBPF = 52;
const int SO_CNX_ADVICE = 53;

// Message flags
const int MSG_OOB = 0x01;
const int MSG_PEEK = 0x02;
const int MSG_DONTROUTE = 0x04;
const int MSG_TRYHARD = 0x04;
const int MSG_CTRUNC = 0x08;
const int MSG_PROBE = 0x10;
const int MSG_TRUNC = 0x20;
const int MSG_DONTWAIT = 0x40;
const int MSG_EOR = 0x80;
const int MSG_WAITALL = 0x100;
const int MSG_FIN = 0x200;
const int MSG_SYN = 0x400;
const int MSG_CONFIRM = 0x800;
const int MSG_RST = 0x1000;
const int MSG_ERRQUEUE = 0x2000;
const int MSG_NOSIGNAL = 0x4000;
const int MSG_MORE = 0x8000;
const int MSG_WAITFORONE = 0x10000;
const int MSG_BATCH = 0x40000;
const int MSG_FASTOPEN = 0x20000000;
const int MSG_CMSG_CLOEXEC = 0x40000000;

// Shutdown how
const int SHUT_RD = 0;
const int SHUT_WR = 1;
const int SHUT_RDWR = 2;

// Socket address structures
struct SockAddr {
    ushort sa_family;
    char[14] sa_data;
}

struct SockAddrStorage {
    ushort ss_family;
    ulong __ss_align;
    char[128 - ushort::size - ulong::size] __ss_padding;
}

// I/O vector
struct IoVec {
    void* iov_base;
    sz iov_len;
}

// Message header
struct MsgHdr {
    void* msg_name;
    SockLen msg_namelen;
    IoVec* msg_iov;
    sz msg_iovlen;
    void* msg_control;
    sz msg_controllen;
    int msg_flags;
}

// Multiple message header (for sendmmsg/recvmmsg)
struct MMsgHdr {
    MsgHdr msg_hdr;
    uint msg_len;
}

// Control message header
struct CMsgHdr {
    sz cmsg_len;
    int cmsg_level;
    int cmsg_type;
}

// User credentials structure
struct UCred {
    uint pid;
    uint uid;
    uint gid;
}

// Linger structure
struct Linger {
    int l_onoff;
    int l_linger;
}

// Linux-specific functions
extern fn int accept4(int sockfd, SockAddr* addr, SockLen* addrlen, int flags);
extern fn int sendmmsg(int sockfd, MMsgHdr* msgvec, uint vlen, int flags);
extern fn int recvmmsg(int sockfd, MMsgHdr* msgvec, uint vlen, int flags, TimeSpec* timeout);

// TimeSpec for recvmmsg timeout
struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

// Socket control message types
const int SCM_RIGHTS = 0x01;
const int SCM_CREDENTIALS = 0x02;
const int SCM_SECURITY = 0x03;




module c::sys::socket @if(env::DARWIN);

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;
const int SOCK_RDM = 4;
const int SOCK_SEQPACKET = 5;

// Address families
const int AF_UNSPEC = 0;
const int AF_UNIX = 1;
const int AF_LOCAL = AF_UNIX;
const int AF_INET = 2;
const int AF_IMPLINK = 3;
const int AF_PUP = 4;
const int AF_CHAOS = 5;
const int AF_NS = 6;
const int AF_ISO = 7;
const int AF_OSI = AF_ISO;
const int AF_ECMA = 8;
const int AF_DATAKIT = 9;
const int AF_CCITT = 10;
const int AF_SNA = 11;
const int AF_DECNET = 12;
const int AF_DLI = 13;
const int AF_LAT = 14;
const int AF_HYLINK = 15;
const int AF_APPLETALK = 16;
const int AF_ROUTE = 17;
const int AF_LINK = 18;
const int AF_XTP = 19;
const int AF_COIP = 20;
const int AF_CNT = 21;
const int AF_RTIP = 22;
const int AF_IPX = 23;
const int AF_SIP = 24;
const int AF_PIP = 25;
const int AF_NDRV = 27;
const int AF_ISDN = 28;
const int AF_E164 = AF_ISDN;
const int AF_KEY = 29;
const int AF_INET6 = 30;
const int AF_NATM = 31;
const int AF_SYSTEM = 32;
const int AF_NETBIOS = 33;
const int AF_PPP = 34;
const int AF_RESERVED_36 = 36;
const int AF_IEEE80211 = 37;
const int AF_UTUN = 38;
const int AF_VSOCK = 40;
const int AF_MAX = 41;

// Protocol families
const int PF_UNSPEC = AF_UNSPEC;
const int PF_LOCAL = AF_LOCAL;
const int PF_UNIX = AF_UNIX;
const int PF_INET = AF_INET;
const int PF_INET6 = AF_INET6;
const int PF_ROUTE = AF_ROUTE;
const int PF_KEY = AF_KEY;
const int PF_SYSTEM = AF_SYSTEM;
const int PF_NDRV = AF_NDRV;
const int PF_VSOCK = AF_VSOCK;

// Socket level
const int SOL_SOCKET = 0xffff;

// Socket options
const int SO_DEBUG = 0x0001;
const int SO_ACCEPTCONN = 0x0002;
const int SO_REUSEADDR = 0x0004;
const int SO_KEEPALIVE = 0x0008;
const int SO_DONTROUTE = 0x0010;
const int SO_BROADCAST = 0x0020;
const int SO_USELOOPBACK = 0x0040;
const int SO_LINGER = 0x0080;
const int SO_OOBINLINE = 0x0100;
const int SO_REUSEPORT = 0x0200;
const int SO_TIMESTAMP = 0x0400;
const int SO_TIMESTAMP_MONOTONIC = 0x0800;
const int SO_ACCEPTFILTER = 0x1000;
const int SO_DONTTRUNC = 0x2000;
const int SO_WANTMORE = 0x4000;
const int SO_WANTOOBFLAG = 0x8000;
const int SO_SNDBUF = 0x1001;
const int SO_RCVBUF = 0x1002;
const int SO_SNDLOWAT = 0x1003;
const int SO_RCVLOWAT = 0x1004;
const int SO_SNDTIMEO = 0x1005;
const int SO_RCVTIMEO = 0x1006;
const int SO_ERROR = 0x1007;
const int SO_TYPE = 0x1008;
const int SO_LABEL = 0x1010;
const int SO_PEERLABEL = 0x1011;
const int SO_NREAD = 0x1020;
const int SO_NKE = 0x1021;
const int SO_NOSIGPIPE = 0x1022;
const int SO_NOADDRERR = 0x1023;
const int SO_NWRITE = 0x1024;
const int SO_REUSESHAREUID = 0x1025;
const int SO_NOTIFYCONFLICT = 0x1026;

// Message flags
const int MSG_OOB = 0x1;
const int MSG_PEEK = 0x2;
const int MSG_DONTROUTE = 0x4;
const int MSG_EOR = 0x8;
const int MSG_TRUNC = 0x10;
const int MSG_CTRUNC = 0x20;
const int MSG_WAITALL = 0x40;
const int MSG_DONTWAIT = 0x80;
const int MSG_EOF = 0x100;
const int MSG_WAITSTREAM = 0x200;
const int MSG_FLUSH = 0x400;
const int MSG_HOLD = 0x800;
const int MSG_SEND = 0x1000;
const int MSG_HAVEMORE = 0x2000;
const int MSG_RCVMORE = 0x4000;
const int MSG_NEEDSA = 0x10000;
const int MSG_NOSIGNAL = 0x80000;

// Shutdown how
const int SHUT_RD = 0;
const int SHUT_WR = 1;
const int SHUT_RDWR = 2;

// Socket address length type (Darwin uses uint8_t for sa_len)
struct SockAddr {
    char sa_len;
    char sa_family;
    char[14] sa_data;
}

struct SockAddrStorage {
    char ss_len;
    char ss_family;
    char[6] __ss_pad1;
    long __ss_align;
    char[128 - 2 - 6 - long::size] __ss_pad2;
}

// I/O vector
struct IoVec {
    void* iov_base;
    sz iov_len;
}

// Message header
struct MsgHdr {
    void* msg_name;
    SockLen msg_namelen;
    IoVec* msg_iov;
    int msg_iovlen;
    void* msg_control;
    SockLen msg_controllen;
    int msg_flags;
}

// Control message header
struct CMsgHdr {
    SockLen cmsg_len;
    int cmsg_level;
    int cmsg_type;
}

// Linger structure
struct Linger {
    int l_onoff;
    int l_linger;
}

// Accept filter (Darwin-specific)
struct AcceptFilter {
    char[16] af_name;
    char[240] af_arg;
}

// Socket control message types
const int SCM_RIGHTS = 0x01;
const int SCM_TIMESTAMP = 0x02;
const int SCM_CREDS = 0x03;
const int SCM_TIMESTAMP_MONOTONIC = 0x04;




module c::sys::socket @if(env::FREEBSD);

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;
const int SOCK_RDM = 4;
const int SOCK_SEQPACKET = 5;

// Socket type flags
const int SOCK_CLOEXEC = 0x10000000;
const int SOCK_NONBLOCK = 0x20000000;

// Address families
const int AF_UNSPEC = 0;
const int AF_UNIX = 1;
const int AF_LOCAL = AF_UNIX;
const int AF_INET = 2;
const int AF_IMPLINK = 3;
const int AF_PUP = 4;
const int AF_CHAOS = 5;
const int AF_NETBIOS = 6;
const int AF_ISO = 7;
const int AF_OSI = AF_ISO;
const int AF_ECMA = 8;
const int AF_DATAKIT = 9;
const int AF_CCITT = 10;
const int AF_SNA = 11;
const int AF_DECNET = 12;
const int AF_DLI = 13;
const int AF_LAT = 14;
const int AF_HYLINK = 15;
const int AF_APPLETALK = 16;
const int AF_ROUTE = 17;
const int AF_LINK = 18;
const int AF_XTP = 19;
const int AF_COIP = 20;
const int AF_CNT = 21;
const int AF_RTIP = 22;
const int AF_IPX = 23;
const int AF_SIP = 24;
const int AF_PIP = 25;
const int AF_ISDN = 26;
const int AF_E164 = AF_ISDN;
const int AF_KEY = 27;
const int AF_INET6 = 28;
const int AF_NATM = 29;
const int AF_ATM = 30;
const int AF_NETGRAPH = 32;
const int AF_SLOW = 33;
const int AF_SCLUSTER = 34;
const int AF_ARP = 35;
const int AF_BLUETOOTH = 36;
const int AF_IEEE80211 = 37;
const int AF_INET_SDP = 40;
const int AF_INET6_SDP = 42;
const int AF_HYPERV = 43;
const int AF_MAX = 43;

// Protocol families
const int PF_UNSPEC = AF_UNSPEC;
const int PF_LOCAL = AF_LOCAL;
const int PF_UNIX = AF_UNIX;
const int PF_INET = AF_INET;
const int PF_INET6 = AF_INET6;
const int PF_ROUTE = AF_ROUTE;
const int PF_LINK = AF_LINK;
const int PF_KEY = AF_KEY;
const int PF_NETGRAPH = AF_NETGRAPH;
const int PF_BLUETOOTH = AF_BLUETOOTH;

// Socket level
const int SOL_SOCKET = 0xffff;

// Socket options
const int SO_DEBUG = 0x00000001;
const int SO_ACCEPTCONN = 0x00000002;
const int SO_REUSEADDR = 0x00000004;
const int SO_KEEPALIVE = 0x00000008;
const int SO_DONTROUTE = 0x00000010;
const int SO_BROADCAST = 0x00000020;
const int SO_USELOOPBACK = 0x00000040;
const int SO_LINGER = 0x00000080;
const int SO_OOBINLINE = 0x00000100;
const int SO_REUSEPORT = 0x00000200;
const int SO_TIMESTAMP = 0x00000400;
const int SO_NOSIGPIPE = 0x00000800;
const int SO_ACCEPTFILTER = 0x00001000;
const int SO_BINTIME = 0x00002000;
const int SO_NO_OFFLOAD = 0x00004000;
const int SO_NO_DDP = 0x00008000;
const int SO_REUSEPORT_LB = 0x00010000;
const int SO_SNDBUF = 0x1001;
const int SO_RCVBUF = 0x1002;
const int SO_SNDLOWAT = 0x1003;
const int SO_RCVLOWAT = 0x1004;
const int SO_SNDTIMEO = 0x1005;
const int SO_RCVTIMEO = 0x1006;
const int SO_ERROR = 0x1007;
const int SO_TYPE = 0x1008;
const int SO_LABEL = 0x1009;
const int SO_PEERLABEL = 0x1010;
const int SO_LISTENQLIMIT = 0x1011;
const int SO_LISTENQLEN = 0x1012;
const int SO_LISTENINCQLEN = 0x1013;
const int SO_SETFIB = 0x1014;
const int SO_USER_COOKIE = 0x1015;
const int SO_PROTOCOL = 0x1016;
const int SO_PROTOTYPE = SO_PROTOCOL;
const int SO_DOMAIN = 0x1019;

// Message flags
const int MSG_OOB = 0x00001;
const int MSG_PEEK = 0x00002;
const int MSG_DONTROUTE = 0x00004;
const int MSG_EOR = 0x00008;
const int MSG_TRUNC = 0x00010;
const int MSG_CTRUNC = 0x00020;
const int MSG_WAITALL = 0x00040;
const int MSG_DONTWAIT = 0x00080;
const int MSG_EOF = 0x00100;
const int MSG_NOTIFICATION = 0x02000;
const int MSG_NBIO = 0x04000;
const int MSG_COMPAT = 0x08000;
const int MSG_CMSG_CLOEXEC = 0x40000;
const int MSG_NOSIGNAL = 0x20000;

// Shutdown how
const int SHUT_RD = 0;
const int SHUT_WR = 1;
const int SHUT_RDWR = 2;

// Socket address structures (FreeBSD has sa_len)
struct SockAddr {
    char sa_len;
    char sa_family;
    char[14] sa_data;
}

struct SockAddrStorage {
    char ss_len;
    char ss_family;
    char[6] __ss_pad1;
    long __ss_align;
    char[128 - 2 - 6 - long::size] __ss_pad2;
}

// I/O vector
struct IoVec {
    void* iov_base;
    sz iov_len;
}

// Message header
struct MsgHdr {
    void* msg_name;
    SockLen msg_namelen;
    IoVec* msg_iov;
    int msg_iovlen;
    void* msg_control;
    SockLen msg_controllen;
    int msg_flags;
}

// Control message header
struct CMsgHdr {
    SockLen cmsg_len;
    int cmsg_level;
    int cmsg_type;
}

// Linger structure
struct Linger {
    int l_onoff;
    int l_linger;
}

// Accept filter
struct AcceptFilter {
    char[16] af_name;
    char[240] af_arg;
}

// Socket control message types
const int SCM_RIGHTS = 0x01;
const int SCM_TIMESTAMP = 0x02;
const int SCM_CREDS = 0x03;
const int SCM_BINTIME = 0x04;
const int SCM_REALTIME = 0x05;
const int SCM_MONOTONIC = 0x06;

// FreeBSD-specific: User credentials
struct Cmsgcred {
    uint cmcred_pid;
    uint cmcred_uid;
    uint cmcred_euid;
    uint cmcred_gid;
    short cmcred_ngroups;
    uint[16] cmcred_groups;
}

// FreeBSD-specific functions
extern fn int accept4(int sockfd, SockAddr* addr, SockLen* addrlen, int flags);
extern fn int bindat(int fd, int sockfd, SockAddr* addr, SockLen addrlen);
extern fn int connectat(int fd, int sockfd, SockAddr* addr, SockLen addrlen);




module c::sys::socket @if(env::NETBSD);

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;
const int SOCK_RDM = 4;
const int SOCK_SEQPACKET = 5;
const int SOCK_CONN_DGRAM = 6;

// Socket type flags
const int SOCK_CLOEXEC = 0x10000000;
const int SOCK_NONBLOCK = 0x20000000;
const int SOCK_NOSIGPIPE = 0x40000000;

// Address families
const int AF_UNSPEC = 0;
const int AF_UNIX = 1;
const int AF_LOCAL = AF_UNIX;
const int AF_INET = 2;
const int AF_IMPLINK = 3;
const int AF_PUP = 4;
const int AF_CHAOS = 5;
const int AF_NS = 6;
const int AF_ISO = 7;
const int AF_OSI = AF_ISO;
const int AF_ECMA = 8;
const int AF_DATAKIT = 9;
const int AF_CCITT = 10;
const int AF_SNA = 11;
const int AF_DECNET = 12;
const int AF_DLI = 13;
const int AF_LAT = 14;
const int AF_HYLINK = 15;
const int AF_APPLETALK = 16;
const int AF_ROUTE = 17;
const int AF_LINK = 18;
const int AF_COIP = 20;
const int AF_CNT = 21;
const int AF_IPX = 23;
const int AF_INET6 = 24;
const int AF_ISDN = 26;
const int AF_E164 = AF_ISDN;
const int AF_NATM = 27;
const int AF_ARP = 28;
const int AF_BLUETOOTH = 31;
const int AF_IEEE80211 = 32;
const int AF_MPLS = 33;
const int AF_ETHIP = 34;
const int AF_MAX = 35;

// Protocol families
const int PF_UNSPEC = AF_UNSPEC;
const int PF_LOCAL = AF_LOCAL;
const int PF_UNIX = AF_UNIX;
const int PF_INET = AF_INET;
const int PF_INET6 = AF_INET6;
const int PF_ROUTE = AF_ROUTE;
const int PF_LINK = AF_LINK;
const int PF_BLUETOOTH = AF_BLUETOOTH;

// Socket level
const int SOL_SOCKET = 0xffff;

// Socket options
const int SO_DEBUG = 0x0001;
const int SO_ACCEPTCONN = 0x0002;
const int SO_REUSEADDR = 0x0004;
const int SO_KEEPALIVE = 0x0008;
const int SO_DONTROUTE = 0x0010;
const int SO_BROADCAST = 0x0020;
const int SO_USELOOPBACK = 0x0040;
const int SO_LINGER = 0x0080;
const int SO_OOBINLINE = 0x0100;
const int SO_REUSEPORT = 0x0200;
const int SO_NOSIGPIPE = 0x0800;
const int SO_ACCEPTFILTER = 0x1000;
const int SO_TIMESTAMP = 0x2000;
const int SO_SNDBUF = 0x1001;
const int SO_RCVBUF = 0x1002;
const int SO_SNDLOWAT = 0x1003;
const int SO_RCVLOWAT = 0x1004;
const int SO_SNDTIMEO = 0x1005;
const int SO_RCVTIMEO = 0x1006;
const int SO_ERROR = 0x1007;
const int SO_TYPE = 0x1008;
const int SO_OVERFLOWED = 0x1009;
const int SO_NOHEADER = 0x100a;

// Message flags
const int MSG_OOB = 0x0001;
const int MSG_PEEK = 0x0002;
const int MSG_DONTROUTE = 0x0004;
const int MSG_EOR = 0x0008;
const int MSG_TRUNC = 0x0010;
const int MSG_CTRUNC = 0x0020;
const int MSG_WAITALL = 0x0040;
const int MSG_DONTWAIT = 0x0080;
const int MSG_BCAST = 0x0100;
const int MSG_MCAST = 0x0200;
const int MSG_NOSIGNAL = 0x0400;
const int MSG_CMSG_CLOEXEC = 0x0800;
const int MSG_NBIO = 0x1000;

// Shutdown how
const int SHUT_RD = 0;
const int SHUT_WR = 1;
const int SHUT_RDWR = 2;

// Socket address structures (NetBSD has sa_len)
struct SockAddr {
    char sa_len;
    char sa_family;
    char[14] sa_data;
}

struct SockAddrStorage {
    char ss_len;
    char ss_family;
    char[6] __ss_pad1;
    long __ss_align;
    char[128 - 2 - 6 - long::size] __ss_pad2;
}

// I/O vector
struct IoVec {
    void* iov_base;
    sz iov_len;
}

// Message header
struct MsgHdr {
    void* msg_name;
    SockLen msg_namelen;
    IoVec* msg_iov;
    int msg_iovlen;
    void* msg_control;
    SockLen msg_controllen;
    int msg_flags;
}

// Control message header
struct CMsgHdr {
    SockLen cmsg_len;
    int cmsg_level;
    int cmsg_type;
}

// Linger structure
struct Linger {
    int l_onoff;
    int l_linger;
}

// Accept filter
struct AcceptFilter {
    char[16] af_name;
    char[240] af_arg;
}

// Socket control message types
const int SCM_RIGHTS = 0x01;
const int SCM_TIMESTAMP = 0x02;
const int SCM_CREDS = 0x04;

// NetBSD-specific functions
extern fn int accept4(int sockfd, SockAddr* addr, SockLen* addrlen, int flags);




module c::sys::socket @if(env::OPENBSD);

// Socket types
const int SOCK_STREAM = 1;
const int SOCK_DGRAM = 2;
const int SOCK_RAW = 3;
const int SOCK_RDM = 4;
const int SOCK_SEQPACKET = 5;

// Socket type flags
const int SOCK_CLOEXEC = 0x8000;
const int SOCK_NONBLOCK = 0x4000;
const int SOCK_DNS = 0x1000;

// Address families
const int AF_UNSPEC = 0;
const int AF_UNIX = 1;
const int AF_LOCAL = AF_UNIX;
const int AF_INET = 2;
const int AF_IMPLINK = 3;
const int AF_PUP = 4;
const int AF_CHAOS = 5;
const int AF_NS = 6;
const int AF_ISO = 7;
const int AF_OSI = AF_ISO;
const int AF_ECMA = 8;
const int AF_DATAKIT = 9;
const int AF_CCITT = 10;
const int AF_SNA = 11;
const int AF_DECNET = 12;
const int AF_DLI = 13;
const int AF_LAT = 14;
const int AF_HYLINK = 15;
const int AF_APPLETALK = 16;
const int AF_ROUTE = 17;
const int AF_LINK = 18;
const int AF_XTP = 19;
const int AF_COIP = 20;
const int AF_CNT = 21;
const int AF_RTIP = 22;
const int AF_IPX = 23;
const int AF_INET6 = 24;
const int AF_PIP = 25;
const int AF_ISDN = 26;
const int AF_E164 = AF_ISDN;
const int AF_NATM = 27;
const int AF_ENCAP = 28;
const int AF_SIP = 29;
const int AF_KEY = 30;
const int AF_BLUETOOTH = 32;
const int AF_MPLS = 33;
const int AF_MAX = 36;

// Protocol families
const int PF_UNSPEC = AF_UNSPEC;
const int PF_LOCAL = AF_LOCAL;
const int PF_UNIX = AF_UNIX;
const int PF_INET = AF_INET;
const int PF_INET6 = AF_INET6;
const int PF_ROUTE = AF_ROUTE;
const int PF_LINK = AF_LINK;
const int PF_KEY = AF_KEY;
const int PF_BLUETOOTH = AF_BLUETOOTH;
const int PF_MPLS = AF_MPLS;

// Socket level
const int SOL_SOCKET = 0xffff;

// Socket options
const int SO_DEBUG = 0x0001;
const int SO_ACCEPTCONN = 0x0002;
const int SO_REUSEADDR = 0x0004;
const int SO_KEEPALIVE = 0x0008;
const int SO_DONTROUTE = 0x0010;
const int SO_BROADCAST = 0x0020;
const int SO_USELOOPBACK = 0x0040;
const int SO_LINGER = 0x0080;
const int SO_OOBINLINE = 0x0100;
const int SO_REUSEPORT = 0x0200;
const int SO_TIMESTAMP = 0x0800;
const int SO_BINDANY = 0x1000;
const int SO_ZEROIZE = 0x2000;
const int SO_SNDBUF = 0x1001;
const int SO_RCVBUF = 0x1002;
const int SO_SNDLOWAT = 0x1003;
const int SO_RCVLOWAT = 0x1004;
const int SO_SNDTIMEO = 0x1005;
const int SO_RCVTIMEO = 0x1006;
const int SO_ERROR = 0x1007;
const int SO_TYPE = 0x1008;
const int SO_NETPROC = 0x1020;
const int SO_RTABLE = 0x1021;
const int SO_PEERCRED = 0x1022;
const int SO_SPLICE = 0x1023;
const int SO_DOMAIN = 0x1024;
const int SO_PROTOCOL = 0x1025;

// Message flags
const int MSG_OOB = 0x0001;
const int MSG_PEEK = 0x0002;
const int MSG_DONTROUTE = 0x0004;
const int MSG_EOR = 0x0008;
const int MSG_TRUNC = 0x0010;
const int MSG_CTRUNC = 0x0020;
const int MSG_WAITALL = 0x0040;
const int MSG_DONTWAIT = 0x0080;
const int MSG_BCAST = 0x0100;
const int MSG_MCAST = 0x0200;
const int MSG_NOSIGNAL = 0x0400;
const int MSG_CMSG_CLOEXEC = 0x0800;

// Shutdown how
const int SHUT_RD = 0;
const int SHUT_WR = 1;
const int SHUT_RDWR = 2;

// Socket address structures (OpenBSD has sa_len)
struct SockAddr {
    char sa_len;
    char sa_family;
    char[14] sa_data;
}

struct SockAddrStorage {
    char ss_len;
    char ss_family;
    char[6] __ss_pad1;
    long __ss_align;
    char[256 - 2 - 6 - long::size] __ss_pad2;
}

// I/O vector
struct IoVec {
    void* iov_base;
    sz iov_len;
}

// Message header
struct MsgHdr {
    void* msg_name;
    SockLen msg_namelen;
    IoVec* msg_iov;
    uint msg_iovlen;
    void* msg_control;
    SockLen msg_controllen;
    int msg_flags;
}

// Control message header
struct CMsgHdr {
    SockLen cmsg_len;
    int cmsg_level;
    int cmsg_type;
}

// Linger structure
struct Linger {
    int l_onoff;
    int l_linger;
}

// Socket control message types
const int SCM_RIGHTS = 0x01;
const int SCM_TIMESTAMP = 0x04;

// OpenBSD-specific: Socket splicing
struct Splice {
    int sp_fd;
    long sp_max;
    Timeval sp_idle;
}

struct Timeval {
    long tv_sec;
    long tv_usec;
}

// OpenBSD-specific functions
extern fn int accept4(int sockfd, SockAddr* addr, SockLen* addrlen, int flags);
extern fn int getrtable();
extern fn int setrtable(int rtableid);
 
