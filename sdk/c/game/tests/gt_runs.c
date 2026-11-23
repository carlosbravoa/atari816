/* gt_runs.c - hgame's test (0.30): runs filled by the blitter in one call (hg_fill_runs:
 * the kernel's fill_runs; with the blitter off the library's CPU path, the same pixels),
 * page flipping without waiting in a framebuffer of three pages (hg_flip_pages, hg_flip,
 * hg_flip_free: what SkyRoads, ports/skyroads, does by hand), groups of a program's own
 * spans (hg_fill_groups), and the microsecond clock (hg_us). The screenshot: page 1 shown,
 * 3,000 runs and 40 groups. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s runs: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

#define N 3000
static hg_run r[N];
static const unsigned rows[3] = {0, 206, 410};     /* each page inside one bank */

/* page p's pixels (64,000 bytes, inside one bank) */
static unsigned char __far *page(unsigned p)
{
    unsigned long a = ((unsigned long)hg_fb_bank << 16) + (unsigned long)rows[p] * 320UL;
    return (unsigned char __far *)a;
}

static void pattern(void)
{
    unsigned k;
    for (k = 0; k < N; ++k)             /* 16 runs a row, overlapping ones too */
        HG_RUN(&r[k], (k / 16) * 320u + (k % 16) * 20u, 1 + k % 37, 16 + k % 200);
}

/* 40 groups over 5-byte elements {u16 left, u16 right, u8 width} in a bank of their own:
 * group k draws elements 10 k .. 10 k + 9, their left offsets (k even) or right ones */
static hg_rungroup g[40];

static void groups(void)
{
    unsigned char __far *e = (unsigned char __far *)hz_far_alloc();
    unsigned k, o;
    for (k = 0; k < 400; ++k) {
        o = (k * 160u) % 60000u;
        e[k * 5] = (unsigned char)o;
        e[k * 5 + 1] = (unsigned char)(o >> 8);
        e[k * 5 + 2] = (unsigned char)(o + 3000u);
        e[k * 5 + 3] = (unsigned char)((o + 3000u) >> 8);
        e[k * 5 + 4] = (unsigned char)(5 + k % 50);
    }
    for (k = 0; k < 40; ++k)
        HG_RUNGROUP(&g[k], e + k * 50u, 10, 200 + k, 5, (k & 1) ? 2 : 0, 4);
}

int main(void)
{
    unsigned k, same;
    unsigned long t0, t1;
    unsigned char __far *a;
    unsigned char __far *b;

    if (hg_screen_fb(HG_320X180, "gt_runs", 320, 610) < 0) {
        printf("FAIL runs: hg_screen_fb\n");
        return 1;
    }
    /* a few runs, read back (hg_peek waits for the blitter) */
    HG_RUN(&r[0], 0, 10, 5);                    /* row 0, x 0-9 */
    HG_RUN(&r[1], 320 + 5, 0, 6);               /* width 0: nothing */
    HG_RUN(&r[2], 320 * 10 + 300, 40, 7);       /* row 10 x 300-319, row 11 x 0-19 */
    HG_RUN(&r[3], 320 * 20 + 100, 50, 8);
    HG_RUN(&r[4], 320 * 20 + 120, 10, 9);       /* over the one before: later wins */
    check("five runs", hg_fill_runs(0, r, 5) == 0);
    check("their pixels", hg_peek(0, 0) == 5 && hg_peek(9, 0) == 5 && hg_peek(10, 0) == 0 &&
          hg_peek(5, 1) == 0 && hg_peek(319, 10) == 7 && hg_peek(19, 11) == 7 &&
          hg_peek(20, 11) == 0 && hg_peek(100, 20) == 8 && hg_peek(120, 20) == 9 &&
          hg_peek(129, 20) == 9 && hg_peek(130, 20) == 8 && hg_peek(149, 20) == 8 &&
          hg_peek(150, 20) == 0);
    /* the page from row 600 is 3,200 bytes: a run may end at its end, not past it */
    HG_RUN(&r[0], 3190, 10, 3);
    HG_RUN(&r[1], 3191, 10, 3);
    check("a run ending at the page's end", hg_fill_runs(600, r, 1) == 0 &&
          hg_peek(310, 609) == 3 && hg_peek(319, 609) == 3);
    check("a run past it is refused", hg_fill_runs(600, r, 2) < 0);

    /* 3,000 runs (two calls) and groups into page 1 by the blitter, into page 2 by the CPU */
    pattern();
    groups();
    check("3,000 runs into page 1", hg_fill_runs(206, r, N) == 0);
    check("and 40 groups", hg_fill_groups(206, g, 40) == 0);
    hg_flush(1);
    hz_ws_config(1);                    /* the blitter off: fill_runs says ENODEV */
    check("the same into page 2 by the CPU", hg_fill_runs(410, r, N) == 0 &&
          hg_fill_groups(410, g, 40) == 0);
    hz_ws_config(0);
    a = page(1);
    b = page(2);
    same = 1;
    for (k = 0; k < 63990u; ++k)         /* (rows 600-609: the edge test above) */
        if (a[k] != b[k]) {
            same = 0;
            printf("(first difference at %u: %u, %u)\n", k, a[k], b[k]);
            break;
        }
    check("the blitter's pixels are the CPU's", same);
    check("and something was drawn", a[0] == 200 && a[3200] == 202);   /* (groups 0, 2) */

    /* the microsecond clock across a vertical blank */
    hz_vsync();
    t0 = hg_us();
    hz_vsync();
    t1 = hg_us();
    check("hg_us: a frame is 16,000 to 17,500 us", t1 - t0 >= 16000 && t1 - t0 <= 17500);

    /* page flipping without waiting */
    check("hg_flip_pages", hg_flip_pages(3, rows) == 0);
    hz_vsync();                         /* (the next three inside one frame) */
    k = hg_flip_free();
    t0 = (unsigned long)hg_flip(1, 0);
    t1 = hg_flip_free();
    check("a free page while 0 is shown", k == 1);
    check("hg_flip(1, 0)", t0 == 0);
    check("then neither 0 (shown) nor 1 (waiting) is free", t1 == 2);
    hz_vsync();
    hz_vsync();
    k = hg_flip_free();                 /* (it sees the blank: hg_flip_shown after it) */
    check("after a blank 1 is shown, 0 free", hg_flip_shown == 1 && k == 0);
    hz_vsync();
    check("a page that waited and was replaced is free again",
          hg_flip(2, 0) == 0 && hg_flip(0, 0) == 0 && hg_flip_free() == 2);
    hg_flip(1, 0);
    printf("gt_runs: %u failed\n", fails);
    t0 = hg_ms();
    while (hg_ms() - t0 < 2500 && hg_frame())   /* shot at 3 s: page 1 */
        ;
    return 0;
}
