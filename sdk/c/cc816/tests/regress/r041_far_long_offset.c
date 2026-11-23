/* r041_far_long_offset.c - a far pointer plus a long (p + 39999: a decimal constant over
 * 32,767 is a long in C) took the long's low word as an int: 39999 became -25537 and the
 * pointer went back a bank. The whole 32-bit value is added now (and with far data a long
 * variable too). Found by the far data model's own test (tests/far/farprog.c). */
#include <horizon.h>

int main(void)
{
    unsigned char __far *b = hz_far_alloc();
    unsigned char __far *p, __far *q;
    if (!b)
        return 1;
    b[39999u] = 7;
    b[65535u] = 9;
    p = b + 39999;
    if (*p != 7 || HZ_BANK(p) != HZ_BANK(b) || HZ_OFF(p) != 39999u)
        return 2;
    q = p - 39999L;
    if (q != b)
        return 3;
    p = b + 65535L;
    if (*p != 9 || HZ_BANK(p) != HZ_BANK(b))
        return 4;
    if ((unsigned long)(b + 70000L) != (unsigned long)b + 70000UL)
        return 5;
#ifdef __CC816_FAR_DATA__
    {
        long n = 39999L;
        int __far *ip = (int __far *)b;
        p = b + n;
        if (*p != 7)
            return 6;
        if ((unsigned char __far *)(ip + 10000L) != b + 20000u)
            return 7;
    }
#endif
    hz_far_free(b);
    return 0;
}
