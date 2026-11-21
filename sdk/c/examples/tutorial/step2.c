/* step2.c - an image made by img2c.py, drawn by the blitter (sdk/docs/c/games.md) */
#include <stdio.h>
#include <hgame.h>
#include "art/ship.h"                       /* made by: img2c.py art/ship.txt -o art/ship.h */

int main(void)
{
    hg_image *shipimg;
    int x = 152, y = 82;
    unsigned j, t = 0;
    char line[40];

    if (hg_screen(HG_320X180 | HG_DOUBLE, "Step 2") < 0)
        return 1;
    shipimg = hg_image_from(ship, SHIP_W, SHIP_H, SHIP_N, SHIP_KEY);
    if (!shipimg)
        return 1;
    while (hg_frame()) {
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        j = hg_p1();
        if (j & HG_LEFT)  x -= 2;
        if (j & HG_RIGHT) x += 2;
        if (j & HG_UP)    y -= 2;
        if (j & HG_DOWN)  y += 2;
        x = HG_CLAMP(x, 0, 304);            /* stay on the screen */
        y = HG_CLAMP(y, 16, 164);
        ++t;
        hg_clear(0);
        hg_draw(shipimg, (t >> 2) & 1, x, y);  /* frame 0 or 1: the flame flickers */
        sprintf(line, "Step 2: x %3d  y %3d", x, y);
        hg_text(8, 4, line, 1);
    }
    return 0;
}
