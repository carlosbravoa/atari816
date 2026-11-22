/* longlong.c - long long and unsigned long long (64 bits): constants, every operator,
 * conversions to and from every type, globals with initialisers, structure members,
 * arrays, arguments and results (also through pointers and variadic), switch, printf's
 * and scanf's %lld family, strtoll, lldiv, the limits. The expected values come from
 * gcc on the host (64-bit long long there too). */
#include <inttypes.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef CHK
static int fails;
#define CHK(n, e, want) do { if ((unsigned long long)(e) != (unsigned long long)(want)) { \
    printf("check %d: %llx, want %llx\n", n, (unsigned long long)(e), (unsigned long long)(want)); \
    ++fails; } } while (0)
#endif

long long g1 = -1234567890123LL;
unsigned long long g2 = 0xFEDCBA9876543210ULL;
long long ga[4] = { 1, -2, 3000000000LL, LLONG_MIN };
struct rec { char tag; long long v; unsigned long long u; int k; } gr = { 'r', -7, 1ULL << 63, 5 };
static const int64_t kc = INT64_C(0x0123456789ABCDEF);

static long long add(long long a, long long b) { return a + b; }
static unsigned long long mulu(unsigned long long a, unsigned long long b) { return a * b; }
static long long (*fp)(long long, long long) = add;
static long long fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }
static struct rec mk(long long v) { struct rec r; r.tag = 'm'; r.v = v; r.u = (unsigned long long)v * 3; r.k = 1; return r; }

static long long vsum(int n, ...)
{
    va_list ap;
    long long s = 0;
    va_start(ap, n);
    while (n-- > 0) {
        s += va_arg(ap, long long);
        s ^= va_arg(ap, int);
    }
    va_end(ap);
    return s;
}

static int kind(long long v)
{
    switch (v) {
    case 0: return 1;
    case -1: return 2;
    case 0x100000000LL: return 3;
    case LLONG_MIN: return 4;
    case 77: return 5;
    default: return 6;
    }
}

