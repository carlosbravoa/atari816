/* scan.c - scanf's reading for cc816 (scanf.c and sscanf.c call it).
 *
 * %d %i %u %o %x %X %p %c %s %[set] %[^set] %n %%; the sizes hh h l (z t: int); ll and j
 * (intmax_t is long long) go to __hz_scan_ll (scanll.c), which a program that uses long
 * long has installed (rt/cc816/ll_hooks.s); without it they are read as l; * (no
 * assignment) and widths. White space in the format skips any white space.
 * %f %F %e %E %g %G %a %A (float *, and with l or L double * and long double *: the same
 * 32-bit format) go to __hz_scan_float (scanfp.c), which a program that uses floating
 * point has installed (rt/cc816/fp_hooks.s); without it they fail. The result: the number
 * of assignments, or EOF when the input ended before the first conversion.
 */
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>

typedef int (*hz_getfn)(void *ctx);
typedef void (*hz_ungetfn)(int c, void *ctx);

/* the float conversion: (get, unget, ctx, width, where the float's bits go, the count of
 * characters read) -> 1, or 0 (no number there) */
int (*__hz_scan_float)(hz_getfn get, hz_ungetfn unget, void *ctx, unsigned width,
                       unsigned long *bits, unsigned *nread);
/* the long long conversion: (get, unget, ctx, width, base (0: %i), the count of
 * characters read, where the value goes or 0) -> 1, or 0 (no number there) */
int (*__hz_scan_ll)(hz_getfn get, hz_ungetfn unget, void *ctx, unsigned width,
                    unsigned base, unsigned *nread, void *to);

static int digit(int c, unsigned base)
{
    unsigned d;
    if (c >= '0' && c <= '9')
        d = (unsigned)(c - '0');
    else if (c >= 'a' && c <= 'z')
        d = (unsigned)(c - 'a' + 10);
    else if (c >= 'A' && c <= 'Z')
        d = (unsigned)(c - 'A' + 10);
    else
        return -1;
    return d < base ? (int)d : -1;
}

