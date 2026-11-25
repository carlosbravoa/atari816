# cc816, the compiler

cc816 is the SDK's own C compiler for the 65C816 and Horizon. It is written in Python 3
(`sdk/c/cc816`), reads C99, most of C11, old C and some GNU C, and writes ca65 assembly.
`hcc` (`sdk/c/bin/hcc`) is the driver around it: it compiles, assembles with ca65, links
with ld65 and the C library, and checks the sizes. Nothing is downloaded: the
preprocessor (pcpp) and the parser (pycparser) are vendored in `sdk/c/cc816/vendor` (BSD
licences); the rest is cc65's ca65, ld65 and ar65.

This chapter is about the compiler itself: how it works, its options, how to read what it
writes, its limits, its tests, and how to report a fault. The C language as cc816 has it
(memory, the code and data models, types, the calling convention, inline assembly, the
library) is in [reference.md](reference.md); this page links to its sections instead of
repeating them.

## From C to a program

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

| Pass | Module | What it does |
| --- | --- | --- |
| preprocess | `vendor/pcpp` (driven by `driver.py`) | `#include`, macros, `#if` with C's arithmetic, `#pragma once`, `__has_include` |
| parse | `vendor/pycparser`, `syntax.py` | the syntax tree; `syntax.py` turns pycparser's "before: X" into a message in plain words (`expected ';' before 'return'`, `unknown type name 'uint8_t'`) |
| front | `front.py`, `ctypes816.py`, `fp.py` | types and their sizes, conversions, constant folding (floats rounded as the run time does: `fp.py`), the memory model (near and far pointers, which locals live in the software-stack frame), warnings; writes the IR |
| optimise | `opt.py` (`-O1`, `-O2`) | CFG clean-up, constant and copy propagation, algebraic simplification, strength reduction (multiplies and divides by constants, induction variables of array loops), dead code; `-O2` adds the loop optimisations |
| register allocation | `regalloc.py` | virtual registers to direct-page registers (`__rg`, scratch and callee-saved) or hardware-stack slots |
| code generation | `gen.py` | 65816 instructions, 16-bit A, X, Y; calls, the arithmetic helpers, far accesses |
| peephole | `peep.py` | drops loads of what a register already holds and dead stores, folds jumps, relaxes branches that do not reach (an inverted branch over a `JMP`, or `JMP` for a `BRL` past 30,000 bytes) |
| diagnostics | `diag.py` | every message in gcc's form, the user's file and line |

`driver.py` holds the options and runs the passes; `ir.py` defines the intermediate
representation (basic blocks of `mov`, `add`, `ld`, `st`, `call`, `br`, ... on virtual
registers of 2 or 4 bytes). The linking side is in `sdk/c/tools`: `hzc816.py` (the
library builds, ld65, the size messages), `hzlarge.py` and `ca65obj.py` (the large code
model's placement of functions in banks), `o65strip.py`, `hui816.py` (the controls
library). [tools.md](../tools.md) describes each.

## Reading its output

`hcc -S` writes FILE.s next to each .c and goes on with the build;
`python3 sdk/c/cc816/cc816.py -S file.c` writes it without building. `--ir` prints the
IR after optimisation on stderr. This program (built and run in the emulator; it prints
`sum: 120003`):

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

gives, for `sum` (`-O2`, the small code model):

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

(the comments are added here). What to look for: `__rg+n` are the direct-page registers
(`__rg+0` to `+47` scratch, `+48` to `+95` callee-saved); `n,s` are arguments and spill
slots on the hardware stack; `(__rg+k),y` is a near pointer, `[__rg+k],y` a far one; `jsr`
(small model) or `jsl` (large) to `__mul16`, `__sdiv32`, `__fadd` ... are the runtime's
helpers. The caller (`main`) pushes the arguments last first (`pea $0004`, `pea _v`),
calls, and takes them off (`ply`, `ply`). The rules: [reference.md](reference.md),
"Calling convention (for assembly)".

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

`%name` is a virtual register (`L`: 4 bytes), `depth` the loop depth. Where the time goes
in a whole program: the profiler ([tools.md](../tools.md), "prof816.py").

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

The three configurations, each built and tested as a whole (the C library, hgame and the
controls library exist for each):

| | small (default) | `--code large` | `--code large --data far` |
| --- | --- | --- | --- |
| Code | one 64 KB bank with everything else | the main bank, then up to 64 more banks | as large |
| Calls | JSR / RTS | JSL / RTL | JSL / RTL |
| Plain data pointer | 16 bits, the main bank | 16 bits, the main bank | 32 bits, any bank |
| Heap, literals, `const` | the main bank | the main bank | other banks |
| Needs | any Horizon | Horizon 0.28 when code leaves the main bank | Horizon 0.28 |
| Made for | most programs | programs with more code than one bank | DOS large-model C (the X-COM port) |

What they cost, measured in the emulator with its board-timing model: a call 2 cycles
more in the large model, so the benchmark runs the same to 10 % slower (fib22, nothing
but calls, the most); far data 8-20 % on loops through
pointers, twice as much for a call with pointer arguments, code about a quarter larger
where pointers are everywhere. The tables: reference.md, "The two code models" ("Costs")
and "The far data model" ("What it costs").

