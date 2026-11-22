# Porting C to the Atari816

What usually breaks when C written for a PC (or for cc65 on the 8-bit Ataris and C64)
comes to Horizon, and how to find it. The SDK's compiler is cc816 (vbcc 65816 with `hcc
--cc vbcc` for `setjmp` and the tiny model); where they differ the table says which. The
details are in [reference.md](reference.md).

## The usual suspects

| What | On a PC | Here | What to do |
| --- | --- | --- | --- |
| `int` | 32 bits | **16 bits** (-32768 to 32767; `unsigned`: 0 to 65535) | `long` (32 bits) where values pass 32767: counters of bytes, file sizes and positions, products of two ints, `x * 1000` in milliseconds. `<stdint.h>` has `int32_t` and friends. cc816 warns where it can see it: `int x = 40000;` and `320 * 200` (`-Woverflow`), `x > 40000` with an `int` x (`-Wtype-limits`), `printf("%d", a_long)` (`-Wformat`). Look also at every `int` that holds a size or a sum |
| `size_t` | 32/64 bits | `unsigned int`, 16 bits | one object, one `malloc`, one `fread` is at most 65,535 bytes |
| `char` | usually signed | **unsigned** (the library is built that way) | `signed char` where negative bytes matter; `c == EOF` tests on a `char` never match (cc816 warns: "comparison is always true"): keep `getc`'s result in an `int`. `hcc -fsigned-char` makes plain `char` signed for code that cannot be changed |
| pointers | 32/64 bits, flat | cc816: 16 bits, an offset in the program's code bank (`__far`: 32 bits, any bank); vbcc: large model 32 bits (offset + bank), tiny 16 bits | memory from `hz_far_alloc` needs `__far` pointers with cc816: `unsigned char __far *p`. Casts between pointers and `int` lose the bank: `long` keeps it (`(unsigned long)p` is p's whole address with cc816). Build far pointers with `hz_farptr(bank, offset)` |
| big arrays | anything | one object must stay inside one 64 KB bank; a program's code, constants, globals, heap and (cc816) software stack share one bank (65,264 bytes); vbcc's tiny model's data, heap and stack share 32 KB | `hcc` says what does not fit, with the sizes. Move big tables to a bank of their own: `hz_far_alloc()` and `__far` pointers |
| `malloc` | gigabytes | the rest of the code bank (cc816: below the software stack, about 48 KB for a small program; vbcc large: about 56 KB), or of the window (vbcc tiny: about 27 KB) | check every `malloc` for NULL; big buffers from `hz_far_alloc` (64 KB each; `hz_mem_info()` says how many banks are free) |
| `long long` | 64 bits | **not supported** (neither compiler) | 32-bit arithmetic, or pairs of `long` |
| `double` | 64 bits (about 16 digits) | **32 bits, the same as `float`** (about 7 digits). cc816: IEEE 754 single precision, so results round as a PC's `float` does; vbcc: MS BASIC's format | code that needs more than 7 digits (whole numbers above 16,777,216, which a float cannot all hold; sums of many small values; seconds since 1970 in a double) gives other answers: use `long` (or fixed point: `hgame.h` has `hg_fix8`, `hg_fix16`) there. Compare with a tolerance, not `==`. Constants such as `0.1` and `M_PI` are rounded to 32 bits too. Floating point costs code: with cc816 about 1.8 KB for the arithmetic, 3.7 KB more for printf's `%f`, 0.5 to 5 KB a math.h function (reference.md, "Floating point") |
| recursion, big locals | megabytes of stack | cc816: local arrays, structures and `&x` locals on an 8 KB software stack (`hcc --stack N`), the rest on a 32 KB hardware stack; vbcc: 32 KB (large), 4 KB (tiny) | arrays of more than a few hundred bytes as `static` or from `malloc`, not as locals. `hcc --debug` reports the stacks a run used; an overflow is reported at exit |
| files | as many as you like | **4 file handles for the whole system** (every program together) | close files as soon as you can; `fopen` returns NULL with `errno == ENFILE` when none is left. Do not keep a log file open across the program's life |
| paths | `/home/x/file.txt`, `C:\x` | FAT, case-insensitive, `/` separators, long names; relative to the current folder | no `\`; no drive letters |
| `printf("%lld")`, `%a` | yes | no | `%ld`, `%lu` (`%zu` works with cc816) |
| `fopen(..., "rb")` | binary vs text | the same (no line-end conversion) | nothing |
| `system()`, `getenv()`, signals, `time` zones | yes | not there (they return failure); `time()` counts from Horizon's clock | `hz_spawn_path` to start another program |
| `stdin` | a pipe or a terminal | the keyboard: a line with echo and editing; ctrl-D on an empty line (or ctrl-C) ends the input | prompts without a newline are shown before reading (stdout is flushed) |
| speed | GHz | a 14 MHz 65C816 (about half that with the memory stalls) | see "Speed" in reference.md: 16-bit `unsigned` loop variables, no `long` in inner loops, no `float` in the frame loop |

## Coming from cc65

| cc65 | C on Horizon |
| --- | --- |
| `int` 16 bits, `char` unsigned | the same: arithmetic code ports as it is |
| `register`, `__fastcall__`, zero-page variables (`#pragma zpsym`) | not needed; both compilers keep variables in direct-page registers themselves. `__fastcall__` must be removed (or `#define __fastcall__`) |
| `<conio.h>`, `<atari.h>`, `<peekpoke.h>` | not there: Horizon programs never touch the hardware. The console is `printf` / `hz_puts`; keys: `hz_input_read` and `hz_key_ascii`; the screen: the window system or full screen (`horizon.h`) |
| POKE / PEEK to hardware registers | not allowed (the program runs in user mode and is killed); use the syscalls: sound (`hz_beep`, `hz_sound_write`, `hz_sample_play`), joysticks (`hz_joystick`) |
| the 6502's 256-byte stack | 32 KB of hardware stack (cc816 and vbcc large): deeper recursion works |
| `asm("...")` in ca65 syntax | no inline assembly; a `.s` file in ca65 syntax is cc816's (reference.md, "Calling convention") |
| linker configs (`.cfg`) | none: `hcc` does the layout (cc816 links with ld65 and `sdk/c/rt/cc816/hzprog.cfg`) |

