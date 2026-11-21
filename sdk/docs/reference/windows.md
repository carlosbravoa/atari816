# Syscalls: the window system

The desktop is 640 x 360 pixels, 8 bits per pixel, shown 2 x 2 on a 1280 x 720 monitor.
Every window has its own bitmap: you draw into it with `win_draw` (see
[drawing.md](drawing.md)) and never redraw on exposure; the kernel's compositor shows it.
Programs cannot write to the screen memory or the hardware directly.

Examples assume `win`, `t0`, `t1` in ZEROPAGE and `ev` (8 bytes), `blk` (16), `buf` (256)
in BSS. Programs that use the controls library read events with `ui_getev` instead of
`SYS_WEVENT` ([controls.md](controls.md)).

## Starting and ending

### $70 ws_start (SYS_WSSTART)
Starts the window system if it is not running. Out: A = 1 started now (you own it), 0
already running (the Desktop). ENOMEM without 6 contiguous free banks. Every window
program calls it first.
```asm
        sys     SYS_WSSTART
        bcs     @fail
        sta     z:t0            ; 1: ours, stop it at the end
@fail:
```

### $71 ws_stop (SYS_WSSTOP)
Its starter only (else EINVAL): every window closes, the text console comes back. Call it
before exit when ws_start returned 1 (a program started from the text shell).
```asm
        lda     z:t0            ; what ws_start returned
        beq     :+
        sys     SYS_WSSTOP
:
```

## Windows

Geometry: a window has a 1-pixel black border and a 14-line title bar with a close box; its
**content** starts 1 pixel right and 16 lines below the outer top left (measured: a window
opened at (10, 20) has its content at (11, 36)). Outer size = content + 2 wide, content
+ 17 high (+ 12 more with WF_RESIZE, the bottom strip with the size grip). Windows are
kept on screen and below the 16-line menu bar (y >= 16). All coordinates in win_draw and in
events are content coordinates.

