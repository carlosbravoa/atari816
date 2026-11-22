# Porting C to the Atari816

What usually breaks when C written for a PC (or for cc65 on the 8-bit Ataris and C64)
comes to Horizon, and how to find it. The SDK's compiler is cc816 (vbcc 65816 with `hcc
--cc vbcc` for its tiny model); where they differ the table says which. The details are
in [reference.md](reference.md).

## The usual suspects

| What | On a PC | Here | What to do |
| --- | --- | --- | --- |
| `int` | 32 bits | **16 bits** (-32768 to 32767; `unsigned`: 0 to 65535) | `long` (32 bits) where values pass 32767: counters of bytes, file sizes and positions, products of two ints, `x * 1000` in milliseconds. `<stdint.h>` has `int32_t` and friends. cc816 warns where it can see it: `int x = 40000;` and `320 * 200` (`-Woverflow`), `x > 40000` with an `int` x (`-Wtype-limits`), `printf("%d", a_long)` (`-Wformat`). Look also at every `int` that holds a size or a sum |
| `size_t` | 32/64 bits | `unsigned int`, 16 bits | one object, one `malloc`, one `fread` is at most 65,535 bytes |
| `char` | usually signed | **unsigned** (the library is built that way) | `signed char` where negative bytes matter; `c == EOF` tests on a `char` never match (cc816 warns: "comparison is always true"): keep `getc`'s result in an `int`. `hcc -fsigned-char` makes plain `char` signed for code that cannot be changed |
| pointers | 32/64 bits, flat | cc816: 16 bits, an offset in the program's code bank (`__far`: 32 bits, any bank); vbcc: large model 32 bits (offset + bank), tiny 16 bits | memory from `hz_far_alloc` needs `__far` pointers with cc816: `unsigned char __far *p`. Casts between pointers and `int` lose the bank: `long` keeps it (`(unsigned long)p` is p's whole address with cc816). Build far pointers with `hz_farptr(bank, offset)` |
| big arrays | anything | one object must stay inside one 64 KB bank; a program's code, constants, globals, heap and (cc816) software stack share one bank (65,264 bytes); vbcc's tiny model's data, heap and stack share 32 KB | `hcc` says what does not fit, with the sizes. Move big tables to a bank of their own: `hz_far_alloc()` and `__far` pointers |
| `malloc` | gigabytes | the rest of the code bank (cc816: below the software stack, about 48 KB for a small program; vbcc large: about 56 KB), or of the window (vbcc tiny: about 27 KB) | check every `malloc` for NULL; big buffers from `hz_far_alloc` (64 KB each; `hz_mem_info()` says how many banks are free) |
| `long long` | 64 bits | cc816: 64 bits, as on a PC (vbcc: none) | works as it is; it is slow (a 64-bit divide is about 1 ms, reference.md, "long long (cc816)"): keep it out of inner loops, use `long` where 32 bits are enough |
| `double` | 64 bits (about 16 digits) | **32 bits, the same as `float`** (about 7 digits). cc816: IEEE 754 single precision, so results round as a PC's `float` does; vbcc: MS BASIC's format | code that needs more than 7 digits (whole numbers above 16,777,216, which a float cannot all hold; sums of many small values; seconds since 1970 in a double) gives other answers: use `long` (or fixed point: `hgame.h` has `hg_fix8`, `hg_fix16`) there. Compare with a tolerance, not `==`. Constants such as `0.1` and `M_PI` are rounded to 32 bits too. Floating point costs code: with cc816 about 1.8 KB for the arithmetic, 3.7 KB more for printf's `%f`, 0.5 to 5 KB a math.h function (reference.md, "Floating point") |
| recursion, big locals | megabytes of stack | cc816: local arrays, structures and `&x` locals on an 8 KB software stack (`hcc --stack N`), the rest on a 32 KB hardware stack; vbcc: 32 KB (large), 4 KB (tiny) | arrays of more than a few hundred bytes as `static` or from `malloc`, not as locals. `hcc --debug` reports the stacks a run used; an overflow is reported at exit |
| files | as many as you like | **4 file handles for the whole system** (every program together) | close files as soon as you can; `fopen` returns NULL with `errno == ENFILE` when none is left. Do not keep a log file open across the program's life |
| paths | `/home/x/file.txt`, `C:\x` | FAT, case-insensitive, `/` separators, long names; relative to the current folder | no `\`; no drive letters |
| the program's own folder | `argv[0]`, the executable's path | `argv[0]` is only the program's name, and the current folder may be any folder (the Desktop starts programs in `/`) | data files next to the program: `hz_prog_dir(buf, 128)` gives its folder, `/GAMES/MINE/` (Horizon 0.28; `hz_task_path` the whole path) |
| `printf("%lld")`, `%a` | yes | cc816: yes (`%a` in programs with floating point); vbcc: no | nothing with cc816 (`%zu` works too) |
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
| `asm("...")` in ca65 syntax | the same with cc816: the text goes out as it is, in ca65 syntax; C variables are named `%[name]`, not with cc65's `%v`/`%o` (reference.md, "Inline assembly (cc816)"). cc65's own zero-page names (`sp`, `ptr1`, `tmp1`) do not exist: use `__rg+0` .. `__rg+47` as scratch. A `.s` file works too |
| linker configs (`.cfg`) | none: `hcc` does the layout (cc816 links with ld65 and `sdk/c/rt/cc816/hzprog.cfg`; with `--code large` hcc writes the configuration and places the functions in banks itself) |

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
- **"program too big by N bytes: build with --code large"** (and "does not fit in its
  code bank"): code, constants, data and bss are more than the code bank holds. The
  message gives each part's size. When code is the big part, build with `hcc --code
  large` ("When the program is too big", below). When data is, move big arrays to a bank
  of their own (`hz_far_alloc` and a `__far` pointer), make them smaller, or give the
  software stack less (`--stack N`).
- **"internal compiler error"** is a fault of cc816 itself. Please report it with the
  file; `CC816_TRACE=1 hcc ...` shows where it happened. Meanwhile try `-O1` or `-O0`, or
  write the line another way.

## When the program is too big

A small program lives in one 64 KB bank: code, constants, data, bss, heap and the
software stack together. A big port usually does not fit. hcc says so:

```
hcc: GAME.PRG: program too big by 133,096 bytes: build with --code large. It does not fit
in its code bank: code and constants 189,260 + data 78 + bss 830 = 190,168 bytes; the
biggest part: code and constants. ...
```

**Build it with `hcc --code large`.** Nothing in the C changes. The code may then fill
several banks; hcc still writes one file, `GAME.PRG`: the other code banks follow the main
bank in it. Copy it to the card, into any folder. It needs Horizon 0.28 or later. In a
Makefile made with c.mk: `HZ_CODE := large` (or
`make HZ_CODE=large`). The whole of it is in reference.md, "The two code models (cc816)".

**What still must fit in the main bank** (the PRG's bank): the startup, the assembly
(the C library's runtime, your `.s` files) and the functions with inline assembly, the
constants (string literals and `const` tables), the initialised data, the bss, the heap
and the software stack. C functions move to other banks: yours and the libraries' (the C
library, hgame, the controls library's C part). If hcc then says "does not fit in its code
bank (the main bank)", the data is too big:

- **Big tables go to banks of their own.** A level map, a tile set, a sound: load them
  from a file into a bank from `hz_far_alloc()` and read them through a `__far` pointer
  (`unsigned char __far *map`). The program gets smaller and starts faster too.
- **Big `const` tables** (a sine table, a font, level maps): declare them `__far`
  (`__far const short sine[1024] = {...};`). hcc then puts them in a bank of their own,
  loaded with the program, and the code reads them through far pointers. Without `__far`
  they are constants of the main bank.
- **Big buffers** (`static char screen[32000];`) are bss: take them from `hz_far_alloc()`.
- **The heap**: `malloc` takes what is left of the main bank. With `--code large` hcc keeps
  at least 4 KB for it when it fills the bank with code (`--heap N` keeps more). Big
  allocations belong in far banks anyway (64 KB each).
- **The software stack** (8 KB): local arrays and structures. A smaller one (`--stack
  4096`) gives the rest room, if the program's locals are small: `hcc --debug` reports how
  much a run used.
- **String literals** are constants too. A program with thousands of messages can keep
  them in a file and load them into a far bank.

`hcc --map` shows the main bank's parts and the other banks' sizes.

**Assembly in a large program** follows the large model's calling convention (JSL/RTL,
the first argument at `4,s`): reference.md, "Calling convention". `#ifdef
__CC816_LARGE__` tells the two models apart in C and in inline assembly.

## Not supported, and what to do instead

| cc816 does not support | Do this instead |
| --- | --- |
| a 64-bit `double` | `double` is the 32-bit `float` format: use `long`, `long long` or fixed point where 7 digits are not enough |
| variable-length arrays (`int a[n];`) | a fixed size, or `malloc(n * sizeof *a)` |
| GNU asm operand lists (`asm("..." : "=r"(x))`) | `%[x]` in the text (reference.md, "Inline assembly (cc816)") |
| `__int128` | `long long` (64 bits) |
| a `long long` bit-field | a `long` one (up to 32 bits) |
| `_Complex` | a structure with the real and the imaginary part |
| an `int` bit-field wider than 16 bits | make it `long` or `unsigned long` (up to 32 bits) |
| `&&label`, `goto *p` (GNU) | a `switch` on a state number |
| nested functions (GNU) | a function at file scope; pass it what it needs |
| `__builtin_...` functions | the C library's function, or a few lines of C |
| one object of 64 KB or more | a bank of its own (`hz_far_alloc`) |
| one function of 64 KB or more | split it (with `--code large` a function must fit in one bank) |

## Porting a DOS or SDL game, step by step

This is the way `ports/digger` was done: Digger Remastered, 6,600 lines of PC C with an SDL
back end, playing on Horizon in about 45 minutes of work, its tests in 2.5 hours. Its
`PORTING-NOTES.md` lists every change; `ports/digger/horizon/` is the worked example of
every part below.

### 1. Before you start

- [ ] **Build the game on a PC first** and run it there. Keep what it prints.
- [ ] **Find its tests.** If the game can record and replay input (Digger's `.DRF` files,
  a demo mode, a "playback" option), keep some recordings and the PC's result for each:
  the score, the level, the number of frames. A replay that ends the same on Horizon is
  the strongest test a port can have. It checks the compiler, 16-bit `int` and the game
  logic at once.
- [ ] **Find the back end.** Most games keep the platform in a few files: `sdl_*.c`,
  `vga.c`, `sound.c`, `timer.c`. List the functions the game calls there. That list is
  your platform layer's interface.
- [ ] **Leave out what Horizon does not need**: the other back ends, threads and their
  locks, network play, a software synthesizer when POKEY can play the tones itself.

### 2. Make it compile

- [ ] Add the game's C files to a Makefile made with `sdk/c/c.mk`. Use `HZ_CODE := large`
  for anything bigger than a small game. Add `-fsigned-char` if the PC build has signed
  `char` (gcc and clang on x86 do).
- [ ] Choose your platform with a macro, as upstream chooses SDL: `-D_HORIZON`, and
  `#if defined(_HORIZON)` beside upstream's `#if defined(_SDL)`. Keep every change to the
  game's own files small, so the changes are easy to see (Digger: 79 lines added).
