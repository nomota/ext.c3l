// sys.termios.h.c3

// ========== Linux ==========

module c::termios @if(env::LINUX);

alias TcFlag = uint;
alias Cc = char;
alias Speed = uint;

const int NCCS = 32;

struct Termios
{
    TcFlag c_iflag;
    TcFlag c_oflag;
    TcFlag c_cflag;
    TcFlag c_lflag;
    Cc[NCCS] c_cc;
}

extern fn int tcgetattr(int fd, Termios* termios_p);
extern fn int tcsetattr(int fd, int optional_actions, Termios* termios_p);
extern fn int tcsendbreak(int fd, int duration);
extern fn int tcdrain(int fd);
extern fn int tcflush(int fd, int queue_selector);
extern fn int tcflow(int fd, int action);
extern fn Speed cfgetispeed(Termios* termios_p);
extern fn Speed cfgetospeed(Termios* termios_p);
extern fn int cfsetispeed(Termios* termios_p, Speed speed);
extern fn int cfsetospeed(Termios* termios_p, Speed speed);
extern fn int cfsetspeed(Termios* termios_p, Speed speed);
extern fn void cfmakeraw(Termios* termios_p);

// c_cc indexes
const int VINTR = 0;
const int VQUIT = 1;
const int VERASE = 2;
const int VKILL = 3;
const int VEOF = 4;
const int VTIME = 5;
const int VMIN = 6;
const int VSWTC = 7;
const int VSTART = 8;
const int VSTOP = 9;
const int VSUSP = 10;
const int VEOL = 11;
const int VREPRINT = 12;
const int VDISCARD = 13;
const int VWERASE = 14;
const int VLNEXT = 15;
const int VEOL2 = 16;

// tcsetattr actions
const int TCSANOW = 0;
const int TCSADRAIN = 1;
const int TCSAFLUSH = 2;

// tcflush queue selector
const int TCIFLUSH = 0;
const int TCOFLUSH = 1;
const int TCIOFLUSH = 2;

// tcflow action
const int TCOOFF = 0;
const int TCOON = 1;
const int TCIOFF = 2;
const int TCION = 3;

// input flags
const TcFlag IGNBRK = 0x000001;
const TcFlag BRKINT = 0x000002;
const TcFlag IGNPAR = 0x000004;
const TcFlag PARMRK = 0x000008;
const TcFlag INPCK = 0x000010;
const TcFlag ISTRIP = 0x000020;
const TcFlag INLCR = 0x000040;
const TcFlag IGNCR = 0x000080;
const TcFlag ICRNL = 0x000100;
const TcFlag IUCLC = 0x000200;
const TcFlag IXON = 0x000400;
const TcFlag IXANY = 0x000800;
const TcFlag IXOFF = 0x001000;
const TcFlag IMAXBEL = 0x002000;
const TcFlag IUTF8 = 0x004000;

// output flags
const TcFlag OPOST = 0x000001;
const TcFlag OLCUC = 0x000002;
const TcFlag ONLCR = 0x000004;
const TcFlag OCRNL = 0x000008;
const TcFlag ONOCR = 0x000010;
const TcFlag ONLRET = 0x000020;
const TcFlag OFILL = 0x000040;
const TcFlag OFDEL = 0x000080;

const TcFlag NLDLY = 0x000100;
const TcFlag NL0 = 0x000000;
const TcFlag NL1 = 0x000100;

const TcFlag CRDLY = 0x000600;
const TcFlag CR0 = 0x000000;
const TcFlag CR1 = 0x000200;
const TcFlag CR2 = 0x000400;
const TcFlag CR3 = 0x000600;

const TcFlag TABDLY = 0x001800;
const TcFlag TAB0 = 0x000000;
const TcFlag TAB1 = 0x000800;
const TcFlag TAB2 = 0x001000;
const TcFlag TAB3 = 0x001800;
const TcFlag XTABS = TAB3;

const TcFlag BSDLY = 0x002000;
const TcFlag BS0 = 0x000000;
const TcFlag BS1 = 0x002000;

