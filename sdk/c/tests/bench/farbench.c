/* farbench.c - the far data model's costs (docs/c/reference.md, "The far data model":
 * "What it costs"): the same C built with near data and with far data (hcc --data far),
 * each loop's time in milliseconds and in cycles of the 14.3 MHz clock a step.
 *   copy     while ((*d++ = *s++)) over 4,000 bytes                          (x 10)
 *   sprite   if (*s) d[k] = *s; a 32 x 40 masked sprite (bench816's shape)    (x 20)
 *   index    s += a[i] over 2,000 ints, int i                                  (x 10)
 *   member   p->x += p->y over 500 structures through a pointer             (x 10)
 *   call     f(p) with a pointer argument and result                     (x 5,000)
 *   memcpy   4,000 bytes                                                       (x 20)
 *   strlen   4,000 bytes                                                       (x 20)
 * The buffers are globals (near data: the main bank; far data: their addresses are far
 * pointers, the bank the main one) and malloc blocks (far data: other banks). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <horizon.h>

struct pt { int x, y; };

static char src[4001], dst[4001];
static unsigned char spr[32 * 40], scr[320 * 50];
static int arr[2000];
static struct pt pts[500];
static unsigned long t0;
static unsigned long sink;

static void start(void)
{
    t0 = hz_uptime();
}

static void stop(const char *name, unsigned long steps)
{
    unsigned long ms = hz_uptime() - t0;
    /* 14,318 cycles a millisecond */
    printf("%-7s %5lu ms %5lu cycles a step\n", name, ms, steps ? ms * 14318UL / steps : 0);
}

static char *pass(char *p) { return p + 1; }

int main(void)
{
    unsigned i, r, k;
    char *d, *s;
    unsigned char *sp, *dp;
    struct pt *p;
    char *heap = malloc(4001);
    long sum = 0;

    for (i = 0; i < 4000; i++)
        src[i] = (char)('a' + i % 26);
    src[4000] = 0;
    for (i = 0; i < sizeof spr; i++)
        spr[i] = (unsigned char)(i % 7 ? i : 0);
    for (i = 0; i < 2000; i++)
        arr[i] = (int)i;

    start();
    for (r = 0; r < 10; r++) {
        d = dst;
        s = src;
        while ((*d++ = *s++) != 0)
            ;
    }
    stop("copy", 40000UL);

    start();
    for (r = 0; r < 20; r++) {
        sp = spr;
        for (i = 0; i < 40; i++) {
            dp = scr + i * 320u + r;
            for (k = 0; k < 32; k++, sp++)
                if (*sp)
                    dp[k] = *sp;
        }
    }
    stop("sprite", 20UL * 32 * 40);

    start();
    for (r = 0; r < 10; r++) {
        int j;
        for (j = 0; j < 2000; j++)
            sum += arr[j];
    }
    stop("index", 20000UL);

    start();
    for (r = 0; r < 10; r++)
        for (p = pts, i = 0; i < 500; i++, p++)
            p->x += p->y + (int)i;
    stop("member", 5000UL);

    start();
    d = dst;
    for (i = 0; i < 5000; i++)
        d = pass(d) - 1;
    stop("call", 5000UL);

    start();
    for (r = 0; r < 20; r++)
        memcpy(heap ? heap : dst, src, 4000);
    stop("memcpy", 80000UL);

    start();
    for (r = 0; r < 20; r++)
        sink += strlen(src);
    stop("strlen", 80000UL);

    sink += (unsigned long)sum + (unsigned)pts[3].x + scr[5] + (unsigned char)dst[7];
    printf("farbench done %lu\n", sink);
    return 0;
}
