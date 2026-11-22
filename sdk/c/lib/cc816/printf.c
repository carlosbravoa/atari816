/* printf.c - printf, fprintf, vprintf, vfprintf (cc816; the formatting: fmt.c) */
#include <stdio.h>
#include <stdarg.h>

int __hz_vformat(void (*out)(int c, void *ctx), void *ctx, const char *fmt, va_list ap);

static void to_file(int c, void *ctx)
{
    fputc(c, (FILE *)ctx);
}

int vfprintf(FILE *f, const char *fmt, va_list ap)
{
    int n = __hz_vformat(to_file, f, fmt, ap);
    return ferror(f) ? -1 : n;
}

int vprintf(const char *fmt, va_list ap)
{
    return vfprintf(stdout, fmt, ap);
}

int fprintf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vfprintf(f, fmt, ap);
    va_end(ap);
    return n;
}

int printf(const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vfprintf(stdout, fmt, ap);
    va_end(ap);
    return n;
}
