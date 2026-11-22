/* math_pow.c - math.h for cc816: pow (fdlibm's single-precision method: log2 of x to about
 * 34 bits in float pairs, times y, then 2^ of that). Two changes: the head of 2/(3 ln2),
 * cp_h, has 12 bits, so that cp_h * p_h is exact (with fdlibm's 13 bits it is not, and
 * pow lost up to 100 ulp when x is near 1 and y large); |y| > 2^27 overflows only when
 * the product says so. */
#include <math.h>
#include "mathint.h"

static const float bp[2] = {1.0f, 1.5f}, dp_h[2] = {0.0f, 5.84960938e-01f},
                   dp_l[2] = {0.0f, 1.56322085e-06f};
#define two24 16777216.0f
#define huge 1.0e30f
#define tiny 1.0e-30f
#define L1 6.0000002384e-01f
#define L2 4.2857143283e-01f
#define L3 3.3333334327e-01f
#define L4 2.7272811532e-01f
#define L5 2.3066075146e-01f
#define L6 2.0697501302e-01f
#define P1 1.6666667163e-01f
#define P2 -2.7777778450e-03f
#define P3 6.6137559770e-05f
#define P4 -1.6533901999e-06f
#define P5 4.1381369442e-08f
#define lg2 6.9314718246e-01f
#define lg2_h 6.93145752e-01f
#define lg2_l 1.42860654e-06f
#define ovt 4.2995665694e-08f
#define cp 9.6179670095e-01f
#define cp_h 9.6166992188e-01f            /* 12 bits (fdlibm's 13 made z_h inexact) */
#define cp_l 1.2677205098e-04f
#define ivln2 1.4426950216e+00f
#define ivln2_h 1.4426879883e+00f
#define ivln2_l 7.0526075433e-06f

#define TRUNC12(v) do { uint32_t w_; GETW(w_, v); SETW(v, w_ & 0xFFFFF000UL); } while (0)

