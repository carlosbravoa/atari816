# Atari816 SDK manual

This manual covers programming the Atari816 and Horizon, release 0.31, in C and in 65816
assembly. For how the machine is built, see
[Architecture and components](../../Docs/architecture/README.md).

## Layers

- Hardware, in `core/`: one Tang Nano 20K FPGA with a 65C816 at 14.3 MHz, 8 MB of RAM,
  FREDDIE II (memory and protection), Marga (video), Ali (blitter), Lau (samples), an OPL2,
  POKEY, and an I/O processor for the card, the keyboard and the PC link. A classic 8-bit
  Atari runs beside it. See [reference/hardware.md](reference/hardware.md) and
  [Docs/02-register-spec.md](../../Docs/02-register-spec.md).
- Horizon kernel and ABI, in `horizon/kernel` and `horizon/ABI.md`: preemptive tasks,
  memory protection, files, windows, sound and games calls, 115 syscalls through `COP #n`.
  See [reference/](reference/README.md) and [horizon/ABI.md](../../horizon/ABI.md).
- Libraries, in `horizon/user` and `sdk/c`. For assembly, ulib and the controls library
  (ui.lib). For C, the C library, `horizon.h` (every syscall), `hui.h` (window apps),
  `hgame.h` (games), `conio.h` and `joystick.h`. See [reference/ulib.md](reference/ulib.md),
  [reference/controls.md](reference/controls.md) and [c/library.md](c/library.md).
- Compiler and build, in `sdk/c/cc816`, `sdk/c/bin/hcc` and `sdk/c/c.mk`: cc816 (the SDK's
  C compiler), hcc (the driver), ca65 and ld65 for assembly, make rules. See
  [c/compiler.md](c/compiler.md) and [tools.md](tools.md).
- Emulator and test tools, in `emu/` and `sdk/tools`: emu816 (the machine, with the
  board's timing) and run816.py (runs a program with scripted input, screenshots and
  checks). See [testing.md](testing.md), [tools.md](tools.md) and
  [emu/README.md](../../emu/README.md).
- Packaging, with `sdk/tools/hzapp.py`: an app is a folder with `APP.INF`, packed into one
  `.HZA` file that users install with a double click. See [apps.md](apps.md).
- Ports, in `ports/`: six games and simulations ported in C, used as examples and as the
  compiler's acceptance test. See [Ports](#ports).

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

## Chapters

- [Getting started](getting-started.md) (assembly) and
  [Getting started with C](c/getting-started.md): install cc65 and Python, build the
  emulator and Horizon, run a hello world in a console and in a window, script its input,
  take screenshots, put it on the board.
- [C reference](c/reference.md): the language as cc816 implements it on Horizon. Memory,
  the small and large code models, far data, types, pointers and banks, the calling
  convention, inline assembly, the C library's behaviour, floating point, `long long`,
  `setjmp`, syscalls from C, the stacks, optimization.
- [C library](c/library.md): every header and function. [Syscalls from C](c/syscalls.md):
  every `hz_` function with its prototype, generated from the header.
- [Window applications](c/apps.md): `hui.h`, Horizon's controls library in C. Windows,
  menus, buttons, fields, lists, scroll bars, the file dialog, alerts, and a tutorial in
  five steps. The interface conventions are in the skill's `references/look-and-feel.md`.
- [Games](c/games.md): `hgame.h`. Full screen in three modes or a window, the blitter,
  images, bobs and hardware sprites, scrolling tile maps (also 16-bit tiles, `hg_map16`), a
  ring framebuffer for worlds the game draws itself (`hg_scroll_wrap`), colour remapping,
  input, POKEY, Lau and OPL2 sound, music files, fixed point, and a tutorial in five steps.
- [Porting C](c/porting.md): C from cc65, DOS or SDL. 16-bit `int`, memory layout, the
  platform layer, the DOS-compatibility options, the far data model, comparison with a PC
  twin.
- [Compiler](c/compiler.md): the build pipeline, the options, the output files, the
  diagnostics, the limits, reporting a fault.
