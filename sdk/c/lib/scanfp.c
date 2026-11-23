/* scanfp.c - scanf's floating-point conversions for cc816: %f %F %e %E %g %G %a %A (with
 * l and L: double and long double, the same 32-bit format as float).
 *
 * scan.c calls __hz_scanfp through the hook rt/fp_hooks.s installs in programs that
 * use floating point. It reads the longest beginning of a number the input has (at most
 * the width; a sign, digits with one '.', an exponent, 0x hexadecimal with a p exponent,
 * inf, infinity, nan), as C's scanf does, and converts it with strtod (exact). When what
 * was read is not a whole number ("1e+", "-", "0x") the conversion fails (matching
 * failure), as with glibc. At most 128 characters a number.
 */
#include <stdlib.h>

typedef int (*hz_getfn)(void *ctx);
typedef void (*hz_ungetfn)(int c, void *ctx);

static int low(int c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static int isdig(int c, int hex)
{
    if (c >= '0' && c <= '9')
        return 1;
    c = low(c);
    return hex && c >= 'a' && c <= 'f';
}

int __hz_scanfp(hz_getfn get, hz_ungetfn unget, void *ctx, unsigned width,
                unsigned long *bits, unsigned *nread)
{
    char buf[130];
    unsigned n = 0;
    int c, hex = 0, dot = 0, digits = 0, expo = 0;
    char *end;
    union { float f; unsigned long u; } v;
#define GETC() (c = get(ctx), c != -1 ? ++*nread : 0)
#define TAKE() (buf[n++] = (char)c, --width, width ? GETC() : (c = -2))
    GETC();
    if (c == '+' || c == '-')
        TAKE();
    if (width && (low(c) == 'i' || low(c) == 'n')) {
        /* inf, infinity, nan, nan(chars) */
        const char *w = low(c) == 'i' ? "infinity" : "nan";
        unsigned k = 0;
        while (w[k] && width && low(c) == w[k] && n < 120) {
            TAKE();
            ++k;
        }
        if (k == 8 || (k == 3 && w[0] == 'i'))
            ;
        else if (k == 3 && w[0] == 'n') {
            if (c == '(') {
                TAKE();
                while (width && n < 120 && (isdig(c, 1) || (low(c) >= 'a' && low(c) <= 'z') ||
                                            c == '_'))
                    TAKE();
                if (c != ')')
                    goto fail;
                TAKE();
            }
        } else
            goto fail;
        goto conv;
    }
    if (width && c == '0') {
        TAKE();
        digits = 1;
        if (width && low(c) == 'x') {
            TAKE();
            hex = 1;
            digits = 0;
        }
    }
    for (;;) {
        if (!width || n >= 126)
            break;
        if (c == '.' && !dot && !expo) {
            dot = 1;
            TAKE();
            continue;
        }
        if (!expo && isdig(c, hex)) {
            digits = 1;
            TAKE();
            continue;
        }
        if (!expo && digits && low(c) == (hex ? 'p' : 'e')) {
            expo = 1;
            TAKE();
            if (width && (c == '+' || c == '-'))
                TAKE();
            if (!width || c < '0' || c > '9')
                goto fail;
            continue;
        }
        if (expo && c >= '0' && c <= '9') {
            TAKE();
            continue;
        }
        break;
    }
    if (!digits)
        goto fail;
conv:
    if (c >= 0) {                       /* the character after the number: back */
        unget(c, ctx);
        --*nread;
    }
    buf[n] = 0;
    v.f = strtod(buf, &end);
    if (*end)
        return 0;
    *bits = v.u;
    return 1;
fail:
    if (c >= 0) {
        unget(c, ctx);
        --*nread;
    }
    return 0;
#undef TAKE
#undef GETC
}
