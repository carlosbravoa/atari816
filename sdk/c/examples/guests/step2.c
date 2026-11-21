/* step2.c - controls: a label, a text field, a button */
#include <stdio.h>
#include <horizon.h>
#include <hui.h>

static char name[32];                   /* the field's text */
static ui_label l_name = UI_LABEL(8, 12, 44, 0, "Name:");
static ui_field f_name = UI_FIELD(56, 9, 176, UF_FOCUS, name, sizeof name);
static ui_button b_add = UI_BUTTON(240, 8, 72, UF_DEFAULT, "Add");
static ui_ctlref ctls[] = { &l_name, &f_name, &b_add, 0 };

int main(void)
{
    hz_winopen wo;
    unsigned own;
    int win;

    own = hz_ws_start();
    ui_init();
    wo.x = 100;
    wo.y = 60;
    wo.w = 320;
    wo.h = 160;
    HZ_U24(wo.title, "Guests");
    wo.flags = 0;
    win = hz_win_open(&wo);
    if (win < 0)
        return 1;
    ui_setwin(ctls, win);               /* the controls are in this window */
    ui_drawall(ctls);

    for (;;) {
        void *c;
        if (ui_getev(0))
            continue;
        switch (ui_event(ctls, &c)) {   /* the controls take their events first */
        case UA_CLICK:                  /* Add, or Enter: the default button */
            if (c == &b_add) {
                char line[48];
                sprintf(line, "Welcome, %s!          ", name);
                ui_text(win, 8, 140, 0, UI_INK(C_BLACK, C_BODY), line);
                printf("guests: welcome %s\n", name);
                ui_fdset(&f_name, "");  /* empty the field for the next one */
            }
            break;
        case UA_NONE:                   /* not for a control: ours */
            if (ui_ev.type == WE_CLOSE)
                goto out;
            break;
        }
    }
out:
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
