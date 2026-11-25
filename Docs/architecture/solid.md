# What makes it solid

Every layer of the Atari816 has tests that run without a person, and most of them without
the board. This page lists them with the counts of one run, says how the tests are made to
mean something, and says what is not covered.

## One run, from a fresh tree

The counts below come from one run on 2026-11-25, at release 0.31 (commit `1b1b0bb`). The
tree was a fresh copy of the repository without any build output (`rsync` without `.git`
and without the `build` folders), built from nothing (`make -C emu`, `make -C horizon`,
`make -C sdk/c`), then tested, on a 16-thread Linux PC with the runs limited to 8 CPUs
(`taskset`). A build left over from an earlier change cannot make a test pass this way.
Every suite exited with status 0. Together they took about 42 minutes.

| Suite | Command | Result | Wall time |
| --- | --- | --- | --- |
| The emulator | `make -C emu test` | 52 checks passed, 0 failed, 1 skipped (the SingleStepTests sample, not downloaded) | 22 s |
| Horizon | `make -C horizon test` | 175 checks passed, 0 failed; console output against expected files, screenshots against stored checksums (693 entries in `horizon/tests/pictures`) | 168 s |
| The compiler | `make -C sdk/c/cc816 check` | 3 configurations (small, large, large with far data), each: 125 of 125 message tests, 400 of 400 damaged programs without an internal error, 58 regression programs, 29 language programs, 17 + 17 regression programs at -O0 and -O1, 1,200 random programs, 600 random negative-index programs, 600 random floating-point programs: all pass | 1,309 s |
| The SDK | `make -C sdk test` | 318 PASS lines, 0 FAIL (details below) | 287 s |
| Digger | `make -C ports/digger test` | 19 passed, 0 failed: the scripted game, its high score and sound, 9 frames of a recording against reference pictures, 7 of upstream's recorded games to upstream's results | 140 s |
| Micropolis | `make -C ports/simcity test` | 10 passed, 0 failed | 152 s |
| Prince of Persia | `make -C ports/prince test` | 21 passed, 0 failed | 94 s |
| Xargon | `make -C ports/xargon test` | 16 passed, 0 failed | 36 s |
| X-COM | `make -C ports/xcom test JOBS=6` | 114 passed, 0 failed | 235 s |
| SkyRoads (experiment) | `make -C ports/skyroads check` | 1,708 of 1,708 demo frames match the C++ original's, and the state after every one of the 1,708 ticks | 58 s |

Xargon, Prince of Persia, X-COM and SkyRoads need the game's files. For this run they were
the copies already converted on the test machine (`data/` of an earlier tree), copied into
the fresh tree; Digger's and Micropolis' data were built from the repository.

The SDK's `make test` is made of: the assembly reference checked against the kernel
(`abicheck.py`: 115 syscalls, 147 constants) and its 149 examples in 17 files assembled
and linked (`snippets.py`); 11 templates and examples in assembly built and run with their
scripts; the host twin's own test (`tests/host16`); the C SDK's 122 tests in the emulator
(the C library, the syscalls, code generation, floating point, `long long`, the stacks, the
controls library, apps, in both code models); the C examples and templates, three of them
again in the large code model and three with far data; hgame's 53 tests in each of the
three configurations; and the coding-agent skill's examples and text check.

The c-testsuite (220 single-exec programs) is part of the compiler's suite when a checkout
is given (`CTS=DIR`). There was none on the test machine, so it was not run here. The
compiler reference records 213 of 220 passing in each configuration; the 7 others are
listed with their reasons in `sdk/c/cc816/tests/cts-known.txt` (a 32-bit `int` or a 64-bit
`double` expected, a variable-length array, an `__LP64__`-style macro).

## How the tests are made to mean something

- **They check the result, not the absence of a crash.** Console lines with values
  (`--expect`), files written on the emulated card (their contents), pictures against
  stored checksums or reference images, sound chip writes against logged streams, a
  program's own PASS lines (no PASS at all is a failure).
- **They follow the program, not the clock.** Input scripts wait for a console line the
  program prints at each state (`wait TEXT`) or for a still screen (`still N`), and
  screenshots are taken at the program's own frames (`--shot-on`). Several suites prove
  it: Digger's scripted game passes with its start delayed by 1.5 and 3 s; Xargon's demo
  and a Prince of Persia replay run again on a machine 30 ms a frame slower and must reach
  the same state; the emulator's `--cpu-slow` and `--kernel-slow` show which pictures were
  taken at moments rather than at states.
- **They are deterministic.** The emulator's time is emulated: the same card and input give
  the same run. `--ram-random SEED` changes what uninitialised memory holds, for programs
  that read it.
- **They can fail.** Expected files and checksums are compared exactly; the Digger notes
  record a deliberate fault (an emerald drawn two rows short) that failed 7 of 9 pictures.
- **Hardware rules are enforced.** The emulator counts every broken blitter rule (a write
  while busy, a read of blitter output without a cache flush); Horizon's tests and
  `run816.py` fail on any. The compiler's programs run under `--log-bankwrap`, which fails
  an indexed access that carries into the next bank.

