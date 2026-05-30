// regex.h.c3

module c::regex;

// ========== Linux ==========

module c::regex @if(env::LINUX);

// Type Definitions
struct RegEx {
    sz re_nsub;      // Number of parenthesized subexpressions
    void* re_pcre;    // Compiled pattern (opaque)
    sz re_erroffset; // Error offset
    void* re_extra;   // Extra data
    uint re_flags;    // Flags
    void*[10] others;
}

struct RegMatch {
    int rm_so;  // Start offset of match
    int rm_eo;  // End offset of match
}

alias RegoffT = int;

// Function Declarations
extern fn int regcomp(RegEx* preg, char* pattern, int cflags);
extern fn int regexec(RegEx* preg, char* string, sz nmatch, RegMatch* pmatch, int eflags);
extern fn sz regerror(int errcode, RegEx* preg, char* errbuf, sz errbuf_size);
extern fn void regfree(RegEx* preg);

// Compilation flags (cflags)
const int REG_EXTENDED = 1;      // Use Extended Regular Expressions
const int REG_ICASE = 2;         // Ignore case in match
const int REG_NOSUB = 4;         // Report only success/fail
const int REG_NEWLINE = 8;       // Change behavior of . and [^...]

// Execution flags (eflags)
const int REG_NOTBOL = 1;        // First character not beginning of line
const int REG_NOTEOL = 2;        // Last character not end of line

// Error codes
const int REG_NOMATCH = 1;       // regexec() failed to match
const int REG_BADPAT = 2;        // Invalid regular expression
const int REG_ECOLLATE = 3;      // Invalid collating element
const int REG_ECTYPE = 4;        // Invalid character class name
const int REG_EESCAPE = 5;       // Trailing backslash
const int REG_ESUBREG = 6;       // Invalid back reference
const int REG_EBRACK = 7;        // Unmatched [ or [^
const int REG_EPAREN = 8;        // Unmatched ( or \(
const int REG_EBRACE = 9;        // Unmatched { or \{
const int REG_BADBR = 10;        // Invalid content of {...}
const int REG_ERANGE = 11;       // Invalid range endpoint
const int REG_ESPACE = 12;       // Out of memory
const int REG_BADRPT = 13;       // Invalid use of repetition operators

// Additional Linux-specific flags
const int REG_PEND = 32;         // Use re_endp field
const int REG_DUMP = 128;        // Unused
const int REG_LARGE = 256;       // Force large automaton
const int REG_INVARG = 16;       // Invalid argument
const int REG_ATOI = 64;         // Convert to integer
const int REG_BACKR = 512;       // Force use of backref code

// ========== Darwin (macOS) ==========

module c::regex @if(env::DARWIN);

// Type Definitions
struct RegEx {
    int re_magic;
    sz re_nsub;
    char* re_endp;
    void* re_g;
}

struct RegMatch {
    int rm_so;
    int rm_eo;
}

// Function Declarations
extern fn int regcomp(RegEx* preg, char* pattern, int cflags);
extern fn int regexec(RegEx* preg, char* string, sz nmatch, RegMatch* pmatch, int eflags);
extern fn sz regerror(int errcode, RegEx* preg, char* errbuf, sz errbuf_size);
extern fn void regfree(RegEx* preg);

// Compilation flags (cflags)
const int REG_BASIC = 0;         // Basic Regular Expressions (default)
const int REG_EXTENDED = 1;      // Extended Regular Expressions
const int REG_ICASE = 2;         // Ignore case
const int REG_NOSUB = 4;         // Report only success/fail
const int REG_NEWLINE = 8;       // Change newline behavior
const int REG_NOSPEC = 16;       // Treat all characters as literal
const int REG_PEND = 32;         // Use re_endp for pattern end
const int REG_DUMP = 128;        // Dump compiled pattern

