# Porting a PC game or program to Horizon (C, cc816)

Purpose: the playbook from the two real ports, `ports/digger` (Digger Remastered: PC C
with an SDL back end, 6,600 lines) and `ports/xargon` (Xargon 1993: Turbo C for DOS, 8,350
lines, VGA mode X, Sound Blaster). Read their `README.md` and `PORTING-NOTES.md` for the
details; `sdk/docs/c/porting.md` is the general guide. C language limits:
`references/c-language.md`; library: `references/c-library.md`; hgame calls:
`references/hgame.md`; speed: `references/performance.md`; tests: `references/testing.md`;
the app archive: `references/packaging.md`.

## What it took (to set expectations)

| | Digger | Xargon |
| --- | --- | --- |
| Game lines changed (`upstream.patch`) | 79 added, 26 removed, 11 files | 82 include lines + 45 others, 6 files |
| New platform layer (`horizon/`) | ~1,200 lines: 6 C, 3 headers, 1 `.s` | ~2,300 lines: 9 C, 2 headers, 1 `.s`, 5 DOS headers |
| Build | `hcc --code large`, DIGGER.PRG 110 KB + DIGGER.DAT 292 KB | `hcc --code large`, XARGON1.PRG 190 KB + 2 MB of data |
| Time to a playing game | 45 min (2.5 h with tests and notes) | about 11 h in all (3 h of it speed work) |
| Determinism | 7 upstream recordings end exactly as upstream's CI | the recorded demo replays exactly, also 30 ms/frame slower |

Both ports pass `make test` today (`ports/digger`: also `make test-app`).

## Order of work

1. **Upstream first, on a PC.** Pick a commit, build it, run its tests, keep what it
   prints. Note its replay facility (Digger: `.drf` recordings with upstream's CI results;
   Xargon: the menu's demo). A replay compared with the PC's result is the best test.
2. **Read the back end.** List the functions the game calls in its platform files
   (`sdl_*.c`, `vga.c`, `sound.c`, `timer.c`, `keyboard.c`). That list is your platform
   layer's interface. Leave out the other back ends, threads and locks, network play, a
   software synthesizer.
3. **Make it compile** (below): a Makefile, `-D_HORIZON`, `-Wall`, every warning read.
4. **Write the platform layer** in `horizon/` with the same interface.
5. **Make it fit the main bank** (below). Expect this; both ports hit it.
6. **First run, then the replays** at full speed. Digger's passed at the first run.
7. **Tests that follow the program**: scripted game with `wait`, pictures at game frames,
   file checks, sound checks (`references/testing.md`).
8. **Speed**: count late frames in the game itself, then profile (`references/performance.md`).
9. **Notes**: keep a `PORTING-NOTES.md` (every change, every SDK problem, the time each
   took) and `upstream.patch`.

## Make it compile

The Makefile can use `sdk/c/c.mk` (Digger) or call hcc itself (Xargon: one `.o` per
file, three programs). Digger's settings:

```make
NAME      := digger
SDK       ?= ../../sdk
RUNMODE   := desktop
HZ_CODE   ?= large
SRCS      := $(wildcard src/*.c) $(wildcard horizon/*.c) horizon/hz_blit.s build/alpha_ok.c
NEEDS     := horizon=0.28,sprites,mem=1280K
HCCFLAGS  += --needs $(NEEDS) --map --stack 4096 --heap 4096 -D_HORIZON \
             -Dmain=digger_main -I src -I horizon -fsigned-char
include $(SDK)/c/c.mk
```

Xargon's compile flags: `--code large -D_HORIZON -I src -I horizon -I horizon/compat
-include horizon/xcompat.h -fsigned-char`; link: `--code large --game --map --stack 4096
--heap 7168`. `.s` files in a large program are assembled with `hcc --code large -c`.

- **Choose the platform with a macro** beside upstream's: `#if defined(_HORIZON)` next to
  `#if defined(_SDL)`. Keep every change to upstream's files inside such blocks.
- **Upstream's `main`**: build with `-Dmain=game_main` (Digger: `-Dmain=digger_main`;
  Xargon: `#define main xargon_main` in the `-include` header) and write `main` in
  `horizon/hz_main.c`. That `main` goes to the program's folder first (below), reads test
  files, then calls upstream's.
