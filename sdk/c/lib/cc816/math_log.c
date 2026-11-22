/* math_log.c - math.h for cc816: log (fdlibm's), log10, log2, log1p. */
#include <math.h>
#include "mathint.h"

double log(double x)
{
    static const float ln2_hi = 6.9313812256e-01f, ln2_lo = 9.0580006145e-06f,
                       two25 = 3.355443200e+07f, Lg1 = 6.6666668653e-01f,
                       Lg2 = 4.0000000596e-01f, Lg3 = 2.8571429849e-01f,
                       Lg4 = 2.2222198546e-01f, Lg5 = 1.8183572590e-01f,
                       Lg6 = 1.5313838422e-01f, Lg7 = 1.4798198640e-01f;
    float hfsq, f, s, z, R, w, t1, t2, dk;
    int32_t k, ix, i, j;
    GETW(ix, x);
    k = 0;
    if ((ix & 0x7FFFFFFFL) == 0)
        return -two25 / 0.0f;                   /* log(+-0) = -inf */
    if (ix < 0)
        return (x - x) / (x - x);               /* log(negative) = NaN */
    if (ix >= 0x7F800000L)
        return x + x;                           /* inf, NaN */
    if (ix < 0x00800000L) {                     /* a denormal: scaled up */
        k -= 25;
        x *= two25;
        GETW(ix, x);
    }
    k += (ix >> 23) - 127;
    ix &= 0x007FFFFFL;
    i = (ix + (0x95F64L << 3)) & 0x800000L;
    SETW(x, ix | (i ^ 0x3F800000L));            /* x or x/2 in [sqrt(2)/2, sqrt(2)) */
    k += i >> 23;
    f = x - 1.0f;
    if ((0x007FFFFFL & (15 + ix)) < 16) {       /* |f| < 2^-20 */
        if (f == 0.0f) {
            if (k == 0)
                return 0.0f;
            dk = (float)k;
            return dk * ln2_hi + dk * ln2_lo;
        }
        R = f * f * (0.5f - 0.33333333333333333f * f);
        if (k == 0)
            return f - R;
        dk = (float)k;
        return dk * ln2_hi - ((R - dk * ln2_lo) - f);
    }
    s = f / (2.0f + f);
    dk = (float)k;
    z = s * s;
    i = ix - (0x6147AL << 3);
    w = z * z;
    j = (0x6B851L << 3) - ix;
    t1 = w * (Lg2 + w * (Lg4 + w * Lg6));
    t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)));
    i |= j;
    R = t2 + t1;
    if (i > 0) {
        hfsq = 0.5f * f * f;
        if (k == 0)
            return f - (hfsq - s * (hfsq + R));
        return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ln2_lo)) - f);
    }
    if (k == 0)
        return f - s * (f - R);
    return dk * ln2_hi - ((s * (f - R) - dk * ln2_lo) - f);
}

/* log10 and log2: x = 2^k * m (m in [1, 2)), k * c + log(m) / ln(base), c split in two */
static float logb_(float x, float ivln, float chi, float clo)
{
    static const float two25 = 3.3554432000e+07f;
    float y, z;
    int32_t k, hx, i;
    GETW(hx, x);
    k = 0;
    if ((hx & 0x7FFFFFFFL) == 0)
        return -two25 / 0.0f;
    if (hx < 0)
        return (x - x) / (x - x);
    if (hx >= 0x7F800000L)
        return x + x;
    if (hx < 0x00800000L) {
        k -= 25;
        x *= two25;
        GETW(hx, x);
    }
    k += (hx >> 23) - 127;
    i = (int32_t)(((uint32_t)k & 0x80000000UL) >> 31);
    hx = (hx & 0x007FFFFFL) | ((0x7FL - i) << 23);
    y = (float)(k + i);
    SETW(x, hx);
    z = y * clo + ivln * log(x);
    return z + y * chi;
}

double log10(double x)
{
    return logb_(x, 4.3429449201e-01f, 3.0102920532e-01f, 7.9034151668e-07f);
}

double log2(double x)
{
    return logb_(x, 1.4426950216e+00f, 1.0f, 0.0f);
}

double log1p(double x)                          /* Goldberg: log(u) x / (u - 1), u = 1 + x */
{
    float u;
    uint32_t w;
    GETW(w, x);
    if (IS_NAN(w))
        return x + x;
    if (x == -1.0f)
        return -1.0f / 0.0f;
    if (x < -1.0f)
        return (x - x) / (x - x);
    u = 1.0f + x;
    if (u == 1.0f)
        return x;
    if (IS_INF(w))
        return x;
    return log(u) * (x / (u - 1.0f));
}
