; horizon.inc - Horizon user ABI: syscall numbers, error codes and macros.
; Programs run in native mode with A/X/Y 16-bit; keep REP #$30 around every syscall.
; A syscall is COP #n. Arguments in A, X, Y; result in A (and X where noted);
; carry clear = OK, carry set = error code in A. Pointers: X = offset, Y = bank.
; See ABI.md.

        .p816
        .smart  -
        .feature string_escapes
        .include "version.inc"

SYS_EXIT      = $00   ; A = exit code
SYS_YIELD     = $01
SYS_SLEEP     = $02   ; A = milliseconds
SYS_GETPID    = $03   ; -> A = task id
SYS_UPTIME    = $04   ; -> A = ms low, X = ms high
SYS_PUTC      = $05   ; A = character
SYS_PUTS      = $06   ; X, Y = zero-terminated string
SYS_CSIZE     = $07   ; -> A = console columns, X = rows
SYS_CHDIR     = $08   ; X, Y = path: the current directory
SYS_GETCWD    = $09   ; X, Y = buffer, A = its size -> A = length
SYS_RESTART   = $0A   ; A = 0 Horizon only, 1 full restart (/atari.ini, the classic core, Horizon); never returns when it works
SYS_SYNC      = $0B   ; A = bit 0: end every other program first (except INIT); every file closed, the card flushed (I/O op $1C)
SYS_SYSREQ    = $0C   ; A = SR_SHUTDOWN / SR_RESTART / SR_FULLRESTART: asks the Desktop (its backdrop gets WE_SYSREQ); EINVAL: no Desktop
SR_SHUTDOWN   = 1
SR_RESTART    = 2
SR_FULLRESTART = 3
SYS_TGET      = $0D   ; (0.14) -> A = seconds low, X = high (since 2000-01-01 00:00), Y = CLK_* (how the clock was set)
SYS_TSET      = $0E   ; (0.14) A = seconds low, X = high, Y = CLK_SAVED / CLK_SET: the clock counts from there
CLK_NONE      = 0     ; time_get Y: never set (it counts from 0 = 2000-01-01 at start)
CLK_SAVED     = 1     ;   provisional: the last value saved (/SYSTEM/CLOCK), not confirmed
CLK_SET       = 2     ;   set (confirmed) in this session
SYS_VSYNC     = $0F   ; (0.15) blocks until the next vertical blank (60 Hz) -> A = (0.18) the frame counter (SYS_FRAME); before REV $09
                      ;   the vertical blanks waited for (any task, wraps). (0.18) It also waits for the caller's draw list
SYS_BALLOC    = $10   ; -> A = bank
SYS_BFREE     = $11   ; A = bank
SYS_MINFO     = $12   ; -> A = free banks, X = total banks
SYS_OPEN      = $20   ; X, Y = path, A = mode -> A = handle
SYS_CLOSE     = $21   ; A = handle
SYS_READ      = $22   ; X, Y = {u8 handle, u24 buffer, u16 length} -> A = bytes
SYS_WRITE     = $23   ; same block -> A = bytes
SYS_SEEK      = $24   ; A = handle, X = offset low, Y = offset high -> A, X = position
SYS_STAT      = $25   ; X, Y = {u24 path, u24 out} -> out = 9-byte record, A, X = size
SYS_READDIR   = $26   ; X, Y = {u24 path, u24 buffer, u16 length, u16 skip} -> A = entries
SYS_DELETE    = $27   ; X, Y = path
SYS_MKDIR     = $28   ; X, Y = path
SYS_RENAME    = $29   ; X, Y = {u24 old path, u24 new path}: rename or move
SYS_SPAWN     = $30   ; X, Y = {u24 path, u24 args (0 = none), u8 priority} -> A = task id
SYS_WAIT      = $31   ; A = task id -> A = exit code
SYS_KILL      = $32   ; A = task id
SYS_TINFO     = $33   ; A = slot 0-15, X, Y = 16-byte record (byte 13: TI_* flags, byte 14: windows)
SYS_SINGLE    = $34   ; one instance of this program only: C set, A = ERUNNING, X = its id when one runs
                      ;   already (its windows were raised: exit); else later spawns of it raise this one
