# Porting notes: SkyRoads on the Atari816 (phase 1: road-pass experiment)

SkyRoads (Bluemoon Interactive, 1993), from Carlos Bravo's C++17 reimplementation
[SDL-skyroads](https://github.com/carlosbravoa/SDL-skyroads) (MIT; about 7,500 lines:
`src/data` loaders and the LZ decoder, `src/core` the integer ship simulation and the app's
state machine, `src/renderer` the 320 x 200 software renderer of the DOS TREKDAT span
pipeline, `src/audio` the OPL2 driver on ymfm). The plan had two phases: first measure
whether the 65816 can draw the road fast enough; port the whole game only if it can reach
at least about 80 % of the original frame rate.

**Round 2 (below, "Speed, round 2"):** the simulation 10.6 -> 2.0 ms a tick (worst 100 -> 12.6),
the drawing 35 -> 28.4 ms a frame (the busy stretch 37.8 -> 31.1), the load 32 -> 4.1 s, every
frame still identical. Shown on a steady beat the demo holds **24 frames a second** through its
busiest stretch with no late frame (50 late of 1,114 over the whole demo, in its two heaviest
spots); an adaptive beat holds 24 for 80 % of the demo and 18 for the rest (8 late frames).
36 frames a second stays out of reach without Ali reading the runs itself.

