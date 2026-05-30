// mswsock.h.c3

module c::mswsock @if(env::WIN32);

import c::winbase;
import c::guiddef;
import c::winsock2;

// ============================================================
// winsock2::Socket options
// ============================================================

const int SO_CONNDATA                = 0x7000;
const int SO_CONNDATALEN             = 0x7001;
const int SO_CONNOPT                 = 0x7002;
const int SO_CONNOPTLEN              = 0x7003;
const int SO_DISCDATA                = 0x7004;
const int SO_DISCDATALEN             = 0x7005;
const int SO_DISCOPT                 = 0x7006;
const int SO_DISCOPTLEN              = 0x7007;
const int SO_OPENTYPE                = 0x7008;
const int SO_SYNCHRONOUS_ALERT       = 0x10;
const int SO_SYNCHRONOUS_NONALERT    = 0x20;
const int SO_MAXDG                   = 0x7009;
const int SO_MAXPATHDG               = 0x700A;
const int SO_UPDATE_ACCEPT_CONTEXT   = 0x700B;
const int SO_CONNECT_TIME            = 0x700C;
const int SO_UPDATE_CONNECT_CONTEXT  = 0x7010;

const int TCP_BSDURGENT              = 0x7000;

// ============================================================
// TransmitFile flags
// ============================================================

const uint TF_DISCONNECT             = 0x01;
const uint TF_REUSE_SOCKET           = 0x02;
const uint TF_WRITE_BEHIND           = 0x04;
const uint TF_USE_DEFAULT_WORKER     = 0x00;
const uint TF_USE_SYSTEM_THREAD      = 0x10;
const uint TF_USE_KERNEL_APC         = 0x20;

// ============================================================
// TransmitPackets flags
// ============================================================

const uint TP_ELEMENT_MEMORY         = 1;
const uint TP_ELEMENT_FILE           = 2;
const uint TP_ELEMENT_EOP            = 4;
const uint TP_DISCONNECT             = TF_DISCONNECT;
const uint TP_REUSE_SOCKET           = TF_REUSE_SOCKET;

// ============================================================
// Structures
// ============================================================

struct TransmitFileBuffers @cname("TRANSMIT_FILE_BUFFERS") {
    void* head;
    uint  headLength;
    void* tail;
    uint  tailLength;
}

alias PTransmitFileBuffers  = TransmitFileBuffers*;
alias LPTransmitFileBuffers = TransmitFileBuffers*;

// TRANSMIT_PACKETS_ELEMENT
struct TransmitPacketsElement @cname("TRANSMIT_PACKETS_ELEMENT") {
    uint  dwElFlags;
    uint  cLength;
    union {
        struct {
            long  nFileOffset;   // LARGE_INTEGER -> long (int64)
            void* hFile;         // HANDLE
        }
        void* pBuffer;
    }
}

alias PTransmitPacketsElement  = TransmitPacketsElement*;
alias LPTransmitPacketsElement = TransmitPacketsElement*;

// WSACMSGHDR / CMSGHDR
struct WsaCmsgHdr @cname("WSACMSGHDR") {
    sz cmsg_len;
    int cmsg_level;
    int cmsg_type;
}

alias PWsaCmsgHdr = WsaCmsgHdr*;
alias PCmsgHdr    = WsaCmsgHdr*;
alias LPCmsgHdr   = WsaCmsgHdr*;

// WSAMSG
struct WsaMsg @cname("WSAMSG") {
    winsock2::SockAddr* name;
    int       namelen;
    winsock2::WSABuf*   lpBuffers;
    uint      dwBufferCount;
    winsock2::WSABuf    control;
    uint      dwFlags;
}

alias PWsaMsg  = WsaMsg*;
alias LPWsaMsg = WsaMsg*;


const guiddef::Guid WSAID_TRANSMITFILE         = { 0xb5367df0, 0xcbac, 0x11cf, { 0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92 } };
const guiddef::Guid WSAID_ACCEPTEX             = { 0xb5367df1, 0xcbac, 0x11cf, { 0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92 } };
const guiddef::Guid WSAID_GETACCEPTEXSOCKADDRS = { 0xb5367df2, 0xcbac, 0x11cf, { 0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92 } };
const guiddef::Guid WSAID_TRANSMITPACKETS      = { 0xd9689da0, 0x1f90, 0x11d3, { 0x99, 0x71, 0x00, 0xc0, 0x4f, 0x68, 0xc8, 0x76 } };
const guiddef::Guid WSAID_CONNECTEX            = { 0x25a207b9, 0xddf3, 0x4660, { 0x8e, 0xe9, 0x76, 0xe5, 0x8c, 0x74, 0x06, 0x3e } };
const guiddef::Guid WSAID_DISCONNECTEX         = { 0x7fda2e11, 0x8630, 0x436f, { 0xa0, 0x31, 0xf5, 0x36, 0xa6, 0xee, 0xc1, 0x57 } };
const guiddef::Guid WSAID_WSARECVMSG           = { 0xf689d7c8, 0x6f1f, 0x436b, { 0x8a, 0x53, 0x5b, 0x08, 0xd7, 0x8f, 0x0b, 0xce } };
const guiddef::Guid WSAID_WSASENDMSG           = { 0xa441e712, 0x754f, 0x43ca, { 0x84, 0xa7, 0x0d, 0xee, 0x44, 0xcf, 0x60, 0x6d } };

