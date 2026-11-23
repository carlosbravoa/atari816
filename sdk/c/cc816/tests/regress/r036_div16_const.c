/* r036_div16_const.c - 16-bit division and remainder by constants, now inline: x % 2^n
 * signed (it was a call of __smod16), x / -2^n, and every other constant as a multiply by
 * its reciprocal (gen.py div16_const: the reciprocal is checked for every dividend when
 * the compiler picks it; the code is checked here). Each constant against the helpers'
 * results (the same divisor in a volatile: __sdiv16 / __udiv16), for the edges and a walk
 * over the whole range. The SkyRoads port: int / 5, / 10, % 10.
 * LEVELS: 0 1 2 */
static volatile int vk;
static volatile unsigned vu;

#define SD(K) do { int k_ = vk + (K); if (x / (K) != x / k_ || x % (K) != x % k_) return __LINE__; } while (0)
#define UD(K) do { unsigned k_ = vu + (K); if (u / (K) != u / k_ || u % (K) != u % k_) return __LINE__; } while (0)

static int sdivs(int x)
{
    SD(2); SD(4); SD(8); SD(16); SD(64); SD(256); SD(1024); SD(0x4000);
    SD(-2); SD(-4); SD(-16); SD(-256); SD(-0x4000);
    SD(3); SD(5); SD(6); SD(7); SD(9); SD(10); SD(11); SD(12); SD(13); SD(14); SD(15);
    SD(17); SD(25); SD(46); SD(60); SD(100); SD(127); SD(255); SD(641); SD(1000);
    SD(5888); SD(10000); SD(12345); SD(16383); SD(16385); SD(32767);
    SD(-3); SD(-5); SD(-7); SD(-10); SD(-100); SD(-1000); SD(-32767);
    return 0;
}

static int udivs(unsigned u)
{
    UD(3u); UD(5u); UD(6u); UD(7u); UD(9u); UD(10u); UD(11u); UD(12u); UD(13u);
    UD(46u); UD(60u); UD(100u); UD(255u); UD(641u); UD(1000u); UD(5888u); UD(10000u);
    UD(32767u); UD(32769u); UD(40000u); UD(65535u); UD(65534u); UD(0x8001u);
    UD(2u); UD(16u); UD(0x8000u);
    return 0;
}

/* the quotient as a value used again (the register holding x is the result's too) */
static int again(int x)
{
    x = x / 10;
    x = x % 7;
    return x;
}

int main(void)
{
    static const int edge[] = { 0, 1, -1, 2, -2, 3, -3, 4, 5, -5, 9, 10, -10, 11, 15, -15,
                                16, -16, 17, 99, 100, -100, 101, 255, 256, -256, 999, 1000,
                                -1000, 5887, 5888, 5889, -5888, 9999, 10000, 16383, 16384,
                                -16384, -16385, 32766, 32767, -32767, -32768 };
    unsigned i;
    int r;
    long x;
    for (i = 0; i < sizeof edge / sizeof edge[0]; i++) {
        if ((r = sdivs(edge[i])) != 0)
            return r;
        if ((r = udivs((unsigned)edge[i])) != 0)
            return r;
    }
    for (x = -32768; x <= 32767; x += 251) {      /* (a walk over the whole range) */
        if ((r = sdivs((int)x)) != 0)
            return r;
        if ((r = udivs((unsigned)x)) != 0)
            return r;
    }
    if (again(-12345) != -1234 % 7 || again(32767) != 3276 % 7)
        return 1;
    if (-7 / 2 != -3 || -7 % 2 != -1 || 7 % -2 != 1 || -7 / -2 != 3)
        return 2;
    return 0;
}
