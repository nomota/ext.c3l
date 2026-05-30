// time.h.c3

module c::time;

// ========== Common Types and Structures ==========

// These are available on all platforms
alias Time_t = long;   // time_t - seconds since epoch
alias Clock_t = long;  // clock_t - processor time

struct Tm {
    int tm_sec;     // Seconds [0-60] (60 for leap second)
    int tm_min;     // Minutes [0-59]
    int tm_hour;    // Hours [0-23]
    int tm_mday;    // Day of month [1-31]
    int tm_mon;     // Month [0-11]
    int tm_year;    // Years since 1900
    int tm_wday;    // Day of week [0-6] (Sunday = 0)
    int tm_yday;    // Day of year [0-365]
    int tm_isdst;   // Daylight Saving Time_t flag
}

// ========== Linux ==========

module c::time @if(env::LINUX);

// Standard C functions
extern fn Time_t time(Time_t* tloc);
extern fn double difftime(Time_t time1, Time_t time0);
extern fn Clock_t clock();
extern fn Tm* localtime(Time_t* timer);
extern fn Tm* gmtime(Time_t* timer);
extern fn Time_t mktime(Tm* timeptr);
extern fn char* asctime(Tm* timeptr);
extern fn char* ctime(Time_t* timer);
extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);

// Thread-safe versions
extern fn Tm* localtime_r(Time_t* timer, Tm* result);
extern fn Tm* gmtime_r(Time_t* timer, Tm* result);
extern fn char* asctime_r(Tm* timeptr, char* buf);
extern fn char* ctime_r(Time_t* timer, char* buf);

// POSIX functions
extern fn int clock_gettime(int clk_id, TimeSpec* tp);
extern fn int clock_settime(int clk_id, TimeSpec* tp);
extern fn int clock_getres(int clk_id, TimeSpec* res);
extern fn int nanosleep(TimeSpec* req, TimeSpec* rem);
extern fn char* strptime(char* s, char* format, Tm* tm);
extern fn void tzset();
extern fn Time_t timegm(Tm* tm);
extern fn Time_t timelocal(Tm* tm);

// Additional structures
struct TimeSpec {
    long tv_sec;   // Seconds
    long tv_nsec;  // Nanoseconds
}

struct TimeVal {
    long tv_sec;   // Seconds
    long tv_usec;  // Microseconds
}

struct ITimerSpec {
    TimeSpec it_interval;
    TimeSpec it_value;
}

// Clock_t IDs
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

// Constants
const long CLOCKS_PER_SEC = 1000000;

// Time_tr constants
const int TIMER_ABSTIME = 1;

// Time_tzone
extern long timezone;
extern int daylight;
extern char** tzname;

// ========== Darwin (macOS) ==========

module c::time @if(env::DARWIN);

// Standard C functions
extern fn Time_t time(Time_t* tloc);
extern fn double difftime(Time_t time1, Time_t time0);
extern fn Clock_t clock();
extern fn Tm* localtime(Time_t* timer);
extern fn Tm* gmtime(Time_t* timer);
extern fn Time_t mktime(Tm* timeptr);
extern fn char* asctime(Tm* timeptr);
extern fn char* ctime(Time_t* timer);
extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);

// Thread-safe versions
extern fn Tm* localtime_r(Time_t* timer, Tm* result);
extern fn Tm* gmtime_r(Time_t* timer, Tm* result);
extern fn char* asctime_r(Tm* timeptr, char* buf);
extern fn char* ctime_r(Time_t* timer, char* buf);

// POSIX functions
extern fn int clock_gettime(int clk_id, TimeSpec* tp);
extern fn int clock_getres(int clk_id, TimeSpec* res);
extern fn int nanosleep(TimeSpec* req, TimeSpec* rem);
extern fn char* strptime(char* s, char* format, Tm* tm);
extern fn void tzset();
extern fn Time_t timegm(Tm* tm);

// Additional structures
struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

struct TimeVal {
    long tv_sec;
    int tv_usec;
}

// Clock_t IDs
const int CLOCK_REALTIME = 0;
const int CLOCK_MONOTONIC = 6;
const int CLOCK_MONOTONIC_RAW = 4;
const int CLOCK_MONOTONIC_RAW_APPROX = 5;
const int CLOCK_UPTIME_RAW = 8;
const int CLOCK_UPTIME_RAW_APPROX = 9;
const int CLOCK_PROCESS_CPUTIME_ID = 12;
const int CLOCK_THREAD_CPUTIME_ID = 16;

