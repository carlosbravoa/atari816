/* math_atan.c - math.h for cc816: atan, atan2 (fdlibm's), asin, acos (through atan). */
#include <math.h>
#include "mathint.h"

static const float atanhi[4] = {4.6364760399e-01f, 7.8539812565e-01f, 9.8279368877e-01f,
                                1.5707962513e+00f};
static const float atanlo[4] = {5.0121582440e-09f, 3.7748947079e-08f, 3.4473217170e-08f,
                                7.5497894159e-08f};
static const float aT[11] = {
    3.3333334327e-01f, -2.0000000298e-01f, 1.4285714924e-01f, -1.1111110449e-01f,
    9.0908870101e-02f, -7.6918758452e-02f, 6.6610731184e-02f, -5.8335702866e-02f,
    4.9768779427e-02f, -3.6531571299e-02f, 1.6285819933e-02f};

double atan(double x)
{
    float w, s1, s2, z;
    int32_t ix, hx;
    int id;
    GETW(hx, x);
    ix = hx & 0x7FFFFFFFL;
    if (ix >= 0x4C000000L) {                    /* |x| >= 2^25 */
        if (ix > 0x7F800000L)
            return x + x;                       /* NaN */
        if (hx > 0)
            return atanhi[3] + atanlo[3];
        return -atanhi[3] - atanlo[3];
    }
    if (ix < 0x3EE00000L) {                     /* |x| < 0.4375 */
        if (ix < 0x31000000L)                   /* |x| < 2^-29 */
            return x;
        id = -1;
    } else {
        x = fabs(x);
        if (ix < 0x3F980000L) {                 /* |x| < 1.1875 */
            if (ix < 0x3F300000L) {             /* 7/16 <= |x| < 11/16 */
                id = 0;
                x = (2.0f * x - 1.0f) / (2.0f + x);
            } else {                            /* 11/16 <= |x| < 19/16 */
                id = 1;
                x = (x - 1.0f) / (x + 1.0f);
            }
        } else {
            if (ix < 0x401C0000L) {             /* |x| < 2.4375 */
                id = 2;
                x = (x - 1.5f) / (1.0f + 1.5f * x);
            } else {                            /* 2.4375 <= |x| < 2^25 */
                id = 3;
                x = -1.0f / x;
            }
        }
    }
    z = x * x;
    w = z * z;
    s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id < 0)
        return x - x * (s1 + s2);
    z = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x);
    return hx < 0 ? -z : z;
}

double atan2(double y, double x)
{
    static const float tiny = 1.0e-30f, pi_o_4 = 7.8539818525e-01f,
                       pi_o_2 = 1.5707963705e+00f, pi = 3.1415927410e+00f,
                       pi_lo = -8.7422776573e-08f;
    float z;
    int32_t k, m, hx, hy, ix, iy;
    GETW(hx, x);
    ix = hx & 0x7FFFFFFFL;
    GETW(hy, y);
    iy = hy & 0x7FFFFFFFL;
    if (ix > 0x7F800000L || iy > 0x7F800000L)
        return x + y;                           /* NaN */
    if (hx == 0x3F800000L)
        return atan(y);                         /* x = 1 */
    m = ((hy >> 31) & 1) | ((hx >> 30) & 2);    /* 2 * sign(x) + sign(y) */
    if (iy == 0) {
        switch ((int)m) {
        case 0:
        case 1: return y;                       /* atan(+-0, +x) = +-0 */
        case 2: return pi + tiny;               /* atan(+0, -x) = pi */
        default: return -pi - tiny;             /* atan(-0, -x) = -pi */
        }
    }
    if (ix == 0)
        return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny;
    if (ix == 0x7F800000L) {
        if (iy == 0x7F800000L) {
            switch ((int)m) {
            case 0: return pi_o_4 + tiny;
            case 1: return -pi_o_4 - tiny;
            case 2: return 3.0f * pi_o_4 + tiny;
            default: return -3.0f * pi_o_4 - tiny;
            }
        }
        switch ((int)m) {
        case 0: return 0.0f;
        case 1: return -0.0f;
        case 2: return pi + tiny;
        default: return -pi - tiny;
        }
    }
    if (iy == 0x7F800000L)
        return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny;
    k = (iy - ix) >> 23;
    if (k > 60)
        z = pi_o_2 + 0.5f * pi_lo;              /* |y/x| > 2^60 */
    else if (hx < 0 && k < -60)
        z = 0.0f;                               /* |y|/x < -2^60 */
    else
        z = atan(fabs(y / x));
    switch ((int)m) {
    case 0: return z;                           /* atan(+, +) */
    case 1: return -z;                          /* atan(-, +) */
    case 2: return pi - (z - pi_lo);            /* atan(+, -) */
    default: return (z - pi_lo) - pi;           /* atan(-, -) */
    }
}

/* asin(x) = atan(x / sqrt(1 - x^2)), acos(x) = 2 atan(sqrt((1 - x) / (1 + x))): within a
 * few ulp (1 - x and 1 + x are exact where they matter) */
double asin(double x)
{
    uint32_t w;
    float a;
    GETW(w, x);
    a = fabs(x);
    if (a > 1.0f || IS_NAN(w))
        return (x - x) / (x - x);
    if (a == 1.0f)
        return x * 1.5707963705e+00f;
    if (a < 2.44140625e-04f)                    /* 2^-12: asin(x) = x */
        return x;
    return atan(x / sqrt((1.0f - a) * (1.0f + a)));
}

double acos(double x)
{
    uint32_t w;
    GETW(w, x);
    if (fabs(x) > 1.0f || IS_NAN(w))
        return (x - x) / (x - x);
    if (x == -1.0f)
        return 3.1415927410e+00f;
    return 2.0f * atan(sqrt((1.0f - x) / (1.0f + x)));
}
