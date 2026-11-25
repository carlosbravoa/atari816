# Drawing: win_draw

Everything a program shows in a window goes through one syscall, `win_draw`, with a
16-byte parameter block. The kernel clips to the window's content, draws with the blitter
(REV $08 boards, the default in the emulator) or with the CPU (REV $07), and shows the
result: at once when no other window covers yours ("direct drawing"), else at the next
repaint (within 10 ms).

### $74 win_draw (SYS_WDRAW)
In: A = window, X, Y = the block below. EINVAL: a bad window or op; EFAULT: a bad pointer.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 1 | op (below) |
| 1 | 1 | c1: colour (ink) |
| 2 | 1 | c2: second colour (paper, key) |
| 3 | 1 | font (WD_TEXT): 0 UI, 1 fixed 8x12 |
| 4 | 2 | x (signed, content coordinates) |
| 6 | 2 | y |
| 8 | 2 | w (WD_LINE: the end x) |
| 10 | 2 | h (WD_LINE: the end y) |
| 12 | 3 | ptr: u24 address of a string or of pixels |
| 15 | 2 | stride (ops 10 and 11 only: their block is 17 bytes) |

| Op | Value | Draws |
| --- | --- | --- |
| `WD_FILL` | 1 | the rectangle x, y, w, h in c1 |
| `WD_FRAME` | 2 | a 1-pixel frame, the rectangle's edge, in c1 |
| `WD_LINE` | 3 | a line from (x, y) to (w, h) in c1 |
| `WD_TEXT` | 4 | the string at ptr (below) |
| `WD_BLIT` | 5 | the w x h picture at ptr (8 bpp, rows of w bytes) |
| `WD_KBLIT` | 6 | the same, pixels of colour c2 are skipped (transparent) |
| `WD_DITHER` | 7 | a checker of c1 and c2 (c2 where x + y is odd) |
| `WD_SBLIT` | 8 | a part of a larger picture (below) |
| `WD_COPY` | 9 | a copy inside the content (below) |
| `WD_EXPAND` | 10 | (0.14) a 1 bpp picture (below) |
| `WD_KSBLIT` | 11 | (0.14) WD_KBLIT with a stride (below) |

- `WD_TEXT`: the zero-terminated string at ptr, its top at y; ink c1, paper c2 ($FF =
  none); font 0 or 1.
- `WD_SBLIT`: like WD_BLIT, with the source stride c1 | c2 << 8: a w x h part of a larger
  picture.
- `WD_COPY`: the rectangle x, y, w, h of the window's own content moves to (c1 | c2 << 8,
  the low word of ptr); the two may overlap (scrolling).
- `WD_EXPAND`: a 17-byte block (+ u16 stride at 15). The w x h 1 bpp picture at ptr (bit 7
  leftmost; its first pixel at bit `font`, 0 = bit 7; rows `stride` bytes apart, 0: the
  bytes a row needs): set bits in c1, clear bits in c2, or left as they are when c2 = $FF.
- `WD_KSBLIT`: a 17-byte block. Like WD_KBLIT, rows `stride` bytes apart (0: w).

Rules:
- A picture for WD_BLIT / WD_KBLIT / WD_SBLIT must lie in one bank (it may be in your code
  bank or in a bank from SYS_BALLOC): w x h bytes (or (h - 1) x stride + w) from ptr,
  not crossing a bank boundary.
- The ops that read your memory (5, 6, 8, 10, 11) return when the blitter has finished
  reading it (Horizon 0.15; before, a picture rewritten right after its blit could be
  corrupted on the board): you may change the picture after the call. **Draw lists differ**:
  `draw_list` returns at once and its sources stay in use until `list_wait` or `vsync`
  ([games.md](games.md)).
- Coordinates may be negative or beyond the content: everything is clipped.
- There is no scaling, no rotation, no blending, no circle, no "read pixels back".
  Pictures with transparency: WD_KBLIT. Fonts other than the two built-in ones: 1 bpp glyphs
  with WD_EXPAND (c2 = $FF: transparent), or expanded to 8 bpp yourself and WD_KBLIT
  (examples/lantern does this).
