# The hardware, for game and graphics programmers

**A Horizon program never touches these registers.** The I/O page ($00:D000-$DFFF) is
closed to user mode: one access and the kernel kills the task. Everything below is
reached through syscalls (the "From a program" column). It is here so you know what the
syscalls cost and why the rules are what they are. The definition is
`Docs/02-register-spec.md`; where the hardware differs from it today, this page says so.

## The machine

| | |
| --- | --- |
| CPU | 65C816 (a soft core in the FPGA, the MiSTer SNES core's), 14.34 MHz (clk_core / 2); a turbo setting exists in the spec, not in the build |
| Memory | 8 MB SDRAM on the Tang Nano 20K (16 MB in the spec): banks $00-$7F; 2-4 KB CPU cache |
| Video | Marga, the video chip: 640 x 360 at 8 bpp (the desktop), 640 x 360 at 4 bpp, 320 x 180 at 8 bpp, shown on 1280 x 720 at 60 Hz (HDMI); hardware pointer 32 x 32; (REV $0B) 16 sprites, fine scrolling with wrap and a split |
| Blitter | Ali, the blitter: rectangle fill, copy, keyed copy, 1-to-8 bpp expand; 8 bpp only; (REV $09) command lists |
| Sound | POKEY 2 of the classic machine (4 voices) + four 8-bit DACs (REV $07+); Lau, the 8-voice sample player (REV $0A; Horizon 0.17: SYS_SPLAY ...) |
| Input | USB keyboard and mouse through the I/O processor; two DB9 joystick ports (classic side) |
| Storage | SD card (FAT32) through the I/O processor (a PicoRV32 in the FPGA) |
| Classic machine | a cycle-exact Atari 800/XL/XE (NMOS 6502, ANTIC, GTIA, two POKEYs, PIA) |

Revisions (SYS_REV; `ws_config` with A = 0 returns it in X):

| REV | Adds |
| --- | --- |
| $06 | (no blitter, no native sound) |
| $07 | native sound: POKEY 2, the DACs |
| $08 | Ali, the blitter |
| $09 | Ali's command lists, Marga's VBLANK interrupt and frame counter (NV_FRAME), raster (LINE) events at the beam |
| $0A | Lau, the sample player |
| $0B | Marga's 16 sprites and fine scrolling (scroll registers, wrap, split) |

**emu816 models REV $0B by default**; `--rev 10`, `9`, `8` or `7` (also `run816.py --rev N`)
emulate the older ones. Test your program on the revisions you care about: without sprites
or scrolling (before $0B) the calls give ENODEV; without the blitter Horizon draws with the
CPU, 5-15 times slower. The board's own revision is whatever its FPGA build is: ask SYS_REV
(the bring-up log, `Docs/03-bringup1-log.md`, says which features have been run on it).

## Marga (video) — $D900

| Register | Address | Meaning | From a program |
| --- | --- | --- | --- |
| NV_CTRL | $00:D900 | bit 0 enable, bits 1-2 mode (0 = 640 x 360 x 8 bpp, 1 = 640 x 360 x 4 bpp, 2 = 320 x 180 x 8 bpp shown 4 x 4), bit 3 the pointer | `fs_enter` (the mode of a full-screen program); the window system uses mode 0, the text console mode 1 |
| NV_BASE | $00:D901-3 | framebuffer address (256-byte aligned), taken at the next vertical blank | `fs_enter` |
| NV_STRIDE | $00:D904-5 | bytes per line (a multiple of 16 from REV $0B) | `fs_enter` |
| NV_LINE | $00:D906-7 | the line being shown (0-359; 360-374 in the blank) | none |
| NV_LINE_CMP | $00:D908-9 | raise the LINE interrupt at this line; (REV $0B) also the split line | `fs_raster`, `fs_scroll` (the kernel's) |
| NV_STATUS | $00:D90A | bit 0 in vertical blank, bit 1 a new base not yet taken | none |
| PAL_IDX / R / G / B | $00:D910-3 | palette entry, red, green, blue (a write to B commits) | `SYS_WSPAL`, `pal_set` |
| PTR_* | $00:D920-A | pointer position, hot spot, image, colours | `SYS_WPTR` (shape only) |
| NV_SCROLLX .. NV_SCROLL_CTRL | $00:D930-A | (REV $0B) scroll offsets, a second set, VHEIGHT, HWRAP / SPLIT | `fs_scroll` |
| NV_SPR_* and records | $00:D940-2, $D980-$D9FF | (REV $0B) sprites on, commit, status; 16 records of 8 bytes | `spr_*` |
| NV_FRAME | $00:D90C-D | (REV $09) the frame counter: + 1 at every vertical blank | `vsync`, `frame` |

- The window system's screen: mode 0, 640 x 360, 8 bpp, stride 1024, in 6 banks the kernel
  takes at `SYS_WSSTART`. Each window has its own 8 bpp bitmap; the compositor copies them
  to the screen (or the window draws straight onto it when nothing covers it).
- **Full-screen mode** (Horizon 0.18, `fs_enter`): a program's own framebuffer (in its
  memory) in any of the three modes, its own palette, the scroll registers (`fs_scroll`),
  a raster table (`fs_raster`: the kernel's LINE interrupt changes palette entries at given
  lines; programs never run interrupt code), page flipping (`fs_enter` again). While its
  window has the focus; Alt+Tab, Alt+Esc and F12 always give the desktop back. See
  [games.md](games.md).
- **Sprites** (REV $0B, Horizon 0.18 `spr_*`): 16, each with its own image in RAM (8 bpp
  16 x 16 / 16 x 32, 4 bpp up to 32 x 32), flips, 2x, BEHIND; written to Marga in the
  vertical blank. In a window only while it has the focus and nothing covers it.
- **Fine scrolling** (REV $0B): NV_SCROLLX / Y, a second set from a split line, horizontal
  wrap (a row is a ring of stride bytes) and vertical wrap (VHEIGHT); full-screen mode only.
- The frame is 60.03 Hz (238,944 CPU cycles). `vsync` blocks until the vertical blank and
  returns Marga's frame counter (REV $09), `frame` reads it, WE_VBL comes at every blank
  if asked for (`win_vbl`); the window timer (`SYS_WTIMER`) ticks every 10 ms. Tearing: a
  blit may be shown half old, half new if the beam passes it meanwhile; a draw list with
  LS_VBL starts in the blank.
- The reset palette is the GTIA NTSC palette; Horizon loads its own system palette (0-15 UI
  colours, 16-231 a 6 x 6 x 6 cube, 232-255 greys) when the window system starts.

## Ali (blitter) — $DA00 (REV $08)

| Register | Address | |
| --- | --- | --- |
| BL_SRC | $DA00-2 | source address (24-bit) |
| BL_SRC_STRIDE | $DA03-4 | source bytes per line |
| BL_DST | $DA05-7 | destination address |
| BL_DST_STRIDE | $DA08-9 | destination bytes per line |
| BL_WIDTH, BL_HEIGHT | $DA0A-D | 1-4096 each |
| BL_FG, BL_BG | $DA0E-F | fill colour / expand colours |
| BL_KEY | $DA10 | the transparent colour of COPY_KEY |
| BL_OP | $DA11 | 0 FILL, 1 COPY, 2 COPY_KEY, 3 EXPAND (1 bpp to FG / BG), 4 EXPAND_KEY (0 bits left alone) |
| BL_FLAGS | $DA12 | bit 0 BACKWARDS (overlapping moves), bits 4-6 the first source bit for EXPAND |
| BL_CTRL | $DA13 | write bit 0 START; read bit 0 BUSY; bit 1 interrupt when done |

Rules the kernel keeps (the emulator reports any break, `run816.py` fails on it): no
register write and no START while BUSY; a CACHE_FLUSH ($00:D80A) before the CPU reads what
the blitter wrote; an overlapping copy in the wrong direction is undefined.

From a program: `SYS_WDRAW` ops. WD_FILL = FILL; WD_BLIT, WD_SBLIT, WD_COPY = COPY;
WD_KBLIT, WD_KSBLIT = COPY_KEY; WD_EXPAND = EXPAND / EXPAND_KEY; WD_TEXT = one EXPAND_KEY per
glyph. The kernel clips, translates your window coordinates, and copies from your memory
(your picture's physical address is used directly: no copy of the data is made). Horizon
0.18: `draw_list` hands up to 128 such operations to Ali as one command list (REV $09),
started in the vertical blank if asked ([games.md](games.md)).

Speed (the RTL's measured cost, modelled by the emulator): about 2 clk_core per pixel for
FILL (one CPU cycle: ~14 million pixels a second), 2.2 for EXPAND, 2.9 for COPY with the
classic machine frozen (3.5 while it runs) plus 0.8 with the video on: about 7.7 million
pixels a second for a copy; plus 8 + 2 per line CPU cycles. See
[performance.md](performance.md) for what a win_draw call costs in all.

## Sound ($00:DB00, REV $07)

| Address | | From a program |
| --- | --- | --- |
| $DB00-$DB0F | POKEY 2 (write only): AUDF1-4, AUDC1-4, AUDCTL, STIMER, SKCTL | `SYS_SNDW` A = $00-$0F |
| $DB10-$DB13 | four 8-bit DACs: 0, 1 left; 2, 3 right | `SYS_SNDW` A = $10-$13 |

The writes are taken only while the classic machine is frozen (it is, whenever the desktop
is shown). The kernel silences AUDC1-4 and the DACs before the classic machine runs. Lau,
the 8-channel sample player (AU_* registers from $DB20, REV $0A), is reached through
SYS_SPLAY, SYS_SSTOP, SYS_SSTAT and SYS_SSET (Horizon 0.17). Details:
[sound.md](sound.md).

## Input

| Register | Address | | From a program |
| --- | --- | --- | --- |
| KB_ROUTE | $00:DE20 | 0: keys to Horizon, 1: to the classic machine | none (classic_show) |
| JOY_PORT | $00:DE21 | DB9 ports: bits 0-3 stick 1 (up, down, left, right), 4-7 stick 2, 1 = pressed | SYS_JOY (Horizon 0.15): A |
| JOY_TRIG | $00:DE22 | bit 0 trigger 1, bit 1 trigger 2 | SYS_JOY: X |

Keyboard and mouse come as events (WE_KEY, WE_BUTTON, WE_MOTION, WE_WHEEL); the joysticks
are polled with SYS_JOY (Horizon 0.15). The emulator reads both joystick registers as 0
(SYS_JOY's test aid can feed values). Keep input in one place (a "joy" bit mask in the DB9
layout, the keys ORed with the stick, as the game template does).

## Timers and interrupts

The kernel owns TIMER0 (the 10 ms scheduler tick), TIMER1, UPTIME (microseconds: programs
get milliseconds from `SYS_UPTIME`), the VBLANK and LINE interrupts and the watchdog
(2 s). Programs get time through `SYS_UPTIME`, `SYS_SLEEP` and `SYS_WTIMER`.

## Bare metal (no Horizon)

The I/O processor can also start a raw 65C816 program instead of Horizon: emu816
`PROGRAM.BIN` (loaded at $01:0000, entered in emulation mode), and on the board
`core/tools/atari.py run816 FILE` (sends it as /A816.BIN and restarts the 65C816 with it).
Such a program owns everything: video modes, the blitter, raster interrupts, the joystick
registers. No files, windows or multitasking unless it talks to the mailbox itself. This
SDK does not cover it; examples: `emu/tests/asm/nvcdemo.s` (palette, every blitter
operation, the pointer, VBLANK timing), `core/sw/a816/nvtest.s`, `sndnat.s`, `kbtest.s`.
