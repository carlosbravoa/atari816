# Porting notes: Micropolis (SimCity's source) to the Atari816

The port's log: the order of work, what was found, the SDK faults and wishes (each with a
reproducer), the measurements, and what is left. engine/FORK.md lists every change to
upstream's files.

## 1. The order of work

1. **Upstream vendored** (tools/vendor.sh: commit c98f6b0 of SimHacker/micropolis, the C
   tree `micropolis-activity`; 23 C files, 5 headers, the data). The Tcl/Tk front end not
   taken.
2. **The host build, headless** (`make host`): `port.h` instead of X11/Tcl, the engine's
   Tcl commands kept and sent to a front end (`port_eval`), upstream's missing functions in
   `hooks.c`, the strings compiled in, `simtest` (a city generated with a seed, loaded or a
   scenario; N ticks; a CRC-32 of the whole state every K ticks). Two twins: host32
   (upstream's types) and host16 (`tools/host16.py`: int -> short).
3. **host32 against host16** found the first 16-bit faults (the random numbers, the boats'
   distance), then **the Atari816 against host16** the rest (products that only overflow in
   16 bits, which host16 computes in 32: gcc promotes shorts) and the memory faults. All ten
   cases equal now, 5,000 ticks each (make test) and 20,000 (make test-long).
4. **The map view and editing** (`view.c`, `game.c`), then the panel, the windows, the app.
5. **Speed**: the profiler, assembly for the two hottest loops, a few C changes with the same
   results (the equality test checks every one).

## 2. Faults found in upstream (fixed; engine/FORK.md has each)

| Where | Fault | Seen as |
| --- | --- | --- |
| rand.c `sim_rand` | `SIM_RAND_MAX + 1` = 0 in 16 bits: a division by zero; a 0-65,535 result in an int | host16's random numbers all small (39, 28, 173 ...) |
| s_sim.c `Rand`, `Rand16`, seeds | unsigned values in int: negative random numbers; half of the seeds negative | (fixed with the above) |
| s_sim.c `GetBoatDis` | `dist = 99999` in an int | every drawbridge opened at once (host32 vs host16, tick 4) |
| s_eval.c `GetAssValue`; s_sim.c `CollectTax` | `PolicePop * 1000`, `PolicePop * 100`, `RoadTotal + RailTotal * 2` | the assessed value 65,536,000 less (the Atari816 vs host16 in Tokyo, tick 16) |
| w_budget.c | `(int)(FireFund * percent)` | (by reading: a fund over 32,767) |
| w_util.c, w_update.c | `year * 48`; `int megalinium = 1000000`; `%d` of a 32-bit value | (by reading) |
| s_eval.c `VoteProblems` | reads (and may count a vote in) `ProblemTable[10]` of 10 | a result that depends on the memory layout |
| s_eval.c `GetUnemployment` | a float out of a short's range to a short | (undefined in C) |
| s_fileio.c | `*(QUAD *)(MiscHis + 50)`: 32-bit values read through a cast, the machine's byte order and alignment | (the file format rewritten word by word) |

## 3. Faults of the port found by the tests

- **A heap of 6 KB**: one sprite's `malloc` returned NULL, upstream wrote the train at
  address 0: the train vanished and the random numbers parted from the PC's at the next rail
  tile (Tokyo, the first MapScan). Found in 30 minutes by tracing the random state per map
  tile on both machines. Fix: the histories in far memory, a check of every malloc
  (`port_fatal`).
- **host16.py** turned `unsigned QUAD` (QUAD: a macro for long) into `unsigned short`: the
  generator's state was 16 bits on the PC. Fixed in our copy (QUAD a type word). The same
  fault is in ports/xcom/tools/host16.py for `unsigned` before any typedef or macro.
- The game's first tool test replayed the drag with the wrong tool: the log now has the tool
  of every call (down, drag, up), and simtest replays them exactly.

## 4. SDK faults and wishes

Each with a reproducer that fails today (run on the fast machine, Horizon 0.30, the tree
of 24 November 2026).

1. **cc816 has no implicit int** (C89 code). Upstream's 248 functions without a return type
   (`SimFrame(void) { ... }`) had to be given one; K&R parameter lists are accepted.
   ```c
   /* kr.c */
   foo(void) { return 3; }
   int main(void) { return foo(); }
   ```
   `hcc -c kr.c`: `error: the function 'foo' has no return type: write 'int foo(...)' (C99
   has no implicit int)`. Wish: `-fimplicit-int` (or `-std=c89`) for old code, as gcc's
   warning. **Done since**: `-fimplicit-int`, `-std=c89` (as warnings).
2. **hgame's scrolling map takes byte tiles only** (`hg_map`: at most 256 tiles, tiles as an
   image's frames one under the other: at most 64 tiles of 16 x 16 within a sheet's 1,024
   rows). Micropolis has 960 tiles in 16-bit map words. The port has its own ring
   (`view.c`) and calls `hz_fs_scroll` itself: hgame has no way to set the vertical wrap
   (`vheight`) and horizontal wrap with a split (`hg_scroll`/`hg_split` refuse a view past
   the framebuffer's edge). Wishes: `hg_map16(map, mw, mh, img, tw, th, panel)` with tiles
   drawn by `hg_draw_part` from a wide sheet, and `hg_scroll_wrap(x, y, vheight)` with the
   split; or a tile callback.
   **Done since** (hgame, `sdk/docs/c/games.md`): `hg_map16`, `hg_map_cells` (the callback),
   `hg_scroll_wrap` / `hg_split_wrap`; the port still uses its own `view.c`.
   Reproducer: `hg_image_from(px, 16, 16, 960, HG_NONE)` makes an image without a sheet
   (960 x 16 rows > 1,024: every blit from it the slow `draw_list` path), and
   `hg_map(m, 120, 100, tiles, 48)` reads `m` as bytes: tiles 256-959 cannot be named.
3. **hgame's hardware sprites at 4 bpp all use palette bank 0** (`hg_sprite.c`:
   `tab[n].pal = 0`): eight kinds of moving things with their own 15 colours each need
   banks 8-15. The port uses `hz_spr_alloc`/`hz_spr_set` directly. Wish:
   `hg_sprite_pal(n, bank)`. Reproducer: a 4 bpp image whose colours are 129-143 shows
   entries 1-15. **Done since**: `hg_sprite_pal(n, bank)`.
