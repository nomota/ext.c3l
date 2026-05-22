// sys.ioctl.h.c3

// ========== Linux ==========

module c::sys::ioctl @if(env::LINUX);

extern fn int ioctl(int fd, ulong request, ...);

const uint IOC_NRBITS = 8;
const uint IOC_TYPEBITS = 8;
const uint IOC_SIZEBITS = 14;
const uint IOC_DIRBITS = 2;

const uint IOC_NRMASK = (1 << IOC_NRBITS) - 1;
const uint IOC_TYPEMASK = (1 << IOC_TYPEBITS) - 1;
const uint IOC_SIZEMASK = (1 << IOC_SIZEBITS) - 1;
const uint IOC_DIRMASK = (1 << IOC_DIRBITS) - 1;

const uint IOC_NRSHIFT = 0;
const uint IOC_TYPESHIFT = IOC_NRSHIFT + IOC_NRBITS;
const uint IOC_SIZESHIFT = IOC_TYPESHIFT + IOC_TYPEBITS;
const uint IOC_DIRSHIFT = IOC_SIZESHIFT + IOC_SIZEBITS;

const uint IOC_NONE = 0;
const uint IOC_WRITE = 1;
const uint IOC_READ = 2;

macro ulong ioc(uint dir, uint type, uint nr, uint size)
{
    return (ulong)((dir << IOC_DIRSHIFT) |
                   (type << IOC_TYPESHIFT) |
                   (nr << IOC_NRSHIFT) |
                   (size << IOC_SIZESHIFT));
}

macro ulong io_none(uint type, uint nr)
{
    return ioc(IOC_NONE, type, nr, 0);
}

macro ulong io_read(uint type, uint nr, uint size)
{
    return ioc(IOC_READ, type, nr, size);
}

macro ulong io_write(uint type, uint nr, uint size)
{
    return ioc(IOC_WRITE, type, nr, size);
}

macro ulong io_read_write(uint type, uint nr, uint size)
{
    return ioc(IOC_READ | IOC_WRITE, type, nr, size);
}

macro uint ioc_dir(ulong nr)
{
    return (uint)((nr >> IOC_DIRSHIFT) & IOC_DIRMASK);
}

macro uint ioc_type(ulong nr)
{
    return (uint)((nr >> IOC_TYPESHIFT) & IOC_TYPEMASK);
}

macro uint ioc_nr(ulong nr)
{
    return (uint)((nr >> IOC_NRSHIFT) & IOC_NRMASK);
}

macro uint ioc_size(ulong nr)
{
    return (uint)((nr >> IOC_SIZESHIFT) & IOC_SIZEMASK);
}

const ulong TCGETS = 0x5401;
const ulong TCSETS = 0x5402;
const ulong TCSETSW = 0x5403;
const ulong TCSETSF = 0x5404;
const ulong TCGETA = 0x5405;
const ulong TCSETA = 0x5406;
const ulong TCSETAW = 0x5407;
const ulong TCSETAF = 0x5408;
const ulong TCSBRK = 0x5409;
const ulong TCXONC = 0x540A;
const ulong TCFLSH = 0x540B;
const ulong TIOCEXCL = 0x540C;
const ulong TIOCNXCL = 0x540D;
const ulong TIOCSCTTY = 0x540E;
const ulong TIOCGPGRP = 0x540F;
const ulong TIOCSPGRP = 0x5410;
const ulong TIOCOUTQ = 0x5411;
const ulong TIOCSTI = 0x5412;
const ulong TIOCGWINSZ = 0x5413;
const ulong TIOCSWINSZ = 0x5414;
const ulong TIOCMGET = 0x5415;
const ulong TIOCMBIS = 0x5416;
const ulong TIOCMBIC = 0x5417;
const ulong TIOCMSET = 0x5418;
const ulong TIOCGSOFTCAR = 0x5419;
const ulong TIOCSSOFTCAR = 0x541A;
const ulong FIONREAD = 0x541B;
const ulong TIOCINQ = FIONREAD;
const ulong TIOCLINUX = 0x541C;
const ulong TIOCCONS = 0x541D;
const ulong TIOCGSERIAL = 0x541E;
const ulong TIOCSSERIAL = 0x541F;
const ulong TIOCPKT = 0x5420;
const ulong FIONBIO = 0x5421;
const ulong TIOCNOTTY = 0x5422;
const ulong TIOCSETD = 0x5423;
const ulong TIOCGETD = 0x5424;
const ulong TCSBRKP = 0x5425;
const ulong TIOCSBRK = 0x5427;
const ulong TIOCCBRK = 0x5428;
const ulong TIOCGSID = 0x5429;
const ulong TCGETS2 = 0x802C542A;
const ulong TCSETS2 = 0x402C542B;
const ulong TCSETSW2 = 0x402C542C;
const ulong TCSETSF2 = 0x402C542D;
const ulong TIOCGRS485 = 0x542E;
const ulong TIOCSRS485 = 0x542F;
const ulong TIOCGPTN = 0x80045430;
const ulong TIOCSPTLCK = 0x40045431;
const ulong TIOCGDEV = 0x80045432;
const ulong TCGETX = 0x5432;
const ulong TCSETX = 0x5433;
const ulong TCSETXF = 0x5434;
const ulong TCSETXW = 0x5435;
const ulong TIOCSIG = 0x40045436;
const ulong TIOCVHANGUP = 0x5437;
const ulong TIOCGPKT = 0x80045438;
const ulong TIOCGPTLCK = 0x80045439;
const ulong TIOCGEXCL = 0x80045440;