- [Programmer's reference](reference/README.md), for assembly, one page per topic: the
  program format, every syscall with an example, the window system, drawing, the controls
  library, sound, the internet, printing, the games calls, the classic machine, the
  hardware, performance, game patterns, limits.
- [Tools](tools.md): hcc, cc816.py, c.mk, run816.py and its input scripts, emu816's
  options, the profiler, the picture and font converters, hzapp.py, host16.py, the board
  tools, the `.PRG` format and the linker configurations.
- [Testing](testing.md): automated tests of a program. Console lines as evidence, scripts
  synchronised to the program's output, pictures of states, reference pictures,
  self-tests, the host twin.
- [Apps and packaging](apps.md): a program in its own folder in `/APPS`, `APP.INF`, the
  user's options, `hcc --needs`, the `.HZA` archive, installing and removing.
- [Limits](reference/limits.md): sizes, counts and timings guaranteed to a program.
- `sdk/skill/atari-816-dev`, a skill for coding agents: the short operational form of this
  manual (`SKILL.md` and `references/`), with three small tested examples. It links back
  here for the full form.

## By task

- A game in C: [c/getting-started.md](c/getting-started.md), [c/games.md](c/games.md)
  (the tutorial), `sdk/templates/c-game`, [testing.md](testing.md), [apps.md](apps.md).
- A window application: [c/getting-started.md](c/getting-started.md),
  [c/apps.md](c/apps.md) (the tutorial), `sdk/templates/c-window-app`, and
  [reference/windows.md](reference/windows.md) for the events.
- Porting DOS or other C code: [c/porting.md](c/porting.md),
  [c/reference.md](c/reference.md) "Far data model" and "Old C", [tools.md](tools.md)
  "host16.py", the ports' notes.
- Assembly: [getting-started.md](getting-started.md),
  [reference/program.md](reference/program.md), [reference/README.md](reference/README.md),
  [reference/ulib.md](reference/ulib.md), `sdk/templates/console`,
  `sdk/templates/window-app`.
- Testing without a board: [testing.md](testing.md), [tools.md](tools.md) "run816.py"
  and "inputscript.py".
- Packaging and installing an app: [apps.md](apps.md), [tools.md](tools.md) "hzapp.py".
- The compiler's internals: [c/compiler.md](c/compiler.md), then
  [c/reference.md](c/reference.md) "Calling convention" and "Compiler notes".
- The machine: [Docs/architecture/README.md](../../Docs/architecture/README.md),
  [reference/hardware.md](reference/hardware.md),
  [Docs/01-architecture-design.md](../../Docs/01-architecture-design.md).
- Optimization and profiling: [reference/performance.md](reference/performance.md),
  [c/reference.md](c/reference.md) "Performance", [tools.md](tools.md) "prof816.py",
  [c/games.md](c/games.md) "Performance".

## Templates and examples

Each has three targets: `make` (build), `make run` and `make test`.

- `sdk/templates/c-console`, `sdk/templates/console`: arguments, output, a line of input, a
  file (C, assembly).
- `sdk/templates/c-window-app`, `sdk/templates/window-app`: a window with menus, a field,
  buttons, the file dialog, an alert.
- `sdk/templates/c-game`, `sdk/templates/game`: Gem Run, with a tile map, sprites, keys and
  mouse, sound, and title, play and game-over states.
- `sdk/templates/basic-game`: a Horizon BASIC 2.0 game.
- `sdk/c/examples/`: `hello`, `window` (raw window calls), `wc`, `guests` (the app
  tutorial), `viewer`, `tutorial` (the games tutorial), `glimmer`, `catch` (conio), `asmfar`
  (C and movable assembly).
- `sdk/examples/`: assembly. `lantern`, `slider`, `hexview`, `deepdive` (full screen),
  `fetch` and `echo` (the internet), `tune` (music).
- `sdk/skill/atari-816-dev/examples/`: `console`, `window`, `game`, small, complete and
  tested.

## Ports

The ports are the largest programs built with the SDK. Each has a README (how to build, run
and test it) and porting notes (what had to change, and why). They are the acceptance test
of the compiler and the libraries.

Four ports need the user's own game files. The data is not in the repository: each port's
`make data` fetches it or converts the user's copy.

- [Digger](../../ports/digger/README.md), from Digger Remastered (C, SDL back end). An SDL
  game on hgame, a 320 x 200 game on a 320 x 180 screen with a split, reference pictures of
  a recorded game, an app (`DIGGER.HZA`). Game data in the repository.
- [Xargon](../../ports/xargon/README.md), from the released DOS source (Turbo C, large
  model). The unreleased assembly (mode X, the keyboard interrupt, the timer, Sound
  Blaster) is replaced by a platform layer. POSIX file calls, Lau samples and music. Needs
  the user's own files.
- [Prince of Persia](../../ports/prince/README.md), from SDLPoP (C). The game's logic
  unchanged on a new platform layer; recorded games compared with the PC state for state
  and picture for picture. Needs the user's own files.
- [Micropolis](../../ports/simcity/README.md) (`ports/simcity`), from the GPL Micropolis
  simulator (K&R C). C89 code built with `-std=c89`, the simulator compared with two PC
  twins every 100 ticks, a mouse-driven full-screen front end. Game data in the
  repository.
- [X-COM](../../ports/xcom/README.md), from XCOM-XT (49,000 lines of Watcom C, DOS large
  model). `--code large --data far`, OPL2 music and sound, colour remapping, every screen
  compared with the host build. Needs the user's own files.
- [SkyRoads](../../ports/skyroads/README.md), from a C translation of SDL-skyroads. An
  experiment, not a playable port: how fast a 3D road can be drawn (fill runs, the
  profiler). Every frame of the demo equals the C++ original's. Needs the user's own
  files.