int main(void)
{
    volatile long long a = 0x0123456789ABCDEFLL, b = -987654321098LL;
    volatile unsigned long long u = 0xFFFFFFFFFFFFFFFFULL, w = 1000000007ULL;
    long long x, y;
    unsigned long long z;
    int i;
    char buf[100];
    struct rec r;
    float f;
    double d;

    /* sizes, limits, constant types */
    CHK(1, sizeof(long long) + sizeof(unsigned long long) + sizeof(int64_t), 24);
    CHK(2, sizeof 4294967296, 8);
    CHK(3, sizeof 0xFFFFFFFFF, 8);
    CHK(4, LLONG_MAX, 0x7FFFFFFFFFFFFFFFULL);
    CHK(5, LLONG_MIN, 0x8000000000000000ULL);
    CHK(6, ULLONG_MAX, 0xFFFFFFFFFFFFFFFFULL);
    CHK(7, (uint64_t)INT64_MAX - (uint64_t)INT64_MIN == UINT64_MAX ? 0 : 1, 0);
    CHK(8, 18446744073709551615ULL / 3, 0x5555555555555555ULL);

    /* + - * / % */
    CHK(10, a + b, 0x123448194E2DA25ULL);
    CHK(11, a - b, 0x123464D7E74C1B9ULL);
    CHK(12, a * b, 0x907F6F539B3DA46AULL);
    CHK(13, a / b, 0xFFFFFFFFFFFEBBBEULL);
    CHK(14, a % b, 0x5019514BDBULL);
    CHK(15, b / 7, 0xFFFFFFDF262C6F76ULL);
    CHK(16, b % 7, 0xFFFFFFFFFFFFFFFCULL);
    CHK(17, u / w, 0x44B82F988ULL);
    CHK(18, u % w, 0x22B5DD47ULL);
    CHK(19, w * w * w, 0xC33F7D1BDD15FF57ULL);
    CHK(20, (long long)-9 / 2, -4);
    CHK(21, (long long)-9 % 2, -1);
    CHK(22, a / 1, a);
    CHK(23, u / 0x100000001ULL, 0xFFFFFFFFULL);
    /* shifts by constants and by variables */
    for (i = 0; i < 64; i += 7) {
        x = a << i;
        y = b >> i;
        z = u >> i;
        CHK(30, x, (unsigned long long)0x0123456789ABCDEFULL << i);
        CHK(31, y, (unsigned long long)(-987654321098LL >> i));
        CHK(32, z, 0xFFFFFFFFFFFFFFFFULL >> i);
    }
    CHK(33, a << 1, 0x02468ACF13579BDEULL);
    CHK(34, a << 16, 0x456789ABCDEF0000ULL);
    CHK(35, a << 32, 0x89ABCDEF00000000ULL);
    CHK(36, b >> 2, 0xFFFFFFC682CDC30DULL);
    CHK(37, b >> 48, 0xFFFFFFFFFFFFFFFFULL);
    CHK(38, (unsigned long long)b >> 3, 0x1FFFFFE34166E186ULL);
    CHK(39, a >> 20, 0x000000123456789AULL);
    /* logic and unary */
    CHK(40, a & b, 0x123450209230C26ULL);
    CHK(41, a | b, 0xFFFFFF7F8BBFCDFFULL);
    CHK(42, a ^ b, 0xFEDCBA7D829CC1D9ULL);
    CHK(43, ~a, 0xFEDCBA9876543210ULL);
    CHK(44, -a, 0xFEDCBA9876543211ULL);
    CHK(45, !a + !(a - a), 1);
    /* compares */
    CHK(50, (a < b) | (a > b) << 1 | (a <= b) << 2 | (a >= b) << 3 | (a == b) << 4 | (a != b) << 5, 0x2A);
    CHK(51, ((unsigned long long)a < (unsigned long long)b) | (u > w) << 1, 3);
    CHK(52, (b < 0) + (u > 0) + (LLONG_MIN < LLONG_MAX), 3);
    CHK(53, a == 0x0123456789ABCDEFLL && b != a ? 7 : 8, 7);
    /* ++ -- and compound assignment */
    x = 0xFFFFFFFFLL;
    x++;
    CHK(60, x, 0x100000000ULL);
    x--;
    --x;
    CHK(61, x, 0xFFFFFFFEULL);
    x = 5;
    x += a;
    x -= 7;
    x *= -3;
    x /= 5;
    x %= 1000000000007LL;
    x <<= 3;
    x >>= 1;
    x &= 0x7FFF0000FFFFLL;
    x |= 0x10;
    x ^= -1;
    CHK(62, x, 0xFFFF8127FFFF9047ULL);
    z = 10;
    z *= z;
    z *= z;
    z *= z;
    z *= z;
    CHK(63, z, 0x2386F26FC10000ULL);
    /* conversions */
    CHK(70, (int16_t)a, 0xFFFFFFFFFFFFCDEFULL);
    CHK(71, (uint16_t)a, 0xCDEF);
    CHK(72, (signed char)a, 0xFFFFFFFFFFFFFFEFULL);
    CHK(73, (unsigned char)a, 0xEF);
    CHK(74, (int32_t)a, 0xFFFFFFFF89ABCDEFULL);
    CHK(75, (uint32_t)a, 0x89ABCDEFULL);
    x = -5;
    CHK(76, x, 0xFFFFFFFFFFFFFFFBULL);
    i = -30000;
    x = (int16_t)i;
    CHK(77, x, -30000);
    x = (uint16_t)i;
    CHK(78, x, 35536);
    x = -100000L;
    CHK(79, x, -100000);
    x = 4000000000UL;
    CHK(80, x, 4000000000ULL);
    x = (signed char)-3;
    CHK(81, x, -3);
    x = (unsigned char)200;
    CHK(82, x, 200);
    CHK(83, (_Bool)(a & 0x100000000LL), 1);
    CHK(84, (_Bool)(a & 0x10000000000000LL), 0);
    /* float */
    f = (float)a;
    CHK(90, __builtin_fbits(f), 0x5B91A2B4);
    f = (float)b;
    CHK(91, __builtin_fbits(f), 0xD365F4C9ULL);
    f = (float)u;
    CHK(92, __builtin_fbits(f), 0x5F800000);
    f = (float)(unsigned long long)0x8000008000000001ULL;
    CHK(93, __builtin_fbits(f), 0x5F000001);
    f = (float)(long long)0x10000010000000LL;
    CHK(94, __builtin_fbits(f), 0x59800000);
    f = (float)(long long)0x10000030000000LL;
    CHK(95, __builtin_fbits(f), 0x59800002);
    f = -1.5e18f;
    CHK(96, (long long)f, 0xEB2EEE0000000000ULL);
    f = 1.5e19f;
    CHK(97, (unsigned long long)f, 0xD02AB50000000000ULL);
    d = 123456.75;
    CHK(98, (long long)d, 123456);
    CHK(99, (long long)-2.9f, -2);
    CHK(100, (long long)9.0e15f, 0x1FF973C0000000ULL);
    /* globals, arrays, structures */
    CHK(110, g1, -1234567890123LL);
    CHK(111, g2, 0xFEDCBA9876543210ULL);
    CHK(112, ga[0] + ga[1] + ga[2], 2999999999LL);
    CHK(113, ga[3], 0x8000000000000000ULL);
    CHK(114, gr.v + gr.k + gr.tag, -7 + 5 + 'r');
    CHK(115, gr.u, 0x8000000000000000ULL);
    CHK(116, kc, 0x0123456789ABCDEFULL);
    ga[1] = g1 * 2;
    gr.v -= ga[1];
    CHK(117, gr.v, 2469135780239LL);
    r = mk(-11);
    CHK(118, r.v + (long long)r.u + r.k, -11 + -33 + 1);
    /* calls */
    CHK(120, add(a, b), a + b);
    CHK(121, fp(1LL << 40, -1), 0xFFFFFFFFFFULL);
    CHK(122, mulu(u, u), 1);
    CHK(123, fact(20), 2432902008176640000LL);
    CHK(124, vsum(3, 1LL << 33, 5, -8LL, 1, 100LL, 0), ((((1LL << 33) ^ 5) - 8) ^ 1) + 100);
    CHK(125, kind(0) * 1000 + kind(-1) * 100 + kind(0x100000000LL) * 10 + kind(LLONG_MIN), 1234);
    CHK(126, kind(77) + kind(78), 11);
    /* printf, scanf, strtoll */
    sprintf(buf, "%lld %llu %llx %llX %llo", b, u, a, a, 511LL);
    CHK(130, strcmp(buf, "-987654321098 18446744073709551615 123456789abcdef 123456789ABCDEF 777"), 0);
    sprintf(buf, "[%20lld|%-6lld|%+lld|%020lld|%.15lld|%#llx|%#llo]", b, 5LL, 7LL, -3LL, 42LL, 255ULL, 8ULL);
    CHK(131, strcmp(buf, "[       -987654321098|5     |+7|-0000000000000000003|000000000000042|0xff|010]"), 0);
    sprintf(buf, "%" PRId64 " %" PRIu64 " %" PRIx64 " %jd %lld %d", INT64_MIN, UINT64_MAX, (uint64_t)255, (intmax_t)-1, 0LL, 9);
    CHK(132, strcmp(buf, "-9223372036854775808 18446744073709551615 ff -1 0 9"), 0);
    x = 0;
    z = 0;
    i = sscanf("-9223372036854775807 0x1fffffffff 12", "%lld %llx %d", &x, &z, &r.k);
    CHK(133, i, 3);
    CHK(134, x, -9223372036854775807LL);
    CHK(135, z, 0x1FFFFFFFFFULL);
    CHK(136, r.k, 12);
    i = sscanf("077 -12345678901", "%lli %" SCNd64, &x, &y);
    CHK(137, x + y, 077 - 12345678901LL);
    CHK(138, strtoll("  -123456789012345", 0, 10), -123456789012345LL);
    CHK(139, strtoull("0xFFFFFFFFFFFFFFFF", 0, 0), 0xFFFFFFFFFFFFFFFFULL);
    CHK(140, strtoll("99999999999999999999", 0, 10), LLONG_MAX);
    CHK(141, atoll("1234567890123"), 1234567890123LL);
    CHK(142, llabs(-5000000000LL), 5000000000LL);
    {
        lldiv_t q = lldiv(-100000000001LL, 7);
        CHK(143, q.quot, -14285714285LL);
        CHK(144, q.rem, -6);
    }
    if (!fails)
        printf("longlong: all checks pass\n");
    return fails;
}
