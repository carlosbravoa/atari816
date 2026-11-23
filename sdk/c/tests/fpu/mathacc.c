/* mathacc.c - the accuracy of cc816's math library (lib/math_*.c), measured on the host:
 * mathhost.sh builds those files for the host in single precision (double = float, as
 * cc816) with their names prefixed t_, and this program compares each function with
 * glibc's double-precision one rounded to float (the correctly rounded result, nearly
 * always), over N random arguments of each kind. Prints the largest error in ulps and
 * where. The same C on SSE gives cc816's results bit for bit (the soft float is exact
 * IEEE single), so this measures the target's accuracy too.
 *
 *   mathacc [N [TABLE]]     N arguments a function (default 200000); TABLE: also write
 *                           the host's results for 500 of them a function, for
 *                           tests/fpu/fptest.c to check on the target bit for bit */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

float t_sin(float), t_cos(float), t_tan(float), t_atan(float), t_asin(float), t_acos(float);
float t_exp(float), t_exp2(float), t_expm1(float), t_log(float), t_log10(float), t_log2(float);
float t_log1p(float), t_sqrt(float), t_cbrt(float), t_sinh(float), t_cosh(float), t_tanh(float);
float t_floor(float), t_ceil(float), t_trunc(float), t_round(float), t_rint(float);
float t_fabs(float);
float t_atan2(float, float), t_pow(float, float), t_fmod(float, float), t_hypot(float, float);
float t_remainder(float, float), t_ldexp(float, int), t_frexp(float, int *);
float t_modf(float, float *);