4. **The main bank is the limit** (as for every big port): MICROPOL.PRG's fixed part is
   54.5 KB (code that must stay 10.4 KB, constants 14.1 KB, data 5.2 KB, bss 24.9 KB) with a
   heap of 5 KB and a software stack of 5 KB. hgame's record queues are 4.6 KB of it
   (`hg__dq` 2,560, `hg__sq` 2,048). Wishes: hgame's queues in far memory or sized by the
   program; `hcc --sizes` printed also when the link fails (now it says only "does not fit
   ... by N bytes"; one has to link with `--stack 512 --heap 512` to see the list).
   **Done since**: the queues are in far memory (4.5 KB of the main bank back), and `hcc
   --sizes` also prints when the link fails for size.
5. **The shell cuts a long argument line**: `run816.py --mode shell --args` with a line of
   about 80 characters gave the program a last argument cut short
   (`... save /APPS/OUT.CTY` arrived as `/APPS/OUT`). Reproducer:
   `run816.py SIMTEST.PRG --mode shell --args "seed 7 load /APPS/KOBE.CTY speed 0 ticks 0 save /APPS/OUT.CTY" --file engine/cities/kobe.cty:/APPS/KOBE.CTY`:
   the card has `/APPS/OUT`. (Not looked into: the shell's line buffer or run816's typing.)
   The tests use shorter names.
6. **A note for the docs**: a full-screen game that sets its whole palette with
   `hg_palette(16, 240, ...)` after its own `hg_color` calls loses them (obvious once seen:
   the panel's text was black on black for one run).
7. **`-Wframe-larger-than`** says "the software stack is 8,192 bytes" at compile time even
   when the program links with `--stack 5120` (the compiler cannot know): it could say "the
   default".

## 5. Speed (the emulator, which models the board within about 5 %)

One tick = upstream's `sim_loop` once (SimFrame: a sixteenth of a simulation pass at the
fast speed; MoveObjects; a quarter of the map's tile animation; DoUpdateHeads). Measured
with SIMTEST.PRG (no screen), 1,000 ticks:

| City | ms a tick | a pass (16 ticks) | a game month (4 passes) |
| --- | --- | --- | --- |
| generated, a small city laid by the tools | 50 | 0.8 s | 3.2 s |
| Tokyo (scenario, 226,000 people) | 106 | 1.7 s | 6.8 s |
| Kobe (306,000 people, dense traffic) | 141 | 2.3 s | 9.0 s |

In the game at the fast speed: Tokyo 86-90 ms a tick (the log's "ms a tick"); the game runs
one tick a frame (16.7 ms) when it can, so about 10 ticks a second in Tokyo; medium and slow
run a tick every other frame and upstream's SimFrame simulates only every 3rd / 5th of them.

Where the time went (the profiler, Kobe) and what was done:

| | before | now |
| --- | --- | --- |
| `animateTiles`, the whole map each tick, in C: 140 cycles a tile | 104 ms a tick | assembly (fast.s), a quarter of the map a tick: about 17 ms |
| the random numbers: `__mul32` in `sim_rand`, a divide and a multiply in each `Rand` | 42 ms | `sim_rand` in assembly (byte tables, 100 cycles), `Rand`'s limit kept: about 6 ms |
| the CRC of the state (tests only) bit by bit | | a table |
| the power map's bit `1 << (x & 15)` (a shift loop) | | a table |

Total: Kobe 223 ms -> 141 ms a tick, Tokyo 150 -> 106, a small city 67 -> 50. What is left
(Kobe, per tick): MapScan 19 ms, the traffic search (TryDrive, TryGo, DriveDone,
GetFromMap) about 30 ms, the power scan (DoPowerScan, TestForCond, MoveMapSim) about 20 ms,
SetZPower 9 ms, the smoothing of the density maps (DoSmooth, DoSmooth2) 6 ms: the next
candidates for assembly, each checked by the equality test. The emulator's memory model
makes C cost about 10 cycles an instruction; the animation loop still takes about 80 cycles
a tile in Kobe (many animated tiles).

Memory: MICROPOL.PRG 173 KB on the card; far memory at run time about 1.3 MB: the maps,
histories and power stack one bank (61 KB used), the framebuffer 7 banks (656 x 696), the
tile sheets 5 banks, the sprites 2 banks, the overview's and the graph's images 3 banks,
the view's slot table 1, the sounds as played (Lau). `--needs mem=2048K`.

## 6. What is left

- The simulation is about 2-3 times slower than one would like in big cities (above).
- Sounds: the tool sounds and the city's (explosions, sirens, traffic, monster) on Lau; the
  palette names of upstream's tools (res.wav ...) are not played.
- Not done: the graph of money and the 120-year view are drawn but not labelled with years;
  the evaluation window has no "Get report" history; chalk and the eraser (upstream's X-only
  drawing tools); the network/multi-player parts; printing; the "priority" setting.
- The traffic sprites (bus) upstream never generates (as upstream).

## 7. Time

About 9 hours: the engine on the PC and the equality on the Atari816 3 h, the front end
4 h, speed 1 h, tests and notes 1 h.
