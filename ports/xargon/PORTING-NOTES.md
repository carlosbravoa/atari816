# Porting notes: Xargon on the Atari816

The C SDK's second acceptance test after Digger: a 16-bit DOS game (Turbo C, large
model), 256-colour VGA mode X with two pages and scrolling, many sprites, Sound Blaster
digital effects and FM music, data files, and its assembly parts never released. This
file lists every change to the game's code and why, every SDK problem met and what became
of it, the time each kind of work took, and suggestions for `sdk/docs/c/porting.md`.

Upstream: the official source release of 4 August 2008 (`Xargon_Source_Code.zip`,
classicdosgames.com; the same files as the `dos-games/vanilla-xargon` mirror on GitHub):
`SOURCE/*.C` and `INCLUDE/*.H`, here in `src/` with their names in lower case and their
CRLF line ends. Not released: `GRASM.OBJ`, `GRL.OBJ` (the mode X drawing), `KEYINTR.OBJ`,
`MUSINTR.OBJ`, `PIXWRITE.OBJ`, `UNCRUNCH.OBJ`, `COPYFILE.OBJ` (assembly), `TCWORXL.LIB`
(Mystic Software's WORX Sound Blaster library). The game's data: the freeware release of
the registered game (`Xargon_Commercial.zip`, all three episodes; `tools/getdata.sh`).

## The numbers

| | |
| --- | --- |
| Upstream C ported | 11 files and 14 headers, 8,350 lines (`xargon.c`, `x_obj*.c`, `x_objman.c`, `x_player.c`, `x_info.c`, `x_vol1-3.c`, `windows.c`, `gamectrl.c`, `graphics.c`); `_xargon.c`, `x_editor.c`, `routines.c` (the level editor's build, dead code) not built |
| Upstream files replaced | `config.c` (the DOS set-up dialogs), `keyboard.c` (int 9, BIOS), `music.c` (WORX, PC speaker, timer), `shapeman.c` (shapes in near memory): by `horizon/hz_cfg.c`, `hz_kbd.c`, `hz_snd.c`, `hz_shm.c` with the same interface |
| Game lines changed | `upstream.patch`: 82 `#include` lines (absolute DOS paths `"\develop\xargon\include\x.h"` to `"x.h"`) and 79 other lines in 7 files, all `#if defined(_HORIZON)` |
| New platform layer | `horizon/`: 9 C files, 2 headers, 1 assembly file, 5 DOS headers: about 2,300 lines; tools and tests 830 lines |
| Build | `hcc --code large`: `XARGON1.PRG` 190,746 bytes (code 147 KB in 3 other banks; the main bank 52,736 bytes without its movable code: bss 34,617, constants 8,947; heap 7 KB, software stack 4 KB; the board, 16 KB, a `__far` object in a bank of its own) |
| Data | `XSHAPES.XR1` 1,001,288 bytes (1,976 shapes in 1,923 atlas rows), `XSOUND.XR1` 174,764, 12 songs 2.5-70 KB, the boards and texts as they are: 2.0 MB for the three episodes |
| Memory at run time | 36 banks (2.3 MB): framebuffer 7, atlas 16, its directory 1, glyph cache 1, effects 3, a song 2, hgame's screen 1, code 4, the board 1; 38 of 92 banks still free |
| Speed | 18.2 game frames a second as the original on the map and in level 1; 17.3 on average (95 %) over the demo's first 5,000 frames, its busiest scenes (see "Speed") |
| Determinism | the recorded demo plays exactly as recorded (to its end at frame 5,077: score 15,050, health 5, 14 emeralds) and the same on a machine 30 ms a frame slower |
| Time | about 11 hours in all (below) |

## Changes to the game's code, by kind

**Include paths (82 lines).** `#include "\develop\xargon\include\gr.h"` in every file:
Borland's IDE took absolute DOS paths. Now `"gr.h"` (`-I src`).

**The board file's object records (`xargon.h`, `xargon.c`: 9 lines).** The boards (and
the saved games) are `bd[128][64]`, then the objects as Turbo C's large model laid
`objtype` out: 31 bytes, its `char *inside` a 4-byte far pointer. Here a pointer is 2
bytes: `objtype` gets `int inside_hi;` after it (the same 31 bytes; cc816 does not pad),
and `loadboard` treats a pointer whose segment half is not 0 as not NULL (a far pointer
with offset 0 is not NULL), as upstream's test of the 4 bytes did. Nothing else of the
game reads or writes the raw records.

**The board in far memory (`xargon.h`, `xargon.c`: 14 lines).** `int bd[128][64]` is
16 KB; with the objects (8 KB), the tile table (5 KB), hgame and the C library the main
bank had 1.8 KB too little. `bd` is `int far bd[...]` (`far` is `__far`: a bank of its own
in the large model); `loadboard` / `saveboard` read and write it with
`hz_readfar` / `hz_writefar` (`read` and `write` take near buffers). cc816 then reached it
through 32-bit addresses at every access, which cost most of the drawing loop: fixed in
the compiler (SDK problem 7).

**The tile names (`x_info.c`: 9 lines).** `init_info` mallocs the 900 tile names, which
only the level editor shows: 8.5 KB, the whole heap; every `malloc` after it (the boards'
texts) failed, and the intro's text objects were drawn from address 0. The names are
read past, not kept.

**The heap (`x_info.c`, `gamectrl.c`, `xargon.c`: 34 lines; `horizon/hz_heap.h`).** See
"The heap" below: `init_info` closes the tile file it never closed (its 512-byte
read-ahead stayed in the heap for good: INSTRUCTIONS on the title then did nothing),
`recordmac` (the level editor's) records nothing, `loadboard` takes the room for the
board's texts with the board's file closed and prints the heap.

**`graphics.c` (6 lines).** Upstream's `drawshape` is left out (`#if !defined(_HORIZON)`):
the platform's (hz_vga.c) does the same with the blitter. `getportnum()` returns the CRTC's
port (0x3D4) instead of reading it from the BIOS's data at 0040:0063.

**`gr.h` (5 lines).** `shm_tbladdr[]` are far pointers (the shapes are in far memory).

**What was not changed.** Everything else runs as upstream wrote it: its 16-bit `int`
code was written for a 16-bit compiler (Turbo C), `char` is signed as Turbo C's
(`-fsigned-char`), its `rand` sequence is Turbo C's (`horizon/hz_dos.c`: the demo depends on
it), its frame loop, its page flipping and palette code (`graphics.c`: fades, palette
cycling), its timing (BIOS ticks), its file I/O (`open`, `read`, `lseek`), its text
windows. The DOS screens before and after the game (`cputs` text, TheDraw's crunched
screen) go to the console or nowhere.

## The platform layer (horizon/)

The idea: keep upstream's hardware-level calls and make each one a small function of the
platform, instead of changing the game: the VGA's DAC (`outportb(0x3C8/0x3C9)`) fills a
shadow palette sent once a frame; the VGA's input status (`inportb(0x3DA)`) tells the
vertical retrace from the frame counter (the first read after a blank sees it, a read
in a loop waits for the next blank); the CRTC's start address (`outport(0x3D4)`) is the
page shown; the BIOS tick at 0040:006C (`*myclock`, read in busy loops) is a macro over a
function counting the vertical blanks at 18.2065 / 60.03 (and waiting for the next blank
on the third read within one); the game port (`inportb(0x201)`) is emulated from the
joysticks (the one-shots' counts for left / centre / right, calibrated in `hz_cfg.c`). So
`graphics.c`, `gamectrl.c` and `windows.c` run unchanged.

- **Video (`hz_vga.c`, `hz_blit.s`, `hz_shm.c`).** One framebuffer of 512-byte rows holds
  both pages (440 rows each): 400 rows of playfield, a ring horizontally (Marga's
  horizontal wrap), and the 40 rows of the status bar. Upstream's `scrollvp` of the whole
  playfield (a 50 KB copy on the VGA, each frame) moves the page's origin instead; when the
  origin nears the page's end the 160 rows shown move back to the middle (one blitter
  move, every 120 rows of vertical scrolling). Page flips are the scroll registers' choice
  of rows. The shapes are in an atlas of 512-byte rows in far memory (tools/mkdata.py
  places each table's shapes on its own rows), registered as two sheets: a tile or a sprite
  is one `sheet_draw` record (a copy for the tiles drawn opaque, a keyed copy with 0
  transparent for sprites), queued 64 at a time; Ali draws them while the game runs on.
  `drawshape`'s common case (wholly inside the playfield's rows, not across the wrap) is
  65816 assembly (`hz_blit.s`), the rest C. The fonts (2-bit shapes in colours that
  `fontcolor` chooses) are made by the CPU into a cache sheet of 512 glyphs in their
  colours, then drawn by the blitter too. A flip waits for the blitter, then the game goes
  on at once: what it draws next waits for the flip's blank only if it is sent before it.
- **Shapes (`hz_shm.c`).** Upstream's `shm_want[]` / `shm_do`: a table is read from
  `XSHAPES.XRn` into its rows of the atlas when first wanted, and stays (upstream freed
  them to fit 640 KB). The palette shape sets the palette as `xlate_table` does.
- **Keyboard (`hz_kbd.c`).** The BIOS's queue (`k_pressed`, `k_read`: ASCII, or 128 +
  the PC scan code for keys without one, from a table of HID usages) from `hg_key_next`,
  with the key repeat; `keydown[0][scan]` for the arrows upstream polls; `k_status` from
  the modifier keys.
