/* hz_vga.c - Xargon's video on Horizon: upstream's mode X drawing (graphics.c's drawshape
 * and grl.obj's ldrawsh_vga, grasm.obj's clrvp, scrollvp, scroll, plot_vga, lcopypage) and
 * the VGA registers graphics.c writes (the DAC's palette, the CRTC's start address: the page
 * shown), on the framebuffer of hz_plat.h, drawn by the blitter (Ali).
 *
 * The shapes are in an atlas of 512-byte rows in far memory (hz_shm.c), registered as two
 * of the kernel's sheets: a cell or a sprite is one sheet_draw record (a copy, or a keyed
 * copy for colour 0 transparent), queued and sent in batches of up to 128; Ali draws them
 * while the CPU goes on with the game. The fonts (upstream's colour table 1: four values
 * mapped to the colours fontcolor sets) are drawn by the CPU (hz_blit.s), after what is
 * queued is drawn. graphics.c itself (palettes, fades, pages) is upstream's. */
#include <string.h>
#include <hgame.h>
#include <horizon.h>
#include "gr.h"
#include "hz_plat.h"

extern vptype gamevp;                   /* xargon.c */

unsigned hzv_fbbank;
int hzv_ox[2], hzv_oy[2];
unsigned char hzv_show;
unsigned char hzv_shown = 0xFF;         /* the page given to Marga */
unsigned long hzv_cnt[4];               /* (statistics: shapes drawn) */

static unsigned char crtc_hi, crtc_lo;  /* the start address written (CRTC 0C, 0D) */
static unsigned char pal[768];          /* the DAC, 8 bits a component */
static unsigned dac_p;                  /* the next byte of pal the DAC writes */
static unsigned dirty_lo = 0xFFFF, dirty_hi = 0xFFFF;
static hz_fsscroll cur;                 /* the scroll set sent */

/* ---------------------------------------------------------------- the blitter's queue */

hz_sheetrec hzv_q[64];                  /* (hz_blit.s's drawshape writes them too) */
unsigned hzv_qn;
unsigned char hzv_sheet_a, hzv_sheet_b; /* the atlas's rows 0-1023, 1024- */
static unsigned char sheet_g;           /* the glyph cache */
#define q hzv_q
#define qn hzv_qn
#define sheet_a hzv_sheet_a
#define sheet_b hzv_sheet_b
unsigned char hzv_ali;                  /* records sent that may still be drawn */

unsigned hzv_flip_frame;                /* the frame counter when a flip was sent */
unsigned char hzv_flip_wait;            /* ... and its blank has not been seen yet */
unsigned long hzv_flip_waits;           /* (statistics: drawing waited for a flip) */

/* the page drawn into may still be the one shown until the flip's blank comes */
static void flip_done(void)
{
    if (hzv_flip_wait) {
        if (hz_frame() == hzv_flip_frame) {
            ++hzv_flip_waits;
            hzf_pump();                 /* (the next vertical blank) */
        }
        hzv_flip_wait = 0;
    }
}

void hzv_flush(void)
{
    flip_done();
    if (qn) {
        hz_sheet_draw(hg_win, qn, q);
        qn = 0;
        hzv_ali = 1;
    }
}

/* what is queued drawn, and done (before the CPU draws, or a page is shown) */
static unsigned char gepoch_next(void);

void hzv_sync(void)
{
    hzv_flush();
    if (hzv_ali) {
        hz_list_wait(0);
        hzv_ali = 0;
    }
    gepoch_next();
}

static hz_sheetrec *rec(void)
{
    if (qn == 64)
        hzv_flush();
    return &q[qn++];
}

/* a move inside the framebuffer (a draw_list record, after the queue) */
static void fbmove(unsigned sx, unsigned sy, unsigned w, unsigned h, unsigned x, unsigned y)
{
    hz_drawrec d;
    hzv_flush();
    memset(&d, 0, sizeof d);
    d.op = LS_MOVE;
    d.x = (short)x;
    d.y = (short)y;
    d.w = w;
    d.h = h;
    d.u.m.sx = (short)sx;
    d.u.m.sy = (short)sy;
    hz_draw_list(hg_win, 1, &d);
    hzv_ali = 1;
}