const int TIOCM_LE = 0x001;
const int TIOCM_DTR = 0x002;
const int TIOCM_RTS = 0x004;
const int TIOCM_ST = 0x008;
const int TIOCM_SR = 0x010;
const int TIOCM_CTS = 0x020;
const int TIOCM_CAR = 0x040;
const int TIOCM_RNG = 0x080;
const int TIOCM_DSR = 0x100;
const int TIOCM_CD = TIOCM_CAR;
const int TIOCM_RI = TIOCM_RNG;

const int TIOCPKT_DATA = 0;
const int TIOCPKT_FLUSHREAD = 1;
const int TIOCPKT_FLUSHWRITE = 2;
const int TIOCPKT_STOP = 4;
const int TIOCPKT_START = 8;
const int TIOCPKT_NOSTOP = 16;
const int TIOCPKT_DOSTOP = 32;
const int TIOCPKT_IOCTL = 64;

const ulong SIOCADDRT = 0x890B;
const ulong SIOCDELRT = 0x890C;
const ulong SIOCRTMSG = 0x890D;
const ulong SIOCGIFNAME = 0x8910;
const ulong SIOCSIFLINK = 0x8911;
const ulong SIOCGIFCONF = 0x8912;
const ulong SIOCGIFFLAGS = 0x8913;
const ulong SIOCSIFFLAGS = 0x8914;
const ulong SIOCGIFADDR = 0x8915;
const ulong SIOCSIFADDR = 0x8916;
const ulong SIOCGIFDSTADDR = 0x8917;
const ulong SIOCSIFDSTADDR = 0x8918;
const ulong SIOCGIFBRDADDR = 0x8919;
const ulong SIOCSIFBRDADDR = 0x891A;
const ulong SIOCGIFNETMASK = 0x891B;
const ulong SIOCSIFNETMASK = 0x891C;
const ulong SIOCGIFMETRIC = 0x891D;
const ulong SIOCSIFMETRIC = 0x891E;
const ulong SIOCGIFMEM = 0x891F;
const ulong SIOCSIFMEM = 0x8920;
const ulong SIOCGIFMTU = 0x8921;
const ulong SIOCSIFMTU = 0x8922;
const ulong SIOCSIFNAME = 0x8923;
const ulong SIOCSIFHWADDR = 0x8924;
const ulong SIOCGIFHWADDR = 0x8927;
const ulong SIOCADDMULTI = 0x8931;
const ulong SIOCDELMULTI = 0x8932;
const ulong SIOCGIFINDEX = 0x8933;
const ulong SIOGIFINDEX = SIOCGIFINDEX;
const ulong SIOCSIFPFLAGS = 0x8934;
const ulong SIOCGIFPFLAGS = 0x8935;
const ulong SIOCDIFADDR = 0x8936;
const ulong SIOCSIFHWBROADCAST = 0x8937;
const ulong SIOCGIFCOUNT = 0x8938;

