# Tools

The SDK's programs for building, running, testing and packaging a program. The commands
are given from the repository's top folder, and every Python tool prints its whole help
with `-h`. The tools need Python 3. Those marked "Pillow" need it for PNG files
(`pip install pillow`). Those that build need cc65's ca65, ld65 and ar65 on the PATH.

| Tool | For |
| --- | --- |
| [hcc](#hcc) | C to a Horizon program in one command |
| [cc816.py](#cc816py) | the compiler alone: C to ca65 assembly |
| [c.mk](#cmk) | make rules for a C program (build, run, test) |
| [run816.py](#run816py) | running a program in the emulator: scripted input, screenshots, checks, sound, profiles |
| [inputscript.py](#inputscriptpy) | the input script language (keys, mouse, waits) |
| [emu816](#emu816) | the emulator |
| [prof816.py](#prof816py), [emu-prof.sh, emu-stats.sh](#emu-profsh-emu-statssh) | profiling |
| [contact.py](#contactpy) | many screenshots on one sheet |
| [img2c.py](#img2cpy), [img2inc.py](#img2incpy), [font2inc.py](#font2incpy) | pictures and fonts to C or assembly |
| [hzapp.py](#hzapppy) | apps: check, pack and list `.HZA` archives, make icons |
| [host16.py](#host16py) | a C program built on the PC with the Atari816's integer sizes (the host twin) |
| [atari816-link, atari.py, deploy816.py](#board-atari816-link-ataripy-deploy816py) | the real board over USB |
| [Program files](#program-files-and-linker-configurations) | the `.PRG` format, `prog.cfg`, `hzprog.cfg`, start-up code |

## hcc

`sdk/c/bin/hcc` compiles every `.c` with cc816, assembles every `.s` with ca65, links with
ld65 and the C library, and writes a program for the card.

```
sdk/c/bin/hcc -o HELLO.PRG hello.c
sdk/c/bin/hcc --code large -o GAME.PRG *.c art.s
sdk/c/bin/hcc --check-calls -I src src/*.c
```

It prints nothing when the build succeeds. With `--map` (which also writes NAME.map and
NAME.lbl) it prints the sizes of what it built:

```
SUM.PRG: 9,193 bytes on the card, 8 relocations
  code bank: code+constants 8,968 + data 84 + bss 1,143 = 10,195 of 57,072; heap 46,877; software stack 8,192
  window:    stack about 32,000 (from $7F7F down to $0100); direct page 120 bytes
```

Every option, grouped by purpose: [c/compiler.md](c/compiler.md), "Options".

Environment variables:

- `HZ_CODE`, `HZ_DATA`: the default `--code` and `--data`.
- `HZ_MAIN_ROOM`, `HZ_BANK_ROOM`, `HZ_SPREAD`: the large model's test placements.
- `HZ_BUILD`: where the libraries are built (default `sdk/c/build`).
- `CC816_TRACE=1`: a traceback with an internal compiler error.

`hcc --build-lib small large large-far` builds the C library for the three configurations
(`make -C sdk/c` does this). A build that needs a library builds it when a source is newer.

## cc816.py

`sdk/c/cc816/cc816.py` is the compiler without hcc, for reading its output.

```
python3 sdk/c/cc816/cc816.py -S -I sdk/c/include sdk/c/examples/hello/hello.c -o build/hello.s
python3 sdk/c/cc816/cc816.py --ir --time -S sdk/c/examples/hello/hello.c -o build/hello.s   # the IR and the passes' times on stderr
python3 sdk/c/cc816/cc816.py -E sdk/c/examples/hello/hello.c -o build/hello.i                # preprocess only
```

It takes the same language options as hcc, and `-S` (the default), `-c` (an object through
ca65), `-E`, `-o FILE`, `--ir`, `--time` and `--trace`. Only hcc links programs. Details:
[c/compiler.md](c/compiler.md).

## c.mk

`sdk/c/c.mk` holds make rules. A program's Makefile:

```make
NAME := greet
SDK  ?= ../..
include $(SDK)/c/c.mk
```

Targets:

- `make`: NAME.PRG (in capitals) from every `.c` and `.s` in the folder.
- `make run`: runs it in the emulator, output in `build/run/`.
- `make test`: runs it with the test's options and checks, output in `build/test/`.
- `make clean`.

Settings, before the `include` line or on make's command line: `SRCS`, `HZ_CODE`,
`HZ_DATA`, `HCCFLAGS`, `RUNMODE` (`shell`, the default, or `desktop`), `ARGS`, `SCRIPT`
(default `test.script` when the folder has one), `RUNFLAGS`, `TESTFLAGS`, `TESTCHECK` (a
shell command whose failure fails the test), `HORIZON`. Details:
[testing.md](testing.md#make-test).

## run816.py

`sdk/tools/run816.py` runs a program in emu816 under Horizon, headless, and writes the
results. It copies Horizon's card (`HORIZON/build/sd`) to `OUT/card`, puts the program on
it, boots, starts the program and plays the input script. It writes:

- `OUT/console.txt`: what was printed on the kernel console.
- `OUT/emu.err`: the emulator's log.
- `OUT/shotN.png`: screenshots, 1280 x 720 (`.ppm` without Pillow).
- `OUT/card/`: the card after the run.

```
python3 sdk/tools/run816.py SUM.PRG --mode shell --expect 'sum: 120003' --out build/try
python3 sdk/tools/run816.py GAME.PRG --script test.script --shot-on 'game: level' --out build/t
```

### Starting the program

- `--mode desktop` (default): the Desktop boots and starts the program from its Programs
  menu, with no arguments. Time 0 is the start, about 5 s after power-on.
- `--mode shell`: the text shell. The path and `--args` are typed at the prompt. For
  console programs and programs with arguments.
- `--mode none`: the Desktop boots and nothing is started (for a script that installs an
  app or opens menus). The program `-` puts nothing on the card.
- `--args TEXT`: the argument string (shell mode). It is at most 127 characters (the
  kernel's spawn), and the whole typed line at most 255 (the shell's line editor in
  Horizon 0.31; 77 before). run816.py rejects a longer one.
- `--cd DIR`: (shell) type `cd DIR` first. The path is then typed relative to it.
- `--dest PATH`: where the program goes on the card (default `/APPS/NAME.PRG`).
- `--file SRC[:DEST]`: copy a file onto the card too (repeatable). The default DEST is the
  root, the name in capitals.
- `--out DIR`: the output folder (default `run-NAME`).
- `--horizon DIR`: the Horizon tree with a built card (default `$HORIZON`, else `horizon/`
  next to the SDK).
- `--emu FILE`: the emulator (default `$EMU`, else `emu/emu816`).

### Input, time and pictures

- `--script FILE`: the input script ([inputscript.py](#inputscriptpy)).
- `--seconds N`: how long to run after the start. The default is the script's last event
  + 2 s, + 20 s for each `wait`.
- `--shot SECONDS`: a screenshot at that time (repeatable, 16 in all).
- `--shot-on TEXT`: a screenshot (`OUT/autoN.png`) two frames after each console line
  holding TEXT.
- `--stop-on TEXT`: end the run at a console line holding TEXT (repeatable).
  `--stop-on-delay MS` ends it MS ms later. `--must-stop` fails the run when no such line
  came.
- `--console-times`: each console line starts with its emulated time since power-on.
- `--kbd-release MS`: release held keys after MS ms without a key change (older board
  firmware did this after 1000 ms).
- `--window`: the emulator's SDL window instead, in real time (emu816 built with
  `make SDL=1`).

### Checks, sound and profiles

- `--expect TEXT`: fail unless `console.txt` holds TEXT (repeatable).
- `--log-sound`, `--log-sound-us`: every write to POKEY (and, before REV $0C, the DACs) in
  `emu.err`. The `-us` form adds the time in microseconds.
- `--log-lau`, `--log-lau-us`: every write to Lau, the sample player.
- `--log-opl`, `--log-opl-us`: every OPL2 register write.
- `--wav FILE`: record Lau and the OPL2 as the board mixes them (48 kHz stereo). POKEY is
  not recorded.
- `--log-bankwrap`: report every indexed access of the program that carries into the next
  bank.
- `--prof FILE`: cycles by instruction address, syscall, kernel and idle. `--prof-from S
  --prof-to S` limits it to a stretch (seconds after the start).
  [prof816.py](#prof816py) makes the table.

### Machine

- `--rev N`: the hardware revision. The default is emu816's, 13 (REV $0D, the blitter's
  colour remap). 12 has no remap, 11 no OPL2 (POKEY 2 and the DACs instead), 10 no sprites
  or scrolling, 9 no Lau, 8 no command lists, 7 no blitter.
- `--fast-card`: the card answers at once. Without it the card costs what the board's
  does from the program's start on (emu816 `--card-board-at`).
- `--net`: the internet through an emulated PC link (`tcp://` URLs are real connections
  of the PC).
- `--net-root DIR`: `http://`, `https://` and `ftp://` URLs are served from
  `DIR/host/path`.
- `--emu-arg ARG`: pass ARG to emu816 as it is (repeatable). `EMU816_ARGS` in the
  environment adds words to every run.

### Exit code

The exit code is 1 when the program was killed (`[kill]` on the console), an `--expect`
text is missing, a script `wait` never ended, emu816 reported a broken blitter rule, or
`--must-stop` was given and no `--stop-on` text came. A 20-second run takes about a
second on a PC.

## inputscript.py

`sdk/tools/inputscript.py` implements the input script language that run816.py reads and
turns a script into emu816's `--keys` and `--mouse` lists. A script has one event a line.
Each line starts with a time in milliseconds, absolute (`2000`) or after the line before
(`+500`). Time 0 is the program's start.

```
# wait for the program, type a name, wait for its answer, take a picture of the state
0 wait sum of
+300 Ada\n
+0 wait saved Ada
+0 still 30
+0 shot
```

(The script of the skill's console example, `sdk/skill/atari-816-dev/examples/console`,
with a picture of the state at the end.)

Lines:

- `T text`: type text. Escapes: `\n` `\b` `\t` `\\`, `^A`..`^Z`, `{esc} {up} {down} {left}
  {right} {home} {end} {pgup} {pgdn} {ins} {del} {tab} {enter} {space} {bksp}
  {f1}`..`{f12}`, `{alt-x}`, `{ctrl-x}`, and `{dXX}`/`{uXX}` for raw HID usages.
- `T key NAME MS`: hold one key for MS ms.
- `T down NAME`, `T up NAME`: press and hold, release (also `lshift lctrl lalt rshift
  rctrl ralt`).
- `T move X Y`, `T click [left|right|middle]`, `T dclick`, `T press [btn]`, `T release`,
  `T drag X Y`, `T wheel N`, `T M dx:dy:wheel:buttons`: the mouse, in screen pixels
  (640 x 360).
- `T shot`: a screenshot.
- `T wait TEXT`: the script continues when the program prints a console line holding
  TEXT. Later times move with it.
- `T still N`: (Horizon 0.31) the script continues when the screen has not changed for N
  frames. Followed by `shot`, this gives a picture of a state, independent of timing.

Run alone, the tool prints the lists, which shows a script's timing:

```
python3 sdk/tools/inputscript.py test.script --keys
python3 sdk/tools/inputscript.py test.script --mouse --offset 5000
python3 sdk/tools/inputscript.py test.script --shots
```

`--offset MS` adds MS to every time, as run816.py adds the start. Guidelines for test
scripts: [testing.md](testing.md#input-scripts).

## emu816

`emu/emu816` (`make -C emu`; `make -C emu SDL=1` for a window) is a C model of the native
machine: the 65C816, FREDDIE II, Marga, Ali, Lau, the OPL2 (Nuked OPL3), POKEY's
registers, the mailbox to the I/O processor with the SD card served from a folder, and the
PC link. run816.py drives it. Give it options through `--emu-arg`, or run it directly.
Its full documentation, including how its timing was measured against the board:
[emu/README.md](../../emu/README.md).

```
cp -r horizon/build/sd build/card        # the emulator writes to its card: use a copy
emu/emu816 --sd build/card --headless --max-seconds 20 --shot out.ppm build/card/SYSTEM/HORIZON.SYS
```

This boots Horizon, runs 20 emulated seconds (exit code 3: the time limit, the normal end)
and writes the last frame.

### Run

`--sd DIR` (the card), `--load FILE@ADDR`, `--max-seconds N` (exit code 3), `--headless`,
`--fast` and `--mute` (SDL builds: no real-time throttle, no live sound), `--rev N`.

### Input

`--keys LIST` (`t_ms:usage:down,...`, with the waits `W`, `Q`, `C`, `A`, the step mark `M`
and screenshots `S`: what inputscript.py writes), `--mouse LIST`, `--kbd-release MS`.

### Output

`--shot FILE.ppm` (repeatable) with `--shot-at SECONDS`, `--shot-on TEXT`
(`--shot-on-prefix`), `--stop-on TEXT` (exit code 4) with `--stop-on-delay MS`,
`--console-times`, `--wav FILE.wav`.

### Debugging

`--trace` (one line an instruction), `--prof FILE` with `--prof-from S` and `--prof-to S`,
`--stats`, `--watch ADDR[:LEN]` (every write into a range) with `--watch-max N`,
`--dump-ram FILE`, `--dump-ram-on TEXT` (`--dump-ram-prefix`), `--log-bankwrap`,
`--log-sound`, `--log-sound-us`, `--log-lau`, `--log-lau-us`, `--log-opl`,
`--log-opl-us`.

### Memory at power-on

`--ram-fill HH`, `--ram-random SEED`. Memory a program never wrote then holds what the
board's might, so a program that reads it behaves differently.

### Timing

- `--ideal-timing`: the model before Horizon 0.19, with no memory stalls, about twice the
  board's speed.
- `--cpu-slow PCT`, `--kernel-slow PCT`: test aids that show whether a program depends on
  the CPU's speed.
- `--console-us N`.

### Card

- `--card-board`: the board's card, request by request (the firmware of Horizon 0.30).
- `--card-board-old`: the same with v0.29's firmware.
- `--card-board-at S`, `--card-costs ...`.
- `--card-kbps R:W`: a simpler model.
- `--card-free BYTES`: a full card.
- `--card-date`, `--log-card`, `--boot-cart PATH`.

### PC link

`--pc-folder DIR` (the `/PC:` volume), `--pc-time`, `--pc-kbps R:W`, `--pc-drop-at S`,
`--pc-back-at S`, `--no-pc-print`, `--net`, `--net-root DIR`, `--net-delay MS`.

### Classic Atari

`--classic-print FILE@SECONDS`: the 8-bit side prints a file (a print job).

## prof816.py

`sdk/tools/prof816.py` prints a table of the CPU's cycles by the program's functions, each
syscall, the kernel and idle. Build with `hcc --map` (NAME.map and NAME.lbl), run with
`--prof`, then:

```
sdk/c/bin/hcc --map -o GAME.PRG *.c
python3 sdk/tools/run816.py GAME.PRG --script test.script --prof build/prof.txt --prof-from 5 --prof-to 15
python3 sdk/tools/prof816.py --counts build/prof.txt --map GAME.map --top 30
```

Options:

- `--counts FILE`: emu816's `--prof` counts (fast).
- `--map FILE`: the program's map.
- `--prg FILE`: the program, for the large model's other banks (matched by their bytes).
- `--top N`, `--out FILE`.
- A trace on stdin instead of `--counts`: `--from S --to S` (emulated seconds since
  power-on, from `emu816 --trace`). Slow, for short stretches.

Reading the table, and the cost of each operation:
[reference/performance.md](reference/performance.md) and the skill's
`references/performance.md`.

## emu-prof.sh, emu-stats.sh

`sdk/tools/emu-prof.sh` runs emu816 with `--trace` and pipes the trace through prof816.py
(set `PROF_MAP`, `PROF_FROM`, `PROF_TO`, `PROF_OUT`). `sdk/tools/emu-stats.sh` runs it with
`--stats` (the CPU's busy share, in `emu.err`). Both are used as `run816.py --emu
sdk/tools/emu-stats.sh ...`.

## contact.py

`sdk/tools/contact.py` (Pillow) puts several screenshots on one sheet, each labelled with
its number.

```
python3 sdk/tools/contact.py build/test/sheet.png build/test/shot*.png
python3 sdk/tools/contact.py build/test/crop.png build/test/shot2.png --full --crop 150,80,340,220
```

- `--half` (default): one sheet pixel is one screen pixel, so coordinates read off the
  sheet are `move X Y` coordinates.
- `--full`: full size.
- `--crop X,Y,W,H`: a part of each picture, in screen pixels.
- `--cols N`: pictures per row.

## img2c.py

`sdk/tools/img2c.py` (Pillow for PNG; text art needs nothing) converts pictures to hgame
images, as a C header or as an `.HGI` file that `hg_image_load()` reads from the card.

```
python3 sdk/tools/img2c.py sdk/c/examples/tutorial/art/ship.txt -o ship.h --name ship --key 0
python3 sdk/tools/img2c.py tiles.png -o TILES.HGI --tile 16x16 --key none
```

- `-o OUT.h|OUT.HGI`: the output.
- `--name NAME`: the C name.
- `--tile WxH`: a sheet cut into frames.
- `--key N|none`: the transparent colour (default 231). Hardware sprites need `--key 0`.
- `--own-palette BASE`: the picture's own colours at entries BASE, BASE + 1, ...
- `--bpp 4`: 16 colours.
- `--preview OUT.png`, `--scale N`.

The text-art format and the palette are in the tool's help and the skill's
`references/pixel-art.md`. The `.HGI` header is in the help. See also
[c/games.md](c/games.md), "Assets".

## img2inc.py

`sdk/tools/img2inc.py` converts the same pictures to a ca65 include file of 8 bpp pixels
for `win_draw`'s blits (assembly programs).

```
python3 sdk/tools/img2inc.py sdk/examples/lantern/art/moth.txt -o build/moth.inc --name moth
```

Options: `-o`, `--name`, `--tile WxH`, `--key N`, `--own-palette BASE` (adds `NAME_PALN`
and `NAME_PAL` for `ws_palette`), `--preview`, `--scale`.

## font2inc.py

`sdk/tools/font2inc.py` converts 1 bpp glyphs (a font, icons, big digits) to a ca65
include file, from a text file or a PNG grid (Pillow).

```
python3 sdk/tools/font2inc.py sdk/examples/lantern/art/bigfont.txt -o build/bigfont.inc --name bigfont --prop
```

Options: `-o`, `--name`, `--cell WxH` and `--first N` (a PNG grid), `--prop`
(proportional: an advance table), `--preview OUT.png`. `sdk/examples/lantern` uses it.

## hzapp.py

`sdk/tools/hzapp.py` handles apps: a program in its own folder with `APP.INF`, packed into
an `.HZA` archive that users install with a double click.

```
cd ports/digger && make app               # build/app/DIGGER/ and DIGGER.HZA
python3 ../../sdk/tools/hzapp.py check build/app/DIGGER
python3 ../../sdk/tools/hzapp.py pack build/app/DIGGER -o DIGGER.HZA --mtime 0
python3 ../../sdk/tools/hzapp.py list DIGGER.HZA
python3 ../../sdk/tools/hzapp.py icon PICTURE.png ICON.ICN --preview icon-big.png
```

(Digger's `make app` runs the `pack` line itself. Its data is in the repository.)

Commands:

- `hzapp.py check FOLDER|FILE.HZA`: the checks only (exit 1 on an error), and what the
  program itself checks at its start (its `--needs` block).
- `hzapp.py pack FOLDER [-o FILE.HZA] [--mtime N] [--needs-from-program]`: check, then
  pack. `--mtime N` gives every entry that time, for reproducible archives.
  `--needs-from-program` puts the program's own needs into the archive's APP.INF.
- `hzapp.py list FILE.HZA`: the entries and the APP.INF.
- `hzapp.py icon IMAGE.png OUT.ICN [--no-shadow] [--preview FILE.png]`: any picture to a
  32 x 32 icon in the Desktop's palette (Pillow).

APP.INF's keys, the limits and the archive format: [apps.md](apps.md).

## host16.py

`sdk/c/tools/host16.py` builds a C program with the PC's compiler and cc816's types:
16-bit `int`, 32-bit `long`, unsigned `char`, packed structures, `double` as `float`. A
port can then be compared with its PC twin step by step. The tool preprocesses each of
the program's `.c` files, rewrites the types, and compiles the copies.

```
python3 sdk/c/tools/host16.py cc -O1 -I src -o build/game16 src/*.c
python3 sdk/c/tools/host16.py --fixups port/host16.fix --report cc -O1 -I src -o build/game16 src/*.c
python3 sdk/c/tools/host16.py -E src/main.c -o build/main16.c
```

Options, before the compiler's name:

- `--native NAME`: keep a C-library callback's signature (repeatable).
- `--keep-double`, `--no-pack`.
- `--keep DIR`: keep the rewritten files.
- `--fixups FILE`: the port's own fix-ups, in `[FILE.C]` sections of `OLD => NEW` lines.
  Each OLD is on one line of that file, exactly once.
- `--report`: list each place of old C that was rewritten.
- `-v`: show the commands.

It also rewrites DOS-era old C that the PC's compiler rejects once `int` is short (K&R
definitions, implicit `int`, calls before declarations). It cannot make the arithmetic
of intermediate results 16 bits: a test that compares the two programs' output shows
where that matters. Its use in the ports: [c/porting.md](c/porting.md), "Test it", and
[testing.md](testing.md#host-twin).

## Board: atari816-link, atari.py, deploy816.py

`tools/atari816-link` is the PC side of the PC link: a shared folder as `/PC:`, the time,
the internet ([Docs/04-pc-link.md](../../Docs/04-pc-link.md)). `core/tools/atari.py` is
the developer's command line over the same USB cable (through the gateway when it runs).
For a Horizon program:

```
core/tools/atari.py send GAME.PRG APPS/GAME.PRG     # copy to the card
core/tools/atari.py shot816 shot.png                # a screenshot of the native screen
core/tools/atari.py peek816 0x7F0000 64             # 65C816 memory
```

Its other commands (`ports`, `ping`, `log`, `run`, `eject`, `key`, `run816`, `reset`,
`status`, `screen`, `peek`, `poke`, `fwpeek`, `hdmidiag`) are in its `-h` and in
[core/README.md](../../core/README.md). Both tools need pyserial.

`sdk/tools/deploy816.py` uses the same library for the edit-and-run cycle: copy a file,
restart Horizon, type keys, wait, take a screenshot.

```
python3 sdk/tools/deploy816.py GEMRUN.PRG --dest /BIN/GEMRUN.PRG --type 'gemrun\n' --wait 3 --shot gemrun.png
```

Options: `--dest PATH`, `--restart`, `--type TEXT`, `--key NAME`, `--wait S`, `--shot
OUT.png`, `--port PORT`, `--dry-run`. Not verified on the board: the key injection
reaching Horizon, and sending a file while Horizon has files open.

## Program files and linker configurations

A Horizon program, `NAME.PRG`, is an **o65** file (cc65's relocatable format, the "small"
variant with 16-bit sizes) linked at $0100 of its code bank. Horizon's loader reads the
o65, puts code, data and bss at $0100 of a fresh bank, applies the bank relocations and
enters the program at $0100 in native mode. The o65 must be smaller than 64 KB, and code
+ data + bss must fit $0100-$FFFF. From Horizon 0.28 the file may be longer: the loader
reads only the o65, and the large code model puts its other banks after it, followed by
their relocations and an 8-byte trailer.

Linker configurations:

- `horizon/user/prog.cfg`: assembly programs (ca65 and ld65 with `horizon/build/ulib.o`).
  Segments ZEROPAGE, CODE, RODATA, DATA, BSS.
- `sdk/c/rt/hzprog.cfg`: C programs (hcc). The same, with STARTUP first (cc816's
  `crt0.s`), HEAPSTART, the constructor and destructor tables, and the software stack
  (`__HZ_SSTACK__`, `--stack N`) kept free below $FFF0.
- With `--code large`, hcc writes its own configuration: the main bank as an o65, each
  other bank as a raw image.

The C start-up, `sdk/c/rt/crt0.s`, sets up cc816's direct-page registers and the software
stack, clears the bss, runs the constructors, the `--needs` check and the large model's
loader of the other banks, splits the argument string into `argv`, calls `main`, then
`exit` (the `atexit` functions run, and the streams are flushed and closed). An assembly
program's start conditions (registers, the argument string, the stacks, how it exits):
[reference/program.md](reference/program.md). The C side's memory layout:
[c/reference.md](c/reference.md#memory), "Memory". The large model's file layout:
[c/reference.md](c/reference.md#file-layout), "File layout".
