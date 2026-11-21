/* hg_map.c - hgame: tile maps. Drawn whole (hg_map_draw, hg_map_image), or scrolling in
 * full screen (hg_map, hg_camera) as examples/deepdive does: the framebuffer is a ring of
 * tile slots (world tile (c, r) always in slot (c mod rc, r mod rr)), one column more and
 * one row more than the screen shows; Marga's scroll registers (horizontal and vertical
 * wrap) put the slots in place, and only the column or row of tiles coming into view is
 * drawn, in the frame's list (the vertical blank, with the scroll values). A panel above
 * or below the ring is shown by the split, never scrolling. */
#include <string.h>
#include "hg_int.h"

int hg_cam_x, hg_cam_y, hg_play_y, hg_panel_y;

int hg__fb_new(unsigned stride, unsigned rows);

static unsigned char *map;      /* the game's map, copied (hg_map_set writes it) */
static unsigned mw, mh, tw, th, rc, rr, playh, border;
static const hg_image *tiles;
static unsigned ltx, lty;       /* the first world column / row in the ring */
static unsigned char top;       /* the panel is at the top */

/* ---------------------------------------------------------------- not scrolling */

void hg_map_draw(const unsigned char *m, unsigned w, unsigned h, const hg_image *t,
                 int x, int y)
{
    unsigned c, r;
    const unsigned char *p = m;
    if (!m || !t) {
        hg__fail("hg_map_draw", "no map or no tiles");
        return;
    }
    for (r = 0; r < h; r++)
        for (c = 0; c < w; c++, p++)
            hg_draw(t, *p < t->n ? *p : 0, x + (int)(c * t->w), y + (int)(r * t->h));
}

void hg__blitmem(unsigned long dst, unsigned dstride, unsigned long src, unsigned sstride,
                 unsigned w, unsigned h, unsigned key);

void hg_map_image(hg_image *dst, const unsigned char *m, unsigned w, unsigned h,
                  const hg_image *t)
{
    static unsigned long fa[256];       /* each tile's address */
    unsigned c, r, k, n, cw, rh;
    unsigned long row, fs;
    const unsigned char *p = m;
    if (!dst || !m || !t || dst->bpp != 8 || t->bpp != 8) {
        hg__fail("hg_map_image", "no image, map or tiles (8 bpp)");
        return;
    }
    n = t->n > 256 ? 256 : t->n;
    fs = hg__umul(t->w, t->h);
    fa[0] = t->addr;
    for (k = 1; k < n; k++)
        fa[k] = fa[k - 1] + fs;
    if (hg__listrun) {
        hz_list_wait(0);
        hg__listrun = 0;
    }
    /* whole tiles only (the image is cut at the last whole one) */
    cw = dst->w / t->w;
    rh = (dst->h * dst->n) / t->h;
    if (w > cw)
        cw = w < cw ? w : cw;
    else
        cw = w;
    if (h < rh)
        rh = h;
    row = dst->addr;
    fs = hg__umul(t->h, dst->stride);
    for (r = 0; r < rh; r++, row += fs) {
        p = m + r * w;
        for (c = 0; c < cw; c++, p++)
            hg__blitmem(row + c * t->w, dst->stride, fa[*p < n ? *p : 0], t->stride, t->w,
                        t->h, t->key);
    }
}

/* ---------------------------------------------------------------- scrolling */

static unsigned cell(unsigned c, unsigned r)
{
    unsigned t;
    if (c >= mw || r >= mh)
        return border;
    t = map[r * mw + c];
    return t < tiles->n ? t : 0;
}

static void slot(unsigned c, unsigned r)
{
    int ox = hg__ox, oy = hg__oy;
    hg_origin(0, 0);
    hg_draw(tiles, cell(c, r), (int)((c % rc) * tw), (int)((r % rr) * th));
    hg_origin(ox, oy);
}

static void loadcol(unsigned c)
{
    unsigned r;
    for (r = lty; r < lty + rr; r++)
        slot(c, r);
}

static void loadrow(unsigned r)
{
    unsigned c;
    for (c = ltx; c < ltx + rc; c++)
        slot(c, r);
}

static void ringall(void)
{
    unsigned r;
    for (r = lty; r < lty + rr; r++)
        loadrow(r);
}

static void close_map(void)
{
    hg__scroll = 0;
    map = 0;
}

