/* llbench.c - cc816's long long and setjmp: the time of one operation, in microseconds
 * (volatile operands, the empty loop taken out), and a few checks of the results.
 * tests/run.py's "ll" test runs it. */
#include <horizon.h>
#include <setjmp.h>
#include <stdio.h>

#define N 2000

static volatile long long a = 0x0123456789ABCDEFLL, b = 12345678901LL, r;
static volatile int k = 13;
static volatile float f = 1.5e12f, fr;
static jmp_buf jb;
static unsigned long t0;
static unsigned long base;
static char buf[40];

static void start(void) { t0 = hz_uptime(); }

static void stop(const char *what)
{
    unsigned long ms = hz_uptime() - t0;
    unsigned long us = ms * 1000 / N;
    printf("%-10s %lu us\n", what, us > base ? us - base : 0);
}

static void jump(void) { longjmp(jb, 1); }

int main(void)
{
    int i;
    start();
    for (i = 0; i < N; i++)
        r = a;
    base = (hz_uptime() - t0) * 1000 / N;
    start();
    for (i = 0; i < N; i++)
        r = a + b;
    stop("add");
    start();
    for (i = 0; i < N; i++)
        r = a - b;
    stop("sub");
    start();
    for (i = 0; i < N; i++)
        r = a < b;
    stop("compare");
    start();
    for (i = 0; i < N; i++)
        r = a * b;
    stop("mul");
    start();
    for (i = 0; i < N; i++)
        r = a / b;
    stop("div");
    start();
    for (i = 0; i < N; i++)
        r = a / 10;
    stop("div10");
    start();
    for (i = 0; i < N; i++)
        r = a % b;
    stop("mod");
    start();
    for (i = 0; i < N; i++)
        r = a << k;
    stop("shift");
    start();
    for (i = 0; i < N; i++)
        fr = (float)a;
    stop("tofloat");
    start();
    for (i = 0; i < N; i++)
        r = (long long)f;
    stop("fromfloat");
    start();
    for (i = 0; i < N / 10; i++)
        sprintf(buf, "%lld", a);
    {
        unsigned long ms = hz_uptime() - t0;
        printf("%-10s %lu us\n", "printf", ms * 10000 / N);
    }
    start();
    for (i = 0; i < N; i++)
        if (setjmp(jb) == 0)
            jump();
    stop("setjmp");
    sprintf(buf, "%lld", a * b / 7 % 1000000007LL);
    printf("check %s %lld %lld\n", buf, a / b, (long long)f);
    printf("llbench done\n");
    return 0;
}
