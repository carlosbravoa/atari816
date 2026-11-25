# Testing

A program is tested by building it, running it in the emulator under Horizon with
scripted input, and checking what it produced: its console lines, the files it wrote, its
screenshots and its sound writes. The tests run unattended. The tools' options are in
[tools.md](tools.md). A short form for coding agents is the skill's
`references/testing.md` (`sdk/skill/atari-816-dev`).

## make targets

```
make            # NAME.PRG
make run        # build/run/: console.txt, shot1.png ...
make test       # build/test/: the same with test.script and the checks
```

These are the targets of a program made with `sdk/c/c.mk`. An assembly template's Makefile
has the same targets. They run `sdk/tools/run816.py`, and one run writes:

- `OUT/console.txt`: everything printed on the kernel console: every `printf` and
  `hz_puts` line, the shell's echo, `[kill]` lines.
- `OUT/emu.err`: the emulator's log: sound writes (`--log-sound`, `--log-lau`,
  `--log-opl`), blitter rule reports.
- `OUT/shotN.png`, `OUT/autoN.png`: screenshots (1280 x 720, each screen pixel 2 x 2)
  from `--shot` and script `shot` lines, and from `--shot-on`.
- `OUT/card/`: the card after the run, with the files the program wrote.

Under the Desktop (`--mode desktop`) a program's `printf` output goes only to
`console.txt`, not to the screen. Console lines are therefore usable as test evidence for
window programs and games too.

## Progress lines

A test that depends on the clock breaks when any part of the system gets faster or
slower. Instead, the program prints a line at each state a test needs, and the script
waits for that line:

```c
printf("sum of %d arguments: %ld\n", argc - 1, total);   /* the sum is done */
...
printf("saved %s in SUM.TXT\n", name);                   /* after fclose */
```

```
# type a name once the program has started (it prints the sum first), then wait
# for its reply
0 wait sum of
+300 Ada\n
+0 wait saved Ada
```

(From `sdk/skill/atari-816-dev/examples/console`: its `main.c` and `test.script`.) The
ports work the same way: Digger prints `digger: title`, `digger: play` and `digger: dead`,
and its script waits for them. Print the line after the program has closed its files, so
that a run that stops at that line (`--stop-on`) finds them complete.

## Input scripts

