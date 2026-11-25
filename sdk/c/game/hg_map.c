/* hg_map.c - hgame: tile maps. Drawn whole (hg_map_draw, hg_map_image), or scrolling in
 * full screen (hg_map, hg_camera) as examples/deepdive does: the framebuffer is a ring of
 * tile slots (world tile (c, r) always in slot (c mod rc, r mod rr)), one column more and
 * one row more than the screen shows; Marga's scroll registers (horizontal and vertical
 * wrap) put the slots in place, and only the column or row of tiles coming into view is
 * drawn, in the frame's list (the vertical blank, with the scroll values). A panel above
 * or below the ring is shown by the split, never scrolling. hg_map16: the same ring for
 * 16-bit tile numbers (the game's map, not copied, or its function) drawn from a sheet. */
#include <string.h>
#include "hg_int.h"

int hg_cam_x, hg_cam_y, hg_play_y, hg_panel_y;

int hg__fb_new(unsigned stride, unsigned rows);

static unsigned char __far *map;      /* the game's map, copied (hg_map_set writes it) */
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

/* map16: 16-bit tile numbers in the game's far memory (not copied), each tile a tw x th
 * rectangle of a sheet image (tile k at column k mod tcols, row k / tcols), drawn with
 * hg_draw_part; or the cells from the game's function (hg_map_cells) */
static unsigned char kind16;
static unsigned __far *map16;
static unsigned (*cellfn)(unsigned c, unsigned r);
static unsigned ntiles, tcols;
static unsigned char tsh = 0xFF, wsh = 0xFF, hsh = 0xFF;    /* log2 of tcols, tw, th */
static unsigned __far *shown;   /* the tile each slot holds (hg_map_refresh) */
static unsigned shown_cap;      /* its slots */
static unsigned refresh_row;    /* the row of the view hg_map_refresh goes on from */
static unsigned char recop;     /* SH_COPY or SH_KEY (hg__mapwalk) */
static unsigned char fast;      /* hg__mapwalk can draw this map's tiles */

/* a run of cells for hg__mapwalk (hg_mapw.s: the offsets are its) */
struct hg__walk {
    unsigned p, pbank, pstep;           /* the first cell's map word, to the next one */
    unsigned sh, shbank, shstep;        /* its slot's word in shown */
    unsigned n, x, y, dx, dy;           /* cells; the first slot's place, to the next */
    unsigned ntiles, tmask, tsh, wsh, hsh, w, h, op, sheet, key;
    unsigned long px;                   /* a record's pixels in the count */
    unsigned diff, drawn;               /* only the changed tiles; tiles queued */
} hg__mw;
void hg__mapwalk(void);

static unsigned char log2of(unsigned v)
{
    unsigned char k = 0;
    if (!v || (v & (v - 1)))
        return 0xFF;
    while (v > 1) {
        v >>= 1;
        ++k;
    }
    return k;
}

/* the tile of cell (c, r), its index mi in the map (r * mw + c: kept by the callers, no
 * multiply a cell) */
static unsigned fetch(unsigned c, unsigned r, unsigned mi)
{
    unsigned t;
    if (c >= mw || r >= mh)
        t = border;
    else if (!kind16)
        t = map[mi];
    else if (cellfn)
        t = cellfn(c, r);
    else
        t = map16[mi];
    return t < ntiles ? t : 0;
}

static unsigned cell(unsigned c, unsigned r)
{
    return fetch(c, r, c < mw && r < mh ? r * mw + c : 0);
}

/* the tile t into the slot at (x, y) of the ring's framebuffer (the origin at 0, 0), slot
 * index si */
static void put(unsigned x, unsigned y, unsigned si, unsigned t)
{
    unsigned sx, sy;
    shown[si] = t;
    if (!kind16) {
        hg_draw(tiles, t, (int)x, (int)y);
        return;
    }
    if (tsh != 0xFF) {
        sx = t & (tcols - 1);
        sy = t >> tsh;
    } else {
        sx = t % tcols;
        sy = t / tcols;
    }
    sx = wsh != 0xFF ? sx << wsh : sx * tw;
    sy = hsh != 0xFF ? sy << hsh : sy * th;
    hg_draw_part(tiles, sx, sy, tw, th, (int)x, (int)y);
}

/* n cells from (c, r) into their slots: down a column (down 1) or along a row (0); diff:
 * only those whose tile differs from the slot's. -> the tiles drawn */
