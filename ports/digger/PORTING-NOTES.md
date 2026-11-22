# Porting notes: Digger on the Atari816

The first real program ported with the C SDK, and its acceptance test. This file lists
every change the game's code needed and why, every SDK problem met (and what became of
it), and how long each kind of work took. It is the feedback for the SDK and for
`sdk/docs/c/porting.md`.

Upstream: Digger Remastered (Andrew Jenner) as kept by Maksym Sobolev,
<https://github.com/sobomax/digger>, commit `53bf330` (2026-03-26, "Unify logs and make
sure to lock it..."): the last commit before the network play ("netsim", `679f030`) was
added, the plain SDL game. Its game files are in `src/` as upstream has them except the
changes below (`upstream.patch` is all of them); the pictures stay in
upstream's C files (`src/data/`, unchanged) and become `DIGGER.DAT` at build time.

## The numbers

| | |
| --- | --- |
| Upstream C ported | 16 game files, 6,636 lines (+ 9,000 lines of picture data, converted at build time) |
| Game lines changed | 79 added, 26 removed (`upstream.patch`, comments included), in 11 files; most are `#if defined(_HORIZON)` |
| New platform layer | `horizon/`: 6 C files, 3 headers, 1 assembly file: about 1,200 lines (video, blitting, keyboard and joystick, timing and the view, sound, data loading, start-up) |
| Build | `hcc --code large`: DIGGER.PRG 109,541 bytes (the o65 / main bank 43,931; one more code bank 65,610; main bank 56,939 of 61,168 used, 4 KB heap, 4 KB software stack) + `DIGGER.DAT` 292,342. At run time 17 banks (1.1 MB): framebuffer and drawing buffer 4 + 4, pictures 5, tables, save-unders, recording, code |
| Determinism | all 7 of upstream's recorded games that run in under 20 min play back exactly (score, level and frame count equal upstream's own CI results) |
| Speed | 12.5 game frames a second as the original; about 12-17 ms of CPU a frame of 80 (see "Speed" below) |
| Time | about 45 minutes from `git clone` to a game that plays and passes upstream's recorded games; about 2.5 hours with the tests, the SDK additions and these notes |

## Changes to the game's code, by kind

**16-bit `int` (4 places, all format strings).** Upstream prints 32-bit values with `%d` /
`%i`, right where `int` is 32 bits:

- `main.c` `game_dbg_info_emit`: `printf("score=%d ... frames=%u", int32, ..., (unsigned)uint32)`
  → `%ld` / `%lu` with casts. (The frame count was even cut to `unsigned` explicitly: on
  a 16-bit machine that loses frames above 65,535.)
- `ini.c` `GetINIInt` / `WriteINIIntconst`: `sprintf(buf, "%i", int32)`: the INI's
  default values (the speed, 80,000 microseconds) would have been read as garbage. Found
  by cc816's `-Wformat` warning before the first run.
- `record.c` `recsavedrf`: the recording's file name from the score (`%i` of an `int32_t`).

Nothing else of the game logic needed a change for 16-bit `int`: Andrew Jenner's code
came from 16-bit DOS (Borland C) and uses `int16_t` / `int32_t` where it matters. The
proof: the recorded games below.

**Plain `char` signedness: none needed, `-fsigned-char` kept.** The PC builds have signed
`char`; the port is built with `-fsigned-char` to be the same. (The recorded games also
pass, so where `char` signedness would show it does not differ.)

**Memory: the main bank (3 changes).** With `--code large` the code moves to other banks,
but the libraries, constants, data and bss do not, and Digger's did not fit by 8.5 KB at
first:

- `drawing.c`: the sprites' save-under buffers (`monbufs` ... `firebufs`, 8.8 KB) are in a
  bank of far memory. Upstream already has a word for that, DOS's `huge`: `def.h` makes
  `huge` `__far` here (empty elsewhere) and the buffer pointers in `draw_api.h`,
  `hardware.h`, `sprite.h`, `sprite.c` become `uint8_t huge *`. `drawing.c` takes the
  buffers from `hz_bufs.h`.
