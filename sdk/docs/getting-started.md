# Getting started

From nothing to your own program running in the emulator (and, if you have one, on the
Atari816). Every command and every output below was run on Linux (x86-64) for this SDK;
the output is what you should see, apart from timing figures and paths.

## 1. Tools

| Tool | For | Install |
| --- | --- | --- |
| cc65 2.19 or later (ca65, ld65, ar65) | assembling and linking | a package (`apt install cc65`, `brew install cc65`) or from source: `git clone https://github.com/cc65/cc65 && make -C cc65 && make -C cc65 install PREFIX=$HOME/.local` |
| a C compiler (gcc or clang), make | building the emulator | your system's |
| python3 3.8+, Pillow | the SDK's tools (`pip install pillow`; only screenshots, previews and PNG art need it) | |
| SDL2 development files (optional) | the emulator's window, to play by hand | `apt install libsdl2-dev` |
| pyserial (optional) | the PC link to the real machine | `pip install pyserial` |

```
$ ca65 --version
ca65 V2.19 - Git 547d923
```

## 2. The emulator and Horizon

The repository has three parts you need: `emu/` (emu816, the emulator), `horizon/` (the
OS, its libraries, and the SD card it boots) and `sdk/` (this).

```
$ make -C emu                 # or: make -C emu SDL=1  (a window; -B to rebuild)
cc -O2 -Wall -std=c11 -D_DEFAULT_SOURCE -o emu816.new main.c cpu65816.c ... && mv -f emu816.new emu816
$ make -C horizon             # the kernel, the programs, and the SD card in horizon/build/sd
...
ld65 -C user/prog.cfg -o build/tsd/SYSTEM/INIT.PRG build/tinit.o build/ulib.o
```

`horizon/build/sd` is a folder that the emulator serves as the SD card. Try the machine
(needs the SDL build): `make -C horizon run`. It boots into the Desktop; F12 shows the
classic Atari (black in the emulator), F12 again comes back.

`horizon/build/ulib.o` (the user library) and `horizon/build/ui.lib` (the controls library)
are what programs link against; the templates' Makefiles build them if they are missing.

If other people work in the Horizon tree while you build, use a copy:
`cp -r horizon emu /some/where/` and pass `HORIZON=/some/where/horizon` to every make below.

## 3. Hello, console

```
$ cp -r sdk/templates/console hello && cd hello
```
Edit the Makefile's `NAME := greet` to `NAME := hello`, and set the paths for the new
place: `HORIZON ?= ../horizon`, `SDK ?= ../sdk` (or pass them on every make command). The
template's `main.s` is a full console program (arguments, output, a line of input, a
file); reduce it to the smallest program:

```asm
; HELLO - the smallest Horizon program
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  print   "Hello, Atari816!\n"
        exit    0
```

```
$ make
mkdir -p build
ca65 -I . -I ../horizon/user -o build/main.o main.s
ld65 -C ../horizon/user/prog.cfg -o HELLO.PRG build/main.o ../horizon/build/ulib.o
$ python3 ../sdk/tools/run816.py HELLO.PRG --horizon ../horizon --mode shell --shot 1
run816: HELLO at /APPS/HELLO.PRG, started at 3.4 s, ran to 6.4 s (emu816 exit 3; 3 = time limit, the normal end)
  /.../hello/run-hello/shot1.png
  /.../hello/run-hello/console.txt
$ tail -2 run-hello/console.txt
> /APPS/HELLO.PRG
Hello, Atari816!
```

What happened: run816 copied the card to `run-hello/card`, put the program at
`/APPS/HELLO.PRG`, booted the emulator without a window, waited for the text shell, typed
the program's path, and took a screenshot one second after starting it. Look at
`run-hello/shot1.png`: the blue text screen with your line under the command.

(The template's own program: `make test` in the template folder runs it with arguments
and typed input and checks three output lines: `run816: PASS (3 expected texts found)`.)

## 4. Hello, window

```
$ cp -r sdk/templates/window-app hellowin && cd hellowin
```
Set `HORIZON ?=` / `SDK ?=` as above. The template opens a window with a menu bar (File:
Open..., Save as..., Quit; Help: About...), a name field, Greet and Clear buttons, and draws
"Hello, NAME!". The smallest window program, without the controls library (`UI := 0` in
the Makefile):

```asm
; HELLOW - a window with a line of text; the close box ends it
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_WSSTART             ; A = 1: we started the window system
        sta     z:own
        ptr     wo
        sys     SYS_WOPEN               ; -> A = the window
        sta     z:win
        ptr     tx
        lda     z:win
        sys     SYS_WDRAW               ; the text
@wait:  lda     #0
        ptr     ev
        sys     SYS_WEVENT              ; wait for an event
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        bne     @wait
        lda     z:own
        beq     :+
        sys     SYS_WSSTOP
:       exit    0
        .segment "RODATA"
wo:     .word   200, 120, 240, 60       ; x, y, content width, height
        .faraddr title
        .byte   0
title:  .byte   "Hello", 0
tx:     .byte   WD_TEXT, C_BLACK, $FF, 0 ; op, ink, no paper, the UI font
        .word   16, 24, 0, 0            ; x, y (w, h unused)
        .faraddr msg
msg:    .byte   "Hello, Atari816!", 0
        .segment "BSS"
ev:     .res    8
        .segment "ZEROPAGE"
own:    .res    2
win:    .res    2
```

