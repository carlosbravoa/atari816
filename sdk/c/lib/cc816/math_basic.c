/* math_basic.c - math.h for cc816: fabs, copysign, floor, ceil, trunc, round, rint,
 * nearbyint, lround, lrint, modf, frexp, ldexp, scalbn, ilogb, logb, nextafter, fmin,
 * fmax, fdim, fma, fpclassify, signbit (all exact, by the bits). */
#include <math.h>
#include "mathint.h"

double fabs(double x)
{
    uint32_t w;
    GETW(w, x);
    SETW(x, w & 0x7FFFFFFFUL);
    return x;
}

double copysign(double x, double y)
{
    uint32_t a, b;
    GETW(a, x);
    GETW(b, y);
    SETW(x, (a & 0x7FFFFFFFUL) | (b & 0x80000000UL));
    return x;
}

int __fpclassify(double x)
{
    uint32_t w;
    GETW(w, x);
    w &= 0x7FFFFFFFUL;
    if (w == 0)
        return FP_ZERO;
    if (w < 0x00800000UL)
        return FP_SUBNORMAL;
    if (w < 0x7F800000UL)
        return FP_NORMAL;
    return w == 0x7F800000UL ? FP_INFINITE : FP_NAN;
}

int __signbit(double x)
{
    uint32_t w;
    GETW(w, x);
    return (w >> 31) != 0;
}

/* the bits below the units of x (an exponent e from 0 to 22): a mask */
#define FRAC(e) (0x007FFFFFUL >> (e))

double trunc(double x)
{
    uint32_t w;
    int e;
    GETW(w, x);
    e = (int)((w >> 23) & 0xFF) - 127;
    if (e >= 23)
        return e == 128 ? x + x : x;    /* integral; inf; NaN (made quiet) */            /* integral, inf (NaN made quiet) */
    if (e < 0)
        SETW(x, w & 0x80000000UL);
    else
        SETW(x, w & ~FRAC(e));
    return x;
}

double floor(double x)
{
    uint32_t w;
    int e;
    GETW(w, x);
    e = (int)((w >> 23) & 0xFF) - 127;
    if (e >= 23)
        return e == 128 ? x + x : x;    /* integral; inf; NaN (made quiet) */
    if (e < 0) {
        if ((w & 0x7FFFFFFFUL) == 0)
            return x;
        SETW(x, (w >> 31) ? 0xBF800000UL : 0);
        return x;
    }
    if (!(w & FRAC(e)))
        return x;
    if (w >> 31)
        w += 0x00800000UL >> e;
    SETW(x, w & ~FRAC(e));
    return x;
}

double ceil(double x)
{
    uint32_t w;
    int e;
    GETW(w, x);
    e = (int)((w >> 23) & 0xFF) - 127;
    if (e >= 23)
        return e == 128 ? x + x : x;    /* integral; inf; NaN (made quiet) */
    if (e < 0) {
        if ((w & 0x7FFFFFFFUL) == 0)
            return x;
        SETW(x, (w >> 31) ? 0x80000000UL : 0x3F800000UL);
        return x;
    }
    if (!(w & FRAC(e)))
        return x;
    if (!(w >> 31))
        w += 0x00800000UL >> e;
    SETW(x, w & ~FRAC(e));
    return x;
}

double round(double x)                  /* halfway cases away from zero */
{
    uint32_t w;
    int e;
    GETW(w, x);
    e = (int)((w >> 23) & 0xFF) - 127;
    if (e >= 23)
        return e == 128 ? x + x : x;    /* integral; inf; NaN (made quiet) */
    if (e < 0) {
        w &= 0x80000000UL;
        if (e == -1)
            w |= 0x3F800000UL;
        SETW(x, w);
        return x;
    }
    if (!(w & FRAC(e)))
        return x;
    w += 0x00400000UL >> e;
    SETW(x, w & ~FRAC(e));
    return x;
}

double rint(double x)                   /* halfway cases to even */
{
    static const float two23 = 8388608.0f;
    uint32_t w, v;
    float t;
    GETW(w, x);
    if ((w & 0x7FFFFFFFUL) >= 0x4B000000UL)
        return (w & 0x7FFFFFFFUL) >= 0x7F800000UL ? x + x : x;
    if (w >> 31) {
        t = (x - two23) + two23;        /* (-0.3 gives +0: the sign back) */
        GETW(v, t);
        SETW(t, v | 0x80000000UL);
    } else
        t = (x + two23) - two23;
    return t;
}

double nearbyint(double x)
{
    return rint(x);
}

long lround(double x)
{
    return (long)round(x);
}

long lrint(double x)
{
    return (long)rint(x);
}