- `main.c`: `sscanf(word, "%hi", &startlev)` (the `/I:` option) → `strtol`: `sscanf`
  brought the whole of scanf, with its floating point (the program uses `double` once,
  in `music()`), into the main bank: 7.6 KB.
- `def.h`: the recording buffer (`MAX_REC_BUFFER`) is 64 KB (one bank, from far memory)
  instead of 256 KB; `farmalloc` gives a bank. About 9 hours of play instead of 36.

**Borland's `huge` (1 change).** `record.c` declared `static char huge *recb, huge *plb,
huge *plp;`: a qualifier before a declarator's `*` is not C (Borland took it). With `huge`
now `__far`, cc816 rightly refused it ("Invalid declarator"); split into three
declarations.

**The platform hooks (the rest).** Upstream chooses its back end with `_SDL` / `_VGL`; the
port adds `_HORIZON` beside them: `input.c` includes `hz_kbd.h` (the keys held), `sound.c`
treats the sound device as SDL's (`pausesounddevice`, `wave_device_available`, waiting in
`soundlevdone`), `sprite.h` declares `doscreenupdate`, `main.c` takes the s1 (sample)
sound functions, logs to stderr, and prints the recorded game's result at the end of
`/E:` always (no environment variables here: upstream asks `DIGGER_CI_RUN`), `def.h` maps
`stricmp`/`strnicmp` to `strcasecmp` and declares `strupr`. `draw_api.h` includes `def.h`
(for `huge`). `main.c` is built with `-Dmain=digger_main`, as upstream's Windows build
makes it `SDL_main`: `horizon/hz_main.c` starts it.

**Not taken from upstream:** the SDL and FreeBSD back ends (`sdl_*.c`, `fbsd_*.c`), the
PC speaker synthesizer (`newsnd.c`, `soundgen.c`: POKEY plays the tones itself),
`digger_log.c` (it locks with C11 atomics for SDL's threads: a plain one in
`hz_main.c`), `spinlock.c`, `digger_math.c` (only the SDL timer's filters), `icon.c`,
`title_gz.c` / `vgagrafx.c` / `alpha.c` as code (their data is converted, see below),
`cgagrafx.c` (the CGA set: the VGA set is used).

## The platform layer (horizon/)

- **Video (`hz_vid.c`, `hz_blit.s`).** Upstream draws by software sprites with save-unders
  (`sprite.c`) on top of a small interface: put a rectangle, get one, put a masked
  sprite, read the pixels under a point (`ggetpix`: the game logic uses it to see
  tunnels!), write a character, the title. These are done as the DOS VGA version did
  them: by the CPU, into a 640 x 400, 16-colour picture (4 bits a pixel, packed). The
  pictures are packed the same way at build time (`tools/mkdata.py`: upstream's
  `vgagrafx.c` arrays, each sprite with its mask, the font in its four colours, the
  title from `title_gz.c` decompressed), loaded into far memory, and drawn by six small
  assembly loops (16 bits at a time; a masked sprite of 32 x 30 is about 0.5 ms). The game
  draws into a buffer of its own; the rectangles it changed are copied to the screen
  just after each vertical blank, so a sprite is never seen half drawn (before that,
  1 screenshot in 7 caught one between its erasing and its drawing).
- **The screen: 640 x 360 for a 640 x 400 game.** See README.md ("The screen"): hgame's
  new `hg_screen_fb` gives a 400-row framebuffer (512-byte rows: never across a bank) and
  `hg_split` keeps the score line fixed while the 372 rows of the playfield are shown 332
  at a time, following the digger.
- **Timing (`hz_timer.c`).** Upstream's `gethrt()` waits for the end of each 80 ms frame.
  Here it waits by hgame frames (60.03 a second, the frame counter as the clock), which
  read the events, run the sound's interrupt and move the view. Frames come 5, 5, 5, 5, 4
  vertical blanks apart: 12.5 a second on average, as on the PC.
- **Sound (`hz_snd.c`).** Upstream's `sound.c` plays everything on the PC speaker, by the
  PIT's timer 2 (effects) and timer 0 (music, its loudness a pulse width), changed by
  `soundint()` 72.8 times a second. Each timer is one of POKEY's channel pairs joined to
  16 bits at 1.79 MHz (hgame's new `hg_note`), a square wave like the speaker's at exactly
  the speaker's pitch (1193182 / divisor Hz); `soundint()` runs from the frame loop as
  often as 72.8 Hz makes due. The music's envelope is the pair's volume. Popcorn, the
  William Tell bonus music, the dirge and every effect play. The level-end jingle's
  beating (timer 2 modulating timer 0) is played as its plain notes.
- **Keyboard and joystick (`hz_kbd.c`).** Upstream's key codes are SDL scancodes, which
  are HID usages, which is what Horizon's keys are: the key table is upstream's, as it
  is. The keys pressed come in order from hgame's new `hg_key_next` (with their
  characters, for the initials). Joystick 1 moves player 1 and its trigger fires; joystick
  2 player 2 (upstream has no joystick for SDL).
- **Files (`hz_main.c`).** The program goes to its own folder at the start
  (`hz_prog_dir`), so `DIGGER.SCO` (the high scores, upstream's format), `DIGGER.INI` and
  the recordings are kept next to it.

## SDK problems met

| # | Problem | Kind | What was done | Time |
| --- | --- | --- | --- | --- |
| 1 | **cc816 refused `static struct bag {...} a[7], b[7], c[7];`** ("redefinition of 'struct bag'", then "'b' undeclared"): a structure, union or enum defined in a declaration of more than one declarator was defined again for each (pycparser gives every declarator the same node). An anonymous one gave each declarator a type of its own, so `a = b` was refused. Basic C; no test had it | compiler bug | fixed (`cc816/front.py`: a definition node is read once), `tests/regress/r026_struct_two_declarators.c` | 15 min |
| 2 | **`<strings.h>` missing** (POSIX: `strcasecmp`; the library had the functions, declared in `string.h` only) | library gap | added `cc816/include/strings.h`, `tests/regress/r027_strings_h.c` | 5 min |
| 3 | **No way to show a game taller than the screen.** 320 x 200 and 640 x 400 are the commonest PC sizes; the screen modes are 180 / 360 rows. hgame's full screen had a framebuffer of exactly the screen, and its scroll registers were only reachable through `hg_map` (tiles) | hgame gap | added `hg_screen_fb(mode, title, stride, rows)` (any framebuffer shape; a stride of 512 / 1024 keeps rows in one bank for CPU drawing) and `hg_scroll` / `hg_split` (the view; a fixed panel over a part that scrolls). Test `sdk/c/game/tests/gt_view.c`, documented in games.md | 30 min |
| 4 | **No exact-pitch tone.** hgame's POKEY voices are 8-bit dividers on the 64 kHz clock: about 4 % between steps at 1 kHz, nothing below 125 Hz. A PC speaker port (and any music) needs exact pitches | hgame gap | added `hg_note(v, hz, vol)`: the two 16-bit voices (channels joined, 1.79 MHz). Tested in gt_view (AUDCTL logged) | 15 min |
| 5 | **No ordered key events.** `hg_key_pressed` is a bitmap per frame (order lost, no character), `hg_getchar` has no usage. SDL code reads `SDL_KEYDOWN` events: usage and symbol, in order | hgame gap | added `hg_key_next()`: usage in bits 0-7, character in 8-15. Tested in gt_view | 10 min |
| 6 | **The main bank fills up even with `--code large`.** Libraries stay in the main bank: here 30 KB of C library (printf and scanf with floating point: one `double` in the program brings `%f` formatting and, with any `sscanf`, float scanning), 7.5 KB of hgame code and 8.5 KB of hgame bss (its record queues, also when only `hg_screen` is used). Digger's own data and bss are 17 KB. The first link failed by 8.5 KB | SDK limit | worked around in the game (save-unders and tables in far memory, no `sscanf`; see above). **Fixed in the SDK since:** the libraries' C functions move to other banks as the program's do (only the startup, the assembly and the loader of the banks stay); a printf's or scanf's constant format links the float (and `long long`) conversions only when it has one; `__far` objects at file scope go to banks of far data (reference.md, "Far objects"). Digger's main bank without its movable code: 53,946 bytes before, 33,488 after. Still open: hgame's record queues (7 KB of bss) | 30 min |
| 7 | **`fopen` failed with ENOMEM** (saving a recording): with `--code large` hcc fills the main bank with code up to `--heap N` bytes, and every `fopen` mallocs a 1 KB buffer. With `--heap 1024` (tried to make room) the second file failed silently | doc / usability | `--heap 4096` (the default) again. **Fixed in the SDK since:** `fopen` takes 128 bytes, or no buffer at all, when the heap has no 1 KB (the FILE structures are static); `setvbuf(f, NULL, _IONBF, 0)` frees the 1 KB; `strerror(ENOMEM)` names the heap; `hcc --debug` prints the heap's most use at exit, `hz_heap_free()` / `hz_heap_peak()` tell it any time; reference.md, "The heap and the stacks (cc816)" | 10 min |
| 8 | **The profiler does not read cc816's maps.** `sdk/c/game/tests/tools/prof816.py` parses vbcc's link maps (`NNN_text.name addr(size)`); cc816's ld65 map (and the large model's banks) give it nothing | tool gap | measured with counters in the game instead (`hz_timer.c`: frames late, CPU a frame). **Fixed since:** `emu816 --prof` (`run816.py --prof FILE --prof-from S --prof-to S`) counts the cycles by address, and prof816.py reads cc816's maps and label files in both code models (games.md, "Speed") | 10 min |
| 9 | **A large program needs Horizon 0.28**, which was not yet committed when the port started (HEAD's 0.27 says "not a Horizon program, or its file is damaged"); the port's tests ran on a copy of the work-in-progress 0.28 tree, which has since been committed (`560701b`) | state of the repository | none needed now | 5 min |
| 10 | **POKEY is silent in the emulator** (only logged): the game's sound can only be checked by its register writes (`--log-sound`) or on the board | emulator limit (known) | the test checks the writes | - |

Nothing else went wrong in the compiler: 6,600 lines of 1998-2026 C with designated
initialisers, `bool`, GNU `args...` variadic macros with `##` (`CALL_METHOD`), function
pointers in structures, `int8_t` arrays initialised from strings, `__attribute__((format))`,
`double`, `strtol`, `fseek`/`ftell`: all compiled as they are, and the game logic runs
exactly as on the PC (below). cc816's `-Wformat` found three of the four 16-bit format
bugs at the first compile.

