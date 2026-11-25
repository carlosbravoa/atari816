# C on Horizon: the language as cc816 implements it

Read this when you write or port C for Horizon: types, memory, far data, stacks, limits,
inline assembly, `.s` files called from C, warnings, hcc's options and its messages. The
C library and the `hz_` calls: references/c-library.md. Full text:
`sdk/docs/c/reference.md`, `sdk/docs/c/porting.md`.

## Build and run

```sh
SDK/c/bin/hcc -o TYPES.PRG types.c                         # small code model, -O2
SDK/c/bin/hcc --code large -o CALLASM.PRG callasm.c add3.s  # large model, with a .s file
python3 SDK/tools/run816.py TYPES.PRG --horizon HORIZON --mode shell --args 'one "two words"' --seconds 4
cat run-types/console.txt          # what it printed (default --out: run-<name in lower case>)
```

cc816 is the only compiler (Python 3; it writes ca65 assembly; hcc links with ld65). It
reads C99, most of C11 (`_Static_assert`, `_Generic`, anonymous structs/unions) and much
of GNU C (statement expressions, `typeof`, case ranges, `__attribute__((noreturn,
naked))`). A program's Makefile from `sdk/c/c.mk`: `HZ_CODE := large`, `HCCFLAGS := ...`.

## Types

Checked with `printf` of `sizeof` in both code models:

| Type | Bytes | Note |
| --- | --- | --- |
| `char` | 1 | **unsigned** (0-255, `CHAR_MIN` 0, `__CHAR_UNSIGNED__` defined). `-fsigned-char`: signed (`(int)(char)200` is -56) |
| `short`, `int` | 2 | **16 bits**: -32,768..32,767. `30000 + 10000` as `int` is -25,536 |
| `long` | 4 | `int32_t`. Use it for sizes, file positions, milliseconds, products of ints |
| `long long` | 8 | full 64-bit support, `%lld`; slow (a 64-bit divide is about 1 ms) |
| `float`, `double`, `long double` | 4 | **all three IEEE single precision** (about 7 digits). `DBL_DIG` is 6 |
| data pointer | 2 | an offset in the main bank (DBR) |
| `T __far *` | 4 | offset, bank, 0: any bank |
| function pointer | 2 | the function (small) or its main-bank entry (large) |
| `size_t`, `ptrdiff_t` | 2 | `unsigned int`, `int`: one object at most 65,535 bytes |
| `wchar_t` | 2 | `unsigned int` |

Structures are packed (no padding), little-endian. `_Alignof` is always 1. Bit-fields:
`int` fields up to 16 bits, `long` up to 32. Enumerators above 32,767 are `unsigned int`,
above 65,535 `long`.

**Predefined macros**: `__CC816__`, `__65816__`, `__HORIZON__`, `__ATARI816__`,
`__CHAR_UNSIGNED__` (not with `-fsigned-char`), `__CC816_LARGE__` (only with `--code
large`; also in `.s` files).

## Memory layout

```
main bank (64 KB, DBR; the "code bank" in the small model)
$0100  code (small model), constants, initialised data, bss
       heap (malloc, fopen's buffers) ... grows up
       software stack guard (256 bytes)
       software stack ... grows down          --stack N (default 8192)
$FFF0
window (bank 0, 32 KB, private)
$0000  direct page: cc816's registers $00-$77 (+ the controls library's)
$0100  hardware stack guard (256 bytes) ... hardware stack, grows down from $7F7F
other banks: hz_far_alloc() banks, __far objects (large model), code banks (large model)
```

Every near pointer (globals, string literals, `malloc` blocks, local arrays) is in the
main bank, so any near pointer reaches any of them. `hcc --map` prints the parts:

```
HEAP.PRG: 9,796 bytes on the card, 8 relocations
  code bank: code+constants 9,571 + data 84 + bss 942 = 10,597 of 57,072; heap 46,475; software stack 8,192
```

## The two code models

| | small (default) | large (`--code large`, `HZ_CODE=large`) |
| --- | --- | --- |
| Code | all in the main bank | main bank while it has room, then up to 64 more banks |
| Calls | JSR/RTS, first argument at `3,s` | JSL/RTL, first argument at `4,s` |
| Data, constants, bss, heap, stacks | main bank | main bank (the same) |
| `__far` objects | stay in the main bank | banks of their own, loaded with the program |
| File | NAME.PRG | still one NAME.PRG (extra banks follow the o65); needs Horizon 0.28+ when code went to other banks |
| Cost | | +2 cycles a call, +1 byte a call site; speed nearly the same |