/* ---------------------------------------------------------------- the pages */

static unsigned dpage(void)
{
    return ((unsigned)drawofs >> 14) & 1;
}

#define PBASE(p) ((p) * HZ_PAGE)        /* the page's first row */

int hzv_init(void)
{
    hz_fsenter fe;
    hz_fsscroll z;
    hz_sheetnew sn;
    unsigned long a;
    unsigned b, k;
    int r;

    if (hg_screen(HG_320X180, "Xargon") < 0)
        return -1;
    b = hg_banks(HZ_FBANKS);
    if (!b)
        return -1;
    hzv_fbbank = b;
    hzb_bank = b;
    memset(&z, 0, sizeof z);
    hz_fs_scroll(&z);                   /* (a set that fits any buffer) */
    fe.mode = 2;                        /* FS_320X8 */
    fe.flags = 0;
    fe.stride = HZ_STRIDE;
    fe.rows = HZ_ROWS;
    HZ_U24B(fe.base, b, 0);
    fe.zero = 0;
    if (hz_fs_enter(hg_win, &fe))
        return -1;
    hzv_oy[0] = hzv_oy[1] = HZ_OYMID;
    /* the atlas (hz_shm.c: its banks), two sheets */
    a = hzshm_atlas();
    if (!a)
        return -1;
    for (k = 0; k < 2 && k * 1024 < hzshm_rows; k++) {
        HZ_U24B(sn.addr, (unsigned)((k ? hzshm_atlas_b() : a) >> 16), 0);
        sn.zero = 0;
        sn.stride = HZ_STRIDE;
        sn.w = HZ_STRIDE;
        sn.h = hzshm_rows - k * 1024 > 1024 ? 1024 : hzshm_rows - k * 1024;
        r = hz_sheet_new(&sn);
        if (r <= 0)
            return -1;
        if (k)
            sheet_b = (unsigned char)r;
        else
            sheet_a = (unsigned char)r;
    }
    if (glyph_init() < 0)
        return -1;
    /* the framebuffer black */
    for (k = 0; k < HZ_ROWS; k += 256) {
        hz_sheetrec *f = rec();
        memset(f, 0, sizeof *f);
        f->w = HZ_STRIDE;
        f->h = HZ_ROWS - k > 256 ? 256 : HZ_ROWS - k;
        f->y = (short)k;
    }
    hzv_sync();
    hzv_show = 0;
    return 0;
}

/* after each vertical blank: the page shown, its view, the palette, for the next one */
void hzv_display(void)
{
    hz_fsscroll s;
    unsigned p = hzv_show, top, split;

    if (gamevp.vpyl == HZ_GAMEVP_H && gamevp.vpy == HZ_GAMEVP_Y) {
        top = HZ_VIEW_Y;                /* playing: the playfield, then the status bar */
        split = HZ_VIEW_H;
    } else {
        top = 0;                        /* a picture of the whole screen: rows 0-179 */
        split = 160;
    }
    hzv_flush();                        /* (what was drawn into the page shown) */
    memset(&s, 0, sizeof s);
    s.x = (unsigned)hzv_ox[p] & (HZ_STRIDE - 1);
    s.y = PBASE(p) + (unsigned)hzv_oy[p] + top;
    s.x2 = 0;
    s.y2 = PBASE(p) + HZ_PANEL;
    s.vheight = 0;
    s.split = split * 2;                /* (Marga counts 360 lines) */
    s.ctrl = 3;                         /* FSC_HWRAP | FSC_SPLIT */
    if (memcmp(&s, &cur, sizeof s)) {
        hz_fs_scroll(&s);
        cur = s;
    }
    hzv_shown = (unsigned char)p;
    if (dirty_lo != 0xFFFF) {           /* (byte positions: the entries they are in) */
        unsigned lo = dirty_lo / 3, hi = dirty_hi / 3;
        hg_palette(lo, hi - lo + 1, pal + lo * 3);
        dirty_lo = dirty_hi = 0xFFFF;
    }
}

