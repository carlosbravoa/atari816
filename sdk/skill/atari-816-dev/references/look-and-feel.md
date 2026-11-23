# Look and feel of Horizon programs

Horizon's own programs (Files, Edit, Write, Paint, Sheet, BASIC, Calculator, Settings)
follow these rules; a new program should too. Source: `horizon/user/ui.inc` ("the look"),
the programs themselves.

## Screen and grid

- 640 x 360 pixels, every pixel shown as 2 x 2 on the monitor. Think in screen pixels.
- A 16-line menu bar on top; windows below it. The Desktop's icons sit at the top right:
  open your window left of centre or centred, e.g. at x 100-160, y 40-80.
- **Positions and sizes on a 4-pixel grid.** The usual gap between controls and from the
  window edge is 8 (`UI_GAP`).
- Window content background: `C_BODY` (it starts so). Do not paint a window black unless
  it is a game or a picture.

## Fonts

- The UI font (font 0): proportional, 12-pixel lines (`UI_LINE`); labels, buttons,
  lists, messages.
- The fixed font (font 1): 8 x 12 cells; code, numbers in columns, terminals, hex dumps,
  game status lines.
- Only those two (printable ASCII 32-126). Bigger text: your own 1 bpp glyphs expanded and
  blitted (sdk/tools/font2inc.py).

## Colours

- Text: `C_BLACK` on `C_BODY`; secondary text `C_DARK`.
- Selection and focus: `C_SELECT` with `C_WHITE` text.
- Raised (buttons): 1-pixel bevel, white top-left, `C_DARK` bottom-right, `C_DARK` outline.
  Sunken (fields, lists): the reverse, white inside. Use ui.lib (`ui_bevel`) rather than
  drawing your own.
- Accents: `C_RED`, `C_YELLOW`, `C_GREEN`, `C_ORANGE` sparingly (warnings, status).
- Pictures and games: the 6 x 6 x 6 cube (16-231) and greys (232-255). Never change the
  palette entries 0-15 (every window uses them).

## Controls (ui.lib metrics)

| | Height | Notes |
| --- | --- | --- |
| Button | 20 (`UI_BTNH`) | width `ui_btnw` (at least 64); label centred |
| Text field | 18 (`UI_FLDH`) | |
| List row | 14 (`UI_ROWH`) | a scroll bar of 14 (`UI_SBW`) at the right |
| Label | 12 (`UI_LINE`) | a field's label left of it, vertically centred: label y = field y + 3 |

Buttons of a window or dialog: bottom right, the default (OK, Save, Open) rightmost,
Cancel left of it, 4 pixels apart; `UF_DEFAULT` on the default (Enter), `UF_CANCEL` on
Cancel (Esc). One control has `UF_FOCUS` at start (the first field).

## Menus

Every document program has, in this order:

```
File:  New / Open... / Save / Save as... / - / Close
Edit:  Undo / Redo / - / Cut / Copy / Paste / Select all   (what applies)
View:  options with check marks (MS_STATE | MS_CHECK)
```
then the program's own menus (Format, Program, Game...). A program without documents
(a game, a tool): `Game` (New game, -, Quit) or `File` (Close) at least.
- "..." after an item that opens a dialog.
- Shortcut texts after a TAB (`"Save", 9, "Ctrl+S"`): shown right-aligned; the program
  implements the key itself.
- Dim (MS_DIM) what does not apply now rather than hiding it.

## Keys

| Key | Meaning |
| --- | --- |
| ctrl+N / O / S | New / Open / Save |
| ctrl+Z / Y | Undo / Redo |
| ctrl+X / C / V / A | Cut / Copy / Paste / Select all (the system clipboard) |
| ctrl+F, F3 or ctrl+G, ctrl+H | Find, Find next, Replace |
| Enter / Esc in a dialog | the default button / Cancel |
| Tab / Shift+Tab | the next / previous control |
| ctrl+W, Alt+F4 | close the window (the kernel sends WE_CLOSE: you get the close event) |
| F10, Alt | the menus (the kernel handles them) |
| F12 | the classic Atari (never reaches programs) |

With `key_ascii`, ctrl+letter arrives as 1-26 (ctrl+S = 19), easier than HID codes.

## Windows and titles

- Title: the program's name, or `Program: FILE.TXT` for a document, with ` *` when it
  has unsaved changes (Edit, Paint, BASIC do this).
- WE_CLOSE (close box, ctrl+W, Alt+F4, the Desktop's Shut down): if there are unsaved
  changes, ask with an alert "Save the changes to NAME?" with **Save / Discard / Cancel**
  (kind 1 = warning); Cancel keeps the window open (the Desktop then cancels its shut
  down). Then close and exit.
- One instance only for tools and settings (`SYS_SINGLE` first thing).
- Resizable windows (`WF_RESIZE`): on WE_RESIZE move the controls, redraw (the new area is
  C_BODY already).

## Dialogs and alerts

- Alerts: `ui_alert`. Kind AL_INFO 0 (an "i"), AL_WARN 1 (a triangle), AL_QUESTION 2 (a "?",
  for confirmations), AL_ERROR 3 (a red "!"); each plays its chime (Horizon 0.15).
  Right-click menus: `ui_popup` (and the menu key, `ui_menukey` / `ui_popat`). A short title (the program's
  name), 1-3 lines, the buttons as verbs ("Save", "Discard", "Cancel"; "OK" for a note).
- Files: always `ui_filedlg` (it remembers the folder: it changes the task's current
  directory). Suggest a name when saving (`NAME.TXT`, the document's name).
- Asking one value: `ui_ask`. Several: `ui_dlgopen` / `ui_dlgrun` with your controls.
- A dialog is modal (WF_MODAL): the program's other windows do not react while it is open.

## Text

Plain, short, sentence case: "Save the changes to NOTES.TXT?", "Cannot open the file.",
"Not enough memory to start it. Close a program and try again." Name things as the user
sees them (files, folders, programs, the card), not as the system does.
