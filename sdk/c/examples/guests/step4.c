/* step4.c - a list: rows from a C function, a status line */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include <hui.h>

#define MAXG 50

static char guests[MAXG][32];           /* the list's data */
static unsigned nguests;
static char name[32];
static char status[48];                 /* the status label's text */

/* the list asks for each row's text when it draws it */
static const char *guest_row(ui_list *ls, unsigned row, const ui_rowinfo *ri)
{
    return guests[row];                 /* the library copies it */
}

static ui_label l_name = UI_LABEL(8, 12, 44, 0, "Name:");
static ui_field f_name = UI_FIELD(56, 9, 176, UF_FOCUS, name, sizeof name);
static ui_button b_add = UI_BUTTON(240, 8, 72, UF_DEFAULT, "Add");
static ui_list l_guests = UI_LIST(8, 36, 304, 96, 0, guest_row);
static ui_label l_status = UI_LABEL(8, 140, 180, 0, status);
static ui_ctlref ctls[] = { &l_name, &f_name, &b_add, &l_guests, &l_status, 0 };

static const char menus[] = "File\0Quit\tCtrl+Q\0\0"
                            "Help\0About...\0\0";
static ui_alertblk about = { AL_INFO, "About Guests", "Guests 1.0\nthe C tutorial's application.",
                             "OK", 0, 0 };

static void show_status(void)
{
    sprintf(status, "%u guest(s)", nguests);
    ui_draw(&l_status);                 /* a label shows its text again */
}

static void add(const char *s)
{
    if (!*s || nguests == MAXG)
        return;
    strcpy(guests[nguests++], s);
    ui_lsset(&l_guests, nguests);       /* the new row count; redrawn */
    ui_lssel(&l_guests, nguests - 1);   /* the new one selected and shown */
    show_status();
}

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
    hz_win_menu(win, menus);
    ui_setwin(ctls, win);
    show_status();
    ui_drawall(ctls);

    for (;;) {
        void *c;
        if (ui_getev(0))
            continue;
        switch (ui_event(ctls, &c)) {
        case UA_CLICK:                  /* Add, or Enter */
            add(name);
            ui_fdset(&f_name, "");
            break;
        case UA_CHANGE:                 /* the field's text, or the list's selection */
            if (c == &l_guests)
                printf("guests: %s selected\n", guests[l_guests.sel]);
            break;
        case UA_OPEN:                   /* a double click (or Enter) on a guest */
            printf("guests: %s opened\n", guests[l_guests.sel]);
            break;
        case UA_NONE:
            if (ui_ev.type == WE_CLOSE)
                goto out;
            if (ui_ev.type == WE_MENU) {
                if (ui_ev.a == 1)
                    ui_alert(&about);
                else
                    goto out;
            }
            if (ui_ev.type == WE_KEY && (ui_ev.b & 0x100) && (ui_ev.b & 0x11) &&
                ui_ev.a == 0x14)
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