/* ---------------------------------------------------------------- the registers */

void hzv_dac_index(unsigned char i)
{
    dac_p = (unsigned)i * 3;
}

/* (fades write the whole palette 32 times: kept short) */
void hzv_dac_data(unsigned char v)
{
    v &= 63;
    pal[dac_p] = (unsigned char)(v << 2 | v >> 4);
    if (dac_p < dirty_lo)
        dirty_lo = dac_p;
    if (dac_p > dirty_hi || dirty_hi == 0xFFFF)
        dirty_hi = dac_p;
    if (++dac_p >= 768)
        dac_p = 0;
}

void hzv_crtc(unsigned char reg, unsigned char v)
{
    unsigned a;
    if (reg == 0x0C)
        crtc_hi = v;
    else if (reg == 0x0D)
        crtc_lo = v;
    else
        return;
    a = (unsigned)crtc_hi << 8 | crtc_lo;
    hzv_show = (unsigned char)((a >> 14) & 1);  /* (pagelen 16384) */
    if (reg == 0x0D)
        hzf_flipped();                  /* (a game frame ends: the statistics) */
}

/* ---------------------------------------------------------------- rectangles */

#define M_KEY   0
#define M_MAP   1
#define M_COPY  3
#define M_FILL  4
#define M_CACHE 5                       /* from the glyph cache, colour 255 transparent */

/* one rectangle of the framebuffer: (fx, fy) w x h, from the atlas at (sx, sy) */
static void put1(unsigned mode, unsigned sx, unsigned sy, unsigned w, unsigned h,
                 unsigned fx, unsigned fy, unsigned colour)
{
    hz_sheetrec *r;
    if (mode == M_MAP) {
        hzv_sync();
        hzb_map((const unsigned char __far *)(hzshm_row(sy) + sx), HZ_STRIDE, w, h, fy, fx);
        return;
    }
    r = rec();
    r->zero = 0;
    r->w = w;
    r->h = h;
    r->x = (short)fx;
    r->y = (short)fy;
    if (mode == M_FILL) {
        r->sheet = 0;
        r->op = SH_FILL;
        r->c = (unsigned char)colour;
        r->sx = r->sy = 0;
        return;
    }
    r->op = mode == M_COPY ? SH_COPY : SH_KEY;
    r->c = 0;
    r->sx = sx;
    if (mode == M_CACHE) {
        r->sheet = sheet_g;
        r->sy = sy;
        r->c = 255;
    } else if (sy < 1024) {
        r->sheet = sheet_a;
        r->sy = sy;
    } else {
        r->sheet = sheet_b;
        r->sy = sy - 1024;
    }
}

/* w x h at screen (X, Y), inside the screen, from the atlas at (sx, sy) */
static void put(unsigned mode, unsigned sx, unsigned sy, int X, int Y, unsigned w,
                unsigned h, unsigned colour)
{
    unsigned p = dpage(), n, c0, w1, fy;
    if (Y < 160) {
        n = h;
        if ((unsigned)Y + n > 160)
            n = 160 - (unsigned)Y;
        h -= n;
        fy = PBASE(p) + (unsigned)hzv_oy[p] + (unsigned)Y;
        c0 = (unsigned)(hzv_ox[p] + X) & (HZ_STRIDE - 1);
        if (c0 + w <= HZ_STRIDE)
            put1(mode, sx, sy, w, n, c0, fy, colour);
        else {                          /* (across the ring's horizontal wrap) */
            w1 = HZ_STRIDE - c0;
            put1(mode, sx, sy, w1, n, c0, fy, colour);
            put1(mode, sx + w1, sy, w - w1, n, 0, fy, colour);
        }
        sy += n;
        Y = 160;
    }
    if (h)
        put1(mode, sx, sy, w, h, (unsigned)X, PBASE(p) + HZ_PANEL + (unsigned)(Y - 160),
             colour);
}

