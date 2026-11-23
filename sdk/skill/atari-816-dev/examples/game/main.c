/* DOT - a game loop with hgame: full screen 320 x 180, a square moved with the arrows. */
#include <stdio.h>
#include <hgame.h>

int main(void)
{
    int x = 150, y = 80, moved = 0;

    if (hg_screen(HG_320X180 | HG_DOUBLE, "Dot") < 0)   /* two pages: drawn unseen */
        return 1;
    puts("DOT: start");
    while (hg_frame()) {                /* one frame: 60 a second; 0 when closed */
        unsigned p = hg_p1();           /* arrows, W A S D, joystick 1 */
        if (hg_key(HG_KEY_ESC))
            break;
        if (p & HG_RIGHT) { x += 2; moved = 1; }
        if (p & HG_LEFT)  { x -= 2; moved = 1; }
        if (p & HG_DOWN)  y += 2;
        if (p & HG_UP)    y -= 2;
        if (moved == 1 && !p) {         /* say it once, when the key is let go */
            printf("DOT: at %d %d\n", x, y);
            moved = 2;
        }
        hg_clear(0);
        hg_fill(x, y, 16, 16, 200);
        hg_text(8, 8, "Arrows move, Esc quits", 255);
    }
    hg_stats("DOT");                    /* frames, missed frames, CPU a frame */
    return 0;                           /* hg_close() runs at exit */
}
