/* view.c - the city on the screen: a ring of tile slots in the framebuffer (world tile
 * (c, r) always in slot (c mod 41, r mod 21), or 82 x 40 slots of 8 pixels zoomed out),
 * which Marga's scroll registers show from any pixel with horizontal and vertical wrap;
 * each frame the slots whose tile differs from the map's are drawn again from the tile
 * sheet (the blitter). Upstream's moving things (w_sprite.c) are hardware sprites, 4 bpp
 * (a 48 x 48 one is four 32 x 32 sprites), and so is the tool's frame (four corners).
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms. */
#include <string.h>
#include <horizon.h>
#include "sim.h"
#include "ui.h"

int cam_x, cam_y;
unsigned char zoom8;
unsigned tile_px = 16;
unsigned char page_on;
unsigned long view_draws;

static unsigned rc = 41, rr = 21;               /* the ring's columns and rows */
static unsigned short __far *shown;              /* each slot's tile (0xFFFF: none), far */
unsigned char scratch[1080];
static unsigned char moved = 1, full = 1, part;
static unsigned blink_t;
static unsigned char blink;
static hz_fsscroll scr;
static unsigned char scr_dirty = 1;
static int shake;

/* ---------------------------------------------------------------- sprites */

#define NSPR 16
static int spr_first = -1;
static hz_sprite rec[NSPR], sent[NSPR];
static unsigned long corner_addr;
static int cur_x0, cur_y0, cur_n, cur_on;

static void make_corners(void)
{
    unsigned char (*img)[128] = (unsigned char (*)[128])scratch;
    unsigned char __far *b;
    unsigned k, x, y, c;

    b = hz_far_alloc();
    if (!b)
        return;
    memset(img, 0, 512);
    for (k = 0; k < 4; k++)
        for (y = 0; y < 16; y++)
            for (x = 0; x < 16; x++) {
                unsigned xx = (k & 1) ? 15 - x : x, yy = (k & 2) ? 15 - y : y;
                c = 0;
                if ((yy < 2 && xx < 9) || (xx < 2 && yy < 9))
                    c = 1;
                else if ((yy == 2 && xx < 10) || (xx == 2 && yy < 10) ||
                         (yy < 3 && xx == 9) || (xx < 3 && yy == 9))
                    c = 2;
                if (c)
                    img[k][y * 8 + x / 2] |= (unsigned char)(x & 1 ? c : c << 4);
            }
    hz_far_copy(b, img, 512);
    corner_addr = (unsigned long)HZ_BANK(b) << 16;
    hg_color(112 + 1, 255, 255, 255);
    hg_color(112 + 2, 0, 0, 0);
}

static void spr_init(void)
{
    unsigned i;
    spr_first = hz_spr_alloc(NSPR, hg_win);
    if (spr_first < 0)
        return;
    make_corners();
    for (i = 0; i < NSPR; i++) {
        memset(&rec[i], 0, sizeof rec[i]);
        rec[i].sprite = (unsigned char)(spr_first + i);
        sent[i] = rec[i];
        sent[i].ctrl = 0xFF;            /* (sent the first time) */
    }
}

static void spr_place(unsigned n, unsigned long addr, int x, int y, unsigned pal, unsigned ctrl)
{
    if (n >= NSPR)
        return;
    if (!addr || x <= -64 || x >= 640 || y <= PANEL_H - 32 || y >= 360) {
        rec[n].ctrl = 0;
        return;
    }
    rec[n].ctrl = (unsigned char)(SPR_EN | ctrl);
    rec[n].x = x;
    rec[n].y = y;
    HZ_U24B(rec[n].image, (unsigned)(addr >> 16), (unsigned)addr);
    rec[n].pal = (unsigned char)pal;
}

