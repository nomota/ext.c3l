// stdlib.h.c3

module c::stdlib;

alias LongLong = long;
alias CUint = uint;

// Memory allocation
extern fn void* malloc(sz size);
extern fn void* calloc(sz nmemb, sz size);
extern fn void* realloc(void* ptr, sz size);
extern fn void free(void* ptr);

// Process control
extern fn void exit(int status);
extern fn void _exit(int status) @cname("_Exit");
extern fn void abort();

alias Exitfn = fn void();
extern fn int atexit(Exitfn func);

// Environment Variable
extern fn char* getenv(char* name);
extern fn int system(char* command);

// String conversion
extern fn int atoi(char* nptr);
extern fn CInt atol(char* nptr);
extern fn double atof(char* nptr);
extern fn CInt strtol(char* nptr, char** endptr, int base);
extern fn CUint strtoul(char* nptr, char** endptr, int base);

// Random number generation
extern fn int rand();
extern fn void srand(uint seed);

// Sort and search.
alias Cmpfn = fn int(void*, void*);
extern fn void qsort(void* base, sz nmemb, sz size, Cmpfn compar);
extern fn void* bsearch(void* key, void* base, sz nmemb, sz size, Cmpfn compar);

// Arithmetic operation
extern fn int abs(int j);
extern fn CInt labs(CInt j);
extern fn LongLong llabs(LongLong j);

struct Div {
    int quot;
    int rem;
}

struct LDiv {
    CInt quot;
    CInt rem;
}

struct LLDiv {
    LongLong quot;
    LongLong rem;
}

extern fn Div div(int numer, int denom);
extern fn LDiv ldiv(CInt numer, CInt denom);
extern fn LLDiv lldiv(LongLong numer, LongLong denom);

// String conversion
extern fn float strtof(char* nptr, char** endptr);
extern fn double strtod(char* nptr, char** endptr);
extern fn LongLong strtoll(char* nptr, char** endptr, int base);
extern fn CUint strtoull(char* nptr, char** endptr, int base);

// Multibyte char (Wchar_t = uint) 
extern fn int mblen(char* s, sz n);
extern fn int mbtowc(uint* pwc, char* s, sz n);
extern fn int wctomb(char* s, uint wc);
extern fn sz mbstowcs(uint* pwcs, char* s, sz n);
extern fn sz wcstombs(char* s, uint* pwcs, sz n);

// Aligned memory allocation (C11)
extern fn void* aligned_alloc(sz alignment, sz size);

// Environment variable and process
extern fn int at_quick_exit(Exitfn func);
extern fn void quick_exit(int status);
extern fn int setenv(char* name, char* value, int overwrite) @if(!env::WIN32);
extern fn int unsetenv(char* name) @if(!env::WIN32);
extern fn int _putenv(char* envstr) @if(env::WIN32);
extern fn int _putenv_s(char* name, char* value) @if(env::WIN32);
extern fn char* mkdtemp(char* template);
extern fn int mkstemp(char* template) @if(!env::WIN32);

// Random numbers-
extern fn CInt lrand48() @if(!env::WIN32);
extern fn double erand48(ushort[3] xsubi) @if(!env::WIN32);
extern fn void srand48(CInt seedval) @if(!env::WIN32);

// Random number, thread safe (POSIX)
extern fn int rand_r(uint* seedp) @if(!env::WIN32);
extern fn int rand_s(uint* randVal) @if(env::WIN32);
// Pathnames absolute path
extern fn char* realpath(char* path, char* resolved_path) @if(!env::WIN32);
extern fn char* _fullpath(char* path, char* resolved, int max) @if(env::WIN32);

// Binary tree search (POSIX/GNU)
extern fn void* tsearch(void* key, void** rootp, Cmpfn compar);
extern fn void* tfind(void* key, void** rootp, Cmpfn compar);
extern fn void* tdelete(void* key, void** rootp, Cmpfn compar);

// Dynamic loading, shared mem (Some platform)
// POSIX / stdlib.h
extern fn int grantpt(int fd);
extern fn int unlockpt(int fd);
extern fn char* ptsname(int fd);

// Floating point conversion (High precision)
extern fn char* ecvt(double value, int ndigit, int* decpt, int* sign);
extern fn char* fcvt(double value, int ndigit, int* decpt, int* sign);

// Memory align (POSIX)
extern fn int posix_memalign(void** memptr, sz alignment, sz size);
