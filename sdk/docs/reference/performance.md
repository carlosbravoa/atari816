# Performance

How fast things are, to plan a game loop or a redraw. Emulator figures were measured for
this SDK with a probe program (`sdk/tools/probe/probe.s`: `make -C sdk probe`), emu816 at
14.34 MHz, a 400 x 300 window not covered by others (so it draws straight onto the screen).
"Board" figures come from Horizon's own measurements (horizon/README.md,
Docs/03-bringup1-log.md); the SDK author did not measure on the board.

## The CPU

- 14.34 MHz, one emulated cycle per bus access. A 5-cycle loop (`dex` / `bne`) ran
  3,276,800 cycles in 230-239 ms in the emulator (the rest is the kernel's tick and
  interrupts: about 3 %).
- **The board is slower than the emulator on CPU work: 1.6 to 2.3 times.** Every write goes
  through to SDRAM, cache misses cost, and the 8 bpp video fetch shares the bus. Measured:
  BASIC's self test 3.66 s on the board against 2.02 s emulated; the sieve 89.0 s against
  45.2 s; an empty FOR loop of 100,000: 4.0 s against 2.4 s; CPU window drawing about 2.3
  times. Plan with the emulator's figures x 2.
- MVN / MVP: 7 cycles per byte (about 2 MB/s emulated; about half that measured on the
  board in the bring-up simulation).

## Syscalls (emulator, REV $08)

| Call | Cost |
| --- | --- |
| `getpid` (the cheapest syscall) | 50 us |
| `sound_write` | 57 us |
| `win_draw`, any op, 1 x 1 pixel (the fixed cost of a draw call) | 170 us |
| `ws_sync` with nothing to show | 90 us |

On the board expect about twice these (CPU-bound kernel code). So: **a few hundred
win_draw calls per second at most**, whatever their size. A 50 Hz game has 20 ms per
frame: in the emulator about 100 small draw calls, on the board about 50; keep it under
20-30 and the game has room for its own logic.

## Drawing (win_draw), emulator

| Operation | With the blitter (REV $08) | CPU only (REV $07) |
| --- | --- | --- |
| fill 16 x 16 | 0.17 ms | 0.72 ms |
| fill 320 x 200 | 4.5 ms | 27 ms |
| blit 16 x 16 (WD_BLIT) | 0.22 ms | 0.80 ms |
| keyed blit 16 x 16 (WD_KBLIT) | 0.23 ms | 1.0 ms |
| blit 320 x 200 | 8.2 ms | 38 ms |
| keyed blit 320 x 200 | 8.3 ms | 124 ms |
| copy 320 x 200 inside the window (WD_COPY) | 8.3 ms | 41 ms |
| text, 20 characters, UI font, with paper | 0.67 ms | 4.9 ms |
| text, 20 characters, fixed font, with paper | 0.60 ms | 5.8 ms |

- With the blitter, a fill is about 14 million pixels a second and a copy about 7.7
  million (the blitter's own speed, which the board has too); small operations are all
  call overhead.
- Without the blitter (REV $07 boards, `--rev 7`) everything big is 5-15 times slower,
  keyed blits worst. The current board is REV $08.
- When another window covers yours, every op is drawn into your window's bitmap and the
  compositor copies the changed area to the screen a tick later: about twice the pixel
  work.

Horizon's own figures (`wdemo bench`, horizon/README.md): a full repaint of 640 x 360 with
three windows 15.7 ms with the blitter, 151 ms without; on the board, CPU drawing measured
434 ms for that repaint (2.3 x the emulator). With the blitter on the board: moving a
302 x 187 window one step 14 ms (176 ms on the CPU), a 60-character line 3.5 ms (24 ms).

## Draw lists against win_draw (Horizon 0.18)

Horizon's own measurement (`gtest m`, emulator, REV $0B): 100 keyed 16 x 16 blits a frame,
60 frames, a window not covered by others.

| | Syscalls a frame | CPU a frame |
| --- | --- | --- |
| 100 `win_draw` (WD_KBLIT) | 100 | 26.6 ms: more than a frame (16.7 ms), so frames are missed |
| one `draw_list` of 100 LS_KEY records | 1 | 14.4 ms in the call: checking and clipping, about 2,000 cycles a record |

While the call returns, Ali's own blitting (about 2.3 ms for the 100 blits) runs concurrently
with the CPU: the program computes the next frame meanwhile, and `vsync` (or `list_wait`)
waits for the list. So a list saves the per-call cost but not the per-record check: plan
with about 0.14 ms a record in the emulator, **about twice that on the board** (CPU work). A
frame of a scrolling game needs far fewer: `examples/deepdive` draws one column (12 records)
or row (21) of tiles every 8 frames and the panel's few letters when they change, and uses
about 1.8 ms of CPU a frame in all (every syscall included) in the emulator.

Sprites cost no CPU time and no blits at all: `spr_set` of 15 entries, or `spr_move`, once a
frame, and Marga draws them. Scrolling with `fs_scroll` is one call a frame whatever the
distance.

## What fits in a frame

At 50 Hz (20 ms), emulator, with the blitter (win_draw); halve the counts for the board:

| | |
| --- | --- |
| 16 x 16 sprites moved (put back the background + a keyed blit: 2 calls, about 0.45 ms) | about 40 |
| a 320 x 192 playfield redrawn from an off-screen picture (one WD_SBLIT) | 8 ms: once per frame is possible, not more |
| a full 640 x 344 "screen" from off-screen pictures (one bank holds 640 x 102: 4 blits) | about 30 ms: too slow for 50 Hz; redraw only what changed |
| CPU work: 14,000 cycles a millisecond | a 16 x 16 sprite composed by the CPU into a buffer (about 15 cycles a pixel): about 0.3 ms |
| draw list records (Horizon 0.18) | about 100 in 14 ms of CPU, Ali's blits running alongside: a few dozen a frame are comfortable |
| hardware sprites (REV $0B) | 16, no CPU time |

## Files

The I/O processor serves one request at a time; the emulator polls every 36 us and serves
at most one request per poll. On the board, reading a file runs at whatever the
PicoRV32 and the SD card give (not measured here). Load levels and pictures at the start
of a level, not during play.

## Console text

Characters per second on the text screen (emulator, BENCH): 7,647 plain, 5,241 scrolling.
The board's debug log (DBG_OUT, the PC link) takes about 90 us a byte.
