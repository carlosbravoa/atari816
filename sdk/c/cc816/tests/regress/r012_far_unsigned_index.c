/* r012_far_unsigned_index.c - a __far pointer plus an unsigned variable of 32768 or more
 * (p + u, p - u) sign-extended the index: the pointer went backwards (bug 3 was the same
 * for constants). Unsigned indexes are now zero-extended. Found while checking the front
 * end (tests/lang/farptr.c). */
#include <horizon.h>

int main(void)
{
    unsigned char __far *p = hz_far_alloc();
    unsigned char __far *q;
    volatile unsigned u = 40000u;
    volatile int i = -3;
    if (!p)
        return 1;
    p[40000u] = 7;
    q = p + u;
    if (*q != 7)
        return 2;
    q = q - u;
    if (q != p)
        return 3;
    q = p + 40003u;
    q = q + i;
    if (*q != 7)
        return 4;
    hz_far_free(p);
    return 0;
}