/* (x, y, w, h) in vp cut to vp and to the screen -> 0 when nothing is left; the source's
 * corner moves by *sx, *sy; x, y become screen coordinates */
static int clip(vptype *vp, int *x, int *y, int *w, int *h, int *sx, int *sy)
{
    int X, Y;
    if (*x < 0) {
        *sx -= *x;
        *w += *x;
        *x = 0;
    }
    if (*y < 0) {
        *sy -= *y;
        *h += *y;
        *y = 0;
    }
    if (*x + *w > vp->vpxl)
        *w = vp->vpxl - *x;
    if (*y + *h > vp->vpyl)
        *h = vp->vpyl - *y;
    X = vp->vpx + *x;
    Y = vp->vpy + *y;
    if (X < 0) {
        *sx -= X;
        *w += X;
        X = 0;
    }
    if (Y < 0) {
        *sy -= Y;
        *h += Y;
        Y = 0;
    }
    if (X + *w > 320)
        *w = 320 - X;
    if (Y + *h > 200)
        *h = 200 - Y;
    *x = X;
    *y = Y;
    return *w > 0 && *h > 0;
}

/* upstream's drawshape (graphics.c): shape n (table n >> 8, a 0x40 in it: drawn opaque,
 * upstream's colour table 3; else a font table's colour table 1, or table 0: colour 0
 * transparent) at (x, y) of viewport vp. The table is loaded when it is not (shm_do).
 * Called for every cell and sprite drawn (and many cut away): the common case, wholly
 * inside the viewport and the playfield's rows, not across the ring's wrap, queues its
 * record straight away */
/* ---------------------------------------------------------------- the fonts' glyphs
 *
 * A font's shape (values 0-3) is drawn in the colours fontcolor chose (upstream's colour
 * table 1; 255: transparent). The glyphs in their colours are kept in a cache (a sheet of
 * its own: 512 slots of 8 x 8), made by the CPU when first drawn, then drawn by the
 * blitter as any shape (a keyed copy, 255 the key). A slot is chosen by a hash of the
 * glyph and its colours; reusing a slot that a record still queued or running may read
 * waits for the blitter first (rare). */
#define GSLOTS 512
static unsigned long gbase;             /* the cache's bank (512-byte rows, 128) */
static unsigned char __far *gtag;       /* each slot's glyph: 6 bytes (nt ns lo hi bk epoch) */
static unsigned char gepoch = 1;        /* + 1 each time the blitter is known idle */

static unsigned char gepoch_next(void)
{
    if (++gepoch == 0)
        gepoch = 1;
    return gepoch;
}
unsigned long hzv_gmade, hzv_gwait;     /* (statistics: glyphs made, waits for a slot) */

static int glyph_init(void)
{
    hz_sheetnew sn;
    unsigned b = hg_banks(1);
    int r;
    if (!b)
        return -1;
    gbase = (unsigned long)b << 16;
    gtag = (unsigned char __far *)(gbase + 0xF000UL);   /* (rows 120-127: the tags) */
    hz_far_set(gtag, 0, GSLOTS * 6);
    HZ_U24B(sn.addr, b, 0);
    sn.zero = 0;
    sn.stride = HZ_STRIDE;
    sn.w = HZ_STRIDE;
    sn.h = 120;
    r = hz_sheet_new(&sn);
    if (r <= 0)
        return -1;
    sheet_g = (unsigned char)r;
    return 0;
}

/* the cache slot (its corner in the sheet) of glyph ns of font table nt, whose pixels are
 * at row sy, byte sx of the atlas, w x h, in colours cmtab[1] */