struct Winsize
{
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}


// ========== Darwin ==========

module c::sys::ioctl @if(env::DARWIN);

extern fn int ioctl(int fd, ulong request, ...);

const ulong IOCPARM_MASK = 0x1fff;
const ulong IOC_VOID = 0x20000000;
const ulong IOC_OUT = 0x40000000;
const ulong IOC_IN = 0x80000000;
const ulong IOC_INOUT = IOC_IN | IOC_OUT;

macro ulong bsd_ioc(ulong inout, uint group, uint num, uint len)
{
    return inout | (((ulong)len & IOCPARM_MASK) << 16) | ((ulong)group << 8) | (ulong)num;
}

macro ulong bsd_io_none(uint group, uint num)
{
    return bsd_ioc(IOC_VOID, group, num, 0);
}

macro ulong bsd_io_read(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_OUT, group, num, len);
}

macro ulong bsd_io_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_IN, group, num, len);
}

macro ulong bsd_io_read_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_INOUT, group, num, len);
}

macro ulong iocparm_len(ulong x)
{
    return (x >> 16) & IOCPARM_MASK;
}

macro ulong iocbasecmd(ulong x)
{
    return x & ~(IOCPARM_MASK << 16);
}

macro ulong iocgroup(ulong x)
{
    return (x >> 8) & 0xff;
}

const uint IOCGROUP_F = 'f';
const uint IOCGROUP_T = 't';
const uint IOCGROUP_S = 's';

const ulong FIONREAD = 0x4004667F;
const ulong FIONBIO = 0x8004667E;
const ulong FIOASYNC = 0x8004667D;
const ulong FIOSETOWN = 0x8004667C;
const ulong FIOGETOWN = 0x4004667B;

const ulong TIOCEXCL = 0x2000740D;
const ulong TIOCNXCL = 0x2000740E;
const ulong TIOCFLUSH = 0x80047410;
const ulong TIOCGETA = 0x40487413;
const ulong TIOCSETA = 0x80487414;
const ulong TIOCSETAW = 0x80487415;
const ulong TIOCSETAF = 0x80487416;
const ulong TIOCGETD = 0x4004741A;
const ulong TIOCSETD = 0x8004741B;
const ulong TIOCGPGRP = 0x40047477;
const ulong TIOCSPGRP = 0x80047476;
const ulong TIOCGWINSZ = 0x40087468;
const ulong TIOCSWINSZ = 0x80087467;
const ulong TIOCNOTTY = 0x20007471;
const ulong TIOCOUTQ = 0x40047473;
const ulong TIOCSTI = 0x80017472;
const ulong TIOCMGET = 0x4004746A;
const ulong TIOCMBIS = 0x8004746C;
const ulong TIOCMBIC = 0x8004746B;
const ulong TIOCMSET = 0x8004746D;

const int TIOCM_LE = 0x0001;
const int TIOCM_DTR = 0x0002;
const int TIOCM_RTS = 0x0004;
const int TIOCM_ST = 0x0008;
const int TIOCM_SR = 0x0010;
const int TIOCM_CTS = 0x0020;
const int TIOCM_CAR = 0x0040;
const int TIOCM_RNG = 0x0080;
const int TIOCM_DSR = 0x0100;
const int TIOCM_CD = TIOCM_CAR;
const int TIOCM_RI = TIOCM_RNG;

struct Winsize
{
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}


// ========== FreeBSD ==========

module c::sys::ioctl @if(env::FREEBSD);

extern fn int ioctl(int fd, ulong request, ...);

const ulong IOCPARM_MASK = 0x1fff;
const ulong IOC_VOID = 0x20000000;
const ulong IOC_OUT = 0x40000000;
const ulong IOC_IN = 0x80000000;
const ulong IOC_INOUT = IOC_IN | IOC_OUT;

macro ulong bsd_ioc(ulong inout, uint group, uint num, uint len)
{
    return inout | (((ulong)len & IOCPARM_MASK) << 16) | ((ulong)group << 8) | (ulong)num;
}

macro ulong bsd_io_none(uint group, uint num)
{
    return bsd_ioc(IOC_VOID, group, num, 0);
}

macro ulong bsd_io_read(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_OUT, group, num, len);
}

