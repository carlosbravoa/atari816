/* farptr.c - __far pointers: arithmetic with signed and unsigned indexes (also 32768
 * and more), differences, compares, a far array of structures. */
#include <horizon.h>

struct rec { int a; long b; };

int main(void)
{
    unsigned char __far *p = hz_far_alloc();
    unsigned char __far *q;
    struct rec __far *r;
    unsigned u = 40000u;
    int i = -2;
    long d;
    if (!p)
        return 1;
    p[40000u] = 7;
    q = p + u;                  /* an unsigned index over 32767: forwards */
    if (*q != 7 || q - p != (int)40000u)
        return 2;
    q = q + i;                  /* a negative index: backwards */
    if (q != p + 39998u || q[2] != 7)
        return 3;
    q -= u - 2;
    if (q != p)
        return 4;
    if (!(p + 1 > p) || p + 100 < p + 99 || p + 5 == p)
        return 5;
    r = (struct rec __far *)(p + 1000);
    r[3].b = 123456L;
    r[3].a = -4;
    if (r[3].b != 123456L || (r + 3)->a != -4 || &r[3] - r != 3)
        return 6;
    d = (long)((unsigned char __far *)&r[3] - p);
    if (d != 1000 + 3 * 6)
        return 7;
    hz_far_free(p);
    return 0;
}