static void glyph(int nt, int ns, unsigned sx, unsigned sy, unsigned w, unsigned h,
                  unsigned *gx, unsigned *gy)
{
    unsigned char lo = (unsigned char)cmtab[1][1], hi = (unsigned char)cmtab[1][2];
    unsigned char bk = (unsigned char)cmtab[1][3];
    unsigned slot = ((unsigned)ns * 7 + (unsigned)nt * 131 + lo * 3 + hi * 5 + bk * 11) &
                    (GSLOTS - 1);
    unsigned char __far *t = gtag + slot * 6;
    unsigned r, c;
    const unsigned char __far *src;
    unsigned char __far *dst;
    unsigned char map[4];

    *gx = (slot & 63) << 3;
    *gy = (slot >> 6) << 3;
    if (t[0] == (unsigned char)nt && t[1] == (unsigned char)ns && t[2] == lo && t[3] == hi &&
        t[4] == bk) {
        t[5] = gepoch;
        return;
    }
    if (t[0] && t[5] == gepoch) {       /* (a record may still read the old glyph) */
        hzv_sync();
        ++hzv_gwait;
    }
    map[0] = (unsigned char)cmtab[1][0];
    map[1] = lo;
    map[2] = hi;
    map[3] = bk;
    src = (const unsigned char __far *)(hzshm_row(sy) + sx);
    dst = (unsigned char __far *)(gbase + ((unsigned long)*gy << 9) + *gx);
    for (r = 0; r < h; r++, src += HZ_STRIDE, dst += HZ_STRIDE)
        for (c = 0; c < w; c++)
            dst[c] = map[src[c] & 3];
    t[0] = (unsigned char)nt;
    t[1] = (unsigned char)ns;
    t[2] = lo;
    t[3] = hi;
    t[4] = bk;
    t[5] = gepoch;
    ++hzv_gmade;
}

/* the rest: cut, across the wraps or into the status bar, a font (a function of its own:
 * drawshape's variables stay in registers) */
static void drawslow(vptype *vp, int ct, int x, int y, int w, int h, int sx, int sy,
                     int nt, int ns)
{
    int x0 = sx, y0 = sy;
    unsigned gx, gy;
    if (ct == 1)                        /* (the glyph whole, its colours: before the cut) */
        glyph(nt, ns, (unsigned)sx, (unsigned)sy, (unsigned)w, (unsigned)h, &gx, &gy);
    if (!clip(vp, &x, &y, &w, &h, &sx, &sy))
        return;
    if (ct == 1)
        put(M_CACHE, gx + (unsigned)(sx - x0), gy + (unsigned)(sy - y0), x, y, (unsigned)w,
            (unsigned)h, 0);
    else
        put(ct == 3 ? M_COPY : M_KEY, (unsigned)sx, (unsigned)sy, x, y, (unsigned)w,
            (unsigned)h, 0);
}