static unsigned cells(unsigned c, unsigned r, unsigned n, unsigned char down,
                      unsigned char diff)
{
    unsigned sc = c % rc, sr = r % rr, si = sr * rc + sc, x = sc * tw, y = sr * th;
    unsigned mi = c < mw && r < mh ? r * mw + c : 0, k, lim, t, drawn = 0;
    unsigned long a;
    hg__mw.diff = diff;
    hg__mw.drawn = 0;
    /* the common case (the map's words, a sheet, power-of-two sizes): runs of cells inside
     * the map and inside the ring by hg__mapwalk (hg_mapw.s); the cells outside the map
     * (the border) below */
    while (n && fast && !cellfn && c < mw && r < mh) {
        k = n;
        lim = down ? mh - r : mw - c;
        if (k > lim)
            k = lim;
        lim = down ? rr - sr : rc - sc;
        if (k > lim)
            k = lim;
        a = (unsigned long)(map16 + mi);
        hg__mw.p = (unsigned)a;
        hg__mw.pbank = (unsigned)(a >> 16);
        a = (unsigned long)(shown + si);
        hg__mw.sh = (unsigned)a;
        hg__mw.shbank = (unsigned)(a >> 16);
        hg__mw.n = k;
        hg__mw.x = x;
        hg__mw.y = y;
        n -= k;
        if (down) {
            hg__mw.pstep = mw * 2;
            hg__mw.shstep = rc * 2;
            hg__mw.dx = 0;
            hg__mw.dy = th;
            hg__mapwalk();
            r += k;
            mi += k * mw;
            sr += k;
            si += k * rc;
            y += k * th;
            if (sr == rr) {
                sr = 0;
                si = sc;
                y = 0;
            }
        } else {
            hg__mw.pstep = 2;
            hg__mw.shstep = 2;
            hg__mw.dx = tw;
            hg__mw.dy = 0;
            hg__mapwalk();
            c += k;
            mi += k;
            sc += k;
            si += k;
            x += k * tw;
            if (sc == rc) {
                sc = 0;
                si -= rc;
                x = 0;
            }
        }
    }
    for (; n; n--) {
        t = fetch(c, r, mi);
        if (!diff || shown[si] != t) {
            put(x, y, si, t);
            ++drawn;
        }
        if (down) {
            ++r;
            mi += mw;
            si += rc;
            y += th;
            if (++sr == rr) {
                sr = 0;
                si = sc;
                y = 0;
            }
        } else {
            ++c;
            ++mi;
            ++si;
            x += tw;
            if (++sc == rc) {
                sc = 0;
                si -= rc;
                x = 0;
            }
        }
    }
    return drawn + hg__mw.drawn;
}

static void loadcol(unsigned c)
{
    cells(c, lty, rr, 1, 0);
}

static void loadrow(unsigned r)
{
    cells(ltx, r, rc, 0, 0);
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
    map16 = 0;
    shown = 0;
    shown_cap = 0;
}

/* the ring and its framebuffer for tiles of tw x th (hg_map, hg_map16) */
static int ring(const char *fn, int panel)
{
    unsigned ph, stride, cols, rows, split;
    unsigned long a;

    hg__scroll = 0;                     /* (until the new ring is made: no map on failure) */
    ph = panel < 0 ? (unsigned)-panel : (unsigned)panel;
    if (ph >= hg_h / 2 || (hg__mode == FS_320X8 && (ph & 1))) {
        hg__fail(fn, "the panel: less than half the screen (320 x 180: even rows)");
        return -1;
    }
    playh = hg_h - ph;
    cols = (hg_w + tw - 1) / tw + 1;                /* one column more than the screen */
    while ((cols * tw) & 15)
        ++cols;
    stride = cols * tw;
    rows = (playh + th - 1) / th + 1;
    if (stride > 4096 || rows * th + ph > 1024) {
        hg__fail(fn, "tiles too large for the ring");
        return -1;
    }
    if (cols * rows > shown_cap) {
        a = hg__farmem((unsigned long)cols * rows * 2);
        if (!a) {
            hg__fail(fn, "no far memory for the ring");
            return -1;
        }
        shown = (unsigned __far *)HG__PTR(a);
        shown_cap = cols * rows;
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
    wsh = log2of(tw);
    hsh = log2of(th);
    rc = cols;
    rr = rows;
    top = (unsigned char)(panel > 0);
    hg_panel_y = (int)(rows * th);
    hg_play_y = top ? (int)ph : 0;
    hg_cam_x = hg_cam_y = 0;
    ltx = lty = 0;
    refresh_row = 0;
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
        ringall();
        hg_origin(ox, oy);
    }
    if (!hg__began) {
        hz_fs_scroll(&hg__scr);
        hg__scr_dirty = 0;
        hg_flush(1);
    }
    return 0;
}

static int full_ok(const char *fn)
{
    if (hg__kind != HG__FULL || hg__double || hg__mode == FS_640X4) {
        hg__fail(fn, "full screen at 256 colours, not HG_DOUBLE");
        return 0;
    }
    return 1;
}

