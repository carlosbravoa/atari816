/* ieee.c - cc816's floating point (IEEE 754 single precision: float = double = long
 * double, 32 bits) at the standard's edges: rounding ties, overflow to infinity, gradual
 * underflow, NaN compares, -0.0, conversions at the limits, printf's exact digits
 * (glibc's strings), strtod's exact rounding and ERANGE, math.h's special values. Prints
 * IEEE PASS or IEEE FAIL. (tests/fpu checks the same parts on tens of thousands of
 * values; this is the readable list.) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include <errno.h>

static unsigned checks, fails;
static void check(int ok, const char *what, double got)
{
    ++checks;
    if (!ok) {
        ++fails;
        printf("FAIL: %s (got %f)\n", what, got);
    }
}
static unsigned long B(float f)
{
    union { float f; unsigned long u; } v;
    v.f = f;
    return v.u;
}
static float F(unsigned long u)
{
    union { float f; unsigned long u; } v;
    v.u = u;
    return v.f;
}
static void same(const char *got, const char *want, const char *what)
{
    ++checks;
    if (strcmp(got, want)) {
        ++fails;
        printf("FAIL: %s: \"%s\", want \"%s\"\n", what, got, want);
    }
}

static void ieee(void)
{
    volatile float one = 1.0f, e24 = F(0x33800000UL) /* 2^-24 */, big = FLT_MAX;
    volatile float tiny = FLT_TRUE_MIN, fmin = FLT_MIN, zero = 0.0f, nz = -0.0f;
    volatile float nan = NAN, inf = INFINITY;
    volatile long l;
    char buf[80];
    char *end;
    /* rounding: to nearest, ties to even */
    check(one + e24 == one, "1 + 2^-24 is a tie: to even (1)", one + e24);
    check(B(one + 3 * e24) == 0x3F800002UL, "1 + 3*2^-24: a tie, to even (up)", 0);
    check(B(one + e24 * 1.5f) == 0x3F800001UL, "1 + 1.5*2^-24: above half: up", 0);
    check(B(one / 3.0f) == 0x3EAAAAABUL, "1/3 rounded", 0);
    check(B(16777216.0f + 1.0f) == 0x4B800000UL, "2^24 + 1: a tie, to even", 0);
    check(B(16777216.0f + 3.0f) == 0x4B800002UL, "2^24 + 3: a tie, to even (up)", 0);
    /* overflow to infinity, and the largest value kept */
    check(big * 2.0f == inf && -big * 2.0f == -inf, "FLT_MAX * 2 = inf", 0);
    check(big + big * e24 / 2.0f == big, "FLT_MAX + half an ulp: stays (a tie, even)", 0);
    check(big + big * e24 == inf, "FLT_MAX + an ulp: inf", 0);
    check(B(1e30f * 1e10f) == 0x7F800000UL, "1e30 * 1e10 = inf", 0);
    /* gradual underflow */
    check(B(fmin / 2.0f) == 0x00400000UL, "FLT_MIN / 2 is a denormal", 0);
    check(B(tiny / 2.0f) == 0, "the smallest denormal / 2: a tie, to even (0)", 0);
    check(B(tiny * 1.5f) == 2, "1.5 * the smallest denormal: a tie, to even (2)", 0);
    check(B(fmin - tiny) == 0x007FFFFFUL, "FLT_MIN - the smallest denormal", 0);
    check(tiny > 0.0f && tiny * 0.25f == 0.0f, "underflow to 0", 0);
    check(B(F(0x00800001UL) * 0.5f) == 0x00400000UL, "a halved odd normal rounds to even", 0);
    /* NaN: unordered; only != is true */
    check(!(nan == nan) && nan != nan && !(nan < one) && !(nan > one) && !(nan <= one) &&
          !(nan >= one) && !(one < nan) && one != nan, "NaN compares", 0);
    check(nan ? 1 : 0, "NaN is true in a condition", 0);
    check(isnan(zero / zero) && isnan(inf - inf) && isnan(zero * inf) && isnan(sqrt(-one)),
          "invalid operations give NaN", 0);
    check(isinf(one / zero) && one / nz == -inf, "1/0 = inf, 1/-0 = -inf", 0);
    /* -0.0 */
    check(nz == zero && signbit(nz) && !signbit(zero) && !(nz < zero), "-0 equals 0", 0);
    check(B(-zero) == 0x80000000UL && B(zero - zero) == 0 && B(nz - zero) == 0x80000000UL,
          "the signs of zero results", 0);
    check(nz ? 0 : 1, "-0.0 is false", 0);
    check(B(ceil(-0.5)) == 0x80000000UL && floor(-0.5) == -1.0f && B(trunc(-0.7)) == 0x80000000UL,
          "ceil(-0.5) = -0", 0);
    /* conversions at the limits (truncation toward zero) */
    l = (long)2147483520.0f;
    check(l == 2147483520L, "(long) of the largest float below 2^31", (double)l);
    l = (long)-2147483648.0f;
    check(l == -2147483647L - 1, "(long)-2^31", 0);
    check((unsigned long)4294967040.0f == 4294967040UL, "(unsigned long) below 2^32", 0);
    check((int)32767.9f == 32767 && (int)-32768.9f == -32768 && (int)-0.9f == 0,
          "(int) truncates", 0);
    check((unsigned)65535.5f == 65535u && (unsigned char)255.9f == 255 &&
          (signed char)-128.5f == -128, "(unsigned) and the char types", 0);
    check((float)16777217L == 16777216.0f && (float)16777219L == 16777220.0f,
          "(float) of a long rounds to even", 0);
    check((float)0xFFFFFFFFUL == 4294967296.0f && (float)(-2147483647L - 1) == -2147483648.0f,
          "(float) of the 32-bit limits", 0);
    check((float)-32768 == -32768.0f && (float)65535u == 65535.0f && (float)(signed char)-1 == -1.0f,
          "(float) of the 16- and 8-bit types", 0);
    check((_Bool)0.5f == 1 && (_Bool)nz == 0 && (_Bool)nan == 1, "(_Bool)", 0);
    /* printf: the exact decimal value, rounded with ties to even (as glibc) */
    sprintf(buf, "%.1f %.1f %.0f %.0f %.0f", 0.25, 0.35f, 0.5, 1.5, 2.5);
    same(buf, "0.2 0.3 0 2 2", "printf ties");
    sprintf(buf, "%.20f", 0.1f);
    same(buf, "0.10000000149011611938", "printf %.20f of 0.1f");
    sprintf(buf, "%e|%g|%g|%#.3g|%+08.2f|%-8.3e|", 0.0, 100000.0, 1e6, 1.0, -3.14159, 1234.5);
    same(buf, "0.000000e+00|100000|1e+06|1.00|-0003.14|1.234e+03|", "printf %e %g flags");
    sprintf(buf, "%f %F %e %g %5.1f %-6f| %a %A", inf, -inf, nan, -nan, inf, nan, 1.0, 0.75);
    same(buf, "inf -INF nan -nan   inf nan   | 0x1p+0 0X1.8P-1", "printf inf nan %a");
    sprintf(buf, "%g %g %g %.3e", FLT_MAX, FLT_MIN, FLT_TRUE_MIN, 1e-40f);
    same(buf, "3.40282e+38 1.17549e-38 1.4013e-45 1.000e-40", "printf limits");
    sprintf(buf, "%.0f", 16777216.0f * 1024.0f);
    same(buf, "17179869184", "printf %.0f of 2^34");
    /* strtod: exact rounding, its end, ERANGE */
    check(B(strtod("0.1", &end)) == 0x3DCCCCCDUL && *end == 0, "strtod 0.1", 0);
    check(B(strtod("1.00000005960464477539062", 0)) == 0x3F800000UL,
          "strtod: just below the halfway point to 1 + ulp: down", 0);
    check(B(strtod("1.000000059604644775390625001", 0)) == 0x3F800001UL,
          "strtod: just above the halfway point: up", 0);
    check(B(strtod("0x1.fffffep127", 0)) == 0x7F7FFFFFUL && B(strtod("0x1p-149", 0)) == 1,
          "strtod hexadecimal", 0);
    errno = 0;
    check(isinf(strtod("3.4028236e38", 0)) && errno == ERANGE, "strtod overflow: ERANGE", 0);
    errno = 0;
    check(strtod("1e-46", 0) == 0.0f && errno == ERANGE, "strtod underflow: ERANGE", 0);
    check(strtod("1e+", &end) == 1.0f && *end == 'e', "strtod stops before a bare e", 0);
    check(isnan(strtod("nan", 0)) && strtod("-Infinity", &end) == -inf && *end == 0,
          "strtod nan, infinity", 0);
    check(strtof("12.5", 0) == 12.5f && strtold("-2", 0) == -2.0, "strtof, strtold", 0);
    /* math.h special values (C99 annex F) */
    check(log(zero) == -inf && isnan(log(-one)) && exp(-inf) == 0.0f && exp(inf) == inf,
          "log and exp edges", 0);
    check(pow(zero, -one) == inf && pow(-8.0, 1.0 / 3.0) != pow(-8.0, 1.0 / 3.0) &&
          pow(-2.0, 3.0) == -8.0f && pow(nan, 0.0) == 1.0f && pow(1.0, nan) == 1.0f,
          "pow edges", 0);
    check(atan2(zero, -one) == F(0x40490FDBUL) && atan2(nz, -one) == -F(0x40490FDBUL) &&
          atan2(one, zero) == F(0x3FC90FDBUL), "atan2 edges", 0);
    check(fmod(5.5, 2.0) == 1.5f && B(fmod(-6.0, 3.0)) == 0x80000000UL &&
          isnan(fmod(one, zero)), "fmod edges", 0);
    check(sqrt(2.0f) == F(0x3FB504F3UL) && sqrt(fmin) == F(0x20000000UL) &&
          sqrt(tiny) == F(0x1A3504F3UL), "sqrt rounded exactly (also denormals)", 0);
    check(B(sin(1e30f)) == 0xBF4A89B0UL, "sin of a huge argument (rounded as glibc)",
          sin(1e30f));
    check(ldexp(1.0, -149) == tiny && ldexp(1.0, 128) == inf, "ldexp", 0);
    {
        int e;
        check(frexp(48.0, &e) == 0.75f && e == 6, "frexp", 0);
        check(frexp(tiny, &e) == 0.5f && e == -148, "frexp of a denormal", 0);
    }
    check(rint(2.5) == 2.0f && rint(-3.5) == -4.0f && round(2.5) == 3.0f && round(-2.5) == -3.0f,
          "rint (ties to even), round (away)", 0);
    check(FLT_EPSILON == F(0x34000000UL) && DBL_MAX == FLT_MAX && sizeof(long double) == 4,
          "float.h", 0);
}

int main(void)
{
    ieee();
    printf("ieee: %u checks, %u failures\n", checks, fails);
    printf(fails ? "IEEE FAIL\n" : "IEEE PASS\n");
    return 0;
}
