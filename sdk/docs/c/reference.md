# C reference

How a C program is laid out in memory, its types, far memory, the calling convention
(for assembly), inline assembly, the C library on Horizon, floating point, `long long`,
`setjmp`, syscalls from C, the stacks, compiler notes and performance. The compiler
itself (its passes, options by purpose, its output, how to report a fault):
[compiler.md](compiler.md). Every header and function: [library.md](library.md). Getting
started: [getting-started.md](getting-started.md). Window applications (the controls
library, `hui.h`): [apps.md](apps.md). Games: [games.md](games.md). Porting:
[porting.md](porting.md).

- Compiler: **cc816**, the SDK's own (`sdk/c/cc816`, Python 3, writes ca65 assembly). It
  needs Python 3 and cc65's ca65, ld65 and ar65. Nothing is downloaded.
- Driver: `sdk/c/bin/hcc` (`hcc -h` lists the options).
- Headers: `horizon.h` (syscalls, blocks, helpers), `hui.h` (the controls library:
  [apps.md](apps.md)), `hgame.h`, `conio.h`, `joystick.h` ([games.md](games.md)),
  `dirent.h`. The C library's are in `sdk/c/cc816/include`: `stdio.h`, `stdlib.h`,
  `string.h`, `fcntl.h`, `unistd.h`, `math.h`, `float.h`, `ctype.h`, `time.h`, `errno.h`,
  `stdint.h`, `inttypes.h`, `stdarg.h`, `setjmp.h`, `limits.h`, ...
- Library: `sdk/c/lib` (the C library, in C) and `sdk/c/rt` (the startup and the runtime,
  in assembly). hcc builds them for each code model into `sdk/c/build/lib/small/` and
  `sdk/c/build/lib/large/`, and for the far data model into `sdk/c/build/lib/large-far/`.
