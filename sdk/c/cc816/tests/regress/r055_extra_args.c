/* r055_extra_args.c - a call with more arguments than the function's prototype
 * (-fextra-args; also -std=c89, -fdos-keywords): a warning (-Wextra-args), as Microsoft
 * C's C4020, and the call works: the arguments are pushed right to left and the caller
 * takes them off, so the extra ones lie beyond the callee's parameters, never read. Also
 * with -fargs-right-to-left (the same layout), a structure returned by value (its hidden
 * pointer first), a long and a far pointer among them, and through a function pointer.
 * LEVELS: 0 1 2 */
// FLAGS: -fextra-args -Wno-extra-args
struct pt { int x, y; };

static int calls;
static int side(int v) { calls++; return v; }

int f2(int a, int b);
int f2(int a, int b) { return a * 10 + b; }

long fl(long a);
long fl(long a) { return a + 1; }

struct pt mk(int x);
struct pt mk(int x) { struct pt p; p.x = x; p.y = -x; return p; }

int f0(void);
int f0(void) { return 77; }

int main(void)
{
    char buf[4] = "abc";
    char __far *fp = (char __far *)buf;
    int (*pf)(int, int) = f2;
    long big = 123456789L;
    struct pt p;
    if (f2(1, 2, 3) != 12) return 1;
    if (f2(4, 5, big, fp, 9) != 45) return 2;
    if (fl(big, 1, 2) != 123456790L) return 3;
    p = mk(6, big);
    if (p.x != 6 || p.y != -6) return 4;
    if (f0(1, 2) != 77) return 5;
    if (pf(7, 8, side(1)) != 78) return 6;
    if (calls != 1) return 7;                 /* the extra argument is evaluated */
    if (f2(side(2), side(3), side(4)) != 23 || calls != 4) return 8;
    return 0;
}
