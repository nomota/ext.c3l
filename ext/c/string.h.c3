// string.h.c3

// string.h C3 Extern Mapping
// Unified for Windows (WIN32) and POSIX systems

module c::string;

// Platform-specific wchar_t handling:
alias Wchar @if(env::WIN32) = ushort;
alias Wchar @if(env::POSIX) = uint;

// Common Functions (All Platforms)

// Copying Functions
extern fn void* memcpy(void* dest, void* src, sz n);
extern fn void* memmove(void* dest, void* src, sz n);
extern fn char* strcpy(char* dest, char* src);
extern fn char* strncpy(char* dest, char* src, sz n);

// Concatenation Functions
extern fn char* strcat(char* dest, char* src);
extern fn char* strncat(char* dest, char* src, sz n);

// Comparison Functions
extern fn CInt memcmp(void* s1, void* s2, sz n);
extern fn CInt strcmp(char* s1, char* s2);
extern fn CInt strncmp(char* s1, char* s2, sz n);
extern fn CInt strcoll(char* s1, char* s2);

// Transformation Functions
extern fn sz strxfrm(char* dest, char* src, sz n);

// Search Functions
extern fn void* memchr(void* s, CInt c, sz n);
extern fn char* strchr(char* s, CInt c);
extern fn sz strcspn(char* s, char* reject);
extern fn char* strpbrk(char* s, char* accept);
extern fn char* strrchr(char* s, CInt c);
extern fn sz strspn(char* s, char* accept);
extern fn char* strstr(char* haystack, char* needle);
extern fn char* strtok(char* str, char* delim);

// Other Functions
extern fn void* memset(void* s, CInt c, sz n);
extern fn char* strerror(CInt errnum);
extern fn sz strlen(char* s);

// C23 / Modern additions (widely available)
extern fn void* memccpy(void* dest, void* src, CInt c, sz n);
extern fn char* strdup(char* s);

// POSIX Extensions

module c::string @if(env::POSIX);

// POSIX String Functions
extern fn CInt strcasecmp(char* s1, char* s2);
extern fn CInt strncasecmp(char* s1, char* s2, sz n);

// String Length (POSIX.1-2008)
extern fn sz strnlen(char* s, sz maxlen);

// String Duplication
extern fn char* strndup(char* s, sz n);

// String Parsing
extern fn char* strsep(char** stringp, char* delim);

// Signal String Functions
extern fn char* strsignal(CInt sig);

// Thread-safe strerror
extern fn CInt strerror_r(CInt errnum, char* buf, sz buflen);

// String Tokenization (reentrant)
extern fn char* strtok_r(char* str, char* delim, char** saveptr);

// BSD Extensions (also in POSIX systems)
extern fn sz strlcpy(char* dest, char* src, sz size);
extern fn sz strlcat(char* dest, char* src, sz size);

// Memory Functions
extern fn void* mempcpy(void* dest, void* src, sz n);  // GNU extension
extern fn void* memrchr(void* s, CInt c, sz n);  // GNU extension
extern fn void* rawmemchr(void* s, CInt c);  // GNU extension
extern fn void* memmem(void* haystack, sz haystacklen, void* needle, sz needlelen);

// String Prefix/Suffix (GNU extensions)
extern fn CInt strverscmp(char* s1, char* s2);

// Explicit memory operations
extern fn void explicit_bzero(void* s, sz n);  // POSIX.1-2008

// Case conversion (non-standard but common)
extern fn char* index(char* s, CInt c);  // Obsolete, use strchr
extern fn char* rindex(char* s, CInt c);  // Obsolete, use strrchr
extern fn void bcopy(void* src, void* dest, sz n);  // Obsolete, use memmove
extern fn void bzero(void* s, sz n);  // Obsolete, use memset
extern fn CInt bcmp(void* s1, void* s2, sz n);  // Obsolete, use memcmp
extern fn CInt ffs(CInt i);  // Find first set bit
extern fn CInt ffsl(CLong i);
extern fn CInt ffsll(CLongLong i);

// String list functions (non-standard)
extern fn char* stpcpy(char* dest, char* src);  // POSIX.1-2008
extern fn char* stpncpy(char* dest, char* src, sz n);  // POSIX.1-2008

// Locale-specific
extern fn char* strcoll_l(char* s1, char* s2, void* locale);
extern fn sz strxfrm_l(char* dest, char* src, sz n, void* locale);
extern fn CInt strcasecmp_l(char* s1, char* s2, void* locale);
extern fn CInt strncasecmp_l(char* s1, char* s2, sz n, void* locale);


// Linux-specific Extensions

module c::string @if(env::LINUX);

// Additional GNU/Linux extensions
extern fn char* strchrnul(char* s, CInt c);  // GNU extension
extern fn char* basename(char* path);  // GNU version (different from POSIX)
extern fn void* memfrob(void* s, sz n);  // GNU extension (obfuscation)

