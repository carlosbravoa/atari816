# Syscalls: frame sync, palette entries, sprites, full screen, draw lists

Horizon 0.18, "the games round": the calls a game needs to use Marga (the video chip) and
Ali (the blitter) the way they were built for. A complete program that uses all of them:
`sdk/examples/deepdive` (a full-screen scrolling game). Patterns: [game-patterns.md](game-patterns.md).
The source of truth is `horizon/ABI.md` (its syscall table and "The games round (0.18)").

Examples assume `win`, `t0`, `t1`, `t2` in ZEROPAGE and `ev` (8 bytes) in BSS.

From BASIC (Horizon BASIC 2.0, `horizon/BASIC.md`, "Games"): `SPRITE n, x, y, picture, flags`,
`HIT`, `SCREEN 1` / `SCREEN 2` (full screen), `SCROLL`, `PANEL`, `RASTER`, `PUT` / `GET` /
`COPY` (draw lists in full screen), `PALETTE`, `VSYNC`, `FRAME`: the same calls, a few a frame
(ABI.md, "For BASIC (2.0)"); `templates/basic-game` is a sprite game in BASIC.

## The memory rule

Marga (the framebuffer, sprite images), Ali (draw lists) and Lau (samples) read and write
memory by themselves, past the memory protection (FREDDIE II). So **every address a program
hands over for them is checked against its own memory**:

- its window (bank 0, $0000-$7FFF: the direct page and stack live there too),
- its code bank,
- banks it took with `bank_alloc`.

A range may run across consecutive banks the program owns, but not into a bank it does not
own or a shared bank. Anything else is **EFAULT**, and nothing changes. Whatever a program
holds (sprites, palette entries, full-screen mode, a running list, voices) goes back when it
ends (exit, kill, crash), and when it frees the memory involved: a freed bank takes along the
full screen whose framebuffer is in it, the images of sprites (hidden, `spr_show` then gives
EINVAL until `spr_set` gives a new image), a list reading from it (stopped) and the voices
playing from it.

What the hardware needs (ENODEV before; `ws_config` with A = 0 returns SYS_REV in X):

| From | |
| --- | --- |
| REV $08 | Ali, the blitter (draw lists are drawn by the CPU before: same picture, slower) |
| REV $09 | Ali's command lists (draw lists run in one go; on REV $08 the kernel starts the records one by one), Marga's VBLANK interrupt and frame counter (`vsync`, `frame`), the raster table, WE_VBL |
| REV $0A | Lau, the sample player ([sound.md](sound.md)) |
| REV $0B | sprites, fine scrolling (`fs_scroll`). The emulator models REV $0B by default ([hardware.md](hardware.md)) |

