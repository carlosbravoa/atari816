/* step5.c - a whole small game: a title, 30 seconds of play, game over; music; the
 * frame statistics at the end (sdk/docs/c/games.md) */
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

enum { TITLE, PLAY, OVER };

static void panel(const char *s)
{
    hg_origin(0, hg_panel_y);
    hg_fill(0, 0, 320, 16, 16 + 1);
    hg_text(8, 3, s, 1);
    hg_origin(0, 0);
}

int main(void)
{
    hg_image *tiles, *shipimg, *starimg;
    hg_sound *ding;
    int x = 400, y = 200, scx, scy, state = TITLE;
    unsigned j, t = 0, i, score = 0, best = 0, secs = 0, shown = 99;
    unsigned long start = 0;
    char line[48];

    if (hg_screen(HG_320X180, "Step 5") < 0)
        return 1;
    maketiles();
    tiles = hg_image_from(tilepx, 16, 16, 3, HG_NONE);
    shipimg = hg_image_from(ship, SHIP_W, SHIP_H, SHIP_N, SHIP_KEY);
    starimg = hg_image_from(star, STAR_W, STAR_H, STAR_N, STAR_KEY);
    ding = hg_sound_make(HG_SINE, 1320, 150, 60);
    for (i = 0; i < MW * MH; i++)
        map[i] = (unsigned char)(hg_rand_n(10) < 2 ? 1 : (i / MW + i % MW / 3) % 9 == 0);
    for (i = 0; i < MW * MH; i += 7)
        if (hg_rand_n(4) == 0)
            map[i] = 2;
    if (hg_map(map, MW, MH, tiles, 16) < 0 || hg_sprites(NSTARS + 1) < 0)
        return 1;
    hg_music_play("/Music/LAU.MOD", 1);            /* (no file: no music, the game goes on) */
    panel("STAR SWEEP   Space: 30 seconds, go!");
    while (hg_frame()) {
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        ++t;
        if (state != PLAY) {                        /* the title and game over: wait */
            hg_camera((int)(t % (MW * 16)), 100);   /* (the world drifts by) */
            if (hg_p1_pressed() & HG_FIRE) {
                state = PLAY;
                score = 0;
                start = hg_ms();
                for (i = 0; i < NSTARS; i++)
                    place(i);
                printf("STEP5: play\n");
            }
            for (i = 0; i <= NSTARS; i++)
                hg_sprite_show(i, 0);
            continue;
        }
        secs = (unsigned)((hg_ms() - start) / 1000);
        if (secs >= 30) {
            state = OVER;
            if (score > best)
                best = score;
            sprintf(line, "GAME OVER: %u stars (best %u). Space", score, best);
            panel(line);
            printf("STEP5: game over, %u\n", score);
            shown = 99;
            continue;
        }
        j = hg_p1();
        if (j & HG_LEFT)  x -= 2;
        if (j & HG_RIGHT) x += 2;
        if (j & HG_UP)    y -= 2;
        if (j & HG_DOWN)  y += 2;
        x = HG_CLAMP(x, 0, MW * 16 - 16);
        y = HG_CLAMP(y, 0, MH * 16 - 16);
        hg_camera(x - 152, y - 74);
        for (i = 0; i < NSTARS; i++) {
            if (hg_overlap(x + 3, y + 3, 10, 10, sx[i] + 3, sy[i] + 3, 10, 10)) {
                ++score;
                shown = 99;
                place(i);
                hg_play(ding, 200);
            }
            scx = hg_screen_x(sx[i]);
            scy = hg_screen_y(sy[i]);
            hg_sprite_set(1 + i, starimg, ((t >> 4) + i) & 1,
                          scx > -16 && scx < 320 && scy > 0 && scy < 180 ? 0 : HG_HIDE);
            hg_sprite_pos(1 + i, scx, scy);
        }
        hg_sprite_set(0, shipimg, (t >> 2) & 1, 0);
        hg_sprite_pos(0, hg_screen_x(x), hg_screen_y(y));
        if (shown != score + secs * 256) {          /* the panel when a number changes */
            shown = score + secs * 256;
            sprintf(line, "STARS %2u   TIME %2u", score, 30 - secs);
            panel(line);
        }
    }
    hg_stats("STEP5");
    return 0;
}
