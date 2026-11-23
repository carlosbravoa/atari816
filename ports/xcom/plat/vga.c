/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The VGA prototype's start and its interface, in C: upstream's
   src/vgainit.c (the start), src/vgaasm.asm's "interface" (entries 9-21:
   pictures streamed from UIV.PAK into A000, glyphs, the clean screen,
   fills, copies, the BIOS-font HUD text, the mouse pointer) and
   src/vgageo.c + src/vgxasm.asm (the DOS palettes per screen from
   PALV.PAK, the VGA themes, the geoscape's world and markers, the
   battle's and the end slides' palettes). Upstream patches its resident
   CGA routines' first bytes into far jumps to code copied to the heap; the
   port's patch (patches/src-0001-port.patch) makes each of them call the
   function of the same entry here when g_vga is set. The battle view
   (entries 0-8, 22-26) is plat/vgabat.c. */
#include "xcompat.h"
#include "plat.h"
#include "vga.h"
#include "gfx.h"
#include "uik.h"
#include "input.h"
#include "vgageo.h"

#define ROW         320
#define SCREEN      ((unsigned char far *)MK_FP(0xA000, 0))

unsigned char g_vpal[768];
unsigned char g_vmap[16];
unsigned g_vshade;
unsigned g_vgx;

extern int g_uk_fd;
extern char g_uk_name[];
extern const unsigned char __near *g_ms_pm, __near *g_ms_pf;

void vga_dac(const unsigned char far *pal, int first, int n)
{
    int i;

    outp(0x3C8, (unsigned)first);
    for (i = 0; i < n * 3; i++)
        outp(0x3C9, pal[i]);
}

/* ---------------------------------------------------------------- entries */
/* A picture's place in the pack and its box (vgaasm.asm's 16-byte entry). */
typedef struct {
    long pos;
    int x, y, w, h, fl;
} Entry;

static Entry tmpe;
static int sy0, sy1;
/* The clean screen (uk_save, uk_restore, uk_pic_clean): a copy of the screen in
   the arena's E000 bank, as the EGA program keeps one in spare video memory.
   (Upstream's VGA prototype had no room for one: it kept the last plain
   picture and up to 4 pictures added to it, read again from the pack at a
   restore, black where none covered the rectangle: the base's view under the
   build cursor, a notice closed over it, went black.) */
#define CLEAN       ((unsigned char far *)MK_FP(XD_CLEAN_SEG, 0))
static unsigned char far *pbase;        /* where part() draws: the screen or CLEAN */
static int qx, qy, qw, qh;              /* the rectangle drawn (V_QX ...) */
static int opened;                      /* the pack opened here (V_OPEN) */
static unsigned char rowbuf[ROW];
static unsigned char cursor[13][9];     /* OpenXcom's pointer */
static unsigned char msave[14][9];
static int mx, my, mw, mh;

static void hide(int x0, int y0, int x1, int y1)
{
    mouse_hide_rect(x0, y0, x1, y1);
}

static int open_pack(void)
{
    opened = 0;
    if (g_uk_fd >= 0)
        return 1;
    g_uk_fd = open(g_uk_name, O_RDONLY);
    if (g_uk_fd < 0)
        return 0;
    opened = 1;
    return 1;
}

static void close_pack(void)
{
    if (opened) {
        close(g_uk_fd);
        g_uk_fd = -1;
        opened = 0;
    }
}

/* The part of entry e inside the rectangle q, read from the pack (vgaasm.asm
   part). */