void drawshape_c(vptype *vp, int n, int x, int y)
{
    int ns = n & 0xff, nt = n >> 8, ct, w, h, sx, sy;
    unsigned p, c0;
    const unsigned char __far *e;
    hz_sheetrec *r;

    if (nt & 0x40) {
        ct = 3;
        nt ^= 0x40;
    } else
        ct = (nt > 0 && nt < shm_maxtbls) ? shm_flags[nt] & shm_fontf : 0;
    if (nt <= 0 || nt >= shm_maxtbls)
        return;
    if (!hzshm_ok[nt]) {
        shm_want[nt] = 1;
        shm_do();
        if (!hzshm_ok[nt])
            return;                     /* (upstream: LOST) */
    }
    if ((unsigned)ns >= hzshm_count[nt])
        return;
    e = hzshm_dir + ((hzshm_first[nt] + (unsigned)ns) << 3);
    w = e[4];
    h = e[5];
    x -= vp->vpox;
    y -= vp->vpoy;
    if (y >= vp->vpyl || y + h <= 0 || x >= vp->vpxl || x + w <= 0)
        return;
    sx = *(const unsigned __far *)e;
    sy = *(const unsigned __far *)(e + 2) + hzshm_row0[nt];
    ++hzv_cnt[ct];
    if (x >= 0 && y >= 0 && x + w <= vp->vpxl && y + h <= vp->vpyl) {
        int X = x + vp->vpx, Y = y + vp->vpy;
        unsigned fy, gx, gy;
        /* wholly in the playfield's rows (not across the wrap) or in the status bar's */
        if (X >= 0 && Y >= 0 && X + w <= 320 && (Y + h <= 160 || (Y >= 160 && Y + h <= 200))) {
            p = ((unsigned)drawofs >> 14) & 1;
            if (Y < 160) {
                c0 = (unsigned)(hzv_ox[p] + X) & (HZ_STRIDE - 1);
                fy = PBASE(p) + (unsigned)hzv_oy[p] + (unsigned)Y;
            } else {
                c0 = (unsigned)X;
                fy = PBASE(p) + HZ_PANEL + (unsigned)(Y - 160);
            }
            if (c0 + (unsigned)w <= HZ_STRIDE) {
                if (ct == 1)            /* (before the record: it may send the queue) */
                    glyph(nt, ns, (unsigned)sx, (unsigned)sy, (unsigned)w, (unsigned)h,
                          &gx, &gy);
                r = qn == 64 ? (hzv_flush(), &q[qn++]) : &q[qn++];
                r->zero = 0;
                if (ct == 1) {
                    r->op = SH_KEY;
                    r->c = 255;
                    r->sheet = sheet_g;
                    r->sx = gx;
                    r->sy = gy;
                } else {
                    r->op = ct == 3 ? SH_COPY : SH_KEY;
                    r->c = 0;
                    r->sx = (unsigned)sx;
                    if ((unsigned)sy < 1024) {
                        r->sheet = sheet_a;
                        r->sy = (unsigned)sy;
                    } else {
                        r->sheet = sheet_b;
                        r->sy = (unsigned)sy - 1024;
                    }
                }
                r->w = (unsigned)w;
                r->h = (unsigned)h;
                r->x = (short)c0;
                r->y = (short)fy;
                return;
            }
        }
    }
    drawslow(vp, ct, x, y, w, h, sx, sy, nt, ns);
}

/* (upstream's grl.obj entry, which drawshape called: not used here) */
void ldrawsh_vga(vptype *vp, int draw_x, int draw_y, int sh_xlb, int sh_yl,
                 char far *shape, int cmtable)
{
    (void)vp, (void)draw_x, (void)draw_y, (void)sh_xlb, (void)sh_yl, (void)shape;
    (void)cmtable;
}

void clrvp(vptype *vp, byte col)
{
    int x = 0, y = 0, w = vp->vpxl, h = vp->vpyl, sx = 0, sy = 0;
    if (clip(vp, &x, &y, &w, &h, &sx, &sy))
        put(M_FILL, 0, 0, x, y, (unsigned)w, (unsigned)h, col);
}

void plot_vga(int x, int y, byte color)
{
    if (x >= 0 && y >= 0 && x < 320 && y < 200)
        put(M_FILL, 0, 0, x, y, 1, 1, color);
}

/* ---------------------------------------------------------------- moving pixels */

/* the framebuffer row and byte of screen (X, Y) in page p */
static void at(unsigned p, int X, int Y, unsigned *fx, unsigned *fy)
{
    if (Y < 160) {
        *fy = PBASE(p) + (unsigned)hzv_oy[p] + (unsigned)Y;
        *fx = (unsigned)(hzv_ox[p] + X) & (HZ_STRIDE - 1);
    } else {
        *fy = PBASE(p) + HZ_PANEL + (unsigned)(Y - 160);
        *fx = (unsigned)X;
    }
}

/* the pixels of screen rectangle (x, y, w, h) moved by (xd, yd); what moves out of it is
 * lost, what comes in is left as it was (upstream redraws it). A row at a time (the ring's
 * wrap may cut a row; a text window's scroll: a few rows) */
