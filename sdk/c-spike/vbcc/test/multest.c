/* multest.c - check 32-bit multiply/divide results without printf's own arithmetic */
#include <stdio.h>
#include "horizon.h"
static char buf[12];
static void hex(unsigned long v)
{
    int i; static const char d[] = "0123456789ABCDEF";
    for (i = 7; i >= 0; i--) { buf[i] = d[(unsigned)v & 15]; v >>= 4; }
    buf[8] = ' '; buf[9] = 0; hz_puts(buf);
}
volatile unsigned long a = 12345, b = 1103515245UL, c = 0xDEADBEEFUL, d7 = 7, big = 0x12345UL;
volatile long sa = -123456789L, sb = 1000L;
int main(void)
{
    hex(a * b); hex(c * b); hex(c * c); hex(c / d7); hex(c % d7);
    hex(c / big); hex(c % big); hex(c / 0x10000UL); hex(sa / sb); hex(sa % sb); hex(sa * sb); hex(0);
    hz_puts("\n");
    printf("%lu %lu %lu\n", a * b, 4275534039UL, c);
    return 0;
}