static void part(const Entry *e)
{
    int t0, t1, r0, r1, rows, skip;
    unsigned char far *d;
    unsigned got;

    t0 = qx > e->x ? qx : e->x;
    t1 = (qx + qw < e->x + e->w ? qx + qw : e->x + e->w) - t0;
    if (t1 <= 0)
        return;
    skip = e->w - t1;
    r0 = qy > e->y ? qy : e->y;
    r1 = qy + qh < e->y + e->h ? qy + qh : e->y + e->h;
    rows = r1 - r0;
    if (rows <= 0)
        return;
    lseek(g_uk_fd, e->pos + (long)(r0 - e->y) * e->w + (t0 - e->x), SEEK_SET);
    d = pbase + (unsigned)r0 * ROW + (unsigned)t0;
    if (!(e->fl & 1)) {
        if (t1 == ROW) {
            _dos_read(g_uk_fd, d, (unsigned)rows * ROW, &got);
            return;
        }
        for (;;) {
            _dos_read(g_uk_fd, d, (unsigned)t1, &got);
            d += ROW;
            if (!--rows)
                return;
            if (skip)
                lseek(g_uk_fd, skip, SEEK_CUR);
        }
    }
    for (;;) {
        int k;
        _dos_read(g_uk_fd, rowbuf, (unsigned)t1, &got);
        for (k = 0; k < t1; k++)
            if (rowbuf[k])
                d[k] = rowbuf[k];
        d += ROW;
        if (!--rows)
            return;
        if (skip)
            lseek(g_uk_fd, skip, SEEK_CUR);
    }
}

/* Fills the rectangle q with c, clipped to the screen. */
static void qfill(unsigned char c)
{
    int x = qx, w = qw, y = qy, h = qh;
    unsigned char far *d;

    if (x < 0) {
        w += x;
        x = 0;
    }
    if (x + w > ROW)
        w = ROW - x;
    if (w <= 0)
        return;
    if (y < 0) {
        h += y;
        y = 0;
    }
    if (y + h > 200)
        h = 200 - y;
    if (h <= 0)
        return;
    d = SCREEN + (unsigned)y * ROW + (unsigned)x;
    while (h--) {
        _fmemset(d, c, (unsigned)w);
        d += ROW;
    }
}

/* ---------------------------------------------------------------- vgxasm.asm: palettes, themes */
#define PALREC      784
#define RAMPS       (8 + 5 * PALREC)
#define THEMES      (RAMPS + 8 * 48)
#define TREC        (15 + 16)
#define TSET        (5 * TREC)

static unsigned char curp, curb, inbat, theme_asked, have_tt;
static unsigned char tt[TSET];
static const UkTheme *ega_themes;

static int read_at(long off, void far *dst, unsigned n)
{
    unsigned got = 0;
    int f = open("PALV.PAK", O_RDONLY);

    if (f < 0)
        return 0;
    if (lseek(f, off, SEEK_SET) == off)
        _dos_read(f, dst, n, &got);
    close(f);
    return got == n;
}

static void apply(void)
{
    const unsigned char *t;

    if (!have_tt)
        return;
    t = tt + theme_asked * TREC;
    g_uk = (const UkTheme *)t;
    memcpy(g_vmap, t + 15, 16);
}

/* vgaasm.asm's uk_theme (entry 16): the EGA themes. */
static void ui_theme(int t)
{
    g_uk = ega_themes + t;
}

static void themes(void)
{
    unsigned char p = curp & 7;

    have_tt = 0;
    if (p > 5 || (p == 5 && inbat)) {
        ui_theme(theme_asked);
        return;
    }
    if (p < 5)
        inbat = 0;
    if (!read_at(THEMES + (long)(((p - 1) * 2 + (curp >> 7)) * TSET), tt, TSET)) {
        ui_theme(theme_asked);
        return;
    }
    have_tt = 1;
    apply();
}

/* The DOS palette of tag t (bits 0-2 palette + 1, 3-6 ramp + 1, 7 style). */
static void set_pal(unsigned char t)
{
    unsigned char a = t & 0x87, r;

    if ((a & 7) && a != curp) {
        unsigned char was = curp;
        curp = a;
        if ((was ^ a) & 7) {
            curb = 0;
            if (!read_at(8 + (long)((a & 7) - 1) * PALREC, g_vpal, 768))
                goto ramp;
            read_at(8 + (long)((a & 7) - 1) * PALREC + 768, g_vmap, 16);
            vga_dac(g_vpal, 0, 256);
        }
        themes();
    }
ramp:
    r = (t >> 3) & 15;
    if (!r || r == curb)
        return;
    curb = r;
    if (read_at(RAMPS + (long)(r - 1) * 48, g_vpal + 224 * 3, 48))
        vga_dac(g_vpal + 224 * 3, 224, 16);
}