const TcFlag VTDLY = 0x004000;
const TcFlag VT0 = 0x000000;
const TcFlag VT1 = 0x004000;

const TcFlag FFDLY = 0x008000;
const TcFlag FF0 = 0x000000;
const TcFlag FF1 = 0x008000;

// control flags
const TcFlag CBAUD = 0x00100F;
const TcFlag B0 = 0x000000;
const TcFlag B50 = 0x000001;
const TcFlag B75 = 0x000002;
const TcFlag B110 = 0x000003;
const TcFlag B134 = 0x000004;
const TcFlag B150 = 0x000005;
const TcFlag B200 = 0x000006;
const TcFlag B300 = 0x000007;
const TcFlag B600 = 0x000008;
const TcFlag B1200 = 0x000009;
const TcFlag B1800 = 0x00000A;
const TcFlag B2400 = 0x00000B;
const TcFlag B4800 = 0x00000C;
const TcFlag B9600 = 0x00000D;
const TcFlag B19200 = 0x00000E;
const TcFlag B38400 = 0x00000F;
const TcFlag EXTA = B19200;
const TcFlag EXTB = B38400;

const TcFlag CSIZE = 0x000030;
const TcFlag CS5 = 0x000000;
const TcFlag CS6 = 0x000010;
const TcFlag CS7 = 0x000020;
const TcFlag CS8 = 0x000030;
const TcFlag CSTOPB = 0x000040;
const TcFlag CREAD = 0x000080;
const TcFlag PARENB = 0x000100;
const TcFlag PARODD = 0x000200;
const TcFlag HUPCL = 0x000400;
const TcFlag CLOCAL = 0x000800;

const TcFlag B57600 = 0x001001;
const TcFlag B115200 = 0x001002;
const TcFlag B230400 = 0x001003;
const TcFlag B460800 = 0x001004;
const TcFlag B500000 = 0x001005;
const TcFlag B576000 = 0x001006;
const TcFlag B921600 = 0x001007;
const TcFlag B1000000 = 0x001008;
const TcFlag B1152000 = 0x001009;
const TcFlag B1500000 = 0x00100A;
const TcFlag B2000000 = 0x00100B;
const TcFlag B2500000 = 0x00100C;
const TcFlag B3000000 = 0x00100D;
const TcFlag B3500000 = 0x00100E;
const TcFlag B4000000 = 0x00100F;

const TcFlag CIBAUD = 0x100F0000;
const TcFlag CMSPAR = 0x40000000;
const TcFlag CRTSCTS = 0x80000000;

// local flags
const TcFlag ISIG = 0x000001;
const TcFlag ICANON = 0x000002;
const TcFlag XCASE = 0x000004;
const TcFlag ECHO = 0x000008;
const TcFlag ECHOE = 0x000010;
const TcFlag ECHOK = 0x000020;
const TcFlag ECHONL = 0x000040;
const TcFlag NOFLSH = 0x000080;
const TcFlag TOSTOP = 0x000100;
const TcFlag ECHOCTL = 0x000200;
const TcFlag ECHOPRT = 0x000400;
const TcFlag ECHOKE = 0x000800;
const TcFlag FLUSHO = 0x001000;
const TcFlag PENDIN = 0x004000;
const TcFlag IEXTEN = 0x008000;
const TcFlag EXTPROC = 0x010000;


// ========== Darwin ==========

module c::termios @if(env::DARWIN);

alias TcFlag = ulong;
alias Cc = uchar;
alias Speed = ulong;

const int NCCS = 20;

struct Termios
{
    TcFlag c_iflag;
    TcFlag c_oflag;
    TcFlag c_cflag;
    TcFlag c_lflag;
    Cc[NCCS] c_cc;
    Speed c_ispeed;
    Speed c_ospeed;
}