macro ulong bsd_io_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_IN, group, num, len);
}

macro ulong bsd_io_read_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_INOUT, group, num, len);
}

macro ulong iocparm_len(ulong x)
{
    return (x >> 16) & IOCPARM_MASK;
}

macro ulong iocbasecmd(ulong x)
{
    return x & ~(IOCPARM_MASK << 16);
}

macro ulong iocgroup(ulong x)
{
    return (x >> 8) & 0xff;
}

const ulong FIONREAD = 0x4004667F;
const ulong FIONBIO = 0x8004667E;
const ulong FIOASYNC = 0x8004667D;
const ulong FIOSETOWN = 0x8004667C;
const ulong FIOGETOWN = 0x4004667B;

const ulong TIOCEXCL = 0x2000740D;
const ulong TIOCNXCL = 0x2000740E;
const ulong TIOCFLUSH = 0x80047410;
const ulong TIOCGETA = 0x40487413;
const ulong TIOCSETA = 0x80487414;
const ulong TIOCSETAW = 0x80487415;
const ulong TIOCSETAF = 0x80487416;
const ulong TIOCGETD = 0x4004741A;
const ulong TIOCSETD = 0x8004741B;
const ulong TIOCGPGRP = 0x40047477;
const ulong TIOCSPGRP = 0x80047476;
const ulong TIOCGWINSZ = 0x40087468;
const ulong TIOCSWINSZ = 0x80087467;
const ulong TIOCNOTTY = 0x20007471;
const ulong TIOCOUTQ = 0x40047473;
const ulong TIOCSTI = 0x80017472;
const ulong TIOCMGET = 0x4004746A;
const ulong TIOCMBIS = 0x8004746C;
const ulong TIOCMBIC = 0x8004746B;
const ulong TIOCMSET = 0x8004746D;

const int TIOCM_LE = 0x0001;
const int TIOCM_DTR = 0x0002;
const int TIOCM_RTS = 0x0004;
const int TIOCM_ST = 0x0008;
const int TIOCM_SR = 0x0010;
const int TIOCM_CTS = 0x0020;
const int TIOCM_CAR = 0x0040;
const int TIOCM_RNG = 0x0080;
const int TIOCM_DSR = 0x0100;
const int TIOCM_CD = TIOCM_CAR;
const int TIOCM_RI = TIOCM_RNG;

struct Winsize
{
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}


// ========== NetBSD ==========

module c::sys::ioctl @if(env::NETBSD);

extern fn int ioctl(int fd, ulong request, ...);

const ulong IOCPARM_MASK = 0x1fff;
const ulong IOC_VOID = 0x20000000;
const ulong IOC_OUT = 0x40000000;
const ulong IOC_IN = 0x80000000;
const ulong IOC_INOUT = IOC_IN | IOC_OUT;

macro ulong bsd_ioc(ulong inout, uint group, uint num, uint len)
{
    return inout | (((ulong)len & IOCPARM_MASK) << 16) | ((ulong)group << 8) | (ulong)num;
}

macro ulong bsd_io_none(uint group, uint num)
{
    return bsd_ioc(IOC_VOID, group, num, 0);
}

macro ulong bsd_io_read(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_OUT, group, num, len);
}

macro ulong bsd_io_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_IN, group, num, len);
}

macro ulong bsd_io_read_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_INOUT, group, num, len);
}

macro ulong iocparm_len(ulong x)
{
    return (x >> 16) & IOCPARM_MASK;
}

macro ulong iocbasecmd(ulong x)
{
    return x & ~(IOCPARM_MASK << 16);
}

macro ulong iocgroup(ulong x)
{
    return (x >> 8) & 0xff;
}

const ulong FIONREAD = 0x4004667F;
const ulong FIONBIO = 0x8004667E;
const ulong FIOASYNC = 0x8004667D;
const ulong FIOSETOWN = 0x8004667C;
const ulong FIOGETOWN = 0x4004667B;