/* ---------------------------------------------------------------- the interface */
typedef struct {
    unsigned short x, y, w, h;
    unsigned char flags, reserved;
} PicHead;

/* 9 uk_pic_cga, with vgxasm.asm's hook in front (vx_pic): the pack stands
   at the picture's data. */
void vga_uk_pic(const void *head, int x, int y, int to_save)
{
    const PicHead *h = head;

    if ((!to_save || curp != 5) && h->reserved)
        set_pal(h->reserved);
    tmpe.x = x;
    tmpe.y = y;
    tmpe.w = h->w;
    tmpe.h = h->h;
    tmpe.fl = h->flags;
    tmpe.pos = lseek(g_uk_fd, 0, SEEK_CUR);
    qx = x;
    qy = y;
    qw = h->w;
    qh = h->h;
    if (to_save) {
        /* vx_pic's clean: into the clean screen, not drawn */
        pbase = CLEAN;
        part(&tmpe);
        pbase = SCREEN;
        return;
    }
    if (y < 144 && y + (int)h->h > 144 && h->w >= 64)
        plat_view(0);                   /* a picture across the view's bottom (a window, the
                                           inventory): the whole screen pans again */
    pbase = SCREEN;
    part(&tmpe);
}

/* 10 uk_cga_c */
int vga_uk_cga_c(int c)
{
    return g_vmap[c & 15];
}

/* 11 uk_glyph_cga: h rows of bpr (1 or 2) bytes, the colour an index. */
#if defined(__CC816__)
/* horizon/hz_vga.s: the same loop in assembly */
void hz_glyph(unsigned char far *d, const unsigned char far *g, int h, int bpr, int c, int right);
#endif
void vga_uk_glyph(int x, int y, const unsigned char far *g, int h, int bpr, int c)
{
    unsigned char far *d = SCREEN + (unsigned)y * ROW + (unsigned)x;
    int right = ROW - x, n;
    unsigned bits;

#if defined(__CC816__)
    hz_glyph(d, g, h, bpr, c, right);
    (void)n;
    (void)bits;
#else
    for (; h > 0; h--, g += bpr, d += ROW) {
        unsigned char far *p = d;
        bits = (unsigned)g[0] << 8;
        if (bpr == 2)
            bits |= g[1];
        for (n = right; bits && n; n--, p++, bits = (bits << 1) & 0xFFFF)
            if (bits & 0x8000)
                *p = (unsigned char)c;
    }
#endif
}

/* 12 uk_pic_clean: entry id into the clean screen's list. */
int vga_uk_pic_clean(unsigned id)
{
    unsigned char b[10];
    unsigned long at;

    if (!open_pack())
        return 0;
    lseek(g_uk_fd, (long)id * 4 + 8, SEEK_SET);
    if (read(g_uk_fd, b, 4) != 4)
        b[0] = b[1] = b[2] = b[3] = 0;
    at = b[0] | (unsigned long)b[1] << 8 | (unsigned long)b[2] << 16 | (unsigned long)b[3] << 24;
    if (!at) {
        close_pack();
        return 0;
    }
    tmpe.pos = (long)at + 10;
    lseek(g_uk_fd, (long)at, SEEK_SET);
    read(g_uk_fd, b, 10);
    tmpe.x = b[0] | b[1] << 8;
    tmpe.y = b[2] | b[3] << 8;
    tmpe.w = b[4] | b[5] << 8;
    tmpe.h = b[6] | b[7] << 8;
    tmpe.fl = b[8];
    qx = tmpe.x;
    qy = tmpe.y;
    qw = tmpe.w;
    qh = tmpe.h;
    pbase = CLEAN;
    part(&tmpe);
    pbase = SCREEN;
    close_pack();
    return 1;
}

