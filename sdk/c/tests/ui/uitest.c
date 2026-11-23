/* uitest.c - the controls library from C (hui.h): every kind of argument and result the
 * bindings have, the callbacks, the controls, the dialogs and the events, driven by
 * tests/ui/uitest.script (run.py: desktop mode, screenshots, pixel checks).
 *
 * Part 1 (at once): string functions with strings in the code bank, on the stack (bank
 * 0) and in a far bank; output buffers on the stack; the clock; the copy routines with a
 * C callback (and its cancel); shortcuts; ulib's Atari helpers.
 * Part 2: a window with a label, a field, buttons, a list whose rows come from a C
 * function (texts from a static buffer, a far bank and constants; an icon drawn in the
 * row), two scroll bars; a timer (WE_TICK), a drop on the window (WE_DROP), menus.
 * Part 3 (the script): typing, the default button, list clicks, a scroll bar arrow, an
 * alert, ui_ask, a dialog of our own, a pop-up menu, the Save and Open file dialogs with
 * the path in a local buffer, ctrl+Q.
 * Prints "UITEST: ..." lines, and UITEST PASS / UITEST FAIL at the end.
 */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include <hui.h>

static unsigned checks, fails;
static void check(int ok, const char *what)
{
    ++checks;
    if (!ok) {
        ++fails;
        printf("UITEST: FAIL %s\n", what);
    }
}

/* ---- part 1 */

static unsigned cb_calls, cb_cancel;
static char cb_name[16];
static unsigned long cb_size;

static unsigned cb_vars;

static int copycb(const char *name, unsigned kdone, unsigned long size)
{
    ++cb_calls;
    if (!strcmp(ui_cpname, name) && ui_cpsize == size && ui_cpk == kdone)
        ++cb_vars;                      /* the library's variables say the same */
    strncpy(cb_name, name, sizeof cb_name - 1);
    cb_size = size;

    return cb_cancel;
}