int hg_map(const unsigned char *m, unsigned w, unsigned h, const hg_image *t, int panel)
{
    unsigned size;
    unsigned long a;

    if (!full_ok("hg_map"))
        return -1;
    if (!m || !t || w == 0 || h == 0 || t->bpp != 8 || t->w < 8 || t->h < 8 ||
        (unsigned long)w * h > 65280UL) {
        hg__fail("hg_map", "a map (at most 65,280 cells) and 8 bpp tiles of 8 x 8 or more");
        return -1;
    }
    size = w * h;
    a = hg__farmem(size);
    if (!a) {
        hg__fail("hg_map", "no far memory for the map");
        return -1;
    }
    map = HG__PTR(a);
    hz_far_copy(map, m, size);
    kind16 = 0;
    fast = 0;
    map16 = 0;
    mw = w;
    mh = h;
    tiles = t;
    tw = t->w;
    th = t->h;
    ntiles = t->n;
    return ring("hg_map", panel);
}

int hg_map16(unsigned __far *m, unsigned w, unsigned h, const hg_image *sheet, unsigned tilew,
             unsigned tileh, int panel)
{
    unsigned long rowsall, cols;

    if (!full_ok("hg_map16"))
        return -1;
    if ((!m && !cellfn) || !sheet || w == 0 || h == 0 || sheet->bpp != 8 || tilew < 8 ||
        tileh < 8 || tilew > sheet->w || tileh > (unsigned long)sheet->h * sheet->n ||
        (unsigned long)w * h > 32768UL ||
        (unsigned long)w * tilew > 32767UL || (unsigned long)h * tileh > 32767UL ||
        (m && ((unsigned long)m & 0xFFFFUL) + (unsigned long)w * h * 2 > 65536UL)) {
        hg__fail("hg_map16", "a map of at most 32,768 cells in one bank (or hg_map_cells),"
                 " an 8 bpp sheet, tiles of 8 x 8 or more");
        return -1;
    }
    rowsall = (unsigned long)sheet->h * sheet->n;
    kind16 = 1;
    map16 = m;
    map = 0;
    mw = w;
    mh = h;
    tiles = sheet;
    tw = tilew;
    th = tileh;
    tcols = sheet->w / tilew;
    cols = (unsigned long)tcols * (rowsall / tileh);
    ntiles = cols > 65535UL ? 65535U : (unsigned)cols;
    tsh = log2of(tcols);
    recop = sheet->key == HG_NONE ? SH_COPY : SH_KEY;
    fast = sheet->sheet && tsh != 0xFF && log2of(tilew) != 0xFF && log2of(tileh) != 0xFF;
    hg__mw.ntiles = ntiles;
    hg__mw.tmask = tcols - 1;
    hg__mw.tsh = tsh;
    hg__mw.wsh = log2of(tilew);
    hg__mw.hsh = log2of(tileh);
    hg__mw.w = tilew;
    hg__mw.h = tileh;
    hg__mw.op = recop;
    hg__mw.sheet = sheet->sheet;
    hg__mw.key = sheet->key & 255;
    hg__mw.px = tilew < 60 && tileh < 60 ? 3481UL : (unsigned long)tilew * tileh;
    return ring("hg_map16", panel);
}

void hg_map_cells(unsigned (*fn)(unsigned c, unsigned r))
{
    cellfn = fn;
}

unsigned hg_map_refresh(unsigned rows)
{
    unsigned c0, c1, r0, r1, nr, n = 0;
    int ox, oy;

    if (!hg__scroll) {
        hg__fail("hg_map_refresh", "hg_map or hg_map16 first");
        return 0;
    }
    c0 = (unsigned)hg_cam_x / tw;
    c1 = ((unsigned)hg_cam_x + hg_w - 1) / tw;
    r0 = (unsigned)hg_cam_y / th;
    r1 = ((unsigned)hg_cam_y + playh - 1) / th;
    nr = r1 - r0 + 1;
    if (!rows || rows > nr)
        rows = nr;
    if (refresh_row >= nr)
        refresh_row = 0;
    ox = hg__ox;
    oy = hg__oy;
    hg_origin(0, 0);
    while (rows--) {
        n += cells(c0, r0 + refresh_row, c1 - c0 + 1, 0, 1);
        if (++refresh_row >= nr)
            refresh_row = 0;
    }
    hg_origin(ox, oy);
    return n;
}

void hg_camera(int x, int y)
{
    int maxx, maxy, ox, oy;
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
    ox = hg__ox;
    oy = hg__oy;
    hg_origin(0, 0);
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
    hg_origin(ox, oy);
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
    if (!kind16)
        map[r * mw + c] = (unsigned char)t;
    else if (!cellfn)
        map16[r * mw + c] = t;
    if (c >= ltx && c < ltx + rc && r >= lty && r < lty + rr) {
        int ox = hg__ox, oy = hg__oy;
        hg_origin(0, 0);
        cells(c, r, 1, 1, 0);
        hg_origin(ox, oy);
    }
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
