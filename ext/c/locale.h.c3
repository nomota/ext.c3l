// locale.h.c3

// Nomota <hiongun@gmail.com>; MIT License

module c::locale;


// Locale information

struct LConv
{
    char* decimal_point;
    char* thousands_sep;
    char* grouping;

    char* int_curr_symbol;
    char* currency_symbol;
    char* mon_decimal_point;
    char* mon_thousands_sep;
    char* mon_grouping;

    char* positive_sign;
    char* negative_sign;

    char int_frac_digits;
    char frac_digits;

    char p_cs_precedes;
    char p_sep_by_space;
    char n_cs_precedes;
    char n_sep_by_space;

    char p_sign_posn;
    char n_sign_posn;

    char int_p_cs_precedes;
    char int_p_sep_by_space;
    char int_n_cs_precedes;
    char int_n_sep_by_space;

    char int_p_sign_posn;
    char int_n_sign_posn;
}


// Standard locale functions

extern fn char* setlocale(int category, char* locale);

extern fn LConv* localeconv();


// POSIX constants
//
// These values follow the Linux/glibc locale.h definitions.

module c::locale @if(env::POSIX);

const int LC_CTYPE = 0;
const int LC_NUMERIC = 1;
const int LC_TIME = 2;
const int LC_COLLATE = 3;
const int LC_MONETARY = 4;
const int LC_MESSAGES = 5;
const int LC_ALL = 6;

const int LC_CTYPE_MASK = 1 << LC_CTYPE;
const int LC_NUMERIC_MASK = 1 << LC_NUMERIC;
const int LC_TIME_MASK = 1 << LC_TIME;
const int LC_COLLATE_MASK = 1 << LC_COLLATE;
const int LC_MONETARY_MASK = 1 << LC_MONETARY;
const int LC_MESSAGES_MASK = 1 << LC_MESSAGES;

const int LC_ALL_MASK =
    LC_CTYPE_MASK |
    LC_NUMERIC_MASK |
    LC_TIME_MASK |
    LC_COLLATE_MASK |
    LC_MONETARY_MASK |
    LC_MESSAGES_MASK;


// POSIX locale objects

alias LocaleT = void*;

extern fn LocaleT newlocale(int category_mask, char* locale, LocaleT base);

extern fn LocaleT duplocale(LocaleT locale);

extern fn void freelocale(LocaleT locale);

extern fn LocaleT uselocale(LocaleT locale);


// Windows constants

module c::locale @if(env::WIN32);

const int LC_ALL = 0;
const int LC_COLLATE = 1;
const int LC_CTYPE = 2;
const int LC_MONETARY = 3;
const int LC_NUMERIC = 4;
const int LC_TIME = 5;

const int LC_MIN = LC_ALL;
const int LC_MAX = LC_TIME;


// Windows locale objects

alias LocaleT = void*;

const int DISABLE_PER_THREAD_LOCALE = 0;
const int ENABLE_PER_THREAD_LOCALE = 1;

extern fn LocaleT create_locale(int category, char* locale) @cname("_create_locale");

extern fn void free_locale(LocaleT locale) @cname("_free_locale");

extern fn int config_thread_locale(int type) @cname("_configthreadlocale");

// eof