// Constants
const long CLOCKS_PER_SEC = 1000000;

// Time_tr constants
const int TIMER_ABSTIME = 1;

// Time_tzone
extern long timezone;
extern int daylight;
extern char** tzname;

// ========== FreeBSD ==========

module c::time @if(env::FREEBSD);

// Standard C functions
extern fn Time_t time(Time_t* tloc);
extern fn double difftime(Time_t time1, Time_t time0);
extern fn Clock_t clock();
extern fn Tm* localtime(Time_t* timer);
extern fn Tm* gmtime(Time_t* timer);
extern fn Time_t mktime(Tm* timeptr);
extern fn char* asctime(Tm* timeptr);
extern fn char* ctime(Time_t* timer);
extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);

// Thread-safe versions
extern fn Tm* localtime_r(Time_t* timer, Tm* result);
extern fn Tm* gmtime_r(Time_t* timer, Tm* result);
extern fn char* asctime_r(Tm* timeptr, char* buf);
extern fn char* ctime_r(Time_t* timer, char* buf);

// POSIX functions
extern fn int clock_gettime(int clk_id, TimeSpec* tp);
extern fn int clock_settime(int clk_id, TimeSpec* tp);
extern fn int clock_getres(int clk_id, TimeSpec* res);
extern fn int nanosleep(TimeSpec* req, TimeSpec* rem);
extern fn char* strptime(char* s, char* format, Tm* tm);
extern fn void tzset();
extern fn Time_t timegm(Tm* tm);

// Additional structures
struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

struct TimeVal {
    long tv_sec;
    long tv_usec;
}

// Clock_t IDs
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

// Constants
const long CLOCKS_PER_SEC = 128;

// Timer constants
const int TIMER_RELTIME = 0;
const int TIMER_ABSTIME = 1;

// Timezone
extern long timezone;
extern int daylight;
extern char** tzname;

// ========== NetBSD ==========

module c::time @if(env::NETBSD);

// Standard C functions
extern fn Time_t time(Time_t* tloc);
extern fn double difftime(Time_t time1, Time_t time0);
extern fn Clock_t clock();
extern fn Tm* localtime(Time_t* timer);
extern fn Tm* gmtime(Time_t* timer);
extern fn Time_t mktime(Tm* timeptr);
extern fn char* asctime(Tm* timeptr);
extern fn char* ctime(Time_t* timer);
extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);

// Thread-safe versions
extern fn Tm* localtime_r(Time_t* timer, Tm* result);
extern fn Tm* gmtime_r(Time_t* timer, Tm* result);
extern fn char* asctime_r(Tm* timeptr, char* buf);
extern fn char* ctime_r(Time_t* timer, char* buf);

// POSIX functions
extern fn int clock_gettime(int clk_id, TimeSpec* tp);
extern fn int clock_settime(int clk_id, TimeSpec* tp);
extern fn int clock_getres(int clk_id, TimeSpec* res);
extern fn int nanosleep(TimeSpec* req, TimeSpec* rem);
extern fn char* strptime(char* s, char* format, Tm* tm);
extern fn void tzset();
extern fn Time_t timegm(Tm* tm);

// Additional structures
struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

struct TimeVal {
    long tv_sec;
    int tv_usec;
}

// Clock_t IDs
const int CLOCK_REALTIME = 0;
const int CLOCK_VIRTUAL = 1;
const int CLOCK_PROF = 2;
const int CLOCK_MONOTONIC = 3;
const int CLOCK_THREAD_CPUTIME_ID = 0x20000000;
const int CLOCK_PROCESS_CPUTIME_ID = 0x40000000;

// Constants
const long CLOCKS_PER_SEC = 100;

// Timer constants
const int TIMER_RELTIME = 0;
const int TIMER_ABSTIME = 1;

// Timezone
extern long timezone;
extern int daylight;
extern char** tzname;

// ========== OpenBSD ==========

module c::time @if(env::OPENBSD);

