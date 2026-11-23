# hui: windows and controls from C (`hui.h`)

Purpose: write a desktop window program in C with Horizon's controls library (buttons,
fields, lists, scroll bars, alerts, dialogs, file dialog, pop-up menus), or with the raw
window calls of `horizon.h`. Authority: `SDK/c/include/hui.h` (the rule, the initialisers)
and `SDK/c/include/huigen.h` (generated: every constant, structure and prototype). Guide:
`SDK/docs/c/apps.md`. Look and feel (grid, colours, menus, shortcuts): references/look-and-feel.md.

## Start here

| Start from | What it shows |
| --- | --- |
| `SDK/templates/c-window-app` (`HELLOWIN.PRG`) | window, menus with shortcut text, label, field, two buttons, file dialog (open/save), alert, ctrl+keys, clean exit; `make test` checks the saved file |
| `SDK/c/examples/guests` (`step1.c` .. `step5.c`) | the tutorial: empty window, controls, menus + alert, a list, file dialog + timer |
| `SDK/c/examples/viewer` | list over far memory, horizontal scroll bar, `WF_RESIZE`, `WE_DROP` (drag a file from Files) |
| `SDK/c/tests/ui/uitest.c` | nearly every call: own dialog, `ui_ask`, pop-up menus, scroll bars, `ui_focus`, drawing helpers |
| `SDK/c/examples/window` (`CWIN.PRG`) | raw window calls, no controls library |

hcc links the library by itself when the program uses a name of `hui.h` (`--ui` forces it);
the first build prints `hcc: building the controls library (...)`. Both code models. Set
`RUNMODE := desktop` in the Makefile (window programs are started from the Desktop).

## A complete program (built and run)

A window with a list (row function drawing a colour swatch), a field, two buttons, a menu,
a timer and a pop-up menu. `make test` passed; the screenshots showed the list with
swatches, the alert, the pop-up menu, and the seconds counter.

```c
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include <hui.h>

static const char *names[] = { "Red", "Green", "Blue", "Yellow" };
static unsigned nnames = 4, secs, win;
static char buf[32];

static const char *row(ui_list *ls, unsigned r, const ui_rowinfo *ri)
{
    static const unsigned char col[] = { C_RED, C_GREEN, C_SELECT, C_YELLOW };
    ui_rect(ri->win, ri->x, ri->y + 3, 8, 8, UI_FILL(col[r]));  /* drawing is allowed */
    return names[r];                                            /* copied by the library */
}

static ui_list   l_cols = UI_LIST(8, 8, 160, 88, 0, row);
static ui_field  f_text = UI_FIELD(176, 8, 136, UF_FOCUS, buf, sizeof buf);
static ui_button b_show = UI_BUTTON(248, 36, 64, UF_DEFAULT, "Show");
static ui_button b_quit = UI_BUTTON(176, 36, 64, UF_CANCEL, "Quit");
static ui_ctlref ctls[] = { &l_cols, &f_text, &b_quit, &b_show, 0 };
static ui_alertblk al = { AL_INFO, "Colors", buf, "OK", 0, 0 };
static const char menus[] = "File\0Quit\tCtrl+Q\0\0";

int main(void)
{
    hz_winopen wo;
    unsigned own = hz_ws_start();       /* 1: we started the window system */
    int w;
    ui_init();                          /* once, after hz_ws_start */
    wo.x = 100; wo.y = 60; wo.w = 320; wo.h = 120;
    HZ_U24(wo.title, "Colors");
    wo.flags = 0;
    if ((w = hz_win_open(&wo)) < 0)
        return 1;
    win = (unsigned)w;
    l_cols.indent = 12;                 /* room for the row function's swatch */
    ui_setwin(ctls, win);
    ui_drawall(ctls);
    ui_lsset(&l_cols, nnames);
    hz_win_menu(win, menus);
    hz_win_timer(win, 100);             /* WE_TICK every second */
    for (;;) {
        void *c;
        unsigned a;
        if (ui_getev(0))
            continue;
        a = ui_event(ctls, &c);
        if (a == UA_CLICK && c == &b_quit)
            break;
        if (a == UA_CLICK && c == &b_show) {
            printf("COLORS: alert %u\n", ui_alert(&al));
        } else if ((a == UA_CHANGE || a == UA_OPEN) && c == &l_cols) {
            ui_fdset(&f_text, names[l_cols.sel]);
            printf("COLORS: picked %s\n", buf);
        } else if (a == UA_NONE) {
            if (ui_ev.type == WE_CLOSE)
                break;
            if (ui_ev.type == WE_MENU && ui_ev.a == 0 && ui_ev.b == 0)
                break;
            if (ui_ev.type == WE_TICK) {
                char t[16];
                sprintf(t, "%u s   ", ++secs);
                ui_text(win, 176, 100, 0, UI_INK(C_BLACK, C_BODY), t);
            }
            if (ui_ev.type == WE_BUTTON && (ui_ev.c & 2))  /* right press */
                printf("COLORS: popup %u\n", ui_popup(win, "Copy\0-\0Paste\0"));
        }
    }
    printf("COLORS: bye\n");
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
```