## How to find what broke

1. **Read the warnings.** `hcc` shows the compiler's warnings with file, line and column
   (with vbcc: it turns some errors into warnings and goes on, "; expected": fix every
   one). With cc816 build once with `-Wall` too, and look at each warning: most of them
   are the 16-bit `int`, the unsigned `char` or a far pointer.
2. **Overflowing ints.** Search for `int` used for sizes, positions, times in ms and
   products; test with values above 32767.
3. **Sizes.** `hcc --map` prints the code bank's and the window's use, and writes
   NAME.map (with cc816 also NAME.lbl: every label with its address).
4. **Crashes.** `[kill] task N NAME cause 04 addr AAAAAA pc PPPPPP` on the console:
   cause $01-$1F is a memory access the task may not make (bit 2: a bank that is not its
   own, usually a bad pointer; bit 0: a write to its code where it may not). Find
   `pc`'s low 16 bits in NAME.lbl (cc816) or NAME.map: the function. `addr` is the address
   it touched. A pointer whose bank is wrong (one more than the code bank, or 0) usually
   comes from a cast of an integer to a pointer. With cc816 a plain pointer cast from a far
   address (`(char *)hz_far_alloc()`) points into the code bank instead: say `__far`.
5. **The stacks.** `hcc --debug` makes the program print `stack: N of M bytes used` (and
   with cc816 `software stack: N of M bytes used`) at exit. "stack overflow: ... guard
   zone ... was written" means it went past: with cc816 give the software stack more
   (`--stack 16384`); with vbcc's tiny model try the large model or `--stack 8192`.
6. **The compiler.** If a file misbehaves only with one compiler, try the other (`hcc --cc
   vbcc`, `hcc --cc cc816`), and with cc816 `-O1` against the default `-O2`; with vbcc
   use its default `-O1`. A difference is worth a minimal program and a report
   (reference.md, "Compiler notes").
7. **Run in the emulator** with a script that types the input (`--script`) and look at
   `console.txt`; add `printf`s (stdout is line-buffered: end them with `\n`).

## Reading cc816's messages

cc816 writes its messages as gcc does: the file, the line and the column, then `error:`
or `warning:`, then what is wrong.

```
game.c:42:13: error: 'score' undeclared (first use in this function)
game.c:57:9: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long [-Wformat]
game.c:80:5: error: cc816 does not support inline assembly (asm): put the code in a .s file (ca65 syntax) and call it as a function
hcc: undefined: fire_laser (used in game.c)
```