## Testing: the recorded games

Upstream's CI plays recorded games (`tests/data/*.drf`: the keys of every frame and the
random seed of every level) at full speed and compares the score, the level and the frame
count at the end with its results. `tests/drf.sh` does the same in the emulator with
the seven recordings that finish in under 20 emulated minutes: all seven end exactly as
upstream's (from 1,330 frames to 41,561, nine levels). The game logic reads the
framebuffer (`ggetpix`), so this also checks the drawing pixel for pixel where the game
looks. It passed at the first run, before any other test: the strongest single check of
the compiler in this port.

`make test` also plays a scripted game (`tests/play.script`): the title, a game started,
digging up through two emeralds, a shot, three lives lost to the nobbins, game over, the
initials typed, the new high score on the title and in `DIGGER.SCO`, the game's recording
saved with F8 and played back to the same score. The screenshots are compared with
`tests/ref/` pixel for pixel (the game is deterministic: no random seed outside playback,
and the emulator's time is exact) — any change of the program's timing (even a different
placement of its code) moves them, and then `make refs` writes them again after a look.

## How long each kind of thing took

(Wall-clock time of the agent doing it, with emulator runs on a fast PC.)

| | |
| --- | --- |
| Finding the source and its licence, choosing the commit, building upstream on a PC and running its recorded-game tests | 15 min |
| Reading the game and its back-end interface, choosing the screen and the sound | 25 min |
| Making upstream's files compile (the two compiler/library faults, the 16-bit formats, the hooks) | 10 min |
| The platform layer (video and its assembly, data converter, timing, sound, keys) | 25 min |
| Making it fit the main bank | 15 min |
| First run to a playing game; the recorded games passed at once | 5 min |
| hgame's additions (`hg_screen_fb`, `hg_scroll`/`hg_split`, `hg_note`, `hg_key_next`), their test and documentation | 20 min |
| The scripted test, screenshots, the drawing buffer (no half-drawn sprites), timing statistics, the recording round trip (and the `fopen` ENOMEM it found) | 35 min |
| The SDK's suites, these notes and the README | 25 min |

## Speed

Measured in the emulator, the game paced as played (upstream's 80 ms frames):

| Run | Game frames | Time | Late frames | CPU a frame (average, most) |
| --- | --- | --- | --- | --- |
| The scripted game (`make test`): title, level 1, three deaths, initials | 792 counted | 68.7 s for the whole run | 21 (the level start, the deaths) | 12 ms, 616 ms (drawing a level) |
| Upstream's `thevoids.drf` played back at the game's pace (9 levels) | 41,561 | 3,365 s; at exactly 80 ms 3,325 s: 1.2 % slower in all | 424 (1.0 %) | 17 ms, 166 ms |

"Late" is a frame whose drawing and logic ended after the end of its 80 ms. They come in
runs: when several nobbins, the digger and its shot overlap, upstream's sprite engine
puts back and redraws every overlapping sprite for each one that moves (quadratic), up
to about 100 ms a frame here; for a few seconds the game is then up to a fifth slower
than the PC (which did the same work in microseconds). Without the drawing buffer (the
game drawing straight into the shown framebuffer) the same playback had 115 late frames:
the copying to the screen costs about 1-3 ms a frame.

**Later: faster blits and compiler.** A profile (`run816.py --prof`, `prof816.py`; 100 s
of `thevoids.drf` at full speed) put 47 % of the CPU in the six blit routines of
`horizon/hz_blit.s`, a third of that in finding each row's address. Now the rows' copies
are MVN (its banks written into it), the next row's address is a 512-byte step, and the
masked put reads the sprite with absolute,Y addressing; cc816 also learnt to share one
induction variable among arrays of one element size, to move loop-invariant arithmetic
out of loops, to step a far pointer's `*p++` in place, and to compare an `unsigned char`
unsigned. The same runs after that:

| Run | Late frames | CPU a frame (average, most) | Time |
| --- | --- | --- | --- |
| The scripted game (`make test`) | 11 (21 before) | 8 ms, 466 ms (12, 616 before) | |
| `thevoids.drf` at the game's pace | 95 (425 before) | 7 ms, 133 ms (17, 166 before) | 3,358 s (3,365 before; 3,325 at exactly 80 ms) |
| `thevoids.drf` at full speed (`/S:0`) | | | 948.5 s (1,236.7 before) |

Still not done: a near-memory cache of the sprites' addresses (the table is in far
memory: every sprite drawn reads it with long addressing and builds a 32-bit address in
C; `hzd_sprite` is about 1 % now).

At full speed (`/S:0`, `tests/drf.sh`) a game frame takes 20-31 ms on average with the
level drawing and the copying to the screen after every vertical blank (30-45 ms before
the faster blits): about three times the original's speed.

## The board's report (round 2): held keys, choppy sound, the scrolling

The owner played the port on the board: it worked, with sound and joystick, but (1) a
held key stopped acting after a short time, (2) the effects were choppy while collecting
emeralds, (3) the scrolling went in jumps.

**1. Held keys: the firmware released them after 1 s.** The whole path, read: the CH9350
(the owner's adapter) sends a keyboard report `57 AB 88 ..` only when the keys change, and
between them status packets `57 AB 82 ..` about 30 times a second (measured in the bring-up,
`Docs/03-bringup1-log.md`); the Pico/TinyUSB bridge forwards the keyboard's reports, which
a USB keyboard also sends only on a change (its idle rate is 0). The I/O processor's
firmware (`uart_keyboard_poll`, `core/firmware/firmware.c`) parses the reports into the keys
held and sends Horizon a press / release for each change; but it also had a "safety
timeout": **no keyboard report for 1 s, every key cleared** (a release to Horizon). A key
held longer than a second, with no other key changing, went up by itself; Horizon's key
repeat (from 0.4 s, every 50 ms, kernel `input.s`) stopped with it, and hgame's state, the
game, everything above was right to take it as released. The joystick has no such path.
The emulator's keys never went through that code (`emu/mailbox.c` models the event
queue, not the timeout), so no test could show it.
- **Fixed** in the firmware: the timeout is gone (a lost report is corrected by the next
  one, which carries the whole state). Both adapters' forms are untouched. It needs a
  firmware build (`make -C core/firmware`), a bitstream and a flash: not done here (no
  board).
- **The emulator reproduces the old board**: `emu816 --kbd-release MS` / `run816.py
  --kbd-release MS` releases the held keys MS ms after the last key change, as the old
  firmware did. `tests/hold.script` (left held 3 s in level 1's bottom tunnel): without it
  the digger goes all the way and eats the two emeralds there (50 points); with
  `--kbd-release 1000` it stops after a third of the way (0 points).
- **On the board**: `tools/keyhold.c` (`hcc -o KEYHOLD.PRG tools/keyhold.c`) lists every key
  event with its time. Hold a letter 3 s: with the old firmware "down", "rep" every 50 ms
  from 0.4 s, then "up" about 1,000 ms after the "down" while the key is still held (the
  emulator with `--kbd-release 1000`: down 2087, reps to 3067, up 3117); with the new one
  the reps go on until the key is let go.

**2. Choppy sound: the speaker's steps went by the vertical blanks.** The PC's sound comes
from a 72.8 Hz timer interrupt (`soundint`, every 13.7 ms). The port ran it from the frame
loop's waits only, by the frame counter: (a) the steps were taken at 60 Hz, so one in five
vertical blanks ran two of them back to back and the first was heard for no time at all;
(b) none ran while the game drew its frame (up to 100 ms), and then several at once. An
emerald's note lasts two steps of eight: it was cut or lost. A Horizon program runs no code
in interrupts, the uptime counts in 10 ms steps and the frame counter in 16.7 ms; but the
music timer (`sample_timer`, the one MUSICD uses) sends a port a message every period with
a count that follows the microsecond clock. So (`horizon/hz_timer.c`): a clock from that
count (a period of 3,434 us, a quarter of a sound step: the steps fall exactly on it);
while waiting the game sleeps until the next period (or the coming vertical blank when
nothing is due before it); while working, the drawing calls look at the clock when, by the
work done (a cost per unit learnt as it goes), the next step or blank should have come.
Measured with the new `emu816 --log-sound-us` and `tests/sndtime.py` in a busy scene
(`tests/emer.script`: up through five emeralds with nobbins about; 8 s):

| | effects (voice 0) | music (voice 1) |
| --- | --- | --- |
| before: off the 13.7 ms grid, average / 95 % / most | 3.0 / 12.4 / 12.4 ms | 4.9 / 12.7 / 12.7 ms |
| before: steps less than 6 ms after the one before (cut short) | 4 of 69 | 45 of 202 |
| after | 1.8 / 4.6 / 6.9 ms | 2.2 / 6.0 / 12.7 ms |
| after: cut short | 0 of 81 | 7 of 220 |

The remaining 1-2 ms is the kernel's wake-up of a task that is not at priority 0. A step
no longer waits for the game's drawing. Without Lau (REV $09 and older: no music timer) it
goes by the frame counter as before. "A list of steps the system plays on time" would do
better still and cost the game nothing: suggested for hgame / MUSICD below.

**3. Scrolling in jumps: the view moved only while the game waited.** It moved toward the
digger by up to 3 rows a vertical blank, but only in the frame loop's waits; while the game
drew its frame the view stood. Now the view takes one step at every vertical blank, also in
the middle of the game's work (the vertical blank's work above: hgame's frame, which sends
the scroll registers for the next blank; `hg_split` costs nothing more), a quarter of the
way and 1-4 rows: the digger's 6 rows a frame become steps of 1-2 rows at 60 Hz. In the
scripted game the view was off its target at 114 blanks and moved at all 114 (before: only
at the blanks in waits). In 4.5 s of digging upwards (`tests/emer.script`) the scroll
registers were written 32 times (steps of about one row) against 14 before (two to three
rows). The changed rectangles still go to the screen only between the game's frames, just
after a vertical blank (now right at it: the wait sleeps until the blank), so a half-drawn
frame is never shown; the scroll registers change only at a blank.

**The frame beat and the input.** A frame now begins within the clock's 3.4 ms of its
80 ms beat: 1.6 ms off on average, at most 32 ms in a frame that came late (scripted
game); before, frames began at vertical blanks, 83.3 ms apart four times and 66.7 ms once
(3.3 and 13.3 ms off, 5.3 ms on average). The picture still changes at vertical blanks
(5, 5, 5, 5, 4 apart: 12.5 a second on a 60 Hz screen). The keys are read at every
vertical blank; the game reads its direction at the start of its frame (upstream does), so
a key reaches the frame that uses it in 40 ms on average and the screen 65 ms on average,
116 ms at most (`tests/keys.script`: 40 taps at uneven times): within one game frame and its
drawing. The late frames of the scripted game (8 of 811) are the title being drawn, the
level's start (its field drawn, which upstream paces itself), the game over and the
initials: none in play. In `thevoids.drf` at the game's pace: 298 late frames of 41,561
(0.7 %; 97 before: the looks at the clock and the vertical blanks' work in the middle of a frame add to the busiest frames), the whole game
3,365 s against 3,358 s before and 3,325 s at exactly 80 ms a frame.

## Suggestions for the porting guide (sdk/docs/c/porting.md)

1. **Start with the recorded-game or replay test if the game has one.** A deterministic
   replay compared with the PC's result is the best test a port can have; it found
   nothing here, which is itself the result: say "build upstream on a PC first and keep
   its outputs".
2. **The main bank is the real limit of a large port**, not the code: a section "What
   fills the main bank" with typical sizes (C library with printf/scanf and floating point
   30 KB; hgame 16 KB with its bss) and the cures in order (big arrays → far memory with
   `__far`; DOS's `huge`/`far` keywords map to `__far` naturally; avoid `sscanf` in a
   program with any `double`).
3. **`fopen` needs 1 KB of heap per open file**; with `--code large` the heap is what
   `--heap` keeps.
4. **A 320 x 200 / 640 x 400 game**: `hg_screen_fb` + `hg_split`, with the choice
   spelled out (fixed score line, playfield follows the player) — and why not to squash:
   the original's pixels were already 1.2 times taller than wide on a 4:3 monitor.
5. **Drawing into the shown framebuffer by the CPU flickers** when the drawing takes
   milliseconds (here up to 15 ms a frame): draw into a buffer of your own and copy the
   changed rectangles after `hg_frame()` (the vertical blank). Worth a helper in hgame
   (`hg_dirty(x, y, w, h)` + a back buffer) — Digger's 60 lines would do.
6. **Format strings are where 16-bit `int` bites first**: build with `-Wall` and fix every
   `-Wformat`; cast to `(long)` and use `%ld`.
7. **The PC speaker**: `hg_note(v, 1193182 / divisor, vol)`; a speaker program's two timers
   map to the two 16-bit voices.
8. **`SDL_KEYDOWN`** → `hg_key_next()`; SDL scancodes are HID usages: key tables port as
   they are.
9. **Sound that must keep time while the game draws** (a PC timer interrupt, a tracker):
   the music timer (`hz_sample_timer`) is the only fine clock a program has; poll it from
   the drawing loop (Digger's `horizon/hz_timer.c`). Better, for hgame: a call that hands a
   list of (time, register, value) steps to a priority-0 player (MUSICD could do it) so that
   no game needs to poll.