Use `--code large` when hcc says "program too big by N bytes: build with --code large"
(code is the big part). It does **not** help when data is too big: the main bank must
still hold constants + data + bss + 4 KB heap (`--heap N`) + the software stack. Nothing
in the C changes. All objects and libraries of a program must be built for one model
(hcc refuses a mix; it builds its libraries for both). Functions with inline asm and
`.s` code stay in the main bank, except `.s` functions opened with `FUNC` ("Movable
assembly", below). One function must fit in 65,535 bytes.

## Far data

A near pointer cannot point into another bank. Memory in other banks needs `__far`
pointers (32 bits, long addressing). Tested in both models:

```c
#include <stdio.h>
#include <horizon.h>

__far const unsigned char table[4][3] = { {1,2,3}, {4,5,6}, {7,8,9}, {10,11,12} };

int main(void)
{
    unsigned char __far *buf = hz_far_alloc();      /* a whole 64 KB bank, offset 0 */
    char back[16];
    const unsigned char __far *row;
    if (buf == NULL) { printf("no bank\n"); return 1; }
    buf[60000u] = 42;                               /* any offset 0-65535 */
    hz_far_copy(buf + 1000, "hello far", 10);       /* near -> far */
    hz_far_copy(back, buf + 1000, 10);              /* far -> near: back to printf */
    printf("bank %u: %s %u\n", HZ_BANK(buf), back, buf[60000u]);
    printf("same: %d\n", HZ_FARPTR(HZ_BANK(buf), 1000) == buf + 1000);
    row = table[2];                                 /* a far object's address is far */
    printf("table[2][1] = %u, row[2] = %u\n", table[2][1], row[2]);
    hz_far_set(buf, 0, 4096);
    hz_far_free(buf);                               /* also freed at exit */
    return 0;
}
```

| Name | What |
| --- | --- |
| `void __far *hz_far_alloc(void)` | a fresh bank (contents undefined), NULL if none (`hz_mem_info()`: free banks; 92 in all, about 80 free) |
| `hz_far_free(p)` | give p's bank back |
| `hz_far_copy(dst, src, n)`, `hz_far_set(dst, c, n)` | MVN, about 7 cycles a byte; a range must not cross a bank, a copy must not overlap |
| `hz_farptr(bank, off)`, `HZ_FARPTR(bank, off)` | a far pointer from bank and offset; `(char __far *)0x050000L` is the same as `hz_farptr(5, 0)` |
| `HZ_OFF(p)`, `HZ_BANK(p)` | offset and bank of any pointer (a near one gives the main bank) |
| `__far` at file scope | a far object (`__far const short sine[1024] = {...};`, `__far short work[4096];`); `extern __far ...` in other files |

Rules:
- Near converts to far by itself (bank = main bank). Far to near keeps only the offset:
  `-Wfar-pointer` warns on assignment, `-Wall`'s `-Wfar-cast` on a cast. Never write
  `(char *)hz_far_alloc()`.
- The C library and `hui.h` take near pointers: copy far data into a main-bank buffer
  (`hz_far_copy`) before `printf`, `strcmp`, `fwrite` and the like (with near data; with
  `--data far`, below, the library takes far pointers).
- Cost: a far access builds a 32-bit address; `a[i][j]` in a `__far` object and an
  unsigned index through a far pointer use `[base],y` (cheap); a signed index keeps the
  32-bit add. Keep hot inner-loop data near when it fits.
- An object (array, struct, `malloc` block) never crosses a bank: pointer arithmetic is
  16-bit within the bank.

## The far data model (`--data far`)

`hcc --code large --data far` (c.mk: `HZ_CODE := large`, `HZ_DATA := far`) makes every
plain data pointer far, as in a DOS large-model program: for ports of such programs
(`ports/xcom`) and for programs whose data is far bigger than one bank.

| | near data (default) | far data |
| --- | --- | --- |
| `char *p`, `sizeof(void *)` | 16 bits, 2 | 32 bits (offset, bank, 0), 4; `char __near *` is 16 bits |
| `size_t`, `ptrdiff_t`, `intptr_t` | 16, 16, 16 bits | 16, 16, 32 bits |
| string literals, `const` objects | main bank | far data banks (long addressing) |
| writable globals and statics | main bank | main bank (unless `__far`) |
| `malloc` | the main bank's leftover | the main bank's room, then 64 KB banks from Horizon (a block at most 65,528 bytes) |
| C library, hgame | near pointers | far pointers (`build/lib/large-far`); `hui.h` not available |
| `__CC816_FAR_DATA__` | undefined | 1 (C and ca65) |

- A near address (a global, `&local`, a local array) converts to far by itself (the main
  bank). `printf("%s", s)` takes any string; `%p` prints `0x` and 6 digits.
- Assembly: a pointer argument is 4 bytes; `model.inc` gives `PTRSZ` (2/4) and
  `FARDATA` (0/1): `lda ARGS+PTRSZ,s` is the argument after a pointer.
- Objects of the two data models never mix (hcc refuses: "an object made for the large
  code model; this program is linked for the large code model with far data").
- A port keeps its declarations: `T far *a, far *b;`, `void (far *f)(void)` (warning:
  ignored), `#pragma aux` (warning: needs a C body) all compile.
- Cost: pointers are 4 bytes everywhere; loops through pointers are about 8-20 % slower,
  calls with pointer arguments about twice as slow, code about 27 % bigger.

## Stacks and heap

| | Size | What lives there |
| --- | --- | --- |
| Hardware stack (window) | about 32,000 bytes, fixed | return addresses, arguments, spilled registers |
| Software stack (main bank) | `--stack N`, 512-32,768, even; default 8,192 | arrays, structures, `volatile` locals, locals whose address is taken |
| Heap (main bank) | what is left (about 46 KB for a small program; less as code grows) | `malloc`, 1 KB per `fopen` |

- Big local arrays: make them `static` or `malloc` them. 64 KB-scale buffers:
  `hz_far_alloc`.
- `hcc --debug` prints at exit: `stack: 115 of 32253 bytes used`, `software stack: 16 of
  3840 bytes used`, `heap: 1028 of 50395 bytes used at most ...`.
- At any time: `hz_heap_free()`, `hz_heap_largest()`, `hz_heap_peak()`,
  `hz_stack_free()`, `hz_sstack_free()`, `hz_stack_check()` (-1 if a guard was written).
- **Software stack overflow** is caught at the entry of the function whose frame does not
  fit, before the heap (just under the stack) is touched: `software stack overflow:
  build_atlas needs a frame of 3700 bytes; 396 of the software stack's 4096 bytes are
  free (...)`, exit code 3. Every function with a frame is checked (9 cycles a call).
  Fix: more `--stack`, or make the big locals `static`, or fill big structures through a
  pointer instead of returning them by value (a returned structure is on the stack twice:
  the callee's local and the caller's copy).
- The compile warns at a frame over 1 KB (`[-Wframe-larger-than]`: `the function 'f'
  needs a software-stack frame of 7,400 bytes (the software stack is 8,192 bytes ...)`) and
  refuses one bigger than the whole stack (`--stack N` as given to hcc). Read these.
- The hardware stack's overflow is reported only at exit and only if its 256-byte guard
  was written: `stack overflow: the guard zone at window address N ... was written`.
- `--stack 100`: `hcc: --stack: the software stack is an even number of bytes, 512 to 32768`.

## Limits

| Limit | Value |
| --- | --- |
| One object, one `malloc`, one `fread`/`memcpy` | 65,535 bytes (`size_t` is 16 bits) |
| Main bank for code (small model) + constants + data + bss | 65,264 bytes less the software stack: 57,072 with the default 8 KB |
| Large model code | main bank's room + 64 banks of 64 KB; one function 65,535 bytes |
| The .PRG's o65 part (main bank + relocations) | below 64 KB (the loader reads only the first 65,535 bytes) |
| `main`'s arguments | at most 32; `argv[0]` is the program's name ("Misc"), not its path |
| Open files | 4 handles for the whole system (see c-library.md) |
| `hz_read`/`read` result | an `int`: read in pieces of at most 32,767 bytes |

## Not supported, and what to do instead

Each is an error that starts `cc816 does not support`:

| Not supported | Instead |
| --- | --- |
| variable-length arrays (`int a[n];`) | a constant size, or `malloc(n * sizeof *a)` |
| a 64-bit `double` | none: `double` is 32 bits; use `long`, `long long` or fixed point (`hgame.h`'s `hg_fix8`, `hg_fix16`) where 7 digits are not enough |
| `__int128`, `_Complex`, `_BitInt` | `long long`; a struct of two floats |
| a `long long` bit-field; an `int` bit-field wider than 16 | `long`/`unsigned long` field (up to 32 bits) |
| GNU asm operand lists (`asm("..." : "=r"(x))`) | `%[name]` in the text (below) |
| `&&label`, `goto *p`; nested functions | a `switch` on a state; a file-scope function |
| GCC built-ins (`__builtin_popcount`, ...) | a few lines of C (cc816's own: `__builtin_fbits(f)`, `__builtin_bitsf(u)`) |
| `#include_next` | `#include` with the path |
| a case range of more than 256 values in a `long` switch | an `if` |
| an object of 65,536 bytes or more | a bank of its own: `hz_far_alloc` |

The VLA message, exactly:

```
vla.c:3:9: error: cc816 does not support variable-length arrays: give the array a constant size, or take the memory from malloc
hcc: 1 file(s) did not compile
```

Ignored with a warning (`-Wattributes`): `aligned(N>1)`, `constructor`, `destructor`,
`section`, `weak`, `alias`, `cleanup`. Library parts that return failure: see
c-library.md, "Not there".

## Inline assembly

`asm("...")` (also `__asm__`, `__asm`; `volatile` ignored) puts ca65 text into the output.
`%[name]` is replaced by a local's direct-page register (`__rg+N`; a `long` or far
pointer: `%[x]` low word, `%[x]+2` next), a global's or static's assembler name
(`_counter`), or an enumerator's value (`#%[MAX]`). Tested in both models:

```c
#include <stdio.h>
unsigned add3(unsigned a, unsigned b, unsigned c);     /* add3.s, next section */
static unsigned counter;
static unsigned twice(unsigned v)
{
    asm("\tlda %[v]\n\tasl a\n\tsta %[v]");    /* the C code after it sees the new v */
    return v;
}
int main(void)
{
    asm("\tinc %[counter]");
    printf("add3 %u twice %u counter %u\n", add3(1, 20, 300), twice(21), counter);
    return 0;                                   /* prints: add3 321 twice 42 counter 1 */
}
```

Rules: A/X/Y are 16-bit at the start and must be at the end (`sep #$20` ... `rep #$20`);
`__rg+0`..`+47`, `__h0`..`__h3`, `__rv` are scratch; keep `__rg+48`..`+95` (except
variables you named), never touch `__sp`, `__cbank`, D, DBR; leave S as found. Cheap
local labels (`@loop`) are local to one statement. An array, struct, `volatile` or
address-taken local cannot be an operand:

```
asmerr.c:4:5: error: %[buf]: 'buf' is an array, kept on the software stack, which one operand cannot reach: take its address in a pointer variable ('p = buf;') and use (%[p]),y
```

`__attribute__((naked))` on a function of only asm statements: no prologue, arguments at
`3,s` (large: `4,s`), ends with its own `rts` (large: `rtl`). Choose text per model with
`#ifdef __CC816_LARGE__`. Examples: `sdk/c/cc816/tests/lang/asm.c`.

## Assembly called from C

Put `.s` files (ca65 syntax) on the hcc command line beside the `.c` files. hcc assembles
them with `sdk/c/rt` on the include path and `-D __CC816_LARGE__=1` in the large model.
`.include "model.inc"` gives `ARGS` (3 or 4: the first argument's offset), `RET`
(`rts`/`rtl`), `CALL name` (`jsr`/`jsl`), `TAILJ name` (`jmp`/`jml`) and `LARGE` (0/1),
so one file suits both models. Tested (`add3(1, 20, 300)` is 321 in both):

```asm
; add3.s - unsigned add3(unsigned a, unsigned b, unsigned c)
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

In C: `unsigned add3(unsigned a, unsigned b, unsigned c);`. Build: `hcc -o T.PRG main.c
add3.s` (or with `--code large`).

The convention:
- Entry and exit: A/X/Y 16-bit, D = 0, DBR = main bank (keep D and DBR).
- Arguments all on the hardware stack, the first at `ARGS,s`, each 2 bytes (`char`,
  `int`, near pointers), 4 (`long`, `float`, far pointers: offset, bank, 0) or 8 (`long
  long`, low word first). The caller removes them. A struct argument is the address of a
  copy (2 bytes); a struct result goes through a hidden first argument.
- Result: A (16-bit and smaller); A low / X high (32-bit, `float` bits); `long long` in
  `__h0`..`__h1+2` (8 bytes, direct page).
- Registers (`.importzp __rg`): `__rg+0`..`+47` scratch, `__rg+48`..`+95` callee-saved;
  `__h0`..`__h3`, `__rv` scratch; never change `__sp` or `__cbank`.
- Names: C `name` is `_name`. A near pointer is an offset in DBR's bank: `lda (__rg+0),y`.
- Large model: a C function's 16-bit address (for `.addr`, `lda #`) is `__T_name`, not
  `_name` (hcc refuses the latter for code in another bank). Calls: `CALL _name`. A call
  through a function pointer from assembly: the pointer into `__fpt`, then `jsl __icall`.
- See the compiler's own code: `hcc -S file.c` writes `file.s` next to it.
- Syscalls, blocks and assembly macros: references/abi-cheatsheet.md.

## Movable assembly (large model)

`.s` code in `.segment "CODE"` stays in the main bank. Open a function with `FUNC _name`
(model.inc) instead and hcc places it as a C function: in the main bank while there is
room, else in another bank (segment `F_name`; in the small model `FUNC` is `CODE`, so one
file serves both). Tested: `sdk/c/examples/asmfar` (`make -C sdk/c test`: small, and large
with every function in other banks). The rules (docs/c/reference.md, "Movable assembly"):

- PBR is the function's bank, DBR the main bank: `lda _global` works; a table the code
  reads with `lda` goes in `RODATA`, not in the code segment.
- Leave the function only with `CALL _name` / `TAILJ _name` (they record the JSL's / JML's
  bank byte for hcc). A bare `jsl _name` is refused ("a bank byte not recorded in XREL").
- `jsr` / `jmp` / `jmp (tab,x)` only to labels of the same `FUNC` (jump table entries:
  `.addr label` or `.word .loword(label)`); to `CODE` or another `FUNC` they are refused.
- Any other bank byte of the program: `XBANK n` after it (`lda #^name`: `XBANK 2`; `lda
  f:name`, `.faraddr`: `XBANK 1`). Never for a fixed bank. The main bank's number is
  also `__cbank`.
- A function's 16-bit address: `FNADDR _name`, then `__T_name` (both models).
- Entry points the system calls with JSR or by a vector stay in `CODE`.
- Test with `hcc --code large --main-room 0`: an unrecorded bank byte naming the main
  bank is not seen while the function is in the main bank.

## Warnings worth heeding

On by default unless marked -Wall; `-Wno-NAME` turns one off, `-Werror` makes them errors
(`[-Werror=overflow]`), `-w` silences all but `-Woverflow` (16-bit `int` changing a value
is never noise; `-w -Wno-overflow` silences it too). `-Wsequence-args` is only on when
named (not in -Wall). From one `hcc -Wall` run:

```
warn.c:5:13: warning: the conversion to int changes the value 40000 to -25536 (int is 16 bits in cc816: use long) [-Woverflow]
warn.c:7:17: warning: integer overflow in a constant expression: the result 64000 does not fit int (16 bits in cc816; it becomes -1536) [-Woverflow]
warn.c:9:24: warning: a cast of a far pointer (unsigned char __far *) to a near one (unsigned char *): only its offset is kept, the bank is lost [-Wfar-cast]
warn.c:11:13: warning: comparison is always true: the value is char, 0 to 255 (plain char is unsigned in cc816: use int, or signed char) [-Wtype-limits]
warn.c:13:9: warning: an assignment used as a condition: write == to compare, or put the assignment in parentheses ((a = b) != 0) [-Wparentheses]
warn.c:14:24: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long [-Wformat]
warn.c:10:9: warning: unused variable 'unused' [-Wunused-variable]
```

| Warning | On this machine it usually means |
| --- | --- |
| `overflow` | a real bug: 16-bit `int` (`320 * 200`, `int x = 40000`): use `long` / `320L`. Added to a far pointer (`p + 4 * T`, 40,000 as -25,536) it moves the pointer 25 KB back, where DOS wrapped the offset: `4u * T`, or `-ffar-wrap` |
| `sequence-args` (named) | two arguments of one call call functions: their side effects come in cc816's order (left to right; DOS's compilers right to left: `-fargs-right-to-left`) |
| `type-limits` | a real bug: `char c = getchar(); c != EOF` never ends; `x > 40000` with an int |
| `format` | a real bug: `%d` with a `long` prints garbage and shifts later arguments; use `%ld`, `%lu` |
| `far-pointer`, `far-cast` (-Wall) | a real bug: the bank is dropped, the pointer now points into the main bank |
| `implicit-function-declaration` | missing header; the result is taken as a 16-bit int (a `long` or pointer result breaks) |
| `unprototyped-args` | a real bug: a call without a prototype whose argument's size differs from the definition's parameter in the same file (`f(0)` where `f` takes a far pointer or a `long`: every later parameter read from the wrong place). Across files: `hcc --check-calls *.c` |
| `implicit-int`, `extra-args` | (`-std=c89`, `-fimplicit-int`, `-fextra-args`, `-fdos-keywords`) C89 code taken as C89 did: `f() {...}` is `int`; extra arguments pushed, never read |
| `int-conversion`, `incompatible-pointer-types` | pointer/int mixups; `long *` vs `int *` are different sizes here |
| `return-type`, `shift-count-overflow`, `div-by-zero`, `excess-initializers` | real bugs |
| `frame-larger-than` | a big array or structure (or a structure returned by value) on the software stack: near its size, or over it (`--stack N`), it overflows; make it `static` or fill it through a pointer. `hcc -c` without `--stack` names the default (8 KB): the link's `--stack` is what counts |
| `tautological-compare` (-Wall) | `u >= 0`, `x <= 32767` with an int: dead tests |
| `unused-variable`, `unused-label` (-Wall), `discarded-qualifiers`, `multichar`, `attributes`, `cpp`, `extern-initializer` | cleanup |

Build a port once with `-Wall` and read every warning.

## hcc options

| Option | What |
| --- | --- |
| `-o FILE` | output (default: the first source's name in capitals, `.PRG`) |
| `-c`, `-S` | compile only (one `.o` each); also write the assembly `.s` next to each `.c` |
| `-I DIR`, `-D NAME[=V]`, `-U NAME`, `-include FILE` | preprocessor |
| `-O0`, `-O1`, `-O2` | optimisation; `-O2` default (`-O3`, `-Os` = `-O2`); `-O1` no loop optimisations |
| `-w`, `-Wall`, `-Werror`, `-Wno-NAME`, `-WNAME` | warnings |
| `-fsigned-char` | plain `char` signed |
| `-fargs-right-to-left` | a call's arguments evaluated right to left (DOS's compilers' order; default left to right); the stack layout is the same |
| `-ffar-wrap` | far pointer arithmetic on the offset alone, the bank never changes (DOS's far pointers; reference.md "Far data model") |
| `--code small\|large` | the code model (default `$HZ_CODE`, else small) |
| `--data near\|far` | the data model (default `$HZ_DATA`, else near); far needs `--code large`: plain data pointers 32 bits (DOS's large model, below) |
| `-fdos-keywords` | `far`, `near`, `huge` are keywords (`__far`, `__near`, `__far`); also `-fimplicit-int` and `-fextra-args` (DOS code is C89) |
| `-std=c89` (`gnu89`, `-ansi`) | C89: `-fimplicit-int` (`f(a) int a; {...}`, `register x;` are `int`, warning `-Wimplicit-int`) and `-fextra-args` (more arguments than the prototype: warning `-Wextra-args`, pushed and never read). `-std=c99`/`c11`/... accepted, no change |
| `-fno-merge-strings`, `-fwritable-strings` | each string literal its own object (default: equal literals in a file are one); the second also puts them in the data. For programs that write into literals |
| `--check-calls` | read the C files together, build nothing: calls without prototypes and prototypes against the definitions in the other files (argument sizes; results: an implicit `int` where a far pointer or `long` comes back, a `void` function's value, one that can end without `return`); exit 1 on a mismatch |
| `--set` | (`--check-calls`) the `-D`/`-U`/`-I`/`-include` after it, up to the next `--set`, are the following files' only: `hcc --check-calls -I src --set -DGAME src/*.c --set port/*.c` |
| `--sizes` | every object and function of the link, its size and where it went (main bank, code bank k, far data bank k), biggest first; also when the program does not fit (a link at the smallest stack to measure it, or each file's segments from the failed map) |
| `--stack N` | software stack bytes (512-32,768, even; default 8,192) |
| `--heap N` | large model: main-bank bytes kept free for malloc (default 4,096) |
| `--bank-room N`, `--main-room N`, `--spread N` | large model, for tests: limit code per bank |
| `--ui`, `--game` | link the controls library / hgame (automatic when `hui.h` names, `<hgame.h>`, `<conio.h>` or `<joystick.h>` are used) |
| `--needs LIST` | start-up check: `horizon=0.29,rev=11,lau,opl2,sprites,blitter,joystick,mem=1024K` (references/packaging.md) |
| `--map` | write NAME.map and NAME.lbl (for `sdk/tools/prof816.py`) and print the sizes |
| `--debug` | report both stacks' and the heap's use at exit |
| `--no-stack-check` | drop the software stack's entry check from the program's functions (1-3 % less code; an overflow then corrupts the heap silently) |
| `-l FILE` | link an extra `.o` or `.lib` |
| `-lm` | accepted, ignored (math is in the C library) |
| `-v`, `--keep DIR`, `--version`, `-h` | show commands; keep intermediate links; version; help |

`CC816_TRACE=1 hcc ...` shows a Python traceback for an internal compiler error.

## Error messages

Compiler messages are gcc's form, `file:line:column: error|warning: text [-Wname]`, with
the header's own name and line for a header. cc816 reports every error of a file, then
stops (after a syntax error at once); hcc then says `hcc: 1 file(s) did not compile` and
exits 1. Syntax errors name what was expected (`expected ';' before 'return'`, `unknown
type name 'uint8_t'`). Link errors are in C's words:

```
hcc: undefined: fire_laser (used in undef.c)
(no file of the program defines it: a .c or .s file missing from the hcc command, a library (-l), a misspelt name, or a function declared but never written)
```

`file.c: internal compiler error: ... (please report; CC816_TRACE=1 shows where)`: a
cc816 fault. Try `-O1`/`-O0` or rewrite the line; report it with a minimal file.

## Program too big

hcc checks the sizes after linking and says what to do. Three forms seen (two 30,000-byte
`static` arrays):

```
hcc: BIG.PRG: program too big by 6,202 bytes. It does not fit in its code bank: code and constants 2,839 + data 0 + bss 60,435 = 63,274 bytes; the biggest part: zeroed globals and statics (bss). ... Its data, constants and bss alone (60,960 bytes) do not fit either, so hcc --code large (code in other banks) is not enough: put big arrays in a bank of their own (hz_far_alloc and a __far pointer, ...), make them smaller, or give the software stack less.
hcc: BIG.PRG: program too big by 58 bytes: build with --code large. ...            (with --stack 2048)
hcc: BIG.PRG does not fit in its code bank (the main bank), by 1,088 bytes: data, constants, bss, the libraries and the software stack (8,192) must fit in it even with --code large; ...
```

What to do, in order:
1. **Code is the big part** ("build with --code large"): `hcc --code large` (`HZ_CODE :=
   large`). Needs Horizon 0.28+ once code spills into other banks.
2. **bss is the big part** (`static char screen[32000];`): take the buffer from
   `hz_far_alloc()` at start-up and use a `__far` pointer.
3. **Constants are big** (level maps, fonts, sine tables): declare them `__far const`
   (own bank in the large model), or load them from a file into a far bank at start-up.
4. **The software stack is mostly unused** (`--debug` shows it): `--stack 4096`.
5. **Floating point or `long long` printing is linked** (`%f` adds about 3.7 KB, the
   float arithmetic 1.8 KB, `pow` 4.8 KB): drop them where `long` or fixed point does.
6. Many string literals: keep messages in a file, load them into a far bank.

`hcc --map` shows each part; with `--code large` it also prints "the main bank without
its movable code", what must fit whatever hcc does with the code. `hcc --sizes` lists
every object and function also when the link fails for size: hcc links once more with a
512-byte stack (and no heap reserve) only to measure it, or, when even that does not
fit, prints each file's segments from the failed link's map.
Speed questions (what costs what): references/performance.md. Porting step by step:
references/porting.md. Traps: references/pitfalls.md.
