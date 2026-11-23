/* rtbench.c - how fast the runtime is: milliseconds (hz_uptime) for many calls of each
 * routine, the empty loop's time taken off.
 */
#include <stdio.h>
#include <string.h>
#include <horizon.h>

static volatile unsigned va, vb, vr, vn = 1000, v6 = 6;  /* volatile sizes: no memcpy
                                                     of a constant size inlined */
static volatile unsigned long la, lb, lr;
static char a[1100], b[1100];
static unsigned long t0, empty;

static void start(void) { t0 = hz_uptime(); }
static void stop(const char *name, unsigned long n)
{
    unsigned long t = hz_uptime() - t0;
    printf("%-22s %5lu ms for %lu\n", name, t > empty ? t - empty : 0, n);
}

int main(void)
{
    unsigned i;
    static const unsigned m16[8] = {3, 100, 1234, 40000, 7, 255, 65535, 999};
    static const unsigned d16[8] = {3, 10, 123, 7, 1000, 255, 40000, 17};
    start();
    for (i = 0; i < 20000; ++i) vr = m16[i & 7];
    empty = hz_uptime() - t0;
    start();
    for (i = 0; i < 20000; ++i) { va = m16[i & 7]; vb = m16[(i + 3) & 7]; vr = va * vb; }
    stop("mul16 (mixed)", 20000);
    start();
    for (i = 0; i < 20000; ++i) { va = 50000u - i; vb = d16[i & 7]; vr = va / vb; }
    stop("div16 (mixed)", 20000);
    start();
    for (i = 0; i < 20000; ++i) { va = m16[i & 7]; vb = 100; vr = va * vb; }
    stop("mul16 (x 100)", 20000);
    empty = empty / 2;      /* the 32-bit loops run 10000 */
    start();
    for (i = 0; i < 10000; ++i) { la = 123456UL + i; lb = 1103515245UL; lr = la * lb; }
    stop("mul32", 10000);
    start();
    for (i = 0; i < 10000; ++i) { la = 12345678UL + i; lb = 1000; lr = la / lb; }
    stop("div32 (/ 1000)", 10000);
    start();
    for (i = 0; i < 10000; ++i) { la = 100000UL + i; lb = 7; lr = la % lb; }
    stop("mod32 (% 7, small)", 10000);
    start();
    for (i = 0; i < 10000; ++i) { la = 0xDEADBEEFUL - i; lb = 0x12345UL; lr = la / lb; }
    stop("div32 (/ $12345)", 10000);
    empty = 0;
    memset(b, 'x', 1000);
    b[1000] = 0;
    start();
    for (i = 0; i < 200; ++i) memcpy(a, b, vn);
    stop("memcpy 1000", 200);
    start();
    for (i = 0; i < 200; ++i) memmove(a + 1, a, vn);
    stop("memmove 1000 (up)", 200);
    start();
    for (i = 0; i < 200; ++i) memset(a, i, vn);
    stop("memset 1000", 200);
    start();
    for (i = 0; i < 200; ++i) vr = strlen(b);
    stop("strlen 1000", 200);
    start();
    for (i = 0; i < 200; ++i) strcpy(a, b);
    stop("strcpy 1000", 200);
    memcpy(a, b, 1001);
    start();
    for (i = 0; i < 200; ++i) vr = memcmp(a, b, vn);
    stop("memcmp 1000", 200);
    start();
    for (i = 0; i < 2000; ++i) memcpy(a, b, v6);
    stop("memcpy 6", 2000);
    puts("rtbench done");
    return 0;
}
