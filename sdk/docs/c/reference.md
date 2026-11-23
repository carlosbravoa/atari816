# C reference

The C SDK for Horizon: its compiler, how a C program is laid out in memory, its types,
far memory, the calling convention (for assembly), inline assembly, the C library on
Horizon, floating point, `long long`, `setjmp`, syscalls from C, the stacks, the
compiler's notes and speed. Getting started: [getting-started.md](getting-started.md);
window applications (the controls library, `hui.h`): [apps.md](apps.md); games:
[games.md](games.md); porting: [porting.md](porting.md).

| | |
| --- | --- |
| Compiler | **cc816**, the SDK's own (`sdk/c/cc816`, Python 3, writes ca65 assembly). It needs Python 3 and cc65's ca65, ld65 and ar65: nothing to download |
| Driver | `sdk/c/bin/hcc` (`hcc -h` lists the options) |
| Headers | `horizon.h` (syscalls, blocks, helpers), `hui.h` (the controls library: [apps.md](apps.md)), `hgame.h`, `conio.h`, `joystick.h` ([games.md](games.md)), `dirent.h`; the C library's in `sdk/c/cc816/include`: `stdio.h`, `stdlib.h`, `string.h`, `fcntl.h`, `unistd.h`, `math.h`, `float.h`, `ctype.h`, `time.h`, `errno.h`, `stdint.h`, `inttypes.h`, `stdarg.h`, `setjmp.h`, `limits.h`, ... |
| Library | `sdk/c/lib` (the C library, in C) and `sdk/c/rt` (the startup and the runtime, in assembly); hcc builds them for each code model into `sdk/c/build/lib/small/` and `sdk/c/build/lib/large/`, and for the far data model into `sdk/c/build/lib/large-far/` |
| Make | `sdk/c/c.mk` (a program's Makefile is three lines) |

cc816 has floating point (IEEE 754 single precision; `double` is the same 32-bit format),
`long long` (64 bits), `setjmp`/`longjmp` and inline assembly (below). It has no 64-bit
`double` and no variable-length arrays. A program with more code than one bank holds is
built with the large code model (`hcc --code large`, "The two code models", below).

## Memory

```
the small code model (the large one: "The two code models", below)

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

| | Size |
| --- | --- |
| Code + constants + data + bss | 65,264 bytes ($0100-$FFF0) less the software stack: 57,072 with the default 8,192 |
| Heap | from the end of bss to the software stack's guard zone (a small program: about 48,000 bytes) |
| Software stack | `--stack N` bytes (512-32,768, even; default 8,192): arrays, structures and locals whose address is taken |
| Hardware stack | about 32,000 bytes (from just below the argument string to $0100) |
| Direct page | $00-$77: 48 bytes of scratch registers, 48 callee-saved, the software stack pointer, the runtime helpers' words, the code bank's number |
| DBR (the data bank) | the code bank |

`hcc` checks the sizes after linking and says what does not fit, in bytes ("program too
big by N bytes: build with --code large" when the code is what does not fit). The
loader's own limits: the program's o65 is less than 64 KB, and code + data + bss fit in
$0100-$FFFF. (Before Horizon 0.28 the whole file had to be less than 64 KB. Since 0.28 a
file may be larger: the loader reads only the o65 at its start.) With `hcc --code large` the code may also fill other banks; the rest of this
picture stays as it is (the code bank is then called the main bank).

## The two code models

cc816 has two code models. Both have the same data: every data pointer is a 16-bit
offset in the main bank, and DBR is always the main bank. They differ in where the code
goes and in how functions are called.

| | small (the default) | large (`hcc --code large`) |
| --- | --- | --- |
| Code | in the code bank, with everything else | in the main bank while it has room, then in other banks of 64 KB (up to 64 of them) |
| Calls | JSR / RTS | JSL / RTL, wherever the function is |
| The first argument | at `3,s` | at `4,s` (the return address has 3 bytes) |
| A function pointer | 16 bits: the function | 16 bits: the function's entry in the main bank (the function itself, or a 4-byte thunk, a JML to it) |
| Files | NAME.PRG | NAME.PRG: one file. When code went to other banks, they follow the o65 in the same file (Horizon 0.28 and later) |
| Data, constants, bss, heap, software stack | the code bank | the main bank: the same |
| `__CC816_LARGE__` | not defined | defined (1) in C and in assembly (`ca65 -D`) |

`hcc --code large` (or `HZ_CODE=large` in the environment; `HZ_CODE := large` in a
Makefile made with c.mk) builds a program in the large model. Nothing in the C changes.
Every file of a program must be built for the same model, libraries included: hcc builds
the C library, the game library and the controls library for both, and refuses an object
made for the other model ("an object made for the small code model; this program is
linked for the large one").

### What goes where

**The main bank** (the .PRG, loaded by Horizon as any program) holds the startup, the
assembly (the C library's runtime: arithmetic, memory and string routines, floating point;
the syscall stubs; hgame's and the controls library's assembly; your `.s` files), the C
functions that have inline assembly or are `naked`, the constructors and destructors
(`_INIT_n_name`, `_EXIT_n_name`), the loader of the other banks (`xload.c`, with
`misc.c`: they run before the other banks are there), the thunks, the constants (string
literals, `const` tables, floating-point constants), the initialised data, the bss, the
heap and the software stack. These are limited to the main bank, as in the small model.
`__far` objects are not: they go to banks of their own ("Far objects", below).

**The other C functions can move**: the program's and the libraries' alike (the C
library's, hgame's, the controls library's C part). cc816 puts each one in a segment of
its own (in a file of more than 100 of them, runs of consecutive functions share one:
ca65 and ar65 take only so many segments a module), and hcc places them after it has
linked the rest:
first in the main bank, as long as it has room (it keeps `--heap N` bytes free for
`malloc`, 4096 by default), then in other banks, each function in the first bank with
room, in the order of the files and of the functions in them. A function must fit in one
bank (65,535 bytes). When everything fits in the main bank, nothing follows the o65 and
nothing is loaded at the start: the program runs on any Horizon, as in the small model.

`hcc --map` shows the result:

```
GAME.PRG: 210,710 bytes on the card, 415 relocations
  code bank: code+constants 43,957 + data 78 + bss 1,754 = 45,789 of 57,072; heap 11,283; software stack 8,192
  window:    stack about 32,000 (from $7F7F down to $0100); direct page 120 bytes
  code model large: 23,038 bytes of movable code in the main bank, 156,494 in 3 other bank(s) (65,475, 65,417, 25,602); 1403 thunks
  one file: the o65 45,036 bytes, then the other banks 165,674 bytes; 4543 bank bytes patched at the start
```

(a program of 1,600 functions, `sdk/c/tests/bigprog/genbig.py`: about 180 KB of code).
Two more lines come when they apply: `far data: N bytes of __far objects in K bank(s) of
their own`, and `the main bank without its movable code: N bytes (code that must stay,
constants, data, bss)`: what the main bank needs whatever hcc does with the code. For
Digger that is 33,488 bytes (8,241 of code, 7,764 of constants, 2,142 of data, 15,341 of
bss); before the libraries could move it was 53,946.

### Far objects

A table declared `__far` at file scope is a **far object**:

```c
__far const unsigned char level[8][2000] = { ... };     /* 16,000 bytes */
__far const struct enemy kinds[40] = { ... };
__far short work[4096];                                 /* writable too */
extern __far const unsigned char level[8][2000];        /* in another file */

const unsigned char __far *row = level[n];              /* its address is a far one */
x = kinds[k].speed;                                     /* read with long addressing */
```

In the large code model hcc puts every far object of the program in a bank of far data
(each object in one bank; as many banks as they need, after the code banks), which is in
the program file and loaded at the start with the code. Nothing of it is in the main bank.
In the small model a far object stays in the code bank; the same source builds in both.

Its elements are reached through far pointers: `level[n][i]` builds the far address and
reads through it, as `p[i]` with a `__far` pointer does (a little slower than a main-bank
array: a 32-bit address). A pointer to it is a far pointer (`&level[3][0]` is `const
unsigned char __far *`); giving it to a near pointer keeps the offset only (cc816 warns).
A far object may hold pointers (near ones, to main-bank data or functions, and far ones,
to other far objects). An object is at most 65,535 bytes, as any. In a library built
split (one module a function: the SDK's own libraries) far objects stay in the main bank.
Test: `sdk/c/cc816/tests/regress/r028_far_objects.c`.

| Limit | |
| --- | --- |
| Code | the main bank's room, plus 64 banks of 64 KB (about 4 MB); an 8 MB machine has about 80 free banks when nothing else runs |
| One function | 65,535 bytes |
| The main bank | startup + the libraries' assembly + `.s` files + functions with inline assembly + constructors + thunks (4 bytes for each function in another bank whose address is used) + constants + data + bss + 4 KB of heap (`--heap N`) + the software stack (`--stack N`) must fit in 65,264 bytes |
| Far data | `__far` objects: up to 64 banks together with the code banks |
| The .PRG file | its o65 part (the main bank and its relocations) below 64 KB: Horizon's loader reads only the first 65,535 bytes of a larger file. The whole file has no limit |
| Horizon | 0.28 or later when code went to other banks (it loads a file of 64 KB or more, and tells the program its own path) |

### How the program is loaded

A large program is one file, NAME.PRG. It starts with the main bank, an ordinary o65
file. The other code banks follow it in the same file. Copy the one file to the card, into
any folder.

Horizon loads NAME.PRG as it loads any program. Since Horizon 0.28 the loader takes a
file of 64 KB or more: it reads only the first 65,535 bytes, where the o65 must lie, and
never loads what follows the o65.

Before the constructors run, the startup (`sdk/c/lib/xload.c`):

1. asks Horizon for the path of its own file (`task_path`, Horizon 0.28) and opens it.
   This works however the program was started: from the shell by any path, from the
   Desktop's Programs menu, or from Files;
2. reads the file's last 8 bytes: where the other banks start, and `HZPX`;
3. checks the header there: the number of banks and the stamp of the build (hcc writes the
   same stamp into the main bank), so a file put together from two builds is refused;
4. takes a bank for each image (`hz_bank_alloc`) and reads the image into it;
5. patches the bank bytes: the bank of each JSL to a function in another bank (and of
   the MVN of a structure copy), in the main bank and in the others: the banks are known
   only now;
6. checks that the data ends just before the last 8 bytes, and closes the file. Then the
   constructors, `main` and the rest run as usual.

In the emulator a program of 45 KB with 165 KB of other banks starts in about 0.15 s (a
small program in 0.01 s). Horizon gives the banks back when the program ends, as all of a
program's banks.

On a Horizon before 0.28 a large program with other banks does not start: the file is
64 KB or more, so the loader refuses it ("not a Horizon program"). If the whole file is
below 64 KB, the old loader takes it, and the startup stops with "needs Horizon 0.28 or
later".

If something is wrong, the program prints one line on the console and ends with exit
code 1 before any of its own code runs; when the window system runs, the line is also
shown in a small window (a key or a click closes it):

| | |
| --- | --- |
| `GAME.PRG: the program file is cut short or damaged (its code banks): copy it again` | the file was cut (a copy that did not finish) or changed |
| `GAME.PRG: its code banks are of another build of the program: build it again` | the file was put together from two builds |
| `GAME.PRG: not enough memory: no free 64 KB bank for the program's code` | the machine has not enough free banks (close a program) |
| `GAME.PRG: needs Horizon 0.28 or later (a program with several code banks)` | an older Horizon (it has no `task_path`) |
| `GAME.PRG: cannot find its own file ...`, `cannot open its own file ...`, `cannot read the program file (a card error)` | the file was removed while the program started, too many open files, a card error |

### The file's layout

| | |
| --- | --- |
| the o65 | the main bank, as in any program; below 64 KB |
| Header, 12 bytes | `HZPX`, version 1, n (the number of banks), 0, 0, the stamp (u32) |
| n x u32 | each bank's image size |
| the images | bank 1, bank 2, ..., each from offset 0 of its bank |
| u16 | the number of relocation groups |
| the groups | each: u8 where (0 the main bank, k bank k), u8 to (the bank whose number is stored), u16 count, then count u16 offsets: the bytes that get that bank's number |
| the trailer, 8 bytes | u32 the offset of the header in the file (= the o65's length), then `HZPX` |

hcc makes it with ld65 alone (`sdk/c/tools/hzlarge.py`, "Program files" below). Before
the SDK of Horizon 0.28, the part after the o65 was a second file, NAME.PRX, which the
program looked for in a list of folders. hcc no longer writes it, and the programs no
longer read it: build such a program again.

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

## The far data model

`hcc --code large --data far` builds a program whose plain data pointers are **far** (32
bits: offset, bank, 0), as a DOS program of Watcom's or Microsoft's large model has them
(`wcc -ml`): its heap is in other banks, its string literals and `const` tables live in
banks of far data, and the C library takes and returns far pointers. It is there to port
DOS-era "large model" C without rewriting its declarations (the acceptance test:
`ports/xcom`, 49,000 lines of Watcom C). The model described above is called **near data**
from here on: it stays the default and does not change (a near-data program compiles to the
same bytes as before the far data model came).

### The option

| | near data (the default) | far data (`hcc --data far`) |
| --- | --- | --- |
| Needs | either code model | `--code large` (far data banks are loaded by the large model's loader; a program that needs far data is a big program: hcc refuses `--data far` alone) |
| `char *p` | 16 bits: an offset in the main bank | 32 bits: offset, bank, 0 |
| `char __near *p` | the same as `char *p` (`__near` is nothing) | 16 bits: an offset in the main bank |
| `char __far *p` | 32 bits | 32 bits (the default spelled out) |
| function pointers | 16 bits (the main-bank entry) | the same: 16 bits |
| `malloc` | the main bank's heap | far: the main bank's free room first, then banks of 64 KB |
| string literals, `const` objects | the main bank | banks of far data |
| other globals and statics | the main bank | the main bank (near: absolute addressing, as fast as near data) unless `__far` |
| `__CC816_FAR_DATA__` | not defined | defined (1) in C and in assembly (`ca65 -D`; `model.inc`: `FARDATA` 1, `PTRSZ` 4) |
| libraries | `build/lib/small`, `build/lib/large` | `build/lib/large-far` (the C library and hgame; the controls library is not built for it) |

`HZ_DATA=far` in the environment (`HZ_DATA := far` with c.mk) does the same as the option.
Every object of a program must be made for the same model: cc816 marks each object
(`__cc816_large` or `__cc816_largefar`), and the link of a near-data object into a far-data
program, or the other way round, is refused with "an object made for the large code
model; this program is linked for the large code model with far data (hcc --data far):
build every file with the same --code and --data (a library too)". A `.s` file carries no
mark: it must follow the model's convention (below).

### Pointers

A far pointer is 4 bytes: the offset (16 bits), the bank (8 bits) and a zero byte, the same
`__far` pointers have always had. Code reads through it with `[dp],y` (the pointer in a
direct-page register: the 65816's own long indirect addressing). The rules:

- **An object never crosses a bank** (a `malloc` block, a far object, a frame: none does),
  as a DOS object never crosses a 64 KB segment. An object is at most 65,535 bytes.
- **Arithmetic** (`p + i`, `p++`, `p - q`): `p + i` adds to the whole 24-bit address (a
  carry goes into the bank, as `__far` pointers always did). For every pointer that stays
  inside its object, and one past its end or one before its start (`p - 1` in a loop
  that walks down to the start), that is the same as DOS's offset-only arithmetic, and it
  keeps a pointer one past an object that ends at a bank's last byte greater than the
  object's start (DOS's would wrap to offset 0). An element `p[i]` (an access, not a
  pointer value) is reached as DOS reaches it: an unsigned `i` in Y (`[p],y`), a signed
  one added to the offset alone (the element is in `p`'s object, so in its bank: cheaper
  than widening `i` to 32 bits). `p - q` is the difference of the offsets (16 bits,
  `ptrdiff_t`). Not supported: arithmetic that relies on the offset wrapping inside its
  segment (DOS's `p + 0xFFFF` as `p - 1`).
- **Compares**: `==`, `!=`, `<` ... compare the whole 32 bits (the bank first). Pointers
  into one object compare as their offsets do.
- **NULL** is 0 (bank 0, offset 0: nothing of a program is there). A near pointer
  converts to a far one by itself: its bank is the main bank (`__cbank`); a null near
  pointer stays null. A far pointer converts to a near one by keeping the offset (cc816
  warns: `-Wfar-pointer`, `-Wfar-cast`).
- **Integers**: `(unsigned long)p` is the 24-bit address (bank << 16 | offset); `(char
  *)0x050000L` is bank 5, offset 0; `(unsigned)p` is the offset. A 16-bit integer converted
  to a far pointer is widened as an integer (bank 0): write `(char *)hz_farptr(bank, off)`
  or a 32-bit value.
- **Types**: `sizeof(void *)` is 4, `size_t` is 16 bits (`unsigned int`) and `ptrdiff_t`
  16 bits (`int`), as in DOS's large model (one object is at most 65,535 bytes);
  `intptr_t` and `uintptr_t` are 32 bits (`long`, `unsigned long`: they hold a pointer);
  `PRIdPTR` is `"ld"`.
- **Structures** that hold pointers grow: each pointer member takes 4 bytes (structures are
  packed, no padding). Code that reads a structure from a file written by DOS with
  pointer members (which DOS wrote as 4-byte far pointers too) reads the same layout.
- **DOS's segment:offset** (`MK_FP`, `FP_SEG`, `FP_OFF`) has no meaning on the 65816; a
  port maps it (ports/xcom's `compat/xdos.h` models the DOS megabyte as an arena of banks).
  `HZ_BANK(p)`, `HZ_OFF(p)` and `hz_farptr(bank, off)` are the 65816's own, and cost a
  word move each: the representation is the 24-bit address.
- **`huge`** (objects over 64 KB, pointer arithmetic that normalises across segments) is
  not supported: it would need 24-bit index arithmetic on every access. XCOM-XT has no
  huge object (its arena keeps every block inside a bank), so it is not done; `huge` and
  `__huge` are accepted as `__far` in the compatibility spellings (below).
- **printf `%p`** prints the 24-bit address as `0x` and 6 hexadecimal digits
  (`0x05a3f0`; near data: 4 digits); `scanf %p` reads it back. `%s` takes a far string. Variable arguments: a pointer is 4 bytes.
- **Function pointers** are as in the large code model: 16 bits, the function's entry in
  the main bank. Converting one to `void *` gives a far pointer into the main bank, and
  back.

### Where objects live

The direct page, both stacks, the runtime, the loader, the thunks and every `__near` object
are in the main bank. So are a function's locals: `&local` (an array, a structure, a local
whose address is taken) is a far pointer whose bank is the main bank, which the code takes
from `__cbank` (a direct-page word the startup sets: the bank is known only at load time;
one `lda __cbank`).

Each object is placed by its declaration, when the file is compiled:

| Object | Where | How the code reaches it by name |
| --- | --- | --- |
| a string literal | far data | long addressing (`lda f:L_S3,x`) |
| a `const` object (the object itself const: `const int t[]`, `const char *const names[]`; not `const char *names[]`, whose elements may change) | far data | long addressing |
| an object declared `__far` | far data | long addressing |
| an object declared `__near` | the main bank | absolute addressing (`lda _x,x`) |
| any other global or static | the main bank | absolute addressing: as fast as near data |

**Far data** is the large code model's banks of far objects, which hcc fills after the code
banks (first fit, in the order of the files, an object in one bank, an object larger than a
bank an error) and the startup loads from the program file with the code. A
literal or a `const` table costs nothing in the main bank. Long addressing (`lda
f:name,x`, 4 bytes, 5 cycles) is one byte and one cycle more than absolute addressing, so a
table in far data is read about as fast as one in the main bank; its address is a far
pointer to its bank. Writable globals stay in the main bank because they are the hot
scalars and arrays of most programs, and absolute addressing has the forms long addressing
lacks (`inc`, `stz`, `ldx`, `ldy`, `,y`).

**Consistency without a rule for every file.** A file that only declares an object
(`extern`) reaches it with absolute addressing only when its declaration says the object
is near (not `const`, not `__far`); otherwise with long addressing, which reaches either
place (the bank byte of a main-bank object is relocated by Horizon's loader). So `extern
const char tbl[];` in one file and `const char tbl[] = ...;` in another always agree, and
the only declarations that must match are the C ones (`const` and `__far` in the extern
declaration as in the definition). The C library (built split) keeps its own constants in
the main bank: it is small, and long addressing finds them there too.

**Control.** `__far` moves a writable object out of the main bank (put it on every
declaration of it, the header's too); `__near` keeps a `const` table in it (for a hot
table read with `,y`). There is no size threshold (Watcom's `-zt`: "objects of N bytes or
more are far"): a file that sees only `extern int t[];` cannot know the size, and the
declaration alone must say how to reach the object; the attribute on the declaration
does it, and `hcc --sizes` says which objects are worth it. `hcc --map` prints the main bank's parts and the far data banks;
`hcc --sizes` prints every object and every function, its size and where it went, biggest
first (the budget of the main bank: ports need it).

**The main bank's budget.** startup + runtime + the libraries' assembly + resident code +
thunks + writable globals + `--heap` + the software stack (`--stack`) must fit 65,264
bytes. The heap needs no room there (it continues in other banks): `--heap N` with `--data
far` is only the part of the heap kept in the main bank (default 1024).

### The heap

`malloc`, `calloc`, `realloc` and `free` return and take far pointers. The heap is a list of
arenas: the main bank's free room first (from the end of bss to the software stack's guard
zone), then whole banks taken from Horizon (`hz_bank_alloc`) when no arena has room, each a
first-fit free list as before. A block is at most 65,528 bytes and never crosses a bank
(DOS's far heap had the same 64 KB limit). A bank whose blocks are all freed goes back to
Horizon while another bank of the heap is empty too (one empty bank is kept, so a
program that takes and frees a big block in turn does not ask Horizon each time); every
bank goes back at the program's end. `malloc` returns NULL with `errno` ENOMEM when no
arena has room and Horizon has no free bank (`tests/libc` takes every bank to see it).
`hz_heap_free()` counts the free bytes of every arena and `hz_heap_peak()` the most in use
at once (both `unsigned long` with far data), `hz_heap_largest()` the biggest `malloc` that
would work now (65,528 while Horizon has a free bank); `hcc --debug` reports the peak at
exit. There is no near heap: a `__near` object is a global or a local. (`lib/malloc.c`:
64 arenas at most, about 4 MB.)

### The C library

The library is the same source built a third time: every function that takes or returns an
object pointer takes a far one (`string.h`, `stdio.h` and `FILE *`, `stdlib.h`, `qsort` and
`bsearch` with far elements, whose comparison function gets far pointers, `printf`'s `%s`
and `%p`, `scanf`'s pointers, `setjmp` (a `jmp_buf` anywhere), `time.h`, `dirent.h`,
`horizon.h`'s helpers and syscall functions). Its assembly (`rt/mem.s`, `setjmp.s`, the
syscall stubs) has a far-data form (`model.inc`'s `FARDATA`): `memcpy`, `memmove` and
`memset` are MVN/MVP between any two banks (the instruction built with both banks, about 7
cycles a byte), `strlen`, `strcpy`, `memcmp` read through `[dp],y`. A syscall takes a
pointer as X = offset, Y = bank (ABI.md), so the stubs pass a far pointer as it is: every
syscall takes a pointer into any bank the program owns. The POSIX `read` and `write` move
the bytes straight between the card and far memory (one `hz_read` / `hz_write` for 512
bytes or more; smaller reads go through the read-ahead as before). hgame is built for the
far data model too; the controls library (`hui.h`) is not (hcc refuses `--ui` with
`--data far`): a window application has no need of DOS's model.

### Calling convention with far data

As in the large code model ("In the large code model"), with one change: **a data pointer
argument is 4 bytes** (offset, bank, 0: low word first), a pointer result is in A (offset)
and X (bank). `ARGS+4,s` is the second argument when the first is a pointer. A structure
passed by value or returned is still a near address of the caller's copy (in its frame).
`va_list` is a far pointer, as always. An assembly function for both data models uses
`model.inc`'s `PTRSZ` (2 or 4) for the offsets and `FARDATA` for the code that differs:

```asm
; unsigned sum8(const unsigned char *p, unsigned n) for every model
        .include "model.inc"
_sum8:  lda     ARGS,s          ; p's offset
        sta     __h0
.if FARDATA
        lda     ARGS+2,s        ; p's bank
.else
        lda     __cbank         ; (near data: the main bank)
.endif
        sta     __h0+2
        lda     ARGS+PTRSZ,s    ; n
        ...                     ; then lda [__h0],y
```

### Compatibility spellings

DOS compilers' keywords are accepted in every model, because ports would otherwise define
them alike: `far`, `_far`, `__far` (= `__far`), `near`, `_near`, `__near` (= `__near`),
`huge`, `_huge`, `__huge` (= `__far`: see "huge" above), and `__cdecl`, `_cdecl`,
`__pascal`, `__loadds`, `__saveregs`, `__interrupt`, `__export`, `_Seg16` (read and
ignored: there is one calling convention; an interrupt function cannot be written in C
here). The lower-case `far`, `near` and `huge` are only keywords with `-fdos-keywords`
(hcc and cc816), since they are ordinary names in other C. Also:

- `T __far *a, __far *b;` and `int n = 1, __far *p;`: a qualifier before a later
  declarator's `*` applies to that declarator (Watcom and Microsoft C take it so).
- `void (__far *f)(void);` (a far function pointer): accepted, `__far` ignored with a
  warning (`-Wfar-function`): a function pointer is the main-bank entry in every model.
- `#pragma aux name = "..."` (Watcom's inline machine code) and every other pragma cc816 does
  not know: a warning (`-Wunknown-pragmas`), with a word on `aux` ("Watcom inline code:
  name needs a C body"). `#pragma pack(1)` / `pack()` / `pack(push, 1)` / `pack(pop)` are
  accepted silently (structures are always packed); `pack(n)` with n above 1 warns (cc816
  cannot pad).

### Not supported with far data

- `huge` pointers and objects of 64 KB or more (above).
- The small code model (`--data far` needs `--code large`), the controls library.
- Mixing objects of the two data models in one program.
- An object reached through near addressing in one file and placed far by another file's
  declaration: give the extern declarations the same `const` and `__far` as the definition.
- (A limit, not a fault: a `__far` object without an initialiser still takes its bytes,
  zeros, in the program file, as before; a big zeroed buffer is better from `malloc`.)

### What it costs

The same C with near data (`--code large`) and with far data (`--code large --data far`),
in the emulator (`tests/run.py`'s bench and fbench; `tests/bench/farbench.c` for the
pointer shapes, in cycles a step: a byte, an element, a call):

| | near data | far data | |
| --- | --- | --- | --- |
| bench: sieve, sum16, mul32, fib22, strs, structs (ms) | 810, 298, 1,279, 420, 849, 675 | 810, 296, 1,287, 416, 954, 740 | strs (pointers and bytes) +12 %, structs +10 % |
| fbench: mandel, sincos, sqrt, expow, conv (ms) | 2,150, 1,650, 370, 1,950, 1,065 | 2,140, 1,647, 349, 1,940, 1,070 | the same |
| copy, `while ((*d++ = *s++))` | 85 | 96 (121 before the pointer's in-place step) | +13 % |
| sprite, `if (*s) d[k] = *s;` (a 32 x 40 masked sprite) | 95 | 105 (111) | +11 % |
| index, `s += a[i]` of a global array | 98 | 103 | the array is near: its name is absolute addressing |
| pindex, the same through a pointer parameter (`int i`) | 171 | 205 (255 before the offset-only index) | +20 % |
| member, `p->x += p->y + i` along an array of structures | 116 | 125 | +8 % |
| call, `d = pass(d) - 1`: a pointer argument and result | 95 | 188 (197) | 4 bytes pushed, A and X back, 32-bit arithmetic |
| `memcpy`, `strlen` (4,000 bytes) | 12, 12 | 10, 10 | MVN either way; `strlen` reads two bytes a round |
| program size: fbench, farbench | 27,881, 10,979 bytes | 32,169, 18,703 | the far library's heap, stdio and printf with far pointers |
| XCOM-XT's code | 578,218 bytes (does not link: its data does not fit) | 732,183 bytes in 12 banks | +27 % |

So: arithmetic, calls without pointers and code that reads globals by name cost nothing;
loops through pointers cost 8-20 % more, a call with pointer arguments about twice as
much, and code grows by about a quarter where pointers are everywhere. A byte read through
a far pointer is an 8-bit load (`sep`/`rep`: a 16-bit one could touch the next bank at a
bank's last byte); a far pointer stepped in place is `inc`, `bne`, `inc` (`p++`), and
an index through it is Y (`[p],y`) when it is unsigned, an add to the offset alone when
it is signed (`r045_far_signed_index.c`). Hot loops can take `__near` pointers to main-bank buffers, or move
to assembly.

## Types

| Type | Size | Range / note |
| --- | --- | --- |
| `char` | 8 bits | **unsigned** (0-255; the library is built so); `signed char` for -128-127; `-fsigned-char` makes plain `char` signed |
| `short`, `int` | 16 bits | -32,768-32,767 (`unsigned`: 0-65,535) |
| `long` | 32 bits | |
| `long long` | 64 bits | `int64_t`, `uint64_t`, `intmax_t`; `LLONG_MAX` ... |
| `float`, `double`, `long double` | 32 bits (all three) | IEEE 754 single precision (24-bit significand: about 7 decimal digits, 1.2e-38 to 3.4e38, denormals down to 1.4e-45) |
| data pointer | 16 bits | an offset in the main bank; `__far` pointers are 32 bits (offset, bank, 0). With far data (`hcc --data far`) 32 bits, `__near` ones 16 ("The far data model") |
| function pointer | 16 bits | the function (small model) or its entry in the main bank (large model) |
| `size_t`, `ptrdiff_t` | 16 bits | `unsigned int`, `int`: one object at most 65,535 bytes (in both data models) |
| `intptr_t`, `uintptr_t` | 16 bits; 32 with far data | `int`, `unsigned int`; `long`, `unsigned long` with far data (they hold a pointer) |

Structures are packed (no padding): the parameter blocks in `horizon.h` match ABI.md byte
for byte (each has a compile-time size check). Bytes are little-endian.

Predefined macros: `__CC816__`, `__65816__`, `__HORIZON__`, `__ATARI816__`,
`__CHAR_UNSIGNED__` (not with `-fsigned-char`), `__CC816_LARGE__` in the large code
model, and `__CC816_FAR_DATA__` in the far data model.

## Pointers, banks and far memory

An object (an array, a structure, a `malloc` block) must not cross a bank boundary: a
pointer's arithmetic is 16-bit. A bank is 64 KB; Horizon gives a program more of them
with `bank_alloc` (`hz_mem_info()` says how many are free: 92 banks in all on the 8 MB
machine, some used by Horizon and other programs).

```c
#include <horizon.h>

unsigned char __far *buf = hz_far_alloc();  /* a fresh bank, offset 0; NULL if none */
buf[60000u] = 1;                             /* any offset 0-65535 */
hz_far_copy(buf + 1000, "text", 5);         /* MVN, about 12 cycles a byte */
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

A plain pointer is an offset in the main bank: it cannot point into another bank. Memory
of other banks is reached through `__far` pointers (`unsigned char __far *p`), which read
and write with long addressing. A near pointer converts to a far one by itself (its bank
is the main bank; a null pointer stays null), and so `(unsigned long)p` is the whole
24-bit address of p: `HZ_BANK(p)` of any pointer is right. A far pointer converted to a
near one keeps its offset only. An integer converts to a far pointer as it is: `(char
__far *)0x050000L` is bank 5, offset 0 (`hz_farptr(5, 0)` is the same). Code that keeps
far addresses in plain pointers (`(char *)hz_far_alloc()`, `(const char *)farbuf`) must
say `__far` instead, or copy the data into the main bank first (`hz_far_copy`): see
[porting.md](porting.md).

## Calling convention (for assembly)

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

### In the large code model

`hcc --code large` changes only this (the rest above stays as it is):

- Functions are called with **JSL** and return with **RTL**: the first argument is at
  `4,s` (above the 3-byte return address). A `.s` function called from C ends with `rtl`;
  it calls a C function with `jsl _name` (any C function, wherever it is: hcc patches the
  bank). PBR is the bank of the code that runs; DBR is the main bank, always: keep it.
- hcc assembles `.s` files with `-D __CC816_LARGE__=1` and with `sdk/c/rt` on the
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

### Inline assembly

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

## The C library on Horizon

cc816 has a C library of its own (`sdk/c/lib`, in C) and a runtime (`sdk/c/rt`: the
startup, the memory and string routines and the arithmetic, in assembly). It is built
split, one function a module, so a program links only what it uses. The libc test
(`tests/libc`, 86 checks: formats, strings, sorting, the heap, files, folders, time, far
memory, errno, argv, the keyboard, atexit) checks it in both code models and with far
data (there the heap is filled by taking every bank Horizon has).

| | |
| --- | --- |
| `main(int argc, char **argv)` / `main(void)` | the argument string split at spaces; `"quoted words"` stay whole (a quote anywhere starts or ends quoting: `a"b c"d` is `ab cd`); `argv[0]` is the program's name as the menu bar shows it ("Greet"), not its path (`hz_task_path` gives the path); at most 32 arguments. The return value is the exit code |
| `exit`, `atexit`, `_Exit` | atexit functions newest first, then every open FILE is flushed and closed. `hz_exit()` ends at once without flushing |
| `printf` family | `%d %i %u %x %X %o %c %s %p %n %%`, the sizes `hh h l` (and `z t`), widths, precision, `-+ 0#`, `*`; `%f %F %e %E %g %G %a %A` (also with `l`, `L`) in programs that use them ("Floating point", below: "Only for programs that use it"); `%lld %lli %llu %llo %llx %llX` (and `j`: `intmax_t` is `long long`; `inttypes.h`'s `PRId64` ...) in programs that use `long long` ("long long") |
| `scanf` family | `%d %i %u %o %x %c %s %[...] %p %n`, `*`, widths, the sizes `hh h l`; `%f %e %g %a` (`float *`; with `l` or `L` `double *`, `long double *`: the same 32 bits) in programs that use them; `%lld %lli %llu %llo %llx` (and `j`, `SCNd64` ...) in programs that use `long long`; `scanf` reads the keyboard (see stdin) |
| stdout, stderr | the console (the screen and the log; a terminal window when started there), line-buffered: a line is sent at `\n`, before reading stdin and at exit |
| stdin | the keyboard: a line typed with echo, Backspace, Left / Right; `fgets(buf, n, stdin)`, `getchar`, `scanf`. Ctrl-C or ctrl-D on an empty line: end of input (EOF) |
| `fopen` | modes `r`, `w`, `a`, `r+`, `w+`, `a+` (`b` is ignored, no line-end conversion; `x` fails if the file exists). **4 file handles for the whole system**: when none is left, NULL and `errno == ENFILE`. A missing file or folder: `ENOENT`. 1 KB of buffer from the heap; when the heap has no 1 KB free, 128 bytes; when not even that, the FILE's own 2 bytes (slow, but the file opens and works). `setvbuf(f, NULL, _IONBF, 0)` gives the 1 KB back. The FILE structures are static (4, one for each of Horizon's handles). `strerror(ENOMEM)`: "Not enough memory (the heap, or no free bank)" |
| `fread fwrite fgets fputs fgetc fputc getc putc ungetc fprintf fscanf fflush fclose feof ferror clearerr` | yes, buffered |
| `fseek ftell rewind`, `fgetpos`, `fsetpos` | yes, any position (32 bits); `SEEK_END` from the size at open plus what was written |
| `remove`, `rename` | yes (rename also moves between folders on the card) |
| `freopen` | files only (not stdin, stdout, stderr) |
| `tmpfile`, `tmpnam` | not supported (NULL) |
| `opendir readdir rewinddir closedir` (`dirent.h`) | yes: `d_name`, `d_size`, `d_attr` (`HZ_ATTR_DIR`); no file handle used |
| `errno`, `strerror`, `perror` | errno from Horizon's codes (`ENOENT` no such file or folder, `EACCES` denied, `EEXIST`, `ENFILE` no handle left, `ENOMEM`, `EINVAL`, `EBADF`, ...); `hz_strerror(code)` says a Horizon code in words |
| `malloc calloc realloc free` | first fit over the heap; NULL when it is full (the libc test: 25 blocks of 1 KB). `hz_heap_free()`, `hz_heap_largest()`, `hz_heap_peak()` (horizon.h) |
| `string.h`, `ctype.h`, `qsort`, `bsearch`, `strtol`, `strtoul`, `atoi`, `atol`, `abs`, `div`, `rand` (RAND_MAX 32767) | yes |
| `strtod`, `strtof`, `strtold`, `atof` | exact (rounded to nearest, ties to even, from any number of digits), hexadecimal (`0x1.8p3`), `inf`, `infinity`, `nan`, `nan(...)`; ERANGE on overflow and when a nonzero number becomes 0 |
| `math.h` | the list under "Floating point", below |
| `strtoll`, `strtoull`, `atoll`, `llabs`, `lldiv` | yes (`inttypes.h`: `strtoimax`, `strtoumax`, `imaxabs`, `imaxdiv` are the same) |
| `setjmp`, `longjmp` | yes ("setjmp and longjmp", below) |
| `assert` | prints the expression, the file and the line on stderr, then exit code 3 |
| `time()` | seconds since 1970 from Horizon's clock (`time_get`: set by the Desktop or the shell from /SYSTEM/CLOCK or the PC; never set: it counts from 2000-01-01); `gmtime`, `localtime`, `mktime`, `strftime` (no time zones) |
| `clock()` | CLOCKS_PER_SEC is 50: 20 ms steps. Milliseconds: `hz_uptime()` |
| `open`, `creat` (`fcntl.h`), `read`, `write`, `lseek`, `close`, `unlink`, `isatty` (`unistd.h`) | POSIX's file descriptors, for code written for Unix or DOS (the Xargon port's boards): `O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC O_EXCL O_APPEND` (`O_BINARY`, `O_TEXT` are 0: nothing is converted); descriptors 0-2 are the console, files 3 and up (Horizon's 4 handles, shared with `fopen`). No buffer for writing; a read-only descriptor reads ahead 512 bytes from the heap (small reads of records, each a call to the card otherwise), a read of 512 or more goes straight to the card. `lseek` any 32-bit position (`SEEK_END` from the size at open); `read` returns all the bytes asked for unless the file ends. Errors in `errno` (`ENOENT`, `EEXIST`, `EBADF`, `ESPIPE`, `ENFILE`). `sdk/c/lib/posixio.c`; tested by `tests/libc` |
| `system`, `getenv`, `signal`, `raise`, locales | not supported (they return failure) |

## Floating point

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

**Where it is.** The arithmetic is in 65816 assembly, `sdk/c/rt/fp_*.s`: `__fadd`,
`__fsub`, `__fmul`, `__fdiv`, `__fcmp`, `__ltof`, `__ultof`, `__ftol`, `__ftoul` (operands in
`__h0`/`__h1`, as the 32-bit helpers; the contract is at the top of `fp_pack.s`). They take
1,792 bytes when all are linked. A float is passed and returned as a `long` is (4 bytes on
the stack; A/X). For assembly: the bits of a float are its IEEE pattern, low word first.
cc816 has two builtins to see them without a union: `__builtin_fbits(x)` (the 32 bits as
an `unsigned long`) and `__builtin_bitsf(u)` (back).

**Only for programs that use it.** The arithmetic helpers are linked as any helper is:
when the code calls them. printf's float conversions (`lib/fmtfp.c`, 3,677 bytes)
and scanf's (`scanfp.c`, 1,699 bytes, with `strtod`, 4,848 bytes) are linked only when a
file may need them. A printf call (`printf`, `sprintf`, `vsnprintf`, ...) whose format is
a string constant links the float conversions when the format has one (`%f %e %g %a` and
their capitals), and nothing for floats when it has none: `printf("%d\n", n)` in a file
full of `double`s brings no float printing. A printf whose format is not a constant (a
variable, a parameter) links them when the file uses floating point (it defines a float
object, has a float constant, converts to or from a float, or calls a function with a
float argument or result; a prototype alone, as in `stdlib.h`, does not count); so does
a float given to any variadic function (a wrapper of printf). That links
`rt/fp_hookp.s`, whose constructor gives printf its float conversions. The same
for scanf: `sscanf(s, "%d", &n)` links no float scanning; `%f` in its format, a format
that is not a constant in a file with floating point, or a float pointer given to a
variadic function links `fp_hooks.s`. So a program without floating point has no float
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
`sdk/c/lib/mathint.h`) in their single-precision form, with two changes to `pow`
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
faster). The benchmark is under "Speed".

**How it is tested.** `tests/fpu` (in `make -C sdk/c test`), 47,159 cases, bit for bit:
28,450 operations (+ - * / compares conversions: specials against specials, ties,
denormal and overflow results, random patterns) whose expected bits are also checked
against the host's SSE hardware; 3,000 printf and strtod results against glibc; 15,709
math.h results against the same C built for the host. `tests/float/float.c` and `ieee.c` (the edges,
readable). The compiler's random programs (`make -C sdk/c/cc816 check`) include float
programs checked bit for bit against gcc.

## long long

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
and other shifts call helpers in 65816 assembly (`sdk/c/rt/rt_mul64.s`,
`rt_div64.s`, `rt_shift64.s`: the operands in `__h0`..`__h3`, the contract at the top of
`rt_shift64.s`). The conversions to and from `float` are C (`sdk/c/lib/llconv.c`),
rounded as the 32-bit ones are (to nearest, ties to even; toward zero to an integer).
`(long long)` of a float out of range gives `LLONG_MIN` (as x86 does), `(unsigned long
long)` gives `ULLONG_MAX` for 2^64 and above and for NaN. A `long long` argument takes 8
bytes on the stack, a result comes back in `__h0`..`__h1` ("Calling convention").

**Only for programs that use it.** The helpers are linked when the code calls them.
printf's and scanf's `%lld` family (`lib/fmtll.c`, `scanll.c`) is linked as the
float conversions are: by a constant format with `%lld` (or `%jd`, ...), by a format that
is not a constant in a file that uses `long long`, or by a `long long` given to a
variadic function. A program without `long long`
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

## setjmp and longjmp

`setjmp.h` has `jmp_buf`, `setjmp`, `longjmp` (and `sigsetjmp`, `siglongjmp`, `_setjmp`,
`_longjmp` as the same). `setjmp` returns 0, then the value `longjmp` gives (1 if that
is 0). A `jmp_buf` (54 bytes) keeps the hardware stack pointer, the return address, the
software stack pointer and the 48 bytes of callee-saved registers; `longjmp` puts them
back (`sdk/c/rt/setjmp.s`). It may jump out of any depth of calls, also out of a
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
prototype and a comment (113 syscalls, 115 functions: `hz_spr_move_many` and
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
  to ASCII, KEY_* for arrows), `hz_prog_dir(buf, size)` (the program's own folder, below).
- **The program's own file** (Horizon 0.28): `hz_task_path(buf, size)` gives the absolute
  path of the file the program was loaded from, such as `/GAMES/MINE/GAME.PRG`, and returns
  its length. `hz_prog_dir(buf, size)` gives its folder, `/GAMES/MINE/`, ending in `/`. A
  128-byte buffer always fits. Both return -1 on an older Horizon (hz_errno `HZ_ENOSYS`).
  A game uses them to find its data files next to it, however it was started (the shell,
  the Desktop's Programs menu, Files):

  ```c
  char path[128];
  FILE *f;
  if (hz_prog_dir(path, sizeof path) < 0)
      strcpy(path, "");               /* an older Horizon: the current folder */
  strcat(path, "LEVELS.DAT");
  f = fopen(path, "rb");
  ```
- **What the program needs** (Horizon 0.29): `hcc --needs horizon=0.29,opl2,mem=1024K`
  (also `rev=N`, `lau`, `sprites`, `blitter`, `joystick`) adds a check that runs
  before `main`: where something is missing the program prints one line ("GAME needs the
  OPL2 sound chip (hardware revision $0C).", also in a small window when the window system
  runs) and exits with code 1. It works on older Horizons too. Without `--needs` nothing is
  added. `hz_sys_info()` returns Horizon's version (major x 256 + minor, 0x001D for 0.29, 0x001E for 0.30)
  and sets `hz_x` to the hardware revision (-1 / 0xFFFF and `HZ_ENOSYS` before 0.29). An
  app (a program in its own folder, installed from an `.HZA` archive):
  [../apps.md](../apps.md).
- **A syscall without a wrapper** (a newer kernel's): `hz_syscall(n, a, x, y)` returns A and
  sets hz_errno, hz_x, hz_y. A pointer is two arguments: `HZ_OFF(p)` and `HZ_BANK(p)`. Or
  write the stub in assembly as the generated ones are (`sdk/c/build/lib/small/stubs/*.s`):
  the arguments into A, X, Y, `cop #$NN`, `bcs` to an error path.

## The heap and the stacks

The main bank (the code bank of the small model) from bottom to top:

```
$0100   code, constants, data, bss      (hcc --map: their sizes)
        heap (malloc, and fopen's buffers) ... grows up
        software stack guard zone (256 bytes)
        software stack ... grows down    --stack N (default 8192)
$FFF0
```

| | How big | Who sets it |
| --- | --- | --- |
| Heap | what is left between the bss and the software stack. `hcc --map` prints it ("heap 11,283") | the small model: everything else; the large model: hcc fills the main bank with code but keeps at least `--heap N` bytes for the heap (default 4096) |
| Software stack | `--stack N` bytes (512 to 32,768, even; default 8,192) | `hcc --stack N` |
| Hardware stack | about 32,000 bytes, in the window | fixed |

`malloc` returns NULL (errno ENOMEM) when the heap has no block big enough. Each open file
takes 1 KB of it (less when there is no 1 KB: "The C library on Horizon"). To see what a
program uses:

- `hcc --debug`: at exit the program prints `stack: N of M bytes used`, `software stack: N
  of M bytes used` and `heap: N of M bytes used at most` (the most in use at once, block
  headers counted);
- at any time: `hz_heap_free()` (the free bytes), `hz_heap_largest()` (the biggest
  `malloc` that would work now), `hz_heap_peak()` (the most in use so far),
  `hz_sstack_free()`, `hz_stack_free()`.

A program short of heap: give it more with `--heap N` (the large code model) or less software
stack (`--stack N`, when `--debug` shows it uses little), and put big buffers in banks of
their own (`hz_far_alloc`).

A program has two stacks. The **hardware stack** is the window's top part (about 32 KB): return
addresses, arguments and the values the register allocator spills. The **software stack**
is the top of the main bank (`--stack N` bytes, default 8,192): arrays, structures and
locals whose address is taken. Big local arrays and deep recursion with arrays use it up.

The startup fills each stack's lowest 256 bytes with a pattern (the **guard zone**); at
exit the program checks them and, if any of a zone was written, prints `stack overflow:
the guard zone at window address N (the stack's last 256 bytes) was written` (the
software stack: `stack overflow: the software stack's guard zone at N ... was written`).
An overflow is only seen if something was written into those 256 bytes (a never-written
local array larger than that can jump over them), and only at exit (`hz_stack_check()`
checks any time; `hz_stack_free()` gives the bytes below the hardware stack pointer now,
`hz_sstack_free()` those of the software stack). With `hcc --debug` the startup
paints the stacks and the exit reports the most used: `stack: 109 of 32251 bytes used`
and `software stack: 660 of 7936 bytes used`.

**The software stack is checked at every function's entry.** A function with a frame
there (an array, a structure, a local whose address is taken, the copy of a structure
returned by value) compares `__sp` minus its frame with the stack's lowest address before
it takes the frame (9 cycles, 9 bytes of code and the name: under 1 % of the
benchmarks). When the frame does not fit, the program stops before anything is
overwritten (the heap lies just under the stack), prints

```
software stack overflow: build_atlas needs a frame of 3700 bytes; 396 of the software stack's 4096 bytes are free (hcc --stack N; docs/c/reference.md)
```

and exits with code 3 (the `atexit` functions and the destructors run, as for `exit`).
Before, such a frame went into the heap without a word and the program's data changed
under it (the SkyRoads port: a 3.7 KB structure returned by value in a 4 KB stack). The
hardware stack is not checked this way (its guard zone, at exit, as above).

The compiler warns at a frame over 1 KB and refuses one bigger than the whole software
stack (hcc gives cc816 the `--stack` size; a library compiled alone is checked against
the default 8,192):

```
atlas.c:14:16: warning: the function 'load_atlas' needs a software-stack frame of 7,400 bytes (the software stack is 8,192 bytes: hcc --stack N; arrays and structures returned by value are there) [-Wframe-larger-than]
atlas.c:30:5: error: the function 'huge' needs a software-stack frame of 9,000 bytes, more than the whole software stack (8,192 bytes): make the big locals static or global, or give hcc --stack 10240
```

A structure returned by value takes its size twice: the callee's local and the caller's
copy (`struct big b = make();` is two of them in the caller). Big structures are better
filled in place through a pointer.

## Program files

ld65 (cc65's linker, the one Horizon's own programs use) writes the o65 file
straight away, with the startup first at $0100 (`rt/hzprog.cfg`), and hcc then
drops the relocation entries that add nothing (`tools/o65strip.py`, the SDK's copy of
Horizon's: the loader always puts a program at $0100, so only the bank bytes need it;
it checks that the result loads the same at three banks). A hello world keeps 8
relocations.

**`--code large`** (`tools/hzlarge.py`): the objects' segments are read first
(`tools/ca65obj.py`: cc816 gives every function that can move a segment of its own, and
ld65's configuration must name every segment). A trial link with those segments in one
big pool gives the main bank's fixed part and the functions whose 16-bit address is used;
hcc places the functions (first fit: the main bank, then banks of 64 KB), writes a glue
module (the thunks, `__T_name = _name` for the functions in the main bank, the loader's
table: the number of banks, the stamp, the program's name) and writes ld65's
configuration: the main bank as an o65 file, each other bank as a raw image. Then it
links **three times**, with bank k at the link-time banks k, k + $40 and $80 + 2(k - 1)
(in the third link at offset 1). In the main bank a byte that differs between the links
must name one bank in all three (the link's bank of k each time): it is a bank byte of
bank k (a JSL to a function there, a thunk's JML) and becomes one of the relocations
after the o65.
The two bytes before such a bank byte may differ by one in the third link (a far
address's offset). Anything else stops the build: a value "bank + 1" is odd in the third
link, and a 16-bit address of a function in another bank written in the main bank (which
ld65's o65 output would cut to 16 bits without a word: `.addr _name` in a `.s` file) is
one more there, without a bank byte after it. The main bank's own bank bytes are o65 SEG
relocations, done by Horizon's loader as in any program. In the other banks the compiler
records the address of every bank byte it writes (segment XREL: each JSL's, JML's and
MVN's), and hcc reads their bank from the first link (0: the main bank); a byte that
differs between the links and was not recorded stops the build. The .PRG is the first
link's o65 file (o65strip, as above), then the bank images, the relocations and the
8-byte trailer ("The file's layout", above). A
build's stamp is a hash of what was linked and where: the same build gives the same
files.

## Compiler notes

cc816 is the SDK's own compiler. It reads C99 and most of C11, and some GNU C. This part
says what it takes, what it does not, how it reports problems, and which faults were
found and fixed.

### What cc816 compiles

- C99: `//` comments, declarations anywhere, `for (int i = ...)`, `_Bool` and
  `<stdbool.h>`, `inline`, `restrict`, designated initialisers (`.a.b = 1`, `[3] = x`, the
  values after a designator go on from there), compound literals (also at file scope),
  flexible array members, variadic macros, `__func__`, `static` and qualifiers in array
  parameters (`int a[static 3]`), hexadecimal floating constants, `long` (32 bits),
  `long long` (64 bits: "long long"), `setjmp`/`longjmp`.
- C11: `_Static_assert`, `_Generic`, `_Alignof` (always 1), anonymous structures and
  unions, `_Noreturn`, `u"..."`, `U"..."`, `u8"..."`.
- Old C: K&R function definitions (`int f(a, b) int a; char *b; { ... }`), functions
  without a prototype, tentative definitions (`int x; int x = 5;`).
- GNU C: statement expressions (`({ int t = f(); t * 2; })`), `typeof` and
  `__typeof__`, a cast as an lvalue, `case` and labels anywhere in a switch (Duff's
  device), case ranges (`case 'a' ... 'z':`: up to 32 values become cases, a wider range
  of a 16-bit switch is one test, a 32- or 64-bit switch takes at most 256), range
  designators (`[0 ... 9] = x`, also nested; a local's x is computed for each element),
  inline assembly ("Inline assembly"), a static object or element initialised
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

### What cc816 does not support

Each of these is an error that starts with "cc816 does not support". What to do instead:

| Not supported | Do this instead |
| --- | --- |
| a 64-bit `double` | none: `double` is the same 32-bit format as `float` ("Floating point") |
| variable-length arrays (`int a[n];`) | a constant size, or `malloc` |
| `__int128` (128-bit integers) | `long long` (64 bits), or a pair of them |
| a `long long` bit-field | a `long` or `unsigned long` one (up to 32 bits), or a whole `long long` |
| GNU asm operand lists (`asm("..." : "=r"(x) : "r"(y))`) | `%[name]` in the text ("Inline assembly") |
| a case range of more than 256 values in a `long` or `long long` switch | an `if` on the range |
| `_Complex` | a structure of two `float`s |
| an `int` bit-field wider than 16 bits | declare it `long` or `unsigned long` (up to 32 bits) |
| labels as values (`&&label`, `goto *p`) | a `switch` on a state number |
| nested functions (a function defined inside another) | a function at file scope, its data passed by pointer |
| GCC built-ins (`__builtin_popcount`, ...) | the C library, or a few lines of C |
| `#include_next` | `#include` with the path |
| an object of 65,536 bytes or more | a bank of its own: `hz_far_alloc` and a `__far` pointer |

### Errors and warnings

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
| `frame-larger-than` | a function's software-stack frame over 1 KB (its arrays, structures, the copies of structures returned by value), with the stack's size ("The heap and the stacks"); a frame bigger than the whole software stack is an error |
| `unknown-pragmas` | a `#pragma` cc816 does not know, ignored: Watcom's `#pragma aux name = "..."` (inline machine code: the function needs a C body) and `#pragma aux name parm ...`, `pack(n)` with n above 1; `once`, `pack(1)`, `GCC`, `STDC` and Watcom's message pragmas are silent |
| `far-function` | `__far` on a function pointer (`void (__far *f)(void)`), ignored: a function pointer is the main-bank entry in every model |
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

### Options

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
environment), `--data near|far` (the data model, "The far data model"; `HZ_DATA`; far
needs `--code large`), `-fdos-keywords` (`far`, `near`, `huge` as keywords; cc816 takes it
too), `--sizes` (every object and function of the link, its size and where it went:
"Where objects live"), with `--code large` also `--heap N` (the main bank's room kept for
malloc) and, for tests, `--main-room N`,
`--bank-room N` and `--spread N` (how much code the main bank and each other bank may
take; the functions in turn in N banks); `--no-stack-check` (the program's functions
without the software stack's entry check, "The heap and the stacks": about 1-3 % less
code, 10 cycles a call of a function with a frame; the library keeps its checks).

### How it is tested

Its regression set (`make -C sdk/c/cc816 check`) has five parts, and runs them in three
configurations: the small code model, the large one, and the large one with far data
(`CODES=small large large-far`; `tests/check.py --code large-far`: every data pointer 32
bits, every string literal and constant in far data, every function in another bank: the
same programs give the same results). `tests/diag/` (109
files, no emulator; `make -C sdk/c/cc816 diag` runs it alone): each file says the errors
and warnings it must give, and nothing else may be said; a Python traceback fails the
test. Then 400 test programs, each with one random change (a token taken out, doubled
or replaced), must all give messages or compile, never an internal compiler error. `tests/regress/`: one small program
for each fault found, run in the emulator (those whose code differs between the levels,
marked `LEVELS: 0 1 2`, at -O0 and -O1 too). `tests/lang/` (29 programs): one for each part
of C listed above, `long long`, `setjmp`, inline assembly and the GNU extensions among
them. Random programs checked against gcc's results
(`cc816/tests/fuzz/genfuzz.py`: arithmetic of every width, casts, compares, shifts,
division, arrays, structures and their copies, structures by value, bit-fields, function
pointers, variable arguments, far pointers, switches, loops that spill registers,
designated initialisers and compound literals, unions read through other members,
anonymous unions, `goto` state machines and Duff's device, enumerations, `_Bool`, the
comma operator, statement expressions, `long long` mixed with every other width (its
operators, conversions both ways and to float, globals, structures, arguments, results,
function pointers, variadic arguments, switches, sprintf `%lld %llu %llx %llo`;
division, remainder and shifts by constants and compares with constants, every width, the
operands at the edges); and floating-point programs, `--features
basic,float`: float and double arithmetic, compares, conversions both ways, `++`, compound
assignments, float arrays, structures, globals, pointers, parameters, results, variadic
doubles, sprintf `%f %e %g`, checked bit for bit against gcc's SSE single precision). And
the c-testsuite when `CTS=` points at a checkout.

### Faults found and fixed

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

23. **`#define NAME= value`** (no white space between the name and the replacement) was
    refused ("Bad macro definition"). C99 asks for the space; older compilers took the
    line as it is, and gcc warns and takes the rest of the line, `=` and all: cc816 now
    does as gcc (`warning: missing whitespace after the macro name`). Xargon's
    keyboard.h has one (`r032_define_no_space.c`).
24. **A header with bytes above 127 that are not UTF-8** (a DOS program's code page 437
    text in a string: Xargon's cfg_win.h) made an internal error (UnicodeDecodeError): the
    main file was read byte for byte (Latin-1), included files as UTF-8. Every file is read
    byte for byte now (`r033_latin1_source.c`).
25. **An undeclared name in an array's size** (`int t[numkinds];` without the header that
    defines numkinds) was reported as "cc816 does not support variable-length arrays"; it
    is "'numkinds' undeclared" now (`tests/diag/array_size_undeclared.c`).
26. **A frame bigger than what was left of the software stack** went into the heap without
    a word (the SkyRoads port: a 3.7 KB structure returned by value with `--stack 4096`;
    the data changed under the program). Every function with a frame now checks at its
    entry and stops the program with its name ("The heap and the stacks"); the compile
    warns at a frame over 1 KB and refuses one bigger than the stack
    (`tests/stack/stackbig.c`, `tests/diag/w_frame*.c`).
27. **The peephole pass made `sec ; sbc #1` a `dec a` before a `bvc`** (the overflow flag
    of a signed compare, which `dec` does not set). No code of the generator produced that
    sequence until the compares as values below; found by their test
    (`r039_compare_values.c`).
28. **A far pointer plus a long** (`p + 39999`: a decimal constant over 32,767 is a
    `long`) took the long's low word as an `int`: 39999 became -25537 and the pointer went
    back a bank. The whole value is added now (`r041_far_long_offset.c`; found by the far
    data model's own test).
29. **`p = p->next` through a far pointer**: the value got the pointer's own register, and
    the 4-byte load stored its low word before it read the high one through the
    half-changed pointer (a crash). Every word is read first now
    (`r043_far_load_self.c`; found by the random programs in the far data model).
30. **A qualified pointer to a structure defined later** (`struct n __near *p;` before
    `struct n {...}`) never saw the definition ("incomplete type"); the qualified copy now
    shares the structure's members. DOS's declarators `T __far *a, __far *b;` and `void
    (__far *f)(void)` were refused ("Invalid declarator") (`r042_far_declarators.c`,
    `tests/diag/far_declarators.c`; the XCOM-XT port).

Faster code from the same port (its profile: 13 % of the time in `__mul16` and
`__sdiv16`, and its board, a `__far` array of arrays, read through 32-bit address
arithmetic at every access):

- a multiply by a constant with up to four non-zero digits in binary **or in the
  non-adjacent form** (signed digits: `x * 31` = `x * 32 - x`, an array of 31-byte
  structures) is shifts and adds or subtracts, inline (before: only binary, so 31, 15,
  63, 255 called `__mul16`);
- a **signed divide by a power of two** (`x / 16` of an `int`) is inline: the bias for
  negative values, then arithmetic shifts (C rounds toward zero); before, `__sdiv16`;
- an **element of an array of arrays** (`a[i][j]`, and members that are arrays) adds its
  indexes into one 16-bit index; in a `__far` object, which lies in one bank, that index
  goes in Y (`[base],y`) instead of a 32-bit address built at every access; an unsigned
  index through a far pointer does the same (Y carries into the bank as the 32-bit add
  did); a signed one through a far pointer keeps the 32-bit step (it may be negative)
  (`r034_mul_div_const.c`, `r035_far_index.c`).

Faster code from the SkyRoads port (its simulation: `long / 512`, `/ 16`, `int / 5`,
`/ 10`, `1UL << c`, 32-bit compares; times with the call around the operation):

- a **16-bit divide or remainder by any constant** is inline: the quotient is
  `(|x| * M) >> (16 + s)`, the multiply by the known M done a bit at a time from the low
  end (a one-bit adds x, every bit halves the 17-bit sum: exact), the sign put back, a
  remainder `x - q * k`. cc816 picks M and s for each divisor and keeps them only if they
  give the exact quotient for every dividend (all 65,536, or 0 to 32,768 for a signed
  one; else the call stays). `int / 10` 9 us, was 51 (`__sdiv16`); `% 10` 13; unsigned
  by 32,768 or more is a compare. `x % 16` of an `int` is a mask (it was a call), `x / -16`
  the shift negated;
- a **signed `long` divide or remainder by a power of two** (`/ 512`, `% 16`, and by
  minus one) is inline: the bias for a negative dividend, then the arithmetic shift; the
  remainder `-((-x) & (2^n - 1))` (`LONG_MIN` too). `long / 512` 16 us with the call,
  was 102 (`__sdiv32`). Unsigned ones were shifts and masks already;
- **32-bit shifts by a constant** move a word for 16 or more and a byte for 8 or more (an
  unaligned word load from the register), then 0-7 bit steps with a word in A; by 7 and
  15 (`x * 128`, `>> 7`) a one-bit shift the other way and a byte move (48 cycles, was
  about 90). **By a variable** (`1UL << c`), `__shl32`, `__shr32`, `__sar32` do the same
  steps (`1UL << 13` 26 us, was 47);
- **a compare as a value** (`return a < b;`, `int c = x >= k;`, a conversion to `_Bool`)
  is the compare's carry or sign rotated into A, no branches (`opt.setcc`; 32-bit `==`
  keeps its branches, quicker when the low words differ); a `_Bool` copied to a `_Bool`
  is not tested again; `x < 0` and `x >= 0` of a `long` test the high word's sign alone;
- a parameter used a few times outside loops stays in its argument slot (`n,s`, as quick
  as the direct page) instead of being copied in by the prologue.

(`r036_div16_const.c`, `r037_div32_pow2.c`, `r038_shift32.c`, `r039_compare_values.c`,
each at -O0, -O1 and -O2 too, and the random programs' `constop` shape: divisions,
remainders and shifts by constants of every width, compares with constants, operands at
the edges.) Not done: a `long` divided by another constant (it would need a 32 x 32 ->
64-bit multiply: about as slow as `__udiv32`), inlining of `static inline` functions (each
is a call: `cell_is_empty` in SkyRoads' probes), and the copy of a structure returned
by value (it is built in the callee's frame and copied to the caller's).

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

## Speed

The 65C816 runs at 14.3 MHz; the memory stalls make CPU-bound code about half the ideal
speed (emu816 models them: its timings are the board's within about 5 %). The benchmark
(`tests/bench`, `make -C sdk/c test` runs it), in milliseconds:

| | sieve | sum16 | mul32 | fib22 | strs | structs |
| --- | --- | --- | --- | --- | --- | --- |
| -O2 (the default) | 808 | 298 | 1279 | 395 | 860 | 667 |
| -O1 | 808 | 478 | 1276 | 400 | 847 | 670 |
| `--code large`, -O2 | 810 | 298 | 1279 | 420 | 849 | 676 |
| `--code large`, -O1 | 810 | 478 | 1285 | 416 | 856 | 680 |

(strs was 994: its `% 26` is a multiply by the reciprocal now. The others move by up to
about 1.5 % between builds of the same code: the 4 KB cache sees the code at other
addresses.)

(The check values are the benchmark's six: 1899, 27824, 1071602483, 17711, 3160,
4275534039.)

What they measure: sieve (byte arrays, 16-bit indexes), sum16 (16-bit arrays), mul32
(32-bit multiply and divide), fib22 (calls), strs (pointers and bytes), structs (structure
fields, signed, shifts).

Floating point (`tests/bench/fbench.c`, `make -C sdk/c test` runs it as `fbench`), in
milliseconds, and the program's size on the card:

| | mandel | sincos | sqrt | expow | conv | program |
| --- | --- | --- | --- | --- | --- | --- |
| -O2 | 2,166 | 1,660 | 360 | 1,970 | 1,068 | 23,132 bytes |
| `--code large` | 2,150 | 1,650 | 370 | 1,950 | 1,066 | 27,881 bytes |

mandel is one 64-point row of the Mandelbrot set (+ - * and compares), sincos `sin` and
`cos` of 200 values, sqrt 500 square roots, expow `exp`, `log` and `pow` of 100 values,
conv 2,000 conversions and divisions. Every operation is rounded exactly (IEEE 754) and
math.h is within an ulp or two of the exact result. The float code takes about 1.8 KB of
arithmetic and 3.7 KB for printf's `%f`; a call to a float helper is 12 to 27 bytes of
code.

The runtime (`sdk/c/rt`), in milliseconds for the loop shown (loop overhead included;
`tests/rt/rtbench.c`):

| Operation | ms |
| --- | --- |
| 16-bit multiply, mixed values, 20,000 times | 625 |
| 16-bit multiply by 100, 20,000 times | 544 |
| 16-bit divide, mixed values, 20,000 times | 938 |
| 32-bit multiply, 10,000 times | 1,183 |
| 32-bit divide by 1000, 10,000 times | 664 |
| 32-bit modulo 7, 10,000 times | 707 |
| 32-bit divide by $12345, 10,000 times | 1,413 |
| memcpy of 1000 bytes, 200 times | 163 |
| memmove of 1000 bytes upwards, 200 times | 163 |
| memset of 1000 bytes, 200 times | 170 |
| strlen of 1000 bytes, 200 times | 148 |
| strcpy of 1000 bytes, 200 times | 320 |
| memcmp of 1000 bytes, 200 times | 199 |
| memcpy of 6 bytes, 2000 times | 26 |

(The 32-bit lines of this test read `volatile` operands: each goes through a direct-page
register before the helper takes it, about 60 cycles a call. In real loops the operands
are already in registers.)

Each routine is checked against host-made tables (3,000 cases per arithmetic operation,
2,000 per memory function, signed and unsigned, edge values: `tests/rt`, in both code
models). The 32-bit multiply's low product is unrolled, and the divisions take a shorter
round when the divisor is below $8000. A structure copy is inline, with MVN.

Advice, from these numbers and the generated code:

- Prefer **`unsigned int`** (16 bits) for counters, indexes and loop variables: the
  65816's own size. Signed division and right shifts of `int` need extra code.
- Avoid **`long`** in inner loops: every 32-bit operation is two 16-bit ones, and a
  multiply or divide is a call (a 32-bit multiply about 0.1 ms with its loop, table above).
- Avoid **float** in anything that runs every frame (20 to 300 microseconds an operation,
  milliseconds for `sin` or `pow`); fixed point (`hgame.h`'s `hg_fix8`, `hg_fix16`) is
  much faster.
- `memcpy`, `memmove`, `memset` move blocks with MVN/MVP (about 12 cycles a byte, 1000
  bytes in about 0.8 ms); `hz_far_copy` too.
- `-O2` (the default) is the fast one; `-O1` drops the loop optimisations (sum16 above).