alias WsaOverlappedCompletionRoutine = void*;

alias LPFnTransmitFile = fn bool(
    winsock2::Socket hSocket,
    void*  hFile,
    uint   nNumberOfBytesToWrite,
    uint   nNumberOfBytesPerSend,
    winbase::Overlapped*           lpOverlapped,
    TransmitFileBuffers*  lpTransmitBuffers,
    uint   dwReserved
);

alias LPFnAcceptEx = fn bool(
    winsock2::Socket sListenSocket,
    winsock2::Socket sAcceptSocket,
    void*  lpOutputBuffer,
    uint   dwReceiveDataLength,
    uint   dwLocalAddressLength,
    uint   dwRemoteAddressLength,
    uint*  lpdwBytesReceived,
    winbase::Overlapped* lpOverlapped
);

alias LPFnGetAcceptExSockaddrs = fn void(
    void*      lpOutputBuffer,
    uint       dwReceiveDataLength,
    uint       dwLocalAddressLength,
    uint       dwRemoteAddressLength,
    winsock2::SockAddr** localSockaddr,
    int*       localSockaddrLength,
    winsock2::SockAddr** remoteSockaddr,
    int*       remoteSockaddrLength
);

alias LPFnTransmitPackets = fn bool(
    winsock2::Socket                  hSocket,
    TransmitPacketsElement* lpPacketArray,
    uint                    nElementCount,
    uint                    nSendSize,
    winbase::Overlapped*             lpOverlapped,
    uint                    dwFlags
);

alias LPFnConnectEx = fn bool(
    winsock2::Socket      s,
    winsock2::SockAddr*   name,
    int         namelen,
    void*       lpSendBuffer,
    uint        dwSendDataLength,
    uint*       lpdwBytesSent,
    winbase::Overlapped* lpOverlapped
);

alias LPFnDisconnectEx = fn bool(
    winsock2::Socket      hSocket,
    winbase::Overlapped* lpOverlapped,
    uint        dwFlags,
    uint        dwReserved
);

alias LPFnWsaRecvMsg = fn int(
    winsock2::Socket                       s,
    WsaMsg*                      lpMsg,
    uint*                        lpdwNumberOfBytesRecvd,
    winbase::Overlapped*                  lpOverlapped,
    WsaOverlappedCompletionRoutine lpCompletionRoutine
);

alias LPFnWsaSendMsg = fn int(
    winsock2::Socket                       s,
    WsaMsg*                      lpMsg,
    uint                         dwFlags,
    uint*                        lpNumberOfBytesSent,
    winbase::Overlapped*                  lpOverlapped,
    WsaOverlappedCompletionRoutine lpCompletionRoutine
);

// ============================================================
// Exported functions  (mswsock.lib / ws2_32.lib)
// ============================================================

extern fn bool transmitFile(Socket hSocket, void* hFile, uint nNumberOfBytesToWrite, uint nNumberOfBytesPerSend, winbase::Overlapped* lpOverlapped, TransmitFileBuffers* lpTransmitBuffers, uint dwReserved) @cname("TransmitFile");

extern fn bool acceptEx(Socket sListenSocket, winsock2::Socket sAcceptSocket, void* lpOutputBuffer, uint dwReceiveDataLength, uint dwLocalAddressLength, uint dwRemoteAddressLength, uint* lpdwBytesReceived, winbase::Overlapped* lpOverlapped) @cname("AcceptEx");

extern fn void getAcceptExSockaddrs(void* lpOutputBuffer, uint dwReceiveDataLength, uint dwLocalAddressLength, uint dwRemoteAddressLength, winsock2::SockAddr** localSockaddr, int* localSockaddrLength, winsock2::SockAddr** remoteSockaddr, int* remoteSockaddrLength) @cname("GetAcceptExSockaddrs");

extern fn int wsaRecvMsg(Socket s, WsaMsg* lpMsg, uint* lpdwNumberOfBytesRecvd, winbase::Overlapped* lpOverlapped, WsaOverlappedCompletionRoutine lpCompletionRoutine) @cname("WSARecvMsg");

extern fn int wsaSendMsg(Socket s, WsaMsg* lpMsg, uint dwFlags, uint* lpNumberOfBytesSent, winbase::Overlapped* lpOverlapped, WsaOverlappedCompletionRoutine lpCompletionRoutine) @cname("WSASendMsg");