double pow(double x, double y)
{
    float z, ax, z_h, z_l, p_h, p_l, y1, t1, t2, r, s, t, u, v, w;
    int32_t i, j, k, yisint, n, hx, hy, ix, iy;
    GETW(hx, x);
    GETW(hy, y);
    ix = hx & 0x7FFFFFFFL;
    iy = hy & 0x7FFFFFFFL;
    if (iy == 0)
        return 1.0f;                            /* x^0 = 1, also for a NaN x */
    if (hx == 0x3F800000L)
        return 1.0f;                            /* 1^y = 1, also for a NaN y */
    if (ix > 0x7F800000L || iy > 0x7F800000L)
        return x + y;
    /* x < 0: is y an integer? 0 no, 1 odd, 2 even */
    yisint = 0;
    if (hx < 0) {
        if (iy >= 0x4B800000L)
            yisint = 2;
        else if (iy >= 0x3F800000L) {
            k = (iy >> 23) - 0x7F;
            j = iy >> (23 - k);
            if ((j << (23 - k)) == iy)
                yisint = 2 - (j & 1);
        }
    }
    if (iy == 0x7F800000L) {                    /* y = +-inf */
        if (ix == 0x3F800000L)
            return 1.0f;                        /* (-1)^+-inf = 1 */
        if (ix > 0x3F800000L)
            return hy >= 0 ? y : 0.0f;
        return hy < 0 ? -y : 0.0f;
    }
    if (iy == 0x3F800000L)                      /* y = +-1 */
        return hy < 0 ? 1.0f / x : x;
    if (hy == 0x40000000L)
        return x * x;                           /* y = 2 */
    if (hy == 0x3F000000L && hx >= 0)
        return sqrt(x);                         /* y = 1/2, x >= +0 */
    ax = fabs(x);
    if (ix == 0x7F800000L || ix == 0 || ix == 0x3F800000L) {
        z = ax;                                 /* x = +-0, +-inf, +-1 */
        if (hy < 0)
            z = 1.0f / z;
        if (hx < 0) {
            if (((ix - 0x3F800000L) | yisint) == 0)
                z = (z - z) / (z - z);          /* (-1)^non-integer */
            else if (yisint == 1)
                z = -z;
        }
        return z;
    }
    if (hx < 0 && yisint == 0)
        return (x - x) / (x - x);               /* negative ^ non-integer: NaN */
    if (iy > 0x4D000000L && ix >= 0x3F7FFFF8L && ix <= 0x3F800007L) {
        /* |y| > 2^27 and x within 8 ulp of 1: log(x) by its series (fdlibm returned
         * inf or 0 for every other x when |y| > 2^27, wrong for x just beyond: 1 - 9
         * ulp to the -2^27.3 is 2^124; the general path below handles them) */
        t = ax - 1.0f;
        w = (t * t) * (0.5f - t * (0.333333333333f - t * 0.25f));
        u = ivln2_h * t;
        v = t * ivln2_l - w * ivln2;
        t1 = u + v;
        TRUNC12(t1);
        t2 = v - (t1 - u);
    } else {
        float s2, s_h, s_l, t_h, t_l;
        n = 0;
        if (ix < 0x00800000L) {                 /* a denormal */
            ax *= two24;
            n -= 24;
            GETW(ix, ax);
        }
        n += (ix >> 23) - 0x7F;
        j = ix & 0x007FFFFFL;
        ix = j | 0x3F800000L;
        if (j <= 0x1CC471L)
            k = 0;                              /* |x| < sqrt(3/2) */
        else if (j < 0x5DB3D7L)
            k = 1;                              /* |x| < sqrt(3) */
        else {
            k = 0;
            n += 1;
            ix -= 0x00800000L;
        }
        SETW(ax, ix);
        /* s = s_h + s_l = (x - 1) / (x + 1) or (x - 1.5) / (x + 1.5) */
        u = ax - bp[k];
        v = 1.0f / (ax + bp[k]);
        s = u * v;
        s_h = s;
        TRUNC12(s_h);
        SETW(t_h, (((ix >> 1) & 0xFFFFF000L) | 0x20000000L) + 0x00400000L + (k << 21));
        t_l = ax - (t_h - bp[k]);
        s_l = v * ((u - s_h * t_h) - s_h * t_l);
        /* log(ax) */
        s2 = s * s;
        r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))));
        r += s_l * (s_h + s);
        s2 = s_h * s_h;
        t_h = 3.0f + s2 + r;
        TRUNC12(t_h);
        t_l = r - ((t_h - 3.0f) - s2);
        u = s_h * t_h;
        v = s_l * t_h + t_l * s;
        p_h = u + v;
        TRUNC12(p_h);
        p_l = v - (p_h - u);
        z_h = cp_h * p_h;
        z_l = cp_l * p_h + p_l * cp + dp_l[k];
        t = (float)n;
        t1 = ((z_h + z_l) + dp_h[k]) + t;
        TRUNC12(t1);
        t2 = z_l - (((t1 - t) - dp_h[k]) - z_h);
    }
    s = 1.0f;                                   /* the sign: negative ^ odd */
    if (hx < 0 && yisint == 1)
        s = -1.0f;
    /* (y1 + y2) * (t1 + t2) */
    y1 = y;
    TRUNC12(y1);
    p_l = (y - y1) * t1 + y * t2;
    p_h = y1 * t1;
    z = p_l + p_h;
    GETW(j, z);
    if (j > 0x43000000L)                        /* z > 128 */
        return s * huge * huge;
    if (j == 0x43000000L) {
        if (p_l + ovt > z - p_h)
            return s * huge * huge;
    } else if ((j & 0x7FFFFFFFL) > 0x43160000L) /* z < -150 */
        return s * tiny * tiny;
    else if ((uint32_t)j == 0xC3160000UL) {     /* z = -150 */
        if (p_l <= z - p_h)
            return s * tiny * tiny;
    }
    /* 2^(p_h + p_l) */
    i = j & 0x7FFFFFFFL;
    k = (i >> 23) - 0x7F;
    n = 0;
    if (i > 0x3F000000L) {                      /* |z| > 1/2: n = [z + 1/2] */
        n = j + (0x00800000L >> (k + 1));
        k = ((n & 0x7FFFFFFFL) >> 23) - 0x7F;
        SETW(t, n & ~(0x007FFFFFL >> k));
        n = ((n & 0x007FFFFFL) | 0x00800000L) >> (23 - k);
        if (j < 0)
            n = -n;
        p_h -= t;
    }
    t = p_l + p_h;
    {
        uint32_t w_;
        GETW(w_, t);
        SETW(t, w_ & 0xFFFF8000UL);
    }
    u = t * lg2_h;
    v = (p_l - (t - p_h)) * lg2 + t * lg2_l;
    z = u + v;
    w = v - (z - u);
    t = z * z;
    t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    r = (z * t1) / (t1 - 2.0f) - (w + z * w);
    z = 1.0f - (r - z);
    GETW(j, z);
    j += (int32_t)((uint32_t)n << 23);
    if ((j >> 23) <= 0)
        z = __hz_scalb(z, n);                   /* a denormal result */
    else
        SETW(z, j);
    return s * z;
}
