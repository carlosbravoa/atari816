/* step5.c - Guests, a small application: names in a list, saved to a file and read back,
 * menus, keys, an alert, and a clock updated by a timer */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include <hui.h>

#define MAXG 50

static char guests[MAXG][32];           /* the list's data */
static unsigned nguests;
static char name[32];
static char status[48];                 /* the status label's text */

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

static const char menus[] = "File\0Open...\tCtrl+O\0Save as...\tCtrl+S\0-\0Quit\tCtrl+Q\0\0"
                            "Help\0About...\0\0";
static ui_alertblk about = { AL_INFO, "About Guests", "Guests 1.0\nthe C tutorial's application.",
                             "OK", 0, 0 };
static ui_alertblk ioerr = { AL_WARN, "Guests", "The file could not be read or written.",
                             "OK", 0, 0 };
static unsigned win;

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

static void save(void)
{
    char path[128];
    FILE *f;
    unsigned i;
    strcpy(path, "GUESTS.TXT");         /* the name the Save dialog suggests */
    if (ui_filedlg(1, path, "Save the guests"))
        return;                         /* cancelled */
    f = fopen(path, "w");
    if (!f) {
        ui_alert(&ioerr);
        return;
    }
    for (i = 0; i < nguests; i++)
        fprintf(f, "%s\n", guests[i]);
    fclose(f);
    printf("guests: saved %u to %s\n", nguests, path);
}

static void open_file(void)
{
    char path[128], line[40];
    FILE *f;
    path[0] = 0;
    if (ui_filedlg(0, path, "Open a guest list"))
        return;
    f = fopen(path, "r");
    if (!f) {
        ui_alert(&ioerr);
        return;
    }
    nguests = 0;
    while (nguests < MAXG && fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = 0;
        strncpy(guests[nguests++], line, 31);
    }
    fclose(f);
    ui_lsset(&l_guests, nguests);
    show_status();
    printf("guests: read %u from %s\n", nguests, path);
}

static void show_clock(void)
{
    char t[20];
    ui_clksplit((unsigned long)hz_time_get());  /* seconds since 2000 -> ui_clk */
    ui_clkfmt(t);                               /* "YYYY-MM-DD HH:MM:SS" */
    ui_text(win, 196, 140, 0, UI_INK(C_DARK, C_BODY), t + 11);    /* HH:MM:SS */
}

int main(void)
{
    hz_winopen wo;
    unsigned own;
    int w;

    own = hz_ws_start();
    ui_init();
    wo.x = 100;
    wo.y = 60;
    wo.w = 320;
    wo.h = 160;
    HZ_U24(wo.title, "Guests");
    wo.flags = 0;
    w = hz_win_open(&wo);
    if (w < 0)
        return 1;
    win = (unsigned)w;
    hz_win_menu(win, menus);
    ui_setwin(ctls, win);
    show_status();
    ui_drawall(ctls);
    show_clock();
    hz_win_timer(win, 100);             /* WE_TICK every 100 x 10 ms */

    for (;;) {
        void *c;
        if (ui_getev(0))
            continue;
        switch (ui_event(ctls, &c)) {
        case UA_CLICK:                  /* Add, or Enter */
            add(name);
            ui_fdset(&f_name, "");
            break;
        case UA_OPEN:                   /* a double click (or Enter) on a guest */
            printf("guests: %s opened\n", guests[l_guests.sel]);
            break;
        case UA_NONE:
            switch (ui_ev.type) {
            case WE_CLOSE:
                goto out;
            case WE_TICK:
                show_clock();
                break;
            case WE_MENU:               /* a = menu, b = item (counting separators) */
                if (ui_ev.a == 1)
                    ui_alert(&about);
                else if (ui_ev.b == 0)
                    open_file();
                else if (ui_ev.b == 1)
                    save();
                else if (ui_ev.b == 3)
                    goto out;
                break;
            case WE_KEY:                /* b = modifiers | down << 8; a = HID usage */
                if ((ui_ev.b & 0x100) && (ui_ev.b & 0x11)) {        /* ctrl + key */
                    if (ui_ev.a == 0x12)
                        open_file();    /* O */
                    else if (ui_ev.a == 0x16)
                        save();         /* S */
                    else if (ui_ev.a == 0x14)
                        goto out;       /* Q */
                }
                break;
            }
            break;
        }
    }
out:
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
