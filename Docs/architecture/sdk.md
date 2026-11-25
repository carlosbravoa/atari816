# The SDK

The SDK (`sdk/`) is what a programmer uses to write, build, test and package programs for
Horizon, in C or in 65816 assembly. Its manual starts at
[sdk/docs/README.md](../../sdk/docs/README.md); this page is the overview.

## The compiler

**cc816** (`sdk/c/cc816/`) is the SDK's own C compiler, written in Python 3 with pycparser
and pcpp vendored: nothing is downloaded. It reads C99, most of C11, old K&R and DOS-era C
under options, and some GNU C, and writes ca65 assembly. Its passes: preprocessing, parsing,
a front end that types the program and lowers it to an intermediate form of basic blocks
and virtual registers, an optimiser (propagation and folding, strength reduction,
dead-code removal), a register allocator that puts the virtual registers in the direct
page or in hardware-stack slots, the code generator and a peephole pass with branch
relaxation. `int` is 16 bits, `long` 32, `long long` 64; `float` and `double` are both IEEE 754
single precision; `__far` pointers reach any bank.

**hcc** (`sdk/c/bin/hcc`) is the one command that turns C and assembly files into a
Horizon program: it runs cc816, ca65 and ld65 with the C library and the start-up code,
checks the sizes and writes NAME.PRG. Three memory models:

| Model | Option | What it gives |
| --- | --- | --- |
| small | (the default) | the whole program in one 64 KB bank |
| large code | `--code large` | code in as many banks as it needs, still one file |
| far data | `--code large --data far` | every data pointer 32 bits, the heap and constants in other banks: DOS's large model |

Details: [sdk/docs/c/compiler.md](../../sdk/docs/c/compiler.md) (the compiler itself) and
[sdk/docs/c/reference.md](../../sdk/docs/c/reference.md) (memory, the models, the calling
convention, the C library, speed).

## The libraries

| Library | Header | For |
| --- | --- | --- |
| The C library | `stdio.h`, `stdlib.h`, `string.h`, `math.h`, `time.h`, ... (`sdk/c/cc816/include`) | files, formatted I/O, the heap, strings, floating point, `long long`, `setjmp` |
| Horizon from C | `horizon.h`, `hzsys.h` (generated) | every syscall as a C function, the parameter blocks, helpers |
| hgame | `hgame.h`, `conio.h`, `joystick.h` | games: full screen or a window, images, sprites, tile maps, input, sound and music |
| hui | `hui.h` | window applications with Horizon's controls library |
| ulib, ui.lib | `horizon.inc`, `ui.inc` | the same for assembly programs |

Chapters: [sdk/docs/c/library.md](../../sdk/docs/c/library.md),
[sdk/docs/c/syscalls.md](../../sdk/docs/c/syscalls.md),
[sdk/docs/c/games.md](../../sdk/docs/c/games.md), [sdk/docs/c/apps.md](../../sdk/docs/c/apps.md),
and the assembly programmer's reference
[sdk/docs/reference/README.md](../../sdk/docs/reference/README.md).

## The tools

All in Python 3, run on the PC: `run816.py` runs a program in emu816 with an input script,
screenshots and checks; `inputscript.py` is its script language; `host16.py` builds a C
program on the PC with the Atari816's integer sizes (the "host twin" of a port);
`prof816.py` turns the emulator's cycle counts into a table of the program's functions;
`img2c.py`, `img2inc.py` and `font2inc.py` convert pictures and fonts; `hzapp.py` checks
and packs apps; `contact.py` puts screenshots on one sheet; `deploy816.py` sends a program
to the board; `doccheck.py` checks that the manual names every public function and option.
One section each: [sdk/docs/tools.md](../../sdk/docs/tools.md). How tests are written:
[sdk/docs/testing.md](../../sdk/docs/testing.md).

## Packaging

An app is a folder in `/APPS` with its program, its data and a text file `APP.INF`
(name, category, icon, version, what it needs). `hzapp.py pack` makes an `.HZA` archive of
it (plain ustar), and Horizon's Installer installs it with a double click. `hcc --needs`
builds into the program a check of what it needs (a Horizon version, a hardware revision,
the OPL2, memory), run before `main`: [sdk/docs/apps.md](../../sdk/docs/apps.md).

## Templates, examples, the skill

Templates for a console program, a window app and a game, in C and in assembly; examples
from a hello world to a full-screen scrolling game; and a skill for coding agents
(`sdk/skill/atari-816-dev/`), the short operational form of the manual. Each template and
example builds with `make` and checks itself with `make test`.
