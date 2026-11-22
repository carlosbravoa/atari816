/* hz_vid.c - Digger's video for Horizon: upstream's VGA drawing interface (hardware.h,
 * draw_api.h: vgainit, vgaputi, vgageti, vgaputim, vgagetpix, vgawrite, ...) on a
 * framebuffer drawn by the CPU (hz_plat.h). The equivalent of upstream's sdl_vid.c; the
 * palettes are sdl_vid.c's (Maxim Sobolev, Beer-ware licence: see COPYING.md). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hgame.h>
#include "def.h"
#include "hardware.h"
#include "alpha.h"
#include "hz_plat.h"
#include "hz_bufs.h"

struct hz_savebufs __far *hz_savebufs;

/* sdl_vid.c's palettes: 1 and 2, normal and high intensity */
static const unsigned char pal1[48] = {
    0,0,0, 0,0,128, 0,128,0, 0,128,128, 128,0,0, 128,0,128, 128,64,0, 128,128,128,
    64,64,64, 0,0,255, 0,255,0, 0,255,255, 255,0,0, 255,0,255, 255,255,0, 255,255,255};
static const unsigned char pal1i[48] = {
    0,0,0, 0,0,255, 0,255,0, 0,255,255, 255,0,0, 255,0,255, 255,128,0, 196,196,196,
    128,128,128, 128,128,255, 128,255,128, 128,255,255, 255,128,128, 255,128,255,
    255,255,128, 255,255,255};
static const unsigned char pal2[48] = {
    0,0,0, 0,128,0, 128,0,0, 128,64,0, 0,0,128, 0,128,128, 128,0,128, 128,128,128,
    64,64,64, 0,255,0, 255,0,0, 255,255,0, 0,0,255, 0,255,255, 255,0,255, 255,255,255};
static const unsigned char pal2i[48] = {
    0,0,0, 0,255,0, 255,0,0, 255,128,0, 0,0,255, 0,255,255, 255,0,255, 196,196,196,
    128,128,128, 128,255,128, 255,128,128, 255,255,128, 128,128,255, 128,255,255,
    255,128,255, 255,255,255};

static int16_t currpal;
static bool inited;

void vgainit(void)
{
    if (inited)
        return;
    if (hzd_load() < 0)
        exit(1);
    hz_savebufs = (struct hz_savebufs __far *)hz_far_alloc();
    if (!hz_savebufs) {
        printf("digger: no free memory bank\n");
        exit(1);
    }
    if (hg_screen_fb(HG_640X360X4, "Digger", HZ_FB_STRIDE, HZ_FB_ROWS) < 0) {
        printf("digger: no full screen (is another game in full screen?)\n");
        exit(1);
    }
    /* the game draws into a buffer of its own (4 banks, the same shape); what changed is
     * copied to the shown framebuffer just after each vertical blank (hzv_show) */
    hzb_showbank = hg_fb_bank;
    hzb_fbbank = hg_banks(HZ_FB_ROWS * (unsigned long)HZ_FB_STRIDE >> 16);
    if (!hzb_fbbank) {
        printf("digger: not enough memory\n");
        exit(1);
    }
    hg_split(HZ_PANEL, 0, HZ_PANEL);
    inited = true;
}

void graphicsoff(void)
{
}

extern bool hzt_title;

/* ---------------------------------------------------------------- what changed */

#define NDIRTY 128
static struct { unsigned x, row, bw, rows; } dirty[NDIRTY];
static unsigned ndirty;
static bool alldirty;

static bool boxed;
static unsigned bx0 = 0xFFFF, by0 = 0xFFFF, bx1, by1;

static void grow(unsigned x, unsigned row, unsigned bw, unsigned rows)
{
    if (x < bx0)
        bx0 = x;
    if (row < by0)
        by0 = row;
    if (x + bw > bx1)
        bx1 = x + bw;
    if (row + rows > by1)
        by1 = row + rows;
}

#define NHASH 256
static unsigned char hash[NHASH];       /* entry + 1, 0 free */

static void mark(unsigned x, unsigned row, unsigned bw, unsigned rows)
{
    unsigned i, h;
    if (alldirty)
        return;
    if (row >= HZ_PIC_ROWS || x >= 320)
        return;
    if (row + rows > HZ_PIC_ROWS)
        rows = HZ_PIC_ROWS - row;
    if (x + bw > 320)
        bw = 320 - x;
    /* the same rectangle again (a sprite put back, drawn again, its neighbours redrawn):
     * once is enough; a small hash of the rectangles of this frame finds it */
    h = (x ^ row * 7 ^ bw * 13 ^ rows * 3) & (NHASH - 1);
    while (hash[h]) {
        i = hash[h] - 1;
        if (dirty[i].x == x && dirty[i].row == row && dirty[i].bw == bw &&
            dirty[i].rows == rows)
            return;
        h = (h + 1) & (NHASH - 1);
    }
    if (ndirty == NDIRTY) {
        /* full (a level being drawn): from now on one rectangle round all of them */
        for (i = 0; i < NDIRTY; i++)
            grow(dirty[i].x, dirty[i].row, dirty[i].bw, dirty[i].rows);
        ndirty = 0;
        memset(hash, 0, sizeof hash);
        boxed = true;
    }
    if (boxed) {
        grow(x, row, bw, rows);
        return;
    }
    hash[h] = (unsigned char)(ndirty + 1);
    dirty[ndirty].x = x;
    dirty[ndirty].row = row;
    dirty[ndirty].bw = bw;
    dirty[ndirty].rows = rows;
    ++ndirty;
}