static void spr_update(void)
{
    SimSprite *s;
    unsigned n = 4, i;
    int changed = 0;

    if (spr_first < 0)
        return;
    for (i = 0; i < NSPR; i++)
        rec[i].ctrl = 0;
    if (!page_on) {
        /* the tool's frame: four corners */
        if (cur_on && corner_addr) {
            int x0 = cur_x0 * (int)tile_px - cam_x, y0 = cur_y0 * (int)tile_px - cam_y + PANEL_H;
            int x1 = x0 + cur_n * (int)tile_px - 16, y1 = y0 + cur_n * (int)tile_px - 16;
            spr_place(0, corner_addr, x0, y0, 7, 0);
            spr_place(1, corner_addr + 128, x1, y0, 7, 0);
            spr_place(2, corner_addr + 256, x0, y1, 7, 0);
            spr_place(3, corner_addr + 384, x1, y1, 7, 0);
        }
        for (s = sim->sprite; s && n < NSPR; s = s->next) {
            int wx, wy, sz;
            if (!s->frame || s->type < 1 || s->type > 8)
                continue;
            wx = s->x + s->x_offset;
            wy = s->y + s->y_offset;
            sz = (int)data_sprite_size(s->type);
            if (zoom8) {
                spr_place(n++, data_sprite(s->type, s->frame - 1, 4), wx / 2 - cam_x,
                          wy / 2 - cam_y + PANEL_H, 7 + s->type, SPR_BPP4 | SPR_WIDE | SPR_TALL);
            } else if (sz == 32) {
                spr_place(n++, data_sprite(s->type, s->frame - 1, 0), wx - cam_x,
                          wy - cam_y + PANEL_H, 7 + s->type, SPR_BPP4 | SPR_WIDE | SPR_TALL);
            } else if (n + 4 <= NSPR) {
                int x = wx - cam_x, y = wy - cam_y + PANEL_H;
                for (i = 0; i < 4; i++)
                    spr_place(n++, data_sprite(s->type, s->frame - 1, i), x + (i & 1) * 32,
                              y + (i >> 1) * 32, 7 + s->type, SPR_BPP4 | SPR_WIDE | SPR_TALL);
            }
        }
    }
    for (i = 0; i < NSPR; i++)
        if (memcmp(&rec[i], &sent[i], sizeof rec[i]) != 0) {
            changed = 1;
            sent[i] = rec[i];
        }
    if (changed)
        hz_spr_set(NSPR, rec);
}

void view_cursor(int tx, int ty, int size, int on)
{
    cur_x0 = tx;
    cur_y0 = ty;
    cur_n = size;
    cur_on = on;
}

/* ---------------------------------------------------------------- the ring */

static void ring_geometry(void)
{
    tile_px = zoom8 ? 8 : 16;
    rc = zoom8 ? 82 : 41;
    rr = zoom8 ? 40 : 21;
    if (!shown)
        shown = hz_far_alloc();
    if (!shown)
        port_fatal("no memory for the view");
    hz_far_set(shown, 0xFF, 82 * 40 * 2);
    full = moved = 1;
    scr_dirty = 1;
}

void view_init(void)
{
    ring_geometry();
    spr_init();
}

void view_invalidate(void)
{
    hz_far_set(shown, 0xFF, 82 * 40 * 2);
    full = 1;
}

static void clamp(void)
{
    int mx = WORLD_X * (int)tile_px - VIEW_W, my = WORLD_Y * (int)tile_px - VIEW_H;
    if (cam_x > mx) cam_x = mx;
    if (cam_y > my) cam_y = my;
    if (cam_x < 0) cam_x = 0;
    if (cam_y < 0) cam_y = 0;
}

void view_center(int tx, int ty)
{
    cam_x = tx * (int)tile_px + (int)tile_px / 2 - VIEW_W / 2;
    cam_y = ty * (int)tile_px + (int)tile_px / 2 - VIEW_H / 2;
    clamp();
    moved = 1;
    scr_dirty = 1;
}

void view_zoom(int z8)
{
    int cx, cy;
    if ((unsigned char)(z8 != 0) == zoom8)
        return;
    cx = (cam_x + VIEW_W / 2) / (int)tile_px;
    cy = (cam_y + VIEW_H / 2) / (int)tile_px;
    zoom8 = (unsigned char)(z8 != 0);
    ring_geometry();
    hg_origin(0, 0);
    hg_fill(0, 0, FB_STRIDE, PANEL_FB, 0);
    view_center(cx, cy);
}

void view_scroll(int dx, int dy)
{
    int ox = cam_x, oy = cam_y;
    cam_x += dx;
    cam_y += dy;
    clamp();
    if (cam_x != ox || cam_y != oy) {
        moved = 1;
        scr_dirty = 1;
    }
}

void view_shake(void)
{
    shake = 60;
}

void view_page(int on)
{
    page_on = (unsigned char)(on != 0);
    scr_dirty = 1;
}

