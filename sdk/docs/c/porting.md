# Porting C to the Atari816

What usually breaks when C written for a PC (or for cc65 on the 8-bit Ataris and C64)
comes to Horizon, and how to find it. The SDK's compiler is cc816 (vbcc 65816 with `hcc
--cc vbcc` for floating point); where they differ the table says which. The details are in
[reference.md](reference.md).

## The usual suspects

| What | On a PC | Here | What to do |
| --- | --- | --- | --- |
| `int` | 32 bits | **16 bits** (-32768 to 32767; `unsigned`: 0 to 65535) | `long` (32 bits) where values pass 32767: counters of bytes, file sizes and positions, products of two ints, `x * 1000` in milliseconds. `<stdint.h>` has `int32_t` and friends. Compile once with warnings and look at every `int` that holds a size or a sum |
| `size_t` | 32/64 bits | `unsigned int`, 16 bits | one object, one `malloc`, one `fread` is at most 65,535 bytes |
| `char` | usually signed | **unsigned** (the library is built that way) | `signed char` where negative bytes matter; `c == EOF` tests on a `char` never match: keep `getc`'s result in an `int` |
| pointers | 32/64 bits, flat | cc816: 16 bits, an offset in the program's code bank (`__far`: 32 bits, any bank); vbcc: large model 32 bits (offset + bank), tiny 16 bits | memory from `hz_far_alloc` needs `__far` pointers with cc816: `unsigned char __far *p`. Casts between pointers and `int` lose the bank: `long` keeps it (`(unsigned long)p` is p's whole address with cc816). Build far pointers with `hz_farptr(bank, offset)` |
| big arrays | anything | one object must stay inside one 64 KB bank; a program's code, constants, globals, heap and (cc816) software stack share one bank (65,264 bytes); vbcc's tiny model's data, heap and stack share 32 KB | `hcc` says what does not fit, with the sizes. Move big tables to a bank of their own: `hz_far_alloc()` and `__far` pointers |
| `malloc` | gigabytes | the rest of the code bank (cc816: below the software stack, about 48 KB for a small program; vbcc large: about 56 KB), or of the window (vbcc tiny: about 27 KB) | check every `malloc` for NULL; big buffers from `hz_far_alloc` (64 KB each; `hz_mem_info()` says how many banks are free) |
| `long long` | 64 bits | **not supported** (neither compiler) | 32-bit arithmetic, or pairs of `long` |
| `double` | 64 bits | cc816: **none yet** (an error with the file and line); vbcc (`hcc --cc vbcc`): **32 bits**, as `float` (about 7 digits), MS BASIC's format | build with `--cc vbcc`, or use fixed point (`hgame.h` has `hg_fix8`, `hg_fix16`). vbcc adds its float library when the program needs it: about 5 KB for arithmetic and `printf("%f")`, more with math.h functions |
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

1. **Read the warnings.** `hcc` shows the compiler's warnings with file and line (with
   vbcc: it turns some errors into warnings and goes on, "; expected": fix every one).
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