```
$ make
$ python3 ../sdk/tools/run816.py HELLOWIN.PRG --horizon ../horizon --shot 1
run816: HELLOWIN at /APPS/HELLOWIN.PRG, started at 5 s, ran to 8 s (emu816 exit 3; 3 = time limit, the normal end)
```
This time (the default `--mode desktop`) the Desktop booted, run816 put the program first
in the Programs menu and chose it with the keyboard (F10, Right, Enter). `shot1.png` shows
the Desktop with Files open and your window on top.

## 5. Scripted input and screenshots

Write what the user does into a script; times in milliseconds after the program started:

```
# my.script
800 Ada\n               type "Ada" and Enter
+700 shot
+200 {alt-h}            Alt+H opens the Help menu
+500 \n
+800 shot
+300 move 376 126       the pointer to screen (376, 126)
+300 click
+600 shot
```
```
$ python3 ../sdk/tools/run816.py HELLOWIN.PRG --horizon ../horizon --script my.script --out build/try
$ python3 ../sdk/tools/contact.py build/try/sheet.png build/try/shot*.png
build/try/sheet.png: 3 shots
```
The sheet shows the shots side by side at half size: one pixel on it is one screen pixel,
so you can read the coordinates for `move`. The script language is in
`sdk/tools/inputscript.py` (keys, ctrl and Alt combinations, held keys for games, clicks,
drags, the wheel). `--expect TEXT` makes the run fail unless the console shows TEXT;
a `[kill]` line (a crash) always fails it. Every template has a `make test` built this way.

## 6. On the real machine

You need the board with its firmware, a USB-C cable to the PC (the PC link), and the
SD card prepared once: copy `horizon/build/sd/SYSTEM`, `horizon/build/sd/BIN` and
`horizon/build/sd/README.TXT` to the card (horizon/README.md). Then, for each new version
of your program (not run by the SDK's author, who had no board; the commands wrap
`core/tools/atari.py`):

```
$ python3 sdk/tools/deploy816.py HELLOWIN.PRG --dest /BIN/HELLOWIN.PRG
send HELLOWIN.PRG (1234 bytes) -> /BIN/HELLOWIN.PRG
OK: /BIN/HELLOWIN.PRG on the card
```
Start it on the machine: in a Terminal window (Programs > Terminal) type `hellowin`, or
add a line `Hello=/BIN/HELLOWIN.PRG` to `/SYSTEM/PROGRAMS` for the Programs menu. A
screenshot of the machine's screen over the link (about 6 s):
```
$ python3 sdk/tools/deploy816.py HELLOWIN.PRG --wait 0 --shot board.png
$ python3 core/tools/atari.py shot816 board.png      # the same, without sending
```
`--type 'hellowin\n'` types on the machine's keyboard through the link (unverified: see
`deploy816.py --help`). `--dry-run` shows what would be done.

Since Horizon 0.19 emu816 runs at the board's speed (its memory stalls are modelled; within
about 5 % on measured loops and the BASIC sieve), so a game that keeps its frame rate in the
emulator should keep it on the board; still check it there.

## 7. Next

- `sdk/templates/`: console, window-app, game (a complete small game), basic-game.
- `sdk/examples/`: Lantern (arcade), Slider (puzzle), Hex View (a utility), Deep Dive (a
  full-screen scrolling game: Horizon 0.18's framebuffer, scrolling, sprites, draw lists),
  with commentary; Fetch and Echo (Horizon 0.22: the internet through the PC link, a URL
  opened as a file and a TCP connection).
- `sdk/docs/reference/`: every syscall with an example, the window system, drawing,
  sound, the hardware, performance; `games.md` for full-screen mode, sprites, draw lists,
  palette entries and frame sync; `internet.md` for URLs and connections (Horizon 0.22).
- [apps.md](apps.md) (Horizon 0.29): your program as an app: one folder in `/APPS` with
  APP.INF, an `.HZA` archive made with `sdk/tools/hzapp.py` that users install with a
  double click, and `HZ_NEEDS` (`needs.inc`): the program checks what it needs at its start.
  (0.31) A program started from the Desktop gets arguments too (APP.INF's `args=`, the
  user's `NAME.ARG` next to it) and, with `console=yes` (or `error`), a Terminal window for
  what it prints: see "The user's options" there.
- [README.md](README.md): the manual's front page, every component and a reading path for
  each kind of program; [tools.md](tools.md) every tool and option, [testing.md](testing.md)
  testing without a person.
- `sdk/skill/atari-816-dev/`: the same knowledge as a Claude skill.