Makefile: `NAME := colors`, `SDK ?= <path to sdk>`, `RUNMODE := desktop`,
`TESTFLAGS := --expect 'COLORS: picked Green' --expect 'COLORS: bye'`, `include $(SDK)/c/c.mk`.
Under the Desktop `printf` goes only to the log (`console.txt`): print a line per event worth
testing. The window opened at (100, 60) has its content at screen (101, 76): a script clicks
row 1 with `move 140 106` + `click`.

## The skeleton, step by step

1. `own = hz_ws_start();` (0 under the Desktop, 1 if this program started the window system).
2. `ui_init();` once, after it, before any other `ui_` call.
3. `hz_win_open(&wo)`: `wo.x, wo.y` the outer top left, `wo.w, wo.h` the content size,
   `HZ_U24(wo.title, "Title")`, `wo.flags` (`WF_RESIZE`, `WF_PLAIN`, `WF_MODAL`, `WF_HOVER`).
   Returns the window (0-15) or -1 (`hz_errno`). Content = outer + (1, 16).
4. `ui_setwin(ctls, win); ui_drawall(ctls);` and `hz_win_menu(win, menus)`.
5. Loop: `ui_getev(0)` (0 wait, 1 poll: -1 when none) then `ui_event(ctls, &c)`.
6. `WE_CLOSE` (close box, Alt+F4, ctrl+W, the Desktop's Shut down): ask about unsaved work,
   then `hz_win_close(win); if (own) hz_ws_stop(); return 0;`.

**Read events with `ui_getev`, never `hz_win_event`**, in a program using controls: the
library must see every event. The event is in `ui_ev` (`type`, `win`, `a`, `b`, `c`).

## ui_event results

| Result | Meaning, `c` |
| --- | --- |
| `UA_NONE` | not a control's: look at `ui_ev.type` (table below); `c` NULL |
| `UA_USED` | a control used it (typing, focus, scrolling): nothing to do |
| `UA_CLICK` | a button was activated (click, Enter for `UF_DEFAULT`, Esc for `UF_CANCEL`) |
| `UA_CHANGE` | a field's text, a list's `sel`, a scroll bar's `pos` changed |
| `UA_OPEN` | a list row double-clicked or Enter |

| `ui_ev.type` | a, b, c |
| --- | --- |
| `WE_MENU` | a = menu (0 = your first), b = item (separators count) |
| `WE_KEY` | a = HID usage ($04 = A .. $1D = Z), b = modifiers \| $100 when pressed; ctrl = `b & 0x11`. ctrl+Q: `(b & 0x100) && (b & 0x11) && a == 0x14` |
| `WE_BUTTON` | a, b = position in the content; c bits 0 left, 1 right, 2 middle (press: bit set) |
| `WE_TICK` | the window's timer: `hz_win_timer(win, ticks)` (10 ms ticks, 0 stops) |
| `WE_RESIZE` | a, b = new content size (`WF_RESIZE`): change controls' x, y, w, h, clear the uncovered body, `ui_drawall` (viewer.c) |
| `WE_DROP` | a file dropped: `hz_win_dropget(win, buf128)` |
| `WE_WHEEL`, `WE_MOTION`, `WE_FOCUS`, `WE_UNFOCUS` | SDK/docs/reference/windows.md |

## Controls

All are structures you declare with the initialisers; a control list
`static ui_ctlref ctls[] = { &a, &b, ..., 0 };` gives the Tab order. There is no check box,
radio button or combo box: use buttons, lists or a pop-up menu.

| Control | Initialiser | Notes |
| --- | --- | --- |
| `ui_label` | `UI_LABEL(x, y, w, flags, text)` | height `UI_LINE` (12); cut with "..."; change the string, then `ui_draw(&lbl)`; `UF_RIGHT` right-aligns |
| `ui_button` | `UI_BUTTON(x, y, w, flags, label)` | height `UI_BTNH` (20); `UF_DEFAULT` (Enter), `UF_CANCEL` (Esc), `UF_DIM` (greyed, inert); `ui_btnw(label)` = a good width (at least 64) |
| `ui_field` | `UI_FIELD(x, y, w, flags, buf, size)` | height `UI_FLDH` (18); text always zero-terminated in `buf`; `ui_fdset(&f, "text")` replaces it; `UF_FOCUS` gets the keyboard; Enter activates the default button |
| `ui_list` | `UI_LIST(x, y, w, h, flags, rowfn)` | rows `UI_ROWH` (14) high, own scroll bar, keys and wheel; `ui_lsset(&ls, count)` (sel none, top 0, redrawn), `ui_lssel(&ls, row)`; `ls.sel` (`UI_NONE` = none); `ls.indent` pixels for an icon |
| `ui_scroll` | `UI_VSCROLL(x, y, h, max, page, step)`, `UI_HSCROLL(x, y, w, max, page, step)` | width/height `UI_SBW` (14); `max` = total - visible; `ui_sbset(&sb, pos)` (redraw), `ui_sbpos(&sb, pos)` (thumb only) |

Other calls: `ui_draw(ctl)` (one control, after changing its fields), `ui_drawall(list)`,
`ui_focus(ctl)` (field, list or button gets the keyboard). Metrics: `UI_GAP` 8; put controls
on a 4-pixel grid (look-and-feel.md).

**List row function** (`ui_rowfn`): `const char *fn(ui_list *ls, unsigned row, const
ui_rowinfo *ri)`; `ri->win`, `ri->x`, `ri->y` (row top left), `ri->sel`. Return the row's
text from anywhere (it is copied: one static buffer may serve all rows). It may draw (an icon
at `ri->x` in the indent).

## Dialogs and menus

| Need | Call |
| --- | --- |
| message / question | `static ui_alertblk al = { AL_INFO, "Title", "line1\nline2", "OK", 0, 0 };` `ui_alert(&al)` -> button index (0 = b1, the rightmost, default; the last given is the cancel: Esc, close box). Kinds `AL_INFO`, `AL_WARN`, `AL_QUESTION`, `AL_ERROR`; at most 3 lines, 3 buttons |
| one value | `static ui_askblk ak = { "Title", "Prompt:", buf, sizeof buf, 0 };` `ui_ask(&ak)` -> 0 (answer in buf) or -1 |
| open / save a file | `char path[128]; path[0] = 0;` (or a suggested name for Save) `ui_filedlg(0 open / 1 save, path, "Title")` -> 0 and the full path, or -1 cancelled. It changes the current folder; Save asks before replacing |
| a dialog of your controls | `static ui_dlgblk dg = { "Title", w, h, dctls, 0 };` `ui_dlgopen(&dg)` (0 or -1), `void *b = ui_dlgrun(&dg)` (returns the button activated: Enter = default, Esc/close = `UF_CANCEL` one), `ui_dlgclose(&dg)` |
| pop-up menu | on a right press: `ui_popup(win, "Open\0-\0Rename...\0")` -> item (separators count) or `UI_NONE`; for the menu key: `if (ui_menukey()) ui_popat(win, items, x, y)` |
| menu bar | `hz_win_menu(win, "File\0Open...\tCtrl+O\0-\0Quit\tCtrl+Q\0\0" "Help\0About...\0\0")`: each menu "title\0items\0...\0", then a final "\0"; text after TAB is the shortcut label only (handle the key yourself); "-" is a separator |

Sounds: `ui_beep()` (error), `ui_chime(CH_INFO)` etc. Files and programs: `ui_open(path)`,
`ui_launch(path, args, name)`, `ui_cptree`, `ui_rmtree`, `ui_mvtree` (with `ui_cpwin(0)` for
a progress window), clock helpers `ui_clksplit`, `ui_clkfmt` (huigen.h has each one).

## Drawing in a window

| Call | |
| --- | --- |
| `ui_rect(win, x, y, w, h, UI_FILL(c))` | also `UI_FRAME(c)`, `UI_DITHER(c1, c2)` |
| `ui_text(win, x, y, font, UI_INK(ink, paper), s)` | font 0 UI (proportional, 12-pixel lines), 1 fixed 8 x 12; paper `UI_NOPAPER` = none. Pad with spaces to cover a longer old text |
| `ui_bevel(win, x, y, w, h, sunken)`, `ui_copy(win, x, y, w, h, dx, dy)` | 1-pixel bevel; move a rectangle (blitter) |
| `ui_twidth(s, font)`, `ui_cwidth(c, font)`, `ui_fit(s, width)` | measure, cut with "..." |

Colours: `C_BLACK`, `C_WHITE`, `C_BODY` (window background), `C_DARK`, `C_MID`, `C_LIGHT`,
`C_SELECT`, `C_TITLE`, `C_RED`, `C_YELLOW`, `C_GREEN`, `C_ORANGE` (hzsys.h); colour cube
`16 + 36 r + 6 g + b`. Each draw call costs about 0.35 ms of CPU (measured: `hz_win_draw` fill
16 x 16 356 us, `ui_text` of 20 characters 1.06 ms): draw few, large things, and only what
changed. Anything that moves: use hgame in a window instead (references/hgame.md).

## THE RULE and callbacks

- **The library keeps 16-bit pointers into the program's code bank**: controls, control
  lists, alert/dialog/ask blocks, field buffers and the strings they point to. Every near C
  object is there (globals, statics, string constants, malloc, locals); only `__far` data is
  not: copy far text into a near buffer first. Make controls `static` or global (they must
  live as long as the window; the template does so). Strings passed straight to a call
  (`ui_text`, `ui_fdset`, a path) are copied (at most 255 characters).
- **Callbacks** (a list's row function, `ui_setcpcb`'s copy callback) run inside a library
  call: they may compute and draw (`ui_rect`, `ui_text`, `ui_bevel`, `ui_copy`, `ui_twidth`,
  `hz_` calls, printf) and must return quickly. They must **not** call a control or dialog
  routine (`ui_draw`, `ui_drawall`, `ui_event`, `ui_getev`, `ui_lsset`, `ui_alert`,
  `ui_filedlg`, ...): the program stops with
  `hui: ui_lsset: a control routine called inside a callback (...): a callback may only draw`.
  Set a flag in the callback and act after `ui_event` returns.
- The library is not reentrant. A pop-up, alert or dialog blocks until it closes.

## Raw window calls (no controls)

For a window that only draws and reads events, skip `hui.h` (a smaller program). Built and
run (a red box, "Hello", `RAW: click 39,24` in the log); `SDK/c/examples/window` is the
longer version.

```c
#include <stdio.h>
#include <horizon.h>

int main(void)
{
    hz_winopen wo;
    hz_event ev;
    hz_windraw d;
    unsigned own = hz_ws_start();
    int win;
    wo.x = 160; wo.y = 100; wo.w = 300; wo.h = 130;
    HZ_U24(wo.title, "Raw");
    wo.flags = 0;
    if ((win = hz_win_open(&wo)) < 0)
        return 1;
    d.op = WD_FILL; d.c1 = C_RED; d.c2 = 0; d.font = 0;
    d.x = 12; d.y = 34; d.w = 120; d.h = 40;
    HZ_U24(d.ptr, 0);
    d.stride = 0;
    hz_win_draw(win, &d);
    d.op = WD_TEXT; d.c1 = C_BLACK; d.c2 = 0xFF; d.x = 12; d.y = 10;
    HZ_U24(d.ptr, "Hello");
    hz_win_draw(win, &d);
    for (;;) {
        if (hz_win_event(0, &ev))
            break;
        if (ev.type == WE_CLOSE)
            break;
        if (ev.type == WE_BUTTON && (ev.c & 1))
            printf("RAW: click %d,%d\n", (int)ev.a, (int)ev.b);
    }
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
```

Ops (`WD_*`): `FILL`, `FRAME`, `LINE` (x, y to w, h as the end point), `TEXT` (c1 ink, c2
paper or 0xFF none), `BLIT`, `KBLIT`, `DITHER`, `SBLIT`, `COPY`, `EXPAND`, `KSBLIT`
(SDK/docs/reference/drawing.md). Other window calls in hzsys.h:
`hz_win_title`, `hz_win_move`, `hz_win_info`, `hz_win_timer`, `hz_win_menu`,
`hz_win_mstate` (grey or tick a menu item that starts with a state byte: windows.md),
`hz_ws_pointer`, `hz_win_popup`,
`hz_draw_list` (many blits in one call). Many drawing calls a frame: use hgame
(`hg_window`) or `hz_draw_list` instead of `hz_win_draw` in a loop.

## Testing

`RUNMODE := desktop`, a `test.script` with `move X Y` / `click` / `click right` / `\n` /
`{esc}` / `shot`, and `TESTFLAGS := --expect '...'`; `TESTCHECK` can check a file the program
saved in `build/test/card/` (the template checks `NAME.TXT`). Files is open at the top left
under the Desktop; open your window right of it (x 100 or more). Details:
references/testing.md.
