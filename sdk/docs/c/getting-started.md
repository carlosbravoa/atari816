# Getting started with C

From an empty folder to a C program running in the emulator and on the Atari816. The SDK's
C compiler is **cc816** (`sdk/c/cc816`, written in Python). `hcc`, the SDK's driver, turns
`.c` files into a Horizon program in one command. Floating point is section 8. The
commands and outputs below are from Linux (x86-64). Your output should match, apart from
paths, timings and sizes.

## 1. What you need

| Tool | For |
| --- | --- |
| python3 3.8+ | `hcc` and cc816, the SDK's tools |
| cc65's ca65, ld65 and ar65 | assembling and linking (cc65 2.19, also used for Horizon) |
| make, a C compiler for the PC | the Makefiles, building the emulator |
| this repository | the SDK, Horizon and the emulator |

Build the emulator and Horizon once, from the repository's top folder
([../getting-started.md](../getting-started.md), section 2):

```
$ make -C emu
$ make -C horizon
```

Nothing else is needed and nothing is downloaded: cc816 and its C library are in the SDK,
which vendors pycparser and pcpp (both BSD-licensed).

## 2. Check the tools

```
$ python3 --version; ca65 --version
Python 3.14.4
ca65 V2.19 - Git 547d923
$ sdk/c/bin/hcc --version
hcc 3.0 (Horizon C SDK: cc816)
```

## 3. Hello, world

```c
/* hello.c */
#include <stdio.h>

int main(int argc, char **argv)
{
    int i;
    printf("Hello, Atari816!\n");
    for (i = 1; i < argc; i++)
        printf("argument %d: %s\n", i, argv[i]);
    return 0;
}
```

```
$ sdk/c/bin/hcc -o HELLO.PRG hello.c
hcc: building the C library for the small code model (/.../sdk/c/build/lib/small)
$ ls -l HELLO.PRG
-rw-rw-r-- 1 user user 8561 Nov 22 21:52 HELLO.PRG
```

The first build also builds the SDK's C library (a few seconds). Later builds only
compile, link and write the program. `--map` adds the sizes:

```
$ sdk/c/bin/hcc --map -o HELLO.PRG hello.c
HELLO.PRG: 8,561 bytes on the card, 8 relocations
  code bank: code+constants 8,335 + data 84 + bss 942 = 9,361 of 57,072; heap 47,711; software stack 8,192
  window:    stack about 32,000 (from $7F7F down to $0100); direct page 120 bytes
```

(HELLO.map and HELLO.lbl, the link map and every label's address, are written too.)

## 4. Run it in the emulator

```
$ python3 sdk/tools/run816.py HELLO.PRG --horizon horizon --mode shell --args 'one "two words"'
run816: HELLO at /APPS/HELLO.PRG, started at 4.2 s, ran to 7.2 s (emu816 exit 3; 3 = time limit, the normal end)
  /.../run-hello/console.txt
$ tail -4 run-hello/console.txt
Hello, Atari816!
argument 1: one
argument 2: two words
>
```

run816 copies Horizon's SD card, puts the program at `/APPS/HELLO.PRG`, boots the
emulator without a window, types the program's path and arguments at the shell's prompt
and records the console. `--shot 2` takes a screenshot two seconds after the start.
`--script FILE` types keys and clicks the mouse ([../getting-started.md](../getting-started.md),
section 5). Window programs start from the Desktop: leave out `--mode shell`.

## 5. A project with make

Copy the C console template (arguments, a line typed at the keyboard, a file written
and read back):

```
$ cp -r sdk/templates/c-console greet && cd greet
```

Its Makefile has a few settings and one include. Set `SDK` to the path of the sdk folder
as seen from the copy (here `../sdk`):

```make
NAME := greet
SDK  ?= ../sdk
ARGS := one "two words"
TESTFLAGS := --expect 'argument 2: two words' --expect 'Hello, Ada! Your name has 3 letters.' \
             --expect 'GREET.LOG now has 1 line(s).'
include $(SDK)/c/c.mk
```

```
$ make
python3 ../sdk/c/bin/hcc  -o GREET.PRG main.c
$ make test
...
run816: PASS (3 expected texts found)
```

`make run` runs it with `test.script` (it types "Ada" and Enter) and leaves the console
and a screenshot in `build/run/`. Every `.c` and `.s` in the folder is part of the
program. `sdk/c/c.mk` lists the settings (HZ_CODE, HCCFLAGS, RUNMODE, ARGS, ...).

## 6. Errors

Compiler messages come with the file, the line and the column (here `bad.c` misses the
`;` at the end of its line 5, `int x = 1`):

```
$ sdk/c/bin/hcc -o BAD.PRG bad.c
bad.c:6:5: error: expected ';' before 'printf' (at the end of line 5)
hcc: 1 file(s) did not compile
```

A program too big for its memory is rejected with the sizes. Here the program is the
SDK's test program of 180 KB of code (`python3 sdk/c/tests/bigprog/genbig.py big` writes
it into `big/`, then `cd big`):

```
$ ../sdk/c/bin/hcc -o GAME.PRG big*.c
hcc: GAME.PRG: program too big by 138,358 bytes: build with --code large. It does not fit
in its code bank: code and constants 194,404 + data 84 + bss 942 = 195,430 bytes; the
biggest part: code and constants. A code bank holds 65,264 bytes ($0100-$FFF0) and the
software stack takes 8,192 of them (hcc --stack N), so 57,072 are left. Build it with hcc
--code large: its code then goes in several banks (docs/c/porting.md). ...
```

