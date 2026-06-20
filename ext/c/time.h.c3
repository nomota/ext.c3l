// time.h.c3

// Nomota <hiongun@gmail.com>; MIT License

module c::time;


// Common types

alias TimeT = long;
alias ClockT = long;


// Common structures

struct Tm
{
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
}

struct TimeSpec
{
    long tv_sec;
    long tv_nsec;
}


// Standard C functions

extern fn TimeT time(TimeT* tloc);

extern fn double difftime(TimeT time1, TimeT time0);

extern fn ClockT clock();

extern fn Tm* localtime(TimeT* timer);

extern fn Tm* gmtime(TimeT* timer);

extern fn TimeT mktime(Tm* timeptr);

extern fn char* asctime(Tm* timeptr);

extern fn char* ctime(TimeT* timer);

extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);


// POSIX common declarations

module c::time @if(env::POSIX);

extern fn Tm* localtime_r(TimeT* timer, Tm* result);

extern fn Tm* gmtime_r(TimeT* timer, Tm* result);

extern fn char* asctime_r(Tm* timeptr, char* buf);

extern fn char* ctime_r(TimeT* timer, char* buf);

extern fn int clock_gettime(int clk_id, TimeSpec* tp);

extern fn int clock_getres(int clk_id, TimeSpec* res);

extern fn int nanosleep(TimeSpec* req, TimeSpec* rem);

extern fn char* strptime(char* s, char* format, Tm* tm);

extern fn void tzset();

extern fn TimeT timegm(Tm* tm);

extern long timezone;
extern int daylight;
extern char** tzname;

const int TIMER_ABSTIME = 1;


// Linux

module c::time @if(env::LINUX);

struct TimeVal
{
    long tv_sec;
    long tv_usec;
}

struct ITimerSpec
{
    TimeSpec it_interval;
    TimeSpec it_value;
}

extern fn int clock_settime(int clk_id, TimeSpec* tp);

extern fn TimeT timelocal(Tm* tm);

const int CLOCK_REALTIME = 0;
const int CLOCK_MONOTONIC = 1;
const int CLOCK_PROCESS_CPUTIME_ID = 2;
const int CLOCK_THREAD_CPUTIME_ID = 3;
const int CLOCK_MONOTONIC_RAW = 4;
const int CLOCK_REALTIME_COARSE = 5;
const int CLOCK_MONOTONIC_COARSE = 6;
const int CLOCK_BOOTTIME = 7;
const int CLOCK_REALTIME_ALARM = 8;
const int CLOCK_BOOTTIME_ALARM = 9;

const long CLOCKS_PER_SEC = 1_000_000;


// Darwin

module c::time @if(env::DARWIN);

struct TimeVal
{
    long tv_sec;
    int tv_usec;
}

const int CLOCK_REALTIME = 0;
const int CLOCK_MONOTONIC_RAW = 4;
const int CLOCK_MONOTONIC_RAW_APPROX = 5;
const int CLOCK_MONOTONIC = 6;
const int CLOCK_UPTIME_RAW = 8;
const int CLOCK_UPTIME_RAW_APPROX = 9;
const int CLOCK_PROCESS_CPUTIME_ID = 12;
const int CLOCK_THREAD_CPUTIME_ID = 16;

const long CLOCKS_PER_SEC = 1_000_000;


// FreeBSD

module c::time @if(env::FREEBSD);

struct TimeVal
{
    long tv_sec;
    long tv_usec;
}

extern fn int clock_settime(int clk_id, TimeSpec* tp);

const int CLOCK_REALTIME = 0;
const int CLOCK_VIRTUAL = 1;
const int CLOCK_PROF = 2;
const int CLOCK_MONOTONIC = 4;
const int CLOCK_UPTIME = 5;
const int CLOCK_UPTIME_PRECISE = 7;
const int CLOCK_UPTIME_FAST = 8;
const int CLOCK_REALTIME_PRECISE = 9;
const int CLOCK_REALTIME_FAST = 10;
const int CLOCK_MONOTONIC_PRECISE = 11;
const int CLOCK_MONOTONIC_FAST = 12;
const int CLOCK_SECOND = 13;
const int CLOCK_THREAD_CPUTIME_ID = 14;
const int CLOCK_PROCESS_CPUTIME_ID = 15;

const long CLOCKS_PER_SEC = 128;

const int TIMER_RELTIME = 0;


// NetBSD

module c::time @if(env::NETBSD);

struct TimeVal
{
    long tv_sec;
    int tv_usec;
}

extern fn int clock_settime(int clk_id, TimeSpec* tp);

const int CLOCK_REALTIME = 0;
const int CLOCK_VIRTUAL = 1;
const int CLOCK_PROF = 2;
const int CLOCK_MONOTONIC = 3;
const int CLOCK_THREAD_CPUTIME_ID = 0x20000000;
const int CLOCK_PROCESS_CPUTIME_ID = 0x40000000;

const long CLOCKS_PER_SEC = 100;

const int TIMER_RELTIME = 0;


// OpenBSD

module c::time @if(env::OPENBSD);

struct TimeVal
{
    long tv_sec;
    long tv_usec;
}

const int CLOCK_REALTIME = 0;
const int CLOCK_PROCESS_CPUTIME_ID = 2;
const int CLOCK_MONOTONIC = 3;
const int CLOCK_THREAD_CPUTIME_ID = 4;
const int CLOCK_UPTIME = 5;
const int CLOCK_BOOTTIME = 6;

const long CLOCKS_PER_SEC = 100;

const int TIMER_RELTIME = 0;


// Windows

module c::time @if(env::WIN32);

struct Timeb
{
    long time;
    ushort millitm;
    short timezone;
    short dstflag;
}

struct Timeb64
{
    long time;
    ushort millitm;
    short timezone;
    short dstflag;
}


// Windows secure functions

extern fn int localtime_s(Tm* result, TimeT* timer);

extern fn int gmtime_s(Tm* result, TimeT* timer);

extern fn int asctime_s(char* buf, sz size, Tm* timeptr);

extern fn int ctime_s(char* buf, sz size, TimeT* timer);


// Windows 64-bit time functions

extern fn long _time64(long* timer);

extern fn Tm* _localtime64(long* timer);

extern fn Tm* _gmtime64(long* timer);

extern fn int _localtime64_s(Tm* result, long* timer);

extern fn int _gmtime64_s(Tm* result, long* timer);

extern fn long _mktime64(Tm* timeptr);

extern fn char* _ctime64(long* timer);

extern fn int _ctime64_s(char* buf, sz size, long* timer);


// Windows additional functions

extern fn int timespec_get(TimeSpec* ts, int base);

extern fn void _ftime(Timeb* timeptr);

extern fn void _ftime64(Timeb64* timeptr);

extern fn void tzset() @cname("_tzset");

extern long timezone @cname("_timezone");
extern int daylight @cname("_daylight");
extern char** tzname @cname("_tzname");

const long CLOCKS_PER_SEC = 1_000;
const int TIME_UTC = 1;

// eof