double modf(double x, double *ip)
{
    uint32_t w;
    float i;
    GETW(w, x);
    if ((w & 0x7FFFFFFFUL) > 0x7F800000UL) {
        *ip = x;
        return x + x;
    }
    i = trunc(x);
    *ip = i;
    if ((w & 0x7FFFFFFFUL) == 0x7F800000UL || i == x) {
        SETW(x, w & 0x80000000UL);      /* a signed 0 */
        return x;
    }
    return x - i;
}

double frexp(double x, int *ep)
{
    uint32_t w;
    int e;
    GETW(w, x);
    e = (int)((w >> 23) & 0xFF);
    *ep = 0;
    if (e == 255)
        return x + x;                   /* inf, NaN */
    if (!(w & 0x7FFFFFFFUL))
        return x;
    if (!e) {                           /* a denormal: scaled to a normal first */
        x *= 33554432.0f;               /* 2^25 */
        GETW(w, x);
        e = (int)((w >> 23) & 0xFF) - 25;
    }
    *ep = e - 126;
    SETW(x, (w & 0x807FFFFFUL) | 0x3F000000UL);
    return x;
}

/* x * 2^n, rounded once (fdlibm's scalbnf) */
double __hz_scalb(double x, long n)
{
    static const float two25 = 33554432.0f, twom25 = 2.9802322388e-08f, huge = 1.0e30f,
                       tiny = 1.0e-30f;
    uint32_t w;
    long k;
    GETW(w, x);
    k = (long)((w >> 23) & 0xFF);
    if (!k) {
        if (!(w & 0x7FFFFFFFUL))
            return x;
        x *= two25;
        GETW(w, x);
        k = (long)((w >> 23) & 0xFF) - 25;
    }
    if (k == 255)
        return x + x;
    if (n > 1000)
        n = 1000;
    if (n < -1000)
        n = -1000;
    k += n;
    if (k > 254)
        return huge * copysign(huge, x);
    if (k > 0) {
        SETW(x, (w & 0x807FFFFFUL) | ((uint32_t)k << 23));
        return x;
    }
    if (k <= -25)
        return tiny * copysign(tiny, x);
    k += 25;
    SETW(x, (w & 0x807FFFFFUL) | ((uint32_t)k << 23));
    return x * twom25;
}

double ldexp(double x, int n)
{
    return __hz_scalb(x, n);
}

double scalbn(double x, int n)
{
    return __hz_scalb(x, n);
}

int ilogb(double x)
{
    uint32_t w;
    int e;
    GETW(w, x);
    w &= 0x7FFFFFFFUL;
    if (!w)
        return -32767 - 1;              /* FP_ILOGB0 */
    if (w >= 0x7F800000UL)
        return 32767;
    e = (int)(w >> 23);
    if (!e) {
        for (e = -126; !(w & 0x00400000UL); w <<= 1)
            --e;
        return e - 1;
    }
    return e - 127;
}

double logb(double x)
{
    uint32_t w;
    GETW(w, x);
    w &= 0x7FFFFFFFUL;
    if (!w)
        return -1.0f / 0.0f;
    if (w >= 0x7F800000UL)
        return x * x;
    return (float)ilogb(x);
}

double nextafter(double x, double y)
{
    uint32_t a, b;
    GETW(a, x);
    GETW(b, y);
    if (IS_NAN(a) || IS_NAN(b))
        return x + y;
    if (x == y)
        return y;
    if (!(a & 0x7FFFFFFFUL)) {
        SETW(x, (b & 0x80000000UL) | 1);
        return x;
    }
    if ((x < y) == !(a >> 31))
        ++a;
    else
        --a;
    SETW(x, a);
    return x;
}

double fmin(double x, double y)
{
    uint32_t a, b;
    GETW(a, x);
    GETW(b, y);
    if (IS_NAN(a))
        return y;
    if (IS_NAN(b))
        return x;
    if (x == y)                         /* -0 is the smaller zero */
        return (a >> 31) ? x : y;
    return x < y ? x : y;
}

double fmax(double x, double y)
{
    uint32_t a, b;
    GETW(a, x);
    GETW(b, y);
    if (IS_NAN(a))
        return y;
    if (IS_NAN(b))
        return x;
    if (x == y)
        return (a >> 31) ? y : x;
    return x > y ? x : y;
}

double fdim(double x, double y)
{
    uint32_t a, b;
    GETW(a, x);
    GETW(b, y);
    if (IS_NAN(a) || IS_NAN(b))
        return x + y;
    return x > y ? x - y : 0.0f;
}

double fma(double x, double y, double z)        /* not fused: x * y rounded, then + z */
{
    return x * y + z;
}
