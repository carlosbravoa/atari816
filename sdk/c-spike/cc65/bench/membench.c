/* membench.c - memcpy speed (4 KB blocks) and a correctness check, for FASTRT=0 vs 1. */
#include <stdio.h>
#include <string.h>
#include "horizon.h"

static char a[4096], b[4096];

int main(void)
{
    unsigned i, sum = 0;
    unsigned long t;
    for (i = 0; i < sizeof a; i++) a[i] = (char)(i * 7);
    t = hz_uptime();
    for (i = 0; i < 100; i++) memcpy(b, a, sizeof a);
    t = hz_uptime() - t;
    memmove(a + 1, a, 1000);                     /* overlapping, downwards (not memcpy) */
    memmove(a, a + 3, 1000);                     /* overlapping, upwards: memcpy_upwards */
    for (i = 0; i < sizeof b; i++) sum += (unsigned char)b[i] ^ (unsigned char)a[i];
    printf("membench memcpy 100 x 4096 bytes: %lu ms, check %u\n", t, sum);
    return 0;
}
