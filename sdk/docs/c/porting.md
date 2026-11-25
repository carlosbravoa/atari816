# Porting C to the Atari816

Common faults when C written for a PC (or for cc65 on the 8-bit Ataris and C64) is built
for Horizon, and how to find them. The SDK's compiler is cc816. The details are in
[reference.md](reference.md).

## Differences from a PC

Each entry gives the PC's behaviour, the Atari816's, and what to do.

- `int`: 32 bits on a PC, 16 bits here (-32768 to 32767; `unsigned`: 0 to 65535). Use
  `long` (32 bits) where values pass 32767: counters of bytes, file sizes and positions,
  products of two ints, `x * 1000` in milliseconds. `<stdint.h>` has `int32_t` and the
  other fixed-width types. cc816 warns where the overflow is visible to it: `int x =
  40000;` and `320 * 200` (`-Woverflow`), `x > 40000` with an `int` x (`-Wtype-limits`),
  `printf("%d", a_long)` (`-Wformat`). Check also every `int` that holds a size or a sum.
- `size_t`: 32/64 bits on a PC, here `unsigned int`, 16 bits. One object, one `malloc`, one
  `fread` is at most 65,535 bytes. `hz_read`'s result is an `int`: read in pieces of at most
  32,767 bytes (or compare with the length requested).
- `char`: usually signed on a PC, unsigned here (the library is built that way). Use
  `signed char` where negative bytes matter. `c == EOF` tests on a `char` never match (cc816
  warns: "comparison is always true"): keep `getc`'s result in an `int`. `hcc
  -fsigned-char` makes plain `char` signed for code that cannot be changed.
- Pointers: 32/64 bits and flat on a PC. Here 16 bits, an offset in the program's main bank
  (`__far`: 32 bits, any bank). Memory from `hz_far_alloc` needs `__far` pointers:
  `unsigned char __far *p`. Casts between pointers and `int` lose the bank. `long` keeps it
  (`(unsigned long)p` is p's whole address). Build far pointers with `hz_farptr(bank,
  offset)`.
- Big arrays: one object must stay inside one 64 KB bank, and a program's code, constants,
  globals, heap and software stack share one bank (65,264 bytes). `hcc` reports what does
  not fit, with the sizes. Move big tables to a bank of their own: `hz_far_alloc()` and
  `__far` pointers.
- `malloc`: gigabytes on a PC. Here the rest of the main bank, below the software stack
  (about 48 KB for a small program). Check every `malloc` for NULL. Take big buffers from
  `hz_far_alloc` (64 KB each; `hz_mem_info()` returns how many banks are free).
- `long long`: 64 bits, as on a PC, and works as it is. It is slow (a 64-bit divide is
  about 1 ms, reference.md, "long long"): keep it out of inner loops and use `long` where
  32 bits are enough.
- `double`: 64 bits on a PC (about 16 digits). Here 32 bits, the same as `float` (about 7
  digits): IEEE 754 single precision, so results round as a PC's `float` does. Code that
  needs more than 7 digits (whole numbers above 16,777,216, which a float cannot all hold;
  sums of many small values; seconds since 1970 in a double) gives other results: use
  `long` (or fixed point: `hgame.h` has `hg_fix8`, `hg_fix16`) there. Compare with a
  tolerance, not `==`. Constants such as `0.1` and `M_PI` are rounded to 32 bits too.
  Floating point costs code: about 1.8 KB for the arithmetic, 3.7 KB more for printf's
  `%f`, 0.5 to 5 KB a math.h function (reference.md, "Floating point").
- Recursion, big locals: megabytes of stack on a PC. Here local arrays, structures and `&x`
  locals are on an 8 KB software stack (`hcc --stack N`), the rest on a 32 KB hardware
  stack. Declare arrays of more than a few hundred bytes `static` or take them from
  `malloc`, not as locals. `hcc --debug` reports the stacks a run used, and an overflow is
  reported at exit.
- Files: 4 file handles for the whole system (every program together). Close files as soon
  as possible. `fopen` returns NULL with `errno == ENFILE` when none is left. Do not keep a
  log file open across the program's life.
- Paths: FAT, case-insensitive, `/` separators, long names, relative to the current
  folder. No `\`, no drive letters (`/home/x/file.txt`, `C:\x` on a PC).
- The program's own folder: on a PC `argv[0]` is the executable's path. Here `argv[0]` is
  only the program's name, and the current folder may be any folder (the Programs menu
  starts an app in its own folder, Files in the folder it shows, a shortcut in `/`, the
  shell in its own folder). Always find data files next to the program with
  `hz_prog_dir(buf, 128)`: its folder, `/GAMES/MINE/` (Horizon 0.28; `hz_task_path` the
  whole path).
- `printf("%lld")`, `%a`: supported (`%a` in programs with floating point; `%zu` works
  too).
- `fopen(..., "rb")`: binary and text are the same (no line-end conversion).
- `system()`, `getenv()`, signals, time zones: not supported (they return failure).
  `time()` counts from Horizon's clock. Use `hz_spawn_path` to start another program.
- `stdin`: the keyboard, a line with echo and editing. Ctrl-D on an empty line (or ctrl-C)
  ends the input. A prompt without a newline is shown before reading (stdout is flushed).
- Speed: a 14 MHz 65C816 (about half that with the memory stalls). See "Performance" in
  [reference.md](reference.md#performance): 16-bit `unsigned` loop variables, no `long` in inner loops, no `float` in
  the frame loop.

## Porting from cc65

- `int` 16 bits, `char` unsigned: the same, so arithmetic code ports as it is.
- `register`, `__fastcall__`, zero-page variables (`#pragma zpsym`): not needed. cc816
  keeps variables in direct-page registers itself. `__fastcall__` must be removed (or
  `#define __fastcall__`).
