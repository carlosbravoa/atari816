/* viewer.c - a small text file viewer for Horizon, in C with the controls library.
 *
 *   viewer [FILE]
 *
 * A resizable window: the file's lines in a list (Up / Down, PgUp / PgDn, Home / End,
 * the wheel, the scroll bar), a horizontal scroll bar for long lines, a status line.
 * Open a file with its argument, File > Open... (ctrl+O), or by dragging it from Files
 * onto the window. Enter or a double click on a line prints it on the console. File >
 * Close, ctrl+W or the close box quits.
 *
 * What it shows of hui.h: a list whose rows come from a C function (the text is in a far
 * bank: a line is copied out for the library), scroll bars, laying the controls out again after
 * WE_RESIZE, a label updated at run time, the file dialog, WE_DROP, menus and keys.
 * The file is read into a bank of its own (64 KB at most: a longer file shows its first
 * 64 KB); the line table is malloc'd (in the code bank, as the library needs nothing
 * from it).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <horizon.h>
#include <hui.h>

#define WIN_X   8                       /* where the window opens (outer top left) */
#define WIN_Y   28
#define WIN_W   600                     /* its first content size */
#define WIN_H   280
#define MINW    160                     /* smaller sizes are laid out as these */
#define MINH    100
#define CHARW   6                       /* about the UI font's average advance */
#define MAXLINES 8000

static char __far *text;                /* the file, its line ends made 0 */
static unsigned *lines;                 /* each line's offset in text */
static unsigned nlines, longest;
static char fname[64];
static char stat[96];                   /* the status label's text */

static const char *row_text(ui_list *ls, unsigned row, const ui_rowinfo *ri);

static ui_list ls = UI_LIST(UI_GAP, UI_GAP, 100, 100, UF_FOCUS, row_text);
static ui_scroll hsb = UI_HSCROLL(UI_GAP, 0, 100, 0, 1, 4);
static ui_label lstat = UI_LABEL(UI_GAP, 0, 100, 0, stat);
static ui_ctlref ctls[] = { &ls, &hsb, &lstat, 0 };

static const char menus[] = "File\0Open...\tCtrl+O\0-\0Close\tCtrl+W\0\0";
static ui_alertblk al_err = { AL_WARN, "Viewer", stat, "OK", 0, 0 };

static unsigned win, ww = WIN_W, wh = WIN_H;

/* the row function: the line from the far bank, from the horizontal scroll position,
 * copied into the code bank (a plain char * is an offset in the code bank with cc816;
 * the library then cuts it with "..." and draws it) */
static const char *row_text(ui_list *l, unsigned row, const ui_rowinfo *ri)
{
    static char buf[256];
    const char __far *line;
    unsigned i;
    if (row >= nlines)
        return "";
    line = text + lines[row];
    for (i = 0; i < hsb.pos && line[i]; ++i)
        ;
    line += i;
    for (i = 0; i < sizeof(buf) - 1 && line[i]; ++i)
        buf[i] = line[i];
    buf[i] = 0;
    return buf;
}

static void status(void)
{
    if (!nlines)
        strcpy(stat, "No file: File > Open..., or drop one from Files");
    else
        sprintf(stat, "%s: %u lines, line %u", fname, nlines, ls.sel == UI_NONE ? 1 :
                ls.sel + 1);
    ui_draw(&lstat);
}

/* the controls from the window's size: the list fills it, the scroll bar and the status
 * line under it */
static void layout(void)
{
    unsigned w = ww < MINW ? MINW : ww, h = wh < MINH ? MINH : wh;
    unsigned vis;
    ls.w = (short)(w - 2 * UI_GAP);
    ls.h = (short)(h - 2 * UI_GAP - UI_SBW - 4 - UI_LINE - 4);
    hsb.y = ls.y + ls.h + 4;
    hsb.w = ls.w;
    lstat.y = hsb.y + UI_SBW + 4;
    lstat.w = ls.w;
    vis = (unsigned)(ls.w - UI_SBW - 8) / CHARW;
    hsb.page = vis;
    hsb.max = longest > vis ? longest - vis : 0;
    if (hsb.pos > hsb.max)
        hsb.pos = hsb.max;
}

