# Porting notes: Prince of Persia on the Atari816

The C SDK's third game port, after Digger and Xargon: SDLPoP (the DOS game's disassembly
in C, SDL2), about 19,700 lines of game code, large code model, 2 MB of data.

Upstream: SDLPoP at commit f7be2e9 (7 November 2026, "1.24 RC"), GPL-3. Its game files are in
`src/` (seg000-seg008, seqtbl, replay, options, data, the headers) with every change in
`#if defined(_HORIZON)` (`upstream.patch`: 11 files, about 327 lines added, 28 removed). Not
built: `seg009.c` (the SDL layer: replaced by `horizon/`), `main.c`, `menu.c` (the pause
menu), `lighting.c`, `screenshot.c`, `midi.c` and `opl3.c` (the music: converted at build
time, played by the real OPL2), `stb_vorbis.c` (OGG music).

## Numbers

- Upstream C built: 13 files, about 19,700 lines with their headers.
- New platform layer: `horizon/`: 7 C files (`hz_seg009.c` is the part of upstream's
  seg009.c that does not touch SDL, taken over unchanged: text, dialogs, rectangles, random
  numbers), 3 headers (an SDL2 shim, `sys/stat.h`).
- Tools and tests: `tools/` (getdata.sh, mkdata.py, midi2imf.c, mkicon.py), `host/` (the
  reference build), `tests/` (check.sh, mkref.sh, hostframes.sh, cmpframe.py, oplcheck.py,
  shots.py, scripts): about 4,600 lines with horizon/.
- Build: `hcc --code large`: PRINCE.PRG 196 KB (146 KB of code in 3 other banks; the main
  bank 48.3 KB without its movable code: bss 20.1 KB, constants 13.4 KB, data 5.8 KB, code
  that must stay 9.1 KB; heap 12.4 KB, software stack 4 KB; 13.5 KB of `__far` objects in a
  bank).
- Data: POP.GFX 1,470 KB (927 images and 500 mirrored copies in an atlas 2048 wide and 735
  rows, packed as a skyline, in parts of 256 rows), POP.MSK 132 KB (1-bit masks), POP.DAT
  61 KB (directory, palettes, levels, the other files' sizes), POP.SND 250 KB (24 digital
  effects, 26 songs as OPL2 streams, 4 PC-speaker sounds): 1,958,240 bytes.
- Loading: 4 files, one open each, 88 reads straight into far memory: 9.6 s in the
  emulator's card model of Horizon 0.30's tree (220 KB/s), 4.0 s at the board's 580 KB/s
  since its firmware's faster card clock; a loading screen with a bar from the first 0.1 s.
- Memory at run time: about 48 banks (3 MB): framebuffer 6 (512 x 768), atlas 27, masks 3,
  sounds 4, directory 1, replay moves and savestate 1, far tables 1, code 3, the main bank.
- Speed: 22-34 ms of work a game frame on average in level 1 and a fight (the game's frame
  is 83 ms: 12 a second; 10 a second in fights); see "Speed".
- Determinism: 4 replays recorded on the PC (2,478 ticks): every state and every picture
  taken equal to upstream's on the PC; every level's start (14 replays, `make test-long`):
  the level's 2,305 bytes, states and picture as the PC's; the shadow's XOR pixel for
  pixel.

## Verification against upstream

