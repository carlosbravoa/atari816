# Pitfalls on Horizon (C with cc816, and 65C816 / ca65)

Purpose: the mistakes that cost real time here, each with its symptom, cause and fix.
Check new code against this list before running it. Language details:
`references/c-language.md`; library: `references/c-library.md`; assembly ABI:
`references/abi-cheatsheet.md`; tests: `references/testing.md`; porting:
`references/porting.md`.

## Things that cost the port agents hours

From `ports/digger/PORTING-NOTES.md` and `ports/xargon/PORTING-NOTES.md`. Times are the
agents' own. "Fixed" means the SDK changed since; the lesson still holds.

| Symptom | Cause | Fix | Cost |
| --- | --- | --- | --- |
| Link fails "does not fit in its code bank (the main bank)" even with `--code large` (Digger by 8.5 KB; Xargon by 1.8 KB) | code moves to other banks, but constants, data, bss, heap, stack and assembly stay in the main bank | big tables `__far`, big buffers from `hz_far_alloc`, no `sscanf` (it pulled 7.6 KB of scanf + float), `--stack 4096`, `.s` functions opened with `FUNC` (movable); read `hcc --map` | 30 min each |
| Every `malloc` after start-up fails; text drawn from address 0 (Xargon) | one early `malloc` of 900 names (8.5 KB) took the whole heap | do not keep what the port does not need; check every `malloc` for NULL; `hz_heap_free()` | in the 30 min above |
| The second `fopen` fails, ENOMEM (Digger) | `--heap 1024`: each `fopen` wanted 1 KB of heap | `--heap 4096` (default). Fixed: `fopen` now falls back to 128 bytes or none | 10 min |
| Sound effects do not load; a 32 KB read "fails" (Xargon) | `hz_read` returns an `int`: 32,768 bytes read is -32,768 | read in 16 KB pieces, or compare with `(int)len` | 20 min, still open |
| Title takes 3 s (Xargon) | 3,600 `read` calls of 1-2 bytes, each a card request (~1 ms) | fixed: read-only descriptors read ahead 512 bytes. Still: read big blocks | 20 min |
| Game logic 13 % in `__mul16`/`__sdiv16` (Xargon) | `x * 31` and signed `x / 16` were calls | fixed in cc816 (inline). Profile before guessing | 30 min |
| A `__far` 2-D array very slow (Xargon `bd[x][y]`) | 32-bit address arithmetic at every access | fixed in cc816 (16-bit index in Y) | 45 min |
| "redefinition of 'struct bag'" on `static struct bag {...} a[7], b[7];` | cc816 bug with several declarators | fixed. Valid C refused = make a minimal case, report it | 15 min |
| "Bad macro definition" on `#define scan_f1= 0x3B` | no space after the name | fixed: a warning, as gcc | 15 min |
| internal compiler error (UnicodeDecodeError) on a header | CP437 bytes in a string | fixed: sources read byte for byte. `CC816_TRACE=1 hcc ...` shows where | 10 min |
| "variable-length arrays" for `a[numobjkinds]` | the size's name was undeclared (missing header) | fixed: now "'numobjkinds' undeclared" | 10 min |
| "Invalid declarator" on `static char huge *a, huge *b;` | Borland's qualifier before a declarator's `*` | one declaration each | minutes |
| A large program: "not a Horizon program, or its file is damaged" | `--code large` needs Horizon 0.28+ | a 0.28+ card; `hcc --needs` says so on old cards | 5 min |
| Board records read wrong (Xargon) | Turbo C's 4-byte far pointer inside a 31-byte file record; here pointers are 2 bytes | pad the struct by hand (`int inside_hi;`); cc816 never pads structures | in the port |
| 1 screenshot in 7 shows a half-drawn sprite (Digger) | the CPU drew into the shown framebuffer during the frame | draw into a buffer; copy changed rectangles right after the vertical blank | in 35 min |
| Reference pictures fail on a fresh checkout (Digger) | made with a card built from someone's work in progress; `git archive` files keep old times, so `make -C horizon` did not rebuild | rebuild the card from a clean tree before writing references | in 35 min |
| Scripted test broke on Horizon 0.29 ("no recording HZD50.DRF saved") | keys at fixed seconds; the Desktop now starts programs later; "up" fell during level drawing | `wait TEXT` lines on the program's own console lines | round 4 |
| `+0 wait X` never ended although X was in `console.txt` | X came while the previous line's keys were still being sent (each key event forgot the lines before it); a wait at a click's own time held back the click's release | fixed in emu816 and `inputscript.py`: lines since the input line before the wait count, and a wait starts after the earlier lines' releases. If it happens again: X came before that input line, or one X already ended an earlier wait | - |
| A held key stops acting after 1 s on the board, not in the emulator (Digger) | the board's keyboard firmware cleared keys after 1 s without a report | fixed in firmware; `run816.py --kbd-release 1000` reproduces the old board | round 2 |
| Choppy effects while the game draws (board) | the 72.8 Hz sound steps ran from the frame loop: at 60 Hz, and none during 100 ms of drawing | the music timer: `hz_sample_timer(port, us)` + `hz_recv`, polled from the drawing code (`ports/digger/horizon/hz_timer.c`) | round 2 |
| Scrolling in jumps (board) | the view moved only while the game waited | move the view at every vertical blank, also mid-work | round 2 |
| No keys, music stops when frames run late (Xargon) | a late game never waits, never calls `hg_frame` | `hg_poll()` once a game frame | 20 min |
| A mouse-driven full-screen game's pointer does not follow the mouse (X-COM) | `hg_screen` opened its window without `WF_HOVER`, and Horizon 0.30's kernel loses the window in full-screen motion events (`k2_fsmove`: none at all, a button held or not) | fixed in hgame: `WF_HOVER`, and on a kernel that sends no motion the pointer is read (`ws_mouse`) at each `hg_frame` / `hg_poll`: `hg_mouse_x/y` follow the mouse always (`gt_poll`) | in the port |
| `hg_scroll` / `hg_split` never reach the screen in a DOS port (X-COM) | it keeps its own time and calls only `hg_poll`; the view was sent only at `hg_end` | fixed: `hg_poll` sends a changed view outside a frame; `hg_view_send()` sends it at once | in the port |
| Every alien path different from DOS's (X-COM) | `cost + 4 * TILES` with `TILES` 10,000: 40,000 is -25,536 in 16-bit `int`; DOS's far pointer wrapped the offset back to 40,000, cc816's 24-bit one went 25 KB back and `memset` wrote over other tables. The port builds with `-w`, which hid `-Woverflow` | `-w` no longer silences `-Woverflow`; write `4u * T`, or build with `-ffar-wrap` (far pointer arithmetic on the offset alone, as DOS) | found by comparing with the PC build |
| Different damage than DOS (X-COM) | `hurt(u, roll_damage(), rl_side())`, both drawing random numbers: cc816 evaluates arguments left to right, Watcom right to left | `-fargs-right-to-left`; `-Wsequence-args` lists such calls | found by comparing with the PC build |
| `read(fd, p, 40000u)` "fails" (X-COM) | `ssize_t` is a 16-bit `int`: 40,000 looks negative | fixed: one `read`/`write` moves at most 32,767 bytes and returns that (a short count); loop until done (`tests/libc/bigio.c`) | in the port |
| Music clips (1-2 % of samples) | the board mixes the OPL2 3x louder than a Lau voice | convert songs 13.5 dB quieter | 20 min |
| "the function 'SimFrame' has no return type" 248 times (SimCity); a DOS strategy game's sources patched | C89's implicit int | fixed: `-std=c89` (or `-fimplicit-int`; `-fdos-keywords` implies it): warnings, `int` as C89 | hours of edits |
| "too many arguments to the function" where MSC only warned (a DOS strategy game port) | a call with an argument the definition never reads | fixed: `-fextra-args` (also `-std=c89`, `-fdos-keywords`): a warning, the extra one pushed and never read | in the port |
| Five buffers that are one (a DOS game's MESSAGE.C) | equal string literals in a file are one object (gcc does the same); DOS compilers kept each | `-fno-merge-strings` (`-fwritable-strings`) | in the port |
| The palette table written to bank $40, first crash (a DOS strategy game port, far data) | `picture_target(0)` through an unprototyped declaration: an `int` (2 bytes) pushed where a far pointer (4) is read, every later argument shifted | prototypes; `-Wunprototyped-args` warns within a file, `hcc --check-calls *.c` across files | in the port |
| `lda 980,s` "Range error" (a function with 928 bytes of spills); "Range error (35946 ...)" on a BRL (a 36 KB function) (a DOS strategy game port) | `n,s` reaches 255 bytes; BRL reaches 32 KB | fixed in cc816: the far spills go to the software stack, a far BRL is a JMP; no more `-O1` or sed | in the port |
| The program's last argument cut short (`/APPS/OUT.CTY` arrived as `/APPS/OUT`) (SimCity) | `run816.py --mode shell --args`: the shell's line editor took 77 characters (80 columns less the prompt) and dropped the rest | fixed: Horizon 0.31's line editor takes 255 (scrolling sideways); a program gets at most 127 characters of arguments (the kernel; the shell says so); run816.py refuses `--args` over 127 and a typed line over 255 | in the port |
| `hcc --sizes` said nothing when the program did not fit (SimCity linked with `--stack 512 --heap 512` to see the list) | the list came only after a link that succeeded | fixed: on a failed link `--sizes` links once more with the smallest stack to measure, or lists each file's segments from the failed map | in the port |
| No sound in the emulator from POKEY | emu816 only logs POKEY | `--log-sound` checks; listen on the board | - |
| Needed emulator options not reachable (`--card-kbps`, `--log-opl`) | run816.py does not pass them | the game's own `/BUSY:ms` for slow runs; call emu816 yourself. `--log-opl`/`--log-opl-us` now pass (Prince of Persia) | `--card-kbps` still open |
| A replay passes with one link order and fails with another (or with `--spread`, `-O0` vs `-O2`) (Prince of Persia) | `a[d + 1]` with a signed `d = -1`: the constant went into the address, X = $FFFF, and abs,X carries into the next bank | fixed in cc816 (`regress/r040`; every negative or wrapping index since, `r046`: an index stays in a register only when it is known non-negative). When results depend on placement, suspect a negative index register (`EMU816_ARGS=--log-bankwrap` reports one) or a far address used as near, before the game | 1 h 30 |
| Sprites drawn far off; no warning (Prince of Persia) | `&p->member` with `p` a `__far` pointer was typed near: given to a near parameter, it pointed into the main bank | fixed: it is a far pointer now, `-Wfar-pointer` warns (`diag/w_far_member.c`); copy into a near local and back | 40 min |
| Whole frames missing, rooms black (Prince of Persia) | `sheet_draw`/`draw_list` refuse the whole call for one bad record (a source x below 0, a rectangle past its sheet) | print `hz_errno` when a call fails; cut sources to their sheet | 40 min |
| Ctrl+G typed quickly arrives as a plain G (Prince of Persia's save) | `hg_mods` is the modifiers at the last event read: Ctrl released in the same frame as G (both in one HID report on a keyboard adapter) reads as up | fixed in hgame: `hg_key_next()` sets `hg_key_mods`, the modifiers held at that press; read shortcuts from it, not from `hg_mods` (`gt_keymods`) | 20 min |

## C pitfalls of cc816 on this machine

- **`read` / `write` move at most 32,767 bytes a call** (`ssize_t` is `int`): asked for
  more they return 32,767, a short count. `if (read(fd, p, n) != n)` with `n` over 32,767
  is then wrong: loop (`while (done < n && (k = read(fd, p + done, n - done)) > 0) done +=
  k;`), or use `fread` (`size_t` counts, no limit).
- **`int` is 16 bits** (`size_t`, pointers too). `printf("%d", a_long)` prints garbage:
  `%ld`/`%lu` and a cast. `a * b` of ints is 16 bits: `(long)a * b`. `1 << 20` shifts
  an `int` past its width: `1L << 20`. Counters of frames, ms, bytes, scores: `long`.
  Build with `-Wall`; cc816 says it plainly:

  ```
  w.c:6:13: warning: the conversion to int changes the value 40000 to -25536 (int is 16 bits in cc816: use long) [-Woverflow]
  w.c:8:14: warning: shift count (20) is negative or not less than the width of int (16 bits in cc816) [-Wshift-count-overflow]
  w.c:12:36: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long [-Wformat]
  w.c:13:9: warning: comparison is always false: 'c' is char, 0 to 255 (plain char is unsigned in cc816: use int, or signed char) [-Wtype-limits]
  w.c:11:15: warning: initialising char * with void __far *: a far pointer given to a near one loses its bank (only the offset is kept: declare the target __far too) [-Wfar-pointer]
  ```
- **Plain `char` is unsigned.** `char c = getc(f); if (c == EOF)` never matches (cc816
  warns): keep it `int`. `-fsigned-char` for PC code that needs signed `char`.
- **`double` is 32-bit `float`** (about 7 digits). Whole numbers above 16,777,216, sums of
  many small values, seconds since 1970 in a double: wrong. Use `long` or fixed point.
- **Structures are packed** (no padding). Binary files written by a PC program with
  padded structs, or with 4-byte pointers inside, do not match: read fields by hand or pad
  explicitly.
- **One object at most 65,535 bytes**, and it must not cross a bank. Bigger: a bank from
  `hz_far_alloc()` and a `__far` pointer.
- **Near vs far** (near data, the default): a plain pointer is an offset in the main bank. `(char *)hz_far_alloc()`
  points into the main bank, not the new bank (`-Wfar-pointer` warns; `-Wall` adds
  `-Wfar-cast`): say `__far`. A far string passed to `printf` or a `hui.h` call must be
  copied to a near buffer first (`hz_far_copy`). `(unsigned long)p` keeps the bank.
- **The main bank is shared** by code (small model), constants, data, bss, heap and the
  software stack. `hcc` prints what does not fit, with sizes; `hcc --sizes` lists every
  object and function, biggest first.
- **Porting a DOS large-model program** (Watcom `-ml`, MSC `/AL`: every plain pointer
  far): build with `--code large --data far` instead of adding `__far` by hand. Then:
  `sizeof(void *)` is 4 but `size_t`/`ptrdiff_t` stay 16 bits (`p - q` of 40,000 bytes is
  negative as an `int`: cast to `unsigned`, as on DOS); structures with pointers grow 2
  bytes a pointer; `(char *)some_int` gives bank 0 (use `hz_farptr` or a `long`); a
  `__near` pointer to a `const` or `__far` object loses the bank (`-Wfar-pointer`);
  `#pragma aux f = "..."` is ignored with a warning (give `f` a C body); `hui.h` is not
  there; objects of near and far data never link together. Speed: pointer-heavy loops
  8-20 % slower, calls with pointer arguments about twice, code about 27 % bigger.
- **Local arrays live on the 8 KB software stack** (`--stack N`). Big arrays: `static` or
  `malloc`. An overflow is reported only at exit ("stack overflow: ... guard zone ...
  was written"); `hcc --debug` prints what each stack and the heap used.
- **4 file handles for the whole system.** Close files at once; `fopen` returns NULL
  with `errno == ENFILE` when none is left. Each open `FILE` takes 1 KB of heap.
- **The current folder is not the program's folder.** Always use `hz_prog_dir` /
  `hz_task_path` (assembly: `task_path`) for your own files (`references/packaging.md`):
  the starter decides it (the shell its folder, a shortcut `/`, Files the folder it shows,
  the Programs menu an app's own folder). No `\`, no drive letters; FAT names ignore case.
- **stdout is line-buffered**: end debug `printf`s with `\n`. Under the Desktop console
  output goes only to the log (`console.txt` in the emulator).
- **Not there**: `system()`, `getenv()`, signals, time zones (they return failure);
  variable-length arrays, `__int128`, `_Complex`, `&&label`, nested functions,
  `__builtin_*`, `#include_next`. `aligned(N>1)`, `constructor`, `section`, `weak` are
  ignored with a warning.
- **`sscanf` brings all of scanf**; a non-constant format brings `%f`. For one number,
  `strtol`. `long long` works but a 64-bit divide is about 1 ms.
- **Inline assembly** is ca65 text; C variables as `%[name]`; scratch is `__rg+0` ..
  `__rg+47` (no cc65 `sp`/`ptr1`/`tmp1`). With `--code large` a function with inline asm
  stays in the main bank, and `.addr _func` in a `.s` file for a function in another bank
  stops the build. A `.s` function opened with `FUNC` moves like C: it leaves with
  `CALL`/`TAILJ` only, never a bare `jsl`/`jsr` (references/c-language.md, "Movable
  assembly"). `__CC816_LARGE__` tells the models apart.
- **No code runs in interrupts.** Fine timing comes from the music timer
  (`hz_sample_timer`), frames from `hz_frame()`/`hg_frame()`, `hz_uptime()` in 10 ms.
- **A file misbehaves after compiling**: try `-O1`, `-O0`, and the other code model; a
  difference is a compiler fault worth a minimal case.
- **cc65 habits**: `__fastcall__`, `<conio.h>`/`<atari.h>`/`<peekpoke.h>` POKEs and zero
  page pragmas do not apply; hardware is reached only through syscalls (a POKE to $Dxxx
  kills the task).

## Register widths (assembly)

- Programs run with A, X, Y 16-bit. `horizon.inc` sets `.smart -`: **ca65 does not follow
  REP/SEP**. After `sep #$20` write `.a8`, after `rep #$20` write `.a16` (`.i8`/`.i16` for
  X/Y). Otherwise `lda #5` gets the wrong operand size and the CPU runs into data.
- Keep 8-bit sections short; every routine starts and ends A16/I16.
- `.a8`/`.a16` are assembler state in source order, not control flow: a label reached by
  a branch from an 8-bit section needs its own `.a8`.
- A 16-bit `sta`/`stz` writes two bytes (it overwrites the next byte); a 16-bit `lda` of
  a byte needs `and #$00FF`; `inc`/`dec` on memory are 16-bit with A16. Filling a byte
  array with 16-bit stores writes one byte past an end: a spare byte, or 8-bit stores.
- `xba` swaps the bytes of A (`value * 256`, `op | colour << 8`).

## Addressing (assembly)

- **Direct page is not the data bank.** ZEROPAGE is in bank 0 (your window); DATA, BSS,
  RODATA are in the code bank (DBR). Write `lda z:var`. Without `z:` ca65 picks absolute
  for a symbol defined later in the file and reads the code bank ("Didn't use zeropage
  addressing for 'X'"). Inside brackets (`lda [ptr],y`, `lda (ptr),y`) it is always
  direct page; `[z:ptr]` is a syntax error.
- **Long pointers**: 3 bytes in zero page (+1 spare: `ptr: .res 4`); set the bank byte
  (`sta z:ptr+2`) or you read bank 0 or garbage (a kill).
- `lda f:label,x` is long; `lda label` uses DBR. `ptr label` for syscalls (X = offset,
  Y = bank); never Y = 0 for a label in the code bank (bank 0 means your window).
- Negative immediates are range errors (`adc #-4`): `sbc #4` or `#.loword(-4)`.
- A constant may not be named like a mnemonic (`STY = 8`): ca65 says only "Expected an
  expression".
- Relocated arithmetic: `lda #.loword(table + 3 * 16)`, not `.loword(table) + 48` (ld65
  "Expression too complex" for o65). `^label` = bank byte; `.faraddr label` = 3 bytes.
- `jmp (table,x)` reads the program bank; `jmp (addr)` reads bank 0.
- MVN/MVP: `mvn #^src, #^dst` for known labels; for a run-time bank patch the operand or
  copy with `[src],y`. MVN sets DBR to the destination: `phb` before, `plb` after. Never
  leave DBR changed when touching your variables or calling ulib / ui.lib.

## Syscalls (assembly)

- Only carry and the documented registers are results. **N and Z are from before the
  COP**: `sys SYS_READ` / `beq @eof` is wrong; `tay`/`beq` or `cmp #0`.
- Call with A16/I16 (`rep #$30`).
- `print` puts text inline: branches across several go out of range ("Range error"): use
  `jmp`, `jeq`, `jne`, `jcc`, `jcs`.
- `print` and ulib / ui.lib routines clobber A, X, Y. ulib output is line-buffered:
  `jsr out_flush` before waiting for input after a prompt.
- u24 fields: `.faraddr`; at run time an 8-bit store for the bank byte; keep blocks a
  byte longer than the last u24.
- `SYS_WEVENT` / `ui_getev`: A = 0 blocks, A = 1 returns C set when empty. ui.lib
  programs use `ui_getev`, never `SYS_WEVENT`.

## Program structure (assembly)

- The entry point is the first byte of CODE (loaded at $0100). `main.o` first on the
  ld65 line (a wildcard may put another module first: the program starts in the wrong
  routine). (0.29) With `HZ_NEEDS`, it is the first thing at `start`
  (`references/packaging.md`).
- End with `exit n`; never RTS from `start`. If `SYS_WSSTART` returned 1 (text shell),
  `SYS_WSSTOP` first; under the Desktop it returns 0: do not stop it.
- Sound: since Horizon 0.15 the kernel silences a program's POKEY channels and DACs when
  it ends (kernel `task.s`: `snd_task_exit`). Still silence it yourself when the game
  pauses or loses the focus.
- win_draw blits return when the blitter has read your picture. **`draw_list` does not**:
  leave sources and target alone until `list_wait` (A = 0), `vsync` or the next
  `draw_list`. `list_wait` before reading a framebuffer Ali drew into.
- Erase and redraw each sprite in consecutive calls, or a video frame can miss it.
- `win_close` of a window you do not own returns EINVAL.
- ui.lib controls are in DATA; store the window number into each control's CT_WIN
  before drawing.
- Focus: WE_UNFOCUS comes when another window takes the keyboard (the keys held got their
  releases first); a full-screen program gets it on Alt+Tab, Alt+Esc, F12.
- Zero page: ulib takes 38 bytes, ui.lib 38; ld65 "Memory area ZP overflow" past 256.
- CODE + RODATA + DATA + BSS at most 65,280 bytes ("MAIN overflow"): tables and pictures
  to a file loaded into a `SYS_BALLOC` bank.

## Full screen, sprites, draw lists (Horizon 0.18+)

- **EFAULT** from spr_set, fs_enter, draw_list, sample_play: the data is not wholly in
  your memory (window $0000-$7FFF, code bank, your banks). A range may cross two banks
  only if they are consecutive; `bank_alloc` does not promise that.
- **Sprite images 16-byte aligned** (else EINVAL); ca65 cannot align inside o65 segments:
  copy them to an aligned address. They must stay unchanged while shown.
- **Window sprites are hidden** while the window is not focused, covered, or a sprite is
  not wholly inside the content. Full-screen positions are screen coordinates.
- **Palette entries show only while you have the focus**; another program's entry: EAGAIN.
- **Full screen is one program at a time** (EAGAIN). Handle WE_UNFOCUS (pause, stop
  samples) and WE_FOCUS (re-read `frame`).
- fs_scroll / fs_enter EINVAL: Marga could read outside the framebuffer, a split line odd
  in 320 x 180 or outside 1-359, stride not a multiple of 16, base not 256-byte aligned.
  The split line counts 360 lines in every mode.
- fs_raster lines ascending, at or after the split line.
- Draw list records: A = window | count << 8 (count 1-128); LS_KEY's key is c2 (offset 3),
  LS_FILL's colour c1 (offset 2); stride 0 = the width; LS_VBL on the frame's first
  record. `vsync` also waits for your running list.

## Faults

`[kill] task N NAME cause CC addr AAAAAA pc PPPPPP` in `console.txt`; run816 exits 1; the
exit code is $FF00 + cause. Example (a C write through `(unsigned char __far *)0x7F0000L`):

```
[kill] task 4 KILL cause 03 addr 7F0000 pc 070237
```

| Cause | Meaning, usually |
| --- | --- |
| $01-$1F | protection, by bits: 0 a write, 1 not the owner, 2 bank not valid, 3 the I/O page, 4 the vectors. $02/$03: a wrong bank byte, bank 0 at $8000+ (the kernel), a stray pointer; $04-$07: a bank never allocated (bank byte not set); $08/$09: touching $00:Dxxx (hardware is syscall-only) |
| $20 | BRK: executing data (a wrong `.a8`/`.a16`, a stack imbalance, falling off a routine) |
| $21 | the stack pointer was bad when the kernel was entered |
| $22 | XCE to emulation mode (copied 6502 code) |
| $23 | interrupts off for 2 s (SEI in a long loop) |

Find the function: `pc`'s bank is the code bank, its low 16 bits an address in the map.
C: `hcc --map` writes `NAME.lbl` (`al 000228 ._poke`: pc $0237 is inside `poke`).
Assembly: `ld65 -m build/x.map ...` (CODE starts at $0100). EFAULT (A = 4, C set) from a
syscall instead of a kill: a pointer range you may not access, or one crossing a bank.
