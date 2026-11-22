# C reference

The C SDK for Horizon: its two compilers, how a C program is laid out in memory, its
types, far memory, the calling convention (for assembly), inline assembly, the C library
on Horizon, floating point, `long long`, `setjmp`, syscalls from C, the stacks, the
compilers' faults and what the SDK does about them, and speed. Getting started: [getting-started.md](getting-started.md); window applications (the
controls library, `hui.h`): [apps.md](apps.md); games: [games.md](games.md); porting:
[porting.md](porting.md).

| | |
| --- | --- |
| Compilers | **cc816**, the SDK's own (`sdk/c/cc816`, Python 3, writes ca65 assembly): the default. **vbcc 65816** Release 2 (Volker Barthelmann): `hcc --cc vbcc`, installed by `sdk/c/tools/get-toolchain.sh` |
| Driver | `sdk/c/bin/hcc` (`hcc -h` lists the options); `--cc cc816` or `--cc vbcc`, or `HZ_CC` in the environment (`make HZ_CC=vbcc` for a program built with c.mk) |
| Headers | `horizon.h` (syscalls, blocks, helpers), `hui.h` (the controls library: [apps.md](apps.md)), `hgame.h`, `conio.h`, `joystick.h` ([games.md](games.md)), `dirent.h`; the C library's: cc816's own (`sdk/c/cc816/include`: `stdio.h`, `stdlib.h`, `string.h`, `math.h`, `float.h`, `ctype.h`, `time.h`, `errno.h`, `stdint.h`, `inttypes.h`, `stdarg.h`, `setjmp.h`, `limits.h`, ...), vbcc's |
| Library | `sdk/c/lib` (both compilers), `sdk/c/lib/cc816` and `sdk/c/rt/cc816` (cc816: the whole C library and its runtime), `sdk/c/lib/vbcc`, `sdk/c/rt`, `sdk/c/fastrt` (vbcc: over vbcc's own binary library); hcc builds them into `sdk/c/build/lib/<cc816, large, tiny>/` |
| Make | `sdk/c/c.mk` (a program's Makefile is three lines) |

## The two compilers

Every file of a program is built with the same compiler: hcc refuses an object or a
library made by the other one ("an object or library made by vbcc ...: build every file
with the same compiler").

| | cc816 (default) | vbcc (`--cc vbcc`) |
| --- | --- | --- |
| Memory | one data model ("Memory", below), two code models (`--code small`, `--code large`: "The two code models") | the large and the tiny model (`--model`) |
| Data pointer | 16 bits: an offset in the code bank; `__far` 32 bits | large: 32 bits; tiny: 16 bits (the window) |
| Floating point | IEEE 754 single precision: `float`, `double` and `long double` are all 32 bits; math.h; linked only into programs that use it ("Floating point", below) | `float`, `double` (32 bits, MS BASIC's format), math.h: `--float` |
| `long long` | yes, 64 bits ("long long (cc816)", below) | no (vbcc 65816 fails on it) |
| `setjmp` / `longjmp` | yes ("setjmp and longjmp (cc816)") | in its library, not tested |
| Inline assembly | `asm("...")`, ca65 text ("Inline assembly (cc816)") | no |
| Assembly files (`.s`) | ca65 syntax ("Calling convention", below) | vasm oldstyle syntax |
| Linking | ld65, Horizon's own linker: an o65 file straight away | vlink three times, then mko65 ("Program files") |
| Controls library (`hui.h`) | linked straight in by ld65 | a block made by ld65 at $0100 |
| Known faults | none open ("Compiler notes") | seven, six repaired by hcc ("Compiler notes") |
| Needs | Python 3, cc65's ca65, ld65 and ar65 | its toolchain (x86-64 Linux binaries, downloaded), and cc65 for `hui.h` |
| Licence | the SDK's (pycparser and pcpp inside are BSD) | free for non-commercial use, may be redistributed only unmodified |

**What needs `--cc vbcc`:** only the tiny model. Floating point, `long long`,
`setjmp`/`longjmp` and inline assembly are all in cc816 (below). Neither compiler has a
64-bit `double` or variable-length arrays. A program with more code than one bank holds
needs cc816's large code model (`hcc --code large`, "The two code models", below).

## Memory (cc816)

```
cc816 (the small code model; the large one: "The two code models", below)

code bank (the program's own 64 KB, DBR)
$0100   code, then constants (strings, const)
        initialised data
        zeroed data (bss)
        heap (malloc) ...
        software stack guard zone (256 bytes)
        software stack ... grows down: arrays, structures,       --stack N (default 8192)
        locals whose address is taken
$FFF0

window (bank 0, 32 KB, private)
$0000   direct page: cc816's registers $00-$77, then the controls
        library's when the program uses hui.h
$0100   hardware stack guard zone (256 bytes)
 ...    hardware stack (grows down): return addresses, arguments,
        spilled registers
$7F7F   ... argument string, at most $7FFE

other banks (64 KB each): hz_far_alloc(), __far pointers
```

Every data pointer is a 16-bit offset in the code bank: globals, string constants,
`malloc` blocks and the locals that need an address (arrays, structures, `&x`) are all
there, so any pointer reaches any of them, and code reads them with 16-bit addresses
through DBR. The other locals live in direct-page registers or on the hardware stack.

| | cc816 |
| --- | --- |
| Code + constants + data + bss | 65,264 bytes ($0100-$FFF0) less the software stack: 57,072 with the default 8,192 |
| Heap | from the end of bss to the software stack's guard zone (a small program: about 48,000 bytes) |
| Software stack | `--stack N` bytes (512-32,768, even; default 8,192): arrays, structures and locals whose address is taken |
| Hardware stack | about 32,000 bytes (from just below the argument string to $0100) |
| Direct page | $00-$77: 48 bytes of scratch registers, 48 callee-saved, the software stack pointer, the runtime helpers' words, the code bank's number |
| DBR (the data bank) | the code bank |

`hcc` checks the sizes after linking and says what does not fit, in bytes ("program too
big by N bytes: build with --code large" when the code is what does not fit). The
loader's own limits: the program file is less than 64 KB, and code + data + bss fit in
$0100-$FFFF. With `hcc --code large` the code may also fill other banks; the rest of this
picture stays as it is (the code bank is then called the main bank).

## The two code models (cc816)

cc816 has two code models. Both have the same data: every data pointer is a 16-bit
offset in the main bank, and DBR is always the main bank. They differ in where the code
goes and in how functions are called.

| | small (the default) | large (`hcc --code large`) |
| --- | --- | --- |
| Code | in the code bank, with everything else | in the main bank while it has room, then in other banks of 64 KB (up to 64 of them) |
| Calls | JSR / RTS | JSL / RTL, wherever the function is |
| The first argument | at `3,s` | at `4,s` (the return address has 3 bytes) |
| A function pointer | 16 bits: the function | 16 bits: the function's entry in the main bank (the function itself, or a 4-byte thunk, a JML to it) |
| Files | NAME.PRG | NAME.PRG, and NAME.PRX when code went to other banks |
| Data, constants, bss, heap, software stack | the code bank | the main bank: the same |
| `__CC816_LARGE__` | not defined | defined (1) in C and in assembly (`ca65 -D`) |

`hcc --code large` (or `HZ_CODE=large` in the environment; `HZ_CODE := large` in a
Makefile made with c.mk) builds a program in the large model. Nothing in the C changes.
Every file of a program must be built for the same model, libraries included: hcc builds
the C library, the game library and the controls library for both, and refuses an object
made for the other model ("an object made for the small code model; this program is
linked for the large one").

### What goes where

**The main bank** (the .PRG, loaded by Horizon as any program) holds the startup, the C
library and every other library (hgame, the controls library, ulib), the `.s` files, the
C functions that have inline assembly or are `naked`, the constructors and destructors
(`_INIT_n_name`, `_EXIT_n_name`), the thunks, all the constants (string literals, `const`
tables, floating-point constants), the initialised data, the bss, the heap and the
software stack. These are limited to the main bank, as in the small model.

**The other C functions can move.** cc816 puts each one in a segment of its own (in a
file of more than 100 of them, runs of consecutive functions share one: ca65 and ar65
take only so many segments a module), and hcc places them after it has linked the rest:
first in the main bank, as long as it has room (it keeps `--heap N` bytes free for
`malloc`, 4096 by default), then in other banks, each function in the first bank with
room, in the order of the files and of the functions in them. A function must fit in one
bank (65,535 bytes). When everything fits in the main bank there is no .PRX and no
loading: the program is one file, as in the small model.

`hcc --map` shows the result:

```
GAME.PRG: 45,049 bytes on the card, 409 relocations
  code bank: code+constants 43,982 + data 78 + bss 1,678 = 45,738 of 57,072; heap 11,334; software stack 8,192
  window:    stack about 32,000 (from $7F7F down to $0100); direct page 120 bytes
  code model large: 23,882 bytes of movable code in the main bank, 155,650 in 3 other bank(s) (65,511, 65,495, 24,644); 1396 thunks
  GAME.PRX: 164,790 bytes, 4527 bank bytes patched at the start
```

(a program of 1,600 functions, `sdk/c/tests/large/genbig.py`: about 180 KB of code).

| Limit | |
| --- | --- |
| Code | the main bank's room, plus 64 banks of 64 KB (about 4 MB); an 8 MB machine has about 80 free banks when nothing else runs |
| One function | 65,535 bytes |
| The main bank | startup + libraries + `.s` files + functions with inline assembly + constructors + thunks (4 bytes for each function in another bank whose address is used) + constants + data + bss + 4 KB of heap (`--heap N`) + the software stack (`--stack N`) must fit in 65,264 bytes |
| The .PRG file | below 64 KB (Horizon's loader) |

### How the program is loaded

Horizon loads NAME.PRG as it loads any program: an o65 file, below 64 KB. A large
program's other code banks cannot be in the same file: Horizon's loader takes only files
below 64 KB, and a program is not told the path it was started from. So they are in a
second file, NAME.PRX, written by hcc next to the .PRG. **Copy both to the card, into the
same folder.**

Before the constructors run, the startup (`sdk/c/lib/cc816/xload.c`):

1. opens NAME.PRX: in the current folder first (where Files starts programs, and where
   the shell is after `cd`), then in `/APPS`, `/BIN`, `/SYSTEM`, `/SYSTEM/TESTS` and
   `/GAMES`. `hcc --prx-path /GAMES/MINE:/APPS` gives other folders (after the current
   one). A program started from the Desktop's Programs menu, or by its path from another
   folder, finds its .PRX only in those folders: install a large program in one of them,
   or build it with `--prx-path` naming its folder;
2. checks it: its header, its number of banks and the stamp of its build (hcc writes the
   same stamp into the .PRG): a .PRX of another build is refused;
3. takes a bank for each image (`hz_bank_alloc`) and reads the image into it;
4. patches the bank bytes: the bank of each JSL to a function in another bank (and of
   the MVN of a structure copy), in the main bank and in the others: the banks are known
   only now;
5. closes the file. Then the constructors, `main` and the rest run as usual.

In the emulator a program of 45 KB with a 165 KB .PRX starts in about 0.15 s (a small
program in 0.01 s). Horizon gives the banks back when the program ends, as all of a
program's banks.

If something is wrong, the program prints one line on the console and ends with exit
code 1 before any of its own code runs; when the window system runs, the line is also
shown in a small window (a key or a click closes it):

| | |
| --- | --- |
| `GAME.PRX: not found (the program's code banks): keep it next to the .PRG, in the current folder or in /APPS, /BIN, /SYSTEM, /SYSTEM/TESTS, /GAMES` | the .PRX is missing, or in a folder the program does not look in |
| `GAME.PRX: made by another build of the program: copy the .PRG and the .PRX of the same build` | the two files are from different builds |
| `GAME.PRX: not enough memory: no free 64 KB bank for the program's code` | the machine has not enough free banks (close a program) |
| `GAME.PRX: not a .PRX file ...`, `cannot read the file ...` | a damaged file, a card error |

### The .PRX file

| | |
| --- | --- |
| Header, 12 bytes | `HZPX`, version 1, n (the number of banks), 0, 0, the stamp (u32) |
| n x u32 | each bank's image size |
| the images | bank 1, bank 2, ..., each from offset 0 of its bank |
| u16 | the number of relocation groups |
| the groups | each: u8 where (0 the main bank, k bank k), u8 to (the bank whose number is stored), u16 count, then count u16 offsets: the bytes that get that bank's number |

hcc makes it with ld65 alone (`sdk/c/tools/hzlarge.py`, "Program files" below).

### Costs

Measured in the emulator (sdk/c/tests/run.py: the same programs in both models; the
large model's runs put every function that can move in another bank: the worst case,
though in the large model every call is a JSL anyway):

| | small | large |
| --- | --- | --- |
| bench (-O2): sieve, sum16, mul32, fib22, strs, structs | 809, 296, 1,277, 388, 994, 670 ms | 808, 300, 1,290, 430, 1,000, 678 ms |
| bench -O1 | 809, 476, 1,280, 400, 999, 659 ms | 808, 490, 1,287, 417, 996, 674 ms |
| fbench: mandel, sincos, sqrt, expow, conv | 2,140, 1,640, 366, 1,947, 1,065 ms | 2,140, 1,640, 368, 1,939, 1,070 ms |
| hello (code + constants) | 8,083 bytes (file 8,304) | 8,213 (file 8,598) |
| window | 10,002 (file 10,227) | 10,153 (file 10,579) |
| bench | 9,733 (file 9,958) | 9,903 (file 10,369) |
| fbench | 25,802 (file 26,036) | 26,421 (file 27,799) |
| viewer (controls library) | 25,792 (file 26,443) | 26,038 (file 27,066) |

(The timer counts in steps of about 10 ms. The sizes are `hcc --map`'s with each model's
default placement: in the large model all of these fit in the main bank.) A call costs 2 cycles more (JSL against JSR),
a call through a pointer 6 more (`__icall`; 10 when the function is in another bank: its
thunk's JML), and each call site 1 byte more; the arithmetic helpers are called
with JSL too (a 16-bit division about 14 cycles more). Calls between banks cost no more
than calls inside one: all are JSL. The .PRG grows a little more than the code: each JSL
to a function in the main bank is a relocation for Horizon's loader (2 or 3 bytes of the
file). A program whose code moves also has the loader in its main bank (about 2 KB of code, 0.5 KB
of constants and 900 bytes of bss); one whose code all fits in the main bank has none.

## Memory models (vbcc)

`hcc --cc vbcc --model large` (vbcc's default) or `--model tiny`. Every file of a program
must be built with the same model.

```
LARGE (default)                                TINY (--model tiny)

code bank (the program's own 64 KB)            code bank
$0100  code, then constants (strings, const)   $0100  code
       initialised data                               the data image (copied to the
       zeroed data (bss)                              window at start)
       heap (malloc) ... up to $FFF0           ...
$FFFF                                          $FFFF

window (bank 0, 32 KB, private)                window (bank 0, 32 KB, private)
$0000  direct page: vbcc's registers           $0000  direct page (as large)
       $00-$4F, free $50-$EF, the float        $0100  constants, initialised data, bss
       library's $F0-$FF                              heap (malloc) ... up to WEND
$0100  stack guard zone (256 bytes)            WEND   stack guard zone (256 bytes)
 ...   stack (grows down)                       ...   stack (grows down)
$7F7F  ... argument string, at most $7FFE      $7F7F  ... argument string

other banks (64 KB each): hz_far_alloc()       other banks: hz_far_alloc(), __far pointers
```

| | Large | Tiny |
| --- | --- | --- |
| Data pointer | 32 bits (offset, bank): reaches the code bank, the window, any bank | 16 bits: the window only (`__far` pointers for other banks) |
| Code + constants + data + bss | 65,280 bytes in all (the code bank, $0100-$FFFF) | code (and the data image) 65,280 bytes |
| Data + bss + heap | shares the code bank with the code | 28,416 bytes (window $0100-$6FFF; `--stack N` moves WEND) |
| Heap | the rest of the code bank to $FFF0 (a small program: about 56 KB) | the rest of the window below WEND (about 27 KB) |
| Stack | about 32,000 bytes | 3,968 bytes at least (`--stack N`: N bytes, 256-28,672) |
| DBR (the data bank) | the code bank | 0 (the window) |
| Speed | the default; byte loops a little slower | faster on pointer-heavy code (bench below) |

`hcc` checks the sizes after linking and says what does not fit, in bytes. The loader's
own limits: the program file is less than 64 KB, and code + data + bss fit in $0100-$FFFF.

The large model is the simplest for ported code: every pointer reaches globals, locals and
other banks alike. The tiny model is faster where code works through pointers, and its
programs are smaller (16-bit pointers), but all data must fit in 28 KB.

## Types

| Type | Size | Range / note |
| --- | --- | --- |
| `char` | 8 bits | **unsigned** (0-255; both compilers, the library is built so); `signed char` for -128-127; cc816's `-fsigned-char` makes plain `char` signed |
| `short`, `int` | 16 bits | -32,768-32,767 (`unsigned`: 0-65,535) |
| `long` | 32 bits | |
| `long long` | 64 bits | cc816 (`int64_t`, `uint64_t`, `intmax_t`; `LLONG_MAX` ...); vbcc has none |
| `float`, `double`, `long double` | 32 bits (all three, both compilers) | cc816: IEEE 754 single precision (24-bit significand: about 7 decimal digits, 1.2e-38 to 3.4e38, denormals down to 1.4e-45); vbcc: MS BASIC's format, about 7 digits (`hcc --cc vbcc --float`) |
| data pointer | cc816: 16 bits; vbcc: 32 bits large, 16 bits tiny | `__far` (32 bits: offset, bank, 0) with both |
| function pointer | cc816: 16 bits (JSR); vbcc: 32 bits (JSL) | |
| `size_t`, `ptrdiff_t` | 16 bits | `unsigned int`, `int`: one object at most 65,535 bytes |

Structures are packed (no padding) with both compilers: the parameter blocks in
`horizon.h` match ABI.md byte for byte (each has a compile-time size check). Bytes are
little-endian.

Predefined macros: `__65816__`, `__HORIZON__`, `__ATARI816__`, and `__CC816__` with cc816
or `__VBCC__` with vbcc; with vbcc's tiny model `__MNEAR` (what vbcc defines) and `__MTINY`
(the manual's name, added by hcc), in its large model `__MLARGE`. `horizon.h` defines
`HZ_TINY` in the tiny model.

## Pointers, banks and far memory

An object (an array, a structure, a `malloc` block) must not cross a bank boundary: a
pointer's arithmetic is 16-bit. A bank is 64 KB; Horizon gives a program more of them
with `bank_alloc` (`hz_mem_info()` says how many are free: 92 banks in all on the 8 MB
machine, some used by Horizon and other programs).

```c
#include <horizon.h>

unsigned char __far *buf = hz_far_alloc();  /* a fresh bank, offset 0; NULL if none */
buf[60000u] = 1;                             /* any offset 0-65535 */
hz_far_copy(buf + 1000, "text", 5);         /* MVN, about 7 cycles a byte */
hz_far_set(buf, 0, 4096);
hz_far_free(buf);                            /* back to the system (also at exit) */
```

| | |
| --- | --- |
| `void __far *hz_far_alloc(void)` | a bank (64 KB, contents undefined) |
| `void hz_far_free(void __far *p)` | give the bank of p back |
| `hz_far_copy(dst, src, n)`, `hz_far_set(dst, c, n)` | between any banks; ranges must not cross a bank, the copy's must not overlap |
| `void __far *hz_farptr(bank, offset)`, `HZ_FARPTR(b, o)` | a pointer from a bank and an offset |
| `HZ_OFF(p)`, `HZ_BANK(p)` | a pointer's offset and bank |
| `HZ_U24(field, p)` | fill a parameter block's 3-byte pointer |

**cc816.** A plain pointer is an offset in the code bank: it cannot point into another
bank. Memory of other banks is reached through `__far` pointers (`unsigned char __far *p`),
which read and write with long addressing. A near pointer converts to a far one by itself
(its bank is the code bank; a null pointer stays null), and so `(unsigned long)p` is the
whole 24-bit address of p: `HZ_BANK(p)` of any pointer is right. A far pointer converted
to a near one keeps its offset only. An integer converts to a far pointer as it is:
`(char __far *)0x050000L` is bank 5, offset 0 (`hz_farptr(5, 0)` is the same). Code
written for vbcc's large model that keeps far addresses in plain pointers (`(char *)
hz_far_alloc()`, `(const char *)farbuf`) must say `__far` instead, or copy the data into
the code bank first (`hz_far_copy`): see [porting.md](porting.md).

**vbcc.** A large-model pointer holds an offset and a bank, and reaches the code bank, the
window and any bank alike. **Do not build pointers by casting integers** with vbcc:
`(char *)0x050000` does not give bank 5 (vbcc turns a constant integer into a pointer in
the data bank); use `hz_farptr(5, 0)`. In the tiny model a plain pointer cannot point into
another bank: declare far data with `__far`. A near pointer converts to a far one (bank 0,
the window) by itself.

## Calling convention (for assembly)

### cc816

- (The small code model, the default; the large one: "In the large code model", below.)
- Functions are called with **JSR** and return with **RTS** (a program's code is all in
  its code bank). On entry and exit A, X and Y are **16-bit** (M = X = 0), D = 0, DBR =
  PBR = the code bank: keep D and DBR.
- **Every argument is on the hardware stack**, pushed last first: at entry the first is at
  `3,s` (above the 2-byte return address), the next ones after it. Each takes 2 bytes
  (`char`, `short`, `int`, pointers, function pointers), 4 (`long`, `float`, `double`,
  `__far` pointers: offset, bank, 0) or 8 (`long long`: like two `long`s, the low word
  first, at the lowest address). The caller removes them. A structure argument is passed
  as the address of a copy the caller made (2 bytes); a structure result is written
  through a hidden first argument (the address of the caller's space), which is also
  returned in A. Variable arguments are the same (`va_list` is a far pointer into the
  stack), except a structure: among the variable arguments it is its bytes themselves,
  padded to an even size (so `va_arg(ap, struct s)` reads it).
- The **result** is in A (16-bit and smaller) or A/X (32-bit: A the low word; a `float`
  or `double` too: its IEEE bits, the sign in bit 15 of X). A `long long` result is in
  the direct page, 8 bytes at `__h0`: `__h0` the low word, `__h0+2`, `__h1`, `__h1+2` the
  high word (A and X are then undefined).
- **Registers** (direct page, `.importzp` them): `__rg` is 96 bytes: `__rg+0` to
  `__rg+47` may be changed by any function, `__rg+48` to `__rg+95` must be kept (save and
  restore what you use). `__h0`, `__h1`, `__h2`, `__h3` (4 bytes each) and `__rv` (4)
  are scratch too (the runtime's helpers use them). Never change `__sp` (the software
  stack pointer) or `__cbank` (a word: the code bank's number).
- **Names**: a C name gets an underscore: `int add(int, int)` is `_add` in assembly.
  C's globals are in the code bank: absolute addresses (DBR) reach them.

The assembler is **ca65** (cc65's: `.p816`, `.a16`/`.a8`/`.i16` after `rep`/`sep`, `.export`,
`.import`, `.importzp`, `.segment "CODE"`/`"RODATA"`/`"DATA"`/`"BSS"`). A file is one
module for the linker: ld65 links a module when the program uses one of its names, and
the whole module then.

```asm
; add3.s - unsigned add3(unsigned a, unsigned b, unsigned c) for cc816:
; a at 3,s, b at 5,s, c at 7,s (above the 2-byte return address)
        .p816
        .a16
        .i16
        .export _add3

        .segment "CODE"
_add3:  lda     3,s
        clc
        adc     5,s
        clc
        adc     7,s
        rts
```

```asm
; sum.s - unsigned long sum(const unsigned *p, unsigned n): a near pointer is an offset in
; the code bank (DBR), so (dp),y reaches it; __rg+0.. are scratch registers
        .p816
        .a16
        .i16
        .importzp __rg
        .export _sum

        .segment "CODE"
_sum:   lda     3,s             ; p
        sta     __rg+0
        lda     5,s             ; n
        asl     a
        sta     __rg+2          ; n * 2: where to stop
        stz     __rg+4          ; the sum, low word
        stz     __rg+6          ; high word
        ldy     #0
@loop:  cpy     __rg+2
        bcs     @done
        lda     (__rg+0),y
        clc
        adc     __rg+4
        sta     __rg+4
        bcc     :+
        inc     __rg+6
:       iny
        iny
        bra     @loop
@done:  lda     __rg+4          ; the result: A low, X high
        ldx     __rg+6
        rts
```

Build them with the C files: `hcc -o PROG.PRG main.c add3.s sum.s` (hcc takes `.s`
files beside the `.c` ones and assembles them with ca65). In C: `unsigned add3(unsigned
a, unsigned b, unsigned c); unsigned long sum(const unsigned *p, unsigned n);` (checked:
`add3(1, 20, 300)` is 321, `sum` of {60000, 60000, 1, 2} is 120003). Bank bytes
(`#^label`, `.faraddr`) are relocated by Horizon's loader. The compiler's own output for
any C file is `hcc -S` (FILE.s next to it), or `python3 sdk/c/cc816/cc816.py -S file.c`.
Horizon's assembly libraries (ulib, the controls library) are linked straight into a
cc816 program: they share the direct page (ld65 places their zero page after cc816's
registers).

#### In the large code model

`hcc --code large` changes only this (the rest above stays as it is):

- Functions are called with **JSL** and return with **RTL**: the first argument is at
  `4,s` (above the 3-byte return address). A `.s` function called from C ends with `rtl`;
  it calls a C function with `jsl _name` (any C function, wherever it is: hcc patches the
  bank). PBR is the bank of the code that runs; DBR is the main bank, always: keep it.
- hcc assembles `.s` files with `-D __CC816_LARGE__=1` and with `sdk/c/rt/cc816` on the
  include path: `.include "model.inc"` gives `ARGS` (3 or 4: the first argument's offset),
  `RET` (`rts` / `rtl`), `CALL name` (`jsr` / `jsl`) and `LARGE` (0 / 1), so one file
  suits both models: `lda ARGS+2,s` is the second argument. The C library's assembly is
  written so.
- `.s` files stay in the main bank. Their labels are 16-bit addresses there as before.
- A **function's 16-bit address** (a function pointer, what C's `&f` and `f` give) is its
  entry in the main bank: `__T_name` (`__T` before the assembler name). It is the
  function itself when the function is in the main bank, else a thunk (`jml _name`) that
  hcc writes. Use `__T_name` where assembly needs a C function's 16-bit address
  (`.addr __T_cb`, `lda #__T_cb`); `_name` alone is the function's code, which may be in
  another bank (hcc refuses `.addr _name` and `lda #_name` for such a function: "a value
  that depends on where code is ... its 16-bit address is __T_name").
  For an assembly function, `__T_name` is made by hcc too.
- A **call through a function pointer**: the pointer (16 bits) into `__fpt`, then `jsl
  __icall` (X is changed): `__icall` (crt0.s) jumps to the entry, and the function
  returns straight to the caller.
- `setjmp`'s `jmp_buf` has 28 words (the return address's bank is kept too).

```asm
; add3.s - unsigned add3(unsigned a, unsigned b, unsigned c), for both code models
        .p816
        .a16
        .i16
        .include "model.inc"
        .export _add3

        .segment "CODE"
_add3:  lda     ARGS,s
        clc
        adc     ARGS+2,s
        clc
        adc     ARGS+4,s
        RET
```

### Inline assembly (cc816)

An `asm` statement puts ca65 text into the compiler's output as it is. `asm`, `__asm__`
and `__asm` are the same; `volatile`, `inline` and `goto` after them are read and
ignored. The text is a string; several lines are joined with `\n` (adjacent strings are
one string, as always in C):

```c
asm("\tsei");                                /* one instruction */
asm volatile("\tlda #1\n"
             "\tsta _flag");                 /* two lines */
```

**Where it can be.** In a function, as a statement. At file scope, between functions: it
goes out in that place, between the functions around it, so a `.macro` defined there can
be used by the asm statements of the functions after it; the code segment and 16-bit
registers are put back after it. A function whose body is only asm statements can be
`__attribute__((naked))`: it gets no prologue and no epilogue, its label is the
function's name, it reads its arguments at `3,s` and after (as a `.s` function does) and
ends with its own `rts`. A `.s` file is the other way to write a whole function.

**Registers at the start of an asm statement in a function, and at its end.**

- A, X and Y are 16-bit (M = X = 0) and must be 16-bit again at the end. Their contents
  at the start are unknown, and the compiler assumes nothing about them afterwards; the
  flags are free too. The file is assembled with `.smart +`, so ca65 follows `rep` and
  `sep` itself; the compiler puts `.a16` and `.i16` after the text.
- `__rg+0` to `__rg+47`, `__h0` to `__h3` and `__rv` are scratch: use them freely.
- `__rg+48` to `__rg+95` must be kept, except the registers of the variables the text
  names (below), which it may read and change.
- Never change `__sp`, `__cbank`, D (0) or DBR (the code bank). S must be the same at the
  end (push and pull in pairs).
- The statement may call C functions (`jsr _name`, the arguments pushed as above and
  removed after). The compiler keeps no value in a scratch register across an asm
  statement, as across a call.

**Names.** A global variable or function is reached by its assembler name: the C name
with an underscore (`counter` is `_counter`); C's globals are in the code bank, so
absolute addressing (DBR) reaches them. `%[name]` in the text is replaced by:

| name is | `%[name]` becomes |
| --- | --- |
| a local variable or a parameter (not an array, a structure, `volatile`, or one whose address is taken) | its direct-page register, `__rg+N`. A variable named so lives in a callee-saved register for the whole function (so the scratch ones stay free). A `long`, `long long` or `__far` pointer is several words: `%[x]` is the low one, `%[x]+2` the next |
| a global, a `static` variable (also a local one), a function | its assembler name (`_counter`, `_main__total_3`) |
| an enumerator | its value, in decimal: `#%[MAX]` |

The text reads the variable's value at its start and may change it: the C code after it
sees the new value (a `char` variable is cut back to 8 bits). An array, a structure, a
`volatile` local or a local whose address is taken lives on the software stack, which
one operand cannot reach: `%[buf]` is an error that says so; take its address in a
pointer variable first (`p = buf;`) and use `(%[p]),y`. GNU's operand lists (`asm("..." :
"=r"(x) : "r"(y))`) are not supported (an error).

**Labels.** Each asm statement in a function gets a label of its own before it, so ca65's
cheap local labels (`@loop`) are local to the statement; `:` and `:+`/`:-` work too.

**In the large code model** (`hcc --code large`) a function with an asm statement, and a
naked function, stays in the main bank (its assembly may name main-bank addresses and
banks as it likes). Its calls follow the large model: `jsl _name` to call a C function,
a naked function's arguments from `4,s` and its own `rtl`. `%[name]` of a function is its
code (for `jsl %[f]`); its 16-bit address is `__T` and the name (`__T%[f]`). `#ifdef
__CC816_LARGE__` chooses the text for each model (`tests/lang/asm.c` does).

A fill loop with 8-bit stores, the length and the pointer from C:

```c
#include <string.h>

/* fill n bytes at p with v: 8-bit stores, Y the index */
static void fill(unsigned char *p, unsigned n, unsigned char v)
{
    asm volatile("\tldy #0\n"
                 "\tsep #$20\n"
                 "\tlda %[v]\n"
                 "@l:\tcpy %[n]\n"
                 "\tbcs @d\n"
                 "\tsta (%[p]),y\n"
                 "\tiny\n"
                 "\tbra @l\n"
                 "@d:\trep #$20");
}
```

cc816 writes for it (`hcc -S`):

```asm
_fill:	pei	(__rg+48)		; the three callee-saved registers it uses
	pei	(__rg+50)
	pei	(__rg+52)
	lda	9,s			; p, n and v into them
	sta	__rg+50
	lda	11,s
	sta	__rg+52
	lda	13,s
	and	#$00FF
	sta	__rg+48
Lfill_asm1:
	ldy #0
	sep #$20
	lda __rg+48
@l:	cpy __rg+52
	bcs @d
	sta (__rg+50),y
	iny
	bra @l
@d:	rep #$20
	.a16
	.i16
	...				; the registers put back, rts
```

`tests/lang/asm.c` (in `make -C sdk/c/cc816 check`) has this loop, a sum through a
`__far` pointer (`[%[fp]],y`), a `long` changed word by word, a C function called from
assembly (`pei (%[x])`, `jsr _twice`, `ply`), a `.macro` from a file-scope asm statement
and a naked function.

### vbcc

vbcc's 65816 calling convention, the same in both models:

- Functions are called with **JSL** and return with **RTL**. On entry and exit A, X and Y
  are **16-bit** (M = X = 0), D = 0, and DBR is the data bank (the code bank in the large
  model, 0 in the tiny model): keep D and DBR.
- The **first argument** is in **A** (8- and 16-bit values; a `char` in the low byte) or in
  **A/X** (32-bit values: `long`, large-model pointers, `float`; A the low word, X the high
  word). A structure as first argument goes on the stack.
- The **other arguments** are on the stack, pushed last first, so at entry the second
  argument is at `4,s` (above the 3-byte return address), the next after it. Each takes
  2 bytes (also a `char`) or 4 (32-bit values, large-model pointers). The caller removes
  them. A function with `...` gets all its variable arguments on the stack (a prototype
  must be in scope).
- The **result** is in A (16-bit and smaller, tiny-model pointers) or A/X (32-bit). Larger
  results (structures) are written through a hidden pointer.
- **Registers**: vbcc's registers r0-r31 are direct-page words $00-$3F, btmp0-btmp3 32-bit
  at $40-$4F. A function may change A, X, Y, r0-r15, r28-r31 and btmp0-btmp3; it must keep
  r16-r27 (save them with `pei (r16)` ... and restore). $50-$EF of the direct page is free
  for assembly; $F0-$FF belongs to the float library when it is linked.
- **Names**: a C name gets an underscore: `int add(int, int)` is `_add` in assembly.

The assembler is **vasm** (`vasm6502_oldstyle -816`, the syntax vbcc writes): `lda #<sym`
the low 16 bits of an address, `#^sym` its bank, `>sym` a 24-bit (long) address, `!sym` a
16-bit absolute address, `a16`/`a8`/`x16`/`x8` tell vasm the register widths. Give a
function its own section, so the linker can drop it when it is not used.

**The `zpage` pitfall.** vasm addresses an external symbol as absolute unless it is told
the symbol is on the direct page. `lda r0` without `zpage r0` assembles to `lda $0000`
through DBR (the code bank in the large model): wrong memory, no error. Declare vbcc's
registers you use:

```asm
; add3.s - unsigned add3(unsigned a, unsigned b, unsigned c): a in A, b at 4,s, c at 6,s
	zpage	r0			; vbcc's register r0 is on the direct page
	section	"DONTMERGE_text.far.add3","acrx"
	global	_add3
	a16
	x16
_add3:	sta	r0
	lda	4,s
	clc
	adc	r0
	clc
	adc	6,s
	rtl
```

Build it with the C files: `hcc --cc vbcc -o PROG.PRG main.c add3.s`. In C: `unsigned
add3(unsigned a, unsigned b, unsigned c);`. A 32-bit far address in data is `dd sym`
(vbcc writes pointers so); hcc relocates every bank byte (see "Program files" below). Assembly libraries written for ca65 (ulib, the controls library) are
another matter: they are called with JSR and use the direct page from $50. With vbcc the
controls library comes in as a block made by ld65 with JSL->JSR shims ([apps.md](apps.md),
"How the library gets into a program"); a `hui.h` program's own assembly must leave
$50-$EF alone.

## The C library on Horizon

Both compilers give the same C library behaviour: the libc test (`tests/libc`, 86 checks:
formats, strings, sorting, the heap, files, folders, time, far memory, errno, argv, the
keyboard, atexit) passes unchanged with cc816 and with both of vbcc's models.

**cc816** has a C library of its own (`sdk/c/lib/cc816`, in C, with the memory and string
routines and the arithmetic in assembly, `sdk/c/rt/cc816`) plus the SDK's shared files
(`sdk/c/lib`: argv, the console's line input, folders, errno's codes, time, the stack
checks). It is built split, one function a module, so a program links only what it uses.
Where it differs from the table below:

| | cc816 |
| --- | --- |
| `printf` family | `%d %i %u %x %X %o %c %s %p %n %%`, the sizes `hh h l` (and `z t`), widths, precision, `-+ 0#`, `*`; `%f %F %e %E %g %G %a %A` (also with `l`, `L`) in programs that use floating point ("Floating point", below); `%lld %lli %llu %llo %llx %llX` (and `j`: `intmax_t` is `long long`; `inttypes.h`'s `PRId64` ...) in programs that use `long long` ("long long (cc816)") |
| `scanf` family | `%d %i %u %o %x %c %s %[...] %p %n`, `*`, widths, the sizes `hh h l`; `%f %e %g %a` (`float *`; with `l` or `L` `double *`, `long double *`: the same 32 bits) in programs that use floating point; `%lld %lli %llu %llo %llx` (and `j`, `SCNd64` ...) in programs that use `long long` |
| `fgetpos`, `fsetpos` | 32-bit positions |
| `malloc` | first fit over the heap; NULL when it is full (the libc test: 25 blocks of 1 KB) |
| `clock()` | CLOCKS_PER_SEC 50, as vbcc's |
| `strtod`, `strtof`, `strtold`, `atof` | exact (rounded to nearest, ties to even, from any number of digits), hexadecimal (`0x1.8p3`), `inf`, `infinity`, `nan`, `nan(...)`; ERANGE on overflow and when a nonzero number becomes 0 |
| `math.h` | the list under "Floating point", below |
| `strtoll`, `strtoull`, `atoll`, `llabs`, `lldiv` | yes (`inttypes.h`: `strtoimax`, `strtoumax`, `imaxabs`, `imaxdiv` are the same) |
| `setjmp`, `longjmp` | yes ("setjmp and longjmp (cc816)", below) |
| `assert` | prints the expression, the file and the line on stderr, then exit code 3 |

**vbcc**: its C library (binary only, its 65816 "simulator" target) does the formatting,
strings, sorting, memory and buffering; the SDK replaces what reaches the machine and what
does not work in it:

| | Status |
| --- | --- |
| `main(int argc, char **argv)` / `main(void)` | the argument string split at spaces; `"quoted words"` stay whole (a quote anywhere starts or ends quoting: `a"b c"d` is `ab cd`); `argv[0]` is the program's name as the menu bar shows it ("Greet"); at most 32 arguments. The return value is the exit code |
| `exit`, `atexit`, `_Exit` | atexit functions newest first, then every open FILE is flushed and closed. `hz_exit()` ends at once without flushing |
| `printf` family | `%d %i %u %x %X %o %c %s %p %%`, `l` and `h` sizes, widths, precision, `-+ 0#`, `*`; `%f %e %g` with the float library. Not: `%lld`, `%zu`, `%a`, `%n` in printf |
| `scanf` family | `%d %u %x %s %c %[...]`, `%f` with the float library; `scanf` reads the keyboard (see stdin) |
| stdout, stderr | the console (the screen and the log; a terminal window when started there), line-buffered: a line is sent at `\n`, before reading stdin and at exit |
| stdin | the keyboard: a line typed with echo, Backspace, Left / Right; `fgets(buf, n, stdin)`, `getchar`, `scanf`. Ctrl-C or ctrl-D on an empty line: end of input (EOF) |
| `fopen` | modes `r`, `w`, `a`, `r+`, `w+`, `a+` (`b` is ignored, no line-end conversion; `x` fails if the file exists). **4 file handles for the whole system**: when none is left, NULL and `errno == ENFILE`. A missing file or folder: `ENOENT` |
| `fread fwrite fgets fputs fgetc fputc getc putc ungetc fprintf fscanf fflush fclose feof ferror clearerr` | yes, buffered (1 KB a file; 512 bytes in the tiny model) |
| `fseek ftell rewind` | yes, any position (32 bits); `SEEK_END` from the size at open plus what was written. `fgetpos`/`fsetpos` use vbcc's 16-bit `fpos_t`: files below 32 KB only |
| `remove`, `rename` | yes (rename also moves between folders on the card) |
| `freopen` | files only (not stdin, stdout, stderr) |
| `tmpfile`, `tmpnam` | not supported (NULL) |
| `opendir readdir rewinddir closedir` (`dirent.h`) | yes: `d_name`, `d_size`, `d_attr` (`HZ_ATTR_DIR`); no file handle used |
| `errno`, `strerror`, `perror` | errno from Horizon's codes (`ENOENT` no such file or folder, `EACCES` denied, `EEXIST`, `ENFILE` no handle left, `ENOMEM`, `EINVAL`, `EBADF`, ...); `hz_strerror(code)` says a Horizon code in words |
| `malloc calloc realloc free` | vbcc's allocator over the heap (above); NULL when it is full (the libc test fills it: 26 blocks of 1 KB in the large model, 22 in the tiny one, with that program's code) |
| `string.h`, `ctype.h`, `qsort`, `bsearch`, `strtol`, `strtoul`, `atoi`, `atol`, `abs`, `div`, `rand` (RAND_MAX 32767) | yes |
| `time()` | seconds since 1970 from Horizon's clock (`time_get`: set by the Desktop or the shell from /SYSTEM/CLOCK or the PC; never set: it counts from 2000-01-01); `gmtime`, `localtime`, `mktime`, `strftime` (no time zones) |
| `clock()` | CLOCKS_PER_SEC is 50 (vbcc's header): 20 ms steps. Milliseconds: `hz_uptime()` |
| `setjmp`/`longjmp` | in the library, not tested |
| `system`, `getenv`, `signal`, `raise`, locales | not supported (they return failure) |
| Floating point | `+ - * /`, conversions, `printf("%f")`, `sscanf("%f")`, `atof`, `strtod`, and math.h (`sqrt sin cos exp log pow floor ...`) were checked (tests/float). Cost: about 4.7 KB for arithmetic and printf's `%f` (8,644 bytes for a small printf program, 13,336 with one float multiply); the float test with seven math.h functions is 24 KB. Slow: thousands of cycles an operation. hcc links the float library when the link needs it (or `--float`) |

### vbcc's library: the replaced parts

`lib/vbcc/stdio.c` replaces the console streams, `__read`/`__write`, `fopen`, `fclose`,
`freopen`, `fseek`, `ftell`, `remove`, `rename`, `sscanf`, `fscanf`, `scanf` and `strtod`;
`rt/crt0.s` replaces `__main` and `exit`; `lib/hzerr.c` `strerror` and `perror`. The
reasons: the simulator target has no files; its `ftell` keeps 16 bits; its `__main` gives
`main` no arguments and reads its constructor list wrongly; its `exit(n)` loses n; its exit
does not flush the console; its `strerror` returns a pointer with a wrong bank (a compiler
fault, below); its `sscanf`/`fscanf`/`scanf` are integer-only variants; the float
library's `strtod` reads nothing.

## Floating point (cc816)

**One format.** cc816's `float`, `double` and `long double` are all IEEE 754 single
precision: 32 bits, a 24-bit significand (about 7 decimal digits), from 1.2e-38 to 3.4e38,
and denormals down to 1.4e-45. `sizeof(double)` is 4. Compilers for small machines often
do this: a 64-bit `double` would take twice the memory and much more time.
The three types still have their names (`_Generic` tells them apart), but they hold the
same values. `float.h` says so: `DBL_DIG` is 6 and `DBL_EPSILON` is `FLT_EPSILON`
(1.19e-7). C written for a 64-bit `double` compiles and runs, with 7 digits instead of
16 ([porting.md](porting.md)).

**Arithmetic.** It follows IEEE 754 for single precision:

- `+ - * /` and the conversions to float are rounded once, to nearest, ties to even.
  `1.0f + 0x1p-24f` is 1 (a tie: to even).
- Gradual underflow: denormals come in and go out, rounded once. Overflow gives infinity.
- Compares are exact. A NaN is unordered: every compare with it is false but `!=`. In a
  condition (`if (x)`, `!x`, `&&`), a NaN is true and -0.0 is false.
- -0.0 is kept as IEEE says (`-0.0 == 0.0`, `1 / -0.0` is -infinity).
- A NaN operand gives that NaN back, made quiet (the first when both are). An invalid
  operation (0/0, inf - inf, 0 * inf, inf / inf, `sqrt(-1)`) gives the default NaN,
  $FFC00000 (the sign bit set, as on x86: printf shows `-nan`). `NAN` in math.h is the
  positive quiet NaN, $7FC00000.
- A conversion to an integer truncates toward zero. Out of range (C leaves it undefined):
  `long` gets -2147483648 for |x| >= 2^31 and for NaN; `unsigned long` gets 4294967295 for
  x >= 2^32 and NaN; `int`, `unsigned` and the char types take the low bits of the `long`
  conversion.
- No exception flags, no other rounding modes, no `fenv.h`.
- Constants: decimal and hexadecimal (`0x1.8p-3`), with or without the suffixes `f`, `F`,
  `l`, `L`; each is rounded exactly once. The compiler folds constant expressions (`1.0 /
  3`, initialisers, `x * 2` becomes `x + x`) with the same rounding as the run time: the
  same bits.

**Where it is.** The arithmetic is in 65816 assembly, `sdk/c/rt/cc816/fp_*.s`: `__fadd`,
`__fsub`, `__fmul`, `__fdiv`, `__fcmp`, `__ltof`, `__ultof`, `__ftol`, `__ftoul` (operands in
`__h0`/`__h1`, as the 32-bit helpers; the contract is at the top of `fp_pack.s`). They take
1,792 bytes when all are linked. A float is passed and returned as a `long` is (4 bytes on
the stack; A/X). For assembly: the bits of a float are its IEEE pattern, low word first.
cc816 has two builtins to see them without a union: `__builtin_fbits(x)` (the 32 bits as
an `unsigned long`) and `__builtin_bitsf(u)` (back).

**Only for programs that use it.** The arithmetic helpers are linked as any helper is:
when the code calls them. printf's float conversions (`lib/cc816/fmtfp.c`, 3,677 bytes)
and scanf's (`scanfp.c`, 1,699 bytes, with `strtod`, 4,848 bytes) are linked in two cases.
A file that uses floating point (it defines a float object, has a float constant, converts
to or from a float, or calls a function with a float argument or result; a prototype
alone, as in `stdlib.h`, does not count) and that calls a printf function (`printf`,
`sprintf`, `vsnprintf`, ...) or gives a float to any variadic function (a wrapper of
printf) links `rt/cc816/fp_hookp.s`, whose constructor gives printf its float
conversions. The same with a scanf function, or a float pointer given to a variadic
function, links `fp_hooks.s` for scanf. So a program without floating point has no float
code in its printf, and a program that computes with floats but prints none has no float
printf (`tests/run.py`'s fpu test checks both). The rule misses only odd code: a printf
whose float argument was never a float in any file (`printf("%f", some_long)`).

**math.h.** Every name has its plain form (`sin`); the `f` and `l` forms (`sinf`, `sinl`)
are macros for it. No function sets errno: a domain error gives NaN, an overflow
`HUGE_VAL` (infinity); `math_errhandling` is 0. Accuracy, measured against glibc on a
million arguments a function (`tests/fpu/mathhost.sh`; "ulp" is a unit in the last place):

| Functions | Accuracy | Bytes linked (about, with what they use) |
| --- | --- | --- |
| `sqrt`, `fabs`, `floor`, `ceil`, `trunc`, `round`, `rint`, `nearbyint`, `lround`, `lrint`, `fmod`, `remainder`, `modf`, `frexp`, `ldexp`, `scalbn`, `ilogb`, `logb`, `copysign`, `nextafter`, `fmin`, `fmax`, `fdim`, `fpclassify`, `signbit`, `isnan`, `isinf`, `isfinite`, `isnormal` | exact (correctly rounded) | `sqrt` 560, `floor` 280, `fmod` 1,100 |
| `sin`, `cos`, `tan` (any argument: 1e30 too, reduced exactly), `atan`, `atan2`, `exp`, `exp2`, `log`, `pow`, `cbrt` | within 1 ulp | `sin` and `cos` 4,300 together, `tan` 1,300 more, `atan2` 1,900, `exp` 1,000, `log` 1,300, `pow` 4,800 |
| `asin`, `acos`, `log10`, `log2`, `log1p`, `hypot`, `cosh` | within 2 ulp | |
| `expm1`, `sinh`, `tanh` | within 3 ulp | |
| `fma` | x * y rounded, then + z (not fused) | |

Not there: `lgamma`, `tgamma`, `erf`, `erfc`, the Bessel functions, `nan()`, `fenv.h`.
The algorithms are fdlibm's (Sun Microsystems; its notice is in
`sdk/c/lib/cc816/mathint.h`) in their single-precision form, with two changes to `pow`
(`math_pow.c`, "Compiler notes"); the reduction of large trigonometric arguments is
cc816's own.

**printf, scanf, strtod.** `%f %F %e %E %g %G %a %A` print a float's exact decimal value,
rounded to the precision with ties to even, as glibc does: `printf("%.1f", 0.25)` gives
`0.2`, and `printf("%.20f", 0.1f)` gives `0.10000000149011611938`. The flags, the width and
the precision work as for integers; `inf`, `nan` (`INF`, `NAN`), with a sign when the sign
bit is set. scanf's `%f` (and `%e %g %a`, with `l` or `L` for `double *` and `long double
*`) reads the longest beginning of a number, as C says (`1e+x` fails), and converts it with
`strtod`. `strtod`, `strtof`, `strtold` and `atof` round exactly (any number of digits;
hexadecimal, `inf`, `infinity`, `nan`, `nan(n)`), and set ERANGE on overflow and when a
nonzero number becomes 0.

**Speed.** In microseconds, one operation on volatile operands, the loop taken out (the
emulator, whose timings are the board's within about 5 %):

| `+` | `-` | `*` | `/` | `<` | `(float)long` | `(float)int` | `(long)float` | `sqrt` | `sin` | `exp` | `log` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 77 | 87 | 207 | 282 | 17 | 47 | 62 | 37 | 587 | 4,147 | 3,560 | 3,402 |

That is about 250 to 4,000 cycles of the 14.3 MHz clock for one arithmetic operation:
keep floating point out of anything that runs every frame (`hgame.h`'s fixed point is much
faster). The benchmark against vbcc is under
"Speed".

**How it is tested.** `tests/fpu` (in `make -C sdk/c test`), 47,159 cases, bit for bit:
28,450 operations (+ - * / compares conversions: specials against specials, ties,
denormal and overflow results, random patterns) whose expected bits are also checked
against the host's SSE hardware; 3,000 printf and strtod results against glibc; 15,709
math.h results against the same C built for the host. `tests/float/float.c` (both compilers) and `ieee.c` (the edges,
readable). The compiler's random programs (`make -C sdk/c/cc816 check`) include float
programs checked bit for bit against gcc.

## long long (cc816)

`long long` and `unsigned long long` are 64 bits (`int64_t`, `uint64_t`, `intmax_t`,
`uintmax_t`; `LLONG_MIN`, `LLONG_MAX`, `ULLONG_MAX` in `limits.h`, `INT64_MAX`,
`INT64_C(...)` in `stdint.h`, `PRId64` and `SCNd64` in `inttypes.h`). Every operator
works on them, and every conversion to and from the other types, `float` and `double`
too. Constants: `LL`, `ULL` (also `ll`, `ull`, `LLU`), and a constant too big for
`long` is a `long long` by itself, as C says. The compiler folds constant expressions
with them (`sizeof`, initialisers, `case`). They can be globals with initialisers,
structure members, array elements, arguments and results, variadic arguments
(`va_arg(ap, long long)`), and a `switch` value. A bit-field cannot be `long long`.

**Where it is.** `+ - & | ^ ~`, unary `-`, the compares, `++`/`--` and shifts by a
multiple of 16 or by 1 to 3 are inline (four 16-bit steps). Multiply, divide, remainder
and other shifts call helpers in 65816 assembly (`sdk/c/rt/cc816/rt_mul64.s`,
`rt_div64.s`, `rt_shift64.s`: the operands in `__h0`..`__h3`, the contract at the top of
`rt_shift64.s`). The conversions to and from `float` are C (`sdk/c/lib/cc816/llconv.c`),
rounded as the 32-bit ones are (to nearest, ties to even; toward zero to an integer).
`(long long)` of a float out of range gives `LLONG_MIN` (as x86 does), `(unsigned long
long)` gives `ULLONG_MAX` for 2^64 and above and for NaN. A `long long` argument takes 8
bytes on the stack, a result comes back in `__h0`..`__h1` ("Calling convention").

**Only for programs that use it.** The helpers are linked when the code calls them.
printf's and scanf's `%lld` family (`lib/cc816/fmtll.c`, `scanll.c`) is linked as the
float conversions are: by a file that uses `long long` and calls a printf (or a scanf)
function, or gives a `long long` to a variadic function. A program without `long long`
links none of it (`tests/run.py`'s `ll` test checks it); its printf is 106 bytes bigger
than before `long long` came (the test for `ll` and the call of the hook), scanf 137.

**Speed.** In microseconds, one operation on volatile operands, the loop taken out
(`tests/ll/llbench.c`, emulated):

| `+` | `-` | `<` | `*` | `/` | `/ 10` | `%` | `<< n` | `(float)ll` | `(long long)f` | `sprintf("%lld")` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 16 | 15 | 21 | 376 | 1,260 | 196 | 1,265 | 85 | 210 | 51 | 2,985 |

The division takes the 32-bit helper when both operands fit 32 bits and a quicker path
when the divisor is below 65,536; the times above are a 57-bit value by a 34-bit one, the
slow case (64 rounds). As with `long`, keep `long long` out of inner loops.

**How it is tested.** `tests/lang/longlong.c` (every operator, conversion and library
function, against values from gcc), the random programs (`--features llong`, in every
seed: 64-bit expressions mixed with every other width, checked against gcc), and the
c-testsuite's ten `long long` programs.

## setjmp and longjmp (cc816)

`setjmp.h` has `jmp_buf`, `setjmp`, `longjmp` (and `sigsetjmp`, `siglongjmp`, `_setjmp`,
`_longjmp` as the same). `setjmp` returns 0, then the value `longjmp` gives (1 if that
is 0). A `jmp_buf` (54 bytes) keeps the hardware stack pointer, the return address, the
software stack pointer and the 48 bytes of callee-saved registers; `longjmp` puts them
back (`sdk/c/rt/cc816/setjmp.s`). It may jump out of any depth of calls, also out of a
library function's callback (a `qsort` comparison); both stacks are as they were at the
`setjmp`. A `setjmp` and `longjmp` pair takes about 86 microseconds.

As C says, after `longjmp` a local variable of the function that called `setjmp` that is
not `volatile` and was changed after the `setjmp` has an unknown value. Declare such a
variable `volatile`: it then lives in memory and keeps its last value. A variable not
changed after the `setjmp` keeps its value: the compiler knows `setjmp` by its name (also
`_setjmp` and `sigsetjmp`) and gives every value live across it a place of its own for the
whole function. Call `setjmp` directly, not through a function pointer. `longjmp` into a
function that has returned is undefined, as in any C. `tests/lang/setjmp.c` checks deep
jumps, a jump out of `qsort`, 2,000 jumps in a loop (no stack lost), `long`, `long long`
and `float` values and volatile locals.

## Syscalls from C

`horizon.h` includes `hzsys.h`, generated by `tools/gensys.py` from horizon.inc, ABI.md
and `tools/syscalls.tab`: every syscall of ABI.md is a function `hz_<name>` with a real
prototype and a comment (111 syscalls, 113 functions: `hz_spr_move_many` and
`hz_task_name_get` are other uses of `spr_move` and `task_name`). `make -C sdk/c check`
fails when the header and horizon.inc or ABI.md disagree (number of syscalls, numbers,
names).

```c
hz_io io;
int h = hz_open("/DATA.BIN", HZ_O_READ);       /* -> handle, or -1 */
if (h < 0) {
    printf("open: %s\n", hz_strerror(hz_errno));
    return 1;
}
io.handle = h;
HZ_U24(io.buf, buffer);                        /* a 3-byte pointer in the block */
io.len = sizeof(buffer);
n = hz_read(&io);
hz_close(h);
```

- **Results**: as the comment of each function says: `ok` functions return 0 or -1;
  others return A (a handle, a window, a count) or -1, `unsigned` ones $FFFF on an error,
  `long` ones A | X << 16 (`hz_uptime`, `hz_seek`, `hz_stat`, `hz_time_get`).
- **hz_errno**: every function sets it: 0 when the call worked, else Horizon's error code.
  Test it where -1 or $FFFF is also a valid answer (`hz_input_poll`, `hz_win_popup`).
- **hz_x, hz_y**: the X and Y registers after the calls that return more than one value
  (`hz_con_size` rows, `hz_input_read`'s position, `hz_mem_info` total, `hz_time_get`'s
  clock state, `hz_open`'s HTTP status, `hz_task_single`'s id).
- **Blocks**: `hz_io`, `hz_winopen`, `hz_windraw`, `hz_event`, `hz_statblk` and
  `hz_fileinfo`, `hz_readdirblk` and `hz_dirent`, `hz_renameblk`, `hz_spawnblk`,
  `hz_taskinfo`, `hz_msg`, `hz_clipblk`, `hz_rect`, `hz_mouse`, `hz_popup`, `hz_sample`,
  `hz_sprite`, `hz_sprmove`, `hz_fsenter`, `hz_fsscroll`, `hz_raster`, `hz_drawrec`,
  `hz_sheetnew`, `hz_sheetrec`, `hz_timermsg`. Blocks may be globals or locals.
- **Constants**: horizon.inc's names (`WD_FILL`, `WE_CLOSE`, `C_RED`, `SPR_EN`, ...), except
  the error codes and the open modes, which get `HZ_` (`HZ_EINVAL`, `HZ_EIO`,
  `HZ_O_CREATE`): their plain names belong to errno.h. Card errors: `HZ_ENOFILE`,
  `HZ_ENOPATH`, `HZ_EDENIED`, `HZ_EEXIST`, `HZ_ENFILE`.
- **Helpers**: `hz_spawn_path(path, args, prio)`, `hz_stat_path(path, &info)`,
  `hz_getline(buf, size)` (a line with editing), `hz_key_ascii(usage, mods)` (a key event
  to ASCII, KEY_* for arrows).
- **A syscall without a wrapper** (a newer kernel's): `hz_syscall(n, a, x, y)` returns A and
  sets hz_errno, hz_x, hz_y. A pointer is two arguments: `HZ_OFF(p)` and `HZ_BANK(p)`. Or
  write the stub in assembly as the generated ones are (cc816: `build/lib/cc816/stubs/*.s`;
  vbcc: `build/lib/large/hzsys.s`):
  the arguments into A, X, Y, `cop #$NN`, `bcs` to an error path.

## The stacks

**cc816** has two. The **hardware stack** is the window's top part (about 32 KB): return
addresses, arguments and the values the register allocator spills. The **software stack**
is the top of the code bank (`--stack N` bytes, default 8,192): arrays, structures and
locals whose address is taken. Big local arrays and deep recursion with arrays use it up.

**vbcc** has one: the window's top part, about 32 KB in the large model, 3,968 bytes at
least in the tiny model (`hcc --stack N` gives it N bytes; the data then has less).
Locals, arguments and return addresses live there.

The startup fills each stack's lowest 256 bytes with a pattern (the **guard zone**); at
exit the program checks them and, if any of a zone was written, prints `stack overflow:
the guard zone at window address N (the stack's last 256 bytes) was written` (cc816's
software stack: `stack overflow: the software stack's guard zone at N ... was written`).
An overflow is only seen if something was written into those 256 bytes (a never-written
local array larger than that can jump over them), and only at exit (`hz_stack_check()`
checks any time; `hz_stack_free()` gives the bytes below the hardware stack pointer now,
cc816's `hz_sstack_free()` those of the software stack). With `hcc --debug` the startup
paints the stacks and the exit reports the most used: `stack: 109 of 32251 bytes used`
and, with cc816, `software stack: 660 of 7936 bytes used`. Neither compiler checks the
stack in every function.

## Program files

**cc816**: ld65 (cc65's linker, the one Horizon's own programs use) writes the o65 file
straight away, with the startup first at $0100 (`rt/cc816/hzprog.cfg`), and hcc then
drops the relocation entries that add nothing (`tools/o65strip.py`, the SDK's copy of
Horizon's: the loader always puts a program at $0100, so only the bank bytes need it;
it checks that the result loads the same at three banks). A hello world keeps 8
relocations.

**cc816, `--code large`** (`tools/hzlarge.py`): the objects' segments are read first
(`tools/ca65obj.py`: cc816 gives every function that can move a segment of its own, and
ld65's configuration must name every segment). A trial link with those segments in one
big pool gives the main bank's fixed part and the functions whose 16-bit address is used;
hcc places the functions (first fit: the main bank, then banks of 64 KB), writes a glue
module (the thunks, `__T_name = _name` for the functions in the main bank, the loader's
table: the number of banks, the stamp, the .PRX's name, the folders) and writes ld65's
configuration: the main bank as an o65 file, each other bank as a raw image. Then it
links **three times**, with bank k at the link-time banks k, k + $40 and $80 + 2(k - 1)
(in the third link at offset 1). In the main bank a byte that differs between the links
must name one bank in all three (the link's bank of k each time): it is a bank byte of
bank k (a JSL to a function there, a thunk's JML) and becomes a relocation of the .PRX.
The two bytes before such a bank byte may differ by one in the third link (a far
address's offset). Anything else stops the build: a value "bank + 1" is odd in the third
link, and a 16-bit address of a function in another bank written in the main bank (which
ld65's o65 output would cut to 16 bits without a word: `.addr _name` in a `.s` file) is
one more there, without a bank byte after it. The main bank's own bank bytes are o65 SEG
relocations, done by Horizon's loader as in any program. In the other banks the compiler
records the address of every bank byte it writes (segment XREL: each JSL's, JML's and
MVN's), and hcc reads their bank from the first link (0: the main bank); a byte that
differs between the links and was not recorded stops the build. The .PRG is the first
link's o65 file (o65strip, as above), the .PRX its bank images and the relocations. A
build's stamp is a hash of what was linked and where: the same build gives the same
files.

**vbcc**: vlink, vbcc's linker, cannot write a relocatable program Horizon's loader takes
(its o65 output does not relocate bank bytes). So hcc links each program **three times**,
as raw images at banks $00, $5A and $A5, and `tools/mko65.py` compares them: a byte that
is the same in all three is copied; a byte that differs must be **exactly** the link's
bank in each ($00, $5A, $A5) and becomes a SEG relocation (the loader stores the code bank
there). Anything else stops the build with the byte's address. Offsets never need
relocating: the loader always puts the program at offset $0100 of its code bank.

**Where this could go wrong silently, and the guard.** The loader *replaces* a SEG byte
with the code bank. A byte holding "the bank + 1" (an address in the next bank, an offset
crossing $FFFF) differs by exactly the bank delta in every link, so a check of the
differences alone would accept it and the program would get the code bank there, one
bank short. mko65 therefore also requires the byte to be 0 in the bank-0 link (the value
is the bank itself, nothing added). Any other function of the bank (twice the bank, a
carry from the low word) gives other differences for $5A and $A5 and is rejected too.
Tiny-model data addresses (the window) are the same in every task and need nothing.

## Compiler notes

### cc816

cc816 is the SDK's own compiler. It reads C99 and most of C11, and some GNU C. This part
says what it takes, what it does not, how it reports problems, and which faults were
found and fixed.

#### What cc816 compiles

- C99: `//` comments, declarations anywhere, `for (int i = ...)`, `_Bool` and
  `<stdbool.h>`, `inline`, `restrict`, designated initialisers (`.a.b = 1`, `[3] = x`, the
  values after a designator go on from there), compound literals (also at file scope),
  flexible array members, variadic macros, `__func__`, `static` and qualifiers in array
  parameters (`int a[static 3]`), hexadecimal floating constants, `long` (32 bits),
  `long long` (64 bits: "long long (cc816)"), `setjmp`/`longjmp`.
- C11: `_Static_assert`, `_Generic`, `_Alignof` (always 1), anonymous structures and
  unions, `_Noreturn`, `u"..."`, `U"..."`, `u8"..."`.
- Old C: K&R function definitions (`int f(a, b) int a; char *b; { ... }`), functions
  without a prototype, tentative definitions (`int x; int x = 5;`).
- GNU C: statement expressions (`({ int t = f(); t * 2; })`), `typeof` and
  `__typeof__`, a cast as an lvalue, `case` and labels anywhere in a switch (Duff's
  device), case ranges (`case 'a' ... 'z':`: up to 32 values become cases, a wider range
  of a 16-bit switch is one test, a 32- or 64-bit switch takes at most 256), range
  designators (`[0 ... 9] = x`, also nested; a local's x is computed for each element),
  inline assembly ("Inline assembly (cc816)"), a static object or element initialised
  with a compound literal of its own type, `#pragma push_macro` / `pop_macro`,
  `__extension__`, `__inline__`, `__restrict`, `__const`, `__signed__`, `__volatile__`,
  `__alignof__`.
- GNU attributes (`__attribute__((...))`): `noreturn` (the end of the function after a
  call of it is not reached: no "control reaches the end" warning) and `naked` are used;
  `unused`, `used`, `packed` (structures are packed anyway), `aligned(1)`, `const`,
  `pure`, `format`, `nonnull`, `always_inline`, `noinline`, `deprecated`, `malloc`, `cold`,
  `hot`, `visibility` and the like are read and ignored; one cc816 cannot honour
  (`aligned(N)` with N above 1, `constructor`, `destructor`, `section`, `weak`, `alias`,
  `cleanup`, an unknown one) is ignored with a warning (`-Wattributes`).
- The preprocessor: `#if` with C's arithmetic (32 bits and more, `/` and `%` round toward
  zero), `defined`, `__has_include`, `#pragma once`, `#line`, `#error`, `#warning`,
  `__FILE__`, `__LINE__`, `__DATE__`, `__TIME__`, `#` and `##` (also with empty
  arguments), `__VA_ARGS__`.
- Wide characters: `wchar_t` is 16 bits (`unsigned int`), `L"..."` and `L'x'` are read
  from a UTF-8 source (a character of Unicode's first plane each), `\u` and `\U` escapes;
  `<wchar.h>` has the string and memory functions (`wcslen`, `wcscpy`, `wcscmp`, `wmemcpy`,
  ...), no locales and no wide input or output.
- Enumerations: an enumerator may be negative or above 32767; one above 32767 is an
  `unsigned int`, one above 65535 a `long` (C wants an `int`: gcc does the same).
- Bit-fields: `signed` and `unsigned`, of `char`, `int` or `long` (an `int` field is at
  most 16 bits, a `long` one 32), packed into units of their type's size; a field that
  does not fit in the unit starts a new one; `: 0` ends the unit.
- Structures and unions by value: passed, returned, assigned, nested.
- `offsetof` is a constant (array sizes, `case`, enumerators, static initialisers).

#### What cc816 does not support

Each of these is an error that starts with "cc816 does not support". What to do instead:

| Not supported | Do this instead |
| --- | --- |
| a 64-bit `double` | none: `double` is the same 32-bit format as `float` ("Floating point") |
| variable-length arrays (`int a[n];`) | a constant size, or `malloc` |
| `__int128` (128-bit integers) | `long long` (64 bits), or a pair of them |
| a `long long` bit-field | a `long` or `unsigned long` one (up to 32 bits), or a whole `long long` |
| GNU asm operand lists (`asm("..." : "=r"(x) : "r"(y))`) | `%[name]` in the text ("Inline assembly (cc816)") |
| a case range of more than 256 values in a `long` or `long long` switch | an `if` on the range |
| `_Complex` | a structure of two `float`s |
| an `int` bit-field wider than 16 bits | declare it `long` or `unsigned long` (up to 32 bits) |
| labels as values (`&&label`, `goto *p`) | a `switch` on a state number |
| nested functions (a function defined inside another) | a function at file scope, its data passed by pointer |
| GCC built-ins (`__builtin_popcount`, ...) | the C library, or a few lines of C |
| `#include_next` | `#include` with the path |
| an object of 65,536 bytes or more | a bank of its own: `hz_far_alloc` and a `__far` pointer |

#### Errors and warnings

Every message has the form gcc uses, with the file and line of the user's source (an
included header's own name and line; `#line` is followed):

```
game.c:42:13: error: 'score' undeclared (first use in this function)
game.c:57:9: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long [-Wformat]
```

The third number is the column. cc816 goes on after an error, so one run reports the
errors of the whole file (every statement is checked; a name that is not declared is
reported once a function; after a syntax error it stops, because the parser cannot go
on). It then stops without an output file and hcc exits with 1. Warnings do not stop the
build. A syntax error names what the parser expected where it can: `expected ';' before
'return'`, `unknown type name 'uint8_t'`.

An internal compiler error (a fault of cc816, not of the program) is one line:
`file.c: internal compiler error: ... (in function f) (please report; CC816_TRACE=1
shows where)`. `CC816_TRACE=1 hcc ...` (or `cc816.py --trace`) shows the Python
traceback.

The warnings, on by default unless marked -Wall. The name in brackets after each
message turns it off: `-Wno-format`.

| Name | What |
| --- | --- |
| `implicit-function-declaration` | a call of a function that is not declared (its result is taken as an `int`): include its header |
| `int-conversion` | a pointer from an integer or an integer from a pointer without a cast (0 is allowed: it is the null pointer); a pointer compared with an integer |
| `incompatible-pointer-types` | a pointer given to one of another type (`long *` from `int *`); pointers of different types compared |
| `discarded-qualifiers` | a `const char *` given to a `char *` |
| `far-pointer` | a `__far` pointer given to a near one: only the offset is kept |
| `type-limits` | a comparison whose result the type decides: `c == EOF` with a `char` (plain `char` is unsigned), `x > 40000` with an `int` |
| `return-type` | the end of a non-void function can be reached; `return;` in a non-void function; `return x;` in a void one |
| `overflow` | a constant that a conversion changes (`int x = 40000;`, `unsigned char c = 300;`); a constant expression that overflows its type (`320 * 200` in a 16-bit `int`); a `case` value the switch's type cannot hold |
| `shift-count-overflow` | a shift by the type's width or more, or by a negative count |
| `div-by-zero` | a division by a constant 0 |
| `format` | `printf`, `fprintf`, `sprintf`, `snprintf`, `scanf`, `fscanf`, `sscanf` with a constant format: each conversion against its argument's size and kind, too few or too many arguments, `scanf` without `&` |
| `excess-initializers` | more values than the array or structure has places; a string longer than its array |
| `cpp` | `#warning` |
| `extern-initializer` | `extern int x = 1;` (it defines x) |
| `multichar` | a character constant of three or more characters |
| `attributes` | a GNU attribute cc816 does not honour (`aligned(16)`, `constructor`, `section`, ...): ignored |
| `unused-variable` (-Wall) | a local or static variable that is never used |
| `unused-label` (-Wall) | a label no `goto` uses |
| `parentheses` (-Wall) | `if (a = b)`: an assignment as a condition |
| `tautological-compare` (-Wall) | a comparison always true at the type's edges: `u >= 0` with an unsigned `u`, `x <= 32767` with an `int` |
| `far-cast` (-Wall) | a cast of a `__far` pointer to a near one (only the offset is kept) |

The link's errors are said in C's words too: `undefined: fire_laser (used in
game.c)` for a function or a variable no file defines, and for a program too big for
its code bank, by how many bytes, with the sizes of the code and constants, the data and
the bss, which of them is the biggest, and what the software stack takes (it is part of
the same 64 KB, so a program that does not fit can also give the stack less: `--stack N`).

#### Options

hcc passes these to cc816 (`cc816.py`, the compiler alone, takes the same):

| Option | What |
| --- | --- |
| `-D NAME[=VALUE]`, `-U NAME` | define or undefine a macro, in the order given |
| `-I DIR` | look for `#include` files in DIR too |
| `-include FILE` | include FILE before the source |
| `-O0`, `-O1`, `-O2` | optimisation (`-O2` the default; `-O3` and `-Os` are `-O2`) |
| `-w` | no warnings |
| `-Wall` | the -Wall warnings too |
| `-Werror` | warnings are errors (the build stops) |
| `-Wno-NAME`, `-WNAME` | one warning off or on (the names above) |
| `-fsigned-char` | plain `char` is signed (-128 to 127): `CHAR_MIN` is -128, `__CHAR_UNSIGNED__` is not defined. The SDK's library is built with unsigned `char` and takes characters as `int`, so it works with both |
| `-E` (`cc816.py` only) | preprocess only |

hcc's own: `--code small|large` (the code model, "The two code models"; `HZ_CODE` in the
environment), with `--code large` also `--heap N` (the main bank's room kept for malloc),
`--prx-path DIRS` (where the program looks for its .PRX) and, for tests, `--main-room N`,
`--bank-room N` and `--spread N` (how much code the main bank and each other bank may
take; the functions in turn in N banks).

#### How it is tested

Its regression set (`make -C sdk/c/cc816 check`) has five parts. `tests/diag/` (101
files, no emulator; `make -C sdk/c/cc816 diag` runs it alone): each file says the errors
and warnings it must give, and nothing else may be said; a Python traceback fails the
test. Then 400 test programs, each with one random change (a token taken out, doubled
or replaced), must all give messages or compile, never an internal compiler error. `tests/regress/`: one small program
for each fault found, run in the emulator. `tests/lang/` (29 programs): one for each part
of C listed above, `long long`, `setjmp`, inline assembly and the GNU extensions among
them. Random programs checked against gcc's results
(`cc816/tests/fuzz/genfuzz.py`: arithmetic of every width, casts, compares, shifts,
division, arrays, structures and their copies, structures by value, bit-fields, function
pointers, variable arguments, far pointers, switches, loops that spill registers,
designated initialisers and compound literals, unions read through other members,
anonymous unions, `goto` state machines and Duff's device, enumerations, `_Bool`, the
comma operator, statement expressions, `long long` mixed with every other width (its
operators, conversions both ways and to float, globals, structures, arguments, results,
function pointers, variadic arguments, switches, sprintf `%lld %llu %llx %llo`); and floating-point programs, `--features
basic,float`: float and double arithmetic, compares, conversions both ways, `++`, compound
assignments, float arrays, structures, globals, pointers, parameters, results, variadic
doubles, sprintf `%f %e %g`, checked bit for bit against gcc's SSE single precision). And
the c-testsuite when `CTS=` points at a checkout.

#### Faults found and fixed

1. **Branch relaxation stopped after 20 branches**: a switch with about 30 cases made code
   ca65 refused (a branch out of range). Every branch out of reach is now relaxed, pass
   after pass (`regress/r001_relax.c`).
2. **A byte read through a far pointer was a 16-bit read**: at a bank's last byte
   (`b[65535u]`) it touched the next bank and Horizon ended the program. Far and volatile
   bytes are read with 8-bit loads (`r002_farbyte.c`).
3. **A far pointer plus an unsigned constant of 32,768 or more** (`p + 65535u`) was
   sign-extended: the pointer went backwards. Unsigned indexes are zero-extended (`r002`).
4. **A row of a 2-D array as a static initialiser** (`static int *p = a[2];`) was refused
   as "not a constant" (`r005_addrconst_array_row.c`).
5. **The value of an assignment to a bit-field** (`v = (s.f = x)`, and the compound forms)
   was the right-hand side, not the value stored: it is now cut to the field's width
   (sign-extended for a signed field) (`r006_bitfield_assign_value.c`).
6. **A structure copy through `__far` pointers** (`p[1] = p[0]`, a far structure passed
   or returned by value) moved the bytes inside the code bank: the block move now takes
   both pointers' banks (`r007_far_struct_copy.c`).
7. **A 16-bit value given to a 32-bit variable without a cast** (`long x = -1;`, `long y
   = i;`, `y = i;`) was not sign-extended: -1 became 65,535. The random programs always
   cast, so they never met it; adding floating point did (`float x = 3;` took the same
   path). It now widens by the value's type (`r008_widen_init.c`).
8. **`a - b` with b a NaN** gave the NaN with its sign flipped (the runtime negated b
   first); IEEE keeps it. Found by `tests/fpu` (`r009_float_sub_nan.c`).
9. **`int e = 97.0;`** gave 0: a mistake of the fix for bug 7 (the float's bits were cut to
   16 bits before the conversion). Found by the c-testsuite (00175.c;
   `r010_float_init_conv.c`).
10. **A far pointer plus an unsigned variable of 32,768 or more** (`p + u`, `p - u`) was
    sign-extended, as bug 3 was for constants (`r012_far_unsigned_index.c`).
11. **The branch of an `if` with a constant condition was left out even with a label or
    a `case` in it**: a `goto` into `if (0) { ... }` was refused, and a `case` inside an
    `if (0)` in a switch was lost (the switch took the default). Found by the c-testsuite
    (00213.c; `r013_dead_branch_labels.c`).
12. **A tentative definition's size**: `int a[];` then `int a[10];` kept one element, and
    a variable of a structure defined later in the file got 0 bytes; the zeroed variables
    after them were written over (`r014_tentative_size.c`).
13. **The preprocessor**: `#if` worked out `-7 / 2` and `-7 % 3` as Python does (-4 and
    2, not -3 and -1); `A ## B` with B empty pasted A to the next token; two tokens a macro
    put side by side were read as one (`a-X` with X defined as -1 became `a--1`); `#line`
    was ignored. Found by the c-testsuite (00202.c, 00152.c; `r015_pp_div_paste.c`).
14. **An enumerator of 32,768 or more was an `int`**: 40000 became -25536 when widened to
    a `long`, 100000 lost its high word (`r016_enum_wide.c`).
15. **`++` of a `_Bool` made it 2** (`r017_bool_incdec.c`).
16. **After a designator into a member** (`.b.x = 3, 4`) the next values went to the
    outer structure's next member, not on inside b; `[1] = 7, 8` of an array of
    structures was refused (`r018_designator_continue.c`).
17. **An initialiser given twice for one member**: a later brace list did not clear the
    rest of the member (`.a = {1, 2}, .a = {3}` left a[1] at 2), and a later 0 was
    skipped in a local (`.x = 5, .x = 0` left 5). Found by the random programs once they
    learnt designators (`r019_init_override.c`).
18. **A pointer variable holding a constant address** (`p = (char *)0x100; *p`): the
    optimiser put the constant into the access and the code generator stopped with an
    internal error. Found by compiling changed (broken) test programs, the robustness
    part of `tests/diag.py` (`r020_const_pointer.c`).

19. **A structure among a variadic function's arguments** was passed as its address, as
    for a parameter, so `va_arg(ap, struct s)` read the pointer and the bytes after it
    (and an odd size put every later argument out of step). It is now its bytes on the
    stack, padded to an even size. Found by the c-testsuite (00204.c, which had been
    listed as needing `long long`; `r021_va_struct.c`).
20. **`typeof`** (and `__typeof__`), which this page said cc816 had, was a syntax error:
    the vendored pycparser knows it only in its C23 mode; `typeof(int)` (a type, not an
    expression) failed too (`r022_typeof.c`).
21. **A union given two designators into its anonymous structure** (`{.b = 8, .a = 7}`)
    kept the first and warned of excess elements (`r023_union_designators.c`).
22. **A static object initialised with a compound literal of its own type** (`struct S g
    = (struct S){1, 2};`, an element of a static array given so) was refused as not a
    constant; GNU C takes the literal's list (`r024_static_compound_literal.c`). 21 and 22
    were found by the c-testsuite (00216.c) once range designators were there.

Bugs 4-6 were found by the random programs once they learnt structures, bit-fields and
far pointers; 10-16 by the programs of `tests/lang/` and the c-testsuite; 17 by the
random programs, 18 by the robustness check; 19-22 while `long long`, the GNU
extensions and their tests were added. The random programs with `long long` found no
fault (they all agreed with gcc from their first run).
`r003_nearfar.c` and `r004_coalesce32.c` guard two changes made on the way (near pointers
widened to far ones; 32-bit results sharing their operand's registers). While floating
point was added, its own tests found more, fixed before they reached a program. In
math.h: `pow` as ported from fdlibm's single-precision code lost up to 100 ulp near x = 1
(the 13-bit head of 2/(3 ln 2) made a product inexact; it has 12 bits now) and gave
infinity or 0 for every |y| > 2^27 when x was more than 8 ulp from 1 (now only when the
result overflows); `floor`, `ceil`, `trunc`, `round`, `rint` and `frexp` of infinity gave
NaN; `cbrt(FLT_MAX)` and `log1p(FLT_MAX)` overflowed inside; `cosh` of a tiny argument
and `sinh`'s overflow were wrong. In the code generator: the peephole pass dropped the
high word of a register whose address goes to a float helper, and address 0 (`__rg+0`)
was taken for "no destination".

Gaps of the front end closed at the same time (refused before, compiled now): statement
expressions, wide strings and characters, `offsetof` in constant expressions, a label
with the name of a typedef (c-testsuite 00129.c, a fix of the vendored pycparser),
`#pragma push_macro` / `pop_macro` (00206.c), `__has_include`, `-U`, `-include` and
`-fsigned-char`.

The c-testsuite (single-exec, 220 programs): 213 pass (201 before `long long`, case
ranges and range designators). Each of the other 7 is listed in
`cc816/tests/cts-known.txt` with its reason: 1 a variable-length array, 2 a 32-bit `int`,
3 a 64-bit `double` (one of them also a 32-bit `int`), 1 one of the `__LP64__` /
`__ILP32__` macros. 00040.c (8 queens by brute force) is right but slow: about 260
emulated seconds (1.5 million calls of its check function; 384 before `a < b & c < d`
in a condition was compiled as `&&`), so `tests/check.py` gives it 400 seconds in a
batch of its own. The random programs of seeds 1, 2 and 3 (1,200 programs, and 600
floating-point ones) all agree with gcc.

### vbcc

vbcc 65816 is a young back end. These faults were found while building the SDK; the SDK
works around each, and `tests/codegen` checks the cases (cc816 passes the same test):

1. **The global optimiser** (`-O2`, `-O3`) does not see that a function called with the
   address of a local writes it, and moves or drops reads of the local (seen: a loop
   calling `hz_task_info(i, &ti)` read `ti.id` once, before the first call). Its warning
   171 "var used before defined" marks the places. **hcc uses `-O1` by default** (local
   optimisations; on the benchmark it is faster on sieve, slower on sum16, the same on
   the rest: see "Speed"), and adds a note to a 171 warning at
   `-O2`/`-O3`. Use `-O2`/`-O3` only for files that do not pass locals by address.
2. **32-bit loads from a far table indexed by a variable** (`return table[i];` with
   `long` or large-model pointer elements) lose the high word. hcc repairs the pattern in
   the compiler's output (`hzc.fix_asm`). The C library's `strerror` has it (replaced).
3. **Saving X in Y** for such an access, the compiler forgets the constant it believed
   was in Y and a following `[rN],y` uses the wrong offset (a `long` compare of two array
   elements read another bank). hcc reloads the constant after the save (`hzc.fix_ysave`).
4. **The tiny model with a pointer in X** loads a 32-bit value through X as "high word,
   TAX, low word": hcc compiles the tiny model with `-nox` (no variable in X).
5. **A pointer member of a static structure, dereferenced at offset 0** (`s.p[0]`,
   `s.next->first`; in the tiny model every pointer member, in the large model `__near`
   ones) is loaded into X and then read at the *member's* offset: `ldx 4+_s` / `lda
   !4,x` where `!0,x` is meant (for any other offset vbcc adds it first and uses `!0,x`).
   hcc writes `!0,x` there (`hzc.fix_nearoff`).
6. **A `__near` pointer in initialised data** (large model: `dw label`) is a 16-bit
   field vlink fills with the whole address, which does not fit in the links at banks
   $5A and $A5 ("doesn't fit into relocation type R_ABS"). hcc writes `dw <label` (the
   offset, which is what is meant; `hzc.fix_neardw`). The controls library's structures
   (`hui.h`) have such pointers.

7. **Not repaired: a structure assigned between array elements** (`a[i] = b[j];`, or
   through a pointer taken as `&a[i]`), at `-O0` and `-O1`: the copy writes to a wrong
   address in a wrong bank and Horizon ends the program. Copy such structures with
   `memcpy`, or member by member; a copy through a pointer that is stepped (`*p++ = *q++`)
   works. `game/tests/vbcc_structcopy.c` reports whether the fault is still there.

The linker scripts (`rt/horizon.cmd`, `rt/horizon-tiny.cmd`) take sections by their
kind (`?????????_text.*`, `_rodata`, `_data`, `_bss`: vlink numbers vbcc's `DONTMERGE`
sections), not by any name containing "text": a static variable called `context` or
`ntext` went into the code (the tiny model then failed to link).

`hcc -v` shows the commands and how many places were repaired in each file.

## Speed

The 65C816 runs at 14.3 MHz; the memory stalls make CPU-bound code about half the ideal
speed (emu816 models them: its timings are the board's within about 5 %). The compiler
trials' benchmark (`tests/bench`, `make -C sdk/c test` runs it), in milliseconds:

| | sieve | sum16 | mul32 | fib22 | strs | structs |
| --- | --- | --- | --- | --- | --- | --- |
| cc816, -O2 (the default) | 809 | 296 | 1277 | 388 | 994 | 670 |
| cc816, -O1 | 809 | 476 | 1280 | 393 | 999 | 659 |
| cc816 `--code large`, -O2 | 808 | 300 | 1290 | 430 | 1000 | 678 |
| cc816 `--code large`, -O1 | 808 | 490 | 1287 | 417 | 996 | 674 |
| vbcc large, -O1 (its default) | 900 | 886 | 1305 | 635 | 1310 | 1397 |
| vbcc tiny, -O1 | 1640 | 556 | 1306 | 687 | 1077 | 1350 |
| vbcc large, -O3 | 1300 | 490 | 1298 | 633 | 1310 | 1348 |
| vbcc tiny, -O3 | 1579 | 500 | 1299 | 634 | 1064 | 1340 |

(The check values are the trials' six: 1899, 27824, 1071602483, 17711, 3160,
4275534039. vbcc's -O3 is not its default because of the optimiser fault above.)

What they measure: sieve (byte arrays, 16-bit indexes), sum16 (16-bit arrays), mul32
(32-bit multiply and divide), fib22 (calls), strs (pointers and bytes), structs (structure
fields, signed, shifts).

Floating point (`tests/bench/fbench.c`, `make -C sdk/c test` runs it as `fbench`), in
milliseconds, and the program's size on the card:

| | mandel | sincos | sqrt | expow | conv | program |
| --- | --- | --- | --- | --- | --- | --- |
| cc816, -O2 | 2,140 | 1,650 | 365 | 1,950 | 1,070 | 25,929 bytes |
| cc816 `--code large` | 2,140 | 1,640 | 368 | 1,939 | 1,070 | 27,799 bytes |
| vbcc large, -O1 | 1,880 | 780 | 1,707 | 690 | 1,049 | 15,138 bytes |
| vbcc tiny, -O1 | 1,908 | 780 | 1,710 | 680 | 1,037 | 13,249 bytes |

mandel is one 64-point row of the Mandelbrot set (+ - * and compares), sincos `sin` and
`cos` of 200 values, sqrt 500 square roots, expow `exp`, `log` and `pow` of 100 values,
conv 2,000 conversions and divisions. cc816 rounds every operation exactly (IEEE 754) and
its math.h is within an ulp or two of the exact result; vbcc uses its own format and its
own library (not measured here for accuracy). vbcc is quicker at multiplying (about 12 %
on mandel) and at `sin`, `exp`, `log` and `pow` (2 to 3 times); cc816 is much quicker at
`sqrt` (exact, bit by bit: 4.7 times); the two are alike on conversions and division. cc816's
float code is larger: about 1.8 KB of arithmetic, 3.7 KB for printf's `%f`, and its math
functions are longer (a call to a float helper is 12 to 27 bytes of code).

The runtimes: cc816's (`sdk/c/rt/cc816`) and vbcc's tuned one (`sdk/c/fastrt`, linked
into every vbcc program in place of its library's routines) against vbcc's library's own,
in milliseconds for the loop shown (loop overhead included; `tests/rt/rtbench.c`; vbcc's
large model):

| Operation | cc816 (rt/cc816) | vbcc (fastrt) |
| --- | --- | --- |
| 16-bit multiply, mixed values, 20,000 times | 625 | 695 |
| 16-bit multiply by 100, 20,000 times | 544 | 584 |
| 16-bit divide, mixed values, 20,000 times | 938 | 1,018 |
| 32-bit multiply, 10,000 times | 1,183 | 1,172 |
| 32-bit divide by 1000, 10,000 times | 664 | 586 |
| 32-bit modulo 7, 10,000 times | 707 | 614 |
| 32-bit divide by $12345, 10,000 times | 1,413 | 1,328 |
| memcpy of 1000 bytes, 200 times | 163 | 168 |
| memmove of 1000 bytes upwards, 200 times | 163 | 180 |
| memset of 1000 bytes, 200 times | 170 | 167 |
| strlen of 1000 bytes, 200 times | 148 | 164 |
| strcpy of 1000 bytes, 200 times | 320 | 298 |
| memcmp of 1000 bytes, 200 times | 199 | 177 |
| memcpy of 6 bytes, 2000 times | 26 | 50 |

(The 32-bit lines of this test read `volatile` operands: cc816 moves each through a
direct-page register before the helper's own words, about 60 cycles a call more than
vbcc, whose helpers take vbcc's registers directly. In real loops the operands are already
in registers: the benchmark's mul32 above is faster with cc816.)

Each routine is checked against host-made tables (3,000 cases per arithmetic operation,
2,000 per memory function, signed and unsigned, edge values: `tests/rt`, for cc816 and
both vbcc models). cc816's are fastrt's algorithms with its own calling contract, its
32-bit multiply's low product unrolled, and its divisions taking a shorter round when the
divisor is below $8000. Both compilers copy a structure (and vbcc a constant-size memcpy)
inline with MVN.

Advice, from these numbers and the generated code:

- Prefer **`unsigned int`** (16 bits) for counters, indexes and loop variables: the
  65816's own size. Signed division and right shifts of `int` need extra code.
- Avoid **`long`** in inner loops: every 32-bit operation is two 16-bit ones, and a
  multiply or divide is a call (a 32-bit multiply about 0.1 ms with its loop, table above).
- Avoid **float** in anything that runs every frame (both compilers: 20 to 300
  microseconds an operation, milliseconds for `sin` or `pow`); fixed point (`hgame.h`'s
  `hg_fix8`, `hg_fix16`) is much faster.
- `memcpy`, `memmove`, `memset` move blocks with MVN/MVP (about 7 cycles a byte, 1000
  bytes in under 1 ms); `hz_far_copy` too.
- cc816: `-O2` (the default) is the fast one; `-O1` drops the loop optimisations (sum16
  above). vbcc: `-O1` is its safe default; `-O3 -speed` changes little here and has the
  faults above.