- An **error** stops the build: there is no program. cc816 goes on to the end of the
  file first, so all of a file's errors come in one run. Fix the first one first: a
  later error can come from an earlier one. After a syntax error cc816 stops at once.
- A **warning** does not stop the build, but it is usually a real fault in ported code.
  The name in brackets turns it off (`-Wno-format`); `-w` turns all of them off,
  `-Werror` makes them errors. reference.md ("Compiler notes", "Errors and warnings")
  lists them.
- In a header, the place is the header's file and line. A message about a macro is at
  the line where the macro is used.
- **"cc816 does not support ..."** is a part of C that cc816 does not have; the message
  says what to do. The list is below.
- **"undefined: NAME (used in FILE)"** comes from the link: no file of the program
  defines NAME. A `.c` or `.s` file is missing from the `hcc` command, or a library
  (`-l`), or the name is misspelt, or the function was declared and never written.
- **"does not fit in its code bank, by N bytes"**: code, constants, data and bss are more
  than the code bank holds. The message gives each part's size. Move big arrays to a bank
  of their own (`hz_far_alloc` and a `__far` pointer), make them smaller, or give the
  software stack less (`--stack N`).
- **"internal compiler error"** is a fault of cc816 itself. Please report it with the
  file; `CC816_TRACE=1 hcc ...` shows where it happened. Meanwhile try `-O1` or `-O0`, or
  write the line another way.

## Not supported, and what to do instead

| cc816 does not support | Do this instead |
| --- | --- |
| `long long`, `int64_t`, `LL` constants | `long` (32 bits); for wider numbers a pair of `long`s |
| a 64-bit `double` | `double` is the 32-bit `float` format: use `long` or fixed point where 7 digits are not enough |
| variable-length arrays (`int a[n];`) | a fixed size, or `malloc(n * sizeof *a)` |
| inline assembly (`asm`, `__asm__`) | a `.s` file in ca65 syntax, called as a C function (reference.md, "Calling convention") |
| `setjmp` / `longjmp` | `hcc --cc vbcc`; or return an error code up the calls |
| `_Complex` | a structure with the real and the imaginary part |
| an `int` bit-field wider than 16 bits | make it `long` or `unsigned long` (up to 32 bits) |
| `case 1 ... 5:`, `[0 ... 9] = x` (GNU ranges) | a `case` for each value, or an `if`; a loop to fill the array |
| `&&label`, `goto *p` (GNU) | a `switch` on a state number |
| nested functions (GNU) | a function at file scope; pass it what it needs |
| `__builtin_...` functions | the C library's function, or a few lines of C |
| one object of 64 KB or more | a bank of its own (`hz_far_alloc`) |

## A ported program, step by step

The `wc` example (`sdk/c/examples/wc`) is a small file tool as it would be written for a
PC: `argv`, `fopen`, `fread` in blocks, `strerror(errno)`, an exit code. The only
Horizon-specific choices are the buffer (1 KB, static: not a 1 KB local in a recursive
function) and counters in `unsigned long` (an `int` would wrap after 32,767 lines). Its
`make test` puts a file on the emulated card (`--file test.txt:/WCTEST.TXT`) and checks
the counts and the error message for a missing file.

## From vbcc's large model to cc816

A program written for vbcc's large model (the SDK's default before cc816) builds with
cc816 as it is unless it keeps addresses of other banks in plain pointers. cc816's plain
pointer is an offset in the code bank, so:

- `char *p = (char *)hz_far_alloc();` becomes `char __far *p = hz_far_alloc();` (with
  vbcc's large model `__far` is the same as a plain pointer, so the source then suits
  both compilers);
- a far string given to a function that takes a `const char *` (a `hui.h` routine, `printf`)
  must be copied into the code bank first (`hz_far_copy` into a static buffer):
  `sdk/c/examples/viewer` does this for its list's rows;
- `HZ_U24(field, p)`, `HZ_OFF(p)` and `HZ_BANK(p)` work on both kinds of pointer.

`hgame` itself went through this (its far memory is `unsigned char __far *`; so is
`hg_image_pixels`' result).

Floating point needs vbcc no more: cc816 has it (IEEE 754, 32 bits for `float` and
`double` alike, as vbcc). A program that used `--cc vbcc --float` for it builds with cc816
as it is. The numbers can differ in the last digit, because vbcc's format rounds
differently (cc816's results are those of a PC's `float`). What still needs vbcc:
`setjmp`/`longjmp` and the tiny model.