When the code does not fit, build with `--code large`: hcc puts the code in several banks.
It still writes one file, `GAME.PRG`, with the other code banks after the main bank. Copy
it to any folder of the card (it requires Horizon 0.28 or later):

```
$ ../sdk/c/bin/hcc --code large --map -o GAME.PRG big*.c
GAME.PRG: 213,679 bytes on the card, 317 relocations
  code bank: code+constants 43,678 + data 84 + bss 1,866 = 45,628 of 57,072; heap 11,444; software stack 8,192
  window:    stack about 32,000 (from $7F7F down to $0100); direct page 120 bytes
  code model large: 28,231 bytes of movable code in the main bank, 161,112 in 3 other bank(s) (65,523, 65,535, 30,054); 1364 thunks
  one file: the o65 44,581 bytes, then the other banks 169,098 bytes; 3946 bank bytes patched at the start
  the main bank without its movable code: 17,397 bytes (code that must stay 11,038, constants 4,409, data 84, bss 1,866)
```

Data, constants and the stacks still share the first bank. When they do not fit, hcc
reports it, and big arrays go to banks of their own (`hz_far_alloc`). See
[porting.md](porting.md), "When the program is too big", and
[reference.md](reference.md#code-models), "Code models".

An undefined name is reported in C's terms (`undefined: nosuch (used in main.s)`). A
crash shows on the console as `[kill] task N NAME cause CC addr AAAAAA pc PPPPPP` (ABI.md,
"Faults"). To find the place, link with `--map` and look up `pc`'s offset (the low 16
bits) in `NAME.lbl`. That file lists every label with its address, sorted by the linker:
the nearest label below the offset is the function or the block in it.

## 7. On the real machine

A `.PRG` is an ordinary Horizon program (one built with `--code large` is one file too):
copy it to the SD card (in `/BIN` it is a command of the shell) or send it over the PC
link with `sdk/tools/deploy816.py`, as for assembly programs
([../getting-started.md](../getting-started.md), section 6). The emulator models the
board's timing within about 5 %.

## 8. Floating point

`float` and `double` work. Both are IEEE 754 single precision: 32 bits, about
7 decimal digits (`double` is not 64 bits, as on a PC). `math.h` has the usual functions,
and printf prints floats with `%f`, `%e` and `%g`:

```c
/* circle.c - floating point */
#include <stdio.h>
#include <math.h>

int main(void)
{
    double r = 2.5;
    printf("area %.4f, circumference %.4f\n", M_PI * r * r, 2 * M_PI * r);
    printf("sqrt(2) = %.7f, sin(1) = %g\n", sqrt(2.0), sin(1.0));
    printf("1/3 = %.10f\n", 1.0 / 3);
    return 0;
}
```

```
$ sdk/c/bin/hcc -o CIRCLE.PRG circle.c
$ python3 sdk/tools/run816.py CIRCLE.PRG --horizon horizon --mode shell
run816: CIRCLE at /APPS/CIRCLE.PRG, started at 3.45 s, ran to 6.45 s (emu816 exit 3; 3 = time limit, the normal end)
  /.../run-circle/console.txt
$ tail -4 run-circle/console.txt
area 19.6350, circumference 15.7080
sqrt(2) = 1.4142135, sin(1) = 0.841471
1/3 = 0.3333333433
>
```

The last line shows the 7 digits: a 64-bit `double` would give 0.3333333333. The command
needs no extra option: hcc links the floating-point code only into programs that use it.
It costs space and time: CIRCLE.PRG is 18 KB (the hello world 8 KB), and an operation
takes from 20 to 300 microseconds, `sin` about 4 milliseconds. Keep floats out of
anything that runs every frame. The details: [reference.md](reference.md), "Floating
point".

## 9. Next

- `sdk/c/examples/`: `hello`, `window` (a window with text, shapes, mouse clicks and the
  close box, on the raw window calls), `wc` (a file tool). Each has `make`, `make run`,
  `make test`.
- [reference.md](reference.md): the compiler, memory (where code, data, heap and the
  stacks live, the limits), int and pointer sizes, far memory, the calling convention for
  assembly, the C library on Horizon, floating point, syscalls from C, performance.
- [apps.md](apps.md): window applications with Horizon's controls library (`hui.h`:
  buttons, fields, lists, menus, dialogs, the file dialog), a tutorial in five steps,
  the template `sdk/templates/c-window-app`, the example `sdk/c/examples/viewer`.
- [porting.md](porting.md): porting C from a PC or from cc65: the usual faults, how to
  find them, and what to do when the program is too big (`hcc --code large`).
- [../apps.md](../apps.md) (Horizon 0.29): your program as an app that users install
  with a double click: one folder in `/APPS` with APP.INF, an `.HZA` archive made with
  `sdk/tools/hzapp.py`, and `hcc --needs` (the program checks its requirements at its
  start).
- [compiler.md](compiler.md): cc816, its options, reading its output.
  [library.md](library.md): every header and function. [../tools.md](../tools.md) and
  [../testing.md](../testing.md): the tools and testing. [../README.md](../README.md): the
  map of the whole manual.