/* 13 uk_save: the screen's rows [y0, y1) are the clean screen (the pointer
   hidden first, as uik.c's EGA and CGA copies). */
void vga_uk_save(int y0, int y1)
{
    sy0 = y0 < 0 ? 0 : y0;
    sy1 = y1 > 200 ? 200 : y1;
    if (sy1 <= sy0)
        return;
    hide(0, sy0, ROW, sy1);
    _fmemcpy(CLEAN + (unsigned)sy0 * ROW, SCREEN + (unsigned)sy0 * ROW, (unsigned)(sy1 - sy0) * ROW);
}

/* 14 uk_restore: the clean screen's rectangle back. */
void vga_uk_restore(int x, int y, int w, int h)
{
    unsigned off;

    if (y < sy0) {
        h -= sy0 - y;
        y = sy0;
    }
    if (y + h > sy1)
        h = sy1 - y;
    if (x < 0) {
        w += x;
        x = 0;
    }
    if (x + w > ROW)
        w = ROW - x;
    if (w <= 0 || h <= 0)
        return;
    hide(x, y, x + w, y + h);
    off = (unsigned)y * ROW + (unsigned)x;
    if (w == ROW)
        _fmemcpy(SCREEN + off, CLEAN + off, (unsigned)h * ROW);
    else
        for (; h > 0; h--, off += ROW)
            _fmemcpy(SCREEN + off, CLEAN + off, (unsigned)w);
}

/* 15 uk_fill, with vx_fill in front: 16-255 is a palette index. */
void vga_uk_fill(int x, int y, int w, int h, int c)
{
    if (w <= 0 || h <= 0)
        return;
    qx = x;
    qy = y;
    qw = w;
    qh = h;
    hide(x, y, x + w, y + h);
    qfill(c >= 16 ? (unsigned char)c : g_vmap[c & 15]);
}

/* 16 uk_theme, with vx_theme in front. */
void vga_uk_theme(int t)
{
    ui_theme(t);
    theme_asked = (unsigned char)t;
    apply();
}

/* 17 uk_copy (the rectangles may overlap). */
void vga_uk_copy(int sx, int sy, int dx, int dy, int w, int h)
{
    unsigned char far *s;
    unsigned char far *d;
    int r;

    hide(dx, dy, dx + w, dy + h);
    if (w <= 0 || h <= 0)
        return;
    s = SCREEN + (unsigned)sy * ROW + (unsigned)sx;
    d = SCREEN + (unsigned)dy * ROW + (unsigned)dx;
    if (d > s)
        for (r = h - 1; r >= 0; r--)
            _fmemmove(d + (unsigned)r * ROW, s + (unsigned)r * ROW, (unsigned)w);
    else
        for (r = 0; r < h; r++)
            _fmemmove(d + (unsigned)r * ROW, s + (unsigned)r * ROW, (unsigned)w);
}

/* 18 hud_text_cga: the BIOS font, 8 x 8 cells, black behind. */
void vga_hud_text(int col, int row, int colour, const char *s, int len)
{
    const unsigned char far *font = (const unsigned char far *)MK_FP(0xF000, 0xFA6E);
    unsigned char c = g_vmap[colour & 15];
    unsigned char far *d;
    int i, r, k;

    d = SCREEN + (unsigned)row * 8 * ROW + (unsigned)col * 8;
    for (i = 0; i < len; i++, d += 8) {
        const unsigned char far *g = font + ((unsigned char)s[i] & 0x7F) * 8;
        for (r = 0; r < 8; r++)
            for (k = 0; k < 8; k++)
                d[(unsigned)r * ROW + k] = (g[r] << k) & 0x80 ? c : 0;
    }
}

/* 19 hud_clear_rows */
void vga_hud_clear(int row, int count)
{
    qx = 0;
    qw = ROW;
    qy = row * 8;
    qh = count * 8;
    hide(0, qy, ROW, qy + qh);
    qfill(0);
}