| Flag | Value | Meaning |
| --- | --- | --- |
| `WF_RESIZE` | 1 | a size grip; WE_RESIZE after a resize |
| `WF_PLAIN` | 2 | no border, no title: the content is the whole window (a game's "full screen": 640 x 344 at (0, 16)) |
| `WF_BACK` | 4 | a backdrop (the Desktop's): always below the others, gets F12 and shows its menus first |
| `WF_TERM` | 16 | a terminal of 8 x 12 cells (see ws_term) |
| `WF_MODAL` | 32 | a dialog: a click on another window of the same program raises the dialog instead (with the error beep) |
| `WF_HOVER` | 64 | motion events also without a button held, and WE_LEAVE |

### $72 win_open (SYS_WOPEN)
In: X, Y = `{i16 x, i16 y, u16 width, u16 height, u24 title, u8 flags}` (x, y = the outer
top left; width, height = the content size). Out: A = window (0-15). It opens on top with
the focus; its content is C_BODY. The title is copied (31 characters). ENOMEM: no banks;
EAGAIN: 16 windows open (the menu bar and an open menu count).
```asm
        ptr     wo
        sys     SYS_WOPEN
        bcs     @err
        sta     z:win
@err:   rts
wo:     .word   100, 60, 320, 200       ; x, y, content width, height
        .faraddr s_title
        .byte   0                       ; flags
s_title: .byte  "My window", 0
```

### $73 win_close (SYS_WCLOSE)
In: A = your window. A task's windows close at its exit anyway.
```asm
        lda     z:win
        sys     SYS_WCLOSE
```

### $78 win_move (SYS_WMOVE)
In: A = window, X = x, Y = y (outer top left; kept on screen).
```asm
        lda     z:win
        ldx     #200
        ldy     #100
        sys     SYS_WMOVE
```

### $88 win_title (SYS_WTITLE)
In: A = your window, X, Y = the new title (31 characters).
```asm
        lda     z:win
        ptr     s_new
        sys     SYS_WTITLE
        rts
s_new:  .byte   "Untitled *", 0
```

### $82 win_info (SYS_WINFO)
In: A = any window, X, Y = 8-byte buffer. Out: `{i16 content x, i16 content y on the
screen, u16 content width, u16 content height}`.
```asm
        lda     z:win
        ptr     buf
        sys     SYS_WINFO
        lda     buf+4           ; content width
```

### $83 win_at (SYS_WINAT)
In: X = screen x, Y = screen y. Out: A = the top-most window there ($FF = none; the menu
bar does not count, a backdrop does).
```asm
        ldx     #320
        ldy     #180
        sys     SYS_WINAT       ; -> A = window or $FF
```

## Events

### $75 win_event (SYS_WEVENT)
In: A = 0 wait / 1 poll, X, Y = 8-byte buffer. Out: the next event of any of your windows,
`{u8 type, u8 window, u16 a, u16 b, u16 c}`. Polling with nothing queued: C set, A =
EAGAIN. Each window queues 32 events; when full, new ones are dropped (when three quarters
full, key releases are dropped).

| Type | Value | a | b | c |
| --- | --- | --- | --- | --- |
| `WE_KEY` | 1 | HID usage (F12 = $FF, to the backdrop) | modifiers \| down << 8 | - |
| `WE_BUTTON` | 2 | x | y (content, signed) | buttons \| modifiers << 8 |
| `WE_CLOSE` | 3 | - | - | - |
| `WE_WHEEL` | 4 | steps (signed: positive = up / away; to the window under the pointer) | - | - |
| `WE_TICK` | 5 | - | - | - |
| `WE_RESIZE` | 6 | new content width | height | - |
| `WE_MENU` | 7 | menu (0 = your first) | item (separators count) | - |
| `WE_DROP` | 8 | x | y | the sender's task id |
| `WE_MOTION` | 9 | x | y | buttons \| modifiers << 8 |
| `WE_LEAVE` | 10 | - | - | - |
| `WE_SYSREQ` | 11 | what SYS_SYSREQ asked (backdrop only) | - | the asking task |
| `WE_STATUS` | 12 | (backdrop only) the status text was clicked | - | - |
| `WE_MENUOPEN` | 13 | (backdrop only) one of its menus is opening | - | - |
| `WE_FOCUS` | 14 | (0.15) the window got the keyboard focus | - | - |
| `WE_UNFOCUS` | 15 | (0.15) it lost it; the keys it held got their releases just before | - | - |
| `WE_VBL` | 16 | (0.18) a vertical blank, asked for with `win_vbl` ([games.md](games.md)) | - | - |
| `WE_NET` | 17 | (0.22) to the program's first window: bit mask of its internet handles (4-7) with news ([internet.md](internet.md)) | - | - |

- **Keys** go to the focused window (the top one). A held key repeats as further down
  events (the user's repeat setting). Modifier bits: 0 left ctrl, 1 left shift, 2 left
  Alt, 3 left GUI, 4-7 the right ones. Some keys never reach programs: F10 and Alt alone
  (menus), Alt+letter of a menu title, Alt+Tab, Alt+F4 and ctrl+W (they send WE_CLOSE),
  F12 (the classic machine).
- **Buttons**: c bits 0 left, 1 right, 2 middle (mask with `$0007`); a press has the bit
  set, the release has it clear. A left press in your content holds the press: you get the
  motion events and the release even outside the window.
- **Motion** comes while a button is held after a press in the window, or always over a
  WF_HOVER window. A queued motion event is updated, not repeated (you get the latest
  position).
- **WE_CLOSE** comes from the close box, Alt+F4, ctrl+W, and from the Desktop's Restart /
  Shut down (it asks every program to close). The window stays open until you close it
  (or exit). Ask about unsaved work there.
- **Focus** (0.15): WE_FOCUS when a window gets the keyboard focus, WE_UNFOCUS when it loses
  it (the keys it held got their releases just before). A game pauses on WE_UNFOCUS. The
  sprites of a window and the palette entries of a program show only while it has the focus;
  a full-screen program's screen only while its window has it ([games.md](games.md)).

```asm
loop:   lda     #0              ; wait
        ptr     ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev
        and     #$00FF          ; the type
        cmp     #WE_CLOSE
        beq     @quit
        cmp     #WE_KEY
        bne     loop
        lda     ev+4            ; b: modifiers | down << 8
        and     #$0100
        beq     loop            ; a release
        lda     ev+2            ; a: the HID usage
        cmp     #$29            ; Esc
        bne     loop
@quit:
```

### $7C win_timer (SYS_WTIMER)
In: A = window, X = period in 10 ms ticks (0 = off). WE_TICK events for that window: the
heartbeat of animations and games (2 = 50 per second).
```asm
        lda     z:win
        ldx     #2              ; every 20 ms
        sys     SYS_WTIMER
```

### $8A ws_mouse (SYS_WMOUSE)
In: A = a window ($FF = none), X, Y = 10-byte buffer. Out: buffer `{i16 x, i16 y on the
screen, i16 x, i16 y relative to window A's content, u16 buttons}`; A = buttons, X = the
window under the pointer ($FF: none or the menu bar). The pointer now, without an event.
```asm
        lda     z:win
        ptr     buf
        sys     SYS_WMOUSE      ; buf+4, buf+6 = pointer in our content
        lda     buf+4
```

## Menus

### $7D win_menu (SYS_WMENU)
In: A = window, X, Y = the menus: `"title", "item", ..., "", "title", ..., "", ""`
(zero-terminated strings; an empty string ends a menu, another one ends the list). An
item `"-"` is a separator (it counts in the item numbers). An item may hold a TAB: the text
after it is shown right-aligned (a shortcut such as "Ctrl+S"; the program handles the key
itself). An item may start with a state byte `MS_STATE | bits` (MS_CHECK a check mark,
MS_DIM greyed out). 254 bytes at most; the kernel reads 256 bytes at the pointer (128
if 256 are not readable), so keep the menus away from the end of a bank (Edit pads its
menu block to 256 bytes). The bar shows the backdrop's menus, then the
focused window's. A choice gives WE_MENU (a = menu, b = item).

| Constant | Value |
| --- | --- |
| `MS_STATE` | $10 |
| `MS_CHECK` | 1 |
| `MS_DIM` | 2 |

```asm
        lda     z:win
        ptr     menus
        sys     SYS_WMENU
        rts
menus:  .byte   "File", 0
        .byte   "New", 9, "Ctrl+N", 0
        .byte   "-", 0
        .byte   "Quit", 9, "Ctrl+Q", 0, 0
        .byte   "View", 0
        .byte   MS_STATE | MS_CHECK, "Grid", 0, 0
        .byte   0
```

### $8C win_mstate (SYS_WMSTATE)
In: A = your window, X = menu | item << 8, Y = MS_CHECK and / or MS_DIM. The item must
start with a state byte. EINVAL: no such window, menu or item.
```asm
        lda     z:win
        ldx     #1 | (0 << 8)   ; menu 1 (View), item 0 (Grid)
        ldy     #0              ; no check mark
        sys     SYS_WMSTATE
```

### $7E ws_status (SYS_WSTATUS)
In: X, Y = text for the right end of the menu bar (31 characters). The Desktop uses it for
the free memory and the time; a program should leave it alone.
```asm
        ptr     s_stat
        sys     SYS_WSTATUS
        rts
s_stat: .byte   "Level 3", 0
```

## Pointer

### $89 ws_pointer (SYS_WPTR)
In: A = shape: `PTR_ARROW` 0, `PTR_DRAG` 1 (carrying a document), `PTR_CROSS` 2,
`PTR_HSIZE` 3 (resize a column), `PTR_VSIZE` 4 (resize a row). Back to the arrow at exit.
There is no hidden pointer and no custom shape for programs.
```asm
        lda     #PTR_CROSS
        sys     SYS_WPTR
```

| Constant | Value |
| --- | --- |
| `PTR_ARROW` | 0 |
| `PTR_DRAG` | 1 |
| `PTR_CROSS` | 2 |
| `PTR_HSIZE` | 3 |
| `PTR_VSIZE` | 4 |

## Clipboard

### $80 clip_put (SYS_CLPUT)
In: X, Y = `{u24 data, u16 length}`. The system clipboard gets a copy (64 KB at most);
length 0 empties it. Text is plain bytes with LF line ends (Sheet puts tab-separated rows).
```asm
        ptr     cblk
        sys     SYS_CLPUT
        rts
cblk:   .faraddr s_clip
        .word   5
s_clip: .byte   "hello"
```

### $81 clip_get (SYS_CLGET)
In: X, Y = `{u24 buffer, u16 size}`. Out: A = the clipboard's length; min(length, size)
bytes are copied. Size 0 asks the length only.
```asm
        ptr     gblk
        sys     SYS_CLGET       ; -> A = length (only 255 copied)
        rts
gblk:   .faraddr buf
        .word   255
```

## Drag and drop

A program that drags something (a file name) shows `PTR_DRAG`, finds the window under the
pointer at the release (`SYS_WINAT`) and sends it a string with `SYS_WDROP`. The receiver
gets WE_DROP and reads the string with `SYS_WDROPGET`. Files and the Desktop send full
paths: drop a file from Files onto your window to get its path.

### $84 win_drop (SYS_WDROP)
In: A = any window, X, Y = a string (127 characters). That window gets WE_DROP (a, b = the
pointer in its content, c = your task id).
```asm
        ldx     #320            ; the release point (screen)
        ldy     #180
        sys     SYS_WINAT       ; -> A = window
        cmp     #$FF
        beq     :+
        ptr     path            ; "/docs/NOTES.TXT"
        sys     SYS_WDROP
:
```

### $85 win_dropget (SYS_WDROPGET)
In: A = your window, X, Y = 128-byte buffer: the last string dropped on it.
```asm
        lda     ev+1            ; the window of the WE_DROP event
        and     #$00FF
        ptr     path
        sys     SYS_WDROPGET    ; path = the dropped file's path
```

## Palette

### $86 ws_palette (SYS_WSPAL)
In: A = index, X = red | green << 8, Y = blue. Sets one palette entry.

- **0-15** (the UI colours): the system palette, for everyone (Settings sets the desktop's 2
  and 3). Leave them alone.
- **16-255** (Horizon 0.18): the entry becomes yours if nobody holds it (EAGAIN if another
  program does) and **shows your colour while one of your windows has the keyboard focus**,
  the system colour otherwise; it goes back to the system when you end (or `pal_alloc` 0).
  So changing it no longer changes other programs' windows while they are in front.
- In full-screen mode: your own palette, all 256 entries.

Several entries at once, and taking entries that nobody uses: `pal_set` and `pal_alloc`
([games.md](games.md), "Palette entries"). Before 0.18 an entry changed for every window, and
programs had to put it back at exit.
```asm
        lda     #231            ; entry 231 (cube white) to a pink, while we are in front
        ldx     #255 | (128 << 8)
        ldy     #192
        sys     SYS_WSPAL       ; C set, A = EAGAIN: another program holds 231
```

## Terminals

### $7F ws_term (SYS_WTERM)
In: A = your WF_TERM window ($FF = detach). From now on your console output and console
input (putc, puts, input_*) go to that window, and those of the programs you start. The
Terminal program is this plus `/BIN/SH.PRG`. A WF_TERM window of w x h pixels has w / 8 x
h / 12 cells and understands the console's control codes and escapes.
```asm
        ptr     tw              ; a WF_TERM window, 76 x 24 cells
        sys     SYS_WOPEN
        sta     z:win
        sys     SYS_WTERM       ; A = that window
        print   "now in the window\n"
        rts
tw:     .word   20, 30, 608, 288
        .faraddr s_term
        .byte   WF_TERM
s_term: .byte   "Log", 0
```

## Measuring and the compositor

### $77 ws_sync (SYS_WSSYNC)
Waits until the screen shows everything drawn so far. Useful before a screenshot or a
timing measurement; a game loop does not need it.
```asm
        sys     SYS_WSSYNC
```

### $8B ws_hold (SYS_WSHOLD)
In: A = 1 hold, 0 release. While you draw one change in several calls (a scroll and the
rows that come in) the compositor waits (5 ticks at most), so the screen never shows it
half done. Released at exit. A window not covered by another one draws straight onto the
screen and does not need it.
```asm
        lda     #1
        sys     SYS_WSHOLD
        ; ... several win_draw calls ...
        lda     #0
        sys     SYS_WSHOLD
```

### $79 ws_redraw (SYS_WSREDRAW)
Repaints the whole screen (for measurements).
```asm
        sys     SYS_WSREDRAW
```

### $7A ws_stats (SYS_WSSTATS)
Out: A, X = microseconds the last repaint took (low, high word).
```asm
        sys     SYS_WSREDRAW
        sys     SYS_WSSYNC
        sys     SYS_WSSTATS     ; A = us (low word)
```

### $7B ws_config (SYS_WSCONFIG)
In: A = bit 0 blitter off, bit 1 the compositor sleeps on the blitter interrupt, bit 2 no
direct drawing. Out: A = 1 if the blitter (Ali) is in use; X = the hardware revision
(SYS_REV, Horizon 0.16). For measurements and tests: it changes how everything is drawn.
`lda #0` restores the default and tells you whether the machine has a blitter (REV $08
and later); X tells the rest (POKEY sound on REV $07+, Lau, the sample player, on REV $0A+, the OPL2 on REV $0C+).
```asm
        lda     #0
        sys     SYS_WSCONFIG    ; -> A = 1: the blitter draws
```

## The Desktop's own calls

### $8D ws_closeall (SYS_WSCLOSEALL)
Every window of every other task gets WE_CLOSE (the Desktop's Restart and Shut down).
EINVAL without the window system. Not for applications.
```asm
        sys     SYS_WSCLOSEALL
```

### $8E win_geom (SYS_WGEOM)
In: A = own window, X, Y = {i16 x, i16 y, u16 width, u16 height}: moves and resizes it (x, y
its outer top-left, width, height its content; x = $8000: it stays where it is). No
WE_RESIZE comes (the program knows). Horizon 0.14. The Calculator changes its view this way.
```asm
        lda     #$8000          ; stays where it is
        sta     blk
        lda     #320            ; the new content size
        sta     blk+4
        lda     #200
        sta     blk+6
        lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WGEOM
```

### $8F task_name (SYS_TNAME)
In: A = task id (0: the caller), X, Y = string: the name the menu bar shows for the task's
windows (15 characters). Horizon 0.14. With A = id | $8000 (0.15) it reads that name
instead into a 16-byte buffer at X, Y.
```asm
        lda     #0
        ldx     #.loword(buf)   ; "Gem Run"
        ldy     #^buf
        sys     SYS_TNAME
```

### $90 win_popup (SYS_WPOPUP)
In: A = own window, X, Y = {u24 items, i16 x, i16 y, u8 flags}. Out: A = the item chosen
(counting separators), $FFFF if the menu was dismissed. Horizon 0.15: a pop-up menu just
right of and below x, y of the content (x = POP_HERE: at the pointer); the items are a
menu's ("Open", "-", "Rename...", "" at the end; state bytes and shortcut texts allowed; 24
at most). It blocks until it closes. Open it on a right press (WE_BUTTON, c & 2: the
menu takes that button's release, so a press, a drag and the release on an item picks it)
and on the menu key (usage $65) or Shift+F10 (flags POP_KEY: the first item highlighted).
The controls library has `ui_popup` and `ui_popat`.
```asm
        lda     #.loword(items)
        sta     blk
        lda     #^items
        sta     blk+2
        lda     #POP_HERE       ; at the pointer
        sta     blk+3
        lda     #0              ; (no flags)
        sta     blk+7
        lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WPOPUP
        cmp     #$FFFF
        beq     :+              ; dismissed
        ; A = 0 Open, 2 Delete
:       rts
items:  .byte   "Open", 0, "-", 0, "Delete", 0, 0
```

### $A0 win_front (SYS_WFRONT)
In: A = own window. The window comes back if it was minimized, is raised to the top of its
class and gets the keyboard focus (a WF_MODAL dialog of the same program stays over it), as
when the user picks it in the Windows menu. For a program that must show a window again by
itself: a window's sprites show only while it has the focus, and a full-screen window shows
its screen only then (BASIC 2.0 calls it at SCREEN, CONT and the end of INPUT). EINVAL: not
your window. Added with BASIC 2.0 (Horizon 0.18).
```asm
        lda     z:win
        sys     SYS_WFRONT      ; in front, with the focus
```

Focus (Horizon 0.15): win_event also gives WE_FOCUS (14) when a window gets the keyboard
and WE_UNFOCUS (15) when it loses it. Just before WE_UNFOCUS every key the window holds
gets its release (b = 0); the real release comes to nobody, so a game that counts held keys
never keeps one stuck.