- **Sound (`hz_snd.c`).** Upstream's `snd_play` priorities, one effect at a time, on Lau
  (`hg_play`, the samples in far memory: `hg_sound_from` takes far pointers now, SDK
  problem 11); the music by `hg_opl_play`; the texts read from `AUDIO.XRn` when shown.
- **Timing (`hz_frame.c`).** Above; plus `hg_poll` once a vertical blank when the game's
  frames run late (no waiting, so no `hg_frame`): the keys and the music go on (SDK
  problem 12). Statistics (`/STATS`): frames, their spacing, the CPU's share, late frames.
- **Configuration (`hz_cfg.c`).** The hardware answers upstream's set-up questions: Lau
  for the effects, the OPL2 for the music, the joystick calibrated for the emulated port.

## The heap

The main bank's heap is what is left of the bank, at least 7,168 bytes (`--heap 7168`):
7,817 bytes in `XARGON1.PRG` now (7,618 and 7,665 in episodes 2 and 3), of which 7,500
are free, 7,496 in one piece, when a board is loaded (317 are taken before `main`, 6 by
`gr_init`). Upstream was written for DOS's 640 KB and checks almost none of its
`malloc`s; a NULL here would be a text drawn from, or written to, the main bank's start.
So `horizon/hz_heap.h` (in every file: the Makefile's `-include`, as ports/prince's)
makes `malloc`, `calloc` and `realloc` stop the game with `xargon: out of memory: N bytes
wanted, F free, L in one piece` (`hz_dos.c`) instead of returning NULL; none returns NULL
silently now (checked once with a `malloc(8000)` put in `main`: the line, then the exit).
Every allocation of the built game:

