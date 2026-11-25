# The Atari816 SDK manual

This is the front page of the SDK's documentation: a map of everything a programmer of the
Atari816 and Horizon (release 0.31) can use, with a link to the chapter for each part. If
you know what you want to make, start at "Reading paths" below. If you want to know how
the whole machine is built first: [Architecture and components](../../Docs/architecture/README.md).

## The layers

| Layer | What it is | Where | Chapter |
| --- | --- | --- | --- |
| Hardware | a 65C816 at 14.3 MHz with 8 MB, FREDDIE II (memory and protection), Marga (video), Ali (blitter), Lau (samples), an OPL2, POKEY, an I/O processor for the card, the keyboard and the PC link; a classic 8-bit Atari beside it. One Tang Nano 20K FPGA | `core/` | [reference/hardware.md](reference/hardware.md), [Docs/02-register-spec.md](../../Docs/02-register-spec.md) |
| Horizon kernel and ABI | preemptive tasks, memory protection, files, windows, sound, games calls: 115 syscalls through `COP #n` | `horizon/kernel`, `horizon/ABI.md` | [reference/](reference/README.md), [horizon/ABI.md](../../horizon/ABI.md) |
| Libraries | for assembly: ulib and the controls library (ui.lib); for C: the C library, `horizon.h` (every syscall), `hui.h` (window apps), `hgame.h` (games), `conio.h`, `joystick.h` | `horizon/user`, `sdk/c` | [reference/ulib.md](reference/ulib.md), [reference/controls.md](reference/controls.md), [c/library.md](c/library.md) |
| Compiler and build | cc816 (the SDK's C compiler), hcc (the driver), ca65 / ld65 for assembly, make rules | `sdk/c/cc816`, `sdk/c/bin/hcc`, `sdk/c/c.mk` | [c/compiler.md](c/compiler.md), [tools.md](tools.md) |
| Emulator and tests | emu816 (the machine, with the board's timing), run816.py (a program run with scripted input, screenshots, checks), the test suites | `emu/`, `sdk/tools` | [testing.md](testing.md), [tools.md](tools.md), [emu/README.md](../../emu/README.md) |
| Packaging | apps: a folder with `APP.INF`, packed into one `.HZA` file that users install with a double click | `sdk/tools/hzapp.py` | [apps.md](apps.md) |
| Ports | six games and simulations ported in C: the worked examples, and the acceptance test of the compiler | `ports/` | "The ports" below |

```
   your program (C or 65816 assembly)
        |  hcc / cc816 / ca65 / ld65           sdk/c, sdk/tools
        v
   NAME.PRG (o65)  --hzapp.py-->  NAME.HZA     sdk/docs/apps.md
        |
   libraries: C library, horizon.h, hui.h, hgame.h | ulib, ui.lib
        |  syscalls (COP #n)
   Horizon kernel                              horizon/, horizon/ABI.md
        |
   the Atari816: the board (core/)  or  emu816 (emu/) driven by run816.py
```

## The parts

**Getting started.** Install cc65 and Python, build the emulator and Horizon, run a hello
world in a console and in a window, script its input, take screenshots, put it on the
board: [getting-started.md](getting-started.md) (assembly) and
[c/getting-started.md](c/getting-started.md) (C).

**C.** Most programs are written in C. [c/reference.md](c/reference.md) is the language as
cc816 has it on Horizon: memory, the small and large code models, far data, types,
pointers and banks, the calling convention, inline assembly, the C library's behaviour,
floating point, `long long`, `setjmp`, syscalls from C, the stacks, speed.
[c/library.md](c/library.md) lists every header and function; [c/syscalls.md](c/syscalls.md)
every `hz_` function with its prototype (generated from the header).

**Window applications in C.** `hui.h`, Horizon's controls library: windows, menus,
buttons, fields, lists, scroll bars, the file dialog, alerts; a tutorial in five steps:
[c/apps.md](c/apps.md). The look and the rules of the house style: the skill's
`references/look-and-feel.md`.

**Games in C.** `hgame.h`: full screen in three modes or a window, the blitter, images,
bobs and hardware sprites, scrolling tile maps (also 16-bit tiles, `hg_map16`), a ring
framebuffer for worlds drawn by the game (`hg_scroll_wrap`), colour remapping, input,
POKEY, Lau and OPL2 sound, music files, fixed point; a tutorial in five steps:
[c/games.md](c/games.md).

**Porting.** C from cc65, DOS or SDL, step by step: the 16-bit traps, memory, the platform
layer, the DOS-compatibility options, the far data model, testing against a PC twin:
[c/porting.md](c/porting.md).

**The compiler.** How cc816 works, its options grouped by purpose, how to read its
output, its diagnostics and limits, how it is tested, how to report a fault:
[c/compiler.md](c/compiler.md).

**Assembly.** The programmer's reference, one page per topic: the program format, every
syscall with an example, the window system, drawing, the controls library, sound, the
internet, printing, the games calls, the classic machine, the hardware, performance, game
patterns, limits: [reference/README.md](reference/README.md).

**Tools.** hcc, cc816.py, c.mk, run816.py and its input scripts, emu816's options, the
profiler, the picture and font converters, hzapp.py, host16.py, the board tools, the
SDK's own checks, the `.PRG` format and the linker configurations: [tools.md](tools.md).

**Testing.** How a program is tested without a person: console lines as evidence,
scripts that wait for the program, pictures of states, reference pictures, self-tests,
the host twin, and the SDK's own suites: [testing.md](testing.md).

**Apps.** A program in its own folder in `/APPS`, `APP.INF`, the user's options,
`hcc --needs`, the `.HZA` archive, installing and removing: [apps.md](apps.md).

**The machine's limits** (what a program may count on): [reference/limits.md](reference/limits.md).

**For coding agents.** `sdk/skill/atari-816-dev` is a skill: the short operational form
of this manual (`SKILL.md` and `references/`), with three small examples that pass their
tests. It links back here for the full form.

## Reading paths

| I want to | Read, in this order |
| --- | --- |
| write a game in C | [c/getting-started.md](c/getting-started.md), [c/games.md](c/games.md) (the tutorial), `sdk/templates/c-game`, [testing.md](testing.md), [apps.md](apps.md) |
| write a windowed app | [c/getting-started.md](c/getting-started.md), [c/apps.md](c/apps.md) (the tutorial), `sdk/templates/c-window-app`, [reference/windows.md](reference/windows.md) for the events |
| port DOS or other C code | [c/porting.md](c/porting.md), [c/reference.md](c/reference.md) "The far data model" and "Old C", [tools.md](tools.md) "host16.py", the ports' notes |
| write assembly | [getting-started.md](getting-started.md), [reference/program.md](reference/program.md), [reference/README.md](reference/README.md), [reference/ulib.md](reference/ulib.md), `sdk/templates/console`, `sdk/templates/window-app` |
| test without a board | [testing.md](testing.md), [tools.md](tools.md) "run816.py" and "inputscript.py" |
| package and install an app | [apps.md](apps.md), [tools.md](tools.md) "hzapp.py" |
| understand the compiler | [c/compiler.md](c/compiler.md), then [c/reference.md](c/reference.md) "Calling convention" and "Compiler notes" |
| understand the machine | [Docs/architecture/README.md](../../Docs/architecture/README.md), [reference/hardware.md](reference/hardware.md), [Docs/01-architecture-design.md](../../Docs/01-architecture-design.md) |
| make a program faster | [reference/performance.md](reference/performance.md), [c/reference.md](c/reference.md) "Speed", [tools.md](tools.md) "prof816.py", [c/games.md](c/games.md) "Performance" |

## Templates and examples

Each builds with `make`, runs with `make run` and checks itself with `make test`.

| Folder | What |
| --- | --- |
| `sdk/templates/c-console`, `sdk/templates/console` | arguments, output, a line of input, a file (C, assembly) |
| `sdk/templates/c-window-app`, `sdk/templates/window-app` | a window with menus, a field, buttons, the file dialog, an alert |
| `sdk/templates/c-game`, `sdk/templates/game` | Gem Run: a tile map, sprites, keys and mouse, sound, title / play / game over |
| `sdk/templates/basic-game` | a Horizon BASIC 2.0 game |
| `sdk/c/examples/` | `hello`, `window` (raw window calls), `wc`, `guests` (the app tutorial), `viewer`, `tutorial` (the games tutorial), `glimmer`, `catch` (conio), `asmfar` (C and movable assembly) |
| `sdk/examples/` | assembly: `lantern`, `slider`, `hexview`, `deepdive` (full screen), `fetch` and `echo` (the internet), `tune` (music) |
| `sdk/skill/atari-816-dev/examples/` | `console`, `window`, `game`: small, complete, tested |

## The ports

The ports are the largest programs built with the SDK. Each has a README (how to build,
run and test it) and porting notes (what had to change, and why). Together they are the
acceptance test of the compiler and the libraries: each one found faults that are now
regression tests.

"The user's own files" means the game's data is not in the repository: each port's
`make data` fetches it or converts the user's copy, and nothing made from it is committed.

| Port | From | What it shows | Game data |
| --- | --- | --- | --- |
| [Digger](../../ports/digger/README.md) | Digger Remastered (C, SDL back end) | an SDL game on hgame; a 320 x 200 game on a 320 x 180 screen with a split; reference pictures of a recorded game; an app (`DIGGER.HZA`) | in the repository |
| [Xargon](../../ports/xargon/README.md) | the released DOS source (Turbo C, large model) | a DOS game whose unreleased assembly (mode X, the keyboard interrupt, the timer, Sound Blaster) is replaced by a platform layer; POSIX file calls; Lau samples and music | the user's own files |
| [Prince of Persia](../../ports/prince/README.md) | SDLPoP (C) | the game's logic unchanged on a new platform layer; recorded games compared with the PC state for state and picture for picture | the user's own files |
| [Micropolis](../../ports/simcity/README.md) (`ports/simcity`) | the GPL Micropolis simulator (K&R C) | C89 code with `-std=c89`; the simulator checked against two PC twins every 100 ticks; a mouse-driven full-screen front end | in the repository |
| [X-COM](../../ports/xcom/README.md) | XCOM-XT (49,000 lines of Watcom C, DOS large model) | `--code large --data far`; OPL2 music and sound; colour remapping; every screen compared with the host build | the user's own files |
| [SkyRoads](../../ports/skyroads/README.md) | a C translation of SDL-skyroads | an experiment, not a playable port: how fast a 3D road can be drawn (fill runs, the profiler); every frame of the demo equal to the C++ original's | the user's own files |

## Keeping this manual true

`make -C sdk/c check` runs `sdk/tools/doccheck.py`, which fails when a public function of
the SDK's headers, a header, a tool, or an option of hcc, cc816.py, run816.py,
inputscript.py, hzapp.py, host16.py or emu816 is mentioned nowhere in `sdk/docs`, and when
[c/syscalls.md](c/syscalls.md) is not what `hzsys.h` gives. It also builds the manual as a
web site with `sdk/tools/mkmanual.py` and checks every link in it. `make -C sdk check`
checks the assembly reference against Horizon's sources and assembles its examples.
