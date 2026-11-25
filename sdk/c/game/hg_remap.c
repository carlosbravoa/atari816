/* hg_remap.c - hgame: colour remap tables, remapped image draws and screen copies. On REV $0D
 * with Horizon 0.31 by the blitter: sheet_draw's SH_TABLE record loads Ali's table from the
 * table's sheet (row k), and SH_COPY / SH_KEY records with SH_REMAP draw through it. Each
 * kernel call starts with the table unknown (another program's list may have loaded its own),
 * so a call's first remapped record has a table record before it, and so has every one whose
 * table differs from the one loaded before it in that call. Elsewhere the CPU draws them,
 * straight into the full-screen framebuffer (hg_rmp.s: hg__remapmem), with the same result.
 * Its own file: a game that does not remap does not link it. */
#include <string.h>
#include "hg_int.h"

/* hg_rmp.s (hg__sheetq: hg_int.h) */
void hg__remapmem(unsigned long dst, unsigned dstride, unsigned long src, unsigned sstride,
                  unsigned w, unsigned h, unsigned key, unsigned long tab);

/* hg_draw.c: the target's clip and the screen -> framebuffer offset */
extern int hg__offx, hg__offy, hg__clx1, hg__cly0, hg__cly1;
extern unsigned hg__four;

static unsigned char mode;              /* 0 not known yet, 1 the blitter, 2 the CPU */
static unsigned tab_at, tab_sheet, tab_row;     /* the last table record queued */
static unsigned char fb_sheet;          /* the framebuffer's sheet (hg_remap_rect), 0 none */
static unsigned fb_gen, fb_h;

static int istable(const hg_image *t, unsigned k, const char *fn)
{
    if (!t || t->w != 256 || t->h != 1 || t->bpp != 8 || k >= t->n) {
        hg__fail(fn, "not a remap table (hg_remap_new), or no such table");
        return 0;
    }
    return 1;
}

hg_image *hg_remap_new(const unsigned char *tables, unsigned n)
{
    hg_image *t;
    unsigned k;

    if (n == 0 || n > 1024 || (tables && n > 255)) {
        hg__fail("hg_remap_new", "1-1024 tables (from bytes: 1-255)");
        return 0;
    }
    t = hg_image_new(256, 1, n);
    if (!t)
        return 0;
    for (k = 0; k < n; k++)
        hg_remap_set(t, k, tables ? tables + (k << 8) : 0);
    return t;
}

void hg_remap_set(hg_image *t, unsigned k, const unsigned char *table)
{
    unsigned char __far *d;
    unsigned i;

    if (!istable(t, k, "hg_remap_set"))
        return;
    if (hg__qn || hg__listrun)          /* (records may read it) */
        hg__cpu_sync();
    d = HG__PTR(t->addr + 256UL * k);   /* (256-byte aligned: inside one bank) */
    for (i = 0; i < 256; i++)
        d[i] = table ? table[i] : (unsigned char)i;
}

int hg_remap_hw(const hg_image *t)
{
    hz_sheetrec r;

    if (mode == 0 && hg__kind != HG__NONE && t && t->sheet) {
        /* one table record: refused (ENODEV: an older board or the blitter off; EINVAL: a
         * Horizon before 0.31) -> the CPU */
        memset(&r, 0, sizeof r);
        r.sheet = t->sheet;
        r.op = SH_TABLE;
        r.w = 256;
        r.h = 1;
        if (hz_sheet_draw(hg_win, 1, &r) < 0)
            mode = 2;
        else {
            mode = 1;
            hg__listrun = 1;
        }
    }
    return mode == 1;
}

/* the queue has room for a table record and a record of w x h in one call */
static void room(unsigned w, unsigned h)
{
    unsigned long px = (unsigned long)w * h;
    if (px < 3481)
        px = 3481;
    if (hg__qn > HG__Q - 2 || hg__qpix + 3481 + px > 460800UL)
        hg__submit(1);
}

