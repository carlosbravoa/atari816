/* hg_util.c - hgame: random numbers, sine / cosine / atan2, fixed point, rectangles. */
#include "hg_int.h"

static unsigned seed = 0xACE1;

void hg_srand(unsigned s)
{
    seed = s ? s : 0xACE1;
}

unsigned hg_rand(void)
{
    seed ^= seed << 7;
    seed ^= seed >> 9;
    seed ^= seed << 8;
    return seed;
}

unsigned hg_rand_n(unsigned n)
{
    if (n == 0)
        return 0;
    return (unsigned)(((unsigned long)hg_rand() * n) >> 16);
}

/* sin of 0..64 (a quarter turn) in 8.8: round(256 * sin(k * pi / 128)) */
static const unsigned short quarter[65] = {
    0, 6, 13, 19, 25, 31, 38, 44, 50, 56, 62, 68, 74, 80, 86, 92,
    98, 104, 109, 115, 121, 126, 132, 137, 142, 147, 152, 157, 162, 167, 172, 177,
    181, 185, 190, 194, 198, 202, 206, 209, 213, 216, 220, 223, 226, 229, 231, 234,
    237, 239, 241, 243, 245, 247, 248, 250, 251, 252, 253, 254, 255, 255, 256, 256,
    256
};

hg_fix8 hg_sin(unsigned a)
{
    int v;
    a &= 255;
    if (a < 64)
        v = quarter[a];
    else if (a < 128)
        v = quarter[128 - a];
    else if (a < 192)
        v = -(int)quarter[a - 128];
    else
        v = -(int)quarter[256 - a];
    return v;
}

hg_fix8 hg_cos(unsigned a)
{
    return hg_sin(a + 64);
}

/* atan(k / 32) for k = 0..32 in 256ths of a turn */
static const unsigned char atab[33] = {
    0, 1, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 25, 26, 27, 28, 29, 29, 30, 31, 31, 32
};

unsigned hg_atan2(int dy, int dx)
{
    unsigned ax = (unsigned)(dx < 0 ? -dx : dx), ay = (unsigned)(dy < 0 ? -dy : dy), a;
    if (!ax && !ay)
        return 0;
    if (ax >= ay)
        a = atab[(unsigned)(((unsigned long)ay * 32) / ax)];
    else
        a = 64 - atab[(unsigned)(((unsigned long)ax * 32) / ay)];
    if (dx < 0)
        a = 128 - a;
    if (dy < 0)
        a = 256 - a;
    return a & 255;
}

hg_fix16 hg_fix16_mul(hg_fix16 a, hg_fix16 b)
{
    unsigned long ua, ub, ah, al, bh, bl, r;
    int neg = 0;
    if (a < 0) {
        ua = (unsigned long)-a;
        neg = 1;
    } else
        ua = (unsigned long)a;
    if (b < 0) {
        ub = (unsigned long)-b;
        neg ^= 1;
    } else
        ub = (unsigned long)b;
    ah = ua >> 16;
    al = ua & 0xFFFF;
    bh = ub >> 16;
    bl = ub & 0xFFFF;
    r = ((ah * bh) << 16) + ah * bl + al * bh + ((al * bl) >> 16);
    return neg ? -(hg_fix16)r : (hg_fix16)r;
}

hg_fix16 hg_fix16_div(hg_fix16 a, hg_fix16 b)
{
    unsigned long ua, ub, q, r;
    unsigned i;
    int neg = 0;
    if (b == 0)
        return a < 0 ? -0x7FFFFFFFL : 0x7FFFFFFFL;
    if (a < 0) {
        ua = (unsigned long)-a;
        neg = 1;
    } else
        ua = (unsigned long)a;
    if (b < 0) {
        ub = (unsigned long)-b;
        neg ^= 1;
    } else
        ub = (unsigned long)b;
    q = ua / ub;
    r = ua % ub;
    for (i = 0; i < 16; i++) {          /* 16 more bits of the quotient */
        q <<= 1;
        r <<= 1;
        if (r >= ub) {
            r -= ub;
            q |= 1;
        }
    }
    return neg ? -(hg_fix16)q : (hg_fix16)q;
}

int hg_overlap(int x1, int y1, unsigned w1, unsigned h1, int x2, int y2, unsigned w2,
               unsigned h2)
{
    return x1 < x2 + (int)w2 && x2 < x1 + (int)w1 && y1 < y2 + (int)h2 && y2 < y1 + (int)h1;
}
