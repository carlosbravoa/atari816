/* gt_mapbench.c - hgame's measurement: what scrolling a map of 16-bit tiles costs a frame,
 * at 640 x 360 and 320 x 180, tiles of 16 x 16 from a sheet of 4096 x 64, a world of
 * 120 x 100 tiles (Micropolis's), on emu816's board timing:
 *   map16      hg_map16 + hg_camera: the ring drawn a column / row at a time
 *   by hand    the Micropolis port's way (ports/simcity/src/view.c, view_update after a
 *              move): every tile in view compared with a far table of the slots' tiles,
 *              the changed ones drawn by hg_draw_part, the map column after column in far
 *              memory; the view by hg_scroll_wrap / hg_split_wrap
 *   still      hg_camera to where it is: the cost of the measuring (two hg_us)
 *   refresh    hg_map_refresh(0) on a view that did not move (what a game that writes its
 *              map itself pays to have the changes drawn: all rows at once)
 * Each a frame's step of 16 pixels (a tile) and of 8 pixels (a column every other
 * frame), to the right, averaged over 32 frames: "cpu" the time until the call returns
 * (the records queued), "done" until the blitter has drawn them (the measuring included:
 * see "still"). */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

void hg__cpu_sync(void);        /* (the library's: the records so far drawn, waited for) */

#define MW 120
#define MH 100
#define NT 960
#define F 32

static unsigned fails;
static unsigned __far *m;       /* row after row (hg_map16) */
static unsigned __far *mt;      /* column after column (the port's Map[c][r]) */
static unsigned __far *shown;   /* the hand-made ring's slots */
static hg_image *sheet;
static unsigned rc, rr, vw, vh, ph;
static int cx, cy;

static void check(const char *what, int ok)
{
    printf("%s mapbench: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

/* the port's view_update after a move: all rows of the view compared, the changed drawn */
static unsigned by_hand(void)
{
    unsigned c, c0, c1, r, r0, r1, sc, n = 0, v, i;
    c0 = (unsigned)cx / 16;
    c1 = (unsigned)(cx + (int)vw - 1) / 16;
    r0 = (unsigned)cy / 16;
    r1 = (unsigned)(cy + (int)vh - 1) / 16;
    if (c1 >= MW) c1 = MW - 1;
    if (r1 >= MH) r1 = MH - 1;
    hg_origin(0, 0);
    for (c = c0; c <= c1; c++) {
        unsigned __far *col = mt + c * MH;
        sc = c % rc;
        for (r = r0; r <= r1; r++) {
            v = col[r];
            i = (r % rr) * rc + sc;
            if (shown[i] != v) {
                shown[i] = v;
                hg_draw_part(sheet, (v & 255) << 4, (v >> 8) << 4, 16, 16, (int)(sc << 4),
                             (int)((r % rr) << 4));
                ++n;
            }
        }
    }
    return n;
}

static unsigned long acc_cpu, acc_done, acc_max;

static void timed_start(unsigned long *t0)
{
    hg__cpu_sync();
    *t0 = hg_us();
}

static void timed_stop(unsigned long t0)
{
    unsigned long t1 = hg_us(), t2;
    hg__cpu_sync();
    t2 = hg_us();
    acc_cpu += t1 - t0;
    acc_done += t2 - t0;
    if (t2 - t0 > acc_max)
        acc_max = t2 - t0;
}

static void report(const char *mode, const char *way, unsigned step)
{
    printf("mapbench %s %-8s %2u px: cpu %5lu us, done %5lu us a frame (max %lu)\n", mode,
           way, step, acc_cpu / F, acc_done / F, acc_max);
    acc_cpu = acc_done = acc_max = 0;
}

static void bench(unsigned smode, const char *name)
{
    unsigned i, step, stride, rows;
    unsigned long t0;

    vw = smode == HG_640X360 ? 640 : 320;
    ph = smode == HG_640X360 ? 48 : 24;
    vh = (smode == HG_640X360 ? 360 : 180) - ph;
    rc = (vw + 15) / 16 + 1;
    rr = (vh + 15) / 16 + 1;
    stride = rc * 16;
    rows = rr * 16 + ph;

    /* by hand: the ring in a framebuffer of the program's shape, the panel at the top */
    if (hg_screen_fb(smode, "gt_mapbench", stride, rows) < 0) {
        check("hg_screen_fb", 0);
        return;
    }
    sheet = hg_image_new(4096, 64, 1);
    if (!sheet || !sheet->sheet) {
        check("the sheet", 0);
        return;
    }
    for (i = 0; i < 4; i++)
        hg_image_fill(sheet, 0, (int)i * 16, 4096, 16, 40 + i * 30);
    hz_far_set(shown, 0xFF, 65535U);
    hg_scroll_wrap(0, 0, rr * 16);
    hg_split_wrap(ph, 0, 0);
    hg_scroll(0, (int)(rr * 16));
    cx = cy = 0;
    hg_frame();
    by_hand();
    for (step = 16; step >= 8; step -= 8) {
        for (i = 0; i < F && hg_frame(); i++) {
            timed_start(&t0);
            cx += (int)step;
            by_hand();
            hg_split_wrap(ph, cx, cy);
            timed_stop(t0);
        }
        report(name, "by hand", step);
    }
    /* hg_map16 */
    check("hg_map16", hg_map16(m, MW, MH, sheet, 16, 16, (int)ph) == 0);
    hg_frame();
    for (i = 0; i < F && hg_frame(); i++) {     /* the cost of the measuring itself */
        timed_start(&t0);
        hg_camera(0, 0);
        timed_stop(t0);
    }
    report(name, "still", 0);
    for (step = 16; step >= 8; step -= 8) {
        cx = hg_cam_x;
        for (i = 0; i < F && hg_frame(); i++) {
            timed_start(&t0);
            cx += (int)step;
            hg_camera(cx, 0);
            timed_stop(t0);
        }
        report(name, "map16", step);
    }
    cx = hg_cam_x;
    for (i = 0; i < F && hg_frame(); i++) {
        timed_start(&t0);
        cx += 16;
        hg_camera(cx, (int)i * 16);
        timed_stop(t0);
    }
    report(name, "map16 dg", 16);
    for (i = 0; i < F && hg_frame(); i++) {
        timed_start(&t0);
        hg_map_refresh(0);
        timed_stop(t0);
    }
    report(name, "refresh", 0);
    check("the camera moved", hg_cam_x > 0);
    hg_close();
}

int main(void)
{
    unsigned c, r;

    m = (unsigned __far *)hz_far_alloc();
    mt = (unsigned __far *)hz_far_alloc();
    shown = (unsigned __far *)hz_far_alloc();
    if (!m || !mt || !shown) {
        printf("FAIL mapbench: no far memory\n");
        return 1;
    }
    for (r = 0; r < MH; r++)
        for (c = 0; c < MW; c++) {
            m[r * MW + c] = (c * 37u + r * 11u) % NT;
            mt[c * MH + r] = (c * 37u + r * 11u) % NT;
        }
    bench(HG_640X360, "640x360");
    bench(HG_320X180, "320x180");
    printf("gt_mapbench: %u failed\n", fails);
    return 0;
}