extern fn int tcgetattr(int fd, Termios* termios_p);
extern fn int tcsetattr(int fd, int optional_actions, Termios* termios_p);
extern fn int tcsendbreak(int fd, int duration);
extern fn int tcdrain(int fd);
extern fn int tcflush(int fd, int queue_selector);
extern fn int tcflow(int fd, int action);
extern fn Speed cfgetispeed(Termios* termios_p);
extern fn Speed cfgetospeed(Termios* termios_p);
extern fn int cfsetispeed(Termios* termios_p, Speed speed);
extern fn int cfsetospeed(Termios* termios_p, Speed speed);
extern fn int cfsetspeed(Termios* termios_p, Speed speed);
extern fn void cfmakeraw(Termios* termios_p);

// c_cc indexes
const int VEOF = 0;
const int VEOL = 1;
const int VEOL2 = 2;
const int VERASE = 3;
const int VWERASE = 4;
const int VKILL = 5;
const int VREPRINT = 6;
const int VINTR = 8;
const int VQUIT = 9;
const int VSUSP = 10;
const int VDSUSP = 11;
const int VSTART = 12;
const int VSTOP = 13;
const int VLNEXT = 14;
const int VDISCARD = 15;
const int VMIN = 16;
const int VTIME = 17;
const int VSTATUS = 18;

// tcsetattr actions
const int TCSANOW = 0;
const int TCSADRAIN = 1;
const int TCSAFLUSH = 2;

// tcflush queue selector
const int TCIFLUSH = 1;
const int TCOFLUSH = 2;
const int TCIOFLUSH = 3;

// tcflow action
const int TCOOFF = 1;
const int TCOON = 2;
const int TCIOFF = 3;
const int TCION = 4;

// input flags
const TcFlag IGNBRK = 0x00000001;
const TcFlag BRKINT = 0x00000002;
const TcFlag IGNPAR = 0x00000004;
const TcFlag PARMRK = 0x00000008;
const TcFlag INPCK = 0x00000010;
const TcFlag ISTRIP = 0x00000020;
const TcFlag INLCR = 0x00000040;
const TcFlag IGNCR = 0x00000080;
const TcFlag ICRNL = 0x00000100;
const TcFlag IXON = 0x00000200;
const TcFlag IXOFF = 0x00000400;
const TcFlag IXANY = 0x00000800;
const TcFlag IMAXBEL = 0x00002000;
const TcFlag IUTF8 = 0x00004000;

// output flags
const TcFlag OPOST = 0x00000001;
const TcFlag ONLCR = 0x00000002;
const TcFlag OXTABS = 0x00000004;
const TcFlag ONOEOT = 0x00000008;
const TcFlag OCRNL = 0x00000010;
const TcFlag ONOCR = 0x00000020;
const TcFlag ONLRET = 0x00000040;
const TcFlag OFILL = 0x00000080;
const TcFlag NLDLY = 0x00000300;
const TcFlag TABDLY = 0x00000C04;
const TcFlag CRDLY = 0x00003000;
const TcFlag FFDLY = 0x00004000;
const TcFlag BSDLY = 0x00008000;
const TcFlag VTDLY = 0x00010000;
const TcFlag OFDEL = 0x00020000;

// control flags
const TcFlag CIGNORE = 0x00000001;
const TcFlag CSIZE = 0x00000300;
const TcFlag CS5 = 0x00000000;
const TcFlag CS6 = 0x00000100;
const TcFlag CS7 = 0x00000200;
const TcFlag CS8 = 0x00000300;
const TcFlag CSTOPB = 0x00000400;
const TcFlag CREAD = 0x00000800;
const TcFlag PARENB = 0x00001000;
const TcFlag PARODD = 0x00002000;
const TcFlag HUPCL = 0x00004000;
const TcFlag CLOCAL = 0x00008000;
const TcFlag CCTS_OFLOW = 0x00010000;
const TcFlag CRTSCTS = CCTS_OFLOW;
const TcFlag CRTS_IFLOW = 0x00020000;
const TcFlag CDTR_IFLOW = 0x00040000;
const TcFlag CDSR_OFLOW = 0x00080000;
const TcFlag CCAR_OFLOW = 0x00100000;