**Result of phase 1: it cannot.** With every acceleration tried below, the attract demo drawn at the
game's speed gets a frame for 685 of its 1,708 ticks: **40 % of the original 36 frames a
second (about 14.5)**, the game logic itself at full speed. The drawing is pixel-exact
(all 1,708 demo frames equal the C++'s), but the CPU cost of a frame is about 33 ms of
drawing plus 10 ms of simulation against a 27.8 ms tick. The work stopped after phase 1,
as agreed; what would be needed is at the end ("Requirements for full speed").

## Game rate

The C++ runs the simulation at 36 Hz (`SIMULATION_HZ_DEFAULT = 36` in
`src/platform/main.cpp`; `core/app.cpp`: "PIT divisor 0x19E4 = 180.02 Hz, and the tick
counter ds:0x160c is bumped on 2 of every 10 interrupts" = 36.0 Hz) and draws one frame per
tick. The target is therefore 36 frames a second, 27.8 ms a frame; 80 % is 28.8 frames a
second.

## Data and licence terms

Bluemoon's page (http://www.bluemoon.ee/history/skyroads/) offers `skyroads.zip`
("Download skyroads.zip (580 Kb, full)") without any licence text on the page. The zip's
`readme.txt` says: "This program is freeware. You can distribute this program freely, as
long as you don't reverse engineer, and/or modify this program or any of its accompanying
files. This program must be distributed as a single unit, with all accompanying files
included and intact in their original form." So the port distributes none of it:
`tools/getdata.sh` downloads the original zip from Bluemoon (sha256 `24762fe1...03ee4`,
593,740 bytes) or takes the user's copy; `make data` decodes it on the user's machine into
`data/card/` (gitignored). Note that the readme forbids reverse engineering and
modification; the upstream C++ is itself built on reverse engineering of the EXE (and
ships tables taken from it), so this is a question for the project's owner rather than for
the port.

## What was built

- `src/`: the C translation (C99, cc816 and gcc alike) of upstream's `data/` (all loaders
  but `exe`), `core/` (`gameplay`, `app`, `dos_render_tables`, `dos_font`) and `renderer/`
  (all scenes but the debug views): one `.c`/`.h` per `.cpp`/`.hpp`, upstream's names,
  structure and comments; the C-specific changes are marked "C:" in the comments. Not yet
  translated: `audio/` (the OPL2 driver), `planner`, `cli`'s `summary`.
- `src/platform.h`, `src/sr.h`: the small platform interface (files, far memory, fills and
  copies, a random byte).
- `host/`: the PC back end (`host_plat.c`) and `srtool` (`cli_main.c`): `demo-sim`
  (upstream's CLI text), `demo-frames` (every demo frame, pure or incremental path),
  `predecode`, `probecheck`.
- `horizon/`: the Horizon back end: `hz_plat.c` (far memory, files, the pre-decoded
  streams), `hz_video.c` (three pages, flips, palette, the blitter), `hz_spans.s`,
  `hz_road.s`, `hz_probe.s` (assembly fast paths), `hz_main.c` (`/BENCH`, `/PACED`,
  `/CHECK`).
- `tools/getdata.sh`, `tests/framesum.py`: the data; the frame checksums.

### Verification

- **The C translation against the C++, on the PC**: `srtool demo-sim DIR 2000` prints the
  very lines of upstream's `skyroads-cli demo-sim` (identical, 2,000 frames);
  `srtool demo-frames` writes every frame of the attract demo (the intro let run out, as
  upstream's app does), 64,000 pixels and the palette: identical to the C++'s (a dumper
  built against upstream's libraries, `ref_frames.cpp`, kept in the agent's scratch) for
  all 1,708 frames, by the pure path and by the incremental one.
- **The Atari816 against the PC**: `make check` draws the demo on the 816 (emulator),
  prints a checksum of each frame's pixels and palette, and compares them with the PC's:
  **1,708 of 1,708 frames match**, through every fast path below. One frame was also
  dumped and compared byte for byte (`/DUMP:n`).
- `srtool probecheck`: the 16-bit collision probe against upstream's 32-bit one at 4
  million random points on all 31 roads: no difference.

## Road-pass experiment

Measured in the emulator (emu816 models the board's timing within about 5 %), Horizon
0.29, the attract demo (road 0, 1,708 ticks). `make bench` times each demo frame's
simulation tick and drawing, each repeated 10 times (`hz_uptime` has 10 ms steps);
`make paced` plays the demo at 36 ticks a second and counts the ticks that get a frame of
their own; profiles: `run816.py --prof`, `prof816.py --counts`.

The road's load, from the C translation on the PC: **718 spans and 16,689 pixels a frame
on average, 2,118 spans and 41,360 pixels at most** (spans a frame: frames 0-300 625,
300-700 646, 700-1100 872, 1100-1708 709; pixels 14.6 K, 8.5 K, 24.1 K, 18.2 K).

Each step on top of the ones before, with the simulation (ms a tick) and the drawing (ms a
frame):

1. First version: the C translation as it is; the spans in assembly (`hz_spans.s`, a jump
   into 127 unrolled 16-bit stores), copies from the underlay by the blitter, the dashboard
   by the blitter: 60, 305.
2. 16-bit divides by 46 from a table (the cell probes): 8, 241.
3. The dashboard band kept and changed only where a gauge segment or a label changes (the
   gauges cost 4,000 `set_pixel` calls a frame): 8, 57.
4. The ship's sprite by an assembly keyed copy: 8, (in the above).
5. The road pass's shapes collected and drawn by one assembly call; the cells' bytes from
   near copies: 8, 41.
6. 32-bit divides by constants replaced (exact shifts and 16-bit divides); Ali restores the
   band while the CPU works out the shapes: 8, 34.

Until here the bench ran on a corrupted level: a 3.7 KB structure returned by value had
overflowed the 4 KB software stack into the heap; the numbers above are relative, the ones
below are right.

7. The cell dispatch (`draw_dos_pointer_row` and the six `draw_dos_type_N`) in assembly
   (`hz_road.s`): 7-28, 31-47.
8. `level_get_cell_128` (no `x * 512`), the shadow's mask without `1u << col`, the pointer
   row read in place: 7-30, 31-53.
9. The collision probe in 16 bits (exact; 32-bit fallback), the span filler driven by a
   width table: 2-18, 26-51.
10. The probe and the shadow in assembly (`hz_probe.s`): 2-17, 26-48.

**Paced, the whole demo at 36 ticks a second** (`make paced`): 1,708 ticks, 685 frames
drawn (40 %); simulation and scene 11.6 ms a tick, drawing and showing 41 ms a frame
(`hz_uptime`); the blitter made the CPU wait 0.5 s in all (1,370 waits).

Where a frame goes (profile of the paced demo, 40 s: 582 frames drawn, 1,440 ticks):

Drawing, per frame:

- the spans (`hz_span_jobs`: 225,000 cycles): 15.7 ms
- the cell dispatch (`hz_road_row`): 5.0 ms
- the C around them (rows, passes, scene, ship placement, palette compare): 5.5 ms
- the kernel's sends and waits (`sheet_draw`, `list_wait`, `fs_scroll`): 2.7 ms
- the ship (`hz_keyed`) and its shadow (`hz_shadow`): 2.4 ms
- in all, with the kernel's share: about 33 ms

Simulation, per tick:

- the collision probe (`hz_inside_tile` and its C wrapper): 4.0 ms
- `move_to`, `handle_bounce`, `interp`: 2.4 ms
- 32-bit multiplies and divides (`__mul32`, `__udiv16`, ...): 1.8 ms
- the scene for the renderer (`build_play_scene`): 0.6 ms
- the rest of the tick: 1.2 ms
- in all: about 10 ms

**Why it cannot reach 80 %.** In a second the game makes 36 ticks (360 ms of simulation)
and the frames share the rest: 640 ms / 33 ms = 19 frames at best, 14.5 measured (the
ticks that pile up behind a late frame run before the next one). Reaching 29 frames needs
about 20 ms a frame with the simulation as it is, or 26 ms with the simulation cut to 4 ms
(more assembly: plausible). The spans alone take 15.7 ms on average and 25-30 ms in the
demo's busiest stretch (frames 700-1100: 24,100 pixels and 872 spans a frame on
average): the CPU fills about 1.5 million pixels a second there (16-bit stores at about 11
cycles each with the SDRAM's stall, and about 90 cycles a span to set up). Even with
everything else made free the busy stretches stay under 70 %; the average with all the
further software work I could see (simulation in assembly, the C glue trimmed) is about
70-80 %, the busy parts about 60 %.

**What was tried that did not help, or cannot:** the blitter for the spans: a fill record
costs the kernel about 1,100 cycles (games.md, performance.md), the spans average 23
pixels (about 200 CPU cycles): only spans over about 120 pixels would gain, and mixing
blitter and CPU spans in one pass needs a wait for every change of side (spans of the same
row overlap, in order). Pre-drawn shapes as 1-bit masks expanded by Ali in their colour:
300-700 shape draws a frame at about 320 cycles of kernel time each (a sheet record) is
15 ms, no better than the CPU. MVN for long spans: 12 cycles a byte against about 5.5 for
the 16-bit stores.

## Requirements for full speed

1. **Many fills in one request to Ali.** The whole road is a list of 700-2,100 runs
   {offset, width, colour} in one 64,000-byte page. A kernel record (or a direct user-mode
   command list for the program's own framebuffer) that fills such a list, validated once
   for the page's bounds instead of per record, with Ali's per-run cost small, would take
   the 15.7 ms of span filling off the CPU (Ali fills about 14 million pixels a second:
   16,700 pixels is 1.2 ms of Ali, 41,000 is 3 ms). The CPU would build the list
   (`hz_road_row` already does: 5 ms), the frame would cost about 17 ms, and 36 frames a
   second would hold with room. This is the one change that determines whether the port is viable.
2. Short of that: a faster CPU write path to SDRAM (a write buffer that hides the
   4-5-cycle stall per store), or a faster CPU, would help in proportion, but not 2x.
3. cc816 code for 32-bit and small-int arithmetic (the simulation): see the SDK wishes
   below; worth 4-6 ms a tick here.

## Horizon 0.30: spans through fill_runs

Horizon 0.30 added the call requested in "Requirements for full speed" 1: `fill_runs` ($A4, horizon/
ABI.md "Fill runs"), many runs in one request, the page checked once, each run with one
compare, Ali filling them while the kernel makes the rest; and its groups (FR_GROUPS): a
program's own span arrays, each drawn in one colour, read where they are. The port now sends
each road pass as one call: a job is a group, its shape's own `PreparedSpan` array
{left, right, width} (stride 5, the offset at 0 or 2, the width at 4) in the job's colour
(`hz_span_groups` in `hz_spans.s` writes 8 bytes a job, `hz_video.c` sends them with
hgame's `hg_fill_groups_at`; `plat_alloc` keeps objects below offset $FF00 of a bank, where
the kernel reads groups). `/NORUNS` (or a Horizon without the call) keeps the CPU's spans.
`make check`: 1,708 of 1,708 frames identical.

0.29 (the CPU's spans) against 0.30 (fill_runs groups):

- `make paced`, frames drawn of 1,708 ticks: 685 (40.1 %) against 730 (42.7 %).
- `make bench`, drawing a frame, frames 1-1481, average / worst: 39.1 / 62.0 ms against
  34.7 / 58.0 ms.
- The busy stretch, frames 700-1099, average / worst: 44.5 / 57.0 ms against
  37.2 / 42.0 ms.
- Simulation a tick: 11.4 ms against 11.5 ms.

(`make bench` runs 900 emulated seconds: 0.29 reached frame 1481 of the demo, 0.30 frame 1617;
the compiler as in git at the time, the same for both. A first version that copied every
span into a 4-byte run, `hz_span_runs`, then one `hg_fill_runs`: 708 frames, 36.6 / 64.0 ms,
busy 39.5 / 46.0 ms.)

**Why it is not the 2x hoped for.** The kernel's floor is about 140 CPU cycles a run (it
writes five bytes of Ali's 24-byte command record for each, with the SDRAM's stall on every
byte; measured by `sdk/c/game/tests/gt_runbench.c`), about 150 for a group's element plus
a few hundred a group (its record, its bank and layout compared with the group before). The
road's spans average 23 pixels and come two or three to a job, and this port's own span
filler was already tight (a jump into unrolled 16-bit stores: about 260 cycles a span of 23
pixels): so a span still costs the CPU about as much bookkeeping as filling it did, and only
the pixels went away. That is why the busy stretch (wider spans: 27 pixels on average, up to
2,100 a frame) gains most, and the average a tenth. The drawing is still about 35 ms a frame
against the 20 the target needs. What
would close the gap is the hardware feature in ABI.md, "For a later hardware revision": Ali
reading the runs (or the groups' elements) by itself from the program's memory, with the
page as a bound it enforces, so the kernel does nothing per run.

## Speed, round 2

Five steps on the port alone (no hardware, no SDK change), every frame still the same: `make
check` compares all 1,708 demo frames (pixels and palette) **and the whole simulation state
after every tick** (`srtool demo-state`, `/CHECK`'s `s` lines) with the PC's; and the PC build
is compared with golden files made from commit 2784ebf (the frames by the incremental and the
pure path, the state, `demo-sim`'s text): all identical after every step.

Measured in emu816 (Horizon 0.30). `make bench` now times each tick and each frame once with
`hz_uptime_us` (the old bench repeated everything 10 times with a 10 ms clock); "draw" includes
building the render scene since step 1 (`app_tick` split in `app_tick_logic` + `app_scene`, the
scene made only for a tick that is drawn). `make sim` (`/SIM`) times the demo's ticks alone
(its average without the clock's own 0.1 ms a reading). Busy = demo frames 700-1099.

Each step on top of the ones before. Sim = simulation ms a tick (average / worst); runs =
runs a frame (busy); draw = draw ms (average / worst); busy = busy stretch ms (average /
worst); paced = `make paced` frames of 1,708; load = load s. Values not listed were not
measured at that step.

- Before (commit 2784ebf, the new bench): sim 10.6 / 100.6; runs 718 (872); draw
  35.1 / 61.2; busy 37.8 / 42.8; paced 801; load 32.0.
- 1. The simulation (below): sim 2.0 / 12.5; runs 718 (872); draw 36.1 / 62.4; busy
  38.8 / 43.7; paced 1,165; load 33.
- 3a. Road glue: the scene's rows by index, the palette copied and compared only when it
  changes, no clock in every blitter wait, no wait before a pass, a cell that draws nothing
  passed over first: sim 2.0; runs 718 (872); draw 34.2 / 60.3; busy 36.9 / 41.7.
- 3b. The level's rows read where they are (no copy of 12 rows a frame): sim 2.0; runs 718
  (872); draw 32.9 / 59.3; busy 35.6 / 40.5.
- 3c. A whole pass in assembly (`hz_road_pass`): its pointer rows, cells and shapes, the
  fill_runs groups written straight (no jobs, no `hz_span_groups`): sim 2.0; runs 718
  (872); draw 30.0 / 54.9; busy 32.1 / 36.5.
- 3d. Both passes worked out before the first is sent: sim 2.0; runs 718 (872); draw
  29.6 / 56.7; busy 32.1 / 36.9; paced 1,425.
- 5. The load (below): sim 2.0; runs 718 (872); draw 29.6 / 55.6; busy 32.0 / 37.0; load
  4.1.
- 3e. The frame's blits in fewer calls (the ship's restore with the band's, the
  dashboard's copy with its art): sim 2.0; runs 718 (872); draw 28.7 / 54.8; busy
  31.1 / 35.7; paced 1,462.
- 2. Spans merged: the centre tile's two halves as one group (below): sim 2.0 / 12.6; runs
  668 (844); draw 28.4 / 54.4; busy 31.1 / 36.2; paced 1,469; load 4.1.

(The worst frame, 1301, is one whose dashboard gauges change; frames 450-500 draw 2,118 runs
and take about 50 ms.)

### 1. Simulation: 10.6 -> 2.0 ms a tick

Profiled with `make sim RUNFLAGS="--prof ..."`. Where the 10.6 ms went: the collision probe
(32 a tick: its C wrapper's 32-bit range tests and the assembly probe, about 1,200 cycles a
probe), `move_to`'s own 32-bit code, `__mul32`/`__udiv16`/`__udiv32` (interp's `* fifths / 5`
with the divisor a variable, the fuel's `0x7530 / fuel` every tick, the demo's `z / 0x666`
twice a tick), the scene for the renderer every tick, and 25 small calls a tick (cc816 inlines
nothing). The **worst tick (100 ms, tick 559) is the jump-o-master** (`run_jump_o_master`): at
the top of a jump it flies up to 25 variants of the trajectory to the ground, about 40 steps
each, a 32-bit multiply a step.

What was done (src/core/gameplay.c, src/data/level.c, horizon/hz_probe.s, horizon/hz_sim.c):
- The probe counted per tick (a PC instrument): interp 3, the z walk 12.9, the y walk 1.8, the
  bounce's two scans 14.2. **The z walk in strides**: the probe depends on z only through z's
  row, so the steps that stay in z + gran's row are taken at once (exactly the step loop's end
  point); a row requested twice is not probed again. **The bounce's scans in the band** (y - 1 in
  0x1E80..0x2800, where a probe is "inside unless both side cells are empty"): whole units and
  a per-row mask of non-empty cells (`Level.row_mask`).
- **`move_to` in 16 bits** (`gameplay_move16_c`) when every point it probes lies in the 16-bit
  probe's range (both ends' x in 6272..57855, y in -20000..32767, z moving forward by at most
  65,535): `trunc(d * k / 5)` as `a * k + floor(b * k / 5)` with `d = 5a + b` (one divide by 5 an
  axis, a 30-entry table), the walks on 16-bit positions. In assembly as `hz_move16` (and the
  bounce's scan as `hz_scan16`), the probe's core a subroutine (`pcore`) reading a byte a cell
  (`Level.cell_bits`: not empty, tunnel, cube, its height; the row's 8th byte records whether it has
  any tunnel or cube at all) and near tables (unit -> column, -> tile start).
- The level's constants once (`Level.gravity_acc_128`, `.oxygen_dec`, `.fuel_q`); the fuel's
  product kept while the velocity stays; the turn's `x_movement_base * motion_vel` by the
  constant 0x1D; the demo input's `z / 0x666` kept from the tick before; `gameplay_step` (the
  demo's tick without the result it does not use); `ship_update`'s 13 small steps written out
  in it, in their order.
- **The jump-o-master**: the number of steps to the ground is the same for every variant (y
  does not depend on x or z): counted once; a variant's step is two 32-bit additions (x's
  increment changes only with z's velocity: by `xmb * 0x4B`, a constant multiply); once the
  velocity stays (no accelerator, or clamped) **the rest of the flight in closed form** (x moves
  by the same amount a step, so its first and last steps are its extremes): 100 -> 12.6 ms.
  The variants' `start * i / 10` in 16 bits.

**Proofs.** `srsimcheck` (host/simcheck.c, built by `make host`) runs the new `ship_update`
beside the old one (host/ref_gameplay.c: gameplay.c of commit 2784ebf) on 2,000,000 random
ships on all 31 roads (positions and velocities typical, at every fast path's edges and far
beyond them; states that start the jump-o-master), each for 40 ticks of random controls,
compared field by field and event by event after every tick: 80,000,000 ticks, no difference;
it also prints how often each path ran (moves in 16 bits 42 M, in 32 bits 38 M; bounce scans in
the band 6.6 M, by 16-bit probes 2.3 M; landing tests 12 M fast, 1.1 M by the loop, 4.3 M closed).
Each narrowed helper against the expression it replaces: `fifths` and `bounce_velocity` for every
value of -200,000..200,000 and 2,000,000 more at the 32-bit edges; the band test against the
probe at 87,000,000 points. On the Atari816: `make probecheck` (the assembly probe and its 16-bit
entry against the 32-bit C at 155,000 random points of all roads) and `make movecheck`
(`hz_move16` and `hz_scan16` against the C at 62,000 random moves and scans): no difference. And
the demo's state after every tick (all 1,708) equals the PC's and commit 2784ebf's.

### 2. Merging spans: 718 -> 668 runs a frame

Measured on the PC first (every demo frame's spans, merged under each rule, the pictures
compared): runs a frame (busy stretch)

Each rule with its runs (busy), whether it is exact by construction, and its cost:

- None (the groups as drawn): 718 (872).
- A shape's own spans that touch: 718 (872); exact; no shape has two.
- A cell's spans resolved (overdraw within a cell taken out, touching ones joined): 707
  (868); exact.
- Consecutive cells' top faces of one colour, on one side: 670 (843); exact when the moved
  faces meet nothing drawn between (checked); cost: lookahead a cell.
- + the centre tile's two halves: 629 (820); exact under the same condition.
- Each span joined to the last run of its line if they touch, same colour: 542 (581); exact
  (nothing was drawn on that line between); cost: CPU work for every span.
- A pointer row resolved (its final runs): 458 (476); cost: per frame.
- A pass resolved: 419 (411); cost: per frame.

The kernel costs about 150 cycles a group element and 300 a group (fill_runs with FR_GROUPS:
it reads the prepared spans where they are), so a merge pays only where it is found for nothing
at frame time. The last-run rule (exact, -25 %) needs about 100 cycles of CPU a span to save
140 on a quarter of them, and plain runs instead of groups: no gain. Resolving a pointer row
(-36 %) works per frame (a row's runs depend on the level's rows, the record and the pointer
row: about 23,000 combinations a level, nothing repeats from frame to frame). What is
precomputed: **the centre tile's two top halves** (pointer slot 3's top face, drawn on the left
and again on the right, the same shape and colour) as one array of spans joined where they meet
(`srtool prepare`, in SKYPREP.DAT: 83 of the 104 record x pointer-row places), drawn at the
left half's turn when the right half meets no shape the cells between can draw (checked on the
PC over every shape draw_dos_type_0..5 can reach from those cells' pointers; column 4's inward
face is left out: it needs column 3 without a tile, which then has no top face). `hz_road_pass`
rewrites the left half's group to the merged array when the right half comes with the same
colour, and drops the right half: -50 runs a frame (-7 %), 0.5 ms. The side chains (-48 more)
were left out: their lookahead costs about what they save.

### 3. Road pass: 13 -> about 7 ms of preparation a frame

How the DOS original walks TREKDAT (upstream's renderer, `scene_draw` @0x2d03): for each of the
pass's pointer rows, the level row's 7 descriptors and the nearer row's, each cell's dispatch
kind choosing which of its 6 pointers' shapes to draw, in order. The translation had added
around it: 12 rows of descriptors copied near every frame from the scene's rows (found by a
search), a C call a pointer row (`draw_dos_pointer_row`, a function pointer with 6 arguments),
jobs written then turned into groups by another pass (`hz_span_groups`), a wait for the band's
restore before each pass, and every frame the 768-byte palette copied and compared. Now one
assembly call works out a whole pass (`hz_road_pass`, horizon/hz_road.s: its pointer rows, the
level's own rows read where they are, the cells, the shapes), writing the fill_runs groups
straight into one of two buffers; both passes are worked out before the first is sent (the CPU
works while Ali restores the band); a cell that draws nothing is passed over on its own
descriptor first. Per frame (busy stretch): the pass 81,000 cycles (5.7 ms) for 96 cells and 123
shapes, the kernel's fill_runs about 145,000 (10 ms): that is now the floor of the frame.

### 4. Pacing: 24 frames a second held

`make beat RATE=N` (`/BEAT N`): the demo at 36 ticks a second, its frames shown on a steady
beat: 36 (every 27.8 ms), 24 (every 41.7 ms: ticks 0, 1, 3, 4, 6, ...) or 18 (every 55.6 ms, every
second tick); 0 (the default) adaptive. A frame is drawn after the one before it is *drawn*
(not shown): it is kept (`hzv_held`) and shown at the first blank after its slot's time
(`beat_poll`, also called between ticks and inside the pass), so a heavy frame uses the time a
light one left; three pages make that possible. A frame finished after its slot's time is late
(shown at once; the slots gone by are skipped). Adaptive: down at once after 2 late frames in 12;
up after 72 frames on time when their drawing would fit the higher rate with about 5 ms to
spare (on average 33 ms and at most 41 ms for 24; 21 and 25 for 36).

Each beat with its frames shown, late frames, and the busy stretch's frames shown and late:

- 36: 1,436 shown, 1,170 late; busy stretch 317 shown, 304 late.
- 24: 1,114 shown, 50 late (the start, frames 450-500's 2,118 runs); busy stretch 267
  shown, 0 late.
- 18: 839 shown, 3 late (the start); busy stretch 200 shown, 0 late.
- Adaptive (from 24): 1,046 shown (826 at 24, 220 at 18), 8 late; busy stretch 255 shown,
  0 late; 4 changes of rate.

The highest rate the busy stretch holds: **24**. (`make paced`, the old measure, as many frames
as the CPU can draw: 1,469 of 1,708 ticks get a frame, against 801 before.)

### 5. Loading: 32 -> 4.1 s

Timed by phase: TREKDAT parsed (9.5 s) and its spans clipped (6.9 s), the ship's 77 sprites cut
and turned (4.3 s), 31 levels' cells built (5.5 s), the dashboard's images for the blitter
(2.6 s), ROADS and DEMO.REC parsed (2.3 s), the image archives (2.2 s). Now:
- `srtool prepare` (run by `make data`) writes **SKYPREP.DAT** (397 KB): TREKDAT's clipped spans
  as renderer_init makes them (packed in chunks a bank each), the pointer tables, the shapes,
  the turned sprites, the centre merges; `renderer_init_prepared` reads it (the PC renders the
  demo from it too: `srtool demo-frames DIR OUT incr SKYPREP.DAT`, identical to the golden
  frames); `/NOPREP` makes it all on the Atari816 as before.
- **Levels built when played** (`level_build` from `gameplay_session_init`; their header at
  the start).
- The dashboard's images a row at a time through near copies; ROADS's rows one copy (the tiles
  are little-endian words already); DEMO.REC's entries made near and copied 32 at a time;
  the decoded LZ streams no longer zeroed before they are read over.

On the board the card's speed adds to this (about 170 KB/s, and about 2 MB are read: the LZS
files only for their headers, as their .DEC hold the streams; leaving the LZS out and loading
the 10 world backdrops and the menus' pictures when first shown would save most of it).

### Did not help / not done

- Plain runs with a per-span merge at frame time (the last-run rule): more CPU than it saves.
- Side chains of top faces: their lookahead costs about what they save (left out).
- Waiting less for the band's restore (3d): the kernel's call blocks until the list is done
  anyway; worth 0.4 ms.
- The kernel's fill_runs is now 10 ms a frame (about 150 cycles a run, 300 a group): the frame's
  floor; 36 frames a second need about 23 ms of drawing.

### Faults and wishes found (round 2)

Each with its kind and a minimal case (numbered after the list in "SDK faults and wishes"
below):

8. prof816 names only exported or `_` labels: an assembly file's local routines are
   counted under the routine before them, here another file's (`hz_road_row`), or under a
   linker constant whose value is an address (`__HZ_SSTACK__` = $1000). Kind: prof816.
   Case: a .s with `foo:` (not exported) after an exported `_bar:`: foo's cycles show as
   `_bar`'s. Workaround here: `_hzq_pcore` etc. labels.
9. ca65 assembles a direct-page equate used before its definition as an absolute address:
   `lda rp` with `rp = __h2` defined later in the file read the main bank's $00xx, a far
   pointer from there crashed the program. Kind: assembler pitfall (pitfalls.md). Case:
   `lda rp` then `rp = __h2`: `lda $xxxx` (absolute). Define every dp name at the top.
10. The large code model still keeps all statics in the main bank: this port's near tables
    and buffers had to shrink twice to fit 65,264 bytes. Kind: cc816 wish. Case: a far
    static array (`static __far char b[8192]`) placed by the linker in a bank of its own.
11. `__umul1632` / `__smul1632` take about 1,000 cycles in the emulator: 16 x 16 -> 32
    multiplies are worth avoiding in a tick. Kind: cc816 speed. Case: `(long)a * b` of two
    ints.
12. No deferred flip: showing a page (`hg_flip`, or here `hzv_show`) makes the CPU wait for
    Ali first, so the next frame's CPU work cannot start meanwhile. Kind: hgame / kernel
    wish. Case: a "show page p once the list is done" call that returns at once.

## C++ to C: translation patterns

This is the first C++ source ported to the Atari816. The patterns, and what was done:

- `namespace skyroads::data` etc.: prefixes where names would clash (`level_`,
  `renderer_`, `app_`), upstream's names otherwise.
- Classes with methods (`Ship::update`, `GameplaySession::run_frame`,
  `AttractModeApp::tick`, `ReferenceRenderer::render_*`): a struct and functions taking it
  first (`ship_update(Ship *s, ...)`).
- `std::vector<T>` of assets: a pointer and a count (`Bytes`, `const RgbColor SR_FAR
  *colors; unsigned color_count`), memory from `plat_alloc` (far banks on the 816), built
  in two passes (count, then fill) where upstream pushed back.
- `std::optional<T>`: a `has_` flag beside the value; a nullable pointer
  (`sample_demo_input_for_ship`).
- `enum class`: an `enum` with prefixed names, stored in a `uint8_t` field.
- Exceptions (`data::Error`): `sr_fail()` prints "error: ..." and exits, as upstream's main
  did; the one place that catches (the decoder's end of an unbounded stream, a shape that
  does not parse) tests a flag.
- `std::map` / `std::set` catalogs (`summary` only): left out.
- Structs returned by value (`LevelCell`, `CarAtlas`, `RenderScene`): small ones kept; the
  cell probes return a pointer (`CellRef`); big ones (`CarAtlas`, 3.7 KB) filled in place:
  **a big return value or local overflows the 4 KB software stack into the heap with no
  message** (this cost an hour here).
- Per-frame copies upstream could afford (`DemoPlaybackState` copying 11 rows of cells and
  the road palette every tick): pointers to the level's rows and palette.
- `double` / `float` at the render boundary (`GameSnapshot`, `ShipRenderState`): the raw
  fixed-point integers; every floor / round / compare redone on them exactly
  (`round_div128`, ...) and proved by the frame comparison.
- `float` fades (intro, `scale_brightness`, `lerp_color`): integer arithmetic that gives
  the float's result, with the float expression itself evaluated only at an exact half
  (where IEEE rounding determines the result); not yet checked exhaustively (the intro was
  not reached in phase 1).
- Lambdas: static functions or macros.
- `constexpr` tables: `const` arrays in a `.c`.

Non-mechanical changes, all proved by the comparisons above: the shade plane is gone (the
road band of the palette starts at 0, so a pixel is its shade; the shadow reads the pixels
as the DOS blit did); TREKDAT shapes are parsed once at load into an array in record order
(upstream: a map and a memo), the next shape is the next index; spans are clipped once at
load; the dashboard band is kept between frames; the road pass collects its shapes and
draws them in one call; divisions in the hot paths are rewritten exactly (tables, shifts,
16-bit forms); the LZ streams come pre-decoded on the 816 (below).

**Pre-decoded streams.** The 65816 decodes the LZ bitstream too slowly for load time
(ROADS.LZS alone about 10 s). `srtool predecode` runs upstream's loaders on the PC and
writes every stream they decode, in order, to `NAME.DEC`; on the 816 `decompress_stream`
takes the next one from there (`decompress_fetch_hook`), the loaders unchanged. Loading
still takes 32 s in the emulator (parsing TREKDAT's 8,320 shapes, transposing 77 sprites,
building 31 levels' cells in C), which would need the same treatment (or a dump of the
parsed form) in a full port.

## Upstream faults found (for the C++ repository)

- `data/level.cpp`, `is_inside_tile_y` / `is_inside_tile_y_128`: the index check is
  `distance_index > 37` (for `TUNNEL_CEILS[38]`) but `TUNNEL_LOWS` has 30 entries, so
  indexes 30-37 read past it (reachable: the adjacent cell's distance 3,776-4,799). In
  the gcc build those bytes are `.rodata` padding (zeros); the C translation gives the
  table 38 entries, the last 8 zero, so that every build reads the same.

## SDK faults and wishes (not fixed in this round)

Each with its kind and a minimal case:

1. `long / 512` and `long / 16` are calls to `__sdiv32` (about 1,000 cycles); `int / 5`
   calls `__sdiv16`. The simulation's `/ 512`, `/ 16`, `/ 5`, `/ 10` were most of its cost.
   Kind: cc816 speed. Case: `long d(long x){return x/512;}` with `hcc -S`: `jsr __sdiv32`.
   Signed division by 2^k could be inline (add the bias for negatives, shift); by small
   constants a multiply.
2. A variable shift of a `long` (`1UL << c`) is a call (`__shl32`). Kind: cc816 speed.
   Case: `unsigned long s(unsigned c){return 1UL << c;}`.
3. A function returning a big structure by value, or with a big local, overflows the
   software stack into the heap silently (seen only at exit with `--debug`, or as corrupt
   data). Kind: cc816 diagnostics. Case: `struct big { char a[3700]; } f(void){ struct big
   b = {0}; return b; }` called with `--stack 4096`: a warning ("this function needs about
   7,400 bytes of software stack") or a check at entry in `--debug` builds would have saved
   an hour.
4. 32-bit comparisons and calls with `long` arguments are slow enough that the C glue of a
   frame (a few dozen calls) costs milliseconds. Kind: cc816 speed. Case: (general: compare
   `level_is_inside_tile_128`'s 32-bit form with the 16-bit one, about 4,000 against 900
   cycles a call).
5. No way to fill many runs in one request (the road's spans); a fill record costs the
   kernel about 1,100 cycles. Kind: Horizon / Ali. Case: "Requirements for full speed" 1.
   (0.30: `fill_runs`, about 140 cycles a run: "Horizon 0.30" above.)
6. hgame has no non-blocking page flip for a taller framebuffer (`hg_screen_fb` +
   `hg_scroll` waits in `hg_frame`): the port calls `hz_fs_scroll` and tracks the pending
   flip itself, with three pages. Kind: hgame gap. Case: `hzv_show` / `hzv_free_page` in
   `horizon/hz_video.c`. (0.30: `hg_flip_pages`, `hg_flip`, `hg_flip_free`.)
7. Programs have no fine clock (`hz_uptime` steps 10 ms): timing a frame needed each frame
   repeated 10 times. Kind: API / emulator wish. Case: a microsecond or cycle counter
   syscall (or emu816-only). (0.30: `uptime_us`, `hz_uptime_us`, `hg_us`.)

## Time

About 1 h 45 of the agent's time (wall clock, builds and emulator runs on a fast PC):
reading upstream and the SDK 25 min; the C translation of data, core and renderer, and the
PC checks 35 min; the Horizon back end, the experiment, the profiling and the fast paths
40 min (about 15 of them lost to the stack overflow, which made the early numbers wrong);
these notes 5 min.

Round 2: about 6 h: the simulation and its proofs 2 h 30, the road pass and the frame's glue
1 h 30, the load 45 min, the pacing 45 min, the merge's measurements and the centre merge 45 min.