- Each call costs about 0.17 ms in the emulator before any pixel is drawn (the board: about
  twice that), plus the pixels: see [performance.md](performance.md). Draw big rectangles,
  not many small ones.
- Draw text with its paper colour (c2 = the background) when it replaces other text: one
  call, no flicker, no clearing first.

## win_draw or a draw list

Horizon 0.18 adds `draw_list` ([games.md](games.md), "Draw lists"): up to 128 fills,
copies, keyed copies, 1 bpp expands and moves in one syscall, run by Ali as one command list
while the call returns at once. The same targets and the same clipping as win_draw (the
window's content; in full-screen mode the program's framebuffer).

win_draw:
- One syscall per operation (about 0.17 ms each, emulator).
- Returns when its blit has read your memory.
- Text: WD_TEXT with the system fonts.
- Lines, frames, dithers.
- No vertical blank synchronisation (call `vsync` before the calls).
- Not in the full-screen framebuffer.

draw_list:
- One syscall per list (about 2,000 cycles a record in the call).
- Returns at once: sources and target stay in use until `list_wait` / `vsync` / the next
  list.
- Text: LS_EXPAND from your own 1 bpp font.
- No lines, frames or dithers.
- LS_VBL on a record: Ali holds the list until the vertical blank, and the CPU continues.
- Draws in the full-screen framebuffer.

