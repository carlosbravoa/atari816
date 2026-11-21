/* step4.c - a world larger than the screen: a scrolling tile map, a panel, hardware
 * sprites (sdk/docs/c/games.md) */
#include <stdio.h>
#include <string.h>
#include <hgame.h>
#include "art/ship.h"
#include "art/star.h"

#define MW 60                               /* the world: 60 x 30 tiles of 16 */
#define MH 30
#define NSTARS 12

static unsigned char map[MW * MH];
static unsigned char tilepx[3 * 256];
static int sx[NSTARS], sy[NSTARS];

/* three tiles made here: space, space with a far star, a nebula */
static void maketiles(void)
{
    unsigned i;
    memset(tilepx, 16 + 1, sizeof tilepx);          /* cube 0 0 1: dark blue */
    tilepx[256 + 5 * 16 + 9] = 250;                 /* a grey dot */
    for (i = 0; i < 256; i++)
        if ((i % 16 + i / 16) % 5 < 2)
            tilepx[512 + i] = 16 + 36 + 2;          /* cube 1 0 2: purple streaks */
}

static void place(unsigned i)
{
    sx[i] = 16 + (int)hg_rand_n(MW * 16 - 32);
    sy[i] = 16 + (int)hg_rand_n(MH * 16 - 32);
}

int main(void)
{
    hg_image *tiles, *shipimg, *starimg;
    int x = 400, y = 200, scx, scy;
    unsigned j, t = 0, i, score = 0, panel = 1;
    char line[40];

    if (hg_screen(HG_320X180, "Step 4") < 0)       /* one page: Marga scrolls */
        return 1;
    maketiles();
    tiles = hg_image_from(tilepx, 16, 16, 3, HG_NONE);
    shipimg = hg_image_from(ship, SHIP_W, SHIP_H, SHIP_N, SHIP_KEY);
    starimg = hg_image_from(star, STAR_W, STAR_H, STAR_N, STAR_KEY);
    for (i = 0; i < MW * MH; i++)
        map[i] = (unsigned char)(hg_rand_n(10) < 2 ? 1 : (i / MW + i % MW / 3) % 9 == 0);
    for (i = 0; i < MW * MH; i += 7)
        if (hg_rand_n(4) == 0)
            map[i] = 2;
    if (hg_map(map, MW, MH, tiles, 16) < 0)        /* 16 rows of panel at the top */
        return 1;
    if (hg_sprites(NSTARS + 1) < 0)                 /* the ship and the stars */
        return 1;
    for (i = 0; i < NSTARS; i++)
        place(i);
    while (hg_frame()) {
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        j = hg_p1();
        if (j & HG_LEFT)  x -= 2;
        if (j & HG_RIGHT) x += 2;
        if (j & HG_UP)    y -= 2;
        if (j & HG_DOWN)  y += 2;
        x = HG_CLAMP(x, 0, MW * 16 - 16);
        y = HG_CLAMP(y, 0, MH * 16 - 16);
        ++t;
        hg_camera(x - 152, y - 74);                 /* the ship in the middle */
        for (i = 0; i < NSTARS; i++) {
            if (hg_overlap(x + 3, y + 3, 10, 10, sx[i] + 3, sy[i] + 3, 10, 10)) {
                ++score;
                panel = 1;
                place(i);
                printf("STEP4: score %u\n", score);
            }
            scx = hg_screen_x(sx[i]);               /* world -> screen */
            scy = hg_screen_y(sy[i]);
            hg_sprite_set(1 + i, starimg, ((t >> 4) + i) & 1,
                          scx > -16 && scx < 320 && scy > 0 && scy < 180 ? 0 : HG_HIDE);
            hg_sprite_pos(1 + i, scx, scy);
        }
        hg_sprite_set(0, shipimg, (t >> 2) & 1, 0);
        hg_sprite_pos(0, hg_screen_x(x), hg_screen_y(y));
        if (panel) {                                /* the panel only when it changes */
            hg_origin(0, hg_panel_y);
            hg_fill(0, 0, 320, 16, 16 + 1);
            sprintf(line, "Step 4: score %u", score);
            hg_text(8, 3, line, 1);
            hg_origin(0, 0);
            panel = 0;
        }
    }
    hg_stats("STEP4");
    return 0;
}
