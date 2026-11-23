/* args_order.h - the order in which a call's arguments are evaluated, shared by
 * r049_args_order.c (the default: left to right) and r050_args_rtl.c
 * (-fargs-right-to-left: right to left, as DOS's compilers): plain, long, far pointer and
 * structure arguments, a structure result, variable arguments, a call through a function
 * pointer, nested calls; the values must arrive where they belong in both. */
#include <stdarg.h>
#include <string.h>

#ifdef __CC816_ARGS_RTL__
#define RTL 1
#else
#define RTL 0
#endif

struct pt { int x, y; long z; };

static char __far fb[2] = { 5, 0 };
static char log_[40];
static int nlog;
static int seed = 1;

static int rnd(void) { seed = seed * 5 + 1; return seed; }
static int mark(int c) { log_[nlog++] = (char)c; return c; }
static long markl(int c) { log_[nlog++] = (char)c; return 100000L * c; }
static char __far *markp(int c, char __far *p) { log_[nlog++] = (char)c; return p; }
static struct pt marks(int c) { struct pt s; log_[nlog++] = (char)c; s.x = c; s.y = -c; s.z = 7L * c; return s; }

static int three(int a, int b, int c) { return a * 100 + b * 10 + c; }
static long mixed(long a, char __far *p, struct pt s, int b)
{
    return a + *p + s.x * 1000L + s.y + s.z + b;
}
static int sum(int n, ...)
{
    va_list ap;
    int s = 0, i;
    va_start(ap, n);
    for (i = 0; i < n; i++)
        s = s * 10 + va_arg(ap, int);
    va_end(ap);
    return s;
}
static struct pt pair(int a, int b) { struct pt s; s.x = a; s.y = b; s.z = 0; return s; }
static int diff(int a, int b) { return a - b; }

static int expect(const char *ltr)
{
    /* the log against the left-to-right order ltr (or ltr backwards) */
    char want[40];
    int n = (int)strlen(ltr), i;
    for (i = 0; i < n; i++)
        want[i] = RTL ? ltr[n - 1 - i] : ltr[i];
    want[n] = 0;
    log_[nlog] = 0;
    i = n == nlog && !strcmp(want, log_);
    nlog = 0;
    return i;
}

int main(void)
{
    int (*fp)(int, int) = diff;
    struct pt s;
    int r1, r2;
    long l;
    if (three(mark(1), mark(2), mark(3)) != 123 || !expect("\1\2\3"))
        return 1;
    l = mixed(markl(1), markp(2, fb), marks(3), mark(4));
    if (l != 100000L + 5 + 3000 - 3 + 21 + 4 || !expect("\1\2\3\4"))
        return 2;
    if (sum(3, mark(4), mark(5), mark(6)) != 456 || !expect("\4\5\6"))
        return 3;
    s = pair(mark(7), mark(8));
    if (s.x != 7 || s.y != 8 || !expect("\7\10"))
        return 4;
    if (fp(mark(9), mark(2)) != 7 || !expect("\11\2"))
        return 5;
    if (three(mark(1), three(mark(2), mark(3), 0), mark(4)) != 100 + 230 * 10 + 4)
        return 6;
    if (!expect("\1\2\3\4"))        /* right to left: 4, then the inner call's 3 2, then 1 */
        return 7;
    /* the case of the X-COM port: two draws of one generator */
    seed = 1;
    r1 = diff(rnd(), rnd());
    seed = 1;
    r2 = rnd();
    r2 = RTL ? rnd() - r2 : r2 - rnd();
    if (r1 != r2)
        return 8;
    return 0;
}
