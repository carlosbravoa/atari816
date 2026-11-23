/* fbench.c - a small floating-point benchmark, for both compilers (tests/run.py's fbench):
 *
 *   mandel   one 64-point row of the Mandelbrot set (y = 0.3, x from -2 to 0.5, at most
 *            64 iterations a point): + - * and compares
 *   sincos   sin(x) and cos(x) for 200 values
 *   sqrt     sqrt(x) for 500 values
 *   expow    exp, log and pow for 100 values each
 *   conv     2000 conversions int -> float -> long, and a float division each
 *
 * Prints "NAME   N ms  check C" for each and "fbench done". The check is an integer made
 * from the results; only the times are compared. */
#include <stdio.h>
#include <math.h>
#include <horizon.h>

static unsigned long ms(void) { return hz_uptime(); }

static unsigned long mandel(void)
{
    unsigned long total = 0;
    int i, k;
    float y = 0.3f;
    for (i = 0; i < 64; ++i) {
        float x = -2.0f + 2.5f * (float)i / 64.0f;
        float zr = 0.0f, zi = 0.0f;
        for (k = 0; k < 64; ++k) {
            float r2 = zr * zr, i2 = zi * zi;
            if (r2 + i2 > 4.0f)
                break;
            zi = 2.0f * zr * zi + y;
            zr = r2 - i2 + x;
        }
        total += (unsigned long)k;
    }
    return total;
}

static unsigned long sincos_(void)
{
    float s = 0.0f;
    int i;
    for (i = 0; i < 200; ++i) {
        float x = (float)i * 0.05f - 5.0f;
        s += sin(x) * cos(x);
    }
    return (unsigned long)(long)(s * 1000.0f + 100000.0f);
}

static unsigned long sqrt_(void)
{
    float s = 0.0f;
    int i;
    for (i = 1; i <= 500; ++i)
        s += sqrt((float)i);
    return (unsigned long)s;
}

static unsigned long expow(void)
{
    float s = 0.0f;
    int i;
    for (i = 1; i <= 100; ++i) {
        float x = (float)i * 0.05f;
        s += exp(x) * 0.001f + log(x) + pow(x, 1.5f);
    }
    return (unsigned long)s;
}

static unsigned long conv(void)
{
    unsigned long s = 0;
    int i;
    for (i = -1000; i < 1000; ++i) {
        float f = (float)i / 3.0f;
        s += (unsigned long)(long)(f * 7.0f);
    }
    return s;
}

int main(void)
{
    unsigned long t, c;
    puts("fbench");
    t = ms(); c = mandel();  printf("%-8s %6lu ms  check %lu\n", "mandel", ms() - t, c);
    t = ms(); c = sincos_(); printf("%-8s %6lu ms  check %lu\n", "sincos", ms() - t, c);
    t = ms(); c = sqrt_();   printf("%-8s %6lu ms  check %lu\n", "sqrt", ms() - t, c);
    t = ms(); c = expow();   printf("%-8s %6lu ms  check %lu\n", "expow", ms() - t, c);
    t = ms(); c = conv();    printf("%-8s %6lu ms  check %lu\n", "conv", ms() - t, c);
    puts("fbench done");
    return 0;
}