void view_update(void)
{
    unsigned c, c0, c1, r, r0, r1, rs, re, sc, tw = tile_px, n = 0;
    unsigned cap = full ? 4000 : (moved ? 260 : 120);
    const hg_image *img = zoom8 ? img_small : img_big;

    /* the unpowered zones' bolt: 0.5 s on, 0.5 off (still while the game is paused) */
    if (SimSpeed && !sim_paused && ++blink_t >= 30) {
        blink_t = 0;
        blink ^= 1;
    }
    if (!page_on && img) {
        c0 = (unsigned)cam_x / tw;
        c1 = (unsigned)(cam_x + VIEW_W - 1) / tw;
        r0 = (unsigned)cam_y / tw;
        r1 = (unsigned)(cam_y + VIEW_H - 1) / tw;
        if (c1 >= WORLD_X) c1 = WORLD_X - 1;
        if (r1 >= WORLD_Y) r1 = WORLD_Y - 1;
        /* all rows after a move; else a share of them each frame (animation, changes) */
        rs = r0;
        re = r1;
        if (!moved && !full) {
            unsigned parts = zoom8 ? 4 : 2, h = (r1 - r0 + parts) / parts;
            part = (unsigned char)((part + 1) % parts);
            rs = r0 + part * h;
            re = rs + h - 1;
            if (re > r1) re = r1;
        }
        hg_origin(0, 0);
        for (c = c0; c <= c1 && n < cap; c++) {
            short MAPFAR *col = Map[c];
            sc = c % rc;
            for (r = rs; r <= re; r++) {
                unsigned v = (unsigned short)col[r], t, i;
                if ((v & LOMASK) >= TILE_COUNT)
                    v -= TILE_COUNT;
                if (blink && (v & ZONEBIT) && !(v & PWRBIT))
                    t = LIGHTNINGBOLT;
                else
                    t = v & LOMASK;
                i = (r % rr) * rc + sc;
                if (shown[i] != t) {
                    shown[i] = (unsigned short)t;
                    if (zoom8)
                        hg_draw_part(img, (t & 511) << 3, (t >> 9) << 3, 8, 8, (int)(sc << 3),
                                     (int)((r % rr) << 3));
                    else
                        hg_draw_part(img, (t & 255) << 4, (t >> 8) << 4, 16, 16, (int)(sc << 4),
                                     (int)((r % rr) << 4));
                    ++n;
                }
            }
        }
        if (n < cap) {
            moved = 0;
            full = 0;
        }
        view_draws += n;
    }
    spr_update();
}

void view_send(void)
{
    if (shake) {
        --shake;
        scr_dirty = 1;
    }
    if (!scr_dirty)
        return;
    memset(&scr, 0, sizeof scr);
    scr.x = 0;
    scr.y = PANEL_FB;
    scr.split = PANEL_H;
    if (page_on) {
        scr.x2 = 0;
        scr.y2 = PAGE_FB;
        scr.vheight = 0;
        scr.ctrl = FSC_SPLIT;
    } else {
        int sy = cam_y + (shake ? ((shake & 2) ? 3 : -3) : 0);
        if (sy < 0) sy = 0;
        scr.x2 = (unsigned)cam_x % (rc * tile_px);
        scr.y2 = (unsigned)sy % (rr * tile_px);
        scr.vheight = rr * tile_px;
        scr.ctrl = FSC_HWRAP | FSC_SPLIT;
    }
    hz_fs_scroll(&scr);
    scr_dirty = 0;
}

/* the map as it is on the screen now, copied to the window page (menus and windows lie
 * over it there): up to four pieces, the ring wraps */
void view_copy_to_page(void)
{
    unsigned W = rc * tile_px, H = rr * tile_px;
    unsigned ox = (unsigned)cam_x % W, oy = (unsigned)cam_y % H;
    unsigned w1 = W - ox < VIEW_W ? W - ox : VIEW_W, h1 = H - oy < VIEW_H ? H - oy : VIEW_H;
    hg_origin(0, 0);
    hg_move((int)ox, (int)oy, w1, h1, 0, PAGE_FB);
    if (w1 < VIEW_W)
        hg_move(0, (int)oy, VIEW_W - w1, h1, (int)w1, PAGE_FB);
    if (h1 < VIEW_H) {
        hg_move((int)ox, 0, w1, VIEW_H - h1, 0, PAGE_FB + (int)h1);
        if (w1 < VIEW_W)
            hg_move(0, 0, VIEW_W - w1, VIEW_H - h1, (int)w1, PAGE_FB + (int)h1);
    }
}

void view_resend(void)
{
    unsigned i;
    scr_dirty = 1;
    for (i = 0; i < NSPR; i++)
        sent[i].ctrl = 0xFF;
}
