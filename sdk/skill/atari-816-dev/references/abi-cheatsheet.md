# Horizon ABI cheat sheet (0.18)

Full text: `SDK/docs/reference/*.md`, `HORIZON/ABI.md`, `HORIZON/user/horizon.inc`,
`HORIZON/user/ui.inc`.

## Calling

`sys SYS_NAME` = `COP #n`. A, X, Y in (16-bit). Out: carry clear OK / set error (A = code);
result in A (X, Y if listed). X, Y, D, DBR, other flags preserved (**Z/N not from A**).
Pointer = X offset, Y bank (`ptr label`); bank 0 = your private window ($0000-$7FFF).
u24 in a block = 3 bytes lo, hi, bank (`.faraddr label`). Ranges may not cross a bank.
Errors: 1 EINVAL, 2 ENOMEM, 4 EFAULT, 5 ECHILD, 6 EAGAIN, 7 ENOSYS, 8 ERUNNING, 9 ENODEV (0.17:
no Lau; 0.18: sprites / fs_scroll before REV $0B, fs_raster / win_vbl before $09),
$40+n file (44 no file, 45 no path, 46 bad name, 47 denied, 48 exists, 52 too many open).

## Program

Start: A16/I16, PC = code bank:$0100 (first CODE byte), DBR = PBR = code bank, D = 0,
A = argument length, X = argument address (bank 0). End: `exit n` (flushes ulib output).
Segments CODE, RODATA, DATA, BSS (code bank, BSS cleared) + ZEROPAGE (direct page,
cleared, 256 bytes minus ulib's 38 and ui.lib's 38). File < 64 KB.
Build: `ca65 -I HORIZON/user -o x.o x.s`; `ld65 -C HORIZON/user/prog.cfg -o X.PRG x.o
HORIZON/build/ulib.o [HORIZON/build/ui.lib]`.

## Macros and ulib

`print "text"` (buffered, clobbers A X Y), `ptr label`, `exit n`, `jeq/jne/jcc/jcs label`.
`out_char` A, `out_str` X,Y (X offset, Y bank, as for syscalls), `put_nl`, `put_dec` A, `put_decw` A,X=width, `put_hex8`,
`put_hex16`, `out_flush`, `key_ascii` (A usage, X mods|down<<8 -> A ASCII; ctrl+letter =
1-26; arrows $80 R $81 L $82 D $83 U, $84 Home $85 PgUp $86 Del $87 End $88 PgDn),
`read_char`, `getline` (X,Y buf, A size -> A len, C = ctrl-C), `args_init` (X), `next_arg`
(X,Y buf, A size -> A len, zero-terminated; C none), `parse_dec` (-> A, C none), `spawn`,
`exit_a` (A). ulib prints numbers only to the console: for a number in a window, convert
it yourself (`dec5` / `digit` in `SDK/templates/game/main.s`: A -> ASCII digits).

## Syscalls

