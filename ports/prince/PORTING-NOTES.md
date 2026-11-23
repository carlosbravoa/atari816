# Porting notes: Prince of Persia on the Atari816

The C SDK's third game port, after Digger and Xargon: SDLPoP (the DOS game's disassembly
in C, SDL2), about 19,700 lines of game code, large code model, 2 MB of data.

Upstream: SDLPoP at commit f7be2e9 (7 November 2026, "1.24 RC"), GPL-3. Its game files are in
`src/` (seg000-seg008, seqtbl, replay, options, data, the headers) with every change in
`#if defined(_HORIZON)` (`upstream.patch`: 11 files, about 275 lines added, 38 removed). Not
built: `seg009.c` (the SDL layer: replaced by `horizon/`), `main.c`, `menu.c` (the pause
menu), `lighting.c`, `screenshot.c`, `midi.c` and `opl3.c` (the music: converted at build
time, played by the real OPL2), `stb_vorbis.c` (OGG music).

## The numbers

| | |
| --- | --- |
| Upstream C built | 13 files, about 19,700 lines with their headers |
| New platform layer | `horizon/`: 7 C files (`hz_seg009.c` is the part of upstream's seg009.c that does not touch SDL, taken over unchanged: text, dialogs, rectangles, random numbers), 3 headers (an SDL2 shim, `sys/stat.h`) |
| Tools and tests | `tools/` (getdata.sh, mkdata.py, midi2imf.c, mkicon.py), `host/` (the reference build), `tests/` (check.sh, mkref.sh, hostframes.sh, cmpframe.py, oplcheck.py, shots.py, scripts): about 4,600 lines with horizon/ |
| Build | `hcc --code large`: PRINCE.PRG 188 KB (142 KB of code in 3 other banks; the main bank 48.1 KB without its movable code: bss 20.2 KB, constants 13.1 KB, data 5.8 KB, code that must stay 9.1 KB; heap 12.4 KB, software stack 4 KB; 9.4 KB of `__far` objects in a bank) |
| Data | POP.GFX 1,680 KB (927 images and 500 mirrored copies in an atlas 2048 wide, in 4 parts of 256 rows), POP.MSK 132 KB (1-bit masks), POP.DAT 61 KB (directory, palettes, levels), POP.SND 250 KB (24 digital effects, 26 songs as OPL2 streams, 4 PC-speaker sounds) |
| Memory at run time | about 48 banks (3 MB): framebuffer 6 (512 x 768), atlas 27, masks 3, sounds 4, directory 1, replay moves and savestate 1, far tables 1, code 3, the main bank |
| Speed | 22-34 ms of work a game frame on average in level 1 and a fight (the game's frame is 83 ms: 12 a second; 10 a second in fights); see "Speed" |
| Determinism | 4 replays recorded on the PC (2,478 ticks): every state and every picture taken equal to upstream's on the PC |

## How the port was checked against upstream

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

## Faults found, and fixes

| # | What | Where | Fix | Time |
| --- | --- | --- | --- | --- |
| 1 | **cc816: `a[d + 1]` with a signed `d` read the next bank** when `d` was -1. The front end takes the constant out of the index (`a + 1`, index `d`), and the 65816 adds an index register to an absolute address in 24 bits: X = $FFFF read `a + $10000`. PoP's `dir_front[Char.direction + 1]` (facing left): the tile in front of the kid came from garbage, how depending on where code and data lay (one link order passed, another failed at tick 5, `-O0` and `-O2` differed) | SDK compiler fault | `cc816/front.py`: a positive constant stays in a signed index; `tests/regress/r040_signed_index_offset.c` (killed by the old compiler, passes now in both models) | 1 h 30 |
| 2 | **cc816: no `-Wfar-pointer` for `&p->member` with `p` far** (and `&far_array[i].member`): `&` gave a near pointer type to a 4-byte far address, so a near parameter took it silently. PoP's `x_to_xh_and_xl(obj_x, &entry->xh, &entry->xl)` (the object table, moved far) wrote into the main bank: every sprite facing right was drawn 170 pixels off | SDK compiler diagnostic | `front.py`: `&` of an lvalue reached through a far pointer has a far pointer type (also correct when assigned to a `__far` pointer: before, it would have been taken as near and given the main bank); `tests/diag/w_far_member.c` | 40 min |
| 3 | `calc_screen_x_coord`: `logical_x*320/280` overflows a 16-bit int (the kid drawn 45 pixels off) | 16-bit int | `logical_x*8/7` (the same values, C's truncation too, no 32-bit divide) | 15 min |
| 4 | quickload's penalty: `720 * (rem_min - old)` overflows (60 minutes = 43,200) | 16-bit int | `720L` | 5 min |
| 5 | The savestate (and so every replay) has `torch_colors` (750 bytes) when `USE_COLORED_TORCHES` is on: turned off first, everything after it was read from the wrong place | port | kept on (its blit is a plain keyed blit) | 20 min |
| 6 | Saves went to a garbage path: `get_writable_file_path` uses `HOME`; Horizon's `getenv` returns nothing and `save_path` stayed uninitialised | upstream (a latent fault) + port | under `_HORIZON` the file's own name (the program's folder is the current one) | 10 min |
| 7 | Rooms black: a peel (save-under) of a sprite partly off the left edge had a negative source x; `sheet_draw` refuses the whole call for one bad record, so 31 good records (the room's copy to the screen) went with it | port | the peel's source cut to the screen; refused calls print their bad record (the first 8) | 40 min |
| 8 | The peels' area filled up: the start-up dialog's peel stays for good, so an allocator that resets when no peel is left never reset | port | a stack of peels: freed ones pop | 15 min |
| 9 | The upstream replays' option sections and `moves[345600]` (345 KB) | main bank | moves and the savestate in a bank of their own (61,440 ticks: 85 minutes), sections of 160 bytes (the biggest is 147) | 20 min |
| 10 | `midi2imf`'s first version had the instrument record's fields in the wrong order (feedback came out 0) | tool | SDLPoP's layout; now the stream's 1,258 writes of the title music equal upstream's own OPL writes (times within 1.3 ms) | 15 min |
| 11 | **Level 1 started empty on the board** (the kid in room 0, dead at once) when the title had run 40 s or more before the key: a key in `fade_out_2`/`fade_in_2` (the story's fades) or in the princess's scene jumps to `start_game` (longjmp), which never frees the fade's 1.5 KB buffer nor the scene's peels (upstream leaks them too: `clear_screen_and_sounds` sets `peels_count = 0`). The 12 KB heap then had no 2,310 bytes in one piece; `load_from_opendats_alloc`'s `malloc` gave NULL and `load_level` silently left the level all zero (25 non-zero bytes of 2,305: exactly what the board showed). Depends on when the key comes, not on the build: in the emulator the tests' key came 2.5 s into the title | port + upstream leaks | the level copied straight from POP.DAT's far copy (no heap); `start_game` frees an abandoned fade (`hzv_fade_abandoned`); `clear_screen_and_sounds` frees its peels; `horizon/hz_heap.h`: every `malloc`/`calloc`/`realloc` of the port stops the game with "prince: out of memory" instead of returning NULL; `list_replay_files` asked 49,792 bytes (128 replays' records, NULL before, written through when a replays folder exists): grows by 4. Test 4b: a key after 15, 40, 60 s, level 1 in room 1 with the same heap | 2 h 30 |
| 12 | `make test`'s scripted-game pictures failed or passed with the layout: how many game ticks a held key covers depends on the CPU's time (emu816 models the cache by address), so the kid's run and the torches' random flames moved. The kid "missing" after the quickload is upstream's: he stops in the wall's column (the PC's build draws the same) | test | the quickload checked by a checksum of the whole savestate (`prince: quicksave state`, `quickload state`); after the first picture only the status line's rows are compared; `make test-layouts` (PAD=n: `tools/mkpad.py`) | 1 h |

Also: `get_joystick_state` used `atan2` and doubles (1.7 KB of floating point in the main
bank for an analog stick Horizon does not have): signs instead; the feather fall's tick
count (18.75 s as a double) and the timers' scaling in integers.

## The platform layer (horizon/)

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
- **Data (`hz_data.c`).** POP.DAT's directory read once; upstream's open_dat chain (the
  last DAT opened searched first) over folder numbers; load_sprites_from_file makes an
  image set's pointers and surfaces in one allocation.
- **Sound (`hz_sound.c`).** As above; `check_sound_playing` counts a sound's known length in
  vertical blanks (the game waits for sounds: level ends, cut scenes), the same with the
  sound off or the chip missing.
- **Time and input (`hz_sys.c`).** SDLPoP's timers are 60 a second: the vertical blanks.
  Keys from hgame's events into upstream's `key_states` and `last_key_scancode`; the
  joystick (port 1) holds the arrows and Shift.

## Speed

Measured in the emulator (models the board within a few per cent) with `stats=100`: the
time from the end of one game frame's wait to the next (logic, building the draw tables,
sending the records, the kernel's share), the replays played at the game's speed:

| Scene | Average | Worst | Late |
| --- | --- | --- | --- |
| Level 1, ten rooms (l1run, 1,207 frames) | 21.7-34.2 ms | 300 ms | 1 in 100 (the room changes) |
| A sword fight, level 2 (frames of 100 ms) | 33.2 ms | 216 ms | 1 in 120 (the room change) |
| the 30 ms slower machine (/BUSY:30) | no change of the game's states | | |

The game's frame is 83 ms (12 a second; 100 ms in fights), so a frame uses a quarter to
two fifths of it. The worst frames are room changes: SDLPoP's deliberate 100 ms of black
("dark transition", as the original) plus drawing the whole room (about 30 tiles in many
records each, the table building in C: 120-200 ms). Not optimised further: the game does
not need it.

## SDK changes made (with tests)

| File | Change | Test |
| --- | --- | --- |
| `sdk/c/cc816/cc816/front.py` | fault 1: a positive constant stays in a signed array index | `sdk/c/cc816/tests/regress/r040_signed_index_offset.c` |
| `sdk/c/cc816/cc816/front.py` | fault 2: `&` through a far pointer is a far pointer (`far_lvalue`) | `sdk/c/cc816/tests/diag/w_far_member.c` |
| `sdk/tools/run816.py` | `--log-opl`, `--log-opl-us` passed to emu816 (Xargon's open tool gap 13) | used by this port's `make test` (tests/oplcheck.py) |

## SDK wishes (not changed)

| # | What | Case |
| --- | --- | --- |
| 1 | hcc's large-model trial link reports every function whose address is taken (`__T_` thunks) as "undefined" whenever one real name is missing: 34 names listed for one missing `load_sound_names` | `sdk/c/tools/hzlarge.py` `link()`: when `und` has names not starting `__T_`, report only those |
| 2 | hgame takes 7.1 KB of the main bank for its draw queues even when a game draws with its own records (both Xargon and this port) | `hg_draw.c`: `hg__dq`, `hg__sq` (used at fixed addresses by `hg_fast.s`), the arena |
| 3 | `int`-typed `switch` on key codes with bit 15 set warns `-Woverflow` for every case (SDLPoP's `WITH_SHIFT` = 0x8000): correct code, 16 lines of noise | a `case` whose value fits `unsigned int` of the same width could be quiet |
| 4 | `sheet_draw` refuses the whole call for one bad record: a game sees its whole frame vanish; it would help if the kernel drew the valid ones and said which was refused (or hgame checked records in a debug build) | fault 7 |

## Time

About 6 h of the agent's time (wall clock), builds and emulator runs on a fast PC:

| | |
| --- | --- |
| Reading the skill, the ports, SDLPoP's layers | 40 min |
| The reference build, the scripted recorder (the replays themselves: a helper agent, 16 min) | 30 min |
| mkdata.py (atlas, palette rows, masks, sounds), midi2imf.c | 40 min |
| The platform layer, the SDL shim, first compile and link | 1 h 10 |
| The main bank (far tables, compact surfaces, buffers, floats) | 40 min |
| Determinism: the savestate layout, the compiler fault 1 (placement-dependent) | 1 h 15 |
| Pictures: the peels, faults 2 and 3, the view | 50 min |
| Sound check, speed, saves, tests, app, notes, the suites | 1 h 10 |

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
   heap of a few KB runs out where the PC never notices.
4. A kernel call that takes many records is refused whole for one bad record: check the
   console for the refusal, print the bad record.
5. Keep the PC's palette layout (VGA rows) when the game had one: images stay keyed copies
   and the palette effects stay the palette's.
