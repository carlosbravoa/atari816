# Porting notes: SkyRoads on the Atari816 (phase 1: the road-pass experiment)

SkyRoads (Bluemoon Interactive, 1993), from Carlos Bravo's C++17 reimplementation
[SDL-skyroads](https://github.com/carlosbravoa/SDL-skyroads) (MIT; about 7,500 lines:
`src/data` loaders and the LZ decoder, `src/core` the integer ship simulation and the app's
state machine, `src/renderer` the 320 x 200 software renderer of the DOS TREKDAT span
pipeline, `src/audio` the OPL2 driver on ymfm). The plan had two phases: first measure
whether the 65816 can draw the road fast enough; port the whole game only if it can reach
at least about 80 % of the original frame rate.

**Result: it cannot.** With every acceleration tried below, the attract demo drawn at the
game's speed gets a frame for 685 of its 1,708 ticks: **40 % of the original 36 frames a
second (about 14.5)**, the game logic itself at full speed. The drawing is pixel-exact
(all 1,708 demo frames equal the C++'s), but the CPU cost of a frame is about 33 ms of
drawing plus 10 ms of simulation against a 27.8 ms tick. The work stopped after phase 1,
as agreed; what would be needed is at the end ("What it would take").

## The game's rate

The C++ runs the simulation at 36 Hz (`SIMULATION_HZ_DEFAULT = 36` in
`src/platform/main.cpp`; `core/app.cpp`: "PIT divisor 0x19E4 = 180.02 Hz, and the tick
counter ds:0x160c is bumped on 2 of every 10 interrupts" = 36.0 Hz) and draws one frame per
tick. The target is therefore 36 frames a second, 27.8 ms a frame; 80 % is 28.8 frames a
second.

## The data and its terms

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

| | |
| --- | --- |
| `src/` | the C translation (C99, cc816 and gcc alike) of upstream's `data/` (all loaders but `exe`), `core/` (`gameplay`, `app`, `dos_render_tables`, `dos_font`) and `renderer/` (all scenes but the debug views): one `.c`/`.h` per `.cpp`/`.hpp`, upstream's names, structure and comments; the C-specific changes are marked "C:" in the comments. Not yet translated: `audio/` (the OPL2 driver), `planner`, `cli`'s `summary` |
| `src/platform.h`, `src/sr.h` | the small platform interface (files, far memory, fills and copies, a random byte) |
| `host/` | the PC back end (`host_plat.c`) and `srtool` (`cli_main.c`): `demo-sim` (upstream's CLI text), `demo-frames` (every demo frame, pure or incremental path), `predecode`, `probecheck` |
| `horizon/` | the Horizon back end: `hz_plat.c` (far memory, files, the pre-decoded streams), `hz_video.c` (three pages, flips, palette, the blitter), `hz_spans.s`, `hz_road.s`, `hz_probe.s` (assembly fast paths), `hz_main.c` (`/BENCH`, `/PACED`, `/CHECK`) |
| `tools/getdata.sh`, `tests/framesum.py` | the data; the frame checksums |

### How it was checked

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

## The road-pass experiment

Measured in the emulator (emu816 models the board's timing within about 5 %), Horizon
0.29, the attract demo (road 0, 1,708 ticks). `make bench` times each demo frame's
simulation tick and drawing, each repeated 10 times (`hz_uptime` has 10 ms steps);
`make paced` plays the demo at 36 ticks a second and counts the ticks that get a frame of
their own; profiles: `run816.py --prof`, `prof816.py --counts`.

The road's load, from the C translation on the PC: **718 spans and 16,689 pixels a frame
on average, 2,118 spans and 41,360 pixels at most** (spans a frame: frames 0-300 625,
300-700 646, 700-1100 872, 1100-1708 709; pixels 14.6 K, 8.5 K, 24.1 K, 18.2 K).

| Step (each on top of the ones before) | Simulation (ms a tick) | Drawing (ms a frame) |
| --- | --- | --- |
| First version: the C translation as it is; the spans in assembly (`hz_spans.s`, a jump into 127 unrolled 16-bit stores), copies from the underlay by the blitter, the dashboard by the blitter | 60 | 305 |
| 16-bit divides by 46 from a table (the cell probes) | 8 | 241 |
| The dashboard band kept and changed only where a gauge segment or a label changes (the gauges cost 4,000 `set_pixel` calls a frame) | 8 | 57 |
| The ship's sprite by an assembly keyed copy | 8 | (in the above) |
| The road pass's shapes collected and drawn by one assembly call; the cells' bytes from near copies | 8 | 41 |
| 32-bit divides by constants replaced (exact shifts and 16-bit divides); Ali restores the band while the CPU works out the shapes | 8 | 34 |
| (until here the bench ran on a corrupted level: a 3.7 KB structure returned by value had overflowed the 4 KB software stack into the heap; the numbers above are relative, the ones below are right) | | |
| The cell dispatch (`draw_dos_pointer_row` and the six `draw_dos_type_N`) in assembly (`hz_road.s`) | 7-28 | 31-47 |
| `level_get_cell_128` (no `x * 512`), the shadow's mask without `1u << col`, the pointer row read in place | 7-30 | 31-53 |
| The collision probe in 16 bits (exact; 32-bit fallback), the span filler driven by a width table | 2-18 | 26-51 |
| The probe and the shadow in assembly (`hz_probe.s`) | 2-17 | 26-48 |

**Paced, the whole demo at 36 ticks a second** (`make paced`): 1,708 ticks, 685 frames
drawn (40 %); simulation and scene 11.6 ms a tick, drawing and showing 41 ms a frame
(`hz_uptime`); the blitter made the CPU wait 0.5 s in all (1,370 waits).

Where a frame goes (profile of the paced demo, 40 s: 582 frames drawn, 1,440 ticks):

| Drawing, per frame | ms | Simulation, per tick | ms |
| --- | --- | --- | --- |
| the spans (`hz_span_jobs`: 225,000 cycles) | 15.7 | the collision probe (`hz_inside_tile` and its C wrapper) | 4.0 |
| the cell dispatch (`hz_road_row`) | 5.0 | `move_to`, `handle_bounce`, `interp` | 2.4 |
| the C around them (rows, passes, scene, ship placement, palette compare) | 5.5 | 32-bit multiplies and divides (`__mul32`, `__udiv16`, ...) | 1.8 |
| the kernel's sends and waits (`sheet_draw`, `list_wait`, `fs_scroll`) | 2.7 | the scene for the renderer (`build_play_scene`) | 0.6 |
| the ship (`hz_keyed`) and its shadow (`hz_shadow`) | 2.4 | the rest of the tick | 1.2 |
| in all, with the kernel's share | about 33 | in all | about 10 |

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

## What it would take

1. **Many fills in one request to Ali.** The whole road is a list of 700-2,100 runs
   {offset, width, colour} in one 64,000-byte page. A kernel record (or a direct user-mode
   command list for the program's own framebuffer) that fills such a list, validated once
   for the page's bounds instead of per record, with Ali's per-run cost small, would take
   the 15.7 ms of span filling off the CPU (Ali fills about 14 million pixels a second:
   16,700 pixels is 1.2 ms of Ali, 41,000 is 3 ms). The CPU would build the list
   (`hz_road_row` already does: 5 ms), the frame would cost about 17 ms, and 36 frames a
   second would hold with room. This is the one change that decides the port.
2. Short of that: a faster CPU write path to SDRAM (a write buffer that hides the
   4-5-cycle stall per store), or a faster CPU, would help in proportion, but not 2x.
3. cc816 code for 32-bit and small-int arithmetic (the simulation): see the SDK wishes
   below; worth 4-6 ms a tick here.

## C++ to C: what came up

This is the first C++ source ported to the Atari816. The patterns, and what was done:

| C++ | C |
| --- | --- |
| `namespace skyroads::data` etc. | prefixes where names would clash (`level_`, `renderer_`, `app_`), upstream's names otherwise |
| classes with methods (`Ship::update`, `GameplaySession::run_frame`, `AttractModeApp::tick`, `ReferenceRenderer::render_*`) | a struct and functions taking it first (`ship_update(Ship *s, ...)`) |
| `std::vector<T>` of assets | a pointer and a count (`Bytes`, `const RgbColor SR_FAR *colors; unsigned color_count`), memory from `plat_alloc` (far banks on the 816), built in two passes (count, then fill) where upstream pushed back |
| `std::optional<T>` | a `has_` flag beside the value; a nullable pointer (`sample_demo_input_for_ship`) |
| `enum class` | an `enum` with prefixed names, stored in a `uint8_t` field |
| exceptions (`data::Error`) | `sr_fail()` prints "error: ..." and exits, as upstream's main did; the one place that catches (the decoder's end of an unbounded stream, a shape that does not parse) tests a flag |
| `std::map` / `std::set` catalogs (`summary` only) | left out |
| structs returned by value (`LevelCell`, `CarAtlas`, `RenderScene`) | small ones kept; the cell probes return a pointer (`CellRef`); big ones (`CarAtlas`, 3.7 KB) filled in place: **a big return value or local overflows the 4 KB software stack into the heap with no message** (this cost an hour here) |
| per-frame copies upstream could afford (`DemoPlaybackState` copying 11 rows of cells and the road palette every tick) | pointers to the level's rows and palette |
| `double` / `float` at the render boundary (`GameSnapshot`, `ShipRenderState`) | the raw fixed-point integers; every floor / round / compare redone on them exactly (`round_div128`, ...) and proved by the frame comparison |
| `float` fades (intro, `scale_brightness`, `lerp_color`) | integer arithmetic that gives the float's result, with the float expression itself evaluated only at an exact half (where IEEE rounding decides); not yet checked exhaustively (the intro was not reached in phase 1) |
| lambdas | static functions or macros |
| `constexpr` tables | `const` arrays in a `.c` |

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

| # | What | Kind | Minimal case |
| --- | --- | --- | --- |
| 1 | `long / 512` and `long / 16` are calls to `__sdiv32` (about 1,000 cycles); `int / 5` calls `__sdiv16`. The simulation's `/ 512`, `/ 16`, `/ 5`, `/ 10` were most of its cost | cc816 speed | `long d(long x){return x/512;}` with `hcc -S`: `jsr __sdiv32`. Signed division by 2^k could be inline (add the bias for negatives, shift); by small constants a multiply |
| 2 | a variable shift of a `long` (`1UL << c`) is a call (`__shl32`) | cc816 speed | `unsigned long s(unsigned c){return 1UL << c;}` |
| 3 | a function returning a big structure by value, or with a big local, overflows the software stack into the heap silently (seen only at exit with `--debug`, or as corrupt data) | cc816 diagnostics | `struct big { char a[3700]; } f(void){ struct big b = {0}; return b; }` called with `--stack 4096`: a warning ("this function needs about 7,400 bytes of software stack") or a check at entry in `--debug` builds would have saved an hour |
| 4 | 32-bit comparisons and calls with `long` arguments are slow enough that the C glue of a frame (a few dozen calls) costs milliseconds | cc816 speed | (general: compare `level_is_inside_tile_128`'s 32-bit form with the 16-bit one, about 4,000 against 900 cycles a call) |
| 5 | no way to fill many runs in one request (the road's spans); a fill record costs the kernel about 1,100 cycles | Horizon / Ali | "What it would take" 1 |
| 6 | hgame has no non-blocking page flip for a taller framebuffer (`hg_screen_fb` + `hg_scroll` waits in `hg_frame`): the port calls `hz_fs_scroll` and tracks the pending flip itself, with three pages | hgame gap | `hzv_show` / `hzv_free_page` in `horizon/hz_video.c` |
| 7 | programs have no fine clock (`hz_uptime` steps 10 ms): timing a frame needed each frame repeated 10 times | API / emulator wish | a microsecond or cycle counter syscall (or emu816-only) |

## Time

About 1 h 45 of the agent's time (wall clock, builds and emulator runs on a fast PC):
reading upstream and the SDK 25 min; the C translation of data, core and renderer, and the
PC checks 35 min; the Horizon back end, the experiment, the profiling and the fast paths
40 min (about 15 of them lost to the stack overflow, which made the early numbers wrong);
these notes 5 min.
