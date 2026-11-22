/* stdio.h - cc816 (Horizon C SDK; lib/cc816/stdio.c, printf.c, scanf.c).
 * stdout and stderr: the console, line-buffered; stdin: a line typed at the keyboard;
 * files on the card, buffered (1 KB a file from the heap; a smaller buffer, or none, when
 * the heap has no room: fopen does not fail for want of it). Horizon has 4 file handles for the whole
 * system (fopen fails with errno ENFILE when none is left). printf's %f %e %g %a and
 * scanf's %f are there in programs that use floating point (docs/c/reference.md). */
#ifndef _STDIO_H
#define _STDIO_H
#include <stddef.h>
#include <stdarg.h>
#define EOF (-1)
#define BUFSIZ 1024
#define FOPEN_MAX 4
#define FILENAME_MAX 128
#define L_tmpnam 16
#define TMP_MAX 0
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
typedef long fpos_t;
typedef struct __hz_file {
    unsigned char *base;        /* the buffer */
    unsigned char *ptr;         /* the next byte in it */
    unsigned cnt;               /* reading: bytes left; writing: bytes room */
    unsigned size;              /* the buffer's size */
    unsigned flags;             /* (lib/cc816/stdio.c) */
    int fh;                     /* the Horizon handle, -1 for the console */
    int ungot;                  /* ungetc's character, or EOF */
    long pos;                   /* the handle's position on the card */
    long fsize;                 /* the file's size (SEEK_END) */
    struct __hz_file *next;     /* every open file */
    unsigned char tiny[2];      /* the buffer when the heap has no room for one */
} FILE;
extern FILE *stdin, *stdout, *stderr;

FILE *fopen(const char *name, const char *mode);
FILE *freopen(const char *name, const char *mode, FILE *f);
int fclose(FILE *f);
int fflush(FILE *f);
void setbuf(FILE *f, char *buf);
int setvbuf(FILE *f, char *buf, int mode, size_t size);
int remove(const char *name);
int rename(const char *from, const char *to);
FILE *tmpfile(void);
char *tmpnam(char *s);

int fgetc(FILE *f);
int getc(FILE *f);
int getchar(void);
char *fgets(char *s, int n, FILE *f);
int ungetc(int c, FILE *f);
int fputc(int c, FILE *f);
int putc(int c, FILE *f);
int putchar(int c);
int fputs(const char *s, FILE *f);
int puts(const char *s);
size_t fread(void *p, size_t size, size_t n, FILE *f);
size_t fwrite(const void *p, size_t size, size_t n, FILE *f);

int fseek(FILE *f, long off, int whence);
long ftell(FILE *f);
void rewind(FILE *f);
int fgetpos(FILE *f, fpos_t *pos);
int fsetpos(FILE *f, const fpos_t *pos);
int feof(FILE *f);
int ferror(FILE *f);
void clearerr(FILE *f);
void perror(const char *s);

int printf(const char *fmt, ...);
int fprintf(FILE *f, const char *fmt, ...);
int sprintf(char *buf, const char *fmt, ...);
int snprintf(char *buf, size_t n, const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vsprintf(char *buf, const char *fmt, va_list ap);
int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);
int scanf(const char *fmt, ...);
int fscanf(FILE *f, const char *fmt, ...);
int sscanf(const char *s, const char *fmt, ...);
int vscanf(const char *fmt, va_list ap);
int vfscanf(FILE *f, const char *fmt, va_list ap);
int vsscanf(const char *s, const char *fmt, va_list ap);
#endif
