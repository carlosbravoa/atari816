# cc816 compiler

cc816 is the SDK's C compiler for the 65C816 and Horizon. It is written in Python 3
(`sdk/c/cc816`), reads C99, most of C11, old C and some GNU C, and writes ca65 assembly.
`hcc` (`sdk/c/bin/hcc`) is the driver: it compiles, assembles with ca65, links with ld65
and the C library, and checks the sizes. Nothing is downloaded. The preprocessor (pcpp)
and the parser (pycparser) are vendored in `sdk/c/cc816/vendor` (BSD licences), and the
rest of the toolchain is cc65's ca65, ld65 and ar65.

The C language as cc816 implements it (memory, the code and data models, types, the
calling convention, inline assembly, the library) is described in
[reference.md](reference.md). This page links to its sections.

## Build pipeline

```
hcc -o SUM.PRG sum.c
   cc816 (in hcc's own Python process)     sum.c -> sum.s        ca65 assembly
   ca65 --cpu 65816                        sum.s -> sum.o
   ld65 -C sdk/c/rt/hzprog.cfg             crt0.o sum.o libc816.lib -> SUM.PRG (o65)
   o65strip.py                             drops the relocations that add nothing
   the size check                          what does not fit, in bytes
```

`hcc -v` prints the ca65 and ld65 commands as it runs them. Inside cc816, one file goes
through these passes (`cc816.py --time` prints the time of each):

- Preprocessing (`vendor/pcpp`, driven by `driver.py`): `#include`, macros, `#if` with
  C's arithmetic, `#pragma once`, `__has_include`.
- Parsing (`vendor/pycparser`, `syntax.py`): the syntax tree. `syntax.py` turns
  pycparser's "before: X" into a message in plain words (`expected ';' before 'return'`,
  `unknown type name 'uint8_t'`).
- Front end (`front.py`, `ctypes816.py`, `fp.py`): types and their sizes, conversions,
  constant folding (floats rounded as the run-time code rounds them: `fp.py`), the memory
  model (near and far pointers, which locals live in the software-stack frame), warnings.
  It writes the IR.
- Optimisation (`opt.py`, `-O1`, `-O2`): CFG clean-up, constant and copy propagation,
  algebraic simplification, strength reduction (multiplies and divides by constants,
  induction variables of array loops), dead code. `-O2` adds the loop optimisations.
- Register allocation (`regalloc.py`): virtual registers to direct-page registers
  (`__rg`, scratch and callee-saved) or hardware-stack slots.
- Code generation (`gen.py`): 65816 instructions with 16-bit A, X and Y, calls, the
  arithmetic helpers, far accesses.
- Peephole optimisation (`peep.py`): removes loads of values a register already holds and
  dead stores, folds jumps, and relaxes branches that are out of range (an inverted branch
  over a `JMP`, or `JMP` for a `BRL` past 30,000 bytes).
- Diagnostics (`diag.py`): every message in gcc's form, with the user's file and line.

`driver.py` holds the options and runs the passes. `ir.py` defines the intermediate
representation: basic blocks of `mov`, `add`, `ld`, `st`, `call`, `br`, ... on virtual
registers of 2 or 4 bytes.

## Reading the output

`hcc -S` writes FILE.s next to each .c and continues the build.
`python3 sdk/c/cc816/cc816.py -S file.c` writes it without building. `--ir` prints the IR
after optimisation on stderr. This program prints `sum: 120003`:

```c
#include <stdio.h>

/* the sum of n 16-bit values */
unsigned long sum(const unsigned *p, unsigned n)
{
    unsigned long s = 0;
    unsigned i;
    for (i = 0; i < n; i++)
        s += p[i];
    return s;
}

static const unsigned v[4] = { 60000u, 60000u, 1, 2 };

int main(void)
{
    printf("sum: %lu\n", sum(v, 4));
    return 0;
}
```

The code for `sum` (`-O2`, the small code model; the comments are added here):