- `<atari.h>`, `<peekpoke.h>`: not available, because Horizon programs never access the
  hardware (`<conio.h>` and `<joystick.h>` exist, on hgame: games.md). The console is
  `printf` / `hz_puts`, keys are `hz_input_read` and `hz_key_ascii`, the screen is the
  window system or full screen (`horizon.h`).
- POKE / PEEK to hardware registers: not allowed (the program runs in user mode and is
  killed). Use the syscalls: sound (`hz_beep`, `hz_sound_write`, `hz_sample_play`),
  joysticks (`hz_joystick`).
- The 6502's 256-byte stack: 32 KB of hardware stack here, so deeper recursion works.
- `asm("...")` in ca65 syntax: the same. The text is emitted as it is, in ca65 syntax. C
  variables are named `%[name]`, not with cc65's `%v`/`%o` (reference.md, "Inline
  assembly"). cc65's own zero-page names (`sp`, `ptr1`, `tmp1`) do not exist: use
  `__rg+0` .. `__rg+47` as scratch. A `.s` file works too.
- Linker configurations (`.cfg`): none. `hcc` does the layout (hcc links with ld65 and
  `sdk/c/rt/hzprog.cfg`; with `--code large` hcc writes the configuration and places the
  functions in banks itself).

## Debugging a port

1. Read the warnings. `hcc` shows the compiler's warnings with file, line and column.
   Build once with `-Wall` too, and check each warning: most of them concern the 16-bit
   `int`, the unsigned `char` or a far pointer.
2. Overflowing ints. Search for `int` used for sizes, positions, times in ms and products.
   Test with values above 32767.
3. Sizes. `hcc --map` prints the code bank's and the window's use, and writes NAME.map and
   NAME.lbl (every label with its address).
4. Crashes. `[kill] task N NAME cause 04 addr AAAAAA pc PPPPPP` on the console: cause
   $01-$1F is a memory access the task may not make (bit 2: a bank that is not its own,
   usually a bad pointer; bit 0: a write to its code where it may not write). Find `pc`'s
   low 16 bits in NAME.lbl: the function. `addr` is the address accessed. A pointer whose
   bank is wrong (one more than the code bank, or 0) usually comes from a cast of an integer
   to a pointer. A plain pointer cast from a far address (`(char *)hz_far_alloc()`) points
   into the main bank instead: declare it `__far`. A far string given to a function that
   takes a `const char *` (a `hui.h` routine, `printf`) must be copied into the main bank
   first (`hz_far_copy` into a static buffer). `sdk/c/examples/viewer` does this for its
   list's rows.
5. The stacks. `hcc --debug` makes the program print `stack: N of M bytes used` and
   `software stack: N of M bytes used` at exit. "stack overflow: ... guard zone ... was
   written" means a stack overflowed: give the software stack more (`--stack 16384`).
6. The compiler. If a file misbehaves, try `-O1` against the default `-O2`, and the other
   code model (`--code large` or not). A difference is worth a minimal program and a report
   (reference.md, "Compiler notes").
7. Run in the emulator with a script that types the input (`--script`) and read
   `console.txt`. Add `printf`s (stdout is line-buffered: end them with `\n`).

## Compiler messages

cc816 writes its messages in gcc's form: the file, the line and the column, then `error:`
or `warning:`, then the fault.

```
game.c:42:13: error: 'score' undeclared (first use in this function)
game.c:57:9: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long [-Wformat]
game.c:80:9: error: cc816 does not support variable-length arrays: give the array a constant size, or take the memory from malloc
hcc: undefined: fire_laser (used in game.c)
```

- An error stops the build: there is no program. cc816 continues to the end of the file
  first, so all of a file's errors come in one run. Fix the first one first: a later error
  can follow from an earlier one. After a syntax error cc816 stops at once.