/* table k of t loaded for the next record, unless the last table record queued is it and
 * lies in the call being made (the queue's last run, of sheet records) */
static void table(const hg_image *t, unsigned k)
{
    unsigned run;
    hz_sheetrec __far *r;

    if (hg__nruns && tab_at < hg__qn) {
        run = hg__runs[hg__nruns - 1];
        r = &hg__sq[tab_at];
        if ((run & 0x8000) && (run & 0x7FFF) <= tab_at && r->op == SH_TABLE &&
            r->sheet == t->sheet && r->sy == k && tab_sheet == t->sheet && tab_row == k)
            return;
    }
    if (!hg__nruns || hg__runkind != 1) {       /* a run of sheet records begins */
        hg__runs[hg__nruns++] = hg__qn | 0x8000;
        hg__runkind = 1;
    }
    tab_at = hg__qn;
    tab_sheet = t->sheet;
    tab_row = k;
    r = &hg__sq[hg__qn++];
    hz_far_set(r, 0, sizeof *r);
    r->sheet = t->sheet;
    r->op = SH_TABLE;
    r->sy = k;
    r->w = 256;
    r->h = 1;
    hg__qpix += 3481;
}

/* the blitter: the source (sx, sy) of sheet s, w x h, to (x, y) (screen coordinates) */
static void hw(unsigned s, unsigned key, unsigned sx, unsigned sy, unsigned w, unsigned h,
               int x, int y, const hg_image *t, unsigned k)
{
    room(w, h);
    table(t, k);
    hg__sheetq(key != HG_NONE ? SH_KEY | SH_REMAP : SH_COPY | SH_REMAP, s, key & 255, sx, sy,
               w, h, x, y);
}

/* the destination (x, y) w x h (screen coordinates) cut to the target, in framebuffer
 * coordinates; *cx, *cy what was cut at the left and the top. 0: nothing left */
static int clip(int *x, int *y, unsigned *w, unsigned *h, unsigned *cx, unsigned *cy)
{
    long x0 = (long)*x + hg__offx, y0 = (long)*y + hg__offy;
    long x1 = x0 + *w, y1 = y0 + *h;

    *cx = x0 < 0 ? (unsigned)-x0 : 0;
    *cy = y0 < hg__cly0 ? (unsigned)(hg__cly0 - y0) : 0;
    if (x0 < 0)
        x0 = 0;
    if (y0 < hg__cly0)
        y0 = hg__cly0;
    if (x1 > hg__clx1)
        x1 = hg__clx1;
    if (y1 > hg__cly1)
        y1 = hg__cly1;
    if (x1 <= x0 || y1 <= y0)
        return 0;
    *x = (int)x0;
    *y = (int)y0;
    *w = (unsigned)(x1 - x0);
    *h = (unsigned)(y1 - y0);
    return 1;
}

/* the CPU (full screen, 256 colours): w x h from src (rows sstride apart) through table k */
static void cpu(unsigned long src, unsigned sstride, unsigned key, unsigned w, unsigned h,
                int x, int y, const hg_image *t, unsigned k, const char *fn)
{
    unsigned cx, cy;

    if (hg__kind != HG__FULL || hg__four) {
        hg__fail(fn, "the CPU remaps only in full screen at 256 colours (the blitter: REV $0D)");
        return;
    }
    if (!clip(&x, &y, &w, &h, &cx, &cy))
        return;
    hg__cpu_sync();
    hg__remapmem(hg__fbaddr((unsigned)x, (unsigned)y), hg_fb_stride,
                 src + hg__umul(cy, sstride) + cx, sstride, w, h, key,
                 t->addr + 256UL * k);
}