static uint32_t B(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static float F(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static int64_t key(float f)
{
    uint32_t u = B(f);
    return u >> 31 ? -(int64_t)(u & 0x7FFFFFFF) : (int64_t)u;
}
static double ulps(float got, float want)
{
    if (isnan(got) && isnan(want)) return 0;
    if (isnan(got) || isnan(want)) return 1e9;
    if (isinf(want) || isinf(got)) return got == want ? 0 : 1e9;
    return (double)llabs(key(got) - key(want));
}

static uint64_t rs = 88172645463325252ULL;
static uint32_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return (uint32_t)rs; }
static double uni(double a, double b) { return a + (b - a) * (rnd() / 4294967296.0); }
static float any(void) { return F(rnd()); }
static float logu(double lo, double hi) { return (float)exp2(uni(lo, hi)); }
static float sgn(float x) { return rnd() & 1 ? -x : x; }

typedef float (*f1)(float);
typedef double (*d1)(double);
typedef float (*f2)(float, float);
typedef double (*d2)(double, double);

static double worst_all;
static int bad;
static FILE *tab;
static int tabop = 100;

static void rec(int op, float x, float y, float r)
{
    uint32_t v[3] = {B(x), B(y), B(r)};
    unsigned char b[16];
    b[0] = (unsigned char)op; b[1] = (unsigned char)(op >> 8); b[2] = b[3] = 0;
    for (int i = 0; i < 3; ++i)
        for (int k = 0; k < 4; ++k)
            b[4 + 4 * i + k] = (unsigned char)(v[i] >> (8 * k));
    fwrite(b, 1, 16, tab);
}

static void report(const char *name, double worst, float wx, float wy, long n, double limit)
{
    printf("%-9s %8ld args, worst %6.0f ulp at %.9g %.9g%s\n", name, n, worst, wx, wy,
           worst > limit ? "  ** OVER THE LIMIT" : "");
    if (worst > limit)
        bad = 1;
}

static const uint32_t spec[] = {0, 0x80000000, 0x7F800000, 0xFF800000, 0x7FC00000,
    0x3F800000, 0xBF800000, 0x3F000000, 0xBF000000, 0x40000000, 0xC0000000, 0x00800000,
    0x00000001, 0x80000001, 0x7F7FFFFF, 0xFF7FFFFF, 0x40400000, 0xC0400000, 0x3FC90FDB,
    0x40490FDB, 0x42B17218, 0xC2CFF1B5, 0x3F800001, 0x3F7FFFFF, 0x4B000001, 0xCB000001};
#define NSPEC (sizeof spec / sizeof spec[0])

static void t1(const char *name, f1 f, d1 d, float (*gen)(void), long n, double limit)
{
    double worst = 0;
    float wx = 0;
    for (unsigned i = 0; i < NSPEC; ++i) {
        float x = F(spec[i]);
        double u = ulps(f(x), (float)d(x));
        if (u > worst) { worst = u; wx = x; }
    }
    for (long i = 0; i < n; ++i) {
        float x = gen();
        double u = ulps(f(x), (float)d(x));
        if (u > worst) { worst = u; wx = x; }
        if (tab && (i < 500 || (i < 1000 && n < 0)))
            rec(tabop, x, 0, f(x));
    }
    if (tab) {
        for (unsigned i = 0; i < NSPEC; ++i)
            rec(tabop, F(spec[i]), 0, f(F(spec[i])));
        ++tabop;
    }
    report(name, worst, wx, 0, n, limit);
}

static void t2(const char *name, f2 f, d2 d, void (*gen)(float *, float *), long n, double limit)
{
    double worst = 0;
    float wx = 0, wy = 0;
    for (unsigned i = 0; i < NSPEC; ++i)
        for (unsigned j = 0; j < NSPEC; ++j) {
            float x = F(spec[i]), y = F(spec[j]);
            double u = ulps(f(x, y), (float)d(x, y));
            if (u > worst) { worst = u; wx = x; wy = y; }
        }
    for (long i = 0; i < n; ++i) {
        float x, y;
        gen(&x, &y);
        double u = ulps(f(x, y), (float)d(x, y));
        if (u > worst) { worst = u; wx = x; wy = y; }
        if (tab && i < 500)
            rec(tabop, x, y, f(x, y));
    }
    if (tab) {
        for (unsigned i = 0; i < NSPEC; i += 2)
            for (unsigned j = 1; j < NSPEC; j += 3)
                rec(tabop, F(spec[i]), F(spec[j]), f(F(spec[i]), F(spec[j])));
        ++tabop;
    }
    report(name, worst, wx, wy, n, limit);
}

static float g_trig(void)
{
    switch (rnd() % 6) {
    case 0: return (float)uni(-10, 10);
    case 1: return sgn(logu(-30, 8));
    case 2: return sgn(logu(7, 128));
    case 3: { long k = (long)(rnd() % 200000) - 100000; float x = (float)(k * M_PI_2);
              return F(B(x) + (int32_t)(rnd() % 5) - 2); }
    case 4: return any();
    default: return (float)uni(-210, 210);
    }
}
static float g_exp(void) { return rnd() & 3 ? (float)uni(-104, 89) : sgn(logu(-30, 7)); }
static float g_exp2(void) { return rnd() & 3 ? (float)uni(-151, 129) : sgn(logu(-30, 8)); }
static float g_pos(void) { return rnd() & 3 ? F(rnd() & 0x7FFFFFFF) : (float)uni(0.5, 2); }
static float g_any(void) { return rnd() & 1 ? any() : (float)uni(-20, 20); }
static float g_unit(void) { return rnd() & 1 ? (float)uni(-1, 1) : sgn(logu(-30, 0)); }
static float g_hyp(void) { return rnd() & 1 ? (float)uni(-92, 92) : sgn(logu(-30, 3)); }
static float g_m1(void) { return rnd() & 1 ? (float)uni(-1, 3) : sgn(logu(-30, 4)); }
static float g_round(void) { return rnd() & 1 ? any() : (float)(uni(-1e4, 1e4) * (rnd() & 1 ? 1 : 0.001)); }

static void g_pow(float *x, float *y)
{
    switch (rnd() % 6) {
    case 0: *x = logu(-10, 10); *y = (float)uni(-30, 30); break;
    case 1: *x = (float)uni(0, 3); *y = (float)uni(-60, 60); break;
    case 2: *x = sgn((float)(rnd() % 20)); *y = (float)((int)(rnd() % 40) - 20); break;
    case 3: *x = F(0x3F800000 + (int32_t)(rnd() % 2000) - 1000); *y = sgn(logu(10, 30)); break;
    case 4: *x = logu(-149, 127); *y = (float)uni(-2, 2); break;
    default: *x = any(); *y = any(); break;
    }
}
static void g_atan2(float *x, float *y) { *x = g_any(); *y = g_any(); }
static void g_fmod(float *x, float *y)
{
    *x = rnd() & 1 ? any() : (float)uni(-1e6, 1e6);
    *y = rnd() & 1 ? any() : (float)uni(-100, 100);
}
static void g_hypot(float *x, float *y) { *x = any(); *y = rnd() & 1 ? any() : *x * (float)uni(-2, 2); }

int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 200000;
    if (argc > 2 && !(tab = fopen(argv[2], "wb"))) {
        perror(argv[2]);
        return 2;
    }
    t1("sqrt", t_sqrt, sqrt, g_pos, n, 0);
    t1("fabs", t_fabs, fabs, g_any, n, 0);
    t1("floor", t_floor, floor, g_round, n, 0);
    t1("ceil", t_ceil, ceil, g_round, n, 0);
    t1("trunc", t_trunc, trunc, g_round, n, 0);
    t1("round", t_round, round, g_round, n, 0);
    t1("rint", t_rint, rint, g_round, n, 0);
    t2("fmod", t_fmod, fmod, g_fmod, n, 0);
    t2("remainder", t_remainder, remainder, g_fmod, n, 0);
    t1("sin", t_sin, sin, g_trig, n, 2);
    t1("cos", t_cos, cos, g_trig, n, 2);
    t1("tan", t_tan, tan, g_trig, n, 3);
    t1("atan", t_atan, atan, g_any, n, 2);
    t2("atan2", t_atan2, atan2, g_atan2, n, 3);
    t1("asin", t_asin, asin, g_unit, n, 4);
    t1("acos", t_acos, acos, g_unit, n, 4);
    t1("exp", t_exp, exp, g_exp, n, 2);
    t1("exp2", t_exp2, exp2, g_exp2, n, 2);
    t1("expm1", t_expm1, expm1, g_m1, n, 4);
    t1("log", t_log, log, g_pos, n, 2);
    t1("log10", t_log10, log10, g_pos, n, 2);
    t1("log2", t_log2, log2, g_pos, n, 2);
    t1("log1p", t_log1p, log1p, g_m1, n, 4);
    t2("pow", t_pow, pow, g_pow, n, 3);
    t1("cbrt", t_cbrt, cbrt, g_any, n, 2);
    t2("hypot", t_hypot, hypot, g_hypot, n, 3);
    t1("sinh", t_sinh, sinh, g_hyp, n, 4);
    t1("cosh", t_cosh, cosh, g_hyp, n, 4);
    t1("tanh", t_tanh, tanh, g_hyp, n, 4);
    if (tab) {
        static const unsigned char end[16];
        fwrite(end, 1, 16, tab);
        fclose(tab);
    }
    printf(bad ? "MATHACC FAIL\n" : "MATHACC PASS\n");
    return bad;
}
