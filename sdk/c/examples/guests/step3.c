/* step3.c - menus, keyboard shortcuts and an alert */
#include <stdio.h>
#include <horizon.h>
#include <hui.h>

static char name[32];
static ui_label l_name = UI_LABEL(8, 12, 44, 0, "Name:");
static ui_field f_name = UI_FIELD(56, 9, 176, UF_FOCUS, name, sizeof name);
static ui_button b_add = UI_BUTTON(240, 8, 72, UF_DEFAULT, "Add");
static ui_ctlref ctls[] = { &l_name, &f_name, &b_add, 0 };

/* the menus: "title", the items, "" for each menu, then "" (TAB: the shortcut's text;
 * "-": a separator, which counts as an item) */
static const char menus[] = "File\0Quit\tCtrl+Q\0\0"
                            "Help\0About...\0\0";
/* an alert: kind, title, text (lines split by \n), buttons (the first is the default) */
static ui_alertblk about = { AL_INFO, "About Guests", "Guests 1.0\nthe C tutorial's application.",
                             "OK", 0, 0 };

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
    hz_win_menu(win, menus);            /* the menu bar shows them while we have the focus */
    ui_setwin(ctls, win);
    ui_drawall(ctls);

    for (;;) {
        void *c;
        if (ui_getev(0))
            continue;
        switch (ui_event(ctls, &c)) {
        case UA_CLICK:
            if (c == &b_add) {
                char line[48];
                sprintf(line, "Welcome, %s!          ", name);
                ui_text(win, 8, 140, 0, UI_INK(C_BLACK, C_BODY), line);
                ui_fdset(&f_name, "");
            }
            break;
        case UA_NONE:
            if (ui_ev.type == WE_CLOSE)
                goto out;
            if (ui_ev.type == WE_MENU) {        /* a = menu (0: File), b = item */
                if (ui_ev.a == 1)
                    printf("guests: about %u\n", ui_alert(&about));     /* the button */
                else
                    goto out;                   /* File > Quit */
            }
            if (ui_ev.type == WE_KEY && (ui_ev.b & 0x100) && (ui_ev.b & 0x11) &&
                ui_ev.a == 0x14)                /* pressed (b & $100) with ctrl: Q */
                goto out;
            break;
        }
    }
out:
    printf("guests: quit\n");
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
