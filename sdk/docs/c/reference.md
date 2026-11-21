# C reference

The C SDK for Horizon: how a C program is laid out in memory, its types, far memory, the
calling convention (for assembly), the C library on Horizon, syscalls from C, the stack,
the compiler's known faults and what the SDK does about them, and speed. Getting
started: [getting-started.md](getting-started.md); porting: [porting.md](porting.md).

| | |
| --- | --- |
| Compiler | vbcc 65816 Release 2 (Volker Barthelmann), C99 without `long long`; installed by `sdk/c/tools/get-toolchain.sh` |
| Driver | `sdk/c/bin/hcc` (`hcc -h` lists the options) |
| Headers | `horizon.h` (syscalls, blocks, helpers), `dirent.h`, and vbcc's: `stdio.h`, `stdlib.h`, `string.h`, `ctype.h`, `math.h`, `time.h`, `errno.h`, `stdint.h`, `stdarg.h`, `setjmp.h`, `limits.h`, ... |
| Library | `sdk/c/lib`, `sdk/c/rt`, `sdk/c/fastrt` over vbcc's C library (binary), built by hcc into `sdk/c/build/lib/<model>/` |
| Make | `sdk/c/c.mk` (a program's Makefile is three lines) |

## Memory models

`hcc --model large` (the default) or `--model tiny`. Every file of a program must be
built with the same model.

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
| `char` | 8 bits | **unsigned** (0-255; the library is built so); `signed char` for -128-127 |
| `short`, `int` | 16 bits | -32,768-32,767 (`unsigned`: 0-65,535) |
| `long` | 32 bits | |
| `long long` | - | not supported by vbcc 65816 |
| `float`, `double` | 32 bits | MS BASIC's format, about 7 digits (`hcc --float`) |
| data pointer | 32 bits large, 16 bits tiny | `__far` (32 bits) in both |
| function pointer | 32 bits | functions are called with JSL in both models |
| `size_t` | 16 bits | `unsigned int`: one object at most 65,535 bytes |

Structures are packed (no padding): the parameter blocks in `horizon.h` match ABI.md
byte for byte (each has a compile-time size check). Bytes are little-endian.

Predefined macros: `__65816__`, `__VBCC__`, `__HORIZON__`, `__ATARI816__`; in the tiny
model `__MNEAR` (what vbcc defines) and `__MTINY` (the manual's name, added by hcc), in the
large model `__MLARGE`. `horizon.h` defines `HZ_TINY` in the tiny model.

## Pointers, banks and far memory

A large-model pointer holds an offset and a bank, but arithmetic on it is 16-bit: an
object (an array, a structure, a `malloc` block) must not cross a bank boundary. A bank
is 64 KB; Horizon gives a program more of them with `bank_alloc` (`hz_mem_info()` says
how many are free: 92 banks in all on the 8 MB machine, some used by Horizon and other
programs).

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

**Do not build pointers by casting integers.** `(char *)0x050000` does not give bank 5:
vbcc turns a constant integer into a pointer in the data bank. Use `hz_farptr(5, 0)`.

In the tiny model a plain pointer cannot point into another bank: declare far data with
`__far` (`unsigned char __far *p`). A near pointer converts to a far one (bank 0, the
window) by itself.

## Calling convention (for assembly)

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

Build it with the C files: `hcc -o PROG.PRG main.c add3.s`. In C: `unsigned
add3(unsigned a, unsigned b, unsigned c);`. A 32-bit far address in data is `dd sym`
(vbcc writes pointers so); hcc relocates every bank byte (see "Program files" below). Assembly libraries written for ca65 (ulib, the controls library) are
another matter: they are called with JSR and use the direct page from $50; binding them
is planned (the controls library's bindings, phase 2).

## The C library on Horizon

vbcc's C library (binary only, its 65816 "simulator" target) does the formatting,
strings, sorting, memory and buffering; the SDK replaces what reaches the machine and what
does not work in it.

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

### The C library's replaced parts

`lib/stdio.c` replaces the console streams, `__read`/`__write`, `fopen`, `fclose`,
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
  write the stub in assembly as the generated ones are (`build/lib/large/hzsys.s`):
  the arguments into A, X, Y, `cop #$NN`, `bcs` to an error path.

## The stack

The stack is the window's top part: about 32 KB in the large model, 3,968 bytes at least
in the tiny model (`hcc --stack N` gives it N bytes; the data then has less). Locals,
arguments and return addresses live there: big local arrays and deep recursion use it up.

The startup fills the stack's lowest 256 bytes with a pattern (the **guard zone**); at
exit the program checks it and, if any of it was written, prints `stack overflow: the
guard zone at window address N (the stack's last 256 bytes) was written`. An overflow is
only seen if something was written into those 256 bytes (a never-written local array
larger than that can jump over them), and only at exit (`hz_stack_check()` checks any
time; `hz_stack_free()` gives the bytes below the stack pointer now). With
`hcc --debug` the startup paints the whole stack and the exit reports the most used:
`stack: 751 of 3835 bytes used`. vbcc has no per-function stack check on the 65816.

## Program files

vlink, vbcc's linker, cannot write a relocatable program Horizon's loader takes (its o65
output does not relocate bank bytes). So hcc links each program **three times**, as raw
images at banks $00, $5A and $A5, and `tools/mko65.py` compares them: a byte that is the
same in all three is copied; a byte that differs must be **exactly** the link's bank in
each ($00, $5A, $A5) and becomes a SEG relocation (the loader stores the code bank there).
Anything else stops the build with the byte's address. Offsets never need relocating: the
loader always puts the program at offset $0100 of its code bank.

**Where this could go wrong silently, and the guard.** The loader *replaces* a SEG byte
with the code bank. A byte holding "the bank + 1" (an address in the next bank, an offset
crossing $FFFF) differs by exactly the bank delta in every link, so a check of the
differences alone would accept it and the program would get the code bank there, one
bank short. mko65 therefore also requires the byte to be 0 in the bank-0 link (the value
is the bank itself, nothing added). Any other function of the bank (twice the bank, a
carry from the low word) gives other differences for $5A and $A5 and is rejected too.
Tiny-model data addresses (the window) are the same in every task and need nothing.

## Compiler notes

vbcc 65816 is a young back end. These faults were found while building the SDK; the SDK
works around each, and `tests/codegen` checks the cases:

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

`hcc -v` shows the commands and how many places were repaired in each file.

## Speed

The 65C816 runs at 14.3 MHz; the memory stalls make CPU-bound code about half the ideal
speed (emu816 models them: its timings are the board's within about 5 %). The compiler
trials' benchmark (`tests/bench`, `make -C sdk/c test` runs it), in milliseconds:

| | sieve | sum16 | mul32 | fib22 | strs | structs |
| --- | --- | --- | --- | --- | --- | --- |
| large, -O1 (the default) | 900 | 886 | 1305 | 635 | 1310 | 1397 |
| tiny, -O1 | 1640 | 556 | 1306 | 687 | 1077 | 1350 |
| large, -O3 | 1300 | 490 | 1298 | 633 | 1310 | 1348 |
| tiny, -O3 | 1579 | 500 | 1299 | 634 | 1064 | 1340 |

(-O3 is faster on sum16 and slower on sieve; it is not the default because of the
optimiser fault below. The check values are the trials' six: 1899, 27824, 1071602483,
17711, 3160, 4275534039.)

What they measure: sieve (byte arrays, 16-bit indexes), sum16 (16-bit arrays), mul32
(32-bit multiply and divide), fib22 (calls), strs (pointers and bytes), structs (structure
fields, signed, shifts).

The SDK's tuned runtime (`sdk/c/fastrt`, linked into every program in place of the C
library's routines) against the library's own, in milliseconds for the loop shown (loop
overhead included; tests/rt/rtbench.c, large model; the tiny model's figures are within a
few per cent):

| Operation | fastrt | library |
| --- | --- | --- |
| 16-bit multiply, mixed values, 20,000 times | 696 | 1,425 |
| 16-bit multiply by 100, 20,000 times | 585 | 1,279 |
| 16-bit divide, mixed values, 20,000 times | 1,019 | 1,665 |
| 32-bit multiply, 10,000 times | 1,172 | 2,387 |
| 32-bit divide by 1000, 10,000 times | 586 | 2,544 |
| 32-bit modulo 7, 10,000 times | 613 | 2,648 |
| 32-bit divide by $12345, 10,000 times | 1,328 | 2,666 |
| memcpy of 1000 bytes, 200 times | 167 | 165 |
| memmove of 1000 bytes upwards, 200 times | 180 | 918 |
| memset of 1000 bytes, 200 times | 166 | 247 |
| strlen of 1000 bytes, 200 times | 163 | 188 |
| strcpy of 1000 bytes, 200 times | 297 | 336 |
| memcmp of 1000 bytes, 200 times | 177 | 300 |

Each routine keeps the library's register contract and is checked against host-made
tables (3,000 cases per arithmetic operation, 2,000 per memory function, signed and
unsigned, edge values: `tests/rt`). memcpy was already a block move (MVN) in the library;
vbcc copies a constant-size memcpy inline.

Advice, from these numbers and the generated code:

- Prefer **`unsigned int`** (16 bits) for counters, indexes and loop variables: the
  65816's own size. Signed division and right shifts of `int` need extra code.
- Avoid **`long`** in inner loops: every 32-bit operation is two 16-bit ones, and a
  multiply or divide is a call (a 32-bit multiply about 0.1 ms with its loop, table above).
- Avoid **float** in anything that runs every frame.
- **Byte arrays** are fast in the large model (sieve), **pointers** are faster in the tiny
  model (strs, sum16).
- `memcpy`, `memmove`, `memset` move blocks with MVN/MVP (about 7 cycles a byte, 1000
  bytes in under 1 ms); `hz_far_copy` too.
- `-O1` is the safe default; `-O3 -speed` changes little here and has the faults above.
