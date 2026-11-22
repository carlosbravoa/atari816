/* stdlibll.c - stdlib.h's long long functions for cc816: strtoll strtoull atoll llabs
 * lldiv (inttypes.h's strtoimax strtoumax imaxabs imaxdiv are macros for them). */
#include <stdlib.h>
#include <errno.h>
#include <limits.h>

static unsigned long long scanll(const char *s, char **end, int base, int *neg, int *ovf)
{
    const char *p = s;
    unsigned long long v = 0, lim;
    unsigned d, rem;
    int any = 0;
    *neg = 0;
    *ovf = 0;
    while (*p == ' ' || (*p >= '\t' && *p <= '\r'))
        ++p;
    if (*p == '-' || *p == '+')
        *neg = *p++ == '-';
    if ((base == 0 || base == 16) && *p == '0' && (p[1] == 'x' || p[1] == 'X') &&
        ((p[2] >= '0' && p[2] <= '9') || ((p[2] | 32) >= 'a' && (p[2] | 32) <= 'f'))) {
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
    lim = ULLONG_MAX / (unsigned)base;
    rem = (unsigned)(ULLONG_MAX % (unsigned)base);
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
    return v;
}

long long strtoll(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long long v = scanll(s, end, base, &neg, &ovf);
    if (ovf || (!neg && v > (unsigned long long)LLONG_MAX) ||
        (neg && v > (unsigned long long)LLONG_MAX + 1)) {
        errno = ERANGE;
        return neg ? LLONG_MIN : LLONG_MAX;
    }
    return neg ? (long long)(0ULL - v) : (long long)v;
}

unsigned long long strtoull(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long long v = scanll(s, end, base, &neg, &ovf);
    if (ovf) {
        errno = ERANGE;
        return ULLONG_MAX;
    }
    return neg ? 0ULL - v : v;
}

long long atoll(const char *s)
{
    return strtoll(s, 0, 10);
}

long long llabs(long long x)
{
    return x < 0 ? -x : x;
}

lldiv_t lldiv(long long a, long long b)
{
    lldiv_t r;
    r.quot = a / b;
    r.rem = a % b;
    return r;
}
