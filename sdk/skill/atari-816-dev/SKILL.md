---
name: atari-816-dev
description: Write, port, build, test and package software for the Atari816 (a 65C816 computer on an FPGA) and its operating system Horizon 0.30, in C (the SDK's hcc and its compiler cc816) or 65816 assembly (ca65/ld65), checked in the emu816 emulator with scripted input, screenshots, sound logs and the profiler, and packed as installable apps (.HZA). Use when asked to write or fix an Atari816 / Horizon program, window app or game, to port a C program or game (for example a DOS game) to the Atari816, to test a .PRG in the emulator, or to package it as an app.
---

# Atari816 development (Horizon 0.30)

## The machine

| | |
| --- | --- |
| CPU | 65C816 at 14.34 MHz (14,343,750 cycles a second), 16-bit registers in programs |
| Memory | 8 MB in 64 KB banks. A program gets its code bank (code, data, bss, heap: 64 KB, one o65 file below 64 KB; C's large code model adds more code banks), a private window in bank 0 ($0000-$7FFF: hardware stack, direct page) and banks it asks for (`hz_far_alloc`, SYS_BALLOC) |
| Screen | the desktop: 640 x 360, 8 bpp (256 colours), each pixel 2 x 2 on a 1280 x 720 monitor, 60.03 frames a second (238,944 cycles a frame). Full screen: 640 x 360 x 8, 640 x 360 x 4 or 320 x 180 x 8, own palette, fine scrolling, 16 hardware sprites |
| Blitter | Ali: fill, copy, keyed copy, 1-to-8 bpp expand; command lists |
| Sound | POKEY (4 voices), Lau (8-voice sample player), OPL2 (YM3812 FM, hardware REV $0C) |
| Storage | SD card, FAT32. 4 open files in the whole system; paths at most 127 characters |
| OS | Horizon: preemptive, memory-protected, a window system. Programs run in user mode and reach all hardware through syscalls (`COP #n`): touching $00:Dxxx kills the task |
| Emulator | emu816 (`emu/emu816`), board speed, REV $0C by default (`--rev 7..11` for older boards). Driven by `sdk/tools/run816.py` |

## Where things are

The repository: `sdk/` (the SDK), `horizon/` (the OS; its card is `horizon/build/sd`),
`emu/` (the emulator), `ports/` (two finished ports: `ports/digger`, `ports/xargon`).
Requirements: Python 3 (Pillow for screenshots as PNG), cc65's `ca65`, `ld65`, `ar65`,
make and a PC C compiler. Before the first build: `make -C emu` and `make -C horizon -j8`.
If other people use the tree, build in a copy of `horizon/` and `emu/` and pass
`HORIZON=<copy>` to every make.

## C or assembly

| Write it in | When |
| --- | --- |
| C (`sdk/c/bin/hcc`, the compiler cc816) | the default: tools, window apps, games, and every port of C code. One file NAME.PRG, the whole C library, floating point, `long long` |
| 65816 assembly (ca65) | a small or very hot program, a routine called from C (`.s` files next to the C files: hcc assembles them), or when the user asks for it |
| Horizon BASIC | only when the user asks (`sdk/templates/basic-game`) |

C on this machine: `int` is 16 bits, plain `char` is unsigned, data pointers are 16 bits
(the code bank), `__far` pointers reach other banks, `float` and `double` are both IEEE
single precision. Read `references/c-language.md` before writing C.

## Start from a template

| Program | C | Assembly |
| --- | --- | --- |
| text in, text out (shell, Terminal) | `sdk/templates/c-console` | `sdk/templates/console` |
| a desktop app: window, menus, controls, dialogs | `sdk/templates/c-window-app` | `sdk/templates/window-app` |
| a game (hgame: full screen or a window, sprites, maps, sound) | `sdk/templates/c-game` | `sdk/templates/game`, `sdk/examples/deepdive` (full screen) |
| a port of existing C code | `ports/digger` (its `horizon/` platform layer and Makefile) | |

Copy the template folder, then set `NAME` in its Makefile. A copy two levels below `sdk/`
builds as it is; anywhere else pass the SDK: `make SDK=/abs/path/to/sdk` (C) or
`make SDK=/abs/sdk HORIZON=/abs/horizon` (assembly). Small complete examples that pass
their tests: `examples/console`, `examples/window`, `examples/game` (beside this file).

## The loop

```
make                    # NAME.PRG (C: hcc; errors as file:line:col)
make run                # the emulator: output in build/run/ (console.txt, shot1.png ...)
make test               # the same with test.script and the checks (TESTFLAGS, TESTCHECK)
```

One-off runs (any program, any options):

```
python3 sdk/tools/run816.py NAME.PRG --mode desktop --script my.script --out build/try
python3 sdk/tools/run816.py NAME.PRG --mode shell --args '2 40' --expect 'sum of 2'
```

`--mode desktop` starts a window program from the Desktop's Programs menu; `--mode shell`
types the path and `--args` at the text shell (console programs). Script lines: `800 text\n`
(type at 800 ms), `+300 key right 500` (hold), `+200 move X Y` / `click`, `+0 wait TEXT` (until
the program prints a line holding TEXT: use it instead of guessing times), `+200 shot`.
Details: `references/testing.md`.

Every round: build, run, then LOOK.
- `build/.../console.txt`: everything the program printed (under the Desktop `printf` goes
  only there). `[kill] task N NAME cause CC ...` = the kernel killed it (run816 exits 1);
  causes in `references/pitfalls.md`, "Faults".
- `shotN.png`: open each picture and look at it (1280 x 720, each screen pixel 2 x 2).
  `--shot-on TEXT` takes a picture each time the program prints TEXT (pictures at game
  frames, not at guessed times).
- Sound: `--log-sound`, `--log-lau` write the chip writes to `emu.err`; `--wav FILE`
  records Lau and the OPL2.
- Speed: `--prof FILE --prof-from S --prof-to S`, then `python3 sdk/tools/prof816.py
  --counts FILE --map NAME.map` (build with `hcc --map`): `references/performance.md`.

A test passes only when it checked something real: the program's own output lines
(`--expect`), files it wrote (`build/test/card/`), pictures against references, input
that is the same every run. Report what you ran and saw, and what you could not check
(sound is never heard; the emulator's joysticks read 0).

## Package it as an app

An app is a folder `/APPS/NAME/` with NAME.PRG, its data and `APP.INF`. Build with
`hcc --needs horizon=0.29,opl2,mem=1024K` (the program refuses to start, with a message,
where something is missing), then `python3 sdk/tools/hzapp.py check FOLDER` and
`python3 sdk/tools/hzapp.py pack FOLDER -o NAME.HZA`. Users install the .HZA with a double
click. `references/packaging.md`.

## Rules that save hours

- 16-bit `int`: `32767 + 1` is negative, `40000` needs `long`/`unsigned`, `%ld` for long.
- The main bank is small: big tables, pictures, levels go to other banks (`__far`) or
  files; a program too big for its bank: `hcc --code large` (code), `__far` (data).
- Keep the 4-files limit in mind: close files soon.
- Under the Desktop, console output reaches only the log (`console.txt`), not the screen.
- Tests follow the program (`wait`, `--shot-on`), not the clock.
- hgame: a game that clears and redraws the whole frame needs `HG_DOUBLE` (two pages);
  without it the text and pictures drawn after `hg_clear` can be lost from the screen.
- Never write to hardware addresses: every device is a syscall (or hgame / hui call).

## References: read when

| File | Read it when |
| --- | --- |
| `references/c-language.md` | writing any C: types, code models, far data, stacks, what cc816 does not support, hcc's options, the warnings that matter |
| `references/c-library.md` | using the C library or Horizon from C: stdio and files, `horizon.h`'s hz_ calls, errors |
| `references/hgame.md` | writing a game in C: screens, the frame loop, drawing, sprites, maps, sound (POKEY, Lau, OPL2), input, timing |
| `references/hui.md` | writing a window app in C: windows, controls, menus, dialogs, events |
| `references/porting.md` | porting existing code (a DOS game): the platform layer, 16-bit traps, memory, timing, deterministic tests |
| `references/testing.md` | writing input scripts and tests, checking pictures, sound and files |
| `references/packaging.md` | making an app: APP.INF, `--needs`, hzapp.py, installing, where saves go |
| `references/pitfalls.md` | something fails in a way you do not understand, or before a port: the traps that cost hours; assembly traps; kill causes |
| `references/performance.md` | the program is slow: the profiler, what costs what |
| `references/abi-cheatsheet.md` | writing assembly: syscalls, blocks, events, keys, colours, ulib, ui.lib |
| `references/asm-games.md` | a game in assembly |
| `references/look-and-feel.md` | any window app: grid, fonts, colours, menus, shortcuts, dialogs |
| `references/pixel-art.md` | drawing art for the screen: the palette, text art, img2c.py / img2inc.py |

The full documentation: `sdk/docs/c/` (C: reference, apps, games, porting),
`sdk/docs/reference/` (assembly: one page per topic), `sdk/docs/apps.md` (apps).
