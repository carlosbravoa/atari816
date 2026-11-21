#ifndef _STDIO_H
#define _STDIO_H
#include <stddef.h>
#include <stdarg.h>
#define EOF (-1)
#define BUFSIZ 128
typedef struct { int fd; } FILE;
extern FILE *stdin, *stdout, *stderr;
int putchar(int c);
int puts(const char *s);
int fputs(const char *s, FILE *f);
int fputc(int c, FILE *f);
#define putc(c, f) fputc(c, f)
int getchar(void);
int fflush(FILE *f);
int printf(const char *fmt, ...);
int fprintf(FILE *f, const char *fmt, ...);
int sprintf(char *buf, const char *fmt, ...);
int snprintf(char *buf, size_t n, const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vsprintf(char *buf, const char *fmt, va_list ap);
int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define FILENAME_MAX 128
#define FOPEN_MAX 4
FILE *fopen(const char *name, const char *mode);
int fclose(FILE *f);
size_t fread(void *p, size_t size, size_t n, FILE *f);
size_t fwrite(const void *p, size_t size, size_t n, FILE *f);
int fseek(FILE *f, long off, int whence);
long ftell(FILE *f);
void rewind(FILE *f);
int fgetc(FILE *f);
#define getc(f) fgetc(f)
char *fgets(char *s, int n, FILE *f);
int ungetc(int c, FILE *f);
int feof(FILE *f);
int ferror(FILE *f);
void clearerr(FILE *f);
int remove(const char *name);
int rename(const char *old, const char *new_);
void perror(const char *s);
int sscanf(const char *s, const char *fmt, ...);
#endif
