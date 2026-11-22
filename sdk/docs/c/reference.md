# C reference

The C SDK for Horizon: its two compilers, how a C program is laid out in memory, its
types, far memory, the calling convention (for assembly), the C library on Horizon,
syscalls from C, the stacks, the compilers' faults and what the SDK does about them, and
speed. Getting started: [getting-started.md](getting-started.md); window applications (the
controls library, `hui.h`): [apps.md](apps.md); games: [games.md](games.md); porting:
[porting.md](porting.md).

| | |
| --- | --- |
| Compilers | **cc816**, the SDK's own (`sdk/c/cc816`, Python 3, writes ca65 assembly): the default. **vbcc 65816** Release 2 (Volker Barthelmann): `hcc --cc vbcc`, installed by `sdk/c/tools/get-toolchain.sh` |
| Driver | `sdk/c/bin/hcc` (`hcc -h` lists the options); `--cc cc816` or `--cc vbcc`, or `HZ_CC` in the environment (`make HZ_CC=vbcc` for a program built with c.mk) |
| Headers | `horizon.h` (syscalls, blocks, helpers), `hui.h` (the controls library: [apps.md](apps.md)), `hgame.h`, `conio.h`, `joystick.h` ([games.md](games.md)), `dirent.h`; the C library's: cc816's own (`sdk/c/cc816/include`: `stdio.h`, `stdlib.h`, `string.h`, `ctype.h`, `time.h`, `errno.h`, `stdint.h`, `stdarg.h`, `limits.h`, ...), vbcc's (with `math.h`, `setjmp.h`) |
| Library | `sdk/c/lib` (both compilers), `sdk/c/lib/cc816` and `sdk/c/rt/cc816` (cc816: the whole C library and its runtime), `sdk/c/lib/vbcc`, `sdk/c/rt`, `sdk/c/fastrt` (vbcc: over vbcc's own binary library); hcc builds them into `sdk/c/build/lib/<cc816, large, tiny>/` |
| Make | `sdk/c/c.mk` (a program's Makefile is three lines) |

## The two compilers

Every file of a program is built with the same compiler: hcc refuses an object or a
library made by the other one ("an object or library made by vbcc ...: build every file
with the same compiler").

| | cc816 (default) | vbcc (`--cc vbcc`) |
| --- | --- | --- |
| Memory | one model ("Memory", below) | the large and the tiny model (`--model`) |
| Data pointer | 16 bits: an offset in the code bank; `__far` 32 bits | large: 32 bits; tiny: 16 bits (the window) |
| Floating point | **none yet**: a `float` or `double` is an error naming the file and the line | `float`, `double` (32 bits), math.h: `--float` |
| `long long` | no | no (vbcc 65816 fails on it) |
| `setjmp` / `longjmp` | no (`setjmp.h` is an `#error`) | in its library, not tested |
| Assembly files (`.s`) | ca65 syntax ("Calling convention", below) | vasm oldstyle syntax |
| Linking | ld65, Horizon's own linker: an o65 file straight away | vlink three times, then mko65 ("Program files") |
| Controls library (`hui.h`) | linked straight in by ld65 | a block made by ld65 at $0100 |
| Known faults | none open ("Compiler notes") | seven, six repaired by hcc ("Compiler notes") |
| Needs | Python 3, cc65's ca65, ld65 and ar65 | its toolchain (x86-64 Linux binaries, downloaded), and cc65 for `hui.h` |
| Licence | the SDK's (pycparser and pcpp inside are BSD) | free for non-commercial use, may be redistributed only unmodified |

**What needs `--cc vbcc`:** floating point (`float`, `double`, `math.h`, `printf("%f")`),
`setjmp`/`longjmp`, the tiny model. Neither compiler has `long long`, variable-length
arrays, inline assembly, or a program larger than its one code bank.

## Memory (cc816)

```
cc816 (one model)

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

`hcc` checks the sizes after linking and says what does not fit, in bytes. The loader's
own limits: the program file is less than 64 KB, and code + data + bss fit in $0100-$FFFF.

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
| `char` | 8 bits | **unsigned** (0-255; both compilers, the library is built so); `signed char` for -128-127 |
| `short`, `int` | 16 bits | -32,768-32,767 (`unsigned`: 0-65,535) |
| `long` | 32 bits | |
| `long long` | - | not supported (neither compiler) |
| `float`, `double` | cc816: none; vbcc: 32 bits | vbcc: MS BASIC's format, about 7 digits (`hcc --cc vbcc --float`) |
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

- Functions are called with **JSR** and return with **RTS** (a program's code is all in
  its code bank). On entry and exit A, X and Y are **16-bit** (M = X = 0), D = 0, DBR =
  PBR = the code bank: keep D and DBR.
- **Every argument is on the hardware stack**, pushed last first: at entry the first is at
  `3,s` (above the 2-byte return address), the next ones after it. Each takes 2 bytes
  (`char`, `short`, `int`, pointers, function pointers) or 4 (`long`, `__far` pointers:
  offset, bank, 0). The caller removes them. A structure argument is passed as the address
  of a copy the caller made (2 bytes); a structure result is written through a hidden
  first argument (the address of the caller's space), which is also returned in A.
  Variable arguments are the same (`va_list` is a far pointer into the stack).
- The **result** is in A (16-bit and smaller) or A/X (32-bit: A the low word).
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

Build them with the C files: `hcc -o PROG.PRG main.c add3.s sum.s`. In C: `unsigned
add3(unsigned a, unsigned b, unsigned c); unsigned long sum(const unsigned *p, unsigned
n);` (checked: `add3(1, 20, 300)` is 321, `sum` of {60000, 60000, 1, 2} is 120003). Bank
bytes (`#^label`, `.faraddr`) are relocated by Horizon's loader. The compiler's own
output for any C file is `hcc -S` (FILE.s next to it), or `python3 sdk/c/cc816/cc816.py
-S file.c`. Horizon's assembly libraries (ulib, the controls library) are linked straight
into a cc816 program: they share the direct page (ld65 places their zero page after
cc816's registers).

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
| `printf` family | `%d %i %u %x %X %o %c %s %p %n %%`, the sizes `hh h l` (and `j z t`), widths, precision, `-+ 0#`, `*`. No floating point (`%f` is printed as written) |
| `scanf` family | `%d %i %u %o %x %c %s %[...] %p %n`, `*`, widths, the sizes `hh h l` |
| `fgetpos`, `fsetpos` | 32-bit positions |
| `malloc` | first fit over the heap; NULL when it is full (the libc test: 25 blocks of 1 KB) |
| `clock()` | CLOCKS_PER_SEC 50, as vbcc's |
| `setjmp`, floating point, `math.h` | not there (`--cc vbcc`) |
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

cc816 is new. Its regression set (`make -C sdk/c/cc816 check`) runs, in the emulator,
one small program for each fault found so far (`cc816/tests/regress/`), random programs
checked against gcc's results (`cc816/tests/fuzz/genfuzz.py`: arithmetic of every width,
casts, compares, shifts, division, arrays, structures and their copies, structures by
value, bit-fields, function pointers, variable arguments, far pointers, switches, loops
that spill registers), and the c-testsuite when `CTS=` points at a checkout. The faults
found while it became the SDK's compiler, all fixed in the compiler:

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

Bugs 4-6 were found by the random programs once they learnt structures, bit-fields and
far pointers. `r003_nearfar.c` and `r004_coalesce32.c` guard two changes made on the way
(near pointers widened to far ones; 32-bit results sharing their operand's registers).

The c-testsuite (single-exec, 220 programs): 190 pass. Of the others, 18 need floating
point, `long long`, a variable-length array or a GNU statement expression; 7 meet gaps of
the front end (pycparser and pcpp: a structure and a label of the same name, empty macro
arguments, `#line`, `wchar.h`, one more parse) or `int64_t`; 5 are listed in
`cc816/tests/cts-known.txt` (two expect a 32-bit `int`, two compiler extensions, and an
8-queens search too slow for the test's time, with vbcc too). The random programs: seeds
1, 2 and 3 (1,200 programs) all agree with gcc.

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
| vbcc large, -O1 (its default) | 900 | 886 | 1305 | 635 | 1310 | 1397 |
| vbcc tiny, -O1 | 1640 | 556 | 1306 | 687 | 1077 | 1350 |
| vbcc large, -O3 | 1300 | 490 | 1298 | 633 | 1310 | 1348 |
| vbcc tiny, -O3 | 1579 | 500 | 1299 | 634 | 1064 | 1340 |

(The check values are the trials' six: 1899, 27824, 1071602483, 17711, 3160,
4275534039. vbcc's -O3 is not its default because of the optimiser fault above.)

What they measure: sieve (byte arrays, 16-bit indexes), sum16 (16-bit arrays), mul32
(32-bit multiply and divide), fib22 (calls), strs (pointers and bytes), structs (structure
fields, signed, shifts).

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
- Avoid **float** (vbcc) in anything that runs every frame.
- `memcpy`, `memmove`, `memset` move blocks with MVN/MVP (about 7 cycles a byte, 1000
  bytes in under 1 ms); `hz_far_copy` too.
- cc816: `-O2` (the default) is the fast one; `-O1` drops the loop optimisations (sum16
  above). vbcc: `-O1` is its safe default; `-O3 -speed` changes little here and has the
  faults above.