void hg_draw_part_remap(const hg_image *img, unsigned sx, unsigned sy, unsigned w, unsigned h,
                        int x, int y, const hg_image *t, unsigned k)
{
    if (!img || img->bpp != 8) {
        hg__fail("hg_draw_part_remap", "no image, or not 256 colours");
        return;
    }
    if (!istable(t, k, "hg_draw_part_remap"))
        return;
    if (sx >= img->w || sy >= img->h * img->n)
        return;
    if (w > img->w - sx)
        w = img->w - sx;
    if (h > img->h * img->n - sy)
        h = img->h * img->n - sy;
    if (hg_remap_hw(t) && img->sheet && t->sheet && !hg__four)
        hw(img->sheet, img->key, sx, sy, w, h, x, y, t, k);
    else if (hg__kind == HG__FULL)
        cpu(img->addr + hg__umul(sy, img->stride) + sx, img->stride, img->key, w, h, x, y,
            t, k, "hg_draw_part_remap");
    else {
        hg__fail("hg_draw_part_remap", "a window remaps only by the blitter (REV $0D): "
                 "drawn as it is");
        hg_draw_part(img, sx, sy, w, h, x, y);
    }
}

void hg_draw_remap(const hg_image *img, unsigned frame, int x, int y, const hg_image *t,
                   unsigned k)
{
    if (!img || frame >= img->n) {
        hg__fail("hg_draw_remap", img ? "no such frame" : "no image (NULL)");
        return;
    }
    hg_draw_part_remap(img, 0, frame * img->h, img->w, img->h, x, y, t, k);
}

/* the framebuffer's sheet (made again when the framebuffer changed) -> its number, 0 none */
static unsigned fbsheet(void)
{
    hz_sheetnew sn;
    int s;

    if (fb_sheet && fb_gen == hg__fbgen)
        return fb_sheet;
    if (fb_sheet) {
        if (hg__qn || hg__listrun)
            hg__cpu_sync();
        hz_sheet_free(fb_sheet);        /* (EINVAL if it went with its bank: no matter) */
        fb_sheet = 0;
    }
    fb_gen = hg__fbgen;
    fb_h = hg_fb_rows > 1024 ? 1024 : hg_fb_rows;
    HZ_U24(sn.addr, HG__PTR(hg__fbbase));
    sn.zero = 0;
    sn.stride = hg_fb_stride;
    sn.w = hg_fb_stride;
    sn.h = fb_h;
    s = hz_sheet_new(&sn);
    if (s > 0 && s <= 32)
        fb_sheet = (unsigned char)s;
    return fb_sheet;
}

void hg_remap_rect(int sx, int sy, unsigned w, unsigned h, int x, int y, const hg_image *t,
                   unsigned k)
{
    long fx, fy;
    unsigned c, s;

    if (hg__kind != HG__FULL || hg__four) {
        hg__fail("hg_remap_rect", "full screen at 256 colours only");
        return;
    }
    if (!istable(t, k, "hg_remap_rect"))
        return;
    /* the source in framebuffer coordinates, cut to the framebuffer (the destination moves
     * with the cut) */
    fx = (long)sx + hg__offx;
    fy = (long)sy + hg__offy;
    if (fx < 0) {
        c = (unsigned)-fx;
        if (c >= w)
            return;
        w -= c;
        x += (int)c;
        fx = 0;
    }
    if (fy < 0) {
        c = (unsigned)-fy;
        if (c >= h)
            return;
        h -= c;
        y += (int)c;
        fy = 0;
    }
    if (fx >= (long)hg_fb_stride || fy >= (long)hg_fb_rows)
        return;
    if (w > hg_fb_stride - (unsigned)fx)
        w = hg_fb_stride - (unsigned)fx;
    if (h > hg_fb_rows - (unsigned)fy)
        h = hg_fb_rows - (unsigned)fy;
    if (hg_remap_hw(t) && t->sheet && (s = fbsheet()) != 0 && fy + h <= fb_h) {
        hw(s, HG_NONE, (unsigned)fx, (unsigned)fy, w, h, x, y, t, k);
        return;
    }
    cpu(hg__fbaddr((unsigned)fx, (unsigned)fy), hg_fb_stride, HG_NONE, w, h, x, y, t, k,
        "hg_remap_rect");
}