Upstream itself is built on the PC (`host/`, `make host`) with three small additions
(`host/ref.patch`, `host/refhook.c`): a hook after each drawn game frame that prints the
game's state (`ref: tick ... kid ... guard ... seed ... time ...`) and writes the screen as a
PNG at chosen replay ticks; an OPL log in the MIDI player; and scripted recording (the
kid's controls read from a text file, the replay saved: `POP_REF_INPUT`). SDL_image is not
needed: `host/sdl_image_shim.c` decodes the paletted PNGs (zlib).

The port prints the same state line (`horizon/hz_ref.c`, `every=N`) and holds the screen
still for a picture at the same ticks (`shots=`). `dump=T` prints every variable of the
savestate (upstream's own `quick_process` with a printing function) on both sides: the
first differing variable of a divergence, at the tick it diverges. These tools found every
fault below in minutes once they existed.

Replays: four recorded with scripted input on the PC (a helper agent wrote the scripts,
`tests/replays/*.txt`): level 1 to the sword (969 ticks), level 1 through ten rooms (1,207),
a loose floor (180), a won sword fight on level 2 (122). Recorded without sound (as
upstream's validate mode runs): played with sound, a replay's "end of the level-1 music"
can come before the music, and the kid stays crouched (upstream behaves so too); `nosound`
plays them at the game's speed.

A replay's savestate begins with the level structure (2,305 bytes: the level's map, its
links, its guards), the publisher's data: git holds each replay without it
(`tests/replays/*.p1x`, `tools/p1rstrip.py strip`), and `tests/replays.sh` rebuilds the
`.p1r` into `build/replays` from the user's `data/sdlpop/data/LEVELS` at every `make test`:
the resource as the game's `load_level` leaves it (`alter_mods_allrm`,
`reset_level_unused_fields`, ported in the tool), then the few bytes the run had changed
before its tick 0 (torch flames, a gate on its way down, a button's timer, guard places:
8 or 13 bytes, kept as their XOR with the loaded level), byte for byte the recorded file
(its MD5 is in the `.p1x` and is checked).

## Faults and fixes

Each fault with where it was, the fix, and the time it took:

1. cc816: `a[d + 1]` with a signed `d` read the next bank when `d` was -1. The front end
   takes the constant out of the index (`a + 1`, index `d`), and the 65816 adds an index
   register to an absolute address in 24 bits: X = $FFFF read `a + $10000`. PoP's
   `dir_front[Char.direction + 1]` (facing left): the tile in front of the kid came from
   garbage, how depending on where code and data lay (one link order passed, another
   failed at tick 5, `-O0` and `-O2` differed). Where: SDK compiler fault. Fix:
   `cc816/front.py`: a positive constant stays in a signed index;
   `tests/regress/r040_signed_index_offset.c` (killed by the old compiler, passes now in
   both models). 1 h 30.
2. cc816: no `-Wfar-pointer` for `&p->member` with `p` far (and `&far_array[i].member`):
   `&` gave a near pointer type to a 4-byte far address, so a near parameter took it
   silently. PoP's `x_to_xh_and_xl(obj_x, &entry->xh, &entry->xl)` (the object table,
   moved far) wrote into the main bank: every sprite facing right was drawn 170 pixels
   off. Where: SDK compiler diagnostic. Fix: `front.py`: `&` of an lvalue reached through a
   far pointer has a far pointer type (also correct when assigned to a `__far` pointer:
   before, it would have been taken as near and given the main bank);
   `tests/diag/w_far_member.c`. 40 min.
3. `calc_screen_x_coord`: `logical_x*320/280` overflows a 16-bit int (the kid drawn 45
   pixels off). Where: 16-bit int. Fix: `logical_x*8/7` (the same values, C's truncation
   too, no 32-bit divide). 15 min.
4. quickload's penalty: `720 * (rem_min - old)` overflows (60 minutes = 43,200). Where:
   16-bit int. Fix: `720L`. 5 min.
5. The savestate (and so every replay) has `torch_colors` (750 bytes) when
   `USE_COLORED_TORCHES` is on: turned off first, everything after it was read from the
   wrong place. Where: port. Fix: kept on (its blit is a plain keyed blit). 20 min.
6. Saves went to a garbage path: `get_writable_file_path` uses `HOME`; Horizon's `getenv`
   returns nothing and `save_path` stayed uninitialised. Where: upstream (a latent fault) +
   port. Fix: under `_HORIZON` the file's own name (the program's folder is the current
   one). 10 min.