- **`-fsigned-char`** when the PC build had signed `char` (gcc/clang on x86, Turbo C).
  Plain `char` is unsigned by default here.
- **DOS keywords**: `#define far __far`, `#define huge __far`, `#define near`. Borland's
  `char huge *a, huge *b;` (qualifier before a declarator's `*`) is not C: cc816 says
  "Invalid declarator"; write one declaration each.
- **Turbo C / Borland** (Xargon): small headers of your own for `dos.h`, `conio.h`,
  `io.h`, `alloc.h`, `mem.h` (`-I horizon/compat`); Borland's names (`max`, `min`, `itoa`,
  `ltoa`, `ultoa`, `random(n)`) in one header given to every file with `-include`. POSIX
  `open`/`read`/`write`/`lseek`/`close`/`creat` are in the SDK (`fcntl.h`, `unistd.h`).
  Keep Turbo C's `rand` (seed * 0x015A4E35 + 1, bits 16-30: `ports/xargon/horizon/hz_dos.c`)
  if the game records demos: they replay only with the same numbers.
- **Absolute DOS include paths** (`#include "\develop\xargon\include\gr.h"`) become
  `"gr.h"` with `-I src`. CP437 bytes and CRLF line ends compile as they are.
- `stricmp`/`strnicmp` → `strcasecmp`/`strncasecmp` (`<strings.h>`).
- Build with `-Wall` and read every warning: most are the 16-bit `int`, the unsigned
  `char` or a far pointer.

## The platform layer: what replaces what

Keep upstream's hardware-level calls and make each one a small function, instead of
changing the game. Xargon's `graphics.c`, `gamectrl.c` and `windows.c` run unchanged
because the few ports and BIOS addresses they touch are emulated.

| Part | PC original | Digger (`horizon/`) | Xargon (`horizon/`) |
| --- | --- | --- | --- |
| Video | SDL surface / VGA mode X | `hg_screen_fb(HG_640X360X4, ...)`: a 400-row, 512-byte-stride framebuffer; the game draws by the CPU into a buffer of its own (`hz_blit.s`, MVN row copies); changed rectangles copied after each vertical blank; `hg_split` keeps the score line, the playfield follows the digger (`hz_vid.c`) | one framebuffer, both pages, 512-byte rows with horizontal wrap; page flip = scroll registers (`hz_fs_scroll`); tiles and sprites from an atlas in far memory as `hz_sheet_draw` records (the blitter draws); fonts via a glyph cache sheet (`hz_vga.c`, `hz_shm.c`) |
| Palette | SDL palette / DAC `outportb(0x3C8/0x3C9)` | `hg_palette` | the DAC writes fill a shadow palette, sent once a frame |
| Input | `SDL_KEYDOWN` scancodes / int 9 | `hg_key_next()` (usage bits 0-7, character 8-15): SDL scancodes are HID usages, upstream's key table works as it is; `hg_key_pressed`, `hg_joy` (`hz_kbd.c`) | the BIOS queue rebuilt from `hg_key_next` (ASCII or 128 + PC scan code from a HID table), `keydown[]` for polled arrows; the game port `inportb(0x201)` emulated from `hz_joystick` |
| Timer | SDL timer, 80 ms frames | `gethrt()` waits by the frame counter and by the music timer's clock (`hz_timer.c`) | the BIOS tick at 0040:006C becomes a macro over a function counting vertical blanks at 18.2065/60.03; VGA retrace `inportb(0x3DA)` from the frame counter (`hz_frame.c`) |
| Sound | PC speaker (PIT timers 0 and 2) | two POKEY 16-bit voices: `hg_note(v, 1193182 / divisor, vol)` (`hz_snd.c`) | effects on Lau (`hg_sound_from` with far samples, `hg_play`); CMF music converted at build time to IMF, played by `hg_opl_play` (`hz_snd.c`) |
| Files | stdio in the current folder | `hz_prog_dir` + `hz_chdir` at start: scores, INI, recordings next to the program (`hz_main.c`) | the same; `open`/`read`/`lseek` as upstream; `hz_readfar`/`hz_writefar` (port-local helpers in `hz_dos.c`, a 256-byte near buffer + `hz_far_copy`) for the 16 KB board in far memory |
| Data | C arrays / DOS data files | `tools/mkdata.py` turns upstream's picture arrays into DIGGER.DAT; loaded into far banks with `hz_read` (`hz_io` with `HZ_U24(io.buf, farptr)`) | `tools/mkdata.py` turns the game's files into an atlas, sound and song files |