static unsigned char far *mbox(int x, int y)
{
    mx = x;
    my = y;
    mw = ROW - x < 9 ? ROW - x : 9;
    mh = 200 - y < 14 ? 200 - y : 14;
    return SCREEN + (unsigned)y * ROW + (unsigned)x;
}

/* 20 ms_draw_cga: the pointer, its background kept. */
void vga_ms_draw(int x, int y)
{
    unsigned char far *d = mbox(x, y);
    int r, k;

    for (r = 0; r < mh; r++)
        for (k = 0; k < mw; k++)
            msave[r][k] = d[(unsigned)r * ROW + k];
    if (g_ms_pm[0] == 0x80) {           /* the arrow (OpenXcom's Cursor) */
        for (r = 0; r < mh && r < 13; r++)
            for (k = 0; k < mw; k++)
                if (cursor[r][k])
                    d[(unsigned)r * ROW + k] = cursor[r][k];
        return;
    }
    for (r = 0; r < mh; r++) {          /* the hourglass: mask black, fill white */
        unsigned char m = g_ms_pm[r], f = g_ms_pf[r];
        for (k = 0; k < mw && k < 8; k++, m <<= 1, f <<= 1)
            if (m & 0x80)
                d[(unsigned)r * ROW + k] = f & 0x80 ? g_vmap[15] : g_vmap[0];
    }
}

/* 21 ms_erase_cga */
void vga_ms_erase(int x, int y)
{
    unsigned char far *d = mbox(mx, my);
    int r, k;

    (void)x;
    (void)y;
    for (r = 0; r < mh; r++)
        for (k = 0; k < mw; k++)
            d[(unsigned)r * ROW + k] = msave[r][k];
}

/* ---------------------------------------------------------------- the geoscape (vgxasm.asm) */
#define VIEW_W      256
#define WMAP_W      320
#define WMAP_H      160
#define BYTES       (320U * 144)
#define STACK0      (BYTES - 2048)

static unsigned xsp = STACK0;           /* the markers' stack in the back buffer */

/* 1: the 256 x 160 view from the 320 x 160 map, each pixel 1, 2 or 4 times.
   A row is made once (zoom 0: copies; 1, 2: each byte 2 or 4 times, in
   assembly on the Atari816: horizon/hz_vga.s) and copied for the rows that
   repeat it. */
#if defined(__CC816__)
void hz_zoom_row(unsigned char far *d, const unsigned char far *s, unsigned n, unsigned zoom);
#endif
static void zoom_part(unsigned char far *p, const unsigned char far *s, unsigned n, unsigned zoom)
{
    unsigned i, k, rep = 1u << zoom;

    if (!zoom) {
        _fmemcpy(p, s, n);
        return;
    }
#if defined(__CC816__)
    hz_zoom_row(p, s, n, zoom);
    (void)i;
    (void)k;
    (void)rep;
#else
    for (i = 0; i < n; i++)
        for (k = 0; k < rep; k++)
            *p++ = s[i];
#endif
}

void vga_vx_world(const unsigned char far *map, unsigned vx, unsigned vy, unsigned zoom)
{
    unsigned char far *d = SCREEN;
    unsigned need = VIEW_W >> zoom, n1 = WMAP_W - vx < need ? WMAP_W - vx : need, y;

    plat_view(0);

    xsp = STACK0;
    for (y = 0; y < WMAP_H; y++, d += ROW) {
        const unsigned char far *s = map + ((y >> zoom) + vy) * WMAP_W;
        if (y && (y >> zoom) == ((y - 1) >> zoom)) {
            _fmemcpy(d, d - ROW, VIEW_W);       /* the row above again */
            continue;
        }
        zoom_part(d, s + vx, n1, zoom);
        if (need > n1)
            zoom_part(d + (n1 << zoom), s, need - n1, zoom);
    }
}

