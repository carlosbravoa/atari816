/* step1.c - an empty window, closed by its close box */
#include <stdio.h>
#include <horizon.h>
#include <hui.h>

int main(void)
{
    hz_winopen wo;
    unsigned own;
    int win;

    own = hz_ws_start();                /* the window system: 1 if we started it */
    ui_init();                          /* the controls library, once, after it */
    wo.x = 100;                         /* the window's outer top left on the screen */
    wo.y = 60;
    wo.w = 320;                         /* its content's size */
    wo.h = 160;
    HZ_U24(wo.title, "Guests");         /* a 3-byte pointer in the block */
    wo.flags = 0;
    win = hz_win_open(&wo);
    if (win < 0)
        return 1;

    for (;;) {
        if (ui_getev(0))                /* wait for the next event, into ui_ev */
            continue;
        if (ui_ev.type == WE_CLOSE)     /* the close box, or the Desktop's Shut down */
            break;
    }
    printf("guests: closed\n");
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