// Standard C functions
extern fn Time_t time(Time_t* tloc);
extern fn double difftime(Time_t time1, Time_t time0);
extern fn Clock_t clock();
extern fn Tm* localtime(Time_t* timer);
extern fn Tm* gmtime(Time_t* timer);
extern fn Time_t mktime(Tm* timeptr);
extern fn char* asctime(Tm* timeptr);
extern fn char* ctime(Time_t* timer);
extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);

// Thread-safe versions
extern fn Tm* localtime_r(Time_t* timer, Tm* result);
extern fn Tm* gmtime_r(Time_t* timer, Tm* result);
extern fn char* asctime_r(Tm* timeptr, char* buf);
extern fn char* ctime_r(Time_t* timer, char* buf);

// POSIX functions
extern fn int clock_gettime(int clk_id, TimeSpec* tp);
extern fn int clock_getres(int clk_id, TimeSpec* res);
extern fn int nanosleep(TimeSpec* req, TimeSpec* rem);
extern fn char* strptime(char* s, char* format, Tm* tm);
extern fn void tzset();
extern fn Time_t timegm(Tm* tm);

// Additional structures
struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

struct TimeVal {
    long tv_sec;
    long tv_usec;
}

// Clock_t IDs
const int CLOCK_REALTIME = 0;
const int CLOCK_PROCESS_CPUTIME_ID = 2;
const int CLOCK_MONOTONIC = 3;
const int CLOCK_THREAD_CPUTIME_ID = 4;
const int CLOCK_UPTIME = 5;
const int CLOCK_BOOTTIME = 6;

// Constants
const long CLOCKS_PER_SEC = 100;

// Timer constants
const int TIMER_RELTIME = 0;
const int TIMER_ABSTIME = 1;

// Timezone
extern long timezone;
extern int daylight;
extern char** tzname;

// ========== Windows ==========

module c::time @if(env::WIN32);

// Standard C functions
extern fn Time_t time(Time_t* tloc);
extern fn double difftime(Time_t time1, Time_t time0);
extern fn Clock_t clock();
extern fn Tm* localtime(Time_t* timer);
extern fn Tm* gmtime(Time_t* timer);
extern fn Time_t mktime(Tm* timeptr);
extern fn char* asctime(Tm* timeptr);
extern fn char* ctime(Time_t* timer);
extern fn sz strftime(char* s, sz maxsize, char* format, Tm* timeptr);

// Windows secure versions
extern fn int localtime_s(Tm* result, Time_t* timer);
extern fn int gmtime_s(Tm* result, Time_t* timer);
extern fn int asctime_s(char* buf, sz size, Tm* timeptr);
extern fn int ctime_s(char* buf, sz size, Time_t* timer);

// Windows 64-bit time functions
extern fn long _time64(long* timer);
extern fn Tm* _localtime64(long* timer);
extern fn Tm* _gmtime64(long* timer);
extern fn int _localtime64_s(Tm* result, long* timer);
extern fn int _gmtime64_s(Tm* result, long* timer);
extern fn long _mktime64(Tm* timeptr);
extern fn char* _ctime64(long* timer);
extern fn int _ctime64_s(char* buf, sz size, long* timer);

// Windows timespec (available from Windows 8+)
extern fn int timespec_get(TimeSpec* ts, int base);

// Windows time structures
struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

struct Timeb {
    long time;
    ushort millitm;
    short timezone;
    short dstflag;
}

struct Timeb64 {
    long time;
    ushort millitm;
    short timezone;
    short dstflag;
}

// Windows time functions
extern fn void _ftime(Timeb* timeptr);
extern fn void _ftime64(Timeb64* timeptr);

// Windows does not have these POSIX functions
// Use QueryPerformanceCounter/QueryPerformanceFrequency instead of clock_gettime
// Use Sleep instead of nanosleep

// Constants
const long CLOCKS_PER_SEC = 1000;

// timespec_get base
const int TIME_UTC = 1;

// Timezone (Windows uses _timezone, _daylight, _tzname)
extern long _timezone;
extern int _daylight;
extern char** _tzname;

extern fn void _tzset();

// Note: Windows does not have strptime
// Note: Windows does not have clock_gettime/nanosleep natively
// Use alternative Windows APIs:
// - QueryPerformanceCounter/QueryPerformanceFrequency for high-resolution timing
// - GetSystemTime_t/GetLocalTime_t for system time
// - Sleep/SleepEx for delays