- [ ] If the game has its own `main` in a file you keep as it is, rename it:
  `-Dmain=game_main`, and write `main` in your platform layer.
- [ ] Build with `-Wall` and **read every warning**.
- [ ] Missing POSIX names: `<strings.h>` is there; `stricmp` is `strcasecmp`.
- [ ] DOS's `far` and `huge` keywords: `#define huge __far` (and `far`). A qualifier
  before a declarator's `*` (`char huge *a, huge *b;`) was Borland's: write one
  declaration each.

### 3. The 16-bit int traps

`int` is 16 bits here. Code from 16-bit DOS is usually safe already (it uses `long` or
`int32_t` where it matters). Code written for 32-bit `int` is not.

- [ ] **Format strings first.** `printf("%d", an_int32_t)` prints garbage. cc816's
  `-Wformat` warning finds most of them at the first compile: cast to `long` and use `%ld`
  (`%lu` for unsigned). Digger had four, three found by the warning.
- [ ] **Counters that pass 32,767**: frame counts, scores, times in milliseconds, file
  sizes. Make them `long`. `-Wtype-limits` warns about `x > 40000` with an `int` x.
- [ ] **Constants**: `int x = 40000;` and `320 * 200` overflow (`-Woverflow`).
- [ ] **Products of two ints**: `a * b` is 16 bits. Write `(long)a * b`.
- [ ] **Sizes**: `size_t` is 16 bits. One object, one `malloc`, one `fread` is at most
  65,535 bytes.