static void part1(void)
{
    char loc[64], out[40];
    char __far *far;
    static char stat[64];
    unsigned w1, w2, icon;
    const char *pn;
    FILE *f;
    hz_fileinfo fi;

    /* strings: code bank, stack (copied for the call), far bank (copied) */
    strcpy(loc, "Hello, world");
    w1 = ui_twidth("Hello, world", 0);
    w2 = ui_twidth(loc, 0);
    check(w1 > 30 && w1 == w2, "ui_twidth: a constant and a local give the same width");
    far = hz_far_alloc();
    check(far != 0, "hz_far_alloc");
    hz_far_copy(far, "Hello, world", 13);
    /* a char * is an offset in the code bank: a far string is copied in first */
    hz_far_copy(stat, far, 13);
    check(ui_twidth(stat, 0) == w1, "ui_twidth: a string from a far bank");
    check(ui_cwidth('W', 1) == 8, "ui_cwidth: the fixed font is 8 wide");
    check(ui_btnw("OK") >= 64, "ui_btnw: at least 64");
    /* an in/out buffer on the stack: copied in, cut, copied back */
    strcpy(loc, "A rather long text that will not fit in fifty pixels");
    strcpy(stat, loc);
    ui_fit(loc, 50);
    ui_fit(stat, 50);
    check(strlen(loc) < 20 && strstr(loc, "...") != 0 && !strcmp(loc, stat),
          "ui_fit: a local buffer is cut as a static one");
    check(ui_twidth(loc, 0) <= 50, "ui_fit: it fits");
    /* results: xoff, Xptr with an out parameter, A */
    check(ui_isurl("http://example.com/a") == 7, "ui_isurl: http:// -> 7");
    strcpy(loc, "ftp://h/x");
    check(ui_isurl(loc) == 6, "ui_isurl: a local -> 6");
    check(ui_isurl("/BIN/EDIT.PRG") == -1, "ui_isurl: a path -> -1");
    ui_urlname("http://host/dir/file.txt?q=1", out);
    check(!strcmp(out, "file.txt"), "ui_urlname into a local buffer");
    check(ui_ftype("NOTES.TXT") == FT_TEXT && ui_ftype("X.PRG") == FT_PRG &&
          ui_ftype("GAME.ATR") == FT_ATARI && ui_ftype("A.BAS") == FT_BASIC,
          "ui_ftype");
    icon = 0;
    pn = ui_prog("/BIN/CALC.PRG", &icon);
    check(pn && !strcmp(pn, "Calculator") && icon == ICO_CALC, "ui_prog: Calculator");
    check(ui_prog("/APPS/NOSUCH.PRG", 0) == 0, "ui_prog: not one of Horizon's: NULL");
    check(ui_ficon("/docs", 1) == ICO_FOLDER, "ui_ficon: a folder");
    strcpy(loc, "GAME.XEX");
    check(atari_kind(loc) == 2 && atari_kind("D.ATR") == 1 && atari_kind("X.TXT") == 0,
          "atari_kind (ulib, any bank)");
    check(atari_rkind("P.BAS") == 4, "atari_rkind: BASIC");

    /* the clock: long in (A, X), long out (AX), out buffers on the stack, ok results */
    ui_clksplit(0);
    check(ui_clk.year == 2000 && ui_clk.mon == 1 && ui_clk.day == 1 && ui_clk.wday == 6,
          "ui_clksplit(0): Saturday 2000-01-01");
    check(ui_clkfmt(out) == 19 && !strcmp(out, "2000-01-01 00:00:00"), "ui_clkfmt");
    strcpy(loc, "2026-11-21 18:30");
    check(ui_clkparse(loc) == 0 && ui_clk.year == 2026 && ui_clk.mon == 11 &&
          ui_clk.day == 21 && ui_clk.hour == 18 && ui_clk.min == 30, "ui_clkparse");
    {
        unsigned long s = ui_clkjoin();
        ui_clksplit(0);
        ui_clksplit(s);
        check(s > 0x30000000UL && ui_clk.year == 2026 && ui_clk.min == 30 &&
              ui_clk.wday == 6, "ui_clkjoin / ui_clksplit round trip (a Saturday)");
    }
    ui_clklong(out);
    check(!strcmp(out, "Saturday, 21 November 2026"), "ui_clklong");
    ui_clk.year = 2024;
    check(ui_clkmdays(2) == 29 && ui_clkmdays(4) == 30, "ui_clkmdays");
    check(ui_clkcheck() == 0, "ui_clkcheck: valid");
    ui_clk.mon = 13;
    check(ui_clkcheck() == -1, "ui_clkcheck: month 13 is not");
    check(ui_clkparse("nonsense") == -1, "ui_clkparse: not a date");

    /* copying with a C callback (err results, hz_errno) */
    f = fopen("/UIT1.TXT", "w");
    check(f != 0, "fopen /UIT1.TXT");
    if (f) {
        fputs("the controls library, from C\n", f);
        fclose(f);
    }
    ui_setcpcb(copycb);
    check(ui_cptree("/UIT1.TXT", "/UIT2.TXT") == 0 && hz_errno == 0, "ui_cptree");
    check(cb_calls >= 1 && !strcmp(cb_name, "UIT1.TXT") && cb_size == 29,
          "the copy callback: called with the name and the size");
    check(cb_vars == cb_calls && ui_cpblk == 16384, "ui_cpname, ui_cpk, ui_cpsize, ui_cpblk");
    printf("UITEST: copy callback %u call(s), %s, %lu bytes\n", cb_calls, cb_name, cb_size);
    cb_cancel = 1;
    check(ui_cptree("/UIT1.TXT", "/UIT3.TXT") == -1 && hz_errno == HZ_ECANCELED,
          "the copy callback cancels: -1, HZ_ECANCELED");
    check(hz_stat_path("/UIT3.TXT", &fi) == -1, "a cancelled copy leaves no file");
    ui_setcpcb(0);
    check(ui_mvtree("/UIT2.TXT", "/UIT4.TXT") == 0, "ui_mvtree");
    check(hz_stat_path("/UIT4.TXT", &fi) == 0 && fi.size == 29 &&
          hz_stat_path("/UIT2.TXT", &fi) == -1, "ui_mvtree moved it");
    check(ui_rmtree("/UIT4.TXT") == 0 && hz_stat_path("/UIT4.TXT", &fi) == -1, "ui_rmtree");
    check(ui_rmtree("/NOSUCH.TXT") == -1 && hz_errno == HZ_ENOFILE,
          "ui_rmtree of nothing: -1, HZ_ENOFILE");

    /* shortcuts: the library's variables */
    check(ui_mklink("/UIT1.TXT") == 0, "ui_mklink");
    check(ui_lnkread("/Desktop/UIT1.TXT.LNK") == 0 && !strcmp(ui_lktgt, "/UIT1.TXT") &&
          !ui_lktitl[0] && !ui_lkargs[0], "ui_lnkread: ui_lktgt, ui_lktitl, ui_lkargs");
    remove("/Desktop/UIT1.TXT.LNK");
    check(ui_atload("/UIT1.TXT") == -1 && hz_errno == 0, "ui_atload: not an Atari file");
    check(ui_dlfilt == 0, "ui_dlfilt");
    {
        int r = ui_clkpc();
        check(r == 0 || r == -1, "ui_clkpc");
        printf("UITEST: ui_clkpc %d\n", r);
    }
    ui_beep();
    ui_chime(CH_INFO);
    hz_far_free(far);
}

