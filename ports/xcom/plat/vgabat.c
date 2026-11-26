/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The VGA prototype's battle view in C: upstream's src/vgaasm.asm entries
   0-8 (the 8-bit back buffer: sprite blits in tools/vgasprite.py's
   formats, clearing, the present to A000, the scroll, the cursor's kept
   box, the palette), 22 (the selected unit's arrow), 23 (smoke, fire and
   flares: the dithered overlay), 24 (night), 25 (tracer dots), 26 (the
   smoke and fire pictures' redraw: not ported, see below). Build with
   -DXD_HAVE_VGABAT (plat/asm.c then leaves its stubs out).

   The back buffer is upstream's: segment g_bufseg, 320 x VIEW_H bytes from
   offset 0. The callers pass CGA offsets (y * 80 + x / 4: a quarter of the
   VGA offset, 16-bit wrap for boxes off the top or left); every offset
   into the buffer is taken modulo 65536 as the assembly's 16-bit
   registers do (unsigned short), so a box hanging off the top writes only
   its visible rows, exactly as upstream.

   The night lights (vgaasm.asm "Night lights", lit_present): each 16 x 8
   cell of the view through its level's table, the levels from
   engine/src/vlit.c (the light sources' model in portable C), shown here
   (night_present). Not ported: vshift (on a scroll by whole cells
   upstream moves the screen and the levels with it; here the caller's
   full present after a scroll shows the view, and the levels are 360
   look-ups of vlit.c's light map). DOS's smoke and fire pictures (fxpic,
   SMOKEV.PAK, loaded by vga_smoke_load) and their animation step
   (pics_next) are entry 23's and 26's, below.

   A platform with a blitter draws the buffer itself (plat.h "the battle
   view": the Atari816, horizon/hz_bb.c); every entry asks it first and
   falls back on the C here, which stays the reference (the host). */
#include "xcompat.h"
#include "plat.h"
#include "gfx.h"
#include "input.h"
#include "render.h"
#include "vga.h"
#include "fx_in.h"
#include "map.h"
#include "vlit.h"
#include <stdio.h>

#define ROW     320u
#define BYTES   (ROW * VIEW_H)          /* 46080 */


typedef unsigned short u16;

/* The buffer of segment seg, offset 0. */
#define BUF(seg)    ((unsigned char far *)xd_mkfp_raw(seg, 0))

static u16 lx, rx, vtop, vbot;          /* V_LX, V_RX, V_TOP, V_BOT */
static unsigned char save_box[32 * 40]; /* SAVE: the cursor's box */

/* clip_vars: wmask's visible 8-pixel columns (contiguous) to [lx, rx). */
static void clip_vars(unsigned top, unsigned bottom, unsigned wmask)
{
    int b;

    vtop = (u16)top;
    vbot = (u16)bottom;
    wmask &= 15;
    lx = 32;
    rx = 0;
    for (b = 0; b < 4; b++)
        if (wmask >> b & 1) {
            if (lx == 32)
                lx = (u16)(b * 8);
            rx = (u16)((b + 1) * 8);
        }
}

/* HEADER: the sprite's first row and row count; the VGA offset of its
   first row (16-bit). */
static u16 header(const unsigned char far *s, unsigned dest, unsigned *first, unsigned *rows)
{
    *first = s[0];
    *rows = s[1];
    return (u16)(s[0] * ROW + (u16)(dest << 2));
}

/* every 32nd sprite the platform's clock and input (plat_busy_tick: a full redraw is
   100-250 ms of them) */
static unsigned char spr_ticks;
#define SPRITE_TICK() do { if (!(++spr_ticks & 31)) plat_busy_tick(); } while (0)

/* ---- 0: masked (transparent spans), unclipped */
void __cdecl blitc_masked(const void *spr, unsigned bufseg, unsigned dest)
{
    const unsigned char far *s = (const unsigned char far *)spr;
    unsigned char far *buf;
    unsigned first, rows, n, x, len;
    u16 o;

    SPRITE_TICK();
    if (plat_bb_sprite(s, 0, dest, 0, 0xFFFF, 0, 0xFFFF))
        return;
    buf = BUF(bufseg);
    o = header(s, dest, &first, &rows);
    s += 2;
    for (; rows; rows--, o = (u16)(o + ROW)) {
        n = *s++;
        for (; n; n--) {
            x = s[0];
            len = s[1];
            s += 2;
            if (x & 0x80)
                s++;                    /* the filler byte */
            x &= 0x7F;
            {
                u16 d = (u16)(o + x);
                while (len--) {
                    buf[d] = *s++;
                    d = (u16)(d + 1);
                }
            }
        }
    }
}

/* CLIPSPAN: the span at x (len bytes, data s) clipped to [lx, rx), to row o. */
static void clipspan(unsigned char far *buf, u16 o, unsigned x, unsigned len,
                     const unsigned char far *s)
{
    unsigned end = x + len, start = x;

    if (end > rx)
        end = rx;
    if (start < lx)
        start = lx;
    if ((int)end - (int)start <= 0)
        return;
    s += start - x;
    {
        u16 d = (u16)(o + start);
        unsigned n = end - start;
        while (n--) {
            buf[d] = *s++;
            d = (u16)(d + 1);
        }
    }
}

/* ---- 1: masked, clipped to rows [top, bottom) and columns [lx, rx) */
void __cdecl blitc_masked_clip(const void *spr, unsigned bufseg, unsigned dest,
                               unsigned top, unsigned bottom, unsigned wmask)
{
    const unsigned char far *s = (const unsigned char far *)spr;
    unsigned char far *buf;
    unsigned first, rows, n, x, len, row;
    u16 o;

    clip_vars(top, bottom, wmask);
    SPRITE_TICK();
    if (plat_bb_sprite(s, 0, dest, vtop, vbot, lx, rx))
        return;
    buf = BUF(bufseg);
    o = header(s, dest, &first, &rows);
    s += 2;
    for (row = first; rows; rows--, row++, o = (u16)(o + ROW)) {
        int hidden = row < vtop || row >= vbot;
        n = *s++;
        for (; n; n--) {
            x = s[0];
            len = s[1];
            s += 2;
            if (x & 0x80)
                s++;
            x &= 0x7F;
            if (!hidden)
                clipspan(buf, o, x, len, s);
            s += len;
        }
    }
}

/* ---- 2: OR format (ground floors on a cleared area), unclipped */
void __cdecl blitc_or(const void *spr, unsigned bufseg, unsigned dest)
{
    const unsigned char far *s = (const unsigned char far *)spr;
    unsigned char far *buf;
    unsigned first, rows, x, n;
    u16 o;

    SPRITE_TICK();
    if (plat_bb_sprite(s, 1, dest, 0, 0xFFFF, 0, 0xFFFF))
        return;
    buf = BUF(bufseg);
    o = header(s, dest, &first, &rows);
    s += 2;
    for (; rows; rows--, o = (u16)(o + ROW)) {
        u16 d;
        x = s[0];
        n = (unsigned)s[1] * 2;
        s += 2;
        d = (u16)(o + x);
        while (n--) {
            buf[d] = *s++;
            d = (u16)(d + 1);
        }
    }
}

/* ---- 3: OR format, clipped */
void __cdecl blitc_or_clip(const void *spr, unsigned bufseg, unsigned dest,
                           unsigned top, unsigned bottom, unsigned wmask)
{
    const unsigned char far *s = (const unsigned char far *)spr;
    unsigned char far *buf;
    unsigned first, rows, x, n, row;
    u16 o;

    clip_vars(top, bottom, wmask);
    SPRITE_TICK();
    if (plat_bb_sprite(s, 1, dest, vtop, vbot, lx, rx))
        return;
    buf = BUF(bufseg);
    o = header(s, dest, &first, &rows);
    s += 2;
    for (row = first; rows; rows--, row++, o = (u16)(o + ROW)) {
        x = s[0];
        n = (unsigned)s[1] * 2;
        s += 2;
        if (!(row < vtop || row >= vbot))
            clipspan(buf, o, x, n, s);  /* (rows of even columns and lengths) */
        s += n;
    }
}

/* cells: the VGA offset of (CGA byte col, row) and the row's bytes. */
#define CELL_OFF(col, row)  ((u16)((row) * ROW + ((col) << 2)))

static unsigned clear_y0, clear_y1;     /* V_CY0, V_CY1 (the rows redrawn) */

/* ---- 4: clear cells of the buffer */
void __cdecl bufc_clear_rect(unsigned bufseg, unsigned col, unsigned row, unsigned cols,
                             unsigned rows)
{
    unsigned char far *buf = BUF(bufseg);
    u16 d = CELL_OFF(col, row);
    unsigned w = cols * 4, i;

    clear_y0 = row;
    clear_y1 = row + rows;
    if (plat_bb_fill(d, w, rows, 0))
        return;
    for (; rows; rows--, d = (u16)(d + ROW))
        for (i = 0; i < w; i++)
            buf[(u16)(d + i)] = 0;
}

/* ---- the night lights: the cells (vlit.h) through their levels' tables
   (vgaasm.asm mktab: OpenXcom's StandardShade, index + level in its block of
   16, at most the block's last; 0 stays 0; level 0 the identity) */
static unsigned char far tabs[16 * 256];
static unsigned char tabs_ok;
static unsigned char far shown[VL_CELLS];       /* the level each cell is shown at, 0xFF:
                                                   not shown (vgaasm.asm AUX's low nibble) */
#define NREC    (VL_CELLS + 16 + 8)             /* copies, tables, tables again in a new call */
static PlatRec far recs[NREC];                  /* one present's records */
static unsigned short far work[4 * VL_CELLS + 80];  /* the runs, their order by level, the joins */
unsigned char g_lit_sheet[2];                   /* the platform's sheets (plat.h) */
unsigned long g_lit_recs, g_lit_presents;       /* (BENCH: records, night presents) */

static void mktabs(void)
{
    unsigned l, b, i;

    for (l = 0; l < 16; l++)
        for (b = 0; b < 256; b += 16)
            for (i = 0; i < 16; i++)
                tabs[l * 256 + b + i] = (unsigned char)(i + l < 16 ? b + i + l : b + 15);
    for (l = 0; l < 16; l++)
        tabs[l * 256] = 0;
    tabs_ok = 1;
}

int vga_lit_shown(unsigned cell)
{
    if (!g_vshade)
        return 0;
    return cell < VL_CELLS && shown[cell] < 16 ? shown[cell] : -1;
}

/* The records of a night present (vgaasm.asm lit_present's mark and draw):
   the rectangle x0..x1, y0..y1 (pixels) of the view; all: every cell (the
   levels changed). A cell whose level is not the one shown is shown whole,
   at its level; the rectangle's other cells in the rectangle. A row's
   neighbours of one level and height make a run (wk: 3 words a run, x, w,
   y | h << 8 | level << 12); the runs by level (row by row within one: wk
   from 3 * VL_CELLS, their places); a run right under the last record of
   its level that starts at its column (wk from 4 * VL_CELLS, by x / 4)
   with its width joins it, else it is a record: level 0 a plain copy, the
   others remapped copies after a table record (PR_TABLE, sy the level)
   where the level changes and at the start of every 128 records (a call
   of the platform's: its table is the call's). *fl: 1 cells shown outside
   the rectangle, 2 among them in columns 18-19 (the panel's markers). The
   Atari816 does it in assembly (horizon/hz_lit.s hz_lit_recs, the same
   records; this C is the host's, the reference). */
#define WK_RUNS 0
#define WK_SORT (3 * VL_CELLS)
#define WK_JX   (4 * VL_CELLS)                  /* this level's last record at x / 4 */
#define WK_N    (4 * VL_CELLS + 80)

unsigned lit_recs(PlatRec far *o, const unsigned char far *lev, unsigned char far *sh,
                  unsigned short far *wk, unsigned x0, unsigned y0, unsigned x1, unsigned y1,
                  unsigned all, unsigned sheets, unsigned far *fl)
{
    unsigned c0, c1, r0, r1, r, c, i, k, n = 0, cnt[16], f = 0, cur, gl, open;

    if (all) {
        c0 = r0 = 0;
        c1 = VL_COLS;
        r1 = VL_ROWS;
    } else {
        c0 = x0 >> 4;
        c1 = (x1 + 15) >> 4;
        r0 = y0 >> 3;
        r1 = (y1 + 7) >> 3;
    }
    for (i = 0; i < 16; i++)
        cnt[i] = 0;
    for (r = r0; r < r1; r++)
        for (c = c0, open = 0; c < c1; c++) {
            unsigned cell = r * VL_COLS + c, l = lev[cell], ax = c * 16, ay = r * 8, aw = 16,
                ah = 8, whole, yhl;
            whole = l != sh[cell];
            if (!whole && !(ax < x1 && ax + 16 > x0 && ay < y1 && ay + 8 > y0)) {
                open = 0;
                continue;
            }
            if (!whole) {
                if (ax < x0) {
                    aw -= x0 - ax;
                    ax = x0;
                }
                if (ax + aw > x1)
                    aw = x1 - ax;
                if (ay < y0) {
                    ah -= y0 - ay;
                    ay = y0;
                }
                if (ay + ah > y1)
                    ah = y1 - ay;
            } else if (ax < x0 || ax + 16 > x1 || ay < y0 || ay + 8 > y1) {
                f |= 1;
                if (c >= 18)
                    f |= 2;
            }
            sh[cell] = (unsigned char)l;
            yhl = ay | ah << 8 | l << 12;
            if (open && wk[WK_RUNS + 3 * n - 1] == yhl
                && wk[WK_RUNS + 3 * n - 3] + wk[WK_RUNS + 3 * n - 2] == ax) {
                wk[WK_RUNS + 3 * n - 2] += (unsigned short)aw;
                continue;
            }
            wk[WK_RUNS + 3 * n] = (unsigned short)ax;
            wk[WK_RUNS + 3 * n + 1] = (unsigned short)aw;
            wk[WK_RUNS + 3 * n + 2] = (unsigned short)yhl;
            n++;
            cnt[l]++;
            open = 1;
        }
    for (i = k = 0; i < 16; i++) {
        unsigned m = cnt[i];
        cnt[i] = k;
        k += m;
    }
    for (i = 0; i < n; i++)
        wk[WK_SORT + cnt[wk[WK_RUNS + 3 * i + 2] >> 12]++] = (unsigned short)(3 * i);
    k = 0;
    cur = gl = 0xFFFF;
    for (i = 0; i < n; i++) {
        unsigned e = wk[WK_SORT + i], ax = wk[WK_RUNS + e], aw = wk[WK_RUNS + e + 1],
            yhl = wk[WK_RUNS + e + 2], ay = yhl & 255, ah = yhl >> 8 & 15, l = yhl >> 12, j;
        PlatRec far *p;
        if (l != gl) {
            gl = l;
            for (j = 0; j < 80; j++)
                wk[WK_JX + j] = 0xFFFF;
        } else if ((j = wk[WK_JX + (ax >> 2)]) != 0xFFFF) {
            /* under this level's last record at these columns: joined */
            p = &o[j];
            if (p->w == aw && p->y + p->h == ay) {
                p->h += ah;
                continue;
            }
        }
        if (!(k & 127))
            cur = 0xFFFF;
        if (l && cur != l) {
            for (;;) {
                p = &o[k++];
                p->sheet = (unsigned char)(sheets >> 8);
                p->op = PR_TABLE;
                p->c = p->zero = 0;
                p->sx = 0;
                p->sy = (unsigned short)l;
                p->w = 256;
                p->h = 1;
                p->x = p->y = 0;
                if (k & 127)
                    break;
                /* (it ended a call: again at the next one's start) */
            }
            cur = l;
        }
        p = &o[k++];
        p->sheet = (unsigned char)sheets;
        p->op = (unsigned char)(l ? PR_COPY | PR_REMAP : PR_COPY);
        p->c = p->zero = 0;
        p->sx = (unsigned short)ax;
        p->sy = (unsigned short)ay;
        p->w = (unsigned short)aw;
        p->h = (unsigned short)ah;
        p->x = (short)ax;
        p->y = (short)ay;
        wk[WK_JX + (ax >> 2)] = (unsigned short)(k - 1);
    }
    *fl = f;
    return k;
}

#if defined(__CC816__)
unsigned hz_lit_recs(PlatRec far *o, const unsigned char far *lev, unsigned char far *sh,
                     unsigned short far *wk, unsigned x0, unsigned y0, unsigned x1, unsigned y1,
                     unsigned all, unsigned sheets, unsigned far *fl);
#if defined(LITCHECK)
/* -DLITCHECK: the assembly against the C on every present (the console says where
   they differ) */
static PlatRec far recs2[NREC];
static unsigned char far shown2[VL_CELLS];
static unsigned recs_check(PlatRec far *o, unsigned x0, unsigned y0, unsigned x1, unsigned y1,
                           unsigned all, unsigned sheets, unsigned far *fl)
{
    static unsigned bad;
    unsigned n, n2, fl2;

    memcpy(shown2, shown, VL_CELLS);
    n = hz_lit_recs(o, g_vl_lev, shown, work, x0, y0, x1, y1, all, sheets, fl);
    n2 = lit_recs(recs2, g_vl_lev, shown2, work, x0, y0, x1, y1, all, sheets, &fl2);
    if ((n != n2 || fl2 != *fl || memcmp(o, recs2, n * sizeof(PlatRec))
         || memcmp(shown, shown2, VL_CELLS)) && bad++ < 20)
        printf("xcom: LITCHECK: %u,%u-%u,%u all %u: asm %u records fl %u, C %u fl %u\n", x0, y0,
               x1, y1, all, n, *fl, n2, fl2);
    return n;
}
#define LIT_RECS(o, x0, y0, x1, y1, all, sheets, fl) recs_check(o, x0, y0, x1, y1, all, sheets, fl)
#else
#define LIT_RECS(o, x0, y0, x1, y1, all, sheets, fl) \
    hz_lit_recs(o, g_vl_lev, shown, work, x0, y0, x1, y1, all, sheets, fl)
#endif
#else
#define LIT_RECS(o, x0, y0, x1, y1, all, sheets, fl) \
    lit_recs(o, g_vl_lev, shown, work, x0, y0, x1, y1, all, sheets, fl)
#endif

/* the whole view's records, kept while the levels and the sheets stay (a present of the
   whole view needs only the levels: then every cell is shown whole) */
static PlatRec far frecs[NREC];
static unsigned fn, fsheets;
static unsigned char fvalid;

/* A night present of the rectangle x0..x0 + w, y0..y0 + rows (pixels; x0
   and w multiples of 4), as vgaasm.asm lit_present: the levels brought up
   to date (vlit.c: when a light came, went or moved, or the camera or the
   view's level moved, every cell is looked at), the records (lit_recs), to
   the screen by the platform's blitter (plat_bb_present_lit) or here. */
static void night_present(unsigned x0, unsigned y0, unsigned w, unsigned rows)
{
    const unsigned char far *buf = BUF(g_bufseg);
    unsigned char far *scr = (unsigned char far *)MK_FP(0xA000, 0);
    const unsigned char far *t = tabs;
    unsigned i, n, r, k, fl, sheets;
    int st, remap, full, hook = 0;
    PlatRec far *p;
    PlatRec far *rc = frecs;

    if (!tabs_ok)
        mktabs();
    plat_busy_tick();                   /* (the pointer: a light that moved costs a little) */
    st = vl_update();
    full = !x0 && !y0 && w == 320 && rows == VIEW_H;
    if (st & VL_MOVED) {
        /* every cell is shown whole: the whole view (its records may be kept), the panel's
           markers again where the rectangle did not reach them */
        memset(shown, 0xFF, VL_CELLS);
        if (!full)
            hook = x0 > 288 || x0 + w < 320 || y0 || rows < VIEW_H;
        full = 1;
        plat_busy_tick();
    }
    remap = plat_bb_lit_ready(tabs);
    sheets = g_lit_sheet[0] | g_lit_sheet[1] << 8;
    if (st || sheets != fsheets)
        fvalid = 0;
    fl = 0;
    if (!full)
        n = LIT_RECS(rc = recs, x0, y0, x0 + w, y0 + rows, st != 0, sheets, &fl);
    else if (fvalid)
        n = fn;                         /* (every cell shown at its level already) */
    else {
        n = fn = LIT_RECS(rc, 0, 0, 320, VIEW_H, st != 0, sheets, &fl);
        fsheets = sheets;
        fvalid = 1;
    }
    if (hook)
        fl |= 2;
    plat_busy_tick();
    if (!n)
        return;
    g_lit_recs += n;
    g_lit_presents++;
    if (st)
        mouse_hide_rect(0, 0, 320, VIEW_H);     /* (cells outside the rectangle may change) */
    if (!remap || !plat_bb_present_lit(rc, n)) {
        PERF_T0(pt0);
        plat_bb_sync();
        for (i = 0; i < n; i++) {
            p = &rc[i];
            if (p->op == PR_TABLE) {
                t = tabs + p->sy * 256u;
                continue;
            }
#if defined(__CC816__)
            {
                /* horizon/hz_vga.s: the remap in assembly (the C took about a second
                   for the whole view); the pointer every 32 rows */
                void hz_shade_rect(unsigned char far *d, const unsigned char far *s, unsigned w,
                                   unsigned rows, const unsigned char far *tab);
                for (r = 0; r < p->h; r += k) {
                    u16 d = (u16)((p->y + r) * ROW + (unsigned)p->x);
                    k = p->h - r < 32 ? p->h - r : 32;
                    hz_shade_rect(scr + d, buf + d, p->w, k, p->op == PR_COPY ? tabs : t);
                    if (k == 32 || p->w * k >= 2048u)
                        plat_busy_tick();
                }
            }
#else
            for (r = 0; r < p->h; r++) {
                u16 d = (u16)((p->y + r) * ROW + (unsigned)p->x);
                const unsigned char far *u = p->op == PR_COPY ? tabs : t;
                for (k = 0; k < p->w; k++)
                    scr[(u16)(d + k)] = u[buf[(u16)(d + k)]];
            }
#endif
        }
        PERF_ADD(PF_SHADE, pt0);
        {
            /* (a present for /M too: its frames and frame rates) */
            PERF_T0(pt1);
            PERF_ADD(PF_PRES, pt1);
        }
    }
    if ((fl & 2) && g_present_hook)
        g_present_hook(0, VIEW_H);
    plat_view(1);
    if (st || full)
        plat_present(0, 0, 320, VIEW_H);
    else
        plat_present((int)x0, (int)y0, (int)(x0 + w), (int)(y0 + rows));
}

/* ---- 5: present cells (the buffer's rows are the screen's) */
void __cdecl bufc_present_rect(unsigned bufseg, unsigned col, unsigned row, unsigned cols,
                               unsigned rows)
{
    const unsigned char far *buf = BUF(bufseg);
    unsigned char far *scr = (unsigned char far *)MK_FP(0xA000, 0);
    u16 d = CELL_OFF(col, row);
    unsigned w = cols * 4, i, n = rows;

    if (!rows || !cols)
        return;
    if (g_vshade) {
        /* (bufseg is g_bufseg) */
        night_present(col * 4, row, w, rows);
        return;
    }
    if (plat_bb_present(d, w, rows))
        goto shown;
    for (; n; n--, d = (u16)(d + ROW))
        for (i = 0; i < w; i++)
            scr[(u16)(d + i)] = buf[(u16)(d + i)];
shown:
    plat_view(1);
    plat_present((int)(col * 4), (int)row, (int)((col + cols) * 4), (int)(row + rows));
}

/* ---- 6: the view moves by delta CGA bytes (the buffer is exactly the
   view's width: what wraps round a row edge lands in the exposed strip,
   which is redrawn) */
static void shift_c(unsigned bufseg, long dx)
{
    unsigned char far *buf = BUF(bufseg);
    unsigned n, i;

    if (dx > 0) {
        n = (unsigned)(BYTES - dx);
        for (i = n; i-- > 0;)
            buf[(u16)(i + dx)] = buf[(u16)i];
    } else if (dx < 0) {
        n = (unsigned)(BYTES + dx);
        for (i = 0; i < n; i++)
            buf[(u16)i] = buf[(u16)(i - dx)];
    }
    /* (at night upstream moves the screen too: vshift; here the caller's
       full present after a scroll shows it: render_scroll) */
}

void __cdecl buf_shift(unsigned bufseg, unsigned plane_bytes, unsigned planes, int delta)
{
    long dx = (long)(short)delta * 4;
    int w = (int)ROW, dr = (int)(dx / w), dc = (int)(dx - (long)dr * w);

    (void)plane_bytes;
    (void)planes;
    PERF_N(PF_SHIFT, 0);
    /* (one delta: the nearer of the two moves it can mean; gfx_shift_window calls
       vga_shift with both numbers instead) */
    if (dc > w / 2) {
        dc -= w;
        dr++;
    } else if (dc < -w / 2) {
        dc += w;
        dr--;
    }
    if (!plat_bb_shift(dc, dr))
        shift_c(bufseg, dx);
}

/* gfx_shift_window: the view moved by dc cells (8 pixels) and dr rows. The blitter
   moves the part that stays as a rectangle, so it needs dc and dr themselves: one
   delta (dr * 320 + dc pixels) means two different moves once dc passes half the
   width (dr 0, dc -192 or dr -1, dc 128), and buf_shift's nearer one was then the
   wrong one: the kept part stayed where it was (a 24-column scroll after an alien's
   turn left half the view stale). The C's linear shift is right for both. */
void vga_shift(int dc, int dr)
{
    PERF_N(PF_SHIFT, 0);
    if (!plat_bb_shift(dc * 8, dr))
        shift_c(g_bufseg, (long)dr * (int)ROW + dc * 8);
}

/* ---- 7: the cursor's box between the buffer and SAVE (out 1: to SAVE).
   The block's own SAVE is used, not the caller's save (as upstream). */
void __cdecl buf_box(unsigned bufseg, unsigned off, unsigned stride, unsigned bytes,
                     unsigned rows, void *save, int out)
{
    unsigned char far *buf = BUF(bufseg);
    u16 s = (u16)(off << 2);
    unsigned w = bytes * 4, i, k = 0;

    (void)stride;
    (void)save;
    if (plat_bb_box(s, w, rows, out))
        return;
    for (; rows; rows--, s = (u16)(s + ROW))
        for (i = 0; i < w; i++, k++) {
            if (k >= sizeof save_box)
                return;
            if (out)
                save_box[k] = buf[(u16)(s + i)];
            else
                buf[(u16)(s + i)] = save_box[k];
        }
}

/* ---- 8: the palette to the DAC */
void vga_pal(void)
{
    vga_dac(g_vpal, 0, 256);
}

/* ---- 22: render_arrow (c0, r0 in cells and rows): the selected unit's
   arrow, 9 x 9 (OpenXcom Map::init: yellow 16, black 15), into the back
   buffer over the cells shown. */
int g_arrow[4];

#define K 15
#define Y 16
static const unsigned char arrow_px[81] = {
    0, 0, K, K, K, K, K, 0, 0,
    0, 0, K, Y, Y, Y, K, 0, 0,
    0, 0, K, Y, Y, Y, K, 0, 0,
    K, K, K, Y, Y, Y, K, K, K,
    K, Y, Y, Y, Y, Y, Y, Y, K,
    0, K, Y, Y, Y, Y, Y, K, 0,
    0, 0, K, Y, Y, Y, K, 0, 0,
    0, 0, 0, K, Y, K, 0, 0, 0,
    0, 0, 0, 0, K, 0, 0, 0, 0
};
#undef K
#undef Y

void render_arrow(int c0, int r0, int cols, int rows)
{
    unsigned char far *buf;
    int qx = (short)(c0 << 3), qw = (short)(cols << 3), qy = r0, qh = rows;
    int t0, t1, r, c, y, x;

    if (!g_arrow[0] || g_arrow[3] > g_view_z)
        return;
    t0 = (short)(g_cam_x + g_arrow[1]);
    t1 = (short)(g_cam_y + g_arrow[2]);
    if (plat_bb_arrow(arrow_px, t0, t1, qx, qy, qw, qh))
        return;
    buf = BUF(g_bufseg);
    for (r = 0; r < 9; r++) {
        y = (short)(t1 + r);
        if (y < qy || y >= qy + qh || (unsigned)y >= VIEW_H)
            continue;
        for (c = 0; c < 9; c++) {
            unsigned char px = arrow_px[r * 9 + c];
            if (!px)
                continue;
            x = (short)(t0 + c);
            if (x < qx || x >= qx + qw || (unsigned)x >= ROW)
                continue;
            buf[(u16)(y * ROW + x)] = px;
        }
    }
}

/* ---- 23: smoke, fire and flare overlays (the dithered fallback of
   vgaasm.asm op_fx): rows [r0, r1) of a 32 x 40 shape (4 bytes a row, bit
   7 the left pixel) through the row's pattern (q01, q23: rows & 3), in
   the CGA colour (colour * 55h & 3) as its EGA colour's palette index,
   the 8-pixel columns of cols only. */
static const unsigned char fx_col[4] = { 7, 10, 12, 14 };

/* DOS's smoke and fire pictures (vgaasm.asm fxpic, OpenXcom
   Map::drawTerrain, SMOKE.PCK as tools/convert.py build_smoke made
   SMOKEV.PAK: "XSM1", 2, 14 pictures, u16 bytes, then u16 offsets[14] and
   the masked pictures, each a 32 x 40 box): fire frames 0-3, smoke 4-9
   (thin 4, thick 5, 6 by its thickness, + the step), a burning unit's
   10-13. A tile's step is its own start (mixed from its place) + the
   pictures' step (pics_next: every 4 BIOS ticks), the tile's old step while
   a pass has not redrawn it yet (no seams). */
static unsigned char far *smk;          /* the pack's bytes (offsets, pictures), NULL: none */
static unsigned char v_step, v_old;     /* V_STEP, V_OLD */
static unsigned v_nxt;                  /* V_NXT: pics_next's next of fire + smoke */
static int rect[4];                     /* V_RX0, V_RY0, V_RX1, V_RY1 */

/* SMOKEV.PAK into the DOS memory once (vgainit.c smoke_pics; plat/vga.c's
   vgx_init calls it where upstream's vga_init loads it) */
void vga_smoke_load(void)
{
    unsigned char h[8];
    unsigned n;
    void *p;
    FILE *f;

    if (smk || (f = fopen("SMOKEV.PAK", "rb")) == NULL)
        return;
    if (fread(h, 8, 1, f) == 1 && !memcmp(h, "XSM1", 4) && h[4] == 2 && h[5] == 14) {
        n = h[6] | h[7] << 8;
        if ((p = malloc(n)) != NULL) {
            if (fread(p, n, 1, f) == 1)
                smk = (unsigned char far *)p;
            else
                free(p);
        }
    }
    fclose(f);
}

/* fxpic: 1 when done (drawn or nothing to draw), 0: the dithered shape at
   rows *r0..*r1 (which it may narrow) */
static int fxpic(unsigned seg, unsigned off, unsigned *r0, unsigned *r1, unsigned q01,
                 unsigned q23, unsigned colour, unsigned cols)
{
    unsigned char al = (unsigned char)colour, ah, fr;
    const Spot *list;
    int n, i, camx4 = (short)g_cam_x >> 2, ftop, fbot, sy = 0;

    ah = (unsigned char)(q01 | q01 >> 8 | q23 | q23 >> 8);
    if (al == 0xFF) {
        /* colour 3: the dot of something on the floor (the full pattern) is
           dithered at its shape's rows 31-32; a flare's glow and fire's
           inner flames are not drawn */
        if ((u16)q01 != 0xFFFF || (u16)q23 != 0xFFFF)
            return 1;
        if ((int)*r0 < 31)
            *r0 = 31;
        if ((int)*r1 > 33)
            *r1 = 33;
        return 0;
    }
    if (al == 0xAA) {
        fr = 0;
        list = fire;
        n = n_fire;
    } else if (al == 0) {
        fr = ah == 0xFF ? 5 : 4;        /* not found: thin or thick by the pattern */
        list = smoke;
        n = n_smoke;
    } else
        return 0;                       /* colour 1: none */
    for (i = 0; i < n; i++) {
        const Spot *t = &list[i];
        int dz = (t->z & 7) * 24;
        u16 o;
        sy = (int)(short)((((t->x + t->y) & 0xFF) << 3) - dz + g_cam_y);
        o = (u16)((u16)sy * 80u + (u16)((int)(signed char)(t->x - t->y) * 4 + camx4));
        if (o == (u16)off)
            break;
    }
    if (i == n) {
        if (fr == 0)                    /* a burning unit (no start of its own) */
            fr = (unsigned char)(10 + (v_step & 3));
        ftop = (int)*r0;
        fbot = (int)*r1;
    } else {
        const Spot *t = &list[i];
        unsigned char a, b, st;
        unsigned k = (unsigned)i;
        if (fr) {
            unsigned v = t->v & 15;
            fr = (unsigned char)(v <= 6 ? 4 : v <= 12 ? 5 : 6);
            k += (unsigned)n_fire;      /* its place in fire, then smoke */
        }
        a = (unsigned char)(t->x * 5);
        b = t->y;
        a ^= b;
        a ^= (unsigned char)(b << 1);
        a = (unsigned char)(a + (unsigned char)(b << 3));
        a ^= t->z;
        a ^= (unsigned char)(a >> 3);
        st = v_nxt && k >= v_nxt ? v_old : v_step;
        fr = (unsigned char)(fr + ((a + st) & 3));
        ftop = (int)clear_y0 - sy;
        if (ftop < 0)
            ftop = 0;
        fbot = (int)clear_y1 - sy;
        if (fbot > 40)
            fbot = 40;
    }
    if (fbot > ftop) {
        const unsigned char far *pic = smk + (smk[fr * 2] | smk[fr * 2 + 1] << 8);
        blitc_masked_clip(pic, seg, off, (unsigned)ftop, (unsigned)fbot, cols);
    }
    return 1;
}

void __cdecl fxtile_cga(unsigned seg, unsigned off, const unsigned char *shape, unsigned r0,
                        unsigned r1, unsigned q01, unsigned q23, unsigned colour, unsigned cols)
{
    unsigned char far *buf;
    const unsigned char far *s = (const unsigned char far *)shape;
    unsigned char pat[4], dl;
    u16 di;
    unsigned t0;
    int n;

    if (smk && fxpic(seg, off, &r0, &r1, q01, q23, colour, cols))
        return;
    buf = BUF(seg);
    di = (u16)(r0 * ROW + (u16)(off << 2));
    t0 = r0;
    n = (int)r1 - (int)r0;
    if (n <= 0)
        return;
    plat_bb_sync();
    pat[0] = (unsigned char)q01;
    pat[1] = (unsigned char)(q01 >> 8);
    pat[2] = (unsigned char)q23;
    pat[3] = (unsigned char)(q23 >> 8);
    dl = g_vmap[fx_col[colour & 3]];
    s += (u16)(r0 << 2);
    for (; n; n--, t0++, di = (u16)(di + ROW)) {
        unsigned char dh = pat[t0 & 3];
        unsigned b, m = cols & 0xFF;
        for (b = 0; b < 4; b++, m >>= 1) {
            unsigned char al = (unsigned char)(*s++ & dh);
            u16 d = (u16)(di + 8 * b);
            if (!(m & 1))
                al = 0;
            while (al) {
                if (al & 0x80)
                    buf[d] = dl;
                al = (unsigned char)(al << 1);
                d = (u16)(d + 1);
            }
        }
    }
}

/* ---- 24: gfx_night: the view's shade at the present (0 by day). */
void vga_gfx_night(int night)
{
    g_vshade = night ? VL_NIGHT_SHADE : 0;
    /* (vgaasm.asm ui_night: no cell shown yet, the levels made anew) */
    memset(shown, 0xFF, VL_CELLS);
    vl_night();
}

/* ---- 25: gfx_dot: 2 x 2 pixels XORed on the screen in the EGA colour's
   palette index (drawn again: gone); not while Hidden Movement covers
   the view. */
void vga_gfx_dot(int x, int y, int colour)
{
    unsigned char far *scr = (unsigned char far *)MK_FP(0xA000, 0);
    unsigned char c;
    u16 d;

    x &= 0xFFFE;
    if ((unsigned)(u16)x > 318 || (unsigned)(u16)y > VIEW_H - 2 || g_view_off)
        return;
    c = g_vmap[colour & 15];
    mouse_hide_rect(x, y, x + 2, y + 2);
    d = (u16)(y * ROW + x);
    scr[d] ^= c;
    scr[(u16)(d + 1)] ^= c;
    scr[(u16)(d + ROW)] ^= c;
    scr[(u16)(d + ROW + 1)] ^= c;
    plat_present(x, y, x + 2, y + 2);
}

/* ---- 26: pics_next: the rectangle to redraw for the smoke and fire
   pictures' step, NULL: nothing. A pass over fire, then smoke, starts when
   the BIOS clock's tick / 4 is not the step (which it then becomes), with
   the view showing and the pictures loaded. A tile in sight (its level
   drawn, its box on the view, discovered) adds render_tile's rectangle to
   the one handed back while that stays within 64 x 72 (neighbours go
   together; a key waits for one such rectangle at most). */
#define PICS_W  64
#define PICS_H  72

const int far *vga_pics_next(void)
{
    rect[0] = -1;
    if (!smk || g_view_off)
        return NULL;
    if (!v_nxt) {
        unsigned char t = (unsigned char)(*(volatile unsigned char far *)MK_FP(0x40, 0x6C) >> 2);
        if (t == v_step)
            return NULL;
        v_old = v_step;
        v_step = t;
    }
    for (;;) {
        const Spot *t;
        unsigned d = v_nxt;
        int z, sx, sy, x0, x1, y0, y1;
        if (d < (unsigned)n_fire)
            t = &fire[d];
        else if (d - (unsigned)n_fire < (unsigned)n_smoke)
            t = &smoke[d - (unsigned)n_fire];
        else {
            v_nxt = 0;                  /* the pass is over */
            break;
        }
        v_nxt++;
        z = t->z & 7;
        if (z > g_view_z && !g_all_layers)
            continue;
        sx = (short)((int)(signed char)(t->x - t->y) * 16 + g_cam_x);
        if (sx <= -32 || sx >= 320)
            continue;
        sy = (short)((((t->x + t->y) & 0xFF) << 3) - z * 24 + g_cam_y);
        if (sy <= -40 || sy >= VIEW_H + 24)
            continue;
        if (g_seen && !(g_seen[(u16)((u16)((u16)z * g_my + t->y) * g_mx + t->x)] & 0x10))
            continue;
        x0 = sx < 0 ? 0 : sx;
        x1 = sx + 32 > 320 ? 320 : sx + 32;
        y0 = sy - 24 < 0 ? 0 : sy - 24;
        y1 = sy + 40 > VIEW_H ? VIEW_H : sy + 40;
        if (rect[0] != -1) {
            if (rect[0] < x0) x0 = rect[0];
            if (rect[2] > x1) x1 = rect[2];
            if (rect[1] < y0) y0 = rect[1];
            if (rect[3] > y1) y1 = rect[3];
            if ((unsigned)(x1 - x0) > PICS_W || (unsigned)(y1 - y0) > PICS_H) {
                v_nxt--;                /* that tile starts the next one */
                break;
            }
        }
        rect[0] = x0;
        rect[1] = y0;
        rect[2] = x1;
        rect[3] = y1;
    }
    return rect[0] == -1 ? NULL : rect;
}

/* BENCH (the patch: vbench.c's pictures' step check): the pictures are
   loaded; a pass from the start with a new step; the pass is over */
int vga_pics_loaded(void)
{
    return smk != NULL;
}

void vga_pics_start(void)
{
    v_step = (unsigned char)~(*(volatile unsigned char far *)MK_FP(0x40, 0x6C) >> 2);
    v_nxt = 0;
}

int vga_pics_over(void)
{
    return !v_nxt;
}

#if !defined(__CC816__)
/* plat_bb_prepare (plat.h): the host draws by the C, nothing to prepare
   (the Atari816's is horizon/hz_bb.c; host/host.c has the other plat_bb_*) */
void plat_bb_prepare(void)
{
}
#endif

/* fxasm.asm's EGA overlay (inside plat/asm.c's XD_HAVE_VGABAT block):
   never called in the VGA mode. */
void __cdecl fxtile_ega(unsigned seg, unsigned off, const unsigned char *shape, unsigned r0,
                        unsigned r1, unsigned q01, unsigned q23, unsigned colour, unsigned cols)
{
    (void)seg; (void)off; (void)shape; (void)r0; (void)r1; (void)q01; (void)q23;
    (void)colour; (void)cols;
    plat_note("vgabat: fxtile_ega called");
}
