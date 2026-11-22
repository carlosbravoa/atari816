/* gt_map.c - hgame's test: a scrolling tile map in full screen: the ring of tile slots
 * (read back from the framebuffer), the camera (kept inside the world), a panel at the top
 * and then at the bottom, tiles changed while shown, the border outside the world. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

#define MW 64
#define MH 40

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s map: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static unsigned char tiles[4 * 256], map[MW * MH];

/* the slot of world tile (c, r) holds tile t (its colour 50 + t, the corner 1)? */
static int slot_is(unsigned c, unsigned r, unsigned t, unsigned rc, unsigned rr)
{
    int x = (int)(c % rc) * 16, y = (int)(r % rr) * 16;
    return hg_peek(x + 5, y + 5) == 50 + t && hg_peek(x, y) == 1;
}

int main(void)
{
    hg_image *ti;
    unsigned long t0 = hg_ms();
    unsigned i, c, r, rc, rr, ok;

    if (hg_screen(HG_320X180, "gt_map") < 0) {
        printf("FAIL map: hg_screen\n");
        return 1;
    }
    for (i = 0; i < 4 * 256; i++)       /* tile t: colour 50 + t, its top left pixel 1 */
        tiles[i] = (i & 255) == 0 ? 1 : (unsigned char)(50 + i / 256);
    for (r = 0; r < MH; r++)
        for (c = 0; c < MW; c++)
            map[r * MW + c] = (unsigned char)((c / 2 + r) % 3);
    ti = hg_image_from(tiles, 16, 16, 4, HG_NONE);
    hg_map_border(3);
    check("hg_map with a panel at the top", hg_map(map, MW, MH, ti, 16) == 0);
    rc = hg_fb_stride / 16;
    rr = (hg_fb_rows - 16) / 16;
    check("the ring: 21 x 12 slots, the panel below", rc == 21 && rr == 12 &&
          hg_panel_y == 192 && hg_play_y == 16);
    hg_origin(0, hg_panel_y);
    hg_fill(0, 0, 320, 16, 9);
    hg_text(4, 3, "panel at the top", 1);
    hg_origin(0, 0);
    hg_frame();
    hg_camera(0, 0);
    hg_flush(1);
    ok = 1;
    for (r = 0; r < rr; r++)
        for (c = 0; c < rc; c++)
            if (!slot_is(c, r, (c / 2 + r) % 3, rc, rr))
                ok = 0;
    check("every slot drawn", ok);
    while (hg_ms() - t0 < 1500 && hg_frame())        /* shot 1 at 1 s */
        ;
    /* scroll right and down a pixel at a time, then check the slots in view */
    for (i = 0; i < 100 && hg_frame(); i++)
        hg_camera((int)i * 3, (int)i);
    hg_flush(1);
    check("the camera", hg_cam_x == 297 && hg_cam_y == 99);
    ok = 1;
    for (r = 99 / 16; r <= (99 + 163) / 16; r++)
        for (c = 297 / 16; c <= (297 + 319) / 16; c++)
            if (!slot_is(c, r, (c / 2 + r) % 3, rc, rr))
                ok = 0;
    check("the slots in view after scrolling", ok);
    hg_map_set(25, 10, 3);
    hg_flush(1);
    check("a tile changed in view", slot_is(25, 10, 3, rc, rr) && hg_map_get(25, 10) == 3);
    check("the border outside the world", hg_map_get(MW, 0) == 3);
    while (hg_ms() - t0 < 3500 && hg_frame())        /* shot 2 at 3.3 s: the camera stopped */
        ;
    hg_frame();
    hg_camera(5000, 5000);                  /* kept inside: the world's last screen */
    check("the camera kept inside", hg_cam_x == MW * 16 - 320 && hg_cam_y == MH * 16 - 164);
    hg_camera(-50, 30000);
    check("... at every edge", hg_cam_x == 0 && hg_cam_y == MH * 16 - 164);
    /* a panel at the bottom */
    check("hg_map with a panel at the bottom", hg_map(map, MW, MH, ti, -20) == 0);
    check("the playfield on top", hg_play_y == 0);
    hg_origin(0, hg_panel_y);
    hg_fill(0, 0, 320, 20, 12);
    hg_text(4, 5, "panel at the bottom", 1);
    hg_origin(0, 0);
    for (i = 0; i < 60 && hg_frame(); i++)
        hg_camera(400 - (int)i * 4, 200 + (int)i * 2);
    while (hg_ms() - t0 < 6000 && hg_frame())        /* shot 3 at 5.5 s */
        ;
    printf("gt_map: %u failed\n", fails);
    return 0;
}
