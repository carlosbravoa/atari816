/* math_trig.c - math.h for cc816: sin, cos, tan.
 *
 * fdlibm's single-precision kernels on [-pi/4, pi/4]. The argument is reduced by a
 * multiple n of pi/2: up to 2^7 pi/2 (201) with pi/2 in three and up to four float parts
 * (fdlibm's medium path); above that by cc816's own exact reduction: x = m * 2^e times
 * the 96 bits of 2/pi that matter at x's exponent, in 16-bit integer arithmetic, gives n
 * mod 4 and the fraction to 64 bits, multiplied by pi/2 (64 bits) and split into two
 * floats. So the result is within about an ulp for every float argument, 1e30 too.
 */
#include <math.h>
#include "mathint.h"

/* 2/pi: 256 bits after the binary point, most significant first */
static const uint16_t twobypi[16] = {
    0xA2F9, 0x836E, 0x4E44, 0x1529, 0xFC27, 0x57D1, 0xF534, 0xDDC0,
    0xDB62, 0x9599, 0x3C43, 0x9041, 0xFE51, 0x63AB, 0xDEBB, 0xC561};
/* floor(pi/2 * 2^63), least significant limb first */
static const uint16_t pio2_63[4] = {0xC234, 0x2168, 0xDAA2, 0xC90F};

/* 16 bits of the little-endian number a (n limbs) from bit b up (bits above: 0) */
static uint16_t bits16(const uint16_t *a, unsigned n, unsigned b)
{
    unsigned q = b >> 4, s = b & 15;
    uint32_t v = 0;
    if (q < n)
        v = a[q];
    if (q + 1 < n)
        v |= (uint32_t)a[q + 1] << 16;
    return (uint16_t)(v >> s);
}

/* r = a * b: na and nb limbs -> na + nb limbs */
static void mul(uint16_t *r, const uint16_t *a, unsigned na, const uint16_t *b, unsigned nb)
{
    unsigned i, j;
    for (i = 0; i < na + nb; ++i)
        r[i] = 0;
    for (i = 0; i < na; ++i) {
        uint32_t c = 0;
        for (j = 0; j < nb; ++j) {
            c += (uint32_t)a[i] * b[j] + r[i + j];
            r[i + j] = (uint16_t)c;
            c >>= 16;
        }
        r[i + nb] = (uint16_t)c;
    }
}

/* a float from a 24-bit integer m (< 2^24) times 2^e (e from -149 - 23 up: a normal or a
 * denormal result, exact for the normal ones) */
static float mkf(uint32_t m, int e)
{
    float f = (float)(long)m;
    return __hz_scalb(f, e);
}

/* the large arguments: |x| > 2^7 pi/2, finite -> n (mod 8), y[0] + y[1] = x - n pi/2 */
static int rem_large(float x, float *y)
{
    uint16_t w[6], m[2], r[8], f[4], q[8];
    uint32_t hx, mx;
    int e, i0, s, n, neg = 0, p, k;
    unsigned i;
    GETW(hx, x);
    mx = (hx & 0x007FFFFFUL) | 0x00800000UL;
    e = (int)((hx >> 23) & 0xFF) - 150;         /* |x| = mx * 2^e */
    i0 = e - 2 > 1 ? e - 2 : 1;                 /* the first bit of 2/pi that matters */
    for (i = 0; i < 6; ++i) {                   /* bits i0 .. i0 + 95, as an integer */
        unsigned b = (unsigned)(i0 - 1) + 16 * (5 - i);
        unsigned qq = b >> 4, sh = b & 15;
        uint32_t v = ((uint32_t)twobypi[qq] << 16) | twobypi[qq + 1];
        w[i] = (uint16_t)(v >> (16 - sh));
    }
    m[0] = (uint16_t)mx;
    m[1] = (uint16_t)(mx >> 16);
    mul(r, m, 2, w, 6);                         /* |x| * 2/pi = r * 2^-s */
    s = i0 + 95 - e;
    n = (int)(bits16(r, 8, (unsigned)s) & 7);
    for (i = 0; i < 4; ++i)                     /* the fraction: 64 bits */
        f[i] = bits16(r, 8, (unsigned)(s - 64 + 16 * (int)i));
    if (f[3] & 0x8000) {                        /* >= 1/2: the next multiple, from below */
        uint32_t c = 1;
        n = (n + 1) & 7;
        neg = 1;
        for (i = 0; i < 4; ++i) {
            c += (uint16_t)~f[i];
            f[i] = (uint16_t)c;
            c >>= 16;
        }
    }
    mul(q, f, 4, pio2_63, 4);                   /* the fraction * pi/2: q[4..7] * 2^-63 */
    for (p = 63; p >= 0 && !((bits16(q, 8, (unsigned)(64 + p)) & 1)); --p)
        ;
    if (p < 24) {                               /* (never: no float is that near) */
        y[0] = y[1] = 0.0f;
    } else {
        uint32_t hi, lo;
        hi = (uint32_t)bits16(q, 8, (unsigned)(64 + p - 23)) |
             ((uint32_t)(bits16(q, 8, (unsigned)(64 + p - 7)) & 0x00FF) << 16);
        k = p - 47;
        lo = (uint32_t)bits16(q, 8, (unsigned)(64 + k)) |
             ((uint32_t)(bits16(q, 8, (unsigned)(64 + k + 16)) & 0x00FF) << 16);
        y[0] = mkf(hi, p - 23 - 63);
        y[1] = mkf(lo, k - 63);
    }
    if (neg) {
        y[0] = -y[0];
        y[1] = -y[1];
    }
    if (hx >> 31) {
        y[0] = -y[0];
        y[1] = -y[1];
        n = -n;
    }
    return n;
}

