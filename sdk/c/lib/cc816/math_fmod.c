/* math_fmod.c - math.h for cc816: fmod (exact: fdlibm's integer method), remainder. */
#include <math.h>
#include "mathint.h"

double fmod(double x, double y)
{
    int32_t n, hx, hy, hz, ix, iy, sx, i;
    GETW(hx, x);
    GETW(hy, y);
    sx = hx & 0x80000000L;
    hx ^= sx;                           /* |x| */
    hy &= 0x7FFFFFFFL;                  /* |y| */
    if (hy == 0 || hx >= 0x7F800000L || hy > 0x7F800000L)
        return (x * y) / (x * y);       /* y = 0, x not finite, y NaN: NaN */
    if (hx < hy)
        return x;                       /* |x| < |y| */
    if (hx == hy) {
        SETW(x, sx);                    /* |x| = |y|: a signed 0 */
        return x;
    }
    /* the exponents */
    if (hx < 0x00800000L) {
        for (ix = -126, i = hx << 8; i > 0; i <<= 1)
            --ix;
    } else
        ix = (hx >> 23) - 127;
    if (hy < 0x00800000L) {
        for (iy = -126, i = hy << 8; i >= 0; i <<= 1)
            --iy;
    } else
        iy = (hy >> 23) - 127;
    /* the significands, normalised */
    if (ix >= -126)
        hx = 0x00800000L | (0x007FFFFFL & hx);
    else
        hx <<= -126 - ix;
    if (iy >= -126)
        hy = 0x00800000L | (0x007FFFFFL & hy);
    else
        hy <<= -126 - iy;
    /* fixed-point fmod */
    n = ix - iy;
    while (n--) {
        hz = hx - hy;
        if (hz < 0)
            hx = hx + hx;
        else {
            if (hz == 0) {
                SETW(x, sx);
                return x;
            }
            hx = hz + hz;
        }
    }
    hz = hx - hy;
    if (hz >= 0)
        hx = hz;
    if (hx == 0) {
        SETW(x, sx);
        return x;
    }
    while (hx < 0x00800000L) {          /* normalise */
        hx = hx + hx;
        --iy;
    }
    if (iy >= -126)
        hx = (hx - 0x00800000L) | ((iy + 127) << 23);
    else
        hx >>= -126 - iy;               /* a denormal (exact) */
    SETW(x, hx | sx);
    return x;
}

double remainder(double x, double p)
{
    int32_t hx, hp;
    uint32_t sx;
    float ph;
    GETW(hx, x);
    GETW(hp, p);
    sx = (uint32_t)hx & 0x80000000UL;
    hp &= 0x7FFFFFFFL;
    hx &= 0x7FFFFFFFL;
    if (hp == 0 || hx >= 0x7F800000L || hp > 0x7F800000L)
        return (x * p) / (x * p);
    if (hp <= 0x7EFFFFFFL)
        x = fmod(x, p + p);             /* now |x| < 2|p| */
    if (hx - hp == 0)
        return 0.0f * x;
    x = fabs(x);
    p = fabs(p);
    if (hp < 0x01000000L) {
        if (x + x > p) {
            x -= p;
            if (x + x >= p)
                x -= p;
        }
    } else {
        ph = 0.5f * p;
        if (x > ph) {
            x -= p;
            if (x >= ph)
                x -= p;
        }
    }
    GETW(hx, x);
    SETW(x, (uint32_t)hx ^ sx);
    return x;
}