// local flags
const TcFlag ECHOKE = 0x00000001;
const TcFlag ECHOE = 0x00000002;
const TcFlag ECHOK = 0x00000004;
const TcFlag ECHO = 0x00000008;
const TcFlag ECHONL = 0x00000010;
const TcFlag ECHOPRT = 0x00000020;
const TcFlag ECHOCTL = 0x00000040;
const TcFlag ISIG = 0x00000080;
const TcFlag ICANON = 0x00000100;
const TcFlag ALTWERASE = 0x00000200;
const TcFlag IEXTEN = 0x00000400;
const TcFlag EXTPROC = 0x00000800;
const TcFlag TOSTOP = 0x00400000;
const TcFlag FLUSHO = 0x00800000;
const TcFlag NOKERNINFO = 0x02000000;
const TcFlag PENDIN = 0x20000000;
const TcFlag NOFLSH = 0x80000000;

// speed values
const Speed B0 = 0;
const Speed B50 = 50;
const Speed B75 = 75;
const Speed B110 = 110;
const Speed B134 = 134;
const Speed B150 = 150;
const Speed B200 = 200;
const Speed B300 = 300;
const Speed B600 = 600;
const Speed B1200 = 1200;
const Speed B1800 = 1800;
const Speed B2400 = 2400;
const Speed B4800 = 4800;
const Speed B9600 = 9600;
const Speed B19200 = 19200;
const Speed B38400 = 38400;
const Speed B7200 = 7200;
const Speed B14400 = 14400;
const Speed B28800 = 28800;
const Speed B57600 = 57600;
const Speed B76800 = 76800;
const Speed B115200 = 115200;
const Speed B230400 = 230400;


// ========== FreeBSD ==========

module c::termios @if(env::FREEBSD);

alias TcFlag = uint;
alias Cc = uchar;
alias Speed = uint;

const int NCCS = 20;

struct Termios
{
    TcFlag c_iflag;
    TcFlag c_oflag;
    TcFlag c_cflag;
    TcFlag c_lflag;
    Cc[NCCS] c_cc;
    Speed c_ispeed;
    Speed c_ospeed;
}

extern fn int tcgetattr(int fd, Termios* termios_p);
extern fn int tcsetattr(int fd, int optional_actions, Termios* termios_p);
extern fn int tcsendbreak(int fd, int duration);
extern fn int tcdrain(int fd);
extern fn int tcflush(int fd, int queue_selector);
extern fn int tcflow(int fd, int action);
extern fn Speed cfgetispeed(Termios* termios_p);
extern fn Speed cfgetospeed(Termios* termios_p);
extern fn int cfsetispeed(Termios* termios_p, Speed speed);
extern fn int cfsetospeed(Termios* termios_p, Speed speed);
extern fn int cfsetspeed(Termios* termios_p, Speed speed);
extern fn void cfmakeraw(Termios* termios_p);

// c_cc indexes
const int VEOF = 0;
const int VEOL = 1;
const int VEOL2 = 2;
const int VERASE = 3;
const int VWERASE = 4;
const int VKILL = 5;
const int VREPRINT = 6;
const int VMIN = 16;
const int VTIME = 17;
const int VINTR = 8;
const int VQUIT = 9;
const int VSUSP = 10;
const int VSTART = 12;
const int VSTOP = 13;
const int VLNEXT = 14;
const int VDISCARD = 15;
const int VSTATUS = 18;

// tcsetattr actions
const int TCSANOW = 0;
const int TCSADRAIN = 1;
const int TCSAFLUSH = 2;

// tcflush queue selector
const int TCIFLUSH = 1;
const int TCOFLUSH = 2;
const int TCIOFLUSH = 3;

// tcflow action
const int TCOOFF = 1;
const int TCOON = 2;
const int TCIOFF = 3;
const int TCION = 4;

// input flags
const TcFlag IGNBRK = 0x00000001;
const TcFlag BRKINT = 0x00000002;
const TcFlag IGNPAR = 0x00000004;
const TcFlag PARMRK = 0x00000008;
const TcFlag INPCK = 0x00000010;
const TcFlag ISTRIP = 0x00000020;
const TcFlag INLCR = 0x00000040;
const TcFlag IGNCR = 0x00000080;
const TcFlag ICRNL = 0x00000100;
const TcFlag IXON = 0x00000200;
const TcFlag IXOFF = 0x00000400;
const TcFlag IXANY = 0x00000800;
const TcFlag IMAXBEL = 0x00002000;