// Windows (WIN32) Extensions

module c::string @if(env::WIN32);

// Secure CRT Functions (_s suffix)
extern fn CInt memcpy_s(void* dest, sz destSize, void* src, sz count);
extern fn CInt memmove_s(void* dest, sz destSize, void* src, sz count);
extern fn CInt strcpy_s(char* dest, sz destSize, char* src);
extern fn CInt strncpy_s(char* dest, sz destSize, char* src, sz count);
extern fn CInt strcat_s(char* dest, sz destSize, char* src);
extern fn CInt strncat_s(char* dest, sz destSize, char* src, sz count);
extern fn CInt strerror_s(char* buffer, sz bufferSize, CInt errnum);
extern fn sz strnlen_s(char* str, sz maxCount);

// Case Conversion (MS-specific, modify in place)
extern fn char* _strlwr(char* str);
extern fn char* _strupr(char* str);
extern fn char* _strlwr_s(char* str, sz size);
extern fn char* _strupr_s(char* str, sz size);

// Locale-specific case conversion
extern fn char* _strlwr_l(char* str, void* locale);
extern fn char* _strupr_l(char* str, void* locale);
extern fn char* _strlwr_s_l(char* str, sz size, void* locale);
extern fn char* _strupr_s_l(char* str, sz size, void* locale);

// String reversal (MS-specific)
extern fn char* _strrev(char* str);

// Set functions (MS-specific)
extern fn char* _strset(char* str, CInt c);
extern fn char* _strnset(char* str, CInt c, sz count);
extern fn char* _strset_s(char* str, sz destSize, CInt c);
extern fn char* _strnset_s(char* str, sz destSize, CInt c, sz count);

// Duplication (MS-specific underscore version)
extern fn char* _strdup(char* str);
extern fn char* _strndup(char* str, sz count);

// Case-insensitive comparison (MS-specific names)
extern fn CInt _stricmp(char* s1, char* s2);
extern fn CInt _strnicmp(char* s1, char* s2, sz count);
extern fn CInt _stricmp_l(char* s1, char* s2, void* locale);
extern fn CInt _strnicmp_l(char* s1, char* s2, sz count, void* locale);

// Collation (MS-specific)
extern fn CInt _strcoll_l(char* s1, char* s2, void* locale);
extern fn CInt _stricoll(char* s1, char* s2);
extern fn CInt _stricoll_l(char* s1, char* s2, void* locale);
extern fn CInt _strncoll(char* s1, char* s2, sz count);
extern fn CInt _strncoll_l(char* s1, char* s2, sz count, void* locale);
extern fn CInt _strnicoll(char* s1, char* s2, sz count);
extern fn CInt _strnicoll_l(char* s1, char* s2, sz count, void* locale);

// Token functions (MS-specific)
extern fn char* _strtok_s(char* str, char* delimiters, char** context);

// Find functions
extern fn char* _strpbrk_l(char* str, char* control, void* locale);
extern fn sz _strspn_l(char* str, char* control, void* locale);
extern fn sz _strcspn_l(char* str, char* control, void* locale);

// Transformation (MS-specific)
extern fn sz _strxfrm_l(char* dest, char* src, sz count, void* locale);

// Additional error functions
extern fn char* _strerror(char* errMsg);
extern fn char* __strerror(CInt errnum);


// Wide Character String Functions (Common across platforms)

module c::string;

// Wide character memory functions
extern fn sz wcslen(Wchar* s);
extern fn Wchar* wcscpy(Wchar* dest, Wchar* src);
extern fn Wchar* wcsncpy(Wchar* dest, Wchar* src, sz n);
extern fn Wchar* wcscat(Wchar* dest, Wchar* src);
extern fn Wchar* wcsncat(Wchar* dest, Wchar* src, sz n);
extern fn CInt wcscmp(Wchar* s1, Wchar* s2);
extern fn CInt wcsncmp(Wchar* s1, Wchar* s2, sz n);
extern fn CInt wcscoll(Wchar* s1, Wchar* s2);
extern fn sz wcsxfrm(Wchar* dest, Wchar* src, sz n);
extern fn Wchar* wcschr(Wchar* s, Wchar c);
extern fn Wchar* wcsrchr(Wchar* s, Wchar c);
extern fn sz wcsspn(Wchar* s, Wchar* accept);
extern fn sz wcscspn(Wchar* s, Wchar* reject);
extern fn Wchar* wcspbrk(Wchar* s, Wchar* accept);
extern fn Wchar* wcsstr(Wchar* haystack, Wchar* needle);
extern fn Wchar* wcstok(Wchar* str, Wchar* delim, Wchar** ptr);
extern fn Wchar* wcsdup(Wchar* s);

