/* variadic.c - variable arguments: va_arg of every size, va_copy, a va_list given on
 * (vsprintf), promoted chars and floats. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static long sum(int n, ...)
{
    va_list ap, ap2;
    long s = 0, s2 = 0;
    int i;
    va_start(ap, n);
    va_copy(ap2, ap);
    for (i = 0; i < n; i++)
        s += va_arg(ap, int);
    for (i = 0; i < n; i++)
        s2 += va_arg(ap2, int);
    va_end(ap2);
    va_end(ap);
    return s == s2 ? s : -1;
}

static int mixed(const char *fmt, ...)
{
    va_list ap;
    int bad = 0;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        switch (*fmt) {
        case 'i': bad |= va_arg(ap, int) != -7; break;
        case 'c': bad |= va_arg(ap, int) != 'q'; break;        /* a char comes as an int */
        case 'l': bad |= va_arg(ap, long) != 100000L; break;
        case 'd': bad |= va_arg(ap, double) != 2.5; break;    /* a float comes as a double */
        case 'p': bad |= strcmp(va_arg(ap, char *), "str") != 0; break;
        case 'u': bad |= va_arg(ap, unsigned) != 65535u; break;
        }
    }
    va_end(ap);
    return bad;
}

static int format(char *buf, const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vsprintf(buf, fmt, ap);
    va_end(ap);
    return n;
}

int main(void)
{
    char buf[40];
    char c = 'q';
    float f = 2.5f;
    if (sum(4, 1, 2, 3, 30000) != 30006L || sum(0) != 0)
        return 1;
    if (mixed("iclpdu", -7, c, 100000L, "str", f, 65535u))
        return 2;
    if (format(buf, "%d-%ld-%s", 12, 70000L, "x") != 10 || strcmp(buf, "12-70000-x") != 0)
        return 3;
    return 0;
}