const ulong TIOCEXCL = 0x2000740D;
const ulong TIOCNXCL = 0x2000740E;
const ulong TIOCFLUSH = 0x80047410;
const ulong TIOCGETD = 0x4004741A;
const ulong TIOCSETD = 0x8004741B;
const ulong TIOCGPGRP = 0x40047477;
const ulong TIOCSPGRP = 0x80047476;
const ulong TIOCGWINSZ = 0x40087468;
const ulong TIOCSWINSZ = 0x80087467;
const ulong TIOCNOTTY = 0x20007471;
const ulong TIOCOUTQ = 0x40047473;
const ulong TIOCSTI = 0x80017472;
const ulong TIOCMGET = 0x4004746A;
const ulong TIOCMBIS = 0x8004746C;
const ulong TIOCMBIC = 0x8004746B;
const ulong TIOCMSET = 0x8004746D;

const int TIOCM_LE = 0x0001;
const int TIOCM_DTR = 0x0002;
const int TIOCM_RTS = 0x0004;
const int TIOCM_ST = 0x0008;
const int TIOCM_SR = 0x0010;
const int TIOCM_CTS = 0x0020;
const int TIOCM_CAR = 0x0040;
const int TIOCM_RNG = 0x0080;
const int TIOCM_DSR = 0x0100;
const int TIOCM_CD = TIOCM_CAR;
const int TIOCM_RI = TIOCM_RNG;

struct Winsize
{
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}


// ========== OpenBSD ==========

module c::sys::ioctl @if(env::OPENBSD);

extern fn int ioctl(int fd, ulong request, ...);

const ulong IOCPARM_MASK = 0x1fff;
const ulong IOC_VOID = 0x20000000;
const ulong IOC_OUT = 0x40000000;
const ulong IOC_IN = 0x80000000;
const ulong IOC_INOUT = IOC_IN | IOC_OUT;

macro ulong bsd_ioc(ulong inout, uint group, uint num, uint len)
{
    return inout | (((ulong)len & IOCPARM_MASK) << 16) | ((ulong)group << 8) | (ulong)num;
}

macro ulong bsd_io_none(uint group, uint num)
{
    return bsd_ioc(IOC_VOID, group, num, 0);
}

macro ulong bsd_io_read(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_OUT, group, num, len);
}

macro ulong bsd_io_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_IN, group, num, len);
}

macro ulong bsd_io_read_write(uint group, uint num, uint len)
{
    return bsd_ioc(IOC_INOUT, group, num, len);
}

macro ulong iocparm_len(ulong x)
{
    return (x >> 16) & IOCPARM_MASK;
}

macro ulong iocbasecmd(ulong x)
{
    return x & ~(IOCPARM_MASK << 16);
}

macro ulong iocgroup(ulong x)
{
    return (x >> 8) & 0xff;
}

const ulong FIONREAD = 0x4004667F;
const ulong FIONBIO = 0x8004667E;
const ulong FIOASYNC = 0x8004667D;
const ulong FIOSETOWN = 0x8004667C;
const ulong FIOGETOWN = 0x4004667B;

const ulong TIOCEXCL = 0x2000740D;
const ulong TIOCNXCL = 0x2000740E;
const ulong TIOCFLUSH = 0x80047410;
const ulong TIOCGETD = 0x4004741A;
const ulong TIOCSETD = 0x8004741B;
const ulong TIOCGPGRP = 0x40047477;
const ulong TIOCSPGRP = 0x80047476;
const ulong TIOCGWINSZ = 0x40087468;
const ulong TIOCSWINSZ = 0x80087467;
const ulong TIOCNOTTY = 0x20007471;
const ulong TIOCOUTQ = 0x40047473;
const ulong TIOCSTI = 0x80017472;
const ulong TIOCMGET = 0x4004746A;
const ulong TIOCMBIS = 0x8004746C;
const ulong TIOCMBIC = 0x8004746B;
const ulong TIOCMSET = 0x8004746D;

const int TIOCM_LE = 0x0001;
const int TIOCM_DTR = 0x0002;
const int TIOCM_RTS = 0x0004;
const int TIOCM_ST = 0x0008;
const int TIOCM_SR = 0x0010;
const int TIOCM_CTS = 0x0020;
const int TIOCM_CAR = 0x0040;
const int TIOCM_RNG = 0x0080;
const int TIOCM_DSR = 0x0100;
const int TIOCM_CD = TIOCM_CAR;
const int TIOCM_RI = TIOCM_RNG;

struct Winsize
{
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}

// eof