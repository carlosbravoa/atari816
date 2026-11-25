# Performance

Measured costs, for planning a game loop or a redraw. Emulator figures: the probe program
`sdk/tools/probe/probe.s` (`make -C sdk probe`), emu816 at 14.34 MHz, a 400 x 300 window
not covered by others (so it draws straight onto the screen). "Board" figures come only
from Horizon's own measurements (horizon/README.md, Docs/03-bringup1-log.md).

## CPU

- **emu816 runs at the board's speed** (Horizon 0.19 and later; emu/README.md, "Memory
  timing"):
  it models the 65C816's 4 KB cache (a read miss costs about 6 cycles), the SDRAM stall of
  every write (about 4 cycles, 5 with the desktop's video on, 9 with the classic machine
  running), Marga's line fetch, the cache sweep of every mailbox reply and Ali's measured
  speed. Measured loops of every kind of access agree with the board within about 5 %; the
  BASIC sieve takes 89.2 s on the board and 87.9 s in emu816. **Plan with the emulator's figures
  as they are.** `--ideal-timing` gives an ideal model (one cycle per bus access, about twice as
  fast: the sieve 45.9 s); the figures below that were measured with it are marked "ideal".
- A 5-cycle loop (`dex` / `bne`, no memory access) runs at the same speed in both: 3,276,800
  cycles in 230-239 ms (the rest is the kernel's tick and interrupts: about 3 %).
- Write-heavy code is slowest: a direct-page store loop runs at 0.41 of the ideal speed
  with the desktop's video on, a loop of long reads that always miss at 0.53, a sieve in
  assembly at 0.80. MVN / MVP: about 13 cycles a byte on the desktop (7 ideal).
- (Horizon 0.18 and older firmware: the board was 1.6 to 2.3 times slower than the ideal
  model; 10-20 % of that was the I/O processor polling the mailbox from SDRAM, removed in
  later firmware.)

## Syscalls (emulator, REV $08, ideal timing)

| Call | Cost |
| --- | --- |
| `getpid` (the cheapest syscall) | 50 us |
| `sound_write` | 57 us |
| `win_draw`, any op, 1 x 1 pixel (the fixed cost of a draw call) | 170 us |
| `ws_sync` with nothing to show | 90 us |

On the board (and in emu816 with its default timing) expect about twice these (CPU-bound kernel code).
So: **a few hundred win_draw calls per second at most**, whatever their size. A 50 Hz game
has 20 ms per frame: about 50 small draw calls; keep it under 20-30 and the game has room for
its own logic, or use sheets (games.md).

## Drawing (win_draw), emulator (ideal timing: about twice as fast as the board)

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
  keyed blits worst. The default board build is REV $0D.
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

- 100 `win_draw` (WD_KBLIT): 100 syscalls a frame, 26.6 ms of CPU a frame: more than a
  frame (16.7 ms), so frames are missed.
- One `draw_list` of 100 LS_KEY records: 1 syscall, 14.4 ms in the call: checking and
  clipping, about 2,000 cycles a record.
- (Horizon 0.19) one `draw_list` of the same: 1 syscall, 13.8 ms (exactly, below: 1,284
  cycles a record).
- (Horizon 0.19) one `sheet_draw` of the same, from a sheet: 1 syscall, 4.0 ms (exactly:
  318 cycles a record).

`uptime` counts in 10 ms ticks, so these per-frame figures are rough for short calls. Measured
exactly (Horizon 0.19, `gtest m`: 500 calls of 100 records, and 2,000 calls of one, each followed
by a loop measured alone): a `draw_list` call of 100 records takes 9.1 ms of CPU (10.0 ms in
0.18), one of a single record 272 us; a `sheet_draw` call of 100 records 2.46 ms, one of a single
record 265 us. So about 90 us (1,300 cycles) a draw_list record and 22 us (320 cycles) a sheet
record, plus about 0.27 ms a call. Fills, SH_TABLE records and records cut at an edge take
the fast path too; with the board's timing (emu816's default, `gtest t`) a sheet
record costs about 31 us, 35 beyond 16 x 16, 51 cut at an edge, and one into a covered window
(the full path) about 150 us (ABI.md, "Sheets").

After the call returns, Ali's own blitting (about 2.3 ms for the 100 blits) runs concurrently
with the CPU: the program computes the next frame meanwhile, and `vsync` (or `list_wait`)
blocks until the list is done. So a list saves the per-call cost but not the per-record check: plan
with about 0.14 ms a record in the emulator, **about twice that on the board** (CPU work). A
frame of a scrolling game needs far fewer: `examples/deepdive` draws one column (12 records)
or row (21) of tiles every 8 frames and the panel's few letters when they change, and uses
about 1.8 ms of CPU a frame in all (every syscall included) in the emulator.

