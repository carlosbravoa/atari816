/* fmt.c - printf's formatting for cc816 (printf.c and sprintf.c call it).
 *
 * %d %i %u %o %x %X %c %s %p %n %%; the sizes hh h l (and j z t: long, int, int; ll is
 * read as l); flags - + space # 0; width and precision, * for either.
 * %f %F %e %E %g %G %a %A (a float, double or long double: one 32-bit format) go to
 * __hz_fmt_float (fmtfp.c), which a program that uses floating point has installed
 * (rt/cc816/fp_hookp.s); without it they print as they are written.
 */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

typedef void (*hz_outfn)(int c, void *ctx);

/* the float conversion: (out, ctx, conversion letter, flags, width, precision or -1, the
 * float's bits) -> characters written */
int (*__hz_fmt_float)(hz_outfn out, void *ctx, unsigned c, unsigned flags, unsigned width,
                      int prec, unsigned long bits);

static const char lower[] = "0123456789abcdef";
static const char upper[] = "0123456789ABCDEF";

int __hz_vformat(hz_outfn out, void *ctx, const char *fmt, va_list ap)
{
    char num[12];
    int total = 0;
    unsigned c;
    while ((c = (unsigned char)*fmt++) != 0) {
        unsigned flags, width, prec, base, len, zeros, pad, plen, i;
        int hasprec, size, neg;
        unsigned long v;
        const char *s, *digits, *prefix;
        char *p;
        if (c != '%') {
            out(c, ctx);
            ++total;
            continue;
        }
        /* flags: 1 '-', 2 '+', 4 ' ', 8 '#', 16 '0' */
        flags = 0;
        for (;;) {
            c = (unsigned char)*fmt;
            if (c == '-') flags |= 1;
            else if (c == '+') flags |= 2;
            else if (c == ' ') flags |= 4;
            else if (c == '#') flags |= 8;
            else if (c == '0') flags |= 16;
            else break;
            ++fmt;
        }
        width = 0;
        if (*fmt == '*') {
            int w = va_arg(ap, int);
            ++fmt;
            if (w < 0) {
                flags |= 1;
                w = -w;
            }
            width = (unsigned)w;
        } else {
            while (*fmt >= '0' && *fmt <= '9')
                width = width * 10 + (unsigned)(*fmt++ - '0');
        }
        hasprec = 0;
        prec = 0;
        if (*fmt == '.') {
            ++fmt;
            hasprec = 1;
            if (*fmt == '*') {
                int pr = va_arg(ap, int);
                ++fmt;
                if (pr < 0)
                    hasprec = 0;
                else
                    prec = (unsigned)pr;
            } else {
                while (*fmt >= '0' && *fmt <= '9')
                    prec = prec * 10 + (unsigned)(*fmt++ - '0');
            }
        }
        /* size: 0 int, 1 char, 2 short, 4 long */
        size = 0;
        for (;;) {
            c = (unsigned char)*fmt;
            if (c == 'h') size = size == 2 ? 1 : 2;
            else if (c == 'l' || c == 'j' || c == 'L') size = 4;
            else if (c == 'z' || c == 't') size = 0;
            else break;
            ++fmt;
        }
        c = (unsigned char)*fmt++;
        if (!c)
            break;
        prefix = "";
        neg = 0;
        digits = lower;
        switch (c) {
        case 'd':
        case 'i':
            if (size == 4) {
                long x = va_arg(ap, long);
                if (x < 0) {
                    neg = 1;
                    v = 0UL - (unsigned long)x;
                } else
                    v = (unsigned long)x;
            } else {
                int x = va_arg(ap, int);
                if (size == 1)
                    x = (signed char)x;
                if (x < 0) {
                    neg = 1;
                    v = (unsigned)-x;
                } else
                    v = (unsigned)x;
            }
            base = 10;
            prefix = neg ? "-" : (flags & 2) ? "+" : (flags & 4) ? " " : "";
            goto number;
        case 'u':
            base = 10;
            goto unsig;
        case 'o':
            base = 8;
            goto unsig;
        case 'X':
            digits = upper;
            /* fall through */
        case 'x':
            base = 16;
        unsig:
            if (size == 4)
                v = va_arg(ap, unsigned long);
            else {
                v = va_arg(ap, unsigned);
                if (size == 1)
                    v &= 0xFF;
            }
            if ((flags & 8) && v && base == 16)
                prefix = digits == upper ? "0X" : "0x";
        number:
            p = num + sizeof(num);
            if ((v >> 16) == 0) {
                unsigned u = (unsigned)v;
                while (u) {
                    *--p = digits[u % base];
                    u /= base;
                }
            } else {
                while (v) {
                    *--p = digits[(unsigned)(v % base)];
                    v /= base;
                }
            }
            len = (unsigned)(num + sizeof(num) - p);
            if (!hasprec && !len)
                *--p = '0', len = 1;
            if ((flags & 8) && base == 8 && (len == 0 || *p != '0') && (!hasprec || prec <= len))
                *--p = '0', ++len;
            zeros = hasprec && prec > len ? prec - len : 0;
            plen = (unsigned)strlen(prefix);
            pad = width > len + zeros + plen ? width - len - zeros - plen : 0;
            if ((flags & 16) && !(flags & 1) && !hasprec) {
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
            total += (int)(pad + plen + zeros + len);
            break;
        case 'p':
            v = (unsigned)va_arg(ap, void *);
            prefix = "0x";
            base = 16;
            hasprec = 1;
            prec = 4;
            goto number;
        case 'c':
            num[0] = (char)va_arg(ap, int);
            s = num;
            len = 1;
            goto str;
        case 's':
            s = va_arg(ap, const char *);
            if (!s)
                s = "(null)";
            for (len = 0; s[len] && (!hasprec || len < prec); ++len)
                ;
        str:
            pad = width > len ? width - len : 0;
            if (!(flags & 1))
                for (i = 0; i < pad; ++i)
                    out(' ', ctx);
            for (i = 0; i < len; ++i)
                out((unsigned char)s[i], ctx);
            if (flags & 1)
                for (i = 0; i < pad; ++i)
                    out(' ', ctx);
            total += (int)(pad + len);
            break;
        case 'n':
            if (size == 4)
                *va_arg(ap, long *) = total;
            else if (size == 1)
                *va_arg(ap, signed char *) = (signed char)total;
            else
                *va_arg(ap, int *) = total;
            break;
        case '%':
            out('%', ctx);
            ++total;
            break;
        default:
            /* f F e E g G a A (tested here, not as cases: the switch's jump table stays
             * as small as it was): the float conversion, if the program has it */
            i = c | 32;
            if (__hz_fmt_float && (i == 'f' || i == 'e' || i == 'g' || i == 'a')) {
                unsigned long bits = va_arg(ap, unsigned long);
                total += __hz_fmt_float(out, ctx, c, flags, width, hasprec ? (int)prec : -1,
                                        bits);
                break;
            }
            /* not known (or no floating point in this program): as written */
            out('%', ctx);
            out(c, ctx);
            total += 2;
            break;
        }
    }
    return total;
}
