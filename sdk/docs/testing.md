# Testing without a person

Every program in this repository is tested the same way: built, run in the emulator under
the real Horizon with scripted input, and checked by what it produced (its console lines,
the files it wrote, its pictures, its sound writes). No one has to watch. This chapter
says how to do that for your own program, and which test suites the SDK itself has. The
tools' options are in [tools.md](tools.md); the short form for coding agents is the
skill's `references/testing.md` (`sdk/skill/atari-816-dev`).

## The loop

```
make            # NAME.PRG
make run        # build/run/: console.txt, shot1.png ...
make test       # build/test/: the same with test.script and the checks
```

(a program made with `sdk/c/c.mk`; an assembly template's Makefile has the same targets).
Behind them is `sdk/tools/run816.py`. One run writes:

| File | What |
| --- | --- |
| `OUT/console.txt` | everything printed on the kernel console: every `printf` and `hz_puts` line, the shell's echo, `[kill]` lines |
| `OUT/emu.err` | the emulator's log: sound writes (`--log-sound`, `--log-lau`, `--log-opl`), blitter rule reports |
| `OUT/shotN.png`, `OUT/autoN.png` | screenshots (1280 x 720: each screen pixel 2 x 2) from `--shot` and script `shot` lines, and from `--shot-on` |
| `OUT/card/` | the card after the run: the files the program wrote |

Under the Desktop (`--mode desktop`) a program's `printf` goes only to `console.txt`, not
to the screen: that is what makes console lines useful as a test's evidence for window
programs and games too.

## Make the program say where it is

A test that follows the clock breaks when anything gets faster or slower. Let the program
print a line at each state a test needs, and let the script wait for it:

```c
printf("sum of %d arguments: %ld\n", argc - 1, total);   /* the sum is done */
...
printf("saved %s in SUM.TXT\n", name);                   /* after fclose */
```

```
# type a name once the program has started (it prints the sum first), then wait
# for its answer
0 wait sum of
+300 Ada\n
+0 wait saved Ada
```

(`sdk/skill/atari-816-dev/examples/console`: its `main.c` and `test.script`; `make -C
sdk/c test` builds and runs it.) The ports do this: Digger prints `digger: title`, `digger: play`, `digger: dead`; its
script waits for them. Print a line after the program has closed its files, so a run that
stops at that line (`--stop-on`) finds them complete.

## Input scripts

The language is [inputscript.py](tools.md#inputscriptpy)'s. Rules that keep scripts
reliable:

- **Wait for the program, do not guess times.** `+0 wait TEXT` right after an input line
  is the normal way to wait for the program's answer to it: a line printed since that
  input line began counts (also one printed while its keys were still down), a line from
  before it does not. In shell and desktop mode `0 wait` sees everything printed since
  the start.
- One line ends one wait: two waits for the same text need the program to print it twice.
- **Pictures of states, not of moments.** `+0 still 30` then `+0 shot` (Horizon 0.31's
  emulator) waits until the screen has not changed for 30 frames, then takes the picture:
  the same picture whatever the speed of the CPU or the kernel.
- Give a `move` time before the `click` (`+100 click`): the click does not wait for the
  move's steps. Two clicks at one place less than about a second apart are a double click.
- Keys typed while a menu is open go to the menu. In desktop mode Files is open at
  (24, 24) and has the focus until your window opens; your menus come after "Horizon" and
  "Programs". A window opened at (x, y) has its content at (x + 1, y + 16).
- `python3 sdk/tools/inputscript.py FILE --keys` prints what the script becomes: a quick
  check of its timing.

## Screenshots

- `--shot S` and `shot` lines are taken at a time: good for windows and still screens,
  fragile for games.
- `--shot-on TEXT`: the program decides. It prints a line when the screen shows the state
  to check and holds the picture still for a few frames (the shot is taken two frames
  after the line). Digger stops at given frames of a recorded game, waits two vertical
  blanks, prints `digger: shot N frame F` and holds six.
- Look at every picture you take. Many at once: `python3 sdk/tools/contact.py sheet.png
  build/test/shot*.png` (half size: a sheet pixel is a screen pixel, so coordinates read
  off it are `move X Y` coordinates).

## Checks

| What | How |
| --- | --- |
| Console output | `--expect 'exact text'` (repeatable) with the values (`score=125 level=1`, not `score=`); or grep `OUT/console.txt` in a check script |
| No crash | a `[kill] task N NAME cause CC addr ... pc ...` line makes run816.py exit 1. The low 16 bits of `pc` in `NAME.lbl` (`hcc --map`) name the function |
| Files written | `OUT/card/` (shell mode starts programs in `/`): check their contents, not that they exist |
| POKEY | `--log-sound`: grep `emu.err` for the writes (`sound $DB08 = $78`) or count them |
| Lau, the OPL2 | `--log-lau`, `--log-opl`: count the `lau ` and `opl ` lines |
| Sound heard | `--wav FILE`: Lau and the OPL2 as the board mixes them; Xargon's `tests/wavcheck.py` wants an RMS above 500 and under 0.05 % clipped samples, hgame's tests a peak above 1000 |
| Self-tests | the program prints `PASS ...` / `FAIL ...` lines; the checker fails on any FAIL **and on no PASS at all** (`sdk/c/game/tests/run.py`) |
| Indexes | `--log-bankwrap`: an indexed access that carries into the next bank is reported |

### Reference pictures

Three ways are in use:

- **Pixel for pixel** (Digger, `ports/digger/tests/cmpshots.py`): Pillow's
  `ImageChops.difference(a, b).getbbox()` must be `None`.
- **MD5 of the pixels** (Xargon, Prince of Persia, Micropolis: `tests/shots.py`): only
  the pictures' checksums are committed (for the first two, the pictures show the user's
  own game data).
- **A small share allowed** (hgame, `sdk/c/game/tests/run.py`): fail above 0.2 % of
  differing pixels and write `NAME-diff.png`.

Make new references (`make refs`, `--update`) only after looking at the pictures. A
picture taken at a time moves with any timing change; one taken at a state (`still`,
`--shot-on` at a frame of a recording) does not.

## make test

`sdk/c/c.mk`'s `make test` runs run816.py with `RUNFLAGS` and `TESTFLAGS`, then the shell
command `TESTCHECK`, which fails the test when it fails:

```make
NAME      := sum
SDK       ?= ../../../..
ARGS      := 2 40
TESTFLAGS := --expect 'sum of 2 arguments: 42' --expect 'saved Ada in SUM.TXT'
TESTCHECK := test "$$(cat build/test/card/SUM.TXT)" = "Ada 42" && echo "PASS  SUM.TXT"
include $(SDK)/c/c.mk
```

(the same example's Makefile: the arguments typed at the shell, two console lines
expected, and the file the program wrote checked on the card after the run.) The templates' tests show the three kinds: `sdk/templates/c-console` (shell mode, `ARGS`,
three `--expect`s), `sdk/templates/c-window-app` (desktop mode, shots, `TESTCHECK` on a
file it wrote), `sdk/templates/c-game` (`--log-sound`, `--expect`s, `TESTCHECK` on
`emu.err`). The skill's three examples (`sdk/skill/atari-816-dev/examples`) are smaller
complete ones, built and run by `make -C sdk/c test`.

