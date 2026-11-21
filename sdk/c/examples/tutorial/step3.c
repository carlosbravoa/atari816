/* step3.c - things to collect, a score, sound (sdk/docs/c/games.md) */
#include <stdio.h>
#include <hgame.h>
#include "art/ship.h"
#include "art/star.h"

#define NSTARS 6

static int sx[NSTARS], sy[NSTARS];

static void place(unsigned i)
{
    sx[i] = 8 + (int)hg_rand_n(296);
    sy[i] = 24 + (int)hg_rand_n(140);
}

int main(void)
{
    hg_image *shipimg, *starimg;
    hg_sound *ding;
    int x = 152, y = 82;
    unsigned j, t = 0, i, score = 0;
    char line[40];

    if (hg_screen(HG_320X180 | HG_DOUBLE, "Step 3") < 0)
        return 1;
    shipimg = hg_image_from(ship, SHIP_W, SHIP_H, SHIP_N, SHIP_KEY);
    starimg = hg_image_from(star, STAR_W, STAR_H, STAR_N, STAR_KEY);
    ding = hg_sound_make(HG_SINE, 1320, 150, 60);   /* a sample, made here */
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
        x = HG_CLAMP(x, 0, 304);
        y = HG_CLAMP(y, 16, 164);
        ++t;
        for (i = 0; i < NSTARS; i++)
            if (hg_overlap(x + 3, y + 3, 10, 10, sx[i] + 3, sy[i] + 3, 10, 10)) {
                ++score;
                place(i);                   /* somewhere else */
                if (hg_play(ding, 200) < 0) /* no Lau (older boards): POKEY */
                    hg_sfx(0, 60, -4, 12, 1, 8, HG_TONE);
                printf("STEP3: score %u\n", score);
            }
        hg_clear(0);
        for (i = 0; i < NSTARS; i++)
            hg_draw(starimg, ((t >> 4) + i) & 1, sx[i], sy[i]);
        hg_draw(shipimg, (t >> 2) & 1, x, y);
        sprintf(line, "Step 3: score %u", score);
        hg_text(8, 4, line, 1);
    }
    return 0;
}