The language is that of [inputscript.py](tools.md#inputscriptpy). Guidelines for
reliable scripts:

- Wait for the program instead of guessing times. `+0 wait TEXT` right after an input
  line is the normal way to wait for the program's reply to that input. A line printed
  since that input line began counts (also one printed while its keys were still down).
  A line from before it does not. In shell and desktop mode, `0 wait` matches everything
  printed since the start.
- One printed line ends one wait. Two waits for the same text need the program to print
  it twice.
- Take pictures of states, not of moments. `+0 still 30` then `+0 shot` (the emulator of
  Horizon 0.31) continues when the screen has not changed for 30 frames, then takes the
  picture. The picture is the same whatever the speed of the CPU or the kernel.
- Give a `move` time before the `click` (`+100 click`): the click does not wait for the
  move's steps. Two clicks at one place less than about a second apart are a double click.
- Keys typed while a menu is open go to the menu. In desktop mode Files is open at
  (24, 24) and has the focus until your window opens. Your menus come after "Horizon" and
  "Programs". A window opened at (x, y) has its content at (x + 1, y + 16).
- `python3 sdk/tools/inputscript.py FILE --keys` prints the script's events with their
  times.

## Screenshots

- `--shot S` and `shot` lines are taken at a time. They suit windows and still screens and
  are fragile for games.
- `--shot-on TEXT` takes the picture at a point the program chooses. The program prints a
  line when the screen shows the state to check and holds the picture still for a few
  frames (the shot is taken two frames after the line). Digger stops at given frames of a
  recorded game, waits two vertical blanks, prints `digger: shot N frame F` and holds six
  frames.
- Look at every picture you take. For many at once: `python3 sdk/tools/contact.py
  sheet.png build/test/shot*.png` (half size: a sheet pixel is a screen pixel, so
  coordinates read off the sheet are `move X Y` coordinates).

## Checks

- Console output: `--expect 'exact text'` (repeatable) with the values (`score=125
  level=1`, not `score=`), or grep `OUT/console.txt` in a check script.
- Crashes: a `[kill] task N NAME cause CC addr ... pc ...` line makes run816.py exit 1.
  The low 16 bits of `pc`, looked up in `NAME.lbl` (`hcc --map`), give the function.
- Files written: `OUT/card/` (shell mode starts programs in `/`). Check their contents,
  not only that they exist.
- POKEY: `--log-sound`, then grep `emu.err` for the writes (`sound $DB08 = $78`) or count
  them.
- Lau and the OPL2: `--log-lau`, `--log-opl`, then count the `lau ` and `opl ` lines.
- Audible sound: `--wav FILE` records Lau and the OPL2 as the board mixes them. Xargon's
  `tests/wavcheck.py` requires an RMS above 500 and under 0.05 % clipped samples. hgame's
  tests require a peak above 1000.
- Self-tests: the program prints `PASS ...` and `FAIL ...` lines. The checker fails on any
  FAIL and also when there is no PASS at all (as `sdk/c/game/tests/run.py` does).
- Indexed accesses: `--log-bankwrap` reports an indexed access that carries into the next
  bank.

### Reference pictures

Three methods are in use:

- Pixel for pixel (Digger, `ports/digger/tests/cmpshots.py`): Pillow's
  `ImageChops.difference(a, b).getbbox()` must be `None`.
- MD5 of the pixels (Xargon, Prince of Persia, Micropolis: `tests/shots.py`): only the
  pictures' checksums are committed. For the first two, the pictures show the user's own
  game data.
- A small share of differing pixels allowed (hgame, `sdk/c/game/tests/run.py`): the test
  fails above 0.2 % and writes `NAME-diff.png`.

Make new references (`make refs`, `--update`) only after looking at the pictures. A
picture taken at a time changes with any timing change. One taken at a state (`still`, or
`--shot-on` at a frame of a recording) does not.

## make test

`make test` of `sdk/c/c.mk` runs run816.py with `RUNFLAGS` and `TESTFLAGS`, then the shell
command `TESTCHECK`. The test fails when that command fails:

```make
NAME      := sum
SDK       ?= ../../../..
ARGS      := 2 40
TESTFLAGS := --expect 'sum of 2 arguments: 42' --expect 'saved Ada in SUM.TXT'
TESTCHECK := test "$$(cat build/test/card/SUM.TXT)" = "Ada 42" && echo "PASS  SUM.TXT"
include $(SDK)/c/c.mk
```

This Makefile, from the same example, types the arguments at the shell, expects two
console lines, and checks the file the program wrote on the card after the run. The
templates' tests show three kinds:

- `sdk/templates/c-console`: shell mode, `ARGS`, three `--expect`s.
- `sdk/templates/c-window-app`: desktop mode, shots, `TESTCHECK` on a file it wrote.
- `sdk/templates/c-game`: `--log-sound`, `--expect`s, `TESTCHECK` on `emu.err`.

The skill's three examples (`sdk/skill/atari-816-dev/examples`) are smaller complete ones.

## Host twin

A port's most thorough test compares it with the same C built on the PC. `host16.py`
([tools.md](tools.md#host16py)) builds the program with the PC's compiler and the
Atari816's integer sizes. Both builds read the same input (a recorded game, a replay, a
scripted session) and print their state at each step, and a script compares the two
outputs line by line. The first difference is the step where 16-bit arithmetic, an
uninitialised variable or the order of evaluation made the two programs diverge. In the
ports:

- Micropolis: the simulator on the Atari816 against two PC twins (host16, and upstream's
  own types), 5,000 ticks of ten cities, the whole state equal every 100 ticks.
- X-COM: 16 scripted runs of every screen on both builds, with the same log, the same
  pictures pixel for pixel, and the same saves.
- Prince of Persia: four recorded games end state for state as on the PC, and their
  pictures equal the PC's pixel for pixel.

([c/porting.md](c/porting.md), "Test it", and each port's README.) Digger is checked
against its own reference pictures of a recorded game instead.

host16.py cannot make the arithmetic of intermediate results 16 bits (the PC adds two
shorts in 32 bits). The comparison shows where that matters, and the port's fix-ups
(`--fixups FILE`) record each place.

## Timing

- Use `wait` and `still` lines, not long fixed delays.
- Verify that the test does not depend on speed. Digger reads `DELAY.TXT` and delays its
  start, and its scripted game must still pass with 1.5 and 3 s. Xargon runs its demo
  again with `/BUSY:30` (30 ms more CPU time each frame) and requires the same state line.
  `--emu-arg --cpu-slow --emu-arg 30` slows the emulated CPU itself.
- `--emu-arg --ram-random --emu-arg 5` fills memory with values the board might hold. A
  program that reads memory it never wrote then behaves differently.
- Independent emulator runs can run in parallel (`&` and `wait` in sh).

## Test criteria

- Every test checks something the program produced. A run without a `[kill]` line shows
  only that the program did not crash.
- Check the end state: the high-score file holds `HZD 125`, the saved game loads where it
  was saved.
- Same input, same result: use scripts and recordings, never the clock or a random seed
  taken from it. (`SYS_UPTIME` has the same value at the same point of every run in the
  emulator, so a seed from it repeats there and not on the board.)
- Break the program on purpose once and confirm that the test fails.
- Record what was not checked. The emulator does not play POKEY (it logs it), its
  joysticks read "nothing pressed", and the keyboard adapter's firmware and the card's
  real speed exist only on the board. emu816 models the card's speed with `--card-board`,
  which run816.py turns on from the program's start.

## On the board

`sdk/tools/deploy816.py` copies a program to the board over the PC link, starts it and
takes a screenshot ([tools.md](tools.md#board-atari816-link-ataripy-deploy816py)). emu816
models the board's timing within a few per cent (its README describes the measurements).
Only the board has POKEY's sound, the joysticks, the keyboard adapter's behaviour and the
HDMI picture itself.