/* x - n pi/2 = y[0] + y[1], |y| <= pi/4 (about) -> n */
static int rem_pio2(float x, float *y)
{
    static const float invpio2 = 6.3661980629e-01f, pio2_1 = 1.5707855225e+00f,
                       pio2_1t = 1.0804334124e-05f, pio2_2 = 1.0804273188e-05f,
                       pio2_2t = 6.0770999344e-11f, pio2_3 = 6.0770943833e-11f,
                       pio2_3t = 6.1232342629e-17f;
    float z, w, t, r, fn;
    int32_t hx, ix, n, j, i;
    uint32_t high;
    GETW(hx, x);
    ix = hx & 0x7FFFFFFFL;
    if (ix > 0x43490F80L)
        return rem_large(x, y);
    t = fabs(x);
    n = (int32_t)(t * invpio2 + 0.5f);
    fn = (float)n;
    r = t - fn * pio2_1;
    w = fn * pio2_1t;                           /* good to 40 bits */
    j = ix >> 23;
    y[0] = r - w;
    GETW(high, y[0]);
    i = j - (int32_t)((high >> 23) & 0xFF);
    if (i > 8) {                                /* cancellation: 57 bits */
        t = r;
        w = fn * pio2_2;
        r = t - w;
        w = fn * pio2_2t - ((t - r) - w);
        y[0] = r - w;
        GETW(high, y[0]);
        i = j - (int32_t)((high >> 23) & 0xFF);
        if (i > 25) {                           /* 74 bits */
            t = r;
            w = fn * pio2_3;
            r = t - w;
            w = fn * pio2_3t - ((t - r) - w);
            y[0] = r - w;
        }
    }
    y[1] = (r - y[0]) - w;
    (void)z;
    if (hx < 0) {
        y[0] = -y[0];
        y[1] = -y[1];
        return (int)-n;
    }
    return (int)n;
}

static float k_sin(float x, float y, int iy)
{
    static const float half = 5.0e-01f, S1 = -1.6666667163e-01f, S2 = 8.3333337680e-03f,
                       S3 = -1.9841270114e-04f, S4 = 2.7557314297e-06f,
                       S5 = -2.5050759689e-08f, S6 = 1.5896910177e-10f;
    float z, r, v;
    uint32_t ix;
    GETW(ix, x);
    ix &= 0x7FFFFFFFUL;
    if (ix < 0x32000000UL)                      /* |x| < 2^-27 */
        return x;
    z = x * x;
    v = z * x;
    r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
    if (iy == 0)
        return x + v * (S1 + z * r);
    return x - ((z * (half * y - v * r) - y) - v * S1);
}

static float k_cos(float x, float y)
{
    static const float C1 = 4.1666667908e-02f, C2 = -1.3888889225e-03f,
                       C3 = 2.4801587642e-05f, C4 = -2.7557314297e-07f,
                       C5 = 2.0875723372e-09f, C6 = -1.1359647598e-11f;
    float a, hz, z, r, qx;
    uint32_t ix;
    GETW(ix, x);
    ix &= 0x7FFFFFFFUL;
    if (ix < 0x32000000UL)
        return 1.0f;
    z = x * x;
    r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
    if (ix < 0x3E99999AUL)                      /* |x| < 0.3 */
        return 1.0f - (0.5f * z - (z * r - x * y));
    if (ix > 0x3F480000UL)                      /* |x| > 0.78125 */
        qx = 0.28125f;
    else
        SETW(qx, ix - 0x01000000UL);            /* x / 4 */
    hz = 0.5f * z - qx;
    a = 1.0f - qx;
    return a - (hz - (z * r - x * y));
}