TI_WINDOWS = 1        ; task_info byte 13: it has windows
TI_MODAL   = 2        ;   a WF_MODAL window (a dialog, an alert) is open
TI_IDLE    = 4        ;   waiting in win_event with nothing queued
TI_SINGLE  = 8        ;   single instance (SYS_SINGLE)
SYS_PCREATE   = $40   ; -> A = port
SYS_SEND      = $41   ; A = port, X, Y = 16-byte message
SYS_RECV      = $42   ; A = port, X, Y = 16-byte buffer (blocks)
SYS_PCLOSE    = $43   ; A = port
SYS_ICLAIM    = $50
SYS_JOY       = $55   ; (0.15) A = 0 -> A = directions (JOY_*: bits 0-3 port 1, 4-7 port 2), X = triggers (bit 0 port 1, 1 port 2); 1 = pressed
                      ;   A = 1 (test aid): X = directions, Y = triggers ORed into the ports' state from now on (0, 0: off)
JOY_UP    = 1         ; joystick directions (port 2: << 4)
JOY_DOWN  = 2
JOY_LEFT  = 4
JOY_RIGHT = 8
SYS_MINJECT   = $5F   ; test aid: A = dx | dy << 8, X = wheel | buttons << 8 (signed bytes): one MOUSE event through the kernel's path
SYS_IREAD     = $51   ; -> A = HID usage, X = modifiers | down << 8 (blocks)
SYS_IRELEASE  = $52
SYS_CLASSIC   = $60   ; keyboard holder only: show the classic machine until F12
SYS_CMOUNT    = $61   ; X, Y = path, A = kind | slot << 8 -> A = kind mounted
SYS_CEJECT    = $62   ; A = kind | slot << 8
SYS_CBOOT     = $63   ; keyboard holder only: cold boot and show the classic machine; (0.18) A = CB_STAY: cold boot, not shown
CB_STAY   = $C01D     ; (0.18) classic_boot: cold boot (a power cycle) and stay on the desktop
SYS_CQUERY    = $64   ; A = 0-3 D1:-D4:, 4 executable, 5 cartridge, X, Y = 128-byte buffer -> A = length
SYS_BEEP      = $65   ; A = pitch (POKEY AUDF), X = duration in 10 ms ticks (0 = silence), Y = volume 0-15
SYS_SNDW      = $66   ; A = register 0-$13 ($DB00 + A: POKEY 2, DACs), X = value (0.15: silenced when the program ends)
SYS_CHIME     = $67   ; (0.15) A = CH_* kind, X = volume 0-15 ($FFFF: the beep volume setting): the chime of the user interface
CH_INFO     = 0       ; chime kinds: information (A5, E5)
CH_WARN     = 1       ;   warning (A5, A5)
CH_QUESTION = 2       ;   question (E5, A5)
CH_ERROR    = 3       ;   error (E5, C5)
; (0.17) Lau, the sample player (REV $0A; ENODEV before: fall back to POKEY 2). The sample must lie in
; the caller's own memory (window, code bank, its banks); its voices stop when it ends or frees that bank
SYS_SPLAY     = $68   ; X, Y = 16-byte block (SPB_* below) -> A = the voice 0-7 (EAGAIN: none free)
SYS_SSTOP     = $69   ; A = voice, $FFFF: every voice of the caller
SYS_SSTAT     = $6A   ; -> A = the caller's voices still playing (bit n = voice n), X = all voices playing
SYS_SSET      = $6B   ; A = voice (the caller's), X = pitch, Y = left volume | right volume << 8: changed while it plays
SPB_ADDR  = 0         ; u24 the first sample (16-bit samples: an even address)
SPB_LEN   = 3         ; u24 the length in samples (1 ..)
SPB_LOOP  = 6         ; u24 loop start in samples (SPF_LOOP: length - loop >= 4)
SPB_PITCH = 9         ; u16 step per 48 kHz output sample, 2.14: $4000 = 48 kHz, $2000 = 24 kHz, $1000 = 12 kHz
SPB_VOLL  = 11        ; u8 left volume 0-255
SPB_VOLR  = 12        ; u8 right volume 0-255
SPB_FLAGS = 13        ; u8 SPF_* below
SPB_VOICE = 14        ; u8 the voice 0-7, SP_ANY ($FF): the first one not playing (else the caller's oldest)
SPB_SIZE  = 16        ; (byte 15: 0)
SPF_LOOP  = 1
SPF_16    = 2         ; signed 16-bit little-endian samples (else signed 8-bit)
SP_ANY    = $FF
CK_AUTO = 0
CK_DISK = 1
CK_XEX  = 2
CK_CART = 3
SYS_ILEND     = $53   ; A = task id, X = 1: ctrl-C kills it; lend the keyboard (back at its exit)
SYS_IPOLL     = $54   ; as SYS_IREAD, but C set and A = EAGAIN at once when nothing is queued

; window system (ws.s)
SYS_WSSTART   = $70   ; the desktop on the screen -> A = 1 started now, 0 already running
SYS_WSSTOP    = $71   ; its starter only
SYS_WOPEN     = $72   ; X, Y = {i16 x, i16 y, u16 width, u16 height, u24 title, u8 flags} -> A = window
SYS_WCLOSE    = $73   ; A = window
SYS_WDRAW     = $74   ; A = window, X, Y = {u8 op, u8 c1, u8 c2, u8 font, i16 x, y, w, h, u24 ptr}
SYS_WEVENT    = $75   ; A = 0 wait / 1 poll, X, Y = 8-byte {u8 type, u8 window, u16 a, b, c}
SYS_WTWIDTH   = $76   ; X, Y = string, A = font -> A = width in pixels
SYS_WSSYNC    = $77   ; wait until the screen shows everything drawn
SYS_WMOVE     = $78   ; A = window, X = x, Y = y
SYS_WSREDRAW  = $79   ; repaint the whole screen
SYS_WSSTATS   = $7A   ; -> A, X = microseconds of the last repaint
SYS_WSCONFIG  = $7B   ; A = bit 0 blitter off, bit 1 the compositor sleeps on its interrupt, bit 2 no direct drawing -> A = 1 blitter in use, X = (0.16) SYS_REV
SYS_WTIMER    = $7C   ; A = window, X = period in 10 ms ticks (0 = off): WE_TICK events
SYS_WMENU     = $7D   ; A = window, X, Y = menus: "title", "item", ..., "", "title", ..., "", "" (0.14: up to 2045 bytes kept;
                      ;   the bar shows 12 titles at most; a drop-down as many items as fit below the bar, 24)
SYS_WSTATUS   = $7E   ; X, Y = string: the text at the right of the menu bar (31 characters)
SYS_WTERM     = $7F   ; A = terminal window: the caller (and tasks it starts) print and read there; $FF = detach
SYS_CLPUT     = $80   ; X, Y = {u24 data, u16 length}: the clipboard (64 KB at most; 0 empties it)
SYS_CLGET     = $81   ; X, Y = {u24 buffer, u16 size} -> A = clipboard length; copies min(length, size)
SYS_WINFO     = $82   ; A = window (any), X, Y = 8 bytes {i16 content x, y on screen, u16 content w, h}
SYS_WINAT     = $83   ; X = screen x, Y = screen y -> A = window there (a backdrop too), $FF = none
SYS_WDROP     = $84   ; A = window (any), X, Y = string (127): it gets WE_DROP (a, b = pointer in its content, c = sender id)
SYS_WDROPGET  = $85   ; A = own window, X, Y = 128-byte buffer: the last string dropped on it
SYS_WSPAL     = $86   ; A = palette index, X = red | green << 8, Y = blue (desktop: 2 and 3)
SYS_SETTING   = $87   ; A = id, X = value ($FFFF: read only) -> A = old: 0 mouse speed 1-4, 1 beep (alert) volume 0-15,
                      ;   2 key repeat delay (10 ms ticks, 0 off), 3 key repeat interval (ticks), (0.18) 4 the sound volume 0-15
                      ;   (Lau's master volume, x 17; default 8; before 0.18 it followed 1)
SYS_WTITLE    = $88   ; A = own window, X, Y = string: its new title (31 characters)
SYS_WPTR      = $89   ; A = pointer shape (PTR_*): 0 arrow, 1 drag (carrying a document), 2 crosshair, 3 column resize, 4 row resize (hot spot centre)
SYS_WMOUSE    = $8A   ; A = window ($FF none), X, Y = 10 bytes {i16 x, y screen, i16 x, y content, u16 buttons} -> A = buttons, X = window under it
SYS_WSHOLD    = $8B   ; A = 1: the screen keeps what it shows while one change is drawn in several calls (at most 5 ticks); 0: release (repaints at once)
SYS_WMSTATE   = $8C   ; A = window, X = menu | item << 8, Y = MS_CHECK | MS_DIM: the item's state (it must start with a state byte)
SYS_WSCLOSEALL = $8D  ; every window of every other program gets WE_CLOSE (shut down)
SYS_WGEOM     = $8E   ; (0.14) A = own window, X, Y = {i16 x, i16 y, u16 width, u16 height}: moved and resized (content size; x = $8000: stays); no WE_RESIZE
SYS_TNAME     = $8F   ; (0.14) A = task id (0 = the caller), X, Y = string: the name the menu bar shows for its windows (15 characters)
                      ;   (0.15) A = id | $8000: read it instead into the 16-byte buffer X, Y (as the bar shows it: the file name if none)
SYS_WPOPUP    = $90   ; (0.15) A = own window, X, Y = {u24 items, i16 x, i16 y, u8 flags}: a pop-up menu at x, y of the content
                      ;   (x = $8000: at the pointer); items as a menu's ("item", ..., ""; 24 at most); blocks -> A = the item
                      ;   chosen (counting separators), $FFFF = none. Flags: POP_KEY the first item highlighted (from the keyboard)
;
; (0.18) the games round (kernel/k2*.s; ABI.md "Sprites", "Full-screen mode", "Palette entries", "Draw lists")
SYS_SPRALLOC  = $91   ; A = count 1-16, X = own window -> A = the first of count sprites in a row (REV $0B; ENODEV before)
SYS_SPRFREE   = $92   ; A = first sprite, X = count; A = $FFFF: every sprite of the caller
SYS_SPRSET    = $93   ; A = count 1-16, X, Y = count entries {u8 sprite, u8 ctrl (SPR_*), i16 x, i16 y, u24 image, u8 pal}: all
                      ;   from the next frame on; the image (16-byte aligned) must be the caller's memory (EFAULT)
SYS_SPRMOVE   = $94   ; A = sprite, X = x, Y = y (the window's content, or the full screen): the cheap call
SYS_SPRSHOW   = $95   ; A = sprite, X = 1 show / 0 hide
SYS_FSENTER   = $96   ; A = own window, X, Y = {u8 mode (FS_*), u8 flags, u16 stride, u16 rows, u24 base, u8 0}: full screen
SYS_FSLEAVE   = $97   ; A = own window: back to the desktop
SYS_FSSCROLL  = $98   ; X, Y = {u16 x, u16 y, u16 x2, u16 y2, u16 vheight, u16 split line, u8 ctrl (FSC_*), u8 0} (REV $0B)
SYS_FSRASTER  = $99   ; A = count 0-16, X, Y = entries {u16 line, u8 index, u8 red, green, blue}: colours from a line on (REV $09)
SYS_PALSET    = $9A   ; A = first | count << 8 (count 0 = 256), X, Y = count * 3 bytes red, green, blue
SYS_PALALLOC  = $9B   ; A = count 1-240, X = the first entry wanted ($FFFF: any) -> A = the first; A = 0: give all back
SYS_DRAWLIST  = $9C   ; A = window | count << 8 (1-128), X, Y = count 20-byte records (LS_*) -> A = records drawn
SYS_LISTWAIT  = $9D   ; A = 0: wait until the caller's list is done (and seen by the CPU); 1: ask -> A = 1 while it runs
SYS_FRAME     = $9E   ; -> A = the frame counter (NV_FRAME: + 1 at every vertical blank; REV $09)
SYS_WINVBL    = $9F   ; A = own window, X = 1 on / 0 off: WE_VBL at each vertical blank while its queue is empty (REV $09)
SYS_WFRONT    = $A0   ; (BASIC 2.0) A = own window: back if minimized, raised, the focus (full screen: shown again)
SPR_EN    = $01       ; sprite ctrl (Marga's record CTRL): shown
SPR_HFLIP = $02
SPR_VFLIP = $04
SPR_MAG   = $08       ;   2x in both directions
SPR_WIDE  = $10       ;   32 pixels wide (4 bpp only)
SPR_TALL  = $20       ;   32 lines
SPR_BPP4  = $40       ;   4 bpp (pal: the palette bank, entries pal * 16 + 1 .. 15), else 8 bpp
SPR_BEHIND = $80      ;   hidden by bitmap pixels that are not colour 0
SE_SPRITE = 0         ; spr_set entry offsets (10 bytes)
SE_CTRL   = 1
SE_X      = 2
SE_Y      = 4
SE_IMAGE  = 6
SE_PAL    = 9
FS_640X8  = 0         ; fs_enter modes: 640x360 8 bpp, 640x360 4 bpp, 320x180 8 bpp
FS_640X4  = 1
FS_320X8  = 2
FS_PTR    = 1         ; fs_enter flags: the mouse pointer is shown (not in 320x180)
FSC_HWRAP = 1         ; fs_scroll ctrl: a row is a ring of stride bytes
FSC_SPLIT = 2         ;   the second set from the split line on
LS_FILL   = 0         ; draw_list ops
LS_COPY   = 1
LS_KEY    = 2         ;   c2 = the key colour
LS_EXPAND = 3         ;   1 bpp: set bits c1, clear bits c2
LS_EXPANDK = 4        ;   1 bpp: set bits c1, clear bits left
LS_MOVE   = 5         ;   inside the target: from (sx, sy)
LS_VBL    = 1         ; draw_list record flags: wait for the vertical blank first (bits 4-6: expand's first bit)
LR_OP     = 0         ; draw_list record offsets (20 bytes)
LR_FLAGS  = 1
LR_C1     = 2
LR_C2     = 3
LR_X      = 4
LR_Y      = 6
LR_W      = 8
LR_H      = 10
LR_SRC    = 12        ;   u24 (copy, keyed copy, expand); move: i16 sx at 12, i16 sy at 14
LR_STRIDE = 16        ;   u16 (0: the width; expand: the bytes a row needs)
WE_VBL    = 16        ; (0.18) the vertical blank (SYS_WINVBL)
POP_HERE = $8000      ; win_popup x: at the pointer
POP_KEY  = 1          ; win_popup flags
; menus (win_menu): an item may start with a state byte MS_STATE | bits (MS_CHECK: a check mark,
; MS_DIM: greyed, cannot be chosen) and may hold a TAB: the text after it (a shortcut, "Ctrl+S")
; is shown at the right
MS_STATE = $10
MS_CHECK = 1
MS_DIM   = 2
; ws_pointer shapes
PTR_ARROW = 0
PTR_DRAG  = 1
PTR_CROSS = 2
PTR_HSIZE = 3         ; resizing sideways (a column)
PTR_VSIZE = 4         ; resizing up and down (a row)
WF_RESIZE = 1         ; win_open flags: a size grip (WE_RESIZE)
WF_PLAIN  = 2         ;   no frame and title: the content is the whole window
WF_BACK   = 4         ;   backdrop: stays at the bottom, gets F12 and the system menu
WF_TERM   = 16        ;   a terminal of 8x12 cells (see SYS_WTERM)
WF_MODAL  = 32        ;   a dialog: while open, clicks on its owner's other windows go to it (with a beep)
WF_HOVER  = 64        ;   WE_MOTION also without a button (pointer over it), WE_LEAVE when it leaves
SP_DETACH = $80       ; spawn priority flag: no parent (nobody waits; freed at its exit)
WD_FILL  = 1          ; win_draw ops
WD_FRAME = 2
WD_LINE  = 3          ; to (w, h)
WD_TEXT  = 4          ; c1 ink, c2 paper ($FF none), font 0 UI / 1 fixed 8x12
WD_BLIT  = 5          ; an 8 bpp image w x h
WD_KBLIT = 6          ; the same, pixels of colour c2 skipped
WD_DITHER = 7         ; a checker of c1 and c2 (c2 where x + y is odd)
WD_SBLIT = 8          ; an 8 bpp image w x h at ptr with source stride c1 | c2 << 8 (a part of a larger image)
WD_COPY  = 9          ; the rectangle x, y, w, h moves to (c1 | c2 << 8, low word of ptr) in the same window (overlap-safe)
; (0.14) ops 10 and 11 take a 17-byte block: {u8 op, c1, c2, font, i16 x, y, w, h, u24 ptr, u16 stride}
WD_EXPAND = 10        ; a 1 bpp image w x h at ptr (bit 7 leftmost): set bits in c1, clear bits in c2 ($FF: left as they are);
                      ;   font = the first pixel's bit in the first byte (0 = bit 7), stride = bytes per row (0: (font + w + 7) / 8)
WD_KSBLIT = 11        ; an 8 bpp image w x h at ptr, pixels of colour c2 skipped, rows stride bytes apart (0: w)
WE_KEY    = 1         ; events: a = usage, b = modifiers | down << 8
WE_BUTTON = 2         ;         a = x, b = y (content), c = buttons
WE_CLOSE  = 3
WE_WHEEL  = 4         ;         a = steps (signed), to the window under the pointer
WE_TICK   = 5         ;         its timer
WE_RESIZE = 6         ;         a = content width, b = height (after a resize)
WE_MENU   = 7         ;         a = menu, b = item (counting separators)
WE_DROP   = 8         ;         a, b = pointer in the content, c = sender task id | modifiers << 8 (0.14); SYS_WDROPGET reads it
WE_MOTION = 9         ;         while a button is held after a press in the window (or WF_HOVER: over it): a, b = pointer (content), c = buttons; coalesced
WE_LEAVE  = 10        ;         (WF_HOVER) the pointer left the window
WE_SYSREQ = 11        ;         (the backdrop) a = SR_* asked with SYS_SYSREQ, c = the asking task's id
WE_STATUS = 12        ;         (0.14, the backdrop) the status text at the right of the menu bar was clicked
WE_MENUOPEN = 13      ;         (0.14, the backdrop) one of its menus is opening: a = the menu (it may call SYS_WMENU now: the menu opens again)
WE_FOCUS  = 14        ;         (0.15) the window got the keyboard focus
WE_UNFOCUS = 15       ;         (0.15) it lost it; the keys it held got their releases (WE_KEY up) just before
; WE_BUTTON and WE_MOTION: c = buttons | modifiers << 8 (the HID modifier bits, as in key events)
; the system palette: 0-15 UI colours, 16-231 colour cube 16 + 36 r + 6 g + b, 232-255 greys
C_BLACK = 0
C_WHITE = 1
C_DESK = 2
C_DESK2 = 3
C_TITLE = 4
C_TITLE_OFF = 5
C_BODY = 6
C_DARK = 7
C_MID = 8
C_LIGHT = 9
C_SELECT = 10
C_RED = 11
C_YELLOW = 12
C_GREEN = 13
C_ORANGE = 14
C_SHADOW = 15

; key_ascii codes for the arrow keys
KEY_RIGHT = $80
KEY_LEFT  = $81
KEY_DOWN  = $82
KEY_UP    = $83
KEY_HOME  = $84
KEY_PGUP  = $85
KEY_DEL   = $86
KEY_END   = $87
KEY_PGDN  = $88

; open modes
O_READ   = 0
O_RDWR   = 1
O_CREATE = 2
O_APPEND = 3

; error codes
EINVAL  = 1
ENOMEM  = 2
ENOENT  = 3
EFAULT  = 4
ECHILD  = 5
EAGAIN  = 6
ENOSYS  = 7
ERUNNING = 8            ; spawn / SYS_SINGLE: a single-instance program runs already (its windows were raised)
ENODEV  = 9            ; (0.17) the hardware is not there (SYS_SPLAY ... on REV < $0A: no Lau; 0.18: sprites before $0B, ...)
EIO    = $40           ; + I/O processor result (FatFs FRESULT: $44 = no file, $45 = no path)

; ---- macros (a16 i16) ----
.macro  sys     n
        cop     n
.endmacro

; print a string literal through the line buffer (A, X, Y clobbered). The string sits
; inline, skipped by a BRA (no label, so @cheap labels around it keep working); at most
; 120 characters.
.macro  print   str
        ldx     #.loword(* + 11)
        ldy     #^(* + 8)
        jsr     out_str
        bra     * + 3 + .strlen(str)
        .byte   str, 0
.endmacro

; X, Y = address of a label in this program
.macro  ptr     lbl
        ldx     #.loword(lbl)
        ldy     #^lbl
.endmacro

.macro  exit    code
        jsr     out_flush
        lda     #code
        cop     SYS_EXIT
.endmacro

; user library (ulib.s), see there. All clobber A, X, Y.
.global out_char, out_str, out_flush, put_char, put_str, put_nl
.global put_hex8, put_hex16, put_dec, put_decw, div10
.global key_ascii, read_char, getline, str_skip, parse_dec
.global spawn, exit_a, args_init, next_arg, atari_kind, atari_run
.globalzp u_p                   ; long pointer used by str_skip / parse_dec
.globalzp u_arg                 ; spawn's argument string (u24, 0 = none)

; long conditional branches (no label: @cheap labels survive)
.macro  jeq     dst
        bne     *+5
        jmp     dst
.endmacro
.macro  jne     dst
        beq     *+5
        jmp     dst
.endmacro
.macro  jcc     dst
        bcs     *+5
        jmp     dst
.endmacro
.macro  jcs     dst
        bcc     *+5
        jmp     dst
.endmacro
