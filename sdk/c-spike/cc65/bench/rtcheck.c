/* rtcheck.c - exercises 32-bit multiply, divide and modulo (signed and unsigned, small and
 * large divisors) and prints one checksum per operation; compare FASTRT=0, FASTRT=1, host. */
#include <stdio.h>

int main(void)
{
    unsigned long x = 1, y, hm = 0, hd = 0, hr = 0, hs = 0;
    long a, b;
    unsigned i;
    for (i = 0; i < 3000; i++) {
        x = x * 1664525UL + 1013904223UL;
        y = (i & 1) ? (x >> 13) | 1 : (x >> 20) + 1;        /* large and small divisors */
        if (i % 3 == 0) y &= 0xFFFFUL;
        if (y == 0) y = 3;
        hm = (hm ^ (x * y)) * 33UL;
        hd += x / y;
        hr ^= x % y;
        a = (long)x; b = (long)(y ^ (x & 0x80000000UL)) | 1;
        hs += (unsigned long)(a / b) ^ (unsigned long)(a % b) ^ (unsigned long)(a * b);
    }
    printf("rtcheck %lu %lu %lu %lu\n", hm, hd, hr, hs);
    return 0;
}
