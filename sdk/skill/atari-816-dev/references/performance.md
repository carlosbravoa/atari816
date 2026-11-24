# Performance on the Atari816 (C and assembly)

Purpose: find where a program's time goes (the profiler), know what is slow and what is
fast before writing the hot loop, and pick the right knobs. The emulator (emu816) models the
board's memory timing: its figures are the board's within about 5 %. Plan with them as they
are. Sources of the numbers: "measured here" = runs made for this page (emu816, Horizon 0.29,
REV $0C, `-O2`, small code model); otherwise the SDK doc named.

Budget: 14,343,750 cycles a second, **238,944 cycles (16.7 ms) a frame** at 60 Hz. About
14,000 cycles a millisecond.

## The profiler workflow

1. Build with a map: `hcc --map -o GAME.PRG ...` (or `HCCFLAGS := --map` in the Makefile).
   It writes `GAME.map` (ld65's map) and `GAME.lbl` (every label) and prints the sizes.
2. Run with counts for a stretch of time (seconds after the program's start, as `--shot`):

   ```
   python3 SDK/tools/run816.py GAME.PRG --file ROCK.HGI:/APPS/ROCK.HGI --script test.script \
     --prof prof.txt --prof-from 1 --prof-to 4 --out build/prof
   ```
   (console programs: add `--mode shell`, and `--args` if needed.)
3. Make the table:

   ```
   python3 SDK/tools/prof816.py --counts prof.txt --map GAME.map --top 14
   ```

Measured here on the minimal hgame game (references/hgame.md, 6 rocks + ship + a score
line with `hg_textf`, `HG_DOUBLE`):

```
prof816: 3.00 s of emulated time, 43,031,340 cycles; banks: $0B = the main bank
the program's own code 15.7 %, syscalls 21.5 %, kernel and idle 62.7 %
       cycles      %  where
   26,747,557  62.16  idle (WAI)
    2,022,367   4.70  syscall $9C (156 calls, 12963 cycles each)
    1,778,739   4.13  syscall $A3 (156 calls, 11402 cycles each)
    1,443,520   3.35  syscall $0F (156 calls, 9253 cycles each)
      993,861   2.31  ___hz_vformat
      784,584   1.82  syscall $9D (156 calls, 5029 cycles each)
      777,570   1.81  __HZ_SSTACK__
      760,742   1.77  hgf_reccore
      ...
```

How to read it:
- Rows are functions (C names with a leading `_`; assembly routines by their label),
  `syscall $NN` (the kernel's cycles for the program's `COP #$NN`, with the call count),
  `kernel`, `idle (WAI)` (time free: 62 % here, so the game has room), and `(user bank $00)`
  (code outside the program, such as the shared ulib).
- Syscall numbers: `HORIZON/user/horizon.inc` (`grep -n '\$9C' HORIZON/user/horizon.inc`): $9C
  `SYS_DRAWLIST`, $A3 `SYS_SHEETDRAW`, $9D `SYS_LISTWAIT`, $0F `SYS_VSYNC`, $98 `SYS_FSSCROLL`,
  $9E `SYS_FRAME`, $04 `SYS_UPTIME`, $75 `SYS_WEVENT`.
- `___hz_vformat` is printf's formatter: here the `hg_textf` score line costs 2.3 % of all
  time. Formatting text every frame is a typical waste: format only when the value changes.
- A row named after a linker constant (here `__HZ_SSTACK__`, a size that equals $2000) is
  code of the function whose label comes just before that address: list the labels around
  it (`awk '{print $2, $3}' GAME.lbl | sort | grep '^001F[EF]\|^0020'`; here
  `001FFA ._hg__strip`, hgame's text routine).
- Works in both code models (the large model's banks are matched by their bytes).
- `hg_stats("NAME")` (hgame) gives the cheap overview: `DODGE: 211 frames, 1 missed, CPU 3.45
  ms a frame`. `hg_missed` > a few means frames run late: profile the stretch where it happens.
- `SDK/tools/emu-prof.sh` profiles from an instruction trace (slow; short stretches only).

## What C operations cost

Measured here (`perf.c`, 20,000 iterations each, operands `volatile`, time per iteration
with the empty loop's 3.5 us taken out; the loop compiled with -O2):

| Operation | us | Note |
| --- | --- | --- |
| `i << 3`, `i * 10` (constant) | 1.6 | multiply by a constant is inline shifts and adds |
| `i * v` (16-bit, variable) | 14.6 | call `__mul16` (~330 cycles) |
| `i / v` (16-bit, variable) | 73 | call `__udiv16` (~1,000 cycles) |
| `i / 10`, `i % 10` (16-bit, any constant) | 9, 13 | inline: a multiply by the reciprocal, exact for every value (cc816 checks each divisor); signed too; was a call (51 us) |
| `i / 16`, `i % 16` (power of two) | 1-2 | shifts and masks, signed too (the bias for negative values) |
| `long * long` | 66 | call `__mul32` |
| `long / long`, `long / 10` | 62 | call `__udiv32` (a non-power-of-2 constant too) |
| `long / 512`, `long % 16` (power of two) | 6-10 | inline shifts and masks, signed too; was a call (100 us) |
| `1UL << n`, `x >> n` (`long`, variable n) | 15-26 | `__shl32` etc.: a word, then a byte, then bits (`1UL << 13`: 26 us, was 47); a constant count is inline (word and byte moves: `x * 128` about 3 us) |
| `float` multiply + add | 335 | soft float (`__fmuli`, `__faddrx`, `__fpack`) |
| a byte read in a loop, near array | 2.7 | `s += a[i]` |
| the same through a `__far` pointer | 4.7 | about 1.8 x near |

From SDK/docs/c/reference.md (one operation, microseconds): float `+` 77, `*` 207, `/` 282,
`<` 17, `sqrt` 587, `sin` 4,147, `exp` 3,560, `log` 3,402; `long long` `+` 16, `*` 376, `/`
1,260 (slow case), `%` 1,265, `sprintf("%lld")` 2,985. Its benchmark (`tests/bench`, ms):
sieve 809, sum16 296, mul32 1,277, fib22 388, strs 994, structs 670.

Rules that follow:
- `unsigned int` (16 bits) for counters, indexes, coordinates. Signed division and right
  shifts of `int` need extra code.
- No division by a variable in the inner loop. A 16-bit division or remainder by a
  constant is inline and cheap (`/ 10`: 9 us); by a power of two it is shifts and masks,
  for `long` too. A `long` divided by another constant is still a call (100 us): keep a
  running counter, or divide a 16-bit value. Multiply by constants freely.
- No `long`, `long long` or `float` per pixel or per object per frame. Use 8.8 fixed point
  in an `int` (`HG_FIX8`) or 16.16 in a `long` only where needed (references/hgame.md).
- Hot data near (globals, statics, malloc: the main bank). `__far` data is for bulk
  storage; copy what a loop needs into a near buffer first.
- Hot loops in assembly cost no main-bank room in a `--code large` program when opened
  with `FUNC` (references/c-language.md, "Movable assembly"): they run as fast in any
  bank (calls are JSL either way).
- No `printf` in the frame loop: `printf` of one character took 220 us here; a console line
  about 2 ms (SDK/docs/c/games.md). Under the Desktop it goes to the log anyway.

## Block moves (MVN / MVP)

Measured here: `memcpy`, `memset` and `hz_far_copy` of 4,096 bytes all take 3.47 ms:
**about 0.85 us (12 cycles) a byte**, about 1.2 MB a second. SDK/docs/reference/performance.md
gives about 13 cycles a byte on the desktop (7 with `--ideal-timing`, the old model); a
"7 cycles a byte" figure elsewhere is the ideal one. A structure copy is inline MVN.

So: copying a 320 x 180 screen (57,600 bytes) by the CPU takes about 49 ms, three frames.
Never move pixels by the CPU when the blitter can (below).

## Drawing costs

The blitter (Ali) fills about 14 million pixels a second and copies about 7.7 million
(SDK/docs/reference/performance.md); small operations are all call overhead.

hgame, measured here (full screen 320 x 180, CPU time per call including the kernel's send
and the wait, `hg_flush(1)` around each batch):

| Call | us each |
| --- | --- |
| `hg_draw` 16 x 16 from a sheet (any hgame image) | 131 |
| `hg_fill` 16 x 16 | 230 |
| `hg_text`, 20 characters | 1,050 |
| `hg_clear` 320 x 180 (blitter, waited for) | 4,880 |
| `hg_pixel` (CPU) | 136 |
| `hg_line`, diagonal, 100 pixels (CPU) | 12,660 |

SDK/docs/c/games.md splits these into library and kernel time (sheet blit 80 + 62 us, fill
66 + 200 us, a send 500 us, a 16 x 16 `hg_image_draw` by the CPU 650 us, `hg_map_image` of
20 x 12 tiles 112 ms) and budgets a frame at about **50 sheet blits or 25 fills**, a few text
lines, 16 sprites for under 1 ms, scrolling nearly free.

Window drawing, measured here (a 400 x 200 window on the Desktop):

| Call | us each |
| --- | --- |
| `hz_win_draw` fill 16 x 16 | 356 |
| `ui_text`, 20 characters | 1,060 |
| `ui_rect` fill 300 x 80 | 2,625 |

Every `win_draw` costs about 0.35 ms whatever its size: **a few dozen a frame at most**.
SDK/docs/reference/performance.md (Horizon's own `gtest m`, 100 keyed 16 x 16 blits a frame):
100 `win_draw` calls 26.6 ms (more than a frame); one `draw_list` of 100 records 9.1 ms
(about 1,300 cycles a record); one `sheet_draw` of 100 records 2.46 ms (about 320 cycles a
record); about 0.27 ms a call. With the board's timing (emu816's default, `gtest t`): about 31
us a sheet record (fills 27, beyond 16 x 16 35, cut at an edge 51, SH_TABLE 25), 150 us one
into a covered window (the full path), 565 us a call.

Many short horizontal runs (Horizon 0.30, `sdk/c/game/tests/gt_runbench.c`, 2,000 runs of
23 pixels, CPU cycles a run): a C loop 1,700; hgame's assembly CPU path 610; a tight unrolled
assembly fill about 260; `hg_fill` records 3,400; **`hg_fill_runs` 140** (8 pixels 138, 100
pixels 175: the pixels cost the CPU nothing); `hg_fill_groups` (the game's own span arrays)
about 150 a run plus 300 a group (groups of 20: 170 a run; of 2: 300). The CPU still pays for every run: batching wins against C
and against wide runs; against a tight assembly fill of very short runs it gains about half.

What is fast, in order:
1. **Hardware sprites**: no CPU and no blits; one `spr_set`/`spr_move` for all of them a
   frame (each syscall about 0.1 ms on the board). hgame sends them in one call.
2. **Scrolling** by Marga (`fs_scroll`, `hg_camera`): one call a frame plus the tiles that
   come into view (a column of 12 tiles about 2 ms, every few frames).
3. **Sheets**: art registered once (`hg_image_*` does it; assembly `SYS_SHEETNEW`), drawn
   with `sheet_draw` records. 32 sheets system-wide.
4. **Draw lists**: many blits in one call (`hz_draw_list`, assembly `SYS_DRAWLIST`); sources
   stay in use until `list_wait` / the next vsync.
5. Single `win_draw` / `ui_*` calls: fine for a UI, too slow for animation.
6. The CPU writing pixels: slowest; only for composing once (a level background).

Measured programs (SDK/docs/c/games.md): Glimmer (full screen, scrolling, 16 sprites, music)
4.53 ms CPU a frame; Gem Run in C (window, 2 bobs) 1.73 ms; tutorial step 4 4.41 ms (4.23 ms
in a run made here).

## Assembly notes

From SDK/docs/reference/performance.md:
- The CPU runs at about half its ideal speed on memory-heavy code: every write stalls on
  SDRAM (about 4-5 cycles, 9 with the classic machine running), a cache read miss costs
  about 6 cycles (4 KB cache). A direct-page store loop runs at 0.41 of ideal with the
  desktop's video on, long reads that miss at 0.53, a sieve at 0.80. A register-only loop
  (`dex`/`bne`) runs at full speed.
- So: keep values in registers, avoid needless stores, prefer MVN/MVP for blocks (12-13
  cycles a byte) over byte loops, let the blitter do pixels.
- A syscall costs 50-100 us or more (`getpid` 50 us ideal, about twice that now); batch them
  (one `draw_list`, one `spr_move` of many). ABI: references/abi-cheatsheet.md.
- File reads go through the I/O processor one request at a time: load at level start.

## Knobs

| Knob | Effect (measured here unless noted) |
| --- | --- |
| `-O2` (default; `-O3`, `-Os` are the same) | the fast one |
| `-O1` | no loop optimisations: reference.md's sum16 476 ms vs 296 ms; other loops about equal |
| `-O0` | no optimisation: the near byte loop took 458 ms vs 219 ms at -O2 |
| `--code large` (`HZ_CODE=large`) | only when the code does not fit one bank: JSL calls cost 2 cycles more, a call through a pointer 6 more (10 to another bank), each call site 1 byte more (reference.md "Costs"); the benchmark is within 1-10 % of small (fib22 388 vs 430 ms); here the shift loop 137 vs 101 ms |
| near vs `__far` data | far byte loop about 1.8 x the near one (above) |
| `hg_steps(hz)` | logic at a fixed rate, drawing at 60: drop logic rate before dropping frames |
| `HG_DOUBLE` | costs the blitter's full redraw each frame (a 320 x 180 clear 5.6 ms of Ali; four times that at 640 x 360): one page with sprites is cheaper |

## Checklist for a slow frame

1. `hg_stats` / `hg_missed`: is it the CPU (high ms a frame) or waiting?
2. Profile the slow stretch (`--prof-from`/`--prof-to`), top 15 rows.
3. Big `syscall $9C`/`$A3` rows (draw_list, sheet_draw): too many records: draw less, draw
   only what changed, use sprites or scrolling; many small fills: one `hg_fill_runs`
   (`syscall $A4`, about 140 cycles a run).
4. `__mul16`, `__udiv16`, `__mul32`, `__udiv32`, `__sdiv32`, `__shl32`, `__f*` rows:
   arithmetic in the hot loop (see the rules above).
5. `___hz_sovf` in a crash or a console line `software stack overflow: F needs a frame of
   N bytes`: F's locals (or a structure returned by value) do not fit the software stack:
   `--stack N`, `static`, or fill the structure through a pointer.
6. `___hz_vformat`: printf / `hg_textf` every frame.
7. CPU drawing rows (`hg_pixel`, line routines): use fills, images or sprites.