// output flags
const TcFlag OPOST = 0x00000001;
const TcFlag ONLCR = 0x00000002;
const TcFlag TABDLY = 0x00000004;
const TcFlag ONOEOT = 0x00000008;
const TcFlag OCRNL = 0x00000010;
const TcFlag ONOCR = 0x00000020;
const TcFlag ONLRET = 0x00000040;

// control flags
const TcFlag CSIZE = 0x00000300;
const TcFlag CS5 = 0x00000000;
const TcFlag CS6 = 0x00000100;
const TcFlag CS7 = 0x00000200;
const TcFlag CS8 = 0x00000300;
const TcFlag CSTOPB = 0x00000400;
const TcFlag CREAD = 0x00000800;
const TcFlag PARENB = 0x00001000;
const TcFlag PARODD = 0x00002000;
const TcFlag HUPCL = 0x00004000;
const TcFlag CLOCAL = 0x00008000;
const TcFlag CCTS_OFLOW = 0x00010000;
const TcFlag CRTSCTS = CCTS_OFLOW;
const TcFlag CRTS_IFLOW = 0x00020000;
const TcFlag CDTR_IFLOW = 0x00040000;
const TcFlag CDSR_OFLOW = 0x00080000;
const TcFlag CCAR_OFLOW = 0x00100000;

// local flags
const TcFlag ECHOKE = 0x00000001;
const TcFlag ECHOE = 0x00000002;
const TcFlag ECHOK = 0x00000004;
const TcFlag ECHO = 0x00000008;
const TcFlag ECHONL = 0x00000010;
const TcFlag ECHOPRT = 0x00000020;
const TcFlag ECHOCTL = 0x00000040;
const TcFlag ISIG = 0x00000080;
const TcFlag ICANON = 0x00000100;
const TcFlag IEXTEN = 0x00000400;
const TcFlag EXTPROC = 0x00000800;
const TcFlag TOSTOP = 0x00400000;
const TcFlag FLUSHO = 0x00800000;
const TcFlag PENDIN = 0x20000000;
const TcFlag NOFLSH = 0x80000000;

// speed values
const Speed B0 = 0;
const Speed B50 = 50;
const Speed B75 = 75;
const Speed B110 = 110;
const Speed B134 = 134;
const Speed B150 = 150;
const Speed B200 = 200;
const Speed B300 = 300;
const Speed B600 = 600;
const Speed B1200 = 1200;
const Speed B1800 = 1800;
const Speed B2400 = 2400;
const Speed B4800 = 4800;
const Speed B9600 = 9600;
const Speed B19200 = 19200;
const Speed B38400 = 38400;
const Speed B57600 = 57600;
const Speed B115200 = 115200;
const Speed B230400 = 230400;


// ========== NetBSD ==========

module c::termios @if(env::NETBSD);

alias TcFlag = uint;
alias Cc = uchar;
alias Speed = uint;

const int NCCS = 20;

struct Termios
{
    TcFlag c_iflag;
    TcFlag c_oflag;
    TcFlag c_cflag;
    TcFlag c_lflag;
    Cc[NCCS] c_cc;
    Speed c_ispeed;
    Speed c_ospeed;
}

extern fn int tcgetattr(int fd, Termios* termios_p);
extern fn int tcsetattr(int fd, int optional_actions, Termios* termios_p);
extern fn int tcsendbreak(int fd, int duration);
extern fn int tcdrain(int fd);
extern fn int tcflush(int fd, int queue_selector);
extern fn int tcflow(int fd, int action);
extern fn Speed cfgetispeed(Termios* termios_p);
extern fn Speed cfgetospeed(Termios* termios_p);
extern fn int cfsetispeed(Termios* termios_p, Speed speed);
extern fn int cfsetospeed(Termios* termios_p, Speed speed);
extern fn int cfsetspeed(Termios* termios_p, Speed speed);
extern fn void cfmakeraw(Termios* termios_p);

