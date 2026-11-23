/* hg_runs.c - hgame (0.30): runs filled by the blitter in one call (fill_runs, or the CPU in
 * hg_runs.s on boards without command lists), page flipping without waiting, the microsecond
 * clock. Its own file: a game that does not use them does not link them. */
#include <stdio.h>
#include "hg_int.h"

/* hg_runs.s: n runs into page (size bytes, 0 = 65,536) by the CPU -> 0xFFFF, or the index
 * of the first run that does not end inside the page (the runs before it are filled) */
unsigned hg__runs_cpu(unsigned long page, unsigned size, const hg_run __far *runs, unsigned n);

unsigned hg__groups_cpu(unsigned long page, unsigned size, const hg_rungroup __far *g,
                        unsigned n);

static unsigned char cpu_runs;          /* fill_runs said ENODEV: the CPU fills */
static hz_fillruns blk;
static unsigned sent;                   /* what fill_runs took (groups: maybe not all) */

static void bad_run(const char *fn, const char *what, unsigned k)
{
    static char m[48];
    sprintf(m, "%s %u ends past the page", what, k);
    hg__fail(fn, m);
}

/* one call of fill_runs (flags: FR_GROUPS or 0) -> 1 sent, 0 the CPU must fill, -1 refused */
static int send(unsigned long page, unsigned size, const void __far *p, unsigned k,
                unsigned flags, unsigned base, const char *fn)
{
    if (cpu_runs)
        return 0;
    HZ_U24B(blk.page, page >> 16, (unsigned)page);
    blk.flags = (unsigned char)flags;
    blk.size = (unsigned short)size;
    HZ_U24(blk.runs, p);
    blk.zero = 0;
    if ((sent = (unsigned)hz_fill_runs(k, &blk)) != 0xFFFF) {
        hg__listrun = 1;
        return 1;
    }
    if (hz_errno == HZ_EINVAL) {
        hg__listrun = 1;
        bad_run(fn, flags ? "a run of group" : "run", base + hz_x);
        return -1;
    }
    if (hz_errno != HZ_ENODEV && hz_errno != HZ_ENOSYS) {
        hg__fail(fn, hz_errno == HZ_EFAULT ? "the page (or the elements) not the game's "
                 "memory" : "fill_runs refused");
        return -1;
    }
    cpu_runs = 1;                       /* before REV $09, the blitter off, before 0.30 */
    return 0;
}

int hg_fill_runs_at(unsigned long page, unsigned size, const hg_run __far *runs, unsigned n)
{
    unsigned i = 0, k, r;
    int s;
    if (hg__qn)                         /* the frame's records first, in order */
        hg__submit(1);
    while (i < n) {
        k = n - i > FR_MAX ? FR_MAX : n - i;
        s = send(page, size, runs + i, k, 0, i, "hg_fill_runs");
        if (s < 0)
            return -1;
        if (!s) {
            hg__cpu_sync();
            r = hg__runs_cpu(page, size, runs + i, k);
            if (r != 0xFFFF) {
                bad_run("hg_fill_runs", "run", i + r);
                return -1;
            }
        }
        i += k;
    }
    return 0;
}

int hg_fill_groups_at(unsigned long page, unsigned size, const hg_rungroup __far *g, unsigned n)
{
    unsigned i = 0, k, r;
    int s;
    if (hg__qn)
        hg__submit(1);
    while (i < n) {
        k = n - i > FR_MAX ? FR_MAX : n - i;
        s = send(page, size, g + i, k, FR_GROUPS, i, "hg_fill_groups");
        if (s < 0)
            return -1;
        if (s) {
            i += sent;                  /* (the kernel stops before 2,688 runs: the rest again) */
            continue;
        }
        hg__cpu_sync();
        r = hg__groups_cpu(page, size, g + i, k);
        if (r != 0xFFFF) {
            bad_run("hg_fill_groups", "a run of group", i + r);
            return -1;
        }
        i += k;
    }
    return 0;
}

/* the page from screen row y: its address and size (0: 65,536) -> 0, or -1 */
static int page_at(int y, const char *fn, unsigned long *base, unsigned *size)
{
    long row;
    unsigned long end, sz;
    if (hg__kind != HG__FULL) {
        hg__fail(fn, "full screen only");
        return -1;
    }
    row = (long)y + hg__oy + (long)hg__pagey;
    if (row < 0 || row >= (long)hg_fb_rows || hg__ox < 0) {
        hg__fail(fn, "the page starts outside the framebuffer");
        return -1;
    }
    *base = hg__fbaddr((unsigned)hg__ox, (unsigned)row);
    end = hg__fbbase + hg__umul(hg_fb_rows, hg_fb_stride);
    sz = end - *base;
    *size = sz >= 65536UL ? 0 : (unsigned)sz;
    return 0;
}

int hg_fill_runs(int y, const hg_run __far *runs, unsigned n)
{
    unsigned long base;
    unsigned size;
    if (page_at(y, "hg_fill_runs", &base, &size) < 0)
        return -1;
    return hg_fill_runs_at(base, size, runs, n);
}

int hg_fill_groups(int y, const hg_rungroup __far *g, unsigned n)
{
    unsigned long base;
    unsigned size;
    if (page_at(y, "hg_fill_groups", &base, &size) < 0)
        return -1;
    return hg_fill_groups_at(base, size, g, n);
}

/* ---------------------------------------------------------------- page flipping */

unsigned hg_flip_shown;
static unsigned char flip_n, flip_wait = 0xFF;
static unsigned flip_row[4], flip_frame;

int hg_flip_pages(unsigned n, const unsigned *rows)
{
    unsigned k;
    if (hg__kind != HG__FULL || hg__double || n < 2 || n > 4) {
        hg__fail("hg_flip_pages", "full screen (hg_screen_fb, no HG_DOUBLE), 2-4 pages");
        return -1;
    }
    for (k = 0; k < n; ++k) {
        if (rows[k] >= hg_fb_rows) {
            hg__fail("hg_flip_pages", "a page starts below the framebuffer");
            return -1;
        }
        flip_row[k] = rows[k];
    }
    flip_n = (unsigned char)n;
    hg_flip_shown = 0;
    flip_wait = 0xFF;
    return 0;
}

/* the page waiting to be shown is on the screen once a vertical blank has passed */
static void flips_done(void)
{
    if (flip_wait != 0xFF && hz_frame() != flip_frame) {
        hg_flip_shown = flip_wait;
        flip_wait = 0xFF;
    }
}

unsigned hg_flip_free(void)
{
    unsigned p;
    flips_done();
    for (p = 0; p < flip_n; ++p)
        if (p != hg_flip_shown && p != flip_wait)
            return p;
    return 0xFFFF;
}

int hg_flip(unsigned page, int dy)
{
    if (page >= flip_n) {
        hg__fail("hg_flip", "no such page (hg_flip_pages first)");
        return -1;
    }
    hg__cpu_sync();                     /* what was sent is drawn before it shows */
    flips_done();
    hg__scr.y = (unsigned short)((int)flip_row[page] + dy);
    if (hz_fs_scroll(&hg__scr) < 0) {
        hg__fail("hg_flip", "fs_scroll refused (REV $0B, the view inside the framebuffer)");
        return -1;
    }
    hg__scr_dirty = 0;
    flip_wait = (unsigned char)page;    /* (a page still waiting is never shown: free again) */
    flip_frame = hz_frame();
    return 0;
}

/* ---------------------------------------------------------------- the clock */

unsigned long hg_us(void)
{
    unsigned long v = (unsigned long)hz_uptime_us();
    return hz_errno ? 0 : v;
}
