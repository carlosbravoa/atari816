/* gnuext.c - GNU extensions: case ranges (narrow ones as cases, a wide one as one test,
 * of signed, unsigned, char and long switches), range designators in global, static and
 * local arrays (also of structures, and nested), attributes read and ignored
 * (noreturn, unused, packed, aligned(1), always_inline, format), __extension__,
 * __inline__, __restrict, __typeof__, __alignof__. */
#include <stdio.h>
#include <stdlib.h>

struct pt { int x, y; };
int ga[10] = { [2 ... 5] = 7, [8] = 1 };
struct pt gp[6] = { [1 ... 3] = { 4, 5 }, [5].y = 9 };
int gm[3][4] = { [0 ... 1] = { [1 ... 2] = 3 }, [2] = { 9 } };

static __inline__ int sq(int x) __attribute__((always_inline, unused));
static __inline__ int sq(int x) { return x * x; }
__attribute__((noreturn)) static void die(int code) { exit(code); }
static int sum(const int *__restrict p, int n) __attribute__((pure));
static int sum(const int *__restrict p, int n) { int s = 0; while (n--) s += *p++; return s; }
struct __attribute__((packed)) hdr { char a; long b; } __attribute__((aligned(1)));
int logf_(const char *f, ...) __attribute__((format(printf, 1, 2)));

static int cls(int c)
{
    switch (c) {
    case '0' ... '9': return 1;
    case 'a' ... 'f':
    case 'A' ... 'F': return 2;
    case -1000 ... -1: return 3;
    case 1000 ... 30000: return 4;
    case 200: return 5;
    default: return 0;
    }
}

static int ucls(unsigned u)
{
    switch (u) {
    case 0 ... 9: return 1;
    case 40000u ... 65535u: return 2;
    default: return 0;
    }
}

static int lcls(long v)
{
    switch (v) {
    case -5 ... 5: return 1;
    case 100000L ... 100100L: return 2;
    default: return 0;
    }
}

static int ccls(unsigned char c)
{
    switch (c) {
    case 128 ... 255: return 1;
    default: return 0;
    }
}

int main(void)
{
    static int sa[8] = { [0 ... 7] = -1, [3] = 4 };
    int la[12] = { [3 ... 10] = 6, [0] = 2 };
    struct pt lp[4] = { [0 ... 2].x = 3 };
    __extension__ long long ext = 1;
    __typeof__(ext) t = 5;
    int bad = 0, k;
    bad |= (sum(ga, 10) != 29) << 0;
    bad |= (gp[0].x || gp[1].x != 4 || gp[3].y != 5 || gp[4].x || gp[5].y != 9) << 1;
    bad |= (gm[0][0] || gm[0][1] != 3 || gm[1][2] != 3 || gm[1][3] || gm[2][0] != 9) << 2;
    bad |= (sum(sa, 8) != -3) << 3;
    bad |= (sum(la, 12) != 2 + 8 * 6) << 4;
    bad |= (lp[2].x != 3 || lp[3].x || lp[1].y) << 5;
    k = cls('5') * 10000 + cls('c') * 1000 + cls('E') * 100 + cls(-7) * 10 + cls(2000);
    bad |= (k != 12234) << 6;
    bad |= (cls(200) != 5 || cls(30001) || cls(-1001) || cls('g')) << 7;
    bad |= (ucls(3) != 1 || ucls(50000u) != 2 || ucls(10) || ucls(39999u)) << 8;
    bad |= (lcls(-5) != 1 || lcls(100050L) != 2 || lcls(6) || lcls(100101L)) << 9;
    bad |= (ccls(200) != 1 || ccls(127)) << 10;
    bad |= (sq(9) != 81 || sizeof(struct hdr) != 5 || t + ext != 6 || __alignof__(int) != 1) << 11;
    if (bad > 4096)
        die(bad);
    return bad;
}
