# The controls library (ui.lib): controls, dialogs, alerts

Horizon's own programs (Files, Edit, Paint, Settings, BASIC, Sheet, Write, Calculator,
Solitaire) share one library for the standard look: buttons, labels, one-line text fields,
lists, scroll bars, alerts, the file open / save dialog, small dialogs, and launching
programs. Using it gives your program the same look and keyboard behaviour (Tab, Enter,
Esc, the clipboard in fields) for about 9 KB of code.

- Include `ui.inc` after `horizon.inc`; link `horizon/build/ui.lib` after your objects
  (the SDK templates: `UI := 1` in the Makefile).
- The full API, with every field and flag, is the comment block of
  `horizon/user/ui.inc`; this page is the overview with examples. A complete program:
  `sdk/templates/window-app/main.s`.
- Every routine: `jsr`, A/X/Y 16-bit, clobbers A, X, Y unless noted. Structures and
  strings must be **in your code bank** (= DBR): a "pointer" here is a 16-bit address.
- After `SYS_WSSTART` call `ui_init` once. Read events with `ui_getev` (not
  `SYS_WEVENT`): the library needs to see them, and dialogs keep events aside for you.

## The look

| Metric | Constant | Pixels |
| --- | --- | --- |
| A line of UI text | `UI_LINE` | 12 |
| Button height | `UI_BTNH` | 20 |
| Field height | `UI_FLDH` | 18 |
| List row | `UI_ROWH` | 14 |
| Scroll bar width | `UI_SBW` | 14 |
| Gap between controls, and to the window's edge | `UI_GAP` | 8 |

Raised controls: a 1-pixel bevel, white top-left, C_DARK bottom-right, in a C_DARK outline;
sunken ones (fields, lists): the reverse, white inside. Selection and focus: C_SELECT with
white text. Labels: the UI font, black. Positions and sizes on a 4-pixel grid.
More in the skill's `references/look-and-feel.md`.

## Controls

A control is a structure you own, in DATA (the library writes into it). Common header
(12 bytes): `u8 CT_TYPE`, `u8 CT_WIN` (set it to your window after SYS_WOPEN), `i16 CT_X,
CT_Y, CT_W, CT_H` (in the content), `u16 CT_FLAGS`. Then the type's fields.

| Type | Value | Fields after the header |
| --- | --- | --- |
| `UT_BUTTON` | 1 | `BT_LABEL` pointer to the label |
| `UT_VSCROLL` | 2 | `SB_POS`, `SB_MAX`, `SB_PAGE`, `SB_STEP`, 2 internal words |
| `UT_HSCROLL` | 3 | the same |
| `UT_FIELD` | 4 | `FD_BUF` buffer, `FD_MAX` its size, `FD_LEN`, `FD_CUR`, `FD_ANC`, `FD_SCR` |
| `UT_LIST` | 5 | `LS_COUNT`, `LS_SEL`, `LS_TOP`, `LS_ROW` (callback), `LS_INDENT`, internal (`LS_SIZE` bytes in all) |
| `UT_LABEL` | 6 | `LB_TEXT` pointer to the text |

| Flag | Value | |
| --- | --- | --- |
| `UF_FOCUS` | 1 | has the keyboard (one per window; Tab moves it) |
| `UF_DEFAULT` | 2 | button: Enter activates it |
| `UF_CANCEL` | 4 | button: Esc activates it |
| `UF_RIGHT` | 16 | label: right-aligned |
| `UF_DIM` | 32 | button / label: greyed, a button does not react |

A label, a field and a default button (their definitions are at the end of the example
below, after the code that sets them up and the event loop).

### Routines

| Routine | In | Does |
| --- | --- | --- |
| `ui_init` | - | once, after SYS_WSSTART |
| `ui_getev` | A = 0 wait / 1 poll | the next event into `ui_ev` (8 bytes, as SYS_WEVENT); C set: none |
| `ui_drawall` | X = control list | draws every control |
| `ui_draw` | X = control | draws one (after you changed it) |
| `ui_event` | X = control list, the event in ui_ev | routes it; A = `UA_NONE` 0 (yours), `UA_USED` 1, `UA_CLICK` 2 (a button), `UA_CHANGE` 3 (a value), `UA_OPEN` 4 (list: double click / Enter); X = the control |
| `ui_focus` | X = control | gives it the focus |
| `ui_fdset` | X = field, Y = string | new text (all selected) |
| `ui_sbset` / `ui_sbpos` | X = scroll bar, A = position | set (redraw all / only the thumb: `SB_POS` must still hold the position drawn now, the new one goes in A) |
| `ui_lsset` | X = list, A = rows | new row count (selection none) |
| `ui_lssel` | X = list, A = row | select and show a row |

