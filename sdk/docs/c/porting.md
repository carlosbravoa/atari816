# Porting C to the Atari816

What usually breaks when C written for a PC (or for cc65 on the 8-bit Ataris and C64)
comes to Horizon with vbcc, and how to find it. The details are in
[reference.md](reference.md).

## The usual suspects

| What | On a PC | Here | What to do |
| --- | --- | --- | --- |
| `int` | 32 bits | **16 bits** (-32768 to 32767; `unsigned`: 0 to 65535) | `long` (32 bits) where values pass 32767: counters of bytes, file sizes and positions, products of two ints, `x * 1000` in milliseconds. `<stdint.h>` has `int32_t` and friends. Compile once with warnings and look at every `int` that holds a size or a sum |
| `size_t` | 32/64 bits | `unsigned int`, 16 bits | one object, one `malloc`, one `fread` is at most 65,535 bytes |
| `char` | usually signed | **unsigned** (the library is built that way) | `signed char` where negative bytes matter; `c == EOF` tests on a `char` never match: keep `getc`'s result in an `int` |
| pointers | 32/64 bits, flat | large model: 32 bits (offset + bank); tiny: 16 bits | casts between pointers and `int` lose the bank: use `long` or `intptr_t`... or better, no such casts. Never build a pointer from an integer with a cast: `hz_farptr(bank, offset)` |
| big arrays | anything | one object must stay inside one 64 KB bank; a program's code, constants and globals share one bank (65,280 bytes, large model); the tiny model's data, heap and stack share 32 KB | `hcc` says what does not fit, with the sizes. Move big tables to a bank of their own: `hz_far_alloc()` |
| `malloc` | gigabytes | the rest of the code bank (large model: about 56 KB for a small program), or of the window (tiny: about 27 KB) | check every `malloc` for NULL; big buffers from `hz_far_alloc` (64 KB each; `hz_mem_info()` says how many banks are free) |
| `long long` | 64 bits | **not supported** by vbcc 65816 | 32-bit arithmetic, or pairs of `long` |
| `double` | 64 bits | **32 bits**, as `float` (about 7 digits); MS BASIC's format | fine for games and tools; not for money or long sums. hcc adds the float library when the program needs it (or `--float`): about 5 KB for arithmetic and `printf("%f")`, more with math.h functions |
| recursion, big locals | megabytes of stack | large model: about 32 KB of stack; tiny: about 4 KB | arrays of more than a few hundred bytes as `static` or from `malloc`, not as locals. `hcc --debug` reports the stack a run used; an overflow is reported at exit |
| files | as many as you like | **4 file handles for the whole system** (every program together) | close files as soon as you can; `fopen` returns NULL with `errno == ENFILE` when none is left. Do not keep a log file open across the program's life |
| paths | `/home/x/file.txt`, `C:\x` | FAT, case-insensitive, `/` separators, long names; relative to the current folder | no `\`; no drive letters |
| `printf("%lld")`, `%zu`, `%a` | yes | no | `%ld`, `%lu`, `%u` |
| `fopen(..., "rb")` | binary vs text | the same (no line-end conversion) | nothing |
| `system()`, `getenv()`, signals, `time` zones | yes | not there (they return failure); `time()` counts from Horizon's clock | `hz_spawn_path` to start another program |
| `stdin` | a pipe or a terminal | the keyboard: a line with echo and editing; ctrl-D on an empty line (or ctrl-C) ends the input | prompts without a newline are shown before reading (stdout is flushed) |
| speed | GHz | a 14 MHz 65C816 (about half that with the memory stalls) | see "Speed" in reference.md: 16-bit `unsigned` loop variables, no `long` in inner loops, no `float` in the frame loop |

## Coming from cc65

| cc65 | vbcc on Horizon |
| --- | --- |
| `int` 16 bits, `char` unsigned | the same: arithmetic code ports as it is |
| `register`, `__fastcall__`, zero-page variables (`#pragma zpsym`) | not needed; vbcc keeps variables in its direct-page registers itself. `__fastcall__` must be removed (or `#define __fastcall__`) |
| `<conio.h>`, `<atari.h>`, `<peekpoke.h>` | not there: Horizon programs never touch the hardware. The console is `printf` / `hz_puts`; keys: `hz_input_read` and `hz_key_ascii`; the screen: the window system or full screen (`horizon.h`) |
| POKE / PEEK to hardware registers | not allowed (the program runs in user mode and is killed); use the syscalls: sound (`hz_beep`, `hz_sound_write`, `hz_sample_play`), joysticks (`hz_joystick`) |
| the 6502's 256-byte stack | 4 KB (tiny) or 32 KB (large): deeper recursion works |
| `asm("...")` in ca65 syntax | vbcc's inline assembly is vasm syntax; better: a `.s` file (reference.md, "Assembly") |
| linker configs (`.cfg`) | none: `hcc` does the layout |

## How to find what broke

1. **Read the warnings.** `hcc` shows vbcc's warnings with file and line. vbcc turns some
   errors into warnings and goes on ("; expected"): fix every one.
2. **Overflowing ints.** Search for `int` used for sizes, positions, times in ms and
   products; test with values above 32767.
3. **Sizes.** `hcc --map` prints the code bank's and the window's use, and writes
   NAME.map (every function and object with its address and size).
4. **Crashes.** `[kill] task N NAME cause 04 addr AAAAAA pc PPPPPP` on the console:
   cause $01-$1F is a memory access the task may not make (bit 2: a bank that is not its
   own, usually a bad pointer; bit 0: a write to its code where it may not). Find
   `pc`'s low 16 bits in NAME.map: the function. `addr` is the address it touched. A
   pointer whose bank is wrong (one more than the code bank, or 0) usually comes from a
   cast of an integer to a pointer.
5. **The stack.** `hcc --debug` makes the program print `stack: N of M bytes used` at
   exit. "stack overflow: the guard zone ... was written" means it went past (the tiny
   model's 4 KB first: try the large model, or `--stack 8192`).
6. **The optimiser.** Build with the default `-O1`. If a file misbehaves only at `-O2` /
   `-O3`, it is the compiler (reference.md, "Compiler notes"), not your code.
7. **Run in the emulator** with a script that types the input (`--script`) and look at
   `console.txt`; add `printf`s (stdout is line-buffered: end them with `\n`).

## A ported program, step by step

The `wc` example (`sdk/c/examples/wc`) is a small file tool as it would be written for a
PC: `argv`, `fopen`, `fread` in blocks, `strerror(errno)`, an exit code. The only
Horizon-specific choices are the buffer (1 KB, static: not a 1 KB local in a recursive
function) and counters in `unsigned long` (an `int` would wrap after 32,767 lines). Its
`make test` puts a file on the emulated card (`--file test.txt:/WCTEST.TXT`) and checks
the counts and the error message for a missing file.
