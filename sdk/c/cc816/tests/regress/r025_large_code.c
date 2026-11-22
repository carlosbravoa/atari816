/* r025_large_code.c - the large code model (hcc --code large; make check runs every
 * program in it too, with the functions that can move in turn in three other banks).
 * What it needs from the compiler and the runtime, in one program: calls and
 * returns across banks (JSL/RTL, the arguments one byte further), a static function's
 * address (its thunk in the main bank), a global one's (hcc's thunk), a table of function
 * pointers in the data, a callback from the C library (qsort), a structure copy (MVN: its
 * banks are the main bank's, not the code's), a jump table (a switch: read through PBR, so
 * it must sit with its code), the 16- and 32-bit division and multiplication helpers and
 * a 64-bit one (JSL entries, udiv16's own RTS kept), float, varargs (va_start's offset),
 * setjmp/longjmp from a function in another bank (the return address's bank), and
 * recursion between two functions. In the small model the same program checks that
 * nothing changed there. Returns 0 when everything is right. */
#include <setjmp.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

struct big { int a[24]; long l; };

static int twice(int x) { return 2 * x; }
int thrice(int x) { return 3 * x; }
static int (*const ops[3])(int) = { twice, thrice, 0 };

static int pick(unsigned k)
{
    switch (k) {
    case 0: return 11;
    case 1: return 22;
    case 2: return 33;
    case 3: return 44;
    case 4: return 55;
    case 5: return 66;
    case 6: return 77;
    }
    return -1;
}

static void copy(struct big *d, const struct big *s) { *d = *s; }

static int cmp(const void *a, const void *b)
{
    return *(const int *)a - *(const int *)b;
}

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

static jmp_buf jb;

static void deep(int n)
{
    if (n == 0)
        longjmp(jb, 42);
    deep(n - 1);
}

unsigned odd(unsigned n);
unsigned even(unsigned n) { return n == 0 ? 1 : odd(n - 1); }
unsigned odd(unsigned n) { return n == 0 ? 0 : even(n - 1); }

static unsigned div16(unsigned a, unsigned b) { return a / b + a % b; }
static int sdiv16(int a, int b) { return a / b + a % b; }
static long mul32(long a, long b) { return a * b / 7; }
static long long mul64(long long a, long long b) { return a * b / 3; }
static float fmix(float a, float b) { return a * b + 0.5f; }

int main(void)
{
    struct big x, y;
    int v[5] = { 9, 3, 7, 1, 5 };
    int (*f)(int) = twice;
    int r, i, bad = 0;

    if (f(5) != 10 || ops[0](4) != 8 || ops[1](4) != 12 || thrice(3) != 9)
        bad |= 1;
    f = thrice;
    if (f(7) != 21)
        bad |= 2;
    for (i = 0; i < 7; i++)
        if (pick(i) != 11 * (i + 1))
            bad |= 4;
    if (pick(9) != -1)
        bad |= 4;
    for (i = 0; i < 24; i++)
        x.a[i] = i * 5;
    x.l = 1234567L;
    memset(&y, 0, sizeof y);
    copy(&y, &x);
    if (y.a[23] != 115 || y.l != 1234567L)
        bad |= 8;
    qsort(v, 5, sizeof v[0], cmp);
    if (v[0] != 1 || v[1] != 3 || v[2] != 5 || v[3] != 7 || v[4] != 9)
        bad |= 16;
    if (sum(4, 1, 2, 3, 4) != 10 || sum(0) != 0)
        bad |= 32;
    r = setjmp(jb);
    if (r == 0)
        deep(20);
    else if (r != 42)
        bad |= 64;
    if (even(101) != 0 || odd(101) != 1)
        bad |= 128;
    if (div16(50000u, 7) != 7142u + 6 || sdiv16(-100, 7) != -14 - 2)
        bad |= 256;
    if (mul32(100000L, 77) != 1100000L || mul64(123456789LL, 1000LL) != 41152263000LL)
        bad |= 512;
    if (fmix(2.5f, 4.0f) != 10.5f)
        bad |= 1024;
    return bad;
}