## Options, by purpose

`hcc -h` and `cc816.py --help` print them; hcc passes the compiler's options to cc816.

**Output.**

| Option | What |
| --- | --- |
| `-o FILE` | the program (default: the first source's name in capitals, `.PRG`); with `-c` and one source, the object |
| `-c` | compile or assemble only: one `.o` per source |
| `-S` | (hcc) also write each .c's assembly next to it, then go on; (cc816.py) write the assembly, the default |
| `-E` | (cc816.py) preprocess only, to stdout or `-o FILE` |
| `--map` | (hcc) write FILE.map (ld65's map) and FILE.lbl (every label: the profiler reads it) and print the sizes |
| `--sizes` | (hcc) every object and function, its size and where it went, biggest first; also when the program does not fit |
| `--keep DIR` | (hcc) keep the intermediate links in DIR |
| `-v` | (hcc) show the commands |

**The preprocessor.** `-I DIR`, `-D NAME[=VALUE]`, `-U NAME` (in the order given),
`-include FILE`.

**The language.**

| Option | What |
| --- | --- |
| `-std=c89` (`c90`, `gnu89`, `gnu90`, `iso9899:1990`, `-ansi`) | C89: `-fimplicit-int` and `-fextra-args`. `-std=c99`, `c11`, `c17`, `c23` and the `gnu` forms are accepted and change nothing |
| `-fimplicit-int`, `-fno-implicit-int` | C89's implicit int as a warning, not an error |
| `-fextra-args`, `-fno-extra-args` | more arguments than the prototype as a warning |
| `-fdos-keywords` | `far`, `near`, `huge` are keywords (`__far`, `__near`, `__far`); implies the two above |
| `-fsigned-char` | plain `char` is signed |
| `-fno-merge-strings`, `-fwritable-strings` | each string literal its own object (and, with the second, in the data) |
| `-fargs-right-to-left` | arguments evaluated right to left, as DOS's compilers did |
| `-ffar-wrap` | far pointer arithmetic on the offset alone (DOS's far pointers) |

The DOS-compatibility options and why each exists: reference.md, "Old C", and
[porting.md](porting.md), "Porting a DOS large-model program".

**Code generation and models.**

| Option | What |
| --- | --- |
| `-O0`, `-O1`, `-O2` | optimisation: `-O2` the default; `-O1` no loop optimisations; `-O0` none. `-O3` and `-Os` are `-O2` |
| `--code small\|large` | the code model (also `$HZ_CODE`) |
| `--data near\|far` | the data model (also `$HZ_DATA`); far needs `--code large` |
| `--stack N` | (hcc) the software stack in bytes (512-32,768, default 8,192) |
| `--heap N` | (hcc, `--code large`) main-bank bytes kept for `malloc` when hcc fills the bank with code (default 4,096) |
| `--main-room N`, `--bank-room N`, `--spread N` | (hcc, `--code large`, for tests) code allowed in the main bank and in each other bank; the functions in turn in N banks (also `$HZ_MAIN_ROOM`, `$HZ_BANK_ROOM`, `$HZ_SPREAD`) |
| `--no-stack-check` | (hcc) no software-stack check at the entry of the program's own functions |
| `--debug` | (hcc) paint the stacks; at exit the program prints how much of each it used and the heap's peak |

**Linking.** `--ui` (the controls library; hcc adds it by itself when a name of `hui.h`
is used), `--game` (hgame; added by itself for `<hgame.h>`, `<conio.h>`, `<joystick.h>`),
`-l FILE` (an extra object or library), `-lm` (accepted and ignored), `--needs LIST`
(what the program checks it has when it starts: [../apps.md](../apps.md), "What a program
needs").

**Warnings.** `-w`, `-Wall`, `-Werror`, `-WNAME`, `-Wno-NAME`. **Audit.** `--check-calls`
and `--set` (below).

**The compiler alone** (`cc816.py`): `--ir` (the IR after optimisation, on stderr),
`--time` (the time of each pass), `--trace` (a Python traceback with an internal compiler
error; also `CC816_TRACE=1` in the environment, which works through hcc).

## Diagnostics

Every message has gcc's form, `file.c:LINE:COL: error: ...` or `warning: ... [-Wname]`,
with the place in the user's file (through `#include` and `#line`). cc816 goes on after an
error and reports the whole file, then stops without output (hcc exits 1). A link error
is said in C's words (`undefined: fire_laser (used in game.c)`); a program too big says by
how many bytes and what to do. The list of warnings, which are on by default, which need
`-Wall` and which only when named: reference.md, "Errors and warnings".

Two warnings matter more here than on a PC: `-Woverflow` (a constant that a 16-bit `int`
changes; `-w` does not silence it) and `-Wformat` (`%d` given a `long`).

**`hcc --check-calls a.c b.c ...`** reads a program's files together and builds nothing.
It reports every call without a prototype and every prototype that disagrees with the
definition in another file, by the sizes of the arguments and of the result (an `int`
pushed where a far pointer is read; an implicit `int` result where a function returns a
far pointer; the value of a `void` function), and exits 1 when one disagrees. `--set`
gives groups of files their own `-D`, `-U`, `-I` and `-include`:

```
hcc --check-calls --code large --data far -I src --set -DGAME src/*.c --set port/*.c
```

Details: reference.md, "Old C".

An internal compiler error is a fault of cc816, not of the program: one line,
`file.c: internal compiler error: ... (please report; CC816_TRACE=1 shows where)`.

## Limits

What cc816 does not have, each refused with an error that starts "cc816 does not support"
and says what to do instead: a 64-bit `double`, variable-length arrays, `__int128`,
`_Complex`, GNU asm operand lists, labels as values, nested functions, GCC's built-ins,
`#include_next`, an object of 65,536 bytes or more ([reference.md](reference.md), "What
cc816 does not support"). Other limits:

- One object (array, structure, `malloc` block) is at most 65,535 bytes and must not cross
  a bank; bigger data goes to `hz_far_alloc` banks or files.
- `inline` is read and ignored: every function is a call (reference.md, "Faults found and
  fixed", the notes after it, say what inlining would take).
- A `long` divided by a constant that is not a power of two is a call (`__sdiv32`,
  `__udiv32`); 16-bit divisions by any constant are inline.
- Parameters past 255 bytes of hardware stack (about 120 `int` parameters) are an error.
- The small model's code, constants, data and bss share 57,072 bytes with the default
  software stack: `--code large`, `--stack N` or far data when they do not fit (the
  messages say which).

## How it is tested

`make -C sdk/c/cc816 check` runs `tests/check.py` in the three configurations (small,
large with every function in another bank, large with far data; `CODES=` chooses):

| Part | What |
| --- | --- |
| `tests/diag/` | 125 C files, each listing the errors and warnings it must give (`// EXPECT:` lines) and nothing else; no emulator (`make -C sdk/c/cc816 diag`, seconds). Then 400 programs with one random change each must give messages or compile, never an internal error |
| `tests/regress/` | 58 programs, one for each fault found (each returns 0 when the fault is not there); those marked `LEVELS: 0 1 2` also at `-O0` and `-O1` |
| `tests/lang/` | 29 programs, one for each part of C the front end has (K&R, designators, compound literals, bit-fields, `long long`, `setjmp`, inline assembly, the GNU extensions, ...) |
| random programs | `tests/fuzz/genfuzz.py`: seeds 1, 2 and 3, checked against gcc's results on the PC; integer programs (every width, structures, bit-fields, far pointers, switches, ...), negative-index programs and floating-point programs (bit for bit against gcc's SSE single precision) |
| c-testsuite | its single-exec programs, when `CTS=` points at a checkout (`git clone https://github.com/c-testsuite/c-testsuite`); the ones cc816 does not pass for a known reason are listed in `tests/cts-known.txt` |

Every program runs under Horizon in emu816 with `--log-bankwrap`: an indexed access that
carries into the next bank fails it. `make -C sdk/c/cc816 quick` is the same with fewer
random programs, `make -C sdk/c/cc816 sdk` compiles every C file of the SDK. The results
at the last full run, and the fault list: reference.md, "How it is tested" and "Faults
found and fixed". The C library, the runtime and the code models are tested by
`make -C sdk/c test` ([testing.md](../testing.md)); the ports are the acceptance test of
the whole compiler ([../README.md](../README.md), "The ports").

`CC816_FLAGS="-fargs-right-to-left"` (or `-ffar-wrap`) in the environment builds every
program of the set with that option too: their results must not change.

## Reporting a fault

A fault of the compiler is code that gives another result than C says (or than gcc gives
for the same program with 16-bit `int`), an internal compiler error, or assembly that
ca65 or ld65 refuses. To report one, or fix it:

1. **Make it small.** Cut the program down until the fault is a few lines in one file
   that prints or returns what is wrong. Keep `-O` the same; try `-O0` and `-O1`: when
   the result changes with the level, say so.
2. **Show the commands and the versions.** The hcc line (`hcc -v` prints the rest), the
   Horizon release (`git describe` or the top of `horizon/README.md`), the configuration
   (`--code`, `--data`).
3. **Run it alone.** `python3 sdk/tools/run816.py PROG.PRG --mode shell --expect 'TEXT'`
   shows it in the emulator without the rest of the program; a host build of the same C
   (`sdk/c/tools/host16.py cc ...`: the PC with the Atari816's integer sizes) shows what
   the result should be ([tools.md](../tools.md), "host16.py").
4. **Attach** the C file, the assembly (`hcc -S`), and for an internal error the
   traceback (`CC816_TRACE=1 hcc ...`).
5. **Make it a test.** A fixed fault becomes `sdk/c/cc816/tests/regress/rNNN_name.c`: a
   comment that says what went wrong, then `int main(void)` that returns 0 when the fault
   is not there and another value when it is; add `LEVELS: 0 1 2` to the comment when the
   code differs between levels. A wrong or missing message becomes a `tests/diag/` file
   with `// EXPECT:` lines. `make -C sdk/c/cc816 check` picks both up by themselves.