/* OpenXcom's GlobeMarkers (vgxasm.asm marks). */
static const unsigned char marks[9][9] = {
    { 9, 9, 9, 9, 0, 9, 9, 9, 9 }, { 0, 11, 0, 11, 0, 11, 0, 11, 0 },
    { 0, 13, 0, 13, 13, 13, 0, 13, 0 }, { 7, 0, 7, 0, 7, 0, 7, 0, 7 },
    { 5, 0, 5, 0, 5, 0, 5, 0, 5 }, { 0, 1, 0, 1, 1, 1, 0, 1, 0 },
    { 3, 0, 3, 0, 3, 0, 3, 0, 3 }, { 1, 1, 1, 1, 0, 1, 1, 1, 1 },
    { 14, 14, 14, 14, 11, 14, 14, 14, 14 }
};

/* 2: a marker box; the last one drawn, asked again, is put back. */
void vga_vx_xor(int x0, int y0, int x1, int y1, int colour)
{
    unsigned char far *buf = (unsigned char far *)MK_FP(g_bufseg, 0);
    unsigned char far *scr;
    unsigned short far *top;
    int w, h, r, k;
    unsigned bytes;

    if (colour >= 16) {
        if (x1 - x0 == 2 && x1 < VIEW_W)
            x1++;
        if (y1 - y0 == 2 && y1 < WMAP_H)
            y1++;
    }
    w = x1 - x0;
    h = y1 - y0;
    if (w <= 0 || h <= 0)
        return;
    bytes = (unsigned)w * (unsigned)h;
    scr = SCREEN + (unsigned)y0 * ROW + (unsigned)x0;
    if (xsp >= STACK0 + 10) {
        top = (unsigned short far *)(buf + xsp - 10);
        if (top[0] == (unsigned short)x0 && top[1] == (unsigned short)y0 && top[2] == (unsigned short)x1
            && top[3] == (unsigned short)y1 && top[4] == (unsigned short)colour) {
            xsp -= 10 + bytes;
            for (r = 0; r < h; r++)
                _fmemcpy(scr + (unsigned)r * ROW, buf + xsp + (unsigned)r * w, (unsigned)w);
            return;
        }
    }
    if ((unsigned long)xsp + bytes > BYTES - 10)
        return;
    for (r = 0; r < h; r++)
        _fmemcpy(buf + xsp + (unsigned)r * w, scr + (unsigned)r * ROW, (unsigned)w);
    top = (unsigned short far *)(buf + xsp + bytes);
    top[0] = (unsigned short)x0;
    top[1] = (unsigned short)y0;
    top[2] = (unsigned short)x1;
    top[3] = (unsigned short)y1;
    top[4] = (unsigned short)colour;
    xsp += bytes + 10;
    if (colour < 16) {
        for (r = 0; r < h; r++)
            _fmemset(scr + (unsigned)r * ROW, g_vmap[colour & 15], (unsigned)w);
        return;
    }
    if (w < 3 || h < 3)
        return;
    if (w != 3 || h != 3)               /* selected: the box's edge */
        for (r = 0; r < h; r++)
            for (k = 0; k < w; k++)
                if (!r || r == h - 1 || !k || k == w - 1)
                    scr[(unsigned)r * ROW + k] = g_vmap[colour & 15];
    scr += (unsigned)((h - 3) / 2) * ROW + (unsigned)((w - 3) / 2);
    {
        const unsigned char *m = marks[((colour >> 4) - 1) % 9];
        for (r = 0; r < 3; r++)
            for (k = 0; k < 3; k++)
                if (m[r * 3 + k])
                    scr[(unsigned)r * ROW + k] = m[r * 3 + k];
    }
}

/* 5: before a battle: black, the battlescape palette. */
void vga_vx_battle(void)
{
    _fmemset(SCREEN, 0, 64000u);
    inbat = 1;
    curp = 0;
    set_pal(5);
}

/* 6: the end slides' palette (NULL: black), the caption's colour. */
void vga_vx_slide(const unsigned char far *dac, int caption)
{
    static const unsigned char black[768];

    curp = curb = 0;
    g_vmap[14] = (unsigned char)caption;
    g_vmap[6] = (unsigned char)(caption + 3);
    vga_dac(dac ? dac : (const unsigned char far *)black, 0, 256);
}

