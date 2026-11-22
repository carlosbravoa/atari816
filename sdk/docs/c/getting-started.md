# Getting started with C

From nothing to a C program running in the emulator and on the Atari816. The SDK's C
compiler is **cc816**, the SDK's own (`sdk/c/cc816`, in Python); `hcc`, the SDK's driver,
turns `.c` files into a Horizon program in one command. A second compiler, vbcc 65816, is
there for what cc816 does not do yet (floating point): section 9. Every command below was
run on Linux (x86-64) for this guide; the output is what you should see, apart from paths,
timings and sizes.

## 1. What you need

| Tool | For |
| --- | --- |
| python3 3.8+ | `hcc` and cc816, the SDK's tools |
| cc65's ca65, ld65 and ar65 | assembling and linking (cc65 2.19; Horizon's own programs are built with them) |
| make | the templates' and examples' Makefiles |
| the emulator and Horizon, built | running programs: `make -C emu` and `make -C horizon` (sdk/docs/getting-started.md, section 2) |

Nothing is downloaded: cc816 and its C library are in the SDK (it vendors pycparser and
pcpp, both BSD-licensed).

## 2. Check the tools

```
$ python3 --version; ca65 --version
Python 3.14.4
ca65 V2.19 - Git 547d923
$ sdk/c/bin/hcc --version
hcc 2.0 (Horizon C SDK: cc816 and vbcc 65816)
```

## 3. Hello in five minutes

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
hcc: building the C library for cc816 (/.../sdk/c/build/lib/cc816)
$ ls -l HELLO.PRG
-rw-rw-r-- 1 carlos carlos 8050 Nov 21 20:51 HELLO.PRG
```

The first build also builds the SDK's C library (a few seconds); after that `hcc`
compiles, links and writes the program at once. `--map` adds the sizes:

```
$ sdk/c/bin/hcc --map -o HELLO.PRG hello.c
HELLO.PRG: 8,050 bytes on the card, 8 relocations
  code bank: code+constants 7,830 + data 78 + bss 826 = 8,734 of 57,072; heap 48,338; software stack 8,192
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
and records the console. `--shot 2` takes a screenshot two seconds after the start,
`--script FILE` types keys and clicks the mouse (sdk/docs/getting-started.md, section 5).
Window programs start from the Desktop: leave out `--mode shell`.

## 5. A project with make

Copy the C console template (arguments, a line typed at the keyboard, a file written
and read back):

```
$ cp -r sdk/templates/c-console greet && cd greet
```

Its Makefile is three settings and one include; set `SDK` to where the sdk folder is
from the copy (here `../sdk`):

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
program; `sdk/c/c.mk` lists the settings (HZ_CC, HCCFLAGS, RUNMODE, ARGS, ...).

## 6. When something is wrong

Compiler messages come with the file and the line:

```
$ sdk/c/bin/hcc -o BAD.PRG bad.c
bad.c:6: error: syntax error, before: printf
hcc: 1 file(s) did not compile
```

A program too big for its memory is stopped with the sizes:

```
$ sdk/c/bin/hcc -o BIG2.PRG big2.c
hcc: BIG2.PRG does not fit in its code bank: code, constants, data and bss = 73,140 bytes;
a code bank holds 65,264 bytes ($0100-$FFF0) and the software stack takes 8,192 of them (hcc
--stack N), so 57,072 are left. Put big arrays in a bank of their own (hz_far_alloc,
docs/c/reference.md), make them smaller, or give the software stack less.
```

A name nothing defines is said in C's terms (`undefined: nosuch (used in main.s)`).
A crash shows on the console as `[kill] task N NAME cause CC addr AAAAAA pc PPPPPP`
(ABI.md, "Faults"): link with `--map`, look up `pc`'s offset (the low 16 bits) in
`NAME.lbl` (every label with its address, sorted by the linker: the nearest one below is
the function or the block in it), and you have the place.

## 7. On the real machine

A `.PRG` is an ordinary Horizon program: copy it to the SD card (in `/BIN` it is a
command of the shell) or send it over the PC link with `sdk/tools/deploy816.py`, as for
assembly programs (sdk/docs/getting-started.md, section 6). Programs built with this SDK
were run in the emulator only so far (it models the board's timing within about 5 %).

## 8. Next

- `sdk/c/examples/`: `hello`, `window` (a window with text, shapes, mouse clicks and the
  close box, on the raw window calls), `wc` (a file tool). Each has `make`, `make run`,
  `make test`.
- [reference.md](reference.md): the two compilers, memory (where code, data, heap and the
  stacks live, the limits), int and pointer sizes, far memory, the calling convention for
  assembly, the C library on Horizon, syscalls from C, speed.
- [apps.md](apps.md): window applications with Horizon's controls library (`hui.h`:
  buttons, fields, lists, menus, dialogs, the file dialog), a tutorial in five steps;
  the template `sdk/templates/c-window-app`, the example `sdk/c/examples/viewer`.
- [porting.md](porting.md): what breaks when C from a PC or from cc65 comes over, and how
  to find it.
- `make -C sdk/c test`: the SDK's own tests in the emulator.

## 9. vbcc, the second compiler

vbcc 65816 (Volker Barthelmann's) has what cc816 has not yet: floating point (`float`,
`double`, `math.h`; `hcc --float`), `setjmp`, and a tiny memory model. It is free for
non-commercial use and may be redistributed only unmodified, so a script downloads the
official archive:

```
$ sdk/c/tools/get-toolchain.sh
get-toolchain: downloading http://www.ibaug.de/vbcc/vbcc65816_r2.zip
get-toolchain: vbcc65816_r2.zip OK (sha256 e8950454d55327e50f6a5f98dc22ac020ee3d6084a17c92d37e088d3c63a922c)
get-toolchain: installed vbcc65816_r2 in /.../sdk/c/toolchain/vbcc
get-toolchain: hcc (sdk/c/bin/hcc) finds it there; nothing to add to PATH
```

It needs Linux on x86-64 (or WSL), sh, curl or wget, unzip and sha256sum. Then `hcc --cc
vbcc ...` (or `HZ_CC=vbcc` in the environment, `make HZ_CC=vbcc` for a project) builds
with it; every file of a program must come from the same compiler. A program with a
`float` tells you so with cc816:

```
$ sdk/c/bin/hcc -o F.PRG f.c
f.c:5: error: floating point (float, double) is not supported by cc816 yet: build with hcc --cc vbcc
hcc: 1 file(s) did not compile
```
