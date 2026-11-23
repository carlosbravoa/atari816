# Testing programs in the emulator

Purpose: how to run, drive and check a Horizon program in emu816 (`sdk/tools/run816.py`),
and how to write a `make test` whose PASS means something. `SDK` = the `sdk` folder,
`HORIZON` = the Horizon tree (`SDK/../horizon`) with a built card.

## run816.py

```
python3 SDK/tools/run816.py PROG.PRG [options]      # PROG '-' with --mode none: no program
```

It copies `HORIZON/build/sd` to `OUT/card`, puts the program on it (default
`/APPS/NAME.PRG`), boots emu816 headless, starts the program, plays the script, and writes:

| File | What |
| --- | --- |
| `OUT/console.txt` | the kernel console: every `printf`/`hz_puts` line, the shell's echo, `[kill]` lines |
| `OUT/emu.err` | emu816's log: `--log-sound`/`--log-lau` writes, blitter rule reports |
| `OUT/shotN.png` | screenshots from `--shot` and script `shot` lines (1280 x 720, each screen pixel 2 x 2) |
| `OUT/autoN.png` | screenshots from `--shot-on` |
| `OUT/card/` | the card after the run: files the program wrote are here |

Options worth knowing (all from `run816.py --help`):

| Option | Use |
| --- | --- |
| `--mode desktop` | default. The Desktop boots and starts the program from its Programs menu (time 0 = 5 s). No arguments. Console output only in `console.txt` |
| `--mode shell` | the text shell types the path and `--args`; console output on the screen too. Time 0 about 3-4 s |
| `--mode none` | the Desktop boots, nothing is started (time 0 = Desktop up): installing an app, opening menus. Program `-` puts nothing on the card |
| `--args TEXT` | argument string (shell mode) |
| `--dest PATH`, `--cd DIR` | where the program goes; `--cd` types `cd DIR` first (shell) |
| `--script FILE` | input script (below) |
| `--shot S` | screenshot at S seconds after the start (repeatable; at most 16 with the script's `shot` lines) |
| `--shot-on TEXT` | `autoN.png` two frames after each console line holding TEXT |
| `--seconds N` | run length after the start (default: last event + 2 s, + 20 s per `wait`) |
| `--stop-on TEXT` | end the run at the first console line holding TEXT (repeatable: any of them); `--seconds` stays the limit. Prints `run816: stopped on 'TEXT' at T s`. Later shots are not taken |
| `--stop-on-delay MS` | end it MS ms after that line (default 0). Better: print the line after the program has closed its files |
| `--must-stop` | fail (exit 1) when the run reached `--seconds` without a `--stop-on` text |
| `--console-times` | each `console.txt` line starts with its emulated time since power-on: `[   3.785939] text` |
| `--out DIR` | output folder (default `run-NAME`); old shots in it are deleted |
| `--file SRC[:DEST]` | copy a file onto the card (default: the root, its name in capitals: `main.c` → `/MAIN.C`; repeatable) |
| `--expect TEXT` | fail unless `console.txt` contains TEXT (repeatable) |
| `--log-sound` / `--log-sound-us` | POKEY writes in `emu.err`: `sound $DB08 = $78` / `sound 149861 $DB01 = $00` (µs) |
| `--log-lau` / `--log-lau-us` | Lau writes: `lau $DBxx = $yy` / `lau 3785939 $DBxx = $yy` (µs) |
| `--wav FILE` | record Lau + OPL2 (48 kHz stereo, as the board mixes; no POKEY) |
| `--rev N` | hardware: 12 default (OPL2), 11 no OPL2, 10 no sprites/scrolling, 9 no Lau, 8 no command lists, 7 no blitter |
| `--kbd-release MS` | release held keys MS ms after the last key change (the board's old firmware: 1000) |
| `--prof FILE --prof-from S --prof-to S` | cycle profile (`references/performance.md`) |
| `--net`, `--net-root DIR` | internet through an emulated PC link |
| `--window` | SDL window, real time, play by hand (emu816 built with `make SDL=1`) |

Exit code 1 when the program was killed (`[kill]`), an `--expect` text is missing, a
`wait` never ended, emu816 reported a blitter rule broken, or `--must-stop` saw no
`--stop-on` text. A run stopped by `--stop-on` and one that ran to `--seconds` both exit 0;
the printed line tells them apart (`run816: stopped on ...` / `run816: no --stop-on text
came`). Times: `--console-times`, `--log-lau-us`, `--log-opl-us` and `--log-sound-us` count
from power-on (`[   3.785939]` is `lau 3785939`); `--shot`, `--prof-from` and script times
count from the program's start, which run816 prints (`started at 3.9 s`). A run of 20 emulated seconds
takes about a second. Facts: emu816 runs at the board's speed (`--ideal-timing`: the old,
faster model); joysticks read "nothing pressed" (they cannot be scripted); POKEY is not
heard (only logged); `SYS_UPTIME` is the same at the same point of every run, so a random
seed from it repeats.

## Input scripts (sdk/tools/inputscript.py)

One event per line; `#` comments and blank lines ignored. Each line starts with a time in
ms after the program's start: absolute (`2000`) or relative to the previous line (`+500`).

| Line | Does |
| --- | --- |
| `T text` | type text: a key every 50 ms, held 20 ms; capitals and symbols hold left Shift |
| `T key NAME MS` | hold one key MS ms (game controls) |
| `T down NAME` / `T up NAME` | press and keep / release (also `lshift lctrl lalt rshift rctrl ralt`) |
| `T move X Y` | pointer to screen pixel (640 x 360 space), steps of 100 px every 20 ms; starts at 320, 180 |
| `T click [left\|right\|middle]` | press and release (80 ms) where the pointer is |
| `T dclick` | double click (left) |
| `T press [btn]` / `T release` | hold / let go of a button |
| `T drag X Y` | move with the button held, 16 px every 30 ms (after `press`; `release` after the drag's time) |
| `T wheel N` | wheel steps, positive = up |
| `T M dx:dy:wheel:buttons` | one raw relative mouse event |
| `T shot` | screenshot |
| `T wait TEXT` | nothing more happens until the program prints a console line holding TEXT, or at once if it printed one since the input line before the wait began (even while that line's keys were still being sent). The wait starts after every key and button event of the lines before it (a click's release, a held key's release); every later time counts from its end. One line ends one wait. Shots after a wait move with it |

Escapes in typed text: `\n` Enter, `\b` Backspace, `\t` Tab, `\\` backslash, `^A`..`^Z`
ctrl+letter, `{esc} {up} {down} {left} {right} {home} {end} {pgup} {pgdn} {ins} {del}
{tab} {enter} {space} {bksp} {f1}`..`{f12}`, `{alt-x}`, `{ctrl-x}`, `{dXX}`/`{uXX}` raw
key down/up by HID usage in hex.

A script that follows the program (verified, `make test` of a scratch console program):

```
# wait for the program's line, then type, then wait for its answer
0 wait t1: ready
+300 shot
+200 Ada\n
+0 wait t1: saved Ada
+300 shot
```

`python3 SDK/tools/inputscript.py FILE --keys` (or `--mouse`, `--shots`) prints the
emu816 lists: a quick check of a script's timing.

Script rules:

- **Wait for the program, do not guess times.** Let the program print a line at each
  state a test needs (Digger: `digger: title`, `digger: play`, `digger: dead`, `digger:
  initials`) and write `+0 wait digger: play`. Digger's fixed-time script broke when
  Horizon 0.29's Desktop started programs a little later.
- **`+0 wait` right after an input line is the normal way** to wait for the program's
  answer to it: `+300 Ada\n` then `+0 wait t1: saved`; `click` then `+0 wait CLICKS: 1`.
  A line the program printed since that input line began counts, also one printed while
  its keys were still down; a line from before it does not (it answered something else).
  In shell and desktop mode, `0 wait` sees everything the program printed since it was
  started.
- Two waits for the same text need the program to print it twice: one line ends one wait.
- Give a `move` time before the `click` (`+100 click`): the click does not wait for the
  move's steps.
- Two clicks at one place less than about a second apart are a double click: a button
  counts one (`examples/window/test.script`).
- Keys typed while a menu is open go to the menu. In desktop mode Files is open at
  (24, 24) and has the focus until your window opens; your menus come after "Horizon"
  and "Programs".
- A window opened at (x, y) has its content at (x + 1, y + 16).

## Screenshots: --shot, shot lines, --shot-on

- `--shot S` and `shot` lines: at a time. Good for windows and still screens; fragile for
  games (a frame earlier or later is another picture).
- `--shot-on TEXT`: the program decides. It prints a line when the screen shows the state
  to check, and keeps the picture still for a few frames (the shot is taken two frames
  after the line). Digger stops at given game frames of a replay, waits two vertical
  blanks, prints `digger: shot N frame F`, then holds six blanks.
- A shot can catch a sprite between erase and redraw: if that happens often, the board
  flickers too.

## Looking at screenshots

Open every PNG you take and look at it (an agent can read PNG files as images). For
many, one sheet:

```
python3 SDK/tools/contact.py build/test/sheet.png build/test/shot*.png
python3 SDK/tools/contact.py build/test/crop.png build/test/shot2.png --full --crop 150,80,340,220
```

Half size (default): one sheet pixel = one screen pixel, so coordinates read off the sheet
are `move X Y` coordinates. `--full --crop X,Y,W,H` zooms into a part (screen pixels).
Each shot is labelled with the number in its file name; a sheet that mixes `shot1` and
`auto1` labels each with its whole name. Look for: text cut or overlapping, controls off the grid,
trails of erased sprites, wrong colours, things not redrawn after a dialog closed.

## Checks

| What | How |
| --- | --- |
| Console output | `--expect 'exact text'`; or grep `OUT/console.txt` in a check script |
| Crashes | `[kill] task 4 KILL cause 03 addr 7F0000 pc 070237` in `console.txt`, run816 exit 1. Low 16 bits of `pc` in `NAME.lbl` (`hcc --map`) name the function (`references/pitfalls.md`, "Faults") |
| Files written | the card is `OUT/card/` (shell mode starts programs in `/`): `grep -q '^name=Ada' build/test/card/RESULT.TXT` |
| POKEY | `--log-sound`; `grep -q 'DB01' OUT/emu.err` (any write) or a specific one: Digger checks `sound $DB08 = $78` (16-bit voices on) and more than 500 writes to `$DB04-$DB07` |
| Lau | `--log-lau`; count `^lau ` lines (Xargon wants more than 100) |
| Music / samples heard | `--wav FILE`: Xargon's `tests/wavcheck.py` wants RMS above 500 in the title and the game and under 0.05 % clipped samples; hgame's tests want a peak above 1000 |
| Program self-test | the program prints `PASS ...` / `FAIL ...` lines; the checker counts them and fails on any FAIL **or on no PASS at all** (`sdk/c/game/tests/run.py`) |

## Reference pictures

- **Pixel for pixel** (Digger, `tests/cmpshots.py RUN REFDIR NAME [--prefix auto]
  [--update]`): PIL `ImageChops.difference(a, b).getbbox()` must be `None`.
- **MD5 of the RGB pixels** (Xargon, `tests/shots.py RUN SUMS [--update]`): when the
  pictures may not be committed (game data). `hashlib.md5(Image.open(p).convert('RGB').tobytes())`.
- **A small share allowed** (hgame, `sdk/c/game/tests/run.py`): fail above 0.2 % of
  differing pixels, write `NAME-diff.png`.
- New references (`make refs`, `--update`, `--update-refs`) only after looking at the
  pictures. A reference made from a work-in-progress Horizon build differs on a clean
  checkout (Digger's frames 3, 4, 7 once did).
- Pictures at times move with any timing change (`make refs` again); pictures at game
  frames of a replay do not.

## make test with c.mk

`sdk/c/c.mk` targets: `make` (NAME.PRG), `make run` (`build/run/`), `make test`
(`build/test/`), `make clean`. `make test` runs run816 with `RUNFLAGS` + `TESTFLAGS`, then
the shell command `TESTCHECK`, which fails the test when it fails. Settings: `NAME`, `SDK`,
`SRCS`, `HZ_CODE`, `HCCFLAGS`, `RUNMODE` (shell default, or desktop), `ARGS`, `SCRIPT`
(default `test.script`), `RUNFLAGS`, `TESTFLAGS`, `TESTCHECK`, `HORIZON`.

```make
NAME      := t1
SDK       ?= ../../sdk
TESTFLAGS := --expect 't1: saved Ada' --shot-on 't1: snap'
TESTCHECK := grep -q '^name=Ada' build/test/card/RESULT.TXT && echo "PASS  RESULT.TXT holds the name" || \
             { echo "FAIL  RESULT.TXT (build/test/card)"; exit 1; }
include $(SDK)/c/c.mk
```

The templates' tests (all pass): `sdk/templates/c-console` (`--expect` of three lines,
shell mode with `ARGS`), `c-window-app` (desktop, shots, `TESTCHECK` on
`build/test/card/NAME.TXT`), `c-game` (desktop, `--log-sound`, four `--expect`s,
`TESTCHECK` greps `DB01` in `emu.err`). Replace their checks with your program's own.
Bigger tests: a `tests/check.sh` with `ok`/`bad` helpers printing `PASS`/`FAIL` and an
exit code (both ports), called from `TESTCHECK` or a `test` target.

## Timing in tests

- Use `wait` lines, not long fixed delays. A `wait` gives the run 20 s more.
- Prove it: Digger's program reads `DELAY.TXT` (ms) and delays its start; the scripted game
  must still pass with 1.5 and 3 s. Xargon runs its demo a second time with `/BUSY:30` (30
  ms more CPU each frame) and wants the same state line.
- `--seconds` must cover a whole replay (Digger's `drf.sh` gives 1500).
- Run independent emulator runs in parallel (`&` and `wait` in sh: Digger's `drf.sh`).

## What passes must mean

- **A test that checks nothing is not a test.** A run that ends without a `[kill]` only
  proves the program did not crash. Every test checks something the program produced.
- **Check the program's own output**: its console lines (`--expect` exact text with the
  values: `score=125 level=1`, not just `score=`), the files it wrote (contents, not
  existence), its pictures against references you looked at, its sound writes.
- **Check the end state, not the path**: the high-score file has `HZD 125`; the saved
  recording plays back to the same score; the loaded game is where it was saved.
- **Deterministic input**: scripts and recordings, never the clock. Same input, same
  result, run after run.
- **A test must be able to fail.** Break the program on purpose once (Digger drew an
  emerald two rows short: 7 of 9 pictures failed) and see it fail.
- **Self-tests**: zero PASS lines is a failure, not a pass.
- **Report honestly** what was verified by running and what was not (sound on the board,
  joysticks, the real card's speed: emu816's own `--card-kbps 170:100` models it, but
  run816.py does not pass it).

## Assembly, BASIC, the board

- `make -C SDK check`: the assembly reference checked against `horizon.inc` and the
  kernel, every reference example assembled. Run it after changing the reference.
- BASIC (`SDK/templates/basic-game`): `--args "-r /APPS/GAME.BAS"` runs a program;
  `--args "-t /APPS/TEST.BAS"` runs a test file and copies the console to the log.
- On the board (only when the user asks): `python3 SDK/tools/deploy816.py PROG.PRG --dest
  /BIN/PROG.PRG [--shot out.png]` over the PC link. emu816 models the board's timing
  within a few per cent (Xargon's notes); things only the board shows: POKEY's sound,
  joysticks, the keyboard adapter's firmware (Digger's held-key fault), the card's speed.