/* ---- part 2: the window */

#define W 400
#define H 236

static char name[32];
static char dname[24];
static char abuf[24];
static char __far *rowfar;
static char rowbuf[24];
static unsigned rowcalls;

static const char *row_text(ui_list *ls, unsigned row, const ui_rowinfo *ri)
{

    ++rowcalls;
    if (!(row & 1))                     /* an icon in the indent: drawing is allowed */
        ui_rect(ri->win, ri->x, ri->y + 3, 8, 8, UI_FILL(ri->sel ? C_WHITE : C_RED));
    switch (row % 3) {
    case 0:
        sprintf(rowbuf, "Row %u (static)", row);
        return rowbuf;
    case 1:
        sprintf(rowbuf, "Row %u (far bank)", row);
        hz_far_copy(rowfar, rowbuf, strlen(rowbuf) + 1);
        hz_far_copy(rowbuf, rowfar, strlen(rowbuf) + 1);   /* (back to the code bank) */
        return rowbuf;
    }
    return row == 2 ? "Row 2 (constant)" : "A constant row";
}

static ui_label l_name = UI_LABEL(8, 10, 60, 0, "Name:");
static ui_field f_name = UI_FIELD(72, 7, 160, UF_FOCUS, name, sizeof name);
static ui_button b_count = UI_BUTTON(240, 6, 64, UF_DEFAULT, "Count");
static ui_button b_dlg = UI_BUTTON(312, 6, 80, 0, "Dialog...");
static ui_list ls = UI_LIST(8, 36, 200, 100, 0, row_text);
static ui_scroll vsb = UI_VSCROLL(216, 36, 100, 90, 10, 1);
static ui_scroll hsb = UI_HSCROLL(8, 144, 200, 50, 10, 5);
static ui_ctlref ctls[] = { &l_name, &f_name, &b_count, &b_dlg, &ls, &vsb, &hsb, 0 };

/* a dialog of our own */
static ui_label dl_lab = UI_LABEL(8, 10, 60, 0, "Value:");
static ui_field dl_fd = UI_FIELD(72, 7, 120, UF_FOCUS, dname, sizeof dname);
static ui_button dl_ok = UI_BUTTON(128, 40, 64, UF_DEFAULT, "OK");
static ui_button dl_cancel = UI_BUTTON(56, 40, 64, UF_CANCEL, "Cancel");
static ui_ctlref dctls[] = { &dl_lab, &dl_fd, &dl_cancel, &dl_ok, 0 };
static ui_dlgblk dlg = { "A dialog", 200, 68, dctls, 0 };

