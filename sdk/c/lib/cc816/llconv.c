/* llconv.c - the conversions between long long and float for cc816 (the compiler calls
 * them: (float)ll, (long long)f and their unsigned forms). They round as the 32-bit ones
 * do, and give what x86 gives where they can: to nearest, ties to even, and toward zero
 * for float -> integer. Out of range (undefined in C): __ftoll gives the smallest long
 * long (as for NaN), __ftoull the largest unsigned long long for 2^64 and above (and
 * NaN); a negative value goes through __ftoll. The compiler folds constants the same way
 * (cc816/fp.py). */

float __ulltof(unsigned long long u)
{
    unsigned long hi = (unsigned long)(u >> 32), t, lo;
    unsigned shift;
    if (!hi)
        return (float)(unsigned long)u;
    /* the top 32 bits, the bits below them OR'ed into bit 0 (a sticky bit: they are far
     * below the 24 bits that remain, so the rounding of the 32-bit conversion is right) */
    shift = 32;                         /* the bits of hi: 1 to 32 */
    if (hi < 0x10000UL) {
        hi <<= 16;
        shift -= 16;
    }
    if (hi < 0x1000000UL) {
        hi <<= 8;
        shift -= 8;
    }
    if (hi < 0x10000000UL) {
        hi <<= 4;
        shift -= 4;
    }
    if (hi < 0x40000000UL) {
        hi <<= 2;
        shift -= 2;
    }
    if (hi < 0x80000000UL)
        --shift;
    t = (unsigned long)(u >> shift);
    lo = (unsigned long)u;
    if (shift < 32)
        lo <<= 32 - shift;
    if (lo)
        t |= 1;
    /* times 2^shift: exact, the exponent field raised (the value stays normal) */
    return __builtin_bitsf(__builtin_fbits((float)t) + ((unsigned long)shift << 23));
}

float __lltof(long long x)
{
    if (x < 0)
        return -__ulltof(0ULL - (unsigned long long)x);
    return __ulltof((unsigned long long)x);
}

long long __ftoll(float f)
{
    unsigned long b = __builtin_fbits(f);
    unsigned e = (unsigned)(b >> 23) & 0xFF;
    unsigned long long m;
    if (e < 127 + 31)
        return (long)f;                         /* |f| < 2^31 (NaN: e is 255) */
    if (e >= 127 + 63)
        return (long long)0x8000000000000000ULL;   /* out of range, infinity, NaN */
    m = (unsigned long long)((b & 0x7FFFFFUL) | 0x800000UL) << (e - 127 - 23);
    return b & 0x80000000UL ? -(long long)m : (long long)m;
}

unsigned long long __ftoull(float f)
{
    unsigned long b = __builtin_fbits(f);
    unsigned e = (unsigned)(b >> 23) & 0xFF;
    if (b & 0x80000000UL)
        return (unsigned long long)__ftoll(f);
    if (e < 127 + 32)
        return (unsigned long)f;                /* below 2^32 */
    if (e >= 127 + 64)
        return 0xFFFFFFFFFFFFFFFFULL;           /* 2^64 and above, infinity, NaN */
    return (unsigned long long)((b & 0x7FFFFFUL) | 0x800000UL) << (e - 127 - 23);
}
