// stdio.h.c3

// Nomota <hiongun@gmail.com>; MIT License

module c::stdio;

alias Size = sz;
alias CFile = void*;


// Constants

const int EOF = -1;

const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;

const int _IOFBF = 0;
const int _IOLBF = 1;
const int _IONBF = 2;

const int FILENAME_MAX = 260;
const int FOPEN_MAX = 20;
const int TMP_MAX = 32767;
const int BUFSIZ = 512;
const int L_TMPNAM = 260;


// Standard streams

extern CFile stdin;
extern CFile stdout;
extern CFile stderr;


// Standard I/O

extern fn int printf(char* format, ...);
extern fn int scanf(char* format, ...);

extern fn int puts(char* s);
extern fn int putchar(int c);
extern fn int getchar();

extern fn int perror(char* s);


// File operations

extern fn CFile fopen(char* filename, char* mode);
extern fn CFile freopen(char* filename, char* mode, CFile stream);
extern fn CFile fdopen(int fd, char* mode);

extern fn int fclose(CFile stream);
extern fn int fflush(CFile stream);

extern fn int remove(char* filename);
extern fn int rename(char* oldname, char* newname);

extern fn CFile tmpfile();
extern fn char* tmpnam(char* s);


// File I/O

extern fn int fprintf(CFile stream, char* format, ...);
extern fn int fscanf(CFile stream, char* format, ...);

extern fn char* fgets(char* s, int n, CFile stream);
extern fn int fputs(char* s, CFile stream);

extern fn Size fread(void* ptr, Size size, Size nmemb, CFile stream);
extern fn Size fwrite(void* ptr, Size size, Size nmemb, CFile stream);

extern fn int fgetc(CFile stream);
extern fn int fputc(int c, CFile stream);
extern fn int ungetc(int c, CFile stream);

extern fn int feof(CFile stream);
extern fn int ferror(CFile stream);
extern fn void clearerr(CFile stream);


// File positioning

extern fn int fseek(CFile stream, long offset, int whence);
extern fn long ftell(CFile stream);
extern fn void rewind(CFile stream);

// Buffer control

extern fn int setvbuf(CFile stream, char* buffer, int mode, Size size);
extern fn void setbuf(CFile stream, char* buffer);


// String I/O

extern fn int sprintf(char* str, char* format, ...);
extern fn int snprintf(char* str, Size size, char* format, ...);
extern fn int sscanf(char* str, char* format, ...);


// Character I/O aliases

extern fn int getc(CFile stream);
extern fn int putc(int c, CFile stream);

// POSIX helpers

module c::stdio @if(env::POSIX);

extern fn int fileno(CFile stream);
extern fn CFile popen(char* command, char* mode);
extern fn int pclose(CFile stream);


// Windows helpers

module c::stdio @if(env::WIN32);

extern fn int _fseeki64(CFile stream, long offset, int whence);
extern fn long _ftelli64(CFile stream);

extern fn int fileno(CFile stream) @cname("_fileno");
extern fn CFile popen(char* command, char* mode) @cname("_popen");
extern fn int pclose(CFile stream) @cname("_pclose");

// eof