/* step1.c - a screen and a box that moves (sdk/docs/c/games.md, the tutorial) */
#include <hgame.h>

int main(void)
{
    int x = 152, y = 82;
    unsigned j;

    if (hg_screen(HG_320X180 | HG_DOUBLE, "Step 1") < 0)    /* full screen, two pages */
        return 1;
    while (hg_frame()) {                    /* 60 times a second */
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        j = hg_p1();                        /* arrows, W A S D, joystick 1 */
        if (j & HG_LEFT)  x -= 2;
        if (j & HG_RIGHT) x += 2;
        if (j & HG_UP)    y -= 2;
        if (j & HG_DOWN)  y += 2;
        hg_clear(0);                        /* the whole frame, drawn unseen */
        hg_fill(x, y, 16, 16, 196);
        hg_text(8, 8, "Step 1: the arrows move the box", 1);
    }
    return 0;
}