/* ---------------------------------------------------------------- the start (vgainit.c) */

/* The battlescape palette from the mission pack named after MISSION, else
   FA1V.PAK: its trailer's "XPL1". */
static int read_palette(void)
{
    const char *name = "FA1V.PAK";
    unsigned short n;
    char m[4];
    FILE *f;
    int i, ok = 0;

    for (i = 1; i + 1 < __argc; i++)
        if (!stricmp(__argv[i], "MISSION"))
            name = __argv[i + 1];
    if ((f = fopen(name, "rb")) == NULL)
        return 0;
    if (!fseek(f, -6L - 6 - 768, SEEK_END) && fread(m, 4, 1, f) == 1 && fread(&n, 2, 1, f) == 1
        && !memcmp(m, "XPL1", 4) && n == 768)
        ok = fread(g_vpal, 768, 1, f) == 1;
    fclose(f);
    return ok;
}

static void interface(void)
{
    static const unsigned char ega[16][3] = {
        { 0, 0, 0 }, { 0, 0, 42 }, { 0, 42, 0 }, { 0, 42, 42 }, { 42, 0, 0 }, { 42, 0, 42 },
        { 42, 21, 0 }, { 42, 42, 42 }, { 21, 21, 21 }, { 21, 21, 63 }, { 21, 63, 21 },
        { 21, 63, 63 }, { 63, 21, 21 }, { 63, 21, 63 }, { 63, 63, 21 }, { 63, 63, 63 }
    };
    int c, i, k;

    for (c = 0; c < 16; c++) {
        long best = 0x7FFFFFFFL;
        for (i = 0; i < 256; i++) {
            long d = 0;
            for (k = 0; k < 3; k++) {
                int e = g_vpal[i * 3 + k] - ega[c][k];
                d += (long)e * e;
            }
            if (d < best) {
                best = d;
                g_vmap[c] = (unsigned char)i;
            }
        }
    }
    g_video = VIDEO_EGA;                /* the EGA themes: uk_theme's choice on an EGA */
    g_vga = 0;                          /* (upstream's uk_theme, not the hook) */
    uk_theme(0);
    g_vga = 1;
    ega_themes = g_uk;
    g_video = VIDEO_CGA;
    memset(cursor, 0, sizeof cursor);
    for (i = 0; i < 4; i++) {
        for (k = 2 * i; k <= 12 - i; k++)
            cursor[k][i] = (unsigned char)(144 + i);
        for (k = 0; i + k <= 8 - i; k++)
            cursor[2 * i + k][i + k] = (unsigned char)(144 + i);
    }
    cursor[8][4] = 147;
    g_uk_name[2] = 'V';
}

/* gfx_init's want 3: 0 on, 2 no memory. */
int vga_init(void)
{
    void *p;

    g_video = VIDEO_CGA;
    /* the DOS memory the prototype takes (its code and buffer), as upstream; the
       buffer itself is at D004 (plat.h XD_BB_SEG), outside the DOS memory: the
       Atari816 maps that bank onto its framebuffer's second bank, where the
       blitter draws it */
    p = malloc(VGA_BYTES + 256 + 16);
    if (!p)
        return 2;
    g_bufseg = XD_BB_SEG;
    _fmemset(MK_FP(g_bufseg, 0), 0, VGA_BYTES);
    vid_setmode(0x13);
    if (read_palette())
        vga_dac(g_vpal, 0, 256);
    g_vga = 1;
    interface();
    log_printf("video: VGA prototype (mode 13h, plat/vga.c), buffer at %04X", g_bufseg);
    vgx_init(0);
    return 0;
}

void vgx_init(unsigned vseg)
{
    (void)vseg;
    g_pakv = 'V';
    g_vgx = 1;
    vga_smoke_load();                   /* (vgainit.c smoke_pics: DOS's smoke and fire pictures) */
}
