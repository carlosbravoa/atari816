/* sscanf.c - sscanf, vsscanf (cc816; the reading: scan.c) */
#include <stdio.h>
#include <stdarg.h>

int __hz_vscan(int (*get)(void *), void (*unget)(int, void *), void *ctx, const char *fmt,
               va_list ap);

static int sget(void *ctx)
{
    const unsigned char **p = ctx;
    if (!**p)
        return EOF;
    return *(*p)++;
}

static void sunget(int c, void *ctx)
{
    const unsigned char **p = ctx;
    (void)c;
    --*p;
}

int vsscanf(const char *s, const char *fmt, va_list ap)
{
    const unsigned char *p = (const unsigned char *)s;
    return __hz_vscan(sget, sunget, &p, fmt, ap);
}

int sscanf(const char *s, const char *fmt, ...)
{
    va_list ap;
    int r;
    const unsigned char *p = (const unsigned char *)s;
    va_start(ap, fmt);
    r = __hz_vscan(sget, sunget, &p, fmt, ap);
    va_end(ap);
    return r;
}