- Make: `sdk/c/c.mk` (a program's Makefile is three lines).

cc816 has floating point (IEEE 754 single precision; `double` is the same 32-bit format),
`long long` (64 bits), `setjmp`/`longjmp` and inline assembly (below). It has no 64-bit
`double` and no variable-length arrays. A program with more code than one bank holds is
built with the large code model (`hcc --code large`, "Code models", below).

## Memory

```
the small code model (the large one: "Code models", below)

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

Every data pointer is a 16-bit offset in the code bank. Globals, string constants,
`malloc` blocks and the locals that need an address (arrays, structures, `&x`) are all
there, so any pointer reaches any of them, and code reads them with 16-bit addresses
through DBR. The other locals are in direct-page registers or on the hardware stack.

- Code + constants + data + bss: 65,264 bytes ($0100-$FFF0) less the software stack,
  57,072 with the default 8,192.
- Heap: from the end of bss to the software stack's guard zone (a small program: about
  48,000 bytes).
- Software stack: `--stack N` bytes (512-32,768, even; default 8,192). Arrays, structures
  and locals whose address is taken.
- Hardware stack: about 32,000 bytes (from directly below the argument string to $0100).
- Direct page: $00-$77. 48 bytes of scratch registers, 48 callee-saved, the software
  stack pointer, the runtime helpers' words, the code bank's number.
- DBR (the data bank): the code bank.

`hcc` checks the sizes after linking and reports what does not fit, in bytes ("program
too big by N bytes: build with --code large" when the code is what does not fit). The
loader's own limits: the program's o65 is less than 64 KB, and code + data + bss fit in
$0100-$FFFF. Before Horizon 0.28 the whole file had to be less than 64 KB. Since 0.28 a
file may be larger: the loader reads only the o65 at its start. With `hcc --code large`
the code may also fill other banks. The rest of this layout stays as it is (the code bank
is then called the main bank).

## Code models

cc816 has two code models. Both have the same data: every data pointer is a 16-bit
offset in the main bank, and DBR is always the main bank. They differ in where the code
goes and in how functions are called.

- Code. Small (the default): in the code bank, with everything else. Large (`hcc --code
  large`): in the main bank while it has room, then in other banks of 64 KB (up to 64 of
  them).
- Calls. Small: JSR / RTS. Large: JSL / RTL, wherever the function is.
- The first argument. Small: at `3,s`. Large: at `4,s` (the return address has 3 bytes).
- A function pointer. Small: 16 bits, the function. Large: 16 bits, the function's entry
  in the main bank (the function itself, or a 4-byte thunk, a JML to it).
- Files. Small: NAME.PRG. Large: NAME.PRG, one file. When code went to other banks, they
  follow the o65 in the same file (Horizon 0.28 and later).
- Data, constants, bss, heap, software stack: the code bank in the small model, the main
  bank in the large one (the same).
- `__CC816_LARGE__`: not defined in the small model. Defined (1) in the large one, in C
  and in assembly (`ca65 -D`).

`hcc --code large` (or `HZ_CODE=large` in the environment, `HZ_CODE := large` in a
Makefile made with c.mk) builds a program in the large model. Nothing in the C changes.
Every file of a program must be built for the same model, libraries included. hcc builds
the C library, the game library and the controls library for both, and stops with an
error at an object made for the other model ("an object made for the small code model;
this program is linked for the large one").

### What goes where

**The main bank** (the .PRG, loaded by Horizon as any program) holds the startup, the
assembly (the C library's runtime: arithmetic, memory and string routines, floating point;
the syscall stubs; hgame's and the controls library's assembly; your `.s` files, except
their functions opened with `FUNC`: "Movable assembly", below), the C
functions that have inline assembly or are `naked`, the constructors and destructors
(`_INIT_n_name`, `_EXIT_n_name`), the loader of the other banks (`xload.c`, with
`misc.c`: they run before the other banks are there), the thunks, the constants (string
literals, `const` tables, floating-point constants), the initialised data, the bss, the
heap and the software stack. These are limited to the main bank, as in the small model.
`__far` objects are not: they go to banks of their own ("Far objects", below).

**The other C functions can move**: the program's and the libraries' alike (the C
library's, hgame's, the controls library's C part), and assembly functions opened with
`FUNC` (rt/model.inc). cc816 puts each one in a segment of its own. In a file of more than
100 of them, runs of consecutive functions share one, because ca65 and ar65 take only so
many segments a module. hcc places them after it has linked the rest: first in the main
bank, as long as it has room (it keeps `--heap N` bytes free for `malloc`, 4096 by
default), then in other banks, each function in the first bank with room, in the order
of the files and of the functions in them. A function must fit in one bank (65,535
bytes). When everything fits in the main bank, nothing follows the o65 and nothing is
loaded at the start: the program runs on any Horizon, as in the small model.

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
constants, data, bss)`, the room the main bank needs wherever hcc puts the code. For
Digger that is 33,488 bytes (8,241 of code, 7,764 of constants, 2,142 of data, 15,341 of
bss).

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
(each object in one bank, as many banks as they need, after the code banks). These banks
are in the program file and loaded at the start with the code. Nothing of them is in the
main bank. In the small model a far object stays in the code bank. The same source builds
in both.

Its elements are reached through far pointers: `level[n][i]` builds the far address and
reads through it, as `p[i]` with a `__far` pointer does (a little slower than a main-bank
array: a 32-bit address). A pointer to it is a far pointer (`&level[3][0]` is `const
unsigned char __far *`). Assigning it to a near pointer keeps the offset only (cc816
warns). A far object may hold pointers (near ones, to main-bank data or functions, and far
ones, to other far objects). An object is at most 65,535 bytes, as any. In a library built
split (one module a function: the SDK's own libraries) far objects stay in the main bank.

Limits:

- Code: the main bank's room, plus 64 banks of 64 KB (about 4 MB). An 8 MB machine has
  about 80 free banks when nothing else runs.
- One function: 65,535 bytes.
- The main bank: startup + the libraries' assembly + `.s` files (but not their `FUNC`
  functions) + functions with inline assembly + constructors + thunks (4 bytes for each
  function in another bank whose address is used) + constants + data + bss + 4 KB of heap
  (`--heap N`) + the software stack (`--stack N`) must fit in 65,264 bytes.
- Far data: `__far` objects, up to 64 banks together with the code banks.
- The .PRG file: its o65 part (the main bank and its relocations) below 64 KB, because
  Horizon's loader reads only the first 65,535 bytes of a larger file. The whole file has
  no limit.
- Horizon: 0.28 or later when code went to other banks (it loads a file of 64 KB or more,
  and gives the program its own path).

### Loading

A large program is one file, NAME.PRG. It starts with the main bank, an ordinary o65
file. The other code banks follow it in the same file. Copy the one file to the card, into
any folder.

Horizon loads NAME.PRG as it loads any program. Since Horizon 0.28 the loader takes a
file of 64 KB or more: it reads only the first 65,535 bytes, where the o65 must lie, and
never loads what follows the o65.

Before the constructors run, the startup (`sdk/c/lib/xload.c`):

1. gets the path of its own file from Horizon (`task_path`, Horizon 0.28) and opens it.
   This works however the program was started: from the shell by any path, from the
   Desktop's Programs menu, or from Files.
2. reads the file's last 8 bytes: where the other banks start, and `HZPX`.
3. checks the header there: the number of banks and the stamp of the build (hcc writes the
   same stamp into the main bank). A file put together from two builds is rejected.
4. takes a bank for each image (`hz_bank_alloc`) and reads the image into it.
5. patches the bank bytes: the bank of each JSL to a function in another bank (and of
   the MVN of a structure copy), in the main bank and in the others. The banks are known
   only at this point.
6. checks that the data ends directly before the last 8 bytes, and closes the file. Then
   the constructors, `main` and the rest run as usual.

In the emulator a program of 45 KB with 165 KB of other banks starts in about 0.15 s (a
small program in 0.01 s). Horizon frees the banks when the program ends, as all of a
program's banks.

On a Horizon before 0.28 a large program with other banks does not start: the file is
64 KB or more, so the loader rejects it ("not a Horizon program"). If the whole file is
below 64 KB, the old loader takes it, and the startup stops with "needs Horizon 0.28 or
later".

If something is wrong, the program prints one line on the console and ends with exit
code 1 before any of its own code runs. When the window system runs, the line is also
shown in a small window (a key or a click closes it). The messages and their causes:

- `GAME.PRG: the program file is cut short or damaged (its code banks): copy it again`:
  the file was cut (a copy that did not finish) or changed.
- `GAME.PRG: its code banks are of another build of the program: build it again`: the
  file was put together from two builds.
- `GAME.PRG: not enough memory: no free 64 KB bank for the program's code`: the machine
  has not enough free banks (close a program).
- `GAME.PRG: needs Horizon 0.28 or later (a program with several code banks)`: an older
  Horizon (it has no `task_path`).
- `GAME.PRG: cannot find its own file ...`, `cannot open its own file ...`, `cannot read
  the program file (a card error)`: the file was removed while the program started, too
  many open files, a card error.

### File layout

In the order of the file:

1. The o65: the main bank, as in any program, below 64 KB.
2. Header, 12 bytes: `HZPX`, version 1, n (the number of banks), 0, 0, the stamp (u32).
3. n x u32: each bank's image size.
4. The images: bank 1, bank 2, ..., each from offset 0 of its bank.
5. u16: the number of relocation groups.
6. The groups. Each: u8 where (0 the main bank, k bank k), u8 to (the bank whose number is
   stored), u16 count, then count u16 offsets: the bytes that get that bank's number.
7. The trailer, 8 bytes: u32 the offset of the header in the file (= the o65's length),
   then `HZPX`.

hcc makes it with ld65 alone (`sdk/c/tools/hzlarge.py`, "Program files" below). Programs
built with the SDK before Horizon 0.28 had the part after the o65 in a second file,
NAME.PRX. hcc does not write it and programs do not read it: build such a program again.

### Costs

Measured in the emulator, the same programs in both models. The large model's runs put
every function that can move in another bank, the worst case (in the large model every
call is a JSL anyway). Small model first, then large:

- bench (-O2), sieve, sum16, mul32, fib22, strs, structs: 809, 296, 1,277, 388, 994,
  670 ms. Large: 808, 300, 1,290, 430, 1,000, 678 ms.
- bench -O1: 809, 476, 1,280, 400, 999, 659 ms. Large: 808, 490, 1,287, 417, 996, 674 ms.
- fbench, mandel, sincos, sqrt, expow, conv: 2,140, 1,640, 366, 1,947, 1,065 ms. Large:
  2,140, 1,640, 368, 1,939, 1,070 ms.
- hello (code + constants): 8,083 bytes (file 8,304). Large: 8,213 (file 8,598).
- window: 10,002 (file 10,227). Large: 10,153 (file 10,579).
- bench: 9,733 (file 9,958). Large: 9,903 (file 10,369).
- fbench: 25,802 (file 26,036). Large: 26,421 (file 27,799).
- viewer (controls library): 25,792 (file 26,443). Large: 26,038 (file 27,066).

The timer counts in steps of about 10 ms. The sizes are `hcc --map`'s with each model's
default placement: in the large model all of these fit in the main bank. A call costs 2
cycles more (JSL against JSR), a call through a pointer 6 more (`__icall`; 10 when the
function is in another bank, for its thunk's JML), and each call site 1 byte more. The
arithmetic helpers are called with JSL too (a 16-bit division about 14 cycles more).
Calls between banks cost no more than calls inside one: all are JSL. The .PRG grows a
little more than the code, because each JSL to a function in the main bank is a
relocation for Horizon's loader (2 or 3 bytes of the file). A program whose code moves
also has the loader in its main bank (about 2 KB of code, 0.5 KB of constants and 900
bytes of bss). One whose code all fits in the main bank has none.

## Far data model

`hcc --code large --data far` builds a program whose plain data pointers are **far** (32
bits: offset, bank, 0), as a DOS program of Watcom's or Microsoft's large model has them
(`wcc -ml`). Its heap is in other banks, its string literals and `const` tables are in
banks of far data, and the C library takes and returns far pointers. The model is for
porting DOS-era "large model" C without rewriting its declarations (the acceptance test:
`ports/xcom`, 49,000 lines of Watcom C). The model described above is called **near
data** from here on. It is the default and does not change.

### Near and far data

Near data (the default) first, then far data (`hcc --data far`):

- Needs: near data works with either code model. Far data needs `--code large`: far data
  banks are loaded by the large model's loader, and a program that needs far data is a
  big program. hcc rejects `--data far` alone.
- `char *p`: 16 bits, an offset in the main bank. Far data: 32 bits, offset, bank, 0.
- `char __near *p`: the same as `char *p` (`__near` has no effect). Far data: 16 bits, an
  offset in the main bank.
- `char __far *p`: 32 bits in both (with far data, the default spelled out).
- Function pointers: 16 bits (the main-bank entry) in both.
- `malloc`: the main bank's heap. Far data: far, the main bank's free room first, then
  banks of 64 KB.
- String literals, `const` objects: the main bank. Far data: banks of far data.
- Other globals and statics: the main bank in both (with far data: near, absolute
  addressing, as fast as near data), unless `__far`.
- `__CC816_FAR_DATA__`: not defined. Far data: defined (1) in C and in assembly (`ca65
  -D`; `model.inc`: `FARDATA` 1, `PTRSZ` 4).
- Libraries: `build/lib/small`, `build/lib/large`. Far data: `build/lib/large-far` (the C
  library and hgame; the controls library is not built for it).

`HZ_DATA=far` in the environment (`HZ_DATA := far` with c.mk) does the same as the option.
Every object of a program must be made for the same model. cc816 marks each object
(`__cc816_large` or `__cc816_largefar`), and the link of a near-data object into a
far-data program, or the other way round, stops with "an object made for the large code
model; this program is linked for the large code model with far data (hcc --data far):
build every file with the same --code and --data (a library too)". A `.s` file carries no
mark: it must follow the model's convention (below).

### Pointers

A far pointer is 4 bytes: the offset (16 bits), the bank (8 bits) and a zero byte, the
same layout `__far` pointers have in every model. Code reads through it with `[dp],y` (the
pointer in a direct-page register: the 65816's own long indirect addressing). The rules:

- An object never crosses a bank (a `malloc` block, a far object, a frame), as a DOS
  object never crosses a 64 KB segment. An object is at most 65,535 bytes.
- Arithmetic (`p + i`, `p++`, `p - q`) follows one of two rules, the default or an option.
  - The default: a pointer value is its 24-bit address. `p + n`, `p - n`, `p++`, `p +=
    n` and `&p[n]` add to the whole address. A carry goes into the bank, as with `__far`
    pointers in every model, so a pointer one past an object that ends at a bank's last
    byte is the next bank's offset 0 (greater than the object's start) and one before an
    object at offset 0 is the bank before (smaller). An `int` is sign-extended first, an
    `unsigned` zero-extended, a `long` added whole. For every pointer that stays inside
    its object, one past its end or one before its start, this is the same as DOS's
    offset-only arithmetic. An element `p[i]` (an access, not a pointer value) is reached
    as DOS reaches it: an unsigned `i` in Y (`[p],y`), a signed one added to the offset
    alone, with its constant part (`p[d + 1]`). The element is in `p`'s object, so in its
    bank, and this is cheaper than widening `i` to 32 bits. `p - q` is the difference of
    the offsets (16 bits, `ptrdiff_t`). The two rules differ for an `int` that
    overflowed. DOS code that adds a 16-bit result of 32,768 or more meant as unsigned
    (`p + 4 * T` with `enum { T = 10000 }`: 40,000 is -25,536 in a 16-bit `int`) reached
    offset 40,000 on DOS, whose offset wraps. Here the pointer goes 25,536 bytes back, out
    of its object and possibly out of its bank. `-Woverflow` reports such a constant (and
    `-w` does not silence it: "Errors and warnings"). A variable one cannot be detected.
    Write `4u * T`, or build with `-ffar-wrap`.
  - `-ffar-wrap` (hcc and cc816): the offset alone, the bank never changes, as with DOS's
    far pointers. `p + n`, `p - n`, `p++`, `p--`, `p += n`, `&p[n]`, `&p->m`, and an
    element `p[i]` with any variable index, signed or unsigned (`p[0xFFFF]` is `p[-1]`),
    or a constant one that is negative or 32,768 or more, compute the offset modulo 65,536
    and keep the bank. The integer's width does not matter: a `long` adds its low word (as
    Watcom's `far + long`). So an `int` that overflowed lands where it did on DOS, for
    every object inside a bank (every object is). A constant offset of 0 to 32,767
    (`p->m`, `p[3]`) is reached with Y as before: it cannot leave an object that lies in
    one bank. The cost to a program: one past an object that ends at a bank's last byte
    wraps to the bank's offset 0, and one before an object at offset 0 to the bank's
    offset $FFFF. A loop `for (q = a; q < a + n; q++)` over such an object, or one that
    walks down past its start, does not end. DOS had the same rule and the same limits,
    and its compilers and allocators kept objects off the segment's ends. The heap's
    blocks never touch either end of a bank (`malloc`'s banks are used from offset 2 to
    $FFFD, a block's bytes start after its 4-byte header), nor does anything in the main
    bank. A bank from `hz_far_alloc` or a far data bank does start at offset 0 and may end
    at $FFFF. To cross banks on purpose, build the address: `hz_farptr(bank, off)`, or
    `(char *)((unsigned long)p + n)`. It is a per-file option: the arithmetic follows the
    file's option, pointers mean the same in both, and files built either way link
    together (the SDK's libraries are built without it). `__CC816_FAR_WRAP__` is defined.
    The code is a little smaller and quicker (`p++` is one `inc` of the offset, a signed
    index is not widened).
- Compares: `==`, `!=`, `<` ... compare the whole 32 bits (the bank first). Pointers into
  one object compare as their offsets do.
- NULL is 0 (bank 0, offset 0: nothing of a program is there). A near pointer converts to
  a far one implicitly: its bank is the main bank (`__cbank`). A null near pointer stays
  null. A far pointer converts to a near one by keeping the offset (cc816 warns:
  `-Wfar-pointer`, `-Wfar-cast`).
- Integers: `(unsigned long)p` is the 24-bit address (bank << 16 | offset). `(char
  *)0x050000L` is bank 5, offset 0. `(unsigned)p` is the offset. A 16-bit integer
  converted to a far pointer is widened as an integer (bank 0): write `(char
  *)hz_farptr(bank, off)` or a 32-bit value.
- Types: `sizeof(void *)` is 4, `size_t` is 16 bits (`unsigned int`) and `ptrdiff_t` 16
  bits (`int`), as in DOS's large model (one object is at most 65,535 bytes). `intptr_t`
  and `uintptr_t` are 32 bits (`long`, `unsigned long`: they hold a pointer). `PRIdPTR` is
  `"ld"`.
- Structures that hold pointers grow: each pointer member takes 4 bytes (structures are
  packed, no padding). Code that reads a structure with pointer members from a file
  written by DOS (which wrote them as 4-byte far pointers too) reads the same layout.
- DOS's segment:offset (`MK_FP`, `FP_SEG`, `FP_OFF`) has no meaning on the 65816. A port
  maps it (ports/xcom's `compat/xdos.h` models the DOS megabyte as an arena of banks).
  `HZ_BANK(p)`, `HZ_OFF(p)` and `hz_farptr(bank, off)` are the 65816's own, and cost a
  word move each: the representation is the 24-bit address.
- Not supported: `huge` (objects over 64 KB, pointer arithmetic that normalises across
  segments). It would need 24-bit index arithmetic on every access. `huge` and `__huge`
  are accepted as `__far` in the compatibility spellings (below).
- printf `%p` prints the 24-bit address as `0x` and 6 hexadecimal digits (`0x05a3f0`;
  near data: 4 digits). `scanf %p` reads it back. `%s` takes a far string. Among variable
  arguments a data pointer is 4 bytes, and a `__near` one is widened to a far one (as a
  `float` goes as a `double`): read it with `va_arg(ap, char *)`, not `char __near *`. A
  function pointer stays 2 bytes there.
- Function pointers are as in the large code model: 16 bits, the function's entry in the
  main bank. Converting one to `void *` gives a far pointer into the main bank, and back.

### Where objects live

The direct page, both stacks, the runtime, the loader, the thunks and every `__near`
object are in the main bank. So are a function's locals: `&local` (an array, a structure,
a local whose address is taken) is a far pointer whose bank is the main bank, which the
code takes from `__cbank` (a direct-page word the startup sets, because the bank is known
only at load time; one `lda __cbank`).

Each object is placed by its declaration, when the file is compiled. Where it goes, and how
the code reaches it by name:

- A string literal: far data, long addressing (`lda f:L_S3,x`).
- A `const` object (the object itself const: `const int t[]`, `const char *const
  names[]`; not `const char *names[]`, whose elements may change): far data, long
  addressing.
- An object declared `__far`: far data, long addressing.
- An object declared `__near`: the main bank, absolute addressing (`lda _x,x`).
- Any other global or static: the main bank, absolute addressing, as fast as near data.

**Far data** is the large code model's banks of far objects. hcc fills them after the code
banks (first fit, in the order of the files, an object in one bank, an object larger than
a bank an error), and the startup loads them from the program file with the code. A
literal or a `const` table costs nothing in the main bank. Long addressing (`lda
f:name,x`, 4 bytes, 5 cycles) is one byte and one cycle more than absolute addressing, so
a table in far data is read about as fast as one in the main bank. Its address is a far
pointer to its bank. Writable globals stay in the main bank because they are the hot
scalars and arrays of most programs, and absolute addressing has the forms long
addressing lacks (`inc`, `stz`, `ldx`, `ldy`, `,y`).

**Consistency between files.** A file that only declares an object (`extern`) reaches it
with absolute addressing only when its declaration marks the object as near (not `const`,
not `__far`). Otherwise it uses long addressing, which reaches either place (the bank byte
of a main-bank object is relocated by Horizon's loader). So `extern const char tbl[];` in
one file and `const char tbl[] = ...;` in another always agree, and the only declarations
that must match are the C ones (`const` and `__far` in the extern declaration as in the
definition). The C library (built split) keeps its own constants in the main bank: it is
small, and long addressing finds them there too.

**Control.** `__far` moves a writable object out of the main bank (put it on every
declaration of it, the header's too). `__near` keeps a `const` table in it (for a hot
table read with `,y`). There is no size threshold (Watcom's `-zt`: "objects of N bytes or
more are far"): a file that sees only `extern int t[];` does not have the size, so the
declaration alone must determine how the object is reached. The attribute on the
declaration does this, and `hcc --sizes` shows which objects are worth it. `hcc --map`
prints the main bank's parts and the far data banks. `hcc --sizes` prints every object and
every function, its size and where it went, biggest first (the budget of the main bank,
which ports need).

**The main bank's budget.** startup + runtime + the libraries' assembly + resident code +
thunks + writable globals + `--heap` + the software stack (`--stack`) must fit 65,264
bytes. The heap needs no room there (it continues in other banks): `--heap N` with `--data
far` is only the part of the heap kept in the main bank (default 1024).

### Heap

`malloc`, `calloc`, `realloc` and `free` return and take far pointers. The heap is a list
of arenas: the main bank's free room first (from the end of bss to the software stack's
guard zone), then whole banks taken from Horizon (`hz_bank_alloc`) when no arena has room,
each a first-fit free list. A block is at most 65,528 bytes and never crosses a bank
(DOS's far heap had the same 64 KB limit). A bank whose blocks are all freed goes back to
Horizon while another bank of the heap is empty too. One empty bank is kept, so a program
that takes and frees a big block in turn does not call Horizon each time. Every bank goes
back at the program's end. `malloc` returns NULL with `errno` ENOMEM when no arena has
room and Horizon has no free bank. `hz_heap_free()` counts the free bytes of every arena
and `hz_heap_peak()` the most in use at once (both `unsigned long` with far data),
`hz_heap_largest()` the biggest `malloc` that would work now (65,528 while Horizon has a
free bank). `hcc --debug` reports the peak at exit. There is no near heap: a `__near`
object is a global or a local. (`lib/malloc.c`: 64 arenas at most, about 4 MB.)

### C library with far data

The library is the same source built a third time. Every function that takes or returns an
object pointer takes a far one (`string.h`, `stdio.h` and `FILE *`, `stdlib.h`, `qsort`
and `bsearch` with far elements, whose comparison function gets far pointers, `printf`'s
`%s` and `%p`, `scanf`'s pointers, `setjmp` (a `jmp_buf` anywhere), `time.h`, `dirent.h`,
`horizon.h`'s helpers and syscall functions). Its assembly (`rt/mem.s`, `setjmp.s`, the
syscall stubs) has a far-data form (`model.inc`'s `FARDATA`). `memcpy`, `memmove` and
`memset` are MVN/MVP between any two banks (the instruction built with both banks, about
7 cycles a byte). `strlen`, `strcpy`, `memcmp` read through `[dp],y`. A syscall takes a
pointer as X = offset, Y = bank (ABI.md), so the stubs pass a far pointer as it is: every
syscall takes a pointer into any bank the program owns. The POSIX `read` and `write` move
the bytes directly between the card and far memory (one `hz_read` / `hz_write` for 512
bytes or more, at most 32,767 a call as in every model). Smaller reads go through the
read-ahead. hgame is built for the far data model too. The controls library (`hui.h`) is
not (hcc rejects `--ui` with `--data far`): a window application has no need of DOS's
model.

### Calling convention with far data

As in the large code model ("Large code model", below), with one change: a data pointer
argument is 4 bytes (offset, bank, 0: low word first), and a pointer result is in A
(offset) and X (bank). `ARGS+4,s` is the second argument when the first is a pointer. A
structure passed by value or returned is still a near address of the caller's copy (in its
frame). `va_list` is a far pointer, as always. An assembly function for both data models
uses `model.inc`'s `PTRSZ` (2 or 4) for the offsets and `FARDATA` for the code that
differs:

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

DOS compilers' keywords are accepted in every model, so that ports need not define them:
`far`, `_far`, `__far` (= `__far`), `near`, `_near`, `__near` (= `__near`), `huge`,
`_huge`, `__huge` (= `__far`: see `huge` above), and `__cdecl`, `_cdecl`, `__pascal`,
`__loadds`, `__saveregs`, `__interrupt`, `__export`, `_Seg16` (read and ignored: there is
one calling convention, and an interrupt function cannot be written in C here). The
lower-case `far`, `near` and `huge` are keywords only with `-fdos-keywords` (hcc and
cc816), since they are ordinary names in other C. Also:

- `T __far *a, __far *b;` and `int n = 1, __far *p;`: a qualifier before a later
  declarator's `*` applies to that declarator (as in Watcom and Microsoft C).
- `void (__far *f)(void);` (a far function pointer): accepted, `__far` ignored with a
  warning (`-Wfar-function`). A function pointer is the main-bank entry in every model.
- `#pragma aux name = "..."` (Watcom's inline machine code) and every other pragma cc816
  does not recognise: a warning (`-Wunknown-pragmas`), with a note on `aux` ("Watcom inline
  code: name needs a C body"). `#pragma pack(1)` / `pack()` / `pack(push, 1)` /
  `pack(pop)` are accepted silently (structures are always packed). `pack(n)` with n
  above 1 gives a warning (cc816 cannot pad).

### Not supported with far data

- `huge` pointers and objects of 64 KB or more (above).
- The small code model (`--data far` needs `--code large`), the controls library.
- Mixing objects of the two data models in one program.
- An object reached through near addressing in one file and placed far by another file's
  declaration: give the extern declarations the same `const` and `__far` as the definition.
- A `__far` object without an initialiser still takes its bytes, zeros, in the program
  file. A big zeroed buffer is better from `malloc`.

### Far data costs

The same C with near data (`--code large`) and with far data (`--code large --data far`),
in the emulator (`tests/run.py`'s bench and fbench, `tests/bench/farbench.c` for the
pointer shapes, in cycles a step: a byte, an element, a call). Near data first, then far
data:

- bench, sieve, sum16, mul32, fib22, strs, structs (ms): 810, 298, 1,279, 420, 849, 675.
  Far: 810, 296, 1,287, 416, 954, 740. strs (pointers and bytes) +12 %, structs +10 %.
- fbench, mandel, sincos, sqrt, expow, conv (ms): 2,150, 1,650, 370, 1,950, 1,065. Far:
  2,140, 1,647, 349, 1,940, 1,070. The same.
- copy, `while ((*d++ = *s++))`: 85. Far: 96, +13 %.
- sprite, `if (*s) d[k] = *s;` (a 32 x 40 masked sprite): 95. Far: 105, +11 %.
- index, `s += a[i]` of a global array: 98. Far: 103. The array is near: its name is
  absolute addressing.
- pindex, the same through a pointer parameter (`int i`): 171. Far: 205, +20 %.
- member, `p->x += p->y + i` along an array of structures: 116. Far: 125, +8 %.
- call, `d = pass(d) - 1`, a pointer argument and result: 95. Far: 188. 4 bytes pushed,
  A and X back, 32-bit arithmetic.
- `memcpy`, `strlen` (4,000 bytes): 12, 12. Far: 10, 10. MVN either way, and `strlen`
  reads two bytes a round.
- Program size, fbench, farbench: 27,881, 10,979 bytes. Far: 32,169, 18,703 (the far
  library's heap, stdio and printf with far pointers).
- XCOM-XT's code: 578,218 bytes (does not link: its data does not fit). Far: 732,183
  bytes in 12 banks, +27 %.

Arithmetic, calls without pointers and code that reads globals by name cost nothing.
Loops through pointers cost 8-20 % more, a call with pointer arguments about twice as
much, and code grows by about a quarter where pointers are everywhere. A byte read through
a far pointer is an 8-bit load (`sep`/`rep`: a 16-bit one could touch the next bank at a
bank's last byte). A far pointer stepped in place is `inc`, `bne`, `inc` (`p++`), and an
index through it is Y (`[p],y`) when it is unsigned, an add to the offset alone when it is
signed. Hot loops can take `__near` pointers to main-bank buffers, or move to assembly.

## Types

- `char`: 8 bits, **unsigned** (0-255; the library is built so). `signed char` for
  -128-127. `-fsigned-char` makes plain `char` signed.
- `short`, `int`: 16 bits, -32,768-32,767 (`unsigned`: 0-65,535).
- `long`: 32 bits.
- `long long`: 64 bits. `int64_t`, `uint64_t`, `intmax_t`, `LLONG_MAX` ...
- `float`, `double`, `long double`: 32 bits (all three), IEEE 754 single precision
  (24-bit significand: about 7 decimal digits, 1.2e-38 to 3.4e38, denormals down to
  1.4e-45).
- Data pointer: 16 bits, an offset in the main bank. `__far` pointers are 32 bits
  (offset, bank, 0). With far data (`hcc --data far`) 32 bits, `__near` ones 16 ("Far
  data model").
- Function pointer: 16 bits, the function (small model) or its entry in the main bank
  (large model).
- `size_t`, `ptrdiff_t`: 16 bits, `unsigned int` and `int`. One object is at most 65,535
  bytes (in both data models).
- `intptr_t`, `uintptr_t`: 16 bits (`int`, `unsigned int`). With far data 32 bits (`long`,
  `unsigned long`: they hold a pointer).

Structures are packed (no padding): the parameter blocks in `horizon.h` match ABI.md byte
for byte (each has a compile-time size check). Bytes are little-endian.

Predefined macros: `__CC816__`, `__65816__`, `__HORIZON__`, `__ATARI816__`,
`__CHAR_UNSIGNED__` (not with `-fsigned-char`), `__CC816_LARGE__` in the large code
model, and `__CC816_FAR_DATA__` in the far data model.

## Pointers, banks and far memory

An object (an array, a structure, a `malloc` block) must not cross a bank boundary: a
pointer's arithmetic is 16-bit. A bank is 64 KB. Horizon gives a program more of them
with `bank_alloc` (`hz_mem_info()` returns how many are free: 92 banks in all on the 8 MB
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
and write with long addressing. A near pointer converts to a far one implicitly (its bank
is the main bank, and a null pointer stays null), so `(unsigned long)p` is the whole
24-bit address of p and `HZ_BANK(p)` of any pointer is right. A far pointer converted to a
near one keeps its offset only. An integer converts to a far pointer as it is: `(char
__far *)0x050000L` is bank 5, offset 0 (`hz_farptr(5, 0)` is the same). A `long` added to
a `__far` pointer is added whole, in both data models. A byte read through a far or a
`volatile` pointer is an 8-bit load, so a byte at a bank's last address (`b[65535u]`) does
not touch the next bank. Code that keeps far addresses in plain pointers
(`(char *)hz_far_alloc()`, `(const char *)farbuf`) must use `__far` instead, or copy the
data into the main bank first (`hz_far_copy`): see [porting.md](porting.md).

### Negative indexes

A near pointer's arithmetic wraps in its bank, as C on a 16-bit machine expects: `p[-1]`,
`p[i]` with `i = -1`, `*(p - n)`, `a[d + 1]` with `d = -1`, and `p[u]` with an unsigned
`u` of 65535 (`p + 0xFFFF` is `p - 1`) all reach the element before. The 65816's index
registers do not wrap: abs,X, abs,Y, (dp),Y and (sr,S),Y add X or Y to their 16-bit base
in 24 bits, so a base plus an index past $FFFF is the next bank. cc816 keeps an element's
access in an index register only when it cannot carry:

- an element of a local array or structure (the software stack): Y is its offset from
  `__sp`, always.
- an element of a global (`abs,x`): when the base is the object's start or below it, or
  the index is known to be a non-negative offset. Otherwise X is the index plus the
  constant offset (`a[d + 1]`: `lda d ; clc ; adc #2 ; tax ; lda a,x`).
- through a near pointer (`(p),y`): when the index is known to be a non-negative offset
  (and stays one with the constant part: `p[i - 1]` with `i` known to be 1 or more).
  Otherwise the address is added in 16 bits and read as `(__h2)`: `lda p ; clc ; adc i ;
  sta __h2 ; lda (__h2)`, about 10 cycles more than `ldy i ; lda (p),y`.

A non-negative offset is an index of an array object (`a[i]`, `a[i][j]`, `s.m[i]`,
`p->m[i]`, `a[n].x`: C keeps it inside its array, so 0 or more). This does not hold with
a positive constant part, `a[d + 1]`, where `d` may be -1. An index outside its array,
`a[2][-1]` for `a[1][5]`, is not C and may carry: write such code through a pointer,
`(&a[2][0])[-1]`. The optimiser can also prove an offset non-negative: a constant below
32,768, an `unsigned char`, a mask (`i & 15`), a right shift, an unsigned quotient or
remainder, a value a branch has compared (`i >= 0`, `i < 100` unsigned), and sums,
products and left shifts of those, among them a loop counter that starts at 0 or more and
only counts up (`for (i = 0; i < n; i++) p[i]`), and one that a compare keeps at 0 or more
(`while (--n >= 0) p[n]`). An `int` parameter or a value loaded from memory is not, nor an
`unsigned` one (it may be a negative index in disguise). In a loop that matters, make the
index an `unsigned char`, mask it, or count up from 0. A member's constant offset in Y
(`p->m`, `p[i].m`) cannot carry: no object crosses the top of a bank. Through a far
pointer the index is part of the 32-bit address ("Far data model"). `--log-bankwrap` of
emu816 (`EMU816_ARGS=--log-bankwrap`, or `run816.py --log-bankwrap`) reports every indexed
access in a program's bank that carries into the next one.

## Calling convention (for assembly)

- This is the small code model, the default. The large one: "Large code model", below.
- Functions are called with **JSR** and return with **RTS** (a program's code is all in
  its code bank). On entry and exit A, X and Y are **16-bit** (M = X = 0), D = 0, DBR =
  PBR = the code bank. Keep D and DBR.
- Every argument is on the hardware stack, pushed last first: at entry the first is at
  `3,s` (above the 2-byte return address), the next ones after it. Each takes 2 bytes
  (`char`, `short`, `int`, pointers, function pointers), 4 (`long`, `float`, `double`,
  `__far` pointers: offset, bank, 0) or 8 (`long long`: like two `long`s, the low word
  first, at the lowest address). The caller removes them. A structure argument is passed
  as the address of a copy the caller made (2 bytes). A structure result is written
  through a hidden first argument (the address of the caller's space), which is also
  returned in A. Variable arguments are the same (`va_list` is a far pointer into the
  stack), except a structure: among the variable arguments it is its bytes themselves,
  padded to an even size (so `va_arg(ap, struct s)` reads it).
- The result is in A (16-bit and smaller) or A/X (32-bit: A the low word; a `float` or
  `double` too, as its IEEE bits, the sign in bit 15 of X). A `long long` result is in
  the direct page, 8 bytes at `__h0`: `__h0` the low word, `__h0+2`, `__h1`, `__h1+2` the
  high word (A and X are then undefined).
- A C function's frame: under the arguments, the callee-saved registers it uses, then
  its spill slots (values live across calls), all read as `n,s`. That addressing reaches
  255 bytes, so a function whose slots would lie further keeps the farthest of them in its
  software-stack frame ("Old C", "Big functions"). Since the callee reads its parameters
  from the top and the caller removes what it pushed, arguments beyond the parameters are
  harmless (`-fextra-args`).
- The order of evaluation of the arguments is left to right by default, right to left
  with `-fargs-right-to-left` (DOS's compilers' order). Either way they are pushed last
  first and lie on the stack as above: the order of evaluation is not tied to the pushes
  (cc816 computes each argument into a register, then pushes them all at the call).
- Registers (direct page, `.importzp` them): `__rg` is 96 bytes. `__rg+0` to `__rg+47`
  may be changed by any function, `__rg+48` to `__rg+95` must be kept (save and restore
  what you use). `__h0`, `__h1`, `__h2`, `__h3` (4 bytes each) and `__rv` (4) are scratch
  too (the runtime's helpers use them). Never change `__sp` (the software stack pointer)
  or `__cbank` (a word: the code bank's number).
- Names: a C name gets an underscore: `int add(int, int)` is `_add` in assembly. C's
  globals are in the code bank: absolute addresses (DBR) reach them.

The assembler is **ca65** (cc65's: `.p816`, `.a16`/`.a8`/`.i16` after `rep`/`sep`,
`.export`, `.import`, `.importzp`, `.segment "CODE"`/`"RODATA"`/`"DATA"`/`"BSS"`). A file
is one module for the linker: ld65 links a module when the program uses one of its names,
and then the whole module.

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

Build them with the C files: `hcc -o PROG.PRG main.c add3.s sum.s` (hcc takes `.s` files
beside the `.c` ones and assembles them with ca65). In C: `unsigned add3(unsigned a,
unsigned b, unsigned c); unsigned long sum(const unsigned *p, unsigned n);`
(`add3(1, 20, 300)` is 321, `sum` of {60000, 60000, 1, 2} is 120003). Bank bytes
(`#^label`, `.faraddr`) are relocated by Horizon's loader. The compiler's own output for
any C file is `hcc -S` (FILE.s next to it), or `python3 sdk/c/cc816/cc816.py -S file.c`.
Horizon's assembly libraries (ulib, the controls library) are linked directly into a
cc816 program. They share the direct page (ld65 places their zero page after cc816's
registers).

### Large code model

`hcc --code large` changes only the following. The rest above stays as it is.

- Functions are called with **JSL** and return with **RTL**: the first argument is at
  `4,s` (above the 3-byte return address). A `.s` function called from C ends with `rtl`.
  It calls a C function with `jsl _name` (any C function, wherever it is: hcc patches the
  bank; in a movable function, `CALL _name`: "Movable assembly", below). PBR is the bank
  of the code that runs. DBR is the main bank, always: keep it.
- hcc assembles `.s` files with `-D __CC816_LARGE__=1` and with `sdk/c/rt` on the include
  path. `.include "model.inc"` gives `ARGS` (3 or 4: the first argument's offset), `RET`
  (`rts` / `rtl`), `CALL name` (`jsr` / `jsl`) and `LARGE` (0 / 1), so one file suits both
  models: `lda ARGS+2,s` is the second argument. The C library's assembly is written so.
- A `.s` file's code is in the main bank (segment `CODE`): its labels are 16-bit
  addresses there as before. A function opened with `FUNC name` instead (rt/model.inc) can
  move as a C function does: "Movable assembly", below.
- A function's 16-bit address (a function pointer, what C's `&f` and `f` give) is its
  entry in the main bank: `__T_name` (`__T` before the assembler name). It is the
  function itself when the function is in the main bank, else a thunk (`jml _name`) that
  hcc writes. Use `__T_name` where assembly needs a C function's 16-bit address (`.addr
  __T_cb`, `lda #__T_cb`). `_name` alone is the function's code, which may be in another
  bank (hcc rejects `.addr _name` and `lda #_name` for such a function: "a value that
  depends on where code is ... its 16-bit address is __T_name"). For an assembly
  function, `__T_name` is made by hcc too.
- A call through a function pointer: the pointer (16 bits) into `__fpt`, then `jsl
  __icall` (X is changed). `__icall` (crt0.s) jumps to the entry, and the function
  returns directly to the caller.
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

### Movable assembly

In the large code model an assembly function can move as a C function does: hcc puts it
in the main bank while there is room, else in another bank, so it no longer counts in what
the main bank must hold. `FUNC name` (rt/model.inc) opens it. The macros, in the small
code model and in the large one:

- `FUNC _name`: small, `.segment "CODE"`, `.export _name`, `_name:`. Large, `.segment
  "F_name"` (a segment of its own, as cc816 gives each C function), `.export _name`,
  `_name:`.
- `RET`: `rts`, large `rtl`.
- `CALL x`: `jsr x`, large `jsl x` with its bank byte recorded (segment `XREL`) after a
  `FUNC`.
- `TAILJ x`: `jmp x`, large `jml x`, recorded the same way.
- `XBANK n`: nothing in the small model. Large: records the byte `n` bytes back as a bank
  byte of the program.
- `FNADDR _name`: `__T_name = _name`, large `.import __T_name`.

So one file serves both models. The name is a C name (`_name`). C declares and calls the
function as any other. The function ends at the next `FUNC` or `.segment`. A function's
code is at most 65,535 bytes.

Rules for a movable function:

- Data: DBR is the main bank, always. Absolute addressing of main-bank data (`lda
  _global`, `lda (__rg+0),y` with a near pointer) works wherever the function is. Data
  the function reads itself (`lda table,x`) must be in `RODATA` or `DATA`, not in its code
  segment: a data access reads DBR's bank, not PBR's.
- Calls and jumps out of the function: `CALL _name` (a C function, a runtime helper,
  another `FUNC`, `__icall` for a call through a pointer) and `TAILJ _name`. In a movable
  function hcc patches a bank byte only where it was recorded: a bare `jsl _name` or `jml
  _name` is an error ("a bank byte not recorded in XREL: hand-written assembly naming a
  bank in a movable function"). A call of Horizon at a fixed address needs no record.
- Inside the function: branches, `jmp label`, `jsr label` ... `rts`, and `jmp
  (table,x)` with the table in the same segment. PBR is the function's bank, and JMP,
  JSR and `jmp (abs,x)` use PBR's bank. A table's entries are `.addr label` (or `.word
  .loword(label)`): a label's 16-bit offset in the bank. A `jsr` or `jmp` to a label of
  another segment (`CODE`, another `FUNC`) is an error ("a JSR to ..., outside its
  segment" or "an address in the main bank").
- Other bank bytes: `lda #^name` (16-bit A: then `XBANK 2`), `lda f:name` (`XBANK 1`),
  `.faraddr name` (`XBANK 1`), a `jsl` or `jml` written out (`XBANK 1`), `mvn` / `mvp`
  with a program's bank (one `XBANK` for each bank byte). The main bank's number is also
  in the direct page: `__cbank`. Do not record a constant bank (Horizon's, the
  hardware's): hcc would patch it.
- Its address: the function's 16-bit address, for a function pointer or a callback, is
  `__T_name` after `FNADDR _name` (a thunk in the main bank when the function is in
  another bank). ld65 rejects `lda #_name` ("Range error": the function may be at a 24-bit
  address), and hcc rejects `.addr _name` in the main bank. `.addr _name` in another
  movable function is not detected (ld65 keeps the low 16 bits): use `__T_name`. Code that
  enters the function with JSR, a hardware vector, or another return convention: keep it
  in `CODE`.
- Direct page, registers, arguments: as in any function (the calling convention above).

hcc cannot detect a bank byte left unrecorded when it names the main bank (it is the same
in every trial link): use `CALL`, `TAILJ` and `XBANK` for every bank byte. `hcc --code
large --main-room 0` puts every movable function in another bank. A test build that way
finds the rest.

Example (`sdk/c/examples/asmfar`: a C program and its assembly, built for both models, and
for the large one with every function in one of three other banks):

```asm
        .include "model.inc"
        .importzp __rg
        .import _scale, _twice
        FNADDR  _twice                  ; __T_twice, twice's 16-bit address

; int asm_sum(const int *v, int n): twice(v[0] * scale + ... + v[n-1] * scale)
        FUNC    _asm_sum
        lda     ARGS,s
        sta     __rg+0                  ; v: main-bank data (DBR)
        ...
        jsr     times_scale             ; a subroutine in this segment: JSR is fine
        ...
        pha
        CALL    _twice                  ; a C function, wherever it is
        ply
        RET
times_scale:                            ; A * scale
        ...
        ldx     _scale                  ; a main-bank global
        ...
        rts

; int asm_op(int op, int a, int b): a jump table in the function's own segment
        FUNC    _asm_op
        ...
        jmp     (@tab,x)                ; read in PBR's bank: this segment
@tab:   .word   .loword(@add), .loword(@sub), .loword(@max)
        ...

        FUNC    _asm_twice_ptr          ; int (*asm_twice_ptr(void))(int)
        lda     #__T_twice
        RET
```

To make a `.s` file movable: `.include "model.inc"`, `FUNC` instead of `.segment "CODE"`
and the label for each entry point, `CALL` / `TAILJ` / `RET` for every `jsr`, `jmp`,
`rts` (`jsl`, `jml`, `rtl`) that leaves the function, `XBANK` after every other bank
byte, tables the code reads moved to `RODATA`. A subroutine several entry points share
goes in a `FUNC` of its own, called with `CALL` (it then ends with `RET`), or is copied
into each. `hcc --sizes` shows where each one went.

### Inline assembly

An `asm` statement puts ca65 text into the compiler's output as it is. `asm`, `__asm__`
and `__asm` are the same. `volatile`, `inline` and `goto` after them are read and
ignored. The text is a string. Several lines are joined with `\n` (adjacent strings are
one string, as always in C):

```c
asm("\tsei");                                /* one instruction */
asm volatile("\tlda #1\n"
             "\tsta _flag");                 /* two lines */
```

**Placement.** In a function, as a statement. At file scope, between functions: it goes
out in that place, between the functions around it, so a `.macro` defined there can be
used by the asm statements of the functions after it. The code segment and 16-bit
registers are restored after it. A function whose body is only asm statements can be
`__attribute__((naked))`: it gets no prologue and no epilogue, its label is the
function's name, it reads its arguments at `3,s` and after (as a `.s` function does) and
ends with its own `rts`. A `.s` file is the other way to write a whole function.

**Registers at the start of an asm statement in a function, and at its end.**

- A, X and Y are 16-bit (M = X = 0) and must be 16-bit again at the end. Their contents
  at the start are unknown, and the compiler assumes nothing about them afterwards. The
  flags are free too. The file is assembled with `.smart +`, so ca65 tracks `rep` and
  `sep` itself. The compiler puts `.a16` and `.i16` after the text.
- `__rg+0` to `__rg+47`, `__h0` to `__h3` and `__rv` are scratch: use them freely.
- `__rg+48` to `__rg+95` must be kept, except the registers of the variables the text
  names (below), which it may read and change.
- Never change `__sp`, `__cbank`, D (0) or DBR (the code bank). S must be the same at the
  end (push and pull in pairs).
- The statement may call C functions (`jsr _name`, the arguments pushed as above and
  removed after). The compiler keeps no value in a scratch register across an asm
  statement, as across a call.

**Names.** A global variable or function is reached by its assembler name: the C name
with an underscore (`counter` is `_counter`). C's globals are in the code bank, so
absolute addressing (DBR) reaches them. `%[name]` in the text is replaced by:

- for a local variable or a parameter (not an array, a structure, `volatile`, or one whose
  address is taken): its direct-page register, `__rg+N`. A variable named so is in a
  callee-saved register for the whole function (so the scratch ones stay free). A `long`,
  `long long` or `__far` pointer is several words: `%[x]` is the low one, `%[x]+2` the
  next.
- for a global, a `static` variable (also a local one), a function: its assembler name
  (`_counter`, `_main__total_3`).
- for an enumerator: its value, in decimal: `#%[MAX]`.

The text reads the variable's value at its start and may change it: the C code after it
uses the new value (a `char` variable is cut back to 8 bits). An array, a structure, a
`volatile` local or a local whose address is taken is on the software stack, which one
operand cannot reach: `%[buf]` is an error. Take its address in a pointer
variable first (`p = buf;`) and use `(%[p]),y`. GNU's operand lists (`asm("..." :
"=r"(x) : "r"(y))`) are not supported (an error).

**Labels.** Each asm statement in a function gets a label of its own before it, so ca65's
cheap local labels (`@loop`) are local to the statement. `:` and `:+`/`:-` work too.

**In the large code model** (`hcc --code large`) a function with an asm statement, and a
naked function, stays in the main bank (its assembly may name main-bank addresses and
banks freely). Its calls follow the large model: `jsl _name` to call a C function, a naked
function's arguments from `4,s` and its own `rtl`. `%[name]` of a function is its code
(for `jsl %[f]`). Its 16-bit address is `__T` and the name (`__T%[f]`). `#ifdef
__CC816_LARGE__` selects the text for each model (`tests/lang/asm.c` does).

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

More examples are in `sdk/c/cc816/tests/lang/asm.c`: this loop, a sum through a `__far`
pointer (`[%[fp]],y`), a `long` changed word by word, a C function called from assembly
(`pei (%[x])`, `jsr _twice`, `ply`), a `.macro` from a file-scope asm statement and a
naked function.

## C library on Horizon

cc816 has a C library of its own (`sdk/c/lib`, in C) and a runtime (`sdk/c/rt`: the
startup, the memory and string routines and the arithmetic, in assembly). It is built
split, one function a module, so a program links only what it uses. It works the same in
both code models and with far data (there the heap takes banks from Horizon as it grows).

- `main(int argc, char **argv)` / `main(void)`: the argument string split at spaces.
  `"quoted words"` stay whole (a quote anywhere starts or ends quoting: `a"b c"d` is `ab
  cd`). `argv[0]` is the program's name as the menu bar shows it ("Greet"), not its path
  (`hz_task_path` gives the path). At most 32 arguments. The return value is the exit
  code.
- `exit`, `atexit`, `_Exit`: atexit functions newest first, then every open FILE is
  flushed and closed. `hz_exit()` ends at once without flushing.
- `printf` family: `%d %i %u %x %X %o %c %s %p %n %%`, the sizes `hh h l` (and `z t`),
  widths, precision, `-+ 0#`, `*`. `%f %F %e %E %g %G %a %A` (also with `l`, `L`) in
  programs that use them ("Floating point", below: "Only for programs that use it").
  `%lld %lli %llu %llo %llx %llX` (and `j`: `intmax_t` is `long long`; `inttypes.h`'s
  `PRId64` ...) in programs that use `long long` ("long long").
- `scanf` family: `%d %i %u %o %x %c %s %[...] %p %n`, `*`, widths, the sizes `hh h l`.
  `%f %e %g %a` (`float *`; with `l` or `L` `double *`, `long double *`: the same 32 bits)
  in programs that use them. `%lld %lli %llu %llo %llx` (and `j`, `SCNd64` ...) in
  programs that use `long long`. `scanf` reads the keyboard (see stdin).
- stdout, stderr: the console (the screen and the log; a terminal window when started
  there), line-buffered. A line is sent at `\n`, before reading stdin and at exit.
- stdin: the keyboard. A line typed with echo, Backspace, Left / Right. `fgets(buf, n,
  stdin)`, `getchar`, `scanf`. Ctrl-C or ctrl-D on an empty line: end of input (EOF).
- `fopen`: modes `r`, `w`, `a`, `r+`, `w+`, `a+` (`b` is ignored, no line-end conversion;
  `x` fails if the file exists). **4 file handles for the whole system**: when none is
  left, NULL and `errno == ENFILE`. A missing file or folder: `ENOENT`. 1 KB of buffer
  from the heap. When the heap has no 1 KB free, 128 bytes. When not even that, the
  FILE's own 2 bytes (slow, but the file opens and works). `setvbuf(f, NULL, _IONBF, 0)`
  gives the 1 KB back. The FILE structures are static (4, one for each of Horizon's
  handles). `strerror(ENOMEM)`: "Not enough memory (the heap, or no free bank)".
- `fread fwrite fgets fputs fgetc fputc getc putc ungetc fprintf fscanf fflush fclose feof
  ferror clearerr`: as C specifies, buffered.
- `fseek ftell rewind`, `fgetpos`, `fsetpos`: any position (32 bits). `SEEK_END` counts
  from the size at open plus what was written.
- `remove`, `rename`: as C specifies (rename also moves between folders on the card).
- `freopen`: files only (not stdin, stdout, stderr).
- `tmpfile`, `tmpnam`: not supported (NULL).
- `opendir readdir rewinddir closedir` (`dirent.h`): `d_name`, `d_size`, `d_attr`
  (`HZ_ATTR_DIR`). No file handle is used.
- `errno`, `strerror`, `perror`: errno from Horizon's codes (`ENOENT` no such file or
  folder, `EACCES` denied, `EEXIST`, `ENFILE` no handle left, `ENOMEM`, `EINVAL`, `EBADF`,
  ...). `hz_strerror(code)` gives a Horizon code in words.
- `malloc calloc realloc free`: first fit over the heap, NULL when it is full.
  `hz_heap_free()`, `hz_heap_largest()`, `hz_heap_peak()` (horizon.h).
- `string.h`, `ctype.h`, `qsort`, `bsearch`, `strtol`, `strtoul`, `atoi`, `atol`, `abs`,
  `div`, `rand` (RAND_MAX 32767): as C specifies.
- `strtod`, `strtof`, `strtold`, `atof`: exact (rounded to nearest, ties to even, from any
  number of digits), hexadecimal (`0x1.8p3`), `inf`, `infinity`, `nan`, `nan(...)`. ERANGE
  on overflow and when a nonzero number becomes 0.
- `math.h`: the list under "Floating point", below.
- `strtoll`, `strtoull`, `atoll`, `llabs`, `lldiv`: as C specifies (`inttypes.h`:
  `strtoimax`, `strtoumax`, `imaxabs`, `imaxdiv` are the same).
- `setjmp`, `longjmp`: "setjmp and longjmp", below.
- `assert`: prints the expression, the file and the line on stderr, then exit code 3.
- `time()`: seconds since 1970 from Horizon's clock (`time_get`, set by the Desktop or
  the shell from /SYSTEM/CLOCK or the PC; when it was never set, it counts from
  2000-01-01). `gmtime`, `localtime`, `mktime`, `strftime` (no time zones).
- `clock()`: CLOCKS_PER_SEC is 50, 20 ms steps. Milliseconds: `hz_uptime()`.
- `open`, `creat` (`fcntl.h`), `read`, `write`, `lseek`, `close`, `unlink`, `isatty`
  (`unistd.h`): POSIX's file descriptors, for code written for Unix or DOS (the Xargon
  port's boards). `O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC O_EXCL O_APPEND` (`O_BINARY`,
  `O_TEXT` are 0: nothing is converted). Descriptors 0-2 are the console, files 3 and up
  (Horizon's 4 handles, shared with `fopen`). No buffer for writing. A read-only
  descriptor reads ahead 512 bytes from the heap (small reads of records would otherwise
  each be a call to the card), and a read of 512 or more goes directly to the card.
  `lseek` takes any 32-bit position (`SEEK_END` from the size at open). `read` returns
  all the bytes asked for unless the file ends, up to 32,767. `ssize_t` is a 16-bit
  `int`, so one `read` or `write` moves at most 32,767 bytes. A call that requests more
  moves that many and returns the count (a short count, as POSIX allows, never one that
  looks negative and is taken for an error by `if (n < 0)`). A loop until all is moved
  works unchanged. A single `read(fd, p, 40000u)` that needs all 40,000 must loop
  (`fread` / `fwrite` count in `size_t` and are not limited). Errors in `errno`
  (`ENOENT`, `EEXIST`, `EBADF`, `ESPIPE`, `ENFILE`). Source: `sdk/c/lib/posixio.c`.
- `system`, `getenv`, `signal`, `raise`, locales: not supported (they return failure).

## Floating point

**One format.** cc816's `float`, `double` and `long double` are all IEEE 754 single
precision: 32 bits, a 24-bit significand (about 7 decimal digits), from 1.2e-38 to 3.4e38,
and denormals down to 1.4e-45. `sizeof(double)` is 4. Compilers for small machines often
do this: a 64-bit `double` would take twice the memory and much more time. The three
types keep their names (`_Generic` distinguishes them), but they hold the same values.
`float.h` reflects this: `DBL_DIG` is 6 and `DBL_EPSILON` is `FLT_EPSILON` (1.19e-7). C
written for a 64-bit `double` compiles and runs, with 7 digits instead of 16
([porting.md](porting.md)).

**Arithmetic.** It follows IEEE 754 for single precision:

- `+ - * /` and the conversions to float are rounded once, to nearest, ties to even.
  `1.0f + 0x1p-24f` is 1 (a tie: to even).
- Gradual underflow: denormals come in and go out, rounded once. Overflow gives infinity.
- Compares are exact. A NaN is unordered: every compare with it is false but `!=`. In a
  condition (`if (x)`, `!x`, `&&`), a NaN is true and -0.0 is false.
- -0.0 is kept as IEEE specifies (`-0.0 == 0.0`, `1 / -0.0` is -infinity).
- A NaN operand gives that NaN back, made quiet (the first when both are). An invalid
  operation (0/0, inf - inf, 0 * inf, inf / inf, `sqrt(-1)`) gives the default NaN,
  $FFC00000 (the sign bit set, as on x86: printf shows `-nan`). `NAN` in math.h is the
  positive quiet NaN, $7FC00000.
- A conversion to an integer truncates toward zero. Out of range (C leaves it undefined):
  `long` gets -2147483648 for |x| >= 2^31 and for NaN. `unsigned long` gets 4294967295
  for x >= 2^32 and NaN. `int`, `unsigned` and the char types take the low bits of the
  `long` conversion.
- No exception flags, no other rounding modes, no `fenv.h`.
- Constants: decimal and hexadecimal (`0x1.8p-3`), with or without the suffixes `f`, `F`,
  `l`, `L`. Each is rounded exactly once. The compiler folds constant expressions (`1.0 /
  3`, initialisers, `x * 2` becomes `x + x`) with the same rounding as the run time: the
  same bits.

**Implementation.** The arithmetic is in 65816 assembly, `sdk/c/rt/fp_*.s`: `__fadd`,
`__fsub`, `__fmul`, `__fdiv`, `__fcmp`, `__ltof`, `__ultof`, `__ftol`, `__ftoul` (operands
in `__h0`/`__h1`, as the 32-bit helpers; the contract is at the top of `fp_pack.s`). They
take 1,792 bytes when all are linked. A float is passed and returned as a `long` is (4
bytes on the stack; A/X). For assembly: the bits of a float are its IEEE pattern, low word
first. cc816 has two builtins to read them without a union: `__builtin_fbits(x)` (the 32
bits as an `unsigned long`) and `__builtin_bitsf(u)` (back).

**Only for programs that use it.** The arithmetic helpers are linked as any helper is:
when the code calls them. printf's float conversions (`lib/fmtfp.c`, 3,677 bytes) and
scanf's (`scanfp.c`, 1,699 bytes, with `strtod`, 4,848 bytes) are linked only when a file
may need them. A printf call (`printf`, `sprintf`, `vsnprintf`, ...) whose format is a
string constant links the float conversions when the format has one (`%f %e %g %a` and
their capitals), and nothing for floats when it has none: `printf("%d\n", n)` in a file
full of `double`s brings no float printing. A printf whose format is not a constant (a
variable, a parameter) links them when the file uses floating point (it defines a float
object, has a float constant, converts to or from a float, or calls a function with a
float argument or result; a prototype alone, as in `stdlib.h`, does not count). So does a
float given to any variadic function (a wrapper of printf). That links `rt/fp_hookp.s`,
whose constructor gives printf its float conversions. The same holds for scanf:
`sscanf(s, "%d", &n)` links no float scanning. `%f` in its format, a format that is not a
constant in a file with floating point, or a float pointer given to a variadic function
links `fp_hooks.s`. So a program without floating point has no float code in its printf,
and a program that computes with floats but prints none has no float printf. The rule
misses only unusual code: a printf whose float argument was never a float in any file
(`printf("%f", some_long)`).

**math.h.** Every name has its plain form (`sin`). The `f` and `l` forms (`sinf`, `sinl`)
are macros for it. No function sets errno: a domain error gives NaN, an overflow
`HUGE_VAL` (infinity). `math_errhandling` is 0. Accuracy, measured against glibc on a
million arguments a function ("ulp" is a unit in the last place), and bytes linked (about,
with what they use):

- Exact (correctly rounded): `sqrt`, `fabs`, `floor`, `ceil`, `trunc`, `round`, `rint`,
  `nearbyint`, `lround`, `lrint`, `fmod`, `remainder`, `modf`, `frexp`, `ldexp`,
  `scalbn`, `ilogb`, `logb`, `copysign`, `nextafter`, `fmin`, `fmax`, `fdim`,
  `fpclassify`, `signbit`, `isnan`, `isinf`, `isfinite`, `isnormal`. Sizes: `sqrt` 560,
  `floor` 280, `fmod` 1,100.
- Within 1 ulp: `sin`, `cos`, `tan` (any argument: 1e30 too, reduced exactly), `atan`,
  `atan2`, `exp`, `exp2`, `log`, `pow`, `cbrt`. Sizes: `sin` and `cos` 4,300 together,
  `tan` 1,300 more, `atan2` 1,900, `exp` 1,000, `log` 1,300, `pow` 4,800.
- Within 2 ulp: `asin`, `acos`, `log10`, `log2`, `log1p`, `hypot`, `cosh`.
- Within 3 ulp: `expm1`, `sinh`, `tanh`.
- `fma`: x * y rounded, then + z (not fused).

Not there: `lgamma`, `tgamma`, `erf`, `erfc`, the Bessel functions, `nan()`, `fenv.h`.
The algorithms are fdlibm's (Sun Microsystems; its notice is in `sdk/c/lib/mathint.h`) in
their single-precision form, with two changes to `pow` (`math_pow.c`): the head of
2/(3 ln 2) has 12 bits instead of 13, which keeps `pow` within 1 ulp near x = 1, and a
large |y| (over 2^27) with x more than 8 ulp from 1 gives infinity or 0 only when the
result overflows.
The reduction of large trigonometric arguments is cc816's own.

**printf, scanf, strtod.** `%f %F %e %E %g %G %a %A` print a float's exact decimal value,
rounded to the precision with ties to even, as glibc does: `printf("%.1f", 0.25)` gives
`0.2`, and `printf("%.20f", 0.1f)` gives `0.10000000149011611938`. The flags, the width
and the precision work as for integers. `inf`, `nan` (`INF`, `NAN`) are printed with a
sign when the sign bit is set. scanf's `%f` (and `%e %g %a`, with `l` or `L` for `double
*` and `long double *`) reads the longest beginning of a number, as C specifies (`1e+x`
fails), and converts it with `strtod`. `strtod`, `strtof`, `strtold` and `atof` round
exactly (any number of digits; hexadecimal, `inf`, `infinity`, `nan`, `nan(n)`), and set
ERANGE on overflow and when a nonzero number becomes 0.

**Timing.** In microseconds, one operation on volatile operands, the loop taken out (the
emulator, whose timings are the board's within about 5 %):

- `+` 77, `-` 87, `*` 207, `/` 282, `<` 17.
- `(float)long` 47, `(float)int` 62, `(long)float` 37.
- `sqrt` 587, `sin` 4,147, `exp` 3,560, `log` 3,402.

That is about 250 to 4,000 cycles of the 14.3 MHz clock for one arithmetic operation:
keep floating point out of anything that runs every frame (`hgame.h`'s fixed point is much
faster). The benchmark is under "Performance".

**Verification.** The arithmetic was checked bit for bit on 47,159 cases: 28,450
operations (+ - * / compares conversions: specials against specials, ties, denormal and
overflow results, random patterns) whose expected bits were also checked against the
host's SSE hardware, 3,000 printf and strtod results against glibc, and 15,709 math.h
results against the same C built for the host. Random float programs agree bit for bit
with gcc's SSE single precision.

## long long

`long long` and `unsigned long long` are 64 bits (`int64_t`, `uint64_t`, `intmax_t`,
`uintmax_t`; `LLONG_MIN`, `LLONG_MAX`, `ULLONG_MAX` in `limits.h`, `INT64_MAX`,
`INT64_C(...)` in `stdint.h`, `PRId64` and `SCNd64` in `inttypes.h`). Every operator
works on them, and every conversion to and from the other types, `float` and `double`
too. Constants: `LL`, `ULL` (also `ll`, `ull`, `LLU`), and a constant too big for `long`
is a `long long`, as C specifies. The compiler folds constant expressions with them
(`sizeof`, initialisers, `case`). They can be globals with initialisers, structure
members, array elements, arguments and results, variadic arguments (`va_arg(ap, long
long)`), and a `switch` value. A bit-field cannot be `long long`.

**Implementation.** `+ - & | ^ ~`, unary `-`, the compares, `++`/`--` and shifts by a
multiple of 16 or by 1 to 3 are inline (four 16-bit steps). Multiply, divide, remainder
and other shifts call helpers in 65816 assembly (`sdk/c/rt/rt_mul64.s`, `rt_div64.s`,
`rt_shift64.s`: the operands in `__h0`..`__h3`, the contract at the top of
`rt_shift64.s`). The conversions to and from `float` are C (`sdk/c/lib/llconv.c`),
rounded as the 32-bit ones are (to nearest, ties to even; toward zero to an integer).
`(long long)` of a float out of range gives `LLONG_MIN` (as x86 does). `(unsigned long
long)` gives `ULLONG_MAX` for 2^64 and above and for NaN. A `long long` argument takes 8
bytes on the stack, and a result comes back in `__h0`..`__h1` ("Calling convention").

**Only for programs that use it.** The helpers are linked when the code calls them.
printf's and scanf's `%lld` family (`lib/fmtll.c`, `scanll.c`) is linked as the float
conversions are: by a constant format with `%lld` (or `%jd`, ...), by a format that is not
a constant in a file that uses `long long`, or by a `long long` given to a variadic
function. A program without `long long` links none of it. The support adds 106 bytes to
printf (the test for `ll` and the call of the hook) and 137 to scanf.

**Timing.** In microseconds, one operation on volatile operands, the loop taken out
(`tests/ll/llbench.c`, emulated):

- `+` 16, `-` 15, `<` 21.
- `*` 376, `/` 1,260, `/ 10` 196, `%` 1,265, `<< n` 85.
- `(float)ll` 210, `(long long)f` 51, `sprintf("%lld")` 2,985.

The division takes the 32-bit helper when both operands fit 32 bits and a quicker path
when the divisor is below 65,536. The times above are a 57-bit value by a 34-bit one, the
slow case (64 rounds). As with `long`, keep `long long` out of inner loops.

Every operator, conversion and library function was checked against values from gcc, and
random programs that mix 64-bit expressions with every other width agree with gcc.

## setjmp and longjmp

`setjmp.h` has `jmp_buf`, `setjmp`, `longjmp` (and `sigsetjmp`, `siglongjmp`, `_setjmp`,
`_longjmp` as the same). `setjmp` returns 0, then the value `longjmp` gives (1 if that
is 0). A `jmp_buf` (54 bytes) keeps the hardware stack pointer, the return address, the
software stack pointer and the 48 bytes of callee-saved registers. `longjmp` restores them
(`sdk/c/rt/setjmp.s`). It may jump out of any depth of calls, also out of a library
function's callback (a `qsort` comparison). Both stacks are as they were at the `setjmp`.
A `setjmp` and `longjmp` pair takes about 86 microseconds.

As C specifies, after `longjmp` a local variable of the function that called `setjmp`
that is not `volatile` and was changed after the `setjmp` has an unknown value. Declare
such a variable `volatile`: it is then in memory and keeps its last value. A variable not
changed after the `setjmp` keeps its value: the compiler recognises `setjmp` by its name
(also `_setjmp` and `sigsetjmp`) and gives every value live across it a place of its own
for the whole function. Call `setjmp` directly, not through a function pointer. `longjmp`
into a function that has returned is undefined, as in any C. 2,000 jumps in a loop lose no
stack.

## Syscalls from C

`horizon.h` includes `hzsys.h`, generated by `tools/gensys.py` from horizon.inc, ABI.md
and `tools/syscalls.tab`. Every syscall of ABI.md is a function `hz_<name>` with a real
prototype and a comment (115 syscalls, 117 functions: `hz_spr_move_many` and
`hz_task_name_get` are other uses of `spr_move` and `task_name`). Every one, with its
prototype and a link to its section of the assembly reference: [syscalls.md](syscalls.md).

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

- Results: as the comment of each function states. `ok` functions return 0 or -1. Others
  return A (a handle, a window, a count) or -1, `unsigned` ones $FFFF on an error, `long`
  ones A | X << 16 (`hz_uptime`, `hz_seek`, `hz_stat`, `hz_time_get`).
- `hz_errno`: every function sets it, 0 when the call worked, else Horizon's error code.
  Test it where -1 or $FFFF is also a valid result (`hz_input_poll`, `hz_win_popup`).
- `hz_x`, `hz_y`: the X and Y registers after the calls that return more than one value
  (`hz_con_size` rows, `hz_input_read`'s position, `hz_mem_info` total, `hz_time_get`'s
  clock state, `hz_open`'s HTTP status, `hz_task_single`'s id).
- Blocks: `hz_io`, `hz_winopen`, `hz_windraw`, `hz_event`, `hz_statblk` and
  `hz_fileinfo`, `hz_readdirblk` and `hz_dirent`, `hz_renameblk`, `hz_spawnblk`,
  `hz_taskinfo`, `hz_msg`, `hz_clipblk`, `hz_rect`, `hz_mouse`, `hz_popup`, `hz_sample`,
  `hz_sprite`, `hz_sprmove`, `hz_fsenter`, `hz_fsscroll`, `hz_raster`, `hz_drawrec`,
  `hz_sheetnew`, `hz_sheetrec`, `hz_timermsg`. Blocks may be globals or locals.
- Constants: horizon.inc's names (`WD_FILL`, `WE_CLOSE`, `C_RED`, `SPR_EN`, ...), except
  the error codes and the open modes, which get `HZ_` (`HZ_EINVAL`, `HZ_EIO`,
  `HZ_O_CREATE`) because their plain names belong to errno.h. Card errors: `HZ_ENOFILE`,
  `HZ_ENOPATH`, `HZ_EDENIED`, `HZ_EEXIST`, `HZ_ENFILE`.
- Helpers: `hz_spawn_path(path, args, prio)`, `hz_stat_path(path, &info)`,
  `hz_getline(buf, size)` (a line with editing, at most size - 1 characters; a line
  longer than the room right of the prompt scrolls sideways, as the shell's does; stdin
  reads lines of up to 255 characters through it), `hz_key_ascii(usage, mods)` (a key
  event to ASCII, KEY_* for arrows), `hz_prog_dir(buf, size)` (the program's own folder,
  below), `hz_ms()`, `hz_errno_to_errno(code)`, `HZ_U24B`, `HZ_STATIC_ASSERT`. The whole
  list: [library.md](library.md#horizonh-helpers), "horizon.h helpers".
- The program's own file (Horizon 0.28): `hz_task_path(buf, size)` writes the absolute
  path of the file the program was loaded from, such as `/GAMES/MINE/GAME.PRG`, and
  returns its length. `hz_prog_dir(buf, size)` writes its folder, `/GAMES/MINE/`, ending
  in `/`. A 128-byte buffer always fits. Both return -1 on an older Horizon (hz_errno
  `HZ_ENOSYS`). A game uses them to find its data files next to it, however it was
  started (the shell, the Desktop's Programs menu, Files):

  ```c
  char path[128];
  FILE *f;
  if (hz_prog_dir(path, sizeof path) < 0)
      strcpy(path, "");               /* an older Horizon: the current folder */
  strcat(path, "LEVELS.DAT");
  f = fopen(path, "rb");
  ```
- Program requirements (Horizon 0.29): `hcc --needs horizon=0.29,opl2,mem=1024K` (also
  `rev=N`, `lau`, `sprites`, `blitter`, `joystick`) adds a check that runs before `main`.
  When something is missing the program prints one line ("GAME needs the OPL2 sound chip
  (hardware revision $0C).", also in a small window when the window system runs) and
  exits with code 1. It works on older Horizons too. Without `--needs` nothing is added.
  `hz_sys_info()` returns Horizon's version (major x 256 + minor, 0x001D for 0.29, 0x001E
  for 0.30, 0x001F for 0.31) and sets `hz_x` to the hardware revision (-1 / 0xFFFF and
  `HZ_ENOSYS` before 0.29). An app (a program in its own folder, installed from an `.HZA`
  archive): [../apps.md](../apps.md).
- A syscall without a wrapper (a newer kernel's): `hz_syscall(n, a, x, y)` returns A and
  sets hz_errno, hz_x, hz_y. A pointer is two arguments: `HZ_OFF(p)` and `HZ_BANK(p)`. Or
  write the stub in assembly as the generated ones are (`sdk/c/build/lib/small/stubs/*.s`):
  the arguments into A, X, Y, `cop #$NN`, `bcs` to an error path.

## Heap and stacks

The main bank (the code bank of the small model) from bottom to top:

```
$0100   code, constants, data, bss      (hcc --map: their sizes)
        heap (malloc, and fopen's buffers) ... grows up
        software stack guard zone (256 bytes)
        software stack ... grows down    --stack N (default 8192)
$FFF0
```

- Heap: what is left between the bss and the software stack. `hcc --map` prints it
  ("heap 11,283"). In the small model it is everything else. In the large model hcc fills
  the main bank with code but keeps at least `--heap N` bytes for the heap (default
  4096).
- Software stack: `--stack N` bytes (512 to 32,768, even; default 8,192), set with `hcc
  --stack N`.
- Hardware stack: about 32,000 bytes, in the window. Fixed.

`malloc` returns NULL (errno ENOMEM) when the heap has no block big enough. Each open file
takes 1 KB of it (less when there is no 1 KB: "C library on Horizon"). To measure what a
program uses:

- `hcc --debug`: at exit the program prints `stack: N of M bytes used`, `software stack: N
  of M bytes used` and `heap: N of M bytes used at most` (the most in use at once, block
  headers counted).
- at any time: `hz_heap_free()` (the free bytes), `hz_heap_largest()` (the biggest
  `malloc` that would work now), `hz_heap_peak()` (the most in use so far),
  `hz_sstack_free()`, `hz_stack_free()`.

A program short of heap: give it more with `--heap N` (the large code model) or less
software stack (`--stack N`, when `--debug` shows it uses little), and put big buffers in
banks of their own (`hz_far_alloc`).

A program has two stacks. The **hardware stack** is the window's top part (about 32 KB):
return addresses, arguments and the values the register allocator spills. The **software
stack** is the top of the main bank (`--stack N` bytes, default 8,192): arrays, structures
and locals whose address is taken. Big local arrays and deep recursion with arrays use it
up.

The startup fills each stack's lowest 256 bytes with a pattern (the **guard zone**). At
exit the program checks them and, if any of a zone was written, prints `stack overflow:
the guard zone at window address N (the stack's last 256 bytes) was written` (the
software stack: `stack overflow: the software stack's guard zone at N ... was written`).
An overflow is detected only if something was written into those 256 bytes (a
never-written local array larger than that can jump over them), and only at exit
(`hz_stack_check()` checks at any time; `hz_stack_free()` gives the bytes below the
hardware stack pointer now, `hz_sstack_free()` those of the software stack). With `hcc
--debug` the startup paints the stacks and the exit reports the most used: `stack: 109 of
32251 bytes used` and `software stack: 660 of 7936 bytes used`.

**The software stack is checked at every function's entry.** A function with a frame
there (an array, a structure, a local whose address is taken, the copy of a structure
returned by value) compares `__sp` minus its frame with the stack's lowest address before
it takes the frame (9 cycles, 9 bytes of code and the name: under 1 % of the
benchmarks). When the frame does not fit, the program stops before anything is
overwritten (the heap lies directly under the stack), prints

```
software stack overflow: build_atlas needs a frame of 3700 bytes; 396 of the software stack's 4096 bytes are free (hcc --stack N; docs/c/reference.md)
```

and exits with code 3 (the `atexit` functions and the destructors run, as for `exit`).
The hardware stack is not checked this way (only its guard zone, at exit, as above).

The compiler warns at a frame over 1 KB and stops with an error at one bigger than the
whole software stack (hcc gives cc816 the `--stack` size; a library compiled alone is
checked against the default 8,192):

```
atlas.c:14:16: warning: the function 'load_atlas' needs a software-stack frame of 7,400 bytes (the software stack is 8,192 bytes: hcc --stack N; arrays and structures returned by value are there) [-Wframe-larger-than]
atlas.c:30:5: error: the function 'huge' needs a software-stack frame of 9,000 bytes, more than the whole software stack (8,192 bytes): make the big locals static or global, or give hcc --stack 10240
```

A structure returned by value takes its size twice: the callee's local and the caller's
copy (`struct big b = make();` is two of them in the caller). Big structures are better
filled in place through a pointer.

## Program files

ld65 (cc65's linker, the one Horizon's own programs use) writes the o65 file directly,
with the startup first at $0100 (`rt/hzprog.cfg`). hcc then drops the relocation entries
that add nothing (`tools/o65strip.py`, the SDK's copy of Horizon's: the loader always puts
a program at $0100, so only the bank bytes need relocating). It checks that the result
loads the same at three banks. A hello world keeps 8 relocations.

**`--code large`** (`tools/hzlarge.py`): the objects' segments are read first
(`tools/ca65obj.py`: cc816 gives every function that can move a segment of its own, and
ld65's configuration must name every segment). A trial link with those segments in one
big pool gives the main bank's fixed part and the functions whose 16-bit address is used.
hcc places the functions (first fit: the main bank, then banks of 64 KB), writes a glue
module (the thunks, `__T_name = _name` for the functions in the main bank, the loader's
table: the number of banks, the stamp, the program's name) and writes ld65's
configuration: the main bank as an o65 file, each other bank as a raw image. Then it
links **three times**, with bank k at the link-time banks k, k + $40 and $80 + 2(k - 1)
(in the third link at offset 1). In the main bank a byte that differs between the links
must name one bank in all three (the link's bank of k each time): it is a bank byte of
bank k (a JSL to a function there, a thunk's JML) and becomes one of the relocations
after the o65. The two bytes before such a bank byte may differ by one in the third link
(a far address's offset). Anything else stops the build: a value "bank + 1" is odd in the
third link, and a 16-bit address of a function in another bank written in the main bank
(which ld65's o65 output would cut to 16 bits without a message: `.addr _name` in a `.s`
file) is one more there, without a bank byte after it. The main bank's own bank bytes are
o65 SEG relocations, done by Horizon's loader as in any program. In the other banks the
compiler records the address of every bank byte it writes (segment XREL: each JSL's,
JML's and MVN's), and hcc reads their bank from the first link (0: the main bank). A byte
that differs between the links and was not recorded stops the build. The .PRG is the
first link's o65 file (o65strip, as above), then the bank images, the relocations and the
8-byte trailer ("File layout", above). A build's stamp is a hash of what was linked and
where: the same build gives the same files.

## Compiler notes

cc816 is the SDK's own compiler. It reads C99 and most of C11, and some GNU C. This part
lists what it accepts, what it does not, how it reports problems, and which constructs it
compiles inline.

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
  without a prototype, tentative definitions (`int x; int x = 5;`). With `-std=c89` (or
  `-fimplicit-int`, or `-fdos-keywords`) C89's implicit int and calls with more arguments
  than the prototype, as warnings ("Old C" below).
- GNU C: statement expressions (`({ int t = f(); t * 2; })`), `typeof` and `__typeof__`
  (of an expression or a type), a cast as an lvalue, `case` and labels anywhere in a
  switch (Duff's device), case ranges (`case 'a' ... 'z':`: up to 32 values become cases,
  a wider range of a 16-bit switch is one test, a 32- or 64-bit switch takes at most 256),
  range designators (`[0 ... 9] = x`, also nested; a local's x is computed for each
  element), inline assembly ("Inline assembly"), a static object or element initialised
  with a compound literal of its own type, `#pragma push_macro` / `pop_macro`,
  `__extension__`, `__inline__`, `__restrict`, `__const`, `__signed__`, `__volatile__`,
  `__alignof__`.
- GNU attributes (`__attribute__((...))`): `noreturn` (the end of the function after a
  call of it is not reached: no "control reaches the end" warning) and `naked` are used.
  `unused`, `used`, `packed` (structures are packed anyway), `aligned(1)`, `const`,
  `pure`, `format`, `nonnull`, `always_inline`, `noinline`, `deprecated`, `malloc`,
  `cold`, `hot`, `visibility` and the like are read and ignored. One cc816 cannot honour
  (`aligned(N)` with N above 1, `constructor`, `destructor`, `section`, `weak`, `alias`,
  `cleanup`, an unknown one) is ignored with a warning (`-Wattributes`).
- The preprocessor: `#if` with C's arithmetic (32 bits and more, `/` and `%` round toward
  zero), `defined`, `__has_include`, `#pragma once`, `#line`, `#error`, `#warning`,
  `__FILE__`, `__LINE__`, `__DATE__`, `__TIME__`, `#` and `##` (also with empty
  arguments), `__VA_ARGS__`. `#define NAME= value` (no white space after the name) is
  taken as gcc takes it, the replacement being the rest of the line, `=` included, with
  `warning: missing whitespace after the macro name`.
- Source files are read byte for byte: bytes above 127 that are not UTF-8 (a DOS
  program's code page 437 text in a string) are kept as they are, in the main file and in
  included headers.
- Wide characters: `wchar_t` is 16 bits (`unsigned int`), `L"..."` and `L'x'` are read
  from a UTF-8 source (a character of Unicode's first plane each), `\u` and `\U` escapes.
  `<wchar.h>` has the string and memory functions (`wcslen`, `wcscpy`, `wcscmp`,
  `wmemcpy`, ...), no locales and no wide input or output.
- Enumerations: an enumerator may be negative or above 32767. One above 32767 is an
  `unsigned int`, one above 65535 a `long` (C requires an `int`: gcc does the same).
- Bit-fields: `signed` and `unsigned`, of `char`, `int` or `long` (an `int` field is at
  most 16 bits, a `long` one 32), packed into units of their type's size. A field that
  does not fit in the unit starts a new one. `: 0` ends the unit.
- Structures and unions by value: passed, returned, assigned, nested.
- `offsetof` is a constant (array sizes, `case`, enumerators, static initialisers).
- A label may have the name of a typedef.

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

Not inlined: `inline` is read and ignored, so every function is a call (the cost is the
call itself: for a three-line accessor the pushes, the JSL/RTL and the stack's clean-up,
20-40 cycles a call). A structure returned by value is built in the callee's frame and
copied to the caller's.

### Errors and warnings

Every message has the form gcc uses, with the file and line of the user's source (an
included header's own name and line; `#line` is followed):

```
game.c:42:13: error: 'score' undeclared (first use in this function)
game.c:57:9: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long [-Wformat]
```

The third number is the column. cc816 goes on after an error, so one run reports the
errors of the whole file (every statement is checked, and a name that is not declared is
reported once a function). After a syntax error it stops, because the parser cannot go
on. It then stops without an output file and hcc exits with 1. Warnings do not stop the
build. A syntax error names what the parser expected where it can: `expected ';' before
'return'`, `unknown type name 'uint8_t'`. A name that is not declared in an array's size
(`int t[numkinds];`) is reported as undeclared.

An internal compiler error (a fault of cc816, not of the program) is one line:
`file.c: internal compiler error: ... (in function f) (please report; CC816_TRACE=1
shows where)`. `CC816_TRACE=1 hcc ...` (or `cc816.py --trace`) shows the Python
traceback.

The warnings are on by default unless marked -Wall below (or "named": only with
`-WNAME`). The name in brackets after each message turns it off: `-Wno-format`. **`-w`
silences every warning but `overflow`**: on a machine whose `int` is 16 bits a constant
that overflows is a wrong value, not a matter of style. gcc's `-w` silences it too, cc816
does not, because with `-w` the fault of `p + 4 * T` ("Far data model", "Pointers") goes
unreported. `-w -Wno-overflow` silences it as well.

- `implicit-function-declaration`: a call of a function that is not declared (its result
  is taken as an `int`). Include its header.
- `int-conversion`: a pointer from an integer or an integer from a pointer without a cast
  (0 is allowed: it is the null pointer). A pointer compared with an integer.
- `incompatible-pointer-types`: a pointer given to one of another type (`long *` from
  `int *`). Pointers of different types compared.
- `discarded-qualifiers`: a `const char *` given to a `char *`.
- `far-pointer`: a `__far` pointer given to a near one: only the offset is kept.
- `type-limits`: a comparison whose result the type decides: `c == EOF` with a `char`
  (plain `char` is unsigned), `x > 40000` with an `int`.
- `return-type`: the end of a non-void function can be reached. `return;` in a non-void
  function. `return x;` in a void one.
- `overflow`: a constant that a conversion changes (`int x = 40000;`, `unsigned char c =
  300;`). A constant expression that overflows its type (`320 * 200` in a 16-bit `int`).
  A `case` value the switch's type cannot hold. Given with `-w` too.
- `shift-count-overflow`: a shift by the type's width or more, or by a negative count.
- `div-by-zero`: a division by a constant 0.
- `format`: `printf`, `fprintf`, `sprintf`, `snprintf`, `scanf`, `fscanf`, `sscanf` with
  a constant format. Each conversion against its argument's size and kind, too few or too
  many arguments, `scanf` without `&`.
- `excess-initializers`: more values than the array or structure has places. A string
  longer than its array.
- `cpp`: `#warning`.
- `extern-initializer`: `extern int x = 1;` (it defines x).
- `multichar`: a character constant of three or more characters.
- `attributes`: a GNU attribute cc816 does not honour (`aligned(16)`, `constructor`,
  `section`, ...), ignored.
- `frame-larger-than`: a function's software-stack frame over 1 KB (its arrays,
  structures, the copies of structures returned by value), with the stack's size ("Heap
  and stacks"). A frame bigger than the whole software stack is an error. A file compiled
  alone (`hcc -c` without `--stack`) does not have the stack size its program links with:
  the message names the default (8 KB) and the `--stack` a bigger frame needs, and only a
  frame past the largest stack (32 KB) is an error. A build that links (`hcc -o`) or
  names `--stack` uses the real size.
- `implicit-int`: (`-fimplicit-int`, `-std=c89`, `-fdos-keywords`) a function defined
  without a return type, an object declared without a type (`register x;`, `static n;`):
  taken as `int` ("Old C").
- `extra-args`: (`-fextra-args`, `-std=c89`, `-fdos-keywords`) a call with more arguments
  than the prototype. They are evaluated and pushed, never read (without the option: an
  error).
- `unprototyped-args`: a call made without a prototype (an old declaration `int f();`, an
  implicit one, a K&R definition) to a function the same file defines, whose arguments do
  not match its parameters. A size that differs (an `int` pushed, 2 bytes, where a far
  pointer or a `long`, 4, is read: every later parameter is read from the wrong place), a
  `float` against an integer, fewer arguments than parameters. A pointer and an integer of
  one size agree (the 65816 passes them alike). `hcc --check-calls` does the same across
  files.
- `prototype-mismatch`, `return-mismatch`: (`hcc --check-calls` only, across files) a
  prototype whose parameters differ from the definition's. A call without a prototype
  that uses the value, or a prototype, whose result type differs from the definition's
  (an implicit `int` where a far pointer comes back), or the value of a function that can
  end without a `return` ("Old C").
- `unknown-pragmas`: a `#pragma` cc816 does not recognise, ignored. Watcom's `#pragma aux name
  = "..."` (inline machine code: the function needs a C body) and `#pragma aux name parm
  ...`, `pack(n)` with n above 1. `once`, `pack(1)`, `GCC`, `STDC` and Watcom's message
  pragmas are silent.
- `far-function`: `__far` on a function pointer (`void (__far *f)(void)`), ignored. A
  function pointer is the main-bank entry in every model.
- `unused-variable` (-Wall): a local or static variable that is never used.
- `unused-label` (-Wall): a label no `goto` uses.
- `parentheses` (-Wall): `if (a = b)`, an assignment as a condition.
- `tautological-compare` (-Wall): a comparison always true at the type's edges: `u >= 0`
  with an unsigned `u`, `x <= 32767` with an `int`.
- `far-cast` (-Wall): a cast of a `__far` pointer to a near one (only the offset is kept).
- `sequence-args` (named): two or more arguments of one call that call functions (`f(a(),
  b())`, a syscall too; not in `sizeof`). Their side effects come in the order the
  compiler evaluates the arguments, which C leaves open. The message states cc816's order
  (left to right, or right to left with `-fargs-right-to-left`). Not in -Wall, because it
  would name every `printf` of two calls. For a port of a DOS program, `-Wsequence-args`
  lists the calls and `-fargs-right-to-left` gives them DOS's order.

The link's errors are given in C's terms too: `undefined: fire_laser (used in game.c)`
for a function or a variable no file defines. For a program too big for its code bank,
the message gives by how many bytes, the sizes of the code and constants, the data and the
bss, which of them is the biggest, and what the software stack takes (it is part of the
same 64 KB, so a program that does not fit can also give the stack less: `--stack N`).

### Options

hcc passes these to cc816 (`cc816.py`, the compiler alone, takes the same):

- `-D NAME[=VALUE]`, `-U NAME`: define or undefine a macro, in the order given.
- `-I DIR`: look for `#include` files in DIR too.
- `-include FILE`: include FILE before the source.
- `-O0`, `-O1`, `-O2`: optimisation (`-O2` the default; `-O3` and `-Os` are `-O2`).
- `-w`: no warnings, except `-Woverflow` (the 16-bit ones: "Errors and warnings").
  `-w -Wno-overflow` gives none.
- `-Wall`: the -Wall warnings too.
- `-Werror`: warnings are errors (the build stops).
- `-Wno-NAME`, `-WNAME`: one warning off or on (the names above).
- `-fsigned-char`: plain `char` is signed (-128 to 127). `CHAR_MIN` is -128,
  `__CHAR_UNSIGNED__` is not defined. The SDK's library is built with unsigned `char` and
  takes characters as `int`, so it works with both.
- `-fargs-right-to-left`: a call's arguments are evaluated right to left, as DOS's
  compilers (Watcom, Microsoft, Borland) and gcc on x86 do. The default is left to right.
  C leaves the order unspecified. A DOS port whose calls draw from one state in two
  arguments (`hurt(roll(), side())`, both calling the random number generator) needs
  DOS's order to behave as on DOS. Only the order of evaluation changes: the arguments are
  pushed and laid out on the stack as always ("Calling convention"), so files built either
  way call each other, and it costs nothing (the code is the same size).
  `__CC816_ARGS_RTL__` is defined. `-Wsequence-args` finds the calls that depend on it.
- `-ffar-wrap`: far pointer arithmetic on the offset alone, the bank never changes, as
  DOS's far pointers ("Far data model", "Pointers"). `__CC816_FAR_WRAP__` is defined.
- `-std=c89`: C89 (also `c90`, `gnu89`, `gnu90`, `iso9899:1990`, `-ansi`), which turns on
  `-fimplicit-int` and `-fextra-args`. `-std=c99`, `c11`, `c17`, `c23` and their `gnu`
  forms are accepted and change nothing (cc816 always reads C99 and most of C11).
- `-fimplicit-int`: C89's implicit int, as a warning (`-Wimplicit-int`) instead of an
  error ("Old C"). `-fno-implicit-int` turns it off where `-std=c89` or `-fdos-keywords`
  turned it on.
- `-fextra-args`: a call with more arguments than the prototype is a warning
  (`-Wextra-args`), as in DOS's compilers, not an error. `-fno-extra-args` turns it off.
- `-fno-merge-strings`: each string literal is an object of its own. By default equal
  literals in a file are one object (as gcc does). For old programs that write into their
  literals (`strcpy(buf, ...)` into five `"    "` meant as five buffers).
- `-fwritable-strings`: `-fno-merge-strings`, and the literals go to the program's data
  instead of its constants (with `--data far`, they stay in far data).
- `-E` (`cc816.py` only): preprocess only.

hcc's own:

- `--code small|large`: the code model ("Code models"; `HZ_CODE` in the environment).
- `--data near|far`: the data model ("Far data model"; `HZ_DATA`). Far needs `--code
  large`.
- `-fdos-keywords`: `far`, `near`, `huge` as keywords (cc816 takes it too).
- `--sizes`: every object and function of the link, its size and where it went ("Where
  objects live"). Also when the program does not fit: hcc then links it once more only to
  measure it, with a 512-byte software stack and no heap reserve, and lists that link, or,
  when even that does not fit, each file's segments from the failed link's map.
- `--heap N` (with `--code large`): the main bank's room kept for malloc.
- `--main-room N`, `--bank-room N`, `--spread N` (with `--code large`, for tests): how
  much code the main bank and each other bank may take, and the functions in turn in N
  banks.
- `--check-calls`: the program's C files read together, nothing built ("Old C").
- `--no-stack-check`: the program's functions without the software stack's entry check
  ("Heap and stacks"): about 1-3 % less code, 10 cycles a call of a function with a frame.
  The library keeps its checks.

### Old C

C89 programs and DOS-era ones (Microsoft C 5.1, Turbo C, Watcom) were written for
compilers that accepted what C99 does not. cc816 accepts it under options, as warnings,
with the code C89 gives:

- Implicit int: `foo(a, b) int a; char *b; {...}`, `static bar() {...}`, `register x;`,
  `static n;`, `const k = 5;`. Option `-fimplicit-int`: the type is `int`, with a warning
  `-Wimplicit-int` (without the option: an error that names the option). A function only
  declared without a type (`static bar();`, `extern baz();`) is always accepted, silently.
- A call before any declaration. No option: `-Wimplicit-function-declaration` (its
  result an `int`).
- More arguments than the prototype (`f(1, 2, 3)` of `int f(int, int)`; MSC's C4020).
  Option `-fextra-args`: a warning `-Wextra-args`. The extra ones are evaluated and pushed
  after the others. The caller takes its arguments off the stack, and the callee reads its
  parameters from the top, so the extra ones are never read. This is harmless in every
  code and data model and with `-fargs-right-to-left` (only the order of evaluation
  changes there, not the layout). A structure returned by value keeps its hidden pointer
  first.
- Writing into string literals, or equal literals meant as separate buffers. Options
  `-fno-merge-strings`, `-fwritable-strings`: each literal its own object (and, with the
  second, in the data).
- A call through an old declaration whose argument does not fit the definition
  (`picture_target(0)` where the definition takes a `char far *`). No option:
  `-Wunprototyped-args` within one file, `hcc --check-calls` across files.
- A result taken as another type than the definition returns (an implicit `int` for a
  function that returns a far pointer or a `long`, the value of a `void` function). No
  option: `hcc --check-calls` across files (`-Wreturn-mismatch`).

`-std=c89` (`c90`, `gnu89`, `-ansi`) turns on `-fimplicit-int` and `-fextra-args`.
`-fdos-keywords` does too (a DOS program is C89 code). Neither changes a program that
compiled without them: they only turn errors into warnings. `-fno-implicit-int` and
`-fno-extra-args` turn them off again. String merging is not implied by any of them: a
merged literal saves main-bank room every program needs, and a program that writes into
its literals declares it with `-fno-merge-strings` (a DOS game's port: five equal literals
used as five buffers).

**`hcc --check-calls a.c b.c ...`** reads a program's C files together (with the same
`-I`, `-D`, `--code` and `--data` as its build; nothing is built) and reports, as warnings
in gcc's form:

- a call without a prototype in one file to a function another file defines, when an
  argument's size or kind differs from the parameter's, or there are fewer arguments
  (`-Wunprototyped-args`, as within one file).
- a prototype in one file that differs from the definition in another (the number of
  parameters, or a parameter's size or kind: `-Wprototype-mismatch`). Every caller that
  uses that prototype pushes the wrong thing.
- the results (`-Wreturn-mismatch`): a call without a prototype that uses the value, or a
  prototype, that takes the result as another type than the definition returns. The
  result comes back in registers of the size the definition gives, and the caller reads
  the size its declaration gives. An implicit `int` (2 bytes) where a far pointer or a
  `long` (4) comes back loses the bank or the high word, a `long` read where an `int`
  comes back gets a garbage high word, a `float` read as a `long` is not converted, and
  the value of a `void` function is whatever the register held. A call that drops the
  value reads nothing and is not reported (`int f();` declared for a `void f(void)` and
  called as a statement is harmless). An `int` and a near pointer agree. Also a function
  that can reach its end without a `return` (its own file's `-Wreturn-type`) whose value
  a caller in another file uses.

It exits with 1 when it found one: an audit for a port's whole source. In the near data
model a pointer and an `int` are both 2 bytes and agree. With `--data far` a plain pointer
is 4 and every `int` given for one is found.

Files of one program built with different options (the game's files with `-DGAME`, the
port's own without) are read together with **`--set`**: the `-D`, `-U`, `-I` and
`-include` options after a `--set`, up to the next one, are those of the files after it.
The ones before the first `--set` apply to every file. The calls between the sets are
compared as any others:

    hcc --check-calls --code large --data far -I src -I port \
        --set -DGAME src/*.c --set port/*.c

**Big functions.** A function whose values live across calls may need more hardware-stack
slots than `n,s` reaches (its offset is 8 bits: 255 bytes with the saved registers, the
return address and the arguments). It then keeps its farthest spill slots in its
software-stack frame instead (loaded into a register before each use, stored after each
change: only such functions pay, and only for those slots). After register allocation
cc816 measures how far its `n,s` operands reach. Past 255 the farthest slots move to the
software-stack frame, then all of them if that is not enough, and the function is
allocated again. A function that fits is compiled unchanged. Branches out of reach are
relaxed (an inverted branch over a `JMP`), and a function of more than 32 KB of code gets
`JMP` where a `BRL` would not reach (a distance estimated past 30,000 bytes; the same size,
and a function never crosses its bank). Only parameters past 255 bytes (about 120 `int`
parameters) remain an error.

### Optimization

Arithmetic that cc816 compiles inline instead of calling a runtime helper:

- A multiply by a constant with up to four non-zero digits in binary or in the
  non-adjacent form (signed digits: `x * 31` = `x * 32 - x`, an array of 31-byte
  structures) is shifts and adds or subtracts.
- A signed divide by a power of two (`x / 16` of an `int`): the bias for negative values,
  then arithmetic shifts (C rounds toward zero).
- A 16-bit divide or remainder by any constant: the quotient is `(|x| * M) >> (16 + s)`,
  the multiply by the known M done a bit at a time from the low end (a one-bit adds x,
  every bit halves the 17-bit sum: exact), the sign restored, a remainder `x - q * k`.
  cc816 picks M and s for each divisor and keeps them only if they give the exact quotient
  for every dividend (all 65,536, or 0 to 32,768 for a signed one; else the call stays).
  `int / 10` takes 9 µs against 51 through `__sdiv16`, and `% 10` 13. An unsigned divide
  by 32,768 or more is a compare. `x % 16` of an `int` is a mask, `x / -16` the shift
  negated.
- A signed `long` divide or remainder by a power of two (`/ 512`, `% 16`, and by minus
  one): the bias for a negative dividend, then the arithmetic shift. The remainder is
  `-((-x) & (2^n - 1))` (`LONG_MIN` too). `long / 512` takes 16 µs with the call around
  it, against 102 through `__sdiv32`. Unsigned ones are shifts and masks.
- 32-bit shifts by a constant move a word for 16 or more and a byte for 8 or more (an
  unaligned word load from the register), then 0-7 bit steps with a word in A. By 7 and 15
  (`x * 128`, `>> 7`) a one-bit shift the other way and a byte move (48 cycles). By a
  variable (`1UL << c`), `__shl32`, `__shr32`, `__sar32` take the same steps (`1UL << 13`
  26 µs).
- A compare as a value (`return a < b;`, `int c = x >= k;`, a conversion to `_Bool`) is
  the compare's carry or sign rotated into A, without branches (32-bit `==` keeps its
  branches, quicker when the low words differ). A `_Bool` copied to a `_Bool` is not
  tested again. `x < 0` and `x >= 0` of a `long` test the high word's sign alone.
- An element of an array of arrays (`a[i][j]`, and members that are arrays) adds its
  indexes into one 16-bit index. In a `__far` object, which lies in one bank, that index
  goes in Y (`[base],y`) instead of a 32-bit address built at every access. An unsigned
  index through a far pointer does the same (Y carries into the bank as the 32-bit add
  would). A signed one through a far pointer keeps the 32-bit step (it may be negative).
- A parameter used a few times outside loops stays in its argument slot (`n,s`, as quick
  as the direct page) instead of being copied in by the prologue.
- A structure copy is inline, with MVN.

Still a call: a `long` divided by a constant that is not a power of two (`__sdiv32`,
`__udiv32`: an inline form would need a 32 x 32 -> 64-bit multiply, about as slow as
`__udiv32`). 16-bit divisions by any constant are inline.

### Conformance

The c-testsuite (single-exec, 220 programs): 213 pass, in each of the three configurations
(small, large, large with far data). The other 7 depend on what cc816 does not have: 1 a
variable-length array, 2 a 32-bit `int`, 3 a 64-bit `double` (one of them also a 32-bit
`int`), 1 one of the `__LP64__` / `__ILP32__` macros. 00040.c (8 queens by brute force)
is right but slow: about 260 emulated seconds (1.5 million calls of its check function).
The random programs of seeds 1, 2 and 3 (1,200 programs, 600 negative-index ones and 600
floating-point ones) agree with gcc in each of the three configurations, and none carries
an access into the next bank.

## Performance

The 65C816 runs at 14.3 MHz. The memory stalls make CPU-bound code about half the ideal
speed (emu816 models them: its timings are the board's within about 5 %). The benchmark
(`sdk/c/tests/bench`), in milliseconds, for sieve, sum16, mul32, fib22, strs, structs:

- -O2 (the default): 808, 298, 1279, 395, 860, 667.
- -O1: 808, 478, 1276, 400, 847, 670.
- `--code large`, -O2: 810, 298, 1279, 420, 849, 676.
- `--code large`, -O1: 810, 478, 1285, 416, 856, 680.

The figures vary by up to about 1.5 % between builds of the same code: the 4 KB cache
holds the code at other addresses. The check values are the benchmark's six: 1899, 27824,
1071602483, 17711, 3160, 4275534039.

What they measure: sieve (byte arrays, 16-bit indexes), sum16 (16-bit arrays), mul32
(32-bit multiply and divide), fib22 (calls), strs (pointers and bytes), structs (structure
fields, signed, shifts).

Floating point (`tests/bench/fbench.c`), in milliseconds for mandel, sincos, sqrt, expow,
conv, and the program's size on the card:

- -O2: 2,166, 1,660, 360, 1,970, 1,068. 23,132 bytes.
- `--code large`: 2,150, 1,650, 370, 1,950, 1,066. 27,881 bytes.

mandel is one 64-point row of the Mandelbrot set (+ - * and compares), sincos `sin` and
`cos` of 200 values, sqrt 500 square roots, expow `exp`, `log` and `pow` of 100 values,
conv 2,000 conversions and divisions. Every operation is rounded exactly (IEEE 754) and
math.h is within an ulp or two of the exact result. The float code takes about 1.8 KB of
arithmetic and 3.7 KB for printf's `%f`. A call to a float helper is 12 to 27 bytes of
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

The 32-bit lines of this test read `volatile` operands: each goes through a direct-page
register before the helper takes it, about 60 cycles a call. In real loops the operands
are already in registers.

Each routine was checked against tables made on the PC (3,000 cases per arithmetic
operation, 2,000 per memory function, signed and unsigned, edge values, in both code
models). The 32-bit multiply's low product is unrolled, and the divisions take a shorter
round when the divisor is below $8000.

Guidelines, from these numbers and the generated code:

- Prefer **`unsigned int`** (16 bits) for counters, indexes and loop variables: the
  65816's own size. Signed division and right shifts of `int` need extra code.
- Avoid **`long`** in inner loops: every 32-bit operation is two 16-bit ones, and a
  multiply or divide is a call (a 32-bit multiply about 0.1 ms with its loop, table above).
- Avoid **float** in anything that runs every frame (20 to 300 microseconds an operation,
  milliseconds for `sin` or `pow`). Fixed point (`hgame.h`'s `hg_fix8`, `hg_fix16`) is
  much faster.
- `memcpy`, `memmove`, `memset` move blocks with MVN/MVP (about 12 cycles a byte, 1000
  bytes in about 0.8 ms). `hz_far_copy` too.
- `-O2` (the default) is the fast one. `-O1` drops the loop optimisations (sum16 above).
