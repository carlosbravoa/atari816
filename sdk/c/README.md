# The Horizon C SDK

C for the Atari816 and Horizon, with the SDK's own compiler, **cc816**. It needs Python 3
and cc65's ca65, ld65 and ar65; nothing is downloaded. cc816 has floating point (IEEE 754
single precision; `double` is the same 32-bit format as `float`, about 7 digits),
`long long` (64 bits), `setjmp`/`longjmp` and inline assembly (`asm("...")` in ca65
syntax, C variables named `%[name]`): [docs/c/reference.md](../docs/c/reference.md).

Two code models. The small one (the default) keeps the whole program in one 64 KB bank. A
program whose code does not fit there builds with `hcc --code large`: the code then fills
several banks (still one file, NAME.PRG, for Horizon 0.28; data, constants and the stacks
stay in the first bank): [docs/c/reference.md](../docs/c/reference.md), "The two code
models".

(Horizon 0.29) `hcc --needs horizon=0.29,opl2,mem=1024K` makes the program check what it
needs when it starts (a message and exit 1 where something is missing, also on older
Horizons); `sdk/tools/hzapp.py` packs a program's folder into an `.HZA` archive that users
install with a double click: [docs/apps.md](../docs/apps.md).

```
sdk/c/bin/hcc -o HELLO.PRG hello.c    # a Horizon program from C, in one command
sdk/c/bin/hcc --code large -o GAME.PRG *.c   # code in several banks, still one file
sdk/c/bin/hcc --needs horizon=0.29,lau -o GAME.PRG *.c  # it checks what it needs at its start
make -C sdk/c test                    # the SDK's tests in the emulator
```

| | |
| --- | --- |
| [bin/hcc](bin/hcc) | the driver: compile, link, make the o65 program; sizes checked; `--code small\|large` (or `HZ_CODE`: the two code models) |
| [cc816/](cc816) | cc816, the C compiler (Python 3: pycparser and pcpp vendored, writes ca65 assembly), its standard headers (`cc816/include`, with `math.h`, `float.h`, `setjmp.h`, `inttypes.h`), its regression set (`make -C cc816 check`, in both code models: the error and warning messages, regress programs, a program for each part of C, random programs against gcc (with `long long`), random floating-point programs checked bit for bit, the c-testsuite) |
| [c.mk](c.mk) | make rules: a program's Makefile is `NAME := x`, `SDK ?= ...`, `include $(SDK)/c/c.mk` |
| [include/horizon.h](include/horizon.h) | every syscall as a C function (`hzsys.h`, generated), the parameter blocks, the helpers; [include/dirent.h](include/dirent.h) |
| [include/hui.h](include/hui.h) | Horizon's controls library for C: windows with buttons, fields, lists, scroll bars, dialogs ([huigen.h](include/huigen.h), generated); hcc links it when a program uses it ([docs/c/apps.md](../docs/c/apps.md)) |
| [include/hgame.h](include/hgame.h), [game/](game) | hgame, the game library: full screen or a window, the blitter, images, sprites, scrolling maps, input, sound, music; `conio.h` and `joystick.h` (cc65's); hcc links it when a program includes one of them ([docs/c/games.md](../docs/c/games.md)); `make -C game test` |
| [ui/](ui) | the controls library's binding: `hui.tab` (the signature table), `lib/` (the assembly helpers), `huirt.c`; built with the Horizon tree's sources into `build/ui/` |
| [lib/](lib), [rt/](rt) | the C library on Horizon: `lib/` in C (argv, the console, stdio with files, printf, malloc, strings, folders, errno, time, math.h and strtod, the stack checks, `xload.c`: the large code model's loader of the other code banks, from the program's own file); `rt/` in assembly (the startup `crt0.s`, the arithmetic helpers (32- and 64-bit), the soft float `fp_*.s`, `setjmp.s`, the memory and string routines, `hzprog.cfg`, `model.inc`: the code model, for assembly, and `FUNC`: movable assembly). Built for both code models into `build/lib/small/` and `build/lib/large/` |
| [tools/](tools) | `hzc816.py` behind hcc, `hzlarge.py` (the large code model's link: placing functions in banks, the banks after the o65) and `ca65obj.py`, `hui816.py`, `gensys.py` (hzsys.h and the syscall stubs from horizon.inc / ABI.md / `syscalls.tab`), `genhui.py` (huigen.h and the shims from ui.inc / `ui/hui.tab`), `genrt.py` (the runtime test's tables), `o65strip.py`; `host16.py`: a program built on the PC with the Atari816's integer sizes (16-bit `int`, 32-bit `long`, unsigned `char`, packed structures; a DOS program's old C too, and the port's own fix-ups: --fixups), to compare a port's behaviour with its PC twin ([docs/c/porting.md](../docs/c/porting.md), "Test it"; its test `tests/host16`) |
| [examples/](examples) | `hello`, `window` (raw window calls), `wc` (a file tool), `guests` (the application tutorial's five steps), `viewer` (a text viewer with the controls library), `tutorial` (the games tutorial), `glimmer`, `catch`, `asmfar` (C and movable assembly: `FUNC`, the large code model): `make`, `make run`, `make test` |
| [tests/](tests) | `run.py`: libc, syscalls, code generation, float (`ieee`, and `fpu`: floating point bit for bit, `tests/fpu`), `long long` and `setjmp` (`ll`: times, and no 64-bit code in programs without it), stack, benchmarks (`bench`, `fbench`), runtime tables (`rt`), the driver's messages (`hcc`), the controls library (`ui`, `uibad`, `uitwin`, `appsdoc`), apps (`apps`), in both code models (the configurations `small` and `large`); `bigprog` (`tests/bigprog`): a program with 180 KB of code, the large model's messages and failed starts |
| | `hcc --check-calls *.c`: a program's files read together, every call without a prototype and every prototype against the definition in another file (an `int` passed where a far pointer is read); `-std=c89` for old code ([docs/c/reference.md](../docs/c/reference.md), "Old C") |
| docs | [getting started](../docs/c/getting-started.md), [reference](../docs/c/reference.md), [applications](../docs/c/apps.md), [games](../docs/c/games.md), [porting](../docs/c/porting.md) |

Templates: [../templates/c-console](../templates/c-console),
[../templates/c-window-app](../templates/c-window-app), [../templates/c-game](../templates/c-game)
(Gem Run in C). The controls library (`hui.h`) also needs the Horizon tree.