int hg_map(const unsigned char *m, unsigned w, unsigned h, const hg_image *t, int panel)
{
    unsigned ph, stride, cols, rows, split, size;
    unsigned long a;

    if (hg__kind != HG__FULL || hg__double || hg__mode == FS_640X4) {
        hg__fail("hg_map", "full screen at 256 colours, not HG_DOUBLE");
        return -1;
    }
    if (!m || !t || w == 0 || h == 0 || t->bpp != 8 || t->w < 8 || t->h < 8 ||
        (unsigned long)w * h > 65280UL) {
        hg__fail("hg_map", "a map (at most 65,280 cells) and 8 bpp tiles of 8 x 8 or more");
        return -1;
    }
    ph = panel < 0 ? (unsigned)-panel : (unsigned)panel;
    if (ph >= hg_h / 2 || (hg__mode == FS_320X8 && (ph & 1))) {
        hg__fail("hg_map", "the panel: less than half the screen (320 x 180: even rows)");
        return -1;
    }
    tw = t->w;
    th = t->h;
    playh = hg_h - ph;
    cols = (hg_w + tw - 1) / tw + 1;                /* one column more than the screen */
    while ((cols * tw) & 15)
        ++cols;
    stride = cols * tw;
    rows = (playh + th - 1) / th + 1;
    if (stride > 4096 || rows * th + ph > 1024) {
        hg__fail("hg_map", "tiles too large for the ring");
        return -1;
    }
    size = w * h;
    a = hg__farmem(size);
    if (!a) {
        hg__fail("hg_map", "no far memory for the map");
        return -1;
    }
    if (hg__listrun) {
        hz_list_wait(0);
        hg__listrun = 0;
    }
    hg__qn = 0;
    hg__qpix = 0;
    hg__nruns = 0;
    if (hg__fb_new(stride, rows * th + ph))
        return -1;
    map = HG__PTR(a);
    hz_far_copy(map, m, size);
    mw = w;
    mh = h;
    tiles = t;
    rc = cols;
    rr = rows;
    top = (unsigned char)(panel > 0);
    hg_panel_y = (int)(rows * th);
    hg_play_y = top ? (int)ph : 0;
    hg_cam_x = hg_cam_y = 0;
    ltx = lty = 0;
    split = top ? ph : playh;
    if (hg__mode == FS_320X8)
        split *= 2;                             /* Marga counts 360 lines */
    memset(&hg__scr, 0, sizeof hg__scr);
    hg__scr.vheight = rows * th;
    hg__scr.ctrl = FSC_HWRAP;
    if (ph) {
        hg__scr.split = split;
        hg__scr.ctrl |= FSC_SPLIT;
        if (top)
            hg__scr.y = rows * th;              /* first set: the panel */
        else
            hg__scr.y2 = rows * th;             /* second set: the panel */
    }
    hg__scr_dirty = 1;
    hg__scroll = 1;
    hg__hook_close_map = close_map;
    /* the panel's rows cleared, every slot drawn */
    {
        int ox = hg__ox, oy = hg__oy;
        hg_origin(0, 0);
        if (ph)
            hg_fill(0, (int)(rows * th), stride, ph, 0);
        hg_origin(ox, oy);
    }
    ringall();
    if (!hg__began) {
        hz_fs_scroll(&hg__scr);
        hg__scr_dirty = 0;
        hg_flush(1);
    }
    return 0;
}

void hg_camera(int x, int y)
{
    int maxx, maxy;
    unsigned tcx, tcy;

    if (!hg__scroll) {
        hg__fail("hg_camera", "hg_map first");
        return;
    }
    maxx = (int)(mw * tw) - (int)hg_w;
    maxy = (int)(mh * th) - (int)playh;
    if (x > maxx)
        x = maxx;
    if (y > maxy)
        y = maxy;
    if (x < 0)
        x = 0;
    if (y < 0)
        y = 0;
    if (x == hg_cam_x && y == hg_cam_y && !hg__scr_dirty)
        return;
    hg_cam_x = x;
    hg_cam_y = y;
    tcx = (unsigned)x / tw;
    tcy = (unsigned)y / th;
    if (tcx + rc <= ltx || ltx + rc <= tcx || tcy + rr <= lty || lty + rr <= tcy) {
        ltx = tcx;                              /* a jump: the whole ring again */
        lty = tcy;
        ringall();
    } else {
        while (ltx < tcx) {                     /* columns first (the old rows) */
            ++ltx;
            loadcol(ltx + rc - 1);
        }
        while (ltx > tcx) {
            --ltx;
            loadcol(ltx);
        }
        while (lty < tcy) {                     /* then rows (the new columns) */
            ++lty;
            loadrow(lty + rr - 1);
        }
        while (lty > tcy) {
            --lty;
            loadrow(lty);
        }
    }
    if (top || !(hg__scr.ctrl & FSC_SPLIT)) {
        if (top) {
            hg__scr.x2 = (unsigned)x % (rc * tw);
            hg__scr.y2 = (unsigned)y % (rr * th);
        } else {
            hg__scr.x = (unsigned)x % (rc * tw);
            hg__scr.y = (unsigned)y % (rr * th);
        }
    } else {
        hg__scr.x = (unsigned)x % (rc * tw);    /* a panel at the bottom: set 1 plays */
        hg__scr.y = (unsigned)y % (rr * th);
    }
    hg__scr_dirty = 1;
}

void hg_map_set(unsigned c, unsigned r, unsigned t)
{
    if (!hg__scroll) {
        hg__fail("hg_map_set", "hg_map first");
        return;
    }
    if (c >= mw || r >= mh)
        return;
    map[r * mw + c] = (unsigned char)t;
    if (c >= ltx && c < ltx + rc && r >= lty && r < lty + rr)
        slot(c, r);
}

unsigned hg_map_get(unsigned c, unsigned r)
{
    if (!hg__scroll)
        return 0;
    return cell(c, r);
}

void hg_map_border(unsigned t)
{
    border = t;
}
