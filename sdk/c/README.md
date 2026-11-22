# The Horizon C SDK

C for the Atari816 and Horizon. Two compilers: **cc816**, the SDK's own (the default:
Python 3 and cc65's tools, nothing to download), and **vbcc 65816** (`hcc --cc vbcc`: for
floating point, `setjmp` and the tiny model).

```
sdk/c/bin/hcc -o HELLO.PRG hello.c    # a Horizon program from C, in one command (cc816)
make -C sdk/c test                    # the SDK's tests in the emulator
sdk/c/tools/get-toolchain.sh          # only for vbcc: download and install it (Linux x86-64)
```

| | |
| --- | --- |
| [bin/hcc](bin/hcc) | the driver: compile, link, make the o65 program; sizes checked; `--cc cc816|vbcc` (or `HZ_CC`) |
| [cc816/](cc816) | cc816, the C compiler (Python 3: pycparser and pcpp vendored, writes ca65 assembly), its standard headers (`cc816/include`), its regression set (`make -C cc816 check`: regress programs, random programs against gcc, the c-testsuite) |
| [c.mk](c.mk) | make rules: a program's Makefile is `NAME := x`, `SDK ?= ...`, `include $(SDK)/c/c.mk` |
| [include/horizon.h](include/horizon.h) | every syscall as a C function (`hzsys.h`, generated), the parameter blocks, the helpers; [include/dirent.h](include/dirent.h) |
| [include/hui.h](include/hui.h) | Horizon's controls library for C: windows with buttons, fields, lists, scroll bars, dialogs ([huigen.h](include/huigen.h), generated); hcc links it when a program uses it ([docs/c/apps.md](../docs/c/apps.md)) |
| [include/hgame.h](include/hgame.h), [game/](game) | hgame, the game library: full screen or a window, the blitter, images, sprites, scrolling maps, input, sound, music; `conio.h` and `joystick.h` (cc65's); hcc links it when a program includes one of them ([docs/c/games.md](../docs/c/games.md)); `make -C game test` |
| [ui/](ui) | the controls library's binding: `hui.tab` (the signature table), `lib816/` (cc816's helpers), `lib/` (vbcc's block), built with the Horizon tree's sources into `build/ui/` |
| [lib/](lib), [rt/](rt) | the C library on Horizon: `lib/` both compilers' (argv, the console, folders, errno, time, the stack checks), `lib/cc816/` and `rt/cc816/` cc816's library and runtime (stdio with files, printf, malloc, strings, the startup, the arithmetic helpers, `hzprog.cfg`), `lib/vbcc/`, `rt/` and [fastrt/](fastrt) vbcc's (over its own binary library) |
| [tools/](tools) | `hzc.py` (vbcc) and `hzc816.py` (cc816) behind hcc, `hui816.py`, `gensys.py` (hzsys.h and the syscall stubs from horizon.inc / ABI.md / `syscalls.tab`), `genhui.py` (huigen.h and the shims from ui.inc / `ui/hui.tab`), `o65strip.py`, `mko65.py`, `get-toolchain.sh` |
| [examples/](examples) | `hello`, `window` (raw window calls), `wc` (a file tool), `guests` (the application tutorial's five steps), `viewer` (a text viewer with the controls library), `tutorial` (the games tutorial), `glimmer`, `catch`: `make`, `make run`, `make test` (`HZ_CC=vbcc` for the other compiler) |
| [tests/](tests) | `run.py`: libc, syscalls, compiler faults, float, stack, benchmark, runtime tables, the controls library (`ui`, `uibad`, `uitiny`, `uitwin`, `appsdoc`), for cc816 and vbcc's two models |
| docs | [getting started](../docs/c/getting-started.md), [reference](../docs/c/reference.md), [applications](../docs/c/apps.md), [games](../docs/c/games.md), [porting](../docs/c/porting.md) |

vbcc is free for non-commercial use and may be redistributed only unmodified: it is
downloaded, not included. Templates: [../templates/c-console](../templates/c-console),
[../templates/c-window-app](../templates/c-window-app), [../templates/c-game](../templates/c-game)
(Gem Run in C). The controls library (`hui.h`) also needs the Horizon tree.