## Host twins

A port's C code is also built on the PC, and the two builds are run on the same input and
compared. `sdk/c/tools/host16.py` builds the PC twin with the Atari816's integer sizes
(16-bit `int`, 32-bit `long`, unsigned `char`, packed structures, `double` as `float`), so
the comparison shows the faults of the 16-bit target and of the compiler, not just of the
platform layer.

| Port | What is compared |
| --- | --- |
| Micropolis | the simulator on the Atari816 against two PC twins (16-bit `int`, and upstream's types): ten cases of 5,000 ticks, the whole state equal every 100 ticks in all three; saved cities byte for byte |
| X-COM | 16 scripted runs of every screen on the PC build (a model of the DOS machine with DOS's 16-bit `int`) and on the Atari816: the same log line for line, the same pictures pixel for pixel at the same virtual times, the same saves; the sound streams against the host's |
| Prince of Persia | four replays recorded with upstream SDLPoP on a PC: the game's state every 10 ticks and upstream's end lines equal to the PC's (246 states, 2,478 ticks), 18 pictures equal to the PC's frames |
| SkyRoads | the attract demo's 1,708 frames and its state after every tick, against the C++ original's |
| Digger | seven of upstream's recorded games played back: each ends with upstream's own score, level and frame count |
| Xargon | the recorded demo to frame 1,500: score, health, emeralds and objects as recorded, twice (once on a slower machine) |

In Micropolis the comparison of the two PC twins found the first 16-bit faults of the
original source (the random numbers, a distance kept in an `int`), and the comparison of
the Atari816 with the 16-bit twin found the rest (products that overflow only in 16 bits)
and the port's memory faults ([ports/simcity/PORTING-NOTES.md](../../ports/simcity/PORTING-NOTES.md)).

## The ports as the compiler's acceptance test

The ports are large C programs written for other compilers (DOS's Watcom and Microsoft C,
Unix C, C++ translated to C), so they test cc816 on code nobody wrote for it. They found
compiler faults that the compiler's own suites had not, each fixed with a regression test:
for example a signed array index whose constant part made the access read the next bank
(Prince of Persia, `tests/regress/r040_signed_index_offset.c`), a structure defined in a
declaration of several objects (Digger), a header with code page 437 bytes that stopped the
compiler (Xargon). They also asked for the options that old code needs: C89's implicit
`int` (the Micropolis source had 248 functions without a return type), more arguments than
the prototype, DOS's right-to-left argument order, and the far data model, DOS's large
model, for X-COM. The faults found and fixed are listed in
[sdk/docs/c/reference.md](../../sdk/docs/c/reference.md), "Faults found and fixed".

## Timing models measured on the board

The emulator's speed is not a guess. These figures were measured on the board and the
emulator was fitted to them:

- **The CPU and memory**: `core/sw/a816/timing.s` (TIMING.BIN) on the board, loop by loop,
  in four video and classic-machine states; the emulator is within about 7 % on every loop,
  most within 2 % ([emu/README.md](../../emu/README.md), "Memory timing").
- **The blitter**: the cycles a pixel of each operation, from the same program.
- **The SD card**: the X-COM port's I/O benchmark (`/IOB`), run on the board with two
  firmware versions and in the emulator on the same folders: every line within 6 %
  ([emu/README.md](../../emu/README.md), "The card's speed").

The colour remap's cost in the emulator (+12 %) comes from the RTL simulation; on the
board, X-COM's night screen drawn through the remap took 4.21 ms against 3.78 ms by day
(+11 %). The card's write rate and folder operations are estimates, not measurements.

## The manual

`sdk/tools/doccheck.py` fails when a public function or macro of the SDK's headers, a
public header, an option of `hcc`, `cc816.py`, `run816.py`, `hzapp.py`, `host16.py`,
`inputscript.py` or `emu816`, or a tool of the SDK is named nowhere in the SDK's manual,
and when the generated index of the syscall functions is out of date. The coding-agent
skill has the opposite check: every name, option and path it mentions must exist.
`make -C sdk check` checks the assembly reference against the kernel's tables.

## What is not covered

- **The board itself.** The suites run in the emulator. The board is checked by hand and
  with its own test programs (`core/sw/a816/`), the RTL by Verilator simulations
  (`core/sim_a816/`); neither is part of these runs. What only the board shows: POKEY's
  sound, the joysticks (the emulator reads them as 0), the keyboard adapters' firmware,
  HDMI. The classic Atari is not in the emulator at all.
- **Sound is measured, not heard**: chip writes, levels and clipping of recordings.
- **Open faults** on the board are listed in [core/KNOWN_ISSUES.md](../../core/KNOWN_ISSUES.md):
  the HDMI picture lost now and then, a desktop without input after F12 during a disk
  load, a restart seen once.
- **Ports that need the game's files** (Xargon, Prince of Persia, X-COM, SkyRoads) can only
  be tested where those files are; Digger's and Micropolis' data are in the repository.
