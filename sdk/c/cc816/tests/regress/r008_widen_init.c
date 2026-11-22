/* r008_widen_init.c - a 16-bit value given to a 32-bit variable without a cast: long x =
 * -1; long y = i; (and x = -2; y = i; as assignments) must sign-extend an int and
 * zero-extend an unsigned. cc816 moved the 16-bit value into the 32-bit register as it
 * was (a zero high word): -1 became 65535. A cast ((long)i) was right, so the random
 * programs (all casts) never saw it. Found while adding floating point (float x = 3; had
 * the same path). */
static long gl(int i) { long y = i; return y; }
static long gm(int i) { long y; y = i; return y; }
static unsigned long gu(unsigned u) { unsigned long y = u; return y; }

int main(void)
{
    volatile int k = -5;
    volatile unsigned u = 0xFFFBu;
    long x = -1;
    long z;
    z = -2;
    if (x != -1L || z != -2L)
        return 1;
    if (gl(k) != -5L || gm(k) != -5L)
        return 2;
    if (gu(u) != 0xFFFBUL)
        return 3;
    {
        long w = k * 2;
        unsigned long v = u;
        if (w != -10L || v != 65531UL)
            return 4;
    }
    return 0;
}
