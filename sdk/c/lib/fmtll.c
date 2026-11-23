/* fmtll.c - printf's long long conversions for cc816: %lld %lli %llu %llo %llx %llX (and
 * j: intmax_t is long long), linked only into programs that use long long
 * (rt/ll_hookp.s installs __hz_fmtll as fmt.c's __hz_fmt_ll). The flags, width and
 * precision as fmt.c does them for the shorter sizes. */
#include <stdarg.h>
#include <string.h>

typedef void (*hz_outfn)(int c, void *ctx);

int __hz_fmtll(hz_outfn out, void *ctx, unsigned c, unsigned flags, unsigned width,
               unsigned uprec, int hasprec, va_list ap)
{
    int prec = hasprec ? (int)uprec : -1;
    char num[24];
    const char *digits = c == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
    const char *prefix = "", *s;
    unsigned base, len, zeros, pad, plen, i;
    unsigned long long v;
    char *p;
    switch (c) {
    case 'd':
    case 'i': {
        long long x = va_arg(ap, long long);
        v = x < 0 ? 0ULL - (unsigned long long)x : (unsigned long long)x;
        prefix = x < 0 ? "-" : (flags & 2) ? "+" : (flags & 4) ? " " : "";
        base = 10;
        break;
    }
    case 'u':
        base = 10;
        goto unsig;
    case 'o':
        base = 8;
        goto unsig;
    case 'x':
    case 'X':
        base = 16;
    unsig:
        v = va_arg(ap, unsigned long long);
        if ((flags & 8) && v && base == 16)
            prefix = c == 'X' ? "0X" : "0x";
        break;
    default:
        return -1;
    }
    p = num + sizeof(num);
    if (base == 10) {
        /* four digits at a time while the value has more than 32 bits (a division by
         * 10000: the runtime's quick one, below $10000), then 32-bit divisions */
        unsigned long w;
        while (v >> 32) {
            unsigned long long q = v / 10000;
            unsigned r = (unsigned)(v - q * 10000);
            for (i = 0; i < 4; ++i) {
                *--p = (char)('0' + r % 10);
                r /= 10;
            }
            v = q;
        }
        for (w = (unsigned long)v; w; w /= 10)
            *--p = (char)('0' + (unsigned)(w % 10));
    } else {
        unsigned sh = base == 16 ? 4 : 3;
        for (; v; v >>= sh)
            *--p = digits[(unsigned)v & (base - 1)];
    }
    len = (unsigned)(num + sizeof(num) - p);
    if (prec < 0 && !len)
        *--p = '0', len = 1;
    if ((flags & 8) && base == 8 && (len == 0 || *p != '0') && (prec < 0 || (unsigned)prec <= len))
        *--p = '0', ++len;
    zeros = prec >= 0 && (unsigned)prec > len ? (unsigned)prec - len : 0;
    plen = (unsigned)strlen(prefix);
    pad = width > len + zeros + plen ? width - len - zeros - plen : 0;
    if ((flags & 16) && !(flags & 1) && prec < 0) {
        zeros += pad;
        pad = 0;
    }
    if (!(flags & 1))
        for (i = 0; i < pad; ++i)
            out(' ', ctx);
    for (s = prefix; *s; ++s)
        out((unsigned char)*s, ctx);
    for (i = 0; i < zeros; ++i)
        out('0', ctx);
    for (i = 0; i < len; ++i)
        out((unsigned char)p[i], ctx);
    if (flags & 1)
        for (i = 0; i < pad; ++i)
            out(' ', ctx);
    return (int)(pad + plen + zeros + len);
}