// Wide character memory operations
extern fn Wchar* wmemcpy(Wchar* dest, Wchar* src, sz n);
extern fn Wchar* wmemmove(Wchar* dest, Wchar* src, sz n);
extern fn Wchar* wmemset(Wchar* s, Wchar c, sz n);
extern fn CInt wmemcmp(Wchar* s1, Wchar* s2, sz n);
extern fn Wchar* wmemchr(Wchar* s, Wchar c, sz n);


// Wide Character String Functions (POSIX)

module c::string @if(env::POSIX);

// POSIX wide character extensions
extern fn sz wcsnlen(Wchar* s, sz maxlen);
extern fn Wchar* wcsndup(Wchar* s, sz n);
extern fn CInt wcscasecmp(Wchar* s1, Wchar* s2);
extern fn CInt wcsncasecmp(Wchar* s1, Wchar* s2, sz n);
extern fn Wchar* wcpcpy(Wchar* dest, Wchar* src);
extern fn Wchar* wcpncpy(Wchar* dest, Wchar* src, sz n);

// Locale-specific wide character functions
extern fn CInt wcscoll_l(Wchar* s1, Wchar* s2, void* locale);
extern fn sz wcsxfrm_l(Wchar* dest, Wchar* src, sz n, void* locale);
extern fn CInt wcscasecmp_l(Wchar* s1, Wchar* s2, void* locale);
extern fn CInt wcsncasecmp_l(Wchar* s1, Wchar* s2, sz n, void* locale);


// Wide Character String Functions (Windows)

module c::string @if(env::WIN32);

// Secure wide string functions
extern fn CInt wcscpy_s(Wchar* dest, sz destSize, Wchar* src);
extern fn CInt wcsncpy_s(Wchar* dest, sz destSize, Wchar* src, sz count);
extern fn CInt wcscat_s(Wchar* dest, sz destSize, Wchar* src);
extern fn CInt wcsncat_s(Wchar* dest, sz destSize, Wchar* src, sz count);
extern fn sz wcsnlen_s(Wchar* str, sz maxCount);
extern fn CInt wmemcpy_s(Wchar* dest, sz destSize, Wchar* src, sz count);
extern fn CInt wmemmove_s(Wchar* dest, sz destSize, Wchar* src, sz count);

// Wide character case conversion (MS-specific)
extern fn Wchar* _wcslwr(Wchar* str);
extern fn Wchar* _wcsupr(Wchar* str);
extern fn Wchar* _wcslwr_s(Wchar* str, sz size);
extern fn Wchar* _wcsupr_s(Wchar* str, sz size);
extern fn Wchar* _wcslwr_l(Wchar* str, void* locale);
extern fn Wchar* _wcsupr_l(Wchar* str, void* locale);
extern fn Wchar* _wcslwr_s_l(Wchar* str, sz size, void* locale);
extern fn Wchar* _wcsupr_s_l(Wchar* str, sz size, void* locale);

// Wide character reversal (MS-specific)
extern fn Wchar* _wcsrev(Wchar* str);

// Wide character set functions (MS-specific)
extern fn Wchar* _wcsset(Wchar* str, Wchar c);
extern fn Wchar* _wcsnset(Wchar* str, Wchar c, sz count);
extern fn Wchar* _wcsset_s(Wchar* str, sz destSize, Wchar c);
extern fn Wchar* _wcsnset_s(Wchar* str, sz destSize, Wchar c, sz count);

// Wide character duplication (MS-specific)
extern fn Wchar* _wcsdup(Wchar* str);
extern fn Wchar* _wcsndup(Wchar* str, sz count);

// Wide character case-insensitive comparison (MS-specific)
extern fn CInt _wcsicmp(Wchar* s1, Wchar* s2);
extern fn CInt _wcsnicmp(Wchar* s1, Wchar* s2, sz count);
extern fn CInt _wcsicmp_l(Wchar* s1, Wchar* s2, void* locale);
extern fn CInt _wcsnicmp_l(Wchar* s1, Wchar* s2, sz count, void* locale);

// Wide character collation (MS-specific)
extern fn CInt _wcscoll_l(Wchar* s1, Wchar* s2, void* locale);
extern fn CInt _wcsicoll(Wchar* s1, Wchar* s2);
extern fn CInt _wcsicoll_l(Wchar* s1, Wchar* s2, void* locale);
extern fn CInt _wcsncoll(Wchar* s1, Wchar* s2, sz count);
extern fn CInt _wcsncoll_l(Wchar* s1, Wchar* s2, sz count, void* locale);
extern fn CInt _wcsnicoll(Wchar* s1, Wchar* s2, sz count);
extern fn CInt _wcsnicoll_l(Wchar* s1, Wchar* s2, sz count, void* locale);

// Wide character token (MS-specific)
extern fn Wchar* _wcstok_s(Wchar* str, Wchar* delimiters, Wchar** context);

// Wide character transformation (MS-specific)
extern fn sz _wcsxfrm_l(Wchar* dest, Wchar* src, sz count, void* locale);


