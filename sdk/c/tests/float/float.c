/* float.c - floating point, for both compilers: arithmetic, conversions, math.h, printf
 * %f %e %g, strtod, sscanf and scanf %f, atof of an argument (cc816's IEEE 754 edges:
 * ieee.c). vbcc's float (MS BASIC's format, about 7 digits) rounds differently in the last
 * digit, so the checks allow for it. Prints FLOAT PASS or FLOAT FAIL.
 *
 *   float 2.5 -1e3          (the arguments; the keyboard types 0.125 and -7.5e-2)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdarg.h>

static unsigned checks, fails;
static void check(int ok, const char *what, double got)
{
    ++checks;
    if (!ok) {
        ++fails;
        printf("FAIL: %s (got %f)\n", what, got);
    }
}
static int near_(double a, double b) { double d = a - b; if (d < 0) d = -d; return d <= 1e-4 * (b < 0 ? -b : b) + 1e-6; }

struct pt { float x, y; int tag; };
static struct pt pts[2] = { { 1.5f, -2.0f, 7 }, { 0.25f, 100.0f, 8 } };
static double table[4] = { 1.0, 0.5, 0.25, 0.125 };
static float gsum(int n, ...)
{
    va_list ap;
    double s = 0;
    va_start(ap, n);
    while (n-- > 0)
        s += va_arg(ap, double);
    va_end(ap);
    return (float)s;
}
static double twice(double x) { return 2 * x; }
static double (*fn)(double) = twice;
static struct pt mid(struct pt a, struct pt b)
{
    struct pt r;
    r.x = (a.x + b.x) / 2;
    r.y = (a.y + b.y) / 2;
    r.tag = a.tag + b.tag;
    return r;
}


int main(int argc, char **argv)
{
    volatile double a = 1.5, b = -2.25, c = 10.0;
    char buf[64];
    double r;
    float f;
    int i;
    long n;
    struct pt m;
    printf("sizeof(float) %u, sizeof(double) %u\n", (unsigned)sizeof(float), (unsigned)sizeof(double));
    r = a + b; check(near_(r, -0.75), "add", r);
    r = a - b; check(near_(r, 3.75), "sub", r);
    r = a * b; check(near_(r, -3.375), "mul", r);
    r = c / a; check(near_(r, 6.666667), "div", r);
    r = sqrt(c); check(near_(r, 3.162278), "sqrt", r);
    r = sin(a); check(near_(r, 0.997495), "sin", r);
    r = cos(a); check(near_(r, 0.0707372), "cos", r);
    r = tan(a); check(near_(r, 14.10142), "tan", r);
    r = atan(b); check(near_(r, -1.152572), "atan", r);
    r = atan2(b, a); check(near_(r, -0.9827937), "atan2", r);
    r = exp(a); check(near_(r, 4.481689), "exp", r);
    r = log(c); check(near_(r, 2.302585), "log", r);
    r = log10(c * c * c); check(near_(r, 3.0), "log10", r);
    r = pow(a, 3.0); check(near_(r, 3.375), "pow", r);
    r = floor(b); check(near_(r, -3.0), "floor", r);
    r = ceil(b); check(near_(r, -2.0), "ceil", r);
    r = fabs(b); check(near_(r, 2.25), "fabs", r);
    r = fmod(c, 3.0); check(near_(r, 1.0), "fmod", r);
    r = atof("12.5e1"); check(near_(r, 125.0), "atof", r);
    r = (double)(long)(c * 1000.0); check(near_(r, 10000.0), "to long and back", r);
    n = (long)(b * 4.0 - 0.5); check(n == -9, "(long) of a negative", (double)n);
    i = (int)(a * 3.0); check(i == 4, "(int) truncates", i);
    f = 1.0f;
    for (i = 0; i < 10; ++i)
        f *= 1.5f;
    check(near_(f, 57.66504), "float loop", f);
    f = 0.0f;
    f += 2; f -= 0.5; f *= 4; f /= 3;
    check(near_(f, 2.0), "compound assignment", f);
    f = 1.0f;
    f++; ++f; f--;
    check(near_(f, 2.0), "++ and --", f);
    check(a > b && b < a && a != b && a >= 1.5 && b <= -2.25 && !(a == b), "compares", 0);
    check(near_(pts[1].y + pts[0].x, 101.5) && pts[0].tag == 7 && near_(table[3], 0.125),
          "initialised globals", 0);
    m = mid(pts[0], pts[1]);
    check(near_(m.x, 0.875) && near_(m.y, 49.0) && m.tag == 15, "structures by value", m.x);
    check(near_(gsum(3, 1.0, 2.5, (double)f), 5.5), "variadic doubles", 0);
    check(near_(fn(4.25), 8.5), "a function pointer", 0);
    check(near_(i ? a : 2, 1.5) && near_(!i ? 1 : b, -2.25), "?: of float and int", 0);
    sprintf(buf, "%.3f %.2f %f", 3.14159, -2.25, 1.0 / 3.0);
    printf("printf: %s\n", buf);
    check(!strcmp(buf, "3.142 -2.25 0.333333"), "printf %f", 0);
    sprintf(buf, "%e %g", 12345.678, 0.0001);
    printf("printf %%e %%g: %s\n", buf);
    check(!strcmp(buf, "1.234568e+04 0.0001") || !strcmp(buf, "1.234567e+04 0.0001"),
          "printf %e %g", 0);                   /* (vbcc: ...67) */
    sprintf(buf, "%8.2f|%-8.1f|%+.0f", 2.5, -0.25, 7.0);
    check(!strcmp(buf, "    2.50|-0.2    |+7") || !strcmp(buf, "    2.50|-0.3    |+7"),
          "printf width and flags", 0);
    {
        float g; double h; int k = sscanf("2.5 -1e-3 x", "%f %lf", &g, &h);
        check(k == 2 && near_(g, 2.5) && near_(h, -0.001), "sscanf %f %lf", g);
    }
    check(argc == 3 && near_(atof(argv[1]), 2.5) && near_(strtod(argv[2], 0), -1000.0),
          "atof, strtod of the arguments", argc);
    {
        float g = 0; double h = 0;
        int k = scanf("%f", &g);
        int k2 = scanf("%lf", &h);
        check(k == 1 && k2 == 1 && near_(g, 0.125) && near_(h, -0.075),
              "scanf %f from the keyboard", g);
    }
    printf("float: %u checks, %u failures\n", checks, fails);
    printf(fails ? "FLOAT FAIL\n" : "FLOAT PASS\n");
    return 0;
}