## The host twin

A port's strongest test compares it with the same C built on the PC. `host16.py`
([tools.md](tools.md#host16py)) builds the program with the PC's compiler and the
Atari816's integer sizes; both builds read the same input (a recorded game, a replay, a
scripted session) and print their state at each step, and a script compares the two
outputs line by line. A difference names the step where the 16-bit arithmetic, an
uninitialised variable, or the order of evaluation made the two programs part. In the
ports:

- **Micropolis**: the simulator on the Atari816 against two PC twins (host16, and
  upstream's own types), 5,000 ticks of ten cities, the whole state equal every 100 ticks.
- **X-COM**: 16 scripted runs of every screen on both builds: the same log, the same
  pictures pixel for pixel, the same saves.
- **Prince of Persia**: four recorded games end state for state as on the PC, and their
  pictures are equal to the PC's pixel for pixel.

([c/porting.md](c/porting.md), "Test it", and each port's README.) Digger is checked
against its own reference pictures of a recorded game instead.

What host16.py cannot make 16 bits is the arithmetic of intermediate results (the PC adds
two shorts in 32 bits); the comparison is what shows where that matters, and the port's
fix-ups (`--fixups FILE`) record each place.

## Timing in tests

- Use `wait` and `still` lines, not long fixed delays.
- Prove that the test does not depend on speed. Digger reads `DELAY.TXT` and delays its
  start; its scripted game must still pass with 1.5 and 3 s. Xargon runs its demo again
  with `/BUSY:30` (30 ms more CPU each frame) and wants the same state line.
  `--emu-arg --cpu-slow --emu-arg 30` slows the emulated CPU itself.
- `--emu-arg --ram-random --emu-arg 5` fills memory with what the board might have: a
  program that reads memory it never wrote shows it.
- Independent emulator runs can run in parallel (`&` and `wait` in sh).

## What a pass must mean

- **A test that checks nothing is not a test.** A run without a `[kill]` only proves that
  the program did not crash. Every test checks something the program produced.
- **Check the end state**: the high-score file holds `HZD 125`; the saved game loads where
  it was saved.
- **Same input, same result**: scripts and recordings, never the clock or a random seed
  from it. (`SYS_UPTIME` is the same at the same point of every run in the emulator, so a
  seed from it repeats there and not on the board.)
- **A test must be able to fail**: break the program on purpose once and see the test
  fail (Digger with an emerald drawn two rows short: 7 of 9 pictures failed).
- **Say what was not checked**: the emulator does not play POKEY (it logs it), its
  joysticks read "nothing pressed", and the keyboard adapter's firmware and the card's
  real speed are the board's alone (emu816 models the card's speed: `--card-board`,
  which run816.py turns on from the program's start).

## The SDK's own suites

| Command | What it runs |
| --- | --- |
| `make -C sdk check` | the assembly reference against horizon.inc and the kernel (`abicheck.py`), every reference example assembled and linked (`snippets.py`) |
| `make -C sdk test` | `make check`, every assembly template and example (`make test` of each), then `make -C sdk/c test` |
| `make -C sdk/c check` | `hzsys.h` and the controls library's binding against Horizon's sources (`gensys.py --check`, `genhui.py --check`), the manual's completeness (`doccheck.py`), the manual's site and its links (`mkmanual.py --check`) |
| `make -C sdk/c test` | `make check`, the host twin's test (`tests/host16`), every test of `tests/run.py` (the C library, syscalls, code generation, floating point bit for bit, `long long`, the stacks, the benchmarks, the runtime's tables, the driver's messages, the controls library, apps, a program of 180 KB of code) in the three configurations, the C examples and templates, hgame's tests (`make -C sdk/c/game test`), the large model and far data with three examples each, and the skill's examples and text |
| `make -C sdk/c/cc816 check` | the compiler's own set ([c/compiler.md](c/compiler.md), "How it is tested") |
| `make -C emu test` | the emulator's CPU tests and its assembly tests |
| `make -C horizon test` | Horizon's tests: the kernel, the programs, the pictures (`horizon/tests`) |
| `make -C ports/NAME test` | each port's tests (`make test-app` installs and starts its app; SkyRoads, an experiment, has `make check`). X-COM, Prince of Persia, Xargon and SkyRoads need the user's own game files; Digger's and Micropolis's data are in the repository |

Each of them needs the emulator and Horizon built first (`make -C emu`, `make -C
horizon`). They print `PASS` / `FAIL` lines and end with a summary line and an exit
status. Run them in a fresh copy of the tree when it matters: objects left from an older
build have hidden faults before.

## On the board

`sdk/tools/deploy816.py` copies a program to the board over the PC link, starts it and
takes a screenshot ([tools.md](tools.md#the-board-atari816-link-and-ataripy)). emu816 models the board's timing
within a few per cent (its README says how it was measured); what only the board shows is
POKEY's sound, the joysticks, the keyboard adapter's behaviour and the HDMI picture
itself.