static ui_alertblk about = { AL_INFO, "About", "uitest: the controls library\nfrom C.",
                             "OK", 0, 0 };
static ui_askblk ask = { "Ask", "Your favourite colour:", abuf, sizeof abuf, 0 };

static const char menus[] = "File\0Save...\0Open...\0-\0Quit\0\0"
                            "Test\0About...\0Ask...\0Launch\0Open\0\0";
static const char popitems[] = "First\0Second\0Third\0";

static unsigned win, ticks, changes;

static void status(const char *s)
{
    char line[64];
    sprintf(line, "%-40s", s);          /* padded: covers a longer one before */
    ui_text(win, 8, 168, 0, UI_INK(C_BLACK, C_BODY), line);
}

int main(void)
{
    hz_winopen wo;
    unsigned own, clicks = 0, quit = 0;
    int w;
    char path[128];                     /* a local: the file dialog's buffer is copied */
    char drop[128];

    own = hz_ws_start();
    ui_init();
    part1();
    printf("UITEST: part 1: %u checks, %u failures\n", checks, fails);

    rowfar = hz_far_alloc();
    wo.x = 40;
    wo.y = 30;
    wo.w = W;
    wo.h = H;
    HZ_U24(wo.title, "UI test");
    wo.flags = WF_RESIZE;
    w = hz_win_open(&wo);
    check(w >= 0, "hz_win_open");
    win = (unsigned)w;
    hz_win_menu(win, menus);
    ui_setwin(ctls, win);
    check(f_name.win == win && hsb.win == win, "ui_setwin");
    ls.indent = 12;
    ui_drawall(ctls);
    ui_lsset(&ls, 40);
    ui_lssel(&ls, 2);
    check(ls.count == 40 && ls.sel == 2, "ui_lsset, ui_lssel");
    ui_sbset(&vsb, 10);
    ui_sbpos(&vsb, 12);
    check(vsb.pos == 12, "ui_sbset, ui_sbpos");
    check(rowcalls >= 7, "the row function was called for the rows shown");
    ui_bevel(win, 240, 40, 152, 96, 1);
    ui_rect(win, 241, 41, 150, 94, UI_DITHER(C_LIGHT, C_WHITE));
    ui_text(win, 250, 60, 1, UI_INK(C_BLACK, UI_NOPAPER), "fixed font");
    ui_copy(win, 250, 58, 80, 14, 250, 100);        /* the text again, lower */
    ui_cpwin(0);                        /* a copy with the progress window (too short to
                                           open it), then ui_cpdone */
    check(ui_cptree("/UIT1.TXT", "/UIT5.TXT") == 0, "ui_cptree with ui_cpwin");
    ui_cpdone();
    check(ui_rmtree("/UIT5.TXT") == 0, "ui_rmtree after it");
    status("ready");
    hz_win_timer(win, 5);               /* WE_TICK every 50 ms */
    hz_win_drop(win, "/DROPPED.TXT");   /* our own window gets WE_DROP */
    printf("UITEST: drawn, %u row calls\n", rowcalls);

    while (!quit) {
        void *c;
        unsigned a;
        if (ui_getev(0))
            continue;
        a = ui_event(ctls, &c);
        if (a == UA_CLICK && c == &b_count) {
            ++clicks;
            printf("UITEST: click %u, name '%s'\n", clicks, name);
            status(name);
            ui_focus(&ls);              /* the list gets the keyboard */
            check((ls.flags & UF_FOCUS) && !(f_name.flags & UF_FOCUS), "ui_focus");
        } else if (a == UA_CLICK && c == &b_dlg) {
            void *b;
            ui_fdset(&dl_fd, "");
            check(ui_dlgopen(&dlg) == 0, "ui_dlgopen");
            b = ui_dlgrun(&dlg);
            ui_dlgclose(&dlg);
            printf("UITEST: dialog %s '%s'\n", b == &dl_ok ? "OK" :
                   b == &dl_cancel ? "Cancel" : "?", dname);
        } else if (a == UA_CHANGE && c == &f_name) {
            ++changes;
        } else if (a == UA_CHANGE && c == &ls) {
            printf("UITEST: list sel %u\n", ls.sel);
        } else if (a == UA_OPEN && c == &ls) {
            printf("UITEST: list open %u\n", ls.sel);
        } else if (a == UA_CHANGE && c == &vsb) {
            printf("UITEST: vscroll %u\n", vsb.pos);
        } else if (a == UA_NONE) {
            switch (ui_ev.type) {
            case WE_CLOSE:
                quit = 1;
                break;
            case WE_TICK:
                if (++ticks == 3) {
                    hz_win_timer(win, 0);
                    printf("UITEST: 3 ticks\n");
                }
                break;
            case WE_DROP:
                check(hz_win_dropget(win, drop) == 0, "hz_win_dropget");
                printf("UITEST: dropped '%s'\n", drop);
                break;
            case WE_BUTTON:
                if (ui_ev.c & 2) {      /* a right press */
                    unsigned it = ui_popup(win, popitems);
                    printf("UITEST: popup %u\n", it);
                }
                break;
            case WE_KEY:
                if ((ui_ev.b & 0x100) && (ui_ev.b & 0x11) && ui_ev.a == 0x14)
                    quit = 1;           /* ctrl+Q */
                else if (ui_menukey())  /* the menu key, Shift+F10 */
                    printf("UITEST: popat %u\n", ui_popat(win, popitems, 300, 200));
                break;
            case WE_MENU:
                if (ui_ev.a == 0 && ui_ev.b == 0) {             /* File > Save... */
                    strcpy(path, "UITEST.TXT");
                    if (ui_filedlg(1, path, "Save the name") == 0) {
                        FILE *f = fopen(path, "w");
                        if (f) {
                            fprintf(f, "%s\n", name);
                            fclose(f);
                        }
                        printf("UITEST: saved '%s'\n", path);
                    } else
                        printf("UITEST: save cancelled\n");
                } else if (ui_ev.a == 0 && ui_ev.b == 1) {      /* File > Open... */
                    path[0] = 0;
                    if (ui_filedlg(0, path, "Open a file") == 0)
                        printf("UITEST: open '%s'\n", path);
                    else
                        printf("UITEST: open cancelled\n");
                } else if (ui_ev.a == 0 && ui_ev.b == 3) {
                    quit = 1;
                } else if (ui_ev.a == 1 && ui_ev.b == 0) {
                    printf("UITEST: alert %u\n", ui_alert(&about));
                } else if (ui_ev.a == 1 && ui_ev.b == 1) {
                    strcpy(abuf, "red");
                    printf("UITEST: ask %d '%s'\n", ui_ask(&ask), abuf);
                } else if (ui_ev.a == 1 && ui_ev.b == 2) {
                    int r = ui_launch("/APPS/NOSUCH.PRG", 0, 0);    /* an alert says why */
                    printf("UITEST: launch %d, error $%X\n", r, hz_errno);
                } else if (ui_ev.a == 1 && ui_ev.b == 3) {
                    printf("UITEST: ui_open %d\n", ui_open("/UIT1.XYZ"));  /* no program */
                }
                break;
            }
        }
    }
    check(changes >= 3, "the field gave UA_CHANGE for each letter");
    check(ticks >= 3, "WE_TICK");
    printf("UITEST: %u field changes, %u ticks\n", changes, ticks);
    hz_far_free(rowfar);
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    printf("uitest: %u checks, %u failures\n", checks, fails);
    printf(fails ? "UITEST FAIL\n" : "UITEST PASS\n");
    return 0;
}