Set every control's `CT_WIN`, draw them, then loop:
```asm
        ldx     #0
@set:   ldy     ctls,x                  ; every control is in window win
        beq     @drawn
        lda     z:win
        sep     #$20
        .a8
        sta     a:CT_WIN,y
        rep     #$20
        .a16
        inx
        inx
        bra     @set
@drawn: ldx     #.loword(ctls)
        jsr     ui_drawall
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #.loword(ctls)
        jsr     ui_event                ; A = UA_*, X = the control
        cmp     #UA_CLICK
        bne     @mine
        cpx     #.loword(b_ok)
        beq     @ok
        bra     loop
@mine:  cmp     #UA_NONE                ; menus, close, keys nobody took...
        bne     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        bne     loop
@ok:
        .segment "DATA"
ctls:   .addr   l_name, f_name, b_ok, 0        ; a control list (the Tab order)
l_name: .byte   UT_LABEL, 0
        .word   8, 12, 72, UI_LINE, 0, s_lab   ; x, y, w, h, flags, text
f_name: .byte   UT_FIELD, 0
        .word   88, 9, 200, UI_FLDH, UF_FOCUS, namebuf, 40, 0, 0, 0, 0
b_ok:   .byte   UT_BUTTON, 0
        .word   224, 40, 64, UI_BTNH, UF_DEFAULT, s_ok
        .segment "BSS"
namebuf: .res   40
        .segment "RODATA"
s_lab:  .byte   "Name:", 0
s_ok:   .byte   "OK", 0
        .segment "CODE"
```

**Lists** get their rows from a callback (`LS_ROW`): called with A = row, `ui_x` / `ui_y`
the row's top left, `ui_rsel` = 1 if selected; it returns X = pointer to the row's text
(and may draw a small icon in the `LS_INDENT` pixels). See `horizon/user/wfiles.s`.

**Scroll bars**: `SB_MAX` = total - visible, `SB_PAGE` = visible, `SB_STEP` = one line.
Each change gives UA_CHANGE with the new `SB_POS`. Example: `sdk/examples/hexview`.

## Alerts

`ui_alert` (X = block): a small modal window, centred, with an icon, 1-3 lines of text and
1-3 buttons. Out: A = the button chosen (0 = `AL_B1`, the rightmost and default; the last
one given is Cancel: Esc and the close box).

| Field | Offset | |
| --- | --- | --- |
| `AL_KIND` | 0 | 0 note, 1 warning (beeps) |
| `AL_TITLE` | 2 | title |
| `AL_TEXT` | 4 | message, lines separated by 10 |
| `AL_B1` | 6 | first button's label |
| `AL_B2` | 8 | second (0 = none) |
| `AL_B3` | 10 | third (0 = none) |

```asm
        ldx     #.loword(al_save)
        jsr     ui_alert                ; -> A = 0 Save, 1 Discard, 2 Cancel
        rts
al_save: .word  1, s_t, s_m, s_save, s_disc, s_canc
s_t:    .byte   "Notes", 0
s_m:    .byte   "Save the changes to this note?", 0
s_save: .byte   "Save", 0
s_disc: .byte   "Discard", 0
s_canc: .byte   "Cancel", 0
```

## The file dialog

`ui_filedlg`: A = 0 open / 1 save, X = a 128-byte path buffer, Y = the title. C clear:
the full path chosen is in the buffer; C set: cancelled. For a save dialog the buffer may
hold a suggested name. The dialog starts in, and changes, the task's current directory.
Save asks before replacing a file.
```asm
        stz     path                    ; nothing suggested
        lda     #0                      ; open
        ldx     #.loword(path)
        ldy     #.loword(s_title)
        jsr     ui_filedlg
        bcs     @cancel
        ; path = "/docs/NOTES.TXT"
@cancel: rts
s_title: .byte  "Open a note", 0
```
In the Open dialog the list has the keyboard focus: typing a name does not go to the Name
field (click it first); a double click or Enter on a file opens it.