Rules learnt:

- **Do not draw by the CPU into the shown framebuffer** when drawing takes milliseconds:
  1 screenshot in 7 caught a half-drawn sprite. Draw into a buffer, copy the changed
  rectangles right after the vertical blank.
- **Or let the blitter draw.** Every CPU write to the framebuffer waits for the SDRAM
  (about 12 cycles a byte even with MVN). Sheets + `hz_sheet_draw` records moved Xargon
  from 8.2 to 3.46 blanks a frame (with the other speed work).
- **Do not squash 400 rows into 360.** Show the picture at its size and scroll
  (`hg_screen_fb` + `hg_split`); the PC's pixels were not square either.
- **Late frames still need events.** A game whose frame runs longer than its tick never
  waits, so never calls `hg_frame`: call `hg_poll()` once a frame (keys, pause, music).
- **Main program folder**: never rely on the current folder (the shell starts programs in
  `/`). Digger's `main` does `hz_prog_dir(buf, 128)`, strips the last `/`, `hz_chdir(buf)`.

## 16-bit int traps

`int` is 16 bits, `size_t` 16 bits, pointers 16 bits. Code from 16-bit DOS (Borland,
Turbo C) is usually safe; code written for 32-bit `int` is not. Digger needed 4 fixes,
all format strings; Xargon none in its logic.