const int VEOF = 0;
const int VEOL = 1;
const int VEOL2 = 2;
const int VERASE = 3;
const int VWERASE = 4;
const int VKILL = 5;
const int VREPRINT = 6;
const int VINTR = 8;
const int VQUIT = 9;
const int VSUSP = 10;
const int VSTART = 12;
const int VSTOP = 13;
const int VLNEXT = 14;
const int VDISCARD = 15;
const int VMIN = 16;
const int VTIME = 17;
const int VSTATUS = 18;

const int TCSANOW = 0;
const int TCSADRAIN = 1;
const int TCSAFLUSH = 2;

const int TCIFLUSH = 1;
const int TCOFLUSH = 2;
const int TCIOFLUSH = 3;

const int TCOOFF = 1;
const int TCOON = 2;
const int TCIOFF = 3;
const int TCION = 4;

const TcFlag IGNBRK = 0x00000001;
const TcFlag BRKINT = 0x00000002;
const TcFlag IGNPAR = 0x00000004;
const TcFlag PARMRK = 0x00000008;
const TcFlag INPCK = 0x00000010;
const TcFlag ISTRIP = 0x00000020;
const TcFlag INLCR = 0x00000040;
const TcFlag IGNCR = 0x00000080;
const TcFlag ICRNL = 0x00000100;
const TcFlag IXON = 0x00000200;
const TcFlag IXOFF = 0x00000400;
const TcFlag IXANY = 0x00000800;
const TcFlag IMAXBEL = 0x00002000;

const TcFlag OPOST = 0x00000001;
const TcFlag ONLCR = 0x00000002;
const TcFlag OCRNL = 0x00000010;
const TcFlag ONOCR = 0x00000020;
const TcFlag ONLRET = 0x00000040;

const TcFlag CSIZE = 0x00000300;
const TcFlag CS5 = 0x00000000;
const TcFlag CS6 = 0x00000100;
const TcFlag CS7 = 0x00000200;
const TcFlag CS8 = 0x00000300;
const TcFlag CSTOPB = 0x00000400;
const TcFlag CREAD = 0x00000800;
const TcFlag PARENB = 0x00001000;
const TcFlag PARODD = 0x00002000;
const TcFlag HUPCL = 0x00004000;
const TcFlag CLOCAL = 0x00008000;
const TcFlag CRTSCTS = 0x00010000;

const TcFlag ECHOE = 0x00000002;
const TcFlag ECHOK = 0x00000004;
const TcFlag ECHO = 0x00000008;
const TcFlag ECHONL = 0x00000010;
const TcFlag ISIG = 0x00000080;
const TcFlag ICANON = 0x00000100;
const TcFlag IEXTEN = 0x00000400;
const TcFlag TOSTOP = 0x00400000;
const TcFlag PENDIN = 0x20000000;
const TcFlag NOFLSH = 0x80000000;

const Speed B0 = 0;
const Speed B50 = 50;
const Speed B75 = 75;
const Speed B110 = 110;
const Speed B134 = 134;
const Speed B150 = 150;
const Speed B200 = 200;
const Speed B300 = 300;
const Speed B600 = 600;
const Speed B1200 = 1200;
const Speed B1800 = 1800;
const Speed B2400 = 2400;
const Speed B4800 = 4800;
const Speed B9600 = 9600;
const Speed B19200 = 19200;
const Speed B38400 = 38400;
const Speed B57600 = 57600;
const Speed B115200 = 115200;
const Speed B230400 = 230400;


// ========== OpenBSD ==========

module c::termios @if(env::OPENBSD);

alias TcFlag = uint;
alias Cc = uchar;
alias Speed = uint;

const int NCCS = 20;

struct Termios
{
    TcFlag c_iflag;
    TcFlag c_oflag;
    TcFlag c_cflag;
    TcFlag c_lflag;
    Cc[NCCS] c_cc;
    Speed c_ispeed;
    Speed c_ospeed;
}