| Where | What | Size | Can it exceed the heap? |
| --- | --- | --- | --- |
| `loadboard` (`xargon.c`) | the board's texts, `objs[].inside`, freed at the next board (`zapobjs`) or when the object goes (`purgeobjs`) | 1-50 bytes each; a board's all from 156 (the map) to 2,318 (the title's, 83 texts) and 3,798 (`STORY.XR1`) | no: the biggest leaves 3,702 free. None leaks: the heap is the same at every board's start (`make test`) |
| `text_get` (`hz_snd.c`) | a text window's text (`dotextmsg`, `pageview`), freed when it closes | up to 4,313 bytes (the help: F1 in a level, INSTRUCTIONS on the title) | no, but it is the tightest: on the title's board (the most texts of the boards with windows) 5,178 bytes are left in one piece for the help's 4,318 (860 to spare; at the smallest heap the link allows, 7,168, about 200). `tests/heapcheck.py` checks every board of the three episodes |
| `playmac` (`gamectrl.c`) | a recorded macro, the whole file: the demo (`DEMO_MAC.XR0`, 2,360 bytes) or the end of episode 1 (`END_MAC.XR1`, 335), freed at its end | the file's length | not with these files (with the demo's held, 5,136 bytes stay free at its boards' starts) |
| `recordmac` (`gamectrl.c`) | the level editor's macro recording | 8,000 bytes | always: more than the heap (and its end test, at 30,000 bytes, wrote past them on DOS too). Only `routines.c` and `_xargon.c` (not built) call it: under `_HORIZON` it records nothing |
| `gr_init` (`graphics.c`) | `LOST=malloc(1)`, never used or freed | 6 bytes | no |
| `init_info` (`x_info.c`) | the 900 tile names (the level editor's) | 8.5 KB | not done here (the names are read past) |
| the C library's `open` (read only) | a 512-byte read-ahead while the file is open (NULL: reads go to the card, no error) | 516 | no. But `init_info` never closed the tile file, so 516 bytes stayed in use for good: INSTRUCTIONS on the title did nothing (the help's `malloc` gave NULL; seen in the emulator with the program before this change). Closed now. And a file's read-ahead taken before a block that outlives the file leaves a hole above it: `loadboard` opened the board, took its texts under the read-ahead, closed it, and 516 bytes over the texts were lost to the help. Now it reads the texts' lengths, closes the file, takes their room, opens it again; `text_get` reads the text's place and length, closes, takes the room, opens again |
| `fopen` (`hzt_shots`, the tests' list) | 1 KB of buffer while open | 1 KB | no (NULL: unbuffered) |

The shapes, the sounds, the songs and the board itself are in far memory (`hg_banks`,
checked: "not enough memory for the pictures"); `strdup` is only in a commented-out
function (`addtext`). The texts' places and lengths (upstream's `textposn[]`,
`textlen[]`: 240 bytes of bss) are read from `AUDIO.XRn` when a text is shown: the main
bank had no room for the heap's checks otherwise (`XARGON2.PRG` did not link).

`loadboard` prints the heap at each board's start and with its texts (`xargon: heap
before intro.xr1: 7500 free, 7496 in one piece`), `text_get` with its text (`xargon: heap
with the help: 864 free, 860 in one piece`). `make test` checks that every board start
shows the same (the title, the map, level 1, level 1 again after a death, the title, the
map loaded from a save; the demo's, the title's as the game's), opens the help on the
title twice (`tests/help.script`), runs `tests/heapcheck.py`, and fails on any "out of
memory".

## SDK problems met

| # | Problem | Kind | What was done | Time |
| --- | --- | --- | --- | --- |
| 1 | **No POSIX file descriptors** (`open`, `read`, `write`, `lseek`, `close`, `creat`, `fcntl.h`, `unistd.h`): DOS and Unix code uses them (Xargon: every file) | library gap | added `cc816/include/fcntl.h`, `unistd.h`, `lib/cc816/posixio.c`; 20 checks in `tests/libc` (`t_posix`) | 30 min |
| 2 | **Small reads were slow**: each `read` a call to the card (about 1 ms). `init_info` reads 3,600 records of 1-2 bytes: 3 s at the title | library | a read-only descriptor reads ahead 512 bytes (`read` still returns all bytes asked for unless the file ends); tested by `t_posix` (300 reads of 1 byte, seeks among them) | 20 min |
| 3 | **`#define scan_f1= 0x3B` refused** ("Bad macro definition"): no space between the name and `=`. C99 asks for one; gcc warns and takes the rest of the line | compiler (preprocessor) | as gcc: a warning, the macro defined (`vendor/pcpp`, `driver.py`); `regress/r032_define_no_space.c`, `diag/define_no_space.c` | 15 min |
| 4 | **Internal compiler error** (UnicodeDecodeError) on a header with code page 437 bytes in a string (`cfg_win.h`): included files were read as UTF-8 | compiler bug | every file read byte for byte; `regress/r033_latin1_source.c` | 10 min |
| 5 | **"variable-length arrays" for an undeclared name** in an array's size (a header used without the one that defines it) | diagnostic | now "'numobjkinds' undeclared"; `diag/array_size_undeclared.c` | 10 min |
| 6 | **`x * 31` and signed `x / 16` were calls** (`__mul16`, `__sdiv16`): 13 % of the game's time (31-byte objects, positions divided by 16 everywhere) | compiler speed | multiplies by constants with up to four signed digits (non-adjacent form) and signed divides by powers of two inline; `regress/r034_mul_div_const.c` (every value against the helpers) | 30 min |
| 7 | **A `__far` array of arrays was indexed through 32-bit address arithmetic** at every access (`bd[x][y]`: base + sign-extended index products) | compiler speed | the indexes of an array of arrays add up in 16 bits; in a `__far` object (one bank) that index goes in Y (`[base],y`); an unsigned index through a far pointer too; `regress/r035_far_index.c` | 45 min |
| 8 | **The main bank was full**: bss 34 KB (the game's objects and tables), hgame's record queues 7 KB (unused by this game: it draws with its own sheet records) | SDK limit | worked around in the port (the board far, the names not kept, small buffers); hgame's 7 KB of queues for every full-screen game is still open (as after Digger) | 30 min |
| 9 | **`hz_read`'s result is an `int`**: a read of 32 KB returns -32,768, taken for an error (the effects did not load) | API wart | worked around (16 KB pieces); documented in porting.md ("size_t" row). Open: the stub could return `unsigned` | 20 min |
| 10 | **No way to play AdLib music from a game**: the OPL2 was reachable only through the music engine's MIDI player (General MIDI instruments) | hgame gap | added `hg_has_opl`, `hg_opl_write`, `hg_opl_reset`, `hg_opl_play` (IMF register streams from far memory, across banks), `hg_opl_stop`, `hg_opl_playing`; tested in `gt_sound` (the stream's timing in frames, looping, stopping); games.md | 45 min |
| 11 | **`hg_sound_from` took a near pointer**: samples loaded into far memory (the normal case for a game's sounds) could not be given | hgame gap | `const void __far *data` (near arrays still convert); tested in `gt_sound` (a sample made in a bank of `hz_far_alloc`, played) | 10 min |
| 12 | **No events without a frame**: a game whose frames run late never waits, so never calls `hg_frame`: no keys, no music | hgame gap | added `hg_poll()` (events, POKEY envelopes, the OPL2 stream, no wait); the OPL2 stream timed by the frame counter; tested in `gt_sound` (a stream played by `hg_poll` and `vsync` alone); games.md | 20 min |
| 13 | **`run816.py` passes no emulator options** (`--card-kbps` for the board's card speed, `--log-opl`) | tool gap | not changed (another job was changing run816.py): the test's slower run uses the game's own `/BUSY:ms`; OPL writes were logged once with a private copy | - |
| 14 | **The emulator's OPL2 at three times a Lau voice** clips music written for a Sound Blaster (1-2 % of the samples) | mix (design) | the converter makes the songs 13.5 dB quieter (`OPL_ATT`); games.md, "AdLib music" | 20 min |

Nothing else failed in the compiler: 8,350 lines of 1993 Turbo C (K&R-ish style, function
pointer tables, `#define` tables included twice with different `defobj` macros, signed
`char` arithmetic, `long` scores, `goto`s across loops in `pageview`) compiled at the
first try once problems 3 and 4 were fixed, and the recorded demo replays exactly.

## Testing

`make test` (`tests/check.sh`): the scripted game (title, menus, a save, the map with its
journal, level 1 with a jump, a shot and a death, the game's menu, quit, high scores, a
load) with 13 pictures compared by checksum, the save files on the card, the loaded
game's position, Lau's writes and the recorded sound's level and clipping, the heap at
every board's start (no leak) and the room on every board for the help (see "The heap");
the help opened twice on the title; then the
recorded demo twice (the second time 30 ms a frame slower) to its frame 1,500, which
must match `tests/demo.ref`, with 7 pictures (the title, the menu, five of the demo's
frames) that must be the same in both runs. The demo is the strongest check: 1,500
frames of the game logic (objects, collisions, `random()`), and its whole run (5,077
frames) ends with what the recording earned (no damage taken, 14 emeralds), the same on
the slower machine.

**The pictures' test.** At first the scripted game took 14 screenshots at fixed times.
Any change of the program's timing (a compiler improvement, the code's place in its
banks) moved the game by a frame or more, and 7 of them failed while the frame-exact
demo passed. Now the program decides when a picture is taken (`/SHOTS:FILE`,
`horizon/hz_frame.c`): `pN` is a screen that waits for keys (the title, a menu, a
dialog: upstream's `checkctrl0` loops, one key poll a BIOS tick, the menu's cursor and the
palette's cycling moved by each) at its Nth key poll with no page flip and no key read
since; `fN` is the play loop's frame N (upstream's `gamecount`) at its page flip, when
the flip before was of frame N - 1. There it finishes the drawing, shows it, prints
`xargon: shot K at poll N` / `at frame N` and holds it for six vertical blanks; the
emulator takes the picture two blanks after the line (`--shot-on`), and the scripts
`wait` for each line before their next key. Level play is pictured only from the demo
(the same inputs each frame); the keyboard game's pictures are of menus, dialogs and the
map just after it starts (a new game, a loaded one). Two of them (the game's menu and the
high scores over level 1) are taken but not compared: the level's frame behind them is
the keys' timing. Three windows over the map are compared as their rectangle only
(`crop:` in `tests/play.md5`): the map's palette (its pods) is cycled by its frames, and
the frame the key that opened the window came at is again the keys' timing. Checked: the
same pictures, three runs each, from the program built at -O2, at -O1 and at -O0, linked
with `--main-room 0`, and run with `/BUSY:10` (the keyboard game and the first demo run)
as well as the demo's `/BUSY:30`. (At -O0 the slower demo run does not reach frame 1,500
within its 160 s; its pictures, which come before, are the same.)

## How long each kind of thing took

(Wall-clock time of the agent, with emulator runs on a fast PC.)

| | |
| --- | --- |
| Finding the source, the data and their licences | 25 min |
| Reading the game, the DOS layer and the SDL port's notes; the data formats | 45 min |
| The data converter (shapes, sounds, CMF to IMF) | 40 min |
| The SDK additions: POSIX I/O, `hg_opl_*`, `hg_sound_from`, `hg_poll`, their tests | 2 h |
| The platform layer, first version (CPU drawing in a ring buffer) to the title and the menu | 1 h 30 |
| Making it fit the main bank, the heap | 30 min |
| Speed: profiling, the compiler's constant multiplies and divides and far indexing, the blitter version of the drawing, the glyph cache, `drawshape` in assembly, flips without waiting | 3 h |
| Finding the way through the map for the tests, the scripted game, save/load, the demo checks | 1 h 30 |
| Sound levels, these notes, the SDK's documents, the suites | 1 h |

## Speed

Measured with `/STATS` in the emulator (which models the board's timing within a few
per cent). A game frame is one BIOS tick, 3.30 vertical blanks; "busy" is the time from
the tick to the page flip.

| Scene | Frames apart (blanks) | Busy (blanks) |
| --- | --- | --- |
| The map | 3.30-3.31 | 1.0-1.1 |
| Level 1 (the test's walk, jumps, a death; load spikes included) | 3.45-3.50 | 1.6-1.7 |
| The recorded demo, its first 5,000 frames (the intro board: 40-60 objects on the screen, rooms of text objects) | 3.46 (worst seconds 3.5) | 2.0-2.3 |

The path that got there, the demo's busy scenes (blanks between game frames):

| | Apart | Notes |
| --- | --- | --- |
| First version: CPU drawing into ring buffers, page flips by `fs_enter` | 8.2 | `__mul16` 8 %, `__sdiv16` 5 %, the copies 11 % |
| cc816: constant multiplies, signed divides by 2^n inline | 6.9 | |
| The opaque copies by MVN, `ldrawsh_vga`'s common case inline | 6.2 | |
| cc816: 16-bit indexes into `__far` arrays of arrays | 6.1 | `refresh` 18 % cheaper |
| The blitter: tiles and sprites as sheet records | 5.4 | |
| `drawshape`'s fast path in C without address-taken locals | 4.4 | |
| `drawshape`'s fast path in assembly | 4.3 | |
| The glyph cache (fonts by the blitter), its fast path | 3.85 | |
| Flips without waiting for their blank; `hg_poll` | 3.46 | |

What is left: upstream's object loop (`upd_objs`, its collision test of every pair of
objects near the screen), `refresh`'s walk over the visible cells and `upd_bkgnd`
(about 40 % of the CPU in the demo), cc816's code for them; the palette upload every frame
(`upd_colors` cycles 56 entries: 40,000 cycles in `pal_set`). Level loading: a board (21
KB), its song (up to 70 KB) and the shape tables it needs the first time (up to 220 KB):
about 30-40 ms in the emulator with its instant card, about 0.6-1.8 s at the board's card
speed (170 KB/s; not measured on the board).

## Suggestions for the porting guide (done in sdk/docs/c/porting.md)

1. A Turbo C / Borland section: compat headers, `-include` for Borland's names, Turbo C's
   `rand` for demos, absolute include paths, CP437 and CRLF sources.
2. "Code that reads hardware": emulate the few ports and the BIOS tick in the platform
   layer instead of changing the game.
3. "Let the blitter draw": every CPU write waits for the SDRAM; tiles and sprites as sheet
   records; a cache sheet for what needs colours chosen at run time.
4. Page flipping with the scroll registers, a ring for the scrolling playfield.
5. `hg_poll` for games whose frames run late.
6. `hz_read`'s `int` result (32 KB reads).
7. (Not yet in porting.md.) A malloc that stops with a message (`horizon/hz_heap.h`, as
   ports/prince's), the heap printed at each level's start and compared in the tests, and
   every file opened for reading closed: each holds 512 bytes of read-ahead from the heap.
