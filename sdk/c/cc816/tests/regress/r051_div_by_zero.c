/* r051_div_by_zero.c - a division by 0 does not trap, and gives the same answers in every
 * width (16, 32 and 64 bits; the Prince port asked whether the 64-bit one differed: it
 * does not): unsigned, the quotient all ones and the remainder the dividend; signed, the
 * quotient -1 (1 for a negative dividend: the unsigned all ones with the sign rule) and the
 * remainder the dividend. LEVELS: 0 1 2 */
static int zi(int x) { return x; }
static long zl(long x) { return x; }
static long long zll(long long x) { return x; }

int main(void)
{
    int i = zi(1234), i0 = zi(0);
    unsigned u = (unsigned)zi(40000u), u0 = (unsigned)zi(0);
    long l = zl(-123456L), l0 = zl(0);
    unsigned long ul = (unsigned long)zl(3000000000L), ul0 = (unsigned long)zl(0);
    long long ll = zll(-1234567890123LL), ll0 = zll(0);
    unsigned long long ull = (unsigned long long)zll(-5LL), ull0 = (unsigned long long)zll(0);
    if (i / i0 != -1 || i % i0 != 1234 || zi(-7) / i0 != 1 || zi(-7) % i0 != -7)
        return 1;
    if (u / u0 != 0xFFFFu || u % u0 != 40000u)
        return 2;
    if (l / l0 != 1L || l % l0 != -123456L || zl(77) / l0 != -1L || zl(77) % l0 != 77)
        return 3;
    if (ul / ul0 != 0xFFFFFFFFul || ul % ul0 != 3000000000ul)
        return 4;
    if (ll / ll0 != 1LL || ll % ll0 != -1234567890123LL)
        return 5;
    if (zll(99) / ll0 != -1LL || zll(99) % ll0 != 99)
        return 6;
    if (ull / ull0 != 0xFFFFFFFFFFFFFFFFull || ull % ull0 != (unsigned long long)-5LL)
        return 7;
    if (zll(0x100000000LL) / ll0 != -1LL || zll(0x100000000LL) % ll0 != 0x100000000LL)
        return 8;
    return 0;
}