static float k_tan(float x, float y, int iy)
{
    static const float pio4 = 7.8539812565e-01f, pio4lo = 3.7748947079e-08f;
    static const float T[13] = {
        3.3333334327e-01f, 1.3333334029e-01f, 5.3968254477e-02f, 2.1869488060e-02f,
        8.8632395491e-03f, 3.5920790397e-03f, 1.4562094584e-03f, 5.8804126456e-04f,
        2.4646313977e-04f, 7.8179444245e-05f, 7.1407252108e-05f, -1.8558637748e-05f,
        2.5907305826e-05f};
    float z, r, v, w, s;
    int32_t ix, hx;
    GETW(hx, x);
    ix = hx & 0x7FFFFFFFL;
    if (ix < 0x31800000L) {                     /* |x| < 2^-28 */
        if (ix == 0 && iy == -1)
            return 1.0f / fabs(x);
        return iy == 1 ? x : -1.0f / x;
    }
    if (ix >= 0x3F2CA140L) {                    /* |x| >= 0.6744 */
        if (hx < 0) {
            x = -x;
            y = -y;
        }
        z = pio4 - x;
        w = pio4lo - y;
        x = z + w;
        y = 0.0f;
    }
    z = x * x;
    w = z * z;
    r = T[1] + w * (T[3] + w * (T[5] + w * (T[7] + w * (T[9] + w * T[11]))));
    v = z * (T[2] + w * (T[4] + w * (T[6] + w * (T[8] + w * (T[10] + w * T[12])))));
    s = z * x;
    r = y + z * (s * (r + v) + y);
    r += T[0] * s;
    w = x + r;
    if (ix >= 0x3F2CA140L) {
        v = (float)iy;
        return (float)(1 - ((hx >> 30) & 2)) * (v - 2.0f * (x - (w * w / (w + v) - r)));
    }
    if (iy == 1)
        return w;
    {                                           /* -1/(x + r), accurately */
        float a, t;
        uint32_t i;
        z = w;
        GETW(i, z);
        SETW(z, i & 0xFFFFF000UL);
        v = r - (z - x);
        t = a = -1.0f / w;
        GETW(i, t);
        SETW(t, i & 0xFFFFF000UL);
        s = 1.0f + t * z;
        return t + a * (s + t * v);
    }
}

double sin(double x)
{
    float y[2];
    uint32_t ix;
    int n;
    GETW(ix, x);
    ix &= 0x7FFFFFFFUL;
    if (ix <= 0x3F490FD8UL)                     /* |x| <= pi/4 */
        return k_sin(x, 0.0f, 0);
    if (ix >= 0x7F800000UL)
        return x - x;                           /* inf, NaN */
    n = rem_pio2(x, y);
    switch (n & 3) {
    case 0: return k_sin(y[0], y[1], 1);
    case 1: return k_cos(y[0], y[1]);
    case 2: return -k_sin(y[0], y[1], 1);
    default: return -k_cos(y[0], y[1]);
    }
}

double cos(double x)
{
    float y[2];
    uint32_t ix;
    int n;
    GETW(ix, x);
    ix &= 0x7FFFFFFFUL;
    if (ix <= 0x3F490FD8UL)
        return k_cos(x, 0.0f);
    if (ix >= 0x7F800000UL)
        return x - x;
    n = rem_pio2(x, y);
    switch (n & 3) {
    case 0: return k_cos(y[0], y[1]);
    case 1: return -k_sin(y[0], y[1], 1);
    case 2: return -k_cos(y[0], y[1]);
    default: return k_sin(y[0], y[1], 1);
    }
}

double tan(double x)
{
    float y[2];
    uint32_t ix;
    int n;
    GETW(ix, x);
    ix &= 0x7FFFFFFFUL;
    if (ix <= 0x3F490FDAUL)
        return k_tan(x, 0.0f, 1);
    if (ix >= 0x7F800000UL)
        return x - x;
    n = rem_pio2(x, y);
    return k_tan(y[0], y[1], 1 - ((n & 1) << 1));
}
