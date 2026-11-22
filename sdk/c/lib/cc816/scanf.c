/* scanf.c - scanf, fscanf, vscanf, vfscanf (cc816; the reading: scan.c) */
#include <stdio.h>
#include <stdarg.h>

int __hz_vscan(int (*get)(void *), void (*unget)(int, void *), void *ctx, const char *fmt,
               va_list ap);

static int fget(void *ctx)
{
    return fgetc((FILE *)ctx);
}

static void funget(int c, void *ctx)
{
    ungetc(c, (FILE *)ctx);
}

int vfscanf(FILE *f, const char *fmt, va_list ap)
{
    return __hz_vscan(fget, funget, f, fmt, ap);
}

int vscanf(const char *fmt, va_list ap)
{
    return __hz_vscan(fget, funget, stdin, fmt, ap);
}

int fscanf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = __hz_vscan(fget, funget, f, fmt, ap);
    va_end(ap);
    return r;
}

int scanf(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = __hz_vscan(fget, funget, stdin, fmt, ap);
    va_end(ap);
    return r;
}
