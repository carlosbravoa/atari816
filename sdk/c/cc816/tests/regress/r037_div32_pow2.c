/* r037_div32_pow2.c - a signed long / and % by +-2^n, now inline (the bias for a negative
 * dividend, then an arithmetic shift; the remainder -((-x) & (2^n - 1))) instead of calls
 * of __sdiv32 / __smod32 (the SkyRoads port: long / 512, / 16). Every n against the
 * helpers' results (the divisor in a volatile), for the edges (LONG_MIN, LONG_MAX, -1,
 * +-2^k +-1) and a pseudo-random walk; long long's unsigned powers of two are shifts and
 * masks (opt.py), its signed ones calls.
 * LEVELS: 0 1 2 */
static volatile long vk;

#define D(K) do { long k_ = vk + (K); if (x / (K) != x / k_ || x % (K) != x % k_) return __LINE__; } while (0)
#define U(K) do { unsigned long k_ = (unsigned long)vk + (K); if (u / (K) != u / k_ || u % (K) != u % k_) return __LINE__; } while (0)

static int sdiv(long x)
{
    D(2L); D(4L); D(8L); D(16L); D(32L); D(64L); D(128L); D(256L); D(512L); D(1024L);
    D(2048L); D(4096L); D(8192L); D(16384L); D(32768L); D(65536L); D(1L << 17);
    D(1L << 18); D(1L << 19); D(1L << 20); D(1L << 21); D(1L << 22); D(1L << 23);
    D(1L << 24); D(1L << 25); D(1L << 26); D(1L << 27); D(1L << 28); D(1L << 29);
    D(1L << 30);
    D(-2L); D(-16L); D(-512L); D(-32768L); D(-65536L); D(-(1L << 24)); D(-(1L << 30));
    /* % LONG_MIN (the same as % 2^31); / LONG_MIN is a call */
    { long k_ = vk + (-2147483647L - 1);
      if (x % (-2147483647L - 1) != x % k_ || x / (-2147483647L - 1) != x / k_)
          return __LINE__; }
    return 0;
}

static int udiv(unsigned long u)
{
    U(2UL); U(16UL); U(512UL); U(65536UL); U(1UL << 31); U(1UL << 20);
    return 0;
}

/* the dividend in a register used afterwards, the result into the same register */
static long twice(long x)
{
    long y = x / 16;
    x = x / 512 + y;
    return x - y % 64;
}

static int ll(long long x)
{
    volatile long long k = 0;
    if (x / 8 != x / (k + 8) || x % 8 != x % (k + 8))
        return 1;
    if ((unsigned long long)x / 1024 != (unsigned long long)x / (unsigned long long)(k + 1024))
        return 2;
    if ((unsigned long long)x % 1024 != (unsigned long long)x % (unsigned long long)(k + 1024))
        return 3;
    return 0;
}

int main(void)
{
    static const long edge[] = { 0, 1, -1, 2, -2, 3, -3, 15, 16, 17, -15, -16, -17, 511, 512,
                                 513, -511, -512, -513, 32767, 32768, -32768, -32769, 65535,
                                 65536, -65536, -65537, 0x7FFFFFL, 0x1000000L, -0x1000000L,
                                 0x3FFFFFFFL, 0x40000000L, -0x40000000L, -0x40000001L,
                                 0x7FFFFFFFL, -0x7FFFFFFFL, -2147483647L - 1 };
    unsigned i;
    int r;
    unsigned long s = 12345;
    for (i = 0; i < sizeof edge / sizeof edge[0]; i++) {
        if ((r = sdiv(edge[i])) != 0)
            return r;
        if ((r = udiv((unsigned long)edge[i])) != 0)
            return r;
        if ((r = ll(edge[i])) != 0 || (r = ll((long long)edge[i] << 20)) != 0)
            return 100 + r;
    }
    for (i = 0; i < 300; i++) {
        s = s * 1103515245UL + 12345UL;
        if ((r = sdiv((long)s)) != 0 || (r = sdiv((long)s >> (i & 31))) != 0)
            return r;
    }
    if (twice(-100000L) != -100000L / 512 + -100000L / 16 - (-100000L / 16) % 64)
        return 1;
    if (twice(77777L) != 77777L / 512 + 77777L / 16 - (77777L / 16) % 64)
        return 2;
    return 0;
}