Sprites cost no CPU time and no blits at all: `spr_set` of 15 entries, or `spr_move`, once a
frame, and Marga draws them. (Horizon 0.24) Each syscall still costs about 0.1 ms on the board:
move many sprites with one `spr_move` (A = $8000 | count, a table), and only those that moved
by a pixel. The screen saver moves 16 sprites so for about 1.5 ms of CPU a frame in all. Scrolling with `fs_scroll` is one call a frame whatever the
distance.

## Many small fills (Horizon 0.30)

A road made of spans, a polygon's scan lines: hundreds or thousands of short horizontal
runs a frame. Measured by `sdk/c/game/tests/gt_runbench.c` (emu816, board timing, 320 x 180,
2,000 runs at scattered places; CPU cycles a run until the program has the CPU again; the
blitter's part runs meanwhile):

- A C loop through a `__far` pointer: 1,700 (23 pixels).
- hgame's CPU path (assembly: 16-bit stores): 420 (8 pixels), 610 (23), 1,550 (100).
- SkyRoads' unrolled assembly (a jump into 127 16-bit stores; ports/skyroads): about 260
  (23 pixels).
- `hg_fill` records (`sheet_draw` fills, 128 a call): 3,400 (23 pixels).
- One call a run (`hg_fill` + `hg_flush`): 10,000 (23 pixels).
- `fill_runs` (`hg_fill_runs`: one call for all of them): 138 (8 pixels), 140 (23), 175
  (100; done: 210).
- `fill_runs` groups of 20 (`hg_fill_groups`: the runs read where they are): 170 (23
  pixels).
- `fill_runs` groups of 2: 300 (23 pixels).

`fill_runs` (ABI.md, "Fill runs") checks the page once and each run with one compare and
writes five bytes of Ali's record for it: about 140 cycles a run, a third of it the SDRAM's
write stall, whatever the run's width; a call itself about 0.35 ms (RTEST m: one run 440 us with the clock call around it). Ali fills a 23-pixel run
in about 70 cycles, so it keeps up with the kernel (the pixels are there about 300 us after
the call returns); 100-pixel runs take Ali longer than the kernel (done 4.6 ms after the
call). The first call of all takes the kernel's list bank (about 25 ms, once).

So the blitter takes runs at about half the cost of a tight assembly fill of 23 pixels,
and the pixels at no CPU cost; the CPU cost of each run remains. Effect in a real program: SkyRoads (ports/skyroads, PORTING-NOTES.md, "Horizon 0.30") draws its road's
700-900 spans a frame through groups and gets 7 % more frames at the game's speed (730 of
1,708 against 685), its drawing 11 % faster on average and 16 % in its busy stretch (37.2
against 44.5 ms a frame; the worst frame there 42 against 57): its spans are short and its
own assembly was already tight. A hardware
run-list mode that read the runs directly would remove the kernel's part (ABI.md, "For a
later hardware revision").

## Frame budget

At 50 Hz (20 ms), emulator, with the blitter (win_draw); halve the counts for the board:

- 16 x 16 sprites moved (put back the background + a keyed blit: 2 calls, about 0.45 ms):
  about 40.
- A 320 x 192 playfield redrawn from an off-screen picture (one WD_SBLIT): 8 ms: once per
  frame is possible, not more.
- A full 640 x 344 "screen" from off-screen pictures (one bank holds 640 x 102: 4 blits):
  about 30 ms: too slow for 50 Hz; redraw only what changed.
- CPU work: 14,000 cycles a millisecond. A 16 x 16 sprite composed by the CPU into a
  buffer (about 15 cycles a pixel): about 0.3 ms.
- Draw list records (Horizon 0.18): about 100 in 14 ms of CPU, Ali's blits running
  alongside: a few dozen a frame are comfortable.
- Hardware sprites (REV $0B): 16, no CPU time.

## Files

The I/O processor serves one request at a time; the emulator polls every 36 us and serves
at most one request per poll. On the board, reading a file runs at whatever the
PicoRV32 and the SD card give (not measured here). Load levels and pictures at the start
of a level, not during play.

## Console text

Characters per second on the text screen (emulator, BENCH): 7,647 plain, 5,241 scrolling.
The board's debug log (DBG_OUT, the PC link) takes about 90 us a byte.
