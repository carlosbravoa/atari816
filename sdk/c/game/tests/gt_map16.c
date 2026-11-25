/* gt_map16.c - hgame's test: the scrolling map with 16-bit tile numbers (hg_map16), tiles
 * from one wide sheet (4096 x 64: 1,024 tiles of 16 x 16, Micropolis's 960 among them), a
 * map of 120 x 100 cells in far memory, not copied. Checked from the framebuffer: every
 * tile in view after scrolling across the ring's edge both ways (right / down, then left /
 * up), by 2.5 tiles a frame, by a jump; that a scroll draws only the tiles that come into
 * view (the cells function counts its calls); hg_map_set, hg_map_refresh (the map written
 * by the game), hg_map_cells (a map column after column), a panel at the bottom, bad
 * arguments. Pictures at the states the program prints ("gt_map16: shot N"), not by the
 * clock. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

#define MW 120
#define MH 100
#define NT 960

static unsigned fails;
static unsigned __far *m;       /* the map: row after row */
static unsigned __far *mt;      /* another one, column after column (hg_map_cells) */
static unsigned rc, rr, playh, calls;

static void check(const char *what, int ok)
{
    printf("%s map16: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static unsigned val(unsigned c, unsigned r)
{
    return (c * 37u + r * 11u) % NT;
}

static unsigned val2(unsigned c, unsigned r)
{
    return (c * 5u + r * 101u + 300u) % NT;
}

static unsigned colfn(unsigned c, unsigned r)
{
    ++calls;
    return mt[c * MH + r];
}

/* the slot of world tile (c, r) holds tile t? (its low byte at (5, 5), 100 + its high
 * byte at (6, 5), colour 1 at the corner) */
static int slot_is(unsigned c, unsigned r, unsigned t)
{
    int x = (int)(c % rc) * 16, y = (int)(r % rr) * 16;
    return hg_peek(x + 5, y + 5) == (t & 255) && hg_peek(x + 6, y + 5) == 100 + (t >> 8) &&
           hg_peek(x, y) == 1;
}

/* every tile in view as the map says (fn: row-major m, or mt) */
static int view_ok(int second)
{
    unsigned c, r, c0, c1, r0, r1;
    hg_flush(1);
    c0 = (unsigned)hg_cam_x / 16;
    c1 = ((unsigned)hg_cam_x + 319) / 16;
    r0 = (unsigned)hg_cam_y / 16;
    r1 = ((unsigned)hg_cam_y + playh - 1) / 16;
    for (r = r0; r <= r1 && r < MH; r++)
        for (c = c0; c <= c1 && c < MW; c++)
            if (!slot_is(c, r, second ? mt[c * MH + r] : m[r * MW + c])) {
                printf("  slot of (%u, %u) wrong\n", c, r);
                return 0;
            }
    return 1;
}

/* a picture: say so, then hold it (the script waits for the line) */
static void shot(unsigned k)
{
    unsigned i;
    printf("gt_map16: shot %u\n", k);
    for (i = 0; i < 40 && hg_frame(); i++)
        ;
}

static void panel(const char *s, unsigned h)
{
    hg_origin(0, hg_panel_y);
    hg_fill(0, 0, 320, h, 9);
    hg_text(4, (int)(h - 10) / 2, s, 1);
    hg_origin(0, 0);
}

int main(void)
{
    hg_image *sheet;
    unsigned i, c, r, t, ok, x, y;
    unsigned char __far *px;
    unsigned long a;

    if (hg_screen(HG_320X180, "gt_map16") < 0) {
        printf("FAIL map16: hg_screen\n");
        return 1;
    }
    /* the sheet: tile t a colour of its own, its number in two pixels, the corner 1 */
    sheet = hg_image_new(4096, 64, 1);
    check("a sheet of 4096 x 64 (a kernel sheet)", sheet && sheet->sheet);
    if (!sheet)
        return 1;
    for (t = 0; t < 1024; t++) {
        x = (t & 255) * 16;
        y = (t >> 8) * 16;
        hg_image_fill(sheet, (int)x, (int)y, 16, 16, 16 + t % 200);
        a = hg_image_addr(sheet, 0) + (unsigned long)y * 4096 + x;
        px = (unsigned char __far *)a;
        px[0] = 1;
        px[5u * 4096u + 5u] = (unsigned char)(t & 255);
        px[5u * 4096u + 6u] = (unsigned char)(100 + (t >> 8));
    }
    m = (unsigned __far *)hz_far_alloc();
    mt = (unsigned __far *)hz_far_alloc();
    if (!m || !mt) {
        printf("FAIL map16: no far memory\n");
        return 1;
    }
    for (r = 0; r < MH; r++)
        for (c = 0; c < MW; c++) {
            m[r * MW + c] = val(c, r);
            mt[c * MH + r] = val2(c, r);
        }

    /* refused: too many cells, tiles too small, a sheet of 4 bpp is checked too */
    check("a map of more than 32,768 cells is refused", hg_map16(m, 200, 200, sheet, 16, 16,
                                                                  0) < 0);
    check("tiles below 8 x 8 are refused", hg_map16(m, MW, MH, sheet, 4, 16, 0) < 0);
    check("no map and no cells function is refused", hg_map16(0, MW, MH, sheet, 16, 16,
                                                               0) < 0);

    /* a panel of 16 rows at the top */
    check("hg_map16 with a panel at the top", hg_map16(m, MW, MH, sheet, 16, 16, 16) == 0);
    rc = hg_fb_stride / 16;
    rr = (hg_fb_rows - 16) / 16;
    playh = 164;
    check("the ring: 21 x 12 slots, the panel below it", rc == 21 && rr == 12 &&
          hg_panel_y == 192 && hg_play_y == 16);
    panel("hg_map16: 16-bit tiles", 16);
    hg_frame();
    check("every tile in view drawn", view_ok(0));
    check("tile numbers above 255 shown (cell (1, 0) = 37, (7, 0) = 259)",
          val(7, 0) == 259 && slot_is(7, 0, 259));
    shot(1);

    /* right and down a few pixels a frame: across the ring's right and bottom edges
     * (336 x 192 pixels) more than once */
    ok = 1;
    for (i = 1; i <= 160 && hg_frame(); i++) {
        hg_camera((int)i * 5, (int)i * 3);
        if (i % 40 == 0 && !view_ok(0))
            ok = 0;
    }
    check("scrolled right and down past the ring's edges", ok && hg_cam_x == 800 &&
          hg_cam_y == 480 && view_ok(0));
    /* left and up: across its left and top edges */
    ok = 1;
    for (i = 1; i <= 140 && hg_frame(); i++) {
        hg_camera(800 - (int)i * 5, 480 - (int)i * 3);
        if (i % 35 == 0 && !view_ok(0))
            ok = 0;
    }
    check("scrolled left and up past the ring's edges", ok && hg_cam_x == 100 &&
          hg_cam_y == 60 && view_ok(0));
    /* 40 pixels a frame (2.5 tiles) right, then 40 left and up: every frame checked */
    ok = 1;
    for (i = 1; i <= 20 && hg_frame(); i++) {
        hg_camera(100 + (int)i * 40, 60 + (int)i * 24);
        if (!view_ok(0))
            ok = 0;
    }
    check("40 pixels a frame, right and down", ok && hg_cam_x == 900 && hg_cam_y == 540);
    ok = 1;
    for (i = 1; i <= 20 && hg_frame(); i++) {
        hg_camera(900 - (int)i * 40, 540 - (int)i * 24);
        if (!view_ok(0))
            ok = 0;
    }
    check("40 pixels a frame, left and up", ok && hg_cam_x == 100 && hg_cam_y == 60);
    hg_frame();
    hg_camera(1500, 1300);                          /* a jump: the ring anew */
    check("a jump of several screens", view_ok(0));
    hg_frame();
    hg_camera(5000, 5000);                          /* kept inside */
    check("the camera kept inside", hg_cam_x == MW * 16 - 320 && hg_cam_y == MH * 16 - 164 &&
          view_ok(0));
    hg_frame();
    hg_camera(1003, 707);
    hg_frame();

    /* a tile set; the map written by the game, then hg_map_refresh */
    hg_map_set(70, 50, 700);
    check("hg_map_set: in the map and on the screen", m[50 * MW + 70] == 700 &&
          hg_map_get(70, 50) == 700 && slot_is(70, 50, 700));
    hg_map_set(MW, 3, 5);                           /* outside: nothing */
    hg_map_border(901);
    check("the border outside the world", hg_map_get(MW, 0) == 901 && hg_map_get(0, MH) == 901);
    m[48 * MW + 66] = 950;                          /* the game writes two cells in view */
    m[52 * MW + 75] = 3;
    check("hg_map_refresh(0): the two changed tiles drawn", hg_map_refresh(0) == 2 &&
          slot_is(66, 48, 950) && slot_is(75, 52, 3));
    check("... and then nothing", hg_map_refresh(0) == 0);
    m[50 * MW + 64] = 951;
    t = 0;
    for (i = 0; i < 11; i++)                        /* the view's 11 rows, one a call */
        t += hg_map_refresh(1);
    check("hg_map_refresh(1) eleven times: the whole view", t == 1 && slot_is(64, 50, 951));
    check("the view after the changes", view_ok(0));
    shot(2);

    /* the cells from a function (a map column after column), a panel at the bottom */
    hg_map_cells(colfn);
    check("hg_map16 from hg_map_cells, a panel at the bottom",
          hg_map16(0, MW, MH, sheet, 16, 16, -20) == 0);
    playh = 160;
    rr = (hg_fb_rows - 20) / 16;
    check("the playfield on top, a ring of 21 x 11", hg_play_y == 0 && rr == 11 &&
          hg_panel_y == (int)rr * 16);
    panel("hg_map_cells, panel below", 20);
    hg_frame();
    check("every tile in view drawn (column after column)", view_ok(1));
    calls = 0;
    hg_camera(16, 0);
    check("one tile right: one column of the ring drawn (11 calls)", calls == rr);
    calls = 0;
    hg_camera(64, 0);
    check("three tiles right in a frame: three columns", calls == 3 * rr);
    calls = 0;
    hg_camera(64, 16);
    check("one tile down: one row", calls == rc);
    calls = 0;
    hg_camera(65, 23);
    check("pixels within the tiles: nothing drawn", calls == 0);
    hg_frame();
    check("the view", view_ok(1));
    ok = 1;
    for (i = 1; i <= 30 && hg_frame(); i++) {
        hg_camera(65 + (int)i * 37, 23 + (int)i * 29);   /* 2.3 x 1.8 tiles a frame */
        if (!view_ok(1))
            ok = 0;
    }
    for (i = 1; i <= 30 && hg_frame(); i++) {
        hg_camera(1175 - (int)i * 33, 893 - (int)i * 27);
        if (!view_ok(1))
            ok = 0;
    }
    check("37 / 29 pixels a frame there and 33 / 27 back", ok && hg_cam_x == 185 &&
          hg_cam_y == 83);
    hg_map_cells(0);
    shot(3);
    printf("gt_map16: %u failed\n", fails);
    return 0;
}
