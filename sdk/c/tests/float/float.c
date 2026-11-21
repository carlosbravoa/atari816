/* float.c - floating point (hcc --float: vbcc's MS BASIC-derived 32-bit float, libms4).
 * float and double are both 32 bits (about 7 digits). Prints FLOAT PASS or FLOAT FAIL. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

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

int main(void)
{
    volatile double a = 1.5, b = -2.25, c = 10.0;
    char buf[64];
    double r;
    printf("sizeof(float) %u, sizeof(double) %u\n", (unsigned)sizeof(float), (unsigned)sizeof(double));
    r = a + b; check(near_(r, -0.75), "add", r);
    r = a - b; check(near_(r, 3.75), "sub", r);
    r = a * b; check(near_(r, -3.375), "mul", r);
    r = c / a; check(near_(r, 6.666667), "div", r);
    r = sqrt(c); check(near_(r, 3.162278), "sqrt", r);
    r = sin(a); check(near_(r, 0.997495), "sin", r);
    r = cos(a); check(near_(r, 0.0707372), "cos", r);
    r = exp(a); check(near_(r, 4.481689), "exp", r);
    r = log(c); check(near_(r, 2.302585), "log", r);
    r = pow(a, 3.0); check(near_(r, 3.375), "pow", r);
    r = floor(b); check(near_(r, -3.0), "floor", r);
    r = atof("12.5e1"); check(near_(r, 125.0), "atof", r);
    r = (double)(long)(c * 1000.0); check(near_(r, 10000.0), "to long and back", r);
    sprintf(buf, "%.3f %.2f %f", 3.14159, -2.25, 1.0 / 3.0);
    printf("printf: %s\n", buf);
    check(!strcmp(buf, "3.142 -2.25 0.333333"), "printf %f", 0);
    sprintf(buf, "%e %g", 12345.678, 0.0001);
    printf("printf %%e %%g: %s\n", buf);
    {
        float f; int n = sscanf("2.5", "%f", &f);
        check(n == 1 && near_(f, 2.5), "sscanf %f", f);
    }
    printf("float: %u checks, %u failures\n", checks, fails);
    printf(fails ? "FLOAT FAIL\n" : "FLOAT PASS\n");
    return 0;
}
