/* CLICKS - a window with a label and a button (the controls library, hui.h). */
#include <stdio.h>
#include <horizon.h>
#include <hui.h>

static ui_label  l_info = UI_LABEL(UI_GAP, 12, 160, 0, "Click the button.");
static ui_button b_go   = UI_BUTTON(UI_GAP, 40, 64, UF_DEFAULT, "Click");
static ui_ctlref ctls[] = { &l_info, &b_go, 0 };

int main(void)
{
    hz_winopen wo;
    unsigned own, clicks = 0;
    int win;
    char msg[32];

    own = hz_ws_start();                /* 1 if we started the window system */
    ui_init();
    wo.x = 100; wo.y = 80;              /* outer top left; content at (101, 96) */
    wo.w = 200; wo.h = 80;              /* content size */
    wo.flags = 0;
    HZ_U24(wo.title, "Clicks");
    win = hz_win_open(&wo);
    if (win < 0)
        return 1;
    ui_setwin(ctls, (unsigned)win);
    ui_drawall(ctls);
    puts("CLICKS: open");               /* under the Desktop this goes to the log */

    for (;;) {
        void *c;
        if (ui_getev(0))                /* wait for an event */
            continue;
        if (ui_event(ctls, &c) == UA_CLICK && c == &b_go) {
            sprintf(msg, "Clicked %u time(s).", ++clicks);
            ui_text((unsigned)win, UI_GAP, 64, 0, UI_INK(C_TITLE, C_BODY), msg);
            printf("CLICKS: %u\n", clicks);
        } else if (ui_ev.type == WE_CLOSE) {
            break;
        }
    }
    hz_win_close((unsigned)win);
    if (own)
        hz_ws_stop();
    return 0;
}