// Execution flags (eflags)
const int REG_NOTBOL = 1;        // First character not beginning of line
const int REG_NOTEOL = 2;        // Last character not end of line
const int REG_STARTEND = 4;      // Use pmatch[0] for start/end
const int REG_TRACE = 256;       // Trace execution
const int REG_LARGE = 512;       // Force large automaton
const int REG_BACKR = 1024;      // Force use of backref code

// Error codes
const int REG_NOMATCH = 1;       // regexec() failed to match
const int REG_BADPAT = 2;        // Invalid regular expression
const int REG_ECOLLATE = 3;      // Invalid collating element
const int REG_ECTYPE = 4;        // Invalid character class
const int REG_EESCAPE = 5;       // Trailing backslash
const int REG_ESUBREG = 6;       // Invalid back reference
const int REG_EBRACK = 7;        // Unmatched []
const int REG_EPAREN = 8;        // Unmatched ()
const int REG_EBRACE = 9;        // Unmatched {}
const int REG_BADBR = 10;        // Invalid {} content
const int REG_ERANGE = 11;       // Invalid range endpoint
const int REG_ESPACE = 12;       // Out of memory
const int REG_BADRPT = 13;       // Invalid repetition
const int REG_EMPTY = 14;        // Empty (sub)expression
const int REG_ASSERT = 15;       // Can't happen
const int REG_INVARG = 16;       // Invalid argument
const int REG_ILLSEQ = 17;       // Illegal byte sequence

// macOS-specific
const int REG_ATOI = 255;        // Convert error code to name
const int REG_ITOA = 256;        // Convert name to error code

// ========== FreeBSD ==========

module c::regex @if(env::FREEBSD);

// Type Definitions
struct RegEx  {
    int re_magic;
    sz re_nsub;
    char* re_endp;
    void* re_guts;
    int re_flags;
}

struct RegMatch {
    int rm_so;
    int rm_eo;
}

alias RegoffT = int;

// Function Declarations
extern fn int regcomp(RegEx* preg, char* pattern, int cflags);
extern fn int regexec(RegEx* preg, char* string, sz nmatch, RegMatch* pmatch, int eflags);
extern fn sz regerror(int errcode, RegEx* preg, char* errbuf, sz errbuf_size);
extern fn void regfree(RegEx* preg);

// Additional FreeBSD functions
extern fn int regncomp(RegEx* preg, char* pattern, sz len, int cflags);
extern fn int regnexec(RegEx* preg, char* string, sz len, sz nmatch, RegMatch* pmatch, int eflags);

// Compilation flags (cflags)
const int REG_BASIC = 0;
const int REG_EXTENDED = 1;
const int REG_ICASE = 2;
const int REG_NOSUB = 4;
const int REG_NEWLINE = 8;
const int REG_NOSPEC = 16;
const int REG_PEND = 32;
const int REG_DUMP = 128;

// Execution flags (eflags)
const int REG_NOTBOL = 1;
const int REG_NOTEOL = 2;
const int REG_STARTEND = 4;
const int REG_TRACE = 256;
const int REG_LARGE = 512;
const int REG_BACKR = 1024;

// Error codes
const int REG_NOMATCH = 1;
const int REG_BADPAT = 2;
const int REG_ECOLLATE = 3;
const int REG_ECTYPE = 4;
const int REG_EESCAPE = 5;
const int REG_ESUBREG = 6;
const int REG_EBRACK = 7;
const int REG_EPAREN = 8;
const int REG_EBRACE = 9;
const int REG_BADBR = 10;
const int REG_ERANGE = 11;
const int REG_ESPACE = 12;
const int REG_BADRPT = 13;
const int REG_EMPTY = 14;
const int REG_ASSERT = 15;
const int REG_INVARG = 16;
const int REG_ILLSEQ = 17;

const int REG_ATOI = 255;
const int REG_ITOA = 256;

// ========== NetBSD ==========

module c::regex @if(env::NETBSD);

// Type Definitions
struct RegEx  {
    int re_magic;
    sz re_nsub;
    char* re_endp;
    void* re_guts;
}

struct RegMatch {
    int rm_so;
    int rm_eo;
}

