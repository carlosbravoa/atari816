/* stdlib.c - stdlib.h's numbers for cc816: atoi atol strtol strtoul abs labs div ldiv
 * rand srand, and the parts Horizon has no use for (getenv, system). */
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>

static unsigned long scan(const char *s, char **end, int base, int *neg, int *ovf)
{
    const char *p = s, *start;
    unsigned long v = 0, lim;
    unsigned d, rem;
    int any = 0;
    *neg = 0;
    *ovf = 0;
    while (isspace((unsigned char)*p))
        ++p;
    if (*p == '-' || *p == '+')
        *neg = *p++ == '-';
    if ((base == 0 || base == 16) && *p == '0' && (p[1] == 'x' || p[1] == 'X') &&
        isxdigit((unsigned char)p[2])) {
        p += 2;
        base = 16;
    } else if (base == 0)
        base = *p == '0' ? 8 : 10;
    if (base < 2 || base > 36) {
        errno = EINVAL;
        if (end)
            *end = (char *)s;
        return 0;
    }
    lim = ULONG_MAX / (unsigned)base;
    rem = (unsigned)(ULONG_MAX % (unsigned)base);
    start = p;
    for (;; ++p) {
        unsigned c = (unsigned char)*p;
        if (c >= '0' && c <= '9')
            d = c - '0';
        else if (c >= 'a' && c <= 'z')
            d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z')
            d = c - 'A' + 10;
        else
            break;
        if (d >= (unsigned)base)
            break;
        any = 1;
        if (v > lim || (v == lim && d > rem))
            *ovf = 1;
        else
            v = v * (unsigned)base + d;
    }
    if (end)
        *end = (char *)(any ? p : s);
    (void)start;
    return v;
}

long strtol(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long v = scan(s, end, base, &neg, &ovf);
    if (ovf || (!neg && v > (unsigned long)LONG_MAX) || (neg && v > (unsigned long)LONG_MAX + 1)) {
        errno = ERANGE;
        return neg ? LONG_MIN : LONG_MAX;
    }
    return neg ? (long)(0UL - v) : (long)v;
}

unsigned long strtoul(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long v = scan(s, end, base, &neg, &ovf);
    if (ovf) {
        errno = ERANGE;
        return ULONG_MAX;
    }
    return neg ? 0UL - v : v;
}

int atoi(const char *s)
{
    return (int)strtol(s, 0, 10);
}

long atol(const char *s)
{
    return strtol(s, 0, 10);
}

int abs(int x)
{
    return x < 0 ? -x : x;
}

long labs(long x)
{
    return x < 0 ? -x : x;
}

div_t div(int a, int b)
{
    div_t r;
    r.quot = a / b;
    r.rem = a % b;
    return r;
}

ldiv_t ldiv(long a, long b)
{
    ldiv_t r;
    r.quot = a / b;
    r.rem = a % b;
    return r;
}

static unsigned long seed = 1;

int rand(void)
{
    seed = seed * 1103515245UL + 12345;
    return (int)((unsigned)(seed >> 16) & 0x7FFF);
}

void srand(unsigned s)
{
    seed = s;
}

char *getenv(const char *name)
{
    (void)name;
    return 0;
}

int system(const char *cmd)
{
    return cmd ? -1 : 0;
}