```asm
_sum:
	lda	3,s             ; p: the first argument, above the 2-byte return address
	sta	__rg+16
	lda	5,s             ; n (lda sets Z: the beq below tests n == 0)
	sta	__rg+14
	stz	__rg+4          ; s, low word
	stz	__rg+6          ; s, high word
	stz	__rg+0          ; i
	beq	Lsum_b0
Lsum_b1:
	lda	__rg+0
	asl	a
	sta	__rg+2          ; i * 2: the byte offset, kept beside i (strength reduction)
Lsum_b2:
	ldy	__rg+2
	lda	(__rg+16),y     ; p[i]: a near pointer is an offset in the code bank (DBR)
	sta	__rg+10
	stz	__rg+12
	clc
	lda	__rg+4
	adc	__rg+10
	sta	__rg+4
	lda	__rg+6
	adc	__rg+12
	sta	__rg+6
	inc	__rg+0
	inc	__rg+2
	inc	__rg+2
	lda	__rg+0
	cmp	__rg+14
	bcc	Lsum_b2
Lsum_b0:
	ldx	__rg+6          ; a 32-bit result: A the low word, X the high word
	lda	__rg+4
	rts
```

How to read it:

- `__rg+n` are the direct-page registers: `__rg+0` to `+47` scratch, `+48` to `+95`
  callee-saved.
- `n,s` are arguments and spill slots on the hardware stack.
- `(__rg+k),y` is a near pointer, `[__rg+k],y` a far one.
- `jsr` (small model) or `jsl` (large) to `__mul16`, `__sdiv32`, `__fadd` ... are calls
  of the runtime's helpers.
- The caller (`main`) pushes the arguments last first (`pea $0004`, `pea _v`), calls, and
  removes them (`ply`, `ply`).

The rules: [reference.md](reference.md), "Calling convention (for assembly)".

The IR of the same function (`cc816.py --ir -S sum.c`):

```
func _sum:
 entry: (depth 0)
    mov %s3L = #0
    mov %i4 = #0
    br %n2, #0 cc='ne' t=<loop_pre> f=<endloop>
 loop_pre: (depth 0)
    shl %ix8 = %i4, #1
    jmp t=<loop>
 loop: (depth 1)
    ld %6 = base=%p1 idx=%ix8 off=0 sz=2 sgn=False vol=False ilo=0
    zx %7L = %6
    add %s3L = %s3L, %7L
    add %i4 = %i4, #1
    add %ix8 = %ix8, #2
    br %i4, %n2 cc='ult' t=<loop> f=<endloop>
 endloop: (depth 0)
    ret %s3L
```

