/* uidemo.c - C calling Horizon's controls library (ui.lib) through hz/uibind.s:
 * a window with a label and two buttons; "Count" counts, "Quit" (or the close box) ends.
 */
#include <stdio.h>
#include "horizon.h"

/* ui.inc structures (the common 12-byte header + one pointer) */
#define UT_BUTTON 1
#define UT_LABEL  6
#define UF_DEFAULT 2
#define UA_CLICK  2
typedef struct {
    unsigned char type, win;
    int x, y, w, h;
    unsigned flags;
    const char *text;           /* BT_LABEL / LB_TEXT: a 16-bit pointer in the code bank */
} ui_ctl_t;

void ui_init(void);
unsigned char __fastcall__ ui_getev(unsigned char poll);
void __fastcall__ ui_drawall(void **list);
unsigned char __fastcall__ ui_event(void **list);
extern hz_event_t ui_ev;
extern ui_ctl_t *ui_ctl;

static hz_wopen_t wo;
static char msg[32] = "Not clicked yet";
static ui_ctl_t label = { UT_LABEL,  0, 12, 12, 200, 12, 0, msg };
static ui_ctl_t count = { UT_BUTTON, 0, 12, 40, 72, 20, UF_DEFAULT, "Count" };
static ui_ctl_t quit  = { UT_BUTTON, 0, 96, 40, 72, 20, 0, "Quit" };
static void *list[] = { &label, &count, &quit, 0 };

int main(void)
{
    unsigned char own, win, ua;
    unsigned n = 0;
    own = (unsigned char)hz_ws_start();
    ui_init();
    wo.x = 200; wo.y = 120; wo.w = 220; wo.h = 72;
    HZ_FAR(wo.title, "C + ui.lib");
    win = (unsigned char)hz_win_open(&wo);
    label.win = count.win = quit.win = win;
    ui_drawall(list);
    for (;;) {
        ui_getev(0);
        ua = ui_event(list);
        if (ua == UA_CLICK && ui_ctl == &count) {
            ++n;
            sprintf(msg, "Clicked %u time%s", n, n == 1 ? "" : "s");
            ui_drawall(list);
            printf("CUI: %s\n", msg);
        } else if ((ua == UA_CLICK && ui_ctl == &quit) || ui_ev.type == WE_CLOSE) {
            break;
        }
    }
    hz_win_close(win);
    if (own) hz_ws_stop();
    puts("CUI: closed");
    return 0;
}