/* read a file into the far bank, find its lines */
static int load(const char *path)
{
    FILE *f;
    unsigned n, i, start;
    const char *base;
    f = fopen(path, "r");
    if (!f) {
        sprintf(stat, "Cannot open %s", path);
        ui_alert(&al_err);
        return -1;
    }
    n = 0;
    while (n < 0xFFF0u) {               /* 64 KB at most, in pieces (fread: 16-bit) */
        static char piece[1024];
        unsigned k = fread(piece, 1, sizeof piece, f);
        if (!k)
            break;
        if (k > 0xFFF0u - n)
            k = 0xFFF0u - n;
        hz_far_copy(text + n, piece, k);
        n += k;
    }
    fclose(f);
    text[n] = 0;
    nlines = 0;
    longest = 0;
    start = 0;
    for (i = 0; i <= n && nlines < MAXLINES; i++) {
        char c = text[i];
        if (c == '\t' || c == '\r')
            text[i] = ' ';
        if (c == '\n' || i == n) {
            if (i == n && i == start)
                break;                  /* no empty line after the last line end */
            text[i] = 0;
            lines[nlines++] = start;
            if (i - start > longest)
                longest = i - start;
            start = i + 1;
        }
    }
    base = strrchr(path, '/');
    strncpy(fname, base ? base + 1 : path, sizeof fname - 1);
    hz_win_title(win, fname);
    printf("viewer: %s, %u bytes, %u lines\n", fname, n, nlines);
    hsb.pos = 0;
    layout();
    ui_lsset(&ls, nlines);              /* top 0, nothing selected, redrawn */
    ui_lssel(&ls, 0);
    ui_draw(&hsb);
    status();
    return 0;
}

static void open_dialog(void)
{
    char path[128];
    path[0] = 0;
    if (ui_filedlg(0, path, "Open a text file") == 0)
        load(path);
}

int main(int argc, char **argv)
{
    hz_winopen wo;
    unsigned own;
    int w;

    own = hz_ws_start();
    ui_init();
    text = hz_far_alloc();              /* a bank for the file */
    lines = malloc(MAXLINES * sizeof *lines);
    if (!text || !lines) {
        printf("viewer: not enough memory\n");
        return 1;
    }
    wo.x = WIN_X;
    wo.y = WIN_Y;
    wo.w = WIN_W;
    wo.h = WIN_H;
    HZ_U24(wo.title, "Viewer");
    wo.flags = WF_RESIZE;               /* a size grip: WE_RESIZE */
    w = hz_win_open(&wo);
    if (w < 0)
        return 1;
    win = (unsigned)w;
    hz_win_menu(win, menus);
    ui_setwin(ctls, win);
    layout();
    status();
    ui_drawall(ctls);
    if (argc > 1)
        load(argv[1]);

    for (;;) {
        void *c;
        unsigned act;
        if (ui_getev(0))
            continue;
        act = ui_event(ctls, &c);
        if (act == UA_CHANGE && c == &hsb) {
            ui_draw(&ls);               /* the rows again, from the new column */
        } else if (act == UA_CHANGE && c == &ls) {
            status();
        } else if (act == UA_OPEN && c == &ls) {
            printf("viewer: line %u: %s\n", ls.sel + 1,
                   row_text(&ls, ls.sel, 0));
        } else if (act == UA_NONE) {
            if (ui_ev.type == WE_CLOSE)
                break;
            if (ui_ev.type == WE_RESIZE) {      /* a, b = the new content size */
                ww = ui_ev.a;
                wh = ui_ev.b;
                layout();
                /* a bigger window's new part is C_BODY already; after a smaller one
                 * the old controls are still painted below and right of the new ones */
                ui_rect(win, 0, ls.y + ls.h, ww, wh - ls.y - ls.h, UI_FILL(C_BODY));
                ui_rect(win, ls.x + ls.w, 0, ww - ls.x - ls.w, wh, UI_FILL(C_BODY));
                ui_drawall(ctls);
                printf("viewer: resized to %ux%u, %u rows shown\n", ww, wh,
                       (unsigned)(ls.h - 4) / UI_ROWH);
            } else if (ui_ev.type == WE_DROP) { /* a file dragged here from Files */
                char path[128];
                if (hz_win_dropget(win, path) == 0)
                    load(path);
            } else if (ui_ev.type == WE_MENU) {
                if (ui_ev.b == 0)
                    open_dialog();
                else if (ui_ev.b == 2)
                    break;
            } else if (ui_ev.type == WE_KEY && (ui_ev.b & 0x100) && (ui_ev.b & 0x11)) {
                if (ui_ev.a == 0x12)            /* ctrl+O */
                    open_dialog();
                else if (ui_ev.a == 0x1A)       /* ctrl+W */
                    break;
            } else if (ui_ev.type == WE_KEY && (ui_ev.b & 0x100) && !(ui_ev.b & 0x11)) {
                /* Left / Right: the columns */
                if (ui_ev.a == 0x4F)
                    ui_sbset(&hsb, hsb.pos + hsb.step);
                else if (ui_ev.a == 0x50)
                    ui_sbset(&hsb, hsb.pos >= hsb.step ? hsb.pos - hsb.step : 0);
                else
                    continue;
                ui_draw(&ls);
            }
        }
    }
    hz_win_close(win);
    hz_far_free(text);
    if (own)
        hz_ws_stop();
    return 0;
}
