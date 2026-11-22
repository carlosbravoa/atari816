/* math_exp.c - math.h for cc816: exp (fdlibm's), exp2, expm1, sinh, cosh, tanh. */
#include <math.h>
#include "mathint.h"

#define P1 1.6666667163e-01f
#define P2 -2.7777778450e-03f
#define P3 6.6137559770e-05f
#define P4 -1.6533901999e-06f
#define P5 4.1381369442e-08f

/* e^(hi - lo) * 2^k, |hi - lo| <= ln2 / 2 (fdlibm's expf after its reduction) */
static float expk(float hi, float lo, int k)
{
    static const float twom100 = 7.8886090522e-31f;
    float x = hi - lo, t, c, y;
    uint32_t hy;
    t = x * x;
    c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    if (k == 0)
        return 1.0f - ((x * c) / (c - 2.0f) - x);
    y = 1.0f - ((lo - (x * c) / (2.0f - c)) - hi);
    GETW(hy, y);
    if (k >= -125) {
        SETW(y, hy + ((uint32_t)(long)k << 23));
        return y;
    }
    SETW(y, hy + ((uint32_t)(long)(k + 100) << 23));
    return y * twom100;
}

double exp(double x)
{
    static const float ln2HI = 6.9313812256e-01f, ln2LO = 9.0580006145e-06f,
                       invln2 = 1.4426950216e+00f, huge = 1.0e+30f, twom100 = 7.8886090522e-31f;
    float hi = 0.0f, lo = 0.0f, t;
    int32_t hx, k = 0;
    int xsb;
    GETW(hx, x);
    xsb = (int)((hx >> 31) & 1);
    hx &= 0x7FFFFFFFL;
    if (hx > 0x7F800000L)
        return x + x;                           /* NaN */
    if (hx == 0x7F800000L)
        return xsb ? 0.0f : x;                  /* e^-inf = 0, e^inf = inf */
    if (!xsb && hx > 0x42B17217L)
        return huge * huge;                     /* overflow */
    if (xsb && hx > 0x42CFF1B5L)
        return twom100 * twom100;               /* underflow */
    if (hx > 0x3EB17218L) {                     /* |x| > ln2 / 2 */
        if (hx < 0x3F851592L) {                 /* and |x| < 1.5 ln2 */
            hi = xsb ? x + ln2HI : x - ln2HI;
            lo = xsb ? -ln2LO : ln2LO;
            k = 1 - xsb - xsb;
        } else {
            k = (int32_t)(invln2 * x + (xsb ? -0.5f : 0.5f));
            t = (float)k;
            hi = x - t * ln2HI;                 /* exact: ln2HI has 16 bits */
            lo = t * ln2LO;
        }
        return expk(hi, lo, (int)k);
    }
    if (hx < 0x31800000L)                       /* |x| < 2^-28 */
        return 1.0f + x;
    return expk(x, 0.0f, 0);
}

/* 2^x: 2^k * e^(f ln2), f = x - k exact, f ln2 split exactly (12-bit halves) */
double exp2(double x)
{
    static const float L1 = 6.9311523438e-01f, L2 = 3.1946183299e-05f;   /* ln2 = L1 + L2 */
    float f, fh, fl, hi, lo, kf;
    uint32_t w;
    long k;
    GETW(w, x);
    if (IS_NAN(w))
        return x + x;
    if (x >= 128.0f)
        return 1.0e30f * 1.0e30f;
    if (x < -150.0f)
        return 1.0e-30f * 1.0e-30f;
    kf = rint(x);
    k = (long)kf;
    f = x - kf;                                 /* |f| <= 1/2, exact */
    GETW(w, f);
    SETW(fh, w & 0xFFFFF000UL);
    fl = f - fh;
    hi = fh * L1;                               /* exact (12 x 12 bits) */
    lo = -(fh * L2 + fl * (L1 + L2));
    if (k > 127) {                              /* 2^128 * e^(...) < FLT_MAX: in two steps */
        return 2.0f * expk(hi, lo, (int)(k - 1));
    }
    return expk(hi, lo, (int)k);
}

double expm1(double x)                          /* Kahan: (u - 1) x / log u, u = e^x */
{
    float u, a;
    uint32_t w;
    GETW(w, x);
    if (IS_NAN(w))
        return x + x;
    a = fabs(x);
    if (a < 2.9802322388e-08f)                  /* 2^-25 */
        return x;
    if (x > 88.72283f)
        return 1.0e30f * 1.0e30f;
    if (x < -17.4f)
        return -1.0f;
    if (a < 0.40546511f) {                      /* log(1.5): u near 1 */
        u = exp(x);
        if (u == 1.0f)
            return x;
        return (u - 1.0f) * x / log(u);
    }
    return exp(x) - 1.0f;
}

double sinh(double x)
{
    float t, w, h, a;
    uint32_t ix;
    GETW(ix, x);
    if (IS_NAN(ix) || IS_INF(ix))
        return x + x;
    h = (ix >> 31) ? -0.5f : 0.5f;
    a = fabs(x);
    if (a < 9.0f) {
        if (a < 2.44140625e-04f)                /* 2^-12 */
            return x;
        t = expm1(a);
        if (a < 1.0f)
            return h * (2.0f * t - t * t / (t + 1.0f));
        return h * (t + t / (t + 1.0f));
    }
    if (a < 88.7216796875f)                     /* log(FLT_MAX) */
        return h * exp(a);
    if (a <= 89.4159851f) {                     /* overflow threshold */
        w = exp(0.5f * a);
        t = h * w;
        return t * w;
    }
    return x * 1.0e30f * 1.0e30f;               /* overflow */
}

double cosh(double x)
{
    float t, w, a;
    uint32_t ix;
    GETW(ix, x);
    if (IS_NAN(ix))
        return x * x;
    a = fabs(x);
    if (a < 0.3465735903f) {                    /* ln2 / 2 */
        if (a < 2.44140625e-04f)                /* 2^-12: 1 + x^2/2 rounds to 1 */
            return 1.0f;
        t = expm1(a);
        w = 1.0f + t;
        return 1.0f + (t * t) / (w + w);
    }
    if (a < 9.0f) {
        t = exp(a);
        return 0.5f * t + 0.5f / t;
    }
    if (a < 88.7216796875f)
        return 0.5f * exp(a);
    if (a <= 89.4159851f) {
        w = exp(0.5f * a);
        t = 0.5f * w;
        return t * w;
    }
    return 1.0e30f * 1.0e30f;
}

double tanh(double x)
{
    float t, z, a;
    uint32_t ix;
    GETW(ix, x);
    if (IS_NAN(ix))
        return x + x;
    a = fabs(x);
    if (a < 9.0f) {
        if (a < 3.7252902984e-09f)              /* 2^-28 */
            return x;
        if (a >= 1.0f) {
            t = expm1(2.0f * a);
            z = 1.0f - 2.0f / (t + 2.0f);
        } else {
            t = expm1(-2.0f * a);
            z = -t / (t + 2.0f);
        }
    } else
        z = 1.0f;
    return (ix >> 31) ? -z : z;
}