| Trap | Example | Fix |
| --- | --- | --- |
| Format strings | `printf("score=%d", int32)`, `sprintf(buf, "%i", int32)` (Digger's INI default 80,000 would read back as garbage) | `%ld`/`%lu` with a `(long)` cast. cc816's `-Wformat` found 3 of Digger's 4 at the first compile |
| Explicit narrowing | `(unsigned)frames` of a 32-bit counter: wraps at 65,535 | keep it `unsigned long` |
| Counters | frame counts, scores, ms times, file sizes | `long`; `-Wtype-limits` flags `x > 40000` on an `int` |
| Constants | `int x = 40000;`, `320 * 200` | `-Woverflow` warns; write `320L * 200` |
| Products | `a * b` of two ints is 16 bits | `(long)a * b` |
| Shifts | `1 << 20`, `x << 16` on an `int` | `1L << 20`; `-Wshift-count-overflow` |
| Sizes | one object, `malloc`, `fread` at most 65,535 bytes | far banks for big data |
| `hz_read` result | an `int`: a read of 32 KB returns -32,768, taken as an error (Xargon's effects did not load) | read pieces of 16 KB, or compare with `(int)len` as Digger's `rd()` does |
| `sizeof(pointer) == 2` in file formats | Xargon's boards store Turbo C's 4-byte far pointer inside a 31-byte record | add `int inside_hi;` after the 2-byte pointer to keep 31 bytes (cc816 does not pad structures); treat segment != 0 as non-NULL |
| `char` signedness | `char c = getc(f); if (c == EOF)` never true | keep `int`; `-fsigned-char` for PC code |

## The main bank budget and far data

With `--code large` the C functions (yours and the libraries') move to other banks, but
the **main bank** still holds: the startup and all assembly (`.s` files, functions with
inline asm), constants (string literals, `const` tables), initialised data, bss, the heap
(`--heap N`, default 4096) and the software stack (`--stack N`, default 8192). That is the
real limit of a big port. `hcc --map` prints its parts:

```
the main bank without its movable code: 34,886 bytes (code that must stay 9,060,
constants 8,183, data 2,148, bss 15,495)
```

What overflowed and what fixed it:

| Port | Problem | Fix |
| --- | --- | --- |
| Digger | 8.8 KB of sprite save-under buffers in bss | DOS's `huge` made `__far`; the buffers in a far bank (`hz_bufs.h`) |
| Digger | `sscanf(word, "%hi", &startlev)` brought all of scanf with float: 7.6 KB | `strtol` |
| Digger | 256 KB recording buffer | 64 KB: one bank from `hz_far_alloc` (upstream's `farmalloc`) |
| Xargon | `int bd[128][64]` (16 KB) | `int far bd[128][64]`: a `__far` object, a bank of its own |
| Xargon | `init_info` malloc'd 900 tile names (8.5 KB, the whole heap): every later malloc failed, text objects drawn from address 0 | names read past, not kept |
| Xargon | hgame's record queues, 7 KB of bss | still open (SDK limit) |

The cures, in order:

1. Big `const` tables: `__far const unsigned char maps[8][2000] = {...};` (a bank of
   far data, loaded with the program; reach them through `__far` pointers).
2. Big buffers: `hz_far_alloc()` (64 KB, `NULL` if none), `unsigned char __far *p`.
   `hz_mem_info()` says how many banks are free.
3. Art and sound: convert at build time into a data file, load it into far banks.
4. `strtol` instead of `sscanf`; no `%f` formats unless needed.
5. `--stack 4096` when `hcc --debug` shows the software stack uses little.
6. Keep `--heap 4096` or more: `fopen` takes 1 KB of heap per open file (128 bytes or
   none when the heap is short; `setvbuf(f, NULL, _IONBF, 0)` frees it). Digger's
   `--heap 1024` made the second `fopen` fail with ENOMEM.

`__far` costs: every access is long addressing. cc816 now indexes `__far` arrays of
arrays with 16-bit indexes in Y, but a hot loop over far data is still slower than near
data. A far string given to a function taking `const char *` (printf, hui.h) must be
copied into the main bank first (`hz_far_copy` into a static buffer).

## Timing and the sound clock

A Horizon program runs no code in interrupts. Clocks it has:

| Clock | Resolution | Use |
| --- | --- | --- |
| `hz_frame()` / `hg_frame()` | 60.03 Hz (16.66 ms) | frame pacing, the vertical blank |
| `hz_uptime()` / `hg_ms()` | 10 ms steps | coarse timing |
| `hz_sample_timer(port, period_us)` + `hz_recv(port, &msg)` | a message every period, count follows the µs clock | the only fine clock; needs Lau (REV $0A+) |

- **Map the game's tick to frames, not 1:1.** Digger's 80 ms frame = 4.8 vertical
  blanks: frames come 5, 5, 5, 5, 4 blanks apart (12.5/s on average). Xargon's BIOS tick
  (18.2065 Hz) = 3.30 blanks; its `*myclock` reads count blanks at 18.2065/60.03.
  `hg_steps(hz)` gives logic steps at a fixed rate independent of the frame rate.
- **Sound that keeps time while the game draws** (a PC timer interrupt at 72.8 Hz, a
  tracker): Digger first ran `soundint()` from the frame loop by the frame counter. Two
  faults on the board: steps at 60 Hz (one in five blanks ran two steps back to back, the
  first inaudible) and none while the game drew a frame (up to 100 ms). Fix
  (`ports/digger/horizon/hz_timer.c`): `hz_port_create()`, `hz_sample_timer(port, 3434)`
  (a quarter of a sound step), sleep on `hz_recv` while waiting, and look at the clock
  from the drawing code when the next step is due. Steps cut short went from 45 of 202 to
  7 of 220. Without Lau it falls back to the frame counter.
- **The view must move at every vertical blank**, also in the middle of the game's work
  (Digger's scrolling jumped while it moved only in the waits).
- **OPL2 music from a DOS game**: convert to an IMF register stream at build time, play
  with `hg_opl_play`; the stream is timed by frames (60 Hz where the Sound Blaster driver
  ticked at 96 Hz: a note may be up to 1/60 s late). The board mixes the OPL2 three times
  louder than a Lau voice: Xargon's songs are converted 13.5 dB quieter (they clipped).
- POKEY is silent in the emulator: check its writes (`--log-sound`, `--log-sound-us`);
  Lau and the OPL2 can be recorded (`--wav`).

## Deterministic tests with recorded input

- **Upstream's replays.** Digger's `tests/drf.sh` plays 7 of upstream's `.drf` recordings
  at full speed (`--mode shell --args "/Q /S:0 /E:NAME.DRF"`, the recording put on the
  card with `--file`), greps the game's `score=` line from `console.txt` and compares it
  with upstream's CI result (`tests/drf/*.drf.out`). The game logic reads framebuffer
  pixels, so this checks drawing too. The program must print its result line in every
  build (Digger prints it always; upstream asked an environment variable).
- **The game's own demo.** Xargon's `tests/check.sh` starts the menu's demo and the game
  prints its state at frame 1,500 (`xargon: demo reached at frame 1500: score ...`),
  compared with `tests/demo.ref`; then again with `/BUSY:30` (30 ms more CPU a frame):
  the same line proves the logic does not depend on timing.
- **A recording of your own scripted game** (Digger's `tests/play.drf`, made with F8):
  played back, it is the same frame by frame however fast the program runs: the base of
  the picture tests.
- **Test-only inputs read from files next to the program** (Digger: `SHOTS.TXT` = game
  frames to stop at; `DELAY.TXT` = delay the start, to prove scripts follow the program).

## Picture tests at game frames (--shot-on)

Screenshots at fixed seconds broke whenever timing moved (a key held 6.5-9 s landed in
other game frames). Digger's `tests/frames.sh`:

1. plays `tests/play.drf` back at full speed;
2. at each game frame listed in `SHOTS.TXT` the program stops: shows the frame drawn,
   puts the view at its place, waits two vertical blanks, prints `digger: shot N frame F`,
   then holds the picture for six blanks (`shot_check` in `hz_timer.c`);
3. `run816.py --shot-on "digger: shot"` takes `autoN.png` two frames after each line;
4. `tests/cmpshots.py build/frames tests/ref frame --prefix auto` compares pixel for
   pixel with `tests/ref/frame-N.png` (`--update` writes them; look first).

Checked: passes on a fresh checkout, with code added to `hg_frame`, and with every
function moved out of the main bank (`hcc --main-room 0`); an emerald drawn two rows short
fails 7 of 9 pictures. Xargon keeps MD5s of fixed-time screenshots instead
(`tests/shots.py`, `tests/play.md5`) because its data may not be in the repository; that
test moves with timing (`make refs` after a change meant to show).

## Keeping upstream diffs

- Upstream's files stay in `src/` as upstream has them, plus your changes, all in
  `#if defined(_HORIZON)`. `upstream.patch` is a unified diff of upstream's files against
  `src/` (`diff -ruN`). Upstream's
  data arrays stay unchanged and are converted at build time (`tools/mkdata.py`).
- Files you replace wholesale (Xargon's `config.c`, `keyboard.c`, `music.c`,
  `shapeman.c`) are not built; their replacements in `horizon/` keep the same interface.
- Record the upstream commit or release, its licence, and the exact files not taken.
- Data you may not redistribute (Xargon's) stays out of git: a `tools/getdata.sh` that
  downloads it (checksum-verified) and `make data`; test pictures kept as MD5s.

## A port is done when

- [ ] It builds from a clean checkout with one `make` (data converted at build time).
- [ ] It says what it needs at start (`hcc --needs ...`) and the README states it.
- [ ] Upstream's replays or demo end exactly as on the PC (score, level, frame count),
      also on a slower run (`/BUSY`-style option or delayed start).
- [ ] `make test` passes: a scripted game that waits for the program's console lines,
      checks the files the game wrote (scores, saves) on `build/.../card/`, its sound
      writes or WAV, and pictures at game frames against references you looked at.
- [ ] It keeps time: late frames counted and printed by the program; speed within a few
      per cent of the original, or the shortfall measured and written down.
- [ ] Saves and settings go next to the program (`hz_prog_dir`), and an app archive
      exists if it is to be installed (`references/packaging.md`).
- [ ] `README.md` (build, run, keys, screen and sound choices, what differs, tests,
      licence), `PORTING-NOTES.md` (every change and why, SDK problems, time taken),
      `upstream.patch`.
