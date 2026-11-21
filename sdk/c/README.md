# The Horizon C SDK

C for the Atari816 and Horizon, on the vbcc 65816 compiler.

```
sdk/c/tools/get-toolchain.sh          # once: download and install vbcc (Linux x86-64)
sdk/c/bin/hcc -o HELLO.PRG hello.c    # a Horizon program from C, in one command
make -C sdk/c test                    # the SDK's tests in the emulator
```

| | |
| --- | --- |
| [bin/hcc](bin/hcc) | the driver: compile, link (three times), make the o65 program; sizes checked |
| [c.mk](c.mk) | make rules: a program's Makefile is `NAME := x`, `SDK ?= ...`, `include $(SDK)/c/c.mk` |
| [include/horizon.h](include/horizon.h) | every syscall as a C function (`hzsys.h`, generated), the parameter blocks, the helpers; [include/dirent.h](include/dirent.h) |
| [include/hui.h](include/hui.h) | Horizon's controls library for C: windows with buttons, fields, lists, scroll bars, dialogs ([huigen.h](include/huigen.h), generated); hcc links it when a program uses it ([docs/c/apps.md](../docs/c/apps.md)) |
| [include/hgame.h](include/hgame.h), [game/](game) | hgame, the game library: full screen or a window, the blitter, images, sprites, scrolling maps, input, sound, music; `conio.h` and `joystick.h` (cc65's); hcc links it when a program includes one of them ([docs/c/games.md](../docs/c/games.md)); `make -C game test` |
| [ui/](ui) | the controls library's binding: `hui.tab` (the signature table), `lib/` (the assembly helpers), built with the Horizon tree's sources into `build/ui/` |
| [lib/](lib), [rt/](rt), [fastrt/](fastrt) | the C library on Horizon (stdio with files, argv, time, far memory, errno), the startup and linker scripts, the tuned runtime |
| [tools/](tools) | `get-toolchain.sh`, `gensys.py` (hzsys.h from horizon.inc / ABI.md / `syscalls.tab`), `genhui.py` (huigen.h and the shims from ui.inc / `ui/hui.tab`), `mko65.py`, `hzc.py` |
| [examples/](examples) | `hello`, `window` (raw window calls), `wc` (a file tool), `guests` (the application tutorial's five steps), `viewer` (a text viewer with the controls library): `make`, `make run`, `make test` |
| [tests/](tests) | `run.py`: libc, syscalls, compiler faults, float, stack, benchmark, runtime tables, the controls library (`ui`, `uibad`, `uitiny`, `uitwin`, `appsdoc`) |
| docs | [getting started](../docs/c/getting-started.md), [reference](../docs/c/reference.md), [applications](../docs/c/apps.md), [games](../docs/c/games.md), [porting](../docs/c/porting.md) |

vbcc is free for non-commercial use and may be redistributed only unmodified: it is
downloaded, not included. Templates: [../templates/c-console](../templates/c-console),
[../templates/c-window-app](../templates/c-window-app), [../templates/c-game](../templates/c-game)
(Gem Run in C). The controls library (`hui.h`)
also needs cc65's ca65, ld65 and ar65 and the Horizon tree.
