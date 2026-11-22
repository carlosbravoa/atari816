/* math.h - cc816 (Horizon C SDK). float, double and long double are one format (IEEE 754
 * single precision, 32 bits), so sin, sinf and sinl are the same function (the f and l
 * names are macros for the plain ones). Accuracy: sqrt, fabs, floor, ceil, trunc, round,
 * fmod, ldexp, frexp, modf exact; the others within a few units in the last place
 * (docs/c/reference.md). No errno: a domain error gives NaN, an overflow HUGE_VAL. */
#ifndef _MATH_H
#define _MATH_H
#define HUGE_VAL   (1.0 / 0.0)
#define HUGE_VALF  (1.0f / 0.0f)
#define HUGE_VALL  (1.0L / 0.0L)
#define INFINITY   (1.0f / 0.0f)
#define NAN        (-(0.0f / 0.0f))     /* the quiet NaN $7FC00000 */
#define M_E        2.7182818284590452354
#define M_LOG2E    1.4426950408889634074
#define M_LOG10E   0.43429448190325182765
#define M_LN2      0.69314718055994530942
#define M_LN10     2.30258509299404568402
#define M_PI       3.14159265358979323846
#define M_PI_2     1.57079632679489661923
#define M_PI_4     0.78539816339744830962
#define M_1_PI     0.31830988618379067154
#define M_2_PI     0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2    1.41421356237309504880
#define M_SQRT1_2  0.70710678118654752440
#define FP_NAN       0
#define FP_INFINITE  1
#define FP_ZERO      2
#define FP_SUBNORMAL 3
#define FP_NORMAL    4
#define MATH_ERRNO       1
#define MATH_ERREXCEPT   2
#define math_errhandling 0
typedef float float_t;
typedef double double_t;

int __fpclassify(double x);
int __signbit(double x);
#define fpclassify(x) __fpclassify(x)
#define signbit(x)    __signbit(x)
#define isnan(x)      (fpclassify(x) == FP_NAN)
#define isinf(x)      (fpclassify(x) == FP_INFINITE)
#define isfinite(x)   (fpclassify(x) >= FP_ZERO)
#define isnormal(x)   (fpclassify(x) == FP_NORMAL)
#define isunordered(a, b) (isnan(a) || isnan(b))
#define isgreater(a, b)      (!isunordered(a, b) && (a) > (b))
#define isgreaterequal(a, b) (!isunordered(a, b) && (a) >= (b))
#define isless(a, b)         (!isunordered(a, b) && (a) < (b))
#define islessequal(a, b)    (!isunordered(a, b) && (a) <= (b))
#define islessgreater(a, b)  (!isunordered(a, b) && ((a) < (b) || (a) > (b)))

double fabs(double x);
double floor(double x);
double ceil(double x);
double trunc(double x);
double round(double x);
double rint(double x);
double nearbyint(double x);
long lround(double x);
long lrint(double x);
double fmod(double x, double y);
double remainder(double x, double y);
double modf(double x, double *ip);
double frexp(double x, int *e);
double ldexp(double x, int e);
double scalbn(double x, int e);
int ilogb(double x);
double logb(double x);
double copysign(double x, double y);
double nextafter(double x, double y);
double fmin(double x, double y);
double fmax(double x, double y);
double fdim(double x, double y);
double fma(double x, double y, double z);
double sqrt(double x);
double cbrt(double x);
double hypot(double x, double y);
double sin(double x);
double cos(double x);
double tan(double x);
double asin(double x);
double acos(double x);
double atan(double x);
double atan2(double y, double x);
double sinh(double x);
double cosh(double x);
double tanh(double x);
double exp(double x);
double exp2(double x);
double expm1(double x);
double log(double x);
double log2(double x);
double log10(double x);
double log1p(double x);
double pow(double x, double y);

#define fabsf fabs
#define floorf floor
#define ceilf ceil
#define truncf trunc
#define roundf round
#define rintf rint
#define nearbyintf nearbyint
#define lroundf lround
#define lrintf lrint
#define fmodf fmod
#define remainderf remainder
#define modff(x, p) modf(x, (double *)(p))
#define frexpf frexp
#define ldexpf ldexp
#define scalbnf scalbn
#define ilogbf ilogb
#define logbf logb
#define copysignf copysign
#define nextafterf nextafter
#define fminf fmin
#define fmaxf fmax
#define fdimf fdim
#define fmaf fma
#define sqrtf sqrt
#define cbrtf cbrt
#define hypotf hypot
#define sinf sin
#define cosf cos
#define tanf tan
#define asinf asin
#define acosf acos
#define atanf atan
#define atan2f atan2
#define sinhf sinh
#define coshf cosh
#define tanhf tanh
#define expf exp
#define exp2f exp2
#define expm1f expm1
#define logf log
#define log2f log2
#define log10f log10
#define log1pf log1p
#define powf pow
#define fabsl fabs
#define floorl floor
#define ceill ceil
#define truncl trunc
#define roundl round
#define fmodl fmod
#define modfl(x, p) modf(x, (double *)(p))
#define frexpl frexp
#define ldexpl ldexp
#define copysignl copysign
#define sqrtl sqrt
#define sinl sin
#define cosl cos
#define tanl tan
#define asinl asin
#define acosl acos
#define atanl atan
#define atan2l atan2
#define sinhl sinh
#define coshl cosh
#define tanhl tanh
#define expl exp
#define logl log
#define log10l log10
#define powl pow
#endif
