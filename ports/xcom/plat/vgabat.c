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

   Not ported (remain): the night lights (vgaasm.asm "Night lights",
   lit_present / vshift: light sources, per-cell levels): here a night
   battle is shown at the sky's one shade (NIGHT_SHADE) everywhere; DOS's
   smoke and fire pictures (fxpic, SMOKEV.PAK) and their animation step
   (pics_next): the dithered shapes are drawn instead, as upstream does
   without SMOKEV.PAK.

   A platform with a blitter draws the buffer itself (plat.h "the battle
   view": the Atari816, horizon/hz_bb.c); every entry asks it first and
   falls back on the C here, which stays the reference (the host). */
#include "xcompat.h"
#include "plat.h"
#include "gfx.h"
#include "input.h"
#include "render.h"
#include "vga.h"

#define ROW     320u
#define BYTES   (ROW * VIEW_H)          /* 46080 */
#define NIGHT_SHADE 10

typedef unsigned short u16;

/* The buffer of segment seg, offset 0. */
#define BUF(seg)    ((unsigned char far *)xd_mkfp_raw(seg, 0))

static u16 lx, rx, vtop, vbot;          /* V_LX, V_RX, V_TOP, V_BOT */
static unsigned char save_box[32 * 40]; /* SAVE: the cursor's box */
static unsigned char shade_tab[256];    /* SHADE at the night's level */
static unsigned shade_lev = 0xFFFF;

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

/* ---- 0: masked (transparent spans), unclipped */
void __cdecl blitc_masked(const void *spr, unsigned bufseg, unsigned dest)
{
    const unsigned char far *s = (const unsigned char far *)spr;
    unsigned char far *buf = BUF(bufseg);
    unsigned first, rows, n, x, len;
    u16 o;

    if (plat_bb_sprite(s, 0, dest, 0, 0xFFFF, 0, 0xFFFF))
        return;
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
    unsigned char far *buf = BUF(bufseg);
    unsigned first, rows, n, x, len, row;
    u16 o;

    clip_vars(top, bottom, wmask);
    if (plat_bb_sprite(s, 0, dest, vtop, vbot, lx, rx))
        return;
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
    unsigned char far *buf = BUF(bufseg);
    unsigned first, rows, x, n;
    u16 o;

    if (plat_bb_sprite(s, 1, dest, 0, 0xFFFF, 0, 0xFFFF))
        return;
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
    unsigned char far *buf = BUF(bufseg);
    unsigned first, rows, x, n, row;
    u16 o;

    clip_vars(top, bottom, wmask);
    if (plat_bb_sprite(s, 1, dest, vtop, vbot, lx, rx))
        return;
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

static void mktab(unsigned lev)
{
    unsigned b, i;

    shade_lev = lev;
    for (b = 0; b < 256; b += 16)
        for (i = 0; i < 16; i++)
            shade_tab[b + i] = (unsigned char)(i + lev < 16 ? b + i + lev : b + 15);
    shade_tab[0] = 0;
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
    if (g_vshade)
        plat_bb_sync();
    else if (plat_bb_present(d, w, rows))
        goto shown;
    if (g_vshade) {
        /* (night: upstream's lit_present shows each cell at its light
           level; here every cell at the sky's) */
        if (shade_lev != g_vshade)
            mktab(g_vshade);
        for (; n; n--, d = (u16)(d + ROW))
            for (i = 0; i < w; i++)
                scr[(u16)(d + i)] = shade_tab[buf[(u16)(d + i)]];
    } else {
        for (; n; n--, d = (u16)(d + ROW))
            for (i = 0; i < w; i++)
                scr[(u16)(d + i)] = buf[(u16)(d + i)];
    }
shown:
    plat_view(1);
    plat_present((int)(col * 4), (int)row, (int)((col + cols) * 4), (int)(row + rows));
}

/* ---- 6: the view moves by delta CGA bytes (the buffer is exactly the
   view's width: what wraps round a row edge lands in the exposed strip,
   which is redrawn) */
void __cdecl buf_shift(unsigned bufseg, unsigned plane_bytes, unsigned planes, int delta)
{
    unsigned char far *buf = BUF(bufseg);
    long dx = (long)(short)delta * 4;
    unsigned n, i;

    (void)plane_bytes;
    (void)planes;
    if (plat_bb_shift(dx))
        return;
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

void __cdecl fxtile_cga(unsigned seg, unsigned off, const unsigned char *shape, unsigned r0,
                        unsigned r1, unsigned q01, unsigned q23, unsigned colour, unsigned cols)
{
    unsigned char far *buf = BUF(seg);
    const unsigned char far *s = (const unsigned char far *)shape;
    unsigned char pat[4], dl;
    u16 di = (u16)(r0 * ROW + (u16)(off << 2));
    unsigned t0 = r0;
    int n = (int)r1 - (int)r0;

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
    g_vshade = night ? NIGHT_SHADE : 0;
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

/* ---- 26: pics_next: the smoke and fire pictures' animation is not
   ported (no SMOKEV.PAK pictures here): nothing to redraw. */
const int far *vga_pics_next(void)
{
    return NULL;
}

/* fxasm.asm's EGA overlay (inside plat/asm.c's XD_HAVE_VGABAT block):
   never called in the VGA mode. */
void __cdecl fxtile_ega(unsigned seg, unsigned off, const unsigned char *shape, unsigned r0,
                        unsigned r1, unsigned q01, unsigned q23, unsigned colour, unsigned cols)
{
    (void)seg; (void)off; (void)shape; (void)r0; (void)r1; (void)q01; (void)q23;
    (void)colour; (void)cols;
    plat_note("vgabat: fxtile_ega called");
}