extern fn int tcgetattr(int fd, Termios* termios_p);
extern fn int tcsetattr(int fd, int optional_actions, Termios* termios_p);
extern fn int tcsendbreak(int fd, int duration);
extern fn int tcdrain(int fd);
extern fn int tcflush(int fd, int queue_selector);
extern fn int tcflow(int fd, int action);
extern fn Speed cfgetispeed(Termios* termios_p);
extern fn Speed cfgetospeed(Termios* termios_p);
extern fn int cfsetispeed(Termios* termios_p, Speed speed);
extern fn int cfsetospeed(Termios* termios_p, Speed speed);
extern fn int cfsetspeed(Termios* termios_p, Speed speed);
extern fn void cfmakeraw(Termios* termios_p);

const int VEOF = 0;
const int VEOL = 1;
const int VEOL2 = 2;
const int VERASE = 3;
const int VWERASE = 4;
const int VKILL = 5;
const int VREPRINT = 6;
const int VINTR = 8;
const int VQUIT = 9;
const int VSUSP = 10;
const int VSTART = 12;
const int VSTOP = 13;
const int VLNEXT = 14;
const int VDISCARD = 15;
const int VMIN = 16;
const int VTIME = 17;
const int VSTATUS = 18;

const int TCSANOW = 0;
const int TCSADRAIN = 1;
const int TCSAFLUSH = 2;

const int TCIFLUSH = 1;
const int TCOFLUSH = 2;
const int TCIOFLUSH = 3;

const int TCOOFF = 1;
const int TCOON = 2;
const int TCIOFF = 3;
const int TCION = 4;

const TcFlag IGNBRK = 0x00000001;
const TcFlag BRKINT = 0x00000002;
const TcFlag IGNPAR = 0x00000004;
const TcFlag PARMRK = 0x00000008;
const TcFlag INPCK = 0x00000010;
const TcFlag ISTRIP = 0x00000020;
const TcFlag INLCR = 0x00000040;
const TcFlag IGNCR = 0x00000080;
const TcFlag ICRNL = 0x00000100;
const TcFlag IXON = 0x00000200;
const TcFlag IXOFF = 0x00000400;
const TcFlag IXANY = 0x00000800;
const TcFlag IMAXBEL = 0x00002000;

const TcFlag OPOST = 0x00000001;
const TcFlag ONLCR = 0x00000002;
const TcFlag OCRNL = 0x00000010;
const TcFlag ONOCR = 0x00000020;
const TcFlag ONLRET = 0x00000040;

const TcFlag CSIZE = 0x00000300;
const TcFlag CS5 = 0x00000000;
const TcFlag CS6 = 0x00000100;
const TcFlag CS7 = 0x00000200;
const TcFlag CS8 = 0x00000300;
const TcFlag CSTOPB = 0x00000400;
const TcFlag CREAD = 0x00000800;
const TcFlag PARENB = 0x00001000;
const TcFlag PARODD = 0x00002000;
const TcFlag HUPCL = 0x00004000;
const TcFlag CLOCAL = 0x00008000;
const TcFlag CRTSCTS = 0x00010000;

const TcFlag ECHOE = 0x00000002;
const TcFlag ECHOK = 0x00000004;
const TcFlag ECHO = 0x00000008;
const TcFlag ECHONL = 0x00000010;
const TcFlag ISIG = 0x00000080;
const TcFlag ICANON = 0x00000100;
const TcFlag IEXTEN = 0x00000400;
const TcFlag TOSTOP = 0x00400000;
const TcFlag PENDIN = 0x20000000;
const TcFlag NOFLSH = 0x80000000;

const Speed B0 = 0;
const Speed B50 = 50;
const Speed B75 = 75;
const Speed B110 = 110;
const Speed B134 = 134;
const Speed B150 = 150;
const Speed B200 = 200;
const Speed B300 = 300;
const Speed B600 = 600;
const Speed B1200 = 1200;
const Speed B1800 = 1800;
const Speed B2400 = 2400;
const Speed B4800 = 4800;
const Speed B9600 = 9600;
const Speed B19200 = 19200;
const Speed B38400 = 38400;
const Speed B57600 = 57600;
const Speed B115200 = 115200;
const Speed B230400 = 230400;

// eof