Use win_draw for a few operations (an application's controls, text in the system fonts); use
a list for many blits a frame (a game's sprites drawn by blits, tiles, a scrolled strip), and
for anything in full-screen mode. 100 keyed 16 x 16 blits a frame: 100 win_draw calls cost
26.6 ms of CPU a frame (more than a frame), one list 14.4 ms in the call
([performance.md](performance.md)).

## Filling the block

The block is easiest to fill with 16-bit stores; mind the two that straddle fields:
`sta blk` (op) also writes c1, and `sta blk+14` (the bank of ptr) also writes the 16th
byte, so keep the block 16 bytes long.

```asm
; a filled rectangle: op | c1 << 8, then x, y, w, h
        lda     #WD_FILL | (C_RED << 8)
        sta     blk
        lda     #10
        sta     blk+4           ; x
        lda     #20
        sta     blk+6           ; y
        lda     #100
        sta     blk+8           ; w
        lda     #50
        sta     blk+10          ; h
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
```

Text, white on blue in the fixed font:
```asm
        lda     #WD_TEXT | (C_WHITE << 8)
        sta     blk
        lda     #C_TITLE | (1 << 8)     ; c2 = paper, font = 1
        sta     blk+2
        lda     #8
        sta     blk+4
        lda     #4
        sta     blk+6
        lda     #.loword(s_score)
        sta     blk+12
        lda     #^s_score
        sta     blk+14                  ; (writes blk+15 too)
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
        rts
s_score: .byte  "SCORE 00100", 0
```

A sprite with transparency (colour 231 skipped):
```asm
        lda     #WD_KBLIT
        sta     blk
        lda     #231 << 8               ; c1 = 0, c2 = the key colour
        sta     blk+1
        lda     #50
        sta     blk+4
        lda     #60
        sta     blk+6
        lda     #4
        sta     blk+8                   ; 4 x 2 pixels
        lda     #2
        sta     blk+10
        lda     #.loword(spr)
        sta     blk+12
        lda     #^spr
        sta     blk+14
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
        rts
spr:    .byte   231, 12, 12, 231        ; row 0
        .byte   12, 0, 0, 12            ; row 1
```

A part of a larger picture (a tile from a 128-pixel-wide tile sheet, tile column 2 row 1,
16 x 16): the source address is sheet + row * 16 * 128 + col * 16, the stride 128:
```asm
        lda     #WD_SBLIT
        sta     blk
        lda     #128                    ; c1 | c2 << 8 = the source stride
        sta     blk+1
        lda     #0
        sta     blk+4                   ; x, y on the window
        sta     blk+6
        lda     #16
        sta     blk+8
        sta     blk+10
        lda     #.loword(sheet + 1 * 16 * 128 + 2 * 16)   ; (the offset inside .loword)
        sta     blk+12
        lda     #^sheet
        sta     blk+14
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
        rts
sheet:  .res    128 * 32                ; 8 x 2 tiles of 16 x 16 (the art goes here)
```

### Scrolling

Scrolling the content up by 12 lines (a text view of 300 x 200): copy (0, 12, 300, 188) to
(0, 0), then draw the new last line:
```asm
        lda     #WD_COPY
        sta     blk                     ; op; c1 = the destination x low byte (0)
        stz     blk+1                   ; destination x = 0 (c1 | c2 << 8)
        stz     blk+4                   ; source x
        lda     #12
        sta     blk+6                   ; source y
        lda     #300
        sta     blk+8
        lda     #188
        sta     blk+10
        stz     blk+12                  ; destination y = 0 (the low word of ptr)
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
```

A line and a frame:
```asm
        lda     #WD_LINE | (C_BLACK << 8)
        sta     blk
        stz     blk+4                   ; from (0, 0)
        stz     blk+6
        lda     #99
        sta     blk+8                   ; to (99, 49)
        lda     #49
        sta     blk+10
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
        lda     #WD_FRAME | (C_DARK << 8)
        sta     blk
        lda     #100
        sta     blk+8                   ; a frame 100 x 50 at (0, 0)
        lda     #50
        sta     blk+10
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
```

### $76 win_twidth (SYS_WTWIDTH)
In: A = font (0 UI, 1 fixed), X, Y = string. Out: A = its width in pixels as WD_TEXT
would draw it. (ui.lib's `ui_twidth` computes it without a syscall.)
```asm
        lda     #0              ; the UI font
        ptr     s_hi
        sys     SYS_WTWIDTH     ; -> A = pixels
        rts
s_hi:   .byte   "Hello", 0
```

## Fonts

- Font 0, the UI font, proportional: 12-line cells: capitals and ascenders 7 rows,
  x-height 6, descenders 2 more; advances 2-7 pixels. Draw lines 12 pixels apart
  (`UI_LINE`).
- Font 1, the console font, fixed: 8 x 12 cells, glyphs at most 6 pixels wide.

Both are Horizon's own designs; only printable ASCII (32-126).

## Colours

The system palette (`horizon/tools/mkpalette.py`):

| Entries | |
| --- | --- |
| 0-15 | the UI colours, named in horizon.inc |
| 16-231 | a 6 x 6 x 6 colour cube: 16 + 36 r + 6 g + b, each 0-5 (0, 51, 102, 153, 204, 255) |
| 232-255 | greys from 8 to 238 in steps of 10 |

| Name | Index | RGB | Use |
| --- | --- | --- | --- |
| `C_BLACK` | 0 | 0 0 0 | text, outlines |
| `C_WHITE` | 1 | 255 255 255 | |
| `C_DESK` | 2 | 36 92 112 | the desktop |
| `C_DESK2` | 3 | 46 104 124 | its dither partner |
| `C_TITLE` | 4 | 28 60 132 | the active title bar |
| `C_TITLE_OFF` | 5 | 132 138 148 | an inactive title bar |
| `C_BODY` | 6 | 228 226 216 | window backgrounds |
| `C_DARK` | 7 | 76 80 90 | bevel shadow, outlines of controls |
| `C_MID` | 8 | 160 164 172 | |
| `C_LIGHT` | 9 | 204 206 210 | |
| `C_SELECT` | 10 | 52 100 204 | selection, focus |
| `C_RED` | 11 | 200 52 44 | |
| `C_YELLOW` | 12 | 240 200 64 | |
| `C_GREEN` | 13 | 60 156 80 | |
| `C_ORANGE` | 14 | 232 128 40 | |
| `C_SHADOW` | 15 | 36 40 48 | |

The system palette is the same for every window. Horizon 0.18: a program may hold entries
16-255 of its own (`pal_alloc`, `pal_set`, `ws_palette`); they show its colours while one of
its windows has the focus, the system colours otherwise ([games.md](games.md), "Palette
entries"); in full-screen mode all 256 entries are the program's. `sdk/tools/img2inc.py` maps
pictures to the system palette, or gives them entries of their own (`--own-palette`).