## Small dialogs

`ui_ask` (X = block `{AK_TITLE, AK_PROMPT, AK_BUF, AK_SIZE, AK_OK}`): asks for one value
(a label, a field, Cancel and OK). C clear: the buffer holds the answer.
```asm
        ldx     #.loword(ask)
        jsr     ui_ask
        bcs     @no                     ; cancelled
@no:    rts
ask:    .word   s_at, s_ap, buf, 32, 0  ; title, prompt, buffer, size, OK label (0: "OK")
s_at:   .byte   "New level", 0
s_ap:   .byte   "Name of the level:", 0
```

`ui_dlgopen` / `ui_dlgrun` / `ui_dlgclose` (X = block `{DG_TITLE, DG_W, DG_H, DG_LIST,
DG_WIN}`): your own modal dialog of controls, centred; `ui_dlgrun` returns X = the button
pressed. See `horizon/user/edit.s` (Find, Replace, Go to line).

## Drawing helpers

Parameters in zero page: `ui_win`, `ui_x`, `ui_y`, `ui_w`, `ui_h`, `ui_font`, `ui_c2`.

| Routine | In | Draws |
| --- | --- | --- |
| `ui_rect` | A = WD_FILL / WD_FRAME / WD_DITHER \| colour << 8 | the rectangle ui_x, ui_y, ui_w, ui_h |
| `ui_bevel` | A = 0 raised / 1 sunken | a bevel just inside the rectangle |
| `ui_text` | X = string, A = ink \| paper << 8 | text at ui_x, ui_y (top), font ui_font |
| `ui_copy` | X, Y = destination | moves the rectangle (WD_COPY) |
| `ui_twidth` | X = string, A = font | -> A = width (no syscall) |
| `ui_fit` | X = string (writable), A = width | cuts it with "..." |
| `ui_btnw` | X = label | -> A = a button's width for it (at least 64) |
| `ui_beep` | - | the error beep |
| `ui_strcpy` | X = from, Y = to | copies -> A = length |
| `ui_strlen` | X = string | -> A = length |

```asm
        lda     z:win
        sta     z:ui_win
        lda     #8
        sta     z:ui_x
        lda     #80
        sta     z:ui_y
        stz     z:ui_font               ; the UI font
        ldx     #.loword(s_msg)
        lda     #C_BLACK | (C_BODY << 8) ; ink, paper
        jsr     ui_text
        rts
s_msg:  .byte   "Saved.", 0
```

## Programs and files

| Routine | In | Does |
| --- | --- | --- |
| `ui_launch` | X = path, Y = argument string (0: none), A = name for messages (0: from the path) | starts a program detached; on an error an alert says why (C set) |
| `ui_spawnerr` | A = a spawn error, X = name | the "Cannot start NAME" alert |
| `ui_ftype` | X = name or path | -> A = `FT_*` by the extension |
| `ui_open` | X = full path | opens it with its program (a folder in Files, .BAS in BASIC, an Atari file in the classic machine, ...) |
| `ui_cptree` | X = source path, Y = destination path (the new name) | (Horizon 0.20) copies a file (a file there is replaced), or a folder and everything in it (the destination folder must not exist); also between the card and the PC volume `/PC:`. C set: A = error |
| `ui_rmtree` | X = path | (0.20) deletes a file, or a folder and everything in it. C set: A = error |
| `ui_mvtree` | X = from, Y = to | (0.20) moves (`SYS_RENAME`); between the card and the PC volume (error $C9) it copies, then deletes the source. C set: A = error ($48: "to" exists) |
| `ui_clkpc` | - | (0.20) when the PC volume is there, sets the clock from the PC's clock and saves it to /SYSTEM/CLOCK. C set: no PC volume |

Paths are in the program's bank. These routines do not need the rest of the library (no
zero page): a console program can link them too. `ui_cpcb` (a word, 0 = none) may hold a
routine that `ui_cptree` calls after every 32 KB (for a progress line: `ui_cpk` = K copied of
the current file, `ui_cpsize` its size, `ui_cpname` its name).

```asm
        ldx     #.loword(s_edit)
        ldy     #.loword(s_file)        ; its argument: the file to open
        lda     #0
        jsr     ui_launch
        rts
s_edit: .byte   "/BIN/EDIT.PRG", 0
s_file: .byte   "/README.TXT", 0
```
