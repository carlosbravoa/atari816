/* r038_shift32.c - 32-bit shifts: by every constant 0-31 (a word move for 16 or more, a
 * byte through an unaligned word load for 8 or more, the bit tricks for 7 and 15, then bit
 * steps), each against the shift by the same count in a volatile (the helpers __shl32,
 * __shr32, __sar32: a word, a byte, then bits), and the helpers against a shift a bit at a
 * time. The operand in a direct-page register, in its incoming argument slot (a parameter
 * used once) and in a stack slot (many longs live across a call); the result into the
 * operand's own register. The SkyRoads port: x * 128, (d + 64) >> 7, 1UL << c.
 * LEVELS: 0 1 2 */
static volatile unsigned vc;

#define K32(X) X(0) X(1) X(2) X(3) X(4) X(5) X(6) X(7) X(8) X(9) X(10) X(11) X(12) X(13) \
    X(14) X(15) X(16) X(17) X(18) X(19) X(20) X(21) X(22) X(23) X(24) X(25) X(26) X(27) \
    X(28) X(29) X(30) X(31)

/* a parameter used once: read from its argument slot */
#define SL(K) static unsigned long shl##K(unsigned long x) { return x << K; }
#define SR(K) static unsigned long shr##K(unsigned long x) { return x >> K; }
#define SA(K) static long sar##K(long x) { return x >> K; }
K32(SL)
K32(SR)
K32(SA)

typedef unsigned long (*UF)(unsigned long);
typedef long (*SF)(long);
#define NM(K) shl##K,
static const UF tshl[32] = { K32(NM) };
#undef NM
#define NM(K) shr##K,
static const UF tshr[32] = { K32(NM) };
#undef NM
#define NM(K) sar##K,
static const SF tsar[32] = { K32(NM) };
#undef NM

/* a shift a bit at a time (adds, and the divide helpers: no shift code) */
static volatile unsigned long vtwo = 2;
static volatile long vstwo = 2;
static unsigned long ref_shl(unsigned long x, unsigned n) { while (n--) x += x; return x; }
static unsigned long ref_shr(unsigned long x, unsigned n) { while (n--) x /= vtwo; return x; }
static long ref_sar(long x, unsigned n)
{
    while (n--) {
        long q = x / vstwo;     /* floor(x / 2): the quotient truncates toward 0 */
        if (x < 0 && x % vstwo)
            q -= 1;
        x = q;
    }
    return x;
}

/* in registers, the result in the operand's own (x = x << k) */
static int inreg(unsigned long x, long y)
{
    unsigned long a = x;
    long b = y;
    unsigned n = vc;
    a <<= 7; b >>= 7;
    if (a != ref_shl(x, 7) || b != ref_sar(y, 7)) return 1;
    a = x; b = y;
    a >>= 15; b >>= 15;
    if (a != ref_shr(x, 15) || b != ref_sar(y, 15)) return 2;
    a = x; b = y;
    a >>= 9; b <<= 12;
    if (a != ref_shr(x, 9) || (unsigned long)b != ref_shl((unsigned long)y, 12)) return 3;
    a = x; b = y;
    a <<= n; b >>= n;
    if (a != ref_shl(x, n) || b != ref_sar(y, n)) return 4;
    return 0;
}

static long keep(long v) { return v; }

/* many longs live across calls: some in stack slots */
static int spilled(long x)
{
    long a = x + 1, b = x + 2, c = x + 3, d = x + 4, e = x + 5, f = x + 6, g = x + 7;
    long h = x + 8, i = x + 9, j = x + 10, k = x + 11, l = x + 12;
    long s = keep(a >> 7) + keep(b << 7) + keep(c >> 15) + keep(d << 15) + keep(e >> 9) +
             keep(f << 11) + keep(g >> 13) + keep(h << 3) + keep(i >> 24) + keep(j << 20) +
             keep((long)((unsigned long)k >> 7)) + keep((long)((unsigned long)l >> 12));
    long t = ref_sar(a, 7) + (long)ref_shl((unsigned long)b, 7) + ref_sar(c, 15) +
             (long)ref_shl((unsigned long)d, 15) + ref_sar(e, 9) +
             (long)ref_shl((unsigned long)f, 11) + ref_sar(g, 13) +
             (long)ref_shl((unsigned long)h, 3) + ref_sar(i, 24) +
             (long)ref_shl((unsigned long)j, 20) + (long)ref_shr((unsigned long)k, 7) +
             (long)ref_shr((unsigned long)l, 12);
    return s == t && keep(a + b + c + d + e + f + g + h + i + j + k + l) == 12 * x + 78 ? 0 : 1;
}

/* a 16-bit value widened, then shifted (x * 128 of a table byte) */
static unsigned char tb[4] = { 0x10, 0xFF, 0x80, 0x01 };

int main(void)
{
    static const unsigned long edge[] = { 0, 1, 2, 0x7F, 0x80, 0xFF, 0x100, 0x7FFF, 0x8000,
                                          0xFFFF, 0x10000, 0x12345678, 0x80000000, 0x7FFFFFFF,
                                          0xFFFFFFFF, 0xFFFFFFFE, 0x80000001, 0xDEADBEEF,
                                          0x00FF00FF, 0xFF00FF00, 0x40000000, 0xC0000000 };
    unsigned i, k;
    unsigned long s = 99;
    for (i = 0; i < sizeof edge / sizeof edge[0] + 60; i++) {
        unsigned long x;
        if (i < sizeof edge / sizeof edge[0]) {
            x = edge[i];
        } else {
            s = s * 1103515245UL + 12345UL;
            x = s ^ (s << 13);
        }
        for (k = 0; k < 32; k++) {
            unsigned n = vc + k;
            unsigned long r1 = tshl[k](x), r2 = tshr[k](x);
            long r3 = tsar[k]((long)x);
            if (r1 != x << n || r1 != ref_shl(x, k))
                return 1;
            if (r2 != x >> n || r2 != ref_shr(x, k))
                return 2;
            if (r3 != (long)x >> n || r3 != ref_sar((long)x, k))
                return 3;
            if ((1UL << n) != ref_shl(1, k) || (1L << n) != (long)ref_shl(1, k))
                return 4;
        }
        if (inreg(x, (long)x) || spilled((long)x))
            return 5;
    }
    for (i = 0; i < 4; i++)
        if ((long)tb[i] * 128 != (long)tb[i] << 7 || ((unsigned long)tb[i] << 7) / 128 != tb[i])
            return 6;
    return 0;
}
