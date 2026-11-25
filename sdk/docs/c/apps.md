# Window applications in C

Horizon's own programs (Files, Edit, Paint, Settings, ...) share one library for the
standard look: buttons, labels, text fields, lists, scroll bars, alerts, the file
dialog, small dialogs, pop-up menus. `hui.h` makes all of it callable from C, with the
same names as the assembly library (`ui_alert`, `ui_filedlg`, ...). Read
[Getting started with C](getting-started.md) first. The C SDK's reference is
[reference.md](reference.md).

```
cp -r sdk/templates/c-window-app mywin    # a window, menus, a field, buttons, dialogs
cd mywin && make && make run              # HELLOWIN.PRG; the Desktop starts it
```

- Header: `#include <hui.h>`, after `horizon.h` (it includes `horizon.h` if needed).
- Linking: automatic. `hcc` links the library when the program uses a name of `hui.h`
  (`--ui` forces it).
- Code models: both small and large. The library is linked into the program.
- Requires: cc65's `ca65`, `ld65` and `ar65` (the library is assembly), and the Horizon
  tree (its sources).
- Template: [sdk/templates/c-window-app](../../templates/c-window-app), the C twin of
  [window-app](../../templates/window-app), with the same window pixel for pixel.
- Examples: [sdk/c/examples/guests](../../c/examples/guests) (this tutorial's steps),
  [sdk/c/examples/viewer](../../c/examples/viewer) (a text viewer: a list, scroll bars,
  resizing, drag and drop).
- The library's assembly documentation: [controls.md](../reference/controls.md),
  [windows.md](../reference/windows.md), `horizon/user/ui.inc`.

## Tutorial: Guests

Five steps from an empty window to a small application: a guest list with a field, a
list, menus, an alert, files and a clock. Each step is a complete program in
[sdk/c/examples/guests](../../c/examples/guests) (`step1.c` .. `step5.c`). `make test`
there builds the five and runs each in the emulator with a script (`stepN.script`).

### Step 1: an empty window

From `step1.c`:

```c
/* step1.c - an empty window, closed by its close box */
#include <stdio.h>
#include <horizon.h>
#include <hui.h>

int main(void)
{
    hz_winopen wo;
    unsigned own;
    int win;

    own = hz_ws_start();                /* the window system: 1 if we started it */
    ui_init();                          /* the controls library, once, after it */
    wo.x = 100;                         /* the window's outer top left on the screen */
    wo.y = 60;
    wo.w = 320;                         /* its content's size */
    wo.h = 160;
    HZ_U24(wo.title, "Guests");         /* a 3-byte pointer in the block */
    wo.flags = 0;
    win = hz_win_open(&wo);
    if (win < 0)
        return 1;

    for (;;) {
        if (ui_getev(0))                /* wait for the next event, into ui_ev */
            continue;
        if (ui_ev.type == WE_CLOSE)     /* the close box, or the Desktop's Shut down */
            break;
    }
    printf("guests: closed\n");
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    return 0;
}
```

```
$ sdk/c/bin/hcc --map -o STEP1.PRG step1.c
hcc: building the controls library (.../sdk/c/build/ui/small)
STEP1.PRG: 16,825 bytes on the card, 22 relocations
  code bank: code+constants 16,521 + data 78 + bss 2,680 = 19,279 of 57,072; heap 37,793; software stack 8,192
  window:    stack about 32,000 (from $7F7F down to $0100); direct page 206 bytes
$ python3 sdk/tools/run816.py STEP1.PRG --mode desktop --shot 2
```

- `hz_ws_start` starts the window system, or returns 0 when it already runs (under the
  Desktop). The program that started it stops it at the end.
- `ui_init` once, after the window system is there.
- **Events come from `ui_getev`, not `hz_win_event`**: the library has to process every
  event (and a dialog holds back a close or resize of your windows until it ends). The event
  is in `ui_ev`, a `hz_event`: `type` (`WE_*`), `win`, `a`, `b`, `c`.
- The first time a program uses `hui.h`, hcc builds the library from the Horizon tree's
  sources (about a second). It then links what the program uses: here the core of the
  library, about 9 KB of the program.

### Step 2: controls

A label, a text field and a button. Controls are structures you declare, **static or
global** (the library keeps pointers to them and writes into them), with the `UI_*`
initialisers. A control list (`ui_ctlref`, ending with 0) gives their order for Tab.

From `step2.c`:

```c
static char name[32];                   /* the field's text */
static ui_label l_name = UI_LABEL(8, 12, 44, 0, "Name:");
static ui_field f_name = UI_FIELD(56, 9, 176, UF_FOCUS, name, sizeof name);
static ui_button b_add = UI_BUTTON(240, 8, 72, UF_DEFAULT, "Add");
static ui_ctlref ctls[] = { &l_name, &f_name, &b_add, 0 };
```

After the window opens, put the controls in it and draw them. Every event then goes to
the controls first:

```c
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
```

- `ui_event` returns what happened: `UA_NONE` (the event is yours: menus, keys nobody
  took, close, resize, timers), `UA_USED`, `UA_CLICK` (a button), `UA_CHANGE` (a field's
  text, a list's selection, a scroll bar's position), `UA_OPEN` (a list: double click or
  Enter); and in `c` the control that acted. The field has the focus (`UF_FOCUS`): typing
  goes there; Enter activates the default button (`UF_DEFAULT`), Tab moves the focus.
- The field's text is in `name`, always zero-terminated; `ui_fdset` replaces it.
- `ui_text` draws text with its paper colour (`UI_INK(ink, paper)`), so a shorter text
  covers a longer one if it is padded with spaces. `line` is a local: strings given
  straight to a function may be anywhere (they are copied for the call).

### Step 3: menus, shortcuts, an alert

From `step3.c`:

```c
/* the menus: "title", the items, "" for each menu, then "" (TAB: the shortcut's text;
 * "-": a separator, which counts as an item) */
static const char menus[] = "File\0Quit\tCtrl+Q\0\0"
                            "Help\0About...\0\0";
/* an alert: kind, title, text (lines split by \n), buttons (the first is the default) */
static ui_alertblk about = { AL_INFO, "About Guests", "Guests 1.0\nthe C tutorial's application.",
                             "OK", 0, 0 };
```

```c
    hz_win_menu(win, menus);            /* the menu bar shows them while we have the focus */
```

```c
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
```

- A menu event: `a` = the menu (0 = your first), `b` = the item, counting separators.
  The text after a TAB is the shortcut shown at the right; the shortcut itself is a key
  you handle (`WE_KEY`: `a` = the HID usage, `$04` = A ... `$1D` = Z; `b` = the
  modifiers, `| $100` when pressed; `$11` = either ctrl).
- `ui_alert` is modal: it returns the button chosen (0 = the first, the rightmost; the
  last one given is the cancel button: Esc and the close box). The block is static: the
  library reads its strings through 16-bit pointers (see
  [Pointers and the code bank](#pointers-and-the-code-bank)).

### Step 4: a list

A list calls your function for each row's text when it draws the row. From `step4.c`:

```c
/* the list asks for each row's text when it draws it */
static const char *guest_row(ui_list *ls, unsigned row, const ui_rowinfo *ri)
{
    return guests[row];                 /* the library copies it */
}
```

```c
static ui_list l_guests = UI_LIST(8, 36, 304, 96, 0, guest_row);
static ui_label l_status = UI_LABEL(8, 140, 180, 0, status);
static ui_ctlref ctls[] = { &l_name, &f_name, &b_add, &l_guests, &l_status, 0 };
```

```c
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
```

```c
        case UA_CHANGE:                 /* the field's text, or the list's selection */
            if (c == &l_guests)
                printf("guests: %s selected\n", guests[l_guests.sel]);
            break;
        case UA_OPEN:                   /* a double click (or Enter) on a guest */
            printf("guests: %s opened\n", guests[l_guests.sel]);
            break;
```

- The row function is a **callback**: the library calls it in the middle of drawing.
  It returns the row's text (from anywhere: the library copies it, so one static buffer
  can serve every row) and may draw (an icon in the list's `indent` pixels at `ri->x`,
  `ri->y`), but must not call a control routine (see [Callbacks](#callbacks)).
- The list has a scroll bar of its own, the keys (Up, Down, PgUp, PgDn, Home, End when
  it has the focus) and the wheel. `l_guests.sel` is the selected row (`UI_NONE`: none).
- A label shows the string its `text` points to; after changing the string, `ui_draw`
  it.

### Step 5: files and a timer

The file dialog, and a clock in the window updated every second. From `step5.c`:

```c
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
```

```c
static void show_clock(void)
{
    char t[20];
    ui_clksplit((unsigned long)hz_time_get());  /* seconds since 2000 -> ui_clk */
    ui_clkfmt(t);                               /* "YYYY-MM-DD HH:MM:SS" */
    ui_text(win, 196, 140, 0, UI_INK(C_DARK, C_BODY), t + 11);    /* HH:MM:SS */
}
```

```c
    hz_win_timer(win, 100);             /* WE_TICK every 100 x 10 ms */
```

```c
            case WE_TICK:
                show_clock();
                break;
```

- `ui_filedlg(0 open / 1 save, path, title)` returns 0 with the full path in `path` (128
  bytes), or -1 when cancelled. `path` is a local here: a local is in the code bank like
  everything else. The dialog changes the task's current folder as the user moves through
  folders. Save prompts for confirmation before replacing a file.
- A timer: `hz_win_timer(win, ticks)` sends `WE_TICK` every ticks x 10 ms (0 stops it).
- The whole program: [step5.c](../../c/examples/guests/step5.c), 174 lines; 26,390 bytes
  on the card.

## Pointers and the code bank

The controls library uses 16-bit pointers into the program's **code bank** (where its
globals, string constants and `malloc` blocks are).

In the near data model this needs no care: every C data pointer is an offset in the code
bank, locals included (arrays, structures and locals whose address is taken live on the
software stack, in the code bank). A control may be a local of a function that does not
return while the control is in use (`main`'s), and a string may be anything. Only memory
of other banks (`__far` pointers) has to be copied in first: a `const char *` cannot hold
a far address at all (see [porting.md](porting.md)).

The structures' pointer fields are `__near` (16 bits), so a static initialiser takes a
string constant or a static array directly (`UI_LABEL(..., "Name:")`, `UI_FIELD(...,
name, sizeof name)`). The text a row function returns may be anywhere, a far bank too:
the library copies it.

## Events

```c
    for (;;) {
        void *c;
        if (ui_getev(0))                /* 0: wait; 1: poll (-1 at once when none) */
            continue;
        switch (ui_event(ctls, &c)) {
        case UA_CLICK:  ...             /* c: the button */
        case UA_CHANGE: ...             /* c: the field, list or scroll bar */
        case UA_OPEN:   ...             /* c: the list */
        case UA_NONE:   ...             /* ui_ev.type: WE_CLOSE, WE_MENU, WE_KEY, ... */
        }
    }
```

The events that reach the program as `UA_NONE`, by `ui_ev.type`, with the meaning of
`a`, `b` and `c`:

- `WE_CLOSE`: the close box, ctrl+W, the Desktop's Shut down.
- `WE_MENU`: a = menu, b = item (counting separators).
- `WE_KEY`: a = HID usage, b = modifiers, `| $100` when pressed (`hz_key_ascii(a, b)`
  gives ASCII).
- `WE_BUTTON`: a, b = the pointer in the content, c = buttons (2: right, for `ui_popup`).
- `WE_RESIZE`: a, b = the new content size (windows opened with `WF_RESIZE`). Change the
  controls' x, y, w, h and draw them again.
- `WE_TICK`: the window's timer (`hz_win_timer`).
- `WE_DROP`: something was dropped on the window (a file from Files).
  `hz_win_dropget(win, buf128)` reads the string.
- `WE_WHEEL`, `WE_MOTION`, `WE_FOCUS`, `WE_UNFOCUS`, `WE_NET`, ...: see
  [windows.md](../reference/windows.md).

Drag and drop: Files drops a file's path on a window (`WE_DROP`); a program can drop a
string on any window with `hz_win_drop(win, s)`. The [viewer](../../c/examples/viewer)
opens a file dragged onto it (its `desktop.script` drags one from Files).

A window program started from the shell (not the Desktop) gets `hz_ws_start() == 1` and
stops the window system when it ends; its `printf` output goes to the console log.

## Callbacks

Two library features call into your C code:

- A list's row text, set by `UI_LIST(..., fn)` (or `ls.rowfn = fn`). Signature:
  `const char *fn(ui_list *ls, unsigned row, const ui_rowinfo *ri)`. `ri` has `win`, `x`,
  `y` (the row's top left) and `sel` (1 if selected).
- The copy routines' progress, set by `ui_setcpcb(fn)` (NULL: none; `ui_cpwin` replaces
  it). Signature: `int fn(const char *name, unsigned kdone, unsigned long size)`. A
  nonzero result cancels the copy (`ui_cptree` then returns -1, `hz_errno ==
  HZ_ECANCELED`).

A callback runs inside a library call (a list's drawing, a copy). It may compute, call the
C library and `hz_` functions, and draw: `ui_rect`, `ui_text`,
`ui_bevel`, `ui_copy`, `ui_twidth`, `ui_cwidth`, `ui_btnw`, `ui_fit`, the clock and
string functions. It must **not** call a control or dialog routine (`ui_draw`,
`ui_drawall`, `ui_event`, `ui_getev`, `ui_lsset`, `ui_alert`, `ui_filedlg`, ...: those
marked `ctl` in `ui/hui.tab`), because the library is in the middle of its own work. Such
a call stops the program with a message:

```
hui: ui_lsset: a control routine called inside a callback (a list's row function, the copy callback): a callback may only draw
```

It should return quickly (a row function runs for every row drawn). The library's
direct page is saved before the call and restored after it, so drawing inside the
callback does not disturb the list being drawn.

## Reference

### Structures

Laid out from `ui.inc`'s offsets by `tools/genhui.py` (in `include/huigen.h`). The
fields ending in `_` are the library's. The controls' fields follow the header `type, win,
x, y, w, h, flags`.

- `ui_button`: `label`. Initialiser `UI_BUTTON(x, y, w, flags, label)` (height
  `UI_BTNH`).
- `ui_label`: `text`. Initialiser `UI_LABEL(x, y, w, flags, text)` (height `UI_LINE`).
- `ui_field`: `buf`, `max` (its size), `len`, `cur`, `anc`, `scr`. Initialiser
  `UI_FIELD(x, y, w, flags, buf, size)` (height `UI_FLDH`).
- `ui_scroll`: `pos`, `max` (total - visible), `page`, `step`. Initialisers
  `UI_VSCROLL(x, y, h, max, page, step)`, `UI_HSCROLL(x, y, w, max, page, step)`.
- `ui_list`: `count`, `sel`, `top`, `indent`, `rowfn`. Initialiser `UI_LIST(x, y, w, h,
  flags, rowfn)`.
- `ui_ctl`: the header alone.
- `ui_alertblk`: `kind` (`AL_INFO`, `AL_WARN`, `AL_QUESTION`, `AL_ERROR`), `title`,
  `text`, `b1`, `b2`, `b3`. Initialiser `{ kind, title, text, b1, b2, b3 }`.
- `ui_dlgblk`: `title`, `w`, `h`, `list`, `win`. Initialiser `{ title, w, h, controls,
  0 }`.
- `ui_askblk`: `title`, `prompt`, `buf`, `size`, `ok`. Initialiser `{ title, prompt, buf,
  size, 0 }`.
- `ui_clock`: `year`, `mon`, `day`, `hour`, `min`, `sec`, `wday` (the variable `ui_clk`).
- `ui_ctlref`: a control list's entry: `static ui_ctlref ctls[] = { &a, &b, 0 };`.

Flags (`flags`): `UF_FOCUS` (has the keyboard), `UF_DEFAULT` (Enter), `UF_CANCEL` (Esc),
`UF_RIGHT` (a label right-aligned), `UF_DIM` (greyed; a dimmed button ignores clicks). Metrics:
`UI_LINE` 12, `UI_BTNH` 20, `UI_FLDH` 18, `UI_ROWH` 14, `UI_SBW` 14, `UI_GAP` 8.
Values of `hui.h`: `UI_NONE` (no row, no item), `UI_INK(ink, paper)`, `UI_NOPAPER`,
`UI_FILL(c)`, `UI_FRAME(c)`, `UI_DITHER(c1, c2)`. Every constant of `ui.inc` and
`icons.inc` (`UT_*`, `UA_*`, `AL_*`, `FT_*`, `ICO_*`, the `CT_*` ... offsets) is defined.

### Functions

Each prototype in `include/huigen.h` has its comment. The assembly reference
([controls.md](../reference/controls.md), `ui.inc`) has the details. Where the comment
states it, a -1 result also sets `hz_errno` (the Horizon error code).

- Start and events: `ui_init()`, `int ui_getev(poll)`, `hz_event ui_ev`.
- Controls: `ui_setwin(list, win)`, `ui_draw(ctl)`, `ui_drawall(list)`, `unsigned
  ui_event(list, &ctl)`, `ui_focus(ctl)`, `ui_sbset(sb, pos)`, `ui_sbpos(sb, pos)`,
  `ui_fdset(fd, text)`, `ui_lsset(ls, count)`, `ui_lssel(ls, row)`.
- Pop-up menus: `unsigned ui_popup(win, items)`, `unsigned ui_popat(win, items, x, y)`,
  `int ui_menukey()`.
- Dialogs: `unsigned ui_alert(al)`, `int ui_filedlg(save, path, title)`, `unsigned
  ui_dlfilt`, `int ui_dlgopen(dg)`, `void *ui_dlgrun(dg)`, `ui_dlgclose(dg)`, `int
  ui_ask(ak)`.
- Drawing: `ui_rect(win, x, y, w, h, op)`, `ui_bevel(win, x, y, w, h, sunken)`,
  `ui_text(win, x, y, font, colors, s)`, `ui_copy(win, x, y, w, h, dx, dy)`, `unsigned
  ui_twidth(s, font)`, `unsigned ui_cwidth(c, font)`, `ui_fit(s, width)`, `unsigned
  ui_btnw(label)`, `ui_beep()`, `ui_chime(kind)`.
- Programs and files: `int ui_launch(path, args, name)` (-1, hz_errno), (0.31) `int
  ui_run(path, args, name)`, `int ui_launchx(path, args, name)` with `ui_lxmode`
  (`LX_TERM`, `LX_TERME`, `LX_NOARG`), `ui_spawnerr(err, name)`, `unsigned
  ui_ftype(name)`, `int ui_open(path)`, `int ui_atload(path)` (kind or -1, hz_errno), `int
  ui_lnkread(path)` (`ui_lktgt`, `ui_lktitl`, `ui_lkargs`), `int ui_mklink(path)`, `const
  char *ui_prog(path, &icon)`, `unsigned ui_ficon(path, folder)`.
- Date: `ui_clock ui_clk`, `ui_clksplit(secs)`, `unsigned long ui_clkjoin()`, `int
  ui_clkcheck()`, `unsigned ui_clkmdays(month)`, `unsigned ui_clkfmt(buf20)`,
  `ui_clklong(buf32)`, `int ui_clkparse(s)`, `int ui_clkload()`, `int ui_clksave()`, `int
  ui_clkpc()`.
- Copying: `int ui_cptree(from, to)`, `int ui_rmtree(path)`, `int ui_mvtree(from, to)`
  (-1, hz_errno), `ui_cpwin(move)`, `ui_cpdone()`, `ui_setcpcb(fn)`, `ui_cpname`,
  `ui_cpk`, `ui_cpsize`, `ui_cpblk`, `ui_cpx`, `int ui_isurl(s)`, `ui_urlname(path,
  buf)`.
- ulib (Atari files): `unsigned atari_kind(path)`, `unsigned atari_rkind(path)`, `int
  atari_run(path)` (-1, hz_errno).

Not bound, because C has its own (`hui.tab` gives the reason for each): `ui_strcpy`, `ui_strlen`
(string.h), ulib's console output (`printf`: ulib's line buffer is never used from C,
so it cannot reorder with stdout), its keyboard and argument routines (`getchar`,
`hz_getline`, `hz_key_ascii`, `argv`), `spawn` (`hz_spawn_path`); the library's direct
page variables (`ui_x` ...: arguments of the drawing functions, `ui_rowinfo` in a row
function).

## Linking the library

The controls library is assembly (ca65), linked by ld65. hcc links it into the program, as
Horizon's own assembly programs do:

1. The SDK build (the first `hcc` of a program using `hui.h`): `tools/hui816.py`
   assembles the Horizon tree's current sources (`horizon/user/ui*.s` into `ui.lib`,
   `ulib.s` into `ulib.lib`, as Horizon's Makefile does), and a binding library
   `hui816.lib`: one generated shim per function and one alias per variable
   (`tools/genhui.py --shims` from `sdk/c/ui/hui.tab`), the SDK's helpers
   (`sdk/c/ui/lib`: the row and copy callbacks, the failure exit) and `ui/huirt.c`.
   All in `sdk/c/build/ui/small/` (and `large/` for the large code model), built again
   whenever one of those files changes.
2. A program's link: when ld65 reports a `hui.h` name undefined (or with `--ui`), hcc
   links again with the three libraries; ld65 takes the shims the program calls and the
   library's modules they need, and places the library's zero page after cc816's registers
   ($78 and up). No block, no list of bank bytes.
3. A call: C calls a shim with JSR (every argument on the stack). The shim checks that it
   is not called inside a callback where that is not allowed, loads A, X, Y and the
   library's direct-page arguments, JSRs the routine, and turns its registers and carry
   into the C result (0 / -1, `hz_errno`). Pointers need no check and no copy: they are in the code
   bank. A callback goes the other way: the library JSRs a small routine that saves the
   library's direct page and calls the C function (a list's row function through
   `HUI_ROWCB`, `hui_rowtramp`).

Measured (`hcc --map`):

| Program | Names of hui.h | Program on the card |
| --- | --- | --- |
| a program calling `ui_beep` only | 1 | 10,903 |
| `step1.c` (a window, `ui_getev`) | 3 | 16,821 |
| the c-window-app template | 10 | 25,168 |
| `step5.c`; the viewer | 15; 13 | 26,390; 26,214 |
| tests/ui/uitest.c (nearly everything) | 66 | 38,471 |

The library is linked by source file: `ui_beep` alone brings in `ui.s`, the core every
control needs. The shims make no checks or copies (the pointers are in the code bank
already), and the C library is linked by the function. The same template in assembly
(`sdk/templates/window-app`) is 16,744 bytes: C's own library (printf, files) is most of
the difference.

## Limits

- Data bank: the library runs with DBR = the code bank, as every C program does.
- Direct page: the library's variables follow cc816's registers ($00-$77). ld65 places
  them: 196 bytes in all for uitest. Your own assembly declares its zero page in a
  `ZEROPAGE` segment and ld65 places it too.
- Program size: the library takes 9-25 KB of the code bank (table above). Big data
  belongs in other banks (`hz_far_alloc`): the viewer keeps the file in one.
- A callback must not call a control routine. The library is not reentrant.
- The C binding has been built and tested in the emulator only, not on the board.

## Files

| | |
| --- | --- |
| `sdk/c/include/hui.h` | the header: the rule, the types, the initialisers |
| `sdk/c/include/huigen.h` | generated: the constants, the structures, the prototypes |
| `sdk/c/ui/hui.tab` | the signature table (its header explains the format) |
| `sdk/c/ui/lib/` | the SDK's assembly helpers (ca65): `hui816.inc`, `core.s`, `row.s`, `cpcb.s`, `setwin.s` |
| `sdk/c/ui/huirt.c` | the C side's failure exit |
| `sdk/c/tools/genhui.py` | huigen.h, the shims (`--shims`), the check |
| `sdk/c/tools/hui816.py` | the three libraries, `link_inputs()` |
| `sdk/c/tests/ui/` | `uitest.c` (+ script), `badhui.c` |