- [ ] **`char` signedness**: with `-fsigned-char` it is as on a PC. Without it, `char c =
  getc(f); if (c == EOF)` never matches (cc816 warns).

### 4. Memory: what goes where

With `--code large` the code goes to other banks: the program's functions and the
libraries' (the C library's, hgame's). What stays in the **main bank** (64 KB with
everything else) is the startup and the assembly, the constants (string literals and
`const` tables), the initialised data, the bss, the heap and the software stack. That is
the real limit of a big port. `hcc --map` prints its parts:

```
the main bank without its movable code: 33,488 bytes (code that must stay 8,241,
constants 7,764, data 2,142, bss 15,341)
```

- [ ] **Big tables in banks of their own.** Declare a big table `__far` at file scope:
  `__far const unsigned char level_maps[8][2000] = { ... };`. hcc puts every `__far`
  object in a bank of far data, loaded with the program; the code reaches it through far
  pointers (`const unsigned char __far *p = level_maps[3];`). The same source works in
  the small model (there the table stays in the code bank). Reference: reference.md,
  "Far objects".
- [ ] **Pictures and sounds from a file.** Art is best converted at build time into a
  data file (Digger: `tools/mkdata.py` makes `DIGGER.DAT` from upstream's C arrays) and
  loaded at the start into banks from `hz_far_alloc()`.
- [ ] **Big buffers** (`static char buf[32000];`): from `hz_far_alloc()`, with a `__far`
  pointer.
- [ ] **One `double` does not bring all of printf.** cc816 links printf's `%f` only when a
  constant format has a float conversion (or the format is not a constant), and scanf's
  only for a scanf with one. Still, `sscanf` brings scanf: for one number, `strtol` is
  smaller.
- [ ] **The heap** is what is left of the main bank (`--heap N` keeps at least N bytes of it
  free of code; the default is 4096). Each `fopen` takes 1 KB of it for its buffer. When
  the heap has no 1 KB, the file gets a 128-byte buffer, or none, and still opens.
  `setvbuf(f, NULL, _IONBF, 0)` gives the 1 KB back.
- [ ] **See what a run used**: `hcc --debug` makes the program print at exit how much of
  each stack and of the heap it used. `hz_heap_free()`, `hz_heap_largest()` and
  `hz_heap_peak()` tell it at any time.

### 5. The platform layer

Write it in a folder of its own (Digger: `horizon/`). Keep upstream's interface: the game
calls the same functions as before.

| Part | What Digger does | Files |
| --- | --- | --- |
| **Video** | hgame's full screen with a taller framebuffer (`hg_screen_fb`: 640 x 400 in a 512-row buffer). `hg_split` keeps the score line fixed while the playfield follows the player (a 400-row game on a 360-row screen). The game draws by the CPU into a buffer of its own; the changed rectangles are copied to the shown framebuffer just after each vertical blank, so a sprite is never seen half drawn | `hz_vid.c`, `hz_blit.s` |
| **Input** | `hg_key_next()` gives the keys in order, with their characters: SDL's scancodes are HID usages, so upstream's key table works as it is. Joysticks: `hg_joy` | `hz_kbd.c` |
| **Sound** | The PC speaker's two timers become POKEY's two 16-bit voices: `hg_note(v, 1193182 / divisor, vol)`. The sound "interrupt" (72.8 Hz on the PC) runs from the frame loop as often as it is due | `hz_snd.c` |
| **Timer** | The game waits for the end of each of its frames by hgame's frames (60 a second, the frame counter as the clock). `hg_frame()` also reads the events | `hz_timer.c` |
| **Files** | The program goes to its own folder at the start (`hz_prog_dir`), so its scores, settings and recordings are kept next to it | `hz_main.c` |
| **Data** | The pictures are loaded from `DIGGER.DAT` into far memory at the start | `hz_data.c` |

- [ ] **Draw into a buffer, show after the vertical blank.** A game that draws by the CPU
  straight into the shown framebuffer flickers when its drawing takes milliseconds.
- [ ] **Do not squash a 400-row picture into 360 rows.** The PC's pixels were not square
  either; show it at its size and scroll (`hg_split`).
- [ ] **Hot drawing loops in assembly.** Digger's six blit routines are short ca65 loops
  (`hz_blit.s`); a copy of whole rows uses MVN.

### 6. Test it

- [ ] **The replays first.** Play the recordings back in the emulator at full speed and
  compare each result with the PC's (Digger: `tests/drf.sh`, seven recordings, from 1,330
  to 41,561 frames). They passed at the first run: that found no bug, which is the result.
- [ ] **A scripted game** (`run816.py --script`): keys at given times, screenshots, the
  console. The game is deterministic in the emulator (no random seed outside a replay,
  exact time), so screenshots can be compared pixel for pixel with references
  (`tests/cmpshots.py`). Any change of timing moves them: look at the new pictures before
  you accept them (`make refs`).
- [ ] **Check the files it writes**: the high-score file on the emulated card
  (`build/test/card/`), a saved recording played back to the same score.
- [ ] **Sound**: POKEY is silent in the emulator. Check its register writes
  (`run816.py --log-sound`) and listen on the board.
- [ ] **Measure the speed.** Count late frames and the CPU time of a frame in the game
  itself (Digger: `hz_timer.c` prints them at the end). Then profile:
  `run816.py --prof prof.txt --prof-from 20 --prof-to 80` and
  `sdk/c/game/tests/tools/prof816.py --counts prof.txt --map GAME.map` give the share
  of each function (both code models; games.md, "Speed").

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
differently (cc816's results are those of a PC's `float`). `setjmp`/`longjmp` need vbcc
no more either. What still needs vbcc: only its tiny model.