7. Rooms black: a peel (save-under) of a sprite partly off the left edge had a negative
   source x; `sheet_draw` rejects the whole call for one bad record, so 31 good records (the
   room's copy to the screen) were lost with it. Where: port. Fix: the peel's source cut to
   the screen; rejected calls print their bad record (the first 8). 40 min.
8. The peels' area filled up: the start-up dialog's peel stays for good, so an allocator
   that resets when no peel is left never reset. Where: port. Fix: a stack of peels: freed
   ones pop. 15 min.
9. The upstream replays' option sections and `moves[345600]` (345 KB). Where: main bank.
   Fix: moves and the savestate in a bank of their own (61,440 ticks: 85 minutes), sections
   of 160 bytes (the biggest is 147). 20 min.
10. `midi2imf`'s first version had the instrument record's fields in the wrong order
    (feedback came out 0). Where: tool. Fix: SDLPoP's layout; now the stream's 1,258 writes
    of the title music equal upstream's own OPL writes (times within 1.3 ms). 15 min.
11. Level 1 started empty on the board (the kid in room 0, dead at once) when the title had
    run 40 s or more before the key: a key in `fade_out_2`/`fade_in_2` (the story's fades)
    or in the princess's scene jumps to `start_game` (longjmp), which never frees the
    fade's 1.5 KB buffer nor the scene's peels (upstream leaks them too:
    `clear_screen_and_sounds` sets `peels_count = 0`). The 12 KB heap then had no 2,310
    bytes in one piece; `load_from_opendats_alloc`'s `malloc` gave NULL and `load_level`
    silently left the level all zero (25 non-zero bytes of 2,305: exactly what the board
    showed). Depends on when the key comes, not on the build: in the emulator the tests'
    key came 2.5 s into the title. Where: port + upstream leaks. Fix: the level copied
    straight from POP.DAT's far copy (no heap); `start_game` frees an abandoned fade
    (`hzv_fade_abandoned`); `clear_screen_and_sounds` frees its peels;
    `horizon/hz_heap.h`: every `malloc`/`calloc`/`realloc` of the port stops the game with
    "prince: out of memory" instead of returning NULL; `list_replay_files` requested
    49,792 bytes (128 replays' records, NULL before, written through when a replays folder
    exists): grows by 4. Test 4b: a key after 15, 40, 60 s, level 1 in room 1 with the same
    heap. 2 h 30.
12. `make test`'s scripted-game pictures failed or passed with the layout: how many game
    ticks a held key covers depends on the CPU's time (emu816 models the cache by address),
    so the kid's run and the torches' random flames moved. The kid "missing" after the
    quickload is upstream's: he stops in the wall's column (the PC's build draws the same).
    Where: test. Fix: the quickload checked by a checksum of the whole savestate
    (`prince: quicksave state`, `quickload state`); after the first picture only the
    status line's rows are compared; `make test-layouts` (PAD=n: `tools/mkpad.py`). 1 h.
13. 35 s of black screen at the start on the board (the user's first play: 25 s and more):
    the data (2.1 MB) was read through a 512-byte buffer, 4,320 reads, each a card request
    of a few ms plus its bytes; nothing was on the screen until it was all in. The
    emulator's card model had no delay then, so the emulator never showed it. Where: port.
    Fix: one open per file, reads of up to 32,767 bytes straight into far memory (a read
    must not cross a bank: three a bank), the sizes of POP.MSK and POP.SND in POP.DAT (no
    STAT); the full screen and a loading screen with a bar first (hgame's font: the game's
    is in the data); the atlas packed as a skyline (735 rows, was 840: 210 KB less).
    35.1 s -> 9.6 s in the emulator's card model (220 KB/s), about 29 -> 4.0 s at the
    board's 580 KB/s; requests 4,250 reads -> 88. 1 h.
14. Shift+L quit the game (allowed on levels 1-3 in the original): the SDL shim's
    `SDL_AddTimer` was a macro giving 0, and upstream quits when the timer cannot be made.
    Where: port. Fix: a one-timer `SDL_AddTimer` run by the frame's input poll (upstream's
    only timer: Shift held again after 250 ms). Found by `make test-long`'s walk through the
    levels. 15 min.
15. Ctrl+G typed quickly did nothing (`make test`'s save, now with the board's card
    timing): hgame's key queue has presses only, and `hg_mods` is the modifiers at the last
    event read; Ctrl and G released together (as a keyboard adapter that sends both in one
    report does) came as a plain G. Where: port, SDK wish 5 (done). Fix: first: a modifier
    pressed earlier in the same batch of events counted; now hgame keeps each press's
    modifiers (`hg_key_mods`, set by `hg_key_next`) and `hz_events` reads them. 20 min.
16. The shadow's colours differed from the PC's (the user's note): the port xored the low
    4 bits of the palette indices (the outline in the kid's red and white); SDLPoP xors
    24-bit RGB (blue, green, yellow: colours of no palette). 114 pixels of the shadow
    standing differed. Where: port. Fix: each (screen colour, image colour) pair gets an
    entry of colour rgb ^ rgb: an existing one, else one of rows 4 and 15 (never used by the
    game), else the nearest; remembered until the palette changes. 0 pixels differ
    (`make test-long`: a replay moved next to level 6's shadow, `tests/patchp1r.py`). 1 h.
17. The music against the effects: measured (`sndtest`, run816 `--wav`, the board's mix)
    the songs were 4.5 dB louder than the effects (median rms -23.1 against -27.6 dBFS)
    even with their carriers 9 dB down; the effects cannot be louder (their samples are
    full scale at Lau's full volume). Where: data. Fix: carriers 13.5 dB down (`OPL_ATT`
    18): -28.2 against -27.6 dBFS, the loudest peak -9 dBFS; `make test` checks it
    (`tests/sndlevel.py`). 30 min.

Also: `get_joystick_state` used `atan2` and doubles (1.7 KB of floating point in the main
bank for an analog stick Horizon does not have): signs instead; the feather fall's tick
count (18.75 s as a double) and the timers' scaling in integers.

## Platform layer (horizon/)

- **Video (`hz_video.c`).** One 8-bit framebuffer of 512-byte rows: rows 0-199 the screen
  the game draws on (`onscreen_surface_`), 200-399 its offscreen buffer, 400-767 the peels.
  The DOS game's images are 16-colour sets each with its palette row on the VGA: the atlas
  keeps that (a pixel is row * 16 + colour, 0 transparent), so the 256-colour palette is
  the game's and every blit is a plain copy or keyed copy: one `sheet_draw` record (the
  atlas's parts and the framebuffer are kernel sheets), queued 32 at a time; fills are fill
  records; one-colour blits (the font, masks, blood, the palace walls' marks, the guard's
  health) are draw_list "expand" records of each image's 1-bit mask. Mirrored images
  (facing right) are copies made by mkdata.py. Only the shadow's XOR is the CPU's. The
  upside-down potion copies the offscreen rows in reverse, one record a row. Fades are the
  palette's (the DOS way); flashes set palette entry 0. An `SDL_Surface` is 8 bytes (its
  size, its POP.DAT record or framebuffer place): 650 images of the loaded sets fit the
  heap.
- **The view.** 172 rows of the room following the kid, the status line below a split;
  pictures from row 20 (`hzv_show`, every vertical blank).
- **Data (`hz_data.c`).** The four files read whole at the start, each opened once, in
  reads of up to 32,767 bytes straight into their banks, behind a loading screen (fault 13);
  POP.DAT's directory read once; upstream's open_dat chain (the
  last DAT opened searched first) over folder numbers; load_sprites_from_file makes an
  image set's pointers and surfaces in one allocation.
- **Sound (`hz_sound.c`).** As above; `check_sound_playing` counts a sound's known length in
  vertical blanks (the game pauses until sounds end: level ends, cut scenes), the same with the
  sound off or the chip missing.
- **Time and input (`hz_sys.c`).** SDLPoP's timers are 60 a second: the vertical blanks.
  Keys from hgame's events into upstream's `key_states` and `last_key_scancode`; the
  joystick (port 1) holds the arrows and Shift.

## Speed

Measured in the emulator (models the board within a few per cent) with `stats=100`: the
time from the end of one game frame's wait to the next (logic, building the draw tables,
sending the records, the kernel's share), the replays played at the game's speed:

- Level 1, ten rooms (l1run, 1,207 frames): 21.7-34.2 ms on average, 300 ms worst, 1 in
  100 late (the room changes).
- The same since the room changes were cut (below): 21.8-34.0 ms on average (26.0 in all),
  171 ms worst, 7 in 1,000 late.
- A sword fight, level 2 (frames of 100 ms): 33.2 ms on average, 216 ms worst, 1 in 120
  late (the room change).
- The 30 ms slower machine (/BUSY:30): no change of the game's states.

The game's frame is 83 ms (12 a second; 100 ms in fights), so a frame uses a quarter to
two fifths of it. The worst frames are room changes: SDLPoP's deliberate 100 ms of black
("dark transition", as the original) plus drawing the whole room (about 30 tiles in many
records each, the table building in C: 120-200 ms).

Room changes, cut (2026-11-23; `stats=N` prints each frame over 150 ms; a profile of one,
run816 `--prof` over its 0.3 s): the 100 ms of black now come after the room is
drawn into the offscreen buffer, before it is copied to the screen (the black lasts as
long; the drawing no longer comes after it: -100 ms); `prandom`'s modulo in 16 bits and
its multiply as one 16 x 16 -> 32 and one 16-bit (the same values; it is called a dozen
times a wall tile); the atlas part of a row by a shift (`/ hzd_part` was a division a
blit); `calc_screen_x_coord`'s `/ 7` by shifts and a correction (a division an image);
the record queues by pointer (an index into 14-byte records was a multiply); the key
release scan up to $E7, not 256. l1run's ten room changes: 218-298 ms -> 130-171 ms. What
is left is upstream's table building (`get_tile_to_draw`, `draw_back_fore`,
`add_backtable`: about 40 % of the drawing, compiled C with a multiply for every index
into a table of structures: SDK wish 6) and the kernel's `sheet_draw` (15 %). During play
the card is not touched: `--stats` counts the same requests for a run stopped at level 1's
first frame and one through the ten rooms, the title and the demo.

## SDK changes made (with tests)

- `sdk/c/cc816/cc816/front.py`: fault 1: a positive constant stays in a signed array
  index. Test: `sdk/c/cc816/tests/regress/r040_signed_index_offset.c`.
- `sdk/c/cc816/cc816/front.py`: fault 2: `&` through a far pointer is a far pointer
  (`far_lvalue`). Test: `sdk/c/cc816/tests/diag/w_far_member.c`.
- `sdk/tools/run816.py`: `--log-opl`, `--log-opl-us` passed to emu816 (Xargon's open tool
  gap 13). Test: used by this port's `make test` (tests/oplcheck.py).

## SDK wishes (not changed unless marked done)

Each wish with its case:

1. hcc's large-model trial link reports every function whose address is taken (`__T_`
   thunks) as "undefined" whenever one real name is missing: 34 names listed for one
   missing `load_sound_names`. Case: `sdk/c/tools/hzlarge.py` `link()`: when `und` has
   names not starting `__T_`, report only those.
2. (done: the record queues, 4.5 KB, are in far memory since; games.md, "Limits and known
   faults") hgame takes 7.1 KB of the main bank for its draw queues even when a game draws
   with its own records (both Xargon and this port). Case: `hg_draw.c`: `hg__dq`, `hg__sq`
   (used at fixed addresses by `hg_fast.s`), the arena.
3. `int`-typed `switch` on key codes with bit 15 set warns `-Woverflow` for every case
   (SDLPoP's `WITH_SHIFT` = 0x8000): correct code, 16 lines of noise. Case: a `case` whose
   value fits `unsigned int` of the same width could be quiet.
4. `sheet_draw` rejects the whole call for one bad record: a game loses its whole frame; it
   would help if the kernel drew the valid ones and reported which was rejected (or hgame
   checked records in a debug build). Case: fault 7.
5. (done) `hg_key_next`'s events had no modifier state (`hg_mods` is the state at the last
   event read): a game could not distinguish Ctrl+G from G when Ctrl went up in the same
   frame (fault 15). hgame now sets `hg_key_mods` with each press
   (`sdk/c/game/tests/gt_keymods.c`). Case: `sdk/c/game/hg_core.c` `events()`.
6. cc816 calls `__mul16` for a multiply by a constant (an index into an array of 14-, 30-
   or 44-byte structures; `44 * row`) and `__udiv16` for a division by one (`x / 7`): about
   10 % of a room's drawing in this port. Shifts and adds for small constants, a
   multiply-shift for division. Case: room changes above.
7. One read moves at most 32,767 bytes and must not cross a bank: three reads a bank
   (32,767 + 32,767 + 2), each a card request. 32,768 (or anything to the bank's end) would
   make it two. Case: fault 13.
8. No hourglass or busy pointer for a full-screen program: a loading screen draws its own.
   Case: fault 13.

## Time

The polish round (2026-11-23: faults 13-17, the room changes, `make test-long`, the
first screen's keys, the tests on the board's card): about 4 h 30.

The port itself: about 6 h of the agent's time (wall clock), builds and emulator runs on a fast PC:

- Reading the skill, the ports, SDLPoP's layers: 40 min
- The reference build, the scripted recorder (the replays themselves: a helper agent,
  16 min): 30 min
- mkdata.py (atlas, palette rows, masks, sounds), midi2imf.c: 40 min
- The platform layer, the SDL shim, first compile and link: 1 h 10
- The main bank (far tables, compact surfaces, buffers, floats): 40 min
- Determinism: the savestate layout, the compiler fault 1 (placement-dependent): 1 h 15
- Pictures: the peels, faults 2 and 3, the view: 50 min
- Sound check, speed, saves, tests, app, notes, the suites: 1 h 10

## Suggestions for the porting guide

1. Build upstream on the PC with a state hook and compare tick by tick; a savestate dump
   (a printing `process` function) finds the first differing variable.
2. When behaviour changes with link order or `--spread`, suspect an index register going
   negative (fault 1) or a far address taken as near (fault 2), before suspecting the game;
   but first check whether the test itself depends on timing (fault 12): input held for a
   time in ms covers a number of game ticks that moves with the program's layout.
   `make test-layouts` runs the tests with the layout shifted; emu816 `--watch ADDR:LEN`
   logs every write into a range with its instruction, `--dump-ram-on TEXT` the RAM at a
   console line, `--ram-random SEED` other power-on memory (run816 `--emu-arg`, or
   `EMU816_ARGS` for a whole `make test`).
3. A game written for a PC does not check malloc: give the port a malloc that stops with a
   message (`horizon/hz_heap.h`), and look for leaks on longjmp/restart paths (fault 11): a
   heap of a few KB runs out where the PC's never does.
4. A kernel call that takes many records is rejected whole for one bad record: check the
   console for the error, print the bad record.
5. Keep the PC's palette layout (VGA rows) when the game had one: images stay keyed copies
   and the palette effects stay the palette's.