`%name` is a virtual register (`L`: 4 bytes), `depth` the loop depth. For profiling a
whole program: [tools.md](../tools.md#prof816py).

## Sizes and models

| Type | Size |
| --- | --- |
| `char` | 8 bits, unsigned (`-fsigned-char`: signed) |
| `short`, `int` | 16 bits |
| `long` | 32 bits |
| `long long` | 64 bits |
| `float`, `double`, `long double` | 32 bits, IEEE 754 single precision |
| data pointer | 16 bits (an offset in the main bank); `__far` 32; with `--data far` 32 |
| function pointer | 16 bits |
| `size_t`, `ptrdiff_t` | 16 bits |

Structures are packed (no padding). Details and the predefined macros: reference.md,
"Types".

There are three configurations. The C library, hgame and the controls library are built
for each.

### Small (default)

- Code: one 64 KB bank, shared with everything else.
- Calls: JSR / RTS.
- Plain data pointer: 16 bits, the main bank.
- Heap, literals, `const`: the main bank.
- Requires: any Horizon.
- For: most programs.

### `--code large`

- Code: the main bank, then up to 64 more banks.
- Calls: JSL / RTL.
- Plain data pointer: 16 bits, the main bank.
- Heap, literals, `const`: the main bank.
- Requires: Horizon 0.28 when code leaves the main bank.
- For: programs with more code than one bank holds.

### `--code large --data far`

- Code and calls: as in the large model.
- Plain data pointer: 32 bits, any bank.
- Heap, literals, `const`: other banks.
- Requires: Horizon 0.28.
- For: DOS large-model C (the X-COM port).

### Costs

Measured in the emulator with its board-timing model: a call costs 2 cycles more in the
large model, so the benchmarks run the same to 10 % slower (fib22, nothing but calls, the
most). Far data costs 8-20 % on loops through pointers, twice as much for a call with
pointer arguments, and makes code about a quarter larger where pointers are everywhere.
The tables: [reference.md](reference.md#costs), "Code models" ("Costs"), and
[reference.md](reference.md#far-data-costs), "Far data model" ("Far data costs").

## Options

`hcc -h` and `cc816.py --help` print them. hcc passes the compiler's options to cc816.
`hcc --version` prints the version.

### Output

- `-o FILE`: the program (default: the first source's name in capitals, `.PRG`). With
  `-c` and one source, the object.
- `-c`: compile or assemble only, one `.o` per source.
- `-S`: (hcc) also write each .c's assembly next to it, then continue. (cc816.py) write
  the assembly, the default.
- `-E`: (cc816.py) preprocess only, to stdout or `-o FILE`.
- `--map`: (hcc) write FILE.map (ld65's map) and FILE.lbl (every label, read by the
  profiler) and print the sizes.
- `--sizes`: (hcc) every object and function, its size and where it went, biggest first.
  Also printed when the program does not fit.
- `--keep DIR`: (hcc) keep the intermediate links in DIR.
- `-v`: (hcc) show the commands.

### Preprocessor

`-I DIR`, `-D NAME[=VALUE]`, `-U NAME` (applied in the order given), `-include FILE`.

### Language

- `-std=c89` (also `c90`, `gnu89`, `gnu90`, `iso9899:1990`, `-ansi`): C89, which turns on
  `-fimplicit-int` and `-fextra-args`. `-std=c99`, `c11`, `c17`, `c23` and the `gnu`
  forms are accepted and change nothing.
- `-fimplicit-int`, `-fno-implicit-int`: C89's implicit int is a warning, not an error.
- `-fextra-args`, `-fno-extra-args`: more arguments than the prototype is a warning.
- `-fdos-keywords`: `far`, `near` and `huge` are keywords (`__far`, `__near`, `__far`).
  Implies the two options above.
- `-fsigned-char`: plain `char` is signed.
- `-fno-merge-strings`, `-fwritable-strings`: each string literal is its own object (and,
  with the second, in the data).
- `-fargs-right-to-left`: arguments are evaluated right to left, as DOS's compilers did.
- `-ffar-wrap`: far pointer arithmetic on the offset alone (DOS's far pointers).

The DOS-compatibility options and the reason for each: reference.md, "Old C", and
[porting.md](porting.md), "Porting a DOS large-model program".

### Code generation and models

- `-O0`, `-O1`, `-O2`: optimisation. `-O2` is the default, `-O1` has no loop
  optimisations, `-O0` none. `-O3` and `-Os` are `-O2`.
- `--code small|large`: the code model (also `$HZ_CODE`).
- `--data near|far`: the data model (also `$HZ_DATA`). far requires `--code large`.
- `--stack N`: (hcc) the software stack in bytes (512-32,768, default 8,192).
- `--heap N`: (hcc, `--code large`) main-bank bytes kept for `malloc` when hcc fills the
  bank with code (default 4,096).
- `--main-room N`, `--bank-room N`, `--spread N`: (hcc, `--code large`, for tests) the code
  allowed in the main bank and in each other bank, and the functions placed in turn in N
  banks (also `$HZ_MAIN_ROOM`, `$HZ_BANK_ROOM`, `$HZ_SPREAD`).
- `--no-stack-check`: (hcc) no software-stack check at the entry of the program's own
  functions.
- `--debug`: (hcc) paint the stacks. At exit the program prints how much of each it used
  and the heap's peak.

### Linking

- `--ui`: the controls library. hcc adds it when the program uses a name of `hui.h`.
- `--game`: hgame. hcc adds it for `<hgame.h>`, `<conio.h>` and `<joystick.h>`.
- `-l FILE`: an extra object or library.
- `-lm`: accepted and ignored.
- `--needs LIST`: what the program checks it has when it starts
  ([../apps.md](../apps.md), "What a program needs").

### Warnings and audit

`-w`, `-Wall`, `-Werror`, `-WNAME`, `-Wno-NAME`. The audit options `--check-calls` and
`--set` are described under [Diagnostics](#diagnostics).

### cc816.py only

- `--ir`: the IR after optimisation, on stderr.
- `--time`: the time of each pass.
- `--trace`: a Python traceback with an internal compiler error. `CC816_TRACE=1` in the
  environment does the same and also works through hcc.

## Diagnostics

Every message has gcc's form, `file.c:LINE:COL: error: ...` or `warning: ... [-Wname]`,
with the place in the user's file (through `#include` and `#line`). After an error cc816
continues and reports the whole file, then stops without output (hcc exits 1). A link
error is reported in C's terms (`undefined: fire_laser (used in game.c)`). A program that
is too big gets an error with the excess in bytes and the remedy. The list of warnings,
and which are on by default, which need `-Wall` and which only when named: reference.md,
"Errors and warnings".

Two warnings matter more here than on a PC: `-Woverflow` (a constant that a 16-bit `int`
changes; `-w` does not silence it) and `-Wformat` (`%d` given a `long`).

`hcc --check-calls a.c b.c ...` reads a program's files together and builds nothing. It
reports every call without a prototype and every prototype that disagrees with the
definition in another file, by the sizes of the arguments and of the result (an `int`
pushed where a far pointer is read, an implicit `int` result where a function returns a
far pointer, the value of a `void` function). It exits 1 when one disagrees. `--set`
gives groups of files their own `-D`, `-U`, `-I` and `-include`:

```
hcc --check-calls --code large --data far -I src --set -DGAME src/*.c --set port/*.c
```

Details: reference.md, "Old C".

An internal compiler error is a fault of cc816, not of the program. It is one line:
`file.c: internal compiler error: ... (please report; CC816_TRACE=1 shows where)`.

## Limits

cc816 does not support the following. Each is rejected with an error that starts "cc816
does not support" and names the alternative: a 64-bit `double`, variable-length arrays,
`__int128`, `_Complex`, GNU asm operand lists, labels as values, nested functions, GCC's
built-ins, `#include_next`, an object of 65,536 bytes or more ([reference.md](reference.md),
"What cc816 does not support"). Other limits:

- One object (array, structure, `malloc` block) is at most 65,535 bytes and must not cross
  a bank. Bigger data goes to `hz_far_alloc` banks or files.
- `inline` is accepted and ignored: every function is a call.
- A `long` divided by a constant that is not a power of two is a call (`__sdiv32`,
  `__udiv32`). 16-bit divisions by any constant are inline.
- Parameters past 255 bytes of hardware stack (about 120 `int` parameters) are an error.
- In the small model, code, constants, data and bss share 57,072 bytes with the default
  software stack. When they do not fit, use `--code large`, `--stack N` or far data (the
  error message names which).

## Reporting compiler faults

A compiler fault is code that gives a different result than C specifies (or than gcc gives
for the same program with 16-bit `int`), an internal compiler error, or assembly that ca65
or ld65 rejects. To report one:

1. Reduce it. Cut the program down until the fault is a few lines in one file that prints
   or returns the wrong value. Keep the same `-O` level, and also try `-O0` and `-O1`.
   Note when the result changes with the level.
2. Give the commands and the versions: the hcc line (`hcc -v` prints the rest), the
   Horizon release (`git describe` or the top of `horizon/README.md`), and the
   configuration (`--code`, `--data`).
3. Run it alone. `python3 sdk/tools/run816.py PROG.PRG --mode shell --expect 'TEXT'` runs
   it in the emulator without the rest of the program. A host build of the same C
   (`sdk/c/tools/host16.py cc ...`: the PC with the Atari816's integer sizes) gives the
   expected result ([tools.md](../tools.md#host16py)).
4. Attach the C file, the assembly (`hcc -S`), and for an internal error the traceback
   (`CC816_TRACE=1 hcc ...`).
