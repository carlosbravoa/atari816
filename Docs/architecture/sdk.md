# SDK

The SDK (`sdk/`) is the toolchain and libraries for writing, building, testing and
packaging programs for Horizon, in C or in 65816 assembly. Its manual starts at
[sdk/docs/README.md](../../sdk/docs/README.md).

## Compiler

cc816 (`sdk/c/cc816/`) is the SDK's own C compiler, written in Python 3 with pycparser and
pcpp vendored, so nothing is downloaded. It reads C99, most of C11, old K&R and DOS-era C
under options, and some GNU C, and generates ca65 assembly. Its passes: preprocessing,
parsing, a front end that types the program and lowers it to an intermediate form of basic
blocks and virtual registers, an optimiser (propagation and folding, strength reduction,
dead-code removal), a register allocator that places the virtual registers in the direct
page or in hardware-stack slots, the code generator, and a peephole pass with branch
relaxation. `int` is 16 bits, `long` 32, `long long` 64. `float` and `double` are both IEEE
754 single precision. `__far` pointers reach any bank.

hcc (`sdk/c/bin/hcc`) builds a Horizon program from C and assembly files: it runs cc816,
ca65 and ld65 with the C library and the start-up code, checks the sizes and writes
NAME.PRG. Three memory models:

- small (the default): the whole program in one 64 KB bank.
- large code, `--code large`: code in as many banks as it needs, still one file.
- far data, `--code large --data far`: every data pointer 32 bits, the heap and constants
  in other banks. This is DOS's large model.

Details: [sdk/docs/c/compiler.md](../../sdk/docs/c/compiler.md) (the compiler) and
[sdk/docs/c/reference.md](../../sdk/docs/c/reference.md) (memory, the models, the calling
convention, the C library, optimization).

## Libraries

- C library: `stdio.h`, `stdlib.h`, `string.h`, `math.h`, `time.h`, ...
  (`sdk/c/cc816/include`). Files, formatted I/O, the heap, strings, floating point,
  `long long`, `setjmp`.
- Horizon from C: `horizon.h` and the generated `hzsys.h`. Every syscall as a C function,
  the parameter blocks, helpers.
- hgame: `hgame.h`, `conio.h`, `joystick.h`. Games: full screen or a window, images,
  sprites, tile maps, input, sound and music.
- hui: `hui.h`. Window applications with Horizon's controls library.
- ulib and ui.lib: `horizon.inc`, `ui.inc`. The same for assembly programs.

Chapters: [sdk/docs/c/library.md](../../sdk/docs/c/library.md),
[sdk/docs/c/syscalls.md](../../sdk/docs/c/syscalls.md),
[sdk/docs/c/games.md](../../sdk/docs/c/games.md), [sdk/docs/c/apps.md](../../sdk/docs/c/apps.md),
and the assembly programmer's reference
[sdk/docs/reference/README.md](../../sdk/docs/reference/README.md).

## Tools

All in Python 3, run on the PC:

- `run816.py` runs a program in emu816 with an input script, screenshots and checks.
  `inputscript.py` is its script language.
- `host16.py` builds a C program on the PC with the Atari816's integer sizes (the "host
  twin" of a port).
- `prof816.py` turns the emulator's cycle counts into a table of the program's functions.
- `img2c.py`, `img2inc.py` and `font2inc.py` convert pictures and fonts.
- `hzapp.py` checks and packs apps.
- `contact.py` puts screenshots on one sheet.
- `deploy816.py` sends a program to the board.

One section each: [sdk/docs/tools.md](../../sdk/docs/tools.md). Writing tests:
[sdk/docs/testing.md](../../sdk/docs/testing.md).

## Packaging

An app is a folder in `/APPS` with its program, its data and a text file `APP.INF` (name,
category, icon, version, requirements). `hzapp.py pack` makes an `.HZA` archive of it
(plain ustar), and Horizon's Installer installs it with a double click. `hcc --needs`
builds into the program a check of its requirements (a Horizon version, a hardware
revision, the OPL2, memory), run before `main`: [sdk/docs/apps.md](../../sdk/docs/apps.md).

## Templates, examples, skill

Templates for a console program, a window app and a game, in C and in assembly. Examples
from a hello world to a full-screen scrolling game. A skill for coding agents
(`sdk/skill/atari-816-dev/`), the short operational form of the manual. Each template and
example builds with `make` and tests itself with `make test`.