int __hz_vscan(hz_getfn get, hz_ungetfn unget, void *ctx, const char *fmt, va_list ap)
{
    int assigned = 0, c = 0;
    unsigned nread = 0;
    unsigned fc;
    int started = 0;            /* a conversion was attempted with input there */

#define GET() (c = get(ctx), c != EOF ? ++nread : 0, c)
#define UNGET() (c != EOF ? (unget(c, ctx), --nread) : 0)

    while ((fc = (unsigned char)*fmt++) != 0) {
        int skip, size, neg, any, d;
        unsigned width, base, k;
        unsigned long v;
        char *out;
        if (isspace(fc)) {
            while (GET() != EOF && isspace(c))
                ;
            UNGET();
            continue;
        }
        if (fc != '%' || *fmt == '%') {
            if (fc == '%') {                    /* %%: white space, then '%' */
                ++fmt;
                while (GET() != EOF && isspace(c))
                    ;
            } else
                GET();
            if (c != (int)fc) {
                UNGET();
                if (c == EOF && !started && !assigned)
                    return EOF;
                return assigned;
            }
            continue;
        }
        skip = 0;
        if (*fmt == '*') {
            skip = 1;
            ++fmt;
        }
        width = 0;
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + (unsigned)(*fmt++ - '0');
        size = 0;
        for (;; ++fmt) {
            k = (unsigned char)*fmt;
            if (k == 'h')
                size = size == 2 ? 1 : 2;
            else if (k == 'l' || k == 'j' || k == 'L')
                size = (size == 4 || k == 'j') && __hz_scan_ll ? 8 : 4;
            else if (k != 'z' && k != 't')
                break;
        }
        fc = (unsigned char)*fmt++;
        if (!fc)
            break;
        if (fc == 'n') {
            if (!skip) {
                if (size == 4)
                    *va_arg(ap, long *) = nread;
                else if (size == 1)
                    *va_arg(ap, unsigned char *) = (unsigned char)nread;
                else
                    *va_arg(ap, int *) = (int)nread;
            }
            continue;
        }
        if (fc != 'c' && fc != '[') {
            while (GET() != EOF && isspace(c))
                ;
            UNGET();
        }
        if (GET() == EOF)
            return started || assigned ? assigned : EOF;
        UNGET();
        started = 1;
        switch (fc) {
        case 'c':
            if (!width)
                width = 1;
            out = skip ? 0 : va_arg(ap, char *);
            for (k = 0; k < width; ++k) {
                if (GET() == EOF)
                    break;
                if (out)
                    *out++ = (char)c;
            }
            if (!k)
                return assigned;
            if (out)
                ++assigned;
            continue;
        case 's':
            out = skip ? 0 : va_arg(ap, char *);
            for (k = 0; !width || k < width; ++k) {
                if (GET() == EOF)
                    break;
                if (isspace(c)) {
                    UNGET();
                    break;
                }
                if (out)
                    *out++ = (char)c;
            }
            if (out) {
                *out = 0;
                ++assigned;
            }
            continue;
        case '[': {
            unsigned char set[32];
            int inv = 0, first = 1;
            unsigned i;
            for (i = 0; i < 32; ++i)
                set[i] = 0;
            if (*fmt == '^') {
                inv = 1;
                ++fmt;
            }
            while (*fmt && (first || *fmt != ']')) {
                unsigned a = (unsigned char)*fmt++, b = a;
                if (*fmt == '-' && fmt[1] && fmt[1] != ']') {
                    b = (unsigned char)fmt[1];
                    fmt += 2;
                }
                for (; a <= b; ++a)
                    set[a >> 3] |= (unsigned char)(1 << (a & 7));
                first = 0;
            }
            if (*fmt == ']')
                ++fmt;
            out = skip ? 0 : va_arg(ap, char *);
            for (k = 0; !width || k < width; ++k) {
                if (GET() == EOF)
                    break;
                if (!(set[(unsigned)c >> 3] & (1 << (c & 7))) != inv) {
                    UNGET();
                    break;
                }
                if (out)
                    *out++ = (char)c;
            }
            if (!k)
                return assigned;
            if (out) {
                *out = 0;
                ++assigned;
            }
            continue;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A': {
            unsigned long bits;
            if (!__hz_scan_float ||
                !__hz_scan_float(get, unget, ctx, width ? width : 0xFFFF, &bits, &nread))
                return assigned;
            if (!skip) {
                *va_arg(ap, unsigned long *) = bits;
                ++assigned;
            }
            continue;
        }
        case 'd': base = 10; break;
        case 'u': base = 10; break;
        case 'i': base = 0; break;
        case 'o': base = 8; break;
        case 'x':
        case 'X':
        case 'p': base = 16; break;
        default:
            return assigned;
        }
        /* a number */
        if (!width)
            width = 0xFFFF;
        if (size == 8 && fc != 'p') {
            if (!__hz_scan_ll(get, unget, ctx, width, base, &nread,
                              skip ? 0 : va_arg(ap, void *)))
                return assigned;
            assigned += !skip;
            continue;
        }
        neg = 0;
        any = 0;
        v = 0;
        GET();
        if ((c == '-' || c == '+') && width) {
            neg = c == '-';
            --width;
            GET();
        }
        if (c == '0' && width && (base == 0 || base == 16)) {
            any = 1;
            --width;
            GET();
            if ((c == 'x' || c == 'X') && width) {
                --width;
                GET();
                base = 16;
                any = 0;
            } else if (base == 0)
                base = 8;
        }
        if (base == 0)
            base = 10;
        while (width && (d = digit(c, base)) >= 0) {
            v = v * base + (unsigned)d;
            any = 1;
            --width;
            GET();
        }
        UNGET();
        if (!any)
            return assigned;
        if (neg)
            v = 0UL - v;
        if (!skip) {
            if (fc == 'p')
                *va_arg(ap, void **) = (void *)(unsigned)v;
            else if (size == 4)
                *va_arg(ap, unsigned long *) = v;
            else if (size == 1)
                *va_arg(ap, unsigned char *) = (unsigned char)v;
            else
                *va_arg(ap, unsigned *) = (unsigned)v;
            ++assigned;
        }
    }
    return assigned;
}