/* (hz_timer.c, just after a vertical blank) the changes to the screen */
void hzv_show(void)
{
    unsigned i;
    if (!inited)
        return;
    if (alldirty)
        hzb_show(0, 0, 320, HZ_PIC_ROWS);
    else {
        for (i = 0; i < ndirty; i++)
            hzb_show(dirty[i].x, dirty[i].row, dirty[i].bw, dirty[i].rows);
        if (boxed)
            hzb_show(bx0, by0, bx1 - bx0, by1 - by0);
    }
    if (ndirty)
        memset(hash, 0, sizeof hash);
    ndirty = 0;
    alldirty = boxed = false;
    bx0 = by0 = 0xFFFF;
    bx1 = by1 = 0;
}

void vgaclear(void)
{
    hzt_title = false;
    hzb_fill(0, 0, 320, HZ_PIC_ROWS, 0);
    alldirty = true;
}

void vgapal(int16_t pal)
{
    hg_palette(0, 16, pal ? pal2 : pal1);
    currpal = pal;
}

void vgainten(int16_t inten)
{
    if (inten == 1)
        hg_palette(0, 16, currpal ? pal2i : pal1i);
    else
        hg_palette(0, 16, currpal ? pal2 : pal1);
}

/* upstream's coordinates: x 0-319 (4 bits a pixel at 640: byte x), y 0-199 (rows 2y,
 * 2y + 1); w in units of 4 (8 pixels: 4 bytes), h in upstream's rows */
#define OK(x, y) ((x) >= 0 && (y) >= 0 && (y) < 256)

void vgaputi(int16_t x, int16_t y, uint8_t __far *p, int16_t w, int16_t h)
{
    if (OK(x, y)) {
        hzb_put((unsigned)x, (unsigned)y * 2, p, (unsigned)w * 4, (unsigned)h * 2);
        hzt_work((unsigned)w * (unsigned)h * 8);
        mark((unsigned)x, (unsigned)y * 2, (unsigned)w * 4, (unsigned)h * 2);
    }
}

void vgageti(int16_t x, int16_t y, uint8_t __far *p, int16_t w, int16_t h)
{
    if (OK(x, y)) {
        hzb_get((unsigned)x, (unsigned)y * 2, p, (unsigned)w * 4, (unsigned)h * 2);
        hzt_work((unsigned)w * (unsigned)h * 8);
    }
}

void vgaputim(int16_t x, int16_t y, int16_t ch, int16_t w, int16_t h)
{
    unsigned n, bw = (unsigned)w * 4, rows = (unsigned)h * 2;
    unsigned long a = hzd_sprite((unsigned)ch, &n);
    if (!a || !OK(x, y))
        return;
    if (bw * rows > n)              /* (never: the data is at least as large) */
        rows = n / bw;
    hzb_putm((unsigned)x, (unsigned)y * 2, a, bw, rows);
    hzt_work(bw * rows * 2);
    mark((unsigned)x, (unsigned)y * 2, bw, rows);
}

/* upstream's vgagetpix: the 8 x 2 pixels of (x, y) as the bits of a CGA byte, a bit for
 * each column with a pixel that is not 0 (0x80 the left one), & 0xEE */
int16_t vgagetpix(int16_t x, int16_t y)
{
    unsigned char b[8];
    unsigned i, r = 0;
    if (x > 319 || y > 199 || x < 0 || y < 0)
        return 0xff;
    hzb_get((unsigned)x & ~1u, (unsigned)y * 2, b, 4, 2);
    if (x & 1) {                    /* (x is always even here; an odd one reads 2 more) */
        unsigned char c[12];
        hzb_get((unsigned)x - 1, (unsigned)y * 2, c, 6, 2);
        for (i = 0; i < 4; i++) {
            b[i] = c[i + 1];
            b[i + 4] = c[i + 7];
        }
    }
    for (i = 0; i < 4; i++) {
        unsigned v = b[i] | b[i + 4];
        if (v & 0xF0)
            r |= 0x80 >> (i * 2);
        if (v & 0x0F)
            r |= 0x40 >> (i * 2);
    }
    return (int16_t)(r & 0xee);
}

void vgawrite(int16_t x, int16_t y, int16_t ch, int16_t c)
{
    unsigned long a;
    if (!isvalchar(ch) || !OK(x, y))
        return;
    a = hzd_char((unsigned)ch - 32, (unsigned)c);
    if (a) {
        hzb_copy((unsigned)x, (unsigned)y * 2, a, 12, 24);
        hzt_work(12 * 24);
        mark((unsigned)x, (unsigned)y * 2, 12, 24);
    }
}

void vgatitle(void)
{
    hzt_title = true;
    hzb_copy(0, 0, hzd_title(0), 320, 200);
    hzb_copy(0, 200, hzd_title(1), 320, 200);
    alldirty = true;
}

/* the frame goes to the screen at the next vertical blank (hzv_show) */
void doscreenupdate(void)
{
}

void gretrace(void)
{
}

/* upstream's CGA functions: the VGA ones serve (sdl_vid.c does the same) */
void cgainit(void) {}
void cgaclear(void) {}
void cgatitle(void) {}
void cgawrite(int16_t x, int16_t y, int16_t ch, int16_t c) {}
void cgaputim(int16_t x, int16_t y, int16_t ch, int16_t w, int16_t h) {}
void cgageti(int16_t x, int16_t y, uint8_t __far *p, int16_t w, int16_t h) {}
void cgaputi(int16_t x, int16_t y, uint8_t __far *p, int16_t w, int16_t h) {}
void cgapal(int16_t pal) {}
void cgainten(int16_t inten) {}
int16_t cgagetpix(int16_t x, int16_t y) { return 0; }
