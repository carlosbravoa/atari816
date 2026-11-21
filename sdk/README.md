# Atari816 SDK

Everything needed to write programs and games for the **Atari816** and its operating
system **Horizon**: a getting-started guide, a programmer's reference, ready-to-build
templates, complete examples, PC-side tools (art converters, an emulator runner, a deploy
script for the real machine) and a Claude skill.

![Lantern, an example game](examples/lantern/screenshot.png)

## The machine

The Atari816 is a 65C816 desktop computer in an FPGA (Sipeed Tang Nano 20K) with a
complete, cycle-exact Atari 8-bit inside it.

| | |
| --- | --- |
| CPU | 65C816 at 14.3 MHz, native mode (memory stalls make CPU-heavy code run at about half the ideal speed; emu816 models them since Horizon 0.19, so its timings are the board's within about 5 %) |
| Memory | 8 MB (banks of 64 KB); hardware memory protection between programs |
| Video | Marga, the video chip: 640 x 360, 256 colours (8 bpp), shown 2 x 2 on 1280 x 720 HDMI at 60 Hz; a 32 x 32 hardware pointer; also 640 x 360 x 4 bpp and 320 x 180 x 8 bpp (programs get all three in full-screen mode, Horizon 0.18); 16 hardware sprites and fine scrolling with wrap and a split (REV $0B) |
| Blitter | Ali, the blitter: fill, copy, keyed (transparent) copy, 1-to-8 bpp expansion: about 14 million pixels a second filled, 7.7 million copied; command lists (programs: draw lists, Horizon 0.18) |
| Sound | POKEY, the classic machine's sound chip, lent while that machine is frozen (4 voices: tones, noise; before REV $0C its second POKEY, with four 8-bit DACs that REV $0C no longer has); Lau, the 8-voice sample player (REV $0A; Horizon 0.17: SYS_SPLAY and friends); the OPL2, a YM3812 FM synthesizer (REV $0C; Horizon 0.27: SYS_OPLW) |
| Input | USB keyboard and mouse; two Atari joystick ports (SYS_JOY, Horizon 0.15) |
| Storage | SD card, FAT32 (long names) |
| Classic | an Atari 400/800/XL/XE: run disk images, executables, cartridges; F12 switches between it and the desktop |

**Horizon** is a preemptive multitasking kernel with a window system: a desktop with a menu
bar, windows (each with its own bitmap), icons, a mouse pointer, a terminal, and
applications (Files, Edit, Write, Sheet, Paint, BASIC, a calculator, solitaire, Quabricks, a
falling-block game). Programs
run in user mode and reach the hardware only through system calls (`COP #n`): about 105 of
them for tasks, memory, files, the window system, drawing, sound, games (full screen,
sprites, scrolling, draw lists) and the classic machine.

## What you can build

- **Console programs**: text in, text out, in the text shell or a Terminal window.
- **Desktop applications**: windows with menus, buttons, text fields, lists, scroll bars,
  file dialogs and alerts (Horizon's controls library, the same look as its own programs).
- **Games**: full screen (Horizon 0.18: the program's own framebuffer in any of Marga's
  three modes, fine scrolling with wrap and a split for a status panel, a raster table,
  16 hardware sprites, draw lists that Ali runs in the vertical blank, its own palette), or
  in a window (blitter sprites over a tile map, or hardware sprites), with keyboard, mouse
  and joysticks, frame sync, POKEY sound effects and sampled sound on Lau (Horizon 0.17).
- **Internet programs** (Horizon 0.22): through the PC link, a URL (`http://`, `https://`,
  `ftp://`) opens as a read-only file and `tcp://host:port` as a connection. Programs can
  reach whatever the PC can reach, including the home network
  ([docs/reference/internet.md](docs/reference/internet.md)).
- **BASIC programs**: Horizon BASIC has graphics, sound and the mouse; BASIC 2.0 the games
  hardware too: sprites with collisions, a scrolling full screen with a panel and raster
  colours, blitter blocks, samples made or loaded and played by note name.

Programs are written in 65816 assembly with ca65 / ld65 from the cc65 suite, or in **C**
with the C SDK ([c/](c), on the vbcc 65816 compiler: one command, `hcc`, builds a program;
[docs/c/getting-started.md](docs/c/getting-started.md)), and run in **emu816**, the
machine's emulator, with scripted input and screenshots.

## The SDK

| | |
| --- | --- |
| [docs/getting-started.md](docs/getting-started.md) | Install, build the emulator and Horizon, hello as a console and a window program, run, screenshot, script input, the real machine |
| [docs/reference/](docs/reference/README.md) | The programmer's reference: program format and memory, every syscall with an example, the window system, drawing, the controls library, sound, the internet ([internet.md](docs/reference/internet.md)), the games calls (full screen, sprites, scrolling, draw lists, palette entries, frame sync: [games.md](docs/reference/games.md)), the classic machine, the hardware, performance, game patterns, limits |
| [c/](c) | The C SDK: `hcc` (one command from .c files to a program), the C library on Horizon (stdio with files, argc/argv, time, far memory), every syscall as a C function (`horizon.h`), examples, tests; [docs/c/](docs/c/getting-started.md): getting started, the reference (memory models, calling convention, speed), porting |
| [docs/roadmap-notes.md](docs/roadmap-notes.md) | The C compiler candidates (vbcc 65816 was chosen: [c/](c)) |
| [templates/console](templates/console) | Arguments, output, a line of input, a file |
| [templates/c-console](templates/c-console) | The same in C (hcc, `make` with sdk/c/c.mk) |
| [templates/window-app](templates/window-app) | A window with menus, a text field, buttons, the file dialog, an alert |
| [templates/game](templates/game) | Gem Run: a timer loop, a tile map, keyed-blit sprites with dirty rectangles, keys + mouse, POKEY sound, title / play / game over |
| [templates/basic-game](templates/basic-game) | Starfall, a BASIC 2.0 game: sprites, HIT, the arrows or a joystick, samples, 60 frames a second |
| [examples/lantern](examples/lantern) | An arcade game: paddle, ball, lanterns and a moth; big letters from a 1 bpp font; a self-playing demo for its test |
| [examples/slider](examples/slider) | A sliding-tile puzzle: mouse and keys, a fanfare |
| [examples/hexview](examples/hexview) | A hex viewer: the controls library, a file loaded into a bank, scrolling with the blitter, resizing, drag and drop |
| [examples/fetch](examples/fetch) | Fetch (Horizon 0.22): prints a URL on the console; a URL opened as a read-only file, a message for every error |
| [examples/echo](examples/echo) | Echo (Horizon 0.22): a TCP client; connect, send a line, poll for the answer |
| [examples/tune](examples/tune) | Tune (Horizon 0.26): play a ProTracker module with the replayer library and the music timer |
| [examples/deepdive](examples/deepdive) | Deep Dive, a full-screen scrolling game skeleton (Horizon 0.18): its own framebuffer in two banks, fine scrolling with wrap and a split panel, one draw list a frame, 15 hardware sprites, its own palette and a raster table, Lau samples, pause on focus loss |
| [tools/](tools) | `run816.py` (run in the emulator: input scripts, screenshots, checks, sound logs), `inputscript.py`, `contact.py` (screenshots on one sheet), `img2inc.py` (PNG or text art to sprites / tiles / palettes), `font2inc.py` (1 bpp fonts), `deploy816.py` (the real machine over the PC link), `abicheck.py` and `snippets.py` (`make check`), `probe/` (the performance measurements) |
| [skill/atari-816-dev](skill/atari-816-dev/SKILL.md) | A Claude skill: the workflow and condensed references for writing Atari816 programs |

Each template and example builds with `make`, runs with `make run` and checks itself with
`make test` (screenshots in its `build/` folder). `HORIZON=path` selects the Horizon tree
(default: `../../../horizon`, the repository's).

## Make targets here

```
make check      # the reference against Horizon's sources (syscall numbers, names,
                # constants) and every example of the reference assembled and linked
make test       # make check, then make test in every template and example
make probe      # the performance figures of docs/reference/performance.md (REV=7: no blitter)
```

## Status

Written for Horizon 0.13 and brought up to 0.18 ("the games round", November 2026).
Verified in the emulator (REV $0B, its default): every template and example builds and
passes its scripted test, every reference example assembles and links, and the reference
matches horizon.inc and the kernel's syscall tables. Not verified: the real board (no access
while writing), sound (the emulator logs it, and writes Lau's and, since Horizon 0.27, the
OPL2's output to a WAV file; POKEY is only logged), the PC link scripts. The C SDK
(November 2026) is tested in the emulator only (`make -C c test`). The internet examples (Fetch, Echo, Horizon 0.22) are tested in the emulator only
(`--net-root` stands in for the web, a local echo server for TCP), not yet through the real gateway. Where a document states something that was not checked,
it says so.
