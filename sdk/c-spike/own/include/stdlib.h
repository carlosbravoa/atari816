#ifndef _STDLIB_H
#define _STDLIB_H
#include <stddef.h>
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 32767
void *malloc(size_t n);
void *calloc(size_t n, size_t m);
void *realloc(void *p, size_t n);
void free(void *p);
void exit(int code);
void abort(void);
int atexit(void (*f)(void));
int abs(int x);
long labs(long x);
int atoi(const char *s);
long atol(const char *s);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
int rand(void);
void srand(unsigned seed);
void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t n, size_t size, int (*cmp)(const void *, const void *));
typedef struct { int quot, rem; } div_t;
typedef struct { long quot, rem; } ldiv_t;
div_t div(int a, int b);
ldiv_t ldiv(long a, long b);
#endif