Full-screen mode itself (`fs_enter`, the program's own framebuffer and palette) works on every
revision.

## Frame sync

The screen is 60.03 frames a second. A game loop: `vsync`, read input (`win_event` polling,
`joystick`), update, draw (one draw list with LS_VBL on its first record is the tear-free
way), repeat. Changes made with `fs_scroll`, `spr_set` / `spr_move` and LS_VBL records all
take effect in the same vertical blank: the one after the call.

### $0F vsync (SYS_VSYNC)
Out: A = the frame counter (as `frame`). Blocks until the next vertical blank begins (line
360). From REV $09 Marga's VBLANK interrupt ends the wait and A is NV_FRAME, so a difference of
more than 1 between two results is a missed frame. Then it also **waits until the caller's
draw list is done** and makes the CPU see what Ali wrote. Before REV $09 the moment comes from
the raster line and a timer, and A counts the vertical blanks waited for by any task.
Interruptible by kill.
```asm
loop:   sys     SYS_VSYNC       ; a new frame: A = the frame counter
        tax
        sec
        sbc     z:t0            ; frames since the last time
        stx     z:t0
        cmp     #2
        bcc     :+
        inc     z:t1            ; one or more frames were missed
:       jsr     step            ; input, rules, the frame's draw list, scroll, sprites
        bra     loop
```

### $9E frame (SYS_FRAME)
Out: A = the frame counter: NV_FRAME, + 1 at every vertical blank since the start, wrapping at
65536 (REV $09). Before REV $09: the vertical blanks waited for with `vsync`. It does not wait.
After a pause, read it again so that the pause does not count as missed frames.
```asm
        sys     SYS_FRAME
        sta     z:t0            ; the next vsync's result minus this = frames passed
```

### $9F win_vbl (SYS_WINVBL)
In: A = one of your windows, X = 1 on, 0 off. That window gets WE_VBL (16) at every vertical
blank while its event queue is empty: for event-loop programs (and ui.lib programs) that draw
once a frame. ENODEV before REV $09 (use `win_timer` then). EINVAL: not your window.

| Event | Value | a | b | c |
| --- | --- | --- | --- | --- |
| `WE_VBL` | 16 | - | - | - |

```asm
        lda     z:win
        ldx     #1
        sys     SYS_WINVBL      ; WE_VBL from now on
        bcs     old             ; ENODEV: a timer instead
loop:   lda     #0              ; wait for the next event
        ptr     ev
        sys     SYS_WEVENT
        lda     ev
        and     #$00FF
        cmp     #WE_VBL
        bne     other
        jsr     step            ; one frame
        jsr     draw
        bra     loop
other:  jsr     handle          ; keys, buttons, ...
        bra     loop
old:    rts
```

## Palette entries

The system palette (0-15 the UI colours, 16-231 the 6 x 6 x 6 cube, 232-255 greys) is the
same for every program. A program takes entries 16-255 for colours of its own with `pal_alloc`
(entries nobody holds) or by setting an entry nobody holds (`ws_palette`, `pal_set`).

**The focus rule: an entry a program holds shows its colour while one of its windows has the
keyboard focus, and the system colour otherwise.** It goes back to the system when the program
ends or calls `pal_alloc` with A = 0. So the program in front always looks as it means to, and
no program's colours change what another shows while that one is in front; a program in the
background may look different meanwhile (games pause there anyway). Two programs never hold
the same entry (EAGAIN). A program that draws with system colours and wants them right also
while another program is in front can claim them at their place with `pal_alloc` (they keep
their system colours; the kernel gives other programs other entries). Entries 0-15 stay global
(`ws_palette` sets them for everyone: Settings' desktop colours). In full-screen mode the
program has a whole palette of its own (below).

### $9B pal_alloc (SYS_PALALLOC)
In: A = count 1-240, X = the first entry wanted, or $FFFF: any. Out: A = the first entry.
count entries in a row that nobody holds become yours, with their system colours (nothing
changes until you set them). With $FFFF the kernel chooses: first in 76-113 and 136-175 (no
desktop icon or UI colour uses them), then from 16 up. A = 0: every entry you hold goes back.
EAGAIN: no such run.
```asm
        lda     #4              ; four entries, where the kernel likes
        ldx     #$FFFF
        sys     SYS_PALALLOC
        bcs     none            ; EAGAIN: no four free in a row
        sta     z:t0            ; the first one
        ora     #4 << 8         ; first | count << 8
        ptr     rgb
        sys     SYS_PALSET
none:   rts
rgb:    .byte   255, 128, 0,  255, 160, 0,  255, 192, 0,  255, 224, 0
```

### $9A pal_set (SYS_PALSET)
In: A = first entry | count << 8 (count 0 = 256), X, Y = count x 3 bytes red, green, blue.
Several entries in one call, each by the rules of `ws_palette` ([windows.md](windows.md)):
16-255 become yours if nobody holds them; EAGAIN (nothing set) if one of them is another
program's; EINVAL past 255. In full-screen mode: your own palette, all 256 entries.
```asm
        lda     #0              ; full screen: all 256 entries black (count 0 = 256)
        ptr     black
        sys     SYS_PALSET
        rts
black:  .res    768
```

## Sprites

Marga has 16 sprites (REV $0B), shared by all programs. A program takes some with `spr_alloc`
for one of its windows; positions are relative to that window's content, or to the screen in
full-screen mode (in 320 x 180 pixels in that mode). Sprites cost no CPU time and no blits:
moving one is a write of its position (`spr_move`), animating one a new image address
(`spr_set`). Every change goes to Marga in the next vertical blank (NV_SPR_COMMIT), all the
changes of one call together: a frame never shows half of a change.

**Images**: rows top to bottom, no gaps; colour 0 is transparent; **16-byte aligned**; in your
own memory (EFAULT otherwise) and left there, unchanged, while shown (Marga reads them every
frame).

| Depth | Size (ctrl) | Bytes |
| --- | --- | --- |
| 8 bpp | 16 x 16 | 256 |
| 8 bpp | 16 x 32 (SPR_TALL) | 512 |
| 4 bpp (SPR_BPP4) | 16 x 16 | 128 |
| 4 bpp | 32 x 16 (SPR_WIDE) | 256 |
| 4 bpp | 16 x 32 (SPR_TALL) | 256 |
| 4 bpp | 32 x 32 (SPR_WIDE \| SPR_TALL) | 512 |

A 4 bpp pixel p (1-15, the left one in the high nibble) shows palette entry pal x 16 + p (pal:
the entry's palette bank). SPR_MAG doubles a sprite on the screen (up to 64 x 64). Wider than
16 at 8 bpp: two sprites side by side.

| ctrl bit | Value | |
| --- | --- | --- |
| `SPR_EN` | $01 | shown |
| `SPR_HFLIP` | $02 | mirrored left to right |
| `SPR_VFLIP` | $04 | upside down |
| `SPR_MAG` | $08 | twice as large |
| `SPR_WIDE` | $10 | 32 pixels wide (4 bpp only) |
| `SPR_TALL` | $20 | 32 lines |
| `SPR_BPP4` | $40 | 4 bpp (else 8 bpp) |
| `SPR_BEHIND` | $80 | hidden by bitmap pixels that are not colour 0 |

- **Priority**: lower numbers in front (`spr_alloc` gives a run: its first sprite is the
  front one); all in front of the bitmap except where SPR_BEHIND hides them; the mouse
  pointer in front of everything.
- **Per line**: Marga draws a sprite on a line if the on-screen widths of the sprites before
  it on that line plus its own come to 512 or less: 16 sprites up to 32 pixels wide always
  fit; eight 64-pixel ones fit on one line.
- **Off the screen**: a sprite may slide out past every edge; the kernel hides one that is far
  outside Marga's range (x -1024..1023, y -512..511).

**The rule for windows.** Hardware sprites cannot be cut to a window's shape, so a window's
sprites are shown only while that window has the keyboard focus, nothing lies over its
content (no other window, menu or pop-up menu) and the desktop is on the screen; and only the
ones that lie wholly inside its content. The others are hidden until that holds again. Their
screen position follows the window (brought up to date after every repaint: a window that
moves takes them along). A program's sprites are freed when it ends or closes their window.

### $91 spr_alloc (SYS_SPRALLOC)
In: A = count 1-16, X = one of your windows. Out: A = the first of count sprites in a row,
hidden, without an image. ENODEV before REV $0B; EINVAL a bad count or not your window; EAGAIN
no such run free (other programs hold sprites too: ask for what you need).
```asm
        lda     #4
        ldx     z:win
        sys     SYS_SPRALLOC
        bcs     nospr           ; ENODEV: no sprites on this machine (blits instead)
        sta     z:t0            ; sprites t0 .. t0 + 3
nospr:  rts
```

### $93 spr_set (SYS_SPRSET)
In: A = count 1-16, X, Y = count entries of 10 bytes. Every field of each sprite; all of them
change together from the next frame on. Checked first, then set: EINVAL a sprite not yours or
an image not 16-byte aligned; EFAULT an image not wholly in your memory; then nothing changes.

| Offset | Constant | Field |
| --- | --- | --- |
| 0 | `SE_SPRITE` | u8 the sprite |
| 1 | `SE_CTRL` | u8 ctrl (SPR_* above; SPR_EN shows it) |
| 2 | `SE_X` | i16 x |
| 4 | `SE_Y` | i16 y |
| 6 | `SE_IMAGE` | u24 the image |
| 9 | `SE_PAL` | u8 the palette bank (4 bpp) |

```asm
        ldx     #0              ; the image into the window: 16-byte aligned, our memory
:       lda     ball,x
        sta     f:$001000,x
        inx
        inx
        cpx     #256
        bcc     :-
        sep     #$20            ; the sprites spr_alloc gave (t0, t0 + 1)
        .a8
        lda     z:t0
        sta     ents+SE_SPRITE
        inc     a
        sta     ents+10+SE_SPRITE
        rep     #$20
        .a16
        lda     #2
        ptr     ents
        sys     SYS_SPRSET
        rts
ball:   .res    256             ; a 16 x 16 8 bpp image, colour 0 transparent
        .segment "DATA"
ents:   .byte   0, SPR_EN       ; sprite, ctrl
        .word   40, 30          ; x, y (the window's content)
        .faraddr $001000        ; the image (bank 0: the window)
        .byte   0               ; palette bank (4 bpp only)
        .byte   0, SPR_EN | SPR_MAG | SPR_HFLIP
        .word   100, 30
        .faraddr $001000
        .byte   0
```
A game sets all its sprites with one `spr_set` a frame (one call, one check of every image),
or moves the ones that only move with `spr_move`.

### $94 spr_move (SYS_SPRMOVE)
In: A = one of your sprites, X = x, Y = y. Its position only: the cheap per-frame call.
```asm
        lda     z:t0            ; the sprite
        ldx     z:t1            ; x
        ldy     z:t2            ; y
        sys     SYS_SPRMOVE
```

### $95 spr_show (SYS_SPRSHOW)
In: A = one of your sprites, X = 1 show, 0 hide. EINVAL: not yours, or shown without an image
(never given, or its bank was freed).
```asm
        lda     z:t0
        ldx     #0              ; hide it
        sys     SYS_SPRSHOW
```

### $92 spr_free (SYS_SPRFREE)
In: A = the first sprite, X = count; A = $FFFF: all of yours. EINVAL: one of them is not yours
(then none is freed).
```asm
        lda     #$FFFF
        sys     SYS_SPRFREE
```

## Full-screen mode

`fs_enter` gives the kernel a framebuffer in the program's own memory and a mode. While that
window has the keyboard focus, Marga shows the framebuffer instead of the desktop, with:

- the program's own palette: all 256 entries (`ws_palette`, `pal_set`), starting as the
  palette shown when it entered;
- its scroll registers (`fs_scroll`, REV $0B): pixel offsets, horizontal wrap, vertical wrap,
  a split line with a second set (a fixed status panel above or below a scrolling playfield);
- its sprites, in screen coordinates (in 320 x 180 pixels in that mode);
- its raster table (`fs_raster`, REV $09): up to 16 palette changes at given lines;
- the mouse pointer if FS_PTR is set (never in 320 x 180).

The menu bar and the other windows are not shown; the window itself stays a normal window
on the desktop (what the program drew in it), seen whenever the full screen is not. One
program at a time is in full-screen mode (another gets EAGAIN, also while the first one is
in the background).

| Mode | Value | Screen | Framebuffer |
| --- | --- | --- | --- |
| `FS_640X8` | 0 | 640 x 360, 256 colours | stride >= 640, rows >= 360 |
| `FS_640X4` | 1 | 640 x 360, 16 colours (entries 0-15; two pixels a byte, the left one in the high nibble) | stride >= 320, rows >= 360 |
| `FS_320X8` | 2 | 320 x 180, 256 colours, each pixel shown 4 x 4 on the monitor | stride >= 320, rows >= 180 |

| Flag | Value | |
| --- | --- | --- |
| `FS_PTR` | 1 | the mouse pointer is shown (not in 320 x 180) |

### $96 fs_enter (SYS_FSENTER)
In: A = one of your windows (not a backdrop, not a terminal), X, Y = a 10-byte block: {u8 mode,
u8 flags, u16 stride, u16 rows, u24 base, u8 0}.

- stride: bytes a row, a multiple of 16, at least 640 / 320 / 320 (by mode), at most 4096;
- rows: 360 / 360 / 180 .. 1024;
- base: row 0's address, 256-byte aligned;
- **rows x stride bytes from base must be your memory** (EFAULT): a window bank's range, the
  code bank, or banks you allocated, across consecutive banks.

Errors: EINVAL a bad value, a backdrop or terminal window, not your window, no window system;
EAGAIN another window is in full-screen mode; EFAULT the framebuffer. Called again for the same
window: a new framebuffer, mode or geometry from the next frame on (page flipping: draw into
one buffer while the other is shown, then hand it over); the scroll set must still fit it,
else EINVAL.
```asm
        sys     SYS_BALLOC      ; 320 x 180 = 57,600 bytes: one bank is enough
        bcs     out
        sep     #$20
        .a8
        sta     fsb+8           ; base = bank:0000
        rep     #$20
        .a16
        lda     z:win
        ptr     fsb
        sys     SYS_FSENTER     ; shown from the next frame on (while the window has the focus)
out:    rts
        .segment "DATA"
fsb:    .byte   FS_320X8, 0     ; mode, flags
        .word   320, 180        ; stride, rows
        .faraddr 0              ; base (its bank is set above)
        .byte   0
```

### The framebuffer

It is your memory: the CPU may draw into it directly (long addressing), and Ali draws into it
through draw lists, with coordinates in the framebuffer: all of its rows and its whole stride,
so the parts off the screen can be prepared before they scroll in. **What Marga reads**: the
rows of the framebuffer the scroll registers select, each from its row's start plus the x
offset, a line's worth of bytes (640, or 320 in the 4 bpp and 320 x 180 modes); `fs_enter`
checked the whole rows x stride range, and `fs_scroll` refuses any value that would make
Marga read outside it.

More than one bank (a framebuffer over 65,536 bytes, or two for page flipping): the range must
run across consecutive banks you own. `bank_alloc` gives the lowest free bank, so the banks of
a program that allocates them one after the other are usually consecutive, but not always
(another program may have freed one in between). Check, and keep asking:
```asm
        sys     SYS_BALLOC
        bcs     fail
        sta     z:t0            ; the first bank
next:   sys     SYS_BALLOC
        bcs     fail
        sta     z:t1
        dec     a
        cmp     z:t0
        beq     pair            ; t0, t0 + 1: done
        lda     z:t1            ; not next to it: go on from the new one (the old one is
        sta     z:t0            ; kept until the end here; examples/deepdive gives it back)
        bra     next
pair:   clc
fail:   rts
```
A 640 x 360 x 8 framebuffer is 230,400 bytes (4 banks at stride 640, more with a stride for
scrolling); 640 x 360 x 4 is 115,200 (2 banks); 320 x 180 x 8 is 57,600 (one bank, with room
for a status panel or a wider ring: `examples/deepdive` uses 336 x 208 in two).

### Keys, focus, and the way out

Keys, buttons, motion (with a button held, or always with WF_HOVER) and the wheel go to the
full-screen window as usual events, with the pointer's position on the screen (halved in
320 x 180). The menu bar is not shown and the window manager keeps only its way out, which
works whatever the program does:

- **Alt+Tab, Alt+Esc** minimize the full-screen window: the desktop comes back as it was;
- **F12** does the same, then shows the classic machine as always;
- **Alt+F4** sends WE_CLOSE (leave and end, or ask);
- whenever the window loses the focus otherwise (another program's window comes up, the
  program's own dialog, the Windows menu), the desktop comes back too;
- the program's end (exit, kill, crash), `fs_leave`, closing the window and freeing a bank the
  framebuffer lies in end full-screen mode.

On leaving, the program gets **WE_UNFOCUS** (pause: stop the samples, wait for events). When
its window gets the focus again (Alt+Tab, the Windows menu, a click on the window) its screen
is shown again exactly as it was and it gets **WE_FOCUS**.

**What is saved and restored.** Nothing of the desktop needs saving: its framebuffer is
untouched (the compositor keeps it current meanwhile), and leaving restores mode 0, NV_BASE,
stride 1024, the scroll registers at their reset values, the raster interrupt off, the system
palette with the front program's entries, the desktop's sprites, the pointer, then repaints.
Of the full-screen program the kernel keeps the mode, flags, framebuffer address, stride,
rows, the scroll set, its 256-entry palette, its raster table and its sprites; entering again
writes them back. The framebuffer itself is your memory and nobody else touches it.

### $97 fs_leave (SYS_FSLEAVE)
In: A = your full-screen window. Back to the desktop (the window stays open). EINVAL: not in
full-screen mode.
```asm
        lda     z:win
        sys     SYS_FSLEAVE
```

### $98 fs_scroll (SYS_FSSCROLL)
In: X, Y = a 14-byte block: {u16 x, u16 y, u16 x2, u16 y2, u16 vheight, u16 split line, u8
ctrl, u8 0}. Marga's scroll registers (REV $0B, else ENODEV), all taken together at the next
vertical blank (and kept while the program is in the background).

- **x, y**: the first set. Line 0 shows row y, from pixel x (pixels of the mode: in 4 bpp two
  a byte). Every following line shows the next row (in 320 x 180 every second line).
- **vheight**: rows of the virtual bitmap (0: no vertical wrap). A row number that reaches
  vheight - 1 goes on at row 0; a set that starts at vheight or below it does not wrap (a
  status panel kept below the ring of rows).
- **ctrl** `FSC_HWRAP`: a row is a ring of stride bytes (a line running past its end goes on
  at the row's start); `FSC_SPLIT`: from the split line on, the second set x2, y2.
- **split line**: 1-359 in screen lines (Marga counts 360 lines in every mode: in 320 x 180 it
  must be even, and the panel above it is split / 2 rows).

| ctrl | Value |
| --- | --- |
| `FSC_HWRAP` | 1 |
| `FSC_SPLIT` | 2 |

**The check** (EINVAL, nothing changes): only the full-screen program may call it; ctrl only
bits 0-1; vheight 0 to rows; with the split, the split line 1-359 (even in 320 x 180); then
for each set in use and the rows it shows (all 360 / 180 without the split; the lines before
and from the split with it): y below 1024, and either y below vheight (it wraps inside the
first vheight rows) or y + its rows <= the framebuffer's rows; x below 4096, and with
FSC_HWRAP x's bytes below the stride, without it x's bytes + a line's bytes <= the stride.
So Marga never reads outside the framebuffer `fs_enter` checked.
```asm
        lda     z:t0            ; the camera, already wrapped into the ring: x2 ...
        sta     scr+4
        lda     z:t1            ; ... and y2
        sta     scr+6
        ptr     scr
        sys     SYS_FSSCROLL    ; at the next vertical blank, all together
        rts
        .segment "DATA"
scr:    .word   0, 192          ; first set: the panel, rows 192-207 (past vheight: no wrap)
        .word   0, 0            ; second set: the playfield (x2, y2)
        .word   192             ; vheight: rows 0-191 wrap
        .word   32              ; the split line (320 x 180: 16 rows of panel)
        .byte   FSC_HWRAP | FSC_SPLIT, 0
```
That is `examples/deepdive`'s set: 320 x 180, stride 336 (a ring of 21 tiles of 16), 208
rows: the playfield is a ring of 21 x 12 tile slots that wraps both ways, and only the column
or row of tiles that comes into view is ever drawn. Sprites and the pointer do not scroll.

### $99 fs_raster (SYS_FSRASTER)
In: A = count 0-16, X, Y = count entries of 6 bytes: {u16 line, u8 entry, u8 red, green, blue}.
The raster table (REV $09, else ENODEV): from that line on the entry has that colour; lines
1-359, ascending (equal ones are written in order); with the split on, the split line or
later. Every frame starts with the palette's own colours. 0: off. EINVAL: not the full-screen
program, a bad line or order.

The kernel's LINE interrupt handler writes the colours in the horizontal blank (it takes the
interrupt one line early and waits for the line to begin); programs never run code in
interrupts. A change is exact from its line on while the CPU runs a program or idles; kernel
work with interrupts masked (a file read, a CPU blit) can delay it.
```asm
        lda     #2
        ptr     ras
        sys     SYS_FSRASTER
        rts
ras:    .word   180             ; from line 180 entry 0 is dark blue ...
        .byte   0, 0, 0, 96
        .word   300             ; ... and from line 300 darker
        .byte   0, 0, 0, 48
```

## Draw lists

### $9C draw_list (SYS_DRAWLIST)
In: A = window | count << 8 (count 1-128), X, Y = count records of 20 bytes in your memory.
Out: A = the records drawn (those clipped away are left out). Many blits in one syscall: Ali
runs them as one command list (REV $09) and **the call returns at once**; on REV $08 the kernel
starts them one by one, without the blitter the CPU draws them: the picture is the same.

| Offset | Constant | Field |
| --- | --- | --- |
| 0 | `LR_OP` | u8 op (below) |
| 1 | `LR_FLAGS` | u8 flags: bit 0 LS_VBL (wait for the vertical blank before this record), bits 4-6 expand's first source bit (0 = bit 7) |
| 2 | `LR_C1` | u8 c1: the fill colour, expand's set bits |
| 3 | `LR_C2` | u8 c2: the key colour of LS_KEY, expand's clear bits |
| 4 | `LR_X` | i16 x: the destination |
| 6 | `LR_Y` | i16 y |
| 8 | `LR_W` | u16 w |
| 10 | `LR_H` | u16 h |
| 12 | `LR_SRC` | u24 source (copy, keyed copy, expand), then u8 0; LS_MOVE: i16 sx at 12, i16 sy at 14 |
| 16 | `LR_STRIDE` | u16 source stride (0: the width; expand: the bytes a row needs) |
| 18 | | u16 0 |

| Op | Value | |
| --- | --- | --- |
| `LS_FILL` | 0 | w x h of colour c1 |
| `LS_COPY` | 1 | an 8 bpp picture |
| `LS_KEY` | 2 | the same, pixels of colour c2 skipped |
| `LS_EXPAND` | 3 | 1 bpp (bit 7 leftmost): set bits c1, clear bits c2 |
| `LS_EXPANDK` | 4 | 1 bpp: set bits c1, clear bits left as they are |
| `LS_MOVE` | 5 | a rectangle of the target from (sx, sy) to (x, y), overlap-safe |

| Flag | Value |
| --- | --- |
| `LS_VBL` | 1 |

- **Target**: the window's content (on the screen itself while nothing lies over it and no
  repaint over it is pending, else its bitmap, which the compositor then shows: the rule of
  `win_draw`), or, in full-screen mode, that window's framebuffer: all its rows and its whole
  stride, coordinates in the framebuffer (in 640 x 360 x 4: x and w in bytes).
- **Clipping**: each record is cut to the target (negative x, y allowed); the source moves
  with the cut. LS_MOVE cuts source and destination by the same amounts.
- **Checking**: every record's whole source must be your memory (EFAULT), and the records
  themselves; EINVAL a bad window, op or count, or more than 460,800 pixels in one call (two
  screens). On an error nothing is drawn. The records are read during the call: you may
  rewrite them as soon as it returns.
- **While a list runs its sources are being read and its target written: leave them alone
  until `list_wait` (or `vsync`, or the next `draw_list`, which wait for it).** Change a
  source picture only after one of those; to read the framebuffer with the CPU after Ali
  wrote it, `list_wait` first (it also makes the CPU see Ali's writes).
- **LS_VBL** on the first record: the blits start in the vertical blank, together with the
  scroll values and sprite changes of the same frame. A frame's whole update in one syscall,
  tear-free. (On any later record: wait for the next blank there.)
- A program's running list is stopped (Ali's ABORT) when it ends or frees a bank.
- Cost (emulator): about 2,000 CPU cycles a record in the call (checking and clipping), then
  Ali's own time, while the CPU goes on: [performance.md](performance.md).
```asm
        lda     z:win
        ora     #2 << 8         ; window | count << 8
        ptr     recs
        sys     SYS_DRAWLIST    ; -> A = the records drawn; Ali works on
        rts
recs:   .byte   LS_FILL, LS_VBL, C_BLACK, 0     ; op, flags, c1, c2: in the vertical blank
        .word   0, 0, 64, 32                    ; x, y, w, h
        .res    8, 0                            ; (no source)
        .byte   LS_KEY, 0, 0, 231               ; a keyed copy: colour 231 skipped
        .word   24, 8, 16, 16
        .faraddr sprite                         ; the source
        .byte   0
        .word   0, 0                            ; stride 0: the width
sprite: .res    256
```

### $9D list_wait (SYS_LISTWAIT)
In: A = 0 wait, 1 ask. Out: A = 1 while your list still runs (asked), 0 when done. Waiting
(or an answer of 0) also makes the CPU see what Ali wrote (CACHE_FLUSH).
```asm
        lda     #0
        sys     SYS_LISTWAIT    ; done: its sources may change now
```
