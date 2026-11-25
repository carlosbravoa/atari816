# Verification

Every layer of the Atari816 has automated tests, and all except the hardware's own run in
the emulator, without the board. The emulator's timing is fitted to measurements on the
board, and the ports are compared with builds of the same C code on a PC.

## Test suites

Each suite runs with one `make` command and exits with a non-zero status on any failure.

- Emulator (`make -C emu test`): 52 checks of the CPU, FREDDIE II, the system block, the
  mailbox, Marga, Ali, Lau and the OPL2, plus a sample of the SingleStepTests suite when it
  has been downloaded (`make sst`).
- Horizon (`make -C horizon test`): 175 checks. Scripted sessions of the kernel, the shell,
  every bundled program, the window system, full screen and sprites, music, the PC link,
  the internet, printing and apps. Console output is compared with expected files, and
  screenshots with stored checksums (693 entries in `horizon/tests/pictures`).
- Compiler (`make -C sdk/c/cc816 check`): three configurations (small, large, large with
  far data). In each: 125 message tests, 400 damaged programs that must compile without an
  internal error, 58 regression programs, 29 language programs, 17 + 17 regression programs
  at -O0 and -O1, 1,200 random programs, 600 random negative-index programs and 600 random
  floating-point programs.
- c-testsuite (part of the compiler's suite when a checkout is given, `CTS=DIR`): 213 of
  its 220 single-exec programs pass in each configuration. The 7 others are listed with
  their reasons in `sdk/c/cc816/tests/cts-known.txt`: a 32-bit `int` or a 64-bit `double`
  expected, a variable-length array, an `__LP64__`-style macro.
- SDK (`make -C sdk test`): 318 checks, listed below.
- Digger (`make -C ports/digger test`): 19 checks. The scripted game, its high score and
  sound, 9 frames of a recording against reference pictures, and 7 of upstream's recorded
  games against upstream's results.
- Micropolis (`make -C ports/simcity test`): 10 checks.
- Prince of Persia (`make -C ports/prince test`): 21 checks.
- Xargon (`make -C ports/xargon test`): 16 checks.
- X-COM (`make -C ports/xcom test`): 114 checks.
- SkyRoads, an experiment (`make -C ports/skyroads check`): all 1,708 frames of the demo
  against the C++ original's, and the game state after each of its 1,708 ticks.

The SDK suite consists of:

- the assembly reference checked against the kernel: 115 syscalls and 147 constants, and
  its 149 examples in 17 files assembled and linked;
- 11 templates and examples in assembly, built and run with their scripts;
- the host twin's own test (`tests/host16`);
- the C SDK's 122 tests in the emulator: the C library, the syscalls, code generation,
  floating point, `long long`, the stacks, the controls library and apps, in both code
  models;
- the C examples and templates, three of them again in the large code model and three with
  far data;
- hgame's 53 tests in each of the three configurations;
- the coding-agent skill's examples.

## Test method

- Results, not the absence of a crash: console lines with values (`--expect`), the
  contents of files written on the emulated card, pictures against stored checksums or
  reference images, sound chip writes against logged streams, and a program's own PASS
  lines (a run with no PASS line fails).
- Synchronisation with the program, not the clock: input scripts continue when the program
  prints a given console line at each state (`wait TEXT`) or when the screen is still
  (`still N`), and screenshots are taken at the program's own frames (`--shot-on`).
  Several suites check this. Digger's scripted game passes with its start delayed by 1.5 s
  and 3 s. Xargon's demo and a Prince of Persia replay run again on a machine 30 ms a frame
  slower and must reach the same state. The emulator's `--cpu-slow` and `--kernel-slow`
  identify pictures taken at a moment rather than at a state.
- Determinism: the emulator's time is emulated, so the same card and input give the same
  run. `--ram-random SEED` changes the contents of uninitialised memory, for programs that
  read it.
- Exact comparison: expected files and checksums are compared exactly. In a deliberate
  fault test, an emerald drawn two rows short failed 7 of Digger's 9 pictures.
- Hardware rules: the emulator counts every broken blitter rule (a write while busy, a read
  of blitter output without a cache flush), and Horizon's tests and `run816.py` fail on
  any. The compiler's programs run under `--log-bankwrap`, which fails an indexed access
  that carries into the next bank.

## Host twins

A port's C code is also built on the PC, and both builds run on the same input and are
compared. `sdk/c/tools/host16.py` builds the PC twin with the Atari816's integer sizes
(16-bit `int`, 32-bit `long`, unsigned `char`, packed structures, `double` as `float`), so
the comparison exposes faults of the 16-bit target and of the compiler as well as of the
platform layer.

- Micropolis: the simulator on the Atari816 against two PC twins (16-bit `int`, and
  upstream's types). Ten cases of 5,000 ticks, with the whole state equal every 100 ticks
  in all three. Saved cities equal byte for byte.
- X-COM: 16 scripted runs of every screen on the PC build (a model of the DOS machine with
  DOS's 16-bit `int`) and on the Atari816. The same log line for line, the same pictures
  pixel for pixel at the same virtual times, the same saves, and the sound streams equal to
  the host's.
- Prince of Persia: four replays recorded with upstream SDLPoP on a PC. The game's state
  every 10 ticks and upstream's end lines equal the PC's (246 states, 2,478 ticks), and 18
  pictures equal the PC's frames.
- SkyRoads: the attract demo's 1,708 frames and its state after every tick, against the
  C++ original's.
- Digger: seven of upstream's recorded games played back. Each ends with upstream's own
  score, level and frame count.
- Xargon: the recorded demo to frame 1,500, with score, health, emeralds and objects as
  recorded, run twice (once on a slower machine).

In Micropolis, the comparison of the two PC twins exposed 16-bit faults of the original
source (the random numbers, a distance kept in an `int`). The comparison of the Atari816
with the 16-bit twin exposed the remaining ones (products that overflow only in 16 bits)
and the port's memory faults ([ports/simcity/PORTING-NOTES.md](../../ports/simcity/PORTING-NOTES.md)).

## Ports as the compiler's acceptance test

The ports are large C programs written for other compilers (DOS's Watcom and Microsoft C,
Unix C, C++ translated to C), so they test cc816 on code not written for it. Compiler faults
they exposed that the compiler's own suites missed are now regression tests, for example a
signed array index whose constant part made the access read the next bank (Prince of
Persia, `tests/regress/r040_signed_index_offset.c`), a structure defined in a declaration
of several objects (Digger), and a header with code page 437 bytes that stopped the
compiler (Xargon). Old code also required options that cc816 now has: C89's implicit `int`
(the Micropolis source has 248 functions without a return type), more arguments than the
prototype, DOS's right-to-left argument order, and the far data model, DOS's large model,
for X-COM. The compiler's conformance results are in
[sdk/docs/c/reference.md](../../sdk/docs/c/reference.md), "Conformance".

## Timing models measured on the board

The emulator's timing is fitted to these board measurements:

- CPU and memory: `core/sw/a816/timing.s` (TIMING.BIN) on the board, loop by loop, in four
  video and classic-machine states. The emulator is within 7 % on every loop, most within
  2 % ([emu/README.md](../../emu/README.md), "Memory timing").
- Blitter: the cycles per pixel of each operation, from the same program.
- SD card: the X-COM port's I/O benchmark (`/IOB`), run on the board with two firmware
  versions and in the emulator on the same folders. Every line is within 6 %
  ([emu/README.md](../../emu/README.md), "The card's speed").

The colour remap's cost in the emulator (+12 %) comes from the RTL simulation. On the
board, X-COM's night screen drawn through the remap took 4.21 ms against 3.78 ms by day
(+11 %). The card's write rate and folder operations are estimates, not measurements.

## Known gaps

- The board itself: the suites run in the emulator. The board is checked by hand and with
  its own test programs (`core/sw/a816/`), the RTL by Verilator simulations
  (`core/sim_a816/`). Neither is part of the suites above. Only the board exercises
  POKEY's sound, the joysticks (the emulator reads them as 0), the keyboard adapters'
  firmware and HDMI. The classic Atari is not in the emulator.
- Sound is checked by measurement only: chip writes, levels and clipping of recordings.
- Open faults on the board are listed in [core/KNOWN_ISSUES.md](../../core/KNOWN_ISSUES.md):
  the HDMI picture lost now and then, a desktop without input after F12 during a disk load,
  a restart seen once.
- The ports that need the game's files (Xargon, Prince of Persia, X-COM, SkyRoads) can be
  tested only where those files are. Digger's and Micropolis' data are in the repository.