| # | Constant | In | Out |
| --- | --- | --- | --- |
| $00 | SYS_EXIT | A code | - |
| $01 | SYS_YIELD | | |
| $02 | SYS_SLEEP | A ms | |
| $03 | SYS_GETPID | | A id |
| $04 | SYS_UPTIME | | A ms lo, X ms hi |
| $05 | SYS_PUTC | A char | |
| $06 | SYS_PUTS | X,Y string | |
| $07 | SYS_CSIZE | | A cols, X rows |
| $08 | SYS_CHDIR | X,Y path | |
| $09 | SYS_GETCWD | X,Y buf, A size | A len |
| $0A | SYS_RESTART | A 0/1 | (no return) |
| $0B | SYS_SYNC | A bit0 end others | |
| $0C | SYS_SYSREQ | A 1 shutdown 2 restart 3 full | |
| $0D | SYS_TGET | | A, X seconds since 2000, Y CLK_* |
| $0E | SYS_TSET | A, X seconds, Y CLK_SAVED / CLK_SET | |
| $0F | SYS_VSYNC | (blocks to the next vertical blank, 60 Hz; 0.18: also until your draw list is done) | A frame counter (REV $09: a jump > 1 = missed frames) |
| $10 | SYS_BALLOC | | A bank |
| $11 | SYS_BFREE | A bank | |
| $12 | SYS_MINFO | | A free, X total banks |
| $20 | SYS_OPEN | X,Y path, A mode 0 r 1 rw 2 create 3 append | A handle 0-3 |
| $21 | SYS_CLOSE | A handle | |
| $22 | SYS_READ | X,Y {u8 h, u24 buf, u16 len} | A bytes (< len: EOF) |
| $23 | SYS_WRITE | same | A bytes |
| $24 | SYS_SEEK | A h, X off lo, Y off hi | A, X position |
| $25 | SYS_STAT | X,Y {u24 path, u24 out9} | A,X size; out: u32 size, u8 attr ($10 dir), u32 time |
| $26 | SYS_READDIR | X,Y {u24 path, u24 buf, u16 len, u16 skip} | A entries {u32 size, u8 attr, u8 nlen, name} |
| $27 | SYS_DELETE | X,Y path | |
| $28 | SYS_MKDIR | X,Y path | |
| $29 | SYS_RENAME | X,Y {u24 old, u24 new} | |
| $30 | SYS_SPAWN | X,Y {u24 path, u24 args/0, u8 prio (1; $80 detach)} | A id |
| $31 | SYS_WAIT | A id | A exit code |
| $32 | SYS_KILL | A id | |
| $33 | SYS_TINFO | A slot, X,Y 16 bytes | |
| $34 | SYS_SINGLE | | C set: already running (exit) |
| $40-$43 | SYS_PCREATE / SEND / RECV / PCLOSE | ports, 16-byte messages | |
| $50 | SYS_ICLAIM | | |
| $51 | SYS_IREAD | (blocks) | A usage, X mods\|down<<8 |
| $52 | SYS_IRELEASE | | |
| $53 | SYS_ILEND | A id, X 1 = ctrl-C kills | |
| $54 | SYS_IPOLL | | as IREAD; C+EAGAIN if none |
| $55 | SYS_JOY | A 0 (0.15) | A dirs (port 1 bits 0-3: 1 up 2 down 4 left 8 right; port 2 4-7), X triggers |
| $60-$64 | SYS_CLASSIC / CMOUNT / CEJECT / CBOOT / CQUERY | the classic Atari | |
| $65 | SYS_BEEP | A pitch, X ticks (0 = silence channel 1), Y vol | |
| $66 | SYS_SNDW | A reg $00-$13 (POKEY 2, DACs), X value (0.15: silenced at exit) | |
| $67 | SYS_CHIME | A CH_INFO/WARN/QUESTION/ERROR, X vol ($FFFF setting) (0.15) | |
| $68 | SYS_SPLAY | X,Y 16-byte block (SPB_*): a sample on Lau (0.17) | A voice; ENODEV: no Lau |
| $69 | SYS_SSTOP | A voice, $FFFF all of the caller's (0.17) | |
| $6A | SYS_SSTAT | - (0.17) | A own voices playing, X all |
| $6B | SYS_SSET | A voice, X pitch, Y vol L \| R << 8 (0.17) | |
| $70 | SYS_WSSTART | | A 1 started (stop it at the end) / 0 running |
| $71 | SYS_WSSTOP | | |
| $72 | SYS_WOPEN | X,Y {i16 x, y, u16 w, h, u24 title, u8 flags} | A window |
| $73 | SYS_WCLOSE | A win | |
| $74 | SYS_WDRAW | A win, X,Y block (below) | |
| $75 | SYS_WEVENT | A 0 wait/1 poll, X,Y 8 bytes | event |
| $76 | SYS_WTWIDTH | A font, X,Y string | A pixels |
| $77 | SYS_WSSYNC | | |
| $78 | SYS_WMOVE | A win, X x, Y y | |
| $7C | SYS_WTIMER | A win, X period (10 ms ticks, 0 off; ticks already queued may still come: unverified) | WE_TICK |
| $7D | SYS_WMENU | A win, X,Y menus | |
| $7E | SYS_WSTATUS | X,Y string | |
| $7F | SYS_WTERM | A WF_TERM win | |
| $80 | SYS_CLPUT | X,Y {u24 data, u16 len} | |
| $81 | SYS_CLGET | X,Y {u24 buf, u16 size} | A length |
| $82 | SYS_WINFO | A win, X,Y 8 bytes | {x, y (screen), w, h of content} |
| $83 | SYS_WINAT | X x, Y y | A win / $FF |
| $84 | SYS_WDROP | A win, X,Y string | |
| $85 | SYS_WDROPGET | A win, X,Y 128 bytes | |
| $86 | SYS_WSPAL | A index, X r\|g<<8, Y b | 0-15 global; 16-255 (0.18) become yours, shown while you have the focus (EAGAIN: another's) |
| $88 | SYS_WTITLE | A win, X,Y string | |
| $89 | SYS_WPTR | A shape 0 arrow 1 drag 2 cross 3 hsize 4 vsize | |
| $8A | SYS_WMOUSE | A win/$FF, X,Y 10 bytes | {sx, sy, cx, cy, buttons}; A buttons |
| $8B | SYS_WSHOLD | A 1/0 | |
| $8C | SYS_WMSTATE | A win, X menu\|item<<8, Y MS_CHECK\|MS_DIM | |
| $8E | SYS_WGEOM | A win, X,Y {i16 x ($8000 stays), y, u16 w, h} | |
| $8F | SYS_TNAME | A id (0 me; \| $8000: read into X,Y 16 bytes), X,Y name | |
| $90 | SYS_WPOPUP | A win, X,Y {u24 items, i16 x ($8000 pointer), y, u8 flags (1 keyboard)} (0.15; blocks) | A item / $FFFF |
| $79-$7B, $87, $8D, $5F | ws_redraw, ws_stats, ws_config, setting, ws_closeall, mouse_inject | measurements / system (setting 4 = the sound volume, Lau's master, 0.18) | |
| $91 | SYS_SPRALLOC | A count 1-16, X own window (0.18, REV $0B) | A first sprite (lower = in front) |
| $92 | SYS_SPRFREE | A first, X count; A $FFFF all of yours | |
| $93 | SYS_SPRSET | A count, X,Y entries {u8 sprite, u8 ctrl SPR_*, i16 x, y, u24 image, u8 pal} | all from the next frame |
| $94 | SYS_SPRMOVE | A sprite, X x, Y y | |
| $95 | SYS_SPRSHOW | A sprite, X 1/0 | |
| $96 | SYS_FSENTER | A own win, X,Y {u8 mode FS_*, u8 flags FS_PTR, u16 stride (16n), u16 rows, u24 base (256-aligned), u8 0} | full screen while focused |
| $97 | SYS_FSLEAVE | A win | |
| $98 | SYS_FSSCROLL | X,Y {x, y, x2, y2, vheight, split line, u8 ctrl FSC_HWRAP 1 / FSC_SPLIT 2, u8 0} (REV $0B) | next blank |
| $99 | SYS_FSRASTER | A count 0-16, X,Y {u16 line, u8 entry, r, g, b} (REV $09) | |
| $9A | SYS_PALSET | A first \| count<<8 (0 = 256), X,Y rgb triples | EAGAIN: one is another's |
| $9B | SYS_PALALLOC | A count, X first / $FFFF any; A 0 = give all back | A first entry |
| $9C | SYS_DRAWLIST | A win \| count<<8 (1-128), X,Y 20-byte records LR_* / LS_* | A drawn; returns at once |
| $9D | SYS_LISTWAIT | A 0 wait / 1 ask | A 1 = still running |
| $9E | SYS_FRAME | | A frame counter |
| $9F | SYS_WINVBL | A own win, X 1/0 (REV $09) | WE_VBL each blank |
| $A1 | SYS_SHEETNEW | X,Y {u24 address, u8 0, u16 stride, u16 width 1-4096, u16 height 1-1024} (0.19; own memory, else EFAULT) | A sheet 1-32 (EAGAIN: 32 sheets / 4096 rows in all) |
| $A2 | SYS_SHEETFREE | A sheet / $FFFF all of yours (stops your running list) | |
| $A3 | SYS_SHEETDRAW | A win \| count<<8 (1-128), X,Y 16-byte records SD_* {u8 sheet, u8 op SH_FILL/COPY/KEY (+SH_VBL $80), u8 colour/key, 0, sx, sy, w, h, x, y} | A drawn; returns at once; ~300 cycles a record |

## Games round (0.18): `SDK/docs/reference/games.md`

- Every address for Marga / Ali / Lau (framebuffer, sprite images, list sources, samples)
  must be your memory: window (bank 0 $0000-$7FFF), code bank, your banks (a range may span
  consecutive own banks). Else EFAULT, nothing changes.
- Sprite images: 16-byte aligned (EINVAL), colour 0 transparent, 8 bpp 16x16 = 256 bytes,
  16x32 512; 4 bpp 128-512. Left in place while shown. A window's sprites show only while it
  has the focus, nothing covers its content, and wholly inside it.
- Full screen: framebuffer rows x stride in your memory; Alt+Tab / Alt+Esc / F12 minimize
  it (WE_UNFOCUS: pause; WE_FOCUS: back as it was); Alt+F4 WE_CLOSE; one program at a time
  (EAGAIN). In full screen pal_set owns all 256 entries; sprites in screen coordinates
  (320x180 units in FS_320X8); split line in 360-line units (even in 320x180).
- Draw list record (20 bytes): +0 op (LS_FILL 0, COPY 1, KEY 2 (c2 skipped), EXPAND 3,
  EXPANDK 4, MOVE 5), +1 flags (LS_VBL 1; bits 4-6 first bit), +2 c1, +3 c2, +4 x, +6 y, +8 w,
  +10 h, +12 u24 src (MOVE: sx, sy), +16 stride (0 = w; expand: bytes a row), +18 0.
  **Sources and target in flight until list_wait / vsync / the next draw_list.**

## Windows

The menu bar shows the Desktop's menus (Horizon, Programs) first, then the focused
window's. Flags: WF_RESIZE 1, WF_PLAIN 2, WF_BACK 4, WF_TERM 16, WF_MODAL 32, WF_HOVER 64.
Content = outer (x + 1, y + 16); outer = content + 2 wide, + 17 high (+12 WF_RESIZE).
Screen 640 x 360, menu bar 16 lines: windows at y >= 16; WF_PLAIN max 640 x 344 at (0, 16).
Menus: `"Title",0,"Item",0,"Item",9,"Ctrl+S",0,"-",0,0, "Title2",0,...,0, 0`; item state
byte MS_STATE $10 | MS_CHECK 1 | MS_DIM 2 first. WE_MENU a = menu (0 = yours), b = item
(separators count).

## win_draw block (16 bytes)

`+0 op, +1 c1, +2 c2, +3 font, +4 x, +6 y, +8 w, +10 h, +12 u24 ptr`
Ops: 1 WD_FILL (c1), 2 WD_FRAME, 3 WD_LINE (to w, h), 4 WD_TEXT (ink c1, paper c2 / $FF
none, font 0 UI / 1 fixed 8x12, y = top), 5 WD_BLIT (w*h bytes at ptr), 6 WD_KBLIT (c2 =
transparent), 7 WD_DITHER, 8 WD_SBLIT (stride = c1|c2<<8), 9 WD_COPY (to c1|c2<<8, ptr low).

## Events (8 bytes: u8 type, u8 window, u16 a, b, c)

| type | a | b | c |
| --- | --- | --- | --- |
| 1 WE_KEY | HID usage | mods \| down<<8 | |
| 2 WE_BUTTON | x | y | buttons(bit0 L,1 R,2 M) \| mods<<8 |
| 3 WE_CLOSE | | | |
| 4 WE_WHEEL | steps | | |
| 5 WE_TICK | | | |
| 6 WE_RESIZE | w | h | |
| 7 WE_MENU | menu | item | |
| 8 WE_DROP | x | y | sender id |
| 9 WE_MOTION | x | y | buttons \| mods<<8 |
| 10 WE_LEAVE | | | |
| 14 WE_FOCUS / 15 WE_UNFOCUS | (0.15; a game pauses on UNFOCUS) | | |
| 16 WE_VBL | (0.18, win_vbl) | | |

Read: `lda ev` / `and #$00FF` = type; `lda ev+1` / `and #$00FF` = window; a = `ev+2`,
b = `ev+4` (down flag: `ev+5` byte or `and #$0100`), c = `ev+6`.
HID: A-Z $04-$1D, 1-9 0 $1E-$27, Enter $28, Esc $29, Bksp $2A, Tab $2B, Space $2C,
F1-F12 $3A-$45, Ins $49, Home $4A, PgUp $4B, Del $4C, End $4D, PgDn $4E, Right $4F,
Left $50, Down $51, Up $52. Mods: bit 0 lctrl, 1 lshift, 2 lalt, 3 lgui, 4-7 right ones
(ctrl = `and #$11`, shift = `and #$22`). Programs never get F10, Alt alone, Alt+menu
letter, Alt+Tab, Alt+F4, ctrl+W (= WE_CLOSE), F12.

## Colours

0 C_BLACK, 1 C_WHITE, 2 C_DESK (teal 36 92 112), 3 C_DESK2, 4 C_TITLE (dark blue 28 60 132),
5 C_TITLE_OFF (grey), 6 C_BODY (light beige-grey 228 226 216, window backgrounds), 7 C_DARK
(76 80 90), 8 C_MID, 9 C_LIGHT, 10 C_SELECT (blue 52 100 204), 11 C_RED, 12 C_YELLOW,
13 C_GREEN, 14 C_ORANGE, 15 C_SHADOW (near black); the full table with RGB:
`SDK/docs/reference/drawing.md`; 16 + 36 r + 6 g + b (r, g, b 0-5) cube;
232-255 greys (8 ... 238).

## ui.lib (window apps, `UI := 1`)

`ui_init` after WSSTART. Loop: `lda #0` / `jsr ui_getev` (-> ui_ev) / `ldx #.loword(list)`
/ `jsr ui_event` -> A = UA_NONE 0 (yours: look at ui_ev) / UA_USED 1 / UA_CLICK 2 /
UA_CHANGE 3 / UA_OPEN 4, X = control. Controls in DATA: header `.byte UT_x, 0` +
`.word x, y, w, h, flags` + fields; set CT_WIN (byte at +1) to the window first.
Button `.word ..., label`; label `.word ..., text`; field `.word ..., buf, size, 0,0,0,0`.
`ui_drawall` X=list, `ui_draw` X=ctl, `ui_fdset` X=field Y=string, `ui_alert` X=block
`{kind, title, text, b1, b2, b3}` -> A button, `ui_filedlg` A 0 open/1 save X=128-byte
buffer Y=title -> C cancelled, `ui_ask`, `ui_text` (X string, A ink|paper<<8, at ui_x,
ui_y in ui_win, font ui_font), `ui_rect`, `ui_strcpy` X->Y, `ui_beep`. All pointers are
16-bit addresses in the code bank.
