/* math_sqrt.c - math.h for cc816: sqrt (exact: rounded once, fdlibm's bit-by-bit method),
 * cbrt, hypot. */
#include <math.h>
#include "mathint.h"

double sqrt(double x)
{
    int32_t ix, s, q, m, t, i;
    uint32_t r;
    GETW(ix, x);
    if ((ix & 0x7F800000L) == 0x7F800000L)
        return x * x + x;               /* NaN, +inf; -inf -> NaN */
    if (ix <= 0) {
        if ((ix & 0x7FFFFFFFL) == 0)
            return x;                   /* +-0 */
        return (x - x) / (x - x);       /* negative: NaN */
    }
    m = ix >> 23;
    if (m == 0) {                       /* a denormal */
        for (i = 0; (ix & 0x00800000L) == 0; ++i)
            ix <<= 1;
        m -= i - 1;
    }
    m -= 127;
    ix = (ix & 0x007FFFFFL) | 0x00800000L;
    if (m & 1)                          /* an odd exponent: x doubled */
        ix += ix;
    m >>= 1;
    ix += ix;
    q = s = 0;
    r = 0x01000000UL;
    while (r != 0) {
        t = s + (int32_t)r;
        if (t <= ix) {
            s = t + (int32_t)r;
            ix -= t;
            q += (int32_t)r;
        }
        ix += ix;
        r >>= 1;
    }
    if (ix != 0)                        /* not exact: round to nearest */
        q += q & 1;
    ix = (q >> 1) + 0x3F000000L;
    ix += (int32_t)((uint32_t)m << 23);
    SETW(x, ix);
    return x;
}

double cbrt(double x)
{
    static const uint32_t B1 = 709958130UL, B2 = 642849266UL;
    static const float C = 5.4285717010e-01f, D = -7.0530611277e-01f, E = 1.4142856598e+00f,
                       F = 1.6071428061e+00f, G = 3.5714286566e-01f;
    float r, s, t, ax;
    uint32_t hx, sign, high;
    GETW(hx, x);
    sign = hx & 0x80000000UL;
    hx ^= sign;
    if (hx >= 0x7F800000UL)
        return x + x;
    if (hx == 0)
        return x;
    SETW(ax, hx);
    if (hx < 0x00800000UL) {            /* a denormal */
        SETW(t, 0x4B800000UL);          /* 2^24 */
        t *= ax;
        GETW(high, t);
        SETW(t, high / 3 + B2);
    } else
        SETW(t, hx / 3 + B1);
    /* a rational approximation, then a Newton step (fdlibm's cbrtf) */
    r = t * t / ax;
    s = C + r * t;
    t *= G + F / (s + E + D / s);
    r = t * t;                          /* one more Newton step: t - (t - x / t^2) / 3 */
    t = t - (t - ax / r) * 0.333333343f;
    GETW(high, t);
    SETW(t, high | sign);
    return t;
}

double hypot(double x, double y)
{
    float a, b, r;
    uint32_t ha, hb;
    GETW(ha, x);
    GETW(hb, y);
    ha &= 0x7FFFFFFFUL;
    hb &= 0x7FFFFFFFUL;
    if (ha == 0x7F800000UL || hb == 0x7F800000UL)
        return 1.0f / 0.0f;             /* inf, even with a NaN */
    if (ha > 0x7F800000UL || hb > 0x7F800000UL)
        return x + y;
    SETW(a, ha);
    SETW(b, hb);
    if (a < b) {
        r = a;
        a = b;
        b = r;
    }
    if (b == 0.0f)
        return a;
    r = b / a;
    return a * sqrt(1.0f + r * r);
}