static void move(int x, int y, int w, int h, int xd, int yd)
{
    unsigned p = dpage(), sfx, sfy, dfx, dfy;
    int r, sx, dx, n, r0, r1, step, k;
    if (xd >= w || -xd >= w || yd >= h || -yd >= h)
        return;
    sx = xd >= 0 ? x : x - xd;
    dx = xd >= 0 ? x + xd : x;
    n = w - (xd >= 0 ? xd : -xd);
    r0 = yd > 0 ? h - 1 - yd : -yd;
    r1 = yd > 0 ? -1 : h;
    step = yd > 0 ? -1 : 1;
    for (r = r0; r != r1; r += step) {
        at(p, sx, y + r, &sfx, &sfy);
        at(p, dx, y + r + yd, &dfx, &dfy);
        if (sfx + (unsigned)n <= HZ_STRIDE && dfx + (unsigned)n <= HZ_STRIDE)
            fbmove(sfx, sfy, (unsigned)n, 1, dfx, dfy);
        else                            /* (a byte at a time across the wrap: rare) */
            for (k = xd > 0 ? n - 1 : 0; k >= 0 && k < n; k += xd > 0 ? -1 : 1)
                fbmove((sfx + (unsigned)k) & (HZ_STRIDE - 1), sfy, 1, 1,
                       (dfx + (unsigned)k) & (HZ_STRIDE - 1), dfy);
    }
}

/* the playfield's view of page p moves to oy, kept inside the page: when it would leave
 * it, the 160 rows shown so far move to the middle (one move by the blitter) */
static void keep_in(unsigned p, int noy)
{
    int d;
    if (noy >= 0 && noy <= HZ_PAGEH - 160) {
        hzv_oy[p] = noy;
        return;
    }
    d = HZ_OYMID - noy;
    fbmove(0, PBASE(p) + (unsigned)hzv_oy[p], HZ_STRIDE, 160, 0,
           PBASE(p) + (unsigned)(hzv_oy[p] + d));
    hzv_oy[p] = HZ_OYMID;
}

void scrollvp(vptype *vp, int xd, int yd)
{
    int x = 0, y = 0, w = vp->vpxl, h = vp->vpyl, sx = 0, sy = 0;
    if (vp == &gamevp) {
        /* the playfield: the page's origin moves (screen rows 0-159 move with it; upstream
         * copies gamevp's rows on the VGA) */
        unsigned p = dpage();
        hzv_ox[p] = (hzv_ox[p] - xd) & (HZ_STRIDE - 1);
        keep_in(p, hzv_oy[p] - yd);
        return;
    }
    if (clip(vp, &x, &y, &w, &h, &sx, &sy))
        move(x, y, w, h, xd, yd);
}

void scroll(vptype *vp, int x0, int y0, int x1, int y1, int xd, int yd)
{
    int x = x0, y = y0, w = x1 - x0, h = y1 - y0, sx = 0, sy = 0;
    if (clip(vp, &x, &y, &w, &h, &sx, &sy))
        move(x, y, w, h, xd, yd);
}

/* the page shown, copied into the page drawn (setpagemode(1): drawing goes on from what
 * is on the screen): screen rows 0-199, the origin with them */
void lcopypage(void)
{
    unsigned s = hzv_show, d = dpage();
    if (s == d)
        return;
    hzv_ox[d] = hzv_ox[s];
    hzv_oy[d] = HZ_OYMID;
    fbmove(0, PBASE(s) + (unsigned)hzv_oy[s], HZ_STRIDE, 160, 0, PBASE(d) + HZ_OYMID);
    fbmove(0, PBASE(s) + HZ_PANEL, 320, 40, 0, PBASE(d) + HZ_PANEL);
}

/* TheDraw's crunched text screens (the DOS screens before and after the game): none here */
void uncrunch(char far *sourceptr, char far *destptr, int length)
{
    (void)sourceptr;
    (void)destptr;
    (void)length;
}