- A warning does not stop the build, but in ported code it usually marks a real fault. The
  name in brackets turns it off (`-Wno-format`). `-w` turns all of them off except
  `-Woverflow` (a constant that 16-bit `int` changes: always a wrong value;
  `-Wno-overflow` turns it off too). `-Werror` makes them errors. reference.md ("Compiler
  notes", "Errors and warnings") lists them.
- In a header, the place is the header's file and line. A message about a macro is at the
  line where the macro is used.
- "cc816 does not support ..." is a part of C that cc816 does not have. The message gives
  the alternative. The list is in [Not supported](#not-supported).
- "undefined: NAME (used in FILE)" comes from the link: no file of the program defines
  NAME. A `.c` or `.s` file is missing from the `hcc` command, or a library (`-l`), or the
  name is misspelt, or the function was declared and never written.
- "program too big by N bytes: build with --code large" (and "does not fit in its code
  bank"): code, constants, data and bss are more than the code bank holds. The message
  gives each part's size. When code is the big part, build with `hcc --code large` ([When
  the program is too big](#when-the-program-is-too-big)). When data is, move big arrays to
  a bank of their own (`hz_far_alloc` and a `__far` pointer), make them smaller, or give
  the software stack less (`--stack N`).
- "internal compiler error" is a fault of cc816 itself. Report it with the file.
  `CC816_TRACE=1 hcc ...` shows where it happened. Meanwhile try `-O1` or `-O0`, or write
  the line another way.

## When the program is too big

A small program lives in one 64 KB bank: code, constants, data, bss, heap and the software
stack together. A big port usually does not fit, and hcc reports it:

```
hcc: GAME.PRG: program too big by 133,096 bytes: build with --code large. It does not fit
in its code bank: code and constants 189,260 + data 78 + bss 830 = 190,168 bytes; the
biggest part: code and constants. ...
```

Build it with `hcc --code large`. Nothing in the C changes. The code may then fill several
banks. hcc still writes one file, `GAME.PRG`: the other code banks follow the main bank in
it. Copy it to the card, into any folder. It needs Horizon 0.28 or later. In a Makefile made
with c.mk: `HZ_CODE := large` (or `make HZ_CODE=large`). The details are in
[reference.md](reference.md#code-models), "Code models".

What still must fit in the main bank (the PRG's bank): the startup, the assembly (the C
library's runtime, your `.s` files except their `FUNC` functions: reference.md, "Movable
assembly") and the functions with inline assembly, the constants (string literals and
`const` tables), the initialised data, the bss, the heap and the software stack. C
functions move to other banks: yours and the libraries' (the C library, hgame, the controls
library's C part). If hcc then reports "does not fit in its code bank (the main bank)", the
data is too big:

- Big tables go to banks of their own. Load a level map, a tile set or a sound from a file
  into a bank from `hz_far_alloc()` and read it through a `__far` pointer (`unsigned char
  __far *map`). The program gets smaller and starts faster too.
- Big `const` tables (a sine table, a font, level maps): declare them `__far` (`__far const
  short sine[1024] = {...};`). hcc then puts them in a bank of their own, loaded with the
  program, and the code reads them through far pointers. Without `__far` they are constants
  of the main bank.
- Big buffers (`static char screen[32000];`) are bss: take them from `hz_far_alloc()`.
- The heap: `malloc` takes what is left of the main bank. With `--code large` hcc keeps at
  least 4 KB for it when it fills the bank with code (`--heap N` keeps more). Big
  allocations belong in far banks (64 KB each).
- The software stack (8 KB) holds local arrays and structures. A smaller one (`--stack
  4096`) leaves more room for the rest, if the program's locals are small: `hcc --debug`
  reports how much a run used.
- String literals are constants too. A program with thousands of messages can keep them in
  a file and load them into a far bank.

`hcc --map` shows the main bank's parts and the other banks' sizes.

Assembly in a large program follows the large model's calling convention (JSL/RTL, the
first argument at `4,s`): reference.md, "Calling convention". `#ifdef __CC816_LARGE__`
distinguishes the two models in C and in inline assembly.

## Porting a DOS large-model program

A program written for a DOS compiler's large (or compact) model (Watcom `wcc -ml`,
Microsoft `/AL`, Borland `-ml`) has far data pointers everywhere: every plain `char *` is a
segment:offset pair, its heap is far, its strings and tables need not fit 64 KB. Build it
with `hcc --code large --data far` (c.mk: `HZ_CODE := large` and `HZ_DATA := far`). Plain
data pointers are then 32-bit far pointers, `malloc` takes banks of 64 KB, string literals
and `const` tables go to banks of far data, and the C library takes far pointers. The
declarations of 49,000 lines need no change (`ports/xcom` is the worked example: XCOM-XT,
Watcom C, ported without changes to upstream's pointers). [reference.md](reference.md#far-data-model), "Far data
model", has the details. The steps:

- [ ] Keywords. `__far`, `_far`, `__huge`, `_huge` and `__near`, `_near`, `__cdecl`,
  `__pascal`, `__loadds`, `__interrupt` ... are accepted as they are. `-fdos-keywords`
  makes `far`, `near` and `huge` keywords too (or `#define far __far` in a header of your
  own, as `ports/xcom/compat/xcompat.h` does). `T far *a, far *b;` and `void (far
  *f)(void)` compile (the second with a warning: a function pointer is always the
  main-bank entry).
- [ ] `__near` in the source (DOS's hot data in DGROUP): a `__near` object stays in the
  main bank, and a `__near` pointer is 16 bits. Writable globals stay in the main bank
  anyway, so a port can also `#define __near` to nothing (one pointer kind: the address of
  a far object never loses its bank by accident). XCOM-XT does that.
- [ ] `#pragma aux` functions (Watcom's inline machine code) are ignored with a warning
  that names them: each needs a C body (or an `asm` statement). `#pragma pack(1)` is what
  cc816 does anyway.
- [ ] Segment arithmetic (`MK_FP`, `FP_SEG`, `FP_OFF`, `_dos_allocmem`): the 65816 has
  banks of 64 KB, not paragraphs. Model DOS's memory where the program does arithmetic on
  segments (`ports/xcom/compat/xdos.h`: the first megabyte as an arena of 17 banks,
  `MK_FP(s, o)` is byte `s * 16 + o` of it, a DOS block never crossing a bank). Where it
  only takes the parts of a pointer, `HZ_BANK(p)`, `HZ_OFF(p)` and `hz_farptr(bank, off)`
  are the 65816's equivalents.
- [ ] `_fmemcpy`, `_fstrlen`, ... are the plain ones (`#define _fmemcpy memcpy`): with far
  data every library function takes far pointers.
- [ ] Files straight into far memory: `read(fd, buf, n)` and `fread` read into a `malloc`
  block in any bank. 512 bytes or more go straight from the card.
- [ ] The main bank's budget: what stays there is the startup, the runtime and the
  libraries' assembly, the thunks, the writable globals (bss and data), `--heap N` (the
  part of the heap kept there: 1 KB by default) and the software stack. `hcc --sizes` lists
  every object and function with its size and where it went, biggest first. The big bss
  arrays at its top are the ones to declare `__far` when the main bank is full.
- [ ] Changes in behaviour: `sizeof(void *)` is 4, `size_t` and `ptrdiff_t` stay 16 bits
  (as on DOS), structures with pointer members are 2 bytes bigger a pointer (structures
  read from DOS files with far pointers in them keep their layout), `intptr_t` is a `long`.
  Pointer arithmetic carries into the bank, while DOS's wrapped inside the segment. This
  matters for code that relies on the wrap, and for an `int` that overflowed and is added
  to a pointer: `p + 4 * T` with `T` 10,000 reached offset 40,000 on DOS and goes 25,536
  bytes back here (in X-COM's path search every alien path differed). `-Woverflow` (on even
  with `-w`) finds the constant cases. `-ffar-wrap` makes every far pointer's arithmetic
  DOS's, on the offset alone, for the variable ones too ([reference.md](reference.md#pointers), "Far data
  model", "Pointers": the cost at a bank's ends).
- [ ] The order of a call's arguments: DOS's compilers evaluate them right to left, cc816
  left to right. `hurt(roll_damage(), rl_side())`, both drawing random numbers, draws them
  in the other order (in X-COM, damage differed from DOS). `-Wsequence-args` lists every
  call with two arguments that call functions. `-fargs-right-to-left` gives them DOS's
  order (no cost: only the order of evaluation changes).
- [ ] Speed: a far pointer is 4 bytes in every register, argument and structure. Loops
  through far pointers cost about 8-20 % more than through near ones, a call with pointer
  arguments about twice as much ([reference.md](reference.md#far-data-costs), "Far data costs"). Hot loops can take
  `__near` pointers to main-bank buffers, or move to assembly.
- [ ] Not supported: `huge` objects over 64 KB (an array must fit a bank), the small code
  model, the controls library (`hui.h`).

## Not supported

Each construct cc816 does not support, and the alternative:

- A 64-bit `double`: `double` is the 32-bit `float` format. Use `long`, `long long` or
  fixed point where 7 digits are not enough.
- Variable-length arrays (`int a[n];`): a fixed size, or `malloc(n * sizeof *a)`.
- GNU asm operand lists (`asm("..." : "=r"(x))`): `%[x]` in the text (reference.md,
  "Inline assembly").
- `__int128`: `long long` (64 bits).
- A `long long` bit-field: a `long` one (up to 32 bits).
- `_Complex`: a structure with the real and the imaginary part.
- An `int` bit-field wider than 16 bits: make it `long` or `unsigned long` (up to 32 bits).
- `&&label`, `goto *p` (GNU): a `switch` on a state number.
- Nested functions (GNU): a function at file scope, passed what it needs.
- `__builtin_...` functions: the C library's function, or a few lines of C.
- One object of 64 KB or more: a bank of its own (`hz_far_alloc`).
- One function of 64 KB or more: split it (with `--code large` a function must fit in one
  bank).

## Porting a DOS or SDL game

`ports/digger` is the first worked example: Digger Remastered, 6,600 lines of PC C with an
SDL back end. Its `PORTING-NOTES.md` lists every change, and `ports/digger/horizon/` is the
worked example of every part below. `ports/xargon` is the second: a 16-bit DOS game (Turbo
C, 9,000 lines, its VGA mode X, keyboard, timer and Sound Blaster parts in assembly that was
not released), scrolling in 256 colours with FM music. Its `PORTING-NOTES.md` has the same
lists.

### 1. Before you start

- [ ] Build the game on a PC first and run it there. Keep what it prints.
- [ ] Find its tests. If the game can record and replay input (Digger's `.DRF` files, a
  demo mode, a "playback" option), keep some recordings and the PC's result for each: the
  score, the level, the number of frames. A replay that ends the same on Horizon is the
  strongest test a port can have. It checks the compiler, 16-bit `int` and the game logic
  at once.
- [ ] Find the back end. Most games keep the platform in a few files: `sdl_*.c`, `vga.c`,
  `sound.c`, `timer.c`. List the functions the game calls there. That list is your
  platform layer's interface.
- [ ] Leave out what Horizon does not need: the other back ends, threads and their locks,
  network play, a software synthesizer when POKEY can play the tones itself.

### 2. Make it compile

- [ ] Add the game's C files to a Makefile made with `sdk/c/c.mk`. Use `HZ_CODE := large`
  for anything bigger than a small game. Add `-fsigned-char` if the PC build has signed
  `char` (gcc and clang on x86 do).
- [ ] Choose your platform with a macro, as upstream chooses SDL: `-D_HORIZON`, and
  `#if defined(_HORIZON)` beside upstream's `#if defined(_SDL)`. Keep every change to the
  game's own files small, so the changes stay visible (Digger: 79 lines added).
- [ ] If the game has its own `main` in a file you keep as it is, rename it:
  `-Dmain=game_main`, and write `main` in your platform layer.
- [ ] Build with `-Wall` and read every warning.
- [ ] Missing POSIX names: `<strings.h>` is there. `stricmp` is `strcasecmp`.
- [ ] DOS's `far` and `huge` keywords: `-fdos-keywords` (or `#define huge __far` and
  `far`). A qualifier before a later declarator's `*` (`char huge *a, huge *b;`) belongs to
  that declarator, as Borland and Watcom read it. A program of DOS's large model (far data
  pointers everywhere): [Porting a DOS large-model
  program](#porting-a-dos-large-model-program).
- [ ] Turbo C / Borland C code (`ports/xargon`): its `dos.h`, `conio.h`, `io.h`,
  `alloc.h`, `mem.h` are small headers of your own (`-I compat`), and Borland's names go
  in one header given to every file with `hcc -include` (`max`/`min`, `itoa`, `ltoa`,
  `ultoa`, `random(n)`, `#define far __far`). The file calls (`open`, `read`, `write`,
  `lseek`, `close`, `creat`) are in the SDK (`fcntl.h`, `unistd.h`). `_open`, `_creat`,
  `filelength` are macros or a few lines over them. Keep Turbo C's `rand` (seed *
  0x015A4E35 + 1, bits 16-30) if the game records demos: they replay only with the same
  numbers. `#include "\develop\game\include\x.h"` (absolute DOS paths) must become `"x.h"`.
  Sources in code page 437 (bytes above 127 in strings) and with CRLF line ends compile as
  they are.
- [ ] C89 code (K&R, Microsoft C 5.1, Turbo C, Unix code of the 1980s): build with
  `-std=c89` (`-fdos-keywords` does the same). A function without a return type
  (`SimFrame() {...}`, `twice(a) int a; {...}`), `register x;`, `static n;` are `int`
  with a warning (`-Wimplicit-int`; `-Wno-implicit-int` once you have checked them), and a
  call with more arguments than the prototype is a warning (`-Wextra-args`), as Microsoft
  C's C4020, not an error. The extra arguments are pushed and never read (reference.md,
  "Old C").
- [ ] String literals written into: DOS compilers gave each literal its own storage.
  cc816, as gcc, makes equal literals in a file one object. A program that uses `"    "`
  five times as five buffers, or `strupr("Land")`, needs `-fno-merge-strings` (or
  `-fwritable-strings`: the literals in the data as well). It costs the main bank the
  copies, so `-std=c89` does not imply it.
- [ ] Calls without prototypes: through an old declaration (`int f();`) or none, each
  argument is pushed as its own type gives. A DOS medium-model program passed `0` where a
  pointer was meant (both 2 bytes there). With far data the callee reads 4 bytes and every
  later parameter is wrong (`picture_target(0)`). `-Wunprototyped-args` finds the calls
  within a file. `hcc --check-calls *.c` (with the build's `-I`, `-D`, `--code`, `--data`)
  compares every file's calls and prototypes with the definitions in the others, before
  the first run: the arguments, and the results (an implicit `int` taken from a function
  that returns a far pointer keeps 2 of its 4 bytes; a `void` function's value). Files
  built with different `-D` are read together with `--set` (`hcc --check-calls -I src
  --set -DGAME src/*.c --set port/*.c`).
- [ ] Huge functions compile as they are: a function whose values need more than 255 bytes
  of hardware stack keeps the rest in its software-stack frame, and one over 32 KB of code
  gets `JMP` where `BRL` does not reach.
- [ ] Code that accesses hardware: DOS games read the BIOS tick (`0040:006C`, through a
  pointer) and the VGA's status port (`inportb(0x3DA)`: the retrace), and write the DAC
  (`outportb(0x3C8/0x3C9)`: the palette) and the CRTC (the page shown). Rather than
  changing the game, make those few calls functions of the platform layer: the tick
  pointer a macro over a function that counts the vertical blanks (and blocks until the
  next one when it is read in a loop), the port reads and writes a small emulation (the
  palette into a shadow sent once a frame with `hg_palette`, the start address to the page
  shown). `ports/xargon/horizon/hz_dos.c` and `hz_frame.c` do so, and the game's
  graphics.c (fades, palette cycling, page flipping) then runs unchanged.

### 3. 16-bit int

`int` is 16 bits here. Code from 16-bit DOS is usually safe already (it uses `long` or
`int32_t` where it matters). Code written for 32-bit `int` is not.

- [ ] Format strings first. `printf("%d", an_int32_t)` prints garbage. cc816's `-Wformat`
  warning finds most of them at the first compile: cast to `long` and use `%ld` (`%lu` for
  unsigned). Digger had four, three found by the warning.
- [ ] Counters that pass 32,767: frame counts, scores, times in milliseconds, file sizes.
  Make them `long`. `-Wtype-limits` warns about `x > 40000` with an `int` x.
- [ ] Constants: `int x = 40000;` and `320 * 200` overflow (`-Woverflow`). `-w` leaves it
  on: build a port with `-w` if you must, but read these.
- [ ] Products of two ints: `a * b` is 16 bits. Write `(long)a * b`.
- [ ] Sizes: `size_t` is 16 bits. One object, one `malloc`, one `fread` is at most 65,535
  bytes.
- [ ] `char` signedness: with `-fsigned-char` it is as on a PC. Without it, `char c =
  getc(f); if (c == EOF)` never matches (cc816 warns).

### 4. Memory layout

With `--code large` the code goes to other banks: the program's functions and the
libraries' (the C library's, hgame's), and assembly functions opened with `FUNC`
(reference.md, "Movable assembly"). What stays in the main bank (64 KB with everything
else) is the startup and the other assembly, the constants (string literals and `const`
tables), the initialised data, the bss, the heap and the software stack. That is the real
limit of a big port. `hcc --map` prints its parts:

```
the main bank without its movable code: 33,488 bytes (code that must stay 8,241,
constants 7,764, data 2,142, bss 15,341)
```

- [ ] Big tables in banks of their own. Declare a big table `__far` at file scope:
  `__far const unsigned char level_maps[8][2000] = { ... };`. hcc puts every `__far`
  object in a bank of far data, loaded with the program, and the code reaches it through
  far pointers (`const unsigned char __far *p = level_maps[3];`). The same source works in
  the small model (there the table stays in the code bank). Reference: reference.md, "Far
  objects".
- [ ] Pictures and sounds from a file. Convert art at build time into a data file (Digger:
  `tools/mkdata.py` makes `DIGGER.DAT` from upstream's C arrays) and load it at the start
  into banks from `hz_far_alloc()`.
- [ ] Big buffers (`static char buf[32000];`): take them from `hz_far_alloc()`, with a
  `__far` pointer.
- [ ] One `double` does not bring all of printf. cc816 links printf's `%f` only when a
  constant format has a float conversion (or the format is not a constant), and scanf's
  only for a scanf with one. `sscanf` still brings scanf: for one number, `strtol` is
  smaller.
- [ ] The heap is what is left of the main bank (`--heap N` keeps at least N bytes of it
  free of code; the default is 4096). Each `fopen` takes 1 KB of it for its buffer. When
  the heap has no 1 KB free, the file gets a 128-byte buffer, or none, and still opens.
  `setvbuf(f, NULL, _IONBF, 0)` gives the 1 KB back.
- [ ] Measure what a run used: `hcc --debug` makes the program print at exit how much of
  each stack and of the heap it used. `hz_heap_free()`, `hz_heap_largest()` and
  `hz_heap_peak()` return the same figures at any time.

### 5. Platform layer

Write it in a folder of its own (Digger: `horizon/`). Keep upstream's interface: the game
calls the same functions as before. Digger's parts:

- Video (`hz_vid.c`, `hz_blit.s`): hgame's full screen with a taller framebuffer
  (`hg_screen_fb`: 640 x 400 in a 512-row buffer). `hg_split` keeps the score line fixed
  while the playfield follows the player (a 400-row game on a 360-row screen). The game
  draws by the CPU into a buffer of its own. The changed rectangles are copied to the shown
  framebuffer just after each vertical blank, so a sprite is never seen half drawn.
- Input (`hz_kbd.c`): `hg_key_next()` gives the keys in order, with their characters.
  SDL's scancodes are HID usages, so upstream's key table works as it is. Joysticks:
  `hg_joy`.
- Sound (`hz_snd.c`): the PC speaker's two timers become POKEY's two 16-bit voices,
  `hg_note(v, 1193182 / divisor, vol)`. The sound "interrupt" (72.8 Hz on the PC) runs
  from the frame loop as often as it is due.
- Timer (`hz_timer.c`): the game paces each of its frames by hgame's frames (60 a second,
  the frame counter as the clock). `hg_frame()` also reads the events.
- Files (`hz_main.c`): the program changes to its own folder at the start (`hz_prog_dir`),
  so its scores, settings and recordings are kept next to it.
- Data (`hz_data.c`): the pictures are loaded from `DIGGER.DAT` into far memory at the
  start.

Further points:

- [ ] Draw into a buffer, show after the vertical blank. A game that draws by the CPU
  straight into the shown framebuffer flickers when its drawing takes milliseconds.
- [ ] Do not squash a 400-row picture into 360 rows. The PC's pixels were not square
  either: show it at its size and scroll (`hg_split`).
- [ ] Hot drawing loops in assembly. Digger's six blit routines are short ca65 loops
  (`hz_blit.s`), and a copy of whole rows uses MVN. With `--code large`, open each routine
  with `FUNC` (rt/model.inc) so it can leave the main bank (reference.md, "Movable
  assembly").
- [ ] Or let the blitter draw. Every CPU write to the framebuffer stalls on the SDRAM
  (about 12 cycles a byte even with MVN): a 320 x 200 game that redraws 50 tiles and 16
  sprites a frame spends 15-20 ms on it. Xargon (`ports/xargon/horizon/hz_vga.c`) keeps its
  art in an atlas of 512-byte rows registered as two of the kernel's sheets, and each tile
  or sprite is one `sheet_draw` record (a copy or a keyed copy, about 300 cycles to queue
  and send). Ali draws while the CPU runs the game. What the blitter cannot do (a font in
  colours chosen at run time) can be made once by the CPU into a cache sheet and drawn
  from there too.
- [ ] A scrolling game on page flips: the hardware scroll registers replace the copy of the
  playfield a VGA or EGA game makes each frame (Marga's horizontal wrap: a row of the
  framebuffer is a ring; vertically, move the rows back to the middle when the view nears
  the end, one blitter move every few screens). With both pages in one framebuffer,
  flipping is the scroll registers' choice of rows.
- [ ] Late frames still need their events. A game whose frame takes longer than its tick
  never reaches `hg_frame`'s vertical-blank wait: call `hg_poll()` once a frame (keys, the
  pause, the music's stream). In a program with no frames at all (it keeps its own time and
  draws straight into the framebuffer, as X-COM does), `hg_poll` sends `hg_scroll` /
  `hg_split`, or `hg_view_send()` sends them at once.
- [ ] `read` moves at most 32,767 bytes a call (`ssize_t` is a 16-bit `int`): a DOS
  `read(fd, p, 40000u)` returns 32,767. A DOS layer's `_dos_read` loops until it has the
  count or the file ends.

### 6. Test it

- [ ] Replays first. Play the recordings back in the emulator at full speed and compare
  each result with the PC's (Digger: `tests/drf.sh`, seven recordings, from 1,330 to
  41,561 frames).
- [ ] A scripted game (`run816.py --script`) synchronised with the program's console
  output, not with the clock. Keys at fixed seconds break as soon as anything changes how
  long things take (Horizon's start, the SDK, the program's own code): a key lands in
  another game frame and the game takes another path. Make the program print a line at
  each state a script needs (Digger: `digger: title`, `digger: play`, `digger: dead`,
  `digger: initials`) and write `+0 wait digger: play` in the script. The next steps come
  when the line has been printed (or at once if it came since the input line before), and
  every later time moves by as long as the wait took (`sdk/tools/inputscript.py`).
  Digger's `tests/play.script` passes with the program's start delayed by 1.5 or 3
  seconds.
- [ ] Pictures of game states, not of moments. Compare screenshots pixel for pixel only
  where the game is in the same state whatever the timing. Digger plays back a recording
  of its scripted game and takes each picture at a game frame: the program stops there and
  prints a line, and `run816.py --shot-on TEXT` takes the picture then
  (`ports/digger/tests/frames.sh`). Look at new pictures before you accept them
  (`make refs`).
- [ ] End each run at the program's last line. Otherwise the emulator runs to `--seconds`,
  also after the program has ended. Print a line when the test's work is done and its files
  are closed, and give it to `run816.py --stop-on TEXT --must-stop`: the run ends there,
  and fails if the line is never printed. `--console-times` puts the emulated time before
  each console line (seconds since power-on, the base of `--log-lau-us` and
  `--log-opl-us`).
- [ ] A host twin with the Atari816's types: `sdk/c/tools/host16.py` builds the program on
  the PC with a 16-bit `int`, a 32-bit `long`, unsigned plain `char`, packed structures and
  `double` as the 32-bit float (`host16.py cc -O1 -I src -o game16 src/*.c`). Run it and
  the Atari816's build with the same input and compare their output. The source is
  preprocessed first, so `unsigned QUAD` with a macro `QUAD` is read as the compiler reads
  it. A callback the C library calls (`qsort`'s comparison) keeps the PC's `int` with
  `--native NAME`. A DOS program's old C goes through as well: `FILE.C` names, K&R
  definitions without a type (`f(a) int a; {`), `static n;`, functions called before their
  declaration, a C library function the program declares again (`extern int abs(int);`), a
  prototype that names a structure before it is declared, and functions declared `f();`
  but defined with `short` or `char` parameters (made K&R definitions, as C's promotions
  need). `--report` lists each place mended. Limits: it does not reproduce 16-bit
  arithmetic before a value is stored (the PC adds two shorts in 32 bits: a 16-bit
  `unsigned` compared with `-1` is equal on the Atari816, never on the PC), nor the
  Atari816's layout of the globals. Those places are the port's: write them in a fix-up
  file and give it with `--fixups FILE` (sections `[FILE.C]` or `[FILE.H]`, lines `OLD =>
  NEW`; each OLD must be in its file once, so a fix-up that no longer applies stops the
  build). gcc's `-Wsign-compare` and `-Wtype-limits` on the twin's build list most of them.
- [ ] Arguments typed at the shell: `run816.py --mode shell --args` types the program's
  path and the arguments at the prompt. Since Horizon 0.31 the shell's line editor takes
  255 characters (the line scrolls sideways; before 0.31 it took 77 and dropped the rest),
  and a program gets at most 127 characters of arguments (the kernel's spawn; the shell
  prints an error when there are more). run816.py rejects `--args` over 127 and a typed line
  over 255: use `--cd DIR` (the path typed relative to it), a shorter `--dest`, shorter
  names, or an options file.
- [ ] Check the files it writes: the high-score file on the emulated card
  (`build/test/card/`), a saved recording played back to the same score.
- [ ] Sound: POKEY is silent in the emulator. Check its register writes
  (`run816.py --log-sound`) and listen on the board.
- [ ] Measure the speed. Count late frames and the CPU time of a frame in the game itself
  (Digger: `hz_timer.c` prints them at the end). Then profile: `run816.py --prof prof.txt
  --prof-from 20 --prof-to 80` and `sdk/tools/prof816.py --counts prof.txt --map GAME.map`
  give the share of each function (both code models; games.md, "Profiling").

## Example: wc

The `wc` example (`sdk/c/examples/wc`) is a small file tool as it would be written for a
PC: `argv`, `fopen`, `fread` in blocks, `strerror(errno)`, an exit code. The only
Horizon-specific choices are the buffer (1 KB, static: not a 1 KB local in a recursive
function) and counters in `unsigned long` (an `int` would wrap after 32,767 lines). Its
`make test` puts a file on the emulated card (`--file test.txt:/WCTEST.TXT`) and checks
the counts and the error message for a missing file.
