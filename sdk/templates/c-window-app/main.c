/* HELLOWIN - the window application template, in C (the twin of
 * sdk/templates/window-app).
 *
 * Shows: a window with menus (with shortcut texts), the controls library (a label, a text
 * field, two buttons), the file dialog (File > Open... reads the first line of a text file
 * into the field, File > Save as... writes the field to a file), an alert (Help >
 * About...), keyboard shortcuts, and a clean exit (the close box, File > Quit, ctrl+Q, or
 * the Desktop's Shut down, which sends WE_CLOSE).
 *
 * Build: make (hcc links the controls library because the program uses hui.h). Run:
 * make run (the Desktop starts it). Tutorial and reference: sdk/docs/c/apps.md.
 *
 * The rule of the controls library: what it keeps (the controls, the control list, the
 * field's buffer, the alert's block and their strings) must live as long as the window:
 * make them global or static. Strings given straight to a function (a path, ui_fdset's
 * text) are copied for the call.
 */
#include <stdio.h>
#include <string.h>
#include <horizon.h>                    /* the syscalls: hz_ws_start, hz_win_open, ... */
#include <hui.h>                        /* the controls library */

#define W       296                     /* the window's content size */
#define H       112
#define MSGY    76                      /* where the greeting is drawn */
#define NAMEMAX 40                      /* the field's buffer */

/* ---- the controls: the library writes into them, so they are static */
static char name[NAMEMAX];              /* the field's text (zero-terminated) */
static ui_label l_name = UI_LABEL(UI_GAP, 12, 72, 0, "Your name:");
static ui_field f_name = UI_FIELD(88, 9, W - 88 - UI_GAP, UF_FOCUS, name, NAMEMAX);
static ui_button b_greet = UI_BUTTON(W - UI_GAP - 64 - 4 - 64, 40, 64, UF_DEFAULT, "Greet");
static ui_button b_clear = UI_BUTTON(W - UI_GAP - 64, 40, 64, 0, "Clear");
static ui_ctlref ctls[] = { &l_name, &f_name, &b_greet, &b_clear, 0 };   /* the Tab order */

static ui_alertblk about = { AL_INFO, "About Hello",
                             "Hello 1.0, a window program\nmade from the Atari816 SDK template.",
                             "OK", 0, 0 };
static ui_alertblk ioerr = { AL_WARN, "Hello", "The file could not be read or written.",
                             "OK", 0, 0 };

/* the menus: "title", items..., "" for each menu, then "" (a TAB before the shortcut
 * text, which is drawn right-aligned; "-" is a separator, and counts as an item) */
static const char menus[] =
    "File\0Open...\tCtrl+O\0Save as...\tCtrl+S\0-\0Quit\tCtrl+Q\0\0"
    "Help\0About...\0\0";

static unsigned win;

/* the greeting under the controls, drawn with its paper: no flicker, no clearing */
static void greet(void)
{
    char msg[64];
    sprintf(msg, "Hello, %s!", name[0] ? name : "world");
    sprintf(msg + strlen(msg), "%*s", 60 - (int)strlen(msg), "");   /* covers a longer one */
    ui_text(win, UI_GAP, MSGY, 0, UI_INK(C_TITLE, C_BODY), msg);
}

/* File > Open...: the first line of a text file into the field */
static void open_file(void)
{
    char path[128], line[NAMEMAX];      /* locals: the dialog's path buffer is copied */
    FILE *f;
    path[0] = 0;                        /* no suggested name */
    if (ui_filedlg(0, path, "Open a text file"))
        return;                         /* cancelled */
    f = fopen(path, "r");
    if (!f || !fgets(line, sizeof line, f)) {
        if (f)
            fclose(f);
        ui_alert(&ioerr);
        return;
    }
    fclose(f);
    line[strcspn(line, "\r\n")] = 0;    /* cut at the line's end */
    ui_fdset(&f_name, line);            /* new text for the field (redrawn) */
    greet();
}

/* File > Save as...: the field's text and a line feed */
static void save_file(void)
{
    char path[128];
    FILE *f;
    strcpy(path, "NAME.TXT");           /* a suggested name */
    if (ui_filedlg(1, path, "Save the name"))
        return;                         /* (Save asks before replacing a file) */
    f = fopen(path, "w");
    if (!f || fprintf(f, "%s\n", name) < 0 || fclose(f)) {
        ui_alert(&ioerr);
        return;
    }
}

int main(void)
{
    hz_winopen wo;
    unsigned own;
    int w;

    own = hz_ws_start();                /* the window system (already running under the
                                           Desktop: 0; started by us: 1) */
    ui_init();                          /* the controls library, after hz_ws_start */
    wo.x = 120;                         /* the outer top left */
    wo.y = 60;
    wo.w = W;                           /* the content's size */
    wo.h = H;
    HZ_U24(wo.title, "Hello");
    wo.flags = 0;
    w = hz_win_open(&wo);
    if (w < 0) {
        printf("hellowin: no window: %s\n", hz_strerror(hz_errno));
        return 1;
    }
    win = (unsigned)w;
    ui_setwin(ctls, win);               /* every control lives in this window */
    hz_win_menu(win, menus);            /* the menu bar shows these while we have the focus */
    ui_drawall(ctls);                   /* (the body is C_BODY already) */
    greet();

    /* ---- the event loop: the library first, then what it did not use */
    for (;;) {
        void *c;
        unsigned act;
        if (ui_getev(0))                /* 0 = wait for the next event (into ui_ev) */
            continue;
        act = ui_event(ctls, &c);       /* -> UA_*, c = the control that acted */
        if (act == UA_CLICK) {
            if (c == &b_clear)
                ui_fdset(&f_name, "");
            greet();                    /* Greet (also Enter: the default button) */
            continue;
        }
        if (act != UA_NONE)             /* used by a control */
            continue;
        if (ui_ev.type == WE_CLOSE)
            break;
        if (ui_ev.type == WE_MENU) {    /* a = menu (0 = our first), b = item */
            if (ui_ev.a == 1) {
                ui_alert(&about);       /* Help > About... */
            } else if (ui_ev.b == 0) {
                open_file();
            } else if (ui_ev.b == 1) {
                save_file();
            } else if (ui_ev.b == 3) {
                break;                  /* File > Quit (item 2 is the separator) */
            }
        } else if (ui_ev.type == WE_KEY && (ui_ev.b & 0x100) && (ui_ev.b & 0x11)) {
            /* a key pressed with ctrl: a = the HID usage ($04 = A ... $1D = Z) */
            if (ui_ev.a == 0x12)
                open_file();            /* ctrl+O */
            else if (ui_ev.a == 0x16)
                save_file();            /* ctrl+S */
            else if (ui_ev.a == 0x14)
                break;                  /* ctrl+Q */
        }
        /* a program using the internet handles WE_NET here; a timer: WE_TICK */
    }
    hz_win_close(win);                  /* (optional: exit closes our windows) */
    if (own)
        hz_ws_stop();                   /* we started the window system: stop it */
    return 0;
}
