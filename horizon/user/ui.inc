; ui.inc - Horizon controls library (build/ui.lib, sources user/ui*.s): the shared look and
; the standard controls of desktop programs. Include it after horizon.inc and link
; build/ui.lib after your objects (ld65 ... prog.o build/ulib.o build/ui.lib; the Makefile's
; UIPROGS list does this).
;
; Conventions: every routine is called with JSR, A/X/Y 16-bit (a16 i16), and clobbers A, X,
; Y unless noted. Structures and strings live in the program's own bank (the code bank,
; = DBR): a "pointer" below is a 16-bit address there. The library uses SYS_WEVENT, so a
; program using it reads its events with ui_getev (into ui_ev) instead of SYS_WEVENT.
; Cost: about 8.7 KB of code (0.2 KB more with ui_dlg*, 0.3 KB with ui_ask, 1.6 KB and 0.5 KB of
; bss with ui_launch / ui_open, (0.21) 0.8 KB with ui_cpwin), 1.5 KB of bss, 38 bytes of zero
; page (ui_*), and a bank only while the file dialog is open. Examples: user/edit.s (a scroll
; bar, the dialogs, ui_dlg* for Find / Replace / Go to line).
;
; ---------------------------------------------------------------- the look
; Window body C_BODY. Raised controls (buttons, scroll bar arrows and thumb): a 1-pixel bevel,
; C_WHITE top/left, C_DARK bottom/right, inside a C_DARK outline. Sunken (fields, lists):
; C_DARK top/left, C_WHITE bottom/right, a white inside. Selection and focus: C_SELECT
; (white text on it). Labels: the UI font (font 0), black. Spacing: multiples of 4 pixels.
; Metrics (pixels):
UI_LINE  = 12           ; a line of UI text (caps 7 rows, descenders 2 more)
UI_BTNH  = 20           ; button height (width: ui_btnw)
UI_FLDH  = 18           ; text field height
UI_ROWH  = 14           ; list row height
UI_SBW   = 14           ; scroll bar width (vertical) / height (horizontal)
UI_GAP   = 8            ; the usual distance between controls and from the window edge
;
; ---------------------------------------------------------------- start
; ui_init           after SYS_WSSTART, before anything else: measures the UI font.
; ui_getev          A = 0 wait / 1 poll -> the next event in ui_ev (8 bytes: u8 type, u8 window,
;                   u16 a, b, c), C set if none (poll). Also returns an event put aside
;                   while an alert or file dialog was open (only WE_RESIZE / WE_CLOSE are kept).
;
; ---------------------------------------------------------------- controls
; A control is a structure the program owns (in its bank; static ones in DATA). Set CT_WIN
; once the window is open (SYS_WOPEN's result). Common header (12 bytes):
CT_TYPE  = 0            ; u8  UT_* below
CT_WIN   = 1            ; u8  the window it is in
CT_X     = 2            ; i16 position and size in the window's content
CT_Y     = 4
CT_W     = 6
CT_H     = 8
CT_FLAGS = 10           ; u16 UF_* below
UT_BUTTON = 1
UT_VSCROLL = 2
UT_HSCROLL = 3
UT_FIELD = 4
UT_LIST  = 5
UT_LABEL = 6
UF_FOCUS   = 1          ; has the keyboard (one per window; Tab moves it): a field, a list, or a
                        ; button (drawn with a dotted frame inside; Space or Enter activates it)
UF_DEFAULT = 2          ; button: Enter activates it (drawn with a heavier outline)
UF_CANCEL  = 4          ; button: Esc activates it
UF_PRESSED = 8          ; (internal) button held down
UF_RIGHT   = 16         ; label: right-aligned in its box
UF_DIM     = 32         ; button / label: drawn greyed, a button does not react
;
; button: a label centred; activates (UA_CLICK) on a release inside it after a press in it
; (a press does not give it the focus: only Tab does).
BT_LABEL = 12           ; u16 pointer to the label string
BT_SIZE  = 14
; label: static text (UI font), cut with "..." to its width. Height UI_LINE.
LB_TEXT  = 12           ; u16 pointer to the string
LB_SIZE  = 14
; scroll bar (UT_VSCROLL: CT_W = UI_SBW; UT_HSCROLL: CT_H = UI_SBW): arrows at both ends, the
; track, a thumb sized page / (max + page) of the track (at least 10 pixels). Press an arrow:
; +- step; press the track: +- page; drag the thumb; the wheel (vertical bars) 3 steps a
; notch. Each change gives UA_CHANGE with the new SB_POS.
SB_POS   = 12           ; u16 position 0 .. max
SB_MAX   = 14           ; u16 the largest position (total - visible; 0 = nothing to scroll)
SB_PAGE  = 16           ; u16 the visible amount (also the step of a track click)
SB_STEP  = 18           ; u16 the step of an arrow (and of a wheel notch / 3)
SB_GRAB  = 20           ; (internal) pointer offset inside the thumb while dragging
SB_PART  = 22           ; (internal) the part pressed: 0 none, 1 arrow -, 2 arrow +, 3 thumb
SB_SIZE  = 24
; text field (one line): the text in the program's buffer, zero-terminated. Keys: characters
; insert (replacing the selection), Backspace / Delete, Left / Right, Home / End, Shift +
; those select, ctrl-A all, ctrl-X / C / V cut / copy / paste (the system clipboard; a pasted
; line ends at its first line break). Mouse: a press places the cursor, a drag selects,
; Shift + press extends. Scrolls sideways when the text is wider than the box. Every change
; of the text gives UA_CHANGE; Enter goes to the window's default button (UA_CLICK on it).
FD_BUF   = 12           ; u16 pointer to the text buffer (zero-terminated)
FD_MAX   = 14           ; u16 the buffer's size (the text is at most FD_MAX - 1 long)
FD_LEN   = 16           ; u16 the text's length (keep it right if you change the buffer: ui_fdset)
FD_CUR   = 18           ; u16 cursor (0 .. len)
FD_ANC   = 20           ; u16 the selection's other end (= FD_CUR: none)
FD_SCR   = 22           ; u16 the first character shown
FD_SIZE  = 24
; list: rows of text (UI_ROWH high) in a sunken box with a vertical scroll bar at its right.
; The program gives the text of a row through a callback (LS_ROW): called with A = row,
; ui_x / ui_y = the row's top-left (inside the box), ui_win set and ui_rsel = 1 if the row is
; selected; it returns X = pointer to the row's text (copied and cut by the library) and may
; draw an icon in the LS_INDENT pixels at ui_x (with ui_rect; it must keep ui_x, ui_y and must
; not call other control routines). Keys (when focused): Up / Down, PgUp / PgDn, Home / End;
; Enter gives UA_OPEN. Mouse: a press selects (UA_CHANGE), a second press on the same row
; within 0.5 s gives UA_OPEN; the wheel scrolls 3 rows. Selecting scrolls to show the row.
LS_COUNT = 12           ; u16 rows (set with ui_lsset)
LS_SEL   = 14           ; u16 the selected row ($FFFF: none)
LS_TOP   = 16           ; u16 the first row shown
LS_ROW   = 18           ; u16 the callback's address
LS_INDENT = 20          ; u16 pixels left of the text for an icon (0: none)
LS_CLICK = 22           ; (internal) time of the last press (ms)
LS_SB    = 24           ; (internal) its scroll bar: a UT_VSCROLL structure (SB_SIZE bytes)
LS_SIZE  = LS_SB + SB_SIZE
;
; ui_draw           X = control: draws it (after a change of its fields, geometry, or at start).
; ui_drawall        X = control list: draws all of them.
; A control list: .addr ctl1, ctl2, ..., 0 (the order is the Tab order).
;
; ui_event          X = control list, the event in ui_ev -> A = UA_* and X = the control that
;                   acted (0 for UA_NONE). Routes: a left press to the control under the pointer
;                   (in the event's window; a field or list gets the focus), the motion and the
;                   release that follow to that same control, keys to the focused control of the
;                   event's window (Tab: the focus to the next control of that window in list
;                   order that takes it: a field, a list or a button not dimmed, Shift + Tab
;                   the one before, round; Enter: the focused button, else a focused list's
;                   UA_OPEN, else the default button; Space: the focused button; Esc: the
;                   cancel button), wheel steps to the first
;                   list or vertical scroll bar of that window. Events it does not use (menus,
;                   close, resize, keys nobody takes, presses outside the controls...) give
;                   UA_NONE: handle them yourself.
UA_NONE   = 0           ; not used: the program's
UA_USED   = 1           ; used, nothing to report
UA_CLICK  = 2           ; a button was activated
UA_CHANGE = 3           ; a value changed: scroll bar SB_POS, list LS_SEL, field text
UA_OPEN   = 4           ; list: double click or Enter on LS_SEL
;
; ui_focus          X = field, list or button: give it the focus (the others of its window in the list
;                   last given to ui_event / ui_drawall lose it; both redrawn). Set the
;                   initial focus by UF_FOCUS in CT_FLAGS before ui_drawall, or call this after.
; ui_sbset          X = scroll bar, A = position: clamped to 0 .. SB_MAX, stored, redrawn.
; ui_sbpos          X = scroll bar, A = position: as ui_sbset, but only the thumb is redrawn (a
;                   copy of it and the track where it was): for a bar drawn before with the
;                   same SB_MAX and SB_PAGE (only the position changed).
; ui_fdset          X = field, Y = pointer to a string: copied into the field's buffer (cut to
;                   FD_MAX - 1), cursor at the end, all selected, scrolled, redrawn.
; ui_lsset          X = list, A = row count: selection none, top 0, redrawn.
; ui_lssel          X = list, A = row ($FFFF none): selected, scrolled into view, redrawn.
;
; Drags: a press on a control captures the pointer; the WE_MOTION events (sent by the kernel
; while the button is held) and the release go to that control (thumb drag, selection drag).
; Drawing: controls redraw only what changed and draw text with its paper, so the screen
; never shows a blank control between two calls (the compositor may repaint at any time).
; Typical event loop:
;       loop:   lda #0
;               jsr ui_getev
;               bcs loop
;               ldx #.loword(my_controls)
;               jsr ui_event            ; A = UA_*, X = the control
;               cmp #UA_CLICK ...       ; react; UA_NONE: look at ui_ev yourself
; After WE_RESIZE: change the controls' CT_X .. CT_H and ui_draw them (the new area is C_BODY).
;
; (0.15) A right press on a text field (or the menu key / Shift+F10 while it has the focus)
; opens its pop-up menu: Cut, Copy, Paste, Select all (as ctrl-X, C, V, A; UA_CHANGE when
; the text changed).
;
; ---------------------------------------------------------------- pop-up menus (0.15)
; ui_popup          A = window, X = items -> A = the item chosen (counting separators), $FFFF:
;                   none (Esc, a click elsewhere). A pop-up menu (SYS_WPOPUP) at the pointer;
;                   the items are a menu's ("Open", "-", "Rename...", "", the last one empty;
;                   state bytes MS_STATE | MS_DIM / MS_CHECK and a TAB before a shortcut
;                   allowed; 24 at most). Blocks until it closes. Call it on a right press
;                   (WE_BUTTON with c & 2); the menu takes that button's release.
; ui_popat          the same at ui_x, ui_y of the window's content, the first item highlighted:
;                   for the menu key (from the keyboard, at the selection).
; ui_menukey        the event in ui_ev: C set if it is the menu key or Shift+F10 pressed.
;
; ---------------------------------------------------------------- dialogs (modal)
; While one is open, events of the program's other windows are dropped (a WE_RESIZE or
; WE_CLOSE is kept for ui_getev), and their keys go to the dialog. The dialogs' windows are
; WF_MODAL: a click on another window of the program raises the dialog instead (with the
; error beep).
;
; ui_alert          X = alert block -> A = the button chosen (0 = AL_B1 ...). A small window
;                   centred on the screen: an icon, the message (1-3 lines), 1-3 buttons at
;                   the bottom right (AL_B1 rightmost: the default, Enter; the last one given
;                   is the cancel button, Esc; the close box = cancel too).
AL_KIND  = 0            ; u16 AL_INFO .. AL_ERROR below: the icon and the chime it plays (CH_* of the same number)
AL_INFO  = 0            ;   information: a blue "i"
AL_WARN  = 1            ;   warning: a yellow triangle with "!"
AL_QUESTION = 2         ;   question (a confirmation): a blue "?"
AL_ERROR = 3            ;   error: a red square with "!"
AL_TITLE = 2            ; u16 pointer to the window title
AL_TEXT  = 4            ; u16 pointer to the message: lines separated by 10 (at most 3)
AL_B1    = 6            ; u16 pointers to the button labels (B2, B3: 0 = none)
AL_B2    = 8
AL_B3    = 10
;
; ui_filedlg        A = 0 open / 1 save, X = path buffer (128 bytes), Y = title -> C clear: the
;                   full path chosen is in the buffer; C set: cancelled (buffer unchanged).
;                   On entry the buffer may hold a suggested name (save; any folder part is
;                   ignored) or be empty. The dialog shows the current folder (it changes the
;                   task's current directory as the user moves: the next dialog starts there):
;                   its path, its entries (folders first, then names, ignoring case), a Name
;                   field (filled when a file is selected), and Parent / Cancel / Open (Save)
;                   buttons. Enter or a double click on a folder enters it; Backspace in the
;                   list or "Parent" goes up. Save asks before replacing a file. (0.15) Typing
;                   while the list has the focus selects the first name starting with the
;                   typed letters (a pause of 1 s starts again); when none does, the letters go
;                   to the Name field, which keeps the focus (a name or a path can be typed).
;                   ui_dlfilt (u16): set it to CK_DISK, CK_XEX or CK_CART before the call to
;                   list only folders and Atari files of that kind (cleared by the dialog).
;
; ui_dlgopen        X = dialog block: a modal window centred on the screen holding the block's
;                   controls (their CT_WIN is set here; CT_X, CT_Y in its content), drawn. Set
;                   a field's UF_FOCUS (and its text) before. C set: no window.
; ui_dlgrun         X = dialog block -> X = the button activated (Enter: the default button,
;                   Esc or the close box: the cancel button). The other events go to the
;                   controls. The dialog stays open: act, call it again, or ui_dlgclose.
;                   (ui_dlgopen takes the focus from the list's buttons: a field set there keeps it.)
; ui_dlgclose       X = dialog block: its window closed.
DG_TITLE = 0            ; u16 pointer to the window title
DG_W     = 2            ; u16 content width
DG_H     = 4            ; u16 content height
DG_LIST  = 6            ; u16 pointer to the control list (buttons, labels, fields)
DG_WIN   = 8            ; u16 (set by ui_dlgopen) the window
DG_SIZE  = 10
;
; ui_ask            X = ask block: a dialog asking for a value: the prompt (a label line), a
;                   text field holding the buffer's text (cut to the size, all selected),
;                   Cancel and OK (at least 248 pixels wide, as wide as the prompt).
;                   C clear: the buffer holds the text (Enter / OK); C set: cancelled (Esc,
;                   Cancel, the close box), the buffer as it was edited.
AK_TITLE = 0            ; u16 pointer to the window title
AK_PROMPT = 2           ; u16 pointer to the prompt
AK_BUF   = 4            ; u16 pointer to the buffer (zero-terminated: the text it starts with)
AK_SIZE  = 6            ; u16 the buffer's size (the text is at most AK_SIZE - 1 long)
AK_OK    = 8            ; u16 pointer to the OK button's label (0: "OK")
AK_SIZEOF = 10
;
; ---------------------------------------------------------------- programs and files
; ui_launch         X = program path, Y = argument string (0: none), A = its name for messages
;                   (0: from the path, the file name without its extension, capitalised:
;                   "/BIN/PAINT.PRG" "Paint") -> started detached (priority 1 | SP_DETACH).
;                   C clear: started (also when a single-instance program ran already: spawn
;                   answered ERUNNING, its windows were raised). C set: not started, A = the
;                   error, after the ui_spawnerr alert.
; ui_spawnerr       A = a spawn error, X = the program's name: a warning alert "Cannot start
;                   NAME" saying why (ENOMEM not enough memory, EAGAIN too many programs, $44 /
;                   $45 not on the card, EINVAL not a Horizon program; others: the code).
; ui_ftype          X = a file name or path -> A = its type FT_* by its extension (Atari files
;                   by ulib atari_kind; never FT_FOLDER: the caller knows its folders).
; ui_open           X = the full path of a file or folder: opened by its type. A folder: Files
;                   there; a .PRG: started (refused with an alert under /SYSTEM: Horizon's
;                   own); an Atari file: ulib atari_run (returns after F12); the others: their
;                   program with the path (quoted). C clear: opened; C set: not (an alert said
;                   why: no program for it, a system program, the spawn error...).
; ui_atload         (0.15) X = an Atari file's path: loaded into the Atari, nothing booted (a
;                   disk on the first empty drive, D1: when all are taken; an executable; a
;                   cartridge). C clear: A = the kind mounted (CK_*); C set: A = 0 not an
;                   Atari file, else classic_mount's error (ENOMEM: no room for a
;                   cartridge). (0.18) A cartridge is a power cycle: the executable is
;                   ejected first, and after the mount the classic machine is cold booted
;                   without being shown (classic_boot CB_STAY; its error, if any).
FT_OTHER   = 0          ; no program for it
FT_FOLDER  = 1          ; a folder (Files)
FT_ATARI   = 2          ; .atr .xfd .xex .com .exe .car .rom .bin (the classic machine)
FT_PRG     = 3          ; a Horizon program
FT_TEXT    = 4          ; .txt .doc .nfo .cfg .ini .asc .log .s .inc .asm (Edit)
FT_BASIC   = 5          ; .bas (BASIC)
FT_PICTURE = 6          ; .pic (Paint)
FT_SHEET   = 7          ; .sht .csv (Sheet)
FT_WRITE   = 8          ; .md (Write)
FT_LINK    = 9          ; (0.14) .lnk: a shortcut (ui_open opens its target)
;
; (0.14) shortcuts: a .LNK file is text: the target's absolute path on a line of its own,
; optional "title=Name" (the label the Desktop shows) and "args=..." (a program's argument
; string); '#' starts a comment.
; ui_lnkread        X = the path of a .LNK -> ui_lktgt, ui_lktitl, ui_lkargs (128 + 0 each,
;                   "" when missing). C set: unreadable or no target.
; ui_mklink         X = a path: a shortcut to it in /Desktop (NAME.LNK; NAME 2.LNK ... when
;                   taken). C set: not made.
; ui_prog           X = a program's path -> X = its name ("Calculator"; 0: not one of
;                   Horizon's), A = its icon (ICO_*, icons.inc).
; ui_ficon          X = a path, A = 1 if it is a folder -> A = its icon (ICO_*, icons.inc):
;                   a program, a document by its type, an Atari file by its kind.
;
; ---------------------------------------------------------------- the date (0.14, uidate.s)
; The kernel's clock counts seconds since 2000-01-01 00:00 (SYS_TGET / SYS_TSET); the board
; has no battery clock, so the last value is kept in /SYSTEM/CLOCK ("YYYY-MM-DD HH:MM:SS").
; ui_clk holds a date as u16 fields (offsets CK_*); the weekday is 0 Sunday .. 6 Saturday.
; ui_clksplit       A = seconds low, X = high -> ui_clk (every field, the weekday too).
; ui_clkjoin        ui_clk (year .. second) -> A = seconds low, X = high (and the weekday).
; ui_clkcheck       C set if ui_clk is not a valid date and time (2000 .. 2135).
; ui_clkmdays       A = month 1-12 (of ui_clk's year) -> A = its days.
; ui_clkfmt         Y = buffer (20 bytes): "YYYY-MM-DD HH:MM:SS" -> A = 19.
; ui_clklong        Y = buffer (32 bytes): "Tuesday, 17 November 2026".
; ui_clkparse       X = "YYYY-MM-DD HH:MM[:SS]" (any separators) -> ui_clk; C set: not valid.
; ui_clkload        the clock never set: /SYSTEM/CLOCK becomes its provisional start
;                   (SYS_TSET CLK_SAVED). C set: nothing loaded.
; ui_clksave        the clock (set or loaded) written to /SYSTEM/CLOCK. C set: not saved.
;                   (0.20) ui_clkload first asks the PC (ui_clkpc) when the clock is not set.
; ui_clkpc          (0.20) the PC link: when the PC volume is there (STAT /PC: works), its
;                   time (the PC's clock) sets the clock (CLK_SET) and is saved to
;                   /SYSTEM/CLOCK. C set: no PC volume (nothing changed).
;
; ---------------------------------------------------------------- copying (0.20, uicopy.s)
; Paths in the program's bank. Self-contained (no zero page; the shell links it too).
; ui_cptree         X = source, Y = destination (the new name): a file copied (a file there is
;                   replaced), or a folder and everything in it (the destination folder must
;                   not exist). Not into itself (EINVAL). C set: A = error (a file copied in
;                   part is deleted; what was copied before it stays). Works between the card
;                   and the PC volume (/PC:) both ways.
; ui_rmtree         X = path: a file deleted, or a folder and everything in it. C set: A = error.
; ui_mvtree         X = from, Y = to: moved (SYS_RENAME); between the card and the PC volume
;                   (SYS_RENAME's $C9) copied with ui_cptree, then the source deleted with
;                   ui_rmtree. C set: A = error ($48: "to" is there already). (0.21) The source
;                   is deleted only when the whole copy worked: never after an error or a
;                   cancel.
; ui_cpcb           (word) a routine called when a file starts (ui_cpk = 0) and after every
;                   piece copied (0.21: 16 KB; 0.20: 32 KB), 0 = none (the default):
;                   ui_cpname = the file's name (in the library's copy of the path), ui_cpk =
;                   K of it copied so far (rounded up), ui_cpsize = its size (u32). It may
;                   change A, X, Y. (0.21) It returns C clear to go on, C set to cancel: the
;                   library closes both files, deletes the partial file (on the card or on
;                   /PC:), stops (in a folder copy what was copied before stays) and returns C
;                   set, A = ECANCELED. An error ($C8 the PC link lost, ...) also deletes the
;                   partial file.
; ---------------------------------------------------------------- copy progress (0.21, uicpwin.s)
; ui_cpwin          A = 0 copy / 1 move: the progress window for the next ui_cptree / ui_mvtree
;                   (call it just before; it sets ui_cpcb). The window ("Copying" / "Moving",
;                   modal, centred) opens only when the copy still runs about 0.5 s after this
;                   call, so a small copy shows nothing. It shows the file's name, "123 of
;                   1,500 KB (8%)", a bar and a Cancel button. Between two pieces it looks at
;                   the events that came, without waiting: Cancel, Esc or its close box cancel
;                   the copy (ui_cptree / ui_mvtree return C set, A = ECANCELED: show no error
;                   for it); keys of the program's other windows go to it, their other events
;                   are dropped (a WE_RESIZE or WE_CLOSE is kept for ui_getev), as for a dialog.
;                   Only what changed is redrawn.
; ui_cpdone         after ui_cptree / ui_mvtree: the window closed if it opened, ui_cpcb = 0.
;                   Keeps A and the carry: jsr ui_cptree, jsr ui_cpdone, bcs error.
CK_YEAR  = 0
CK_MON   = 2
CK_DAY   = 4
CK_HOUR  = 6
CK_MIN   = 8
CK_SEC   = 10
CK_WDAY  = 12
;
; ---------------------------------------------------------------- drawing helpers
; Parameters in zero page: ui_win (window), ui_x, ui_y, ui_w, ui_h, ui_font (0 UI, 1 fixed).
; ui_rect           A = WD_FILL / WD_FRAME / WD_DITHER | colour << 8 (WD_DITHER: second colour
;                   in ui_c2): the rectangle ui_x, ui_y, ui_w, ui_h of window ui_win.
; ui_bevel          A = 0 raised / 1 sunken: the 1-pixel bevel just inside ui_x, ui_y, ui_w, ui_h.
; ui_text           X = string, A = ink | paper << 8 (paper $FF: none): at ui_x, ui_y (its top),
;                   font ui_font. Keeps ui_x .. ui_h.
; ui_copy           X, Y = destination: the rectangle ui_x, ui_y, ui_w, ui_h of window ui_win
;                   moves there (WD_COPY: one blitter COPY; the two may overlap).
; ui_twidth         X = string, A = font -> A = its width in pixels (computed locally: no syscall).
; ui_cwidth         A = character, X = font -> A = its advance (UI font: 2-7; fixed: 8). Keeps X, Y.
; ui_fit            X = string (writable), A = width: cut it with "..." to fit (UI font).
; ui_btnw           X = label -> A = the width of a button for it (at least 64).
; ui_beep           the error beep (0.15: the soft error chime, CH_ERROR, at the beep volume).
; ui_chime          A = CH_* kind: that chime at the beep volume setting (0.15).
; ui_strcpy         X = source, Y = destination: copy a zero-terminated string -> A = length.
; ui_strlen         X = string -> A = length.

; library state, for programs that need it
.global ui_init, ui_getev, ui_draw, ui_drawall, ui_event, ui_focus, ui_sbset, ui_fdset
.global ui_lsset, ui_lssel, ui_alert, ui_filedlg, ui_rect, ui_bevel, ui_text, ui_twidth
.global ui_cwidth, ui_fit, ui_btnw, ui_beep, ui_strcpy, ui_strlen, ui_copy, ui_sbpos
.global ui_dlgopen, ui_dlgrun, ui_dlgclose, ui_ask
.global ui_popup, ui_popat, ui_menukey, ui_chime, ui_dlfilt, ui_atload
.global ui_launch, ui_spawnerr, ui_ftype, ui_open
.global ui_lnkread, ui_mklink, ui_prog, ui_ficon, ui_lktgt, ui_lktitl, ui_lkargs
.global ui_clk, ui_clksplit, ui_clkjoin, ui_clkcheck, ui_clkmdays, ui_clkfmt, ui_clklong
.global ui_clkparse, ui_clkload, ui_clksave, ui_clkpc
.global ui_cptree, ui_rmtree, ui_mvtree, ui_cpcb, ui_cpname, ui_cpk, ui_cpsize
.global ui_cpwin, ui_cpdone
.global ui_ev                   ; 8 bytes: the event (ui_getev)
.globalzp ui_win, ui_x, ui_y, ui_w, ui_h, ui_font, ui_c2, ui_rsel

; (internal: shared between the library's files)
.global ui_blk, ui_tbuf, ui_wdraw, ui_kmod, ui_key, ui_defer_put
.global ui_sb_draw, ui_sb_press, ui_sb_drag, ui_sb_wheel, ui_sb_geom
.global ui_fd_draw, ui_fd_press, ui_fd_drag, ui_fd_key
.global ui_ls_draw, ui_ls_press, ui_ls_drag, ui_ls_key, ui_ls_wheel, ui_ls_show
.global ui_muldiv
.globalzp ui_c, ui_t0, ui_t1, ui_t2, ui_t3, ui_t4, ui_t5, ui_p, ui_q