alias RegoffT = int;

// Function Declarations
extern fn int regcomp(RegEx* preg, char* pattern, int cflags);
extern fn int regexec(RegEx* preg, char* string, sz nmatch, RegMatch* pmatch, int eflags);
extern fn sz regerror(int errcode, RegEx* preg, char* errbuf, sz errbuf_size);
extern fn void regfree(RegEx* preg);

// Compilation flags (cflags)
const int REG_BASIC = 0;
const int REG_EXTENDED = 1;
const int REG_ICASE = 2;
const int REG_NOSUB = 4;
const int REG_NEWLINE = 8;
const int REG_NOSPEC = 16;
const int REG_PEND = 32;
const int REG_DUMP = 128;

// Execution flags (eflags)
const int REG_NOTBOL = 1;
const int REG_NOTEOL = 2;
const int REG_STARTEND = 4;
const int REG_TRACE = 256;
const int REG_LARGE = 512;
const int REG_BACKR = 1024;

// Error codes
const int REG_NOMATCH = 1;
const int REG_BADPAT = 2;
const int REG_ECOLLATE = 3;
const int REG_ECTYPE = 4;
const int REG_EESCAPE = 5;
const int REG_ESUBREG = 6;
const int REG_EBRACK = 7;
const int REG_EPAREN = 8;
const int REG_EBRACE = 9;
const int REG_BADBR = 10;
const int REG_ERANGE = 11;
const int REG_ESPACE = 12;
const int REG_BADRPT = 13;
const int REG_EMPTY = 14;
const int REG_ASSERT = 15;
const int REG_INVARG = 16;
const int REG_ILLSEQ = 17;

const int REG_ATOI = 255;
const int REG_ITOA = 256;

// ========== OpenBSD ==========

module c::regex @if(env::OPENBSD);

// Type Definitions
struct RegEx  {
    int re_magic;
    sz re_nsub;
    char* re_endp;
    void* re_guts;
}

struct RegMatch {
    int rm_so;
    int rm_eo;
}

alias RegoffT = int;

// Function Declarations
extern fn int regcomp(RegEx* preg, char* pattern, int cflags);
extern fn int regexec(RegEx* preg, char* string, sz nmatch, RegMatch* pmatch, int eflags);
extern fn sz regerror(int errcode, RegEx* preg, char* errbuf, sz errbuf_size);
extern fn void regfree(RegEx* preg);

// Compilation flags (cflags)
const int REG_BASIC = 0;
const int REG_EXTENDED = 1;
const int REG_ICASE = 2;
const int REG_NOSUB = 4;
const int REG_NEWLINE = 8;
const int REG_NOSPEC = 16;
const int REG_PEND = 32;
const int REG_DUMP = 128;

// Execution flags (eflags)
const int REG_NOTBOL = 1;
const int REG_NOTEOL = 2;
const int REG_STARTEND = 4;
const int REG_TRACE = 256;
const int REG_LARGE = 512;
const int REG_BACKR = 1024;

// Error codes
const int REG_NOMATCH = 1;
const int REG_BADPAT = 2;
const int REG_ECOLLATE = 3;
const int REG_ECTYPE = 4;
const int REG_EESCAPE = 5;
const int REG_ESUBREG = 6;
const int REG_EBRACK = 7;
const int REG_EPAREN = 8;
const int REG_EBRACE = 9;
const int REG_BADBR = 10;
const int REG_ERANGE = 11;
const int REG_ESPACE = 12;
const int REG_BADRPT = 13;
const int REG_EMPTY = 14;
const int REG_ASSERT = 15;
const int REG_INVARG = 16;
const int REG_ILLSEQ = 17;

const int REG_ATOI = 255;
const int REG_ITOA = 256;

// ========== Windows ==========

// Note: Windows does not have POSIX regex.h natively
// You need to use:
// 1. Third-party libraries (PCRE, Boost.Regex, etc.)
// 2. C++11 <regex> (if using C++)
// 3. Windows-specific pattern matching APIs


