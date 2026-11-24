/* h16test.c - host16.py's test: the same program gives the same answers with cc816 on the
 * Atari816 and with the PC's compiler through host16.py (the types the Atari816's). Prints
 * one line per check that fails, then "host16: N failures". */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "h16types.h"

static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)

static int sum(int n, ...)
{
    va_list ap;
    int s = 0;
    va_start(ap, n);
    while (n--)
        s += va_arg(ap, int);
    va_end(ap);
    return s;
}

static int cmp(const void *a, const void *b)    /* host16: native */
{
    return *(const int *)a - *(const int *)b;
}

static unsigned QUAD mul(unsigned QUAD a, unsigned WORD b)
{
    return a * b;
}

int main(int argc, char **argv)
{
    int i = 32767;
    unsigned u = 65535u;
    long l = 100000L;
    unsigned QUAD q = 0xFFFFFFFFul;
    WORD w = -1;
    char c = (char)200;
    int a[4] = { 30, -5, 12, 0 };
    double d = 1.0 / 3.0;
    (void)argv;
    CHECK(sizeof(int) == 2);
    CHECK(sizeof(unsigned) == 2);
    CHECK(sizeof(long) == 4);
    CHECK(sizeof(unsigned QUAD) == 4);
    CHECK(sizeof(u32) == 4);
    CHECK(sizeof(u16) == 2);
    CHECK(sizeof(WORD) == 2);
    CHECK(sizeof(long long) == 8);
    CHECK(sizeof(struct rec) == 7);
    CHECK(sizeof(double) == 4);
    CHECK(sizeof(5L) == 4);
    i++;
    CHECK(i == -32768);
    u++;
    CHECK(u == 0);
    CHECK(l * 3 == 300000L);
    q++;
    CHECK(q == 0);
    CHECK(w == -1);
    CHECK(c > 0);                       /* plain char is unsigned */
    CHECK(sum(3, 1, 2, 3) == 6);
    qsort(a, 4, sizeof a[0], cmp);
    CHECK(a[0] == -5 && a[3] == 30);
    CHECK(mul(70000ul, 3) == 210000ul);
    CHECK((float)d == (float)(1.0f / 3.0f));
    CHECK(argc >= 1);
    printf("host16: %d failures\n", fails);
    return fails != 0;
}
