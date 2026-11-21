# Getting started with C

From nothing to a C program running in the emulator and on the Atari816. The SDK's C
compiler is **vbcc** (Volker Barthelmann's, its 65816 release); `hcc`, the SDK's driver,
turns `.c` files into a Horizon program in one command. Every command below was run on
Linux (x86-64) for this guide; the output is what you should see, apart from paths,
timings and sizes.

**Licence.** vbcc is free for non-commercial use; commercial use needs the author's
permission (vbcc.pdf, "Legal"). It may be redistributed only unmodified, so the SDK does
not include it: a script downloads the official archive. The SDK's own files are under
the SDK's licence.

## 1. What you need

| Tool | For |
| --- | --- |
| Linux on x86-64 (or WSL on Windows) | the vbcc 65816 binaries are x86-64 Linux programs |
| python3 3.8+ | `hcc`, the SDK's tools |
| sh, curl or wget, unzip, sha256sum (or shasum) | the toolchain installer |
| make | the templates' and examples' Makefiles |
| the emulator and Horizon, built | running programs: `make -C emu` and `make -C horizon` (sdk/docs/getting-started.md, section 2) |
| gcc (only with `--source`) | building vbcc's compiler from its source snapshot instead |

## 2. Install the compiler

```
$ sdk/c/tools/get-toolchain.sh
get-toolchain: downloading http://www.ibaug.de/vbcc/vbcc65816_r2.zip
get-toolchain: vbcc65816_r2.zip OK (sha256 e8950454d55327e50f6a5f98dc22ac020ee3d6084a17c92d37e088d3c63a922c)
get-toolchain: installed vbcc65816_r2 in /.../sdk/c/toolchain/vbcc
get-toolchain: hcc (sdk/c/bin/hcc) finds it there; nothing to add to PATH
```

It downloads "vbcc for 65816 Release 2" (10 MB), checks its SHA-256 sum and unpacks the
Linux binaries into `sdk/c/toolchain/vbcc` (ignored by git). Running it again does nothing
(`--force` installs again). Without network, copy `vbcc65816_r2.zip` into
`sdk/c/toolchain/dl/` (or pass `--dl FOLDER`). If the server ever has a different file,
the script stops and says so rather than install something untested.

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
hcc: building the C library for the large model (/.../sdk/c/build/lib/large)
$ ls -l HELLO.PRG
-rw-rw-r-- 1 carlos carlos 8770 Nov 21 17:32 HELLO.PRG
```

The first build of each memory model also builds the SDK's C library (a few seconds);
after that `hcc` compiles, links and writes the program at once. `--map` adds the sizes:

```
$ sdk/c/bin/hcc --map -o HELLO.PRG hello.c
HELLO.PRG: 8,770 bytes on the card, 168 bank relocations
  code bank: code+constants 7,964 + data 91 + bss 776 = 8,831 of 65,280; heap 56,433
  window:    stack about 32,000 (from $7F7F down to $0100)
```

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
python3 ../sdk/c/bin/hcc --model large  -o GREET.PRG main.c
$ make test
...
run816: PASS (3 expected texts found)
```

`make run` runs it with `test.script` (it types "Ada" and Enter) and leaves the console
and a screenshot in `build/run/`. Every `.c` and `.s` in the folder is part of the
program; `sdk/c/c.mk` lists the settings (MODEL, HCCFLAGS, RUNMODE, ARGS, ...).

## 6. When something is wrong

Compiler messages come with the file and line:

```
$ sdk/c/bin/hcc -o BAD.PRG bad.c
bad.c:5: warning: ; expected (vbcc 54)
```

(vbcc repairs some syntax errors with a warning and goes on; read every warning.) A
program too big for its memory is stopped with the sizes:

```
$ sdk/c/bin/hcc -o BIG2.PRG big2.c
hcc: BIG2.PRG does not fit in its code bank: code and constants 4,047 bytes + initialised
data 91 bytes + zeroed data (bss) 70,776 bytes = 74,914 bytes; a code bank holds 65,280
bytes ($0100-$FFFF). Put big arrays in a bank of their own (hz_far_alloc,
docs/c/reference.md) or make them smaller.
```

A crash shows on the console as `[kill] task N NAME cause CC addr AAAAAA pc PPPPPP`
(ABI.md, "Faults"): link with `--map`, look up `pc`'s offset (the low 16 bits) in
`NAME.map`, and you have the function.

## 7. On the real machine

A `.PRG` is an ordinary Horizon program: copy it to the SD card (in `/BIN` it is a
command of the shell) or send it over the PC link with `sdk/tools/deploy816.py`, as for
assembly programs (sdk/docs/getting-started.md, section 6). Programs built with this SDK
were run in the emulator only so far (it models the board's timing within about 5 %).

## 8. Next

- `sdk/c/examples/`: `hello`, `window` (a window with text, shapes, mouse clicks and the
  close box, on the raw window calls), `wc` (a file tool). Each has `make`, `make run`,
  `make test`.
- [reference.md](reference.md): the memory models (where code, data, heap and stack live,
  the limits), int and pointer sizes, far memory, the calling convention for assembly, the
  C library on Horizon, syscalls from C, speed.
- [apps.md](apps.md): window applications with Horizon's controls library (`hui.h`:
  buttons, fields, lists, menus, dialogs, the file dialog), a tutorial in five steps;
  the template `sdk/templates/c-window-app`, the example `sdk/c/examples/viewer`.
- [porting.md](porting.md): what breaks when C from a PC or from cc65 comes over, and how
  to find it.
- `make -C sdk/c test`: the SDK's own tests in the emulator.
