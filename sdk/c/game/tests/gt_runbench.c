/* gt_runbench.c - hgame's measurement (0.30): what a horizontal run costs by each way of
 * filling it, on emu816's board timing (sdk/docs/reference/performance.md, "Many small
 * fills"). 2,000 runs at scattered places of a 320 x 180 screen, timed with hg_us:
 *   C          a C loop storing the bytes through a __far pointer
 *   CPU asm    hgame's own CPU path (hg_fill_runs with the blitter off: hg_runs.s)
 *   hg_fill+flush  one hg_fill and one call (sheet_draw) a run
 *   hg_fill    hg_fill a run, sent 128 records a call (the frame's queue)
 *   fill_runs  hg_fill_runs: one call for all of them (the kernel's fill_runs, 0.30)
 *   groups of 20, of 2  hg_fill_groups: the same runs as 100 groups of 20 and as 1,000
 *              groups of 2, read where they are
 * "call" is the time until the program has the CPU again, "done" until the pixels are all
 * there (list_wait). Cycles at 14.318 MHz. */
#include <stdio.h>
#include <hgame.h>

#define N 2000
static hg_run r[N];
static unsigned rx[N], ry[N];
static hg_rungroup grs[100], grs2[1000];
static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s runbench: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static void make(unsigned w)
{
    unsigned k, s = 12345;
    for (k = 0; k < N; ++k) {
        s = s * 25173u + 13849u;
        ry[k] = (s >> 8) % 180u;
        rx[k] = s % (320u - w);
        HG_RUN(&r[k], ry[k] * 320u + rx[k], w, 16 + k % 200);
    }
}

/* "name: call X us, done Y us: Z cycles a run (W pixels a run)" -> cycles a run */
static unsigned long show(const char *name, unsigned w, unsigned long call, unsigned long done)
{
    unsigned long ns = done * 1000UL / N;          /* a run, nanoseconds */
    unsigned long cyc = ns * 143UL / 10000UL;
    printf("runbench %-14s w %3u: call %6lu us, done %6lu us: %4lu cycles a run (call %lu)\n",
           name, w, call, done, cyc, call * 1000UL / N * 143UL / 10000UL);
    return cyc;
}

static unsigned long t_call, t_done;
static unsigned long t0;

static void start(void)
{
    hg_flush(1);
    hz_list_wait(0);
    t0 = hg_us();
}

static void stop(void)
{
    t_call = hg_us() - t0;
    hg_flush(1);
    t_done = hg_us() - t0;
}

static void by_c(void)
{
    unsigned k, i;
    unsigned char __far *fb = (unsigned char __far *)((unsigned long)hg_fb_bank << 16);
    start();
    for (k = 0; k < N; ++k) {
        unsigned char __far *p = fb + r[k].ofs;
        unsigned char c = r[k].color;
        for (i = r[k].w; i; --i)
            *p++ = c;
    }
    stop();
}

int main(void)
{
    unsigned k, wi;
    unsigned long c_c, c_q, c_one, c_runs[3], c_cpu[3];
    static const unsigned ws[3] = {8, 23, 100};

    if (hg_screen(HG_320X180, "gt_runbench") < 0) {
        printf("FAIL runbench: hg_screen\n");
        return 1;
    }
    make(23);
    hg_fill_runs(0, r, 1);              /* (the kernel's first call takes its list bank) */
    by_c();
    c_c = show("C", 23, t_call, t_done);

    start();
    for (k = 0; k < N; ++k) {
        hg_fill((int)rx[k], (int)ry[k], 23, 1, r[k].color);
        hg_flush(0);
    }
    stop();
    c_one = show("hg_fill+flush", 23, t_call, t_done);

    start();
    for (k = 0; k < N; ++k)
        hg_fill((int)rx[k], (int)ry[k], 23, 1, r[k].color);
    stop();
    c_q = show("hg_fill", 23, t_call, t_done);

    for (wi = 0; wi < 3; ++wi) {
        make(ws[wi]);
        start();
        hg_fill_runs(0, r, N);
        stop();
        c_runs[wi] = show("fill_runs", ws[wi], t_call, t_done);
    }
    /* groups: the same runs read where they are (100 groups of 20, stride 4) */
    make(23);
    for (k = 0; k < 100; ++k)
        HG_RUNGROUP(&grs[k], &r[k * 20], 20, 16 + k, 4, 0, 3);
    start();
    hg_fill_groups(0, grs, 100);
    stop();
    show("groups of 20", 23, t_call, t_done);
    for (k = 0; k < 1000; ++k)          /* and as 1,000 groups of 2 (a road's shapes) */
        HG_RUNGROUP(&grs2[k], &r[k * 2], 2, 16 + k % 200, 4, 0, 3);
    start();
    hg_fill_groups(0, grs2, 1000);
    stop();
    show("groups of 2", 23, t_call, t_done);
    /* (last: once fill_runs said ENODEV, hgame keeps the CPU path) */
    hz_ws_config(1);
    for (wi = 0; wi < 3; ++wi) {
        make(ws[wi]);
        start();
        hg_fill_runs(0, r, N);
        stop();
        c_cpu[wi] = show("CPU asm", ws[wi], t_call, t_done);
    }
    hz_ws_config(0);
    check("fill_runs is the cheapest way for 23-pixel runs",
          c_runs[1] < c_cpu[1] && c_runs[1] < c_c && c_runs[1] < c_q && c_q < c_one);
    printf("gt_runbench: %u failed\n", fails);
    return 0;
}
